# Selective Discard Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Allow a player to choose which 1–4 cards to discard (and draw that many) instead of always discarding all 4.

**Architecture:** Discard mode lives entirely in `hud.gd`. Pressing "Discard & Pass" activates a selection mode on the active hand; confirm calls a new `CardSystem.selective_discard()` then emits the existing `discard_pass_requested` signal. `turn_manager.gd` loses card management from `on_discard_and_pass`. `main.gd` simplifies — the old "confirm preview" step is removed.

**Tech Stack:** Godot 4.6.1 GDScript, MCP Pro tools. No test runner — verification is via `validate_script` + `play_scene` + visual inspection. Use `create_script` for all full-file rewrites. NEVER use `edit_script`.

---

## Context for implementer

- Git: `git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz`
- `validate_script` warnings for autoloads (TurnManager, CardSystem, GameManager, CardType) = expected false-positives. Only fail on real parse errors.
- `create_script` overwrites the entire file — always read current content first with `read_script`, apply changes, then write the full new content.

---

### Task 1: Update `turn_manager.gd` — remove card draw from `on_discard_and_pass`

**Files:**
- Modify: `res://scripts/game/turn_manager.gd`

Card management moves to hud.gd. `on_discard_and_pass` should only change the phase.

**Step 1: Read current script**

`read_script("res://scripts/game/turn_manager.gd")`

**Step 2: Validate baseline**

`validate_script("res://scripts/game/turn_manager.gd")` — expect valid (autoload warnings OK).

**Step 3: Rewrite with create_script**

Replace `on_discard_and_pass` function body — remove the `CardSystem.discard_and_refill` call:

```gdscript
func on_discard_and_pass() -> void:
	phase = Phase.END
	phase_changed.emit(phase)
	# end_turn() is called by Main after flip animation
```

Full new `on_discard_and_pass` is just those 3 lines. Everything else stays identical.

**Step 4: Validate**

`validate_script("res://scripts/game/turn_manager.gd")` — expect valid.

**Step 5: Commit**

```bash
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz add scripts/game/turn_manager.gd
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz commit -m "refactor: remove card draw from on_discard_and_pass"
```

---

### Task 2: Update `card_system.gd` — add `selective_discard`

**Files:**
- Modify: `res://scripts/cards/card_system.gd`

**Step 1: Read current script**

`read_script("res://scripts/cards/card_system.gd")`

**Step 2: Rewrite with create_script**

Add this method at the end of the file, before the last line:

```gdscript
func selective_discard(player: int, indices: Array[int]) -> void:
	var hand := _get_hand(player)
	var sorted := indices.duplicate()
	sorted.sort()
	sorted.reverse()
	for i in sorted:
		discard_pile.append(hand[i])
		hand.remove_at(i)
	var count := sorted.size()
	_ensure_drawable(count)
	for _j in count:
		hand.append(_draw_one())
	_set_hand(player, hand)
	hand_changed.emit(player, hand.duplicate())
```

Logic: sort indices descending so earlier indices don't shift when removing later ones. Draws exactly `count` new cards.

**Step 3: Validate**

`validate_script("res://scripts/cards/card_system.gd")` — expect valid.

**Step 4: Commit**

```bash
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz add scripts/cards/card_system.gd
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz commit -m "feat: add selective_discard to CardSystem"
```

---

### Task 3: Update `hud.gd` — add discard mode

**Files:**
- Modify: `res://scripts/ui/hud.gd`

This is the largest change. Read the full current file first.

**Step 1: Read current script**

`read_script("res://scripts/ui/hud.gd")`

**Step 2: Rewrite with create_script**

Apply ALL of the following changes in one full rewrite:

**A. Remove signal `turn_end_confirmed`** (no longer needed — confirm button is now exclusively for discard).

**B. Add state variables** (after existing `var play_card_btn: Button` line):
```gdscript
var _discard_mode: bool = false
var _selected_discard: Array[int] = []
var _cancel_discard_btn: Button
```

**C. In `_ready()`, after the `play_card_btn` block**, add `_cancel_discard_btn`:
```gdscript
	_cancel_discard_btn = Button.new()
	_cancel_discard_btn.text = "Cancel"
	_cancel_discard_btn.custom_minimum_size = Vector2(80, 60)
	_cancel_discard_btn.visible = false
	$BottomBar.add_child(_cancel_discard_btn)
```

**D. In `_ready()`, remove** `hud.turn_end_confirmed.connect(...)` connection line (it no longer exists).
Add at end of connections:
```gdscript
	_cancel_discard_btn.pressed.connect(_on_cancel_discard_btn_pressed)
```

**E. Update `_set_all_action_buttons_hidden()`**:
```gdscript
func _set_all_action_buttons_hidden() -> void:
	done_btn.visible = false
	discard_pass_btn.visible = false
	confirm_btn.visible = false
	play_card_btn.visible = false
	_cancel_discard_btn.visible = false
	_pending_card_index = -1
	_discard_mode = false
	_selected_discard.clear()
```

**F. Replace `_on_discard_pass_btn_pressed()`**:
```gdscript
func _on_discard_pass_btn_pressed() -> void:
	_discard_mode = true
	_selected_discard.clear()
	discard_pass_btn.visible = false
	_cancel_discard_btn.visible = true
	_update_discard_selection_display()
```

