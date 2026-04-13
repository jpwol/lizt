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
    var list = filestat.buildDirList() catch |err| {
        try stderr.print("{s}: '{s}': {s}\n", .{argv[0], path, @errorName(err)});
        return;
    };
    var max_width: usize = 0;
    for (list.items) |i| {
        const width = std.fmt.count("{d}", .{i.size});
        if (width > max_width) max_width = width;
    }

    for (list.items) |i| {
        const name = std.c.getpwuid(i.uid);
        const group = std.c.getgrgid(i.gid);

        try stdout.print("\x1b[32m{[user]s} \x1b[33m{[group]s} \x1b[34m{[size]d:>[width]} \x1b[35m{[name]s:<5}\n", .{
            .user = name.?.name.?, 
            .group = group.?.name.?, 
            .size = i.size, 
            .width = max_width, 
            .name = i.name
        }); 
    }

    filestat.deinit(&list);
    
    try stdout.flush();
    try stderr.flush();
}
