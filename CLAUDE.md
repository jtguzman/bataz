# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Bataz** — a 2D turn-based card-driven strategy game built in Godot 4.6.1.
- Viewport: 1152×648, renderer: GL Compatibility (OpenGL)
- Engine version: 4.6.1-stable (official)
- No build step, no test runner, no linter — Godot is the runtime and editor.

The game is in **early development**. No game scenes or scripts exist yet.

### Game Design Summary

Two players on an 8×8 chessboard, each controlling 8 pawns. Objective: eliminate all enemy pawns.

**Deck:** 30 cards shared — 10 Movement, 10 Attack, 10 Defense. Each player holds 4 cards; plays 1 per turn, draws 1 back.

**Movement card:** Roll 1d4 → distribute movement points freely among any pawns. Pawns move like a chess king (1 square any direction, can multi-step with remaining points).

**Attack card:** Pawn must be adjacent to an enemy. Declare attacker + defender before rolling. Die scales with **adjacent friendly pawns**: 0→1d4, 1→1d6, 2→1d8, 3→1d10, 4→1d12, 5+→1d20.

**Defense card:** Reactive response to an attack. Same die scale as attack (based on adjacent allies of the **defender**). Success if defense roll ≥ attack roll — pawn survives. When a Defense card is played, both attacker and defender draw 1 card at end of attacker's turn.

Depleted draw pile → shuffle discard into new draw pile. Last player with pawns wins.

---

## Development Workflow

This project is developed entirely through **Claude Code + Godot MCP Pro**. The Godot editor must be open with the project loaded for MCP tools to work.

### How to develop

1. Open the Godot project at `C:/Users/jtguz/OneDrive/Documentos/GODOT/bataz/`
2. Ensure the MCP plugin is enabled (`Project > Project Settings > Plugins > Godot MCP`)
3. Use MCP tools from Claude Code to create scenes, nodes, and scripts directly in the editor

### Key workflow rules

- **Always call `save_scene` after modifying a scene** via MCP — changes live in memory until saved.
- After creating a new scene, call `open_scene` before adding nodes to it.
- Node paths are relative to the scene root. Use `get_scene_tree` to verify paths before acting on them.
- Use `batch_set_property` when setting multiple properties on the same node — it's a single round-trip.
- `execute_editor_script` runs arbitrary GDScript in the editor context (useful for bulk operations).
- `execute_game_script` runs GDScript inside a running game session.

### Local documentation (read at session start, update at session end)

The `docs/` directory is the persistent knowledge base for this project. **No Godot code lives here** — only architecture docs maintained by Claude.

| File | Read when | Update when |
|---|---|---|
| `docs/scenes.md` | Before querying scene structure | After creating/changing any scene |
| `docs/architecture.md` | Before adding a new system | After introducing or restructuring a system |
| `docs/progress.md` | At session start to orient | At session end to reflect what changed |
| `docs/decisions.md` | Before making a non-obvious choice | After making one |
| `docs/plans/` | When implementing a planned feature | New file per planning session |

---

## MCP Plugin Architecture

The plugin (`res://addons/godot_mcp/`) is a **client-side WebSocket bridge** between Claude Code and the Godot editor. It does not run a server — it *connects to* the Node.js MCP server that Claude Code runs.

### Connection model

`websocket_server.gd` connects to ports **6505–6509** simultaneously (one per active Claude Code session). Each Claude Code instance gets its own port; Godot fans out to all of them. Reconnects every 3 seconds if a port is unavailable. Messages use **JSON-RPC 2.0**.

### Editor-side pipeline

```
MCP Tool call
  → Node.js MCP server (port 6505-6509)
    → WebSocketPeer in Godot editor
      → command_router.gd (dispatches by method name)
        → command class extending base_command.gd
          → EditorPlugin / EditorInterface APIs
```

`command_router.gd` instantiates all command classes at startup and builds a flat `method_name → Callable` dictionary. Each command class implements `get_commands() -> Dictionary`.

### Runtime / play-mode pipeline

When the game is running, three autoloads handle runtime inspection via **temp files** in `user://` (not WebSocket — they're in a separate process):

| Autoload | Temp files | Purpose |
|---|---|---|
| `MCPGameInspector` | `mcp_game_request` / `mcp_game_response` | Scene tree, node properties, frame capture, property monitoring |
| `MCPInputService` | `mcp_input_commands` | Simulated input (keyboard, mouse, actions) |
| `MCPScreenshot` | `mcp_screenshot_request` / `mcp_screenshot.png` | Screenshots during play mode |

The editor-side plugin polls for `mcp_debugger_continue` to auto-press the debugger Continue button if the game gets stuck on a breakpoint.

### Adding new commands (if needed)

1. Create `res://addons/godot_mcp/commands/my_commands.gd` extending `base_command.gd`
2. Implement `get_commands() -> Dictionary` returning `{ "method_name": _handler_func }`
3. Register the class in `command_router.gd`'s `_register_commands()` array

`base_command.gd` provides helpers: `success()`, `error()`, `require_string()`, `optional_string/bool/int()`, `find_node_by_path()`, `get_edited_root()`, `get_undo_redo()`.

---

## Planned Project Structure

As the game is built, follow this directory convention:

```
res://
├── scenes/
│   ├── board/          # Board, cells, visual grid
│   ├── pieces/         # Pawn scene
│   ├── cards/          # Card scene, deck, hand UI
│   ├── ui/             # HUD, turn indicator, dice display
│   └── main.tscn       # Main game scene
├── scripts/
│   ├── game/           # GameManager, TurnManager, RulesEngine
│   ├── board/          # Board logic, cell state
│   ├── cards/          # CardDeck, CardHand, card types
│   └── dice/           # DiceRoller
├── assets/
│   ├── sprites/
│   └── fonts/
└── addons/godot_mcp/   # MCP plugin — do not modify
```

---

## GDScript Conventions

- Use **static typing** everywhere (`var x: int`, `func foo(a: String) -> void`)
- Prefer `@export` for designer-tunable values
- Use signals for decoupled communication between game systems
- Autoloads are appropriate for global managers (GameManager, TurnManager) — register via `Project Settings > Autoload`, not by MCP plugin injection
- Scene composition over inheritance: build complex nodes from smaller scene instances

---

## Desktop & Mobile Compatibility

The game targets **desktop (Windows, Linux, macOS) and mobile (Android, iOS)**. Every UI and interaction decision must work on both.

### Input
- **Never use keyboard-only or mouse-only input.** All actions must be reachable via touch.
- Use `InputEventScreenTouch` and `InputEventScreenDrag` for touch; map equivalent mouse events so desktop works without extra branches.
- Touch targets must be large enough to tap comfortably — minimum ~48×48 dp. Board cells and cards must meet this size at the target resolution.
- Avoid hover states as a primary interaction cue (no hover on mobile).

### Layout & Resolution
- Design for the **1152×648 base resolution** (16:9). Use `stretch_mode = canvas_items` and `stretch_aspect = keep` in project settings so the viewport scales cleanly on all screens.
- Use **anchors and `Control` layout properties** rather than hardcoded pixel positions for all UI nodes. Test portrait orientation on mobile — the board may need to reflow.
- Avoid placing interactive elements in the bottom ~80px or top ~40px (system gesture zones on mobile).

### Rendering
- GL Compatibility renderer is already set — correct for broad mobile GPU support. Do not switch to Forward+ or Mobile renderer.
- Keep draw calls and overdraw low. Prefer `CanvasItem` with simple materials; avoid heavy shaders on cards or the board.

### Export
- Android and iOS export presets must be configured before first build.
- Test on a real device or emulator before considering any feature "done."
