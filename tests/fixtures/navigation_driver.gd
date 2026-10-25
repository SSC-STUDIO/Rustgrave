extends "res://tools/input_walkthrough.gd"
## Local physics fixture: suppress campaign startup, keep production input crossing.
var world: Node


func _ready() -> void:
	pass


func _process(_delta: float) -> void:
	pass


func _world_root() -> Node:
	return world
