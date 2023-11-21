const std = @import("std");
const builtin = @import("builtin");

const Self = @This();

const version_size_limit = 256;
const anchor_dir_name = "zig-current";

zig_root: []const u8 = undefined,
versions: [version_size_limit]LocalVersion = undefined,
num_versions: usize = 0,

const LocalVersion = struct {
    os: []const u8,
    arch: []const u8,
    version: []const u8,
    build_id: ?[]const u8 = null,
    buf: [64]u8 = undefined,
    buf_len: usize = 0,
    is_current: bool = false,

    fn store(self: *LocalVersion, str: []const u8) []const u8 {
        const dest = self.buf[self.buf_len..][0..str.len];
        @memcpy(dest, str);
        self.buf_len += str.len;
        return dest;
    }

    // zig fmt: off
    fn eql(self: *const LocalVersion, ver: *const LocalVersion) bool {
        return std.mem.eql(u8, self.os, ver.os)
            and std.mem.eql(u8, self.arch, ver.arch)
            and std.mem.eql(u8, self.version, ver.version)
            and std.mem.eql(u8, self.build_id orelse "", ver.build_id orelse "");
    }

    pub fn fromFilePath(self: *LocalVersion, path: []const u8) bool {
        const name = std.fs.path.basename(path);
        var it = std.mem.splitScalar(u8, name, '-');
        if (!std.mem.eql(u8, it.next().?, "zig")) return false;

        if (it.next()) |os| {
            if (it.next()) |arch| {
                if (it.next()) |version| {
                    if (name.len > self.buf.len) return false;
                    self.os = self.store(os);
                    self.arch = self.store(arch);
                    self.version = self.store(version);
                    if (it.next()) |extra_info| {
                        self.build_id = self.store(extra_info);
                    }
                    return true;
                }
            }
        }
        return false;
    }
};

pub fn init(self: *Self, zig_root: []const u8) !void {
    self.zig_root = zig_root;
    self.num_versions = 0;

    var itdir = try std.fs.openIterableDirAbsolute(zig_root, .{ .no_follow = true });
    defer itdir.close();

    var it = itdir.iterateAssumeFirstIteration();
    while (try it.next()) |entry| {
        if (self.versions[self.num_versions].fromFilePath(entry.name)) {
            if (self.num_versions >= version_size_limit) return error.TooManyLocalVersions;
            self.num_versions += 1;
        }
    }
}

pub fn initWithCurrent(self: *Self, allocator: std.mem.Allocator, zig_root: []const u8) !void {
    try self.init(zig_root);
    const cur_ver_maybe = try self.getCurrent(allocator);
    if (cur_ver_maybe) |cur_ver| {
        for (self.versions[0..self.num_versions]) |*ver| {
            if (cur_ver.eql(ver)) {
                ver.is_current = true;
            }
        }
    }
}

// zig fmt: off
pub fn isInstalled(self: Self, version: []const u8, build_id: ?[]const u8, platform: []const u8) bool {
    for (self.versions[0..self.num_versions]) |*ver| {
        if (std.mem.eql(u8, version, ver.version)
            and platform.len == (ver.os.len + ver.arch.len + 1)
            and std.mem.startsWith(u8, platform, ver.arch)
            and platform[ver.arch.len] == '-'
            and std.mem.eql(u8, platform[ver.arch.len + 1 ..], ver.os)
            and std.mem.eql(u8, ver.build_id orelse "", build_id orelse ""))
        {
            return true;
        }
    }
    return false;
}
// zig fmt: on
pub fn getAll(self: *const Self) []const LocalVersion {
    return self.versions[0..self.num_versions];
}

pub fn makeCurrent(self: *Self, allocator: std.mem.Allocator, dir_name: []const u8) !void {
    const link_path = try std.fs.path.join(allocator, &.{ self.zig_root, anchor_dir_name });
    defer allocator.free(link_path);

    const dest_path = try std.fs.path.join(allocator, &.{ self.zig_root, dir_name });
    defer allocator.free(dest_path);

    switch (builtin.os.tag) {
        .windows => try @import("winapi.zig").makeMountPoint(link_path, dest_path),
        else => @compileError("Not implemented"),
    }
}

pub fn getCurrent(self: *Self, allocator: std.mem.Allocator) !?LocalVersion {
    const link_path = try std.fs.path.join(allocator, &.{ self.zig_root, anchor_dir_name });
    defer allocator.free(link_path);

    var buffer: [std.os.PATH_MAX]u8 = undefined;
    const real_path = switch (builtin.os.tag) {
        .windows => @import("winapi.zig").readMountPoint(link_path, &buffer),
        else => @compileError("Not implemented"),
    } catch |err| {
        if (err == error.FileNotFound) return null;
        return err;
    };
    var version: LocalVersion = undefined;
    if (version.fromFilePath(real_path)) return version;
    return null;
}
