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
pub const WS_POPUP: u32 = 0x80000000;
pub const WS_THICKFRAME: u32 = 0x00040000;
pub const WS_MINIMIZEBOX: u32 = 0x00020000;
pub const WS_MAXIMIZEBOX: u32 = 0x00010000;
pub const WS_VISIBLE: u32 = 0x10000000;
pub const WS_CHILD: u32 = 0x40000000;
pub const WS_VSCROLL: u32 = 0x00200000;
pub const WS_CLIPCHILDREN: u32 = 0x02000000;
pub const BS_PUSHBUTTON: u32 = 0x00000000;
pub const SS_CENTER: u32 = 0x00000001;
pub const SS_ICON: u32 = 0x00000003;
pub const STM_SETICON: u32 = 0x0170;
pub const CW_USEDEFAULT: i32 = @bitCast(@as(u32, 0x80000000));

// window messages
pub const WM_DESTROY: u32 = 0x0002;
pub const WM_SIZE: u32 = 0x0005;
pub const WM_SETREDRAW: u32 = 0x000B;
pub const WM_PAINT: u32 = 0x000F;
pub const WM_ERASEBKGND: u32 = 0x0014;
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
pub const CBN_CLOSEUP: u16 = 8;

// button notifications
pub const BN_CLICKED: u16 = 0;
pub const BM_SETSTATE: u32 = 0x00F3;
pub const BM_GETCHECK: u32 = 0x00F0;
pub const BM_SETCHECK: u32 = 0x00F1;
pub const BS_AUTOCHECKBOX: u32 = 0x00000003;
pub const BST_UNCHECKED: u32 = 0x0000;
pub const BST_CHECKED: u32 = 0x0001;

// menu flags
pub const MF_STRING: u32 = 0x00000000;
pub const MF_POPUP: u32 = 0x00000010;
pub const MF_DISABLED: u32 = 0x00000002;
pub const MF_GRAYED: u32 = 0x00000001;
pub const MF_RIGHTJUSTIFY: u32 = 0x00004000;
pub const MF_OWNERDRAW: u32 = 0x00000100;

// owner-drawn menu structs
pub const MEASUREITEMSTRUCT = extern struct {
    CtlType: u32,
    CtlID: u32,
    itemID: u32,
    itemWidth: u32,
    itemHeight: u32,
    itemData: usize,
};

pub const ODT_MENU: u32 = 1;
pub const WM_MEASUREITEM: u32 = 0x002C;

// static control color
pub const WM_CTLCOLORSTATIC: u32 = 0x0138;

// messagebox
pub const MB_OK: u32 = 0x00000000;
pub const MB_ICONINFORMATION: u32 = 0x00000040;

// keyboard
pub const WM_KEYDOWN: u32 = 0x0100;
pub const WM_KEYUP: u32 = 0x0101;
pub const WM_KILLFOCUS: u32 = 0x0008;

// mouse
pub const WM_LBUTTONUP: u32 = 0x0202;

// ui state (hide focus rectangles)
pub const WM_UPDATEUISTATE: u32 = 0x0128;
pub const UIS_SET: u32 = 1;
pub const UISF_HIDEFOCUS: u32 = 0x1;

// timer
pub const WM_TIMER: u32 = 0x0113;
pub const VK_PRIOR: u32 = 0x21; // page up
pub const VK_NEXT: u32 = 0x22; // page down
pub const VK_END: u32 = 0x23;
pub const VK_HOME: u32 = 0x24;
pub const VK_UP: u32 = 0x26;
pub const VK_DOWN: u32 = 0x28;

// sound flags
pub const SND_MEMORY: u32 = 0x0004;
pub const SND_ASYNC: u32 = 0x0001;
pub const SND_NOSTOP: u32 = 0x0010;
pub const SND_FILENAME: u32 = 0x00020000;

// color
pub const COLOR_BTNFACE: usize = 15;

// drawing
pub const DRAWITEMSTRUCT = extern struct {
    CtlType: u32,
    CtlID: u32,
    itemID: u32,
    itemAction: u32,
    itemState: u32,
    hwndItem: ?*anyopaque, // HWND for controls, HMENU for menus
    hDC: HDC,
    rcItem: RECT,
    itemData: usize,
};

pub const ODS_SELECTED: u32 = 0x0001;
pub const ODS_FOCUS: u32 = 0x0010;
pub const WM_DRAWITEM: u32 = 0x002B;
pub const BS_OWNERDRAW: u32 = 0x0000000B;
pub const DT_CENTER: u32 = 0x00000001;
pub const DT_VCENTER: u32 = 0x00000004;
pub const DT_SINGLELINE: u32 = 0x00000020;

