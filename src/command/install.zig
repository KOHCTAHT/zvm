const builtin = @import("builtin");
const std = @import("std");

const http_client = @import("../http_client.zig");
const known_folder = @import("../known_folder.zig");
const LocalVersions = @import("../local_versions.zig");
const unpacker = @import("../unpacker.zig");
const util = @import("../util.zig");
const winapi = @import("../winapi.zig");
const Context = @import("../command.zig").Context;

const Self = @This();

version: ?[]const u8 = null,
platform: ?[]const u8 = null,

const native_platform = std.fmt.comptimePrint("{s}-{s}", .{ @tagName(builtin.cpu.arch), @tagName(builtin.os.tag) });

pub fn execute(self: Self, ctx: *const Context) !void {
    const platform = self.platform orelse native_platform;

    var local_ver: LocalVersions = .{};
    local_ver.init(ctx.zig_root) catch |err| {
        if (err == error.FileNotFound) {
            try ctx.stdout.print("zig root folder \"{s}\" not found\n", .{ctx.zig_root});
            return;
        }
        return err;
    };

    const is_master = std.mem.eql(u8, self.version.?, "master");

    if (!is_master and local_ver.isInstalled(self.version.?, null, platform)) {
        return error.AlreadyInstalled;
    }

    var ver_index = try util.downloadVersionIndex(ctx.allocator);
    defer ver_index.deinit();

    if (is_master) {
        const master_ver = try ver_index.getVersionInfo("master");
        std.debug.print("master ver: {?s}  plat:{s}\n", .{ master_ver.version, platform });
        if (local_ver.isInstalled(master_ver.version.?, master_ver.build_id, platform)) {
            return error.AlreadyInstalled;
        }
    }

    const artefact = try ver_index.getArtefact(self.version.?, platform);

    var temp_path = try known_folder.getTempFolder(ctx.allocator);
    defer ctx.allocator.free(temp_path);

    var temp_dir = try std.fs.openDirAbsolute(temp_path, .{});
    defer temp_dir.close();

    const dw_file_name = std.fs.path.basename(artefact.tarball);
    var dw_file = try temp_dir.createFile(dw_file_name, .{});
    defer dw_file.close();
    var writer = dw_file.writer();

    try ctx.stdout.print("Downloading {s}{c}{s}\n", .{ temp_path, std.fs.path.sep, dw_file_name });
    try http_client.downloadFile(ctx.allocator, artefact.tarball, writer);
    defer temp_dir.deleteFile(dw_file_name) catch {};

    var dw_file_path = try std.fs.path.join(ctx.allocator, &.{ temp_path, dw_file_name });
    defer ctx.allocator.free(dw_file_path);

    std.debug.print("\nzig_root: {s}\n", .{ctx.zig_root});

    var dest_dir = try std.fs.openDirAbsolute(ctx.zig_root, .{});
    defer dest_dir.close();

    try unpacker.unpackFile(ctx.allocator, dest_dir, dw_file_path, progressCallback, ctx);

    try local_ver.makeCurrent(ctx.allocator, unpacker.zstem(dw_file_name));
}

const ansi_hide_cursor = "\x1b[?25l";
const ansi_show_cursor = "\x1b[?25h";

fn progressCallback(total: usize, current: usize, ctx: anytype) void {
    if (current == 0) {
        ctx.stdout.print(ansi_hide_cursor ++ "\nUnpacking {} files to zig_root\n", .{total}) catch unreachable;
    } else {
        var buffer: [128]u8 = undefined;
        var line = std.fmt.bufPrint(buffer[0..], "\r {: >7}/{}", .{ current, total }) catch unreachable;
        ctx.stdout.writeAll(line) catch unreachable;
        if (current == total)
            ctx.stdout.writeAll(ansi_show_cursor) catch unreachable;
    }
}
