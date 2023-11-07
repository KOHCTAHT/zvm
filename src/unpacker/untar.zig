// Taken from zig std lib
// then added long name 'L' support
//
const std = @import("std");
const assert = std.debug.assert;

pub const Options = struct {
    /// Number of directory levels to skip when extracting files.
    strip_components: u32 = 0,
    /// How to handle the "mode" property of files from within the tar file.
    mode_mode: ModeMode = .executable_bit_only,

    const ModeMode = enum {
        /// The mode from the tar file is completely ignored. Files are created
        /// with the default mode when creating files.
        ignore,
        /// The mode from the tar file is inspected for the owner executable bit
        /// only. This bit is copied to the group and other executable bits.
        /// Other bits of the mode are left as the default when creating files.
        executable_bit_only,
    };
};

pub const Header = struct {
    bytes: [512]u8 = undefined,

    pub const FileType = enum(u8) {
        regular_file = '0',
        hard_link = '1',
        symbolic_link = '2',
        character_special = '3',
        block_special = '4',
        directory = '5',
        fifo = '6',
        contiguous = '7',
        global_extended_header = 'g',
        extended_header = 'x',
        long_name = 'L',
        _,
    };

    pub fn fileSize(header: *const Header) !u64 {
        const raw = header.bytes[124..][0..12];
        const ltrimmed = std.mem.trimLeft(u8, raw, "0");
        const rtrimmed = std.mem.trimRight(u8, ltrimmed, " \x00");
        if (rtrimmed.len == 0) return 0;
        return std.fmt.parseInt(u64, rtrimmed, 8);
    }

    pub fn is_ustar(header: *const Header) bool {
        return std.mem.eql(u8, header.bytes[257..][0..6], "ustar\x00");
    }

    /// Includes prefix concatenated, if any.
    /// Return value may point into Header buffer, or might point into the
    /// argument buffer.
    /// TODO: check against "../" and other nefarious things
    pub fn fullFileName(header: *const Header, buffer: *[std.fs.MAX_PATH_BYTES]u8) ![]const u8 {
        const n = name(header);
        if (!is_ustar(header))
            return n;
        const p = prefix(header);
        if (p.len == 0)
            return n;
        @memcpy(buffer[0..p.len], p);
        buffer[p.len] = '/';
        @memcpy(buffer[p.len + 1 ..][0..n.len], n);
        return buffer[0 .. p.len + 1 + n.len];
    }

    pub fn name(header: *const Header) []const u8 {
        return str(header, 0, 0 + 100);
    }

    pub fn prefix(header: *const Header) []const u8 {
        return str(header, 345, 345 + 155);
    }

    pub fn fileType(header: *const Header) FileType {
        const result = @as(FileType, @enumFromInt(header.bytes[156]));
        return if (result == @as(FileType, @enumFromInt(0))) .regular_file else result;
    }

    fn str(header: *const Header, start: usize, end: usize) []const u8 {
        var i: usize = start;
        while (i < end) : (i += 1) {
            if (header.bytes[i] == 0) break;
        }
        return header.bytes[start..i];
    }
};

fn stripComponents(path: []const u8, count: u32) ![]const u8 {
    var i: usize = 0;
    var c = count;
    while (c > 0) : (c -= 1) {
        if (std.mem.indexOfScalarPos(u8, path, i, '/')) |pos| {
            i = pos + 1;
        } else {
            return error.TarComponentsOutsideStrippedPrefix;
        }
    }
    return path[i..];
}

test stripComponents {
    const expectEqualStrings = std.testing.expectEqualStrings;
    try expectEqualStrings("a/b/c", try stripComponents("a/b/c", 0));
    try expectEqualStrings("b/c", try stripComponents("a/b/c", 1));
    try expectEqualStrings("c", try stripComponents("a/b/c", 2));
}

pub fn pipeToFileSystem(dir: std.fs.Dir, reader: anytype, options: Options) !void {
    var buffer: [64 * 4096]u8 = undefined;
    var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    var header: Header = .{};
    var override_file_name: []u8 = &.{};

    while (true) {
        var size = try reader.read(&header.bytes);
        if (size == 0) break;
        if (size != header.bytes.len) return error.UnexpectedEndOfStream;

        const file_type = header.fileType();
        const file_size = try header.fileSize();
        const file_name = if (override_file_name.len == 0)
            try header.fullFileName(&path_buf)
        else
            std.mem.trimRight(u8, override_file_name, " \x00");
        override_file_name.len = 0;

        if (file_name.len == 0) break;

        switch (file_type) {
            .directory => {
                const stripped_file_name = try stripComponents(file_name, options.strip_components);
                if (stripped_file_name.len != 0) {
                    try dir.makePath(stripped_file_name);
                }
            },
            .regular_file => {
                if (std.fs.path.dirname(file_name)) |dir_name| {
                    try dir.makePath(dir_name);
                }
                var out_file = try dir.createFile(file_name, .{});
                defer out_file.close();

                var out_writer = out_file.writer();
                const rounded_file_size = std.mem.alignForward(u64, file_size, header.bytes.len);
                var offset: usize = 0;
                while (offset < rounded_file_size) {
                    const read_size = @min(rounded_file_size - offset, buffer.len);
                    size = try reader.readAll(buffer[0..read_size]);
                    if (size != read_size) return error.UnexpectedEndOfStream;

                    try out_writer.writeAll(buffer[0..size]);
                    offset += size;
                }
            },
            .long_name => {
                if (file_size > path_buf.len) return error.LongNameIsTooLong;
                size = try reader.readAll(path_buf[0..header.bytes.len]);
                if (size < file_size) return error.UnexpectedEndOfStream;
                override_file_name = path_buf[0..file_size];
            },
            else => std.debug.print("\n\n================\nfull name: {s}\nsize: {}\nis ustar: {}\nfile type: {c}\n\n", .{
                file_name,
                file_size,
                header.is_ustar(),
                header.fileType(),
            }),
        }
    }
}
