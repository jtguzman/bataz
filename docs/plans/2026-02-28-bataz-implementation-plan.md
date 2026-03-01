# Bataz — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a complete 2-player local hotseat card-driven strategy game in Godot 4.6 using only MCP tools.

**Architecture:** Three autoload singletons (GameManager, TurnManager, CardSystem) own all game state and emit signals. Visual scenes (Board, Pawn, HUD) are dumb — they subscribe to signals and render. Main scene orchestrates the interaction between HUD signals and autoload calls. No scene holds state that another system needs.

**Tech Stack:** Godot 4.6.1, GDScript (static typed), Godot MCP Pro v1.4.0, GL Compatibility renderer, 1152×648 viewport.

**MCP Note:** All Godot code lives in the Godot editor via MCP. Use `create_script`, `edit_script`, `create_scene`, `add_node`, `update_property`, `batch_set_property`, `save_scene`. Verify steps use `play_scene` / `get_game_screenshot` / `stop_scene`. Always call `save_scene` after modifying a scene. No git repo exists — docs are the only cross-session persistence.

**Layout constants (locked):**
- `CELL_SIZE = 63` px → board = `504×504` px
- Board position in Main: `x = 324`, `y = 48` (centers board below 48px top HUD bar)
- HUD: 48px top bar, 96px bottom bar → total 648px ✓

---

## Task 1: Project Settings

**Step 1: Set stretch mode via MCP**
Use `set_project_setting`:
- `display/window/stretch/mode` = `"canvas_items"`
- `display/window/stretch/aspect` = `"keep"`

**Step 2: Verify**
Use `get_project_settings` to confirm values saved.

---

## Task 2: Global Types — CardType & DiceRoller

**Files to create:**
- `res://scripts/global/card_type.gd`
- `res://scripts/global/dice_roller.gd`

**Step 1: Create CardType script**
```gdscript
# res://scripts/global/card_type.gd
class_name CardType

enum Type {
	MOVEMENT,
	ATTACK,
	DEFENSE
}
```

**Step 2: Create DiceRoller script**
```gdscript
# res://scripts/global/dice_roller.gd
class_name DiceRoller

static func roll(sides: int) -> int:
	return randi_range(1, sides)

static func get_die_sides(adjacent_allies: int) -> int:
	match adjacent_allies:
		0: return 4
		1: return 6
		2: return 8
		3: return 10
		4: return 12
		_: return 20
```

**Step 3: Verify**
Use `validate_script` on both files. Expect no errors.

---

## Task 3: CardSystem Autoload

**File to create:** `res://scripts/cards/card_system.gd`

**Step 1: Create script**
```gdscript
# res://scripts/cards/card_system.gd
extends Node

signal card_played(player: int, type: CardType.Type)
signal card_drawn(player: int, type: CardType.Type)
signal hand_changed(player: int, hand: Array)

var draw_pile: Array[CardType.Type] = []
var discard_pile: Array[CardType.Type] = []
var hand_p1: Array[CardType.Type] = []
var hand_p2: Array[CardType.Type] = []

func setup() -> void:
	_build_deck()
	draw_pile.shuffle()
	hand_p1.clear()
	hand_p2.clear()
	for i in 4:
		hand_p1.append(_draw_one())
	for i in 4:
		hand_p2.append(_draw_one())
	hand_changed.emit(1, hand_p1.duplicate())
	hand_changed.emit(2, hand_p2.duplicate())

func _build_deck() -> void:
	draw_pile.clear()
	discard_pile.clear()
	for i in 10:
		draw_pile.append(CardType.Type.MOVEMENT)
		draw_pile.append(CardType.Type.ATTACK)
		draw_pile.append(CardType.Type.DEFENSE)

func _ensure_drawable(count: int) -> void:
	if draw_pile.size() < count:
		draw_pile.append_array(discard_pile)
		discard_pile.clear()
		draw_pile.shuffle()

func _draw_one() -> CardType.Type:
	_ensure_drawable(1)
	if draw_pile.is_empty():
		push_error("[CardSystem] No cards left!")
		return CardType.Type.MOVEMENT
	return draw_pile.pop_front()

func play_card(player: int, index: int) -> CardType.Type:
	var hand := _get_hand(player)
	assert(index >= 0 and index < hand.size(), "Invalid card index %d" % index)
	var type: CardType.Type = hand[index]
	hand.remove_at(index)
	discard_pile.append(type)
	_set_hand(player, hand)
	card_played.emit(player, type)
	hand_changed.emit(player, hand.duplicate())
	return type

func draw_card(player: int) -> void:
	var type := _draw_one()
	var hand := _get_hand(player)
	hand.append(type)
	_set_hand(player, hand)
	card_drawn.emit(player, type)
	hand_changed.emit(player, hand.duplicate())

func discard_and_refill(player: int) -> void:
	var hand := _get_hand(player)
	for card in hand:
		discard_pile.append(card)
	hand.clear()
	_ensure_drawable(4)
	for i in 4:
		hand.append(_draw_one())
	_set_hand(player, hand)
	hand_changed.emit(player, hand.duplicate())

func get_hand(player: int) -> Array:
	return _get_hand(player).duplicate()

func _get_hand(player: int) -> Array[CardType.Type]:
	return hand_p1 if player == 1 else hand_p2

func _set_hand(player: int, hand: Array[CardType.Type]) -> void:
	if player == 1:
		hand_p1 = hand
	else:
		hand_p2 = hand
```

