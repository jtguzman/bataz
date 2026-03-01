# HUD Visuals Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add three visual features to the HUD: (1) turn history sidebar (right), (2) dice roll overlay on the board (center), (3) draw/discard pile panel (left).

**Architecture:** All three features are implemented as a single rewrite of `res://scripts/ui/hud.gd` using `create_script`. All panels are created programmatically in `_ready()` per ADR-007 (add_node/save_scene has a runtime sync bug where nodes appear in .tscn but are null at runtime). No other files are modified.

**Tech Stack:** Godot 4.6.1 GDScript, MCP tools (`create_script`, `validate_script`, `play_scene`).

---

## CRITICAL CONTEXT — READ BEFORE STARTING

### Tooling rules
- Use `create_script` to write the script (full content replacement). **NEVER use `edit_script`** — it silently inserts garbage characters at line boundaries.
- After writing: run `validate_script("res://scripts/ui/hud.gd")`. `valid: true` is the pass condition.
- Ignore "Identifier not found: TurnManager / CardSystem / GameManager" warnings — these are autoloads registered in Project Settings and cannot be resolved by GDScript's static analyzer.
- Git repo is at the Windows path. All git commands use: `git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz`

### Layout (1152×648 viewport, CanvasLayer coords)
- Left column (deck panel): x=0→324, y=48→552 (empty space left of board)
- Board area: x=324→828, y=48→552 (center 504×504)
- Right column (history panel): x=828→1152, y=48→552 (empty space right of board)
- Board center in viewport: (576, 300)
- Dice overlay position: (496, 240) = board center minus half the 160×120 panel size

### What signals CardSystem emits
- `card_played(player, type)` — when a card is consumed from hand (NOT during discard_and_refill)
- `card_drawn(player, type)` — when a single card is drawn
- `hand_changed(player, hand)` — after EVERY hand change: play, draw, and discard_and_refill
- `draw_pile` and `discard_pile` are public `Array[CardType.Type]` vars — read directly

### Key data flow for history
- `_pending_history: Dictionary` accumulates as signals fire, then is committed to the panel on `turn_ended`
- For Discard & Pass: `card_played` does NOT fire — set `_pending_history` directly in `_on_discard_pass_btn_pressed()`
- Movement: `movement_rolled(points)` → set detail = `"  Rolled N pts"`
- Attack: `attack_resolved(dp, survives, atk, def)` → set detail = `"  Atk:X Def:Y -> Hit!"`

---

## Task 1: Write the combined hud.gd

**Files:**
- Modify: `res://scripts/ui/hud.gd` (full rewrite via `create_script`)

### Step 1: Verify baseline

Run `validate_script("res://scripts/ui/hud.gd")`. Confirm `valid: true`. This is the starting point.

### Step 2: Write the new script

Use `create_script` with path `res://scripts/ui/hud.gd` and the complete content below.

