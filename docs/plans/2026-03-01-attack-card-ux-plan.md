# Attack Card UX — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Tapping an Attack card then tapping your own pawn confirms the card and selects the attacker in one step; Cancel is available until the enemy pawn is tapped and returns the card to the hand.

**Architecture:** `hud.gd` adds two new signals (`attack_card_pending`, `attack_card_cancelled`) and a new `_cancel_attack_btn` button. `main.gd` owns the attacker-selection state (`_pending_attack_card_index`, `_pending_attacker_pos`) and a new `_handle_attack_card_tap` handler that plays the card + declares the attack only when the enemy is tapped. The `phase_changed` signal automatically cleans up the pending state when phases transition.

**Tech Stack:** Godot 4.6.1 GDScript, MCP Pro tools. No test runner — verification via `validate_script` + `play_scene` + `execute_game_script`. Use `create_script` for all full-file rewrites. NEVER use `edit_script`.

---

## Context for implementer

- Git: `git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz`
- `validate_script` warnings for autoloads (TurnManager, CardSystem, GameManager, CardType) = expected false-positives. Only fail on real parse errors.
- `create_script` overwrites the entire file — always `read_script` first, apply changes, then write full content.
- Design doc: `docs/plans/2026-03-01-attack-card-ux-design.md`
- Movement cards are NOT affected — "Play Card" button still appears for them.

---

### Task 1: Update `hud.gd` — new signals, cancel attack button, attack card tap behavior

**Files:**
- Modify: `res://scripts/ui/hud.gd`

**Step 1: Read current script**

`read_script("res://scripts/ui/hud.gd")`

**Step 2: Validate baseline**

`validate_script("res://scripts/ui/hud.gd")` — expect valid.

**Step 3: Rewrite with create_script**

Apply ALL of the following changes in one full rewrite:

**A. Add two new signals** (after the existing signal declarations):
```gdscript
signal attack_card_pending(player: int, card_index: int)
signal attack_card_cancelled
```

**B. Add `_cancel_attack_btn` var** (after `_cancel_discard_btn` declaration):
```gdscript
var _cancel_attack_btn: Button
```

**C. In `_ready()`, after the `_cancel_discard_btn` block**, add:
```gdscript
	_cancel_attack_btn = Button.new()
	_cancel_attack_btn.text = "Cancel"
	_cancel_attack_btn.custom_minimum_size = Vector2(80, 60)
	_cancel_attack_btn.visible = false
	$BottomBar.add_child(_cancel_attack_btn)
```

**D. In `_ready()`, add connection** (after `_cancel_discard_btn.pressed.connect(...)`):
```gdscript
	_cancel_attack_btn.pressed.connect(_on_cancel_attack_btn_pressed)
```

**E. Update `_set_all_action_buttons_hidden()`** — add `_cancel_attack_btn.visible = false`:
```gdscript
func _set_all_action_buttons_hidden() -> void:
	done_btn.visible = false
	discard_pass_btn.visible = false
	confirm_btn.visible = false
	play_card_btn.visible = false
	_cancel_discard_btn.visible = false
	_cancel_attack_btn.visible = false
	_placement_label.visible = false
	_placement_confirm_btn.visible = false
	_pending_card_index = -1
	_discard_mode = false
	_selected_discard.clear()
```

**F. Replace `_on_hand_card_tapped(idx)`** — split Attack cards from others:
```gdscript
func _on_hand_card_tapped(idx: int) -> void:
	if _discard_mode:
		if idx in _selected_discard:
			_selected_discard.erase(idx)
		else:
			_selected_discard.append(idx)
		_update_discard_selection_display()
		return
	if TurnManager.phase != TurnManager.Phase.PLAY_CARD:
		return
	var hand := CardSystem.get_hand(TurnManager.current_player)
	var card_type: int = hand[idx]
	if card_type == CardType.Type.DEFENSE:
		_show_message("Defense cards are reactive only")
		return
	if card_type == CardType.Type.ATTACK and not _has_valid_attacker():
		_show_message("No pawns adjacent to enemies")
		return
	_pending_card_index = idx
	_update_hand_selection()
	if card_type == CardType.Type.ATTACK:
		_cancel_attack_btn.visible = true
		attack_card_pending.emit(TurnManager.current_player, idx)
	else:
		play_card_btn.visible = true
```

