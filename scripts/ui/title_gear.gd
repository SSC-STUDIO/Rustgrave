class_name TitleGear
extends Sprite2D
## A big slow gear for the title hall. The art is a pre-rendered grid of rotation
## frames covering exactly one spoke period (tools/gen_title_assets.py), so the
## loop is seamless and nothing is rotated at runtime: a rotated pixel sprite
## breaks its pixels, a frame swap never does.

var period_degrees := 45.0
## Degrees per second at speed_mult 1.0 (always advances the frame index; each
## strip was rendered with its own turning direction).
var speed := 4.0
var speed_mult := 1.0

var _angle := 0.0
var _frame_count := 1


## `path` is the grid texture, `columns` x `rows` its layout, `frames` how many
## cells hold a frame, `period` the rotation (degrees) the frames span.
func setup(path: String, columns: int, rows: int, frames: int, period: float,
		deg_per_second: float, start_degrees: float = 0.0) -> bool:
	var tex := load(path) as Texture2D
	if tex == null:
		return false
	texture = tex
	hframes = columns
	vframes = rows
	_frame_count = maxi(frames, 1)
	period_degrees = period
	speed = deg_per_second
	_angle = fposmod(start_degrees, period)
	centered = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sync_frame()
	return true


func frame_count() -> int:
	return _frame_count


func angle() -> float:
	return _angle


func _process(delta: float) -> void:
	if speed_mult <= 0.0:
		return
	_angle = fposmod(_angle + speed * speed_mult * delta, period_degrees)
	_sync_frame()


func _sync_frame() -> void:
	var f := int(_angle / period_degrees * float(_frame_count)) % _frame_count
	if f != frame:
		frame = f
