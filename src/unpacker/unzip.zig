// Quick and dirty Unzip implementation.
// !!! NOT FINISHED
const std = @import("std");

const MB = 1024 * 1024;

//
// End of central directory record
//
const EndOfCDirRecord = struct {
    const size = 22; // physical size inside the file
    const signature = 0x06054b50;

    this_disk_no: u16,
    cdir_disk_no: u16,
    num_entries: u16,
    total_size: u32,
    cdir_offset: u32,

    fn findInFile(file: std.fs.File) !EndOfCDirRecord {
        var file_size = try file.getEndPos();
        if (file_size >= std.math.maxInt(u32)) {
            return error.UnsupportedZipFormat;
        }
        if (file_size < EndOfCDirRecord.size) {
            return error.NotAZipFile;
        }

        var buffer: Buffer = .{};
        var offset: u64 = if (file_size > buffer.len) file_size - buffer.len else 0;

        // TODO: while( offset > EndOfCDirRecord.size ) move offset backwards and refill buffer
        try file.seekTo(offset);
        const bytes_read = try file.readAll(&buffer.buffer);
        if (bytes_read < EndOfCDirRecord.size) return error.NotAZipFile;

        for (EndOfCDirRecord.size..bytes_read) |i| {
            const ri = bytes_read - i;
            if (buffer.readU32(ri) == EndOfCDirRecord.signature) {
                return .{
                    .this_disk_no = buffer.readU16(ri + 4),
                    .cdir_disk_no = buffer.readU16(ri + 6),
                    // we skip Number of Cdir entries on this disk @(+8)
                    .num_entries = buffer.readU16(ri + 10),
                    .total_size = buffer.readU32(ri + 12),
                    .cdir_offset = buffer.readU32(ri + 16),
                };
            }
        }
        return error.NotAZipFile;
    }
};

//
// Central Directory Entry
//
const CDirEntry = struct {
    const size = 46; // physical size inside the file
    const signature = 0x02014b50;

    total_size: usize,
    method: CompressionMethod,
    mtime: u16, // TODO: currently not used
    mdate: u16, // TODO: currently not used
    crc32: u32, // TODO: currently not used
    compressed_size: u32,
    uncompressed_size: u32,
    disk_no: u16,
    attrib: u16, // TODO: not used
    attrib_ex: u32, // TODO: what is it?
    lfh_offset: u32,
    file_name: []const u8,
    extra_field: []const u8, // TODO: currently not used
    comment: []const u8,
    extras_buf: ?[]const u8,

    fn isDir(self: *const CDirEntry) bool {
        // implemented by wild guessing of the constants - probably wrong
        return if (self.attrib_ex != 0)
            (self.attrib_ex & 0x10) != 0 or (self.attrib_ex & 0x10000) != 0
        else
            self.file_name[self.file_name.len - 1] == '/';
    }

    fn deserialize(b: *const Buffer, offset: usize) !CDirEntry {
        if (b.readU32(offset) != CDirEntry.signature) return error.BadZipFile;

        const file_name_len = b.readU16(offset + 28);
        const extra_field_len = b.readU16(offset + 30);
        const comment_len = b.readU16(offset + 32);
        const extras_size = file_name_len + extra_field_len + comment_len;

        const method: CompressionMethod = @enumFromInt(b.readU16(offset + 10));
        return .{
            .total_size = CDirEntry.size + extras_size,
            .method = method,
            .mtime = b.readU16(offset + 12),
            .mdate = b.readU16(offset + 14),
            .crc32 = b.readU32(offset + 16),
            .compressed_size = b.readU32(offset + 20),
            .uncompressed_size = b.readU32(offset + 24),
            .disk_no = b.readU16(offset + 34),
            .attrib = b.readU16(offset + 36),
            .attrib_ex = b.readU32(offset + 38),
            .lfh_offset = b.readU32(offset + 42),
            .extras_buf = null,
            .file_name = sliceFromLen(u8, file_name_len),
            .extra_field = sliceFromLen(u8, extra_field_len),
            .comment = sliceFromLen(u8, comment_len),
        };
    }

    fn deserializeExtras(self: *CDirEntry, arena: std.mem.Allocator, b: *const Buffer, offset: usize) !void {
        const extras_size = self.total_size - CDirEntry.size;
        const ptr = try arena.dupe(u8, b.buffer[offset + CDirEntry.size ..][0..extras_size]);
        self.extras_buf = ptr;
        self.file_name = ptr[0..self.file_name.len];
        self.extra_field = ptr[self.file_name.len..][0..self.extra_field.len];
        self.comment = ptr[self.file_name.len + self.extra_field.len ..][0..self.comment.len];
    }
};

// TODO
const LocalFileHeader = struct {
    const size = 30;
    const signature = 0x04034b50;
};

const CompressionMethod = enum(u16) {
    none = 0,
    shrink = 1,
    reduce_factor1 = 2,
    reduce_factor2 = 3,
    reduce_factor3 = 4,
    reduce_factor4 = 5,
    implode = 6,
    reserved7 = 7,
    deflate = 8,
    deflate64 = 9,
    implode_old_terse = 10,
    reserved11 = 11,
    bzip2 = 12,
    reserved13 = 13,
    lzma = 14,
    zstd = 93,
    mp3 = 94,
    xz = 95,
    jpeg = 96,
    wavpack = 97,
    ppmd_I_v1 = 98,
    _,
};

