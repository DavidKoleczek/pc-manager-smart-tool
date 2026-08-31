# Configuration

Defines the inputs that apply across capabilities: user settings and the model provider.

## User Settings

Machine-local, stored in the platform's per-user config directory and never part of any repository:
`%APPDATA%\pc-manager\settings.json` on Windows, `$XDG_CONFIG_HOME/pc-manager/settings.json` (default `~/.config/pc-manager/settings.json`) elsewhere.
A missing file or field means the default applies; a file that exists but does not parse is an error.

```json
{
  "model": "claude-sonnet-5"
}
```

- `model`: the model [Suggest](01-library.md#suggest) runs on, passed to the Claude Code CLI as its `--model` value, so an alias like `sonnet` or a full id like `claude-sonnet-5` both work. Defaults to `claude-sonnet-5`.

## Model Provider

The intelligent capabilities shell out to the [Claude Code CLI](https://code.claude.com/docs/en/cli-reference): install it, run `claude`, and sign in with a Claude subscription.
Invocations always bill that subscription: `ANTHROPIC_API_KEY` and `ANTHROPIC_AUTH_TOKEN` are removed from the CLI's environment, so a key in the environment never silently switches billing to the metered API.
Each invocation is a single self-contained model call with no tools, no MCP servers, no settings from `~/.claude`, and no session left behind.
Deterministic capabilities run with none of this configured.
