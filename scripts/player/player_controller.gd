class_name PlayerController
extends Node
## Heavy-momentum locomotion for the Ember-Knight.
## Variable acceleration (not snappy), gravity-scaled fall, gated extra jump, dash i-frames.

signal dashed
signal jumped(is_extra: bool)

@export_group("Move")
@export var max_speed: float = 108.0
@export var acceleration: float = 400.0
@export var deceleration: float = 420.0
@export var air_acceleration: float = 270.0
@export var air_deceleration: float = 130.0

@export_group("Jump")
@export var jump_velocity: float = -268.0
@export var extra_jumps: int = 1
@export var extra_jumps_unlocked: bool = false
@export var extra_jump_scale: float = 0.92
@export var fall_gravity_scale: float = 1.85
@export var jump_cut_gravity_scale: float = 2.15
@export var jump_cut_delay: float = 0.07
@export var apex_window: float = 16.0
@export var apex_gravity_scale: float = 0.62
@export var max_fall_speed: float = 420.0
@export var coyote_time: float = CombatRules.COYOTE_TIME
@export var jump_buffer_time: float = CombatRules.JUMP_BUFFER
@export var land_probe: float = 12.0
@export var land_grip_time: float = 0.08

@export_group("Dash")
@export var dash_speed: float = 236.0
@export var dash_duration: float = CombatRules.DASH_DURATION
@export var dash_cooldown: float = CombatRules.DASH_COOLDOWN
@export var iframe_duration: float = CombatRules.DASH_IFRAMES
@export var air_dashes: int = 1
## 冲刺预输入：按早了（后摇取消窗口 / 冷却 / 空中无次数）不丢，最多等这么久。
@export var dash_buffer_time: float = CombatRules.DASH_BUFFER

## 事件线程里记下的按键只在这么多个物理帧内有效（见 MeleeCombat.LATCH_TICKS）。
const LATCH_TICKS := 6

## 提交锁（挥砍中）期间冲刺的闸门：由 MeleeCombat 注入 can_dash_cancel。
## 无效 / 返回 false 时冲刺被预输入攒着，等窗口打开。
var dash_cancel_gate: Callable = Callable()

var facing: int = 1
var _coyote: float = 0.0
var _buffer: float = 0.0
var _jumps_left: int = 0
var _dash_timer: float = 0.0
var _dash_cd: float = 0.0
var _iframe: float = 0.0
var _air_dashes_left: int = 0
var _dash_dir: float = 1.0
var _commit_lock: bool = false
var _cut_lock: float = 0.0
var _cut_armed: bool = false
var _land_grip: float = 0.0
var _was_floor: bool = false
var _floor_snap: float = 4.0
var _dash_buffer: float = 0.0
var _jump_latched_tick: int = -1000
var _dash_latched_tick: int = -1000


## 短按在两个物理帧之间按下又松开（顿帧 / 低帧率）时，Input.is_action_just_pressed
## 会看漏；事件线程先记一笔，下一个物理帧补收。触控走 Input.action_press（无事件），
## 仍由轮询覆盖。
func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"jump"):
		_jump_latched_tick = Engine.get_physics_frames()
	if event.is_action_pressed(&"dash"):
		_dash_latched_tick = Engine.get_physics_frames()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		clear_buffers()


func _take_latch(latched_tick: int) -> bool:
	return Engine.get_physics_frames() - latched_tick <= LATCH_TICKS


## 清空预输入（暂停 / 过场 / 重生边界）。
func clear_buffers() -> void:
	_buffer = 0.0
	_dash_buffer = 0.0
	_jump_latched_tick = -1000
	_dash_latched_tick = -1000


func dash_buffered() -> float:
	return _dash_buffer


func is_dashing() -> bool:
	return _dash_timer > 0.0


func is_invincible() -> bool:
	return _iframe > 0.0


func set_commit_lock(locked: bool) -> void:
	_commit_lock = locked


func grant_air_jump() -> void:
	_jumps_left = maxi(_jumps_left, 1)