const Buffer = struct {
    buffer: [1 * MB]u8 = undefined,
    comptime len: usize = 1 * MB,

    fn readU16(b: *const Buffer, offset: usize) u16 {
        return std.mem.readInt(u16, b.buffer[offset..][0..2], .little);
    }
    fn readU32(b: *const Buffer, offset: usize) u32 {
        return std.mem.readInt(u32, b.buffer[offset..][0..4], .little);
    }
    fn readU64(b: *const Buffer, offset: usize) u64 {
        return std.mem.readInt(u64, b.buffer[offset..][0..8], .little);
    }
};

fn writeReaderToFileSystem(dest_dir: std.fs.Dir, file_name: []const u8, reader: anytype, write_size: usize) !void {
    var buffer: [1 * MB]u8 = undefined;

    //    if (std.fs.path.dirname(file_name)) |dir_name| {
    //        try dest_dir.makePath(dir_name);
    //    }
    const out_file = try dest_dir.createFile(file_name, .{});
    defer out_file.close();

    const out_writer = out_file.writer();
    var offset: usize = 0;
    while (offset < write_size) {
        const read_size = @min(write_size - offset, buffer.len);
        const size = try reader.readAll(buffer[0..read_size]);
        if (size == 0) return error.UnexpectedEndOfStream;

        try out_writer.writeAll(buffer[0..size]);
        offset += size;
    }
}

fn touchFile(dest_dir: std.fs.Dir, file_name: []const u8) !void {
    if (std.fs.path.dirname(file_name)) |dir_name| {
        try dest_dir.makePath(dir_name);
    }
    const out_file = try dest_dir.createFile(file_name, .{});
    out_file.close();
}

// zig fmt: off
pub fn unzipToDirectory(
        base_allocator: std.mem.Allocator,
        dest_dir: std.fs.Dir,
        file: std.fs.File,
        comptime progress: anytype,
        progress_param: anytype) !void
{
    var arena = std.heap.ArenaAllocator.init(base_allocator);
    var allocator = arena.allocator();
    defer arena.deinit();

    var eocdr = try EndOfCDirRecord.findInFile(file);
    if (eocdr.this_disk_no != 0 or eocdr.cdir_disk_no != 0) return error.MultivolumeZipNotSupported;
    if (eocdr.num_entries == 0) return error.EmptyZipFile;

    if (progress) |callback| {
        callback(eocdr.num_entries, 0, progress_param);
    }

    try file.seekTo(eocdr.cdir_offset);

    var buffer: Buffer = .{};
    var bytes_inbuf = try file.readAll(&buffer.buffer);

    var offset: usize = 0;
    var cdir_array = try allocator.alloc(CDirEntry, eocdr.num_entries);

    // read all Central Directory Entries into an array:
    for (cdir_array) |*cdir_entry| {
        var bytes_remaining = bytes_inbuf - offset;
        if (bytes_remaining < CDirEntry.size) {
            @memcpy(buffer.buffer[0..bytes_remaining], buffer.buffer[offset..][0..bytes_remaining]);

            bytes_inbuf = bytes_remaining + try file.readAll(buffer.buffer[bytes_remaining..]);
            offset = 0;
            bytes_remaining = bytes_inbuf;
        }
        cdir_entry.* = try CDirEntry.deserialize(&buffer, offset);

        if (bytes_remaining < cdir_entry.total_size) {
            @memcpy(buffer.buffer[0..bytes_remaining], buffer.buffer[offset..][0..bytes_remaining]);
            bytes_inbuf = bytes_remaining + try file.readAll(buffer.buffer[bytes_remaining..]);
            offset = 0;
        }
        try cdir_entry.deserializeExtras(allocator, &buffer, offset);

        offset += cdir_entry.total_size;
    }

    for (cdir_array, 0..) |cdir, index| {
        if (try file.getPos() != cdir.lfh_offset) {
            try file.seekTo(cdir.lfh_offset);
        }
        // TODO: maybe parse Local File Header instead of assuming file name fields are the same
        const skip_bytes = LocalFileHeader.size + cdir.file_name.len;
        try file.seekBy(@intCast(skip_bytes));

        switch (cdir.method) {
            .none => {
                if (cdir.compressed_size != 0 and cdir.uncompressed_size != 0) {
                    if (cdir.compressed_size == cdir.uncompressed_size) {
                        try writeReaderToFileSystem(dest_dir, cdir.file_name, file.reader(), cdir.uncompressed_size);
                    } else return error.ZipError;
                } else {
                    if (cdir.isDir()) {
                        // directory: don't do anything for now
                        try dest_dir.makePath(cdir.file_name);
                    } else {
                        // zero-length file
                        try touchFile(dest_dir, cdir.file_name);
                    }
                }
            },
            .deflate => {
                var lr = std.io.limitedReader(file.reader(), cdir.compressed_size);
                var br = std.io.bufferedReaderSize(4 * MB, lr);
                var dec = try std.compress.deflate.decompressor(allocator, br.reader(), null);
                defer dec.deinit();
                try writeReaderToFileSystem(dest_dir, cdir.file_name, dec.reader(), cdir.uncompressed_size);
            },
            else => return error.UnsupportedCompressionMethod,
        }
        if (progress) |callback| {
            callback(eocdr.num_entries, index + 1, progress_param);
        }
    }
}

fn sliceFromLen(comptime T: type, len: usize) []T {
    @setRuntimeSafety(false);
    return @as([]T, &.{})[0..len];
}

