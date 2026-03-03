# res://scripts/network/network_manager.gd
# NetworkManager — GDScript bridge between SpacetimeDB (via GodotJS) and local autoloads.
# Register as autoload: NetworkManager
extends Node

# ── Public state ────────────────────────────────────────────────────────────

var is_online: bool = false
var my_player_slot: int = 0   # 1 or 2, set after game_joined
var game_id: int = -1

# ── Private ──────────────────────────────────────────────────────────────────

var _client: Node  # SpacetimeClient GodotJS instance

# ── Signals (forwarded to UI / lobby) ────────────────────────────────────────

signal connected
signal game_created(game_id: int, join_code: String)
signal game_joined(game_id: int)
signal join_failed(reason: String)
signal event_logged(text: String)

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Do not auto-connect; LobbyManager calls connect_online() after scene is ready
	pass

# ── Public API ───────────────────────────────────────────────────────────────

func connect_online() -> void:
	is_online = true
	# Use load() instead of preload() — scene may not be imported at parse time
	var scene: PackedScene = load("res://scenes/network/spacetime_client.tscn")
	_client = scene.instantiate()
	add_child(_client)

	# Lifecycle
	_client.connected.connect(_on_connected)
	_client.disconnected.connect(_on_disconnected)

	# Lobby
	_client.game_created.connect(_on_game_created)
	_client.game_joined.connect(_on_game_joined)
	_client.join_failed.connect(_on_join_failed)

	# Placement
	_client.placement_phase_started.connect(_on_placement_phase_started)

	# Gameplay
	_client.game_state_updated.connect(_on_game_state_updated)
	_client.board_sync.connect(_on_board_sync)
	_client.pawn_moved.connect(_on_pawn_moved)
	_client.pawn_removed.connect(_on_pawn_removed)
	_client.hand_updated.connect(_on_hand_updated)
	_client.attack_declared.connect(_on_attack_declared)
	_client.movement_rolled.connect(_on_movement_rolled)
	_client.game_over.connect(_on_game_over)
	_client.event_logged.connect(_on_event_logged)

	_client.connect_to_server()

# ── Outgoing action methods (called by main.gd when is_online) ──────────────

func place_pawn(col: int, row: int) -> void:
	_client.place_pawn(game_id, col, row)

func remove_placement_pawn(col: int, row: int) -> void:
	_client.remove_placement_pawn(game_id, col, row)

func confirm_placement() -> void:
	_client.confirm_placement(game_id)

func play_card(slot_index: int) -> void:
	_client.play_card(game_id, slot_index)

func discard_and_pass() -> void:
	_client.discard_and_pass(game_id)

func move_pawn(from: Vector2i, to: Vector2i) -> void:
	_client.move_pawn(game_id, from.x, from.y, to.x, to.y)

func done_moving() -> void:
	_client.done_moving(game_id)

func declare_attack(attacker: Vector2i, defender: Vector2i) -> void:
	_client.declare_attack(game_id, attacker.x, attacker.y, defender.x, defender.y)

func play_defense(slot_index: int) -> void:
	_client.play_defense(game_id, slot_index)

func pass_defense() -> void:
	_client.pass_defense(game_id)

func end_turn() -> void:
	_client.end_turn(game_id)

# ── Incoming: server → local state ──────────────────────────────────────────

func _on_connected() -> void:
	connected.emit()

func _on_disconnected() -> void:
	pass  # TODO: show reconnect UI

func _on_game_created(gid: int, join_code: String) -> void:
	game_id = gid
	game_created.emit(gid, join_code)

func _on_game_joined(gid: int) -> void:
	game_id = gid
	my_player_slot = _client.get_my_player_slot()
	game_joined.emit(gid)

func _on_join_failed(reason: String) -> void:
	join_failed.emit(reason)

func _on_placement_phase_started(player: int) -> void:
	# Re-use GameManager.placement_started so board.gd / main.gd react normally
	GameManager.state = _state_str_to_enum("PLACEMENT_P%d" % player)
	GameManager.placement_started.emit(player)

