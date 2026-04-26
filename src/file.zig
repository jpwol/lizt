const Self = @This();

const std = @import("std");
const Io = std.Io;
const Terminal = Io.Terminal;
const File = Io.File;
const Dir = Io.Dir;
const linux = std.os.linux;
const posix = std.posix;
const Allocator = std.mem.Allocator;

const opts = @import("opts.zig");
const ftype = @import("ftype.zig");

const RDUSR = 0o400;
const WRUSR = 0o200;
const EXUSR = 0o100;
const RDGRP = 0o040;
const WRGRP = 0o020;
const EXGRP = 0o010;
const RDOTH = 0o004;
const WROTH = 0o002;
const EXOTH = 0o001;

const SUID = 0o4000;
const SGID = 0o2000;
const STICKY = 0o1000;

pub const FileStatLong = struct {
    name: []const u8,
    uname: []const u8,
    gname: []const u8,
    link: ?[]const u8,
    kind: File.Kind,
    exec: bool,
    mode: u16,
    size: []const u8,
    nlink: u32,
    perm: [10]u8,
};

pub const FileStatShort = struct {
    name: []const u8,
    kind: File.Kind,
    exec: bool,
};

const Statx = struct {
    mode: u16,
    size: u64,
    uid: linux.uid_t,
    gid: linux.gid_t,
    nlink: u32,
};

path: []const u8,
uname_cache: std.AutoHashMap(linux.uid_t, []const u8),
grname_cache: std.AutoHashMap(linux.gid_t, []const u8),
kind: File.Kind,
io: Io,
allocator: Allocator,
term: Terminal,
opt: opts.Opts,

pub fn init(path: []const u8, kind: File.Kind, io: Io, writer: *Io.Writer, allocator: Allocator, opt: opts.Opts) !Self {
    if (opt.long and opt.column) return error.LongAndColumn;

    if (opt.long) {
        return .{
            .path = path,
            .kind = kind,
            .io = io,
            .allocator = allocator,
            .uname_cache = .init(allocator),
            .grname_cache = .init(allocator),
            .term = .{ .mode = try .detect(io, File.stdout(), false, true), .writer = writer },
            .opt = opt,
        };
    } else {
        return .{
            .path = path,
            .kind = kind,
            .io = io,
            .allocator = allocator,
            .uname_cache = undefined,
            .grname_cache = undefined,
            .opt = opt,
            .term = .{ .mode = try .detect(io, File.stdout(), false, true), .writer = writer },
        };
    }
}

fn lessThanLong(context: void, a: FileStatLong, b: FileStatLong) bool {
    _ = context;
    return std.ascii.lessThanIgnoreCase(a.name, b.name);
}
fn lessThanShort(context: void, a: FileStatShort, b: FileStatShort) bool {
    _ = context;
    return std.ascii.lessThanIgnoreCase(a.name, b.name);
}

