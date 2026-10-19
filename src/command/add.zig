const std = @import("std");
const mem = std.mem;
const Io = std.Io;

const rpc = @import("../rpc.zig");

fn isDirectory(io: Io, path: []const u8) !bool {
    const stat = try Io.Dir.cwd().statFile(io, path, .{});
    return stat.kind == .directory;
}

fn isDuplicate(data: rpc.AddInfo) u8 {
    return if (data.is_duplicate) '!' else '+';
}

pub fn addPath(gpa: mem.Allocator, io: Io, stdout: *Io.Writer, path: []const u8) !void {
    if (try isDirectory(io, path)) {
        // walk over dir and add *.torrent files
        const dir = try Io.Dir.cwd().openDir(
            io,
            path,
            .{ .iterate = true },
        );
        defer dir.close(io);

        var walker = try dir.walk(gpa);
        defer walker.deinit();

        while (try walker.next(io)) |entry| {
            if (mem.endsWith(u8, entry.basename, ".torrent")) {
                const filename = try std.fmt.allocPrint(
                    gpa,
                    "{s}/{s}",
                    .{ path, entry.path },
                );
                defer gpa.free(filename);

                const response = try rpc.torrentAdd(gpa, filename, null);
                defer response.deinit(gpa);

                try stdout.print(
                    "{c} | {d} | {s}\n",
                    .{ isDuplicate(response), response.id, response.name },
                );
            }
        }
        try stdout.flush();

        return;
    }

    // add one file
    const filename = try Io.Dir.cwd().realPathFileAlloc(io, path, gpa);
    defer gpa.free(filename);

    const response = try rpc.torrentAdd(gpa, filename, null);
    defer response.deinit(gpa);

    try stdout.print("{c} | {d} | {s}\n", .{ isDuplicate(response), response.id, response.name });
    try stdout.flush();
}

pub fn addMagnet(gpa: mem.Allocator, stdout: *Io.Writer, magnet: []const u8) !void {
    const response = try rpc.torrentAdd(gpa, magnet, null);
    defer response.deinit(gpa);

    try stdout.print("{c} | {d} | {s}\n", .{ isDuplicate(response), response.id, response.name });
    try stdout.flush();
}
