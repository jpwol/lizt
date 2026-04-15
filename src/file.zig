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

const SUID = 0o4000;
const SGID = 0o2000;
const STICKY = 0o1000;

pub const FileStats = struct {
    name: []const u8,
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
uname_cache: std.AutoHashMap(linux.uid_t, []const u8),
grname_cache: std.AutoHashMap(linux.gid_t, []const u8),
kind: File.Kind,
io: Io,
allocator: Allocator,

pub fn init(path: []const u8, stat: File.Kind, io: Io, allocator: Allocator) Self {
    return .{
        .path = path,
        .kind = stat,
        .io = io,
        .allocator = allocator,
        .uname_cache = .init(allocator),
        .grname_cache = .init(allocator),
    };
}

pub fn printlist(self: *Self, stdout: *Io.Writer) !void {
    if (self.kind == .directory) {
        var list = try self.handleDir();
        var max_width: usize = 0;
        var max_user_width: usize = 0;
        var max_group_width: usize = 0;
        var max_pwidth: usize = 0;
        for (list.items) |i| {
            const uname = self.getUserName(i.uid);
            const gname = self.getGroupName(i.gid);
            var n = i.size;
            var width: usize = 1;
            while (n >= 10) : (n /= 10) width += 1;
            if (width > max_width) max_width = width;
            if (uname.len > max_user_width) max_user_width = uname.len;
            if (gname.len > max_group_width) max_group_width = gname.len;
            if (i.name.len > max_pwidth) max_pwidth = i.name.len;
        }

        for (list.items) |i| {
            try stdout.print("│ \x1b[36m{[perm]s} │ \x1b[32m{[user]s: <[uwidth]} {[group]s: <[gwidth]} │ \x1b[34m{[size]d:>[width]} │ \x1b[33m{[name]s} \x1b[36m{[link]s}\n", .{
                .perm = i.perm,
                .user = self.getUserName(i.uid),
                .uwidth = max_user_width,
                .group = self.getGroupName(i.gid),
                .gwidth = max_group_width,
                .size = i.size,
                .width = max_width,
                .name = i.name,
                .link = i.link orelse "",
            });
        }

        self.deinit(&list);
    } else {
        const file = try self.handleFile();
        if (file) |f| {
            const width = std.fmt.count("{d}", .{f.size});
            const uwidth = self.getUserName(f.uid).len;
            const gwidth = self.getGroupName(f.gid).len;

            try stdout.print("\x1b[36m{[perm]s} \x1b[32m{[user]s: <[uwidth]} {[group]s: <[gwidth]} \x1b[34m{[size]d:>[width]} \x1b[35m{[name]s:<5} \x1b[36m{[link]s}\n", .{
                .perm = f.perm,
                .user = self.getUserName(f.uid),
                .uwidth = uwidth,
                .group = self.getGroupName(f.gid),
                .gwidth = gwidth,
                .size = f.size,
                .width = width,
                .name = f.name,
                .link = f.link orelse "",
            });
            self.allocator.free(f.name);
            if (f.link) |link| self.allocator.free(link);
        }
    }
}

fn getstatx(handle: linux.fd_t, path: [:0]const u8) ?Statx {
    var statx: linux.Statx = undefined;
    const mask = linux.STATX{
        .MODE = true,
        .NLINK = true,
        .UID = true,
        .GID = true,
        .MTIME = true,
        .SIZE = true,
    };
    const errno = linux.errno(linux.statx(handle, @ptrCast(path), posix.AT.SYMLINK_NOFOLLOW | posix.AT.STATX_SYNC_AS_STAT | posix.AT.NO_AUTOMOUNT, mask, &statx));
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

fn handleFile(self: *Self) !?FileStats {
    var path_buf: [std.fs.max_path_bytes:0]u8 = undefined;
    @memcpy(path_buf[0..self.path.len], self.path);
    path_buf[self.path.len] = 0;
    const file = getstatx(posix.AT.FDCWD, &path_buf);
    if (file) |f| {
        return .{
            .name = try self.allocator.dupe(u8, self.path),
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

fn handleDir(self: *Self) !std.ArrayList(FileStats) {
    const d = try Dir.cwd().openDir(self.io, self.path, .{ .follow_symlinks = true, .iterate = true });
    var itr = d.iterate();

    var list: std.ArrayList(FileStats) = .empty;

    while (try itr.next(self.io)) |i| {
        var name_buf: [std.fs.max_name_bytes:0]u8 = undefined;
        @memcpy(name_buf[0..i.name.len], i.name);
        name_buf[i.name.len] = 0;
        const stat = getstatx(d.handle, &name_buf);

        if (stat) |s| {
            try list.append(self.allocator, .{
                .name = try self.allocator.dupe(u8, i.name),
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
                        const rc = linux.readlinkat(d.handle, @ptrCast(&name_buf), buf[3..], buf.len - 3);
                        const n = std.math.cast(usize, rc) orelse continue;
                        // const n = try Dir.readLink(d, self.io, i.name, buf[3..]);
                        buf[0..3].* = "-> ".*;
                        break :blk try self.allocator.dupe(u8, buf[0 .. n + 3]);
                    } else {
                        break :blk null;
                    }
                },
            });
        }
    }

    return list;
}

pub fn deinit(self: *Self, list: *std.ArrayList(FileStats)) void {
    for (list.items) |i| {
        self.allocator.free(i.name);
        if (i.link) |link| {
            self.allocator.free(link);
        }
    }

    list.clearAndFree(self.allocator);
}
