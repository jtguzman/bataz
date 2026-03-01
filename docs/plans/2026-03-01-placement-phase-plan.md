# Placement Phase Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a placement phase before turns begin where each player taps cells to place their 8 pawns in their home territory (P1: rows 5–7, P2: rows 0–2), with hidden information between players.

**Architecture:** New `PLACEMENT_P1` / `PLACEMENT_P2` states in `GameManager`. `main.gd` wires tap events to placement logic during these states. Board renders placement pawns in real time. HUD shows a placement label and confirm button. After both players confirm, `finalize_placement()` merges both dicts into `board_state` and hands off to `TurnManager`. No changes to `turn_manager.gd` or `card_system.gd`.

**Tech Stack:** Godot 4.6.1 GDScript, MCP Pro tools. No test runner — verification is via `validate_script` + `play_scene` + visual inspection. Use `create_script` for all full-file rewrites. NEVER use `edit_script`.

---

## Context for implementer

- Git: `git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz`
- `validate_script` warnings for autoloads (TurnManager, CardSystem, GameManager, CardType) = expected false-positives. Only fail on real parse errors.
- `create_script` overwrites the entire file — always read current content first with `read_script`, apply changes, then write the full new content.
- **Board coordinate convention:** row 0 = visual top (P2's home side), row 7 = visual bottom (P1's home side). P1 places in rows 5–7; P2 places in rows 0–2.
- After P1 confirms, the Main node is rotated +180° (same flip used between turns). After P2 confirms, it is rotated +180° again (back to 0°) before the game starts.

---

### Task 1: Update `game_manager.gd` — add placement states and logic

**Files:**
- Modify: `res://scripts/game/game_manager.gd`

**Step 1: Read current script**

`read_script("res://scripts/game/game_manager.gd")`

**Step 2: Rewrite with create_script**

Full new content (replaces entire file):

