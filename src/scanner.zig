// runtime scanner for worms armageddon speech banks
// reads registry for install path, scans Speech directory

const std = @import("std");
const win32 = @import("win32.zig");

// registry helpers

fn registryGetString(key_path: [*:0]const u8, value_name: [*:0]const u8, buf: []u8) ?[]const u8 {
    var key: win32.HKEY = undefined;
    const status = win32.RegOpenKeyExA(
        win32.HKEY_CURRENT_USER,
        key_path,
        0,
        win32.KEY_READ,
        &key,
    );
    if (status != win32.ERROR_SUCCESS) return null;
    defer _ = win32.RegCloseKey(key);

    var data_type: u32 = 0;
    var data_size: u32 = @intCast(buf.len);
    const query_status = win32.RegQueryValueExA(
        key,
        value_name,
        null,
        &data_type,
        buf.ptr,
        &data_size,
    );
    if (query_status != win32.ERROR_SUCCESS or data_type != win32.REG_SZ) return null;

    const len = if (data_size > 0) data_size - 1 else 0;
    return buf[0..len];
}

fn registrySetString(key_path: [*:0]const u8, value_name: [*:0]const u8, data: []const u8) void {
    var key: win32.HKEY = undefined;
    const status = win32.RegCreateKeyExA(
        win32.HKEY_CURRENT_USER,
        key_path,
        0,
        null,
        0,
        win32.KEY_WRITE,
        null,
        &key,
        null,
    );
    if (status != win32.ERROR_SUCCESS) return;
    defer _ = win32.RegCloseKey(key);

    _ = win32.RegSetValueExA(
        key,
        value_name,
        0,
        win32.REG_SZ,
        data.ptr,
        @intCast(data.len),
    );
}

fn registryGetDword(key_path: [*:0]const u8, value_name: [*:0]const u8, default: u32) u32 {
    var key: win32.HKEY = undefined;
    const status = win32.RegOpenKeyExA(
        win32.HKEY_CURRENT_USER,
        key_path,
        0,
        win32.KEY_READ,
        &key,
    );
    if (status != win32.ERROR_SUCCESS) return default;
    defer _ = win32.RegCloseKey(key);

    var value: u32 = default;
    var data_type: u32 = 0;
    var data_size: u32 = @sizeOf(u32);
    const query_status = win32.RegQueryValueExA(
        key,
        value_name,
        null,
        &data_type,
        @ptrCast(&value),
        &data_size,
    );
    if (query_status != win32.ERROR_SUCCESS or data_type != win32.REG_DWORD) return default;

    return value;
}

fn registrySetDword(key_path: [*:0]const u8, value_name: [*:0]const u8, value: u32) void {
    var key: win32.HKEY = undefined;
    const status = win32.RegCreateKeyExA(
        win32.HKEY_CURRENT_USER,
        key_path,
        0,
        null,
        0,
        win32.KEY_WRITE,
        null,
        &key,
        null,
    );
    if (status != win32.ERROR_SUCCESS) return;
    defer _ = win32.RegCloseKey(key);

    _ = win32.RegSetValueExA(
        key,
        value_name,
        0,
        win32.REG_DWORD,
        @ptrCast(&value),
        @sizeOf(u32),
    );
}

// generic comparator for types with a .name field
fn compareByName(comptime T: type) fn (void, T, T) bool {
    return struct {
        fn lessThan(_: void, lhs: T, rhs: T) bool {
            return std.mem.lessThan(u8, lhs.name, rhs.name);
        }
    }.lessThan;
}

pub const RuntimeWav = struct {
    name: [:0]const u8, // display name (lowercase, no extension)
    path: [:0]const u8, // full path to wav file
};

pub const RuntimeBank = struct {
    name: [:0]const u8,
    wavs: []RuntimeWav,
};

pub const ScanResult = struct {
    banks: []RuntimeBank,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ScanResult) void {
        for (self.banks) |bank| {
            for (bank.wavs) |wav| {
                self.allocator.free(wav.name);
                self.allocator.free(wav.path);
            }
            self.allocator.free(bank.wavs);
            self.allocator.free(bank.name);
        }
        self.allocator.free(self.banks);
    }
};

const WORMTALKER_REG_KEY = "Software\\wormtalker";
const WORMS_REG_KEY = "Software\\Team17SoftwareLTD\\WormsArmageddon";

// save auto-preview setting to registry
pub fn saveAutoPreview(enabled: bool) void {
    registrySetDword(WORMTALKER_REG_KEY, "AutoPreview", if (enabled) 1 else 0);
}

// get auto-preview setting from registry (defaults to true if not set)
pub fn getAutoPreview() bool {
    return registryGetDword(WORMTALKER_REG_KEY, "AutoPreview", 1) != 0;
}

// save browsed path to registry
pub fn saveBrowsedPath(path: []const u8) void {
    registrySetString(WORMTALKER_REG_KEY, "Path", path);
}

// try to read saved path from our registry key
pub fn getSavedPath(buf: []u8) ?[]const u8 {
    return registryGetString(WORMTALKER_REG_KEY, "Path", buf);
}

