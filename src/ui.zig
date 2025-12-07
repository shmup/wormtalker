const win32 = @import("win32.zig");
const scanner = @import("scanner.zig");

// layout constants
pub const BUTTON_HEIGHT: i32 = 25;
pub const BUTTON_PADDING: i32 = 2;
pub const BUTTON_CHAR_WIDTH: i32 = 7;
pub const MIN_BUTTON_WIDTH: i32 = 40;
pub const MIN_WINDOW_WIDTH: i32 = 600;
pub const MIN_WINDOW_HEIGHT: i32 = 460;
pub const TOOLBAR_PADDING: i32 = 8;
pub const TOOLBAR_ITEM_SPACING: i32 = 4;
pub const TOOLBAR_CTRL_HEIGHT: i32 = 23;
pub const TOOLBAR_HEIGHT: i32 = TOOLBAR_CTRL_HEIGHT + 2 * TOOLBAR_PADDING;
pub const COMBOBOX_WIDTH: i32 = 160;
pub const COMBOBOX_HEIGHT: i32 = 250;
pub const RANDOM_BUTTON_WIDTH: i32 = 55;
pub const ICON_SIZE: i32 = 22;
pub const MAX_BUTTONS: usize = 128;
pub const CHECKBOX_WIDTH: i32 = 110;
pub const CHECKBOX_HEIGHT: i32 = 20;
pub const SCROLL_LINE_AMOUNT: i32 = 20;
pub const SCROLL_WHEEL_AMOUNT: i32 = 30;
pub const MENU_ITEM_WIDTH: u32 = 160;
pub const MENU_RIGHT_MARGIN: i32 = 100;

// control IDs
pub const ID_COMBOBOX: usize = 1000;
pub const ID_AUTO_PREVIEW: usize = 3002;
pub const ID_RANDOM: usize = 3003;

// menu IDs
pub const IDM_ABOUT: usize = 2001;
pub const IDM_EXIT: usize = 2002;
pub const IDM_CLOSE: usize = 2003;

// cached grid layout state
pub const GridCache = struct {
    client_width: i32 = 0,
    num_buttons: usize = 0,
    num_cols: usize = 0,
    btn_width: i32 = 0,
    content_height: i32 = 0,
};

pub fn createMenuBar(hwnd: win32.HWND) void {
    const menu_bar = win32.CreateMenu();
    const help_menu = win32.CreatePopupMenu();

    if (help_menu) |help| {
        _ = win32.AppendMenuA(help, win32.MF_STRING, IDM_ABOUT, "&About");
        _ = win32.AppendMenuA(help, win32.MF_STRING, IDM_EXIT, "E&xit");
    }

    if (menu_bar) |bar| {
        // title text on the left (owner-drawn so it's truly non-interactive)
        _ = win32.AppendMenuA(bar, win32.MF_OWNERDRAW | win32.MF_DISABLED, 0, "wormtalker v1.2 by shmup");
        // help menu (right-justified, left of X)
        _ = win32.AppendMenuA(bar, win32.MF_POPUP | win32.MF_RIGHTJUSTIFY, @intFromPtr(help_menu), "&Help");
        // close button on the right
        _ = win32.AppendMenuA(bar, win32.MF_STRING, IDM_CLOSE, "X");
        _ = win32.SetMenu(hwnd, bar);
    }
}

