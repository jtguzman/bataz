# res://scripts/game/turn_manager.gd
extends Node

signal turn_started(player: int)
signal phase_changed(phase: Phase)
signal turn_ended(player: int)
signal defense_requested(attacker_pos: Vector2i, defender_pos: Vector2i, attacker_die_sides: int)
signal attack_resolved(defender_pos: Vector2i, pawn_survives: bool, attack_roll: int, defense_roll: int)
signal movement_rolled(points: int)

enum Phase {
	PLAY_CARD,
	RESOLVE_MOVEMENT,
	RESOLVE_ATTACK,
	RESOLVE_DEFENSE,
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
	CardSystem.draw_card(current_player)
	phase = Phase.END
	phase_changed.emit(phase)
	# end_turn() is called by Main after flip animation

func consume_movement_point() -> void:
	assert(movement_points > 0, "[TurnManager] No movement points to consume")
	movement_points -= 1

func on_attack_declared(attacker_pos: Vector2i, defender_pos: Vector2i, attacker_adjacent: int) -> void:
	var die_sides := DiceRoller.get_die_sides(attacker_adjacent)
	pending_attack = {
		"attacker_pos": attacker_pos,
		"defender_pos": defender_pos,
		"die_sides": die_sides,
	}
	phase = Phase.RESOLVE_DEFENSE
	phase_changed.emit(phase)
	defense_requested.emit(attacker_pos, defender_pos, die_sides)

func on_defense_resolved(defender_played_card: bool, defender_adjacent: int) -> void:
	var attack_roll := DiceRoller.roll(pending_attack["die_sides"])
	var defender_pos: Vector2i = pending_attack["defender_pos"]
	var def_roll := 0
	var pawn_survives := false

	if defender_played_card:
		var def_sides := DiceRoller.get_die_sides(defender_adjacent)
		def_roll = DiceRoller.roll(def_sides)
		pawn_survives = def_roll >= attack_roll
		CardSystem.draw_card(current_player)
		var other := 2 if current_player == 1 else 1
		CardSystem.draw_card(other)
	else:
		CardSystem.draw_card(current_player)

	attack_resolved.emit(defender_pos, pawn_survives, attack_roll, def_roll)
	pending_attack = {}
	phase = Phase.END
	phase_changed.emit(phase)
	# end_turn() is called by Main after flip animation

func on_discard_and_pass() -> void:
	phase = Phase.END
	phase_changed.emit(phase)
	# end_turn() is called by Main after flip animation

func end_turn() -> void:
	turn_ended.emit(current_player)
	current_player = 2 if current_player == 1 else 1
	_begin_turn()
