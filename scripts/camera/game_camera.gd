class_name GameCamera
extends Camera2D
## Smooth follow with a small horizontal look-ahead based on facing / velocity,
## plus a decaying trauma shake that nudges `offset` (never the limits), and an
## external decaying jolt written by the Juice autoload via `shake_offset`.

## 视口已是 1280x720；zoom=2.0 让可视范围回到 640x360 世界单位，
## 因此速度/碰撞盒/关卡坐标无需改动，只是每个世界单位渲染成 2x2 像素。
## 改这个值等于改画面取景（WorldScale 不变，看得更多或更少）。
const ZOOM := 1.0
## 1280×720 在 2560×1440（2.5K）上是 2× 整数拉伸。zoom=2 时
## 1 世界单位 = 4 屏幕像素；对齐 0.25 世界单位 = 1 物理像素。
const PIXEL_GRID := 1.0
## 与 Director 宽银幕条同高（viewport 像素），只读、不改 Director。
const LETTER_BAR_PX := 32.0
const LAND_PUNCH_Y := 5.0
const LAND_PUNCH_DECAY := 0.22

@export var follow_speed: float = 7.2
@export var look_ahead: float = 48.0
@export var look_ahead_speed: float = 4.8
@export var vertical_offset: float = -18.0
@export var deadzone: Vector2 = Vector2(16.0, 28.0)
@export var edge_margin: Vector2 = Vector2(52.0, 30.0)

@export var max_shake_offset := Vector2(6.0, 4.5)
@export var max_shake_roll: float = 0.012
@export var trauma_decay: float = 1.9

var _look: float = 0.0
var _vert_look: float = 0.0
var _land_punch: float = 0.0
var _was_air: bool = false
var _air_time: float = 0.0
var _follow: Vector2 = Vector2.ZERO
var _follow_inited: bool = false
var _trauma: float = 0.0
var _noise := FastNoiseLite.new()
var _noise_t := 0.0

## External decaying shake, written by Juice every frame while a jolt is
## active (Vector2.ZERO otherwise). Folded into `offset` in _apply_shake so
## it stacks with the trauma shake instead of stomping it.
var shake_offset := Vector2.ZERO

## Director takeover: when directed, we lerp toward a focus point instead
## of the player. release() hands the lens back.
var _focused: bool = false
var _focus_node: Node2D
var _focus_pos: Vector2 = Vector2.ZERO
var _focus_zoom: float = ZOOM
var _focus_speed: float = 4.0


func _ready() -> void:
	make_current()
	# Camera2D.offset 与世界坐标同空间，会随 zoom 线性放大；但世界内容也同比例放大，
	# 震屏的“相对幅度”不变，所以 max_shake_offset 无需按 ZOOM 补偿。
	zoom = Vector2(ZOOM, ZOOM)
	position_smoothing_enabled = false
	limit_left = 0
	limit_top = 0
	limit_right = 1600
	limit_bottom = 400
	_follow = global_position
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.75
	_noise.seed = randi()
	add_to_group("game_camera")
	GameEvents.hit.connect(_on_hit)
	GameEvents.parried.connect(_on_parried)
	# The chain finisher is a big committed swing — sell it with a shake.
	GameEvents.swing_started.connect(_on_swing_started)
	GameEvents.rusty_gate_melted.connect(_on_gate_melted)
	GameEvents.player_died.connect(_on_player_died)


## Public juice entry point. Strength is clamped to [0, 1].
func add_trauma(strength: float) -> void:
	# 舒适选项：在落手这一刻读 shake_scale（滑块实时生效，不缓存）。
	var scaled := strength * clampf(Settings.shake_scale, 0.0, 1.0)
	_trauma = clampf(maxf(_trauma, scaled), 0.0, 1.0)


func focus(target: Variant, zoom: float = ZOOM, duration: float = 0.55) -> void:
	_focused = true
	_focus_zoom = zoom
	_focus_speed = 1.0 / maxf(duration, 0.08)
	if target is Node2D:
		_focus_node = target
		_focus_pos = (target as Node2D).global_position
	elif target is Vector2:
		_focus_node = null
		_focus_pos = target


