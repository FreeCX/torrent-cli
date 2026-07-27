const std = @import("std");
const mem = std.mem;
const Io = std.Io;
const net = Io.net;

const rpc = @import("rpc.zig");
const arg = @import("arg.zig");

const command = .{
    .add = @import("cmd_add.zig").add,
    .delete = @import("cmd_delete.zig").delete,
    .start = @import("cmd_start.zig").start,
    .stop = @import("cmd_stop.zig").stop,
    .status = @import("cmd_status.zig").status,
};

const log = std.log.scoped(.app);

// custom loging, because .log_level cannot be changed after compilation
pub const std_options: std.Options = .{
    .log_level = .debug,
    .logFn = logFn,
};
// customizable log level
var log_level: std.log.Level = .err;

fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    if (@intFromEnum(message_level) <= @intFromEnum(log_level)) {
        std.log.defaultLog(message_level, scope, format, args);
    }
}

// TODO: better error handling
pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    var arguments = arg.setupArgs(init) catch return;
    defer arguments.deinit();

    log_level = arguments.level;

    const rpc_buffer = try gpa.alloc(u8, 65536);
    defer gpa.free(rpc_buffer);

    const host = arguments.result.getOrString("host", "127.0.0.1");
    const port: u16 = @intCast(arguments.result.getOrUint("port", 9091));
    try rpc.init(io, gpa, host, port, rpc_buffer);
    defer rpc.deinit();

    switch (arguments.command) {
        arg.Command.Add => {
            const path = arguments.result.subcommand_args.?.getString("path");
            const magnet = arguments.result.subcommand_args.?.getString("magnet");
            try command.add(gpa, io, stdout, path, magnet);
        },
        arg.Command.Delete => {
            const ids = arguments.result.subcommand_args.?.getArray("id");
            try command.delete(gpa, stdout, ids);
        },
        arg.Command.Start => {
            const ids = arguments.result.subcommand_args.?.getArray("id");
            try command.start(gpa, stdout, ids);
        },
        arg.Command.Stop => {
            const ids = arguments.result.subcommand_args.?.getArray("id");
            try command.stop(gpa, stdout, ids);
        },
        arg.Command.Status => try command.status(gpa, stdout),
    }
}
