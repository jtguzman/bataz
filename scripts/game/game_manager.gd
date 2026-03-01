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
	var rows: Array[int]
	if player == 1:
		rows = [5, 6, 7]
	else:
		rows = [0, 1, 2]
	for row in rows:
		for col in 8:
			cells.append(Vector2i(col, row))
	return cells

func place_pawn(player: int, pos: Vector2i) -> void:
	var dict := placement_p1 if player == 1 else placement_p2
	if dict.size() >= 8 and not dict.has(pos):
		push_warning("[GameManager] place_pawn: player %d already has 8 pawns placed" % player)
		return
	var zone := get_placement_zone(player)
	if pos not in zone:
		push_warning("[GameManager] place_pawn: pos %s outside zone for player %d" % [str(pos), player])
		return
	dict[pos] = player

func remove_pawn_from_placement(player: int, pos: Vector2i) -> void:
	if player == 1:
		placement_p1.erase(pos)
	else:
		placement_p2.erase(pos)

func confirm_placement(player: int) -> void:
	var expected_state := State.PLACEMENT_P1 if player == 1 else State.PLACEMENT_P2
	if state != expected_state:
		push_error("[GameManager] confirm_placement: called for player %d in wrong state" % player)
		return
	var dict := placement_p1 if player == 1 else placement_p2
	if dict.size() != 8:
		push_error("[GameManager] confirm_placement: player %d has %d pawns, expected 8" % [player, dict.size()])
		return
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
	pawn_count = [0, placement_p1.size(), placement_p2.size()]
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
