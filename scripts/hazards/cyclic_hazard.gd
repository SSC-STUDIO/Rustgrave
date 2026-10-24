class_name CyclicHazard
extends Node2D
## 周期机关：休止 → 预警 → 判定 → 休止……（蒸汽喷口、炉口喷火、渣喷泉、坠钟、冲击波）。
##
## 规则（LevelSanity / docs/level_authoring.md §8 会拒绝违反的布局）：
##   · 预警不短于 MIN_TELEGRAPH：读招画面（漏气 / 漏光 / 冒泡 / 阴影 / 地线）一定先于判定；
##   · 判定体与画面同步：喷柱升到哪里判定就到哪里，冲击波只在前沿一条窄带里伤人；
##   · 相位由 `phase` 与节点自己的时钟决定，出生即确定，测试与战役 bot 可以用
##     `seconds_until_active()` / `safe_window()` 读它；
##   · 伤害只走 Hitbox → Hurtbox → Health，冲刺 i-frames 照常能穿过；
##   · 纯关卡机关：不写存档、不改玩家公式；过场锁玩家时整条时间线冻结并收刀。
##
## 朝向 `facing` 只允许四个正方向；原点是喷口（坠钟 / 冲击波是落点地面中心）。
## 绘制统一在「向上」坐标系里做，再整体旋转 90° 的倍数，像素不会被转糊。

enum State { REST, WARN, ACTIVE }

signal state_changed(new_state: int)
## 进入判定期的那一刻（音效 / 镜头 / 测试读它）。
signal fired

const GROUP := &"hazards"
const MIN_TELEGRAPH := 0.5
const MIN_ACTIVE := 0.2
const MIN_REST := 0.3
## 坠钟悬挂高度与落地时间。
const BELL_DROP := 150.0
const BELL_FALL_TIME := 0.12
## 冲击波前沿带宽（只有这一条窄带伤人）。
const SHOCK_FRONT := 24.0
const IDLE_REDRAW := 0.12
const ADDITIVE_SKINS := ["flame", "slag", "shock"]
const HEAVY_SKINS := ["slag", "bell", "shock"]

@export_enum("steam", "flame", "slag", "bell", "shock") var skin: String = "steam"
## 沿喷口朝向的判定长度 / 垂直朝向的判定宽度（坠钟：落点高 / 宽；冲击波：带高 / 总宽）。
@export var reach: float = 56.0
@export var thick: float = 24.0
@export var facing: Vector2 = Vector2.UP
@export var rest_time: float = 2.0
@export var telegraph_time: float = 0.7
@export var active_time: float = 0.6
@export_range(0.0, 1.0) var phase: float = 0.0
@export var damage: int = 1
## 受击推力；(0,0) 时按皮肤取默认值。
@export var knockback: Vector2 = Vector2.ZERO
## 首遇提示的 HintService.CATALOG 键；空 = 不放提示区。
@export var hint_id: StringName = &""

var _state: int = State.REST
var _t := 0.0
var _vt := 0.0
var _hitbox: Hitbox
var _shapes: Array[CollisionShape2D] = []
var _base: Node2D
var _on_screen := true
var _redraw_cd := 0.0
var _armed := false
var _frozen_hold := false


func _ready() -> void:
	add_to_group(GROUP)
	set_meta("hazard_kind", "cyclic")
	facing = HazardFx.cardinal(facing)
	if skin == "bell" or skin == "shock":
		facing = Vector2.UP
	rest_time = maxf(MIN_REST, rest_time)
	telegraph_time = maxf(MIN_TELEGRAPH, telegraph_time)
	active_time = maxf(MIN_ACTIVE, active_time)
	z_index = 1
	if skin in ADDITIVE_SKINS:
		material = Fx.additive_mat()
	_t = phase * period()
	_build_hitbox()
	_build_base()
	_build_notifier()
	if hint_id != &"":
		HazardFx.attach_hint(self, hint_id, local_hit_rect())
	_state = state_at(_t)
	if _base != null:
		(_base as HazardBase).state_id = _state
	if _state == State.ACTIVE:
		_set_armed(true)
	_apply_shape()
	queue_redraw()


