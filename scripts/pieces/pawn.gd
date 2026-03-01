# res://scripts/pieces/pawn.gd
extends Node2D

var team: int = 1
var board_pos: Vector2i = Vector2i.ZERO
var pawn_color: Color = Color("#4A90D9")
var is_selected: bool = false

const RADIUS := 26.0

func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, pawn_color)
	if is_selected:
		draw_arc(Vector2.ZERO, RADIUS + 4.0, 0.0, TAU, 32, Color.WHITE, 3.0)

func select() -> void:
	is_selected = true
	queue_redraw()

func deselect() -> void:
	is_selected = false
	queue_redraw()
