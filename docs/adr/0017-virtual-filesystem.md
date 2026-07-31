# ADR-0017: Session-local virtual filesystem

- Status: Accepted
- Date: 2026-07-31

## Context

Sandbox commands need deterministic file-like state without gaining any path to host
storage, persistent data, or shared mutable namespaces.

## Decision

Each sandbox session owns one bounded in-memory POSIX-like tree. It is created with
the session, deeply copies an optional bounded initial-tree description, and is released
on destruction. The two node kinds are directories and opaque-byte regular files. The
root always exists. There are no mounts, live host storage, persistence, symlinks, hard
links, devices, descriptors, ownership, permissions, timestamps, or executable
semantics. Filesystem contents and mutations are not terminal semantics, recordings,
or checkpoints.

Paths are Lua byte strings. `/` separates components and NUL is forbidden; only a
complete `.` or `..` component has lexical meaning. Resolution collapses repeated
slashes, removes `.`, clamps `..` at root, and returns canonical absolute components,
not a host path. All other bytes, including invalid UTF-8, are opaque and compare by
unsigned byte order. Empty paths fail. A non-root trailing slash requires the resolved
target to be a directory.

The session stores cwd as canonical absolute components plus its logical directory
node. Relative paths resolve from cwd. Renaming cwd or its ancestor preserves that
logical node and derives its new canonical cwd after the atomic rename.

Immutable per-session limits bound path and canonical bytes, components, nodes,
directories, files, file bytes, total file bytes, directory entries, initial depth,
and returned list/read bytes. Configuration only tightens project defaults. Operations
validate all bounds and arithmetic before mutation; failures leave the tree, cwd, and
accounting unchanged. `write_file` replaces a whole file atomically; `append_file`
requires an existing regular file and never creates one implicitly. `remove` accepts
only files or empty directories, never root, cwd, or a cwd ancestor. `rename` never
replaces a destination and rejects moves into a directory's own subtree.

`vfs.read`, `vfs.write`, and `vfs.chdir` are independent command capabilities. A
session's dense host grant set is copied at construction and checked before a handler
starts. A handler receives `context.fs` only for declared, granted filesystem
capabilities: read exposes `stat`, `list`, `read_file`, and `get_cwd`; write exposes
the mutation methods; chdir exposes `change_directory`. The facade expires when that
single synchronous invocation returns. It never exposes nodes, roots, accounting,
host paths, other sessions, or a filesystem facade to completion callbacks.

## Consequences

Sandbox file state is deterministic for equal initial trees, commands, limits, cwd,
and capability grants. Directory lists use explicit bytewise ascending order. Stable
typed sandbox-command reasons include `empty_path`, `path_too_large`,
`component_too_large`, `too_many_components`, `invalid_path_byte`, `not_found`,
`already_exists`, `not_a_directory`, `is_a_directory`, `directory_not_empty`,
`root_operation_forbidden`, `cwd_operation_forbidden`, `invalid_move`,
`file_too_large`, `filesystem_full`, `directory_full`, `invalid_range`,
`capability_denied`, `unsupported_capability`, and `resource_limit`.

Host mounts, snapshots/import/export, durable storage, path ACLs, filesystem-aware
completion, recursive deletion, and any external provider require a separate ADR.
