const std = @import("std");
const Io = std.Io;
const StringHashMap = std.StringHashMap;
const Allocator = std.mem.Allocator;

const KeyEntry = struct {
    type: []const u8, //
    name: []const u8,
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
    pub fn deinit(self: *KeysFile) void {
        self.hosts.deinit();
        self.aliases.deinit();
    }
};

pub const Context = struct {
    base: []const u8,
    token: []const u8,
};

pub fn main(init: std.process.Init) !void {
    const arena: Allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    const io = init.io;
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    try stdout.print("Hello from your new CLI! Total arguments: {d}\n", .{args.len});
    try stdout.flush();
}
