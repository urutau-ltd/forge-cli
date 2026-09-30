const std = @import("std");
const lib = @import("lib");

const Io = std.Io;
const StringHashMap = std.StringHashMap;
const Allocator = std.mem.Allocator;

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
