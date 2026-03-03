# res://scripts/ui/hud.gd
extends CanvasLayer

signal card_played_by_ui(player: int, card_index: int)
signal discard_pass_requested(player: int)
signal defense_chosen(played_defense: bool, card_index: int)
signal movement_done_requested
signal placement_confirmed(player: int)
signal attack_card_pending(player: int, card_index: int)
signal attack_card_cancelled

# Scene-referenced nodes (TopBar stays in .tscn)
@onready var top_hand: HBoxContainer = $TopBar/TopHand
@onready var turn_label: Label = $TopBar/TurnLabel
@onready var turn_overlay: PanelContainer = $TurnOverlay
@onready var turn_overlay_label: Label = $TurnOverlay/Label

# --- Zone 1: Action buttons (x=0, w=240, below left card panel) ---
var _cards_panel: PanelContainer
var _cancel_discard_btn: Button
var _cancel_attack_btn: Button
var _placement_confirm_btn: Button

# --- Right column info panel (x=910, y=480, w=242, h=168) ---
# Shared by dice/messages AND defense request
var _info_panel: PanelContainer
var _dice_type_label: Label
var _dice_result_label: Label
var _dice_zone_gen: int = 0
var defense_title: Label
var _defense_play_btn: Button
var defense_pass_btn: Button
var _defense_card_index: int = -1

# --- Zone 4 merged into Zone 1 ---
var done_btn: Button
var discard_pass_btn: Button
var confirm_btn: Button

# Double-tap state
var _last_tapped_hand_idx: int = -1
var _last_tap_time: float = -1.0
const DOUBLE_TAP_SEC := 0.4

# Card system
var _card_scene: PackedScene
var _pending_card_index: int = -1
var _discard_mode: bool = false
var _selected_discard: Array[int] = []
var _placement_player: int = 0
var _placement_label: Label

# History panel
var _history_scroll: ScrollContainer
var _history_list: VBoxContainer
var _pending_history: Dictionary = {}

# Deck panel (unused but kept for signal handler guard)
var _draw_count_label: Label
var _discard_count_label: Label
var _discard_card_rect: ColorRect

# Left hand (card sprites on left panel)
var _left_hand_container: Control
var _card_textures: Dictionary = {}

# Waiting overlay (online)
var _waiting_overlay: PanelContainer

# Generation counters
var _dice_panel_gen: int = 0
var _turn_overlay_gen: int = 0

# Layout constants
# Board grid: 486×486, center at (575,324), grid top-left at (332,81)
const ZONE_Y      := 552.0   # bottom of left action zone
const ZONE_H      := 96.0
const BOARD_X     := 332.0   # board grid left edge
const BOARD_Y     := 81.0    # board grid top edge
const BOARD_SIZE  := 486.0   # grid width/height
const RIGHT_X     := 910.0   # right column start
const RIGHT_W     := 242.0   # right column width
const INFO_Y      := 480.0   # where info panel starts (below history)
const INFO_H      := 168.0   # info panel height

func _ready() -> void:
	_card_scene = load("res://scenes/cards/card.tscn")
	_load_card_textures()
	_create_placement_label()
	_create_left_hand_panel()
	_create_cards_zone()
	_create_info_panel()
	_create_history_panel()
	_create_waiting_overlay()
	($TopBar as Control).visible = false
	_connect_signals()
	_set_all_action_buttons_hidden()
	turn_overlay.visible = false
	turn_overlay.position = Vector2(415, 284)
	turn_overlay.size = Vector2(320, 80)
	move_child(turn_overlay, get_child_count() - 1)
	move_child(_waiting_overlay, get_child_count() - 1)

