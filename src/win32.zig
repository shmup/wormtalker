const std = @import("std");
const windows = std.os.windows;

// win32 types
pub const HWND = windows.HWND;
pub const HINSTANCE = windows.HINSTANCE;
pub const LPARAM = windows.LPARAM;
pub const WPARAM = windows.WPARAM;
pub const LRESULT = windows.LRESULT;
pub const BOOL = windows.BOOL;
pub const HBRUSH = *opaque {};
pub const HICON = *opaque {};
pub const HCURSOR = *opaque {};
pub const HDC = *opaque {};
pub const HMENU = *opaque {};

pub const RECT = extern struct {
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
};

pub const PAINTSTRUCT = extern struct {
    hdc: HDC,
    fErase: BOOL,
    rcPaint: RECT,
    fRestore: BOOL,
    fIncUpdate: BOOL,
    rgbReserved: [32]u8,
};

pub const POINT = extern struct {
    x: i32,
    y: i32,
};

pub const MSG = extern struct {
    hwnd: ?HWND,
    message: u32,
    wParam: WPARAM,
    lParam: LPARAM,
    time: u32,
    pt: POINT,
};

pub const WNDCLASSEXA = extern struct {
    cbSize: u32 = @sizeOf(WNDCLASSEXA),
    style: u32 = 0,
    lpfnWndProc: *const fn (HWND, u32, WPARAM, LPARAM) callconv(.c) LRESULT,
    cbClsExtra: i32 = 0,
    cbWndExtra: i32 = 0,
    hInstance: ?HINSTANCE = null,
    hIcon: ?HICON = null,
    hCursor: ?HCURSOR = null,
    hbrBackground: ?HBRUSH = null,
    lpszMenuName: ?[*:0]const u8 = null,
    lpszClassName: [*:0]const u8,
    hIconSm: ?HICON = null,
};

pub const CREATESTRUCTA = extern struct {
    lpCreateParams: ?*anyopaque,
    hInstance: ?HINSTANCE,
    hMenu: ?HMENU,
    hwndParent: ?HWND,
    cy: i32,
    cx: i32,
    y: i32,
    x: i32,
    style: i32,
    lpszName: ?[*:0]const u8,
    lpszClass: ?[*:0]const u8,
    dwExStyle: u32,
};

pub const SCROLLINFO = extern struct {
    cbSize: u32 = @sizeOf(SCROLLINFO),
    fMask: u32 = 0,
    nMin: i32 = 0,
    nMax: i32 = 0,
    nPage: u32 = 0,
    nPos: i32 = 0,
    nTrackPos: i32 = 0,
};

pub const MINMAXINFO = extern struct {
    ptReserved: POINT,
    ptMaxSize: POINT,
    ptMaxPosition: POINT,
    ptMinTrackSize: POINT,
    ptMaxTrackSize: POINT,
};

// window styles
pub const WS_OVERLAPPEDWINDOW: u32 = 0x00CF0000;
pub const WS_VISIBLE: u32 = 0x10000000;
pub const WS_CHILD: u32 = 0x40000000;
pub const WS_VSCROLL: u32 = 0x00200000;
pub const WS_CLIPCHILDREN: u32 = 0x02000000;
pub const BS_PUSHBUTTON: u32 = 0x00000000;
pub const CW_USEDEFAULT: i32 = @bitCast(@as(u32, 0x80000000));

// window messages
pub const WM_DESTROY: u32 = 0x0002;
pub const WM_SIZE: u32 = 0x0005;
pub const WM_SETREDRAW: u32 = 0x000B;
pub const WM_PAINT: u32 = 0x000F;
pub const WM_COMMAND: u32 = 0x0111;
pub const WM_VSCROLL: u32 = 0x0115;
pub const WM_MOUSEWHEEL: u32 = 0x020A;
pub const WM_CREATE: u32 = 0x0001;
pub const WM_GETMINMAXINFO: u32 = 0x0024;

// RedrawWindow flags
pub const RDW_INVALIDATE: u32 = 0x0001;
pub const RDW_ERASE: u32 = 0x0004;
pub const RDW_ALLCHILDREN: u32 = 0x0080;

