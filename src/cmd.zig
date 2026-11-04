const std = @import("std");
const mem = std.mem;
const Io = std.Io;

const api = @import("api.zig");
const rpc = @import("rpc.zig");

const log = std.log.scoped(.cmd);

const asMB: f32 = 1024 * 1024;

fn duplicateOrAddSymbol(data: api.AddInfo) u8 {
    return if (data.is_duplicate) '!' else '+';
}

fn statusAsSymbol(stat: api.Status) []const u8 {
    return switch (stat) {
        .Downloading => "↓",
        .Seeding => "↑",
        .Stopped => "■",
        .Verifying => "⭯",
        else => "∅",
    };
}

fn renderProgressBar(percent: u8, buffer: []u8) []u8 {
    const filler = @divTrunc(percent, 10);
    const spacer = 10 - filler;
    var writer = Io.Writer.fixed(buffer);
    _ = writer.splatBytes("▮", filler) catch {};
    _ = writer.splatBytes("⋅", spacer) catch {};
    return buffer[0..writer.end];
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
fn addFromDirectory(gpa: mem.Allocator, io: Io, client: *rpc.Client, stdout: *Io.Writer, path: []const u8) !void {
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

            // TODO: делать вне функции?
            const response = try api.torrentAdd(gpa, client, resolved, null);
            defer response.deinit(gpa);

            try stdout.print(
                "{c} | {d} | {s}\n",
                .{ duplicateOrAddSymbol(response), response.id, response.name },
            );
        }
    }
    try stdout.flush();
}

fn addOneFile(gpa: mem.Allocator, io: Io, client: *rpc.Client, stdout: *Io.Writer, path: []const u8) !void {
    const resolved = try resolveFullPath(gpa, io, ".", path);
    defer gpa.free(resolved);

    const response = try api.torrentAdd(gpa, client, resolved, null);
    defer response.deinit(gpa);

    try stdout.print("{c} | {d} | {s}\n", .{ duplicateOrAddSymbol(response), response.id, response.name });
    try stdout.flush();
}

// TODO: process ErrorResponse?
pub fn addPath(gpa: mem.Allocator, io: Io, client: *rpc.Client, stdout: *Io.Writer, path: []const u8) !void {
    const stat = try Io.Dir.cwd().statFile(io, path, .{});
    if (stat.kind == .directory) {
        try addFromDirectory(gpa, io, client, stdout, path);
        return;
    }

    try addOneFile(gpa, io, client, stdout, path);
}

// TODO: process ErrorResponse?
pub fn addMagnet(gpa: mem.Allocator, client: *rpc.Client, stdout: *Io.Writer, magnet: []const u8) !void {
    const response = try api.torrentAdd(gpa, client, magnet, null);
    defer response.deinit(gpa);

    try stdout.print("{c} | {d} | {s}\n", .{ duplicateOrAddSymbol(response), response.id, response.name });
    try stdout.flush();
}

pub fn delete(gpa: mem.Allocator, client: *rpc.Client, stdout: *Io.Writer, ids: ?[]u32) !void {
    const stats = try api.torrentStatus(gpa, client, ids);
    defer stats.deinit(gpa);

    _ = try api.torrentDelete(client, ids);

    for (stats.items) |torrent| {
        try stdout.print("× | {d} | {s}\n", .{ torrent.id, torrent.name });
    }
    try stdout.flush();
}

pub fn start(gpa: mem.Allocator, client: *rpc.Client, stdout: *Io.Writer, ids: ?[]u32) !void {
    const stats = try api.torrentStatus(gpa, client, ids);
    defer stats.deinit(gpa);

    _ = try api.torrentStart(client, ids);

    for (stats.items) |torrent| {
        try stdout.print("▶ | {d} | {s}\n", .{ torrent.id, torrent.name });
    }
    try stdout.flush();
}

// TODO: подумать над вариабельным форматом статуса
pub fn status(gpa: mem.Allocator, client: *rpc.Client, stdout: *Io.Writer) !void {
    const stats = try api.torrentStatus(gpa, client, null);
    defer stats.deinit(gpa);

    var bar_buffer: [32]u8 = undefined;

    for (stats.items) |torrent| {
        const percent_clamped = std.math.clamp(torrent.percent_done, 0.0, 1.0);
        const percent: u8 = @trunc(percent_clamped * 100);
        const download = @as(f32, @floatFromInt(torrent.rate_download)) / asMB;
        const upload = @as(f32, @floatFromInt(torrent.rate_upload)) / asMB;

        try stdout.print("{d} | {s} | {s} {d:3}% | {d: >5.2}↓ {d: >5.2}↑ {d: >5.2}÷ | {s}\n", .{
            torrent.id,
            statusAsSymbol(torrent.status),
            renderProgressBar(percent, &bar_buffer),
            percent,
            download,
            upload,
            torrent.upload_ratio,
            torrent.name,
        });
    }
    try stdout.flush();
}

pub fn stop(gpa: mem.Allocator, client: *rpc.Client, stdout: *Io.Writer, ids: ?[]u32) !void {
    const stats = try api.torrentStatus(gpa, client, ids);
    defer stats.deinit(gpa);

    _ = try api.torrentStop(client, ids);

    for (stats.items) |torrent| {
        try stdout.print("■ | {d} | {s}\n", .{ torrent.id, torrent.name });
    }
    try stdout.flush();
}
