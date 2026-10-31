extends Camera3D
## Orthographic follow camera for the 3D pixel mode. Its position is snapped to
## whole render texels on the camera plane, so static geometry rasterises the
## same way every frame; the leftover sub-texel offset is handed to the stage,
## which shifts the upscaled image instead.

const PIXEL_STAGE := preload("res://scripts/moba/view/pixel_stage.gd")
const PITCH_DEG := -55.0
const DISTANCE := 40.0

var stage: PIXEL_STAGE
var target: Node3D
## Ground point the camera looks at (smoothed toward the target).
var focus := Vector3.ZERO
## World metres covered by the visible texel rows.
var view_height := 13.0
var smoothing := 9.0
var snap_enabled := true

var _shake := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	projection = Camera3D.PROJECTION_ORTHOGONAL
	keep_aspect = Camera3D.KEEP_HEIGHT
	near = 0.05
	far = 120.0
	rotation_degrees = Vector3(PITCH_DEG, 0.0, 0.0)
	# Followers move first; the camera reads their final position each frame.
	process_priority = 100
	_rng.seed = 7
	if is_instance_valid(target):
		focus = _ground(target.global_position)
	make_current()


func _process(delta: float) -> void:
	if is_instance_valid(target):
		var goal := _ground(target.global_position)
		focus = focus.lerp(goal, 1.0 - exp(-smoothing * delta)) if smoothing > 0.0 else goal
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 0.8)
	apply_view()


func apply_view() -> void:
	if stage == null:
		return
	var t := texel_world()
	size = t * float(stage.internal_size.y + PIXEL_STAGE.MARGIN * 2)
	var b := global_transform.basis
	var desired := focus + b.z * DISTANCE + _shake_offset(b)
	if not snap_enabled:
		global_position = desired
		stage.set_camera_offset(Vector2.ZERO, Vector2i.ZERO)
		return
	var lx := desired.dot(b.x) / t
	var ly := desired.dot(b.y) / t
	var lz := desired.dot(b.z)
	var ix := roundf(lx)
	var iy := roundf(ly)
	global_position = b.x * (ix * t) + b.y * (iy * t) + b.z * lz
	stage.set_camera_offset(Vector2(lx - ix, iy - ly), Vector2i(int(ix), int(-iy)))


## World metres per render texel on the camera plane.
func texel_world() -> float:
	return view_height / float(maxi(stage.internal_size.y, 1))


## Offset that moves `p` onto the camera's texel grid (keeps its depth), so a
## moving unit rasterises identically to its last position, only shifted.
func snap_offset(p: Vector3) -> Vector3:
	var t := texel_world()
	var b := global_transform.basis
	var lx := p.dot(b.x) / t
	var ly := p.dot(b.y) / t
	return b.x * ((roundf(lx) - lx) * t) + b.y * ((roundf(ly) - ly) * t)


func zoom_by(step: float) -> void:
	view_height = clampf(view_height + step, 8.0, 24.0)


func add_shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _shake_offset(b: Basis) -> Vector3:
	# Read comfort at display time: disabling shake also removes a live impact.
	var strength := _shake * Settings.shake_scale
	if strength <= 0.0:
		return Vector3.ZERO
	return (b.x * _rng.randf_range(-1.0, 1.0) + b.y * _rng.randf_range(-1.0, 1.0)) * strength


static func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, 0.0, p.z)
