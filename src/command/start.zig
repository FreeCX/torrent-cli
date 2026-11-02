const std = @import("std");
const mem = std.mem;
const Io = std.Io;

const core = @import("core.zig");
const rpc = @import("../rpc.zig");

pub fn start(gpa: mem.Allocator, client: *rpc.Client, stdout: *Io.Writer, ids: ?[]u32) !void {
    const stats = try core.torrentStatus(gpa, client, ids);
    defer stats.deinit(gpa);

    _ = try core.torrentStart(client, ids);

    for (stats.items) |torrent| {
        try stdout.print("▶ | {d} | {s}\n", .{ torrent.id, torrent.name });
    }
    try stdout.flush();
}
