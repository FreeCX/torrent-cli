const std = @import("std");
const Io = std.Io;

const rpc = @import("rpc.zig");
const arg = @import("arg.zig");

const command = .{
    .add = @import("command/add.zig"),
    .delete = @import("command/delete.zig").delete,
    .start = @import("command/start.zig").start,
    .stop = @import("command/stop.zig").stop,
    .status = @import("command/status.zig").status,
};

const log = std.log.scoped(.app);

// custom logging, because .log_level cannot be changed after compilation
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
    if (@backingInt(message_level) <= @backingInt(log_level)) {
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

    var arguments = arg.parseArgs(gpa, init, stdout) catch |err| switch (err) {
        error.Exit => return,
        else => return err,
    };
    defer arguments.deinit(gpa);

    log_level = arguments.level;

    const read_buffer = try gpa.alloc(u8, arguments.buffer_size);
    defer gpa.free(read_buffer);
    const write_buffer = try gpa.alloc(u8, arguments.buffer_size);
    defer gpa.free(write_buffer);

    var client: rpc.Client = .init(
        io,
        gpa,
        arguments.host,
        arguments.port,
        read_buffer,
        write_buffer,
    );
    defer client.deinit();

    switch (arguments.command) {
        arg.Command.add => |params| {
            if (params.path) |path| {
                try command.add.addPath(gpa, io, &client, stdout, path);
            }
            if (params.magnet) |magnet| {
                try command.add.addMagnet(gpa, &client, stdout, magnet);
            }
            // TODO: nothing to do
        },
        arg.Command.delete => |params| try command.delete(gpa, &client, stdout, params.id),
        arg.Command.start => |params| try command.start(gpa, &client, stdout, params.id),
        arg.Command.stop => |params| try command.stop(gpa, &client, stdout, params.id),
        arg.Command.status => try command.status(gpa, &client, stdout),
    }
}
