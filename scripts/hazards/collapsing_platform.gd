class_name CollapsingPlatform
extends SolidPlatform
## 塌陷台：骑士踩上去先抖，抖完就塌，隔一会儿原样长回来（锈梁 / 塌瓦 / 断桥）。
##
## 继承 SolidPlatform，所以皮肤、碰撞、遮光、LevelSanity 的台面统计都照旧；只多了
##   IDLE → SHAKING → FALLEN → RETURNING 一条时间线。规则：
##   · 抖动时间 `shake_time` 足够跑过一整块台（默认 0.6s），"别停"才是教学，不是陷阱；
##   · 塌下去后碰撞关闭、贴片坠落淡出，`respawn_time` 后在原位淡入；骑士还站在原位上方
##     的实体范围里时先不长回来，不把人卡进砖里；
##   · 余烬巢 / 压板 / 出口 / 锈门不得以它为唯一支撑（LevelSanity 拒绝）；
##   · 会话内表现，不写存档，读档 / 重进关卡一律是完好的。

enum State { IDLE, SHAKING, FALLEN, RETURNING }

signal collapsed
signal restored

const GROUP := &"hazards"
const SENSOR_HEIGHT := 8.0
const FALL_GRAVITY := 900.0
const RETURN_TIME := 0.35
const MIN_SHAKE := 0.5

@export var shake_time: float = 0.6
@export var fall_time: float = 0.45
@export var respawn_time: float = 4.0
## 首遇提示键（HintService.CATALOG）；空 = 不放。
@export var hint_id: StringName = &"collapse"

var _state: int = State.IDLE
var _timer := 0.0
var _fall_t := 0.0
var _vt := 0.0
var _dust_cd := 0.0
var _skin_root: Node2D
var _sensor: Area2D
var _collision_shapes: Array[CollisionShape2D] = []


func _ready() -> void:
	super._ready()
	add_to_group(GROUP)
	add_to_group(&"collapsing")
	set_meta("hazard_kind", "collapsing")
	shake_time = maxf(MIN_SHAKE, shake_time)
	_collect_collision_shapes()
	_wrap_visuals()
	_build_sensor()
	if hint_id != &"":
		HazardFx.attach_hint(self, hint_id, Rect2(0.0, -28.0, size.x, 28.0), Vector2(96.0, 36.0))


## 父类重画贴片时会把新精灵直接挂在自己下面：先清旧容器，让父类画，再收进容器。
func apply_tone(new_tone: Color) -> void:
	if _skin_root != null:
		for child in _skin_root.get_children():
			_skin_root.remove_child(child)
			child.free()
	super.apply_tone(new_tone)
	_wrap_visuals()


func state() -> int:
	return _state


func is_collapsed() -> bool:
	return _state == State.FALLEN


func is_solid() -> bool:
	return _state != State.FALLEN


func time_left() -> float:
	return _timer


## 顶面中心（世界坐标）。
func top_center() -> Vector2:
	return global_position + Vector2(size.x * 0.5, 0.0)


func _collect_collision_shapes() -> void:
	_collision_shapes.clear()
	for child in get_children():
		if child is CollisionShape2D:
			_collision_shapes.append(child as CollisionShape2D)


func _wrap_visuals() -> void:
	if _skin_root == null:
		_skin_root = Node2D.new()
		_skin_root.name = "Skin"
		add_child(_skin_root)
	for child in get_children():
		if child == _skin_root:
			continue
		if child is Sprite2D or child is ColorRect:
			remove_child(child)
			_skin_root.add_child(child)


func _build_sensor() -> void:
	_sensor = Area2D.new()
	_sensor.name = "Sensor"
	_sensor.collision_layer = 0
	_sensor.collision_mask = 2
	_sensor.monitoring = true
	_sensor.monitorable = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(maxf(4.0, size.x - 4.0), SENSOR_HEIGHT)
	shape.shape = rect
	shape.position = Vector2(size.x * 0.5, -SENSOR_HEIGHT * 0.25)
	_sensor.add_child(shape)
	add_child(_sensor)


func _physics_process(delta: float) -> void:
	tick(delta)


## 推进 delta 秒（测试可直接驱动，不依赖物理帧）。
func tick(delta: float) -> void:
	_vt += delta
	match _state:
		State.IDLE:
			if _player_on_top():
				trigger()
		State.SHAKING:
			_timer -= delta
			_apply_shake()
			_dust_cd -= delta
			if _dust_cd <= 0.0:
				_dust_cd = 0.18
				Fx.dust_puff(top_center())
			if _timer <= 0.0:
				_fall()
		State.FALLEN:
			_fall_t += delta
			_apply_fall()
			_timer -= delta
			if _timer <= 0.0 and not _player_inside_body():
				_begin_return()
		State.RETURNING:
			_timer -= delta
			_apply_return()
			if _timer <= 0.0:
				_finish_return()


