const Self = @This();

const std = @import("std");
const Io = std.Io;
const File = Io.File;
const Dir = Io.Dir;
const linux = std.os.linux;
const posix = std.posix;
const Allocator = std.mem.Allocator;

const RDUSR = 0o400;
const WRUSR = 0o200;
const EXUSR = 0o100;
const RDGRP = 0o040;
const WRGRP = 0o020;
const EXGRP = 0o010;
const RDOTH = 0o004;
const WROTH = 0o002;
const EXOTH = 0o001;

const SUID   = 0o4000;
const SGID   = 0o2000;
const STICKY = 0o1000;

pub const FileStats = struct {
    name: []const u8,
    username: []const u8,
    groupname: []const u8,
    link: ?[]const u8,
    kind: File.Kind,
    mode: u16,
    size: u64,
    uid: linux.uid_t,
    gid: linux.gid_t,
    nlink: u32,
    perm: [10]u8,
};

const Statx = struct {
    mode: u16,
    size: u64,
    uid: linux.uid_t,
    gid: linux.gid_t,
    nlink: u32,
};

path: []const u8,
kind: File.Kind,
io: Io,
allocator: Allocator,

pub fn init(path: []const u8, stat: File.Stat, io: Io, allocator: Allocator) Self {
    return .{
        .path = path,
        .kind = stat.kind,
        .io = io,
        .allocator = allocator,
    };
}

pub fn printlist(self: Self, stdout: *Io.Writer) !void {
    if (self.kind == .directory) {
        var list = try self.handleDir();
        var max_width: usize = 0;
        var max_user_width: usize = 0;
        var max_group_width: usize = 0;
        var max_pwidth: usize = 0;
        for (list.items) |i| {
            const width = std.fmt.count("{d}", .{i.size});
            const user_width = std.fmt.count("{s}", .{i.username});
            const group_width = std.fmt.count("{s}", .{i.groupname});
            const pwidth = std.fmt.count("{s}", .{i.name});
            if (width > max_width) max_width = width;
            if (user_width > max_user_width) max_user_width = user_width;
            if (group_width > max_group_width) max_group_width = group_width;
            if (pwidth > max_pwidth) max_pwidth = pwidth;
        }

        for (list.items) |i| {

            try stdout.print("\x1b[36m{[perm]s} \x1b[32m{[user]s: <[uwidth]} \x1b[33m{[group]s: <[gwidth]} \x1b[34m{[size]d:>[width]} \x1b[35m{[name]s} \x1b[36m{[link]s}\n", .{
                .perm = i.perm,
                .user = i.username,
                .uwidth = max_user_width,
                .group = i.groupname,
                .gwidth = max_group_width,
                .size = i.size,
                .width = max_width,
                .name = i.name,
                .link = i.link orelse ""
            });
        }

        self.deinit(&list);
    } else {
        const file = try self.handleFile();
        if (file) |f| {
            const width = std.fmt.count("{d}", .{f.size});
            const uwidth = std.fmt.count("{s}", .{f.username});
            const gwidth = std.fmt.count("{s}", .{f.groupname});

            try stdout.print("\x1b[36m{[perm]s} \x1b[32m{[user]s: <[uwidth]} \x1b[33m{[group]s: <[gwidth]} \x1b[34m{[size]d:>[width]} \x1b[35m{[name]s:<5} \x1b[36m{[link]s}\n", .{
                .perm = f.perm,
                .user = f.username,
                .uwidth = uwidth,
                .group = f.groupname,
                .gwidth = gwidth,
                .size = f.size,
                .width = width,
                .name = f.name,
                .link = f.link orelse "",
            });
            self.allocator.free(f.name);
            self.allocator.free(f.username);
            self.allocator.free(f.groupname);
            if (f.link) |link| self.allocator.free(link);
        }
    }
}

fn getstatx(path: [*:0]const u8) ?Statx {
    var statx: linux.Statx = undefined;
    const errno = linux.errno(linux.statx(posix.AT.FDCWD, path, posix.AT.SYMLINK_NOFOLLOW, linux.STATX.BASIC_STATS, &statx));
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

fn handleFile(self: Self) !?FileStats {
    const path = try std.fmt.allocPrintSentinel(self.allocator, "{s}", .{self.path}, 0);
    const file = getstatx(path);
    self.allocator.free(path);
    if (file) |f| {
        const pw = std.c.getpwuid(f.uid);
        const gr = std.c.getgrgid(f.gid);
        return .{
            .name = try self.allocator.dupe(u8, self.path),
            .username = try self.allocator.dupe(u8, std.mem.span(pw.?.name.?)),
            .groupname = try self.allocator.dupe(u8, std.mem.span(gr.?.name.?)),
            .kind = self.kind,
            .mode = f.mode,
            .size = f.size,
            .nlink = f.nlink,
            .uid = f.uid,
            .gid = f.gid,
            .perm = buildPermString(self.kind, f.mode),
            .link = blk: {
                if (self.kind == .sym_link) {
                    var buf: [std.fs.max_path_bytes]u8 = undefined;
                    const n = try Dir.readLink(Dir.cwd(), self.io, self.path, buf[3..]);
                    buf[0..3].* = "-> ".*;
                    break :blk try self.allocator.dupe(u8, buf[0..n + 3]);
                } else {
                    break :blk null;
                }
            }
        };
    } else {
        return null;
    }
}

fn handleDir(self: Self) !std.ArrayList(FileStats) {
    const d = try Dir.cwd().openDir(self.io, self.path, .{ .follow_symlinks = true, .iterate = true });
    var itr = d.iterate();

    var list: std.ArrayList(FileStats) = .empty;

    while (try itr.next(self.io)) |i| {
        const path = try std.fmt.allocPrintSentinel(self.allocator, "{s}/{s}", .{ self.path, i.name }, 0);
        const stat = getstatx(path);
        self.allocator.free(path);

        if (stat) |s| {
        const pw = std.c.getpwuid(s.uid);
        const gr = std.c.getgrgid(s.gid);
            try list.append(self.allocator, .{
                .name = try self.allocator.dupe(u8, i.name),
                .username = try self.allocator.dupe(u8, std.mem.span(pw.?.name.?)),
                .groupname = try self.allocator.dupe(u8, std.mem.span(gr.?.name.?)),
                .kind = i.kind,
                .mode = s.mode,
                .size = s.size,
                .nlink = s.nlink,
                .uid = s.uid,
                .gid = s.gid,
                .perm = buildPermString(i.kind, s.mode),
                .link = blk: {
                    if (i.kind == .sym_link) {
                        var buf: [std.fs.max_path_bytes]u8 = undefined;
                        const n = try Dir.readLink(d, self.io, i.name, buf[3..]);
                        buf[0..3].* = "-> ".*;
                        break :blk try self.allocator.dupe(u8, buf[0..n + 3]);
                    } else {
                        break :blk null;
                    }
                }
            });
        }
    }

    return list;
}

pub fn deinit(self: Self, list: *std.ArrayList(FileStats)) void {
    for (list.items) |i| {
        self.allocator.free(i.name);
        self.allocator.free(i.username);
        self.allocator.free(i.groupname);
        if (i.link) |link| {
            self.allocator.free(link);
        }
    }

    list.clearAndFree(self.allocator);
}