## 各皮肤的缺省参数（ChapterLayout.cyclic 以它为底，props 覆盖）。
## 时间都留足："休止 + 预警" ≥ 1.2s，是 LevelSanity 的底线。
static func preset(for_skin: String) -> Dictionary:
	match for_skin:
		"flame":
			return {"reach": 64.0, "thick": 20.0, "rest_time": 2.2, "telegraph_time": 0.8,
					"active_time": 0.6, "hint_id": &"flame"}
		"slag":
			return {"reach": 72.0, "thick": 26.0, "rest_time": 2.4, "telegraph_time": 0.9,
					"active_time": 0.8, "hint_id": &"slag"}
		"bell":
			return {"reach": 44.0, "thick": 34.0, "rest_time": 2.8, "telegraph_time": 0.9,
					"active_time": 0.45, "hint_id": &"bell"}
		"shock":
			return {"reach": 16.0, "thick": 220.0, "rest_time": 3.0, "telegraph_time": 0.9,
					"active_time": 0.9, "hint_id": &"shock"}
		_:
			return {"reach": 56.0, "thick": 22.0, "rest_time": 2.0, "telegraph_time": 0.8,
					"active_time": 0.7, "hint_id": &"steam"}


# --------------------------------------------------------------------------
# 时间线（纯函数 + 读数；测试 / bot / LevelSanity 都读这里）
# --------------------------------------------------------------------------

func period() -> float:
	return maxf(MIN_REST, rest_time) + maxf(MIN_TELEGRAPH, telegraph_time) + maxf(MIN_ACTIVE, active_time)


static func cycle_state(t: float, rest: float, warn: float, active: float) -> int:
	var total := rest + warn + active
	var c := fposmod(t, total)
	if c < rest:
		return State.REST
	if c < rest + warn:
		return State.WARN
	return State.ACTIVE


func state_at(t: float) -> int:
	return cycle_state(t, maxf(MIN_REST, rest_time), maxf(MIN_TELEGRAPH, telegraph_time),
			maxf(MIN_ACTIVE, active_time))


func state() -> int:
	return _state


func is_active() -> bool:
	return _state == State.ACTIVE


func is_warning() -> bool:
	return _state == State.WARN


func clock() -> float:
	return _t


## 距离下一次判定开始还有多久；正在判定期返回 0。
func seconds_until_active() -> float:
	var c := fposmod(_t, period())
	var start := maxf(MIN_REST, rest_time) + maxf(MIN_TELEGRAPH, telegraph_time)
	if c >= start:
		return 0.0
	return start - c


## 距离当前判定期结束还有多久；不在判定期返回 0。
func seconds_until_safe() -> float:
	if _state != State.ACTIVE:
		return 0.0
	return period() - fposmod(_t, period())


## 现在踏进判定区、并停留 `duration` 秒，会不会撞上判定期。
func safe_window(duration: float = 0.0) -> bool:
	if _state == State.ACTIVE:
		return false
	return seconds_until_active() > duration


func _warn_k() -> float:
	var c := fposmod(_t, period())
	return clampf((c - maxf(MIN_REST, rest_time)) / maxf(MIN_TELEGRAPH, telegraph_time), 0.0, 1.0)


func _active_k() -> float:
	var c := fposmod(_t, period())
	var start := maxf(MIN_REST, rest_time) + maxf(MIN_TELEGRAPH, telegraph_time)
	return clampf((c - start) / maxf(MIN_ACTIVE, active_time), 0.0, 1.0)


## 判定期里喷柱 / 冲击波「伸出去」的比例 0..1：升起、保持、收回。
func extent() -> float:
	if _state != State.ACTIVE:
		return 0.0
	var k := _active_k()
	match skin:
		"flame":
			return minf(k / 0.12, 1.0) * minf((1.0 - k) / 0.12, 1.0)
		"slag":
			return minf(k / 0.2, 1.0) * minf((1.0 - k) / 0.25, 1.0)
		"shock":
			return k
		"bell":
			return 1.0
		_:
			return minf(k / 0.18, 1.0) * minf((1.0 - k) / 0.2, 1.0)


# --------------------------------------------------------------------------
# 几何
# --------------------------------------------------------------------------