// try to read worms installation path from registry
pub fn getWormsPath(buf: []u8) ?[]const u8 {
    return registryGetString(WORMS_REG_KEY, "PATH", buf);
}

// check if path looks like worms root (has DATA directory)
fn isWormsRoot(path: []const u8) bool {
    var check_buf: [win32.MAX_PATH]u8 = undefined;
    const data_path = std.fmt.bufPrint(&check_buf, "{s}\\DATA", .{path}) catch return false;

    var dir = std.fs.cwd().openDir(data_path, .{}) catch return false;
    dir.close();
    return true;
}

// find worms root by traveling up from given path
pub fn findWormsRoot(start_path: []const u8, buf: []u8) ?[]const u8 {
    var current: []const u8 = start_path;

    while (true) {
        if (isWormsRoot(current)) {
            const len = @min(current.len, buf.len);
            @memcpy(buf[0..len], current[0..len]);
            return buf[0..len];
        }
        current = std.fs.path.dirnameWindows(current) orelse break;
    }

    return null;
}

// scan a directory for sound banks
pub fn scanSpeechDirectory(allocator: std.mem.Allocator, base_path: []const u8) !ScanResult {
    // build path to Speech directory: <base_path>\DATA\User\Speech
    var path_buf: [win32.MAX_PATH]u8 = undefined;
    const speech_path = std.fmt.bufPrint(&path_buf, "{s}\\DATA\\User\\Speech", .{base_path}) catch return error.PathTooLong;

    var banks: std.ArrayListUnmanaged(RuntimeBank) = .empty;
    errdefer {
        for (banks.items) |bank| {
            for (bank.wavs) |wav| {
                allocator.free(wav.name);
                allocator.free(wav.path);
            }
            allocator.free(bank.wavs);
            allocator.free(bank.name);
        }
        banks.deinit(allocator);
    }

    // open speech directory
    var dir = std.fs.cwd().openDir(speech_path, .{ .iterate = true }) catch {
        return error.SpeechDirNotFound;
    };
    defer dir.close();

    // iterate over subdirectories (each is a sound bank)
    var dir_iter = dir.iterate();
    while (try dir_iter.next()) |entry| {
        if (entry.kind == .directory) {
            var wavs: std.ArrayListUnmanaged(RuntimeWav) = .empty;
            errdefer {
                for (wavs.items) |wav| {
                    allocator.free(wav.name);
                    allocator.free(wav.path);
                }
                wavs.deinit(allocator);
            }

            // open bank directory
            var bank_dir = dir.openDir(entry.name, .{ .iterate = true }) catch continue;
            defer bank_dir.close();

            // find all wav files
            var wav_iter = bank_dir.iterate();
            while (try wav_iter.next()) |wav_entry| {
                if (wav_entry.kind == .file) {
                    const name = wav_entry.name;
                    if (std.mem.endsWith(u8, name, ".WAV") or std.mem.endsWith(u8, name, ".wav")) {
                        // create display name (lowercase, no extension)
                        const base_name = name[0 .. name.len - 4];
                        var display_buf: [128]u8 = undefined;
                        const display_len = @min(base_name.len, display_buf.len - 1);
                        for (base_name[0..display_len], 0..) |c, i| {
                            display_buf[i] = std.ascii.toLower(c);
                        }
                        const display_name = try allocator.dupeZ(u8, display_buf[0..display_len]);
                        errdefer allocator.free(display_name);

                        // create full path
                        var full_path_buf: [win32.MAX_PATH]u8 = undefined;
                        const full_path = std.fmt.bufPrint(&full_path_buf, "{s}\\{s}\\{s}", .{ speech_path, entry.name, name }) catch continue;
                        const full_path_z = try allocator.dupeZ(u8, full_path);
                        errdefer allocator.free(full_path_z);

                        try wavs.append(allocator, .{
                            .name = display_name,
                            .path = full_path_z,
                        });
                    }
                }
            }

            // sort wavs by name
            std.mem.sort(RuntimeWav, wavs.items, {}, compareByName(RuntimeWav));

            if (wavs.items.len > 0) {
                const bank_name = try allocator.dupeZ(u8, entry.name);
                errdefer allocator.free(bank_name);

                try banks.append(allocator, .{
                    .name = bank_name,
                    .wavs = try wavs.toOwnedSlice(allocator),
                });
            }
        }
    }

    // sort banks by name
    std.mem.sort(RuntimeBank, banks.items, {}, compareByName(RuntimeBank));

    return .{
        .banks = try banks.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

// scan entire worms directory for any folder containing wavs
pub fn scanFullDirectory(allocator: std.mem.Allocator, base_path: []const u8) !ScanResult {
    var banks: std.ArrayListUnmanaged(RuntimeBank) = .empty;
    errdefer {
        for (banks.items) |bank| {
            for (bank.wavs) |wav| {
                allocator.free(wav.name);
                allocator.free(wav.path);
            }
            allocator.free(bank.wavs);
            allocator.free(bank.name);
        }
        banks.deinit(allocator);
    }

    // directories to scan (relative to base_path)
    const scan_dirs = [_]struct { path: []const u8, prefix: []const u8 }{
        .{ .path = "DATA\\Streams", .prefix = "" },
        .{ .path = "DATA\\User\\Fanfare", .prefix = "" },
        .{ .path = "DATA\\Wav\\Effects", .prefix = "" },
        .{ .path = "FESfx", .prefix = "" },
        .{ .path = "DATA\\User\\Speech", .prefix = "Speech/" },
        .{ .path = "User\\Speech", .prefix = "Speech/" },
    };

    for (scan_dirs) |scan_dir| {
        var path_buf: [win32.MAX_PATH]u8 = undefined;
        const dir_path = std.fmt.bufPrint(&path_buf, "{s}\\{s}", .{ base_path, scan_dir.path }) catch continue;

        // check if this is a leaf directory (contains wavs directly)
        if (scanDir(allocator, dir_path, scan_dir.prefix, &banks)) |_| {
            // scanned successfully
        } else |_| {
            // try scanning subdirectories (for Speech folder)
            var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch continue;
            defer dir.close();

            var dir_iter = dir.iterate();
            while (dir_iter.next() catch null) |entry| {
                if (entry.kind == .directory) {
                    var subdir_buf: [win32.MAX_PATH]u8 = undefined;
                    const subdir_path = std.fmt.bufPrint(&subdir_buf, "{s}\\{s}", .{ dir_path, entry.name }) catch continue;
                    scanDir(allocator, subdir_path, scan_dir.prefix, &banks) catch continue;
                }
            }
        }
    }

    // sort banks by name
    std.mem.sort(RuntimeBank, banks.items, {}, compareByName(RuntimeBank));

    if (banks.items.len == 0) return error.NoBanksFound;

    return .{
        .banks = try banks.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

// scan a single directory for wav files, add as bank if any found
fn scanDir(allocator: std.mem.Allocator, dir_path: []const u8, prefix: []const u8, banks: *std.ArrayListUnmanaged(RuntimeBank)) !void {
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return error.DirNotFound;
    defer dir.close();

    var wavs: std.ArrayListUnmanaged(RuntimeWav) = .empty;
    errdefer {
        for (wavs.items) |wav| {
            allocator.free(wav.name);
            allocator.free(wav.path);
        }
        wavs.deinit(allocator);
    }

    var wav_iter = dir.iterate();
    while (try wav_iter.next()) |entry| {
        if (entry.kind == .file) {
            const name = entry.name;
            if (std.mem.endsWith(u8, name, ".WAV") or std.mem.endsWith(u8, name, ".wav")) {
                // create display name (lowercase, no extension)
                const base_name = name[0 .. name.len - 4];
                var display_buf: [128]u8 = undefined;
                const display_len = @min(base_name.len, display_buf.len - 1);
                for (base_name[0..display_len], 0..) |c, i| {
                    display_buf[i] = std.ascii.toLower(c);
                }
                const display_name = try allocator.dupeZ(u8, display_buf[0..display_len]);
                errdefer allocator.free(display_name);

                // create full path
                var full_path_buf: [win32.MAX_PATH]u8 = undefined;
                const full_path = std.fmt.bufPrint(&full_path_buf, "{s}\\{s}", .{ dir_path, name }) catch continue;
                const full_path_z = try allocator.dupeZ(u8, full_path);
                errdefer allocator.free(full_path_z);

                try wavs.append(allocator, .{
                    .name = display_name,
                    .path = full_path_z,
                });
            }
        }
    }

    if (wavs.items.len == 0) return error.NoWavsFound;

    // sort wavs by name
    std.mem.sort(RuntimeWav, wavs.items, {}, compareByName(RuntimeWav));

    // extract directory name for bank name
    const dir_name = std.fs.path.basename(dir_path);

    // build bank name with prefix
    var bank_name_buf: [256]u8 = undefined;
    const bank_name = if (prefix.len > 0)
        std.fmt.bufPrint(&bank_name_buf, "{s}{s}", .{ prefix, dir_name }) catch dir_name
    else
        dir_name;

    const bank_name_z = try allocator.dupeZ(u8, bank_name);
    errdefer allocator.free(bank_name_z);

    try banks.append(allocator, .{
        .name = bank_name_z,
        .wavs = try wavs.toOwnedSlice(allocator),
    });
}

// show folder browser dialog
pub fn browseForFolder(hwnd: ?win32.HWND, buf: []u8) ?[]const u8 {
    const hr = win32.CoInitialize(null);
    if (hr < 0) return null; // COM init failed

    var bi = win32.BROWSEINFOA{
        .hwndOwner = hwnd,
        .lpszTitle = "Select Worms Armageddon installation folder",
        .ulFlags = win32.BIF_RETURNONLYFSDIRS | win32.BIF_NEWDIALOGSTYLE,
    };

    const pidl = win32.SHBrowseForFolderA(&bi);
    if (pidl == null) {
        return null;
    }
    defer win32.CoTaskMemFree(pidl);

    if (win32.SHGetPathFromIDListA(pidl, buf.ptr) == 0) {
        return null;
    }

    // find null terminator
    for (buf, 0..) |c, i| {
        if (c == 0) return buf[0..i];
    }
    return null;
}