pub extern "gdi32" fn SetBkColor(hdc: HDC, color: u32) callconv(.c) u32;
pub extern "gdi32" fn SetBkMode(hdc: HDC, mode: i32) callconv(.c) i32;
pub extern "gdi32" fn SetTextColor(hdc: HDC, color: u32) callconv(.c) u32;

pub const TRANSPARENT: i32 = 1;
pub extern "gdi32" fn CreateSolidBrush(color: u32) callconv(.c) ?HBRUSH;
pub extern "gdi32" fn DeleteObject(ho: ?*anyopaque) callconv(.c) BOOL;
pub extern "gdi32" fn FillRect(hdc: HDC, lprc: *const RECT, hbr: HBRUSH) callconv(.c) i32;
pub extern "gdi32" fn SelectObject(hdc: HDC, h: ?*anyopaque) callconv(.c) ?*anyopaque;
pub extern "user32" fn DrawTextA(hdc: HDC, lpchText: [*:0]const u8, cchText: i32, lprc: *RECT, format: u32) callconv(.c) i32;
pub extern "user32" fn GetWindowTextA(hwnd: HWND, lpString: [*]u8, nMaxCount: i32) callconv(.c) i32;
pub extern "user32" fn DrawEdge(hdc: HDC, qrc: *RECT, edge: u32, grfFlags: u32) callconv(.c) BOOL;

pub const EDGE_RAISED: u32 = 0x0005;
pub const EDGE_SUNKEN: u32 = 0x000A;
pub const BF_RECT: u32 = 0x000F;
pub const BF_ADJUST: u32 = 0x2000;

// cursor
pub const IDC_ARROW: usize = 32512;

// extended window styles
pub const WS_EX_APPWINDOW: u32 = 0x00040000;

// non-client hit test
pub const WM_NCHITTEST: u32 = 0x0084;
pub const HTCAPTION: LRESULT = 2;

// menu bar info
pub const MENUBARINFO = extern struct {
    cbSize: u32 = @sizeOf(MENUBARINFO),
    rcBar: RECT = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
    hMenu: ?HMENU = null,
    hwndMenu: ?HWND = null,
    fBarFocused: u32 = 0,
    fFocused: u32 = 0,
};

pub extern "user32" fn GetMenuBarInfo(hwnd: HWND, idObject: i32, idItem: i32, pmbi: *MENUBARINFO) callconv(.c) BOOL;
pub const OBJID_MENU: i32 = -3;

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
pub const SW_HIDE: i32 = 0;
pub extern "user32" fn UpdateWindow(HWND) callconv(.c) BOOL;
pub extern "user32" fn DestroyWindow(HWND) callconv(.c) BOOL;
pub extern "user32" fn SendMessageA(HWND, u32, WPARAM, LPARAM) callconv(.c) LRESULT;
pub extern "user32" fn InvalidateRect(?HWND, ?*const RECT, BOOL) callconv(.c) BOOL;
pub extern "kernel32" fn GetModuleHandleA(?[*:0]const u8) callconv(.c) ?HINSTANCE;
pub extern "kernel32" fn GetCommandLineA() callconv(.c) ?[*:0]const u8;
pub extern "gdi32" fn GetStockObject(i32) callconv(.c) ?HBRUSH;
pub extern "winmm" fn PlaySoundA(?[*]const u8, ?HINSTANCE, u32) callconv(.c) BOOL;
pub extern "user32" fn RedrawWindow(?HWND, ?*const RECT, ?*anyopaque, u32) callconv(.c) BOOL;
pub extern "user32" fn CreateMenu() callconv(.c) ?HMENU;
pub extern "user32" fn CreatePopupMenu() callconv(.c) ?HMENU;
pub extern "user32" fn AppendMenuA(HMENU, u32, usize, ?[*:0]const u8) callconv(.c) BOOL;
pub extern "user32" fn SetMenu(HWND, ?HMENU) callconv(.c) BOOL;
pub extern "user32" fn MessageBoxA(?HWND, [*:0]const u8, [*:0]const u8, u32) callconv(.c) i32;
pub extern "user32" fn SetFocus(?HWND) callconv(.c) ?HWND;
pub extern "user32" fn SetTimer(?HWND, usize, u32, ?*anyopaque) callconv(.c) usize;
pub extern "user32" fn KillTimer(?HWND, usize) callconv(.c) BOOL;
pub extern "user32" fn GetCursorPos(*POINT) callconv(.c) BOOL;
pub extern "user32" fn ScreenToClient(HWND, *POINT) callconv(.c) BOOL;
pub extern "user32" fn ChildWindowFromPoint(HWND, POINT) callconv(.c) ?HWND;
pub extern "user32" fn GetDlgCtrlID(HWND) callconv(.c) i32;
pub extern "user32" fn SetCapture(HWND) callconv(.c) ?HWND;
pub extern "user32" fn ReleaseCapture() callconv(.c) BOOL;
pub extern "user32" fn LoadIconA(?HINSTANCE, usize) callconv(.c) ?HICON;
pub extern "user32" fn LoadImageA(?HINSTANCE, usize, u32, i32, i32, u32) callconv(.c) ?*anyopaque;
pub extern "user32" fn GetSystemMetrics(nIndex: i32) callconv(.c) i32;

