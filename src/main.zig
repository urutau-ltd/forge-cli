const std = @import("std");
const http = std.http;
const Io = std.Io;
const StringHashMap = std.StringHashMap;
const Allocator = std.mem.Allocator;

const lib = @import("lib");

const DEFAULT_HOST = "sl.urutau-ltd.org:23231";
const DEFAULT_BASE = "https://sl.urutau-ltd.org";

const USAGE =
    \\usage: forge-cli ACTION [ARGS] [OPTIONS]
    \\
    \\actions:
    \\  repo-view REPO
    \\  issue-search REPO [QUERY] [--state open|closed|all]
    \\  issue-create REPO TITLE [--body BODY]
    \\  issue-edit REPO NUMBER [--body BODY] [--labels NAME[,NAME...]] [--milestone ID|TITLE] [--assignees USER[,USER...]] [--state open|closed]
    \\  issue-block REPO BLOCKER --blocked N[,N...]
    \\  issue-unblock REPO BLOCKER --blocked N[,N...]
    \\  comment-create REPO NUMBER --body BODY
    \\  comment-list REPO NUMBER [LIMIT]
    \\  comment-edit REPO COMMENT-ID --body BODY
    \\  comment-delete REPO COMMENT-ID
    \\  label-list REPO [LIMIT]
    \\  milestone-list REPO [LIMIT]
    \\  pr-view REPO NUMBER
    \\  pr-create REPO TITLE --head BRANCH --base BRANCH [--body BODY]
    \\
    \\options:
    \\  --config PATH   forgejo-cli keys file (default ~/.local/share/forgejo-cli/keys.json)
    \\  --host HOST     host key in the keys file
;

