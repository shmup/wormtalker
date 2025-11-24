const std = @import("std");
const win32 = @import("win32.zig");
const sound_banks = @import("sound_banks.zig");

// layout constants
const BUTTON_HEIGHT: i32 = 25;
const BUTTON_PADDING: i32 = 4;
const BUTTON_CHAR_WIDTH: i32 = 8;
const MIN_BUTTON_WIDTH: i32 = 60;
const MIN_WINDOW_WIDTH: i32 = 400;
const MIN_WINDOW_HEIGHT: i32 = 300;
const TOOLBAR_HEIGHT: i32 = 30;
const COMBOBOX_WIDTH: i32 = 150;
const COMBOBOX_HEIGHT: i32 = 200;
const MAX_BUTTONS: usize = 128;

// control IDs
const ID_COMBOBOX: usize = 1000;

// menu IDs
const IDM_ABOUT: usize = 2001;
const IDM_EXIT: usize = 2002;

// globals for window state
var g_buttons: [MAX_BUTTONS]?win32.HWND = [_]?win32.HWND{null} ** MAX_BUTTONS;
var g_num_buttons: usize = 0;
var g_combobox: ?win32.HWND = null;
var g_current_bank: usize = 0;
var g_scroll_pos: i32 = 0;
var g_content_height: i32 = 0;
var g_main_hwnd: ?win32.HWND = null;

fn wndProc(hwnd: win32.HWND, msg: u32, wParam: win32.WPARAM, lParam: win32.LPARAM) callconv(.c) win32.LRESULT {
    switch (msg) {
        win32.WM_CREATE => {
            g_main_hwnd = hwnd;
            createMenuBar(hwnd);
            createCombobox(hwnd);
            createButtonsForBank(hwnd, 0);
            return 0;
        },
        win32.WM_SIZE => {
            layoutControls(hwnd);
            return 0;
        },
        win32.WM_GETMINMAXINFO => {
            const mmi: *win32.MINMAXINFO = @ptrFromInt(@as(usize, @bitCast(lParam)));
            mmi.ptMinTrackSize.x = MIN_WINDOW_WIDTH;
            mmi.ptMinTrackSize.y = MIN_WINDOW_HEIGHT;
            return 0;
        },
        win32.WM_COMMAND => {
            const notification = @as(u16, @truncate(wParam >> 16));
            const control_id = @as(u16, @truncate(wParam));
            // menu commands (notification == 0 for menus)
            if (notification == 0) {
                if (control_id == IDM_EXIT) {
                    win32.PostQuitMessage(0);
                    return 0;
                } else if (control_id == IDM_ABOUT) {
                    _ = win32.MessageBoxA(hwnd, "wormboard\n\nsoundboard for worms armageddon", "about wormboard", win32.MB_OK | win32.MB_ICONINFORMATION);
                    return 0;
                }
            }
            if (control_id == ID_COMBOBOX and notification == win32.CBN_SELCHANGE) {
                handleBankChange(hwnd);
            } else if (notification == win32.BN_CLICKED and control_id < MAX_BUTTONS) {
                playSound(control_id);
            }
            return 0;
        },
        win32.WM_VSCROLL => {
            handleScroll(hwnd, wParam);
            return 0;
        },
        win32.WM_MOUSEWHEEL => {
            const hi_word: u16 = @truncate(@as(u64, @bitCast(wParam)) >> 16);
            const delta: i16 = @bitCast(hi_word);
            const scroll_amount: i32 = if (delta > 0) -30 else 30;
            scrollContent(hwnd, scroll_amount);
            return 0;
        },
        win32.WM_DESTROY => {
            win32.PostQuitMessage(0);
            return 0;
        },
        else => return win32.DefWindowProcA(hwnd, msg, wParam, lParam),
    }
}

fn createMenuBar(hwnd: win32.HWND) void {
    const menu_bar = win32.CreateMenu();
    const help_menu = win32.CreatePopupMenu();

    if (help_menu) |help| {
        _ = win32.AppendMenuA(help, win32.MF_STRING, IDM_ABOUT, "&About");
        _ = win32.AppendMenuA(help, win32.MF_STRING, IDM_EXIT, "E&xit");
    }

    if (menu_bar) |bar| {
        _ = win32.AppendMenuA(bar, win32.MF_POPUP, @intFromPtr(help_menu), "&Help");
        _ = win32.SetMenu(hwnd, bar);
    }
}