**G. Add `_on_cancel_attack_btn_pressed()`** (new function, place near other cancel handlers):
```gdscript
func _on_cancel_attack_btn_pressed() -> void:
	_cancel_attack_btn.visible = false
	_pending_card_index = -1
	_update_hand_selection()
	attack_card_cancelled.emit()
```

**Step 4: Validate**

`validate_script("res://scripts/ui/hud.gd")` — expect valid.

**Step 5: Commit**

```bash
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz add scripts/ui/hud.gd
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz commit -m "feat: add attack_card_pending/cancelled signals and cancel attack button to HUD"
```

---

### Task 2: Update `main.gd` — pending attack state, tap handler, execute attack

**Files:**
- Modify: `res://scripts/game/main.gd`

**Step 1: Read current script**

`read_script("res://scripts/game/main.gd")`

**Step 2: Validate baseline**

`validate_script("res://scripts/game/main.gd")` — expect valid.

**Step 3: Rewrite with create_script**

Apply ALL of the following changes in one full rewrite:

**A. Add two new vars** (after `_attack_selected` and `_is_transitioning`):
```gdscript
var _pending_attack_card_index: int = -1
var _pending_attacker_pos: Vector2i = Vector2i(-1, -1)
```

**B. In `_ready()`, add two new connections** (after `hud.placement_confirmed.connect(...)`):
```gdscript
	hud.attack_card_pending.connect(_on_attack_card_pending)
	hud.attack_card_cancelled.connect(_on_attack_card_cancelled)
```

**C. Add `_on_attack_card_pending` and `_on_attack_card_cancelled`** (in the placement phase section or nearby):
```gdscript
func _on_attack_card_pending(_player: int, card_index: int) -> void:
	_pending_attack_card_index = card_index
	_pending_attacker_pos = Vector2i(-1, -1)
	board.clear_highlights()

func _on_attack_card_cancelled() -> void:
	_pending_attack_card_index = -1
	_pending_attacker_pos = Vector2i(-1, -1)
	board.clear_highlights()
```

**D. Update `_on_phase_changed`** — reset pending attack state on any phase transition:
```gdscript
func _on_phase_changed(phase: TurnManager.Phase) -> void:
	board.clear_highlights()
	_move_selected = Vector2i(-1, -1)
	_attack_selected = Vector2i(-1, -1)
	_pending_attack_card_index = -1
	_pending_attacker_pos = Vector2i(-1, -1)
	if phase == TurnManager.Phase.END:
		if GameManager.state != GameManager.State.GAME_OVER:
			_do_flip_then_next_turn()
```

**E. Update `_on_board_cell_tapped`** — add PLAY_CARD branch under PLAYING:
```gdscript
func _on_board_cell_tapped(cell: Vector2i) -> void:
	match GameManager.state:
		GameManager.State.PLACEMENT_P1:
			_handle_placement_tap(cell, 1)
		GameManager.State.PLACEMENT_P2:
			_handle_placement_tap(cell, 2)
		GameManager.State.PLAYING:
			match TurnManager.phase:
				TurnManager.Phase.PLAY_CARD:
					if _pending_attack_card_index >= 0:
						_handle_attack_card_tap(cell)
				TurnManager.Phase.RESOLVE_MOVEMENT:
					_handle_movement_tap(cell)
				TurnManager.Phase.RESOLVE_ATTACK:
					_handle_attack_tap(cell)
```

**F. Add `_handle_attack_card_tap` and `_execute_pending_attack`** (new functions, place after `_handle_placement_tap`):
```gdscript
func _handle_attack_card_tap(cell: Vector2i) -> void:
	var team := TurnManager.current_player
	if _pending_attacker_pos == Vector2i(-1, -1):
		if GameManager.get_team_at(cell) == team:
			var targets := GameManager.get_valid_attack_targets(cell)
			if not targets.is_empty():
				_pending_attacker_pos = cell
				board.set_selected(cell)
				board.highlight_attack_targets(targets)
	else:
		var targets := GameManager.get_valid_attack_targets(_pending_attacker_pos)
		if cell in targets:
			_execute_pending_attack(cell)
		elif GameManager.get_team_at(cell) == team and not GameManager.get_valid_attack_targets(cell).is_empty():
			_pending_attacker_pos = cell
			board.set_selected(cell)
			board.highlight_attack_targets(GameManager.get_valid_attack_targets(cell))
		else:
			_pending_attacker_pos = Vector2i(-1, -1)
			board.clear_highlights()

func _execute_pending_attack(enemy_cell: Vector2i) -> void:
	var player := TurnManager.current_player
	var attacker := _pending_attacker_pos
	var card_index := _pending_attack_card_index
	_pending_attack_card_index = -1
	_pending_attacker_pos = Vector2i(-1, -1)
	CardSystem.play_card(player, card_index)
	TurnManager.on_card_played(CardType.Type.ATTACK)
	var adjacent := GameManager.get_adjacent_allies(attacker, player)
	TurnManager.on_attack_declared(attacker, enemy_cell, adjacent)
```