func release() -> void:
	_focused = false
	_focus_node = null
	zoom = Vector2(ZOOM, ZOOM)


func snap_to_pixel(v: Vector2) -> Vector2:
	var g := PIXEL_GRID
	return Vector2(roundf(v.x / g) * g, roundf(v.y / g) * g)


func desired_look_ahead(facing: int, vel_x: float, world_y: float) -> float:
	var face := float(facing)
	if face == 0.0:
		face = 1.0
	var idle := face * look_ahead * 0.18
	var ax := absf(vel_x)
	var desired := idle
	if ax > 36.0:
		desired = signf(vel_x) * look_ahead
	elif ax > 12.0:
		var t := clampf((ax - 12.0) / 24.0, 0.0, 1.0)
		desired = lerpf(idle, signf(vel_x) * look_ahead, t)
	if world_y < 200.0:
		var k := clampf((200.0 - world_y) / 88.0, 0.0, 1.0)
		desired *= lerpf(1.0, 0.52, k)
	return desired


func look_ahead_rate(current: float, desired: float, dashing: bool = false) -> float:
	var k := look_ahead_speed
	if current != 0.0 and desired != 0.0 and signf(desired) != signf(current):
		k *= 2.15
	if dashing:
		k *= 1.7
	return k


func deadzone_target(current: Vector2, dest: Vector2) -> Vector2:
	var err := dest - current
	var out := current
	if absf(err.x) > deadzone.x:
		out.x = dest.x - signf(err.x) * deadzone.x
	if absf(err.y) > deadzone.y:
		out.y = dest.y - signf(err.y) * deadzone.y
	return out


func letter_inset() -> float:
	return LETTER_BAR_PX / maxf(zoom.x, 0.001) * _letter_k()


func punch_offset() -> Vector2:
	return Vector2(0.0, LAND_PUNCH_Y * _land_punch * lerpf(1.0, 0.32, _letter_k())
			* clampf(Settings.shake_scale, 0.0, 1.0))


func keep_in_view(cam: Vector2, subject: Vector2) -> Vector2:
	var half := _half_extents()
	var margin := Vector2(edge_margin.x, edge_margin.y + letter_inset())
	var max_off := Vector2(maxf(8.0, half.x - margin.x), maxf(8.0, half.y - margin.y))
	return Vector2(
		clampf(cam.x, subject.x - max_off.x, subject.x + max_off.x),
		clampf(cam.y, subject.y - max_off.y, subject.y + max_off.y)
	)


func _physics_process(delta: float) -> void:
	_land_punch = move_toward(_land_punch, 0.0, delta / LAND_PUNCH_DECAY)
	if _focused:
		_tick_focus(delta)
		_apply_shake(delta)
		return
	zoom = Vector2(ZOOM, ZOOM)
	var target := get_tree().get_first_node_in_group("player") as Player
	if target == null:
		global_position = snap_to_pixel(global_position)
		_apply_shake(delta)
		return
	var airborne := not target.is_on_floor()
	if airborne:
		_air_time += delta
	if _was_air and not airborne:
		_auto_land()
		_air_time = 0.0
	elif not airborne:
		_air_time = 0.0
	_was_air = airborne
	var facing := 1
	var dashing := false
	if target.controller != null:
		facing = target.controller.facing
		dashing = target.controller.is_dashing()
	var desired := desired_look_ahead(facing, target.velocity.x, target.global_position.y)
	_look = lerpf(_look, desired, 1.0 - exp(-look_ahead_rate(_look, desired, dashing) * delta))
	var climb := 0.0
	if target.global_position.y < 200.0:
		var k := clampf((200.0 - target.global_position.y) / 88.0, 0.0, 1.0)
		climb = -22.0 * k * lerpf(1.0, 0.35, _letter_k())
	_vert_look = lerpf(_vert_look, climb, 1.0 - exp(-4.0 * delta))
	var dest := target.global_position + Vector2(0.0, _framed_vertical_offset() + _vert_look)
	if not _follow_inited:
		_follow = dest
		_follow_inited = true
	var fk := follow_speed * (1.65 if dashing else 1.0)
	_follow = _follow.lerp(deadzone_target(_follow, dest), 1.0 - exp(-fk * delta))
	var cam := keep_in_view(_follow + Vector2(_look, 0.0), target.global_position)
	global_position = snap_to_pixel(_clamp_limits(cam))
	_apply_shake(delta)