fn createCombobox(hwnd: win32.HWND) void {
    const hinstance = win32.GetModuleHandleA(null);
    g_combobox = win32.CreateWindowExA(
        0,
        "COMBOBOX",
        "",
        win32.WS_CHILD | win32.WS_VISIBLE | win32.CBS_DROPDOWNLIST | win32.CBS_HASSTRINGS,
        BUTTON_PADDING,
        BUTTON_PADDING,
        COMBOBOX_WIDTH,
        COMBOBOX_HEIGHT,
        hwnd,
        @ptrFromInt(ID_COMBOBOX),
        hinstance,
        null,
    );

    if (g_combobox) |combo| {
        for (sound_banks.sound_banks) |bank| {
            _ = win32.SendMessageA(combo, win32.CB_ADDSTRING, 0, @bitCast(@intFromPtr(bank.name.ptr)));
        }
        _ = win32.SendMessageA(combo, win32.CB_SETCURSEL, 0, 0);
    }
}

fn createButtonsForBank(hwnd: win32.HWND, bank_index: usize) void {
    const hinstance = win32.GetModuleHandleA(null);

    // destroy existing buttons
    for (g_buttons[0..g_num_buttons]) |maybe_btn| {
        if (maybe_btn) |btn| {
            _ = win32.DestroyWindow(btn);
        }
    }
    g_buttons = [_]?win32.HWND{null} ** MAX_BUTTONS;

    const bank = sound_banks.sound_banks[bank_index];
    g_num_buttons = @min(bank.wavs.len, MAX_BUTTONS);

    for (bank.wavs[0..g_num_buttons], 0..) |wav, i| {
        var name_buf: [64:0]u8 = undefined;
        const name_len = @min(wav.name.len, 63);
        @memcpy(name_buf[0..name_len], wav.name[0..name_len]);
        name_buf[name_len] = 0;

        g_buttons[i] = win32.CreateWindowExA(
            0,
            "BUTTON",
            &name_buf,
            win32.WS_CHILD | win32.WS_VISIBLE | win32.BS_PUSHBUTTON,
            0,
            0,
            100,
            BUTTON_HEIGHT,
            hwnd,
            @ptrFromInt(i),
            hinstance,
            null,
        );
    }
}

fn layoutControls(hwnd: win32.HWND) void {
    var rect: win32.RECT = undefined;
    _ = win32.GetClientRect(hwnd, &rect);
    const client_width = rect.right - rect.left;
    const client_height = rect.bottom - rect.top;
    const button_area_height = client_height - TOOLBAR_HEIGHT;

    const bank = sound_banks.sound_banks[g_current_bank];

    // layout buttons in rows
    var x: i32 = BUTTON_PADDING;
    var y: i32 = TOOLBAR_HEIGHT + BUTTON_PADDING - g_scroll_pos;
    const row_height: i32 = BUTTON_HEIGHT + BUTTON_PADDING;

    for (bank.wavs[0..g_num_buttons], 0..) |wav, i| {
        const text_width = @as(i32, @intCast(wav.name.len)) * BUTTON_CHAR_WIDTH + 16;
        const btn_width = @max(text_width, MIN_BUTTON_WIDTH);

        if (x + btn_width + BUTTON_PADDING > client_width and x > BUTTON_PADDING) {
            x = BUTTON_PADDING;
            y += row_height;
        }

        if (g_buttons[i]) |btn| {
            _ = win32.MoveWindow(btn, x, y, btn_width, BUTTON_HEIGHT, 1);
        }

        x += btn_width + BUTTON_PADDING;
    }

    g_content_height = (y - TOOLBAR_HEIGHT) + row_height + g_scroll_pos;

    var si = win32.SCROLLINFO{
        .fMask = win32.SIF_ALL,
        .nMin = 0,
        .nMax = g_content_height,
        .nPage = @intCast(button_area_height),
        .nPos = g_scroll_pos,
    };
    _ = win32.SetScrollInfo(hwnd, win32.SB_VERT, &si, 1);
}

