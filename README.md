# PC Manager Smart Tool

A Smart Tool for Managing your PC.

## Installation

Install [Zig](https://ziglang.org/download/) 0.16.0 or newer, then build straight from this repository:

```bash
git clone https://github.com/DavidKoleczek/pc-manager-smart-tool.git
cd pc-manager-smart-tool

# Linux
zig build -Doptimize=ReleaseSafe --prefix ~/.local

# Windows (PowerShell)
zig build -Doptimize=ReleaseSafe --prefix "$env:USERPROFILE\.local"
```

This puts `pc-manager` in the `bin` directory under that prefix (`~/.local/bin`, `%USERPROFILE%\.local\bin`); pick any prefix whose `bin` is on your PATH. Verify with:

```bash
pc-manager manifest
```

To upgrade to the latest, pull and build again from the clone:

```bash
git pull
# Run build command for your system
```

## Interface

```bash
# Run every scan kind, or one explicitly; prints indented JSON
pc-manager scan
pc-manager scan disk --top 50

# Get cleanup suggestions
pc-manager suggest --request "what files can safely be removed?"
pc-manager suggest --request "old dev environments"
```

## Configuration

`suggest` is model-backed through the [Claude Code CLI](https://code.claude.com/docs/en/quickstart): install it, run `claude`, and sign in with a Claude subscription.
The model defaults to `claude-sonnet-5` and is changed in the user settings file; see [docs/02-configuration.md](docs/02-configuration.md).
Scans are deterministic and need nothing configured.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for details on how to set up your development environment.
