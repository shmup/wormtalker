const std = @import("std");
const win32 = @import("win32.zig");
const sound_banks = @import("sound_banks.g.zig");
const scanner = @import("scanner.zig");

// constants {{{

// layout constants
const BUTTON_HEIGHT: i32 = 25;
const BUTTON_PADDING: i32 = 2;
const BUTTON_CHAR_WIDTH: i32 = 7;
const MIN_BUTTON_WIDTH: i32 = 40;
const MIN_WINDOW_WIDTH: i32 = 600;
const MIN_WINDOW_HEIGHT: i32 = 360;
const TOOLBAR_PADDING: i32 = 8; // vertical padding above/below toolbar controls
const TOOLBAR_CTRL_HEIGHT: i32 = 23; // match combobox edit height
const TOOLBAR_HEIGHT: i32 = TOOLBAR_CTRL_HEIGHT + 2 * TOOLBAR_PADDING;
const COMBOBOX_WIDTH: i32 = 160;
const COMBOBOX_HEIGHT: i32 = 250;
const RANDOM_BUTTON_WIDTH: i32 = 55;
const ICON_SIZE: i32 = 22; // fill toolbar height
const MAX_BUTTONS: usize = 128;

// control IDs
const ID_COMBOBOX: usize = 1000;

// menu IDs
const IDM_ABOUT: usize = 2001;
const IDM_EXIT: usize = 2002;
const IDM_CLOSE: usize = 2003;

// browse button ID
const ID_BROWSE: usize = 3001;
const ID_AUTO_PREVIEW: usize = 3002;
const ID_RANDOM: usize = 3003;

// timer IDs
const TIMER_BUTTON_RELEASE: usize = 4001;
const TIMER_NAV_REPEAT: usize = 4002;
const FLASH_DURATION_MS: u32 = 100;
const NAV_INITIAL_DELAY_MS: u32 = 300; // delay before repeat starts
const NAV_REPEAT_MS: u32 = 50; // fast repeat rate after initial delay

// navigation
const BANKS_PER_PAGE: i32 = 13;

// UI state
const UIState = enum {
    normal,
    browse_needed,
};

// }}}

// sound bank access {{{

// keyboard mapping: 1-9, 0, then QWERTY order
// virtual key codes: '0'-'9' = 0x30-0x39, 'A'-'Z' = 0x41-0x5A
const QWERTY_KEYS = "QWERTYUIOPASDFGHJKLZXCVBNM";

fn keyToSoundIndex(vk: u32) ?u16 {
    // number keys: 1-9 -> 0-8, 0 -> 9
    if (vk >= '1' and vk <= '9') return @intCast(vk - '1');
    if (vk == '0') return 9;

    // letter keys: QWERTY order -> 10+
    for (QWERTY_KEYS, 0..) |key, i| {
        if (vk == key) return @intCast(10 + i);
    }
    return null;
}

// unified bank access functions (work for both embedded and runtime modes)
fn getBankCount() usize {
    if (sound_banks.runtime_mode) {
        return if (g_runtime_banks) |banks| banks.banks.len else 0;
    }
    return sound_banks.sound_banks.len;
}

fn getBankName(index: usize) [:0]const u8 {
    if (sound_banks.runtime_mode) {
        if (g_runtime_banks) |banks| {
            if (index < banks.banks.len) return banks.banks[index].name;
        }
        return "";
    }
    return sound_banks.sound_banks[index].name;
}

fn getWavCount(bank_index: usize) usize {
    if (sound_banks.runtime_mode) {
        if (g_runtime_banks) |banks| {
            if (bank_index < banks.banks.len) return banks.banks[bank_index].wavs.len;
        }
        return 0;
    }
    return sound_banks.sound_banks[bank_index].wavs.len;
}

fn getWavName(bank_index: usize, wav_index: usize) []const u8 {
    if (sound_banks.runtime_mode) {
        if (g_runtime_banks) |banks| {
            if (bank_index < banks.banks.len) {
                const bank = banks.banks[bank_index];
                if (wav_index < bank.wavs.len) return bank.wavs[wav_index].name;
            }
        }
        return "";
    }
    return sound_banks.sound_banks[bank_index].wavs[wav_index].name;
}

