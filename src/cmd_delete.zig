const std = @import("std");
const mem = std.mem;
const Io = std.Io;

const rpc = @import("rpc.zig");
const util = @import("util.zig");

pub fn delete(gpa: mem.Allocator, stdout: *Io.Writer, raw_ids: ?[]const []const u8) !void {
    const ids = try util.processIds(gpa, u32, raw_ids);
    defer if (ids != null) gpa.free(ids.?);

    const torrents = try rpc.torrentStatus(gpa, ids);
    defer gpa.free(torrents);

    _ = try rpc.torrentDelete(ids);

    for (torrents) |torrent| {
        try stdout.print("× | {d} | {s}\n", .{ torrent.id, torrent.name });
    }
    try stdout.flush();
}
