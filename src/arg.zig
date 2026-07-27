const std = @import("std");
const args = @import("args");

const app = @import("build_zig_zon");

pub const Command = enum {
    Add,
    Start,
    Stop,
    Delete,
    Status,

    pub fn parse(command: ?[]const u8) ?Command {
        if (command == null) return null;

        if (std.mem.eql(u8, command.?, "add")) return Command.Add;
        if (std.mem.eql(u8, command.?, "start")) return Command.Start;
        if (std.mem.eql(u8, command.?, "stop")) return Command.Stop;
        if (std.mem.eql(u8, command.?, "delete")) return Command.Delete;
        if (std.mem.eql(u8, command.?, "status")) return Command.Status;

        return null;
    }
};

pub const Args = struct {
    parser: args.ArgumentParser,
    result: args.ParseResult,
    level: std.log.Level,
    command: Command,

    pub fn deinit(self: *Args) void {
        self.result.deinit();
        self.parser.deinit();
    }
};

fn parseLogLevel(value: []const u8) std.log.Level {
    if (std.mem.eql(u8, value, "err")) return .err;
    if (std.mem.eql(u8, value, "warn")) return .warn;
    if (std.mem.eql(u8, value, "info")) return .info;
    if (std.mem.eql(u8, value, "debug")) return .debug;
    // default log level
    return .err;
}

// https://muhammad-fiaz.github.io/args.zig/
pub fn setupArgs(init: std.process.Init) !Args {
    var parser = try args.ArgumentParser.init(init.gpa, .{
        .name = @tagName(app.name),
        .version = app.version,
        .description = app.description,
        .config = .{ .check_for_updates = false, .show_update_notification = false },
    });
    errdefer parser.deinit();

    try parser.addHostNameOption("host", .{
        .default = "127.0.0.1",
        .short = 'i',
        .help = "Transmission host",
    });
    try parser.addIntOption("port", .{
        .default = "9091",
        .short = 'p',
        .min = 1,
        .max = 65535,
        .help = "Transmission port",
    });
    try parser.addOption("level", .{
        .short = 'l',
        .help = "Log level",
        .choices = &[_][]const u8{ "err", "warn", "info", "debug" },
    });

    try parser.addSubcommand(.{
        .name = "add",
        .help = "Add torrent",
        .args = &[_]args.ArgSpec{
            .{
                .name = "path",
                .short = 'p',
                .long = "path",
                .value_type = .path,
                .conflicts_with = &.{"magnet"},
                .help = "From file/folder",
            },
            .{
                .name = "magnet",
                .short = 'm',
                .long = "magnet",
                .conflicts_with = &.{"path"},
                .help = "From magnet url",
            },
        },
    });

    try parser.addSubcommand(.{
        .name = "start",
        .help = "Start torrent",
        .args = &[_]args.ArgSpec{
            .{
                .name = "id",
                .short = 'i',
                .long = "id",
                .nargs = .zero_or_more,
                .value_type = .array,
                .help = "By ids",
            },
        },
    });

    try parser.addSubcommand(.{
        .name = "stop",
        .help = "Stop torrent",
        .args = &[_]args.ArgSpec{
            .{
                .name = "id",
                .short = 'i',
                .long = "id",
                .nargs = .zero_or_more,
                .value_type = .array,
                .help = "By ids",
            },
        },
    });

    try parser.addSubcommand(.{
        .name = "delete",
        .help = "Delete torrent",
        .args = &[_]args.ArgSpec{
            .{
                .name = "id",
                .short = 'i',
                .long = "id",
                .nargs = .zero_or_more,
                .value_type = .array,
                .help = "By ids",
            },
        },
    });

    try parser.addSubcommand(.{
        .name = "status",
        .help = "Show torrent stats",
        // TODO: aliases just doesn't work
        .aliases = &[_][]const u8{ "s", "stat" },
    });

    var result = try parser.parseProcess(init);
    errdefer result.deinit();

    const command = Command.parse(result.subcommand);
    if (command == null) {
        try parser.printHelp();
        return error.Exit;
    }

    return Args{
        .parser = parser,
        .result = result,
        .command = command.?,
        .level = parseLogLevel(result.getOrString("level", "err")),
    };
}