```gdscript
# res://scripts/game/game_manager.gd
extends Node

signal game_started
signal game_over(winner: int)
signal pawn_removed(board_pos: Vector2i, team: int)
signal pawn_moved(from_pos: Vector2i, to_pos: Vector2i)
signal placement_started(player: int)

enum State { SETUP, PLACEMENT_P1, PLACEMENT_P2, PLAYING, GAME_OVER }

var state: State = State.SETUP
var board_state: Dictionary = {}
var pawn_count: Array[int] = [0, 8, 8]

var placement_p1: Dictionary = {}
var placement_p2: Dictionary = {}

func start_placement() -> void:
	state = State.PLACEMENT_P1
	placement_p1.clear()
	placement_p2.clear()
	board_state.clear()
	pawn_count = [0, 8, 8]
	placement_started.emit(1)

func get_placement_zone(player: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var rows: Array[int] = [5, 6, 7] if player == 1 else [0, 1, 2]
	for row in rows:
		for col in 8:
			cells.append(Vector2i(col, row))
	return cells

func place_pawn(player: int, pos: Vector2i) -> void:
	if player == 1:
		placement_p1[pos] = player
	else:
		placement_p2[pos] = player

func remove_pawn_from_placement(player: int, pos: Vector2i) -> void:
	if player == 1:
		placement_p1.erase(pos)
	else:
		placement_p2.erase(pos)

func confirm_placement(player: int) -> void:
	if player == 1:
		state = State.PLACEMENT_P2
		placement_started.emit(2)
	else:
		finalize_placement()

func finalize_placement() -> void:
	for pos in placement_p1:
		board_state[pos] = placement_p1[pos]
	for pos in placement_p2:
		board_state[pos] = placement_p2[pos]
	state = State.PLAYING
	CardSystem.setup()
	TurnManager.start_game()
	game_started.emit()

func get_team_at(pos: Vector2i) -> int:
	return board_state.get(pos, 0)

func is_occupied(pos: Vector2i) -> bool:
	return board_state.has(pos)

func move_pawn(from_pos: Vector2i, to_pos: Vector2i) -> void:
	assert(board_state.has(from_pos), "No pawn at %s" % str(from_pos))
	var team: int = board_state[from_pos]
	board_state.erase(from_pos)
	board_state[to_pos] = team
	pawn_moved.emit(from_pos, to_pos)

func remove_pawn_at(pos: Vector2i) -> void:
	if not board_state.has(pos):
		push_warning("[GameManager] No pawn at %s" % str(pos))
		return
	var team: int = board_state[pos]
	board_state.erase(pos)
	pawn_count[team] -= 1
	pawn_removed.emit(pos, team)
	_check_win()

func get_adjacent_allies(pos: Vector2i, team: int) -> int:
	var count := 0
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			if get_team_at(Vector2i(pos.x + dx, pos.y + dy)) == team:
				count += 1
	return count

func get_valid_moves(pos: Vector2i) -> Array[Vector2i]:
	var team := get_team_at(pos)
	var moves: Array[Vector2i] = []
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var neighbor := Vector2i(pos.x + dx, pos.y + dy)
			if _in_bounds(neighbor) and get_team_at(neighbor) != team:
				moves.append(neighbor)
	return moves

func get_valid_attack_targets(pos: Vector2i) -> Array[Vector2i]:
	var team := get_team_at(pos)
	var targets: Array[Vector2i] = []
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var neighbor := Vector2i(pos.x + dx, pos.y + dy)
			var other := get_team_at(neighbor)
			if other != 0 and other != team:
				targets.append(neighbor)
	return targets

func has_valid_attacker(team: int) -> bool:
	for pos in board_state:
		if board_state[pos] == team:
			if not get_valid_attack_targets(pos).is_empty():
				return true
	return false

func _in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < 8 and pos.y >= 0 and pos.y < 8

func _check_win() -> void:
	if pawn_count[1] <= 0:
		state = State.GAME_OVER
		game_over.emit(2)
	elif pawn_count[2] <= 0:
		state = State.GAME_OVER
		game_over.emit(1)
```

**Step 3: Validate**

`validate_script("res://scripts/game/game_manager.gd")` — expect valid (autoload warnings OK).

**Step 4: Commit**

```bash
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz add scripts/game/game_manager.gd
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz commit -m "feat: add placement states and logic to GameManager"
```

---

### Task 2: Update `board.gd` — add placement visual methods

**Files:**
- Modify: `res://scripts/board/board.gd`

**Step 1: Read current script**

`read_script("res://scripts/board/board.gd")`

**Step 2: Rewrite with create_script**

Full new content (adds `highlight_placement_zone`, `render_placement`, `clear_placement_pawns` after `_ready`):

