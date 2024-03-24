const c = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/cursorfont.h");
    @cInclude("X11/Xft/Xft.h");
});
const std = @import("std");
const print = std.debug.print;
const allocator = std.heap.c_allocator;

fn process_client_message(message: [20]u8, display: *c.Display) void {
    print("Message arrived: {s}\n ", .{message});
    switch (message[0]) {
        'k' => _ = if (focus) |f| {
            _ = c.XKillClient(display, f.win);
            print("Killing client {}\n", .{f.win});
        },
        else => {
            print("Unknown message recived: {s}\n", .{message});
        },
    }
}

fn OnWMDetected(display: ?*c.Display, e: [*c]c.XErrorEvent) callconv(.C) c_int {
    _ = display;
    _ = e;
    print("\tError: Another window manager is running.", .{});
    std.os.exit(1);
}

var clients = std.ArrayList(*Client).init(allocator);
var focus: ?*Client = null;
const Cursor = enum { Normal, Resize, Move, Last };

const Dimension = struct { width: i32, height: i32 };
const Position = struct { x: i32, y: i32 };
const Client = struct {
    name: [25]u8,
    mina: f32,
    maxa: f32,
    pos: Position,
    dim: Dimension,
    old_pos: Position,
    old_dim: Dimension,
    base_dim: Dimension,
    inc_dim: Dimension,
    max_dim: Dimension,
    min_dim: Dimension,
    border_width: i32,
    oldborderwidth: i32,
    tags: u32,
    isfixed: bool,
    isfloating: bool,
    isurgent: bool,
    neverfocus: i32,
    oldstate: i32,
    isfullscreen: i32,
    isdecorated: bool,
    win: c.Window,

    pub fn init(self: *Client, wa: c.XWindowAttributes) *Client {
        self.pos = Position{ .x = wa.x, .y = wa.y };
        self.old_pos = Position{ .x = wa.x, .y = wa.y };
        self.dim = Dimension{ .width = wa.width, .height = wa.height };
        self.old_dim = Dimension{ .width = wa.width, .height = wa.height };
        return self;
    }
    pub fn setDecorations(self: *Client) void {
        self.*.isdecorated = true;
    }
};