pub fn main(init: std.process.Init) !void {
    const minimal = init.minimal;
    const arena: Allocator = init.arena.allocator();
    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    const args = (try minimal.args.toSlice(arena))[1..];
    const opts = try lib.parseFlags(args);

    // help is the only action that works without a repository argument.
    // --help falls into the positionals because parseFlags does not know it.
    const first_arg: []const u8 = if (opts.positional_count >= 1)
        opts.positionals[0]
    else
        "";
    if (std.mem.eql(u8, first_arg, "help") or std.mem.eql(u8, first_arg, "--help")) {
        try stdout.print("{s}", .{USAGE});
        try stdout.flush();
        return;
    }

    if (opts.positional_count < 2) {
        std.log.err("Error: expected an action and a repository\n", .{});
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
        if (opts.positional_count < 3) {
            std.log.err("Error: missing issue number for {s}\n", .{action});
            return error.UsageError;
        }

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
    } else if (std.mem.eql(u8, action, "comment-edit")) {
        if (opts.positional_count < 3) {
            std.log.err("Error: missing comment id for {s}\n", .{action});
            return error.UsageError;
        }

        const comment_id = try std.fmt.parseInt(
            u32,
            opts.positionals[2],
            10,
        );

        const body = opts.body orelse "";

        if (std.mem.eql(u8, body, "")) {
            std.log.err(
                "Error: The body of the comment cannot be empty!\n",
                .{},
            );
            return error.IssueCommentEditMissingBody;
        }

        const query = try lib.commentEdit(
            arena,
            &client,
            ctx,
            repo,
            comment_id,
            body,
        );

        try stdout.print(
            "{s}\n",
            .{query},
        );
    } else if (std.mem.eql(u8, action, "comment-list")) {
        if (opts.positional_count < 3) {
            std.log.err("Error: missing issue number for {s}\n", .{action});
            return error.UsageError;
        }

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
    } else if (std.mem.eql(u8, action, "comment-delete")) {
        if (opts.positional_count < 3) {
            std.log.err("Error: missing comment id for {s}\n", .{action});
            return error.UsageError;
        }

        const comment_id = try std.fmt.parseInt(
            u32,
            opts.positionals[2],
            10,
        );

        _ = try lib.commentDelete(
            arena,
            &client,
            ctx,
            repo,
            comment_id,
        );

        try stdout.print(
            "Comment {d} deleted from repository {s}\n",
            .{ comment_id, repo },
        );
    } else if (std.mem.eql(u8, action, "label-list")) {
        var limit: u32 = undefined;

        if (opts.positional_count >= 3) {
            limit = try std.fmt.parseInt(
                u32,
                opts.positionals[2],
                10,
            );
        } else {
            limit = 100;
        }

        const query = try lib.labelList(
            arena,
            &client,
            ctx,
            repo,
            limit,
        );
        try stdout.print("{s}\n", .{query});
    } else if (std.mem.eql(u8, action, "milestone-list")) {
        var limit: u32 = undefined;

        if (opts.positional_count >= 3) {
            limit = try std.fmt.parseInt(
                u32,
                opts.positionals[2],
                10,
            );
        } else {
            limit = 100;
        }

        const query = try lib.milestoneList(
            arena,
            &client,
            ctx,
            repo,
            limit,
        );

        try stdout.print("{s}\n", .{query});
    } else if (std.mem.eql(u8, action, "pr-view")) {
        if (opts.positional_count < 3) {
            std.log.err("Error: missing pull request number for {s}\n", .{action});
            return error.UsageError;
        }

        const number = try std.fmt.parseInt(
            u32,
            opts.positionals[2],
            10,
        );

        const query = try lib.prList(
            arena,
            &client,
            ctx,
            repo,
            number,
        );
        try stdout.print("{s}\n", .{query});
    } else if (std.mem.eql(u8, action, "issue-search")) {
        const q: ?[]const u8 = if (opts.positional_count >= 3)
            opts.positionals[2]
        else
            null;

        const query = try lib.issueSearch(
            arena,
            &client,
            ctx,
            repo,
            q,
            opts.state,
        );
        try stdout.print("{s}\n", .{query});
    } else if (std.mem.eql(u8, action, "issue-create")) {
        const issue_title = opts.positionals[2];
        const body = opts.body orelse "";

        if (std.mem.eql(u8, issue_title, "")) {
            std.log.err(
                "Error: The title of an issue cannot be empty!\n",
                .{},
            );
            return error.IssueMissingTitle;
        }

        const query = try lib.issueCreate(
            arena,
            &client,
            ctx,
            repo,
            issue_title,
            body,
        );

        try stdout.print(
            "{s}\n",
            .{query},
        );
    } else if (std.mem.eql(u8, action, "pr-create")) {
        const title = opts.positionals[2];
        const head = opts.head orelse "";
        const base = opts.base orelse "";

        const body = opts.body orelse "";
        if (std.mem.eql(u8, body, "")) {
            std.log.err(
                "Error: The body of a merge request cannot be empty!\n",
                .{},
            );
            return error.IssueCommentMissingBody;
        }

        if (std.mem.eql(u8, head, "") or std.mem.eql(
            u8,
            base,
            "",
        )) {
            std.log.err(
                "Error: missing either head or base flags for merge request!\n",
                .{},
            );
            return error.MissingPRCreateFlags;
        }

        const query = try lib.prCreate(
            arena,
            &client,
            ctx,
            repo,
            title,
            body,
            base,
            head,
        );

        try stdout.print(
            "{s}\n",
            .{query},
        );
    } else if (std.mem.eql(u8, action, "issue-block")) {
        const blocker = try std.fmt.parseInt(u32, opts.positionals[2], 10);

        const list = opts.blocked orelse "";

        var blocked: [16]u32 = undefined;
        var count: usize = 0;
        var it = std.mem.splitScalar(u8, list, ',');
        while (it.next()) |piece| {
            if (piece.len == 0) continue;
            blocked[count] = try std.fmt.parseInt(u32, piece, 10);
            count += 1;
        }

        if (count == 0) {
            std.log.err("Error: missing --blocked flag!\n", .{});
            return error.MissingBlockedFlag;
        }

        const query = try lib.issueBlock(
            arena,
            &client,
            ctx,
            repo,
            blocker,
            blocked[0..count],
        );
        try stdout.print("{s}\n", .{query});
    } else if (std.mem.eql(u8, action, "issue-unblock")) {
        const blocker = try std.fmt.parseInt(u32, opts.positionals[2], 10);

        const list = opts.blocked orelse "";

        var blocked: [16]u32 = undefined;
        var count: usize = 0;
        var it = std.mem.splitScalar(u8, list, ',');
        while (it.next()) |piece| {
            if (piece.len == 0) continue;
            blocked[count] = try std.fmt.parseInt(u32, piece, 10);
            count += 1;
        }

        if (count == 0) {
            std.log.err("Error: missing --blocked flag!\n", .{});
            return error.MissingBlockedFlag;
        }

        const query = try lib.issueUnblock(
            arena,
            &client,
            ctx,
            repo,
            blocker,
            blocked[0..count],
        );
        try stdout.print("{s}\n", .{query});
    } else if (std.mem.eql(u8, action, "issue-edit")) {
        const number = try std.fmt.parseInt(u32, opts.positionals[2], 10);

        const query = try lib.issueEdit(
            arena,
            &client,
            ctx,
            repo,
            number,
            .{
                .body = opts.body,
                .labels = opts.labels,
                .assignees = opts.assignees,
                .milestone = opts.milestone,
                .state = opts.state,
            },
        );
        try stdout.print("{s}\n", .{query});
    } else {
        std.log.err("Error: unknown action '{s}'\n", .{action});
        return error.UnknownAction;
    }

    try stdout.flush();
}