func _on_game_state_updated(data: Dictionary) -> void:
	TurnManager.current_player = data["current_player"]
	TurnManager.movement_points = data["movement_points"]
	TurnManager.phase = _str_to_phase(data["phase"])
	TurnManager.phase_changed.emit(TurnManager.phase)

	var state_str: String = data["state"]
	GameManager.state = _state_str_to_enum(state_str)

func _on_board_sync(pawns: Array) -> void:
	GameManager.board_state.clear()
	for p in pawns:
		GameManager.board_state[Vector2i(p["col"], p["row"])] = p["team"]
	GameManager.pawn_count[1] = pawns.filter(func(p): return p["team"] == 1).size()
	GameManager.pawn_count[2] = pawns.filter(func(p): return p["team"] == 2).size()
	GameManager.game_started.emit()

func _on_pawn_moved(fc: int, fr: int, tc: int, tr: int) -> void:
	var from := Vector2i(fc, fr)
	var to   := Vector2i(tc, tr)
	if not GameManager.board_state.has(from):
		return
	var team: int = GameManager.board_state[from]
	GameManager.board_state.erase(from)
	GameManager.board_state[to] = team
	GameManager.pawn_moved.emit(from, to)

func _on_pawn_removed(col: int, row: int, team: int) -> void:
	GameManager.board_state.erase(Vector2i(col, row))
	if team >= 1 and team <= 2:
		GameManager.pawn_count[team] -= 1
	GameManager.pawn_removed.emit(Vector2i(col, row), team)

func _on_hand_updated(player: int, hand: Array) -> void:
	var types := _strings_to_card_types(hand)
	if player == 1:
		CardSystem.hand_p1 = types
	else:
		CardSystem.hand_p2 = types
	CardSystem.hand_changed.emit(player, types)

func _on_attack_declared(data: Dictionary) -> void:
	TurnManager.pending_attack = {
		"attacker_pos": Vector2i(data["attacker_col"], data["attacker_row"]),
		"defender_pos": Vector2i(data["defender_col"], data["defender_row"]),
		"die_sides":    data["die_sides"],
	}
	TurnManager.defense_requested.emit(
		Vector2i(data["attacker_col"], data["attacker_row"]),
		Vector2i(data["defender_col"], data["defender_row"]),
		data["die_sides"]
	)

func _on_movement_rolled(points: int) -> void:
	TurnManager.movement_points = points
	TurnManager.movement_rolled.emit(points)

func _on_game_over(winner: int) -> void:
	GameManager.state = GameManager.State.GAME_OVER
	if winner == 2:
		GameManager.pawn_count[1] = 0
	else:
		GameManager.pawn_count[2] = 0
	GameManager.game_over.emit(winner)

func _on_event_logged(text: String) -> void:
	event_logged.emit(text)

# ── Helpers ───────────────────────────────────────────────────────────────────

func _str_to_phase(s: String) -> TurnManager.Phase:
	match s:
		"PLAY_CARD":        return TurnManager.Phase.PLAY_CARD
		"RESOLVE_MOVEMENT": return TurnManager.Phase.RESOLVE_MOVEMENT
		"RESOLVE_ATTACK":   return TurnManager.Phase.RESOLVE_ATTACK
		"RESOLVE_DEFENSE":  return TurnManager.Phase.RESOLVE_DEFENSE
		"END":              return TurnManager.Phase.END
		_:                  return TurnManager.Phase.PLAY_CARD

func _state_str_to_enum(s: String) -> GameManager.State:
	match s:
		"PLACEMENT_P1": return GameManager.State.PLACEMENT_P1
		"PLACEMENT_P2": return GameManager.State.PLACEMENT_P2
		"PLAYING":      return GameManager.State.PLAYING
		"GAME_OVER":    return GameManager.State.GAME_OVER
		_:              return GameManager.State.SETUP

func _strings_to_card_types(strings: Array) -> Array:
	var result: Array = []
	for s in strings:
		match s:
			"MOVEMENT": result.append(CardType.Type.MOVEMENT)
			"ATTACK":   result.append(CardType.Type.ATTACK)
			"DEFENSE":  result.append(CardType.Type.DEFENSE)
	return result
