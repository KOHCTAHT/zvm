const std = @import("std");
const Context = @import("../command.zig").Context;

version: ?[]const u8 = null,
arch: ?[]const u8 = null,

pub fn execute(self: @This(), ctx: *const Context) !void {
    _ = self;
    try ctx.stdout.writeAll("not implemented\n");
}
