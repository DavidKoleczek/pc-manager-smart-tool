# Library Reference

Every capability of PC Manager is reachable from the `pc_manager` library.
All other surfaces, including the CLI, are thin wrappers over the library and add no capability of their own.

The intelligent capabilities shell out to the [Claude Code CLI](https://code.claude.com/docs/en/cli-reference) with structured output, behind a thin internal interface so the intelligence layer can be swapped for something else.
An intelligent capability invoked without the Claude Code CLI on PATH, or without its credentials [configured](02-configuration.md), fails naming exactly what to install or configure.
Deterministic capabilities run with no model provider configured.

## Manifest

Returns the tool's manifest, the frontmatter of the `SMART_TOOL.md` shipped inside the package, as structured data: name, version, description, use cases, supported platforms, and environment prerequisites.
This is the same file the `smart-tool.json` descriptor at the repository root points to, so a caller reads it through the library after installation instead of locating the file.

```zig
pub fn loadManifest(gpa: Allocator) !Manifest
```

## Scan

A scan is a deterministic, read-only snapshot of one aspect of the system, returned as structured data.
Each scan kind is its own capability with its own result type; [Suggest](#suggest) consumes scans.
Nothing in a scan consults a model.

### Scan Disk

Walks each volume and reports how its space is used: capacity and free space, plus the largest files and the largest directories.
A directory's size is recursive.

```zig
pub const DiskScanOptions = struct {
    roots: []const []const u8 = &.{},
    top: u32 = 100,
    min_size_bytes: u64 = 0,
};

pub fn scanDisk(gpa: Allocator, options: DiskScanOptions) !DiskScan
```

- `roots`: paths to scan; every mounted fixed volume when empty.
- `top`: how many largest files and largest directories to keep per volume.
- `min_size_bytes`: entries below this size are ignored.

`DiskScan` records when the scan started, how long it took, and one `Volume` per root: its path, `capacity_bytes`, `free_bytes`, `largest_files` and `largest_dirs` (each an array of path and size), and `skipped`, the paths that could not be read.
A scan over a live system always meets paths it cannot read, from permissions or locks, so partial completion is the normal outcome and `skipped` says exactly what the scan could not see.

## Suggest

Proposes cleanups, steered by a request describing what the caller wants. Model-backed.
Suggest runs the [scans](#scan) it needs based on the request.
Each suggestion identifies a path, its size, a proposed action (which might be the user uninstalling something in Programs as an example), the rationale, and a risk level.
Suggest never deletes or modifies anything; acting on a suggestion is the caller's decision.

```zig
pub const SuggestOptions = struct {
    request: []const u8,
};

pub fn suggest(gpa: Allocator, options: SuggestOptions) !Suggestions
```

- `request`: what the caller wants suggestions about, like what can safely be removed.

`Suggestions` holds `items`, the list of suggestions, and `message`, the model's closing message.

## Failure

Failures explain what went wrong and name the remedy, so the caller can act without reading documentation.

- A missing prerequisite fails immediately, naming what is absent and how to install it.
- Suggest without the Claude Code CLI or its credentials fails saying exactly what to install or configure, and never falls back to a deterministic answer.
- Scan Disk completes partially by design, recording unreadable paths in `skipped`. Every other capability either completes or fails whole.
