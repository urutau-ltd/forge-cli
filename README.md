# forge-cli

Small, fast client for the `sl.urutau-ltd.org` forgejo instance (`forgejo-cli`
wasn't working for me on Guix and this was the perfect excuse for me to learn
how to code in Zig).

It reads the original `forgejo-cli` configuration file, to avoid reinventing the
configuration file.

The binary is ~1.1 MB and takes some time to compile. Mind this when installing
the guix package.

## Build

```shell
$ maak build
```

Or as a reproducible Guix package:

```shell
$ guix build -f ./guix.scm
```

## Usage

```shell
$ forge-cli
usage: forge-cli ACTION [ARGS] [OPTIONS]

actions:
  repo-view REPO
  issue-search REPO [QUERY] [--state open|closed|all]
  issue-create REPO TITLE [--body BODY]
  issue-edit REPO NUMBER [--body BODY] [--labels NAME[,NAME...]] [--milestone ID|TITLE] [--assignees USER[,USER...]] [--state open|closed]
  issue-block REPO BLOCKER --blocked N[,N...]
  issue-unblock REPO BLOCKER --blocked N[,N...]
  comment-create REPO NUMBER --body BODY
  comment-list REPO NUMBER [LIMIT]
  comment-edit REPO COMMENT-ID --body BODY
  comment-delete REPO COMMENT-ID
  label-list REPO [LIMIT]
  milestone-list REPO [LIMIT]
  pr-view REPO NUMBER
  pr-create REPO TITLE --head BRANCH --base BRANCH [--body BODY]

options:
  --config PATH   forgejo-cli keys file (default ~/.local/share/forgejo-cli/keys.json)
  --host HOST     host key in the keys file
```

## Configuration

Reads `~/.local/share/forgejo-cli/keys.json`. Use `--config PATH` for another
file and `--host HOST` to pick a host entry.

## Development

```shell
$ maak test
```

Run the test suite. Tests live in `src/lib.zig`; `src/main.zig` is the CLI
layer.

---

_And I think to myself. What a wonderful world._
