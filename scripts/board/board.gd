# res://scripts/board/board.gd
extends Node2D

signal board_cell_tapped(cell: Vector2i)

const CELL_SIZE := 81
const COLOR_LIGHT := Color("#F0D9B5")
const COLOR_DARK  := Color("#B58863")
const COLOR_MOVE_HIGHLIGHT  := Color(1.0, 1.0, 0.0, 0.35)
const COLOR_ATTACK_HIGHLIGHT := Color(1.0, 0.2, 0.2, 0.45)
const COLOR_SELECTED := Color(1.0, 1.0, 1.0, 0.35)
const COLOR_PLACEMENT_ZONE := Color(1.0, 1.0, 0.0, 0.25)

var highlight_move_cells: Array[Vector2i] = []
var highlight_attack_cells: Array[Vector2i] = []
var selected_cell: Vector2i = Vector2i(-1, -1)
var highlight_placement_cells: Array[Vector2i] = []

var pawn_nodes: Dictionary = {}
var dying_count: int = 0

var _pawn_scene: PackedScene
var _board_texture: Texture2D

func _ready() -> void:
	_pawn_scene = load("res://scenes/pieces/pawn.tscn")
	_board_texture = load("res://assets/sprites/board/capiboard.png")
	GameManager.game_started.connect(_on_game_started)
	GameManager.pawn_removed.connect(_on_pawn_removed)
	GameManager.pawn_moved.connect(_on_pawn_moved)

func _on_game_started() -> void:
	highlight_move_cells = []
	highlight_attack_cells = []
	highlight_placement_cells = []
	selected_cell = Vector2i(-1, -1)
	dying_count = 0
	for pawn in pawn_nodes.values():
		pawn.queue_free()
	pawn_nodes.clear()
	for child in get_children():
		child.queue_free()
	for pos in GameManager.board_state:
		var team: int = GameManager.board_state[pos]
		_spawn_pawn(pos, team)
	queue_redraw()

func _spawn_pawn(board_pos: Vector2i, team: int) -> void:
	var pawn: Node2D = _pawn_scene.instantiate()
	pawn.team = team
	pawn.board_pos = board_pos
	pawn.pawn_color = Color("#4A90D9") if team == 1 else Color("#E05252")
	pawn.position = get_cell_center(board_pos)
	add_child(pawn)
	pawn_nodes[board_pos] = pawn

func get_cell_center(pos: Vector2i) -> Vector2:
	return Vector2(pos.x * CELL_SIZE + CELL_SIZE * 0.5, pos.y * CELL_SIZE + CELL_SIZE * 0.5)

# --- Placement phase methods ---

func highlight_placement_zone(cells: Array[Vector2i]) -> void:
	highlight_placement_cells = cells
	queue_redraw()

func clear_placement_zone() -> void:
	highlight_placement_cells = []
	queue_redraw()

func render_placement(placement_dict: Dictionary, team: int) -> void:
	assert(team == 1 or team == 2, "render_placement: team must be 1 or 2, got %d" % team)
	var to_remove: Array[Vector2i] = []
	for pos in pawn_nodes:
		if pawn_nodes[pos].team == team and not placement_dict.has(pos):
			to_remove.append(pos)
	for pos in to_remove:
		pawn_nodes[pos].queue_free()
		pawn_nodes.erase(pos)
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
		var pawn: Node2D = pawn_nodes[board_pos]
		pawn_nodes.erase(board_pos)
		dying_count += 1
		pawn.tree_exiting.connect(func(): dying_count -= 1)
		pawn.play_death_anim()
	queue_redraw()

func _on_pawn_moved(from_pos: Vector2i, to_pos: Vector2i) -> void:
	if pawn_nodes.has(from_pos):
		var pawn: Node2D = pawn_nodes[from_pos]
		pawn.board_pos = to_pos
		pawn.move_to(get_cell_center(to_pos))
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

func _draw() -> void:
	for row in 6:
		for col in 6:
			var rect := Rect2(col * CELL_SIZE, row * CELL_SIZE, CELL_SIZE, CELL_SIZE)
			draw_rect(rect, COLOR_LIGHT if (col + row) % 2 == 0 else COLOR_DARK)
	# Capiboard image overlay — full 1024×1024 including decorative border
	# Grid occupies 770×770 in source (126px frame on each side)
	# Scale grid to 504px (CELL_SIZE*6); border maps to 126*(504/770) ≈ 82px in screen space
	if _board_texture:
		var border := 126.0 * (CELL_SIZE * 6.0) / 770.0
		var total := CELL_SIZE * 6.0 + border * 2.0
		draw_texture_rect_region(
			_board_texture,
			Rect2(-border, -border, total, total),
			Rect2(0.0, 0.0, 1024.0, 1024.0)
		)
	for pos in highlight_move_cells:
		draw_rect(Rect2(pos.x * CELL_SIZE, pos.y * CELL_SIZE, CELL_SIZE, CELL_SIZE), COLOR_MOVE_HIGHLIGHT)
	for pos in highlight_attack_cells:
		draw_rect(Rect2(pos.x * CELL_SIZE, pos.y * CELL_SIZE, CELL_SIZE, CELL_SIZE), COLOR_ATTACK_HIGHLIGHT)
	for pos in highlight_placement_cells:
		draw_rect(Rect2(pos.x * CELL_SIZE, pos.y * CELL_SIZE, CELL_SIZE, CELL_SIZE), COLOR_PLACEMENT_ZONE)
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
	if col >= 0 and col < 6 and row >= 0 and row < 6:
		board_cell_tapped.emit(Vector2i(col, row))