## 开始抖。返回是否真的开始了（已经在抖 / 已塌时不重复）。
func trigger() -> bool:
	if _state != State.IDLE:
		return false
	_state = State.SHAKING
	_timer = shake_time
	_dust_cd = 0.0
	HazardFx.play("collapse", "warn", top_center(), -8.0)
	return true


func _fall() -> void:
	_state = State.FALLEN
	_fall_t = 0.0
	_timer = respawn_time
	_set_collision(false)
	if _skin_root != null:
		_skin_root.position = Vector2.ZERO
	var center := global_position + size * 0.5
	HazardFx.play("collapse", "fire", center, -4.0)
	Fx.burst(&"stone", center)
	Fx.burst(&"dust", center)
	collapsed.emit()


func _begin_return() -> void:
	_state = State.RETURNING
	_timer = RETURN_TIME
	_fall_t = 0.0
	if _skin_root != null:
		_skin_root.position = Vector2.ZERO
		_skin_root.visible = true
		_skin_root.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_set_collision(true)


func _finish_return() -> void:
	_state = State.IDLE
	_timer = 0.0
	if _skin_root != null:
		_skin_root.position = Vector2.ZERO
		_skin_root.modulate = Color.WHITE
	restored.emit()


func _set_collision(enabled: bool) -> void:
	for shape in _collision_shapes:
		if is_instance_valid(shape):
			shape.set_deferred("disabled", not enabled)
	var occluder := get_node_or_null("LightOccluder") as LightOccluder2D
	if occluder != null:
		occluder.visible = enabled


func _apply_shake() -> void:
	if _skin_root == null:
		return
	var k := 1.0 - clampf(_timer / maxf(MIN_SHAKE, shake_time), 0.0, 1.0)
	var x := roundf(sin(_vt * 70.0) * (1.0 if k < 0.5 else 2.0) * 0.5)
	var y := roundf(sin(_vt * 53.0 + 1.3)) if k > 0.5 else 0.0
	_skin_root.position = Vector2(x, y)


func _apply_fall() -> void:
	if _skin_root == null:
		return
	_skin_root.position = Vector2(0.0, 0.5 * FALL_GRAVITY * _fall_t * _fall_t)
	var a := 1.0 - clampf(_fall_t / maxf(0.05, fall_time), 0.0, 1.0)
	_skin_root.modulate = Color(1.0, 1.0, 1.0, a)
	_skin_root.visible = a > 0.01


func _apply_return() -> void:
	if _skin_root == null:
		return
	var a := 1.0 - clampf(_timer / RETURN_TIME, 0.0, 1.0)
	var flash := 1.0 + 0.8 * (1.0 - a)
	_skin_root.modulate = Color(flash, flash, flash, a)


## 骑士站在顶面上（传感器贴着顶面 8px 厚的一条）。
func _player_on_top() -> bool:
	if _sensor == null:
		return false
	for body in _sensor.get_overlapping_bodies():
		if not (body is CharacterBody2D) or not body.is_in_group(&"player"):
			continue
		var knight := body as CharacterBody2D
		if knight.is_on_floor() or knight.velocity.y >= -5.0:
			return true
	return false


## 骑士身体压在台体范围里（不含顶面这一条）：长回来会卡进砖里，先等一等。
func _player_inside_body() -> bool:
	if not is_inside_tree():
		return false
	var space := get_world_2d().direct_space_state
	if space == null:
		return false
	var rect := RectangleShape2D.new()
	rect.size = Vector2(maxf(2.0, size.x - 2.0), maxf(2.0, size.y - 4.0))
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = rect
	query.transform = Transform2D(0.0, global_position + Vector2(size.x * 0.5, 2.0 + (size.y - 4.0) * 0.5))
	query.collision_mask = 2
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return not space.intersect_shape(query, 4).is_empty()


## 现在踏上台面并停留 duration 秒，台面是否始终有实体支撑；查询不触发塌陷。
func safe_window(duration: float = 0.0) -> bool:
	var stay := maxf(0.0, duration)
	match _state:
		State.IDLE:
			return stay < maxf(MIN_SHAKE, shake_time)
		State.SHAKING:
			return stay < _timer
		State.RETURNING:
			return stay < _timer + maxf(MIN_SHAKE, shake_time)
	return false