func _connect_signals() -> void:
	TurnManager.turn_started.connect(_on_turn_started)
	TurnManager.phase_changed.connect(_on_phase_changed)
	TurnManager.defense_requested.connect(_on_defense_requested)
	TurnManager.movement_rolled.connect(_on_movement_rolled)
	TurnManager.attack_resolved.connect(_on_attack_resolved)
	TurnManager.turn_ended.connect(_on_turn_ended_history)
	CardSystem.hand_changed.connect(_on_hand_changed)
	CardSystem.card_played.connect(_on_card_played_history)
	GameManager.game_over.connect(_on_game_over)
	if NetworkManager.is_online:
		NetworkManager.event_logged.connect(_on_event_logged_online)

# ─── Zone helpers ──────────────────────────────────────────────

func _make_zone_panel(x: float, w: float, bg: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(x, ZONE_Y)
	panel.size = Vector2(w, ZONE_H)
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	if x > 0.0:
		style.border_width_left = 1
		style.border_color = Color(0.35, 0.35, 0.35)
	panel.add_theme_stylebox_override("panel", style)
	return panel

# ─── Zone 1: Action buttons ────────────────────────────────────

func _create_cards_zone() -> void:
	_cards_panel = _make_zone_panel(0.0, 240.0, Color(0.10, 0.10, 0.10))
	add_child(_cards_panel)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 4)
	_cards_panel.add_child(vbox)

	discard_pass_btn = _make_action_btn("Discard & Pass", 0)
	discard_pass_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(discard_pass_btn)

	done_btn = _make_action_btn("Done", 0)
	done_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(done_btn)

	_cancel_discard_btn = _make_action_btn("Cancel", 0)
	_cancel_discard_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cancel_discard_btn.visible = false
	vbox.add_child(_cancel_discard_btn)

	_cancel_attack_btn = _make_action_btn("Cancel Atk", 0)
	_cancel_attack_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cancel_attack_btn.visible = false
	vbox.add_child(_cancel_attack_btn)

	_placement_confirm_btn = _make_action_btn("Confirm Placement", 0)
	_placement_confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_placement_confirm_btn.visible = false
	vbox.add_child(_placement_confirm_btn)

	confirm_btn = _make_action_btn("Confirm", 0)
	confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_btn.visible = false
	vbox.add_child(confirm_btn)

	discard_pass_btn.pressed.connect(_on_discard_pass_btn_pressed)
	done_btn.pressed.connect(_on_done_btn_pressed)
	_cancel_discard_btn.pressed.connect(_on_cancel_discard_btn_pressed)
	_cancel_attack_btn.pressed.connect(_on_cancel_attack_btn_pressed)
	_placement_confirm_btn.pressed.connect(_on_placement_confirm_btn_pressed)
	confirm_btn.pressed.connect(_on_confirm_btn_pressed)

func _make_action_btn(label: String, min_w: int) -> Button:
	var btn := Button.new()
	btn.text = label
	if min_w > 0:
		btn.custom_minimum_size = Vector2(min_w, 0)
	return btn

# ─── Right info panel: dice/messages + defense ─────────────────

func _create_info_panel() -> void:
	_info_panel = PanelContainer.new()
	_info_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_info_panel.position = Vector2(RIGHT_X, INFO_Y)
	_info_panel.size = Vector2(RIGHT_W, INFO_H)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.15)
	style.border_width_top = 1
	style.border_color = Color(0.35, 0.35, 0.35)
	_info_panel.add_theme_stylebox_override("panel", style)
	add_child(_info_panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 4)
	_info_panel.add_child(vbox)

	# Dice / message section
	_dice_type_label = Label.new()
	_dice_type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dice_type_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dice_type_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_dice_type_label)

	_dice_result_label = Label.new()
	_dice_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dice_result_label.add_theme_font_size_override("font_size", 34)
	vbox.add_child(_dice_result_label)

	# Defense section (hidden until defense is requested)
	defense_title = Label.new()
	defense_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	defense_title.add_theme_font_size_override("font_size", 13)
	defense_title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	defense_title.visible = false
	vbox.add_child(defense_title)

	_defense_play_btn = Button.new()
	_defense_play_btn.text = "Play Defense Card"
	_defense_play_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_defense_play_btn.visible = false
	_defense_play_btn.pressed.connect(_on_defense_play_btn_pressed)
	vbox.add_child(_defense_play_btn)

	defense_pass_btn = Button.new()
	defense_pass_btn.text = "Pass (take hit)"
	defense_pass_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	defense_pass_btn.visible = false
	defense_pass_btn.pressed.connect(_on_defense_pass_btn_pressed)
	vbox.add_child(defense_pass_btn)

