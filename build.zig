const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .x86_64,
            .os_tag = .windows,
            .abi = .gnu,
        },
    });
    const optimize = b.standardOptimizeOption(.{});

    // build option: embed wav files in binary (fat binary) or load from disk (runtime scan)
    const embed = b.option(bool, "embed", "Embed WAV files in binary (default: false for runtime scan)") orelse false;
    // build option: compress wavs to ADPCM (~4x smaller, requires ffmpeg)
    const compress = b.option(bool, "compress", "Convert WAVs to ADPCM when embedding (default: false)") orelse false;
    // build option: full explorer mode (scan all wav directories, not just speech banks)
    const full = b.option(bool, "full", "Full explorer mode - scan all wav dirs (default: false for speech only)") orelse false;

    if (embed) {
        // generate sound_banks.zig at configure time (writes to src/)
        generateSoundBanksFile(b.allocator, compress) catch @panic("failed to generate sound banks");
    } else {
        // generate minimal runtime stub
        generateRuntimeStub(b.allocator, full) catch @panic("failed to generate runtime stub");
    }

    const exe = b.addExecutable(.{
        .name = "wormtalker",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .win32_manifest = null,
    });

    // build as GUI app (no console window)
    exe.subsystem = .Windows;

    // link windows libs
    exe.linkSystemLibrary("gdi32");
    exe.linkSystemLibrary("user32");
    exe.linkSystemLibrary("winmm");
    exe.linkSystemLibrary("advapi32");
    exe.linkSystemLibrary("shell32");
    exe.linkSystemLibrary("ole32");

    // add windows resources (icon)
    exe.addWin32ResourceFile(.{ .file = b.path("src/resources.rc") });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "run wormtalker");
    run_step.dependOn(&run_cmd.step);
}

fn generateSoundBanksFile(allocator: std.mem.Allocator, compress: bool) !void {
    var output: std.ArrayListUnmanaged(u8) = .empty;
    const writer = output.writer(allocator);

    // scan Speech-Banks directory
    const banks_path = "src/wavs/Speech-Banks";
    var banks_dir = std.fs.cwd().openDir(banks_path, .{ .iterate = true }) catch |err| {
        std.debug.print("failed to open {s}: {}\n", .{ banks_path, err });
        return error.FailedToOpenDir;
    };
    defer banks_dir.close();

    // if compressing, create cache directory (must be inside src/ for @embedFile)
    const cache_path = "src/.wav-cache/Speech-Banks";
    if (compress) {
        std.fs.cwd().makePath(cache_path) catch |err| {
            std.debug.print("failed to create cache dir {s}: {}\n", .{ cache_path, err });
            return error.FailedToCreateCacheDir;
        };
    }

    var banks: std.ArrayListUnmanaged(BankInfo) = .empty;
    defer banks.deinit(allocator);

    var dir_iter = banks_dir.iterate();
    while (try dir_iter.next()) |entry| {
        if (entry.kind == .directory) {
            var wavs: std.ArrayListUnmanaged([]const u8) = .empty;

            var bank_dir = banks_dir.openDir(entry.name, .{ .iterate = true }) catch continue;
            defer bank_dir.close();

            // create bank subdir in cache if compressing
            if (compress) {
                var cache_bank_path_buf: [512]u8 = undefined;
                const cache_bank_path = std.fmt.bufPrint(&cache_bank_path_buf, "{s}/{s}", .{ cache_path, entry.name }) catch continue;
                std.fs.cwd().makePath(cache_bank_path) catch continue;
            }

            var wav_iter = bank_dir.iterate();
            while (try wav_iter.next()) |wav_entry| {
                if (wav_entry.kind == .file) {
                    const name = wav_entry.name;
                    if (std.mem.endsWith(u8, name, ".WAV") or std.mem.endsWith(u8, name, ".wav")) {
                        if (compress) {
                            // convert to ADPCM via ffmpeg
                            convertToAdpcm(allocator, banks_path, entry.name, name, cache_path) catch |err| {
                                std.debug.print("warning: failed to convert {s}/{s}: {}\n", .{ entry.name, name, err });
                                continue;
                            };
                        }
                        try wavs.append(allocator, try allocator.dupe(u8, name));
                    }
                }
            }

            std.mem.sort([]const u8, wavs.items, {}, struct {
                fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
                    return std.mem.lessThan(u8, lhs, rhs);
                }
            }.lessThan);

            if (wavs.items.len > 0) {
                try banks.append(allocator, .{
                    .name = try allocator.dupe(u8, entry.name),
                    .wavs = try wavs.toOwnedSlice(allocator),
                });
            }
        }
    }

    std.mem.sort(BankInfo, banks.items, {}, struct {
        fn lessThan(_: void, lhs: BankInfo, rhs: BankInfo) bool {
            return std.mem.lessThan(u8, lhs.name, rhs.name);
        }
    }.lessThan);

    // write header
    try writer.writeAll(
        \\// auto-generated by build.zig - do not edit
        \\// embedded mode: WAV files compiled into binary
        \\
        \\pub const runtime_mode = false;
        \\pub const full_mode = false;
        \\
        \\pub const WavFile = struct {
        \\    name: []const u8,
        \\    data: []const u8,
        \\};
        \\
        \\pub const SoundBank = struct {
        \\    name: [:0]const u8,
        \\    wavs: []const WavFile,
        \\};
        \\
        \\
    );

    // path prefix for @embedFile (relative to src/)
    const embed_prefix = if (compress) ".wav-cache/Speech-Banks" else "wavs/Speech-Banks";

    // generate each bank's wav array
    for (banks.items) |bank| {
        var ident_buf: [128]u8 = undefined;
        const ident = sanitizeIdent(bank.name, &ident_buf);

        try writer.print("const {s}_wavs = [_]WavFile{{\n", .{ident});
        for (bank.wavs) |wav| {
            var base_buf: [128]u8 = undefined;
            const base = wavBaseName(wav, &base_buf);
            try writer.print("    .{{ .name = \"{s}\", .data = @embedFile(\"{s}/{s}/{s}\") }},\n", .{ base, embed_prefix, bank.name, wav });
        }
        try writer.writeAll("};\n\n");
    }

    // generate the banks array
    try writer.writeAll("pub const sound_banks = [_]SoundBank{\n");
    for (banks.items) |bank| {
        var ident_buf: [128]u8 = undefined;
        const ident = sanitizeIdent(bank.name, &ident_buf);
        try writer.print("    .{{ .name = \"{s}\", .wavs = &{s}_wavs }},\n", .{ bank.name, ident });
    }
    try writer.writeAll("};\n");

    // write to src/sound_banks.g.zig
    const file = try std.fs.cwd().createFile("src/sound_banks.g.zig", .{});
    defer file.close();
    try file.writeAll(try output.toOwnedSlice(allocator));
}