pub fn main() void {
    print("\n\tZig Window Manager. Minimal version.\n\n", .{});
    print(" 1. Open X display.\n", .{});

    var display: *c.Display = c.XOpenDisplay(0x0) orelse return print("\tError: Failed to open X display\n", .{});
    defer _ = c.XCloseDisplay(display);

    var root = c.XDefaultRootWindow(display);
    var nofocus: c.Window = undefined;

    { // 1. Initialization.
        //   a. Select events on root window. Use a special error handler so we can
        //   exit gracefully if another window manager is already running.
        _ = c.XSetErrorHandler(OnWMDetected) orelse return print("Error: Failed to set Error Handler\n", .{});
        //causes an error if another window manager is running.
        _ = c.XSelectInput(display, root, 0 // thanks to katriawm
        | c.FocusChangeMask // FocusIn, FocusOut
        // RandR protocol says: "Clients MAY select for
        // ConfigureNotify on the root window to be
        // informed of screen changes." Selecting for
        // StructureNotifyMask creates such events. */
        | c.StructureNotifyMask
        // Manage creation and destruction of windows.
        // SubstructureRedirectMask is also used by our IPC
        // client and possibly EWMH clients, both sending us
        // ClientMessages.
        | c.SubstructureRedirectMask | c.SubstructureNotifyMask // Important ones!!
        // DWM also sets this masks:
        // ButtonPressMask | PointerMotionMask | EnterWindowMask
        // LeaveWindowMaks | PropertyChangeMask
        );
        _ = c.XSync(display, c.False);

        // b. Set Error Handler
        _ = c.XSetErrorHandler(OnXError);
        _ = c.XSync(display, c.False); // it is not necessary to run it now.

        // init screen
        var screen: i32 = c.XDefaultScreen(display); // TODO Document differece respect to XDefaultScreen / DefaultScreen.
        // root = c.XRootWindow(display, screen); for multiple screens. otherwise is not necessary
        var sw: i32 = c.XDisplayWidth(display, screen);
        var sh: i32 = c.XDisplayHeight(display, screen);
        print("Screen initialized\n", .{});

        // c. Set default cursor on root window and center.
        var cursor_normal = c.XCreateFontCursor(display, c.XC_left_ptr);
        var cursor_resize = c.XCreateFontCursor(display, c.XC_sizing);
        _ = cursor_resize;
        var cursor_move = c.XCreateFontCursor(display, c.XC_fleur);
        _ = cursor_move;
        _ = c.XDefineCursor(display, root, cursor_normal);
        _ = c.XWarpPointer(display, c.None, root, 0, 0, 0, 0, @divTrunc(sw, 2), @divTrunc(sh, 2)); // center pointer
        print("Cursor initialized\n", .{});

        // TODO d. Set fonts. Initialize font and colors. - katriawm
        // TODO Colors - catwm
        // TODO decorations_load - katriawm

        // katriawm
        // Create a window which will receive input focus when no real
        // window has focus. We do this to avoid any kind of "*PointerRoot"
        // usage. Focusing the root window confuses applications and kind of
        // returns to sloppy focus.
        {
            nofocus = c.XCreateSimpleWindow(display, root, -10, -10, 1, 1, 0, 0, 0);
            var wa: c.XSetWindowAttributes = undefined;
            wa.override_redirect = c.True;
            _ = c.XChangeWindowAttributes(display, nofocus, c.CWOverrideRedirect, &wa);
            _ = c.XMapWindow(display, nofocus);
            _ = c.XSetInputFocus(display, nofocus, c.RevertToParent, c.CurrentTime); //focus(null); - katriawm
            print("nofocus window created.\n", .{});
        }
        print("SETUP complete\n", .{});
    }
    // SCAN OPENED WINDOWS
    {
        //Grab X server to prevent windows from changing under us.
        _ = c.XGrabServer(display);
        defer _ = c.XUngrabServer(display);

        var returned_root: c.Window = undefined;
        var returned_parent: c.Window = undefined;
        var top_level_windows: [*c]c.Window = undefined;
        defer _ = c.XFree(top_level_windows);

        var num_top_level_windows: u32 = undefined;
        // First, manage all top-level windows.
        // Then manage transient windows.
        // This is required because the windows pointed to by
        // "transient_for" must already be managed by us
        // attributes from the parents to their popups. */
        if (c.XQueryTree(display, root, &returned_root, &returned_parent, &top_level_windows, &num_top_level_windows) != 0) {
            var i: u32 = 0;
            var window_attrs: c.XWindowAttributes = undefined;
            while (i < num_top_level_windows) : (i = i + 1) {
                var window = top_level_windows[i];
                // katriawm
                if (c.XGetWindowAttributes(display, window, &window_attrs) == 0 or window_attrs.override_redirect != 0 or c.XGetTransientForHint(display, window, &returned_root) != 0)
                    continue;
                if (window_attrs.map_state == c.IsViewable) // dwm -> or getstate(window) == IconicState))
                    manageWindow(window, window_attrs, display);
            }
            i = 0; // now the transients
            while (i < num_top_level_windows) : (i = i + 1) {
                var window = top_level_windows[i];

                if (c.XGetWindowAttributes(display, window, &window_attrs) == 0 or window_attrs.override_redirect != 0)
                    continue;
                if (c.XGetTransientForHint(display, window, &returned_root) != 0 and window_attrs.map_state == c.IsViewable) // dwm -  or getstate(window) == IconicState
                    manageWindow(window, window_attrs, display);
            }
        }
    }

    print(" 2. main event loop:\n\n", .{});
    var e: c.XEvent = undefined;
    while (c.XNextEvent(display, &e) == 0) {
        print("recived event {}: ", .{e.type});
        switch (e.type) {
            // 2. Configuring a Newly Created Window
            // Since the window is still invisible, the window manager doesn’t need to care.
            c.ConfigureRequest => {
                print("Configure Request\n", .{});
                if (wintoclient(e.xconfigurerequest.window)) |client| {
                    _ = client;
                } else {}
            },
            c.ConfigureNotify => {
                print("Configure Notify\n", .{});
                if (e.xconfigure.window != root)
                    continue;
            },

            // This is where we start managing a new window (unless it has been detected by scan() at startup).
            // Note that windows might have existed before a MapRequest.
            // Explicitly ignore windows with override_redirect being True to allow popups, bars, panels, ...
            c.MapRequest => {
                print("Map Request\n", .{});
                var wa: c.XWindowAttributes = undefined;
                if (c.XGetWindowAttributes(display, e.xmaprequest.window, &wa) == 0 or wa.override_redirect != 0)
                    continue;
                manageWindow(e.xmaprequest.window, wa, display);
            },
            c.MappingNotify => {
                print("Mapping Notify\n", .{});
                _ = c.XRefreshKeyboardMapping(&e.xmapping);
                //if(e.xmapping.request == c.MappingKeyboard)
                //    grabkeys(display, root);
            },
            c.UnmapNotify => {
                print("Unmap Notify\n", .{});
                var cl: *Client = wintoclient(e.xunmap.window) orelse continue;
                if (e.xunmap.send_event != 0) {
                    //set clientsstate ( c, WithdeawnState)
                } else {
                    //unmanage(cl,0)
                    // detach(cl)
                    // detachstack(cl);
                    var window_changes: c.XWindowChanges = undefined;
                    _ = c.XGrabServer(display);
                    defer _ = c.XUngrabServer(display);
                    _ = c.XSetErrorHandler(xerrordummy);
                    _ = c.XConfigureWindow(display, cl.win, c.CWBorderWidth, &window_changes); // restore border
                    _ = c.XUngrabButton(display, c.AnyButton, c.AnyModifier, cl.win);
                    // TODO setclintstate(c,WithdrawnState);
                    _ = c.XSync(display, c.False);
                    //_ = c.SetErrorHandler(xerror);
                }
            },
            c.DestroyNotify => {
                print("Destroy Notify\n", .{});
                var cl: *Client = wintoclient(e.xdestroywindow.window) orelse continue;
                _ = cl;
                //unmanage(c,1)
            },
            c.EnterNotify => {
                print("Enter Notify\n", .{});
                var ev = e.xcrossing;
                if ((ev.mode != c.NotifyNormal or ev.detail == c.NotifyInferior) and ev.window != root)
                    return;
                var cl = wintoclient(ev.window) orelse {
                    continue; // no estic segur
                };
                // m = cl.mon
                focus = cl;
            },
            c.Expose => {},
            c.FocusIn => {
                print("Focus In\n", .{});
            },
            c.ClientMessage => {
                print("Client Message\n", .{});
                var cme: *c.XClientMessageEvent = &e.xclient;
                //var cl = wintoclient(cme.window) orelse {
                //    print("window: {}\n", .{cme.window});
                //    print("all clients:\n",.{});
                //    for (clients.items) |cl|
                //        print("client: {} - {}\n",.{cl.name, cl.win});
                //    continue;};
                if (focus) |f| print("window: {}\n", .{f.win});
                // All sorts of client messages arrive here, including our own IPC mechanism
                if (cme.message_type == c.XInternAtom(display, "ZWM_CLIENT_COMMAND", c.False)) {
                    process_client_message(cme.data.b, display);
                    continue;
                }
            },
            c.PropertyNotify => {
                var ev = &e.xproperty;
                if (ev.window == root) { // and ev.atom == c.XA_WM_NAME){
                    //updatestatus
                } else if (ev.state == c.PropertyDelete) {}
            },
            c.FocusOut => print("Focus Out\n", .{}),
            else => print("Unhandeled event\n", .{}),
        }
    }
}