func physics_tick(body: CharacterBody2D, delta: float, move_scale: float) -> void:
	if _dash_cd > 0.0:
		_dash_cd = maxf(0.0, _dash_cd - delta)
	if _iframe > 0.0:
		_iframe = maxf(0.0, _iframe - delta)

	var on_floor := body.is_on_floor()
	if on_floor:
		if not _was_floor:
			_land_grip = land_grip_time
		_coyote = coyote_time
		_jumps_left = extra_jumps if extra_jumps_unlocked else 0
		_air_dashes_left = air_dashes
		_cut_armed = false
		if body.floor_snap_length <= 0.0:
			body.floor_snap_length = _floor_snap
	else:
		_coyote = maxf(0.0, _coyote - delta)
	_was_floor = on_floor

	var jump_latched := _take_latch(_jump_latched_tick)
	var dash_latched := _take_latch(_dash_latched_tick)
	_jump_latched_tick = -1000
	_dash_latched_tick = -1000
	if Input.is_action_just_pressed("jump") or jump_latched:
		_buffer = jump_buffer_time
	elif not is_dashing():
		# Dash lasts longer than a tap-buffer; freeze the window so a jump
		# pressed mid-dash still fires on the first grounded/airborne tick after.
		_buffer = maxf(0.0, _buffer - delta)
	if Input.is_action_just_pressed("dash") or dash_latched:
		_dash_buffer = dash_buffer_time
	else:
		_dash_buffer = maxf(0.0, _dash_buffer - delta)

	if is_dashing():
		_dash_timer = maxf(0.0, _dash_timer - delta)
		body.velocity.x = _dash_dir * _dash_speed_for(body)
		body.velocity.y = 0.0
		return

	_apply_gravity(body, delta)

	# 挥砍提交锁期间冲刺只在取消窗口里放行（前摇 / 判定期永远不放行）；
	# 按早了的冲刺攒在预输入里，窗口一开立刻出，从不缩短已承诺的阶段。
	if _dash_buffer > 0.0 and _dash_gate_open() and _try_dash(body):
		_dash_buffer = 0.0

	if _buffer > 0.0:
		_try_jump(body)

	var axis := Input.get_axis("move_left", "move_right")
	axis = _axis_away_from_wall(body, axis)
	_apply_move(body, axis, delta, move_scale)

	if absf(axis) > 0.2:
		facing = 1 if axis > 0.0 else -1


## Zero residual into-wall speed after move_and_slide. Box colliders otherwise
## keep a sliver of vx and "glue" to walls at ZOOM=2. Rising along a lip is
## how you climb a pit bank — keep the approach so a 32px hop can land.
func settle_after_slide(body: CharacterBody2D) -> void:
	if body.is_on_floor() or not body.is_on_wall():
		return
	if body.velocity.y < 0.0:
		return
	var n := body.get_wall_normal()
	if absf(n.x) < 0.45:
		return
	if body.velocity.x * n.x < 0.0:
		body.velocity.x = 0.0


func _axis_away_from_wall(body: CharacterBody2D, axis: float) -> float:
	if body.is_on_floor() or not body.is_on_wall() or absf(axis) <= 0.05:
		return axis
	if body.velocity.y < 0.0:
		return axis
	var n := body.get_wall_normal()
	if absf(n.x) < 0.45:
		return axis
	if signf(axis) == -signf(n.x):
		return 0.0
	return axis


func _apply_gravity(body: CharacterBody2D, delta: float) -> void:
	if _cut_lock > 0.0:
		_cut_lock = maxf(0.0, _cut_lock - delta)
	var gravity: float = float(ProjectSettings.get_setting("physics/2d/default_gravity"))
	var scale := 1.0
	if absf(body.velocity.y) < apex_window:
		scale = apex_gravity_scale
	elif body.velocity.y > 0.0:
		scale = fall_gravity_scale
	elif _cut_armed and _cut_lock <= 0.0 and not Input.is_action_pressed("jump") \
			and body.velocity.y < 0.0:
		scale = jump_cut_gravity_scale
	body.velocity.y += gravity * scale * delta
	if body.velocity.y > max_fall_speed:
		body.velocity.y = max_fall_speed


