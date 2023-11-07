const std = @import("std");

pub const VersionIndex = struct {
    json: std.json.Parsed(std.json.Value),

    pub fn fromJson(allocator: std.mem.Allocator, json: []const u8) !VersionIndex {
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{ .ignore_unknown_fields = true });
        return .{ .json = parsed };
    }

    pub fn deinit(self: VersionIndex) void {
        self.json.deinit();
    }

    pub fn getVersionInfo(self: VersionIndex, version: []const u8) !VersionInfo {
        const version_list = self.json.value.object;
        if (version_list.get(version)) |json_ver| {
            return VersionInfo.fromValue(json_ver);
        }
        return error.NotFound;
    }

    pub fn getArtefact(self: VersionIndex, version: []const u8, platform: []const u8) !Artefact {
        const version_list = self.json.value.object;
        if (version_list.get(version)) |json_ver| {
            if (json_ver.object.get(platform)) |art| {
                return Artefact.fromValue(art);
            }
        }
        return error.NotFound;
    }

    pub fn forEachVersion(self: VersionIndex, comptime callback: fn (ver: []const u8, param: anytype) void, param: anytype) void {
        const version_list = self.json.value.object;
        for (version_list.keys()) |version| {
            callback(version, param);
        }
    }
};

pub const VersionInfo = struct {
    version: ?[]const u8,
    build_id: ?[]const u8,
    docs: ?[]const u8,
    std_docs: ?[]const u8,
    date: ?[]const u8,
    pub fn fromValue(value: std.json.Value) !VersionInfo {
        const version_str = if (value.object.get("version")) |j| j.string else "";
        const dash_index = std.mem.indexOfScalar(u8, version_str, '-');
        return .{
            .version = if (dash_index) |di| version_str[0..di] else version_str,
            .build_id = if (dash_index) |di| version_str[di + 1 ..] else null,
            .docs = if (value.object.get("docs")) |j| j.string else "",
            .std_docs = if (value.object.get("stdDocs")) |j| j.string else "",
            .date = if (value.object.get("date")) |j| j.string else "",
        };
    }
};

pub const Artefact = struct {
    tarball: []const u8,
    shasum: []const u8,
    size: usize,

    pub fn fromValue(value: std.json.Value) !Artefact {
        return .{
            .tarball = if (value.object.get("tarball")) |j| j.string else "",
            .shasum = if (value.object.get("shasum")) |j| j.string else "",
            .size = try std.fmt.parseInt(usize, value.object.get("size").?.string, 10),
        };
    }
};
