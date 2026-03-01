# Attack Die Timing Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Roll the attack die after the defender decides whether to play a Defense card, not before.

**Architecture:** Two files change — `turn_manager.gd` moves the dice roll from `on_attack_declared` to `on_defense_resolved`, and `hud.gd` updates `_on_defense_requested` to show the die size instead of the roll result. The `defense_requested` signal loses its `attack_roll` and `die_label` parameters and gains `attacker_die_sides` instead.

**Tech Stack:** Godot 4.6.1 GDScript, MCP `create_script`.

---

## CRITICAL CONTEXT

- All code lives in the Godot editor (Windows). No local .gd files exist in WSL.
- Use `create_script` for all rewrites. **NEVER use `edit_script`** — it corrupts code silently.
- `validate_script` errors for TurnManager/CardSystem/GameManager/CardType = expected false-positives (autoloads). Only fail on real parse errors.
- Git commands: `git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz`

---

## Task 1: Update turn_manager.gd

**Files:**
- Modify: `res://scripts/game/turn_manager.gd` (full rewrite via `create_script`)

### Step 1: Verify baseline

`validate_script("res://scripts/game/turn_manager.gd")` → expect `valid: true`.

### Step 2: Write new script

Use `create_script` with the complete content below.

```gdscript
# res://scripts/game/turn_manager.gd
extends Node

signal turn_started(player: int)
signal phase_changed(phase: Phase)
signal turn_ended(player: int)
signal defense_requested(attacker_pos: Vector2i, defender_pos: Vector2i, attacker_die_sides: int)
signal attack_resolved(defender_pos: Vector2i, pawn_survives: bool, attack_roll: int, defense_roll: int)
signal movement_rolled(points: int)

enum Phase {
	PLAY_CARD,
	RESOLVE_MOVEMENT,
	RESOLVE_ATTACK,
	RESOLVE_DEFENSE,
	DRAW,
	END
}

var current_player: int = 1
var phase: Phase = Phase.PLAY_CARD
var movement_points: int = 0
var pending_attack: Dictionary = {}

func start_game() -> void:
	current_player = 1
	_begin_turn()

func _begin_turn() -> void:
	phase = Phase.PLAY_CARD
	turn_started.emit(current_player)
	phase_changed.emit(phase)

func on_card_played(type: CardType.Type) -> void:
	match type:
		CardType.Type.MOVEMENT:
			var roll := DiceRoller.roll(4)
			movement_points = roll
			movement_rolled.emit(roll)
			phase = Phase.RESOLVE_MOVEMENT
			phase_changed.emit(phase)
		CardType.Type.ATTACK:
			phase = Phase.RESOLVE_ATTACK
			phase_changed.emit(phase)
		CardType.Type.DEFENSE:
			push_warning("[TurnManager] Defense card cannot be played proactively")

func on_movement_done() -> void:
	movement_points = 0
	CardSystem.draw_card(current_player)
	phase = Phase.END
	phase_changed.emit(phase)
	# end_turn() is called by Main after flip animation

func on_attack_declared(attacker_pos: Vector2i, defender_pos: Vector2i, attacker_adjacent: int) -> void:
	var die_sides := DiceRoller.get_die_sides(attacker_adjacent)
	pending_attack = {
		"attacker_pos": attacker_pos,
		"defender_pos": defender_pos,
		"die_sides": die_sides,
	}
	phase = Phase.RESOLVE_DEFENSE
	phase_changed.emit(phase)
	defense_requested.emit(attacker_pos, defender_pos, die_sides)

func on_defense_resolved(defender_played_card: bool, defender_adjacent: int) -> void:
	var attack_roll := DiceRoller.roll(pending_attack["die_sides"])
	var defender_pos: Vector2i = pending_attack["defender_pos"]
	var def_roll := 0
	var pawn_survives := false

	if defender_played_card:
		var def_sides := DiceRoller.get_die_sides(defender_adjacent)
		def_roll = DiceRoller.roll(def_sides)
		pawn_survives = def_roll >= attack_roll
		CardSystem.draw_card(current_player)
		var other := 2 if current_player == 1 else 1
		CardSystem.draw_card(other)
	else:
		CardSystem.draw_card(current_player)

	attack_resolved.emit(defender_pos, pawn_survives, attack_roll, def_roll)
	pending_attack = {}
	phase = Phase.END
	phase_changed.emit(phase)
	# end_turn() is called by Main after flip animation

func on_discard_and_pass() -> void:
	CardSystem.discard_and_refill(current_player)
	phase = Phase.END
	phase_changed.emit(phase)
	# end_turn() is called by Main after user confirms preview

func end_turn() -> void:
	turn_ended.emit(current_player)
	current_player = 2 if current_player == 1 else 1
	_begin_turn()
```

### Step 3: Validate

`validate_script("res://scripts/game/turn_manager.gd")` → expect `valid: true`. Ignore autoload warnings.

### Step 4: Commit

```bash
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz add scripts/game/turn_manager.gd
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz commit -m "fix: roll attack die after defense decision, not before"
```

---

## Task 2: Update hud.gd

**Files:**
- Modify: `res://scripts/ui/hud.gd` (full rewrite via `create_script`)

### Step 1: Read current script

`read_script("res://scripts/ui/hud.gd")` to get the exact current content. The only function that changes is `_on_defense_requested`.

### Step 2: Write new script

Rewrite `res://scripts/ui/hud.gd` via `create_script`. The only change from the current file is `_on_defense_requested`:

**Old:**
```gdscript
func _on_defense_requested(_ap: Vector2i, _dp: Vector2i, attack_roll: int, die_label: String) -> void:
	_show_dice(die_label, attack_roll)
	var defender := 2 if current_player == 1 else 1
	var hand := CardSystem.get_hand(defender)
	defense_title.text = "Player %d - Defend? (ATK=%d)" % [defender, attack_roll]
```

**New:**
```gdscript
func _on_defense_requested(_ap: Vector2i, _dp: Vector2i, die_sides: int) -> void:
	var defender := 2 if current_player == 1 else 1
	var hand := CardSystem.get_hand(defender)
	defense_title.text = "Player %d - Defend? (Attack: 1d%d)" % [defender, die_sides]
```

Everything else in the file is identical. Do NOT change any other function.

### Step 3: Validate

`validate_script("res://scripts/ui/hud.gd")` → expect `valid: true`. Ignore autoload warnings.

### Step 4: Commit

```bash
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz add scripts/ui/hud.gd
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz commit -m "fix: update defense panel to show die size instead of attack roll"
```

---

## Task 3: Visual verification

### Step 1: Run game

`play_scene("res://scenes/main.tscn")`

### Step 2: Check output log

`get_output_log` — confirm no errors. Specifically check there are no signal connection errors related to `defense_requested`.

### Step 3: Stop game

`stop_scene()`

### Step 4: Push

```bash
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz push
```
