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

pub const std_options: std.Options = .{ .log_level = .info };

// TODO: обработка ошибок
pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    // setup stdout
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    // настройка и парсинг аргументов
    var arguments = arg.setupArgs(init) catch return;
    defer arguments.deinit();

    // буфер для rpc
    const buffer = try gpa.alloc(u8, 65536);
    defer gpa.free(buffer);

    // connect
    const host = arguments.result.getOrString("host", "127.0.0.1");
    const port: u16 = @intCast(arguments.result.getOrUint("port", 9091));
    try rpc.init(io, gpa, host, port, buffer);
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
