const win32 = @import("win32.zig");
const scanner = @import("scanner.zig");
const sound_banks = @import("sound_banks.g.zig");

// control IDs
pub const ID_BROWSE: usize = 3001;

pub fn createBrowseUI(hwnd: win32.HWND, label_out: *?win32.HWND, button_out: *?win32.HWND) void {
    const hinstance = win32.GetModuleHandleA(null);

    // create label
    label_out.* = win32.CreateWindowExA(
        0,
        "STATIC",
        "please browse to your worms armagedon installation folder",
        win32.WS_CHILD | win32.WS_VISIBLE | win32.SS_CENTER,
        0,
        0,
        300,
        20,
        hwnd,
        null,
        hinstance,
        null,
    );

    // create browse button
    button_out.* = win32.CreateWindowExA(
        0,
        "BUTTON",
        "browse...",
        win32.WS_CHILD | win32.WS_VISIBLE | win32.BS_PUSHBUTTON,
        0,
        0,
        100,
        30,
        hwnd,
        @ptrFromInt(ID_BROWSE),
        hinstance,
        null,
    );
}

pub fn layoutBrowseUI(hwnd: win32.HWND, browse_label: ?win32.HWND, browse_button: ?win32.HWND) void {
    var rect: win32.RECT = undefined;
    _ = win32.GetClientRect(hwnd, &rect);
    const client_width = rect.right - rect.left;
    const client_height = rect.bottom - rect.top;

    const label_width: i32 = 400;
    const label_height: i32 = 30;
    const button_width: i32 = 100;
    const button_height: i32 = 30;
    const spacing: i32 = 10;

    const total_height = label_height + spacing + button_height;
    const start_y = @divTrunc(client_height - total_height, 2);

    if (browse_label) |label| {
        const label_x = @divTrunc(client_width - label_width, 2);
        _ = win32.MoveWindow(label, label_x, start_y, label_width, label_height, 1);
    }

    if (browse_button) |btn| {
        const btn_x = @divTrunc(client_width - button_width, 2);
        const btn_y = start_y + label_height + spacing;
        _ = win32.MoveWindow(btn, btn_x, btn_y, button_width, button_height, 1);
    }

    // hide scrollbar in browse mode
    var si = win32.SCROLLINFO{
        .fMask = win32.SIF_ALL,
        .nMin = 0,
        .nMax = 0,
        .nPage = 1,
        .nPos = 0,
    };
    _ = win32.SetScrollInfo(hwnd, win32.SB_VERT, &si, 1);
}

// result of browse attempt
pub const BrowseResult = union(enum) {
    success: scanner.ScanResult,
    cancelled,
    invalid_folder,
};

pub fn handleBrowse(hwnd: win32.HWND, allocator: std.mem.Allocator) BrowseResult {
    var path_buf: [win32.MAX_PATH]u8 = undefined;
    if (scanner.browseForFolder(hwnd, &path_buf)) |path| {
        // try to find worms root (travel up if needed)
        var root_buf: [win32.MAX_PATH]u8 = undefined;
        const worms_root = scanner.findWormsRoot(path, &root_buf) orelse path;

        // try to scan the selected/found directory
        const scan_result = if (sound_banks.full_mode)
            scanner.scanFullDirectory(allocator, worms_root)
        else
            scanner.scanSpeechDirectory(allocator, worms_root);

        if (scan_result) |result| {
            // save for next time
            scanner.saveBrowsedPath(worms_root);
            return .{ .success = result };
        } else |_| {
            return .invalid_folder;
        }
    }
    return .cancelled;
}

const std = @import("std");