## 判定区（节点本地坐标）。坠钟 / 冲击波取整块可能被波及的范围。
func local_hit_rect() -> Rect2:
	var f := HazardFx.cardinal(facing)
	var half := thick * 0.5
	if f == Vector2.UP:
		return Rect2(-half, -reach, thick, reach)
	if f == Vector2.DOWN:
		return Rect2(-half, 0.0, thick, reach)
	if f == Vector2.LEFT:
		return Rect2(-reach, -half, reach, thick)
	return Rect2(0.0, -half, reach, thick)


## 判定区（世界坐标）。
func hit_rect() -> Rect2:
	var local := local_hit_rect()
	return Rect2(global_position + local.position, local.size)


func _knockback_vector() -> Vector2:
	if knockback != Vector2.ZERO:
		return knockback
	match skin:
		"flame":
			return HazardFx.cardinal(facing) * 70.0 + Vector2(0.0, -80.0)
		"slag":
			return Vector2(0.0, -190.0)
		"bell":
			return Vector2(0.0, -120.0)
		"shock":
			return Vector2(0.0, -150.0)
		_:
			return Vector2(0.0, -170.0)


# --------------------------------------------------------------------------
# 构建
# --------------------------------------------------------------------------

func _build_hitbox() -> void:
	_hitbox = Hitbox.new()
	_hitbox.name = "HazardHitbox"
	_hitbox.damage = maxi(1, damage)
	_hitbox.team = &"enemy"
	_hitbox.blow = &"heavy" if skin in HEAVY_SKINS else &"light"
	var count := 2 if skin == "shock" else 1
	for i in count:
		var shape := CollisionShape2D.new()
		shape.name = "CollisionShape2D" if i == 0 else "CollisionShape2D_%d" % i
		var rect := RectangleShape2D.new()
		rect.size = Vector2(maxf(2.0, thick), maxf(2.0, reach))
		shape.shape = rect
		_hitbox.add_child(shape)
		_shapes.append(shape)
	add_child(_hitbox)


func _build_base() -> void:
	if skin == "bell" or skin == "shock":
		return
	var base := HazardBase.new()
	base.name = "Base"
	base.facing = facing
	base.thick = thick
	base.state_id = _state
	base.z_index = -1
	_base = base
	add_child(base)


func _build_notifier() -> void:
	var notifier := VisibleOnScreenNotifier2D.new()
	notifier.name = "OnScreen"
	var bounds := local_hit_rect().grow(28.0)
	if skin == "bell":
		bounds = bounds.merge(Rect2(-thick, -BELL_DROP - 8.0, thick * 2.0, BELL_DROP))
	notifier.rect = bounds
	notifier.screen_entered.connect(func() -> void:
		_on_screen = true
		queue_redraw())
	notifier.screen_exited.connect(func() -> void: _on_screen = false)
	add_child(notifier)


# --------------------------------------------------------------------------
# 逐帧
# --------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	tick(delta)


## 推进 delta 秒。测试可以直接驱动它（不依赖物理帧）。
func tick(delta: float) -> void:
	if _is_frozen():
		if not _frozen_hold:
			_frozen_hold = true
			_hold_hitbox(true)
		return
	if _frozen_hold:
		_frozen_hold = false
		_hold_hitbox(false)
	_vt += delta
	_t += delta
	var s := state_at(_t)
	if s != _state:
		_enter(s)
	if _state == State.ACTIVE:
		_apply_shape()
	if _state != State.REST:
		queue_redraw()
	else:
		_redraw_cd -= delta
		if _redraw_cd <= 0.0:
			_redraw_cd = IDLE_REDRAW
			queue_redraw()


func _is_frozen() -> bool:
	return Director != null and Director.is_input_locked()


func _hold_hitbox(hold: bool) -> void:
	if _hitbox == null:
		return
	if hold:
		_hitbox.monitoring = false
	elif _armed:
		_hitbox.monitoring = true