**Step 2: Register autoload**
Use `add_autoload`: name = `CardSystem`, path = `res://scripts/cards/card_system.gd`

**Step 3: Validate**
Use `validate_script`. Expect no errors.

---

## Task 4: TurnManager Autoload

**File to create:** `res://scripts/game/turn_manager.gd`

**Step 1: Create script**
```gdscript
# res://scripts/game/turn_manager.gd
extends Node

signal turn_started(player: int)
signal phase_changed(phase: Phase)
signal turn_ended(player: int)
signal defense_requested(attacker_pos: Vector2i, defender_pos: Vector2i, attack_roll: int, die_label: String)
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
	phase = Phase.DRAW
	phase_changed.emit(phase)
	CardSystem.draw_card(current_player)
	end_turn()

func on_attack_declared(attacker_pos: Vector2i, defender_pos: Vector2i, attacker_adjacent: int) -> void:
	var die_sides := DiceRoller.get_die_sides(attacker_adjacent)
	var roll := DiceRoller.roll(die_sides)
	pending_attack = {
		"attacker_pos": attacker_pos,
		"defender_pos": defender_pos,
		"attack_roll": roll,
		"die_sides": die_sides,
	}
	phase = Phase.RESOLVE_DEFENSE
	phase_changed.emit(phase)
	defense_requested.emit(attacker_pos, defender_pos, roll, "1d%d" % die_sides)

func on_defense_resolved(defender_played_card: bool, defender_adjacent: int) -> void:
	var attack_roll: int = pending_attack["attack_roll"]
	var defender_pos: Vector2i = pending_attack["defender_pos"]
	var def_roll := 0
	var pawn_survives := false

	if defender_played_card:
		var def_sides := DiceRoller.get_die_sides(defender_adjacent)
		def_roll = DiceRoller.roll(def_sides)
		pawn_survives = def_roll >= attack_roll
		# Both players draw
		CardSystem.draw_card(current_player)
		var other := 2 if current_player == 1 else 1
		CardSystem.draw_card(other)
	else:
		# Only attacker draws
		CardSystem.draw_card(current_player)

	attack_resolved.emit(defender_pos, pawn_survives, attack_roll, def_roll)
	pending_attack = {}
	phase = Phase.END
	phase_changed.emit(phase)

func on_discard_and_pass() -> void:
	CardSystem.discard_and_refill(current_player)
	phase = Phase.END
	phase_changed.emit(phase)

func end_turn() -> void:
	turn_ended.emit(current_player)
	current_player = 2 if current_player == 1 else 1
	_begin_turn()
```

**Step 2: Register autoload**
Use `add_autoload`: name = `TurnManager`, path = `res://scripts/game/turn_manager.gd`

**Step 3: Validate**
Use `validate_script`. Expect no errors.

---

## Task 5: GameManager Autoload

**File to create:** `res://scripts/game/game_manager.gd`

