class_name CombatMarker
extends Node2D
## 读招 / 破绽的统一小图标（纯表现）：收缩圆环 = 前摇倒计时，地面区域框 = 落点，
## 路径线 = 冲锋方向（锁向后变白），金色箭头 = 现在可以打，青色菱形 = 破绽（下一击翻倍）。
## 全是 1-2 像素的点阵线条、加法混合、寿命有限；同屏总数受 CombatRules.BUDGET[&"markers"]
## 限制，超出时 spawn() 返回 null，调用方不必处理。

enum Kind { RING, ZONE, LANE, OPENING, RIPOSTE }

const Z := 6

## 当前在树内的标记数（预算 / 测试用）。
static var live: int = 0

var kind: Kind = Kind.RING
var lifetime: float = 0.5
var color: Color = Color.WHITE
## RING：半径从 radius_from 收缩到 radius_to；ZONE：rect；LANE：length + facing。
var radius_from: float = 22.0
var radius_to: float = 5.0
var rect: Rect2 = Rect2(-18, -14, 36, 28)
var length: float = 120.0
var facing: float = 1.0
var _age: float = 0.0
var _locked: bool = false


static func spawn(parent: Node, p_kind: Kind, at: Vector2, p_lifetime: float,
		p_color: Color, params: Dictionary = {}) -> CombatMarker:
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return null
	if live >= int(CombatRules.BUDGET[&"markers"]):
		return null
	var marker := CombatMarker.new()
	marker.kind = p_kind
	marker.position = at
	marker.lifetime = p_lifetime
	marker.color = p_color
	for key in params:
		marker.set(key, params[key])
	parent.add_child(marker)
	return marker


## 路径线锁向：变成实线并提亮（梦魇冲锋最后 0.2 秒）。
func lock() -> void:
	_locked = true
	queue_redraw()


func is_locked() -> bool:
	return _locked


func age() -> float:
	return _age


func dismiss() -> void:
	if not is_queued_for_deletion():
		queue_free()


func _enter_tree() -> void:
	live += 1


func _exit_tree() -> void:
	live = maxi(0, live - 1)


func _ready() -> void:
	z_index = Z
	z_as_relative = true
	material = Fx.additive_mat()


func _process(delta: float) -> void:
	# Telegraphs and openings must stay in time with the AI/attack windows that
	# they describe; a cinematic must not spend a warning while the AI is held.
	if Director.is_input_locked():
		return
	_age += delta
	if lifetime > 0.0 and _age >= lifetime:
		queue_free()
		return
	queue_redraw()


func _progress() -> float:
	if lifetime <= 0.0:
		return 0.0
	return clampf(_age / lifetime, 0.0, 1.0)


func _draw() -> void:
	match kind:
		Kind.RING:
			_draw_ring()
		Kind.ZONE:
			_draw_zone()
		Kind.LANE:
			_draw_lane()
		Kind.OPENING:
			_draw_opening()
		Kind.RIPOSTE:
			_draw_riposte()


func _tint(alpha: float) -> Color:
	return Color(color.r, color.g, color.b, clampf(alpha, 0.0, 1.0))


func _dot(p: Vector2, c: Color) -> void:
	draw_rect(Rect2(Vector2(roundf(p.x) - 1.0, roundf(p.y) - 1.0), Vector2(2, 2)), c)


## 圆环越收越亮：亮到最实的那一帧就是判定出现的时刻。
func _draw_ring() -> void:
	var k := _progress()
	var radius := lerpf(radius_from, radius_to, k)
	var c := _tint(color.a * (0.35 + 0.65 * k))
	var dots := 14
	for i in dots:
		var ang := TAU * float(i) / float(dots)
		_dot(Vector2(cos(ang), sin(ang)) * radius, c)


## 落点框：细线 + 极淡的底色，越接近出招闪得越快。
func _draw_zone() -> void:
	var k := _progress()
	var blink := 0.55 + 0.45 * sin(_age * lerpf(10.0, 34.0, k))
	var c := _tint(color.a * (0.35 + 0.65 * k) * blink)
	draw_rect(rect, _tint(0.10 * color.a * k), true)
	draw_rect(rect, c, false, 1.0)


## 冲锋路径：虚线，锁向后实线转白。
func _draw_lane() -> void:
	var c := _tint(color.a * 0.55)
	if _locked:
		c = Color(1.6, 1.6, 1.6, 0.9)
	var step := 4.0 if _locked else 8.0
	var x := 0.0
	while x < length:
		draw_rect(Rect2(Vector2(facing * x - (1.0 if facing < 0.0 else 0.0), 0.0), Vector2(2, 1)), c)
		x += step


## 破绽箭头：停在头顶，上下浮动。
func _draw_opening() -> void:
	var bob := roundf(sin(_age * 9.0) * 1.5)
	var c := _tint(color.a * (0.85 if lifetime <= 0.0 else 1.0 - 0.5 * _progress()))
	var pts := PackedVector2Array([Vector2(-4, -5 + bob), Vector2(4, -5 + bob), Vector2(0, 1 + bob)])
	draw_colored_polygon(pts, c)


## 反击菱形：青白，轻微脉动。向右偏 6 px：盾卫被弹反时金色破绽箭头与
## 青色菱形会同时出现，两个符号必须并排可读而不是互相盖住。
func _draw_riposte() -> void:
	var pulse := 0.75 + 0.25 * sin(_age * 12.0)
	var c := _tint(color.a * pulse)
	var bob := roundf(sin(_age * 6.0))
	var ox := 6.0
	var pts := PackedVector2Array([Vector2(ox, -6 + bob), Vector2(ox + 4, -2 + bob),
			Vector2(ox, 2 + bob), Vector2(ox - 4, -2 + bob)])
	draw_colored_polygon(pts, c)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
			Color(1.0, 1.0, 1.0, 0.7 * pulse), 1.0)
