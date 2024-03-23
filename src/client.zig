const std = @import("std");
const c = @cImport({
    @cInclude("X11/Xlib.h");
});

const print = std.debug.print;

pub fn main() anyerror!void {
    var args = std.process.ArgIteratorPosix.init();
    _ = args.skip();
    var arg_one = args.next() orelse return usage();
    if (arg_one.len <= 1 or arg_one[0] != '-') return usage();
    switch (arg_one[1]) {
        'k', 'R', 'q' => return send_command(arg_one[1], 0),
        //'c' => {
        //    if (arg_one.len != 2) usageclient();
        //    switch (arg_one[2]){
        //        'n' => return,
        //        'p' => return,
        //        else => return,
        //    }
        //},
        else => return usage(),
    }
}

fn send_command(command: u8, arg: u8) !void {
    var display: *c.Display = c.XOpenDisplay(null) orelse return; // TODO Error
    defer _ = c.XCloseDisplay(display);
    var root = c.XDefaultRootWindow(display);
    var ev: c.XEvent = undefined;
    ev.xclient.type = c.ClientMessage;
    ev.xclient.window = root;
    // This is our "protocol": One byte opcode, one byte argument
    ev.xclient.message_type = c.XInternAtom(display, "ZWM_CLIENT_COMMAND", c.False);
    ev.xclient.format = 8;
    ev.xclient.data.b[0] = command;
    ev.xclient.data.b[1] = arg;

    // Send this message to all clients which have selected for
    // "SubstructureRedirectMask" on the root window. By definition,
    // this is the window manager.
    print("Sending command {}, arg {}\n", .{ command, arg });
    _ = c.XSendEvent(display, root, c.False, c.SubstructureRedirectMask, &ev);
    _ = c.XSync(display, c.False);
    return;
}
fn usage() void {
    print("Usage: client COMMAND [OPTION]\n\n", .{});
    print("-h [OPTIONS]\t--help\n\n", .{});
    //   print("-f\t\t--floating-toggle\n", .{});
    //   print("-F\t\t--fullscreen-toggle\n", .{});
    print("-k\t\t--kill-client\n", .{});
    //   print("-r [OPTIONS]\t--resize\n", .{});
    //   print("-c [OPTIONS]\t--client\n", .{}); // -p --prev / -n --next
    //   print("-w [OPTIONS]\t--workspace\n", .{});
    //   print("-l [OPTIONS]\t--layout\n\n",.{});
    print("-R\t\t--restart\n", .{});
    print("-q\t\t--quit\n", .{});
}
fn usageclient() void {
    //   print("-cn --next-client\n", .{});
}
