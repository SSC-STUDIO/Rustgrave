class_name CandleBridge
extends SolidPlatform
## 烛光桥：平时无碰撞、只留半透明剪影的幽暗石台；骑士靠近关联烛台（~48px）或挥剑斩击烛台时
## 点燃烛火，桥面在 `lit_time`（默认 6s）内化为实心可站台面，熄灭前 `warn_time` 秒闪烁预警，
## 烛灭台灭，再次靠近或挥砍可重新点燃。
##
## 规则（docs/overhaul-v3-agents/g3.md & docs/level_authoring.md §8）：
##   · 继承 SolidPlatform，进 `hazards` 组并带 `hazard_kind="candle"` 元数据；
##   · LevelSanity 将桥面按可站台面计入主线可达（allow_hook=false），但拒绝将其作为
##     余烬巢 / 压板 / 出口 / 门 / 碑的支撑，且烛台离余烬巢 ≥40px；
##   · 桥面消失时脚下必须是安全石台/地面（不死、不软锁，且有路返回烛台重燃）；
##   · 过场锁玩家（Director.is_input_locked()）时冻结倒计时。

enum State { UNLIT, LIT }

signal ignited
signal extinguished

const GROUP := &"hazards"
const DEFAULT_LIT_TIME := 6.0
const MIN_LIT_TIME := 2.0
const DEFAULT_WARN_TIME := 1.2
const MIN_WARN_TIME := 0.5
const DEFAULT_LIGHT_RADIUS := 48.0
const UNLIT_MODULATE := Color(0.76, 0.72, 0.96, 0.28)
const LIT_MODULATE := Color(1.06, 0.96, 0.82, 1.0)

## 关联烛台的世界坐标（脚点）；若为 ZERO 则默认放在桥面西侧。
@export var candle_pos: Vector2 = Vector2.ZERO
@export var lit_time: float = DEFAULT_LIT_TIME
@export var warn_time: float = DEFAULT_WARN_TIME
@export var light_radius: float = DEFAULT_LIGHT_RADIUS
@export var start_lit: bool = false
## 首遇提示键（HintService.CATALOG）；空 = 不放。
@export var hint_id: StringName = &"candle"

var _state: int = State.UNLIT
var _timer := 0.0
var _vt := 0.0
var _skin_root: Node2D
var _candle: Area2D
var _silhouette: Node2D
var _collision_shapes: Array[CollisionShape2D] = []


func _ready() -> void:
	super._ready()
	add_to_group(GROUP)
	add_to_group(&"candle_bridges")
	set_meta("hazard_kind", "candle")
	lit_time = maxf(MIN_LIT_TIME, lit_time)
	warn_time = clampf(warn_time, MIN_WARN_TIME, lit_time * 0.6)
	light_radius = maxf(16.0, light_radius)
	if candle_pos == Vector2.ZERO:
		candle_pos = position + Vector2(-24.0, 0.0)
	_collect_collision_shapes()
	_wrap_visuals()
	_build_silhouette()
	_build_candle()
	if hint_id != &"":
		var c_local := candle_pos - position
		var bridge_rect := Rect2(0.0, -28.0, size.x, 28.0 + size.y)
		var candle_rect := Rect2(c_local - Vector2(light_radius, light_radius),
				Vector2(light_radius * 2.0, light_radius * 2.0))
		HazardFx.attach_hint(self, hint_id, bridge_rect.merge(candle_rect), Vector2(64.0, 28.0))
	if start_lit:
		_state = State.LIT
		_timer = lit_time
		_set_collision(true)
	else:
		_state = State.UNLIT
		_timer = 0.0
		_set_collision(false)
	_apply_visual()


func apply_tone(new_tone: Color) -> void:
	if _skin_root != null:
		for child in _skin_root.get_children():
			_skin_root.remove_child(child)
			child.free()
	super.apply_tone(new_tone)
	_wrap_visuals()
	_apply_visual()


func state() -> int:
	return _state


func is_lit() -> bool:
	return _state == State.LIT


func is_solid() -> bool:
	return _state == State.LIT


func is_warning() -> bool:
	return _state == State.LIT and _timer > 0.0 and _timer <= warn_time


func time_left() -> float:
	return _timer


func candle_area() -> Area2D:
	return _candle


func candle_global_position() -> Vector2:
	if _candle != null and is_instance_valid(_candle) and _candle.is_inside_tree():
		return _candle.global_position
	var parent := get_parent() as Node2D
	if parent != null and parent.is_inside_tree():
		return parent.to_global(candle_pos)
	return candle_pos


