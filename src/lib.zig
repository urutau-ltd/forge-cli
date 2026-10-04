const std = @import("std");
const StringHashMap = std.StringHashMap;
const Allocator = std.mem.Allocator;
const Io = std.Io;
const json = std.json;

/// Represents a Forgejo CLI instance key entry
const KeyEntry = struct {
    /// The type of Key, usually it's "Application".
    type: []const u8,
    /// The user-readable name for the instance key.
    name: []const u8,
    /// The token value itself provided by the forgejo instance
    token: []const u8,
};

/// Represents the entire keys.json file
pub const KeysFile = struct {
    /// Represents the Child JSON in the keys.json file. Where we have the
    /// "hosts" : { ... } form to be used.
    hosts: StringHashMap(KeyEntry),
    /// Represents a given shorthand alias for a host, also a JSON with
    /// a map for name -> host inside in the keys.json file.
    aliases: StringHashMap([]const u8),

    /// Initializes both Hash maps when instantiating this struct. Make sure
    /// to use an allocator for initialization whether it's an arena or
    /// general purpose allocator, or the testing allocator to detect memory
    /// errors.
    pub fn init(allocator: Allocator) KeysFile {
        return .{
            .hosts = StringHashMap(KeyEntry).init(allocator),
            .aliases = StringHashMap([]const u8).init(allocator),
        };
    }

    /// Deinitializing the KeysFile will clean up all JSON record values inside
    /// it. Make sure to use the same allocator, you can call it with defer
    /// as it doesn't return an error.
    pub fn deinit(self: *KeysFile, allocator: Allocator) void {
        var host_it = self.hosts.iterator();
        while (host_it.next()) |kv| {
            allocator.free(kv.key_ptr.*);
            allocator.free(kv.value_ptr.type);
            allocator.free(kv.value_ptr.name);
            allocator.free(kv.value_ptr.token);
        }
        self.hosts.deinit();

        var alias_it = self.aliases.iterator();
        while (alias_it.next()) |kv| {
            allocator.free(kv.key_ptr.*);
            allocator.free(kv.value_ptr.*);
        }

        self.aliases.deinit();
    }
};

/// Represents the request context needed to make a successful query to the
/// forgejo API.
pub const Context = struct {
    /// Represents the base URL that the query will use to send it's requests.
    base: []const u8,
    /// Represents the secret token created by the forgejo instance, this one
    /// is particularly used inside the Authorization header, do not call this
    /// for anything outside this purpose!
    token: []const u8,

    /// When deinitializing this, make sure to pass your allocator to
    /// free both base and token copies.
    pub fn deinit(self: Context, allocator: Allocator) void {
        allocator.free(self.base);
        allocator.free(self.token);
    }
};

/// Represents a parsed collection of CLI arguments for post-processing
pub const Options = struct {
    /// Optional field for the path of the configuration file in case it's not
    /// present in the default intended path.
    config: ?[]const u8 = null,

    /// The keys.json file host without schema. Used for resolveContext.
    host: ?[]const u8 = null,

    /// The JSON payload required by several forgejo endpoint operations and
    /// the CLI's --body flag.
    body: ?[]const u8 = null,

    /// Value flag for head of pr-create
    head: ?[]const u8 = null,

    /// Value flag for base of pr-create
    base: ?[]const u8 = null,

    /// Represents the positional arguments for the CLI. We do not need more
    /// than 16 in the entire program's lifecycle AFAIK.
    positionals: [16][]const u8 = undefined,

    /// Counter for positional arguments, used for safety/correct operations
    positional_count: usize = 0,
};

/// Options for the api function exported in this module.
pub const ApiOptions = struct {
    /// Method used to send the fetch request
    method: std.http.Method = .GET,
    /// Request body
    body: ?[]const u8 = null,
    /// Headers sent by the fetch method.
    headers: []const std.http.Header = &.{},
};