**G. Add `_on_cancel_discard_btn_pressed()`** (new function):
```gdscript
func _on_cancel_discard_btn_pressed() -> void:
	_discard_mode = false
	_selected_discard.clear()
	_cancel_discard_btn.visible = false
	confirm_btn.visible = false
	discard_pass_btn.visible = true
	_rebuild_hand(current_player, CardSystem.get_hand(current_player))
```

**H. Add `_update_discard_selection_display()`** (new function):
```gdscript
func _update_discard_selection_display() -> void:
	var i := 0
	for child in bottom_hand.get_children():
		if i in _selected_discard:
			child.modulate = Color(1.0, 0.5, 0.5, 1.0)
		else:
			child.modulate = Color(1.0, 1.0, 1.0, 1.0)
		i += 1
	if _selected_discard.size() > 0:
		confirm_btn.text = "Confirm Discard (%d)" % _selected_discard.size()
		confirm_btn.visible = true
	else:
		confirm_btn.visible = false
```

**I. Update `_on_hand_card_tapped(idx)`** — add discard mode branch at the top:
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
	# ... rest of existing logic unchanged
```

**J. Replace `_on_confirm_btn_pressed()`**:
```gdscript
func _on_confirm_btn_pressed() -> void:
	if not _discard_mode:
		return
	var indices: Array[int] = []
	indices.assign(_selected_discard)
	_discard_mode = false
	_selected_discard.clear()
	CardSystem.selective_discard(current_player, indices)
	_pending_history = {"player": current_player, "card": -1, "detail": "  Passed (discarded %d)" % indices.size()}
	discard_pass_requested.emit(current_player)
```

**K. Remove `show_discard_preview()`** function entirely.

**Step 3: Validate**

`validate_script("res://scripts/ui/hud.gd")` — expect valid (autoload warnings OK).

**Step 4: Commit**

```bash
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz add scripts/ui/hud.gd
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz commit -m "feat: add discard mode to HUD for selective card discard"
```

---

### Task 4: Update `main.gd` — simplify discard handler

**Files:**
- Modify: `res://scripts/game/main.gd`

**Step 1: Read current script**

`read_script("res://scripts/game/main.gd")`

**Step 2: Rewrite with create_script**

Apply these changes:

**A. Remove** `var _awaiting_discard_confirm: bool = false`

**B. In `_ready()`, remove** `hud.turn_end_confirmed.connect(_on_turn_end_confirmed)`

**C. Replace `_on_phase_changed()`** — remove `_awaiting_discard_confirm` guard:
```gdscript
func _on_phase_changed(phase: TurnManager.Phase) -> void:
	board.clear_highlights()
	_move_selected = Vector2i(-1, -1)
	_attack_selected = Vector2i(-1, -1)
	if phase == TurnManager.Phase.END:
		if GameManager.state != GameManager.State.GAME_OVER:
			_do_flip_then_next_turn()
```

**D. Replace `_on_discard_pass_requested()`**:
```gdscript
func _on_discard_pass_requested(_player: int) -> void:
	TurnManager.on_discard_and_pass()
```

**E. Remove `_on_turn_end_confirmed()`** function entirely.

**Step 3: Validate**

`validate_script("res://scripts/game/main.gd")` — expect valid.

**Step 4: Commit**

```bash
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz add scripts/game/main.gd
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz commit -m "refactor: simplify discard handler in main, remove confirm preview step"
```

---

### Task 5: Visual verification + push

**Step 1: Play scene**

`play_scene("res://scenes/main.tscn")`

**Step 2: Check output log**

`get_output_log` — zero ERROR lines expected.

**Step 3: Screenshot — initial state**

`get_game_screenshot` — verify "Discard & Pass" button is visible.

**Step 4: Trigger discard mode via game script**

```gdscript
# Simulate pressing "Discard & Pass" via HUD directly
var hud = get_tree().root.get_node("Main/HUD")
hud._on_discard_pass_btn_pressed()
_mcp_print("discard_mode: " + str(hud._discard_mode))
```

Expected output: `discard_mode: true`

**Step 5: Screenshot — discard mode active**

`get_game_screenshot` — verify:
- "Discard & Pass" button is hidden
- "Cancel" button is visible
- Hand cards are visible (normal color, none selected yet)
- "Confirm Discard" button NOT visible (0 selected)

**Step 6: Select a card via game script**

```gdscript
var hud = get_tree().root.get_node("Main/HUD")
hud._on_hand_card_tapped(0)
_mcp_print("selected: " + str(hud._selected_discard))
```

Expected: `selected: [0]`

**Step 7: Screenshot — card selected**

`get_game_screenshot` — verify:
- Card 0 is reddish/highlighted
- "Confirm Discard (1)" button is visible

**Step 8: Cancel via game script**

```gdscript
var hud = get_tree().root.get_node("Main/HUD")
hud._on_cancel_discard_btn_pressed()
_mcp_print("discard_mode: " + str(hud._discard_mode))
```

Expected: `discard_mode: false`

**Step 9: Screenshot — after cancel**

`get_game_screenshot` — verify normal PLAY_CARD state restored ("Discard & Pass" visible, no reddish cards).

**Step 10: Stop scene**

`stop_scene()`

**Step 11: Push**

```bash
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz push
```

---

## After implementation: Code review

The user has also requested a full-app code review for inconsistencies, duplication, and anti-patterns. After Task 5 is complete and pushed, use the `superpowers:requesting-code-review` skill to initiate a review of all game scripts.
