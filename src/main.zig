const std = @import("std");
const Io = std.Io;

const rpc = @import("rpc.zig");
const arg = @import("arg.zig");
const cmd = @import("cmd.zig");
const logging = @import("logging.zig");

const log = std.log.scoped(.app);

pub const std_options = logging.std_options;

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

    logging.level = arguments.level;

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
                try cmd.addPath(gpa, io, stdout, &client, path);
            }
            if (params.magnet) |magnet| {
                try cmd.addMagnet(gpa, stdout, &client, magnet);
            }
            // TODO: nothing to do
        },
        arg.Command.delete => |params| try cmd.delete(gpa, stdout, &client, params.id),
        arg.Command.start => |params| try cmd.start(gpa, stdout, &client, params.id),
        arg.Command.stop => |params| try cmd.stop(gpa, stdout, &client, params.id),
        arg.Command.status => try cmd.status(gpa, stdout, &client),
    }
}