func _show_defense_zone() -> void:
	defense_title.visible = true
	_defense_play_btn.visible = _defense_card_index >= 0
	defense_pass_btn.visible = true

func _hide_defense_zone() -> void:
	defense_title.visible = false
	_defense_play_btn.visible = false
	defense_pass_btn.visible = false

# ─── Left hand panel (card sprites) ────────────────────────────

const CARD_W := 110.0
const CARD_H := 154.0
const STACK_OFFSET := 7.0
const CARD_GROUP_GAP := 12.0

func _create_left_hand_panel() -> void:
	_left_hand_container = Control.new()
	_left_hand_container.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_left_hand_container.position = Vector2(12.0, 20.0)
	_left_hand_container.size = Vector2(220.0, 530.0)
	add_child(_left_hand_container)

func _load_card_textures() -> void:
	_card_textures[CardType.Type.MOVEMENT] = load("res://assets/sprites/cards/card-move.png")
	_card_textures[CardType.Type.ATTACK]   = load("res://assets/sprites/cards/card-attack.png")
	_card_textures[CardType.Type.DEFENSE]  = load("res://assets/sprites/cards/card-defense.png")

func _get_card_texture(type: int) -> Texture2D:
	return _card_textures.get(type, null)

func _rebuild_left_hand(hand: Array) -> void:
	for child in _left_hand_container.get_children():
		child.queue_free()
	var type_order: Array[int] = [CardType.Type.MOVEMENT, CardType.Type.ATTACK, CardType.Type.DEFENSE]
	var groups: Dictionary = {}
	for i in hand.size():
		var t: int = hand[i]
		if not groups.has(t):
			groups[t] = []
		groups[t].append(i)
	var y := 0.0
	for type in type_order:
		if not groups.has(type):
			continue
		var indices: Array = groups[type]
		var count := indices.size()
		var group := Control.new()
		group.name = "Stack_%d" % type
		group.position = Vector2(0.0, y)
		group.size = Vector2(CARD_W + (count - 1) * STACK_OFFSET, CARD_H + (count - 1) * STACK_OFFSET)
		_left_hand_container.add_child(group)
		for vi in range(count - 1, -1, -1):
			var hand_idx: int = indices[vi]
			var offset := float(vi) * STACK_OFFSET
			var card_ctrl := Control.new()
			card_ctrl.name = "Card_%d" % hand_idx
			card_ctrl.position = Vector2(offset, offset)
			card_ctrl.size = Vector2(CARD_W, CARD_H)
			group.add_child(card_ctrl)
			var tex_rect := TextureRect.new()
			tex_rect.texture = _get_card_texture(type)
			tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
			tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card_ctrl.add_child(tex_rect)
			var glow := Panel.new()
			glow.name = "Glow"
			glow.set_anchors_preset(Control.PRESET_FULL_RECT)
			glow.visible = false
			glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var gs := StyleBoxFlat.new()
			gs.bg_color = Color(0, 0, 0, 0)
			gs.border_width_left = 4; gs.border_width_right = 4
			gs.border_width_top = 4; gs.border_width_bottom = 4
			gs.border_color = Color(1.0, 0.85, 0.1, 1.0)
			gs.corner_radius_top_left = 6; gs.corner_radius_top_right = 6
			gs.corner_radius_bottom_left = 6; gs.corner_radius_bottom_right = 6
			glow.add_theme_stylebox_override("panel", gs)
			card_ctrl.add_child(glow)
			var btn := Button.new()
			btn.flat = true
			btn.set_anchors_preset(Control.PRESET_FULL_RECT)
			var hi := hand_idx
			var tp := type
			btn.pressed.connect(func(): _on_left_card_pressed(hi, tp))
			card_ctrl.add_child(btn)
		if count > 1:
			var badge := Label.new()
			badge.text = "x%d" % count
			badge.position = Vector2(CARD_W - 28.0, 4.0)
			badge.size = Vector2(28.0, 20.0)
			badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			badge.add_theme_font_size_override("font_size", 14)
			group.add_child(badge)
		y += CARD_H + (count - 1) * STACK_OFFSET + CARD_GROUP_GAP

