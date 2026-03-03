# res://scripts/ui/lobby.gd
# Home screen — title, play buttons, 12 dancing capybaras, background music.
extends Control

# ── State ──────────────────────────────────────────────────────────────────

var _join_code_input: LineEdit
var _status_label: Label
var _online_panel: Control
var _waiting_label: Label
var _join_code_display: Label
var _music: AudioStreamPlayer
var _active: bool = true  # set false when leaving screen to stop all loops
var _ui_card: PanelContainer  # the center card panel (fades in)
var _howto_overlay: Control = null

const SCREEN_W := 1152.0
const SCREEN_H := 648.0
const CAPYBARA_COUNT := 12
const PAWN_SCENE := "res://scenes/pieces/pawn.tscn"

# Per-capybara state for the roaming loop
var _capi_targets: Array[Vector2] = []
var _capi_nodes: Array[Node2D] = []

# Palette of fun colors for the capybaras
const CAPI_COLORS: Array = [
	Color("#E05252"), Color("#4A90D9"), Color("#52C77A"), Color("#E0A030"),
	Color("#B04AE0"), Color("#E05AA0"), Color("#4ACCE0"), Color("#E0D040"),
	Color("#E07030"), Color("#5090E0"), Color("#A0E050"), Color("#E05080"),
]

# ── Lifecycle ──────────────────────────────────────────────────────────────

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_spawn_capybaras()
	_build_ui()
	_start_music()
	NetworkManager.game_created.connect(_on_game_created)
	NetworkManager.game_joined.connect(_on_game_joined)
	NetworkManager.join_failed.connect(_on_join_failed)
	NetworkManager.connected.connect(_on_connected)
	# Fade in the UI card after 1 second
	_ui_card.modulate.a = 0.0
	await get_tree().create_timer(1.0).timeout
	if _active:
		var fade := create_tween()
		fade.tween_property(_ui_card, "modulate:a", 1.0, 0.6)\
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _exit_tree() -> void:
	_active = false

# ── Capybara dancers ───────────────────────────────────────────────────────

func _spawn_capybaras() -> void:
	var pawn_scene: PackedScene = load(PAWN_SCENE)
	for i in CAPYBARA_COUNT:
		var pawn: Node2D = pawn_scene.instantiate()
		pawn.team = (i % 2) + 1
		pawn.pawn_color = CAPI_COLORS[i]
		# Random starting position, avoid center column (UI lives there)
		var start := _random_screen_pos()
		pawn.position = start
		add_child(pawn)
		_capi_nodes.append(pawn)
		_capi_targets.append(_random_screen_pos())
	# Wait 2s before starting, then stagger each capybara slightly
	for i in CAPYBARA_COUNT:
		_start_capi_loop(i, 1.0 + randf() * 1.5)

func _random_screen_pos() -> Vector2:
	# Keep away from the center UI strip (roughly x 340–810)
	var margin := 55.0
	var zone := randi() % 3
	var x: float
	match zone:
		0: x = randf_range(margin, 300.0)         # left strip
		1: x = randf_range(820.0, SCREEN_W - margin)  # right strip
		_: x = randf_range(margin, SCREEN_W - margin)  # anywhere (far from center)
	var y := randf_range(margin, SCREEN_H - margin)
	return Vector2(x, y)

func _start_capi_loop(idx: int, initial_delay: float) -> void:
	await get_tree().create_timer(initial_delay).timeout
	if _active:
		_capi_roam(idx)

func _capi_roam(idx: int) -> void:
	if not _active or not is_instance_valid(_capi_nodes[idx]):
		return
	var pawn: Node2D = _capi_nodes[idx]
	var target := _random_screen_pos()
	_capi_targets[idx] = target

	# Flip horizontally to face movement direction
	if target.x < pawn.position.x:
		pawn.scale.x = -absf(pawn.scale.x)
	else:
		pawn.scale.x = absf(pawn.scale.x)

	# Pick a random animation style for this move
	var anim_roll := randi() % 5
	match anim_roll:
		0, 1, 2:   # Most common: just walk
			pawn.move_to(target)
			await _wait_not_animating(pawn)
		3:         # Spin + walk
			var spin_tween := create_tween()
			spin_tween.tween_property(pawn, "rotation_degrees",
				pawn.rotation_degrees + 360.0, 0.5).set_trans(Tween.TRANS_BACK)
			await spin_tween.finished
			if not _active:
				return
			pawn.move_to(target)
			await _wait_not_animating(pawn)
		4:         # Attack lunge toward target then continue
			pawn.play_attack_anim(target)
			await _wait_not_animating(pawn)
			if not _active:
				return
			pawn.move_to(target)
			await _wait_not_animating(pawn)

	if not _active:
		return

	# Random pause before next move (0.2–1.8s)
	var pause := randf_range(0.2, 1.8)
	# Occasionally do a defense shake while waiting
	if randf() < 0.3:
		await get_tree().create_timer(pause * 0.4).timeout
		if not _active:
			return
		pawn.play_defense_anim()
		await _wait_not_animating(pawn)
		if not _active:
			return
		await get_tree().create_timer(pause * 0.6).timeout
	else:
		await get_tree().create_timer(pause).timeout

	if not _active:
		return

	# Change color occasionally
	if randf() < 0.25:
		var new_color: Color = CAPI_COLORS[randi() % CAPI_COLORS.size()]
		pawn.pawn_color = new_color
		# Find the Sprite2D child and recolor it
		for child in pawn.get_children():
			if child is Sprite2D:
				(child as Sprite2D).modulate = Color(1,1,1).lerp(new_color, 0.4)

	# Loop
	_capi_roam(idx)

