# res://scripts/pieces/pawn.gd
extends Node2D

var team: int = 1
var board_pos: Vector2i = Vector2i.ZERO
var pawn_color: Color = Color("#4A90D9")
var is_selected: bool = false
var is_animating: bool = false

const RADIUS := 28.0

var _sprite: Sprite2D
var _tex_idle: Texture2D
var _tex_moving: Texture2D
var _tex_attacking: Texture2D
var _tex_defending: Texture2D
var _idle_tween: Tween = null

func _ready() -> void:
	_tex_idle      = load("res://assets/sprites/pawns/capybara_idle.png")
	_tex_moving    = load("res://assets/sprites/pawns/capybara_moving.png")
	_tex_attacking = load("res://assets/sprites/pawns/capybara_attacking.png")
	_tex_defending = load("res://assets/sprites/pawns/capybara_defending.png")
	_sprite = Sprite2D.new()
	_sprite.texture = _tex_idle
	# Pivot near feet: shift sprite up so rotation rocks from base
	_sprite.offset = Vector2(0.0, -38.0)
	# Blend team color with white so the capybara's natural browns show through
	_sprite.modulate = Color(1.0, 1.0, 1.0).lerp(pawn_color, 0.4)
	_sprite.scale = Vector2(0.41, 0.41)
	add_child(_sprite)
	_start_idle_dance()

# ── Idle dance ─────────────────────────────────────────────────

func _start_idle_dance() -> void:
	if is_instance_valid(_idle_tween):
		_idle_tween.kill()
	_idle_tween = create_tween().set_loops()
	_idle_tween.tween_property(_sprite, "rotation_degrees", 3.5, 0.55)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idle_tween.tween_property(_sprite, "rotation_degrees", -3.5, 0.55)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _stop_idle_dance() -> void:
	if is_instance_valid(_idle_tween):
		_idle_tween.kill()
		_idle_tween = null
	if is_instance_valid(_sprite):
		_sprite.rotation_degrees = 0.0

func set_state(state: String) -> void:
	var tex: Texture2D
	match state:
		"idle":      tex = _tex_idle
		"moving":    tex = _tex_moving
		"attacking": tex = _tex_attacking
		"defending": tex = _tex_defending
	if tex and _sprite:
		_sprite.texture = tex

func move_to(target: Vector2) -> void:
	_stop_idle_dance()
	is_animating = true
	set_state("moving")
	var tween := create_tween().set_parallel(false)
	tween.tween_property(self, "scale", Vector2(1.2, 1.2), 0.08)
	tween.tween_property(self, "position", target, 0.18)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.08)
	await tween.finished
	set_state("idle")
	is_animating = false
	_start_idle_dance()

func play_attack_anim(target_pos: Vector2) -> void:
	_stop_idle_dance()
	is_animating = true
	set_state("attacking")
	var origin := position
	var lunge := origin + (target_pos - origin) * 0.4
	var tween := create_tween().set_parallel(false)
	tween.tween_property(self, "scale", Vector2(1.15, 1.15), 0.06)
	tween.tween_property(self, "position", lunge, 0.1)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position", origin, 0.12)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.06)
	await tween.finished
	set_state("idle")
	is_animating = false
	_start_idle_dance()

func play_defense_anim() -> void:
	_stop_idle_dance()
	is_animating = true
	set_state("defending")
	var origin := position
	var tween := create_tween().set_parallel(false)
	tween.tween_property(self, "position", origin + Vector2(6, 0), 0.07)
	tween.tween_property(self, "position", origin + Vector2(-6, 0), 0.07)
	tween.tween_property(self, "position", origin + Vector2(6, 0), 0.07)
	tween.tween_property(self, "position", origin + Vector2(-6, 0), 0.07)
	tween.tween_property(self, "position", origin, 0.05)
	await tween.finished
	set_state("idle")
	is_animating = false
	_start_idle_dance()

func play_death_anim() -> void:
	_stop_idle_dance()
	is_animating = true
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.45).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "scale", Vector2(0.0, 0.0), 0.45).set_trans(Tween.TRANS_CUBIC)
	await tween.finished
	is_animating = false
	queue_free()

func select() -> void:
	is_selected = true
	queue_redraw()

func deselect() -> void:
	is_selected = false
	queue_redraw()

func _draw() -> void:
	if is_selected:
		draw_arc(Vector2.ZERO, RADIUS + 4.0, 0.0, TAU, 32, Color.WHITE, 3.0)
