const std = @import("std");
const mem = std.mem;
const Io = std.Io;

const rpc = @import("../rpc.zig");

var buffer: [4096]u8 = undefined;

fn isDirectory(io: Io, path: []const u8) !bool {
    const stat = try Io.Dir.cwd().statFile(io, path, .{});
    return stat.kind == .directory;
}

fn filePath(io: Io, path: []const u8) ![]u8 {
    const size = try Io.Dir.cwd().realPathFile(io, path, &buffer);
    return buffer[0..size];
}

fn isDuplicate(data: rpc.AddInfo) u8 {
    return if (data.is_duplicate) '!' else '+';
}

pub fn add(gpa: mem.Allocator, io: Io, stdout: *Io.Writer, path: ?[]const u8, magnet: ?[]const u8) !void {
    if (path != null) {
        if (try isDirectory(io, path.?)) {
            // walk over dir and add *.torrent files
            const dir = try Io.Dir.cwd().openDir(
                io,
                path.?,
                .{ .iterate = true },
            );
            defer dir.close(io);

            var walker = try dir.walk(gpa);
            defer walker.deinit();

            while (try walker.next(io)) |entry| {
                if (mem.endsWith(u8, entry.basename, ".torrent")) {
                    const filename = try std.fmt.bufPrint(
                        &buffer,
                        "{s}/{s}",
                        .{ path.?, entry.path },
                    );
                    const response = try rpc.torrentAdd(gpa, filename, null);
                    defer response.deinit(gpa);
                    try stdout.print("{c} | {d} | {s}\n", .{ isDuplicate(response), response.id, response.name });
                }
            }
            try stdout.flush();

            return;
        }

        // add one file
        const response = try rpc.torrentAdd(
            gpa,
            try filePath(io, path.?),
            null,
        );
        defer response.deinit(gpa);
        try stdout.print("{c} | {d} | {s}\n", .{ isDuplicate(response), response.id, response.name });
        try stdout.flush();
        return;
    }

    if (magnet != null) {
        // add magnet url
        const response = try rpc.torrentAdd(gpa, magnet, null);
        defer response.deinit(gpa);
        try stdout.print("{c} | {d} | {s}\n", .{ isDuplicate(response), response.id, response.name });
        try stdout.flush();
    }
}