func _wait_not_animating(pawn: Node2D) -> void:
	while is_instance_valid(pawn) and pawn.is_animating:
		if not is_inside_tree():
			return
		await get_tree().process_frame

# ── Music ──────────────────────────────────────────────────────────────────

func _start_music() -> void:
	_music = AudioStreamPlayer.new()
	_music.stream = load("res://assets/audio/bataz-home-screen.ogg")
	_music.volume_db = -6.0
	_music.autoplay = true
	add_child(_music)
	_music.finished.connect(_on_music_finished)

func _on_music_finished() -> void:
	# Song played once — stop all capybara roaming so they settle into idle
	_active = false

func _stop_music() -> void:
	if is_instance_valid(_music):
		var fade := create_tween()
		fade.tween_property(_music, "volume_db", -40.0, 0.6)
		await fade.finished
		_music.stop()

# ── UI Construction ────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Semi-transparent center card so UI is readable over capybaras
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	card.position = Vector2(576.0 - 210.0, 324.0 - 270.0)
	card.size = Vector2(420.0, 540.0)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.06, 0.06, 0.10, 0.82)
	card_style.corner_radius_top_left    = 16
	card_style.corner_radius_top_right   = 16
	card_style.corner_radius_bottom_left = 16
	card_style.corner_radius_bottom_right = 16
	card.add_theme_stylebox_override("panel", card_style)
	add_child(card)
	_ui_card = card

	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 14)
	card.add_child(center)

	# Title
	var title := Label.new()
	title.text = "BATAZ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	center.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Card-Driven Strategy"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 20)
	center.add_child(subtitle)

	center.add_child(HSeparator.new())

	# Local play button
	var local_btn := Button.new()
	local_btn.text = "Play Local (Hot-Seat)"
	local_btn.custom_minimum_size = Vector2(320, 72)
	local_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	local_btn.add_theme_font_size_override("font_size", 22)
	local_btn.pressed.connect(_on_local_btn_pressed)
	center.add_child(local_btn)

	# Online play button
	var online_btn := Button.new()
	online_btn.text = "Play Online"
	online_btn.custom_minimum_size = Vector2(320, 72)
	online_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	online_btn.add_theme_font_size_override("font_size", 22)
	online_btn.pressed.connect(_on_online_btn_pressed)
	center.add_child(online_btn)

	center.add_child(HSeparator.new())

	# How to Play button
	var howto_btn := Button.new()
	howto_btn.text = "How to Play"
	howto_btn.custom_minimum_size = Vector2(320, 56)
	howto_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	howto_btn.add_theme_font_size_override("font_size", 18)
	howto_btn.pressed.connect(_on_howto_btn_pressed)
	center.add_child(howto_btn)

	center.add_child(HSeparator.new())

	# Online sub-panel (hidden until "Play Online" is pressed)
	_online_panel = VBoxContainer.new()
	_online_panel.visible = false
	_online_panel.add_theme_constant_override("separation", 10)
	center.add_child(_online_panel)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.3, 1.0))
	_online_panel.add_child(_status_label)

	var create_btn := Button.new()
	create_btn.text = "Create Game"
	create_btn.custom_minimum_size = Vector2(280, 56)
	create_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	create_btn.pressed.connect(_on_create_game_pressed)
	_online_panel.add_child(create_btn)

	_join_code_display = Label.new()
	_join_code_display.text = ""
	_join_code_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_join_code_display.add_theme_font_size_override("font_size", 26)
	_join_code_display.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5, 1.0))
	_join_code_display.visible = false
	_online_panel.add_child(_join_code_display)

	var or_label := Label.new()
	or_label.text = "— or —"
	or_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_online_panel.add_child(or_label)

	var join_row := HBoxContainer.new()
	join_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	join_row.add_theme_constant_override("separation", 8)
	_online_panel.add_child(join_row)

	_join_code_input = LineEdit.new()
	_join_code_input.placeholder_text = "Enter code (e.g. ABC123)"
	_join_code_input.custom_minimum_size = Vector2(200, 52)
	_join_code_input.max_length = 6
	join_row.add_child(_join_code_input)

	var join_btn := Button.new()
	join_btn.text = "Join"
	join_btn.custom_minimum_size = Vector2(80, 52)
	join_btn.pressed.connect(_on_join_game_pressed)
	join_row.add_child(join_btn)

	_waiting_label = Label.new()
	_waiting_label.text = ""
	_waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_waiting_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0, 1.0))
	_online_panel.add_child(_waiting_label)

# ── Button handlers ────────────────────────────────────────────────────────

