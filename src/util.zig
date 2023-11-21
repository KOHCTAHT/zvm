const std = @import("std");
const builtin = @import("builtin");

const http_client = @import("http_client.zig");
const VersionIndex = @import("version_index.zig").VersionIndex;

const index_url = "https://ziglang.org/download/index.json";

pub fn downloadVersionIndex(allocator: std.mem.Allocator) !VersionIndex {
    const index_json = try http_client.getContent(allocator, index_url);
    defer allocator.free(index_json);

    return VersionIndex.fromJson(allocator, index_json);
}

pub fn dump(s: []const u8) void {
    var j: usize = 0;
    while (j < s.len) : (j += 16) {
        for (0..16) |i| {
            if (i + j < s.len) {
                std.debug.print("{x:0<2} ", .{s[i + j]});
            } else {
                std.debug.print("   ", .{});
            }
        }
        for (0..16) |i| {
            if (i + j >= s.len) break;
            std.debug.print("{c} ", .{s[i + j]});
        }
        std.debug.print("\n", .{});
    }
}
