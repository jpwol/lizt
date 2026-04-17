const std = @import("std");

pub fn ParseResult(comptime T: type) type {
    return struct {
        flags: T,
        argv: [][]const u8,
    };
}

pub fn parse(
    comptime T: type,
    allocator: std.mem.Allocator,
    args: std.process.Args,
) !ParseResult(T) {
    return parseSlice(T, allocator, try args.toSlice(allocator));
}

pub fn parseSlice(
    comptime T: type,
    allocator: std.mem.Allocator,
    raw: []const []const u8,
) !ParseResult(T) {
    var flags = T{};
    var positionals: std.ArrayList([]const u8) = .empty;
    errdefer positionals.deinit(allocator);

    var i: usize = 0;
    while (i < raw.len) : (i += 1) {
        const arg = raw[i];

        if (std.mem.eql(u8, arg, "--")) {
            i += 1;
            while (i < raw.len) : (i += 1)
                try positionals.append(allocator, raw[i]);
            break;
        }

        if (std.mem.startsWith(u8, arg, "--")) {
            const body = arg[2..];
            const eq = std.mem.indexOfScalar(u8, body, '=');
            const name = if (eq) |e| body[0..e] else body;
            const inline_val = if (eq) |e| body[e + 1 ..] else null;

            if (!try setField(T, &flags, name, inline_val, raw, &i))
                return error.UnknownFlag;

        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            const shorts = arg[1..];
            for (shorts, 0..) |ch, si| {
                const long_name = resolveShort(T, ch) orelse return error.UnknownFlag;

                const can_consume = (si == shorts.len - 1);
                if (!try setField(T, &flags, long_name, null, if (can_consume) raw else &.{}, &i))
                    return error.UnknownFlag;
            }
        } else {
            try positionals.append(allocator, arg);
        }
    }

    return .{
        .flags = flags,
        .argv = try positionals.toOwnedSlice(allocator),
    };
}

fn resolveShort(comptime T: type, ch: u8) ?[]const u8 {
    if (!@hasDecl(T, "shorthands")) return null;
    const sh = T.shorthands;
    inline for (std.meta.fields(@TypeOf(sh))) |f| {
        if (f.name.len == 1 and f.name[0] == ch)
            return @field(sh, f.name);
    }
    return null;
}

fn setField(
    comptime T: type,
    flags: *T,
    name: []const u8,
    inline_val: ?[]const u8,
    raw: []const []const u8,
    i: *usize,
) !bool {
    inline for (std.meta.fields(T)) |f| {
        if (f.name[0] == '_') continue;
        if (std.mem.eql(u8, f.name, name)) {
            switch (f.type) {
                bool => @field(flags, f.name) = true,
                []const u8 => {
                    const val = inline_val orelse blk: {
                        i.* += 1;
                        if (i.* >= raw.len) return error.MissingArgument;
                        break :blk raw[i.*];
                    };
                    @field(flags, f.name) = val;
                },
                else => {
                    const val = inline_val orelse blk: {
                        i.* += 1;
                        if (i.* >= raw.len) return error.MissingArgument;
                        break :blk raw[i.*];
                    };
                    @field(flags, f.name) = std.fmt.parseInt(f.type, val, 10) catch
                        return error.InvalidArgument;
                },
            }
            return true;
        }
    }
    return false;
}
