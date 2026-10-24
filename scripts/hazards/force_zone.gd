class_name ForceZone
extends Area2D
## 外力区：风道、闸口涌流、锈泥沼、余烬风。站在里面的骑士被推着走 / 被拖慢。
##
## 推力不替换玩家公式：区域每个物理帧把 (push, drag) 交给 `PlayerController.add_environment`，
## 控制器把 push.x 当作「目标速度偏移」（顺风更快、逆风顶住、不按键会被推着走），
## push.y 当作竖向加速度（上升气流抵消一部分重力），drag 把目标速度与加速度按比例压低。
## 冲刺期间不受推力（冲刺就是风里的"硬过"），所以不会取消冲刺的无敌与手感。
##
## `gust_period > 0` 时是阵风：每个周期里前 `gust_duty` 比例有风，进出各有 0.3s 缓坡，
## 阵风前 `WARN_TIME` 秒先有风声与细风丝（预兆）。原点在区域矩形中心。
## 纯关卡机关：不写存档、不改物理层；泥沼可附带毒素暴露。

const GROUP := &"hazards"
const WARN_TIME := 0.6
## 速度偏移的上限：低于骑士跑速（108）；再大就成了"不可逆行"。
const MAX_PUSH := 96.0
const SKIN_HINTS := {"wind": &"wind", "water": &"surge", "mud": &"mud", "ember": &"wind"}

@export var size: Vector2 = Vector2(160.0, 96.0)
## x：速度偏移（像素/秒，正 = 向右）；y：竖向加速度（像素/秒²，负 = 向上）。
@export var push: Vector2 = Vector2.ZERO
## 0..0.85：把目标速度与加速度压低的比例（泥沼）。
@export_range(0.0, 0.85) var drag: float = 0.0
@export var gust_period: float = 0.0
@export_range(0.05, 1.0) var gust_duty: float = 0.6
@export_range(0.0, 1.0) var phase: float = 0.0
@export_enum("wind", "water", "mud", "ember") var skin: String = "wind"
## 每秒毒素暴露量（锈泥沼）；0 = 不带毒。毒池是 36/s、毒槽满值 100：泥沼取 12–20，
## 站着不动约 6 秒才满，比毒池温和，主要靠拖慢逼玩家跳过去。
@export var toxin_per_second: float = 0.0
## 首遇提示键；空 = 按皮肤取默认。
@export var hint_id: StringName = &""
@export var auto_hint: bool = true

var _t := 0.0
var _vt := 0.0
var _bodies: Array[Node2D] = []
var _seeds: Array[Vector2] = []
var _on_screen := true


func _ready() -> void:
	add_to_group(GROUP)
	set_meta("hazard_kind", "force")
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	monitorable = false
	push.x = clampf(push.x, -MAX_PUSH, MAX_PUSH)
	_t = phase * maxf(0.0, gust_period)
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	add_child(shape)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_build_seeds()
	_build_notifier()
	var hint := hint_id
	if hint == &"" and auto_hint:
		hint = SKIN_HINTS.get(skin, &"")
	if hint != &"":
		HazardFx.attach_hint(self, hint, Rect2(-size * 0.5, size), Vector2(72.0, 24.0))


## 区域矩形（世界坐标）。
func zone_rect() -> Rect2:
	return Rect2(global_position - size * 0.5, size)


## 时刻 t 的阵风强度 0..1（常风恒为 1）。
func gust_factor(t: float) -> float:
	if gust_period <= 0.05:
		return 1.0
	var on_time := gust_period * gust_duty
	var c := fposmod(t, gust_period)
	if c >= on_time:
		return 0.0
	var ramp := minf(0.3, on_time * 0.3)
	return minf(c / ramp, 1.0) * minf((on_time - c) / ramp, 1.0)


## 距离下一阵风开始还有多久；有风时返回 0；常风返回 0。
func seconds_until_gust() -> float:
	if gust_period <= 0.05:
		return 0.0
	var on_time := gust_period * gust_duty
	var c := fposmod(_t, gust_period)
	if c < on_time:
		return 0.0
	return gust_period - c


func is_gusting() -> bool:
	return gust_factor(_t) > 0.02


func clock() -> float:
	return _t


func current_push() -> Vector2:
	return push * gust_factor(_t)


func _build_seeds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(int(position.x), int(position.y))) ^ 0x51ed
	var n := clampi(int(size.x * size.y / 700.0), 8, 48)
	_seeds.clear()
	for i in n:
		_seeds.append(Vector2(rng.randf(), rng.randf()))


func _build_notifier() -> void:
	var notifier := VisibleOnScreenNotifier2D.new()
	notifier.name = "OnScreen"
	notifier.rect = Rect2(-size * 0.5, size).grow(16.0)
	notifier.screen_entered.connect(func() -> void:
		_on_screen = true
		queue_redraw())
	notifier.screen_exited.connect(func() -> void: _on_screen = false)
	add_child(notifier)


func _on_body_entered(body: Node2D) -> void:
	if not _bodies.has(body):
		_bodies.append(body)


func _on_body_exited(body: Node2D) -> void:
	_bodies.erase(body)


func _physics_process(delta: float) -> void:
	tick(delta)