```gdscript
# res://scripts/board/board.gd
extends Node2D

signal board_cell_tapped(cell: Vector2i)

const CELL_SIZE := 63
const COLOR_LIGHT := Color("#F0D9B5")
const COLOR_DARK  := Color("#B58863")
const COLOR_MOVE_HIGHLIGHT  := Color(1.0, 1.0, 0.0, 0.35)
const COLOR_ATTACK_HIGHLIGHT := Color(1.0, 0.2, 0.2, 0.45)
const COLOR_SELECTED := Color(1.0, 1.0, 1.0, 0.35)

var highlight_move_cells: Array[Vector2i] = []
var highlight_attack_cells: Array[Vector2i] = []
var selected_cell: Vector2i = Vector2i(-1, -1)

var pawn_nodes: Dictionary = {}

var _pawn_scene: PackedScene

func _ready() -> void:
	_pawn_scene = load("res://scenes/pieces/pawn.tscn")
	GameManager.game_started.connect(_on_game_started)
	GameManager.pawn_removed.connect(_on_pawn_removed)
	GameManager.pawn_moved.connect(_on_pawn_moved)

func _on_game_started() -> void:
	for pawn in pawn_nodes.values():
		pawn.queue_free()
	pawn_nodes.clear()
	for child in get_children():
		child.queue_free()
	for pos in GameManager.board_state:
		var team: int = GameManager.board_state[pos]
		_spawn_pawn(pos, team)

func _spawn_pawn(board_pos: Vector2i, team: int) -> void:
	var pawn: Node2D = _pawn_scene.instantiate()
	pawn.team = team
	pawn.board_pos = board_pos
	pawn.pawn_color = Color("#4A90D9") if team == 1 else Color("#E05252")
	pawn.position = _cell_center(board_pos)
	add_child(pawn)
	pawn_nodes[board_pos] = pawn

# --- Placement phase methods ---

func highlight_placement_zone(cells: Array[Vector2i]) -> void:
	highlight_move_cells = cells
	highlight_attack_cells = []
	queue_redraw()

func render_placement(placement_dict: Dictionary, team: int) -> void:
	# Remove visual pawns for this team no longer in placement_dict
	var to_remove: Array[Vector2i] = []
	for pos in pawn_nodes:
		if pawn_nodes[pos].team == team and not placement_dict.has(pos):
			to_remove.append(pos)
	for pos in to_remove:
		pawn_nodes[pos].queue_free()
		pawn_nodes.erase(pos)
	# Spawn new pawns for positions added to placement_dict
	for pos in placement_dict:
		if not pawn_nodes.has(pos):
			_spawn_pawn(pos, team)
	queue_redraw()

func clear_placement_pawns(team: int) -> void:
	var to_remove: Array[Vector2i] = []
	for pos in pawn_nodes:
		if pawn_nodes[pos].team == team:
			to_remove.append(pos)
	for pos in to_remove:
		pawn_nodes[pos].queue_free()
		pawn_nodes.erase(pos)
	queue_redraw()

# --- Game phase methods ---

func _on_pawn_removed(board_pos: Vector2i, _team: int) -> void:
	if pawn_nodes.has(board_pos):
		pawn_nodes[board_pos].queue_free()
		pawn_nodes.erase(board_pos)
	queue_redraw()

func _on_pawn_moved(from_pos: Vector2i, to_pos: Vector2i) -> void:
	if pawn_nodes.has(from_pos):
		var pawn: Node2D = pawn_nodes[from_pos]
		pawn.board_pos = to_pos
		pawn.position = _cell_center(to_pos)
		pawn_nodes.erase(from_pos)
		pawn_nodes[to_pos] = pawn
	queue_redraw()

func set_selected(pos: Vector2i) -> void:
	if selected_cell != Vector2i(-1, -1) and pawn_nodes.has(selected_cell):
		pawn_nodes[selected_cell].deselect()
	selected_cell = pos
	if pos != Vector2i(-1, -1) and pawn_nodes.has(pos):
		pawn_nodes[pos].select()
	queue_redraw()

func highlight_moves(cells: Array[Vector2i]) -> void:
	highlight_move_cells = cells
	highlight_attack_cells = []
	queue_redraw()

func highlight_attack_targets(cells: Array[Vector2i]) -> void:
	highlight_attack_cells = cells
	highlight_move_cells = []
	queue_redraw()

func clear_highlights() -> void:
	highlight_move_cells = []
	highlight_attack_cells = []
	set_selected(Vector2i(-1, -1))
	queue_redraw()

func _cell_center(pos: Vector2i) -> Vector2:
	return Vector2(pos.x * CELL_SIZE + CELL_SIZE * 0.5, pos.y * CELL_SIZE + CELL_SIZE * 0.5)

func _draw() -> void:
	for row in 8:
		for col in 8:
			var rect := Rect2(col * CELL_SIZE, row * CELL_SIZE, CELL_SIZE, CELL_SIZE)
			draw_rect(rect, COLOR_LIGHT if (col + row) % 2 == 0 else COLOR_DARK)
	for pos in highlight_move_cells:
		draw_rect(Rect2(pos.x * CELL_SIZE, pos.y * CELL_SIZE, CELL_SIZE, CELL_SIZE), COLOR_MOVE_HIGHLIGHT)
	for pos in highlight_attack_cells:
		draw_rect(Rect2(pos.x * CELL_SIZE, pos.y * CELL_SIZE, CELL_SIZE, CELL_SIZE), COLOR_ATTACK_HIGHLIGHT)
	if selected_cell != Vector2i(-1, -1):
		draw_rect(Rect2(selected_cell.x * CELL_SIZE, selected_cell.y * CELL_SIZE, CELL_SIZE, CELL_SIZE), COLOR_SELECTED)

func _input(event: InputEvent) -> void:
	if GameManager.state == GameManager.State.GAME_OVER:
		return
	var tap_pos: Vector2 = Vector2.ZERO
	var got_tap := false
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		tap_pos = (event as InputEventScreenTouch).position
		got_tap = true
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			tap_pos = mb.position
			got_tap = true
	if not got_tap:
		return
	var local_pos := to_local(tap_pos)
	var col := int(local_pos.x / CELL_SIZE)
	var row := int(local_pos.y / CELL_SIZE)
	if col >= 0 and col < 8 and row >= 0 and row < 8:
		board_cell_tapped.emit(Vector2i(col, row))
```

