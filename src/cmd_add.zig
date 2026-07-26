const std = @import("std");
const mem = std.mem;
const Io = std.Io;

const rpc = @import("rpc.zig");

const log = std.log.scoped(.add);

var buffer: [4096]u8 = undefined;

fn isDirectory(io: Io, path: []const u8) !bool {
    const stat = try std.Io.Dir.cwd().statFile(io, path, .{});
    return stat.kind == .directory;
}

pub fn add(gpa: mem.Allocator, io: Io, stdout: *Io.Writer, path: ?[]const u8, magnet: ?[]const u8) !void {
    if (path != null) {
        if (try isDirectory(io, path.?)) {
            const dir = try std.Io.Dir.cwd().openDir(
                io,
                path.?,
                .{ .iterate = true },
            );
            defer dir.close(io);
            var walker = try dir.walk(gpa);
            defer walker.deinit();
            while (try walker.next(io)) |entry| {
                if (std.mem.endsWith(u8, entry.basename, ".torrent")) {
                    const filename = try std.fmt.bufPrint(
                        &buffer,
                        "{s}/{s}",
                        .{ path.?, entry.basename },
                    );
                    const response = try rpc.torrentAdd(gpa, filename, null);
                    defer response.deinit(gpa);
                    try stdout.print("+ | {d} | {s}\n", .{ response.id, response.name });
                }
            }
            try stdout.flush();
            return;
        }

        const response = try rpc.torrentAdd(gpa, path.?, null);
        defer response.deinit(gpa);
        try stdout.print("+ | {d} | {s}\n", .{ response.id, response.name });
        try stdout.flush();
        return;
    }

    if (magnet != null) {
        const response = try rpc.torrentAdd(gpa, magnet, null);
        defer response.deinit(gpa);
        try stdout.print("+ | {d} | {s}\n", .{ response.id, response.name });
        try stdout.flush();
    }
}