pub fn printlist(self: *Self) !void {
    if (self.kind == .directory) {
        if (self.opt.long) {
            var list = try self.handleDirLong();
            std.mem.sort(FileStatLong, list.items, {}, lessThanLong);
            var max_size_width: usize = 0;
            var max_user_width: usize = 0;
            var max_group_width: usize = 0;
            var max_pwidth: usize = 0;
            for (list.items) |i| {
                // var n = i.size;
                // var width: usize = 1;
                // while (n >= 10) : (n /= 10) width += 1;
                if (i.size.len > max_size_width) max_size_width = i.size.len;
                if (i.uname.len > max_user_width) max_user_width = i.uname.len;
                if (i.gname.len > max_group_width) max_group_width = i.gname.len;
                if (i.name.len > max_pwidth) max_pwidth = i.name.len;
            }

            for (list.items) |i| {
                try self.term.writer.print("\x1b[36m {[perm]s} │ \x1b[32m{[user]s: <[uwidth]} {[group]s: <[gwidth]} \x1b[36m│ \x1b[34m{[size]s:>[width]} \x1b[36m│ ", .{
                    .perm = i.perm,
                    .user = i.uname,
                    .uwidth = max_user_width,
                    .group = i.gname,
                    .gwidth = max_group_width,
                    .size = i.size,
                    .width = max_size_width,
                });
                try ftype.setTermColor(i.kind, self.term, i.exec);
                try self.term.writer.print("{[name]s} \x1b[0;90m{[link]s}\x1b[0m\n", .{
                    .name = i.name,
                    .link = i.link orelse "",
                });
            }

            self.deinit(&list);
        } else {
            const list = try self.handleDirShort();
            std.mem.sort(FileStatShort, list.items, {}, lessThanShort);
            if (self.opt.column) {
                for (list.items) |i| {
                    try ftype.setTermColor(i.kind, self.term, i.exec);
                    try self.term.writer.print("{[name]s}\x1b[0m\n", .{
                        .name = i.name,
                    });
                }
            } else {
                var w: std.c.winsize = undefined;
                const errno = posix.errno(linux.ioctl(1, posix.T.IOCGWINSZ, @intFromPtr(&w)));
                switch (errno) {
                    .SUCCESS => {},
                    else => return error.Ioctl,
                }
                const term_width: usize = if (w.col == 0) {
                    for (list.items) |item| {
                        try ftype.setTermColor(item.kind, self.term, item.exec);
                        try self.term.writer.print("{s}\x1b[0m\n", .{item.name});
                    }
                    return;
                } else w.col;

                const max_possible_cols = @min(list.items.len, term_width);
                var num_cols: usize = 1;

                for (2..max_possible_cols + 1) |try_cols| {
                    const try_rows = (list.items.len + try_cols - 1) / try_cols;

                    var total_width: usize = 0;
                    for (0..try_cols) |col| {
                        var col_max: usize = 0;
                        for (0..try_rows) |row| {
                            const idx = col * try_rows + row;
                            if (idx >= list.items.len) break;
                            if (list.items[idx].name.len > col_max) col_max = list.items[idx].name.len;
                        }

                        total_width += col_max + (if (col < try_cols - 1) @as(usize, 2) else 0);
                    }

                    if (total_width <= term_width) {
                        num_cols = try_cols;
                    }
                }
                const num_rows = (list.items.len + num_cols - 1) / num_cols;

                var col_widths = try self.allocator.alloc(usize, num_cols);
                defer self.allocator.free(col_widths);
                @memset(col_widths, 0);
                for (list.items, 0..) |item, idx| {
                    const col = idx / num_rows;
                    if (item.name.len > col_widths[col]) col_widths[col] = item.name.len + 2;
                }

                for (0..num_rows) |row| {
                    for (0..num_cols) |col| {
                        const idx = col * num_rows + row;
                        if (idx >= list.items.len) break;
                        const item = list.items[idx];
                        const next_idx = (col + 1) * num_rows + row;
                        const is_last = (col == num_cols - 1) or (next_idx >= list.items.len);

                        try ftype.setTermColor(item.kind, self.term, item.exec);
                        if (is_last) {
                            try self.term.writer.print("{s}\x1b[0m\n", .{item.name});
                        } else {
                            try self.term.writer.print("{[name]s:<[width]}\x1b[0m", .{
                                .name = item.name,
                                .width = col_widths[col],
                            });
                        }
                    }
                }
            }
        }
    } else {
        if (self.opt.long) {
            const file = try self.handleFileLong();
            if (file) |f| {
                const width = f.size.len;
                const uwidth = f.uname.len;
                const gwidth = f.gname.len;

                try self.term.writer.print("\x1b[36m{[perm]s} \x1b[32m{[user]s: <[uwidth]} {[group]s: <[gwidth]} \x1b[34m{[size]s:>[width]} ", .{
                    .perm = f.perm,
                    .user = f.uname,
                    .uwidth = uwidth,
                    .group = f.gname,
                    .gwidth = gwidth,
                    .size = f.size,
                    .width = width,
                });
                try ftype.setTermColor(f.kind, self.term, f.exec);
                try self.term.writer.print("{[name]s:<5} \x1b[0;90m{[link]s}\n", .{
                    .name = f.name,
                    .link = f.link orelse "",
                });
                self.allocator.free(f.name);
                if (f.link) |link| self.allocator.free(link);
            }
        } else {
            const file = try self.handleFileShort();
            if (file) |f| {
                try ftype.setTermColor(f.kind, self.term, f.exec);
                try self.term.writer.print("{[name]s}\n", .{
                    .name = f.name,
                });
            }
        }
    }
}

fn getstatx(handle: linux.fd_t, path: [:0]const u8) ?Statx {
    var statx: linux.Statx = undefined;
    const errno = linux.errno(linux.statx(handle, @ptrCast(path), posix.AT.SYMLINK_NOFOLLOW, linux.STATX.BASIC_STATS, &statx));
    switch (errno) {
        .SUCCESS => {
            return Statx{
                .mode = statx.mode,
                .size = statx.size,
                .uid = statx.uid,
                .gid = statx.gid,
                .nlink = statx.nlink,
            };
        },
        else => return null,
    }
}

