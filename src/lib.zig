const std = @import("std");
const StringHashMap = std.StringHashMap;
const Allocator = std.mem.Allocator;
const fs = std.fs;
const json = std.json;

/// Represents a Forgejo CLI instance key entry
const KeyEntry = struct {
    /// The type of Key, usually it's "Application".
    type: []const u8, //
    /// The user-readable name for the instance key.
    name: []const u8,
    /// The token value itself provided by the forgejo instance
    token: []const u8,
};

pub const KeysFile = struct {
    hosts: StringHashMap(KeyEntry), //
    aliases: StringHashMap([]const u8),

    // Initializer
    pub fn init(allocator: Allocator) KeysFile {
        return .{
            .hosts = StringHashMap(KeyEntry).init(allocator), //
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

pub fn readKeys(allocator: Allocator, path: []const u8) !KeysFile {
    const file = fs.cwd().openFile(path, .{}) catch |err| {
        std.debug.print("unable to read forgejo-cli keys at {s}: {s}\n", //
            .{ path, @errorName(err) });
        return err;
    };

    defer file.close();

    // I doubt a file of this kind would grow over 10MB big
    const source = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(source);

    // Parse the JSON into an unknown type
    var parsed = json.parseFromSlice(json.Value, //
        allocator, source, .{});
    defer parsed.deinit();

    // Map the parsed value into a struct
    const root = parsed.value.object;
    var keys_file: KeysFile = KeysFile.init(allocator);
    errdefer keys_file.deinit();

    if (root.get("hosts")) |hosts_val| {
        var it = hosts_val.object.iterator();
        while (it.next()) |kv| {
            const host_obj = kv.value_ptr.*.object;

            const entry = KeyEntry{
                .type = try allocator.dupe(u8, host_obj.get("type").?.string),
                .name = try allocator.dupe(u8, host_obj.get("name").?.string),
                .token = try allocator.dupe(u8, host_obj.get("token").?.string),
            };
            try keys_file.hosts.put(try allocator.dupe(u8, kv.key_ptr.*), entry);
        }
    }

    return keys_file;
}
