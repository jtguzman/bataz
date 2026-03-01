# res://scripts/game/game_manager.gd
extends Node

signal game_started
signal game_over(winner: int)
signal pawn_removed(board_pos: Vector2i, team: int)
signal pawn_moved(from_pos: Vector2i, to_pos: Vector2i)

enum State { SETUP, PLAYING, GAME_OVER }

var state: State = State.SETUP
var board_state: Dictionary = {}
var pawn_count: Array[int] = [0, 8, 8]

const P1_ROWS: Array[int] = [7]
const P2_ROWS: Array[int] = [0]

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