func _enter(new_state: int) -> void:
	var old := _state
	_state = new_state
	# 一次大步长可能跨过休止期：只要离开判定期，判定体一定收刀。
	if old == State.ACTIVE and new_state != State.ACTIVE:
		_set_armed(false)
	match new_state:
		State.WARN:
			_on_warn()
		State.ACTIVE:
			_on_active()
	if _base != null:
		(_base as HazardBase).state_id = new_state
		_base.queue_redraw()
	state_changed.emit(new_state)


func _on_warn() -> void:
	if is_inside_tree():
		var local := local_hit_rect()
		var tint := _warn_color()
		CombatMarker.spawn(self, CombatMarker.Kind.ZONE, local.get_center(), telegraph_time, tint,
				{"rect": Rect2(-local.size * 0.5, local.size)})
	HazardFx.play(skin, "warn", global_position, -9.0)


func _on_active() -> void:
	_set_armed(true)
	_apply_shape()
	HazardFx.play(skin, "fire", global_position, -5.0)
	match skin:
		"flame":
			Fx.burst(&"ember", global_position)
		"slag":
			Fx.burst(&"ember", global_position)
			Fx.burst(&"spark", global_position)
		"bell":
			Fx.burst(&"stone", global_position)
			Fx.burst(&"dust", global_position)
			Juice.shake(2.6, 140)
		"shock":
			Fx.burst(&"dust", global_position)
			Juice.shake(1.8, 120)
		_:
			Fx.burst(&"dust", global_position)
	fired.emit()


func _set_armed(armed: bool) -> void:
	_armed = armed
	if _hitbox == null:
		return
	if armed:
		_hitbox.damage = maxi(1, damage)
		_hitbox.arm(_knockback_vector())
		if _frozen_hold:
			_hitbox.monitoring = false
	else:
		_hitbox.disarm()


## 判定体跟着画面走：喷柱升到哪判定到哪；冲击波只在两条前沿窄带里伤人。
func _apply_shape() -> void:
	if _shapes.is_empty():
		return
	var e := maxf(0.04, extent()) if _state == State.ACTIVE else 1.0
	if skin == "shock":
		var half := thick * 0.5
		var front := half * e
		for i in _shapes.size():
			var side := -1.0 if i == 0 else 1.0
			var rect := _shapes[i].shape as RectangleShape2D
			rect.size = Vector2(SHOCK_FRONT, maxf(2.0, reach))
			_shapes[i].position = Vector2(side * front, -reach * 0.5)
		return
	var local := local_hit_rect()
	var rect := _shapes[0].shape as RectangleShape2D
	var f := HazardFx.cardinal(facing)
	if skin == "bell":
		rect.size = local.size
		_shapes[0].position = local.get_center()
		return
	if f == Vector2.UP or f == Vector2.DOWN:
		rect.size = Vector2(local.size.x, maxf(2.0, local.size.y * e))
		var cy := -rect.size.y * 0.5 if f == Vector2.UP else rect.size.y * 0.5
		_shapes[0].position = Vector2(0.0, cy)
	else:
		rect.size = Vector2(maxf(2.0, local.size.x * e), local.size.y)
		var cx := -rect.size.x * 0.5 if f == Vector2.LEFT else rect.size.x * 0.5
		_shapes[0].position = Vector2(cx, 0.0)


func _warn_color() -> Color:
	match skin:
		"steam":
			return Color(0.8, 0.95, 1.0, 0.9)
		"flame":
			return Color(1.0, 0.5, 0.2, 0.95)
		"slag":
			return Color(1.0, 0.62, 0.15, 0.95)
		"bell":
			return Color(1.0, 0.85, 0.5, 0.9)
		_:
			return Color(1.0, 0.75, 0.45, 0.9)


# --------------------------------------------------------------------------
# 绘制（向上坐标系 + 整体旋转）
# --------------------------------------------------------------------------

func _draw() -> void:
	if not _on_screen:
		return
	draw_set_transform(Vector2.ZERO, HazardFx.rotation_for(facing), Vector2.ONE)
	match skin:
		"steam":
			_draw_steam()
		"flame":
			_draw_flame()
		"slag":
			_draw_slag()
		"bell":
			_draw_bell()
		"shock":
			_draw_shock()


func _px(rect: Rect2, color: Color) -> void:
	HazardFx.px_rect(self, rect, color)