**Step 4: Validate**

`validate_script("res://scripts/game/main.gd")` — expect valid.

**Step 5: Commit**

```bash
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz add scripts/game/main.gd
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz commit -m "feat: attack card confirms on own pawn tap, cancel returns card to hand"
```

---

### Task 3: Visual verification + push

**Step 1: Play scene**

`play_scene("res://scenes/main.tscn")`

**Step 2: Check output log**

`get_output_log` — zero ERROR lines expected.

**Step 3: Verify attack card pending state via game script**

```gdscript
# Skip placement phase
GameManager.board_state = {Vector2i(3,3): 1, Vector2i(3,4): 2}
GameManager.pawn_count = [0, 1, 1]
GameManager.state = GameManager.State.PLAYING
CardSystem.setup()
TurnManager.start_game()
# Force an Attack card into P1's hand at index 0
var hand := CardSystem.get_hand(1)
hand[0] = CardType.Type.ATTACK
# Simulate tapping the attack card
var hud = get_tree().root.get_node("Main/HUD")
hud._on_hand_card_tapped(0)
_mcp_print("pending_card_index: " + str(hud._pending_card_index))
_mcp_print("cancel_attack_visible: " + str(hud._cancel_attack_btn.visible))
_mcp_print("play_card_visible: " + str(hud.play_card_btn.visible))
var main = get_tree().root.get_node("Main")
_mcp_print("pending_attack_card_index: " + str(main._pending_attack_card_index))
```

Expected:
```
pending_card_index: 0
cancel_attack_visible: true
play_card_visible: false
pending_attack_card_index: 0
```

**Step 4: Verify own pawn tap selects attacker**

```gdscript
var main = get_tree().root.get_node("Main")
main._handle_attack_card_tap(Vector2i(3,3))
_mcp_print("pending_attacker_pos: " + str(main._pending_attacker_pos))
_mcp_print("phase: " + str(TurnManager.phase))
```

Expected:
```
pending_attacker_pos: (3, 3)
phase: 0
```
(Phase 0 = PLAY_CARD — card not played yet)

**Step 5: Verify Cancel resets state**

```gdscript
var hud = get_tree().root.get_node("Main/HUD")
var main = get_tree().root.get_node("Main")
hud._on_cancel_attack_btn_pressed()
_mcp_print("pending_attack_card_index: " + str(main._pending_attack_card_index))
_mcp_print("pending_attacker_pos: " + str(main._pending_attacker_pos))
_mcp_print("cancel_attack_visible: " + str(hud._cancel_attack_btn.visible))
_mcp_print("phase: " + str(TurnManager.phase))
```

Expected:
```
pending_attack_card_index: -1
pending_attacker_pos: (-1, -1)
cancel_attack_visible: false
phase: 0
```

**Step 6: Verify full attack flow (card pending → tap own pawn → tap enemy)**

```gdscript
# Re-select attack card
var hud = get_tree().root.get_node("Main/HUD")
var main = get_tree().root.get_node("Main")
hud._on_hand_card_tapped(0)
main._handle_attack_card_tap(Vector2i(3,3))
# Tap enemy
main._handle_attack_card_tap(Vector2i(3,4))
_mcp_print("phase_after_attack: " + str(TurnManager.phase))
_mcp_print("pending_attack_card_index: " + str(main._pending_attack_card_index))
```

Expected:
```
phase_after_attack: 3
pending_attack_card_index: -1
```
(Phase 3 = RESOLVE_DEFENSE)

**Step 7: Stop scene**

`stop_scene()`

**Step 8: Push**

```bash
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz push
```
