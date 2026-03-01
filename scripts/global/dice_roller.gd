# res://scripts/global/dice_roller.gd
class_name DiceRoller

static func roll(sides: int) -> int:
	return randi_range(1, sides)

static func get_die_sides(adjacent_allies: int) -> int:
	match adjacent_allies:
		0: return 4
		1: return 6
		2: return 8
		3: return 10
		4: return 12
		_: return 20
