const std = @import("std");
const config = @import("config.zig");
const command = @import("command.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        if (gpa.deinit() != .ok) {
            std.debug.print("leak detected\n", .{});
        }
    }
    const allocator = gpa.allocator();

    const conf = try config.load(allocator);
    defer conf.deinit(allocator);

    const ctx: command.Context = .{
        .allocator = allocator,
        .stdout = std.io.getStdOut().writer(),
        .zig_root = conf.zig_root.?,
    };
    const cmd = try command.fromCommandLineArgs(allocator);
    try cmd.execute(&ctx);
    defer cmd.deinit(allocator);
}
