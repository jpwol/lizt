const std = @import("std");
const file = @import("file.zig");
const linux = std.os.linux;
const posix = std.posix;

var threaded: std.Io.Threaded = undefined;

pub fn main(init: std.process.Init.Minimal) !void {
    const c_allocator = std.heap.c_allocator;
    var arena_impl = std.heap.ArenaAllocator.init(c_allocator);
    defer arena_impl.deinit();
    const allocator = arena_impl.allocator();

    threaded = std.Io.Threaded.init(c_allocator, .{
    });
    defer threaded.deinit();
    const io = threaded.io();
    
    const argv = try init.args.toSlice(allocator);
    defer allocator.free(argv);

    const stdout = blk: {
        var buf: [4096]u8 = undefined;
        var stdout = std.Io.File.stdout().writer(io, &buf);
        break :blk &stdout.interface;
    };
    const stderr = blk: {
        var stderr = std.Io.File.stderr().writer(io, &.{});
        break :blk &stderr.interface;
    };

    const path = if (argv.len == 2) argv[1] else ".";

    const cwd = std.Io.Dir.cwd();
    const s = cwd.statFile(io, path, .{ .follow_symlinks = false }) catch |err| {
        try stderr.print("{s}: '{s}': {s}\n", .{argv[0], path, @errorName(err)});
        return;
    };

    var filestat = file.init(path, s.kind, io, allocator);

    filestat.printlist(stdout) catch |err| {
        try stderr.print("{s}: '{s}': {s}\n", .{argv[0], path, @errorName(err)});
        return;
    };
    
    try stdout.flush();
}