func _puff(center: Vector2, size: float, alpha: float) -> void:
	if alpha <= 0.01 or size < 1.0:
		return
	var body := Color(0.86, 0.91, 0.93, alpha)
	_px(Rect2(center.x - size * 0.5, center.y - size * 0.3, size, size * 0.6), body)
	_px(Rect2(center.x - size * 0.3, center.y - size * 0.5, size * 0.6, size), body)
	_px(Rect2(center.x - size * 0.15, center.y - size * 0.15, size * 0.3, size * 0.3),
			Color(1.0, 1.0, 1.0, alpha * 0.85))


func _steam_wisps(count: int, height: float, alpha: float, size: float) -> void:
	var half := thick * 0.5
	for i in count:
		var y := -fposmod(_vt * 14.0 + float(i) * (height / float(maxi(1, count))), height)
		var x := sin(_vt * 2.4 + float(i) * 2.1) * half * 0.35
		var fade := 1.0 - (-y / maxf(1.0, height))
		_puff(Vector2(x, y), size, alpha * fade)


func _draw_steam() -> void:
	var half := thick * 0.5
	match _state:
		State.REST:
			_steam_wisps(2, reach * 0.16, 0.22, 3.0)
		State.WARN:
			var k := _warn_k()
			_steam_wisps(3 + int(k * 5.0), reach * (0.2 + 0.35 * k), 0.3 + 0.3 * k, 4.0 + 2.0 * k)
			_px(Rect2(-half + 2.0, -2.0, thick - 4.0, 2.0), Color(1.0, 0.82, 0.55, 0.3 + 0.5 * k))
		State.ACTIVE:
			var e := extent()
			var fade := 1.0 - clampf((_active_k() - 0.8) / 0.2, 0.0, 1.0)
			var n := maxi(2, int(reach * e / 7.0))
			for i in n:
				var f := float(i) / float(maxi(1, n))
				var y := -float(i) * 7.0 - 3.0
				var wob := sin(_vt * 9.0 + float(i) * 1.7) * half * 0.35 * (0.3 + f)
				_puff(Vector2(wob, y), lerpf(thick * 0.55, thick, f), (0.88 - 0.45 * f) * fade)


func _flame_tongue(height: float, width_k: float, alpha: float) -> void:
	var rows := maxi(1, int(height / 3.0))
	for r in rows:
		var f := float(r) / float(rows)
		var w := thick * width_k * (1.0 - f * 0.75) * (0.88 + 0.12 * sin(_vt * 30.0 + float(r) * 2.3))
		var sway := sin(_vt * 11.0 + float(r) * 0.9) * 2.0 * f
		var col := Color(1.0, 0.92, 0.6).lerp(Color(1.0, 0.55, 0.1), clampf(f * 1.6, 0.0, 1.0))
		col = col.lerp(Color(0.85, 0.2, 0.1), clampf((f - 0.55) * 2.2, 0.0, 1.0))
		col.a = alpha * (1.0 - f * 0.4)
		_px(Rect2(sway - w * 0.5, -float(r + 1) * 3.0, w, 3.0), col)
		if f < 0.6:
			_px(Rect2(sway - w * 0.22, -float(r + 1) * 3.0, w * 0.44, 3.0),
					Color(1.0, 0.95, 0.75, alpha * 0.8))


func _draw_flame() -> void:
	var half := thick * 0.5
	match _state:
		State.REST:
			_flame_tongue(7.0, 0.3, 0.55)
		State.WARN:
			var k := _warn_k()
			_flame_tongue(8.0 + 10.0 * k, 0.35 + 0.25 * k, 0.65 + 0.3 * k)
			_px(Rect2(-half, -3.0, thick, 3.0), Color(1.0, 0.3, 0.1, 0.25 + 0.45 * k))
		State.ACTIVE:
			var e := extent()
			_flame_tongue(reach * e, 1.0, 0.95)
			_px(Rect2(-half - 3.0, -4.0, thick + 6.0, 4.0), Color(1.0, 0.6, 0.2, 0.4))


