const c = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/Xutil.h");
    @cInclude("X11/Xos.h");
    @cInclude("unistd.h"); // execvp
});
const std = @import("std");
const print = std.debug.warn;

var attr: c.XWindowAttributes = undefined;
var start: c.XButtonEvent = undefined;
var wm_detected = false;

pub fn main() void {
    print("\n\tMy Window Manager\n\n", .{});
    print(" 1. Open X display.\n", .{});

    var display: *c.Display = c.XOpenDisplay(null) orelse {
        print("\tError: Failed to open X display {}.\n", .{c.XDisplayName(null)});
        return;
    };
    defer _ = c.XCloseDisplay(display);

    var root = c.XDefaultRootWindow(display);

    { // CHECK OTHER WINDOW MANAGERS
        _ = c.XSetErrorHandler(OnWMDetected);

        _ = c.XSelectInput(display, root, c.SubstructureRedirectMask | c.SubstructureNotifyMask); // | c.ExposureMask |
        _ = c.XSync(display, c.False);
        if (wm_detected) {
            print("\tError: Detected another window manager on display {}", .{c.XDisplayName(null)});
            return;
        }

        // Set error handler.
        _ = c.XSetErrorHandler(OnXError);
        _ = c.XSync(display, c.False); //dwm does this, I don't think it is necessary.
    }

    //SETUP
    var wa: c.XSetWindowAttributes = undefined;
    var screen: c_int = c.XDefaultScreen(display);
    var sw: c_int = c.XDisplayWidth(display, screen);
    var sh: c_int = c.XDisplayHeight(display, screen);
    {
        // init vars
        {
            //var m: *c.XMonitor = undefined;
            //var wa1: c.XSetWindowAttributes = c.XSetWindowAttributes{ .override_redirect = c.True, .background_pixmap = c.ParentRelative, .event_mask = c.ButtonPressMask | c.ExposureMask };
        }
        _ = c.XSelectInput(display, root, c.SubstructureRedirectMask | c.SubstructureNotifyMask);
        // GRAB KEYS
        {
            {
                _ = c.XUngrabKey(display, c.AnyKey, c.AnyModifier, root);

                var code = c.XKeysymToKeycode(display, c.XStringToKeysym("F4"));
                //funciona
                _ = c.XGrabKey(display, c.XKeysymToKeycode(display, c.XK_Return), c.Mod1Mask, root, c.False, c.GrabModeAsync, c.GrabModeAsync);
                // focus(null)
            }
        }
    }
    // DETECT OPENED WINDOWS
    {
        // c. Grab X server to prevent windows from changing under us.
        _ = c.XGrabServer(display);
        defer _ = c.XUngrabServer(display);

        var returned_root: c.Window = undefined;
        var returned_parent: c.Window = undefined;
        var top_level_windows: [*c]c.Window = undefined;
        defer _ = c.XFree(top_level_windows);
        var num_top_level_windows: u32 = undefined;
        var Xquery_successful = c.XQueryTree(display, root, &returned_root, &returned_parent, &top_level_windows, &num_top_level_windows);
        print("XQuery: {}\n", .{Xquery_successful});

        var i: u32 = 0;
        while (i < num_top_level_windows) : (i = i + 1) {
            var window = top_level_windows[i];

            var x_window_attrs: c.XWindowAttributes = undefined;
            _ = c.XGetWindowAttributes(display, window, &x_window_attrs);

            // non visible windows
            if (x_window_attrs.override_redirect != 0 or x_window_attrs.map_state != c.IsViewable) continue;

            print("Visible. Making it sensible to sortcuts\n", .{});
            MakeSensible(display, window, false);
        }
    }

    print(" 2. main event loop:\n\n", .{});
    while (true) {
        var e: c.XEvent = undefined;
        _ = c.XNextEvent(display, &e);
        print("recived event: ", .{});
        switch (e.type) {
            // 1. Creating a Window
            // A newly created window is always invisible, so there’s nothing for our window manager to do
            //OnCreateNotify(e.xcreatewindow),
            c.CreateNotify => print("CreateNotify. Window is invisible, nothing to do.\n", .{}),

            // 2. Configuring a Newly Created Window
            // Since the window is still invisible, the window manager doesn’t need to care.
            c.ConfigureRequest => {
                print("ConfigureRequest. Window still invisible, we don't care.\n", .{});
                OnConfigureRequest(e.xconfigurerequest, display);
            },
            //Our window manager will then receive a ConfigureNotify event, which it will ignore
            c.ConfigureNotify => print("ConfigureNotify.\n", .{}),

            // 3. Mapping a Window
            //
            //    a. Render window (and/or frame) with XMapWindow().
            //    b. Register for mouse or keyboard shortcuts on w and/or f.
            c.MapRequest => {
                print("MapRequest\n", .{});
                OnMapRequest(e.xmaprequest, display);
                // 2. Actually map window.
                _ = c.XMapWindow(display, e.xmaprequest.window);
                MakeSensible(display, e.xmaprequest.window, false);
            },
            //    c. When our window manager calls XMapWindow() to map the frame window (step 6 in the example code), the X server knows that the action originates from the current window manager, and will execute it directly instead of redirecting it back as a MapRequest event. Our window manager will later receive a MapNotify event, which it can ignore:
            c.MapNotify => print("MapNotify. Nothing to do.\n", .{}),

            //    d. Unmapping a window
            c.UnmapNotify => OnUnmapNotify(e.xunmap),

            // When a client application exits or no longer needs a window, it will call XDestroyWindow() to dispose of the window. This triggers a DestroyNotify event. In our case, there’s nothing we need to do in response.
            c.DestroyNotify => print("DestroyNotify.\n", .{}),

            // When our window manager calls XReparentWindow(), it will trigger a ReparentNotify event, which it will ignore:
            c.ReparentNotify => print("ReparentNotify. Nothing to do.\n", .{}),

            c.KeyPress => {
                var text: [255]u8 = undefined;
                var key: c.KeySym = undefined;
                _ = c.XLookupString(&e.xkey, &text, 255, &key, 0);
                print("Key {} pressed on window {}, subwindow {}\n", .{ text[0], e.xkey.window, e.xkey.subwindow });

                OnKeyPress(e.xkey, display);

                //if (e.xkey.subwindow != 0) {
                // print("Raising window\n", .{});
                // _ = c.XRaiseWindow(display, e.xkey.subwindow);

                //}
            },
            c.KeyRelease => print("Key released\n", .{}),
            c.ButtonPress => {
                print("Button pressed on window {}, subwindow {}\n", .{ e.xbutton.window, e.xbutton.subwindow });
                if (e.xbutton.subwindow != 0) {
                    _ = c.XGetWindowAttributes(display, e.xbutton.subwindow, &attr);
                    start = e.xbutton;
                }
                // 3. Raise clicked window to top.
                print("Raising window {}\n", .{e.xbutton.window});
                _ = c.XRaiseWindow(display, e.xbutton.window);
                _ = c.XAllowEvents(display, c.ReplayPointer, c.CurrentTime);
            },
            c.ButtonRelease => {
                start.subwindow = undefined;
                print("Button released\n", .{});
            },
            c.MotionNotify => {
                print("MotionNotify\n", .{});
                if (start.subwindow != 0) {
                    var xdiff = e.xbutton.x_root - start.x_root;
                    var ydiff = e.xbutton.y_root - start.y_root;
                    if (start.button == 1) {
                        print("Button 1 pressed. Moving window.\n", .{});
                        //if (attr.width > 0)
                        // _ = c.XMoveResizeWindow(display, start.subwindow, attr.x + xdiff, attr.y + ydiff, @truncate(c_uint, attr.width), attr.height);
                    }
                    if (start.button == 3) {
                        print("Button 3 pressed. Resizing window.\n", .{});
                        // _ = c.XMoveResizeWindow(display, start.subwindow, attr.x, attr.y, attr.width + xfidd, attr.height + ydiff);
                    }
                }
            },
            else => print("Unhandeled event\n", .{}),
        }
    }
}

