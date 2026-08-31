---
smart_tool_format: 1
name: pc-manager
version: 0.1.0
description: >
  Manages and monitors a personal computer, starting with disk space: deterministic,
  read-only scans of what fills each volume, and model-backed suggestions for what
  could be cleaned up. Use when a machine is running out of space and you want to
  know why, or want a reasoned list of cleanups to act on yourself.
use_cases:
  - Find out what is taking the space on each volume
  - Get cleanup suggestions with a rationale and risk level for each
  - Feed a machine-readable disk snapshot into scripts or agents
platforms:
  - windows
  - linux
requires:
  - name: claude-code
    purpose: >
      Powers suggest, signed in with a Claude subscription. Without it, only the
      deterministic scans run.
    optional: true
    install: https://code.claude.com/docs/en/quickstart
---

# PC Manager

Scans a computer for how its disk space is used and suggests what could be cleaned up.
Scans and suggestions never modify the system; acting on a suggestion is always your decision.

## When to reach for it

- A volume is filling up and you want to see the largest files and directories behind it
- You want cleanup candidates weighed for you, each with a rationale and a risk level
- A script or agent needs a machine-readable snapshot of disk usage

Not for cleaning anything itself: it proposes, you dispose.

## Straight and smart paths

`scan` and `manifest` are deterministic and run with nothing configured.
`suggest` is model-backed through the Claude Code CLI and needs it installed and signed in.

## Worked invocations

```bash
# what is on every fixed volume
pc-manager scan

# the 50 largest files and directories under one root
pc-manager scan disk --root C:\ --top 50

# ignore anything under 100MB
pc-manager scan disk --min-size 100MB

# cleanup proposals for a specific concern
pc-manager suggest --request "old dev environments I no longer use"

# the manifest, doubling as an install smoke test
pc-manager manifest
```

## Sharp edges

- A scan over a live system always meets paths it cannot read; they are listed in `skipped` rather than failing the scan.
- Directory sizes are recursive, so a parent and its child both appearing in `largest_dirs` is expected.
- `suggest` sends scan data to the model provider; run `scan` alone if that must stay local.

The docs directory of the repository covers the library, configuration, and CLI in full.
