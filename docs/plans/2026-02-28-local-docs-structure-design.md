# Local Documentation Structure Design
**Date:** 2026-02-28

## Problem
The Godot project lives in the Godot editor and is developed entirely via MCP tools. Between Claude Code sessions, context about what has been built, why decisions were made, and where things live is lost. Repeated `get_scene_tree` calls and re-reasoning about architecture waste time.

## Chosen Approach
Flat `docs/` directory with one markdown file per concern. Claude updates files automatically as part of the development workflow — no manual effort from the user.

## File Structure

```
docs/
├── scenes.md        # Scene registry: paths, root types, scripts, key children
├── architecture.md  # System map: responsibilities, connections, data flow
├── progress.md      # Feature checklist by milestone
├── decisions.md     # ADR-style numbered design decisions
└── plans/           # Timestamped brainstorming & implementation plan outputs
```

## Update Protocol (Claude's responsibility)
- `scenes.md` — updated after every scene creation or structural change
- `architecture.md` — updated when a new system is introduced or significantly changed
- `progress.md` — updated at the end of every session
- `decisions.md` — a new entry appended whenever a non-obvious choice is made
- `plans/` — new file created per planning session, never modified after creation