**Step 3: Validate**

`validate_script("res://scripts/board/board.gd")` — expect valid.

**Step 4: Commit**

```bash
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz add scripts/board/board.gd
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz commit -m "feat: add placement visual methods to Board"
```

---

### Task 3: Update `hud.gd` — add placement UI

**Files:**
- Modify: `res://scripts/ui/hud.gd`

**Step 1: Read current script**

`read_script("res://scripts/ui/hud.gd")`

**Step 2: Apply changes with create_script**

Apply ALL of the following in one full rewrite:

**A. Add signal** (after existing signals):
```gdscript
signal placement_confirmed(player: int)
```

**B. Add state variables** (after `_cancel_discard_btn: Button` line):
```gdscript
var _placement_player: int = 0
var _placement_label: Label
var _placement_confirm_btn: Button
```

**C. In `_ready()`, after the `_cancel_discard_btn` block**, add:
```gdscript
	_placement_label = Label.new()
	_placement_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_placement_label.position = Vector2(324, 8)
	_placement_label.size = Vector2(504, 40)
	_placement_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placement_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_placement_label.visible = false
	add_child(_placement_label)
	_placement_confirm_btn = Button.new()
	_placement_confirm_btn.text = "Confirm Placement"
	_placement_confirm_btn.custom_minimum_size = Vector2(180, 60)
	_placement_confirm_btn.visible = false
	$BottomBar.add_child(_placement_confirm_btn)
```

**D. In `_ready()`, add connection** (at end of connections block):
```gdscript
	_placement_confirm_btn.pressed.connect(_on_placement_confirm_btn_pressed)
```

**E. Update `_set_all_action_buttons_hidden()`** — add two lines before `_pending_card_index = -1`:
```gdscript
func _set_all_action_buttons_hidden() -> void:
	done_btn.visible = false
	discard_pass_btn.visible = false
	confirm_btn.visible = false
	play_card_btn.visible = false
	_cancel_discard_btn.visible = false
	_placement_label.visible = false
	_placement_confirm_btn.visible = false
	_pending_card_index = -1
	_discard_mode = false
	_selected_discard.clear()
```

