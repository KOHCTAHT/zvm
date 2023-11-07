const std = @import("std");
const w = std.os.windows;

const MountPointData = extern struct {
    reparseTag: u32,
    reparseDataLength: u16,
    reserved: u16 = 0,
    substituteNameOffset: u16 = 0,
    substituteNameLength: u16,
    printNameOffset: u16 = 0,
    printNameLength: u16 = 0,
};

// SymLink:
// TODO: GetVolumeInformation(dest_path) and (link_path) and check that they're on NTFS
//
// link_path mast be an empty directory or non-existent
//
pub fn makeMountPoint(link_path: []const u8, dest_path: []const u8) !void {
    std.fs.makeDirAbsolute(link_path) catch |err| if (err != error.PathAlreadyExists) return err;

    const link_path_wide = try w.sliceToPrefixedFileW(null, link_path);
    const dest_path_wide = try w.sliceToPrefixedFileW(null, dest_path);

    const handle = try w.OpenFile(link_path_wide.span(), .{ .access_mask = w.GENERIC_WRITE, .creation = w.FILE_OPEN, .follow_symlinks = false, .filter = .dir_only, .io_mode = .blocking });

    const buf_len: u16 = @intCast(@sizeOf(MountPointData) + dest_path_wide.len * 2 + 4);

    const mpdata: MountPointData = .{
        .reparseTag = w.IO_REPARSE_TAG_MOUNT_POINT,
        .reparseDataLength = buf_len - 8,
        .substituteNameOffset = 0,
        .substituteNameLength = @intCast(dest_path_wide.len * 2),
        .printNameOffset = @intCast(dest_path_wide.len * 2 + 2),
        .printNameLength = 0,
    };
    var in_buffer: [w.MAX_PATH]u8 = undefined;

    @memcpy(in_buffer[0..@sizeOf(MountPointData)], std.mem.asBytes(&mpdata));
    @memcpy(in_buffer[@sizeOf(MountPointData)..][0 .. dest_path_wide.len * 2], @as([*]const u8, std.mem.asBytes(&dest_path_wide.data)));

    // Four 00 bytes: 1) 00 00 to zero terminate substituteName 2) 00 00 for empty printName
    @memset(in_buffer[buf_len - 4 ..][0..4], 0);
    try w.DeviceIoControl(handle, w.FSCTL_SET_REPARSE_POINT, in_buffer[0..buf_len], null);
}

pub fn readMountPoint(link_path: []const u8, buffer: []u8) ![]const u8 {
    @setRuntimeSafety(false);
    const link_path_wide = try w.sliceToPrefixedFileW(null, link_path);

    const handle = try w.OpenFile(link_path_wide.span(), .{ .access_mask = w.GENERIC_READ, .creation = w.FILE_OPEN, .follow_symlinks = false, .filter = .dir_only, .io_mode = .blocking });

    var out_buffer: [@sizeOf(MountPointData) + w.MAX_PATH * 2]u8 align(@alignOf(MountPointData)) = undefined;

    try w.DeviceIoControl(handle, w.FSCTL_GET_REPARSE_POINT, null, out_buffer[0..]);
    const mp_ptr: *const MountPointData = @ptrCast(&out_buffer[0]);
    const path_ptr: [*]const u16 = @ptrCast(&mp_ptr.printNameLength);
    const subst_name = path_ptr[1 + mp_ptr.substituteNameOffset ..][0 .. mp_ptr.substituteNameLength / 2];
    const prefix = w.getNamespacePrefix(u16, subst_name);
    const offset: usize = if (prefix == .nt) 4 else 0;
    const subst_name_len = try std.unicode.utf16leToUtf8(buffer[0..], subst_name[offset..]);
    return buffer[0..subst_name_len];
}
