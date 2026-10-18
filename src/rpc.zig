const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const http = std.http;
const json = std.json;

const RpcClient = @This();
const log = std.log.scoped(.rpc);
var client: http.Client = undefined;
var uri: std.Uri = undefined;

var buffer: []u8 = undefined;
var decompress_buffer: [std.compress.flate.max_window_len]u8 = undefined;

var id: u64 = 0;
var session_id: [256]u8 = undefined;
var session_id_len: usize = 0;

const session_id_key = "X-Transmission-Session-Id";

// base json with custom result
fn TorrentBase(T: type) type {
    return struct {
        id: u64,
        jsonrpc: []u8,
        result: T,
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

// part of http response
const MiniResponse = struct { body: []u8, status: http.Status };

pub fn init(io: Io, gpa: mem.Allocator, host: []const u8, port: u16, buf: []u8) void {
    uri = std.Uri{
        .scheme = "http",
        .host = .{ .percent_encoded = host },
        .port = port,
        .path = .{ .percent_encoded = "/transmission/rpc/" },
    };
    client = http.Client{ .allocator = gpa, .io = io };
    buffer = buf;
}

pub fn deinit() void {
    client.deinit();
}

fn doRequest(method: []const u8, params: anytype) !MiniResponse {
    log.debug("--- new request ---", .{});
    // construct request
    var request = try client.request(.POST, uri, .{
        .headers = .{
            .content_type = .{ .override = "application/json; utf-8" },
        },
    });
    if (session_id_len > 0) {
        request.extra_headers = &[_]http.Header{http.Header{
            .name = session_id_key,
            .value = session_id[0..session_id_len],
        }};
    }
    defer request.deinit();

    // send head + body
    const body = try jsonify(.{ .id = nextId(), .jsonrpc = "2.0", .method = method, .params = params });
    log.debug("request={s}", .{body});
    _ = try request.sendBodyComplete(body);

    // responce headers
    var response = try request.receiveHead(buffer);
    log.debug("status_code={any}", .{response.head.status});
    if (response.head.status == .conflict) {
        log.debug("409 occured", .{});
        var it = response.head.iterateHeaders();
        while (it.next()) |header| {
            if (mem.eql(u8, header.name, session_id_key)) {
                log.debug("session_id={s}", .{header.value});
                session_id_len = header.value.len;
                if (session_id_len > session_id.len) {
                    return error.SessionIdTooLong;
                }
                @memcpy(session_id[0..session_id_len], header.value);
            }
        }
        // TODO: need a better retry policy
        return doRequest(method, params);
    }

    // response body
    var transfer_buffer: [64]u8 = undefined;
    var decompress: http.Decompress = undefined;
    const reader = response.readerDecompressing(
        &transfer_buffer,
        &decompress,
        &decompress_buffer,
    );
    const readed = try reader.readSliceShort(buffer);
    if (readed == 0) {
        return error.MissingBody;
    }
    if (readed == buffer.len) {
        return error.ResponseTooLarge;
    }
    log.debug("response={s}", .{buffer[0..readed]});

    return MiniResponse{ .body = buffer[0..readed], .status = response.head.status };
}

fn nextId() u64 {
    const current = id;
    id += 1;
    return current;
}

fn jsonify(data: anytype) ![]u8 {
    var writer = Io.Writer.fixed(buffer);
    var stringifier = json.Stringify{
        .writer = &writer,
        .options = .{ .emit_null_optional_fields = false },
    };
    try stringifier.write(data);
    return buffer[0..writer.end];
}

pub fn torrentStatus(gpa: mem.Allocator, ids: ?[]u32) !TorrentStatsList {
    const params = .{
        .ids = ids,
        .fields = .{ "id", "name", "status", "rate_download", "rate_upload", "percent_done" },
    };

    const response = try doRequest("torrent_get", params);
    const parsed = try json.parseFromSlice(
        TorrentStatusResponse,
        gpa,
        response.body,
        .{},
    );
    defer parsed.deinit();

    const duped = try gpa.dupe(StatusInfo, parsed.value.result.torrents);
    errdefer gpa.free(duped);
    for (duped) |*item| {
        item.name = try gpa.dupe(u8, item.name);
    }

    return TorrentStatsList{ .items = duped };
}

pub fn torrentAdd(gpa: mem.Allocator, filename: ?[]const u8, metainfo: ?[]const u8) !AddInfo {
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
    const response = doRequest("torrent_add", params) catch |err| {
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

    if (parsed.value.result.torrent_added == null and parsed.value.result.torrent_duplicate != null) {
        return AddInfo{
            .id = parsed.value.result.torrent_duplicate.?.id,
            .name = try gpa.dupe(u8, parsed.value.result.torrent_duplicate.?.name),
            .hash_string = try gpa.dupe(u8, parsed.value.result.torrent_duplicate.?.hash_string),
            .is_duplicate = true,
        };
    }

    return AddInfo{
        .id = parsed.value.result.torrent_added.?.id,
        .name = try gpa.dupe(u8, parsed.value.result.torrent_added.?.name),
        .hash_string = try gpa.dupe(u8, parsed.value.result.torrent_added.?.hash_string),
        .is_duplicate = false,
    };
}

pub fn torrentStart(ids: ?[]u32) !bool {
    const response = try doRequest("torrent_start", .{ .ids = ids });
    return response.status == .ok;
}

pub fn torrentStop(ids: ?[]u32) !bool {
    const response = try doRequest("torrent_stop", .{ .ids = ids });
    return response.status == .ok;
}

pub fn torrentDelete(ids: ?[]u32) !bool {
    const response = try doRequest(
        "torrent_remove",
        .{ .ids = ids, .delete_local_data = false },
    );
    return response.status == .ok;
}