**Step 1: Create script**
```gdscript
# res://scripts/game/game_manager.gd
extends Node

signal game_started
signal game_over(winner: int)
signal pawn_removed(board_pos: Vector2i, team: int)
signal pawn_moved(from_pos: Vector2i, to_pos: Vector2i)

enum State { SETUP, PLAYING, GAME_OVER }

var state: State = State.SETUP
# board_state maps Vector2i -> team (int: 1 or 2)
var board_state: Dictionary = {}
var pawn_count: Array[int] = [0, 8, 8]

const P1_ROWS: Array[int] = [6, 7]
const P2_ROWS: Array[int] = [0, 1]

func start_game() -> void:
	state = State.PLAYING
	board_state.clear()
	pawn_count = [0, 8, 8]
	_place_pawns(1, P1_ROWS)
	_place_pawns(2, P2_ROWS)
	CardSystem.setup()
	TurnManager.start_game()
	game_started.emit()

func _place_pawns(team: int, rows: Array[int]) -> void:
	for row in rows:
		for col in 8:
			board_state[Vector2i(col, row)] = team

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

**Step 2: Register autoload**
Use `add_autoload`: name = `GameManager`, path = `res://scripts/game/game_manager.gd`

**Step 3: Validate**
Use `validate_script`. Expect no errors.

---

## Task 6: Pawn Scene

**Files:**
- Create: `res://scenes/pieces/pawn.tscn` (root Node2D)
- Create: `res://scripts/pieces/pawn.gd`

**Step 1: Create pawn script**
```gdscript
# res://scripts/pieces/pawn.gd
extends Node2D

var team: int = 1
var board_pos: Vector2i = Vector2i.ZERO
var pawn_color: Color = Color("#4A90D9")
var is_selected: bool = false

const RADIUS := 26.0

func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, pawn_color)
	if is_selected:
		draw_arc(Vector2.ZERO, RADIUS + 4.0, 0.0, TAU, 32, Color.WHITE, 3.0)

func select() -> void:
	is_selected = true
	queue_redraw()

func deselect() -> void:
	is_selected = false
	queue_redraw()
```

**Step 2: Create scene via MCP**
- `create_scene` path=`res://scenes/pieces/pawn.tscn` root_type=`Node2D` root_name=`Pawn`
- `attach_script` node_path=`.` script=`res://scripts/pieces/pawn.gd`
- `save_scene`

**Step 3: Validate script**
Use `validate_script`. Expect no errors.

---

## Task 7: Board Scene

**Files:**
- Create: `res://scenes/board/board.tscn` (root Node2D)
- Create: `res://scripts/board/board.gd`

**Step 1: Create board script**
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

# Visual pawn nodes: board_pos -> Node2D
var pawn_nodes: Dictionary = {}

var _pawn_scene: PackedScene

func _ready() -> void:
	_pawn_scene = load("res://scenes/pieces/pawn.tscn")
	GameManager.game_started.connect(_on_game_started)
	GameManager.pawn_removed.connect(_on_pawn_removed)
	GameManager.pawn_moved.connect(_on_pawn_moved)

func _on_game_started() -> void:
	# Clear old pawns
	for child in get_children():
		child.queue_free()
	pawn_nodes.clear()
	# Spawn for all positions in board_state
	for pos in GameManager.board_state:
		var team: int = GameManager.board_state[pos]
		_spawn_pawn(pos, team)

func _spawn_pawn(board_pos: Vector2i, team: int) -> void:
	var pawn: Node2D = _pawn_scene.instantiate()
	pawn.set_script(load("res://scripts/pieces/pawn.gd"))
	pawn.team = team
	pawn.board_pos = board_pos
	pawn.pawn_color = Color("#4A90D9") if team == 1 else Color("#E05252")
	pawn.position = _cell_center(board_pos)
	add_child(pawn)
	pawn_nodes[board_pos] = pawn

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
	# Deselect previous
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
	# Draw base grid
	for row in 8:
		for col in 8:
			var rect := Rect2(col * CELL_SIZE, row * CELL_SIZE, CELL_SIZE, CELL_SIZE)
			draw_rect(rect, COLOR_LIGHT if (col + row) % 2 == 0 else COLOR_DARK)
	# Move highlights
	for pos in highlight_move_cells:
		draw_rect(Rect2(pos.x * CELL_SIZE, pos.y * CELL_SIZE, CELL_SIZE, CELL_SIZE), COLOR_MOVE_HIGHLIGHT)
	# Attack highlights
	for pos in highlight_attack_cells:
		draw_rect(Rect2(pos.x * CELL_SIZE, pos.y * CELL_SIZE, CELL_SIZE, CELL_SIZE), COLOR_ATTACK_HIGHLIGHT)
	# Selected cell
	if selected_cell != Vector2i(-1, -1):
		draw_rect(Rect2(selected_cell.x * CELL_SIZE, selected_cell.y * CELL_SIZE, CELL_SIZE, CELL_SIZE), COLOR_SELECTED)