**F. Add placement UI methods** (before `_on_game_over`):
```gdscript
func show_placement_ui(player: int) -> void:
	_placement_player = player
	_set_all_action_buttons_hidden()
	turn_label.text = "Player %d" % player
	_placement_label.text = "Player %d — Place your pieces (0/8)" % player
	_placement_label.visible = true
	_placement_confirm_btn.visible = false

func update_placement_count(n: int) -> void:
	_placement_label.text = "Player %d — Place your pieces (%d/8)" % [_placement_player, n]
	_placement_confirm_btn.visible = (n == 8)

func hide_placement_ui() -> void:
	_placement_label.visible = false
	_placement_confirm_btn.visible = false

func _on_placement_confirm_btn_pressed() -> void:
	placement_confirmed.emit(_placement_player)
```

**Step 3: Validate**

`validate_script("res://scripts/ui/hud.gd")` — expect valid (autoload warnings OK).

**Step 4: Commit**

```bash
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz add scripts/ui/hud.gd
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz commit -m "feat: add placement UI to HUD"
```

---

### Task 4: Update `main.gd` — wire placement phase

**Files:**
- Modify: `res://scripts/game/main.gd`

**Step 1: Read current script**

`read_script("res://scripts/game/main.gd")`

**Step 2: Rewrite with create_script**

Full new content:

