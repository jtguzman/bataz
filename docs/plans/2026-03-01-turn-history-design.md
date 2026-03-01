# Turn History Panel — Design

**Date:** 2026-03-01

## Goal

Add a scrollable turn history sidebar that shows each player's card choice, dice result, and turn outcome for the entire game.

## Layout

- **Panel:** Always visible, right of the board. Position `(828, 48)`, size `(324, 504)`.
- **Placement rationale:** Fills the empty space to the right of the 504×504 board. The HUD is a CanvasLayer so it never rotates with the 180° flip — both players always see the same log.
- **Created programmatically** in `hud.gd _ready()` per ADR-007 (add_node/save_scene has a runtime sync bug).

## Panel Structure

```
HistoryPanel (PanelContainer)
  └── VBox (VBoxContainer, fill both axes)
       ├── Title (Label) — "History", centered
       └── Scroll (ScrollContainer, expand fill)
            └── HistoryList (VBoxContainer) ← entries appended here
```

## Entry Format

Per turn, two nodes are added to HistoryList:
1. `HSeparator`
2. A `Label` with two lines:
   - Line 1: `"P{player} — {CardType}"` e.g. `"P1 — Movement"`
   - Line 2: indented detail depending on card:
     - Movement: `"  Rolled {N} pts"`
     - Attack (from attacker's turn): `"  Atk:{X} Def:{Y} → Hit!"` or `"  Atk:{X} Def:{Y} → Blocked!"`
     - Defense (no separate entry — result captured during attacker's turn via attack_resolved)
     - Discard & Pass: `"  Passed"`

After each append, the ScrollContainer scrolls to the bottom.

## Data Flow

A `_pending_history: Dictionary` in `hud.gd` accumulates data as signals fire:

| Signal | Source | Action |
|--------|--------|--------|
| `card_played(player, type)` | CardSystem | Set player + card type |
| `movement_rolled(points)` | TurnManager | Set detail = "Rolled N pts" |
| `attack_resolved(dp, survives, atk, def)` | TurnManager | Set detail = "Atk:X Def:Y → Hit!/Blocked!" |
| `turn_ended(player)` | TurnManager | Finalize + append entry, clear `_pending_history` |

Discard & Pass: handled inside `_on_discard_pass_btn_pressed()` — sets detail = "Passed" before turn_ended fires.

## Out of Scope (YAGNI)

- No color-coding per player
- No entry count limit
- No export/copy functionality
- No timestamps
