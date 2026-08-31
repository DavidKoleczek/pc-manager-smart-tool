# Vision

PC Manager is a [Smart Tool](https://github.com/microsoft/amplifier-smart-tools) that manages and monitors your personal computer.
Eventually it will contain all sorts of smart functionality to manage and monitor your PC.
To start, it only focuses on managing the space on your system.

## Goals

- Scan: fast, deterministic, read-only snapshots of the system, starting with disk space (the largest files and directories on each volume). New areas of the system become new scan kinds.
- Suggest: model-backed analysis over scan data that proposes what could be cleaned up.
- Scans and suggestions never modify the system. Anything that makes changes happens only with the user's permission.
- Written in Zig for performance. It should be portable across Windows and Linux.

## Non-Goals

- A full system utility suite: antivirus, driver updates, OS tweaking.
- Cleaning anything up without a person deciding.
- NOTE: Ideas that might be goals, but we are not targeting yet are in [ROADMAP.md](ROADMAP.md)

## Principles

- The library is the tool. The CLI and any other surface are thin wrappers over it.
- The intelligence is implemented by shelling out to Claude Code. However, it should be architected and structured such that it is easy to swap in something else.
- Deterministic paths run with no model provider configured.
