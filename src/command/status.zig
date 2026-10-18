const std = @import("std");
const mem = std.mem;
const Io = std.Io;

const rpc = @import("../rpc.zig");

var buffer: [64]u8 = undefined;

fn statusAsSymbol(stat: rpc.Status) []const u8 {
    return switch (stat) {
        .Downloading => "↓",
        .Seeding => "↑",
        .Stopped => "■",
        .Verifying => "⭯",
        else => "∅",
    };
}

fn renderProgressBar(percent: u8) []u8 {
    const filler = @divTrunc(percent, 10);
    const spacer = 10 - filler;
    var writer = Io.Writer.fixed(&buffer);
    _ = writer.splatBytes("▮", filler) catch {};
    _ = writer.splatByte('.', spacer) catch {};
    return buffer[0..writer.end];
}

pub fn status(gpa: mem.Allocator, stdout: *Io.Writer) !void {
    const stats = try rpc.torrentStatus(gpa, null);
    defer stats.deinit(gpa);

    for (stats.items) |torrent| {
        const percent_clamped = std.math.clamp(torrent.percent_done, 0.0, 1.0);
        const percent: u8 = @trunc(percent_clamped * 100);
        try stdout.print("{d} | {s} | {s} {d:3}% | {d:0.2}↓ {d:0.2}↑ | {s}\n", .{
            torrent.id,
            statusAsSymbol(torrent.status),
            renderProgressBar(percent),
            percent,
            @as(f32, @floatFromInt(torrent.rate_download)) / (1024.0 * 1024.0),
            @as(f32, @floatFromInt(torrent.rate_upload)) / (1024.0 * 1024.0),
            torrent.name,
        });
    }
    try stdout.flush();
}