## 推进 delta 秒并把外力交给区域里的骑士（测试可直接驱动）。
func tick(delta: float) -> void:
	if Director != null and Director.is_input_locked():
		return
	_t += delta
	_vt += delta
	var factor := gust_factor(_t)
	for body in _bodies.duplicate():
		if not is_instance_valid(body):
			_bodies.erase(body)
			continue
		if body is Player:
			var knight := body as Player
			if knight.controller != null:
				knight.controller.add_environment(push * factor, drag)
			if toxin_per_second > 0.0 and knight.toxin != null:
				knight.toxin.expose(toxin_per_second * delta)
	if _on_screen:
		queue_redraw()


func _draw() -> void:
	if not _on_screen:
		return
	var factor := gust_factor(_t)
	var warn := 0.0
	if gust_period > 0.05 and factor <= 0.02:
		var until := seconds_until_gust()
		if until > 0.0 and until < WARN_TIME:
			warn = 1.0 - until / WARN_TIME
	var strength := maxf(factor, warn * 0.5)
	match skin:
		"water":
			_draw_water(strength)
		"mud":
			_draw_mud()
		"ember":
			_draw_streaks(strength, Color(1.0, 0.62, 0.22), true)
		_:
			_draw_streaks(strength, Color(0.86, 0.9, 0.9), false)


func _flow_dir() -> Vector2:
	if absf(push.y) > absf(push.x):
		return Vector2(0.0, signf(push.y))
	return Vector2(signf(push.x) if push.x != 0.0 else 1.0, 0.0)


func _draw_streaks(strength: float, color: Color, dotted: bool) -> void:
	if strength <= 0.02:
		return
	var dir := _flow_dir()
	var speed := 40.0 + 90.0 * clampf(push.length() / MAX_PUSH, 0.0, 1.0)
	var half := size * 0.5
	for i in _seeds.size():
		var s := _seeds[i]
		var along := fposmod((s.x if dir.x != 0.0 else s.y) * (size.x if dir.x != 0.0 else size.y)
				+ _vt * speed * (dir.x + dir.y), size.x if dir.x != 0.0 else size.y)
		var pos := Vector2.ZERO
		if dir.x != 0.0:
			pos = Vector2(along - half.x, s.y * size.y - half.y)
		else:
			pos = Vector2(s.x * size.x - half.x, along - half.y)
		var a := (0.24 + 0.42 * strength) * (0.65 + 0.35 * sin(_vt * 3.0 + float(i)))
		var c := Color(color.r, color.g, color.b, a)
		if dotted:
			HazardFx.px_rect(self, Rect2(pos, Vector2(2.0, 2.0)), Color(c.r, c.g, c.b, a * 1.3))
		elif dir.x != 0.0:
			var streak_len := 6.0 + float(i % 3) * 4.0
			var x := pos.x - streak_len if dir.x > 0.0 else pos.x
			HazardFx.px_rect(self, Rect2(x, pos.y, streak_len, 1.0), c)
		else:
			var streak_len := 6.0 + float(i % 3) * 4.0
			var y := pos.y - streak_len if dir.y > 0.0 else pos.y
			HazardFx.px_rect(self, Rect2(pos.x, y, 1.0, streak_len), c)


func _draw_water(strength: float) -> void:
	var half := size * 0.5
	var dir := _flow_dir()
	var flow := dir.x if dir.x != 0.0 else 1.0
	if strength > 0.02:
		HazardFx.px_rect(self, Rect2(-half.x, -half.y, size.x, size.y),
				Color(0.3, 0.6, 0.75, 0.10 + 0.14 * strength))
	var rows := maxi(2, int(size.y / 12.0))
	for r in rows:
		var y := -half.y + (float(r) + 0.5) * size.y / float(rows)
		var x := -half.x
		var phase_x := fposmod(_vt * 60.0 * flow * maxf(strength, 0.2) + float(r) * 7.0, 16.0)
		while x < half.x:
			var wob := roundf(sin((x + phase_x) * 0.4 + float(r)))
			var a := (0.2 + 0.45 * strength)
			HazardFx.px_rect(self, Rect2(x + phase_x, y + wob, 6.0, 1.0), Color(0.6, 0.88, 1.0, a))
			x += 16.0
	if strength > 0.4:
		for i in _seeds.size():
			var s := _seeds[i]
			var fx := fposmod(s.x * size.x + _vt * 80.0 * flow, size.x) - half.x
			HazardFx.px_rect(self, Rect2(fx, s.y * size.y - half.y, 2.0, 2.0), Color(1.0, 1.0, 1.0, 0.5 * strength))


func _draw_mud() -> void:
	var half := size * 0.5
	HazardFx.px_rect(self, Rect2(-half.x, half.y - 14.0, size.x, 14.0), Color(0.28, 0.17, 0.08, 0.55))
	HazardFx.px_rect(self, Rect2(-half.x, half.y - 14.0, size.x, 2.0), Color(0.5, 0.32, 0.14, 0.7))
	for i in _seeds.size():
		var s := _seeds[i]
		var life := fposmod(_vt * 0.5 + s.y * 3.0, 1.0)
		var r := 1.0 + life * 2.0
		var bx := s.x * size.x - half.x
		var by := half.y - 12.0 + s.y * 8.0
		HazardFx.px_rect(self, Rect2(bx, by - life * 4.0, r, r), Color(0.7, 0.5, 0.2, 0.6 * (1.0 - life)))
