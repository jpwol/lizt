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

pub const FileStats = struct {
    name: []const u8,
    kind: File.Kind,
    mode: u16,
    size: u64,
    uid: linux.uid_t,
    gid: linux.gid_t,
    nlink: u32,
    perm: [10]u8
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

pub fn getstatx(path: [*:0]const u8) ?Statx {
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
    buf[0] = switch(kind) {
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
    buf[3] = if (mode & EXUSR != 0) 'x' else '-';
    buf[4] = if (mode & RDGRP != 0) 'r' else '-';
    buf[5] = if (mode & WRGRP != 0) 'w' else '-';
    buf[6] = if (mode & EXGRP != 0) 'x' else '-';
    buf[7] = if (mode & RDOTH != 0) 'r' else '-';
    buf[8] = if (mode & WROTH != 0) 'w' else '-';
    buf[9] = if (mode & EXOTH != 0) 'x' else '-';

    return buf;
}

pub fn buildDirList(self: Self) !std.ArrayList(FileStats) {
    const d = try Dir.cwd().openDir(self.io, self.path, .{ .follow_symlinks = false, .iterate = true });
    var itr = d.iterate();

    var list: std.ArrayList(FileStats) = .empty;

    while (try itr.next(self.io)) |i| {
        const path = try std.fmt.allocPrintSentinel(self.allocator, "{s}/{s}", .{self.path, i.name}, 0);
        const stat = getstatx(path);
        self.allocator.free(path);
        
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
            });
        }
    }

    return list;
}

pub fn deinit(self: Self, list: *std.ArrayList(FileStats)) void {
    for (list.items) |i| {
        self.allocator.free(i.name);
    }

    list.clearAndFree(self.allocator);
}
