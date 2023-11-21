const std = @import("std");

const max_config_size = 64 * 1024;

pub const AppConfig = struct {
    app_dir: []const u8 = &.{},
    zig_root: ?[]const u8 = null,

    pub fn deinit(self: AppConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.app_dir);
        if (self.zig_root) |ptr|
            allocator.free(ptr);
    }
};

pub fn load(allocator: std.mem.Allocator) !AppConfig {
    const app_dir = try std.fs.getAppDataDir(allocator, "zvm");
    errdefer allocator.free(app_dir);

    var dir = try std.fs.openDirAbsolute(app_dir, .{});
    defer dir.close();

    var zig_root_maybe: ?[]const u8 = null;
    const text_or_err = dir.readFileAlloc(allocator, "config.json", max_config_size);
    if (text_or_err) |text| {
        defer allocator.free(text);

        var parsed = try std.json.parseFromSlice(AppConfig, allocator, text, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();
        if (parsed.value.zig_root) |zig_root| zig_root_maybe = try allocator.dupe(u8, zig_root);
    } else |_| {}

    if (zig_root_maybe == null) {
        zig_root_maybe = try std.fs.path.join(allocator, &.{ app_dir, "zig" });
    }

    return .{ .app_dir = app_dir, .zig_root = zig_root_maybe };
}
