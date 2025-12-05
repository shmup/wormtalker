const std = @import("std");
const win32 = @import("win32.zig");
const sound_banks = @import("sound_banks.g.zig");
const scanner = @import("scanner.zig");
const ui = @import("ui.zig");
const input = @import("input.zig");
const drawing = @import("drawing.zig");
const browse = @import("browse.zig");

// timer IDs
const TIMER_BUTTON_RELEASE: usize = 4001;
const TIMER_NAV_REPEAT: usize = 4002;
const TIMER_AUTO_PREVIEW: usize = 4003;
const TIMER_BANK_UPDATE: usize = 4004;
const FLASH_DURATION_MS: u32 = 100;
const NAV_INITIAL_DELAY_MS: u32 = 150;
const NAV_REPEAT_MS: u32 = 0;
const AUTO_PREVIEW_DELAY_MS: u32 = 150;
const BANK_UPDATE_DELAY_MS: u32 = 30;

// UI state enum
const UIState = enum {
    normal,
    browse_needed,
};

// consolidated application state {{{
const AppState = struct {
    // window handles
    buttons: [ui.MAX_BUTTONS]?win32.HWND = [_]?win32.HWND{null} ** ui.MAX_BUTTONS,
    num_buttons: usize = 0,
    combobox: ?win32.HWND = null,
    auto_preview_checkbox: ?win32.HWND = null,
    random_button: ?win32.HWND = null,
    main_hwnd: ?win32.HWND = null,
    icon_ctrl: ?win32.HWND = null,
    browse_button: ?win32.HWND = null,
    browse_label: ?win32.HWND = null,
    toolbar_brush: ?win32.HBRUSH = null,

    // current state
    current_bank: usize = 0,
    scroll_pos: i32 = 0,
    content_height: i32 = 0,
    ui_state: UIState = .normal,
    buttons_hidden: bool = false,

    // input state
    held_key: ?u32 = null,
    held_nav_key: ?u32 = null,
    nav_repeat_started: bool = false,
    pending_button: ?u16 = null,
    flash_button: ?u16 = null,

    // runtime mode
    runtime_banks: ?scanner.ScanResult = null,
    allocator: std.mem.Allocator = std.heap.page_allocator,

    // cached grid layout
    grid_cache: ui.GridCache = .{},

    // prng
    prng: std.Random.DefaultPrng = undefined,
};

// }}}

var g: AppState = .{};

// sound bank access {{{

fn getBankCount() usize {
    if (sound_banks.runtime_mode) {
        return if (g.runtime_banks) |banks| banks.banks.len else 0;
    }
    return sound_banks.sound_banks.len;
}

fn getBankName(index: usize) [:0]const u8 {
    if (sound_banks.runtime_mode) {
        if (g.runtime_banks) |banks| {
            if (index < banks.banks.len) return banks.banks[index].name;
        }
        return "";
    }
    return sound_banks.sound_banks[index].name;
}

fn getWavCount(bank_index: usize) usize {
    if (sound_banks.runtime_mode) {
        if (g.runtime_banks) |banks| {
            if (bank_index < banks.banks.len) return banks.banks[bank_index].wavs.len;
        }
        return 0;
    }
    return sound_banks.sound_banks[bank_index].wavs.len;
}