pub fn createToolbar(
    hwnd: win32.HWND,
    bank_count: usize,
    getBankName: *const fn (usize) [:0]const u8,
    icon_ctrl_out: *?win32.HWND,
    random_button_out: *?win32.HWND,
    combobox_out: *?win32.HWND,
    checkbox_out: *?win32.HWND,
) void {
    const hinstance = win32.GetModuleHandleA(null);

    // create icon first (leftmost)
    icon_ctrl_out.* = win32.CreateWindowExA(
        0,
        "STATIC",
        "",
        win32.WS_CHILD | win32.WS_VISIBLE | win32.SS_ICON,
        BUTTON_PADDING,
        TOOLBAR_PADDING,
        ICON_SIZE,
        ICON_SIZE,
        hwnd,
        null,
        hinstance,
        null,
    );

    // load small icon and set it
    if (icon_ctrl_out.*) |ctrl| {
        const small_icon = win32.LoadImageA(hinstance, win32.IDI_APP, win32.IMAGE_ICON, ICON_SIZE, ICON_SIZE, win32.LR_DEFAULTCOLOR);
        if (small_icon) |ico| {
            _ = win32.SendMessageA(ctrl, win32.STM_SETICON, @intFromPtr(ico), 0);
        }
    }

    const random_x = BUTTON_PADDING + ICON_SIZE + TOOLBAR_ITEM_SPACING;

    // create random button (after icon) - owner-drawn to avoid focus rectangle
    random_button_out.* = win32.CreateWindowExA(
        0,
        "BUTTON",
        "random",
        win32.WS_CHILD | win32.WS_VISIBLE | win32.BS_OWNERDRAW,
        random_x,
        TOOLBAR_PADDING,
        RANDOM_BUTTON_WIDTH,
        TOOLBAR_CTRL_HEIGHT,
        hwnd,
        @ptrFromInt(ID_RANDOM),
        hinstance,
        null,
    );

    // only show combobox if we have multiple banks
    var checkbox_x = random_x + RANDOM_BUTTON_WIDTH + TOOLBAR_ITEM_SPACING;

    if (bank_count > 1) {
        const combobox_x = checkbox_x;
        combobox_out.* = win32.CreateWindowExA(
            0,
            "COMBOBOX",
            "",
            win32.WS_CHILD | win32.WS_VISIBLE | win32.CBS_DROPDOWNLIST | win32.CBS_HASSTRINGS,
            combobox_x,
            TOOLBAR_PADDING,
            COMBOBOX_WIDTH,
            COMBOBOX_HEIGHT,
            hwnd,
            @ptrFromInt(ID_COMBOBOX),
            hinstance,
            null,
        );

        if (combobox_out.*) |combo| {
            for (0..bank_count) |i| {
                const name = getBankName(i);
                _ = win32.SendMessageA(combo, win32.CB_ADDSTRING, 0, @bitCast(@intFromPtr(name.ptr)));
            }
            _ = win32.SendMessageA(combo, win32.CB_SETCURSEL, 0, 0);
        }

        checkbox_x = combobox_x + COMBOBOX_WIDTH + TOOLBAR_ITEM_SPACING;
    } else {
        combobox_out.* = null;
    }

    // create auto-preview checkbox
    checkbox_out.* = win32.CreateWindowExA(
        0,
        "BUTTON",
        "auto-preview",
        win32.WS_CHILD | win32.WS_VISIBLE | win32.BS_AUTOCHECKBOX,
        checkbox_x,
        TOOLBAR_PADDING + 3,
        CHECKBOX_WIDTH,
        CHECKBOX_HEIGHT,
        hwnd,
        @ptrFromInt(ID_AUTO_PREVIEW),
        hinstance,
        null,
    );

    // load saved setting from registry
    if (checkbox_out.*) |checkbox| {
        const check_state: usize = if (scanner.getAutoPreview()) win32.BST_CHECKED else win32.BST_UNCHECKED;
        _ = win32.SendMessageA(checkbox, win32.BM_SETCHECK, check_state, 0);
    }
}