func _draw_slag() -> void:
	var half := thick * 0.5
	match _state:
		State.REST:
			var pulse := 0.45 + 0.35 * sin(_vt * 2.0)
			_px(Rect2(-half * 0.6, -2.0, thick * 0.6, 2.0), Color(1.0, 0.45, 0.1, pulse))
		State.WARN:
			var k := _warn_k()
			_px(Rect2(-half * 0.8, -3.0, thick * 0.8, 3.0), Color(1.0, 0.5, 0.1, 0.4 + 0.5 * k))
			var n := 2 + int(k * 6.0)
			for i in n:
				var life := fposmod(_vt * (2.0 + 3.0 * k) + float(i) * 0.37, 1.0)
				var bx := sin(float(i) * 2.7) * half * 0.6
				var by := -3.0 - life * (6.0 + 8.0 * k)
				_px(Rect2(bx - 1.0, by, 2.0 + float(i % 2), 2.0 + float(i % 2)),
						Color(1.0, 0.75, 0.3, 0.9 * (1.0 - life)))
		State.ACTIVE:
			var e := extent()
			var h := reach * e
			var w := thick * 0.62
			_px(Rect2(-w * 0.5, -h, w, h), Color(1.0, 0.45, 0.1, 0.85))
			_px(Rect2(-w * 0.3, -h, w * 0.6, h), Color(1.0, 0.72, 0.28, 0.95))
			_px(Rect2(-w * 0.12, -h, w * 0.24, h), Color(1.0, 0.95, 0.7, 1.0))
			_px(Rect2(-half, -4.0, thick, 4.0), Color(1.0, 0.55, 0.15, 0.7))
			var tau := _active_k()
			for i in 9:
				var dir := float(i) - 4.0
				var vx := dir * 9.0
				var tt := fposmod(tau * 2.0 + float(i) * 0.11, 1.0)
				var px := vx * tt * 1.4
				var py := -(h * 0.9) * (1.0 - pow(tt * 2.0 - 1.0, 2.0))
				_px(Rect2(px - 1.0, py, 2.0, 2.0), Color(1.0, 0.8, 0.35, 1.0 - tt * 0.7))


func _bell_shape(bottom: Vector2, alpha: float) -> void:
	var half := thick * 0.5
	var bronze := Color(0.62, 0.45, 0.22, alpha)
	var light := Color(0.92, 0.74, 0.36, alpha)
	var dark := Color(0.28, 0.18, 0.09, alpha)
	var w := thick
	_px(Rect2(bottom.x - w * 0.18, bottom.y - 38.0, w * 0.36, 7.0), bronze)
	_px(Rect2(bottom.x - w * 0.32, bottom.y - 31.0, w * 0.64, 9.0), bronze)
	_px(Rect2(bottom.x - w * 0.44, bottom.y - 22.0, w * 0.88, 10.0), bronze)
	_px(Rect2(bottom.x - half, bottom.y - 12.0, w, 12.0), bronze)
	_px(Rect2(bottom.x - half, bottom.y - 12.0, 3.0, 12.0), light)
	_px(Rect2(bottom.x - w * 0.44, bottom.y - 22.0, 3.0, 10.0), light)
	_px(Rect2(bottom.x + half - 3.0, bottom.y - 12.0, 3.0, 12.0), dark)
	_px(Rect2(bottom.x - half, bottom.y - 3.0, w, 3.0), dark)
	_px(Rect2(bottom.x - 3.0, bottom.y - 5.0, 6.0, 5.0), Color(0.15, 0.1, 0.06, alpha))


