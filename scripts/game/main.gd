# res://scripts/game/main.gd
extends Node2D

@onready var board: Node2D = $Board
@onready var hud = $HUD

var _move_selected: Vector2i = Vector2i(-1, -1)
var _attack_selected: Vector2i = Vector2i(-1, -1)
var _is_transitioning: bool = false
var _pending_attack_card_index: int = -1
var _pending_attacker_pos: Vector2i = Vector2i(-1, -1)
var _active_attacker_pos: Vector2i = Vector2i(-1, -1)

# ── Music ──────────────────────────────────────────────────────────────────

const GAME_TRACKS: Array = [
	"res://assets/audio/bataz-game-01.ogg",
	"res://assets/audio/bataz-game-02.ogg",
	"res://assets/audio/bataz-game-03.mp3",
	"res://assets/audio/bataz-game-04.mp3",
]
const WIN_TRACK := "res://assets/audio/bataz-win.ogg"

var _music: AudioStreamPlayer
var _last_track_idx: int = -1

func _start_game_music() -> void:
	_music = AudioStreamPlayer.new()
	_music.volume_db = -6.0
	add_child(_music)
	_music.finished.connect(_on_track_finished)
	_play_random_track()

func _play_random_track() -> void:
	var idx := _last_track_idx
	while idx == _last_track_idx:
		idx = randi() % GAME_TRACKS.size()
	_last_track_idx = idx
	_music.stream = load(GAME_TRACKS[idx])
	_music.play()

func _on_track_finished() -> void:
	if GameManager.state != GameManager.State.GAME_OVER:
		_play_random_track()

func _stop_music_for_win() -> void:
	if not is_instance_valid(_music):
		return
	_music.stop()
	_music.stream = load(WIN_TRACK)
	_music.play()

# ── Lifecycle ──────────────────────────────────────────────────────────────

func _ready() -> void:
	hud.card_played_by_ui.connect(_on_card_played_by_ui)
	hud.discard_pass_requested.connect(_on_discard_pass_requested)
	hud.movement_done_requested.connect(_on_movement_done)
	hud.defense_chosen.connect(_on_defense_chosen)
	hud.placement_confirmed.connect(_on_placement_confirmed)
	hud.attack_card_pending.connect(_on_attack_card_pending)
	hud.attack_card_cancelled.connect(_on_attack_card_cancelled)
	board.board_cell_tapped.connect(_on_board_cell_tapped)
	TurnManager.phase_changed.connect(_on_phase_changed)
	TurnManager.attack_resolved.connect(_on_attack_resolved)
	GameManager.placement_started.connect(_on_placement_started)
	GameManager.game_over.connect(_on_game_over_music)
	_start_game_music()

	if NetworkManager.is_online:
		pass
	else:
		GameManager.start_placement()

func _on_game_over_music(_winner: int) -> void:
	_stop_music_for_win()

# --- Placement phase ---

func _on_placement_started(player: int) -> void:
	if NetworkManager.is_online and NetworkManager.my_player_slot != player:
		return
	board.clear_highlights()
	board.clear_placement_zone()
	board.highlight_placement_zone(GameManager.get_placement_zone(player))
	hud.show_placement_ui(player)

func _on_placement_confirmed(player: int) -> void:
	_is_transitioning = true
	hud.hide_placement_ui()
	if NetworkManager.is_online:
		board.clear_placement_zone()
		NetworkManager.confirm_placement()
		_is_transitioning = false
		return
	if player == 1:
		board.clear_placement_pawns(1)
		await _flip_board()
	elif player == 2:
		board.clear_placement_zone()
		await _flip_board()
	GameManager.confirm_placement(player)
	_is_transitioning = false

func _on_attack_card_pending(player: int, card_index: int) -> void:
	assert(player == TurnManager.current_player, \
		"[Main] attack_card_pending from wrong player %d" % player)
	if player != TurnManager.current_player:
		return
	_pending_attack_card_index = card_index
	_pending_attacker_pos = Vector2i(-1, -1)
	board.clear_highlights()