fn buildPermString(kind: File.Kind, mode: u16) [10]u8 {
    var buf: [10]u8 = undefined;
    buf[0] = switch (kind) {
        .directory => 'd',
        .sym_link => 'l',
        .block_device => 'b',
        .character_device => 'c',
        .unix_domain_socket => 's',
        .named_pipe => 'p',
        .file => '-',
        else => '?',
    };

    buf[1] = if (mode & RDUSR != 0) 'r' else '-';
    buf[2] = if (mode & WRUSR != 0) 'w' else '-';
    buf[3] = blk: {
        if (mode & EXUSR != 0) {
            if (mode & SUID != 0) break :blk 's' else break :blk 'x';
        } else {
            if (mode & SUID != 0) break :blk 'S' else break :blk '-';
        }
    };
    buf[4] = if (mode & RDGRP != 0) 'r' else '-';
    buf[5] = if (mode & WRGRP != 0) 'w' else '-';
    buf[6] = blk: {
        if (mode & EXGRP != 0) {
            if (mode & SGID != 0) break :blk 's' else break :blk 'x';
        } else {
            if (mode & SGID != 0) break :blk 'S' else break :blk '-';
        }
    };
    buf[7] = if (mode & RDOTH != 0) 'r' else '-';
    buf[8] = if (mode & WROTH != 0) 'w' else '-';
    buf[9] = blk: {
        if (mode & EXOTH != 0) {
            if (mode & STICKY != 0) break :blk 't' else break :blk 'x';
        } else {
            if (mode & STICKY != 0) break :blk 'T' else break :blk '-';
        }
    };

    return buf;
}

fn getUserName(self: *Self, uid: linux.uid_t) []const u8 {
    if (self.uname_cache.get(uid)) |name| return name;
    const pw = std.c.getpwuid(uid);
    const name = self.allocator.dupe(u8, std.mem.span(pw.?.name.?)) catch return "";
    self.uname_cache.put(uid, name) catch {};
    return name;
}

fn getGroupName(self: *Self, gid: linux.gid_t) []const u8 {
    if (self.grname_cache.get(gid)) |name| return name;
    const gr = std.c.getgrgid(gid);
    const name = self.allocator.dupe(u8, std.mem.span(gr.?.name.?)) catch return "";
    self.grname_cache.put(gid, name) catch {};
    return name;
}

fn handleFileShort(self: *Self) !?FileStatShort {
    var path_buf: [std.fs.max_path_bytes:0]u8 = undefined;
    @memcpy(path_buf[0..self.path.len], self.path);
    path_buf[self.path.len] = 0;
    const file = getstatx(posix.AT.FDCWD, &path_buf);
    if (file) |f| {
        return .{
            .name = self.path,
            .kind = self.kind,
            .exec = if (f.mode & EXUSR != 0 or f.mode & EXGRP != 0 or f.mode & EXOTH != 0) true else false,
        };
    } else {
        return null;
    }
}

fn handleFileLong(self: *Self) !?FileStatLong {
    var path_buf: [std.fs.max_path_bytes:0]u8 = undefined;
    @memcpy(path_buf[0..self.path.len], self.path);
    path_buf[self.path.len] = 0;
    const file = getstatx(posix.AT.FDCWD, &path_buf);
    if (file) |f| {
        return .{
            .name = self.path,
            .uname = self.getUserName(f.uid),
            .gname = self.getGroupName(f.gid),
            .kind = self.kind,
            .exec = if (f.mode & EXUSR != 0 or f.mode & EXGRP != 0 or f.mode & EXOTH != 0) true else false,
            .mode = f.mode,
            .size = try self.getSizeString(f.size),
            .nlink = f.nlink,
            .perm = buildPermString(self.kind, f.mode),
            .link = blk: {
                if (self.kind == .sym_link) {
                    var buf: [std.fs.max_path_bytes]u8 = undefined;
                    const rc = linux.readlinkat(posix.AT.FDCWD, @ptrCast(&path_buf), buf[3..], buf.len - 3);
                    const n = std.math.cast(usize, rc) orelse break :blk null;
                    // const n = try Dir.readLink(Dir.cwd(), self.io, self.path, buf[3..]);
                    buf[0..3].* = "-> ".*;
                    break :blk try self.allocator.dupe(u8, buf[0 .. n + 3]);
                } else {
                    break :blk null;
                }
            },
        };
    } else {
        return null;
    }
}

