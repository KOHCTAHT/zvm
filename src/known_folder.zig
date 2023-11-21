const std = @import("std");

pub fn getTempFolder(allocator: std.mem.Allocator) ![]const u8 {
    const temp_vars = [_][]const u8{ "TMPDIR", "TEMP", "TMP" };
    for (temp_vars) |temp_var| {
        return std.process.getEnvVarOwned(allocator, temp_var) catch |err| {
            if (err == error.EnvironmentVariableNotFound) continue;
            return err;
        };
    }
    return allocator.dupe(u8, "/tmp");
}

test "getTempFolder" {
    var allocator = std.testing.allocator;
    const temp = try getTempFolder(allocator);
    defer allocator.free(temp);
    std.debug.print("{s}\n", .{temp});
    try std.testing.expect(temp.len != 0);
}
