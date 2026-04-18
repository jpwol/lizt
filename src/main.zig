const std = @import("std");
const file = @import("file.zig");
const linux = std.os.linux;
const posix = std.posix;
const zopt = @import("zopt");

const Args = struct {
    help: bool = false,
    long: bool = false,
    column: bool = false,
    hidden: bool = false,

    pub const short = .{
        .h = "help",
        .l = "long",
        .c = "column",
        .a = "hidden",
    };
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const res = try zopt.parse(Args, allocator, init.minimal.args);

    const stdout = blk: {
        var buf: [4096]u8 = undefined;
        var stdout = std.Io.File.stdout().writer(init.io, &buf);
        break :blk &stdout.interface;
    };
    const stderr = blk: {
        var stderr = std.Io.File.stderr().writer(init.io, &.{});
        break :blk &stderr.interface;
    };

    const cwd = std.Io.Dir.cwd();
    if (res.argv.len <= 2) {
        const path = if (res.argv.len == 2) res.argv[1] else ".";
        const s = cwd.statFile(init.io, path, .{ .follow_symlinks = false }) catch |err| {
            try stderr.print("{s}: '{s}': {s}\n", .{res.argv[0], path, @errorName(err)});
            return;
        };

        var filestat = try file.init(path, s.kind, init.io, stdout, allocator, .{ .long = res.flags.long, .column = res.flags.column, .hidden = res.flags.hidden });

        filestat.printlist() catch |err| {
            try stderr.print("{s}: '{s}': {s}\n", .{res.argv[0], path, @errorName(err)});
            return;
        };
    } else {
        for (res.argv[1..], 1..) |path, idx| {
            try stdout.print("{s}:\n", .{path});
            const s = cwd.statFile(init.io, path, .{ .follow_symlinks = false }) catch |err| {
                try stderr.print("{s}: '{s}': {s}\n", .{res.argv[0], path, @errorName(err)});
                return;
            };

            var filestat = try file.init(path, s.kind, init.io, stdout, allocator, .{ .long = res.flags.long, .column = res.flags.column, .hidden = res.flags.hidden });

            filestat.printlist() catch |err| {
                try stderr.print("{s}: '{s}': {s}\n", .{res.argv[0], path, @errorName(err)});
                return;
            };

            if (idx < res.argv.len - 1)
                try stdout.writeByte('\n');
        }
    }



    try stdout.flush();
}