## 点燃（或续燃）烛台，使桥面在 `lit_time` 秒内实心。返回是否是从熄灭转为点燃。
func ignite() -> bool:
	var was_unlit := _state != State.LIT
	_state = State.LIT
	_timer = maxf(MIN_LIT_TIME, lit_time)
	_set_collision(true)
	_apply_visual()
	if was_unlit:
		if is_inside_tree():
			HazardFx.play("flame", "warn", candle_global_position(), -8.0)
			Fx.burst(&"ember", candle_global_position() + Vector2(0.0, -14.0))
		ignited.emit()
	return was_unlit


## 熄灭烛台，桥面恢复无碰撞半透明剪影。
func extinguish() -> void:
	if _state == State.UNLIT and _timer <= 0.0:
		_set_collision(false)
		_apply_visual()
		return
	_state = State.UNLIT
	_timer = 0.0
	_set_collision(false)
	_apply_visual()
	if is_inside_tree():
		Fx.dust_puff(global_position + size * 0.5)
	extinguished.emit()


func _physics_process(delta: float) -> void:
	tick(delta)


## 推进 delta 秒（测试可直接调用）。
func tick(delta: float) -> void:
	if Director != null and Director.is_input_locked():
		return
	_vt += delta
	if _check_ignition_sources():
		ignite()
	elif _state == State.LIT:
		_timer -= delta
		if _timer <= 0.0:
			extinguish()
			return
	_apply_visual()


func _check_ignition_sources() -> bool:
	if _candle == null or not is_instance_valid(_candle):
		return false
	if _candle.monitoring:
		for body in _candle.get_overlapping_bodies():
			if body is CharacterBody2D and body.is_in_group(&"player"):
				return true
		for area in _candle.get_overlapping_areas():
			if _is_igniting_area(area):
				return true
	if is_inside_tree() and get_tree() != null:
		var cpos := candle_global_position()
		for node in get_tree().get_nodes_in_group(&"player"):
			if node is Node2D and is_instance_valid(node):
				var ppos := (node as Node2D).global_position
				# 骑士原点在脚底或身体中心，取水平与垂直综合距离。
				if ppos.distance_to(cpos) <= light_radius \
						or (ppos + Vector2(0.0, -14.0)).distance_to(cpos + Vector2(0.0, -10.0)) <= light_radius:
					return true
	return false


func _is_igniting_area(area: Area2D) -> bool:
	if area == null or not is_instance_valid(area):
		return false
	if area is Hitbox:
		var box := area as Hitbox
		return box.monitoring and box.team == &"player"
	if area is Projectile:
		var proj := area as Projectile
		return proj.team == &"player"
	return false


func _on_candle_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D and body.is_in_group(&"player"):
		ignite()


func _on_candle_area_entered(area: Area2D) -> void:
	if _is_igniting_area(area):
		ignite()


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
		if child == _skin_root or child == _candle or child == _silhouette:
			continue
		if child is Sprite2D or child is ColorRect:
			remove_child(child)
			_skin_root.add_child(child)


func _build_silhouette() -> void:
	if _silhouette != null:
		return
	var overlay := BridgeOverlay.new()
	overlay.name = "Silhouette"
	overlay.bridge_size = size
	overlay.owner_bridge = self
	overlay.z_index = 1
	_silhouette = overlay
	add_child(overlay)


func _build_candle() -> void:
	if _candle != null and is_instance_valid(_candle):
		_candle.queue_free()
	var stand := CandleStand.new()
	stand.name = "Candle"
	stand.position = candle_pos - position
	stand.radius = light_radius
	stand.owner_bridge = self
	stand.collision_layer = 0
	stand.collision_mask = 2 | 8 | 16
	stand.monitoring = true
	stand.monitorable = true
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var circle := CircleShape2D.new()
	circle.radius = light_radius
	shape.shape = circle
	shape.position = Vector2(0.0, -10.0)
	stand.add_child(shape)
	stand.body_entered.connect(_on_candle_body_entered)
	stand.area_entered.connect(_on_candle_area_entered)
	_candle = stand
	add_child(stand)


func _set_collision(enabled: bool) -> void:
	for shape in _collision_shapes:
		if is_instance_valid(shape):
			shape.set_deferred("disabled", not enabled)
	var occluder := get_node_or_null("LightOccluder") as LightOccluder2D
	if occluder != null:
		occluder.visible = enabled


func _apply_visual() -> void:
	if _skin_root != null:
		if _state == State.UNLIT:
			_skin_root.modulate = UNLIT_MODULATE
		elif is_warning():
			var pulse := 0.5 + 0.5 * sin(_vt * 26.0)
			var a := lerpf(0.42, 0.98, pulse)
			_skin_root.modulate = Color(LIT_MODULATE.r, LIT_MODULATE.g, LIT_MODULATE.b, a)
		else:
			_skin_root.modulate = LIT_MODULATE
	if _candle != null:
		_candle.queue_redraw()
	if _silhouette != null:
		_silhouette.queue_redraw()


