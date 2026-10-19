const std = @import("std");
const Io = std.Io;
const mem = std.mem;

const args = @import("args");

const app = @import("build_zig_zon");

pub const Command = enum {
    add,
    start,
    stop,
    delete,
    status,
};

pub const AddCommandArgs = struct {
    path: ?[]const u8,
    magnet: ?[]const u8,
};

pub const OtherCommandArgs = struct {
    all: ?bool,
    id: ?[]u32,
};

pub const Commands = union(Command) {
    add: AddCommandArgs,
    start: OtherCommandArgs,
    stop: OtherCommandArgs,
    delete: OtherCommandArgs,
    status: struct {},
};

pub const Args = struct {
    command: Commands,
    host: []const u8,
    port: u16,
    level: std.log.Level,
    buffer_size: u32,

    pub fn deinit(self: Args, gpa: mem.Allocator) void {
        gpa.free(self.host);
        switch (self.command) {
            .add => |cmd| {
                if (cmd.path) |path| gpa.free(path);
                if (cmd.magnet) |magnet| gpa.free(magnet);
            },
            .start, .stop, .delete => |cmd| {
                if (cmd.id) |id| gpa.free(id);
            },
            .status => {},
        }
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

fn parseIds(gpa: std.mem.Allocator, T: type, items: ?[]const []const u8) !?[]T {
    if (items == null) return null;

    var result = try gpa.alloc(T, items.?.len);
    errdefer gpa.free(result);
    for (items.?, 0..) |item, index| {
        result[index] = try std.fmt.parseInt(T, item, 10);
    }

    return result;
}

pub fn parseArgs(gpa: mem.Allocator, init: std.process.Init, stdout: *Io.Writer) !Args {
    var parser = try args.ArgumentParser.init(gpa, .{
        .name = @tagName(app.name),
        .version = app.version,
        .description = app.description,
        .config = .{ .allow_negated_flags = false },
    });
    defer parser.deinit();

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
    try parser.addUintOption("buffer", .{
        .default = "65536",
        .short = 'b',
        .help = "RPC buffer size",
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
                .name = "all",
                .short = 'a',
                .long = "all",
                .conflicts_with = &.{"id"},
                .action = .store_true,
                .help = "Start all",
            },
            .{
                .name = "id",
                .short = 'i',
                .long = "id",
                .nargs = .zero_or_more,
                .value_type = .array,
                .conflicts_with = &.{"all"},
                .help = "By id",
            },
        },
    });

    try parser.addSubcommand(.{
        .name = "stop",
        .help = "Stop torrent",
        .args = &[_]args.ArgSpec{
            .{
                .name = "all",
                .short = 'a',
                .long = "all",
                .conflicts_with = &.{"id"},
                .action = .store_true,
                .help = "Stop all",
            },
            .{
                .name = "id",
                .short = 'i',
                .long = "id",
                .nargs = .zero_or_more,
                .value_type = .array,
                .conflicts_with = &.{"all"},
                .help = "By id",
            },
        },
    });

    try parser.addSubcommand(.{
        .name = "delete",
        .help = "Delete torrent",
        .args = &[_]args.ArgSpec{
            .{
                .name = "all",
                .short = 'a',
                .long = "all",
                .conflicts_with = &.{"id"},
                .action = .store_true,
                .help = "Delete all",
            },
            .{
                .name = "id",
                .short = 'i',
                .long = "id",
                .nargs = .zero_or_more,
                .value_type = .array,
                .conflicts_with = &.{"all"},
                .help = "By id",
            },
        },
    });

    try parser.addSubcommand(.{
        .name = "status",
        .help = "Show torrent stats",
    });

    var result = try parser.parseProcess(init);
    defer result.deinit();

    if (result.subcommand == null) {
        try parser.printHelp();
        return error.Exit;
    }
    if (result.subcommand_args == null) {
        return error.MissingSubcommandArgs;
    }

    var cmd_name: Command = undefined;
    if (std.mem.eql(u8, result.subcommand.?, "add")) cmd_name = .add;
    if (std.mem.eql(u8, result.subcommand.?, "start")) cmd_name = .start;
    if (std.mem.eql(u8, result.subcommand.?, "stop")) cmd_name = .stop;
    if (std.mem.eql(u8, result.subcommand.?, "delete")) cmd_name = .delete;
    if (std.mem.eql(u8, result.subcommand.?, "status")) cmd_name = .status;

    var command: Commands = undefined;
    switch (cmd_name) {
        .add => {
            const path = result.subcommand_args.?.getString("path");
            const magnet = result.subcommand_args.?.getString("magnet");

            if (path == null and magnet == null) {
                try stdout.print("add: missing --path or --magnet argument\n", .{});
                try stdout.flush();
                return error.Exit;
            }
            if (path != null and magnet != null) {
                try stdout.print("add: required one of --path or --magnet argument\n", .{});
                try stdout.flush();
                return error.Exit;
            }

            command = .{
                .add = AddCommandArgs{
                    .path = if (path != null) try gpa.dupe(u8, path.?) else null,
                    .magnet = if (magnet != null) try gpa.dupe(u8, magnet.?) else null,
                },
            };
        },
        .start, .stop, .delete => {
            const all = result.subcommand_args.?.getBool("all");
            const ids = result.subcommand_args.?.getArray("id");

            if (all == null and ids == null) {
                try stdout.print("{s}: missing --all or --id argument\n", .{@tagName(cmd_name)});
                try stdout.flush();
                return error.Exit;
            }
            if (all != null and ids != null) {
                try stdout.print("{s}: required one of --all or --id argument\n", .{@tagName(cmd_name)});
                try stdout.flush();
                return error.Exit;
            }

            const data = OtherCommandArgs{
                .all = all,
                .id = if (ids != null) try parseIds(gpa, u32, ids) else null,
            };

            switch (cmd_name) {
                .start => command = .{ .start = data },
                .stop => command = .{ .stop = data },
                .delete => command = .{ .delete = data },
                else => {},
            }
        },
        .status => {
            command = .{ .status = .{} };
        },
    }

    return Args{
        .command = command,
        .host = try gpa.dupe(u8, result.getOrString("host", "127.0.0.1")),
        .port = @intCast(result.getOrUint("port", 9091)),
        .buffer_size = @intCast(result.getOrUint("buffer", 65536)),
        .level = parseLogLevel(result.getOrString("level", "err")),
    };
}
