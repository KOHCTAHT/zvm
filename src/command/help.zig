const std = @import("std");
const Context = @import("../command.zig").Context;

const usage: []const u8 =
    \\ Usage: 
    \\    zvm install <version> [<arch-os>]
    \\    zvm uninstall <version> [<arch-os>]
    \\    zvm use <version> [<arch-os>]
    \\    zvm list [-r|--remote]
    \\    zvm cache [purge]
    \\    zvm version
;

pub fn execute(self: @This(), ctx: *const Context) !void {
    _ = self;
    try ctx.stdout.writeAll(usage);
}
