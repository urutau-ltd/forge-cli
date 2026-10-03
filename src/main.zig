const std = @import("std");
const http = std.http;
const Io = std.Io;
const StringHashMap = std.StringHashMap;
const Allocator = std.mem.Allocator;

const lib = @import("lib");

const DEFAULT_HOST = "sl.urutau-ltd.org:23231";
const DEFAULT_BASE = "https://sl.urutau-ltd.org";

pub fn main(init: std.process.Init) !void {
    const minimal = init.minimal;
    const arena: Allocator = init.arena.allocator();
    const io = init.io;

    const args = (try minimal.args.toSlice(arena))[1..];
    const opts = try lib.parseFlags(args);

    if (opts.positional_count < 2) {
        std.log.err("Usage: <action> <owner/repo> [OPTIONS]\n", .{});
        return error.UsageError;
    }

    const action = opts.positionals[0];
    const repo = opts.positionals[1];

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

    var client: http.Client = .{ .allocator = arena, .io = io };
    defer client.deinit();

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    if (std.mem.eql(u8, action, "repo-view")) {
        const query = try lib.repoView(
            arena,
            &client,
            ctx,
            repo,
        );

        try stdout.print(
            "{s}\n",
            .{query},
        );
    } else if (std.mem.eql(u8, action, "comment-create")) {
        const number = try std.fmt.parseInt(
            u32,
            opts.positionals[2],
            10,
        );

        const body = opts.body orelse "";
        if (std.mem.eql(u8, body, "")) {
            std.log.err(
                "Error: The body of an issue comment cannot be empty!\n",
                .{},
            );
            return error.IssueCommentMissingBody;
        }

        const query = try lib.commentCreate(
            arena,
            &client,
            ctx,
            repo,
            number,
            body,
        );

        try stdout.print(
            "{s}\n",
            .{query},
        );
    } else if (std.mem.eql(u8, action, "comment-list")) {
        const number = try std.fmt.parseInt(
            u32,
            opts.positionals[2],
            10,
        );

        var limit: u32 = undefined;

        if (opts.positional_count >= 4) {
            limit = try std.fmt.parseInt(
                u32,
                opts.positionals[3],
                10,
            );
        } else {
            limit = 100;
        }

        const query = try lib.commentList(
            arena,
            &client,
            ctx,
            repo,
            number,
            limit,
        );
        try stdout.print("{s}\n", .{query});
    } else {
        std.log.err("Error: unknown action '{s}'\n", .{action});
        return error.UnknownAction;
    }

    try stdout.flush();
}
