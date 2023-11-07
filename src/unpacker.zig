const std = @import("std");
const unzip = @import("unpacker/unzip.zig");

pub const ProgressCallback = fn (total: usize, current: usize, ctx: anytype) void;

const FileType = enum {
    unknown,
    zip,
    tar,
    tar_xz,
};

fn fileTypeFromPath(file_path: []const u8) FileType {
    if (std.ascii.endsWithIgnoreCase(file_path, ".tar")) return .tar;
    if (std.ascii.endsWithIgnoreCase(file_path, ".tar.xz")) return .tar_xz;
    if (std.ascii.endsWithIgnoreCase(file_path, ".zip")) return .zip;
    return .unknown;
}

pub fn unpackFile(allocator: std.mem.Allocator, dest_dir: std.fs.Dir, file_path: []const u8, comptime progress_callback: ?*const ProgressCallback, ctx: anytype) !void {
    var file = try std.fs.openFileAbsolute(file_path, .{});
    defer file.close();

    switch (fileTypeFromPath(file_path)) {
        .zip => try unzip.unzipToDirectory(allocator, dest_dir, file, progress_callback, ctx),
        .tar_xz => {},
        .tar => {},
        .unknown => return error.UnknownPackedFile,
    }
}

fn unpackTarball(
    gpa: std.mem.Allocator,
    reader: anytype,
    out_dir: std.fs.Dir,
    comptime compression: type,
) !void {
    var br = std.io.bufferedReaderSize(std.crypto.tls.max_ciphertext_record_len, reader);

    var decompress = try compression.decompress(gpa, br.reader());
    defer decompress.deinit();

    try std.tar.pipeToFileSystem(out_dir, decompress.reader(), .{
        .strip_components = 1,
        .mode_mode = .ignore,
    });
}

pub fn zstem(file_path: []const u8) []const u8 {
    const ext_len: usize = switch (fileTypeFromPath(file_path)) {
        .tar_xz => 6,
        .tar => 3,
        .zip => 3,
        .unknown => 0,
    };
    return std.fs.path.basename(file_path[0 .. file_path.len - ext_len]);
}
