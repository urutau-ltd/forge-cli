const std = @import("std");
const lib = @import("lib");

const Io = std.Io;
const StringHashMap = std.StringHashMap;
const Allocator = std.mem.Allocator;

const DEFAULT_HOST = "sl.urutau-ltd.org:23231";
const DEFAULT_BASE = "https://sl.urutau-ltd.org";

pub fn main(init: std.process.Init) !void {
    const minimal = init.minimal;
    const arena: Allocator = init.arena.allocator();
    const io = init.io;

    const args = try minimal.args.toSlice(arena);
    const opts = try lib.parseFlags(args);

    const home = init.environ_map.get("HOME") orelse {
        std.log.err("Error: environment variable 'HOME' not found!\n", .{});
        return error.HomeNotFound;
    };

    const config_path = opts.config orelse try lib.defaultConfigPath(
        arena,
        home,
    );

    const host = opts.host orelse DEFAULT_HOST;
    const ctx = try lib.resolveContext(
        io,
        arena,
        config_path,
        host,
        DEFAULT_BASE,
    );

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    try stdout.print("Hello from your new CLI! Total arguments: {d}\n", .{args.len});
    try stdout.print("Got base: {s}, and token: {s}\n", .{ ctx.base, ctx.token });
    try stdout.flush();
}
