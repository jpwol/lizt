const std = @import("std");
const Io = std.Io;
const File = Io.File;
const Terminal = Io.Terminal;
const Color = Terminal.Color;
const Kind = File.Kind;

pub fn setTermColor(kind: Kind, term: Terminal, exec: bool) !void {
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