fn handleScroll(hwnd: win32.HWND, wParam: win32.WPARAM) void {
    var si = win32.SCROLLINFO{ .fMask = win32.SIF_ALL };
    _ = win32.GetScrollInfo(hwnd, win32.SB_VERT, &si);

    const action = @as(u32, @truncate(wParam));
    var new_pos = si.nPos;

    switch (action) {
        win32.SB_LINEUP => new_pos -= 20,
        win32.SB_LINEDOWN => new_pos += 20,
        win32.SB_PAGEUP => new_pos -= @as(i32, @intCast(si.nPage)),
        win32.SB_PAGEDOWN => new_pos += @as(i32, @intCast(si.nPage)),
        win32.SB_THUMBTRACK => new_pos = si.nTrackPos,
        else => {},
    }

    const max_pos = si.nMax - @as(i32, @intCast(si.nPage));
    new_pos = @max(0, @min(new_pos, max_pos));

    if (new_pos != g_scroll_pos) {
        const delta = g_scroll_pos - new_pos;
        g_scroll_pos = new_pos;
        _ = win32.ScrollWindow(hwnd, 0, delta, null, null);
        layoutControls(hwnd);
    }
}

fn scrollContent(hwnd: win32.HWND, delta: i32) void {
    var si = win32.SCROLLINFO{ .fMask = win32.SIF_ALL };
    _ = win32.GetScrollInfo(hwnd, win32.SB_VERT, &si);

    var new_pos = g_scroll_pos + delta;
    const max_pos = si.nMax - @as(i32, @intCast(si.nPage));
    new_pos = @max(0, @min(new_pos, max_pos));

    if (new_pos != g_scroll_pos) {
        const scroll_delta = g_scroll_pos - new_pos;
        g_scroll_pos = new_pos;
        _ = win32.ScrollWindow(hwnd, 0, scroll_delta, null, null);
        layoutControls(hwnd);
    }
}

fn playSound(index: u16) void {
    const bank = sound_banks.sound_banks[g_current_bank];
    if (index < bank.wavs.len) {
        const wav = bank.wavs[index];
        _ = win32.PlaySoundA(wav.data.ptr, null, win32.SND_MEMORY | win32.SND_ASYNC);
    }
}

fn handleBankChange(hwnd: win32.HWND) void {
    if (g_combobox) |combo| {
        const sel = win32.SendMessageA(combo, win32.CB_GETCURSEL, 0, 0);
        if (sel >= 0 and @as(usize, @intCast(sel)) < sound_banks.sound_banks.len) {
            // freeze painting
            _ = win32.SendMessageA(hwnd, win32.WM_SETREDRAW, 0, 0);

            g_current_bank = @intCast(sel);
            g_scroll_pos = 0;
            createButtonsForBank(hwnd, g_current_bank);
            layoutControls(hwnd);

            // resume painting and force redraw
            _ = win32.SendMessageA(hwnd, win32.WM_SETREDRAW, 1, 0);
            _ = win32.RedrawWindow(hwnd, null, null, win32.RDW_ERASE | win32.RDW_INVALIDATE | win32.RDW_ALLCHILDREN);
        }
    }
}

pub fn main() void {
    const hinstance = win32.GetModuleHandleA(null);

    const wc = win32.WNDCLASSEXA{
        .lpfnWndProc = wndProc,
        .hInstance = hinstance,
        .hCursor = win32.LoadCursorA(null, win32.IDC_ARROW),
        .hbrBackground = @ptrFromInt(win32.COLOR_BTNFACE + 1),
        .lpszClassName = "WormboardClass",
    };

    if (win32.RegisterClassExA(&wc) == 0) {
        return;
    }

    const hwnd = win32.CreateWindowExA(
        0,
        "WormboardClass",
        "wormboard",
        win32.WS_OVERLAPPEDWINDOW | win32.WS_VISIBLE | win32.WS_VSCROLL | win32.WS_CLIPCHILDREN,
        win32.CW_USEDEFAULT,
        win32.CW_USEDEFAULT,
        600,
        400,
        null,
        null,
        hinstance,
        null,
    );

    if (hwnd == null) {
        return;
    }

    var msg: win32.MSG = undefined;
    while (win32.GetMessageA(&msg, null, 0, 0) != 0) {
        _ = win32.TranslateMessage(&msg);
        _ = win32.DispatchMessageA(&msg);
    }
}
