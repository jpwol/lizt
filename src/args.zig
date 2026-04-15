const std = @import("std");

const MAX_ARGS: usize = 64;

const ArgV = struct {
    argv: [MAX_ARGS][*:0]const u8,
    opt: [MAX_ARGS][*:0]const u8,

    pub fn init(args: std.process.Args) ArgV {
         
    }
};
