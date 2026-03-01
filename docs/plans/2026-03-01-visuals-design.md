# Dice Overlay + Deck Panel — Design

**Date:** 2026-03-01

## Goal

Add two placeholder visual improvements: a dice roll overlay centered on the board, and a draw/discard pile panel on the left of the board.

## Scope

All changes in `res://scripts/ui/hud.gd`. No changes to `board.gd` or any other file. Both visuals are CanvasLayer nodes created programmatically in `_ready()` per ADR-007.

## 1. Dice Overlay

### Placement
- `PanelContainer`, `position=(496, 240)`, `size=(160, 120)`
- Center of board area in viewport: (576, 300) → offset by half size → (496, 240)
- Not affected by the 180° board flip (CanvasLayer doesn't rotate)

### Structure
```
DiceOverlay (PanelContainer, visible=false)
  └── VBox (VBoxContainer)
       ├── DiceTypeLabel (Label) — e.g. "1d4"  (small)
       └── DiceResultLabel (Label) — e.g. "3"   (font_size=64)
```

### Behavior
- `_show_dice(die_label, result)` sets both labels, shows overlay, hides after 1.5s
- `_show_message(msg)` continues to use the existing `DicePanel` unchanged

## 2. Deck Panel

### Placement
- `PanelContainer`, `position=(0, 48)`, `size=(324, 504)`
- Fills the empty left column between TopBar and BottomBar

### Structure
```
DeckPanel (PanelContainer)
  └── VBox (VBoxContainer, alignment=CENTER)
       ├── DrawLabel   (Label) — "Draw — 18"
       ├── DrawCardRect (ColorRect, 100×140, dark blue #333399) — face-down
       ├── HSeparator
       ├── DiscardLabel (Label) — "Discard — 4"
       └── DiscardCardRect (ColorRect, 100×140) — color by last card type
```

### Card colors
| Last discarded type | Color |
|---------------------|-------|
| MOVEMENT | `Color(0.2, 0.7, 0.2)` — green |
| ATTACK | `Color(0.8, 0.2, 0.2)` — red |
| DEFENSE | `Color(0.2, 0.4, 0.8)` — blue |
| (empty) | `Color(0.3, 0.3, 0.3)` — gray |

### Data source
- `CardSystem.draw_pile.size()` — draw pile count
- `CardSystem.discard_pile.size()` — discard count
- `CardSystem.discard_pile[-1]` — last discarded card type (when non-empty)

### Update triggers
Connect to both `CardSystem.card_played` and `CardSystem.card_drawn` → call `_update_deck_display()`.

## Dependency Note

This feature and the Turn History Panel (plan: `2026-03-01-turn-history-plan.md`) both modify `hud.gd`. They will be implemented together in a single combined rewrite of that script.

## Out of Scope (YAGNI)

- No animation on the dice (rolling effect)
- No card labels on the draw pile (face-down = "?")
- No click interaction on deck/discard
- No font customization beyond font_size override