func _input(event: InputEvent) -> void:
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

**Step 2: Create scene via MCP**
- `create_scene` path=`res://scenes/board/board.tscn` root_type=`Node2D` root_name=`Board`
- `attach_script` node_path=`.` script=`res://scripts/board/board.gd`
- `save_scene`

**Step 3: Validate**
Use `validate_script`. Expect no errors.

---

## Task 8: Card UI Scene

**Files:**
- Create: `res://scenes/cards/card.tscn` (root Button)
- Create: `res://scripts/cards/card_ui.gd`

**Step 1: Create script**
```gdscript
# res://scripts/cards/card_ui.gd
extends Button

signal card_selected(index: int)

var card_index: int = 0
var card_type: CardType.Type = CardType.Type.MOVEMENT

const BG_COLORS := {
	CardType.Type.MOVEMENT: Color("#2E7D32"),
	CardType.Type.ATTACK:   Color("#B71C1C"),
	CardType.Type.DEFENSE:  Color("#1565C0"),
}
const LABELS := {
	CardType.Type.MOVEMENT: "MOV",
	CardType.Type.ATTACK:   "ATK",
	CardType.Type.DEFENSE:  "DEF",
}

func setup(index: int, type: CardType.Type, face_down: bool = false) -> void:
	card_index = index
	card_type = type
	if face_down:
		text = "?"
		self_modulate = Color(0.35, 0.35, 0.35)
		disabled = true
	else:
		text = LABELS[type]
		self_modulate = BG_COLORS[type]
		disabled = false

func _on_pressed() -> void:
	card_selected.emit(card_index)
```

**Step 2: Create scene via MCP**
- `create_scene` path=`res://scenes/cards/card.tscn` root_type=`Button` root_name=`Card`
- `update_property` node_path=`.` property=`custom_minimum_size` value=`Vector2(100, 80)`
- `attach_script` node_path=`.` script=`res://scripts/cards/card_ui.gd`
- Connect signal: `pressed` → `_on_pressed` (same node)
- `save_scene`

**Step 3: Validate**
Use `validate_script`. Expect no errors.

---

## Task 9: HUD Scene

**Files:**
- Create: `res://scenes/ui/hud.tscn` (root CanvasLayer)
- Create: `res://scripts/ui/hud.gd`