func _on_local_btn_pressed() -> void:
	_active = false
	await _stop_music()
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_online_btn_pressed() -> void:
	_online_panel.visible = true
	_status_label.text = "Connecting…"

func _on_create_game_pressed() -> void:
	if not NetworkManager.is_online:
		NetworkManager.connect_online()
		_status_label.text = "Connecting…"
	else:
		NetworkManager._client.create_game()

func _on_join_game_pressed() -> void:
	var code := _join_code_input.text.strip_edges().to_upper()
	if code.length() != 6:
		_status_label.text = "Enter a 6-character join code"
		return
	if not NetworkManager.is_online:
		NetworkManager.connect_online()
		_status_label.text = "Connecting…"
	else:
		NetworkManager._client.join_game(code)
		_status_label.text = "Joining…"

# ── Network callbacks ──────────────────────────────────────────────────────

func _on_connected() -> void:
	_status_label.text = "Connected"
	if _join_code_input.text.strip_edges().length() == 6:
		NetworkManager._client.join_game(_join_code_input.text.strip_edges().to_upper())
	else:
		NetworkManager._client.create_game()

func _on_game_created(_gid: int, join_code: String) -> void:
	_status_label.text = "Game created!"
	_join_code_display.text = "Your code: %s" % join_code
	_join_code_display.visible = true
	_waiting_label.text = "Waiting for opponent…"

func _on_game_joined(_gid: int) -> void:
	_active = false
	_status_label.text = "Joined! Loading game…"
	_waiting_label.text = ""
	NetworkManager.my_player_slot = NetworkManager._client.get_my_player_slot()
	await _stop_music()
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_join_failed(reason: String) -> void:
	_status_label.text = "Failed: %s" % reason
	_waiting_label.text = ""

# ── How to Play ────────────────────────────────────────────────────────────

func _on_howto_btn_pressed() -> void:
	if _howto_overlay == null:
		_build_howto_overlay()
	_howto_overlay.visible = true

func _build_howto_overlay() -> void:
	_howto_overlay = Control.new()
	_howto_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_howto_overlay)

	# Dark backdrop
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.05, 0.88)
	_howto_overlay.add_child(bg)

	# Scrollable card
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_TOP_LEFT)
	scroll.position = Vector2(SCREEN_W * 0.5 - 310.0, 32.0)
	scroll.size = Vector2(620.0, SCREEN_H - 80.0)
	_howto_overlay.add_child(scroll)

	var inner := VBoxContainer.new()
	inner.custom_minimum_size = Vector2(580.0, 0.0)
	inner.add_theme_constant_override("separation", 10)
	scroll.add_child(inner)

	# Title
	var title := Label.new()
	title.text = "How to Play"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	inner.add_child(title)

	inner.add_child(HSeparator.new())

	var sections: Array = [
		["Objective", "Eliminate all enemy capybaras. Last player standing wins."],
		["Board & Pieces", "6×6 board. Each player places 6 capybaras in their starting rows before the game begins."],
		["Cards", "A shared deck of 30 cards: 10 Movement, 10 Attack, 10 Defense.\nEach player holds 4 cards. On your turn, play 1 card and draw 1 back.\nIf the draw pile runs out, the discard pile is reshuffled."],
		["Movement Card", "Roll 1d4 to get movement points.\nDistribute them freely among any of your pieces.\nEach point moves one piece one square (any direction, including diagonal)."],
		["Attack Card", "Your piece must be adjacent (including diagonally) to an enemy.\nDeclare attacker and defender, then roll:\n  • 0 allies nearby → 1d4\n  • 1 ally → 1d6\n  • 2 allies → 1d8\n  • 3 allies → 1d10\n  • 4 allies → 1d12\n  • 5+ allies → 1d20\nThe defender is removed if they fail to defend."],
		["Defense Card", "Played in reaction to an attack — before the result is revealed.\nRoll the same die scale as the attacker (based on your adjacent allies).\nIf your roll ≥ attacker's roll, your piece survives.\nBoth players draw 1 card when a Defense card is played."],
		["Turn Order", "1. Play a card from your hand.\n2. Resolve the card effect.\n3. Draw 1 card.\n4. Board flips — opponent's turn begins."],
	]

	for section in sections:
		var heading := Label.new()
		heading.text = section[0]
		heading.add_theme_font_size_override("font_size", 20)
		heading.add_theme_color_override("font_color", Color(0.3, 1.0, 0.55, 1.0))
		inner.add_child(heading)

		var body := Label.new()
		body.text = section[1]
		body.add_theme_font_size_override("font_size", 15)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(560.0, 0.0)
		inner.add_child(body)

		inner.add_child(HSeparator.new())

	# Close button
	var close_btn := Button.new()
	close_btn.text = "Got it!"
	close_btn.custom_minimum_size = Vector2(200.0, 56.0)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.add_theme_font_size_override("font_size", 20)
	close_btn.pressed.connect(func() -> void: _howto_overlay.visible = false)
	inner.add_child(close_btn)

	# Also close on backdrop tap
	bg.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			_howto_overlay.visible = false
	)