```gdscript
# res://scripts/ui/hud.gd
extends CanvasLayer

signal card_played_by_ui(player: int, card_index: int)
signal discard_pass_requested(player: int)
signal defense_chosen(played_defense: bool, card_index: int)
signal movement_done_requested
signal turn_end_confirmed

@onready var top_hand: HBoxContainer = $TopBar/TopHand
@onready var bottom_hand: HBoxContainer = $BottomBar/BottomHand
@onready var turn_label: Label = $TopBar/TurnLabel
@onready var done_btn: Button = $BottomBar/DoneBtn
@onready var discard_pass_btn: Button = $BottomBar/DiscardPassBtn
@onready var confirm_btn: Button = $BottomBar/ConfirmBtn
@onready var dice_panel: PanelContainer = $DicePanel
@onready var dice_label: Label = $DicePanel/DiceLabel
@onready var defense_panel: PanelContainer = $DefensePanel
@onready var defense_hand: HBoxContainer = $DefensePanel/VBox/DefenseHand
@onready var defense_pass_btn: Button = $DefensePanel/VBox/PassBtn
@onready var defense_title: Label = $DefensePanel/VBox/Title
@onready var turn_overlay: PanelContainer = $TurnOverlay
@onready var turn_overlay_label: Label = $TurnOverlay/Label

var _card_scene: PackedScene
var current_player: int = 1
var _pending_card_index: int = -1
var play_card_btn: Button

# History panel
var _history_scroll: ScrollContainer
var _history_list: VBoxContainer
var _pending_history: Dictionary = {}

# Dice overlay
var _dice_overlay: PanelContainer
var _dice_type_label: Label
var _dice_result_label: Label

# Deck panel
var _draw_count_label: Label
var _discard_count_label: Label
var _discard_card_rect: ColorRect

func _ready() -> void:
	_card_scene = load("res://scenes/cards/card.tscn")
	# Programmatic nodes: add_node/save_scene has runtime sync bug (ADR-007)
	play_card_btn = Button.new()
	play_card_btn.text = "Play Card"
	play_card_btn.custom_minimum_size = Vector2(120, 60)
	play_card_btn.visible = false
	$BottomBar.add_child(play_card_btn)
	_create_history_panel()
	_create_dice_overlay()
	_create_deck_panel()
	TurnManager.turn_started.connect(_on_turn_started)
	TurnManager.phase_changed.connect(_on_phase_changed)
	TurnManager.defense_requested.connect(_on_defense_requested)
	TurnManager.movement_rolled.connect(_on_movement_rolled)
	TurnManager.attack_resolved.connect(_on_attack_resolved)
	TurnManager.turn_ended.connect(_on_turn_ended_history)
	CardSystem.hand_changed.connect(_on_hand_changed)
	CardSystem.hand_changed.connect(func(_p: int, _h: Array): _update_deck_display())
	CardSystem.card_played.connect(_on_card_played_history)
	GameManager.game_over.connect(_on_game_over)
	_set_all_action_buttons_hidden()
	dice_panel.visible = false
	defense_panel.visible = false
	turn_overlay.visible = false
	done_btn.pressed.connect(_on_done_btn_pressed)
	discard_pass_btn.pressed.connect(_on_discard_pass_btn_pressed)
	confirm_btn.pressed.connect(_on_confirm_btn_pressed)
	defense_pass_btn.pressed.connect(_on_defense_pass_btn_pressed)
	play_card_btn.pressed.connect(_on_play_card_btn_pressed)

# --- History panel ---

func _create_history_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(828, 48)
	panel.size = Vector2(324, 504)
	add_child(panel)
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)
	var title := Label.new()
	title.text = "History"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	_history_scroll = ScrollContainer.new()
	_history_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_history_scroll)
	_history_list = VBoxContainer.new()
	_history_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history_scroll.add_child(_history_list)

func _on_card_played_history(player: int, type: int) -> void:
	_pending_history = {"player": player, "card": type, "detail": ""}

func _on_turn_ended_history(_player: int) -> void:
	if _pending_history.is_empty():
		return
	_append_history_entry(
		_pending_history.get("player", 0),
		_pending_history.get("card", -1),
		_pending_history.get("detail", "")
	)
	_pending_history = {}

func _append_history_entry(player: int, card_type: int, detail: String) -> void:
	_history_list.add_child(HSeparator.new())
	var card_name: String
	match card_type:
		CardType.Type.MOVEMENT:
			card_name = "Movement"
		CardType.Type.ATTACK:
			card_name = "Attack"
		CardType.Type.DEFENSE:
			card_name = "Defense"
		_:
			card_name = "Passed"
	var lbl := Label.new()
	lbl.text = "P%d -- %s\n%s" % [player, card_name, detail]
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_history_list.add_child(lbl)
	_scroll_history_to_bottom()

func _scroll_history_to_bottom() -> void:
	await get_tree().process_frame
	_history_scroll.scroll_vertical = int(_history_scroll.get_v_scroll_bar().max_value)

# --- Dice overlay ---

func _create_dice_overlay() -> void:
	_dice_overlay = PanelContainer.new()
	_dice_overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_dice_overlay.position = Vector2(496, 240)
	_dice_overlay.size = Vector2(160, 120)
	_dice_overlay.visible = false
	add_child(_dice_overlay)
	var vbox := VBoxContainer.new()
	_dice_overlay.add_child(vbox)
	_dice_type_label = Label.new()
	_dice_type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_dice_type_label)
	_dice_result_label = Label.new()
	_dice_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dice_result_label.add_theme_font_size_override("font_size", 64)
	vbox.add_child(_dice_result_label)

# --- Deck panel ---

func _create_deck_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(0, 48)
	panel.size = Vector2(324, 504)
	add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	_draw_count_label = Label.new()
	_draw_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_draw_count_label)
	var draw_card := ColorRect.new()
	draw_card.color = Color(0.2, 0.2, 0.6, 1)
	draw_card.custom_minimum_size = Vector2(100, 140)
	draw_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(draw_card)
	vbox.add_child(HSeparator.new())
	_discard_count_label = Label.new()
	_discard_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_discard_count_label)
	_discard_card_rect = ColorRect.new()
	_discard_card_rect.color = Color(0.3, 0.3, 0.3, 1)
	_discard_card_rect.custom_minimum_size = Vector2(100, 140)
	_discard_card_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(_discard_card_rect)
	_update_deck_display()

func _update_deck_display() -> void:
	var draw_count := CardSystem.draw_pile.size()
	var discard_count := CardSystem.discard_pile.size()
	_draw_count_label.text = "Draw -- %d" % draw_count
	_discard_count_label.text = "Discard -- %d" % discard_count
	if discard_count > 0:
		var last_type: int = CardSystem.discard_pile[-1]
		match last_type:
			CardType.Type.MOVEMENT:
				_discard_card_rect.color = Color(0.2, 0.7, 0.2, 1)
			CardType.Type.ATTACK:
				_discard_card_rect.color = Color(0.8, 0.2, 0.2, 1)
			CardType.Type.DEFENSE:
				_discard_card_rect.color = Color(0.2, 0.4, 0.8, 1)
	else:
		_discard_card_rect.color = Color(0.3, 0.3, 0.3, 1)

# --- Existing turn/phase handlers ---

func _on_turn_started(player: int) -> void:
	current_player = player
	turn_label.text = "Player %d" % player
	_rebuild_both_hands()
	_set_all_action_buttons_hidden()
	discard_pass_btn.visible = true

func _on_phase_changed(phase: TurnManager.Phase) -> void:
	_set_all_action_buttons_hidden()
	match phase:
		TurnManager.Phase.PLAY_CARD:
			discard_pass_btn.visible = true
		TurnManager.Phase.RESOLVE_MOVEMENT:
			done_btn.visible = true
		TurnManager.Phase.END:
			pass

func _on_movement_rolled(points: int) -> void:
	_show_dice("1d4", points)
	_pending_history["detail"] = "  Rolled %d pts" % points

func _on_defense_requested(_ap: Vector2i, _dp: Vector2i, attack_roll: int, die_label: String) -> void:
	_show_dice(die_label, attack_roll)
	var defender := 2 if current_player == 1 else 1
	var hand := CardSystem.get_hand(defender)
	defense_title.text = "Player %d - Defend? (ATK=%d)" % [defender, attack_roll]
	for child in defense_hand.get_children():
		child.queue_free()
	var has_defense_card := false
	for i in hand.size():
		if hand[i] == CardType.Type.DEFENSE:
			var card = _card_scene.instantiate()
			card.setup(i, hand[i])
			var idx := i
			card.card_selected.connect(func(_x): _on_defense_card_tapped(idx))
			defense_hand.add_child(card)
			has_defense_card = true
	if not has_defense_card:
		var lbl := Label.new()
		lbl.text = "(no Defense cards)"
		defense_hand.add_child(lbl)
	defense_panel.visible = true

func _on_defense_card_tapped(index: int) -> void:
	defense_panel.visible = false
	defense_chosen.emit(true, index)

func _on_defense_pass_btn_pressed() -> void:
	defense_panel.visible = false
	defense_chosen.emit(false, -1)

func _on_attack_resolved(_dp: Vector2i, pawn_survives: bool, attack_roll: int, defense_roll: int) -> void:
	var msg := ""
	if defense_roll > 0:
		msg = "ATK %d vs DEF %d - %s" % [attack_roll, defense_roll, "Blocked!" if pawn_survives else "Hit!"]
	else:
		msg = "ATK %d - Hit!" % attack_roll
	dice_label.text = msg
	dice_panel.visible = true
	get_tree().create_timer(2.0).timeout.connect(func(): dice_panel.visible = false)
	if defense_roll > 0:
		_pending_history["detail"] = "  Atk:%d Def:%d -> %s" % [attack_roll, defense_roll, "Blocked!" if pawn_survives else "Hit!"]
	else:
		_pending_history["detail"] = "  Atk:%d -> Hit!" % attack_roll

func show_discard_preview() -> void:
	_set_all_action_buttons_hidden()
	confirm_btn.visible = true

func _on_hand_changed(player: int, hand: Array) -> void:
	_rebuild_hand(player, hand)

func _rebuild_both_hands() -> void:
	_rebuild_hand(1, CardSystem.get_hand(1))
	_rebuild_hand(2, CardSystem.get_hand(2))

func _rebuild_hand(player: int, hand: Array) -> void:
	var is_active := player == current_player
	var container: HBoxContainer = bottom_hand if is_active else top_hand
	for child in container.get_children():
		child.queue_free()
	for i in hand.size():
		var card = _card_scene.instantiate()
		card.setup(i, hand[i], not is_active)
		if is_active:
			var idx := i
			card.card_selected.connect(func(_x): _on_hand_card_tapped(idx))
		container.add_child(card)

func _on_hand_card_tapped(idx: int) -> void:
	if TurnManager.phase != TurnManager.Phase.PLAY_CARD:
		return
	var hand := CardSystem.get_hand(current_player)
	var card_type: int = hand[idx]
	if card_type == CardType.Type.DEFENSE:
		_show_message("Defense cards are reactive only")
		return
	if card_type == CardType.Type.ATTACK and not _has_valid_attacker():
		_show_message("No pawns adjacent to enemies")
		return
	_pending_card_index = idx
	_update_hand_selection()
	play_card_btn.visible = true

func _has_valid_attacker() -> bool:
	var team := TurnManager.current_player
	for pos in GameManager.board_state:
		if GameManager.board_state[pos] == team:
			if not GameManager.get_valid_attack_targets(pos).is_empty():
				return true
	return false

func _show_message(msg: String) -> void:
	dice_label.text = msg
	dice_panel.visible = true
	get_tree().create_timer(2.0).timeout.connect(func(): dice_panel.visible = false)

func _update_hand_selection() -> void:
	var i := 0
	for child in bottom_hand.get_children():
		child.modulate = Color(1, 1, 1, 1) if i == _pending_card_index else Color(0.4, 0.4, 0.4, 1)
		i += 1

func _on_play_card_btn_pressed() -> void:
	if _pending_card_index < 0:
		return
	card_played_by_ui.emit(current_player, _pending_card_index)
	_pending_card_index = -1
	play_card_btn.visible = false

func show_turn_overlay(player: int) -> void:
	turn_overlay_label.text = "Player %d's Turn" % player
	turn_overlay.visible = true
	get_tree().create_timer(0.8).timeout.connect(func(): turn_overlay.visible = false)

func _show_dice(die_label: String, result: int) -> void:
	_dice_type_label.text = die_label
	_dice_result_label.text = str(result)
	_dice_overlay.visible = true
	get_tree().create_timer(1.5).timeout.connect(func(): _dice_overlay.visible = false)

func _set_all_action_buttons_hidden() -> void:
	done_btn.visible = false
	discard_pass_btn.visible = false
	confirm_btn.visible = false
	play_card_btn.visible = false
	_pending_card_index = -1

func _on_done_btn_pressed() -> void:
	movement_done_requested.emit()

func _on_discard_pass_btn_pressed() -> void:
	_pending_history = {"player": current_player, "card": -1, "detail": "  Passed"}
	discard_pass_requested.emit(current_player)

func _on_confirm_btn_pressed() -> void:
	turn_end_confirmed.emit()

func _on_game_over(winner: int) -> void:
	turn_label.text = "Player %d Wins!" % winner
	_set_all_action_buttons_hidden()
```

