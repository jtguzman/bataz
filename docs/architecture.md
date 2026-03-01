# System Architecture

> Maintained by Claude. Updated when a new system is introduced or significantly restructured.

## System Map

```
[ Main (Node2D) ]
      │
      ├── wires HUD signals → autoload calls
      ├── wires Board signals → game logic
      └── handles screen flip (180° Tween, 0.4s)

[ GameManager (Autoload) ] ── calls ──► [ TurnManager (Autoload) ]
      │                                        │
  board_state (Dict)                     phase enum
  pawn_count [0,8,8]                     current_player
      │                                        │
  signals: game_started, game_over,      signals: turn_started, phase_changed,
           pawn_removed, pawn_moved              defense_requested, attack_resolved,
                                                 movement_rolled, turn_ended

[ CardSystem (Autoload) ]
  draw_pile, discard_pile
  hand_p1[4], hand_p2[4]
  signals: hand_changed, card_played, card_drawn

[ DiceRoller (static class) ] ◄── called by ── TurnManager

[ Board (Node2D scene) ]
  ◄── signals from GameManager (game_started, pawn_removed, pawn_moved)
  ◄── called by Main (highlight_moves, set_selected, clear_highlights)
  ──► emits board_cell_tapped(Vector2i) → Main

[ HUD (CanvasLayer scene) ]
  ◄── signals from TurnManager, CardSystem, GameManager
  ──► emits card_played_by_ui, discard_pass_requested, defense_chosen,
       movement_done_requested, turn_end_confirmed → Main
```

---

## Systems

### GameManager
- **Type:** Autoload
- **Script:** `res://scripts/game/game_manager.gd`
- **Responsibility:** Board state (Vector2i → team int). Pawn placement, movement, removal. Win condition check. Adjacency queries.
- **Signals emitted:** `game_started`, `game_over(winner)`, `pawn_removed(pos, team)`, `pawn_moved(from, to)`
- **Depends on:** CardSystem (calls `setup()`), TurnManager (calls `start_game()`)

### TurnManager
- **Type:** Autoload
- **Script:** `res://scripts/game/turn_manager.gd`
- **Responsibility:** Phase state machine (PLAY_CARD → RESOLVE_MOVEMENT/ATTACK → RESOLVE_DEFENSE → DRAW → END). Dice rolling. Attack pending state.
- **Phase enum:** `PLAY_CARD, RESOLVE_MOVEMENT, RESOLVE_ATTACK, RESOLVE_DEFENSE, DRAW, END`
- **Signals emitted:** `turn_started(player)`, `phase_changed(phase)`, `turn_ended(player)`, `defense_requested(ap, dp, roll, label)`, `attack_resolved(dp, survives, atk, def)`, `movement_rolled(points)`
- **Depends on:** CardSystem (draw_card, discard_and_refill), DiceRoller
- **Critical:** `on_movement_done()` and `on_defense_resolved()` set phase=END only — Main calls `end_turn()` after flip animation.

### CardSystem
- **Type:** Autoload
- **Script:** `res://scripts/cards/card_system.gd`
- **Responsibility:** 30-card deck (10×MOV/ATK/DEF). Two 4-card hands. Draw/discard/reshuffle logic.
- **Reshuffle rule:** Before ANY draw, if draw pile insufficient → shuffle entire discard into draw pile first.
- **Signals emitted:** `hand_changed(player, hand)`, `card_played(player, type)`, `card_drawn(player, type)`

### DiceRoller
- **Type:** Static class (no autoload)
- **Script:** `res://scripts/global/dice_roller.gd`
- **Responsibility:** `roll(sides) -> int`, `get_die_sides(adjacent_allies) -> int` (0→4, 1→6, 2→8, 3→10, 4→12, 5+→20)

### CardType
- **Type:** Global enum class
- **Script:** `res://scripts/global/card_type.gd`
- **Responsibility:** `enum Type { MOVEMENT, ATTACK, DEFENSE }`

### Main
- **Type:** Node2D (root scene)
- **Script:** `res://scripts/game/main.gd`
- **Responsibility:** Signal routing between HUD and autoloads. Board tap handling (movement + attack FSM). Discard & Pass confirm guard (`_awaiting_discard_confirm`). Screen flip Tween.

### Board
- **Type:** Node2D (scene)
- **Script:** `res://scripts/board/board.gd`
- **Responsibility:** Visual rendering of grid + pawns. Input handling → `board_cell_tapped`. Highlight management.

### HUD
- **Type:** CanvasLayer (scene)
- **Script:** `res://scripts/ui/hud.gd`
- **Responsibility:** Card hand display, button visibility per phase, defense panel, dice display, turn overlay.