/// Calls a Forgejo API endpoint. It needs an allocator for both request and
/// response purposes, the returned slice is owned by the caller and gets freed
/// with allocator.free. If it fails, HttpRedirection, HttpClientError,
/// HttpServerError and HttpRequestFailed errors are raised alongside
/// network IO errors that may arise. On HTTP errors, the status code, URL and
/// response body are printed to stderr before the error is returned.
///
/// NOTE: There's a special case, if the response comes with a response code of
/// 204 (No Content) the switch inside the function will make the function
/// return an empty slice to mimic the original TypeScript program behaviour.
///
/// TODO: This function doesn't have any tests, I'm not
/// sick on the head enough to mock an entire HTTP request loop in zig.
pub fn api(
    allocator: Allocator,
    client: *std.http.Client,
    ctx: Context,
    path: []const u8,
    options: ApiOptions,
) ![]const u8 {
    const url_str = try std.fmt.allocPrint(
        allocator,
        "{s}/api/v1{s}",
        .{
            ctx.base,
            path,
        },
    );
    defer allocator.free(url_str);

    const auth_val = try std.fmt.allocPrint(
        allocator,
        "token {s}",
        .{ctx.token},
    );
    defer allocator.free(auth_val);

    var response_writer = std.Io.Writer.Allocating.init(
        allocator,
    );
    errdefer response_writer.deinit();

    var extra_headers: [2]std.http.Header = undefined;
    var count: usize = 0;

    extra_headers[count] = .{
        .name = "Authorization",
        .value = auth_val,
    };
    count += 1;

    if (options.body != null) {
        extra_headers[count] = .{
            .name = "Content-Type",
            .value = "application/json",
        };
        count += 1;
    }

    const req = try client.fetch(.{
        .location = .{ .url = url_str },
        .method = options.method,
        .extra_headers = extra_headers[0..count],
        .payload = options.body,
        .response_writer = &response_writer.writer,
        // BUG: A 204 response without Content-Length hangs the function call
        // until timeout occurrs. This is from the zig's stdlib side.
        .keep_alive = false,
    });

    const status_code = @intFromEnum(req.status);
    const body = try response_writer.toOwnedSlice();
    errdefer allocator.free(body);

    switch (status_code) {
        200...299 => {},
        300...399 => {
            std.debug.print("HTTP {d} for {s}: {s}\n", .{
                status_code,
                url_str,
                body,
            });
            return error.HttpRedirection;
        },
        400...499 => {
            std.debug.print("HTTP {d} for {s}: {s}\n", .{
                status_code,
                url_str,
                body,
            });
            return error.HttpClientError;
        },
        500...599 => {
            std.debug.print("HTTP {d} for {s}: {s}\n", .{
                status_code,
                url_str,
                body,
            });
            return error.HttpServerError;
        },
        else => {
            std.debug.print("HTTP {d} for {s}: {s}\n", .{
                status_code,
                url_str,
                body,
            });
            return error.HttpRequestFailed;
        },
    }

    return body;
}

/// Receives the process CLI arguments passed by the shell and serializes them
/// into the Options structure.
///
/// Note: Positional args are stored using a fixed inline buffer inside the
/// Options struct. This avoids the need for dynamic memory allocation and
/// a corresponding deinit lifecycle, For standard CLI usage, an arbitrary
/// limit like 16 simplifies memory management significantly...for me at least.
pub fn parseFlags(args: []const []const u8) !Options {
    var opts = Options{};
    var i: usize = 0;

    while (i < args.len) : (i += 1) {
        const arg: []const u8 = args[i];

        if (std.mem.eql(
            u8,
            arg,
            "--config",
        ) or std.mem.eql(u8, arg, "-c")) {
            if (i + 1 >= args.len) return error.MissingValue;
            i += 1;
            opts.config = args[i];
        } else if (std.mem.eql(
            u8,
            arg,
            "--host",
        ) or std.mem.eql(u8, arg, "-h")) {
            if (i + 1 >= args.len) return error.MissingValue;
            i += 1;
            opts.host = args[i];
        } else if (std.mem.eql(u8, arg, "--body") or std.mem.eql(
            u8,
            arg,
            "-b",
        )) {
            if (i + 1 >= args.len) return error.MissingValue;
            i += 1;
            opts.body = args[i];
        } else if (std.mem.eql(u8, arg, "--head")) {
            if (i + 1 >= args.len) return error.MissingValue;
            i += 1;
            opts.head = args[i];
        } else if (std.mem.eql(u8, arg, "--base")) {
            if (i + 1 >= args.len) return error.MissingValue;
            i += 1;
            opts.base = args[i];
        } else {
            // Unrecognized flags or regular values are treated as positional
            // arguments
            if (opts.positional_count >= opts.positionals.len) {
                return error.TooManyPositionalArguments;
            }

            opts.positionals[opts.positional_count] = arg;
            opts.positional_count += 1;
        }
    }

    return opts;
}

