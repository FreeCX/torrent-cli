const std = @import("std");
const mem = std.mem;
const Io = std.Io;

const rpc = @import("../rpc.zig");

pub fn stop(gpa: mem.Allocator, stdout: *Io.Writer, ids: ?[]u32) !void {
    const stats = try rpc.torrentStatus(gpa, ids);
    stats.deinit(gpa);

    _ = try rpc.torrentStop(ids);

    for (stats.items) |torrent| {
        try stdout.print("■ | {d} | {s}\n", .{ torrent.id, torrent.name });
    }
    try stdout.flush();
}
