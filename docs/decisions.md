# Design Decisions

> Maintained by Claude. A new entry is appended whenever a non-obvious architectural or design choice is made.
> Format: ADR (Architecture Decision Record).

---

## ADR-001 — Renderer: GL Compatibility

**Date:** 2026-02-28
**Context:** Godot 4 offers three renderers: Forward+, Mobile, and GL Compatibility.
**Decision:** Use GL Compatibility.
**Rationale:** The game targets both desktop and mobile (Android/iOS). GL Compatibility has the broadest GPU support across low-end Android devices and all iOS devices. The game is 2D with no complex lighting needs, so the reduced feature set is not a constraint.
**Consequences:** No global illumination, no compute shaders, no advanced post-processing. Acceptable for a 2D board game.

---

## ADR-002 — Viewport: 1152×648 with canvas_items stretch

**Date:** 2026-02-28
**Context:** The game must run on desktop monitors and mobile screens in varying aspect ratios.
**Decision:** Base viewport 1152×648 (16:9), stretch mode `canvas_items`, stretch aspect `keep`.
**Rationale:** 1152×648 is a clean 16:9 resolution that scales well up (1080p, 1440p) and down (mobile). `canvas_items` stretch re-renders at native resolution rather than blurring a fixed framebuffer. `keep` preserves aspect ratio with letterboxing/pillarboxing on non-16:9 screens.
**Consequences:** UI must use anchors — no hardcoded pixel positions. Portrait mobile layouts may need additional handling.

---

## ADR-003 — Development workflow: MCP-only, no local Godot code

**Date:** 2026-02-28
**Context:** The project is developed by Claude Code via Godot MCP Pro. The local WSL workspace and the Godot project (Windows) are separate locations.
**Decision:** All Godot scenes, scripts, and resources are created exclusively via MCP tools. The local workspace (`/home/jtguzman/workspace/godot/bataz/`) contains only documentation — no `.gd`, `.tscn`, or `.tres` files.
**Rationale:** Keeping code in the Godot editor (via MCP) ensures the editor's filesystem, undo history, and scene serialization stay consistent. Mixing direct file writes with editor-managed files causes desync.
**Consequences:** Claude must always use `save_scene` after edits. The local docs must be kept accurate because they are the only persistent cross-session context outside of Godot itself.

---

## ADR-004 — Instantiated card scenes: avoid typed Button variable

**Date:** 2026-02-28
**Context:** `card.tscn` root is a Button with `card_ui.gd` attached. When instantiated and assigned to a `var card: Button` typed variable, calling `card.setup()` fails at runtime with "Nonexistent function 'setup' in base 'Button'" — GDScript resolves methods against the declared type, not the actual runtime type.
**Decision:** Always instantiate card scenes into an untyped variable: `var card = _card_scene.instantiate()`.
**Rationale:** Duck typing allows GDScript to resolve `setup()` and `card_selected` against the actual runtime object (which has `card_ui.gd` attached).
**Consequences:** No type safety on instantiated cards. Alternative would be to add `class_name CardUi` to `card_ui.gd` and type as `CardUi`, but untyped is simpler for this use case.

---

## ADR-005 — Discard & Pass confirm guard in Main

**Date:** 2026-02-28
**Context:** `TurnManager.on_discard_and_pass()` sets `phase = END` synchronously, which triggers `_on_phase_changed(END)` in Main and would immediately start the screen flip. But the player must first see their new hand and confirm before the flip.
**Decision:** Main holds a `_awaiting_discard_confirm: bool` flag. `_on_discard_pass_requested()` sets the flag true before calling `on_discard_and_pass()`. `_on_phase_changed(END)` skips the flip if the flag is set. `_on_turn_end_confirmed()` clears the flag and calls `_do_flip_then_next_turn()`.
**Rationale:** Avoids restructuring TurnManager's synchronous signal flow. Keeps the guard logic entirely in Main where it belongs.
**Consequences:** Main must always clear `_awaiting_discard_confirm` in `_on_turn_end_confirmed()`. If a future code path reaches END without going through confirm, the flag must be explicitly cleared.

---

## ADR-006 — Main scene rotation pivot: (576, 300)

**Date:** 2026-02-28
**Context:** The 180° screen flip rotates `Main` (Node2D). With `Main.position = (0, 0)`, rotation pivots around the top-left corner of the viewport, sending all children to negative coordinates (off screen).
**Decision:** Set `Main.position = (576, 300)` (center of the 504×504 board area) and `Board.position = (-252, -252)`.
**Rationale:** The board's center is at viewport `(576, 300)` — horizontally centered and vertically centered between the 48px top bar and 96px bottom bar. Placing Main's origin at this point means rotation always keeps the board within the viewport. The HUD (CanvasLayer) is unaffected by Main's transform.
**Consequences:** Board local position is `(-252, -252)` instead of `(324, 48)`. Any future children of Main that need viewport-space positioning must account for the `(576, 300)` offset.

---

## ADR-007 — PlayCardBtn created programmatically, not via scene editor

**Date:** 2026-03-01
**Context:** `add_node` + `save_scene` via MCP successfully writes the node to the .tscn file (verified with `get_scene_file_content`), but the node is silently absent at runtime — `$BottomBar/PlayCardBtn` returns null. This is a known MCP runtime sync issue where the editor's in-memory scene state does not fully propagate to the running game after a `save_scene`.
**Decision:** `PlayCardBtn` is created programmatically in `hud.gd`'s `_ready()` using `Button.new()` and added to `$BottomBar` with `add_child()`.
**Rationale:** Programmatic creation is immune to scene file caching issues. The node is guaranteed to exist when `_ready()` runs and all downstream references are valid.
**Consequences:** `PlayCardBtn` is not visible in the editor scene tree. Any future nodes that suffer the same sync issue should be created programmatically instead.
