//! pc_manager: manages and monitors a personal computer. Scans are
//! deterministic, read-only snapshots; suggest is model-backed analysis over
//! them. Nothing here modifies the system.
const std = @import("std");

const config_mod = @import("config.zig");
const manifest_mod = @import("manifest.zig");
const scan_mod = @import("scan.zig");
const suggest_mod = @import("suggest.zig");

pub const Manifest = manifest_mod.Manifest;
pub const Requirement = manifest_mod.Requirement;
pub const LoadManifestError = manifest_mod.LoadManifestError;
pub const loadManifest = manifest_mod.loadManifest;

pub const DiskScanOptions = scan_mod.DiskScanOptions;
pub const DiskScan = scan_mod.DiskScan;
pub const Volume = scan_mod.Volume;
pub const SizedPath = scan_mod.SizedPath;
pub const ScanDiskError = scan_mod.ScanDiskError;
pub const scanDisk = scan_mod.scanDisk;

pub const SuggestOptions = suggest_mod.SuggestOptions;
pub const Suggestions = suggest_mod.Suggestions;
pub const Suggestion = suggest_mod.Suggestion;
pub const Risk = suggest_mod.Risk;
pub const SuggestError = suggest_mod.SuggestError;
pub const suggest = suggest_mod.suggest;

pub const Settings = config_mod.Settings;
pub const default_model = config_mod.default_model;
pub const settingsPath = config_mod.settingsPath;

/// The remedy for a failure from this library, phrased so the caller can act
/// without reading documentation, or null for errors with no standing remedy.
pub fn remedyFor(err: anyerror) ?[]const u8 {
    return switch (err) {
        error.ClaudeCliNotFound => "Install the Claude Code CLI from https://code.claude.com/docs/en/quickstart, then run `claude` once and sign in.",
        error.ClaudeCliNotSignedIn => "Run `claude` and complete /login with your Claude subscription.",
        error.ClaudeCliFailed => "The Claude Code CLI run failed. Check the installation with `claude auth status`, then retry.",
        error.ModelOutputInvalid => "The model returned output that could not be read. Retry the request.",
        error.SettingsInvalid => "The settings file is not valid JSON. Fix or delete it: %APPDATA%\\pc-manager\\settings.json on Windows, ~/.config/pc-manager/settings.json elsewhere.",
        error.RootNotFound => "A scan root does not exist. Check the --root paths.",
        error.RootUnreadable => "A scan root could not be opened. Check the --root paths and their permissions.",
        error.ManifestInvalid => "The packaged SMART_TOOL.md is unreadable; reinstall the tool.",
        error.OutOfMemory => "The system ran out of memory. Retry with fewer roots or a smaller --top.",
        else => null,
    };
}

test {
    _ = config_mod;
    _ = manifest_mod;
    _ = scan_mod;
    _ = suggest_mod;
}
