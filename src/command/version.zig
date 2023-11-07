const std = @import("std");
const Context = @import("../command.zig").Context;

pub fn execute(self: @This(), ctx: *const Context) !void {
    _ = self;
    try ctx.stdout.writeAll(@import("../zvm.zig").VERSION ++ "\n");
}
