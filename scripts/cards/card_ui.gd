# res://scripts/cards/card_ui.gd
extends Button

signal card_selected(index: int)

var card_index: int = 0
var card_type: CardType.Type = CardType.Type.MOVEMENT

const BG_COLORS := {
	CardType.Type.MOVEMENT: Color("#2E7D32"),
	CardType.Type.ATTACK:   Color("#B71C1C"),
	CardType.Type.DEFENSE:  Color("#1565C0"),
}
const LABELS := {
	CardType.Type.MOVEMENT: "MOV",
	CardType.Type.ATTACK:   "ATK",
	CardType.Type.DEFENSE:  "DEF",
}

func _ready() -> void:
	pressed.connect(_on_pressed)

func setup(index: int, type: CardType.Type, face_down: bool = false) -> void:
	card_index = index
	card_type = type
	if face_down:
		text = "?"
		self_modulate = Color(0.35, 0.35, 0.35)
		disabled = true
	else:
		text = LABELS[type]
		self_modulate = BG_COLORS[type]
		disabled = false

func _on_pressed() -> void:
	card_selected.emit(card_index)