fn manageWindow(window: c.Window, window_attrs: c.XWindowAttributes, display: *c.Display) void {
    print("Manage window {}\n", .{window});
    if (wintoclient(window)) |_| {
        print("Window {} already known.", .{window});
        return;
    }
    const cl: *Client = allocator.create(Client) catch {
        return;
    };
    //errdefer allocator.destroy(cl);
    _ = cl.init(window_attrs);
    cl.win = window;
    cl.isdecorated = true;
    _ = c.XSetWindowBorderWidth(display, window, 0);

    { // client update title
        var tp: c.XTextProperty = undefined;
        defer _ = c.XFree(tp.value);
        var AtomNetWMName = c.XInternAtom(display, "_NET_WM_NAME", c.False);
        if (c.XGetTextProperty(display, window, &tp, AtomNetWMName) == 0) {
            print("Title of client could not be read from EWMH\n", .{});
            var XA_WM_NAME: c.Atom = 39;
            if (c.XGetTextProperty(display, window, &tp, XA_WM_NAME) != 0)
                print("Title of client  could not be read from ICCCM\n", .{});
        }
        if (tp.nitems == 0)
            std.mem.copy(u8, cl.name[0..25], "NAME UNKNOWN");
        const XA_STRING: c.Atom = 31;
        if (tp.encoding == XA_STRING) {
            std.mem.copy(u8, cl.name[0..25], tp.value[0..25]);
            print("Title of client {s} read as verbatim string\n", .{cl.name});
        }
        print("Title of client is now {s}\n", .{cl.name});
    }
    _ = c.XSelectInput(display, window, 0 | c.FocusChangeMask // FocusIn, FocusOut */
    | c.PropertyChangeMask // All kinds of properties, window titles, EWMH, ... */
    );
    // ICCCM says: "The WM_TRANSIENT_FOR property (of type WINDOW)
    // contains the ID of another top-level window. The implication
    // is that this window is a pop-up on behalf of the named
    // window [...]"
    //
    // A popup window should always be floating. */
    var transient_for: c.Window = undefined;
    if (c.XGetTransientForHint(display, window, &transient_for) != 0)
        cl.isfloating = true; // katriawm also sets monitor and workspaces.
    // katriawm - evaluate various hints
    print("client.win {}, win {}\n", .{ cl.win, window });
    cl.win = window;
    clients.append(cl) catch {
        print("Error while saving client to list clients.", .{});
        unreachable;
    };
    focus = cl;
    _ = c.XMapWindow(display, cl.win);
}

