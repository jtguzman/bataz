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
