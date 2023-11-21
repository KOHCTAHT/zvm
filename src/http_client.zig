const std = @import("std");
const Allocator = std.mem.Allocator;

const MB: usize = 1024 * 1024;
const download_buf_size = 10 * MB;

pub fn getContent(allocator: Allocator, url: []const u8) ![]u8 {
    const uri = try std.Uri.parse(url);

    const headers: std.http.Headers = .{ .allocator = allocator };

    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();

    var request = try client.open(.GET, uri, headers, .{});
    defer request.deinit();

    try request.send(.{});
    try request.wait();

    const reader = request.reader();
    const content = try reader.readAllAlloc(allocator, download_buf_size);
    return content;
}

pub fn getHeaders(allocator: Allocator, url: []const u8) ![]std.http.Field {
    const uri = try std.Uri.parse(url);

    const headers: std.http.Headers = .{ .allocator = allocator };

    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();

    var request = try client.open(.HEAD, uri, headers, .{});
    defer request.deinit();

    try request.send(.{});
    try request.wait();

    const headers_clone = try allocator.alloc(std.http.Field, request.response.headers.list.items.len);
    for (headers_clone, request.response.headers.list.items) |*dest, src| {
        dest.*.name = try allocator.dupe(@TypeOf(src.name[0]), src.name);
        dest.*.value = try allocator.dupe(@TypeOf(src.name[0]), src.value);
    }
    return headers_clone;
}

pub fn downloadFile(allocator: Allocator, url: []const u8, fwriter: std.fs.File.Writer) !void {
    const uri = try std.Uri.parse(url);

    const headers: std.http.Headers = .{ .allocator = allocator };

    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();

    var request = try client.open(.GET, uri, headers, .{});
    defer request.deinit();

    try request.send(.{});
    try request.wait();

    const reader = request.reader();
    var buffer: [download_buf_size]u8 = undefined;
    while (true) {
        const size = try reader.readAll(&buffer);
        try fwriter.writeAll(buffer[0..size]);
        std.debug.print(".", .{});
        if (size < buffer.len) break;
    }
}

test "http getContent" {
    var allocator = std.testing.allocator;
    const index = try getContent(allocator, "https://ziglang.org/download/index.json");
    defer allocator.free(index);
    std.debug.print("{s}\n", .{index});
}

test "http getHeaders" {
    const stderr = std.io.getStdErr().writer();
    var allocator = std.testing.allocator;
    const headers = try getHeaders(allocator, "https://ziglang.org/download/index.json");
    defer allocator.free(headers);

    for (headers) |h| {
        stderr.print("{s}: {s}\n", .{ h.name, h.value }) catch return;
        allocator.free(h.name);
        allocator.free(h.value);
    }
}
