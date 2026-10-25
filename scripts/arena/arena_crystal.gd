extends "res://scripts/arena/arena_tower.gd"
## 水晶。两座塔都倒之前伤害被护盾吃掉。


func _ready() -> void:
	unit_kind = "crystal"
	role = "crystal"
	if structure_index < 0:
		structure_index = 2
	super()
