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
	board.clear_placement_zone()
	board.highlight_placement_zone(GameManager.get_placement_zone(player))
	hud.show_placement_ui(player)

func _on_placement_confirmed(player: int) -> void:
	if player == 1:
		await _flip_board()
		board.clear_placement_pawns(1)
	elif player == 2:
		board.clear_placement_zone()
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
