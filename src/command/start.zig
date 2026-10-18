const std = @import("std");
const mem = std.mem;
const Io = std.Io;

const rpc = @import("../rpc.zig");
const util = @import("../util.zig");

pub fn start(gpa: mem.Allocator, stdout: *Io.Writer, raw_ids: ?[]const []const u8) !void {
    const ids = try util.parseIds(gpa, u32, raw_ids);
    defer if (ids != null) gpa.free(ids.?);

    const stats = try rpc.torrentStatus(gpa, ids);
    defer stats.deinit(gpa);

    _ = try rpc.torrentStart(ids);

    for (stats.items) |torrent| {
        try stdout.print("▶ | {d} | {s}\n", .{ torrent.id, torrent.name });
    }
    try stdout.flush();
}