**Step 1: Create HUD script**
```gdscript
# res://scripts/ui/hud.gd
extends CanvasLayer

signal card_played_by_ui(player: int, card_index: int)
signal discard_pass_requested(player: int)
signal defense_chosen(played_defense: bool, card_index: int)
signal movement_done_requested
signal turn_end_confirmed

@onready var top_bar: HBoxContainer = $TopBar
@onready var bottom_bar: HBoxContainer = $BottomBar
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

func _ready() -> void:
	_card_scene = load("res://scenes/cards/card.tscn")
	TurnManager.turn_started.connect(_on_turn_started)
	TurnManager.phase_changed.connect(_on_phase_changed)
	TurnManager.defense_requested.connect(_on_defense_requested)
	TurnManager.movement_rolled.connect(_on_movement_rolled)
	TurnManager.attack_resolved.connect(_on_attack_resolved)
	CardSystem.hand_changed.connect(_on_hand_changed)
	GameManager.game_over.connect(_on_game_over)
	_set_all_action_buttons_hidden()
	dice_panel.visible = false
	defense_panel.visible = false
	turn_overlay.visible = false

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
			pass  # flip handled by Main

func _on_movement_rolled(points: int) -> void:
	_show_dice("1d4", points)

func _on_defense_requested(_ap: Vector2i, _dp: Vector2i, attack_roll: int, die_label: String) -> void:
	_show_dice(die_label, attack_roll)
	var defender := 2 if current_player == 1 else 1
	var hand := CardSystem.get_hand(defender)
	defense_title.text = "Player %d — Defend? (ATK=%d)" % [defender, attack_roll]
	# Rebuild defense hand showing only Defense cards
	for child in defense_hand.get_children():
		child.queue_free()
	var has_defense_card := false
	for i in hand.size():
		if hand[i] == CardType.Type.DEFENSE:
			var card: Button = _card_scene.instantiate()
			card.setup(i, hand[i])
			var idx := i  # capture
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
		msg = "ATK %d vs DEF %d — %s" % [attack_roll, defense_roll, "Blocked!" if pawn_survives else "Hit!"]
	else:
		msg = "ATK %d — Hit!" % attack_roll
	dice_label.text = msg
	dice_panel.visible = true
	get_tree().create_timer(2.0).timeout.connect(func(): dice_panel.visible = false)

func show_discard_preview() -> void:
	# Hand already updated via hand_changed; show confirm button
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
		var card: Button = _card_scene.instantiate()
		card.setup(i, hand[i], not is_active)
		if is_active:
			var idx := i  # capture for closure
			card.card_selected.connect(func(_x): card_played_by_ui.emit(player, idx))
		container.add_child(card)

func show_turn_overlay(player: int) -> void:
	turn_overlay_label.text = "Player %d's Turn" % player
	turn_overlay.visible = true
	get_tree().create_timer(0.8).timeout.connect(func(): turn_overlay.visible = false)

func _show_dice(die_label: String, result: int) -> void:
	dice_label.text = "%s → %d" % [die_label, result]
	dice_panel.visible = true
	get_tree().create_timer(1.5).timeout.connect(func(): dice_panel.visible = false)

func _set_all_action_buttons_hidden() -> void:
	done_btn.visible = false
	discard_pass_btn.visible = false
	confirm_btn.visible = false

# Button signal handlers wired in scene
func _on_done_btn_pressed() -> void:
	movement_done_requested.emit()

func _on_discard_pass_btn_pressed() -> void:
	discard_pass_requested.emit(current_player)

func _on_confirm_btn_pressed() -> void:
	turn_end_confirmed.emit()

func _on_game_over(winner: int) -> void:
	turn_label.text = "🏆 Player %d Wins!" % winner
	_set_all_action_buttons_hidden()
```

**Step 2: Build HUD scene node tree via MCP**

Create `res://scenes/ui/hud.tscn`, root `CanvasLayer` named `HUD`. Build this tree:

```
HUD (CanvasLayer)
├── TopBar (HBoxContainer)          anchor: top-wide, h=48, offset_top=0
│   ├── TurnLabel (Label)           size_flags_horizontal = EXPAND+FILL
│   └── TopHand (HBoxContainer)     size_flags_horizontal = EXPAND+FILL
├── BottomBar (HBoxContainer)       anchor: bottom-wide, h=96
│   ├── BottomHand (HBoxContainer)  size_flags_horizontal = EXPAND+FILL
│   ├── DoneBtn (Button)            text="Done", visible=false, min_size=(90,60)
│   ├── DiscardPassBtn (Button)     text="Discard & Pass", min_size=(130,60)
│   └── ConfirmBtn (Button)         text="Confirm", visible=false, min_size=(90,60)
├── DicePanel (PanelContainer)      anchor: center, visible=false
│   └── DiceLabel (Label)           text="1d4 → 3"
├── DefensePanel (PanelContainer)   anchor: center, visible=false
│   └── VBox (VBoxContainer)
│       ├── Title (Label)
│       ├── DefenseHand (HBoxContainer)
│       └── PassBtn (Button)        text="Pass (take the hit)"
└── TurnOverlay (PanelContainer)    anchor: center, visible=false
    └── Label                       text="Player 1's Turn"
```

Set anchors:
- `TopBar`: `anchor_left=0, anchor_right=1, anchor_top=0, anchor_bottom=0, offset_bottom=48`
- `BottomBar`: `anchor_left=0, anchor_right=1, anchor_top=1, anchor_bottom=1, offset_top=-96`
- `DicePanel`: `anchor_left=0.3, anchor_right=0.7, anchor_top=0.3, anchor_bottom=0.7`
- `DefensePanel`: `anchor_left=0.2, anchor_right=0.8, anchor_top=0.2, anchor_bottom=0.8`
- `TurnOverlay`: `anchor_left=0.25, anchor_right=0.75, anchor_top=0.4, anchor_bottom=0.6`

