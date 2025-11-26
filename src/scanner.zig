// runtime scanner for worms armageddon speech banks
// reads registry for install path, scans Speech directory

const std = @import("std");
const win32 = @import("win32.zig");

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

// save browsed path to registry
pub fn saveBrowsedPath(path: []const u8) void {
    var key: win32.HKEY = undefined;
    const status = win32.RegCreateKeyExA(
        win32.HKEY_CURRENT_USER,
        WORMTALKER_REG_KEY,
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

    // include null terminator in size
    _ = win32.RegSetValueExA(
        key,
        "Path",
        0,
        win32.REG_SZ,
        path.ptr,
        @intCast(path.len + 1),
    );
}

// try to read saved path from our registry key
pub fn getSavedPath(buf: []u8) ?[]const u8 {
    var key: win32.HKEY = undefined;
    const status = win32.RegOpenKeyExA(
        win32.HKEY_CURRENT_USER,
        WORMTALKER_REG_KEY,
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
        "Path",
        null,
        &data_type,
        buf.ptr,
        &data_size,
    );

    if (query_status != win32.ERROR_SUCCESS or data_type != win32.REG_SZ) return null;

    const len = if (data_size > 0) data_size - 1 else 0;
    return buf[0..len];
}

// try to read worms installation path from registry
pub fn getWormsPath(buf: []u8) ?[]const u8 {
    var key: win32.HKEY = undefined;
    const status = win32.RegOpenKeyExA(
        win32.HKEY_CURRENT_USER,
        "Software\\Team17SoftwareLTD\\WormsArmageddon",
        0,
        win32.KEY_READ,
        &key,
    );

    if (status != win32.ERROR_SUCCESS) {
        return null;
    }
    defer _ = win32.RegCloseKey(key);

    var data_type: u32 = 0;
    var data_size: u32 = @intCast(buf.len);

    const query_status = win32.RegQueryValueExA(
        key,
        "PATH",
        null,
        &data_type,
        buf.ptr,
        &data_size,
    );

    if (query_status != win32.ERROR_SUCCESS or data_type != win32.REG_SZ) {
        return null;
    }

    // data_size includes null terminator
    const len = if (data_size > 0) data_size - 1 else 0;
    return buf[0..len];
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

// show folder browser dialog
pub fn browseForFolder(hwnd: ?win32.HWND, buf: []u8) ?[]const u8 {
    _ = win32.CoInitialize(null);

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