fn getWavName(bank_index: usize, wav_index: usize) []const u8 {
    if (sound_banks.runtime_mode) {
        if (g.runtime_banks) |banks| {
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
        if (g.runtime_banks) |banks| {
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

// }}}

// bank change handling {{{

fn applyBankChange(hwnd: win32.HWND, target: usize) void {
    const num_banks = getBankCount();
    if (num_banks == 0 or target >= num_banks) return;

    _ = win32.PlaySoundA(null, null, 0);

    g.current_bank = target;
    g.scroll_pos = 0;

    if (g.combobox) |combo| {
        _ = win32.SendMessageA(combo, win32.CB_SETCURSEL, @intCast(target), 0);
    }

    hideAllButtons();
    _ = win32.SetTimer(hwnd, TIMER_BANK_UPDATE, BANK_UPDATE_DELAY_MS, null);

    if (ui.isAutoPreviewEnabled(g.auto_preview_checkbox)) {
        _ = win32.SetTimer(hwnd, TIMER_AUTO_PREVIEW, AUTO_PREVIEW_DELAY_MS, null);
    }
}

fn hideAllButtons() void {
    if (g.buttons_hidden) return;

    if (g.flash_button) |btn_index| {
        ui.setButtonState(&g.buttons, btn_index, false);
        if (g.main_hwnd) |hwnd| {
            _ = win32.KillTimer(hwnd, TIMER_BUTTON_RELEASE);
        }
        g.flash_button = null;
    }

    ui.hideAllButtons(g.buttons[0..g.num_buttons]);
    g.buttons_hidden = true;
}

fn performBankUpdate(hwnd: win32.HWND) void {
    _ = win32.SendMessageA(hwnd, win32.WM_SETREDRAW, 0, 0);

    // clear flash state before destroying buttons
    if (g.flash_button) |btn_index| {
        ui.setButtonState(&g.buttons, btn_index, false);
        _ = win32.KillTimer(hwnd, TIMER_BUTTON_RELEASE);
        g.flash_button = null;
    }

    ui.createButtonsForBank(hwnd, &g.buttons, &g.num_buttons, g.current_bank, getWavCount, getWavName);
    layoutControls(hwnd);

    g.buttons_hidden = false;

    _ = win32.SendMessageA(hwnd, win32.WM_SETREDRAW, 1, 0);
    var rect: win32.RECT = undefined;
    _ = win32.GetClientRect(hwnd, &rect);
    rect.top = ui.TOOLBAR_HEIGHT;
    _ = win32.RedrawWindow(hwnd, &rect, null, win32.RDW_ERASE | win32.RDW_INVALIDATE | win32.RDW_ALLCHILDREN);
}

// }}}

// input handling {{{

fn releaseHeldKey() void {
    if (g.held_key) |vk| {
        if (input.keyToSoundIndex(vk)) |index| {
            ui.setButtonState(&g.buttons, index, false);
        }
        g.held_key = null;
    }
}

fn applyNavKey(hwnd: win32.HWND, vk: u32) void {
    if (input.getNavTarget(vk, g.current_bank, getBankCount())) |target| {
        applyBankChange(hwnd, target);
    }
}

fn handleKeyDown(hwnd: win32.HWND, vk: u32) bool {
    if (input.isNavKey(vk)) {
        if (g.held_nav_key != null) return true;

        g.held_nav_key = vk;
        g.nav_repeat_started = false;
        applyNavKey(hwnd, vk);
        _ = win32.SetTimer(hwnd, TIMER_NAV_REPEAT, NAV_INITIAL_DELAY_MS, null);
        return true;
    }

    if (g.held_key == null) {
        if (input.keyToSoundIndex(vk)) |index| {
            g.held_key = vk;
            ui.setButtonState(&g.buttons, index, true);
            return true;
        }
    }
    return false;
}

fn handleKeyUp(hwnd: win32.HWND, vk: u32) bool {
    if (g.held_nav_key == vk) {
        g.held_nav_key = null;
        g.nav_repeat_started = false;
        _ = win32.KillTimer(hwnd, TIMER_NAV_REPEAT);

        // only auto-preview if we actually have multiple banks to navigate
        if (getBankCount() > 1 and ui.isAutoPreviewEnabled(g.auto_preview_checkbox)) {
            _ = win32.SetTimer(hwnd, TIMER_AUTO_PREVIEW, AUTO_PREVIEW_DELAY_MS, null);
        }
        return true;
    }

    if (g.held_key == vk) {
        if (input.keyToSoundIndex(vk)) |index| {
            ui.setButtonState(&g.buttons, index, false);
            playSound(index);
        }
        g.held_key = null;
        return true;
    }
    return false;
}

// }}}

// layout {{{

fn layoutControls(hwnd: win32.HWND) void {
    if (g.ui_state == .browse_needed) {
        browse.layoutBrowseUI(hwnd, g.browse_label, g.browse_button);
        return;
    }

    ui.layoutButtons(hwnd, g.buttons[0..g.num_buttons], g.current_bank, &g.scroll_pos, &g.content_height, &g.grid_cache, getWavName);
}

// }}}

// playback {{{

fn playSound(index: u16) void {
    if (index < getWavCount(g.current_bank)) {
        playWav(g.current_bank, index);
        _ = win32.SetFocus(g.main_hwnd);
    }
}

fn playRandomSound() void {
    const wav_count = getWavCount(g.current_bank);
    if (wav_count == 0) return;

    const random_index: u16 = @intCast(g.prng.random().uintLessThan(usize, wav_count));

    if (g.flash_button) |btn_index| {
        ui.setButtonState(&g.buttons, btn_index, false);
    }

    ui.setButtonState(&g.buttons, random_index, true);
    _ = win32.SetTimer(g.main_hwnd, TIMER_BUTTON_RELEASE, FLASH_DURATION_MS, null);
    g.flash_button = random_index;

    playSound(random_index);
}

fn handleBankChange(hwnd: win32.HWND) void {
    if (g.combobox) |combo| {
        const sel = win32.SendMessageA(combo, win32.CB_GETCURSEL, 0, 0);
        if (sel >= 0 and @as(usize, @intCast(sel)) < getBankCount()) {
            _ = win32.SendMessageA(hwnd, win32.WM_SETREDRAW, 0, 0);

            g.current_bank = @intCast(sel);
            g.scroll_pos = 0;

            // clear flash state before destroying buttons
            if (g.flash_button) |btn_index| {
                ui.setButtonState(&g.buttons, btn_index, false);
                _ = win32.KillTimer(hwnd, TIMER_BUTTON_RELEASE);
                g.flash_button = null;
            }

            ui.createButtonsForBank(hwnd, &g.buttons, &g.num_buttons, g.current_bank, getWavCount, getWavName);
            layoutControls(hwnd);

            _ = win32.SendMessageA(hwnd, win32.WM_SETREDRAW, 1, 0);
            _ = win32.RedrawWindow(hwnd, null, null, win32.RDW_ERASE | win32.RDW_INVALIDATE | win32.RDW_ALLCHILDREN);
        }
    }
}

fn handleRandomClick(hwnd: win32.HWND) void {
    playRandomSound();
    _ = win32.SetFocus(hwnd);
}

// }}}

// browse handling {{{

fn handleBrowseClick(hwnd: win32.HWND) void {
    switch (browse.handleBrowse(hwnd, g.allocator)) {
        .success => |result| {
            if (g.runtime_banks) |*old_banks| {
                old_banks.deinit();
            }
            g.runtime_banks = result;
            transitionToNormalUI(hwnd);
        },
        .cancelled => {},
        .invalid_folder => {
            _ = win32.MessageBoxA(
                hwnd,
                "Could not find DATA\\User\\Speech in the selected folder or parent directories.\n\nPlease select your Worms Armageddon installation directory.",
                "Invalid folder",
                win32.MB_OK | win32.MB_ICONINFORMATION,
            );
        },
    }
}

fn transitionToNormalUI(hwnd: win32.HWND) void {
    if (g.browse_label) |label| {
        _ = win32.DestroyWindow(label);
        g.browse_label = null;
    }
    if (g.browse_button) |btn| {
        _ = win32.DestroyWindow(btn);
        g.browse_button = null;
    }

    g.ui_state = .normal;
    ui.createToolbar(hwnd, getBankCount(), getBankName, &g.icon_ctrl, &g.random_button, &g.combobox, &g.auto_preview_checkbox);
    ui.createButtonsForBank(hwnd, &g.buttons, &g.num_buttons, 0, getWavCount, getWavName);
    layoutControls(hwnd);
    _ = win32.RedrawWindow(hwnd, null, null, win32.RDW_ERASE | win32.RDW_INVALIDATE | win32.RDW_ALLCHILDREN);
}

// }}}

// window proc {{{

fn wndProc(hwnd: win32.HWND, msg: u32, wParam: win32.WPARAM, lParam: win32.LPARAM) callconv(.c) win32.LRESULT {
    switch (msg) {
        win32.WM_CREATE => {
            g.main_hwnd = hwnd;
            g.toolbar_brush = win32.CreateSolidBrush(drawing.COLOR_TOOLBAR);
            ui.createMenuBar(hwnd);
            if (g.ui_state == .browse_needed) {
                browse.createBrowseUI(hwnd, &g.browse_label, &g.browse_button);
            } else {
                ui.createToolbar(hwnd, getBankCount(), getBankName, &g.icon_ctrl, &g.random_button, &g.combobox, &g.auto_preview_checkbox);
                ui.createButtonsForBank(hwnd, &g.buttons, &g.num_buttons, 0, getWavCount, getWavName);
            }
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
            mmi.ptMinTrackSize.x = ui.MIN_WINDOW_WIDTH;
            mmi.ptMinTrackSize.y = ui.MIN_WINDOW_HEIGHT;
            return 0;
        },
        win32.WM_COMMAND => {
            const notification = @as(u16, @truncate(wParam >> 16));
            const control_id = @as(u16, @truncate(wParam));
            if (notification == 0) {
                if (control_id == ui.IDM_EXIT or control_id == ui.IDM_CLOSE) {
                    win32.PostQuitMessage(0);
                    return 0;
                } else if (control_id == ui.IDM_ABOUT) {
                    _ = win32.MessageBoxA(hwnd, "wormtalker\n\nsoundboard for worms armageddon\n\nhotkeys:\n  up/down - change bank\n  1-9, 0 - play sound 1-10\n  qwerty - play sound 11+", "about wormtalker", win32.MB_OK | win32.MB_ICONINFORMATION);
                    return 0;
                }
            }
            if (control_id == browse.ID_BROWSE and notification == win32.BN_CLICKED) {
                handleBrowseClick(hwnd);
                return 0;
            } else if (control_id == ui.ID_RANDOM and notification == win32.BN_CLICKED) {
                handleRandomClick(hwnd);
                return 0;
            } else if (control_id == ui.ID_AUTO_PREVIEW and notification == win32.BN_CLICKED) {
                scanner.saveAutoPreview(ui.isAutoPreviewEnabled(g.auto_preview_checkbox));
                _ = win32.SetFocus(hwnd);
                return 0;
            } else if (control_id == ui.ID_COMBOBOX and notification == win32.CBN_SELCHANGE) {
                handleBankChange(hwnd);
            } else if (control_id == ui.ID_COMBOBOX and notification == win32.CBN_CLOSEUP) {
                var pt: win32.POINT = undefined;
                if (win32.GetCursorPos(&pt) != 0) {
                    _ = win32.ScreenToClient(hwnd, &pt);
                    if (win32.ChildWindowFromPoint(hwnd, pt)) |child| {
                        const child_id = win32.GetDlgCtrlID(child);
                        if (child_id >= 0 and child_id < ui.MAX_BUTTONS) {
                            const btn_index: u16 = @intCast(child_id);
                            ui.setButtonState(&g.buttons, btn_index, true);
                            g.pending_button = btn_index;
                            _ = win32.SetCapture(hwnd);
                        }
                    }
                }
                _ = win32.SetFocus(hwnd);
            } else if (notification == win32.BN_CLICKED and control_id < ui.MAX_BUTTONS) {
                playSound(control_id);
            }
            return 0;
        },
        win32.WM_VSCROLL => {
            if (ui.handleScroll(hwnd, wParam, &g.scroll_pos)) {
                layoutControls(hwnd);
            }
            return 0;
        },
        win32.WM_MOUSEWHEEL => {
            const hi_word: u16 = @truncate(@as(u64, @bitCast(wParam)) >> 16);
            const delta: i16 = @bitCast(hi_word);
            const scroll_amount: i32 = if (delta > 0) -ui.SCROLL_WHEEL_AMOUNT else ui.SCROLL_WHEEL_AMOUNT;
            if (ui.scrollContent(hwnd, scroll_amount, &g.scroll_pos)) {
                layoutControls(hwnd);
            }
            return 0;
        },
        win32.WM_LBUTTONUP => {
            if (g.pending_button) |btn_index| {
                _ = win32.ReleaseCapture();
                ui.setButtonState(&g.buttons, btn_index, false);
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
                g.pending_button = null;
                return 0;
            }
            return win32.DefWindowProcA(hwnd, msg, wParam, lParam);
        },
        win32.WM_KILLFOCUS => {
            releaseHeldKey();
            if (g.held_nav_key != null) {
                g.held_nav_key = null;
                g.nav_repeat_started = false;
                _ = win32.KillTimer(hwnd, TIMER_NAV_REPEAT);
            }
            _ = win32.KillTimer(hwnd, TIMER_AUTO_PREVIEW);
            if (g.pending_button) |btn_index| {
                _ = win32.ReleaseCapture();
                ui.setButtonState(&g.buttons, btn_index, false);
                g.pending_button = null;
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
                if (g.flash_button) |btn_index| {
                    ui.setButtonState(&g.buttons, btn_index, false);
                    g.flash_button = null;
                }
            } else if (wParam == TIMER_NAV_REPEAT) {
                if (g.held_nav_key) |vk| {
                    applyNavKey(hwnd, vk);
                    if (!g.nav_repeat_started) {
                        g.nav_repeat_started = true;
                        _ = win32.SetTimer(hwnd, TIMER_NAV_REPEAT, NAV_REPEAT_MS, null);
                    }
                } else {
                    _ = win32.KillTimer(hwnd, TIMER_NAV_REPEAT);
                }
            } else if (wParam == TIMER_AUTO_PREVIEW) {
                _ = win32.KillTimer(hwnd, TIMER_AUTO_PREVIEW);
                if (ui.isAutoPreviewEnabled(g.auto_preview_checkbox)) {
                    playRandomSound();
                }
            } else if (wParam == TIMER_BANK_UPDATE) {
                _ = win32.KillTimer(hwnd, TIMER_BANK_UPDATE);
                performBankUpdate(hwnd);
            }
            return 0;
        },
        win32.WM_ERASEBKGND => {
            const hdc: win32.HDC = @ptrFromInt(@as(usize, @truncate(wParam)));
            var rect: win32.RECT = undefined;
            _ = win32.GetClientRect(hwnd, &rect);
            if (g.toolbar_brush) |brush| {
                _ = win32.FillRect(hdc, &rect, brush);
            }
            return 1;
        },
        win32.WM_MEASUREITEM => {
            const mis: *win32.MEASUREITEMSTRUCT = @ptrFromInt(@as(usize, @bitCast(lParam)));
            if (mis.CtlType == win32.ODT_MENU) {
                mis.itemWidth = ui.MENU_ITEM_WIDTH;
                mis.itemHeight = @intCast(win32.GetSystemMetrics(win32.SM_CYMENU));
                return 1;
            }
            return win32.DefWindowProcA(hwnd, msg, wParam, lParam);
        },
        win32.WM_DRAWITEM => {
            const dis: *win32.DRAWITEMSTRUCT = @ptrFromInt(@as(usize, @bitCast(lParam)));
            if (dis.CtlType == win32.ODT_MENU) {
                _ = win32.SetBkMode(dis.hDC, win32.TRANSPARENT);
                _ = win32.SetTextColor(dis.hDC, drawing.COLOR_TEXT);
                const title = "wormtalker v1.2 by shmup";
                var text_rect = dis.rcItem;
                text_rect.left += 6;
                _ = win32.DrawTextA(dis.hDC, title, @intCast(title.len), &text_rect, win32.DT_VCENTER | win32.DT_SINGLELINE);
                return 1;
            }
            drawing.drawButton(dis);
            return 1;
        },
        win32.WM_CTLCOLORSTATIC => {
            const control: win32.HWND = @ptrFromInt(@as(usize, @bitCast(lParam)));
            const hdc: win32.HDC = @ptrFromInt(@as(usize, @truncate(wParam)));

            // auto-preview checkbox uses toolbar brush
            if (g.auto_preview_checkbox != null and control == g.auto_preview_checkbox.?) {
                _ = win32.SetBkMode(hdc, win32.TRANSPARENT);
                if (g.toolbar_brush) |brush| {
                    return @bitCast(@intFromPtr(brush));
                }
            }

            // browse label uses same brush as toolbar
            if (g.browse_label != null and control == g.browse_label.?) {
                _ = win32.SetBkMode(hdc, win32.TRANSPARENT);
                if (g.toolbar_brush) |brush| {
                    return @bitCast(@intFromPtr(brush));
                }
            }

            return win32.DefWindowProcA(hwnd, msg, wParam, lParam);
        },
        win32.WM_NCHITTEST => {
            var mbi = win32.MENUBARINFO{};
            if (win32.GetMenuBarInfo(hwnd, win32.OBJID_MENU, 0, &mbi) != 0) {
                var pt: win32.POINT = undefined;
                if (win32.GetCursorPos(&pt) != 0) {
                    if (pt.y >= mbi.rcBar.top and pt.y < mbi.rcBar.bottom) {
                        const menu_right_area = mbi.rcBar.right - ui.MENU_RIGHT_MARGIN;
                        if (pt.x < menu_right_area) {
                            return win32.HTCAPTION;
                        }
                    }
                }
            }
            return win32.DefWindowProcA(hwnd, msg, wParam, lParam);
        },
        win32.WM_DESTROY => {
            if (g.toolbar_brush) |brush| {
                _ = win32.DeleteObject(@ptrCast(brush));
                g.toolbar_brush = null;
            }
            win32.PostQuitMessage(0);
            return 0;
        },
        else => return win32.DefWindowProcA(hwnd, msg, wParam, lParam),
    }
}

// }}}

// main {{{

fn parseArgs() bool {
    const cmd_line = win32.GetCommandLineA();
    if (cmd_line == null) return false;

    const cmd = std.mem.span(cmd_line.?);

    // skip program name (may be quoted)
    var rest = cmd;
    if (rest.len > 0 and rest[0] == '"') {
        // quoted program name - find closing quote
        if (std.mem.indexOfScalar(u8, rest[1..], '"')) |end| {
            rest = rest[end + 2 ..];
        }
    } else {
        // unquoted - skip to first space
        if (std.mem.indexOfScalar(u8, rest, ' ')) |end| {
            rest = rest[end..];
        } else {
            return false; // no args
        }
    }

    // check each space-separated token
    var iter = std.mem.tokenizeScalar(u8, rest, ' ');
    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "-b") or std.mem.eql(u8, arg, "--browse")) {
            return true;
        }
    }
    return false;
}

fn scanPath(path: []const u8) ?scanner.ScanResult {
    if (sound_banks.full_mode) {
        return scanner.scanFullDirectory(g.allocator, path) catch null;
    } else {
        return scanner.scanSpeechDirectory(g.allocator, path) catch null;
    }
}

fn initRuntime(force_browse: bool) void {
    if (!sound_banks.runtime_mode) return;

    if (force_browse) {
        g.ui_state = .browse_needed;
        return;
    }

    var path_buf: [win32.MAX_PATH]u8 = undefined;

    if (scanner.getSavedPath(&path_buf)) |path| {
        if (scanPath(path)) |result| {
            g.runtime_banks = result;
            g.ui_state = .normal;
            return;
        }
    }

    if (scanner.getWormsPath(&path_buf)) |path| {
        if (scanPath(path)) |result| {
            g.runtime_banks = result;
            g.ui_state = .normal;
            return;
        }
    }

    g.ui_state = .browse_needed;
}

pub fn main() void {
    const seed: u64 = @bitCast(std.time.milliTimestamp());
    g.prng = std.Random.DefaultPrng.init(seed);

    const force_browse = parseArgs();
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

    const window_style = win32.WS_POPUP | win32.WS_THICKFRAME | win32.WS_MINIMIZEBOX | win32.WS_MAXIMIZEBOX | win32.WS_VISIBLE | win32.WS_VSCROLL | win32.WS_CLIPCHILDREN;
    const hwnd = win32.CreateWindowExA(
        win32.WS_EX_APPWINDOW,
        "WormboardClass",
        "wormtalker",
        window_style,
        100,
        100,
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