### Step 3: Validate

Run `validate_script("res://scripts/ui/hud.gd")`.

Expected: `valid: true`. Ignore "Identifier not found" warnings for TurnManager, CardSystem, GameManager, CardType.

If `valid: false` with a real parse error: use `read_script("res://scripts/ui/hud.gd")` to inspect the written content, find the offending line, and rewrite with `create_script`.

### Step 4: Commit

```bash
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz add scripts/ui/hud.gd
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz commit -m "feat: add history panel, dice overlay, and deck panel to HUD"
```

---

## Task 2: Visual verification

**Files:** None (read-only testing)

### Step 1: Run the game

```
play_scene("res://scenes/main.tscn")
```

### Step 2: Take initial screenshot

Use `get_game_screenshot`. Verify:
- Left column (x=0→324): gray panel with "Draw -- N" label + dark blue rectangle + "Discard -- 0" + gray rectangle
- Right column (x=828→1152): panel with "History" title
- Board center area is clear (no dice overlay yet)

### Step 3: Play a Movement card

Select a Movement card → press "Play Card" → dice overlay should appear centered on board showing die type + big number → disappears after ~1.5s → after moving pawns and pressing Done, history panel shows a new entry.

Take a screenshot confirming the dice overlay appeared (may need to capture during the 1.5s window — try `capture_frames` if available, otherwise trust the signal flow and check history entry).

