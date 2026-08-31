This is a Smart Tool that must conform to Microsoft's Amplifier Smart Tool Spec.

## Writing Style

- Be concise. The user will not read walls of text.
- When adding to existing documents, add only what's needed.
- Do not restructure or rewrite existing content unless asked.
- Always prefer code blocks and other formatting over tables.
- Match the tone and density of what's already in the file.
- Never write em dashes

## Code, Markdown Files, etc. Are Not Conversation

Every file you write is read later by someone with no memory of this session, and often by a machine. 
Write for that reader, not for me. This applies to all durable output, not just markdown: help text, docstrings, code comments, error messages.

- Never record the state of our work in an artifact. No "Status", "scaffolding", "not implemented yet", "for now", "coming soon", "TODO: remove this later". If a sentence becomes false after the next commit, it does not belong in the file. Tell me in chat instead.
- Never describe the format inside an instance of the format. A manifest does not explain what a manifest is. A test does not explain what testing is.
- When working from a spec, sample, fixture, or reference implementation, copy the structure, never the prose. Their explanatory sentences are written to teach the format to a spec reader. Our users are not that reader.
- Write every artifact as the finished version up to that point, even if it is a scaffold. Incompleteness is tracked in chat and in plan files, never in the artifact itself.

## Instructions

- Never modify this file unless explictly told.
- Never commit or do any other git operations unless explictly told.
- When developing, you must always follow the instructions and patterns described in CONTRIBUTING.md
- When told to look at a GitHub repo or the task requires it, don't do so through web search and web fetch (unless it is a reference). Instead, clone the repo to a temporary directory like in /tmp and then explore it directly.
  - For example if you need to look at the `uv` docs, clone https://github.com/astral-sh/uv into reference/ and then look at its docs/ dir. Things that might be just minor needs, clone them into tmp/.
- If you run into permission issues, STOP and tell the user about the problem. DO NOT create forks or push to other repos that are different from the submodule.
- When you are unusure, prefer to ask me questions.
- For spikes, implementing features, exploring, running/polling for test results, you should use a sub-agent so the main thread does not get polluted with too much context. Be careful about churning for too long however.
- When making PRs, commit messages, or anything that will be public. NEVER mention files, plans, designs, transcripts, that are NOT being made public unless asked.
- Always stay true first and foremost to `docs/00-vision.md`, then the `README.md`/`CONTRIBUTING.md`, then the rest of the docs. 
- When we work on something, and it will impact the docs, at the end propose to make changes to the docs to keep them up to date. Also call out if any contradictions exist.
- Prefer to ask the user more questions to clarify their needs.
- When a question is asked that means answer the question - do not start making changes, refactoring, etc. in the actual project. You *can* take separate spikes, research, etc. But you should answer the question instead of diving into changes!
- When looking for something specific that might take a while, use a sub-agent to find it. Tell the sub-agent return the location (paths) of what is found so it can be referenced easily later.
- For libraries that are new or change frequently, you must refer to their official documentation or source code, using the clones from `reference/` when its a GitHub repo.

## Key Files

@CONTRIBUTING.md
@docs/00-vision.md
@docs/01-library.md

## References

The `reference/` directory should be used for exemplars, references, documentation, or other notes that we want to pull from as we are working on. 
They should all be shallow clones with no history to save space, at the repo's latest stable release tag so the reference matches the version we build against, falling back to the main branch for repos that publish no releases:

```bash
git clone --depth 1 --branch <tag> <url> reference/<name>
```

Documentation that has no repo is fetched instead of cloned, as a snapshot with no pinned version, so re-fetch it when something reads wrong rather than trusting it against a newer release.
Claude Code docs come from `https://code.claude.com/llms.txt`, which indexes every page; any page in it is fetched as markdown by appending `.md` to its URL.

They should also always be gitignored and not impact anything else (like pytest discovery, formatters, etc). 
The repos that we have exemplars are (add to the list as we get more, the one exception to modifying this file):

- https://codeberg.org/ziglang/zig
- https://github.com/microsoft/amplifier-smart-tools
- https://github.com/DavidKoleczek/mybench-smart-tool
- https://github.com/anthropics/claude-agent-sdk-python
- `reference/claude-code-docs/`, fetched from https://code.claude.com/llms.txt