/// Returns a deserialized JSON keys file into a KeysFile structure, every
/// time you use this function you should deinit the result of this function
/// using your allocator.
///
/// Also, mind that this function reads files no bigger than 10MB.
/// It returns either error.FileNotFound, json.SyntaxError, etc if the keys file
/// doesn't exist or if it contains a malformed JSON.
pub fn readKeys(io: Io, allocator: Allocator, path: []const u8) !KeysFile {
    const file = Io.Dir.cwd().openFile(io, path, .{}) catch |err| {
        std.debug.print("unable to read forgejo-cli keys at {s}: {s}\n", //
            .{ path, @errorName(err) });
        return err;
    };
    defer file.close(io);

    // Limit read buffer to 4KB
    var read_buffer: [4096]u8 = undefined;
    var reader = file.reader(io, &read_buffer);

    // I doubt a file of this kind would grow over 10MB big
    const source = try reader.interface.allocRemaining(
        allocator,
        .limited(10 * 1024 * 1024),
    );
    defer allocator.free(source);

    // Parse the JSON into an unknown type
    var parsed = try json.parseFromSlice(json.Value, //
        allocator, source, .{});
    defer parsed.deinit();

    // Map the parsed value into a struct
    const root = parsed.value.object;
    var keys_file: KeysFile = KeysFile.init(allocator);
    errdefer keys_file.deinit(allocator);

    if (root.get("hosts")) |hosts_val| {
        var it = hosts_val.object.iterator();
        while (it.next()) |kv| {
            const host_obj = kv.value_ptr.*.object;

            const entry = KeyEntry{
                .type = try allocator.dupe(
                    u8,
                    host_obj.get("type").?.string,
                ),

                .name = try allocator.dupe(
                    u8,
                    host_obj.get("name").?.string,
                ),

                .token = try allocator.dupe(
                    u8,
                    host_obj.get("token").?.string,
                ),
            };

            try keys_file.hosts.put(
                try allocator.dupe(u8, kv.key_ptr.*),
                entry,
            );
        }
    }

    if (root.get("aliases")) |aliases_val| {
        var it = aliases_val.object.iterator();
        while (it.next()) |kv| {
            try keys_file.aliases.put(
                try allocator.dupe(u8, kv.key_ptr.*),
                try allocator.dupe(u8, kv.value_ptr.*.string),
            );
        }
    }

    return keys_file;
}

/// Returns the default configuration path of the forgejo-cli given a resolved
/// HOME environment variable, it needs an allocator to construct the full
/// file path, the caller must free the returned slice with allocator.free.
pub fn defaultConfigPath(allocator: Allocator, home: []const u8) ![]const u8 {
    return try std.fs.path.join(
        allocator,
        &[_][]const u8{
            home,
            ".local",
            "share",
            "forgejo-cli",
            "keys.json",
        },
    );
}