fn convertToAdpcm(allocator: std.mem.Allocator, src_base: []const u8, bank: []const u8, wav: []const u8, cache_base: []const u8) !void {
    // build input path: src/wavs/Speech-Banks/{bank}/{wav}
    var input_buf: [512]u8 = undefined;
    const input_path = try std.fmt.bufPrint(&input_buf, "{s}/{s}/{s}", .{ src_base, bank, wav });

    // build output path: .wav-cache/Speech-Banks/{bank}/{wav}
    var output_buf: [512]u8 = undefined;
    const output_path = try std.fmt.bufPrint(&output_buf, "{s}/{s}/{s}", .{ cache_base, bank, wav });

    // check if output already exists and is newer than input
    const input_stat = try std.fs.cwd().statFile(input_path);
    if (std.fs.cwd().statFile(output_path)) |output_stat| {
        if (output_stat.mtime >= input_stat.mtime) {
            return; // already up to date
        }
    } else |_| {}

    // run ffmpeg to convert
    var child = std.process.Child.init(
        &.{ "ffmpeg", "-y", "-i", input_path, "-c:a", "adpcm_ima_wav", output_path },
        allocator,
    );
    child.stderr_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    _ = try child.spawnAndWait();
}

const BankInfo = struct {
    name: []const u8,
    wavs: []const []const u8,
};

fn sanitizeIdent(name: []const u8, buf: []u8) []const u8 {
    var i: usize = 0;
    for (name) |c| {
        if (i >= buf.len - 1) break;
        if (std.ascii.isAlphanumeric(c)) {
            buf[i] = std.ascii.toLower(c);
            i += 1;
        } else if (c == ' ' or c == '-' or c == '_') {
            buf[i] = '_';
            i += 1;
        }
    }
    return buf[0..i];
}

fn wavBaseName(filename: []const u8, buf: []u8) []const u8 {
    const name = if (std.mem.endsWith(u8, filename, ".WAV") or std.mem.endsWith(u8, filename, ".wav"))
        filename[0 .. filename.len - 4]
    else
        filename;
    // lowercase the name
    for (name, 0..) |c, i| {
        if (i >= buf.len) break;
        buf[i] = std.ascii.toLower(c);
    }
    return buf[0..@min(name.len, buf.len)];
}

fn generateRuntimeStub(allocator: std.mem.Allocator, full_mode: bool) !void {
    var output: std.ArrayListUnmanaged(u8) = .empty;
    const writer = output.writer(allocator);

    try writer.writeAll(
        \\// auto-generated by build.zig - do not edit
        \\// runtime mode: WAV files loaded from disk at startup
        \\
        \\pub const runtime_mode = true;
        \\
    );

    try writer.print("pub const full_mode = {};\n", .{full_mode});

    try writer.writeAll(
        \\
        \\pub const WavFile = struct {
        \\    name: []const u8,
        \\    data: []const u8,
        \\};
        \\
        \\pub const SoundBank = struct {
        \\    name: [:0]const u8,
        \\    wavs: []const WavFile,
        \\};
        \\
        \\// empty - banks loaded at runtime
        \\pub const sound_banks = [_]SoundBank{};
        \\
    );

    const file = try std.fs.cwd().createFile("src/sound_banks.g.zig", .{});
    defer file.close();
    try file.writeAll(try output.toOwnedSlice(allocator));
}
