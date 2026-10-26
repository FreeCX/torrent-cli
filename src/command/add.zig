const std = @import("std");
const mem = std.mem;
const Io = std.Io;

const rpc = @import("../rpc.zig");

const log = std.log.scoped(.add);

fn isDirectory(io: Io, path: []const u8) !bool {
    const stat = try Io.Dir.cwd().statFile(io, path, .{});
    return stat.kind == .directory;
}

fn isDuplicate(data: rpc.AddInfo) u8 {
    return if (data.is_duplicate) '!' else '+';
}

fn resolveFullPath(gpa: mem.Allocator, io: Io, path: []const u8, sub_path: []const u8) ![]u8 {
    const cwd = try Io.Dir.cwd().realPathFileAlloc(io, path, gpa);
    defer gpa.free(cwd);
    log.debug("cwd={s}", .{cwd});

    const resolved = try Io.Dir.path.resolveAlloc(gpa, &.{ cwd, sub_path });
    log.debug("resolved={s}", .{resolved});
    return resolved;
}

// walk over dir and add *.torrent files
fn addAllFromDirectory(gpa: mem.Allocator, io: Io, stdout: *Io.Writer, path: []const u8) !void {
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
            const resolved = try resolveFullPath(gpa, io, path, entry.path);
            defer gpa.free(resolved);

            const response = try rpc.torrentAdd(gpa, resolved, null);
            defer response.deinit(gpa);

            try stdout.print(
                "{c} | {d} | {s}\n",
                .{ isDuplicate(response), response.id, response.name },
            );
        }
    }
    try stdout.flush();
}

fn addOneFile(gpa: mem.Allocator, io: Io, stdout: *Io.Writer, path: []const u8) !void {
    const resolved = try resolveFullPath(gpa, io, ".", path);
    defer gpa.free(resolved);

    const response = try rpc.torrentAdd(gpa, resolved, null);
    defer response.deinit(gpa);

    try stdout.print("{c} | {d} | {s}\n", .{ isDuplicate(response), response.id, response.name });
    try stdout.flush();
}

pub fn addPath(gpa: mem.Allocator, io: Io, stdout: *Io.Writer, path: []const u8) !void {
    if (try isDirectory(io, path)) {
        try addAllFromDirectory(gpa, io, stdout, path);
        return;
    }

    try addOneFile(gpa, io, stdout, path);
}

pub fn addMagnet(gpa: mem.Allocator, stdout: *Io.Writer, magnet: []const u8) !void {
    const response = try rpc.torrentAdd(gpa, magnet, null);
    defer response.deinit(gpa);

    try stdout.print("{c} | {d} | {s}\n", .{ isDuplicate(response), response.id, response.name });
    try stdout.flush();
}
