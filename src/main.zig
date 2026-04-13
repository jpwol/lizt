const std = @import("std");
const file = @import("file.zig");

pub fn main(init: std.process.Init) !void {
    const argv = try init.minimal.args.toSlice(init.gpa);
    defer init.gpa.free(argv);

    const stdout = blk: {
        var buf: [1024]u8 = undefined;
        var stdout = std.Io.File.stdout().writer(init.io, &buf);
        break :blk &stdout.interface;
    };
    const stderr = blk: {
        var stderr = std.Io.File.stderr().writer(init.io, &.{});
        break :blk &stderr.interface;
    };

    const path = if (argv.len == 2) argv[1] else ".";
    
    const cwd = std.Io.Dir.cwd();
    const s = cwd.statFile(init.io, path, .{ .follow_symlinks = false }) catch |err| {
        try stderr.print("{s}: '{s}': {s}\n", .{argv[0], path, @errorName(err)});
        return;
    };
    
    const filestat = file.init(path, s, init.io, init.gpa);

    filestat.printlist(stdout) catch |err| {
        try stderr.print("{s}: '{s}': {s}\n", .{argv[0], path, @errorName(err)});
        return;
    };
    
    try stdout.flush();
    try stderr.flush();
}
