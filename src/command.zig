const std = @import("std");

const HelpCommand = @import("command/help.zig");
const InstallCommand = @import("command/install.zig");
const ListCommand = @import("command/list.zig");
const RemoteListCommand = @import("command/remote_list.zig");
const UninstallCommand = @import("command/uninstall.zig");
const UseCommand = @import("command/use.zig");
const VersionCommand = @import("command/version.zig");

const Allocator = std.mem.Allocator;

pub const Context = struct {
    allocator: Allocator,
    stdout: std.fs.File.Writer,
    zig_root: []const u8,
};

const Command = union(enum) {
    const Self = @This();
    const Tag = std.meta.Tag(Self);

    help: HelpCommand,
    install: InstallCommand,
    list: ListCommand,
    remote_list: RemoteListCommand,
    uninstall: UninstallCommand,
    use: UseCommand,
    version: VersionCommand,

    pub fn execute(self: Self, ctx: *const Context) !void {
        switch (self) {
            inline else => |cmd| {
                return cmd.execute(ctx);
            },
        }
    }

    pub fn validate(cmd: []const u8) ?Tag {
        return std.meta.stringToEnum(Tag, cmd);
    }

    pub fn fromEnum(tag: Tag) Command {
        return switch (tag) {
            inline else => |cttag| @unionInit(Self, @tagName(cttag), .{}),
        };
    }

    pub fn setVersion(self: *Self, ver: []const u8) void {
        switch (self.*) {
            .install => self.install.version = ver,
            .uninstall => self.uninstall.version = ver,
            .use => self.use.version = ver,
            else => unreachable,
        }
    }

    pub fn setPlatform(self: *Self, platform: []const u8) void {
        switch (self.*) {
            .install => self.install.platform = platform,
            .uninstall => self.uninstall.platform = platform,
            else => unreachable,
        }
    }

    pub fn deinit(self: Self, allocator: Allocator) void {
        switch (self) {
            .install, .uninstall, .use => {
                if (self.install.version) |ver| {
                    allocator.free(ver);
                }
                if (self.install.platform) |platform| {
                    allocator.free(platform);
                }
            },
            .list, .remote_list, .version, .help => {},
        }
    }
};

pub fn fromCommandLineArgs(allocator: Allocator) !Command {
    const ParserState = enum { cmd, ver, platform, list_opt, should_end };
    var command: Command = Command.fromEnum(.help);

    var arg_itr = try std.process.argsWithAllocator(allocator);
    defer arg_itr.deinit();

    // just skip the 0th argument
    _ = arg_itr.next() orelse return command;

    var state = ParserState.cmd;
    while (arg_itr.next()) |arg| {
        switch (state) {
            .cmd => {
                if (Command.validate(arg)) |cmdtag| {
                    command = Command.fromEnum(cmdtag);

                    state = switch (cmdtag) {
                        .install, .uninstall, .use => .ver,
                        .list => .list_opt,
                        .remote_list => .should_end, // or return error.InvalidCommand,
                        .help, .version => .should_end,
                    };
                } else {
                    return error.InvalidCommand;
                }
            },
            .ver => {
                command.setVersion(try allocator.dupe(u8, arg));
                state = switch (command) {
                    .install, .uninstall => .platform,
                    else => .should_end,
                };
            },
            .platform => {
                command.setPlatform(try allocator.dupe(u8, arg));
                state = .should_end;
            },
            .list_opt => {
                if (std.mem.eql(u8, arg, "-r") or std.mem.eql(u8, arg, "--remote")) {
                    command = Command.fromEnum(.remote_list);
                }
                state = .should_end;
            },
            .should_end => return error.UnexpectedToken,
        }
    }

    if (state == .ver) return error.MissingVersion;

    return command;
}
