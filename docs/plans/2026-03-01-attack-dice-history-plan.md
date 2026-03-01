# Attack Dice in History — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Show which die the attacker and defender used in the history panel after each attack resolution.

**Architecture:** Extend the `attack_resolved` signal in `TurnManager` with two new parameters (`attack_die_sides`, `defense_die_sides`), then update `hud.gd` and `main.gd` to accept them. History format becomes `1d8=7 vs 1d6=3 → Hit!` with defense, or `1d6=5 → Hit! (undefended)` without.

**Tech Stack:** Godot 4.6.1 GDScript, MCP Pro tools. No test runner — verification via `validate_script` + `play_scene` + `execute_game_script`. Use `create_script` for all full-file rewrites. NEVER use `edit_script`.

---

## Context for implementer

- Git: `git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz`
- `validate_script` warnings for autoloads (TurnManager, CardSystem, GameManager, CardType) = expected false-positives. Only fail on real parse errors.
- `create_script` overwrites the entire file — always read current content first with `read_script`, apply changes, then write the full new content.
- Design doc: `docs/plans/2026-03-01-attack-dice-history-design.md`

---

### Task 1: Update `turn_manager.gd` — extend `attack_resolved` signal

**Files:**
- Modify: `res://scripts/game/turn_manager.gd`

**Step 1: Read current script**

`read_script("res://scripts/game/turn_manager.gd")`

**Step 2: Validate baseline**

`validate_script("res://scripts/game/turn_manager.gd")` — expect valid.

**Step 3: Rewrite with create_script**

Apply two changes:

**A. Update signal declaration** — add two parameters:

```gdscript
signal attack_resolved(defender_pos: Vector2i, pawn_survives: bool, attack_roll: int, defense_roll: int, attack_die_sides: int, defense_die_sides: int)
```

**B. Update `on_defense_resolved`** — hoist `attack_die_sides` and `def_sides` to function scope so they are available for the emit call:

```gdscript
func on_defense_resolved(defender_played_card: bool, defender_adjacent: int) -> void:
	var attack_die_sides: int = pending_attack["die_sides"]
	var attack_roll := DiceRoller.roll(attack_die_sides)
	var defender_pos: Vector2i = pending_attack["defender_pos"]
	var def_roll := 0
	var def_sides := 0
	var pawn_survives := false

	if defender_played_card:
		def_sides = DiceRoller.get_die_sides(defender_adjacent)
		def_roll = DiceRoller.roll(def_sides)
		pawn_survives = def_roll >= attack_roll
		CardSystem.draw_card(current_player)
		var other := 2 if current_player == 1 else 1
		CardSystem.draw_card(other)
	else:
		CardSystem.draw_card(current_player)

	attack_resolved.emit(defender_pos, pawn_survives, attack_roll, def_roll, attack_die_sides, def_sides)
	pending_attack = {}
	phase = Phase.END
	phase_changed.emit(phase)
	# end_turn() is called by Main after flip animation
```

Everything else in the file stays identical.

**Step 4: Validate**

`validate_script("res://scripts/game/turn_manager.gd")` — expect valid.

**Step 5: Commit**

```bash
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz add scripts/game/turn_manager.gd
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz commit -m "feat: add die sides to attack_resolved signal"
```

---

### Task 2: Update `hud.gd` and `main.gd` — new history format + verify

**Files:**
- Modify: `res://scripts/ui/hud.gd`
- Modify: `res://scripts/game/main.gd`

**Step 1: Read current scripts**

`read_script("res://scripts/ui/hud.gd")`
`read_script("res://scripts/game/main.gd")`

**Step 2: Rewrite `hud.gd` with create_script**

Replace `_on_attack_resolved` — add `attack_die_sides: int` and `defense_die_sides: int` parameters and update `_pending_history["detail"]` format:

```gdscript
func _on_attack_resolved(_dp: Vector2i, pawn_survives: bool, attack_roll: int, defense_roll: int, attack_die_sides: int, defense_die_sides: int) -> void:
	var msg := ""
	if defense_roll > 0:
		msg = "ATK %d vs DEF %d - %s" % [attack_roll, defense_roll, "Blocked!" if pawn_survives else "Hit!"]
	else:
		msg = "ATK %d - Hit!" % attack_roll
	dice_label.text = msg
	dice_panel.visible = true
	_dice_panel_gen += 1
	var gen := _dice_panel_gen
	get_tree().create_timer(2.0).timeout.connect(func():
		if _dice_panel_gen == gen:
			dice_panel.visible = false
	)
	if defense_roll > 0:
		var outcome := "Blocked!" if pawn_survives else "Hit!"
		_pending_history["detail"] = "  1d%d=%d vs 1d%d=%d → %s" % [attack_die_sides, attack_roll, defense_die_sides, defense_roll, outcome]
	else:
		_pending_history["detail"] = "  1d%d=%d → Hit! (undefended)" % [attack_die_sides, attack_roll]
```

Everything else in `hud.gd` stays identical.

**Step 3: Validate hud.gd**

`validate_script("res://scripts/ui/hud.gd")` — expect valid.

**Step 4: Rewrite `main.gd` with create_script**

Replace `_on_attack_resolved` — add two ignored parameters to the signature:

```gdscript
func _on_attack_resolved(defender_pos: Vector2i, pawn_survives: bool, _ar: int, _dr: int, _ads: int, _dds: int) -> void:
	if not pawn_survives:
		GameManager.remove_pawn_at(defender_pos)
```

Everything else in `main.gd` stays identical.

**Step 5: Validate main.gd**

`validate_script("res://scripts/game/main.gd")` — expect valid.

**Step 6: Commit**

```bash
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz add scripts/ui/hud.gd scripts/game/main.gd
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz commit -m "feat: show attack and defense dice in history panel"
```

**Step 7: Play scene and verify**

`play_scene("res://scenes/main.tscn")`

`get_output_log` — zero ERROR lines expected.

Run a game script to force an undefended attack and check history format:

```gdscript
# Set up board state with two adjacent pawns (one per team)
GameManager.board_state = {Vector2i(3,3): 1, Vector2i(3,4): 2}
GameManager.pawn_count = [0, 1, 1]
GameManager.state = GameManager.State.PLAYING
CardSystem.setup()
TurnManager.start_game()
# Simulate playing an attack card
TurnManager.on_attack_declared(Vector2i(3,3), Vector2i(3,4), 0)  # 0 adjacent = 1d4
# Simulate no defense
TurnManager.on_defense_resolved(false, 0)
var hud = get_tree().root.get_node("Main/HUD")
_mcp_print("detail: " + hud._pending_history.get("detail", "(empty)"))
```

Expected: `detail: 1d4=N → Hit! (undefended)` where N is 1–4.

`stop_scene()`

**Step 8: Push**

```bash
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz push
```
