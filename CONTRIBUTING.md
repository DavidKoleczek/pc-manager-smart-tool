# Contributing to PC Manager Smart Tool

## Development Setup

### Prerequisites

Install:

- [Git](https://git-scm.com/)
- [Zig](https://ziglang.org/download/) 0.16.0 or newer

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

Always use `zig build fmt`, never `zig fmt .`, so formatting only touches the project's own source and not `reference/` or other local directories.