Attach script `res://scripts/ui/hud.gd`.

Wire button `pressed` signals to script methods:
- `DoneBtn.pressed` → `_on_done_btn_pressed`
- `DiscardPassBtn.pressed` → `_on_discard_pass_btn_pressed`
- `ConfirmBtn.pressed` → `_on_confirm_btn_pressed`
- `PassBtn.pressed` → `_on_defense_pass_btn_pressed`

`save_scene`

**Step 3: Validate**
Use `validate_script`. Expect no errors.

---

## Task 10: Main Scene

**Files:**
- Create: `res://scenes/main.tscn` (root Node2D)
- Create: `res://scripts/game/main.gd`

**Step 1: Create main script**
```gdscript
# res://scripts/game/main.gd
extends Node2D

@onready var board: Node2D = $Board
@onready var hud = $HUD

# Movement state
var _move_selected: Vector2i = Vector2i(-1, -1)

# Attack state
var _attack_selected: Vector2i = Vector2i(-1, -1)

func _ready() -> void:
	# HUD → game actions
	hud.card_played_by_ui.connect(_on_card_played_by_ui)
	hud.discard_pass_requested.connect(_on_discard_pass_requested)
	hud.movement_done_requested.connect(_on_movement_done)
	hud.defense_chosen.connect(_on_defense_chosen)
	hud.turn_end_confirmed.connect(_on_turn_end_confirmed)

	# Board input
	board.board_cell_tapped.connect(_on_board_cell_tapped)

	# Turn events
	TurnManager.turn_ended.connect(_on_turn_ended)
	TurnManager.attack_resolved.connect(_on_attack_resolved)
	TurnManager.phase_changed.connect(_on_phase_changed)

	# Start game
	GameManager.start_game()

func _on_phase_changed(_phase: TurnManager.Phase) -> void:
	board.clear_highlights()
	_move_selected = Vector2i(-1, -1)
	_attack_selected = Vector2i(-1, -1)

func _on_card_played_by_ui(player: int, card_index: int) -> void:
	if TurnManager.phase != TurnManager.Phase.PLAY_CARD:
		return
	if player != TurnManager.current_player:
		return
	var type := CardSystem.play_card(player, card_index)
	TurnManager.on_card_played(type)

func _on_discard_pass_requested(_player: int) -> void:
	TurnManager.on_discard_and_pass()
	hud.show_discard_preview()

func _on_turn_end_confirmed() -> void:
	TurnManager.end_turn()

func _on_movement_done() -> void:
	TurnManager.on_movement_done()

func _on_board_cell_tapped(cell: Vector2i) -> void:
	match TurnManager.phase:
		TurnManager.Phase.RESOLVE_MOVEMENT:
			_handle_movement_tap(cell)
		TurnManager.Phase.RESOLVE_ATTACK:
			_handle_attack_tap(cell)

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
			TurnManager.movement_points -= 1
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
		CardSystem.play_card(defender, card_index)
		defender_adjacent = GameManager.get_adjacent_allies(defender_pos, defender)
	TurnManager.on_defense_resolved(played_defense, defender_adjacent)

func _on_attack_resolved(defender_pos: Vector2i, pawn_survives: bool, _ar: int, _dr: int) -> void:
	if not pawn_survives:
		GameManager.remove_pawn_at(defender_pos)

func _on_turn_ended(player: int) -> void:
	if GameManager.state == GameManager.State.GAME_OVER:
		return
	hud.show_turn_overlay(2 if player == 1 else 1)
	var tween := create_tween()
	tween.tween_property(self, "rotation_degrees", rotation_degrees + 180.0, 0.4)
	await tween.finished
	TurnManager.end_turn()
```

Wait — `end_turn` is called inside `on_movement_done` already. Let me correct the flow:

**Corrected flow note:** `TurnManager.on_movement_done()` internally calls `end_turn()`. Same with `on_defense_resolved()` which sets phase to END. `end_turn()` itself emits `turn_ended` which triggers the flip. The flip awaits and then should NOT call `end_turn()` again.

