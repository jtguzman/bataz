# Attack Dice in History — Design

**Date:** 2026-03-01
**Status:** Approved

## Feature

Show which die the attacker and defender used in the history panel after each attack resolution.

## UX

History entry for an attack with defense:
```
P1 -- Attack
  1d8=7 vs 1d6=3 → Hit!
  1d8=7 vs 1d6=5 → Blocked!
```

History entry for an undefended attack:
```
P1 -- Attack
  1d6=5 → Hit! (undefended)
```

## Code Changes

### `turn_manager.gd`

- Extend `attack_resolved` signal with two new parameters:
  ```gdscript
  signal attack_resolved(
      defender_pos: Vector2i,
      pawn_survives: bool,
      attack_roll: int,
      defense_roll: int,
      attack_die_sides: int,
      defense_die_sides: int
  )
  ```
- In `on_defense_resolved`, pass `pending_attack["die_sides"]` as `attack_die_sides` and `def_sides` (0 if no defense card played) as `defense_die_sides` to the `attack_resolved.emit()` call.

### `hud.gd`

- Update `_on_attack_resolved` signature to accept `attack_die_sides: int` and `defense_die_sides: int`.
- Rebuild `_pending_history["detail"]` using the new format:
  - With defense: `"  1d%d=%d vs 1d%d=%d → %s"` where the last token is `Hit!` or `Blocked!`
  - Without defense: `"  1d%d=%d → Hit! (undefended)"`

### `main.gd`

- Update `_on_attack_resolved` signature to accept `_attack_die_sides: int` and `_defense_die_sides: int` (ignored — main.gd only uses `defender_pos` and `pawn_survives`).

## What Does NOT Change

- The `dice_panel` overlay (shows `ATK N vs DEF M - Hit!` as before)
- Movement history (`Rolled N pts`)
- All other signals and systems
