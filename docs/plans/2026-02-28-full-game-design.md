# Bataz — Full Game Design
**Date:** 2026-02-28
**Status:** Approved

---

## Visual Style
- Simple shapes + theme colors. No external art assets.
- Board light cells: `#F0D9B5`, dark cells: `#B58863`
- Player 1 pawns: `#4A90D9` (blue), Player 2 pawns: `#E05252` (red)
- Pawns: filled circles drawn via `draw_circle()` in `_draw()`
- Selected pawn: white ring overlay
- Cards: color-coded panels — Movement = green, Attack = red, Defense = blue

---

## Multiplayer
Local hotseat with 180° screen flip between turns. After each turn, `Main` node rotates 180° via a ~0.4s Tween. The HUD `CanvasLayer` does not rotate — its anchor points swap so the active player's hand is always at the bottom. A brief "Player X's turn" overlay appears during the flip.

---

## Scene Structure

```
res://scenes/
├── main.tscn               # Node2D — root, composes board + HUD
├── board/
│   ├── board.tscn          # Node2D — generates 64 cells, holds PawnLayer
│   └── cell.tscn           # Node2D — ColorRect bg + highlight overlay
├── pieces/
│   └── pawn.tscn           # Node2D — draw_circle + selection ring
├── cards/
│   └── card.tscn           # Control — card Button (type label + color bg)
└── ui/
    └── hud.tscn            # CanvasLayer — hand strip, turn bar, dice display, action panel
```

Board cells are generated procedurally in `board._ready()`. Pawns are spawned by `GameManager` at game start and parented to `PawnLayer` inside the board.

**Board sizing:** `CELL_SIZE = 72px` → board = `576×576px`, centered in `1152×648` viewport.

---

## Autoloads

### GameManager (`scripts/game/game_manager.gd`)
- State machine: `SETUP → PLAYING → GAME_OVER`
- Owns: `pawns_p1: Array[Pawn]`, `pawns_p2: Array[Pawn]`
- Spawns pawns at game start (P1 rows 0–1, P2 rows 6–7)
- Calls win check after every pawn removal
- Signals: `game_started`, `game_over(winner: int)`, `pawn_removed(pawn)`

### TurnManager (`scripts/game/turn_manager.gd`)
- Owns: `current_player: int` (1 or 2), `phase: Phase`
- Phase enum: `PLAY_CARD, RESOLVE, DRAW, END`
- Drives screen flip at END phase
- Signals: `turn_started(player)`, `phase_changed(phase)`, `turn_ended(player)`

### CardSystem (`scripts/cards/card_system.gd`)
- Owns: `draw_pile: Array[CardType]`, `discard_pile: Array[CardType]`
- Owns: `hand_p1: Array[CardType]`, `hand_p2: Array[CardType]` (always 4 cards)
- **Reshuffle rule:** before ANY draw, if draw pile has insufficient cards, shuffle entire discard pile into draw pile first
- Signals: `card_played(player, type)`, `card_drawn(player, type)`, `hand_changed(player, hand)`

### Supporting (not autoloads)
- `DiceRoller` — static class, `roll(sides: int) -> int` using `randi_range(1, sides)`
- `CardType` — global enum `{MOVEMENT, ATTACK, DEFENSE}`

---

## Turn Flow

```
turn_started(player)
    │
    ▼
[PLAY_CARD]
    ├─ Player plays a card → phase = RESOLVE
    └─ Player taps "Discard & Pass"
           → all 4 cards → discard pile
           → draw 4 new cards (reshuffle if needed)
           → player SEES new hand (read-only, cannot play)
           → player confirms → phase = END (skip RESOLVE and DRAW)

[RESOLVE]
    ├─ MOVEMENT
    │   → roll 1d4 → N movement points
    │   → player taps pawn → valid destinations highlight
    │   → player taps destination → pawn moves, N--
    │   → repeat until N=0 or player taps "Done"
    │
    ├─ ATTACK
    │   → player taps attacking pawn → valid enemy targets highlight
    │   → player taps target enemy
    │   → count attacker's adjacent allies → roll attack die
    │   → show result in HUD
    │   → defending player sees their hand (both hands visible)
    │   → defender: play DEFENSE card OR tap "Pass"
    │       DEFENSE played:
    │           → count defender's adjacent allies → roll defense die
    │           → defense ≥ attack → pawn survives
    │           → attack > defense → pawn removed
    │       Pass:
    │           → pawn removed automatically
    │
    └─ DEFENSE (cannot be played proactively — only reactive during ATTACK)

[DRAW]
    → attacker always draws 1 (reshuffle if needed)
    → defender draws 1 ONLY IF they played a Defense card (reshuffle if needed)

[END]
    → GameManager checks win condition
    → if winner → show game_over screen
    → if no winner → screen flip 180° (~0.4s Tween)
    → turn_started(other_player)
```

---

## Board & Movement Detail

- `board.cell_state: Dictionary` maps `Vector2i → Pawn` (null = empty)
- Valid move targets: 8 neighbors, in-bounds, not occupied by own team
- Pawns can move through empty cells only (no jumping)
- Movement points can be split freely across any pawns

## Combat Adjacency → Die Mapping

```gdscript
func get_die_sides(adjacent_allies: int) -> int:
    match adjacent_allies:
        0: return 4
        1: return 6
        2: return 8
        3: return 10
        4: return 12
        _: return 20  # 5+
```

Adjacency = 8-directional neighbors of the relevant pawn that contain a pawn of the same team.

---

## HUD Layout (landscape 1152×648)

```
┌─────────────────────────────────────────────────────────┐
│  [P2 face-down cards strip]    Turn: Player 1      [P2] │  ← 48px top bar
├─────────────────────────────────────────────────────────┤
│                                                          │
│                    BOARD  576×576                        │
│         [Dice result panel — center, slides up]          │
│                                                          │
├─────────────────────────────────────────────────────────┤
│ [P1] ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐  [Done/Pass] │  ← 96px bottom bar
│      │ MOV  │ │ ATK  │ │ DEF  │ │ MOV  │              │
│      └──────┘ └──────┘ └──────┘ └──────┘              │
└─────────────────────────────────────────────────────────┘
```

- Cards: min `100×80px` touch targets
- Inactive player's cards: face-down grey panels, not tappable
- During ATTACK resolution: both hands visible; attacker's hand greyed, defender's Defense cards highlighted
- Dice display: center panel, slides up, shows `"1d6 → 4"`, fades after 1.5s
- Action panel: contextual — "Done" during movement, "Defend"/"Pass" during combat, "End Turn" after Discard & Pass preview

---

## Deck Rules
- 30 cards total: 10 Movement, 10 Attack, 10 Defense
- Shuffled at game start
- Each player draws 4 at game start (8 cards dealt before play)
- Reshuffle: triggered BEFORE any draw when draw pile is insufficient — entire discard pile shuffled into draw pile
- Discard & Pass: discard all 4, draw 4 fresh, see new hand (read-only), confirm → turn ends