func notify_landed() -> void:
	_land_punch = 1.0


func land_punch() -> float:
	return _land_punch


func _auto_land() -> void:
	if _air_time < 0.075:
		return
	_land_punch = maxf(_land_punch, clampf(_air_time / 0.30, 0.4, 1.0))


func _tick_focus(delta: float) -> void:
	if _focus_node != null and is_instance_valid(_focus_node):
		_focus_pos = _focus_node.global_position
	if not _follow_inited:
		_follow = global_position
		_follow_inited = true
	var dest := _focus_pos + Vector2(0.0, _framed_vertical_offset())
	_follow = _follow.lerp(dest, 1.0 - exp(-_focus_speed * delta))
	global_position = snap_to_pixel(_follow)
	var z := lerpf(zoom.x, _focus_zoom, 1.0 - exp(-_focus_speed * delta))
	zoom = Vector2(z, z)


func _framed_vertical_offset() -> float:
	return vertical_offset * lerpf(1.0, 0.52, _letter_k())


func _letter_k() -> float:
	return clampf(Director.letterbox_amount(), 0.0, 1.0)


func _half_extents() -> Vector2:
	# The camera always frames the fixed 640x360 world viewport. The display
	# wrapper enlarges that texture after world rendering.
	var vp := Vector2(640.0, 360.0)
	return vp / (2.0 * maxf(zoom.x, 0.001))


func _clamp_limits(pos: Vector2) -> Vector2:
	var half := _half_extents()
	var min_x := float(limit_left) + half.x
	var max_x := float(limit_right) - half.x
	var min_y := float(limit_top) + half.y
	var max_y := float(limit_bottom) - half.y
	if min_x > max_x:
		pos.x = (limit_left + limit_right) * 0.5
	else:
		pos.x = clampf(pos.x, min_x, max_x)
	if min_y > max_y:
		pos.y = (limit_top + limit_bottom) * 0.5
	else:
		pos.y = clampf(pos.y, min_y, max_y)
	return pos


func _apply_shake(delta: float) -> void:
	var punch := punch_offset()
	var letter := _letter_k()
	if _trauma <= 0.0:
		offset = snap_to_pixel(shake_offset + punch)
		rotation = 0.0
		return
	_noise_t += delta * 18.0
	var power := _trauma * _trauma
	var shake_scale := lerpf(1.0, 0.45, letter)
	var shake := Vector2(
		_noise.get_noise_2d(_noise_t, 0.0) * max_shake_offset.x * power,
		_noise.get_noise_2d(_noise_t, 100.0) * max_shake_offset.y * power
	) * shake_scale
	offset = snap_to_pixel(shake_offset + punch + shake)
	# 宽银幕条轴对齐；旋转会从条下漏画，也和 2.5K 整数像素打架。
	if letter > 0.12:
		rotation = 0.0
	else:
		rotation = _noise.get_noise_2d(_noise_t, 200.0) * max_shake_roll * power
	_trauma = maxf(0.0, _trauma - trauma_decay * delta)


func _on_hit(attacker: Node, target: Node, _amount: int) -> void:
	if attacker == null or target == null:
		return
	add_trauma(0.34 if target.is_in_group("player") else 0.18)


func _on_parried(_projectile: Node, _by_actor: Node) -> void:
	add_trauma(0.45)


func _on_swing_started(combo_index: int) -> void:
	if combo_index >= 2:
		add_trauma(0.30)


func _on_gate_melted() -> void:
	add_trauma(0.38)


func _on_player_died() -> void:
	add_trauma(0.55)