fn playWav(bank_index: usize, wav_index: usize) void {
    if (sound_banks.runtime_mode) {
        if (g_runtime_banks) |banks| {
            if (bank_index < banks.banks.len) {
                const bank = banks.banks[bank_index];
                if (wav_index < bank.wavs.len) {
                    _ = win32.PlaySoundA(bank.wavs[wav_index].path.ptr, null, win32.SND_FILENAME | win32.SND_ASYNC);
                }
            }
        }
    } else {
        const bank = sound_banks.sound_banks[bank_index];
        if (wav_index < bank.wavs.len) {
            _ = win32.PlaySoundA(bank.wavs[wav_index].data.ptr, null, win32.SND_MEMORY | win32.SND_ASYNC);
        }
    }
}

// check if auto-preview is enabled
fn isAutoPreviewEnabled() bool {
    if (g_auto_preview_checkbox) |checkbox| {
        return win32.SendMessageA(checkbox, win32.BM_GETCHECK, 0, 0) == win32.BST_CHECKED;
    }
    return true; // default to enabled if checkbox doesn't exist
}

// apply a bank change immediately (called from debounce timer)
fn applyBankChange(hwnd: win32.HWND, target: usize) void {
    const num_banks = getBankCount();
    if (num_banks == 0 or target >= num_banks) return;

    // ensure combobox shows correct selection (might have drifted)
    if (g_combobox) |combo| {
        _ = win32.SendMessageA(combo, win32.CB_SETCURSEL, @intCast(target), 0);
    }

    // freeze painting
    _ = win32.SendMessageA(hwnd, win32.WM_SETREDRAW, 0, 0);

    g_current_bank = target;
    g_scroll_pos = 0;
    createButtonsForBank(hwnd, g_current_bank);
    layoutControls(hwnd);

    // resume painting and force redraw
    _ = win32.SendMessageA(hwnd, win32.WM_SETREDRAW, 1, 0);
    _ = win32.RedrawWindow(hwnd, null, null, win32.RDW_ERASE | win32.RDW_INVALIDATE | win32.RDW_ALLCHILDREN);

    // play random sound from new bank (if auto-preview enabled)
    if (isAutoPreviewEnabled()) {
        playRandomSound();
    }
}

// }}}

// globals {{{

// globals for window state
var g_buttons: [MAX_BUTTONS]?win32.HWND = [_]?win32.HWND{null} ** MAX_BUTTONS;
var g_num_buttons: usize = 0;
var g_combobox: ?win32.HWND = null;
var g_auto_preview_checkbox: ?win32.HWND = null;
var g_random_button: ?win32.HWND = null;
var g_current_bank: usize = 0;
var g_scroll_pos: i32 = 0;
var g_content_height: i32 = 0;
var g_main_hwnd: ?win32.HWND = null;
var g_held_key: ?u32 = null; // tracks sound key held down to ignore repeats
var g_held_nav_key: ?u32 = null; // tracks nav key held (for our own repeat timer)
var g_nav_repeat_started: bool = false; // true after initial delay, now repeating fast
var g_pending_button: ?u16 = null; // tracks button pressed while dropdown was closing
var g_prng: std.Random.DefaultPrng = undefined;
var g_flash_button: ?u16 = null; // button being flashed after bank change

// runtime mode state
var g_ui_state: UIState = .normal;
var g_runtime_banks: ?scanner.ScanResult = null;
var g_browse_button: ?win32.HWND = null;
var g_browse_label: ?win32.HWND = null;
var g_allocator: std.mem.Allocator = std.heap.page_allocator;
var g_toolbar_brush: ?win32.HBRUSH = null;
var g_icon_ctrl: ?win32.HWND = null;

// }}}

// input handling {{{

// button state helper
fn setButtonState(index: u16, pressed: bool) void {
    if (g_buttons[index]) |btn| {
        _ = win32.SendMessageA(btn, win32.BM_SETSTATE, @intFromBool(pressed), 0);
    }
}

// release held key and unpress its button
fn releaseHeldKey() void {
    if (g_held_key) |vk| {
        if (keyToSoundIndex(vk)) |index| {
            setButtonState(index, false);
        }
        g_held_key = null;
    }
}