func _on_left_card_pressed(hand_idx: int, _type: int) -> void:
	if _discard_mode:
		if hand_idx in _selected_discard:
			_selected_discard.erase(hand_idx)
		else:
			_selected_discard.append(hand_idx)
		_update_left_hand_discard_display()
		return
	if TurnManager.phase != TurnManager.Phase.PLAY_CARD:
		return
	if NetworkManager.is_online and NetworkManager.my_player_slot != TurnManager.current_player:
		return
	var hand := CardSystem.get_hand(TurnManager.current_player)
	if hand_idx >= hand.size():
		return
	var card_type: int = hand[hand_idx]
	if card_type == CardType.Type.DEFENSE:
		_show_message("Defense cards are reactive only")
		return
	if card_type == CardType.Type.ATTACK and not _has_valid_attacker():
		_show_message("No pawns adjacent to enemies")
		return
	if card_type == CardType.Type.ATTACK:
		_pending_card_index = hand_idx
		_last_tapped_hand_idx = -1
		_update_left_hand_selection()
		_cancel_attack_btn.visible = true
		attack_card_pending.emit(TurnManager.current_player, hand_idx)
		return
	var now := Time.get_ticks_msec() / 1000.0
	var is_double := hand_idx == _last_tapped_hand_idx \
		and _pending_card_index == hand_idx \
		and (now - _last_tap_time) < DOUBLE_TAP_SEC
	_last_tapped_hand_idx = hand_idx
	_last_tap_time = now
	if is_double:
		_pending_card_index = -1
		_last_tapped_hand_idx = -1
		_update_left_hand_selection()
		card_played_by_ui.emit(TurnManager.current_player, hand_idx)
	else:
		_pending_card_index = hand_idx
		_update_left_hand_selection()
		_show_message("Tap again to play")

func _update_left_hand_selection() -> void:
	var selected_type := -1
	if _pending_card_index >= 0:
		var hand := CardSystem.get_hand(TurnManager.current_player)
		if _pending_card_index < hand.size():
			selected_type = hand[_pending_card_index]
	for stack in _left_hand_container.get_children():
		var sname := stack.name as String
		if not sname.begins_with("Stack_"):
			continue
		var stack_type := int(sname.split("_")[1])
		var is_sel := selected_type != -1 and stack_type == selected_type
		stack.modulate = Color(1, 1, 1, 1) if selected_type == -1 or is_sel \
			else Color(0.35, 0.35, 0.35, 1.0)
		for card_ctrl in stack.get_children():
			if not (card_ctrl.name as String).begins_with("Card_"):
				continue
			var g := card_ctrl.get_node_or_null("Glow")
			if g:
				g.visible = is_sel

func _update_left_hand_discard_display() -> void:
	for stack in _left_hand_container.get_children():
		if not (stack.name as String).begins_with("Stack_"):
			continue
		for card_ctrl in stack.get_children():
			if not (card_ctrl.name as String).begins_with("Card_"):
				continue
			var hi := int((card_ctrl.name as String).split("_")[1])
			card_ctrl.modulate = Color(1.0, 0.45, 0.45, 1.0) if hi in _selected_discard \
				else Color(1.0, 1.0, 1.0, 1.0)
	confirm_btn.visible = _selected_discard.size() > 0
	if _selected_discard.size() > 0:
		confirm_btn.text = "Confirm Discard (%d)" % _selected_discard.size()