// scroll bar
pub const SB_VERT: i32 = 1;
pub const SIF_RANGE: u32 = 0x0001;
pub const SIF_PAGE: u32 = 0x0002;
pub const SIF_POS: u32 = 0x0004;
pub const SIF_ALL: u32 = SIF_RANGE | SIF_PAGE | SIF_POS;
pub const SB_LINEUP: u32 = 0;
pub const SB_LINEDOWN: u32 = 1;
pub const SB_PAGEUP: u32 = 2;
pub const SB_PAGEDOWN: u32 = 3;
pub const SB_THUMBTRACK: u32 = 5;

// combobox
pub const CBS_DROPDOWNLIST: u32 = 0x0003;
pub const CBS_HASSTRINGS: u32 = 0x0200;
pub const CB_ADDSTRING: u32 = 0x0143;
pub const CB_SETCURSEL: u32 = 0x014E;
pub const CB_GETCURSEL: u32 = 0x0147;
pub const CBN_SELCHANGE: u16 = 1;

// button notifications
pub const BN_CLICKED: u16 = 0;

// sound flags
pub const SND_MEMORY: u32 = 0x0004;
pub const SND_ASYNC: u32 = 0x0001;
pub const SND_NOSTOP: u32 = 0x0010;

// color
pub const COLOR_BTNFACE: usize = 15;

// cursor
pub const IDC_ARROW: usize = 32512;

// win32 functions
pub extern "user32" fn RegisterClassExA(*const WNDCLASSEXA) callconv(.c) u16;
pub extern "user32" fn CreateWindowExA(
    dwExStyle: u32,
    lpClassName: [*:0]const u8,
    lpWindowName: [*:0]const u8,
    dwStyle: u32,
    x: i32,
    y: i32,
    nWidth: i32,
    nHeight: i32,
    hWndParent: ?HWND,
    hMenu: ?HMENU,
    hInstance: ?HINSTANCE,
    lpParam: ?*anyopaque,
) callconv(.c) ?HWND;
pub extern "user32" fn DefWindowProcA(HWND, u32, WPARAM, LPARAM) callconv(.c) LRESULT;
pub extern "user32" fn GetMessageA(*MSG, ?HWND, u32, u32) callconv(.c) BOOL;
pub extern "user32" fn TranslateMessage(*const MSG) callconv(.c) BOOL;
pub extern "user32" fn DispatchMessageA(*const MSG) callconv(.c) LRESULT;
pub extern "user32" fn PostQuitMessage(i32) callconv(.c) void;
pub extern "user32" fn BeginPaint(HWND, *PAINTSTRUCT) callconv(.c) ?HDC;
pub extern "user32" fn EndPaint(HWND, *const PAINTSTRUCT) callconv(.c) BOOL;
pub extern "user32" fn GetClientRect(HWND, *RECT) callconv(.c) BOOL;
pub extern "user32" fn MoveWindow(HWND, i32, i32, i32, i32, BOOL) callconv(.c) BOOL;
pub extern "user32" fn SetScrollInfo(HWND, i32, *const SCROLLINFO, BOOL) callconv(.c) i32;
pub extern "user32" fn GetScrollInfo(HWND, i32, *SCROLLINFO) callconv(.c) BOOL;
pub extern "user32" fn ScrollWindow(HWND, i32, i32, ?*const RECT, ?*const RECT) callconv(.c) BOOL;
pub extern "user32" fn LoadCursorA(?HINSTANCE, usize) callconv(.c) ?HCURSOR;
pub extern "user32" fn ShowWindow(HWND, i32) callconv(.c) BOOL;
pub extern "user32" fn UpdateWindow(HWND) callconv(.c) BOOL;
pub extern "user32" fn DestroyWindow(HWND) callconv(.c) BOOL;
pub extern "user32" fn SendMessageA(HWND, u32, WPARAM, LPARAM) callconv(.c) LRESULT;
pub extern "user32" fn InvalidateRect(?HWND, ?*const RECT, BOOL) callconv(.c) BOOL;
pub extern "kernel32" fn GetModuleHandleA(?[*:0]const u8) callconv(.c) ?HINSTANCE;
pub extern "gdi32" fn GetStockObject(i32) callconv(.c) ?HBRUSH;
pub extern "winmm" fn PlaySoundA(?[*]const u8, ?HINSTANCE, u32) callconv(.c) BOOL;
pub extern "user32" fn RedrawWindow(?HWND, ?*const RECT, ?*anyopaque, u32) callconv(.c) BOOL;