```gdscript
# res://scripts/game/main.gd
extends Node2D

@onready var board: Node2D = $Board
@onready var hud = $HUD

var _move_selected: Vector2i = Vector2i(-1, -1)
var _attack_selected: Vector2i = Vector2i(-1, -1)

func _ready() -> void:
	hud.card_played_by_ui.connect(_on_card_played_by_ui)
	hud.discard_pass_requested.connect(_on_discard_pass_requested)
	hud.movement_done_requested.connect(_on_movement_done)
	hud.defense_chosen.connect(_on_defense_chosen)
	hud.placement_confirmed.connect(_on_placement_confirmed)
	board.board_cell_tapped.connect(_on_board_cell_tapped)
	TurnManager.phase_changed.connect(_on_phase_changed)
	TurnManager.attack_resolved.connect(_on_attack_resolved)
	GameManager.placement_started.connect(_on_placement_started)
	GameManager.start_placement()

# --- Placement phase ---

func _on_placement_started(player: int) -> void:
	board.clear_highlights()
	board.highlight_placement_zone(GameManager.get_placement_zone(player))
	hud.show_placement_ui(player)

func _on_placement_confirmed(player: int) -> void:
	if player == 1:
		await _flip_board()
		board.clear_placement_pawns(1)
	elif player == 2:
		await _flip_board()
	GameManager.confirm_placement(player)

# --- Turn phase ---

func _on_phase_changed(phase: TurnManager.Phase) -> void:
	board.clear_highlights()
	_move_selected = Vector2i(-1, -1)
	_attack_selected = Vector2i(-1, -1)
	if phase == TurnManager.Phase.END:
		if GameManager.state != GameManager.State.GAME_OVER:
			_do_flip_then_next_turn()

func _flip_board() -> void:
	var tween := create_tween()
	tween.tween_property(self, "rotation_degrees", rotation_degrees + 180.0, 0.4)
	await tween.finished

func _do_flip_then_next_turn() -> void:
	hud.show_turn_overlay(2 if TurnManager.current_player == 1 else 1)
	await _flip_board()
	TurnManager.end_turn()

func _on_card_played_by_ui(player: int, card_index: int) -> void:
	if TurnManager.phase != TurnManager.Phase.PLAY_CARD:
		return
	if player != TurnManager.current_player:
		return
	var type := CardSystem.play_card(player, card_index)
	TurnManager.on_card_played(type)

func _on_discard_pass_requested(_player: int) -> void:
	TurnManager.on_discard_and_pass()

func _on_movement_done() -> void:
	TurnManager.on_movement_done()

func _on_board_cell_tapped(cell: Vector2i) -> void:
	match GameManager.state:
		GameManager.State.PLACEMENT_P1:
			_handle_placement_tap(cell, 1)
		GameManager.State.PLACEMENT_P2:
			_handle_placement_tap(cell, 2)
		GameManager.State.PLAYING:
			match TurnManager.phase:
				TurnManager.Phase.RESOLVE_MOVEMENT:
					_handle_movement_tap(cell)
				TurnManager.Phase.RESOLVE_ATTACK:
					_handle_attack_tap(cell)

func _handle_placement_tap(cell: Vector2i, player: int) -> void:
	var zone := GameManager.get_placement_zone(player)
	if cell not in zone:
		return
	var placement_dict := GameManager.placement_p1 if player == 1 else GameManager.placement_p2
	if placement_dict.has(cell):
		GameManager.remove_pawn_from_placement(player, cell)
	elif placement_dict.size() < 8:
		GameManager.place_pawn(player, cell)
	board.render_placement(placement_dict, player)
	hud.update_placement_count(placement_dict.size())

func _handle_movement_tap(cell: Vector2i) -> void:
	var team := TurnManager.current_player
	if _move_selected == Vector2i(-1, -1):
		if GameManager.get_team_at(cell) == team:
			_move_selected = cell
			board.set_selected(cell)
			board.highlight_moves(GameManager.get_valid_moves(cell))
	else:
		var moves := GameManager.get_valid_moves(_move_selected)
		if cell in moves and TurnManager.movement_points > 0:
			GameManager.move_pawn(_move_selected, cell)
			TurnManager.consume_movement_point()
			_move_selected = cell
			board.set_selected(cell)
			if TurnManager.movement_points > 0:
				board.highlight_moves(GameManager.get_valid_moves(cell))
			else:
				board.clear_highlights()
				TurnManager.on_movement_done()
		elif GameManager.get_team_at(cell) == team:
			_move_selected = cell
			board.set_selected(cell)
			board.highlight_moves(GameManager.get_valid_moves(cell))
		else:
			_move_selected = Vector2i(-1, -1)
			board.clear_highlights()

func _handle_attack_tap(cell: Vector2i) -> void:
	var team := TurnManager.current_player
	if _attack_selected == Vector2i(-1, -1):
		if GameManager.get_team_at(cell) == team:
			var targets := GameManager.get_valid_attack_targets(cell)
			if not targets.is_empty():
				_attack_selected = cell
				board.set_selected(cell)
				board.highlight_attack_targets(targets)
	else:
		var targets := GameManager.get_valid_attack_targets(_attack_selected)
		if cell in targets:
			var adjacent := GameManager.get_adjacent_allies(_attack_selected, team)
			TurnManager.on_attack_declared(_attack_selected, cell, adjacent)
			board.clear_highlights()
		else:
			_attack_selected = Vector2i(-1, -1)
			board.clear_highlights()

func _on_defense_chosen(played_defense: bool, card_index: int) -> void:
	var defender := 2 if TurnManager.current_player == 1 else 1
	var defender_adjacent := 0
	if played_defense and card_index >= 0:
		var defender_pos: Vector2i = TurnManager.pending_attack["defender_pos"]
		var hand := CardSystem.get_hand(defender)
		assert(card_index < hand.size() and hand[card_index] == CardType.Type.DEFENSE,
			"Defense card index %d is stale or invalid" % card_index)
		CardSystem.play_card(defender, card_index)
		defender_adjacent = GameManager.get_adjacent_allies(defender_pos, defender)
	TurnManager.on_defense_resolved(played_defense, defender_adjacent)

func _on_attack_resolved(defender_pos: Vector2i, pawn_survives: bool, _ar: int, _dr: int) -> void:
	if not pawn_survives:
		GameManager.remove_pawn_at(defender_pos)
```

Key changes from old `main.gd`:
- `GameManager.start_game()` → `GameManager.start_placement()`
- Added `hud.placement_confirmed.connect` and `GameManager.placement_started.connect`
- Added `_on_placement_started`, `_on_placement_confirmed` handlers
- Extracted `_flip_board()` helper (used by both placement and turn transitions)
- `_on_board_cell_tapped` now dispatches on `GameManager.state` first (placement states), then `TurnManager.phase` (playing state)
- Added `_handle_placement_tap`

