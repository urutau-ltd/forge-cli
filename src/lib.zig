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
    hosts: StringHashMap(KeyEntry), //
    aliases: StringHashMap([]const u8),

    // Initializer
    pub fn init(allocator: Allocator) KeysFile {
        return .{
            .hosts = StringHashMap(KeyEntry).init(allocator),
            .aliases = StringHashMap([]const u8).init(allocator),
        };
    }

    // Free
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

pub const Context = struct {
    base: []const u8,
    token: []const u8,

    pub fn deinit(self: Context, allocator: Allocator) void {
        allocator.free(self.base);
        allocator.free(self.token);
    }
};

/// Returns a deserialized JSON keys file into a KeysFile structure, every
/// time you use this function you should deinit the result of this function
/// using your allocator.
///
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

    // Limit buffer to 4KB
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
        &[_][]const u8{ home, ".local", "share", "forgejo-cli", "keys.json" },
    );
}

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