# ─── History panel (right column, top section) ─────────────────

func _create_history_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(RIGHT_X, 0)
	panel.size = Vector2(RIGHT_W, INFO_Y)
	add_child(panel)
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)
	var title := Label.new()
	title.text = "History"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	_history_scroll = ScrollContainer.new()
	_history_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_history_scroll)
	_history_list = VBoxContainer.new()
	_history_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history_scroll.add_child(_history_list)

# ─── Deck display (guard only — panel not shown) ───────────────

func _update_deck_display() -> void:
	pass

# ─── Waiting overlay (online multiplayer) ──────────────────────

func _create_waiting_overlay() -> void:
	_waiting_overlay = PanelContainer.new()
	_waiting_overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_waiting_overlay.position = Vector2(BOARD_X, BOARD_Y)
	_waiting_overlay.size = Vector2(BOARD_SIZE, BOARD_SIZE)
	_waiting_overlay.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	_waiting_overlay.add_theme_stylebox_override("panel", style)
	add_child(_waiting_overlay)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_waiting_overlay.add_child(vbox)
	var lbl := Label.new()
	lbl.text = "Waiting for opponent…"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 22)
	vbox.add_child(lbl)

func _update_waiting_overlay() -> void:
	if not NetworkManager.is_online:
		_waiting_overlay.visible = false
		return
	var my_slot := NetworkManager.my_player_slot
	var is_my_turn := (my_slot == TurnManager.current_player)
	if TurnManager.phase == TurnManager.Phase.RESOLVE_DEFENSE:
		var defender := 2 if TurnManager.current_player == 1 else 1
		if my_slot == defender:
			_waiting_overlay.visible = false
			return
	_waiting_overlay.visible = not is_my_turn

# ─── Placement label ───────────────────────────────────────────

func _create_placement_label() -> void:
	_placement_label = Label.new()
	_placement_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_placement_label.position = Vector2(BOARD_X, BOARD_Y + 8.0)
	_placement_label.size = Vector2(BOARD_SIZE, 40)
	_placement_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placement_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_placement_label.visible = false
	add_child(_placement_label)

# ─── Turn / phase handlers ─────────────────────────────────────

func _on_turn_started(player: int) -> void:
	turn_label.text = "Player %d" % player
	_rebuild_both_hands()
	_set_all_action_buttons_hidden()
	discard_pass_btn.visible = true
	_update_waiting_overlay()

func _on_phase_changed(phase: TurnManager.Phase) -> void:
	_set_all_action_buttons_hidden()
	match phase:
		TurnManager.Phase.PLAY_CARD:
			discard_pass_btn.visible = true
		TurnManager.Phase.RESOLVE_MOVEMENT:
			done_btn.visible = true
		TurnManager.Phase.END:
			pass
	_update_waiting_overlay()

func _on_movement_rolled(points: int) -> void:
	_show_dice("1d4", points)
	if not NetworkManager.is_online:
		_pending_history["detail"] = "  Rolled %d pts" % points

func _on_defense_requested(_ap: Vector2i, _dp: Vector2i, die_sides: int) -> void:
	var defender := 2 if TurnManager.current_player == 1 else 1
	if NetworkManager.is_online and NetworkManager.my_player_slot != defender:
		return
	var hand := CardSystem.get_hand(defender)
	_defense_card_index = -1
	for i in hand.size():
		if hand[i] == CardType.Type.DEFENSE:
			_defense_card_index = i
			break
	defense_title.text = "P%d – Defend? (ATK: 1d%d)" % [defender, die_sides]
	_show_defense_zone()
	_waiting_overlay.visible = false

func _on_defense_play_btn_pressed() -> void:
	_hide_defense_zone()
	defense_chosen.emit(true, _defense_card_index)

