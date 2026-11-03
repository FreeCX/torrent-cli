const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const http = std.http;
const json = std.json;

const rpc = @import("rpc.zig");

const log = std.log.scoped(.api);

// base json with custom result
fn TorrentBase(T: type) type {
    return struct {
        id: u64,
        jsonrpc: []u8,
        result: ?T = null,
        @"error": ?struct { code: u32, message: []u8 } = null,
    };
}

// torrent get
pub const Status = enum(u8) {
    Stopped = 0,
    QueuedVerify = 1,
    Verifying = 2,
    QueuedDownload = 3,
    Downloading = 4,
    QueuedSeed = 5,
    Seeding = 6,
};
pub const StatusInfo = struct {
    id: u64,
    name: []u8,
    percent_done: f64,
    rate_download: u64,
    rate_upload: u64,
    status: Status,
};
pub const TorrentStatsList = struct {
    items: []StatusInfo,

    pub fn deinit(self: TorrentStatsList, gpa: mem.Allocator) void {
        for (self.items) |t| {
            gpa.free(t.name);
        }
        gpa.free(self.items);
    }
};
const TorrentStatusResult = struct { torrents: []StatusInfo };
const TorrentStatusResponse = TorrentBase(TorrentStatusResult);

// torrent add
const TorrentAddInfo = struct { id: u64, name: []u8, hash_string: []u8 };
pub const AddInfo = struct {
    id: u64,
    name: []u8,
    hash_string: []u8,
    is_duplicate: bool,

    pub fn deinit(self: AddInfo, gpa: mem.Allocator) void {
        gpa.free(self.name);
        gpa.free(self.hash_string);
    }
};
const TorrentAddResult = struct {
    torrent_added: ?TorrentAddInfo = null,
    torrent_duplicate: ?TorrentAddInfo = null,
};
const TorrentAddResponse = TorrentBase(TorrentAddResult);

pub fn torrentStatus(gpa: mem.Allocator, client: *rpc.Client, ids: ?[]u32) !TorrentStatsList {
    const params = .{
        .ids = ids,
        .fields = .{ "id", "name", "status", "rate_download", "rate_upload", "percent_done" },
    };

    const response = try client.request("torrent_get", params);
    const parsed = try json.parseFromSlice(
        TorrentStatusResponse,
        gpa,
        response.body,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    // TODO
    if (parsed.value.@"error") |err| {
        log.err("code={d}, message='{s}'", .{ err.code, err.message });
        return error.ErrorResponse;
    }

    const duped = try gpa.dupe(StatusInfo, parsed.value.result.?.torrents);
    errdefer gpa.free(duped);
    for (duped) |*item| {
        item.name = try gpa.dupe(u8, item.name);
        errdefer gpa.free(item.name);
    }

    return TorrentStatsList{ .items = duped };
}

pub fn torrentAdd(gpa: mem.Allocator, client: *rpc.Client, filename: ?[]const u8, metainfo: ?[]const u8) !AddInfo {
    if (filename != null and metainfo != null) {
        return error.MultipleFieldsProvided;
    }
    if (filename == null and metainfo == null) {
        return error.NoFieldProvided;
    }

    var metainfo_encoded: ?[]const u8 = null;
    var encoded: []u8 = undefined;
    if (metainfo != null) {
        const codec = std.base64.standard;
        encoded = try gpa.alloc(u8, codec.Encoder.calcSize(metainfo.?.len));
        metainfo_encoded = codec.Encoder.encode(encoded, metainfo.?);
    }

    const params = .{ .metainfo = metainfo_encoded, .filename = filename };
    const response = client.request("torrent_add", params) catch |err| {
        if (metainfo != null) {
            gpa.free(encoded);
        }
        return err;
    };

    if (metainfo != null) {
        gpa.free(encoded);
    }

    const parsed = try json.parseFromSlice(
        TorrentAddResponse,
        gpa,
        response.body,
        .{},
    );
    defer parsed.deinit();

    // TODO
    if (parsed.value.@"error") |err| {
        log.err("code={d}, message='{s}'", .{ err.code, err.message });
        return error.ErrorResponse;
    }

    var is_duplicate = false;
    var info: TorrentAddInfo = undefined;
    if (parsed.value.result.?.torrent_added != null) {
        info = parsed.value.result.?.torrent_added.?;
    } else if (parsed.value.result.?.torrent_duplicate != null) {
        info = parsed.value.result.?.torrent_duplicate.?;
        is_duplicate = true;
    } else {
        return error.MissingInfo;
    }

    const duped_name = try gpa.dupe(u8, info.name);
    errdefer gpa.free(duped_name);
    const duped_hash = try gpa.dupe(u8, info.hash_string);

    return AddInfo{
        .id = info.id,
        .name = duped_name,
        .hash_string = duped_hash,
        .is_duplicate = is_duplicate,
    };
}

pub fn torrentStart(client: *rpc.Client, ids: ?[]u32) !bool {
    const response = try client.request("torrent_start", .{ .ids = ids });
    return response.status == .ok;
}

pub fn torrentStop(client: *rpc.Client, ids: ?[]u32) !bool {
    const response = try client.request("torrent_stop", .{ .ids = ids });
    return response.status == .ok;
}

pub fn torrentDelete(client: *rpc.Client, ids: ?[]u32) !bool {
    const response = try client.request(
        "torrent_remove",
        .{ .ids = ids, .delete_local_data = false },
    );
    return response.status == .ok;
}