// apply nav key action (called on first press and by repeat timer)
fn applyNavKey(hwnd: win32.HWND, vk: u32) void {
    const num_banks = getBankCount();
    if (num_banks == 0) return;

    const base: i32 = @intCast(g_current_bank);
    const num: i32 = @intCast(num_banks);

    var target: i32 = switch (vk) {
        win32.VK_UP => base - 1,
        win32.VK_DOWN => base + 1,
        win32.VK_PRIOR => base - BANKS_PER_PAGE,
        win32.VK_NEXT => base + BANKS_PER_PAGE,
        win32.VK_HOME => 0,
        win32.VK_END => num - 1,
        else => base,
    };

    // wrap around
    target = @mod(target, num);

    applyBankChange(hwnd, @intCast(target));
}

// handle WM_KEYDOWN - returns true if handled
fn handleKeyDown(hwnd: win32.HWND, vk: u32) bool {
    switch (vk) {
        win32.VK_UP, win32.VK_DOWN, win32.VK_PRIOR, win32.VK_NEXT, win32.VK_HOME, win32.VK_END => {
            // ignore if already holding a nav key (we handle repeat ourselves)
            if (g_held_nav_key != null) return true;

            g_held_nav_key = vk;
            g_nav_repeat_started = false;
            applyNavKey(hwnd, vk);

            // start timer with initial delay (longer before repeat kicks in)
            _ = win32.SetTimer(hwnd, TIMER_NAV_REPEAT, NAV_INITIAL_DELAY_MS, null);
        },
        else => {
            // alphanumeric keys - show button pressed (ignore key repeat)
            if (g_held_key == null) {
                if (keyToSoundIndex(vk)) |index| {
                    g_held_key = vk;
                    setButtonState(index, true);
                    return true;
                }
            }
            return false;
        },
    }
    return true;
}

// handle WM_KEYUP - returns true if handled
fn handleKeyUp(hwnd: win32.HWND, vk: u32) bool {
    // nav key release - stop repeat timer
    if (g_held_nav_key == vk) {
        g_held_nav_key = null;
        g_nav_repeat_started = false;
        _ = win32.KillTimer(hwnd, TIMER_NAV_REPEAT);
        return true;
    }

    // sound key release - play sound
    if (g_held_key == vk) {
        if (keyToSoundIndex(vk)) |index| {
            setButtonState(index, false);
            playSound(index);
        }
        g_held_key = null;
        return true;
    }
    return false;
}

// }}}

// window proc {{{

