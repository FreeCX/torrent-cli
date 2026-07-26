const std = @import("std");

pub fn processIds(gpa: std.mem.Allocator, T: type, items: ?[]const []const u8) !?[]T {
    if (items == null) return null;

    var result = try gpa.alloc(T, items.?.len);
    for (items.?, 0..) |item, index| {
        result[index] = try std.fmt.parseInt(T, item, 10);
    }

    return result;
}