fn OnMapRequest(event: c.XMapRequestEvent, display: *c.Display) void {
    // This is where we start managing a new window (unless it has been detected by scan() at startup).
    // Note that windows might have existed before a MapRequest.
    // Explicitly ignore windows with override_redirect being True to allow popups, bars, panels, ...
    var wa: c.XWindowAttributes = undefined;
    if (c.XGetWindowAttributes(display, event.window, &wa) != c.Success)
        return;
    if (wa.override_redirect != c.Success)
        return;
    // 2. Actually map window.
    _ = c.XMapWindow(display, event.window);
    return;
}

fn OnWMDetected(display: ?*c.Display, e: [*c]c.XErrorEvent) callconv(.C) c_int {
    wm_detected = true;
    return 0;
}
fn OnXError(display: ?*c.Display, e: [*c]c.XErrorEvent) callconv(.C) c_int {
    //print e
    return 1;
}

fn OnCreateNotify(e: c.XCreateWindowEvent) void {
    print("OnCreateNotify\n", .{});
}
// var root = c.XDefaultRootWindow(display);
fn OnConfigureRequest(e: c.XConfigureRequestEvent, display: *c.Display) void {
    var changes: c.XWindowChanges = undefined;
    changes.x = e.x;
    changes.y = e.y;
    changes.width = e.width;
    changes.height = e.height;
    changes.border_width = e.border_width;
    changes.sibling = e.above;
    changes.stack_mode = e.detail;

    //  Falta un if

    // Grant request by calling XConfigureWindow().
    _ = c.XConfigureWindow(display, e.window, @truncate(u32, e.value_mask), &changes);
    // print("Resize {} to {},{}", .{ e.window, w.width, e.height });
}
fn OnUnmapNotify(e: c.XUnmapEvent) void {
    // If the window is a client window we manage, unframe it upon UnmapNotify. We need the check  because we will recive an UnmapNotify event for a frame we just destroyes ourselves.
    // if ...

    // Ignore event if it is triggered by reparenting a window that was mapped before the window manager started.
    //    c.Unframe(e.window);
    print("Unmapping Window.\n", .{});
}
fn xerrordummy(display: ?*c.Display, ee: [*c]c.XErrorEvent) callconv(.C) c_int {
    return 0;
}
fn OnKeyPress(e: c.XKeyEvent, display: *c.Display) void {
    if ((e.state & c.Mod1Mask != 0) and (e.keycode == c.XKeysymToKeycode(display, c.XStringToKeysym("F4")))) {
        //    if ((e.state & c.Mod1Mask != 0) and (e.keycode == c.XKeysymToKeycode(display, c.XK_F4))) {
        print("Alt + F4: Close window\n", .{});

        // K...

        {
            var proto: c_ulong = c.XInternAtom(display, "WM_DELETE_WINDOW", c.False);

            var n: i32 = undefined;
            var protocols: [*c]c.Atom = undefined;
            _ = c.XGetWMProtocols(display, e.window, &protocols, &n);
            var exists = false;
            var count: u32 = 0;
            print("n: {}\n", .{n});
            while (!exists and n > 0) {
                n = n - 1;
                exists = protocols[count] == proto;
                count = count + 1;
            }
            _ = c.XFree(protocols);
            //sendevent(sel: Client,wmatom[WMDelete]: Atom)
            if (exists) {
                var ev: c.XEvent = undefined;
                print("Exists.", .{});
                ev.type = c.ClientMessage;
                //ev.xclientwindow = e.window;
                //ev.xclient.message_type=
                ev.xclient.format = 32;
                //ev.xclient.data.l[0] = proto;
                ev.xclient.data.l[1] = c.CurrentTime;
                _ = c.XSendEvent(display, e.window, c.False, c.NoEventMask, &ev);

                _ = c.XGrabServer(display);
                defer _ = c.XUngrabServer(display);

                _ = c.XSetErrorHandler(xerrordummy);
                _ = c.XSetCloseDownMode(display, c.DestroyAll);
                _ = c.XKillClient(display, e.window);
                _ = c.XSync(display, c.False);
                _ = c.XSetErrorHandler(OnXError);
            }
        }
        // _ = c.XUnmapWindow(display, e.window);
        // _ = c.XDestroyWindow(display, e.window);
        //        _ = c.XKillClient(display, e.window);
        //        _ = c.XDestroyWindow(display, e.window);
    }
}

fn MakeSensible(display: *c.Display, window: c.Window, focused: bool) void {
    _ = c.XSelectInput(display, window, c.SubstructureRedirectMask | c.SubstructureNotifyMask);

    _ = c.XGrabKey(display, c.XKeysymToKeycode(display, c.XStringToKeysym("F4")), c.Mod1Mask, window, c.False, c.GrabModeAsync, c.GrabModeAsync);

    // if (!focused)
    _ = c.XGrabButton(display, c.AnyButton, c.AnyModifier, window, c.False, c.ButtonPressMask | c.ButtonReleaseMask | c.PointerMotionMask, c.GrabModeSync, c.GrabModeSync, c.None, c.None);
    _ = c.XGrabKey(display, c.XKeysymToKeycode(display, c.XK_Return), c.Mod1Mask, window // root better
    , c.False, c.GrabModeAsync, c.GrabModeAsync);
    // _ = c.XGrabButton(display, c.Button1, c.Mod1Mask, window, c.False, c.ButtonPressMask | c.ButtonReleaseMask | c.PointerMotionMask, c.GrabModeAsync, c.GrabModeAsync, c.None, c.None);

    // Gain focus on click.
}
