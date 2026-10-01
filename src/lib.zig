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
};

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
