# Contributing to PC Manager Smart Tool

## Development Setup

### Prerequisites

Install:

- [Git](https://git-scm.com/)
- [Zig](https://ziglang.org/download/) 0.16.0 or newer
- [Claude Code CLI](https://code.claude.com/docs/en/quickstart) signed in with a Claude subscription, for the model-backed `suggest`; the deterministic paths need only Zig. Model selection and billing behavior are in [docs/02-configuration.md](docs/02-configuration.md).

## Development Commands

```bash
# build the executable into zig-out/
zig build      
# build and run the CLI
zig build run    
# run all tests, including the formatting check
zig build test
# format the source in place
zig build fmt
```