func _on_attack_card_cancelled() -> void:
	_pending_attack_card_index = -1
	_pending_attacker_pos = Vector2i(-1, -1)
	board.clear_highlights()

# --- Turn phase ---

func _on_phase_changed(phase: TurnManager.Phase) -> void:
	board.clear_highlights()
	_move_selected = Vector2i(-1, -1)
	_attack_selected = Vector2i(-1, -1)
	_pending_attack_card_index = -1
	_pending_attacker_pos = Vector2i(-1, -1)
	if phase == TurnManager.Phase.END:
		if GameManager.state != GameManager.State.GAME_OVER:
			_do_flip_then_next_turn()

func _wait_for_pawn_animations() -> void:
	# Poll until all live pawns and dying pawns finish animating (max ~1.5s safety cap)
	var safety := 90
	while safety > 0:
		var any_busy := false
		for pawn in board.pawn_nodes.values():
			if pawn.is_animating:
				any_busy = true
				break
		if not any_busy and board.dying_count == 0:
			break
		await get_tree().process_frame
		safety -= 1
	# One extra frame so all queue_free() calls from death anims are processed
	await get_tree().process_frame

func _flip_board() -> void:
	# Step 1: scale down
	var t1 := create_tween()
	t1.tween_property(self, "scale", Vector2(0.85, 0.85), 0.15)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await t1.finished
	await get_tree().create_timer(0.08).timeout

	# Step 2: rotate board + counter-rotate all pawns in parallel so they stay upright
	var target_rot := rotation_degrees + 180.0
	var t2 := create_tween().set_parallel(true)
	t2.tween_property(self, "rotation_degrees", target_rot, 0.4)
	for pawn in board.pawn_nodes.values():
		t2.tween_property(pawn, "rotation_degrees", pawn.rotation_degrees - 180.0, 0.4)
	await t2.finished

	# Step 3: scale back up
	var t3 := create_tween()
	t3.tween_property(self, "scale", Vector2(1.0, 1.0), 0.15)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await t3.finished

func _do_flip_then_next_turn() -> void:
	if NetworkManager.is_online:
		if NetworkManager.my_player_slot == TurnManager.current_player:
			NetworkManager.end_turn()
		return
	await _wait_for_pawn_animations()
	hud.show_turn_overlay(2 if TurnManager.current_player == 1 else 1)
	await _flip_board()
	TurnManager.end_turn()

func _on_card_played_by_ui(player: int, card_index: int) -> void:
	if TurnManager.phase != TurnManager.Phase.PLAY_CARD:
		return
	if player != TurnManager.current_player:
		return
	if NetworkManager.is_online:
		NetworkManager.play_card(card_index)
		return
	var type := CardSystem.play_card(player, card_index)
	TurnManager.on_card_played(type)

func _on_discard_pass_requested(_player: int) -> void:
	if NetworkManager.is_online:
		NetworkManager.discard_and_pass()
		return
	TurnManager.on_discard_and_pass()

func _on_movement_done() -> void:
	if NetworkManager.is_online:
		NetworkManager.done_moving()
		return
	TurnManager.on_movement_done()

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
				TurnManager.Phase.RESOLVE_DEFENSE:
					pass

func _handle_placement_tap(cell: Vector2i, player: int) -> void:
	if _is_transitioning:
		return
	if NetworkManager.is_online:
		if NetworkManager.my_player_slot != player:
			return
		var zone := GameManager.get_placement_zone(player)
		if cell not in zone:
			return
		var placement_dict := GameManager.placement_p1 if player == 1 else GameManager.placement_p2
		if placement_dict.has(cell):
			NetworkManager.remove_placement_pawn(cell.x, cell.y)
			placement_dict.erase(cell)
		elif placement_dict.size() < 6:
			NetworkManager.place_pawn(cell.x, cell.y)
			placement_dict[cell] = player
		board.render_placement(placement_dict, player)
		hud.update_placement_count(placement_dict.size())
		return
	var zone := GameManager.get_placement_zone(player)
	if cell not in zone:
		return
	var placement_dict := GameManager.placement_p1 if player == 1 else GameManager.placement_p2
	if placement_dict.has(cell):
		GameManager.remove_pawn_from_placement(player, cell)
	elif placement_dict.size() < 6:
		GameManager.place_pawn(player, cell)
	board.render_placement(placement_dict, player)
	hud.update_placement_count(placement_dict.size())

