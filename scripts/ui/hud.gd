# res://scripts/ui/hud.gd
extends CanvasLayer

signal card_played_by_ui(player: int, card_index: int)
signal discard_pass_requested(player: int)
signal defense_chosen(played_defense: bool, card_index: int)
signal movement_done_requested
signal turn_end_confirmed

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
var _pending_card_index: int = -1
var play_card_btn: Button

func _ready() -> void:
	_card_scene = load("res://scenes/cards/card.tscn")
	# PlayCardBtn is created here because add_node/save_scene have runtime sync issues
	play_card_btn = Button.new()
	play_card_btn.text = "Play Card"
	play_card_btn.custom_minimum_size = Vector2(120, 60)
	play_card_btn.visible = false
	$BottomBar.add_child(play_card_btn)
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
	done_btn.pressed.connect(_on_done_btn_pressed)
	discard_pass_btn.pressed.connect(_on_discard_pass_btn_pressed)
	confirm_btn.pressed.connect(_on_confirm_btn_pressed)
	defense_pass_btn.pressed.connect(_on_defense_pass_btn_pressed)
	play_card_btn.pressed.connect(_on_play_card_btn_pressed)

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
			pass

func _on_movement_rolled(points: int) -> void:
	_show_dice("1d4", points)

func _on_defense_requested(_ap: Vector2i, _dp: Vector2i, attack_roll: int, die_label: String) -> void:
	_show_dice(die_label, attack_roll)
	var defender := 2 if current_player == 1 else 1
	var hand := CardSystem.get_hand(defender)
	defense_title.text = "Player %d - Defend? (ATK=%d)" % [defender, attack_roll]
	for child in defense_hand.get_children():
		child.queue_free()
	var has_defense_card := false
	for i in hand.size():
		if hand[i] == CardType.Type.DEFENSE:
			var card = _card_scene.instantiate()
			card.setup(i, hand[i])
			var idx := i
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
		msg = "ATK %d vs DEF %d - %s" % [attack_roll, defense_roll, "Blocked!" if pawn_survives else "Hit!"]
	else:
		msg = "ATK %d - Hit!" % attack_roll
	dice_label.text = msg
	dice_panel.visible = true
	get_tree().create_timer(2.0).timeout.connect(func(): dice_panel.visible = false)

func show_discard_preview() -> void:
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
		var card = _card_scene.instantiate()
		card.setup(i, hand[i], not is_active)
		if is_active:
			var idx := i
			card.card_selected.connect(func(_x): _on_hand_card_tapped(idx))
		container.add_child(card)

func _on_hand_card_tapped(idx: int) -> void:
	if TurnManager.phase != TurnManager.Phase.PLAY_CARD:
		return
	var hand := CardSystem.get_hand(current_player)
	var card_type: int = hand[idx]
	if card_type == CardType.Type.DEFENSE:
		_show_message("Defense cards are reactive only")
		return
	if card_type == CardType.Type.ATTACK and not _has_valid_attacker():
		_show_message("No pawns adjacent to enemies")
		return
	_pending_card_index = idx
	_update_hand_selection()
	play_card_btn.visible = true

func _has_valid_attacker() -> bool:
	var team := TurnManager.current_player
	for pos in GameManager.board_state:
		if GameManager.board_state[pos] == team:
			if not GameManager.get_valid_attack_targets(pos).is_empty():
				return true
	return false

func _show_message(msg: String) -> void:
	dice_label.text = msg
	dice_panel.visible = true
	get_tree().create_timer(2.0).timeout.connect(func(): dice_panel.visible = false)

func _update_hand_selection() -> void:
	var i := 0
	for child in bottom_hand.get_children():
		child.modulate = Color(1, 1, 1, 1) if i == _pending_card_index else Color(0.4, 0.4, 0.4, 1)
		i += 1

func _on_play_card_btn_pressed() -> void:
	if _pending_card_index < 0:
		return
	card_played_by_ui.emit(current_player, _pending_card_index)
	_pending_card_index = -1
	play_card_btn.visible = false

func show_turn_overlay(player: int) -> void:
	turn_overlay_label.text = "Player %d's Turn" % player
	turn_overlay.visible = true
	get_tree().create_timer(0.8).timeout.connect(func(): turn_overlay.visible = false)

func _show_dice(die_label: String, result: int) -> void:
	dice_label.text = "%s -> %d" % [die_label, result]
	dice_panel.visible = true
	get_tree().create_timer(1.5).timeout.connect(func(): dice_panel.visible = false)

func _set_all_action_buttons_hidden() -> void:
	done_btn.visible = false
	discard_pass_btn.visible = false
	confirm_btn.visible = false
	play_card_btn.visible = false
	_pending_card_index = -1

func _on_done_btn_pressed() -> void:
	movement_done_requested.emit()

func _on_discard_pass_btn_pressed() -> void:
	discard_pass_requested.emit(current_player)

func _on_confirm_btn_pressed() -> void:
	turn_end_confirmed.emit()

func _on_game_over(winner: int) -> void:
	turn_label.text = "Player %d Wins!" % winner
	_set_all_action_buttons_hidden()