pub fn createButtonsForBank(
    hwnd: win32.HWND,
    buttons: *[MAX_BUTTONS]?win32.HWND,
    num_buttons: *usize,
    bank_index: usize,
    getWavCount: *const fn (usize) usize,
    getWavName: *const fn (usize, usize) []const u8,
) void {
    const hinstance = win32.GetModuleHandleA(null);

    // destroy existing buttons
    for (buttons[0..num_buttons.*]) |maybe_btn| {
        if (maybe_btn) |btn| {
            _ = win32.DestroyWindow(btn);
        }
    }
    buttons.* = [_]?win32.HWND{null} ** MAX_BUTTONS;

    const wav_count = getWavCount(bank_index);
    num_buttons.* = @min(wav_count, MAX_BUTTONS);

    for (0..num_buttons.*) |i| {
        const wav_name = getWavName(bank_index, i);
        var name_buf: [64:0]u8 = undefined;
        const name_len = @min(wav_name.len, 63);
        @memcpy(name_buf[0..name_len], wav_name[0..name_len]);
        name_buf[name_len] = 0;

        buttons[i] = win32.CreateWindowExA(
            0,
            "BUTTON",
            &name_buf,
            win32.WS_CHILD | win32.WS_VISIBLE | win32.BS_OWNERDRAW,
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

pub fn layoutButtons(
    hwnd: win32.HWND,
    buttons: []?win32.HWND,
    current_bank: usize,
    scroll_pos: *i32,
    content_height: *i32,
    cache: *GridCache,
    getWavName: *const fn (usize, usize) []const u8,
) void {
    var rect: win32.RECT = undefined;
    _ = win32.GetClientRect(hwnd, &rect);
    const client_width = rect.right - rect.left;
    const client_height = rect.bottom - rect.top;
    const button_area_height = client_height - TOOLBAR_HEIGHT;
    const row_height: i32 = BUTTON_HEIGHT + BUTTON_PADDING;
    const num_buttons = buttons.len;

    // only recalculate grid if width or button count changed
    if (client_width != cache.client_width or num_buttons != cache.num_buttons) {
        cache.client_width = client_width;
        cache.num_buttons = num_buttons;

        // find widest button needed for this bank
        var max_btn_width: i32 = MIN_BUTTON_WIDTH;
        for (0..num_buttons) |i| {
            const wav_name = getWavName(current_bank, i);
            const text_width = @as(i32, @intCast(wav_name.len)) * BUTTON_CHAR_WIDTH + 4;
            max_btn_width = @max(max_btn_width, text_width);
        }

        // calculate grid dimensions
        const target_width = @max(max_btn_width, 76);
        const cell_width = target_width + BUTTON_PADDING;

        // first pass: calculate content height to see if scrollbar needed
        var available_width = client_width - BUTTON_PADDING * 2;
        var num_cols: usize = @intCast(@max(1, @divTrunc(available_width + BUTTON_PADDING, cell_width)));
        var num_rows: i32 = @intCast((num_buttons + num_cols - 1) / num_cols);
        var calc_content_height = num_rows * row_height + BUTTON_PADDING;

        // if scrollbar needed, recalculate with reduced width
        if (calc_content_height > button_area_height) {
            const scrollbar_width = win32.GetSystemMetrics(win32.SM_CXVSCROLL);
            available_width = client_width - scrollbar_width - BUTTON_PADDING * 2;
            num_cols = @intCast(@max(1, @divTrunc(available_width + BUTTON_PADDING, cell_width)));
            num_rows = @intCast((num_buttons + num_cols - 1) / num_cols);
            calc_content_height = num_rows * row_height + BUTTON_PADDING;
        }

        cache.num_cols = num_cols;
        cache.btn_width = @divTrunc(available_width - @as(i32, @intCast(num_cols - 1)) * BUTTON_PADDING, @as(i32, @intCast(num_cols)));
        cache.content_height = calc_content_height;
    }

    // layout buttons using cached grid values with deferred positioning
    // this batches all moves into a single atomic operation for smooth scrolling
    const hdwp = win32.BeginDeferWindowPos(@intCast(num_buttons));
    if (hdwp) |h| {
        var current_hdwp = h;
        for (0..num_buttons) |i| {
            const col: i32 = @intCast(@mod(i, cache.num_cols));
            const row: i32 = @intCast(@divTrunc(i, cache.num_cols));

            const x = BUTTON_PADDING + col * (cache.btn_width + BUTTON_PADDING);
            const y = TOOLBAR_HEIGHT + row * row_height - scroll_pos.*;

            if (buttons[i]) |btn| {
                if (win32.DeferWindowPos(
                    current_hdwp,
                    btn,
                    null,
                    x,
                    y,
                    cache.btn_width,
                    BUTTON_HEIGHT,
                    win32.SWP_NOZORDER | win32.SWP_NOACTIVATE,
                )) |new_hdwp| {
                    current_hdwp = new_hdwp;
                }
            }
        }
        _ = win32.EndDeferWindowPos(current_hdwp);
    } else {
        // fallback to individual moves if BeginDeferWindowPos fails
        for (0..num_buttons) |i| {
            const col: i32 = @intCast(@mod(i, cache.num_cols));
            const row: i32 = @intCast(@divTrunc(i, cache.num_cols));

            const x = BUTTON_PADDING + col * (cache.btn_width + BUTTON_PADDING);
            const y = TOOLBAR_HEIGHT + row * row_height - scroll_pos.*;

            if (buttons[i]) |btn| {
                _ = win32.MoveWindow(btn, x, y, cache.btn_width, BUTTON_HEIGHT, 1);
            }
        }
    }

    content_height.* = cache.content_height;

    // clamp scroll position in case content shrunk on resize
    const max_scroll = @max(0, content_height.* - button_area_height);
    scroll_pos.* = @min(scroll_pos.*, max_scroll);

    var si = win32.SCROLLINFO{
        .fMask = win32.SIF_ALL,
        .nMin = 0,
        .nMax = content_height.*,
        .nPage = @intCast(button_area_height),
        .nPos = scroll_pos.*,
    };
    _ = win32.SetScrollInfo(hwnd, win32.SB_VERT, &si, 1);
}

pub fn handleScroll(hwnd: win32.HWND, wParam: win32.WPARAM, scroll_pos: *i32) bool {
    var si = win32.SCROLLINFO{ .fMask = win32.SIF_ALL };
    _ = win32.GetScrollInfo(hwnd, win32.SB_VERT, &si);

    const action = @as(u32, @truncate(wParam));
    var new_pos = si.nPos;

    switch (action) {
        win32.SB_LINEUP => new_pos -= SCROLL_LINE_AMOUNT,
        win32.SB_LINEDOWN => new_pos += SCROLL_LINE_AMOUNT,
        win32.SB_PAGEUP => new_pos -= @as(i32, @intCast(si.nPage)),
        win32.SB_PAGEDOWN => new_pos += @as(i32, @intCast(si.nPage)),
        win32.SB_THUMBTRACK => new_pos = si.nTrackPos,
        else => {},
    }

    const max_pos = si.nMax - @as(i32, @intCast(si.nPage));
    new_pos = @max(0, @min(new_pos, max_pos));

    if (new_pos != scroll_pos.*) {
        const delta = scroll_pos.* - new_pos;
        scroll_pos.* = new_pos;
        _ = win32.ScrollWindow(hwnd, 0, delta, null, null);
        return true; // needs layout refresh
    }
    return false;
}

pub fn scrollContent(hwnd: win32.HWND, delta: i32, scroll_pos: *i32) bool {
    var si = win32.SCROLLINFO{ .fMask = win32.SIF_ALL };
    _ = win32.GetScrollInfo(hwnd, win32.SB_VERT, &si);

    var new_pos = scroll_pos.* + delta;
    const max_pos = si.nMax - @as(i32, @intCast(si.nPage));
    new_pos = @max(0, @min(new_pos, max_pos));

    if (new_pos != scroll_pos.*) {
        const scroll_delta = scroll_pos.* - new_pos;
        scroll_pos.* = new_pos;
        _ = win32.ScrollWindow(hwnd, 0, scroll_delta, null, null);
        return true; // needs layout refresh
    }
    return false;
}

pub fn setButtonState(buttons: []?win32.HWND, index: u16, pressed: bool) void {
    if (index >= buttons.len) return;
    if (buttons[index]) |btn| {
        _ = win32.SendMessageA(btn, win32.BM_SETSTATE, @intFromBool(pressed), 0);
        _ = win32.InvalidateRect(btn, null, 1);
        _ = win32.UpdateWindow(btn);
    }
}

pub fn hideAllButtons(buttons: []?win32.HWND) void {
    for (buttons) |maybe_btn| {
        if (maybe_btn) |btn| {
            _ = win32.ShowWindow(btn, win32.SW_HIDE);
        }
    }
}

pub fn isAutoPreviewEnabled(checkbox: ?win32.HWND) bool {
    if (checkbox) |cb| {
        return win32.SendMessageA(cb, win32.BM_GETCHECK, 0, 0) == win32.BST_CHECKED;
    }
    return true;
}