// system metrics
pub const SM_CXVSCROLL: i32 = 2;
pub const SM_CYMENU: i32 = 15;

// icon resource id
pub const IDI_APP: usize = 1;

// LoadImage types and flags
pub const IMAGE_ICON: u32 = 1;
pub const LR_DEFAULTCOLOR: u32 = 0x00000000;

// registry types and constants
pub const HKEY = *opaque {};
pub const LSTATUS = i32;
pub const REGSAM = u32;

pub const HKEY_CURRENT_USER: HKEY = @ptrFromInt(0x80000001);
pub const KEY_READ: REGSAM = 0x20019;
pub const KEY_WRITE: REGSAM = 0x20006;
pub const KEY_ALL_ACCESS: REGSAM = 0xF003F;
pub const REG_SZ: u32 = 1;
pub const REG_DWORD: u32 = 4;
pub const ERROR_SUCCESS: LSTATUS = 0;

// registry functions
pub extern "advapi32" fn RegOpenKeyExA(
    hKey: HKEY,
    lpSubKey: [*:0]const u8,
    ulOptions: u32,
    samDesired: REGSAM,
    phkResult: *HKEY,
) callconv(.c) LSTATUS;

pub extern "advapi32" fn RegQueryValueExA(
    hKey: HKEY,
    lpValueName: [*:0]const u8,
    lpReserved: ?*u32,
    lpType: ?*u32,
    lpData: ?[*]u8,
    lpcbData: ?*u32,
) callconv(.c) LSTATUS;

pub extern "advapi32" fn RegCloseKey(hKey: HKEY) callconv(.c) LSTATUS;

pub extern "advapi32" fn RegCreateKeyExA(
    hKey: HKEY,
    lpSubKey: [*:0]const u8,
    Reserved: u32,
    lpClass: ?[*:0]const u8,
    dwOptions: u32,
    samDesired: REGSAM,
    lpSecurityAttributes: ?*anyopaque,
    phkResult: *HKEY,
    lpdwDisposition: ?*u32,
) callconv(.c) LSTATUS;

pub extern "advapi32" fn RegSetValueExA(
    hKey: HKEY,
    lpValueName: [*:0]const u8,
    Reserved: u32,
    dwType: u32,
    lpData: [*]const u8,
    cbData: u32,
) callconv(.c) LSTATUS;

// shell types for folder browser
pub const LPITEMIDLIST = ?*anyopaque;
pub const MAX_PATH: usize = 260;

pub const BROWSEINFOA = extern struct {
    hwndOwner: ?HWND = null,
    pidlRoot: LPITEMIDLIST = null,
    pszDisplayName: ?[*]u8 = null,
    lpszTitle: ?[*:0]const u8 = null,
    ulFlags: u32 = 0,
    lpfn: ?*anyopaque = null,
    lParam: LPARAM = 0,
    iImage: i32 = 0,
};

// browse flags
pub const BIF_RETURNONLYFSDIRS: u32 = 0x00000001;
pub const BIF_NEWDIALOGSTYLE: u32 = 0x00000040;

// shell functions
pub extern "shell32" fn SHBrowseForFolderA(*BROWSEINFOA) callconv(.c) LPITEMIDLIST;
pub extern "shell32" fn SHGetPathFromIDListA(LPITEMIDLIST, [*]u8) callconv(.c) BOOL;
pub extern "ole32" fn CoTaskMemFree(?*anyopaque) callconv(.c) void;
pub extern "ole32" fn CoInitialize(?*anyopaque) callconv(.c) i32;