func _handle_attack_card_tap(cell: Vector2i) -> void:
	if NetworkManager.is_online and NetworkManager.my_player_slot != TurnManager.current_player:
		return
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

	if NetworkManager.is_online:
		NetworkManager.play_card(card_index)
		NetworkManager.declare_attack(attacker, enemy_cell)
		return

	CardSystem.play_card(player, card_index)
	TurnManager.on_card_played(CardType.Type.ATTACK)
	var adjacent := GameManager.get_adjacent_allies(attacker, player)
	if board.pawn_nodes.has(attacker):
		board.pawn_nodes[attacker].play_attack_anim(board.get_cell_center(enemy_cell))
	_active_attacker_pos = attacker
	TurnManager.on_attack_declared(attacker, enemy_cell, adjacent)

func _handle_movement_tap(cell: Vector2i) -> void:
	if NetworkManager.is_online and NetworkManager.my_player_slot != TurnManager.current_player:
		return
	var team := TurnManager.current_player
	if _move_selected == Vector2i(-1, -1):
		if GameManager.get_team_at(cell) == team:
			_move_selected = cell
			board.set_selected(cell)
			board.highlight_moves(GameManager.get_valid_moves(cell))
	else:
		var moves := GameManager.get_valid_moves(_move_selected)
		if cell in moves and TurnManager.movement_points > 0:
			if NetworkManager.is_online:
				NetworkManager.move_pawn(_move_selected, cell)
				board.clear_highlights()
				_move_selected = cell
				board.set_selected(cell)
			else:
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
	if NetworkManager.is_online and NetworkManager.my_player_slot != TurnManager.current_player:
		return
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
			if NetworkManager.is_online:
				NetworkManager.declare_attack(_attack_selected, cell)
			else:
				if board.pawn_nodes.has(_attack_selected):
					board.pawn_nodes[_attack_selected].play_attack_anim(board.get_cell_center(cell))
				_active_attacker_pos = _attack_selected
				var adjacent := GameManager.get_adjacent_allies(_attack_selected, team)
				TurnManager.on_attack_declared(_attack_selected, cell, adjacent)
			board.clear_highlights()
		else:
			_attack_selected = Vector2i(-1, -1)
			board.clear_highlights()

func _on_defense_chosen(played_defense: bool, card_index: int) -> void:
	if NetworkManager.is_online:
		if played_defense and card_index >= 0:
			NetworkManager.play_defense(card_index)
		else:
			NetworkManager.pass_defense()
		return
	var defender := 2 if TurnManager.current_player == 1 else 1
	var defender_adjacent := 0
	if played_defense and card_index >= 0:
		var defender_pos: Vector2i = TurnManager.pending_attack["defender_pos"]
		var hand := CardSystem.get_hand(defender)
		assert(card_index < hand.size() and hand[card_index] == CardType.Type.DEFENSE,
			"Defense card index %d is stale or invalid" % card_index)
		CardSystem.play_card(defender, card_index)
		if board.pawn_nodes.has(defender_pos):
			board.pawn_nodes[defender_pos].play_defense_anim()
		defender_adjacent = GameManager.get_adjacent_allies(defender_pos, defender)
	TurnManager.on_defense_resolved(played_defense, defender_adjacent)

func _on_attack_resolved(defender_pos: Vector2i, pawn_survives: bool, _ar: int, _dr: int, _ads: int, _dds: int) -> void:
	_active_attacker_pos = Vector2i(-1, -1)
	if not pawn_survives:
		GameManager.remove_pawn_at(defender_pos)