### Step 4: Verify deck counts update

After playing the Movement card: "Draw" count should decrease by 1 from the next turn's draw, discard count should increase. Check via screenshot after turn ends.

### Step 5: Play an Attack card (if pawns are adjacent)

Move pawns into position, then play Attack card. Dice overlay should appear with the attack die type + roll number. After combat, DicePanel (center text) shows "ATK X vs DEF Y - Hit!" or "ATK X - Hit!". History entry shows the combat result.

### Step 6: Test Discard & Pass

Press "Discard & Pass" → confirm → after turn ends, history should show:
```
P1 -- Passed
  Passed
```

### Step 7: Stop scene

```
stop_scene()
```

---

## Task 3: Update docs

**Files:**
- `/home/jtguzman/workspace/godot/bataz/docs/progress.md`
- `/mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz/docs/progress.md`

### Step 1: Add to Milestone 6 in progress.md

After the existing last line in Milestone 6:
```
- [x] Turn overlay ("Player X's Turn" during flip)
```

Add:
```
- [x] Turn history sidebar (card played, dice result, outcome per turn)
- [x] Dice roll overlay on board (die type + result, fades after 1.5s)
- [x] Draw/discard pile panel left of board (live card counts, last discard color)
```

Update both copies (WSL and Windows).

### Step 2: Commit

```bash
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz add docs/progress.md
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz commit -m "docs: update progress — HUD visuals complete"
```