/// Returns the token and trimmed default base from the provided keys file
/// at config_path. Will fail if the requested host key is not found on the
/// file. Caller must ensure they free both base and token after using their
/// values.
pub fn resolveContext(
    io: Io,
    allocator: Allocator,
    config_path: []const u8,
    host: []const u8,
    default_base: []const u8,
) !Context {
    var keys = try readKeys(io, allocator, config_path);
    defer keys.deinit(allocator);

    const entry = keys.hosts.get(host) orelse {
        std.debug.print(
            "no token found for host {s} in {s}",
            .{
                host,
                config_path,
            },
        );

        return error.NoTokenFound;
    };

    const raw_base = if (keys.aliases.get(host)) |alias| alias else default_base;
    const trimmed_base = std.mem.trimEnd(u8, raw_base, "/");

    const base_dupe = try allocator.dupe(u8, trimmed_base);
    errdefer allocator.free(base_dupe);

    const token_dupe = try allocator.dupe(u8, entry.token);

    return Context{
        .base = base_dupe,
        .token = token_dupe,
    };
}

// ===> API ENDPOINT ABSTRACTIONS

/// Updates a given Forgejo comment by ID inside a given repository path. It
/// returns the updated comment and the result is owned by the caller.
pub fn commentEdit(
    allocator: Allocator,
    client: *std.http.Client,
    ctx: Context,
    repo: []const u8,
    comment_id: u32,
    comment: []const u8,
) ![]const u8 {
    const path = try std.fmt.allocPrint(
        allocator,
        "/repos/{s}/issues/comments/{d}",
        .{ repo, comment_id },
    );

    const body = try std.json.Stringify.valueAlloc(
        allocator,
        .{ .body = comment },
        .{},
    );

    defer allocator.free(path);
    defer allocator.free(body);

    return api(allocator, client, ctx, path, .{
        .method = .PATCH,
        .body = body,
    });
}

/// Deletes a given Forgejo comment by ID. It returns the deleted comment
/// status and the result is owned by the caller.
pub fn commentDelete(
    allocator: Allocator,
    client: *std.http.Client,
    ctx: Context,
    repo: []const u8,
    comment_id: u32,
) ![]const u8 {
    const path = try std.fmt.allocPrint(
        allocator,
        "/repos/{s}/issues/comments/{d}",
        .{ repo, comment_id },
    );

    defer allocator.free(path);
    return api(allocator, client, ctx, path, .{
        .method = .DELETE,
    });
}

/// Lists the comments of a given Forgejo issue. Returns a JSON value owned by
/// the caller.
pub fn commentList(
    allocator: Allocator,
    client: *std.http.Client,
    ctx: Context,
    repo: []const u8,
    number: u32,
    limit: u32,
) ![]const u8 {
    const path = try std.fmt.allocPrint(
        allocator,
        "/repos/{s}/issues/{d}/comments?limit={d}",
        .{
            repo,
            number,
            limit,
        },
    );

    defer allocator.free(path);
    return api(allocator, client, ctx, path, .{});
}

/// Creates a comment inside a given Forgejo issue. The returned JSON is the
/// created comment and it's owned by the caller.
pub fn commentCreate(
    allocator: Allocator,
    client: *std.http.Client,
    ctx: Context,
    repo: []const u8,
    issue_number: u32,
    comment: []const u8,
) ![]const u8 {
    const path = try std.fmt.allocPrint(
        allocator,
        "/repos/{s}/issues/{d}/comments",
        .{ repo, issue_number },
    );

    const body = try std.json.Stringify.valueAlloc(
        allocator,
        .{ .body = comment },
        .{},
    );

    defer allocator.free(path);
    defer allocator.free(body);

    return api(allocator, client, ctx, path, .{
        .method = .POST,
        .body = body,
    });
}

/// Returns a JSON containing details about a given Forgejo repository. The
/// returned JSON is owned by the caller.
pub fn repoView(
    allocator: Allocator,
    client: *std.http.Client,
    ctx: Context,
    repo: []const u8,
) ![]const u8 {
    const path = try std.fmt.allocPrint(
        allocator,
        "/repos/{s}",
        .{repo},
    );

    defer allocator.free(path);
    return api(allocator, client, ctx, path, .{});
}

