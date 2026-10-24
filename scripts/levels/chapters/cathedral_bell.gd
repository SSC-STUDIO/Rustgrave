extends Node2D
## A cathedral bell shares its timing with the ground wave. Damage remains in CyclicHazard.
var wave: CyclicHazard
var _swing := 0.0


func _ready() -> void:
	z_index = -2
	if wave != null:
		wave.state_changed.connect(_on_state_changed)
	queue_redraw()


func _on_state_changed(_state: int) -> void:
	queue_redraw()


func _process(_delta: float) -> void:
	if not is_instance_valid(wave):
		return
	var t := wave.clock()
	_swing = sin(t * 12.0) * (4.0 if wave.is_warning() else 1.0)
	queue_redraw()


func ringing() -> bool:
	return is_instance_valid(wave) and (wave.is_warning() or wave.is_active())


func _draw() -> void:
	# Floor bells hang above the singing gallery; gallery bells hang lower so the
	# full silhouette remains inside the world camera's top edge.
	var y := -112.0 if global_position.y < 256.0 else -192.0
	var x := roundf(_swing)
	var chain_top := -global_position.y + 4.0
	draw_line(Vector2(0, chain_top), Vector2(x, y - 30), Color("#5c4e66"), 2.0)
	var bronze := Color("#8d7555")
	var edge := Color("#d6b77a") if ringing() else Color("#aa9676")
	draw_rect(Rect2(x - 6, y - 29, 12, 8), bronze)
	draw_rect(Rect2(x - 10, y - 21, 20, 10), bronze)
	draw_rect(Rect2(x - 15, y - 11, 30, 11), bronze)
	draw_rect(Rect2(x - 15, y - 11, 3, 11), edge)
	draw_rect(Rect2(x - 18, y - 3, 36, 4), edge)
	draw_rect(Rect2(x - 2, y - 8, 4, 11), Color("#3a2c39"))
	if ringing():
		for side in [-1.0, 1.0]:
			draw_line(Vector2(x + side * 22, y - 20), Vector2(x + side * 25, y - 25), edge, 1)
			draw_line(Vector2(x + side * 24, y - 8), Vector2(x + side * 30, y - 8), edge, 1)