fn handleDirShort(self: *Self) !std.ArrayList(FileStatShort) {
    const d = try Dir.cwd().openDir(self.io, self.path, .{ .follow_symlinks = true, .iterate = true });
    var itr = d.iterate();
    var list: std.ArrayList(FileStatShort) = .empty;

    while (try itr.next(self.io)) |i| {
        if (!self.opt.hidden and i.name[0] == '.') continue;

        var name_buf: [std.fs.max_name_bytes:0]u8 = undefined;
        @memcpy(name_buf[0..i.name.len], i.name);
        name_buf[i.name.len] = 0;
        const stat = getstatx(d.handle, &name_buf);
        if (stat) |s| {
            try list.append(self.allocator, .{
                .name = try self.allocator.dupe(u8, i.name),
                .kind = i.kind,
                .exec = if (s.mode & EXUSR != 0 or s.mode & EXGRP != 0 or s.mode & EXOTH != 0) true else false,
            });
        }
    }

    if (self.opt.hidden) {
        try list.insert(self.allocator, 0, .{
            .name = ".",
            .kind = .directory,
            .exec = false,
        });
        try list.insert(self.allocator, 0, .{
            .name = "..",
            .kind = .directory,
            .exec = false,
        });
    }

    return list;
}

fn handleDirLong(self: *Self) !std.ArrayList(FileStatLong) {
    const d = try Dir.cwd().openDir(self.io, self.path, .{ .follow_symlinks = true, .iterate = true });
    var itr = d.iterate();

    var list: std.ArrayList(FileStatLong) = .empty;

    while (try itr.next(self.io)) |i| {
        if (!self.opt.hidden and i.name[0] == '.') continue;
        var name_buf: [std.fs.max_name_bytes:0]u8 = undefined;
        @memcpy(name_buf[0..i.name.len], i.name);
        name_buf[i.name.len] = 0;
        const stat = getstatx(d.handle, &name_buf);

        if (stat) |s| {
            try list.append(self.allocator, .{
                .name = try self.allocator.dupe(u8, i.name),
                .uname = self.getUserName(s.uid),
                .gname = self.getGroupName(s.gid),
                .kind = i.kind,
                .exec = if (s.mode & EXUSR != 0 or s.mode & EXGRP != 0 or s.mode & EXOTH != 0) true else false,
                .mode = s.mode,
                .size = try self.getSizeString(s.size),
                .nlink = s.nlink,
                .perm = buildPermString(i.kind, s.mode),
                .link = blk: {
                    if (i.kind == .sym_link) {
                        var buf: [std.fs.max_path_bytes]u8 = undefined;
                        const rc = linux.readlinkat(d.handle, @ptrCast(&name_buf), buf[3..], buf.len - 3);
                        const n = std.math.cast(usize, rc) orelse continue;
                        buf[0..3].* = "-> ".*;
                        break :blk try self.allocator.dupe(u8, buf[0 .. n + 3]);
                    } else {
                        break :blk null;
                    }
                },
            });
        }
    }

    if (self.opt.hidden) {
        const this_dir_stat = getstatx(d.handle, ".");
        const prev_dir_stat = getstatx(d.handle, "..");
        if (this_dir_stat) |dir| {
            try list.insert(self.allocator, 0, .{
                .name = try self.allocator.dupe(u8, "."),
                .uname = self.getUserName(dir.uid),
                .gname = self.getGroupName(dir.gid),
                .kind = .directory,
                .exec = false,
                .link = null,
                .mode = dir.mode,
                .nlink = dir.nlink,
                .perm = buildPermString(.directory, dir.mode),
                .size = try self.getSizeString(dir.size),
            });
        }
        if (prev_dir_stat) |dir| {
            try list.insert(self.allocator, 0, .{
                .name = try self.allocator.dupe(u8, ".."),
                .uname = self.getUserName(dir.uid),
                .gname = self.getGroupName(dir.gid),
                .kind = .directory,
                .exec = false,
                .link = null,
                .mode = dir.mode,
                .nlink = dir.nlink,
                .perm = buildPermString(.directory, dir.mode),
                .size = try self.getSizeString(dir.size),
            });
        }
    }

    return list;
}

fn getSizeString(self: *Self, size: u64) ![]const u8 {
    const suffixes = [_][]const u8{ "B", "K", "M", "G", "T", "P" };
    var value: f64 = @floatFromInt(size);
    var i: usize = 0;
    while (value >= 1024 and i < suffixes.len) : (i += 1) {
        value /= 1024;
    }
    var buf: [256]u8 = undefined;
    if (i == 0) {
        return self.allocator.dupe(u8, try std.fmt.bufPrint(&buf, "{d}{s}", .{ size, suffixes[i] }));
    } else {
        return self.allocator.dupe(u8, try std.fmt.bufPrint(&buf, "{d}{s}", .{ std.math.ceil(value), suffixes[i] }));
    }
}

pub fn deinit(self: *Self, list: *std.ArrayList(FileStatLong)) void {
    for (list.items) |i| {
        self.allocator.free(i.name);
        if (i.link) |link| {
            self.allocator.free(link);
        }
    }

    list.clearAndFree(self.allocator);
}