func visual_time() -> float:
	return _vt


## 烛台（Area2D）：未点燃时是带残蜡的铁烛台，点燃时亮起暖色烛火与光晕。
## 内嵌类不直接引用外层 class_name。
class CandleStand extends Area2D:
	var radius: float = 48.0
	var owner_bridge: Node = null

	func _ready() -> void:
		z_index = 1

	func _draw() -> void:
		if owner_bridge == null:
			return
		var lit := bool(owner_bridge.call("is_lit"))
		var warn := bool(owner_bridge.call("is_warning"))
		var vt := float(owner_bridge.call("visual_time"))
		var iron := Color(0.24, 0.21, 0.28)
		var rim := Color(0.44, 0.39, 0.50)
		var wax := Color(0.92, 0.84, 0.66)
		# 铁底座 + 烛柱 + 托盘 + 蜡烛本体（脚点在 (0, 0)）
		HazardFx.px_rect(self, Rect2(-6.0, -3.0, 12.0, 3.0), iron)
		HazardFx.px_rect(self, Rect2(-4.0, -4.0, 8.0, 1.0), rim)
		HazardFx.px_rect(self, Rect2(-2.0, -14.0, 4.0, 10.0), iron)
		HazardFx.px_rect(self, Rect2(-5.0, -16.0, 10.0, 2.0), rim)
		HazardFx.px_rect(self, Rect2(-3.0, -24.0, 6.0, 8.0), wax)
		HazardFx.px_rect(self, Rect2(-1.0, -26.0, 2.0, 2.0), Color(0.18, 0.14, 0.12))
		if lit:
			var flicker := 0.85 + 0.15 * sin(vt * 18.0)
			if warn:
				flicker *= 0.45 + 0.55 * (0.5 + 0.5 * sin(vt * 28.0))
			var halo_a := 0.22 * flicker
			HazardFx.px_rect(self, Rect2(-12.0, -36.0, 24.0, 20.0), Color(1.0, 0.68, 0.28, halo_a))
			HazardFx.px_rect(self, Rect2(-7.0, -33.0, 14.0, 14.0), Color(1.0, 0.78, 0.36, halo_a * 1.4))
			var sway := roundf(sin(vt * 13.0))
			var fh := 5.0 if not warn else 3.0
			HazardFx.px_rect(self, Rect2(-2.0 + sway, -26.0 - fh, 4.0, fh), Color(1.0, 0.62, 0.18, 0.95))
			HazardFx.px_rect(self, Rect2(-1.0 + sway, -25.0 - fh * 0.6, 2.0, maxf(2.0, fh * 0.6)),
					Color(1.0, 0.95, 0.72, 0.98))
		else:
			# 未点燃时留一点微弱烛芯余温，提示玩家此处可点燃。
			var pulse := 0.35 + 0.25 * sin(vt * 4.0)
			HazardFx.px_rect(self, Rect2(-2.0, -28.0, 4.0, 2.0), Color(0.95, 0.65, 0.30, pulse))


## 桥面轮廓描边：未点燃时勾出虚线蜡光剪影，点燃后在顶沿铺一层暖烛光边。
class BridgeOverlay extends Node2D:
	var bridge_size: Vector2 = Vector2(64.0, 16.0)
	var owner_bridge: Node = null

	func _draw() -> void:
		if owner_bridge == null:
			return
		var lit := bool(owner_bridge.call("is_lit"))
		var warn := bool(owner_bridge.call("is_warning"))
		var vt := float(owner_bridge.call("visual_time"))
		if lit:
			var a := 0.75 if not warn else (0.3 + 0.55 * (0.5 + 0.5 * sin(vt * 26.0)))
			HazardFx.px_rect(self, Rect2(0.0, 0.0, bridge_size.x, 2.0), Color(1.0, 0.82, 0.46, a))
		else:
			var x := 2.0
			var a := 0.42 + 0.12 * sin(vt * 3.5)
			var col := Color(0.92, 0.78, 0.52, a)
			while x < bridge_size.x - 2.0:
				var seg := minf(6.0, bridge_size.x - 2.0 - x)
				HazardFx.px_rect(self, Rect2(x, 0.0, seg, 1.0), col)
				HazardFx.px_rect(self, Rect2(x, bridge_size.y - 1.0, seg, 1.0),
						Color(col.r, col.g, col.b, a * 0.65))
				x += 10.0
			HazardFx.px_rect(self, Rect2(0.0, 1.0, 1.0, bridge_size.y - 2.0), col)
			HazardFx.px_rect(self, Rect2(bridge_size.x - 1.0, 1.0, 1.0, bridge_size.y - 2.0), col)