func _on_defense_pass_btn_pressed() -> void:
	_hide_defense_zone()
	defense_chosen.emit(false, -1)

func _on_attack_resolved(_dp: Vector2i, pawn_survives: bool, attack_roll: int, defense_roll: int, attack_die_sides: int, defense_die_sides: int) -> void:
	if defense_roll > 0:
		_dice_type_label.text = "ATK %d vs DEF %d" % [attack_roll, defense_roll]
		_dice_result_label.text = "Blocked!" if pawn_survives else "Hit!"
	else:
		_dice_type_label.text = "ATK %d" % attack_roll
		_dice_result_label.text = "Hit!"
	_dice_zone_gen += 1
	var gen := _dice_zone_gen
	get_tree().create_timer(2.0).timeout.connect(func():
		if _dice_zone_gen == gen:
			_dice_type_label.text = ""
			_dice_result_label.text = ""
	)
	if not NetworkManager.is_online:
		if defense_die_sides > 0:
			var outcome := "Blocked!" if pawn_survives else "Hit!"
			_pending_history["detail"] = "  1d%d=%d vs 1d%d=%d → %s" % [attack_die_sides, attack_roll, defense_die_sides, defense_roll, outcome]
		else:
			_pending_history["detail"] = "  1d%d=%d → Hit! (undefended)" % [attack_die_sides, attack_roll]

# ─── Dice / Status display ─────────────────────────────────────

func _show_dice(die_label: String, result: int) -> void:
	_dice_type_label.text = die_label
	_dice_result_label.text = str(result)
	_dice_zone_gen += 1
	var gen := _dice_zone_gen
	get_tree().create_timer(1.5).timeout.connect(func():
		if _dice_zone_gen == gen:
			_dice_type_label.text = ""
			_dice_result_label.text = ""
	)

func _show_message(msg: String) -> void:
	_dice_type_label.text = msg
	_dice_result_label.text = ""
	_dice_zone_gen += 1
	var gen := _dice_zone_gen
	get_tree().create_timer(2.0).timeout.connect(func():
		if _dice_zone_gen == gen:
			_dice_type_label.text = ""
			_dice_result_label.text = ""
	)

# ─── Turn overlay ──────────────────────────────────────────────

func show_turn_overlay(player: int) -> void:
	turn_overlay_label.text = "Player %d's Turn" % player
	turn_overlay.visible = true
	_turn_overlay_gen += 1
	var gen := _turn_overlay_gen
	get_tree().create_timer(0.8).timeout.connect(func():
		if _turn_overlay_gen == gen:
			turn_overlay.visible = false
	)

# ─── Hand management ───────────────────────────────────────────

func _on_hand_changed(player: int, hand: Array) -> void:
	_rebuild_hand(player, hand)
	_update_deck_display()

func _rebuild_both_hands() -> void:
	_rebuild_hand(1, CardSystem.get_hand(1))
	_rebuild_hand(2, CardSystem.get_hand(2))

func _rebuild_hand(player: int, hand: Array) -> void:
	var is_active := player == TurnManager.current_player
	if NetworkManager.is_online:
		is_active = (player == NetworkManager.my_player_slot)
	if is_active:
		_rebuild_left_hand(hand)

func _has_valid_attacker() -> bool:
	return GameManager.has_valid_attacker(TurnManager.current_player)

# ─── Button handlers ───────────────────────────────────────────

func _set_all_action_buttons_hidden() -> void:
	done_btn.visible = false
	discard_pass_btn.visible = false
	confirm_btn.visible = false
	_cancel_discard_btn.visible = false
	_cancel_attack_btn.visible = false
	_placement_label.visible = false
	_placement_confirm_btn.visible = false
	_pending_card_index = -1
	_last_tapped_hand_idx = -1
	_discard_mode = false
	_selected_discard.clear()

func _on_done_btn_pressed() -> void:
	movement_done_requested.emit()