**Corrected main script — replace `_on_turn_ended` and `_on_movement_done`:**

```gdscript
# In main.gd — corrected signal flow:
# TurnManager.turn_ended is NOT connected in Main.
# Instead, TurnManager.phase_changed handles END phase → Main triggers flip → then calls TurnManager.end_turn()

func _on_phase_changed(phase: TurnManager.Phase) -> void:
	board.clear_highlights()
	_move_selected = Vector2i(-1, -1)
	_attack_selected = Vector2i(-1, -1)
	if phase == TurnManager.Phase.END:
		if GameManager.state != GameManager.State.GAME_OVER:
			_do_flip_then_next_turn()

func _do_flip_then_next_turn() -> void:
	hud.show_turn_overlay(2 if TurnManager.current_player == 1 else 1)
	var tween := create_tween()
	tween.tween_property(self, "rotation_degrees", rotation_degrees + 180.0, 0.4)
	await tween.finished
	TurnManager.end_turn()

func _on_movement_done() -> void:
	TurnManager.on_movement_done()
	# on_movement_done sets phase to END internally → _on_phase_changed fires → flip happens
```

**Step 2: Create scene via MCP**
- `create_scene` path=`res://scenes/main.tscn` root_type=`Node2D` root_name=`Main`
- `add_scene_instance` scene_path=`res://scenes/board/board.tscn` name=`Board`
- `update_property` node=`Board` property=`position` value=`Vector2(324, 48)`
- `add_scene_instance` scene_path=`res://scenes/ui/hud.tscn` name=`HUD`
- `attach_script` node_path=`.` script=`res://scripts/game/main.gd`
- `save_scene`

**Step 3: Set main scene**
Use `set_project_setting`: `application/run/main_scene` = `"res://scenes/main.tscn"`

**Step 4: Fix TurnManager — remove internal end_turn call from on_movement_done**

`on_movement_done` should only set phase to END and draw the card — NOT call `end_turn()`. `end_turn()` is called by Main after the flip animation.

Updated `on_movement_done` in TurnManager:
```gdscript
func on_movement_done() -> void:
	movement_points = 0
	CardSystem.draw_card(current_player)
	phase = Phase.END
	phase_changed.emit(phase)
	# end_turn() is called by Main after flip animation
```

Similarly, `on_defense_resolved` already sets `phase = Phase.END` — it should NOT call `end_turn()`. Main handles it via `_on_phase_changed`.

**Step 5: Validate all scripts**
Use `validate_script` on:
- `res://scripts/game/main.gd`
- `res://scripts/game/turn_manager.gd`

Fix any errors before proceeding.

---

## Task 11: First Run Verification

**Step 1: Play scene**
Use `play_scene` mode=`"main"`

**Step 2: Screenshot — initial state**
Use `get_game_screenshot`
Expected: 8×8 board with blue pawns on bottom 2 rows, red on top 2 rows. Both hands of 4 cards visible (bottom = P1, top = P2 face-down). "Player 1" in turn label.

**Step 3: Screenshot — after movement card**
Use `execute_game_script` to simulate:
1. Tap P1's first Movement card
2. Tap a P1 pawn
3. Tap a valid adjacent cell
Use `get_game_screenshot` — pawn should have moved, movement points shown.

**Step 4: Stop**
Use `stop_scene`

**Step 5: Update docs**
- Update `docs/scenes.md` with all scenes created
- Update `docs/architecture.md` with the autoload system map
- Update `docs/progress.md` — mark Milestones 1–6 tasks complete as applicable
- Append ADRs to `docs/decisions.md` for any non-obvious choices made during implementation

---

## Post-Implementation Checklist

- [ ] All 5 scripts validate with no errors
- [ ] Board renders 8×8 grid with correct colors
- [ ] Pawns placed correctly (P1 rows 6-7, P2 rows 0-1)
- [ ] Both hands show 4 cards each
- [ ] Movement card: dice rolls, pawn moves, points decrement
- [ ] Attack card: attacker selected, targets highlight, attack die rolls
- [ ] Defense panel appears for defender
- [ ] Pawn removed on successful attack
- [ ] Discard & Pass: hand refills, preview shown, confirm ends turn
- [ ] Screen flips 180° between turns
- [ ] HUD shows correct active player after flip
- [ ] Win condition triggers game over message
