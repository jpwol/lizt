const Self = @This();

const std = @import("std");
const Io = std.Io;
const File = Io.File;
const Dir = Io.Dir;
const linux = std.os.linux;
const posix = std.posix;
const Allocator = std.mem.Allocator;

pub const FileStats = struct {
    name: []const u8,
    kind: File.Kind,
    mode: u16,
    size: u64,
    uid: linux.uid_t,
    gid: linux.gid_t,
    nlink: u32,
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

pub fn buildDirList(self: Self) !std.ArrayList(FileStats) {
    var d = try Dir.cwd().openDir(self.io, self.path, .{ .follow_symlinks = false, .iterate = true });
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