/// Lists the labels of a given Forgejo repository.
/// Returns a JSON value owned by the caller.
pub fn labelList(
    allocator: Allocator,
    client: *std.http.Client,
    ctx: Context,
    repo: []const u8,
    limit: u32,
) ![]const u8 {
    const path = try std.fmt.allocPrint(
        allocator,
        "/repos/{s}/labels?limit={d}",
        .{
            repo,
            limit,
        },
    );

    defer allocator.free(path);
    return api(allocator, client, ctx, path, .{});
}

/// Lists the milestones of a given Forgejo repository.
/// Returns a JSON value owned by the caller.
pub fn milestoneList(
    allocator: Allocator,
    client: *std.http.Client,
    ctx: Context,
    repo: []const u8,
    limit: u32,
) ![]const u8 {
    const path = try std.fmt.allocPrint(
        allocator,
        "/repos/{s}/milestones?state=all&limit={d}",
        .{
            repo,
            limit,
        },
    );

    defer allocator.free(path);
    return api(allocator, client, ctx, path, .{});
}

/// Lists the merge requests of a given Forgejo repository. Returns a JSON value
/// owned by the caller.
pub fn prList(
    allocator: Allocator,
    client: *std.http.Client,
    ctx: Context,
    repo: []const u8,
    number: u32,
) ![]const u8 {
    const path = try std.fmt.allocPrint(
        allocator,
        "/repos/{s}/pulls/{d}",
        .{
            repo,
            number,
        },
    );

    defer allocator.free(path);
    return api(allocator, client, ctx, path, .{});
}

/// Creates an issue inside a given Forgejo repository. The returned JSON is the
/// created issue and it's owned by the caller.
pub fn issueCreate(
    allocator: Allocator,
    client: *std.http.Client,
    ctx: Context,
    repo: []const u8,
    issue_title: []const u8,
    issue_body: []const u8,
) ![]const u8 {
    const path = try std.fmt.allocPrint(
        allocator,
        "/repos/{s}/issues",
        .{repo},
    );

    const body = try std.json.Stringify.valueAlloc(
        allocator,
        .{
            .title = issue_title,
            .body = issue_body,
        },
        .{},
    );

    defer allocator.free(path);
    defer allocator.free(body);

    return api(allocator, client, ctx, path, .{
        .method = .POST,
        .body = body,
    });
}

/// Creates a merge request inside a given Forgejo repository. The returned
/// JSON is the created merge request and it's owned by the caller.
pub fn prCreate(
    allocator: Allocator,
    client: *std.http.Client,
    ctx: Context,
    repo: []const u8,
    pr_title: []const u8,
    pr_body: []const u8,
    pr_base: []const u8,
    pr_head: []const u8,
) ![]const u8 {
    const path = try std.fmt.allocPrint(
        allocator,
        "/repos/{s}/pulls",
        .{repo},
    );

    const body = try std.json.Stringify.valueAlloc(
        allocator,
        .{
            .title = pr_title,
            .head = pr_head,
            .base = pr_base,
            .body = pr_body,
        },
        .{},
    );

    defer allocator.free(path);
    defer allocator.free(body);

    return api(allocator, client, ctx, path, .{
        .method = .POST,
        .body = body,
    });
}

// ===> TESTS START HERE

test "parseFlags should handle valid CLI options and positionals properly" {
    const args = [_][]const u8{
        "--config",
        "settings.json",
        "-h",
        "foo",
        "repo-view",
    };
    const opts = try parseFlags(&args);

    // Assert flags
    try std.testing.expectEqualStrings("settings.json", opts.config.?);
    try std.testing.expectEqualStrings("foo", opts.host.?);

    // Assert positional args
    try std.testing.expectEqual(@as(usize, 1), opts.positional_count);
    try std.testing.expectEqualStrings("repo-view", opts.positionals[0]);
}