func _draw_bell() -> void:
	var half := thick * 0.5
	match _state:
		State.WARN:
			var k := _warn_k()
			var sw := lerpf(8.0, thick * 1.25, k)
			_px(Rect2(-sw * 0.5, -3.0, sw, 3.0), Color(0.0, 0.0, 0.0, 0.7 * k))
			_px(Rect2(-sw * 0.38, -5.0, sw * 0.76, 2.0), Color(0.0, 0.0, 0.0, 0.5 * k))
			# 暖色边线：阴影压在暗地面上也读得出来。
			_px(Rect2(-sw * 0.5, -1.0, sw, 1.0), Color(1.0, 0.8, 0.4, 0.55 * k))
			for i in 4:
				var life := fposmod(_vt * 1.6 + float(i) * 0.31, 1.0)
				var dx := sin(float(i) * 3.1) * half
				_px(Rect2(dx - 1.0, -BELL_DROP * 0.6 + life * BELL_DROP * 0.6, 2.0, 2.0),
						Color(0.8, 0.72, 0.6, 0.6 * k))
			var shake := roundf(sin(_vt * 40.0)) * 1.0
			_bell_shape(Vector2(shake, -BELL_DROP), 0.2 + 0.45 * k)
		State.ACTIVE:
			var tau := _active_k() * maxf(MIN_ACTIVE, active_time)
			var fall := clampf(tau / BELL_FALL_TIME, 0.0, 1.0)
			var fade := 1.0 - clampf((_active_k() - 0.75) / 0.25, 0.0, 1.0)
			var y := -BELL_DROP * (1.0 - fall * fall)
			_bell_shape(Vector2(0.0, y), 1.0 if fall < 1.0 else fade)
			if fall >= 1.0:
				var ring := clampf((tau - BELL_FALL_TIME) / 0.2, 0.0, 1.0)
				var rw := half + ring * thick * 0.9
				_px(Rect2(-rw, -2.0, rw * 2.0, 2.0), Color(0.9, 0.82, 0.65, 0.5 * (1.0 - ring) * fade))


func _draw_shock() -> void:
	var half := thick * 0.5
	match _state:
		State.WARN:
			var k := _warn_k()
			var blink := 0.5 + 0.5 * sin(_vt * lerpf(12.0, 36.0, k))
			var x := -half
			while x < half:
				_px(Rect2(x, -1.0, 6.0, 1.0), Color(1.0, 0.75, 0.45, (0.2 + 0.5 * k) * blink))
				x += 12.0
			_px(Rect2(-4.0, -3.0 - 4.0 * k, 8.0, 3.0 + 4.0 * k), Color(1.0, 0.8, 0.5, 0.4 + 0.5 * k))
		State.ACTIVE:
			var e := extent()
			var front := half * e
			var fade := 1.0 - e * 0.6
			for side in [-1.0, 1.0]:
				_px(Rect2(side * front - SHOCK_FRONT * 0.5, -reach, SHOCK_FRONT, reach),
						Color(1.0, 0.7, 0.35, 0.28 * fade))
				_px(Rect2(side * front - 2.0, -reach, 4.0, reach), Color(1.0, 0.92, 0.7, 0.85 * fade))
			_px(Rect2(-front, -2.0, front * 2.0, 2.0), Color(1.0, 0.7, 0.35, 0.3 * fade))


## 喷口底座：预警 / 判定期漏光，休止期暗着。不参与判定。
## 内嵌类不引用外层 class_name（headless 扫描阶段外层类名可能还没注册），
## 所需参数由机关在状态变化时写进来。
class HazardBase extends Node2D:
	var facing: Vector2 = Vector2.UP
	var thick: float = 24.0
	## 0 休止 / 1 预警 / 2 判定（与 CyclicHazard.State 同值）。
	var state_id: int = 0

	func _draw() -> void:
		draw_set_transform(Vector2.ZERO, HazardFx.rotation_for(facing), Vector2.ONE)
		var w := thick + 8.0
		var iron := Color(0.2, 0.17, 0.15)
		var edge := Color(0.38, 0.32, 0.27)
		HazardFx.px_rect(self, Rect2(-w * 0.5, 0.0, w, 4.0), iron)
		HazardFx.px_rect(self, Rect2(-w * 0.5, 0.0, w, 1.0), edge)
		HazardFx.px_rect(self, Rect2(-w * 0.5 + 1.0, 1.0, 2.0, 2.0), edge)
		HazardFx.px_rect(self, Rect2(w * 0.5 - 3.0, 1.0, 2.0, 2.0), edge)
		var glow := Color(0.35, 0.1, 0.05)
		if state_id == 1:
			glow = Color(1.0, 0.55, 0.15)
		elif state_id == 2:
			glow = Color(1.0, 0.85, 0.5)
		HazardFx.px_rect(self, Rect2(-thick * 0.5 + 2.0, 1.0, thick - 4.0, 2.0), glow)
