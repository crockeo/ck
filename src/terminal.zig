const std = @import("std");
const c = @cImport({
    @cInclude("sys/ioctl.h");
    @cInclude("stdlib.h");
    @cInclude("termios.h");
});

var termios = c.struct_termios{};
var stdin_handle: c_int = -1;

/// `enableRawMode` sets up the terminal in raw mode,
/// so that we can... you know... write an editor.
pub fn enableRawMode(stdin: std.fs.File) void {
    // NOTE: a lot of this is taken from this blog post
    // https://viewsourcecode.org/snaptoken/kilo/02.enteringRawMode.html
    if (stdin_handle != -1) {
        @panic("enableRawMode already installed");
    }
    if (c.tcgetattr(stdin.handle, &termios) != 0) {
        @panic("Failed to get termios");
    }
    if (c.atexit(disableRawMode) != 0) {
        @panic("Failed to register atexit");
    }
    stdin_handle = stdin.handle;

    var new_termios = termios;
    new_termios.c_iflag &= ~@as(c_ulong, (c.BRKINT | c.ICRNL | c.INPCK | c.ISTRIP | c.IXON));
    new_termios.c_oflag &= ~@as(c_ulong, (c.OPOST));
    new_termios.c_cflag |= (c.CS8);
    new_termios.c_lflag &= ~@as(c_ulong, (c.ECHO | c.ICANON | c.IEXTEN | c.ISIG));
    new_termios.c_cc[c.VMIN] = 0;
    new_termios.c_cc[c.VTIME] = 1;

    if (c.tcsetattr(stdin.handle, c.TCSAFLUSH, &new_termios) != 0) {
        @panic("Failed to set termios");
    }
}

export fn disableRawMode() void {
    if (c.tcsetattr(stdin_handle, c.TCSAFLUSH, &termios) != 0) {
        @panic("Failed to disable raw mode; probably worth closing this terminal.");
    }
}

pub fn clearScreen(stdout: std.fs.File) !void {
    try stdout.writeAll("\x1b[2J");
}

pub const Size = struct {
    rows: usize,
    cols: usize,
};

pub fn getSize(stdout: std.fs.File) !Size {
    var winsize: c.struct_winsize = undefined;
    if (c.ioctl(stdout.handle, c.TIOCGWINSZ, &winsize) != 0) {
        @panic("TODO: turn this into a normal error");
    }
    return Size{
        .rows = winsize.ws_row,
        .cols = winsize.ws_col,
    };
}