var stats: Object = null


func _speed_multiplier_for(body: CharacterBody2D) -> float:
	if stats != null and stats.has_method(&"get_speed_multiplier"):
		return clampf(float(stats.get_speed_multiplier()), 0.1, 3.0)
	if body != null and "stats" in body and body.stats != null and body.stats.has_method(&"get_speed_multiplier"):
		return clampf(float(body.stats.get_speed_multiplier()), 0.1, 3.0)
	return 1.0


func _apply_move(body: CharacterBody2D, axis: float, delta: float, move_scale: float) -> void:
	var on_floor := body.is_on_floor()
	var spd_mult := _speed_multiplier_for(body)
	var target := axis * max_speed * spd_mult * move_scale
	var accel := acceleration if on_floor else air_acceleration
	var decel := deceleration if on_floor else air_deceleration
	if _land_grip > 0.0:
		decel *= 1.85
		_land_grip = maxf(0.0, _land_grip - delta)
	if _commit_lock:
		accel *= 0.35
		decel *= 0.8
		target *= 0.45

	if absf(axis) > 0.05:
		var turning := signf(axis) != signf(body.velocity.x) and absf(body.velocity.x) > 8.0
		var rate := accel * (1.55 if turning else 1.0)
		body.velocity.x = move_toward(body.velocity.x, target, rate * delta)
	else:
		body.velocity.x = move_toward(body.velocity.x, 0.0, decel * delta)


func _try_jump(body: CharacterBody2D) -> void:
	if _coyote > 0.0:
		_do_jump(body, false)
		return
	# extra_jumps_unlocked 填地上刷新的次数；grant_air_jump() 可在空中临时加一条。
	if _jumps_left > 0 and not body.is_on_floor():
		# Falling onto a floor within land_probe: keep the buffer for the
		# landing jump instead of burning the extra charge 1–2 frames early.
		if body.velocity.y > 0.0 and _near_floor(body):
			return
		_jumps_left -= 1
		_do_jump(body, true)


func _near_floor(body: CharacterBody2D) -> bool:
	return body.test_move(body.global_transform, Vector2(0.0, land_probe))


func _do_jump(body: CharacterBody2D, is_extra: bool) -> void:
	_buffer = 0.0
	_coyote = 0.0
	_cut_armed = true
	_cut_lock = jump_cut_delay
	if body.floor_snap_length > 0.0:
		_floor_snap = body.floor_snap_length
	body.floor_snap_length = 0.0
	var power := jump_velocity
	if is_extra:
		power *= extra_jump_scale
	body.velocity.y = power
	jumped.emit(is_extra)
	GameEvents.jumped.emit(is_extra)
	Sfx.play(&"jump")


func _dash_gate_open() -> bool:
	if not _commit_lock:
		return true
	return dash_cancel_gate.is_valid() and bool(dash_cancel_gate.call())


## 毒素档位的冲刺倍率（温档起 +12%，读 CombatRules.TOXIN_TIERS）。
func _dash_speed_for(body: CharacterBody2D) -> float:
	var speed := dash_speed
	if body is Player:
		speed *= float(CombatRules.toxin_tier((body as Player).toxin.band())["dash"])
	speed *= _speed_multiplier_for(body)
	return speed


## 返回 true = 冲刺真的开始了（调用方据此消耗预输入）。
func _try_dash(body: CharacterBody2D) -> bool:
	if _dash_cd > 0.0:
		return false
	if not body.is_on_floor() and _air_dashes_left <= 0:
		return false
	if not body.is_on_floor():
		_air_dashes_left -= 1

	var axis := Input.get_axis("move_left", "move_right")
	if absf(axis) > 0.2:
		_dash_dir = signf(axis)
		facing = int(_dash_dir)
	else:
		_dash_dir = float(facing)

	_dash_timer = dash_duration
	_dash_cd = dash_cooldown
	_iframe = iframe_duration
	body.velocity.x = _dash_dir * _dash_speed_for(body)
	body.velocity.y = 0.0
	dashed.emit()
	GameEvents.dash_performed.emit()
	Sfx.play(&"dash")
	return true
