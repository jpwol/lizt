const std = @import("std");
const Io = std.Io;
const File = Io.File;
const Terminal = Io.Terminal;
const Color = Terminal.Color;
const Kind = File.Kind;

pub fn setTermColor(kind: Kind, term: Terminal, exec: bool, use_color: bool) !void {
    if (!use_color) {
        return;
    }
    switch (kind) {
        .directory => {
            try term.setColor(Color.blue);
            try term.setColor(Color.bold);
        },
        .file => {
            if (exec) {
                try term.setColor(Color.bold);
                try term.setColor(Color.green);
            } else {
                try term.setColor(Color.yellow);
            }
        },
        .sym_link => {
            try term.setColor(Color.bold);
            try term.setColor(Color.cyan);
        },
        else => try term.setColor(Color.bright_white),
    }
}

pub const icons: std.StaticStringMap([]const u8) = .initComptime(.{
    .{ ".zig", "  " },
    .{ ".zon", "  " },
    .{ ".c", "  " },
    .{ ".cpp", "  " },
    .{ ".h", "  " },
    .{ ".hpp", "  " },
    .{ ".cs", "  " },
    .{ ".rs", "  " },
    .{ ".go", "󰟓  " },
    .{ ".py", "  " },
    .{ ".lua", "  " },
    .{ ".java", "  " },
    .{ ".html", "  " },
    .{ ".js", "  " },
    .{ ".ts", "  " },
    .{ ".css", "  " },
    .{ ".sh", "  " },
    .{ ".zsh", "  " },
    .{ ".fish", "  " },
    .{ ".exe", "  " },
    .{ ".png", "󰋩  " },
    .{ ".jpg", "󰋩  " },
    .{ ".jpeg", "󰋩  " },
    .{ ".bmp", "󰋩  " },
    .{ ".webp", "󰋩  " },
    .{ ".gif", "󰋩  " },
    .{ ".md", "󰍔  " },

    .{ "", "  " },
});