test "parseFlags should error out when a flag has no provided value" {
    const args = [_][]const u8{"--config"};
    try std.testing.expectError(error.MissingValue, parseFlags(&args));
}

test "parseFlags should error out when the positional arguments limit is exceeded" {
    const args = [_][]const u8{
        "1",
        "2",
        "3",
        "4",
        "5",
        "6",
        "7",
        "8",
        "9",
        "10",
        "11",
        "12",
        "13",
        "14",
        "15",
        "16",
        "17",
    };
    try std.testing.expectError(
        error.TooManyPositionalArguments,
        parseFlags(&args),
    );
}

test "resolveContext should fallback to the default base and trim the trailing slash" {
    const allocator: Allocator = std.testing.allocator;
    const io: Io = std.testing.io;

    const DEFAULT_BASE = "https://sl.urutau-ltd.org/";
    const DEFAULT_HOST = "sl.urutau-ltd.org";

    var tmp: std.testing.TmpDir = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Apparently this is the way of mocking JSON
    const payload =
        \\{
        \\  "hosts": {
        \\    "sl.urutau-ltd.org" : {
        \\      "type": "Application",
        \\      "name": "testingkey",
        \\      "token": "0000000000000000000000000000000000000000"
        \\    }
        \\  },
        \\  "aliases": { "sl": "sl.urutau-ltd.org" },
        \\  "default_ssh": []
        \\}
    ;

    // write the mocked JSON into the temporal directory we did earlier
    try tmp.dir.writeFile(
        std.testing.io,
        .{ .sub_path = "test_keys.json", .data = payload },
    );

    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const abs_path_len = try tmp.dir.realPathFile(
        std.testing.io,
        "test_keys.json",
        &path_buffer,
    );
    const abs_path = path_buffer[0..abs_path_len];

    const context = try resolveContext(
        io,
        allocator,
        abs_path,
        DEFAULT_HOST,
        DEFAULT_BASE,
    );

    defer allocator.free(context.base);
    defer allocator.free(context.token);

    try std.testing.expectEqualStrings(
        "https://sl.urutau-ltd.org",
        context.base,
    );

    try std.testing.expectEqualStrings(
        "0000000000000000000000000000000000000000",
        context.token,
    );
}

test "defaultConfigPath should return the default forgejo-cli configuration" {
    const allocator: Allocator = std.testing.allocator;

    const fake_home: []const u8 = "/home/zig";
    const config_path: []const u8 = try defaultConfigPath(
        allocator,
        fake_home,
    );
    defer allocator.free(config_path);

    try std.testing.expectEqualStrings(
        "/home/zig/.local/share/forgejo-cli/keys.json",
        config_path,
    );
}

test "readKeys should load keys from a valid JSON file" {
    const allocator: Allocator = std.testing.allocator;
    const io: Io = std.testing.io;

    var tmp: std.testing.TmpDir = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Apparently this is the way of mocking JSON
    const payload =
        \\{
        \\  "hosts": {
        \\    "sl.urutau-ltd.org" : {
        \\      "type": "Application",
        \\      "name": "testingkey",
        \\      "token": "0000000000000000000000000000000000000000"
        \\    }
        \\  },
        \\  "aliases": { "sl": "sl.urutau-ltd.org" },
        \\  "default_ssh": []
        \\}
    ;

    // write the mocked JSON into the temporal directory we did earlier
    try tmp.dir.writeFile(
        std.testing.io,
        .{ .sub_path = "test_keys.json", .data = payload },
    );

    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const abs_path_len = try tmp.dir.realPathFile(
        std.testing.io,
        "test_keys.json",
        &path_buffer,
    );
    const abs_path = path_buffer[0..abs_path_len];

    var keys_file = try readKeys(io, allocator, abs_path);
    defer keys_file.deinit(allocator);

    try std.testing.expect(keys_file.hosts.contains("sl.urutau-ltd.org"));

    const alias_val = keys_file.aliases.get("sl").?;
    try std.testing.expectEqualStrings("sl.urutau-ltd.org", alias_val);
}
