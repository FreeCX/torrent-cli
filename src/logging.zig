const std = @import("std");

// custom logging, because .log_level cannot be changed after compilation
pub const std_options: std.Options = .{
    .log_level = .debug,
    .logFn = logFn,
};
// customizable log level
pub var level: std.log.Level = .err;

fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    if (@backingInt(message_level) <= @backingInt(level)) {
        std.log.defaultLog(message_level, scope, format, args);
    }
}
