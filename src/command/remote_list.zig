const std = @import("std");
const util = @import("../util.zig");
const Context = @import("../command.zig").Context;

pub fn execute(self: @This(), ctx: *const Context) !void {
    _ = self;
    var ver_index = try util.downloadVersionIndex(ctx.allocator);
    defer ver_index.deinit();

    var ver_info = try ver_index.getVersionInfo("master");
    try ctx.stdout.print("Available versions:\n" ++
        " master\t(version: {?s}-{?s}  date: {?s})\n", .{ ver_info.version, ver_info.build_id, ver_info.date });

    ver_index.forEachVersion(printVersion, ctx.stdout);
}

fn printVersion(ver: []const u8, stdout: anytype) void {
    if (std.mem.eql(u8, ver, "master")) return;
    stdout.print(" {s}\n", .{ver}) catch unreachable;
}
