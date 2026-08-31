# CLI Reference

The CLI is a thin wrapper over the [library](01-library.md). Each command maps to one library capability; this page documents only the command-line surface: flags, defaults, output, and exit behavior.
`-h` prints the terse summary for a person; `--help` prints the complete listing for an agent: every command, its flags and types, what it prints, and which commands are model-backed.

## pc-manager scan

```bash
# Run every scan kind
pc-manager scan

# Run one kind, with its flags
pc-manager scan disk
pc-manager scan disk --root C: --root D: --top 50 --min-size 100MB
```

Prints the scan result as indented JSON on stdout, so the same output reads in a terminal and parses in a pipeline.
Bare `scan` runs every kind and prints one object keyed by kind; `scan <kind>` prints that kind's result alone.

- `--root`: a path to scan, repeatable; every mounted fixed volume when omitted.
- `--top`: largest files and largest directories kept per volume; 100 when omitted.
- `--min-size`: ignore entries below this size, as bytes or a suffixed size like `500MB` or `2GB`; 0 when omitted.

## pc-manager suggest

```bash
# Get cleanup suggestions
pc-manager suggest --request "what files can safely be removed?"

# Narrowed to one directory
pc-manager suggest --request "old dev environments" --root C:\mydir
```

Model-backed; needs the Claude Code CLI and its credentials, see [Configuration](02-configuration.md#model-provider).
Runs the scans it needs on its own, so nothing has to be scanned first.

- `--root`: a path the scans are narrowed to, repeatable; every mounted fixed volume when omitted.
Prints the suggestions as indented JSON on stdout: the items and the model's closing message.

## pc-manager manifest

```bash
# Print the tool's manifest as JSON
pc-manager manifest
```

Prints the [manifest](01-library.md#manifest) on stdout.
Needs no credentials or prerequisites, so it doubles as a smoke test of the installation.

## Exit Codes

```bash
0  # success
1  # the command failed and printed the remedy: a root that does not exist, the Claude Code CLI missing or without credentials, a suggest run that errored
2  # invalid usage: unknown command, scan kind, or flag
```

A failure prints `{"error": {"code", "message", "remedy"}}` as indented JSON on stdout, so the remedy parses in a pipeline the same way results do.
