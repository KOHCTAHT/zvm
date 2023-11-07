const std = @import("std");
const Context = @import("../command.zig").Context;
const LocalVersions = @import("../local_versions.zig");

pub fn execute(self: @This(), ctx: *const Context) !void {
    _ = self;
    var local_ver: LocalVersions = .{};
    local_ver.initWithCurrent(ctx.allocator, ctx.zig_root) catch |err| {
        if (err == error.FileNotFound) {
            try ctx.stdout.print("zig root folder \"{s}\" not found\n", .{ctx.zig_root});
            return;
        }
        return err;
    };

    try ctx.stdout.print("Installed versions:\n", .{});
    var buffer: [4096]u8 = undefined;
    for (local_ver.getAll()) |ver| {
        const fullver = if (ver.build_id) |build_id| join(ver.version, build_id, &buffer) else ver.version;
        const is_current = if (ver.is_current) "  * " else "    ";
        ctx.stdout.print("{s}{s}  {s}-{s}\n", .{ is_current, fullver, ver.os, ver.arch }) catch unreachable;
    }
}

fn join(s1: []const u8, s2: []const u8, buffer: []u8) []const u8 {
    @memcpy(buffer[0..s1.len], s1);
    buffer[s1.len] = '-';
    @memcpy(buffer[s1.len + 1 ..][0..s2.len], s2);
    return buffer[0 .. s1.len + s2.len + 1];
}