**Step 3: Validate**

`validate_script("res://scripts/game/main.gd")` — expect valid.

**Step 4: Commit**

```bash
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz add scripts/game/main.gd
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz commit -m "feat: wire placement phase in main — tap handler, flip, signals"
```

---

### Task 5: Visual verification + push

**Step 1: Play scene**

`play_scene("res://scenes/main.tscn")`

**Step 2: Check output log**

`get_output_log` — zero ERROR lines expected.

**Step 3: Screenshot — P1 placement initial state**

`get_game_screenshot` — verify:
- Empty board (no pawns)
- Rows 5–7 (bottom 3 rows) highlighted yellow
- Label "Player 1 — Place your pieces (0/8)" visible at top of board area
- No "Confirm Placement" button visible
- No action buttons (Discard & Pass, Done, etc.)

**Step 4: Place P1 pawn via game script**

```gdscript
var main = get_tree().root.get_node("Main")
main._handle_placement_tap(Vector2i(0, 7), 1)
_mcp_print("p1 count: " + str(GameManager.placement_p1.size()))
```

Expected: `p1 count: 1`

**Step 5: Screenshot — P1 one pawn placed**

`get_game_screenshot` — verify:
- One blue pawn at bottom-left cell (col 0, row 7)
- Label shows "Player 1 — Place your pieces (1/8)"
- No confirm button yet

**Step 6: Remove pawn (tap same cell)**

```gdscript
var main = get_tree().root.get_node("Main")
main._handle_placement_tap(Vector2i(0, 7), 1)
_mcp_print("p1 count after remove: " + str(GameManager.placement_p1.size()))
```

Expected: `p1 count after remove: 0`

**Step 7: Place all 8 P1 pawns via game script**

```gdscript
var main = get_tree().root.get_node("Main")
for col in 8:
	main._handle_placement_tap(Vector2i(col, 7), 1)
_mcp_print("p1 final count: " + str(GameManager.placement_p1.size()))
```

Expected: `p1 final count: 8`

**Step 8: Screenshot — P1 confirm button visible**

`get_game_screenshot` — verify:
- 8 blue pawns on row 7
- "Confirm Placement" button visible
- Label shows "(8/8)"

**Step 9: Confirm P1 placement via HUD**

```gdscript
var hud = get_tree().root.get_node("Main/HUD")
hud._on_placement_confirm_btn_pressed()
```

Wait ~1 second for flip animation, then screenshot.

**Step 10: Screenshot — P2 placement state**

`get_game_screenshot` — verify:
- Board is flipped 180°
- No P1 pawns visible
- Rows 0–2 highlighted (appear at visual bottom after flip)
- Label "Player 2 — Place your pieces (0/8)"

**Step 11: Place all 8 P2 pawns and confirm**

```gdscript
var main = get_tree().root.get_node("Main")
for col in 8:
	main._handle_placement_tap(Vector2i(col, 0), 2)
var hud = get_tree().root.get_node("Main/HUD")
hud._on_placement_confirm_btn_pressed()
```

Wait ~1 second for flip animation.

**Step 12: Screenshot — game started, P1's turn**

`get_game_screenshot` — verify:
- Board back at 0° (P1's perspective)
- 8 blue pawns on row 7 (P1) and 8 red pawns on row 0 (P2)
- "Discard & Pass" button visible (normal PLAY_CARD state)
- No placement label visible

**Step 13: Check output log**

`get_output_log` — zero ERROR lines expected.

**Step 14: Stop scene**

`stop_scene()`

**Step 15: Push**

```bash
git -C /mnt/c/Users/jtguz/OneDrive/Documentos/GODOT/bataz push
```

---

## After implementation: Code review

After Task 5 is complete, use the `superpowers:requesting-code-review` skill to review the placement phase implementation across the 4 modified files.
