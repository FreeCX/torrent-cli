const std = @import("std");
const mem = std.mem;
const Io = std.Io;

const rpc = @import("../rpc.zig");

fn statusAsSymbol(stat: rpc.Status) []const u8 {
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

fn renderSpeedRate(value: u64, buffer: []u8) ![]u8 {
    const divider: u64 = 1024 * 1024;
    const a = value / divider;
    // TODO: есть проблема с округлением
    const b = (value % divider) * 100 / divider;
    return try std.fmt.bufPrint(buffer, "{d:2}.{d:02}", .{ a, b });
}

pub fn status(gpa: mem.Allocator, stdout: *Io.Writer) !void {
    const stats = try rpc.torrentStatus(gpa, null);
    defer stats.deinit(gpa);

    var bar_buffer: [32]u8 = undefined;
    var download_buffer: [16]u8 = undefined;
    var upload_buffer: [16]u8 = undefined;

    for (stats.items) |torrent| {
        const percent_clamped = std.math.clamp(torrent.percent_done, 0.0, 1.0);
        const percent: u8 = @trunc(percent_clamped * 100);
        try stdout.print("{d} | {s} | {s} {d:3}% | {s}↓ {s}↑ | {s}\n", .{
            torrent.id,
            statusAsSymbol(torrent.status),
            renderProgressBar(percent, &bar_buffer),
            percent,
            try renderSpeedRate(torrent.rate_download, &download_buffer),
            try renderSpeedRate(torrent.rate_upload, &upload_buffer),
            torrent.name,
        });
    }
    try stdout.flush();
}