/// There's no way to check accesses to destroyed windows, thus those cases are
/// ignored (especially on UnmapNotify's). Other types of errors call Xlibs
/// default error handler, which may call exit.
fn OnXError(display: ?*c.Display, ee: [*c]c.XErrorEvent) callconv(.C) c_int {
    _ = display;
    _ = ee;
    // if (ee.error_code == c.BadWindow
    // or (ee.request_code == c.X_SetInputFocus     and ee.error_code == c.BadMatch)
    // or (ee.request_code == c.X_PolyText8         and ee.error_code == c.BadDrawable)
    // or (ee.request_code == c.X_PolyFillRectangle and ee.error_code == c.BadDrawable)
    // or (ee.request_code == c.X_PolySegment       and ee.error_code == c.BadDrawable)
    // or (ee.request_code == c.X_ConfigureWindow   and ee.error_code == c.BadMatch)
    // or (ee.request_code == c.X_GrabButton        and ee.error_code == c.BadAccess)
    // or (ee.request_code == c.X_GrabKey           and ee.error_code == c.BadAccess)
    // or (ee.request_code == c.X_CopyArea          and ee.error_code == c.BadDrawable))
    //    return 0;
    //print("zwm: fatal error: request code={}, error code={}\n", ee.requestcode, ee.error_code);
    return 1;
}

fn OnConfigureRequest(e: c.XConfigureRequestEvent, display: *c.Display) void {
    defer _ = c.XSync(display, c.False);

    var client: *Client = wintoclient(e.window) orelse
        {
        var window_changes: c.XWindowChanges = undefined;
        window_changes.x = e.x;
        window_changes.y = e.y;
        window_changes.width = e.width;
        window_changes.height = e.height;
        window_changes.border_width = e.border_width;
        window_changes.sibling = e.above;
        window_changes.stack_mode = e.detail;
        // Grant request by calling XConfigureWindow().
        _ = c.XConfigureWindow(display, e.window, @truncate(u32, e.value_mask), &window_changes);
        return;
    };
    if (e.value_mask != 0) { // & cwborderwidth != 0){
        client.border_width = e.border_width;
    } else if (client.isfloating) //or  TODO
    {} else {}
    //configure(client);

}

// There's no way to check accesses to destroyed windows, thus those cases are
// ignored (especially on UnmapNotify's). Other types of errors call Xlibs
// default error handler, which may call exit.
fn xerrordummy(display: ?*c.Display, ee: [*c]c.XErrorEvent) callconv(.C) c_int {
    _ = display;
    _ = ee;
    return 0;
}

fn wintoclient(w: c.Window) ?*Client {
    print("Number of clients: {}. Searching for {}\n", .{ clients.items.len, w });
    print("Windows of clients listed:\n", .{});
    for (clients.items) |client| {
        print("{}\n", .{client.win});
        if (client.win == w)
            return client;
    }
    print("---------\n", .{});
    return null;
}