func _on_discard_pass_btn_pressed() -> void:
	_discard_mode = true
	_selected_discard.clear()
	discard_pass_btn.visible = false
	_cancel_discard_btn.visible = true
	_update_left_hand_discard_display()

func _on_cancel_discard_btn_pressed() -> void:
	_discard_mode = false
	_selected_discard.clear()
	_cancel_discard_btn.visible = false
	confirm_btn.visible = false
	discard_pass_btn.visible = true
	_rebuild_hand(TurnManager.current_player, CardSystem.get_hand(TurnManager.current_player))

func _on_cancel_attack_btn_pressed() -> void:
	_cancel_attack_btn.visible = false
	if TurnManager.phase == TurnManager.Phase.PLAY_CARD:
		discard_pass_btn.visible = true
	_pending_card_index = -1
	_update_left_hand_selection()
	attack_card_cancelled.emit()

func _on_confirm_btn_pressed() -> void:
	if not _discard_mode:
		return
	var indices: Array[int] = []
	indices.assign(_selected_discard)
	_discard_mode = false
	_selected_discard.clear()
	CardSystem.selective_discard(TurnManager.current_player, indices)
	if not NetworkManager.is_online:
		_pending_history = {"player": TurnManager.current_player, "card": -1, "detail": "  Passed (discarded %d)" % indices.size()}
	discard_pass_requested.emit(TurnManager.current_player)

# ─── Placement UI ──────────────────────────────────────────────

func show_placement_ui(player: int) -> void:
	_placement_player = player
	_set_all_action_buttons_hidden()
	turn_label.text = "Player %d" % player
	_placement_label.text = "Player %d — Place your pieces (0/6)" % player
	_placement_label.visible = true
	_placement_confirm_btn.visible = false

func update_placement_count(n: int) -> void:
	_placement_label.text = "Player %d — Place your pieces (%d/6)" % [_placement_player, n]
	_placement_confirm_btn.visible = (n == 6)

func hide_placement_ui() -> void:
	_placement_label.visible = false
	_placement_confirm_btn.visible = false

func _on_placement_confirm_btn_pressed() -> void:
	placement_confirmed.emit(_placement_player)

# ─── History ───────────────────────────────────────────────────

func _on_event_logged_online(text: String) -> void:
	_history_list.add_child(HSeparator.new())
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_history_list.add_child(lbl)
	_scroll_history_to_bottom()

func _on_card_played_history(player: int, type: CardType.Type) -> void:
	if NetworkManager.is_online:
		return
	_pending_history = {"player": player, "card": type, "detail": ""}

func _on_turn_ended_history(_player: int) -> void:
	if NetworkManager.is_online:
		return
	if _pending_history.is_empty():
		return
	_append_history_entry(
		_pending_history.get("player", 0),
		_pending_history.get("card", -1),
		_pending_history.get("detail", "")
	)
	_pending_history = {}

func _append_history_entry(player: int, card_type: int, detail: String) -> void:
	_history_list.add_child(HSeparator.new())
	var card_name: String
	match card_type:
		CardType.Type.MOVEMENT: card_name = "Movement"
		CardType.Type.ATTACK:   card_name = "Attack"
		CardType.Type.DEFENSE:  card_name = "Defense"
		_:                      card_name = "Passed"
	var lbl := Label.new()
	lbl.text = "P%d -- %s\n%s" % [player, card_name, detail]
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_history_list.add_child(lbl)
	_scroll_history_to_bottom()

func _scroll_history_to_bottom() -> void:
	await get_tree().process_frame
	_history_scroll.scroll_vertical = int(_history_scroll.get_v_scroll_bar().max_value)

# ─── Game over ─────────────────────────────────────────────────

func _on_game_over(winner: int) -> void:
	turn_overlay_label.text = "Player %d Wins!" % winner
	turn_overlay.visible = true
	_turn_overlay_gen += 1
	_set_all_action_buttons_hidden()
	_waiting_overlay.visible = false