fn wndProc(hwnd: win32.HWND, msg: u32, wParam: win32.WPARAM, lParam: win32.LPARAM) callconv(.c) win32.LRESULT {
    switch (msg) {
        win32.WM_CREATE => {
            g_main_hwnd = hwnd;
            // create toolbar brush (used for menu bar and checkbox background)
            g_toolbar_brush = win32.CreateSolidBrush(COLOR_TOOLBAR);
            createMenuBar(hwnd);
            if (g_ui_state == .browse_needed) {
                createBrowseUI(hwnd);
            } else {
                createCombobox(hwnd);
                createButtonsForBank(hwnd, 0);
            }
            // hide focus rectangles on buttons
            _ = win32.SendMessageA(hwnd, win32.WM_UPDATEUISTATE, (win32.UISF_HIDEFOCUS << 16) | win32.UIS_SET, 0);
            return 0;
        },
        win32.WM_SIZE => {
            layoutControls(hwnd);
            _ = win32.RedrawWindow(hwnd, null, null, win32.RDW_ERASE | win32.RDW_INVALIDATE | win32.RDW_ALLCHILDREN);
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
                if (control_id == IDM_EXIT or control_id == IDM_CLOSE) {
                    win32.PostQuitMessage(0);
                    return 0;
                } else if (control_id == IDM_ABOUT) {
                    _ = win32.MessageBoxA(hwnd, "wormtalker\n\nsoundboard for worms armageddon", "about wormtalker", win32.MB_OK | win32.MB_ICONINFORMATION);
                    return 0;
                }
            }
            if (control_id == ID_BROWSE and notification == win32.BN_CLICKED) {
                handleBrowseClick(hwnd);
                return 0;
            } else if (control_id == ID_RANDOM and notification == win32.BN_CLICKED) {
                handleRandomClick(hwnd);
                return 0;
            } else if (control_id == ID_AUTO_PREVIEW and notification == win32.BN_CLICKED) {
                // save setting to registry
                scanner.saveAutoPreview(isAutoPreviewEnabled());
                // return focus to main window so keyboard shortcuts work
                _ = win32.SetFocus(hwnd);
                return 0;
            } else if (control_id == ID_COMBOBOX and notification == win32.CBN_SELCHANGE) {
                handleBankChange(hwnd);
            } else if (control_id == ID_COMBOBOX and notification == win32.CBN_CLOSEUP) {
                // check if mouse is over a button - show it pressed, wait for release
                var pt: win32.POINT = undefined;
                if (win32.GetCursorPos(&pt) != 0) {
                    _ = win32.ScreenToClient(hwnd, &pt);
                    if (win32.ChildWindowFromPoint(hwnd, pt)) |child| {
                        const child_id = win32.GetDlgCtrlID(child);
                        if (child_id >= 0 and child_id < MAX_BUTTONS) {
                            const btn_index: u16 = @intCast(child_id);
                            setButtonState(btn_index, true);
                            g_pending_button = btn_index;
                            _ = win32.SetCapture(hwnd);
                        }
                    }
                }
                // return focus to main window after dropdown closes
                _ = win32.SetFocus(hwnd);
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
        win32.WM_LBUTTONUP => {
            // handle pending button from dropdown close
            if (g_pending_button) |btn_index| {
                _ = win32.ReleaseCapture();
                setButtonState(btn_index, false);
                // check if mouse is still over the same button
                var pt: win32.POINT = undefined;
                if (win32.GetCursorPos(&pt) != 0) {
                    _ = win32.ScreenToClient(hwnd, &pt);
                    if (win32.ChildWindowFromPoint(hwnd, pt)) |child| {
                        const child_id = win32.GetDlgCtrlID(child);
                        if (child_id >= 0 and @as(u16, @intCast(child_id)) == btn_index) {
                            playSound(btn_index);
                        }
                    }
                }
                g_pending_button = null;
                return 0;
            }
            return win32.DefWindowProcA(hwnd, msg, wParam, lParam);
        },
        win32.WM_KILLFOCUS => {
            releaseHeldKey();
            // stop nav repeat
            if (g_held_nav_key != null) {
                g_held_nav_key = null;
                g_nav_repeat_started = false;
                _ = win32.KillTimer(hwnd, TIMER_NAV_REPEAT);
            }
            // also release pending button from dropdown
            if (g_pending_button) |btn_index| {
                _ = win32.ReleaseCapture();
                setButtonState(btn_index, false);
                g_pending_button = null;
            }
            return 0;
        },
        win32.WM_KEYDOWN => {
            const vk: u32 = @truncate(wParam);
            if (handleKeyDown(hwnd, vk)) return 0;
            return win32.DefWindowProcA(hwnd, msg, wParam, lParam);
        },
        win32.WM_KEYUP => {
            const vk: u32 = @truncate(wParam);
            if (handleKeyUp(hwnd, vk)) return 0;
            return win32.DefWindowProcA(hwnd, msg, wParam, lParam);
        },
        win32.WM_TIMER => {
            if (wParam == TIMER_BUTTON_RELEASE) {
                _ = win32.KillTimer(hwnd, TIMER_BUTTON_RELEASE);
                if (g_flash_button) |btn_index| {
                    setButtonState(btn_index, false);
                    g_flash_button = null;
                }
            } else if (wParam == TIMER_NAV_REPEAT) {
                // repeat nav key while held
                if (g_held_nav_key) |vk| {
                    applyNavKey(hwnd, vk);
                    // after initial delay, switch to fast repeat
                    if (!g_nav_repeat_started) {
                        g_nav_repeat_started = true;
                        _ = win32.SetTimer(hwnd, TIMER_NAV_REPEAT, NAV_REPEAT_MS, null);
                    }
                } else {
                    _ = win32.KillTimer(hwnd, TIMER_NAV_REPEAT);
                }
            }
            return 0;
        },
        win32.WM_ERASEBKGND => {
            const hdc: win32.HDC = @ptrFromInt(@as(usize, @truncate(wParam)));
            var rect: win32.RECT = undefined;
            _ = win32.GetClientRect(hwnd, &rect);

            // paint entire window with yellow
            if (g_toolbar_brush) |brush| {
                _ = win32.FillRect(hdc, &rect, brush);
            }
            return 1;
        },
        win32.WM_MEASUREITEM => {
            const mis: *win32.MEASUREITEMSTRUCT = @ptrFromInt(@as(usize, @bitCast(lParam)));
            if (mis.CtlType == win32.ODT_MENU) {
                // measure title menu item
                mis.itemWidth = 160; // approximate width for "wormtalker v1.2 by shmup"
                mis.itemHeight = @intCast(win32.GetSystemMetrics(win32.SM_CYMENU));
                return 1;
            }
            return win32.DefWindowProcA(hwnd, msg, wParam, lParam);
        },
        win32.WM_DRAWITEM => {
            const dis: *win32.DRAWITEMSTRUCT = @ptrFromInt(@as(usize, @bitCast(lParam)));
            if (dis.CtlType == win32.ODT_MENU) {
                // draw title menu item - just text, no highlight
                _ = win32.SetBkMode(dis.hDC, win32.TRANSPARENT);
                _ = win32.SetTextColor(dis.hDC, COLOR_TEXT);
                const title = "wormtalker v1.2 by shmup";
                var text_rect = dis.rcItem;
                text_rect.left += 6; // padding
                _ = win32.DrawTextA(dis.hDC, title, @intCast(title.len), &text_rect, win32.DT_VCENTER | win32.DT_SINGLELINE);
                return 1;
            }
            drawButton(dis);
            return 1;
        },
        win32.WM_CTLCOLORSTATIC => {
            // handle checkbox background color
            const control: win32.HWND = @ptrFromInt(@as(usize, @bitCast(lParam)));
            if (g_auto_preview_checkbox != null and control == g_auto_preview_checkbox.?) {
                const hdc: win32.HDC = @ptrFromInt(@as(usize, @truncate(wParam)));
                _ = win32.SetBkMode(hdc, win32.TRANSPARENT);
                if (g_toolbar_brush) |brush| {
                    return @bitCast(@intFromPtr(brush));
                }
            }
            return win32.DefWindowProcA(hwnd, msg, wParam, lParam);
        },
        win32.WM_DESTROY => {
            if (g_toolbar_brush) |brush| {
                _ = win32.DeleteObject(@ptrCast(brush));
                g_toolbar_brush = null;
            }
            win32.PostQuitMessage(0);
            return 0;
        },
        else => return win32.DefWindowProcA(hwnd, msg, wParam, lParam),
    }
}

// }}}

// ui creation {{{

fn createMenuBar(hwnd: win32.HWND) void {
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

fn createCombobox(hwnd: win32.HWND) void {
    const hinstance = win32.GetModuleHandleA(null);

    // create icon first (leftmost)
    g_icon_ctrl = win32.CreateWindowExA(
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
    if (g_icon_ctrl) |ctrl| {
        const small_icon = win32.LoadImageA(hinstance, win32.IDI_APP, win32.IMAGE_ICON, ICON_SIZE, ICON_SIZE, win32.LR_DEFAULTCOLOR);
        if (small_icon) |ico| {
            _ = win32.SendMessageA(ctrl, win32.STM_SETICON, @intFromPtr(ico), 0);
        }
    }

    const random_x = BUTTON_PADDING + ICON_SIZE + BUTTON_PADDING;

    // create random button (after icon) - owner-drawn to avoid focus rectangle
    g_random_button = win32.CreateWindowExA(
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

    const combobox_x = random_x + RANDOM_BUTTON_WIDTH + BUTTON_PADDING;
    g_combobox = win32.CreateWindowExA(
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

    if (g_combobox) |combo| {
        const bank_count = getBankCount();
        for (0..bank_count) |i| {
            const name = getBankName(i);
            _ = win32.SendMessageA(combo, win32.CB_ADDSTRING, 0, @bitCast(@intFromPtr(name.ptr)));
        }
        _ = win32.SendMessageA(combo, win32.CB_SETCURSEL, 0, 0);
    }

    // create auto-preview checkbox to the right of combobox
    g_auto_preview_checkbox = win32.CreateWindowExA(
        0,
        "BUTTON",
        "auto-preview",
        win32.WS_CHILD | win32.WS_VISIBLE | win32.BS_AUTOCHECKBOX,
        combobox_x + COMBOBOX_WIDTH + BUTTON_PADDING,
        TOOLBAR_PADDING + 3, // slight vertical offset to align with combobox text
        100,
        20,
        hwnd,
        @ptrFromInt(ID_AUTO_PREVIEW),
        hinstance,
        null,
    );

    // load saved setting from registry
    if (g_auto_preview_checkbox) |checkbox| {
        const check_state: usize = if (scanner.getAutoPreview()) win32.BST_CHECKED else win32.BST_UNCHECKED;
        _ = win32.SendMessageA(checkbox, win32.BM_SETCHECK, check_state, 0);
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

    const wav_count = getWavCount(bank_index);
    g_num_buttons = @min(wav_count, MAX_BUTTONS);

    for (0..g_num_buttons) |i| {
        const wav_name = getWavName(bank_index, i);
        var name_buf: [64:0]u8 = undefined;
        const name_len = @min(wav_name.len, 63);
        @memcpy(name_buf[0..name_len], wav_name[0..name_len]);
        name_buf[name_len] = 0;

        g_buttons[i] = win32.CreateWindowExA(
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

fn layoutControls(hwnd: win32.HWND) void {
    // handle browse UI layout
    if (g_ui_state == .browse_needed) {
        layoutBrowseUI(hwnd);
        return;
    }

    var rect: win32.RECT = undefined;
    _ = win32.GetClientRect(hwnd, &rect);
    const client_width = rect.right - rect.left;
    const client_height = rect.bottom - rect.top;
    const button_area_height = client_height - TOOLBAR_HEIGHT;
    const available_width = client_width - BUTTON_PADDING * 2;

    // find widest button needed for this bank
    var max_btn_width: i32 = MIN_BUTTON_WIDTH;
    for (0..g_num_buttons) |i| {
        const wav_name = getWavName(g_current_bank, i);
        const text_width = @as(i32, @intCast(wav_name.len)) * BUTTON_CHAR_WIDTH + 4;
        max_btn_width = @max(max_btn_width, text_width);
    }

    // calculate grid dimensions - use generous width so buttons fill space
    const target_width = @max(max_btn_width, 76);
    const cell_width = target_width + BUTTON_PADDING;
    const num_cols: usize = @intCast(@max(1, @divTrunc(available_width + BUTTON_PADDING, cell_width)));
    const btn_width = @divTrunc(available_width - @as(i32, @intCast(num_cols - 1)) * BUTTON_PADDING, @as(i32, @intCast(num_cols)));
    const row_height: i32 = BUTTON_HEIGHT + BUTTON_PADDING;

    // layout buttons in grid
    for (0..g_num_buttons) |i| {
        const col: i32 = @intCast(@mod(i, num_cols));
        const row: i32 = @intCast(@divTrunc(i, num_cols));

        const x = BUTTON_PADDING + col * (btn_width + BUTTON_PADDING);
        const y = TOOLBAR_HEIGHT + row * row_height - g_scroll_pos;

        if (g_buttons[i]) |btn| {
            _ = win32.MoveWindow(btn, x, y, btn_width, BUTTON_HEIGHT, 1);
        }
    }

    // calculate content height
    const num_rows: i32 = @intCast((@as(usize, g_num_buttons) + num_cols - 1) / num_cols);
    g_content_height = num_rows * row_height + BUTTON_PADDING;

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

// }}}

// drawing {{{

// colors (BGR format)
const COLOR_NORMAL: u32 = 0x00F0F0F0; // light gray (default button)
const COLOR_PRESSED: u32 = 0x00CFCFFF; // pale pink (RGB: 0xFFCFCF)
const COLOR_TEXT: u32 = 0x00000000; // black
// ABGR (Alpha, Blue, Green, Red) - bytes reversed from RGB
// #RRGGBB → 0x00BBGGRR
// #FFFCA5 → 0x00A5FCFF
const COLOR_TOOLBAR: u32 = COLOR_NORMAL;

fn drawButton(dis: *win32.DRAWITEMSTRUCT) void {
    const is_pressed = (dis.itemState & win32.ODS_SELECTED) != 0;

    // pick background color
    const bg_color = if (is_pressed) COLOR_PRESSED else COLOR_NORMAL;
    const brush = win32.CreateSolidBrush(bg_color);
    defer _ = win32.DeleteObject(@ptrCast(brush));

    // fill background
    if (brush) |b| {
        _ = win32.FillRect(dis.hDC, &dis.rcItem, b);
    }

    // draw 3d edge
    var edge_rect = dis.rcItem;
    const edge = if (is_pressed) win32.EDGE_SUNKEN else win32.EDGE_RAISED;
    _ = win32.DrawEdge(dis.hDC, &edge_rect, edge, win32.BF_RECT);

    // get button text
    var text_buf: [64:0]u8 = undefined;
    const hwnd_item: win32.HWND = @ptrCast(dis.hwndItem);
    const text_len = win32.GetWindowTextA(hwnd_item, &text_buf, 64);
    if (text_len > 0) {
        text_buf[@intCast(text_len)] = 0;

        // setup text drawing
        _ = win32.SetBkColor(dis.hDC, bg_color);
        _ = win32.SetTextColor(dis.hDC, COLOR_TEXT);

        // offset text when pressed
        var text_rect = dis.rcItem;
        if (is_pressed) {
            text_rect.left += 1;
            text_rect.top += 1;
        }

        _ = win32.DrawTextA(dis.hDC, &text_buf, text_len, &text_rect, win32.DT_CENTER | win32.DT_VCENTER | win32.DT_SINGLELINE);
    }
}

fn playSound(index: u16) void {
    if (index < getWavCount(g_current_bank)) {
        playWav(g_current_bank, index);
        // return focus to main window so keyboard shortcuts work
        _ = win32.SetFocus(g_main_hwnd);
    }
}

fn playRandomSound() void {
    const wav_count = getWavCount(g_current_bank);
    if (wav_count == 0) return;

    const random_index: u16 = @intCast(g_prng.random().uintLessThan(usize, wav_count));

    // show button pressed briefly
    setButtonState(random_index, true);
    _ = win32.SetTimer(g_main_hwnd, TIMER_BUTTON_RELEASE, FLASH_DURATION_MS, null);
    g_flash_button = random_index;

    playSound(random_index);
}

fn handleBankChange(hwnd: win32.HWND) void {
    handleBankChangeInternal(hwnd, false);
}

fn handleBankChangeWithSound(hwnd: win32.HWND) void {
    handleBankChangeInternal(hwnd, true);
}

fn handleBankChangeInternal(hwnd: win32.HWND, play_random: bool) void {
    if (g_combobox) |combo| {
        const sel = win32.SendMessageA(combo, win32.CB_GETCURSEL, 0, 0);
        if (sel >= 0 and @as(usize, @intCast(sel)) < getBankCount()) {
            // freeze painting
            _ = win32.SendMessageA(hwnd, win32.WM_SETREDRAW, 0, 0);

            g_current_bank = @intCast(sel);
            g_scroll_pos = 0;
            createButtonsForBank(hwnd, g_current_bank);
            layoutControls(hwnd);

            // resume painting and force redraw
            _ = win32.SendMessageA(hwnd, win32.WM_SETREDRAW, 1, 0);
            _ = win32.RedrawWindow(hwnd, null, null, win32.RDW_ERASE | win32.RDW_INVALIDATE | win32.RDW_ALLCHILDREN);

            // play random sound from new bank (if auto-preview enabled)
            if (play_random and isAutoPreviewEnabled()) {
                playRandomSound();
            }
        }
    }
}

fn handleRandomClick(hwnd: win32.HWND) void {
    const num_banks = getBankCount();
    if (num_banks == 0) return;

    // pick a random bank
    const random_bank: usize = g_prng.random().uintLessThan(usize, num_banks);

    // update combobox selection
    if (g_combobox) |combo| {
        _ = win32.SendMessageA(combo, win32.CB_SETCURSEL, @intCast(random_bank), 0);
    }

    // apply the bank change (with auto-preview sound)
    applyBankChange(hwnd, random_bank);

    // restore focus so hotkeys work
    _ = win32.SetFocus(hwnd);
}

// }}}

// browse ui {{{

fn createBrowseUI(hwnd: win32.HWND) void {
    const hinstance = win32.GetModuleHandleA(null);

    // create label
    g_browse_label = win32.CreateWindowExA(
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
    g_browse_button = win32.CreateWindowExA(
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

fn layoutBrowseUI(hwnd: win32.HWND) void {
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

    if (g_browse_label) |label| {
        const label_x = @divTrunc(client_width - label_width, 2);
        _ = win32.MoveWindow(label, label_x, start_y, label_width, label_height, 1);
    }

    if (g_browse_button) |btn| {
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

fn handleBrowseClick(hwnd: win32.HWND) void {
    var path_buf: [win32.MAX_PATH]u8 = undefined;
    if (scanner.browseForFolder(hwnd, &path_buf)) |path| {
        // try to find worms root (travel up if needed)
        var root_buf: [win32.MAX_PATH]u8 = undefined;
        const worms_root = scanner.findWormsRoot(path, &root_buf) orelse path;

        // try to scan the selected/found directory
        if (scanner.scanSpeechDirectory(g_allocator, worms_root)) |result| {
            g_runtime_banks = result;
            // save for next time
            scanner.saveBrowsedPath(worms_root);
            transitionToNormalUI(hwnd);
        } else |_| {
            _ = win32.MessageBoxA(
                hwnd,
                "Could not find DATA\\User\\Speech in the selected folder or parent directories.\n\nPlease select your Worms Armageddon installation directory.",
                "Invalid folder",
                win32.MB_OK | win32.MB_ICONINFORMATION,
            );
        }
    }
}

fn transitionToNormalUI(hwnd: win32.HWND) void {
    // destroy browse UI
    if (g_browse_label) |label| {
        _ = win32.DestroyWindow(label);
        g_browse_label = null;
    }
    if (g_browse_button) |btn| {
        _ = win32.DestroyWindow(btn);
        g_browse_button = null;
    }

    // switch to normal UI
    g_ui_state = .normal;
    createCombobox(hwnd);
    createButtonsForBank(hwnd, 0);
    layoutControls(hwnd);
    _ = win32.RedrawWindow(hwnd, null, null, win32.RDW_ERASE | win32.RDW_INVALIDATE | win32.RDW_ALLCHILDREN);
}

// }}}

// main {{{

fn parseArgs() bool {
    const cmd_line = win32.GetCommandLineA();
    if (cmd_line == null) return false;

    // find -b or --browse in command line
    const cmd = std.mem.span(cmd_line.?);
    return std.mem.indexOf(u8, cmd, " -b") != null or
        std.mem.indexOf(u8, cmd, " --browse") != null;
}

// runtime initialization (called before window creation)
fn initRuntime(force_browse: bool) void {
    if (!sound_banks.runtime_mode) return;

    // skip registry lookup if browse forced
    if (force_browse) {
        g_ui_state = .browse_needed;
        return;
    }

    var path_buf: [win32.MAX_PATH]u8 = undefined;

    // try saved path first (from previous browse)
    if (scanner.getSavedPath(&path_buf)) |path| {
        if (scanner.scanSpeechDirectory(g_allocator, path)) |result| {
            g_runtime_banks = result;
            g_ui_state = .normal;
            return;
        } else |_| {}
    }

    // fall back to worms registry key
    if (scanner.getWormsPath(&path_buf)) |path| {
        if (scanner.scanSpeechDirectory(g_allocator, path)) |result| {
            g_runtime_banks = result;
            g_ui_state = .normal;
            return;
        } else |_| {}
    }

    // no path found or scan failed - show browse UI
    g_ui_state = .browse_needed;
}

pub fn main() void {
    // seed prng with timestamp
    const seed: u64 = @bitCast(std.time.milliTimestamp());
    g_prng = std.Random.DefaultPrng.init(seed);

    // parse command line args
    const force_browse = parseArgs();

    // initialize runtime mode (check registry, scan speech directory)
    initRuntime(force_browse);

    const hinstance = win32.GetModuleHandleA(null);

    const icon = win32.LoadIconA(hinstance, win32.IDI_APP);
    const wc = win32.WNDCLASSEXA{
        .lpfnWndProc = wndProc,
        .hInstance = hinstance,
        .hIcon = icon,
        .hIconSm = icon,
        .hCursor = win32.LoadCursorA(null, win32.IDC_ARROW),
        .hbrBackground = @ptrFromInt(win32.COLOR_BTNFACE + 1),
        .lpszClassName = "WormboardClass",
    };

    if (win32.RegisterClassExA(&wc) == 0) {
        return;
    }

    // popup window with resize border but no title bar (our menu bar serves as the title)
    const window_style = win32.WS_POPUP | win32.WS_THICKFRAME | win32.WS_MINIMIZEBOX | win32.WS_MAXIMIZEBOX | win32.WS_VISIBLE | win32.WS_VSCROLL | win32.WS_CLIPCHILDREN;
    const hwnd = win32.CreateWindowExA(
        win32.WS_EX_APPWINDOW, // show in taskbar
        "WormboardClass",
        "wormtalker",
        window_style,
        100, // x position (CW_USEDEFAULT doesn't work well with popup windows)
        100, // y position
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

// }}}

// vim: set foldmethod=marker:
