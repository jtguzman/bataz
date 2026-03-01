# Placement Phase — Design

**Date:** 2026-03-01
**Status:** Approved

## Feature

Before turns begin, each player places their 8 pawns within the first 3 rows of their rank. The enemy player cannot see the opponent's placed pieces during their own placement. Players place one at a time (P1 first, then P2).

## UX Flow

1. App starts → `GameManager.start_placement()` → state `PLACEMENT_P1`
2. Board highlights P1's 3 valid rows (rows 0–2); all other rows are empty
3. P1 taps a valid empty cell → pawn placed (real-time render). Taps occupied own cell → pawn removed
4. HUD shows "Player 1 — Place your pieces (N/8)". "Confirm Placement" button appears when N==8
5. P1 confirms → placement saved → state `PLACEMENT_P2` → board flips 180°
6. P2 sees clean board (rows 5–7 highlighted, P1 zone visually empty)
7. P2 places their 8 pawns the same way and confirms
8. `GameManager.finalize_placement()` merges both placements into `board_state` → `TurnManager.start_game()`
9. Game begins normally

## Architecture — State Machine

New states added to `GameManager.State`:
```
PLACEMENT_P1 → PLACEMENT_P2 → PLAYING → GAME_OVER
```

## Code Changes

### `game_manager.gd`

- Add `PLACEMENT_P1`, `PLACEMENT_P2` to `State` enum
- New vars: `placement_p1: Dictionary`, `placement_p2: Dictionary` (Vector2i → int team)
- `start_placement()` — replaces old `start_game()` fixed-position logic; sets state = PLACEMENT_P1, emits `placement_started(1)`
- `place_pawn(player: int, pos: Vector2i)` — add pawn to player's placement dict
- `remove_pawn_from_placement(player: int, pos: Vector2i)` — remove pawn from placement dict
- `get_placement_zone(player: int) -> Array[Vector2i]` — returns the 24 valid cells (rows 0–2 for P1, rows 5–7 for P2)
- `confirm_placement(player: int)` — if player==1: state→PLACEMENT_P2, emit placement_started(2); if player==2: call finalize_placement()
- `finalize_placement()` — merge placement_p1 + placement_p2 into board_state, call TurnManager.start_game(), state→PLAYING
- New signal: `placement_started(player: int)`

### `board.gd`

- `highlight_placement_zone(cells: Array[Vector2i])` — highlight valid placement cells
- `render_placement(placement_dict: Dictionary, team: int)` — spawn/remove pawn visuals in real time for the active player only (enemy pieces not shown)
- `clear_placement_pawns(team: int)` — remove visual pawns for a team (used between P1 and P2 transitions)
- Reuses existing `_spawn_pawn` internally

### `hud.gd`

- New programmatic `_placement_confirm_btn: Button`
- New programmatic `_placement_label: Label` — shows "Player X — Place your pieces (N/8)"
- `show_placement_ui(player: int)` — shows label + hides all game UI (hand, action buttons)
- `update_placement_count(n: int)` — updates label count and shows/hides confirm button
- `hide_placement_ui()` — hides placement UI when game starts
- New signal: `placement_confirmed(player: int)`

### `main.gd`

- `GameManager.start_game()` call in `_ready()` → replaced with `GameManager.start_placement()`
- Connect `GameManager.placement_started` → `_on_placement_started(player)`
- Connect `hud.placement_confirmed` → `_on_placement_confirmed(player)`
- `_on_board_cell_tapped` — add branches for PLACEMENT_P1 / PLACEMENT_P2:
  - If cell in valid zone and empty → `GameManager.place_pawn`, `board.render_placement`, `hud.update_placement_count`
  - If cell occupied by own pawn → `GameManager.remove_pawn_from_placement`, update visuals
- `_on_placement_started(player)` — show placement UI, highlight zone, if player==2 flip board first
- `_on_placement_confirmed(player)` — call `GameManager.confirm_placement(player)` + if player==1 flip board for P2

### `turn_manager.gd` / `card_system.gd`

No changes.

## Visual Details

- Valid placement rows highlighted (same system as `highlight_moves`)
- Pawns render in real time as placed
- Enemy zone appears empty (no pawns, no highlight) during placement
- Middle rows (3–4) appear as normal empty board
- Board flip between P1→P2 uses the existing 180° tween animation
- "Player X's Turn" overlay does NOT show during placement — replaced by placement label
- No time limit for placement

## Edge Cases

- Tap occupied own cell → removes pawn (count goes back, Confirm disappears if was showing)
- Confirm button visible only when placement_dict.size() == 8 exactly
- After P1 confirms, placement_p1 is frozen (P2 placement is independent)
- Board already has rendered pawns at finalize_placement() time — only state changes, no re-spawn needed
