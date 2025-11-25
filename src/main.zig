const std = @import("std");
const win32 = @import("win32.zig");
const sound_banks = @import("sound_banks.zig");
const scanner = @import("scanner.zig");

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

// browse button ID
const ID_BROWSE: usize = 3001;

// UI state
const UIState = enum {
    normal,
    browse_needed,
};

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
        if (g_runtime_banks) |banks| return banks.banks.len;
        return 0;
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
                    const wav = bank.wavs[wav_index];
                    _ = win32.PlaySoundA(wav.path.ptr, null, win32.SND_FILENAME | win32.SND_ASYNC);
                }
            }
        }
    } else {
        const bank = sound_banks.sound_banks[bank_index];
        if (wav_index < bank.wavs.len) {
            const wav = bank.wavs[wav_index];
            _ = win32.PlaySoundA(wav.data.ptr, null, win32.SND_MEMORY | win32.SND_ASYNC);
        }
    }
}

fn changeBankByDelta(hwnd: win32.HWND, delta: i32) void {
    const num_banks: i32 = @intCast(getBankCount());
    if (num_banks == 0) return;

    var new_bank: i32 = @as(i32, @intCast(g_current_bank)) + delta;
    // wrap around
    if (new_bank < 0) new_bank = num_banks - 1;
    if (new_bank >= num_banks) new_bank = 0;

    if (g_combobox) |combo| {
        _ = win32.SendMessageA(combo, win32.CB_SETCURSEL, @intCast(new_bank), 0);
    }
    handleBankChange(hwnd);
}

// globals for window state
var g_buttons: [MAX_BUTTONS]?win32.HWND = [_]?win32.HWND{null} ** MAX_BUTTONS;
var g_num_buttons: usize = 0;
var g_combobox: ?win32.HWND = null;
var g_current_bank: usize = 0;
var g_scroll_pos: i32 = 0;
var g_content_height: i32 = 0;
var g_main_hwnd: ?win32.HWND = null;
var g_held_key: ?u32 = null; // tracks key held down to ignore repeats
var g_pending_button: ?u16 = null; // tracks button pressed while dropdown was closing

// runtime mode state
var g_ui_state: UIState = .normal;
var g_runtime_banks: ?scanner.ScanResult = null;
var g_browse_button: ?win32.HWND = null;
var g_browse_label: ?win32.HWND = null;
var g_allocator: std.mem.Allocator = std.heap.page_allocator;

fn wndProc(hwnd: win32.HWND, msg: u32, wParam: win32.WPARAM, lParam: win32.LPARAM) callconv(.c) win32.LRESULT {
    switch (msg) {
        win32.WM_CREATE => {
            g_main_hwnd = hwnd;
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
                if (control_id == IDM_EXIT) {
                    win32.PostQuitMessage(0);
                    return 0;
                } else if (control_id == IDM_ABOUT) {
                    _ = win32.MessageBoxA(hwnd, "wormboard\n\nsoundboard for worms armageddon", "about wormboard", win32.MB_OK | win32.MB_ICONINFORMATION);
                    return 0;
                }
            }
            if (control_id == ID_BROWSE and notification == win32.BN_CLICKED) {
                handleBrowseClick(hwnd);
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
                            if (g_buttons[btn_index]) |btn| {
                                _ = win32.SendMessageA(btn, win32.BM_SETSTATE, 1, 0);
                                g_pending_button = btn_index;
                                _ = win32.SetCapture(hwnd);
                            }
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
                // release button visual state
                if (g_buttons[btn_index]) |btn| {
                    _ = win32.SendMessageA(btn, win32.BM_SETSTATE, 0, 0);
                }
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
            // release any held button when window loses focus
            if (g_held_key) |vk| {
                if (keyToSoundIndex(vk)) |index| {
                    if (g_buttons[index]) |btn| {
                        _ = win32.SendMessageA(btn, win32.BM_SETSTATE, 0, 0);
                    }
                }
                g_held_key = null;
            }
            // also release pending button from dropdown
            if (g_pending_button) |btn_index| {
                _ = win32.ReleaseCapture();
                if (g_buttons[btn_index]) |btn| {
                    _ = win32.SendMessageA(btn, win32.BM_SETSTATE, 0, 0);
                }
                g_pending_button = null;
            }
            return 0;
        },
        win32.WM_KEYDOWN => {
            const vk: u32 = @truncate(wParam);
            // up/down arrows navigate banks
            if (vk == win32.VK_UP) {
                changeBankByDelta(hwnd, -1);
                return 0;
            } else if (vk == win32.VK_DOWN) {
                changeBankByDelta(hwnd, 1);
                return 0;
            }
            // alphanumeric keys - show button pressed (ignore key repeat)
            if (g_held_key == null) {
                if (keyToSoundIndex(vk)) |index| {
                    g_held_key = vk;
                    if (g_buttons[index]) |btn| {
                        _ = win32.SendMessageA(btn, win32.BM_SETSTATE, 1, 0);
                    }
                    return 0;
                }
            }
            return win32.DefWindowProcA(hwnd, msg, wParam, lParam);
        },
        win32.WM_KEYUP => {
            const vk: u32 = @truncate(wParam);
            // release button and play sound
            if (g_held_key == vk) {
                if (keyToSoundIndex(vk)) |index| {
                    if (g_buttons[index]) |btn| {
                        _ = win32.SendMessageA(btn, win32.BM_SETSTATE, 0, 0);
                    }
                    playSound(index);
                }
                g_held_key = null;
                return 0;
            }
            return win32.DefWindowProcA(hwnd, msg, wParam, lParam);
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
        const bank_count = getBankCount();
        for (0..bank_count) |i| {
            const name = getBankName(i);
            _ = win32.SendMessageA(combo, win32.CB_ADDSTRING, 0, @bitCast(@intFromPtr(name.ptr)));
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

    // layout buttons in rows
    var x: i32 = BUTTON_PADDING;
    var y: i32 = TOOLBAR_HEIGHT + BUTTON_PADDING - g_scroll_pos;
    const row_height: i32 = BUTTON_HEIGHT + BUTTON_PADDING;

    for (0..g_num_buttons) |i| {
        const wav_name = getWavName(g_current_bank, i);
        const text_width = @as(i32, @intCast(wav_name.len)) * BUTTON_CHAR_WIDTH + 16;
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
    if (index < getWavCount(g_current_bank)) {
        playWav(g_current_bank, index);
        // return focus to main window so keyboard shortcuts work
        _ = win32.SetFocus(g_main_hwnd);
    }
}

fn handleBankChange(hwnd: win32.HWND) void {
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
        }
    }
}

// browse UI functions (shown when worms installation not found)
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

// parse command line arguments
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

    // try to read worms path from registry
    var path_buf: [win32.MAX_PATH]u8 = undefined;
    if (scanner.getWormsPath(&path_buf)) |path| {
        // try to scan the speech directory
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
