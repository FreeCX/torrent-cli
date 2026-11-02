const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const http = std.http;
const json = std.json;

const log = std.log.scoped(.rpc);

const session_id_key = "X-Transmission-Session-Id";

// tiny part of http response
pub const Response = struct {
    body: []u8,
    status: http.Status,
};

// TODO:
//  - выделить класс ошибок для всех !
//  - перейти на Reader и Writer по буферам
pub const Client = struct {
    id: u64,
    session_id_len: usize,
    client: http.Client,
    uri: std.Uri,

    read_buffer: []u8,
    write_buffer: []u8,

    session_id: [256]u8 = undefined,
    decompress_buffer: [std.compress.flate.max_window_len]u8 = undefined,

    max_attempt_count: u8 = 3,

    pub fn init(
        io: Io,
        gpa: mem.Allocator,
        host: []const u8,
        port: u16,
        read_buffer: []u8,
        write_buffer: []u8,
    ) Client {
        return Client{
            .id = 0,
            .session_id_len = 0,
            .client = http.Client{ .allocator = gpa, .io = io },
            .uri = std.Uri{
                .scheme = "http",
                .host = .{ .percent_encoded = host },
                .port = port,
                .path = .{ .percent_encoded = "/transmission/rpc/" },
            },
            .read_buffer = read_buffer,
            .write_buffer = write_buffer,
        };
    }

    pub fn deinit(self: *Client) void {
        self.id = 0;
        self.session_id_len = 0;
        self.client.deinit();
    }

    fn nextId(self: *Client) u64 {
        const current = self.id;
        self.id += 1;
        return current;
    }

    fn jsonify(self: *Client, data: anytype) ![]u8 {
        var writer = Io.Writer.fixed(self.write_buffer);
        var stringifier = json.Stringify{
            .writer = &writer,
            .options = .{ .emit_null_optional_fields = false },
        };
        try stringifier.write(data);
        return self.write_buffer[0..writer.end];
    }

    pub fn request(self: *Client, method: []const u8, params: anytype) !Response {
        for (0..self.max_attempt_count) |attempt| {
            log.debug("request attempt={d}", .{attempt + 1});

            // construct request
            var req = try self.client.request(.POST, self.uri, .{
                .headers = .{
                    .content_type = .{ .override = "application/json; utf-8" },
                },
            });
            if (self.session_id_len > 0) {
                req.extra_headers = &[_]http.Header{http.Header{
                    .name = session_id_key,
                    .value = self.session_id[0..self.session_id_len],
                }};
            }
            defer req.deinit();

            // send head + body
            const body = try self.jsonify(.{
                .id = self.nextId(),
                .jsonrpc = "2.0",
                .method = method,
                .params = params,
            });
            log.debug("request body={s}", .{body});
            _ = try req.sendBodyComplete(body);

            // responce headers
            var response = try req.receiveHead(self.read_buffer);
            log.debug("status_code={any}", .{response.head.status});
            if (response.head.status == .conflict) {
                var it = response.head.iterateHeaders();
                while (it.next()) |header| {
                    if (mem.eql(u8, header.name, session_id_key)) {
                        log.debug("session_id={s}", .{header.value});
                        self.session_id_len = header.value.len;
                        if (self.session_id_len > self.session_id.len) {
                            return error.SessionIdTooLong;
                        }
                        @memcpy(self.session_id[0..self.session_id_len], header.value);
                    }
                }
                continue;
            }

            // response body
            var transfer_buffer: [64]u8 = undefined;
            var decompress: http.Decompress = undefined;
            const reader = response.readerDecompressing(
                &transfer_buffer,
                &decompress,
                &self.decompress_buffer,
            );
            const readed = try reader.readSliceShort(self.read_buffer);
            if (readed == 0) {
                return error.MissingBody;
            }
            if (readed == self.read_buffer.len) {
                return error.ResponseTooLarge;
            }
            log.debug("response={s}", .{self.read_buffer[0..readed]});

            return Response{
                .body = self.read_buffer[0..readed],
                .status = response.head.status,
            };
        }

        return error.TooManyRetries;
    }
};
