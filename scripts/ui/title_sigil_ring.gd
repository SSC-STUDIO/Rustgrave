class_name TitleSigilRing
extends Control
## 印记环：字标外的一圈铁与余烬——「炉厅记得你来过」。
##
## EmberSigils 的每次「点燃」是一枚刻度，沿椭圆从左肩顺时针走下侧腹、
## 经过底心（底心留一枚「炉厅的钉」：整环唯一的固定记认），最新的一枚
## 停在右肩，还烧着；
## 越老的越冷，按真实日数冷却（30 天凉透成暗铁）。每次「殁」是一粒
## 内圈的锈红菱形，凑在刻度圈里侧。没有记录时整环不画（冷启动不变）。
##
## 几何：开口在**上方**——字标又宽又亮，顶弧整段让给它（藏在其后），
## 能看见的部分是左右两肩（字标边翼之外）与底弧（副题和菜单之间）。
## 悬停由自身 _process 轮询（mouse_filter 保持 IGNORE，不抢输入），
## 悬到某枚刻度上时通过 hover_changed 把「第 N 次点燃 · 章 · 时间」
## 交给标题屏写进页脚。
##
## 视觉纪律：纯 _draw()，2px 台阶，无 PointLight2D（UI 层光源预算为 0）。

signal hover_changed(text: String)

const RUST := Color(0.42, 0.26, 0.16)
const IRON := Color(0.36, 0.33, 0.36)
const HOT := Color(1.0, 0.76, 0.29)
const MID := Color(1.0, 0.55, 0.16)
const COLD := Color(0.45, 0.31, 0.22)
const DEATH := Color(0.66, 0.25, 0.17)
## 顶部开口的半角（度）：弧从左肩 90+MOUTH 顺时针经过底心 180° 画到右肩 270-MOUTH。
## 60° 时尾端落在字标左右边翼的外侧（肩位），顶弧整段藏进字标后面。
const MOUTH_DEG := 60.0
## 多少天凉透：冷却曲线的满程。
const COOL_DAYS := 30.0
## 环上最多画的刻度数（超出取最近的）。
const MAX_TICKS := 64

## 开屏显现 0→1（wake() 驱动；默认 1，测试 / 工具不必感知）。
var reveal := 1.0:
	set(value):
		var next := clampf(value, 0.0, 1.0)
		if not is_equal_approx(reveal, next):
			reveal = next
			queue_redraw()

var _time := 0.0
var _hover := -1
var _ticks: Array[Dictionary] = []    # {d: int, label: String}
var _marks: Array[Dictionary] = []    # 死亡 {d: int, label: String}
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## 标题屏把准备好的记录交进来（label 已由 EmberSigils 解好章名）。
func configure(visits: Array[Dictionary], deaths: Array[Dictionary]) -> void:
	_ticks = visits
	if _ticks.size() > MAX_TICKS:
		_ticks = _ticks.slice(_ticks.size() - MAX_TICKS)
	_marks = deaths
	if _marks.size() > MAX_TICKS:
		_marks = _marks.slice(_marks.size() - MAX_TICKS)
	_hover = -1
	queue_redraw()


## 开屏：环从 12 点向两侧点亮一圈。delay 是字标锻入完成前的等待。
func wake(delay: float = 0.0) -> void:
	if _ticks.is_empty():
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	reveal = 0.0
	_tween = create_tween()
	_tween.tween_interval(maxf(delay, 0.0))
	_tween.tween_property(self, "reveal", 1.0, 0.9) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## 跳过开屏时立即全亮。
func skip_reveal() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	reveal = 1.0


func has_marks() -> bool:
	return not _ticks.is_empty()


func tick_count() -> int:
	return _ticks.size()


func _process(delta: float) -> void:
	if _ticks.is_empty():
		return
	_time += delta
	# 最新一枚刻度的余烬脉动 + 悬停检测：环很便宜，每帧重画无妨。
	queue_redraw()
	_update_hover()


## phi 是「自 12 点顺时针」的弧度（0=顶，PI/2=右，PI=底）。开口在顶：
## 可画弧从左肩 (PI/2 + MOUTH) 顺时针经过底心 (PI) 到右肩 (3PI/2 - MOUTH)。
func _ellipse_point(phi: float, rx: float, ry: float) -> Vector2:
	var c := size * 0.5
	return Vector2(c.x + rx * sin(phi), c.y - ry * cos(phi))


func _tick_phi(i: int, n: int) -> float:
	# 左肩（最老，TAU-MOUTH）经过底心（PI）到右肩（最新，MOUTH）。
	# phi 自 12 点顺时针：MOUTH=60° 是右上肩，TAU-MOUTH=300° 是左上肩。
	var span := TAU - deg_to_rad(float(MOUTH_DEG)) * 2.0
	if n <= 1:
		return PI
	var t := float(i) / float(n - 1)
	return (TAU - deg_to_rad(float(MOUTH_DEG))) - span * t


func _update_hover() -> void:
	if not is_visible_in_tree():
		return
	var mouse := get_local_mouse_position()
	var c := size * 0.5
	var rx := size.x * 0.5 - 6.0
	var ry := size.y * 0.5 - 6.0
	if rx <= 0.0 or ry <= 0.0:
		return
	var nx := (mouse.x - c.x) / rx
	var ny := (mouse.y - c.y) / ry
	var u := nx * nx + ny * ny
	var idx := -1
	if u >= 0.80 and u <= 1.15 and _ticks.size() > 0:
		# 自 12 点顺时针的角度，归一化到 [0, TAU)：底心是 PI。
		var phi := atan2(mouse.x - c.x, -(mouse.y - c.y))
		if phi < 0.0:
			phi += TAU
		var best := 99999.0
		for i in _ticks.size():
			var tp := _tick_phi(i, _ticks.size())
			var d := absf(angle_difference(phi, tp))
			if d < best:
				best = d
				idx = i if d < 0.16 else -1
	if idx != _hover:
		_hover = idx
		hover_changed.emit(_hover_text())


func _hover_text() -> String:
	if _hover < 0 or _hover >= _ticks.size():
		return ""
	var rec: Dictionary = _ticks[_hover]
	var label := String(rec.get("label", ""))
	var ago: int = maxi(0, EmberSigils.today() - int(rec.get("d", 0)))
	var line := "印记 · 第 %d 次点燃" % (_hover + 1)
	if label != "":
		line += " · %s" % label
	return "%s · %s" % [line, EmberSigils.ago_text(ago)]


func _draw() -> void:
	if _ticks.is_empty() or reveal <= 0.0:
		return
	var c := size * 0.5
	var rx := size.x * 0.5 - 6.0
	var ry := size.y * 0.5 - 6.0
	var a0 := deg_to_rad(float(MOUTH_DEG))
	var a1 := TAU - deg_to_rad(float(MOUTH_DEG))
	# ---- 铁环本体：沿椭圆 2px 台阶描一条暗铁线，随 reveal 从底心向两肩亮。
	var steps := 150
	var points := PackedVector2Array()
	for i in steps + 1:
		points.append(_ellipse_point(a0 + (a1 - a0) * float(i) / float(steps), rx, ry))
	var ring_col := Color(RUST.r, RUST.g, RUST.b, 0.40 + 0.10 * reveal)
	for i in points.size() - 1:
		var mid := float(i) / float(steps - 1)
		# 从底心向两肩显现：底弧先亮，肩部后亮。
		var t := absf(mid * 2.0 - 1.0)
		if t > reveal:
			continue
		draw_line(points[i], points[i + 1], ring_col, 1.0)
	# 尾端两粒铁帽。
	for phi in [a0, a1]:
		if reveal >= 0.999:
			_cap(_ellipse_point(phi, rx, ry))
	# ---- 底心凹口：「炉厅的钉」，整环唯一的固定记认（挂在副题正下方）。
	var notch_reveal := clampf(reveal * 1.6 - 0.3, 0.0, 1.0)
	if notch_reveal > 0.0:
		var bottom := _ellipse_point(PI, rx, ry)
		draw_rect(Rect2(bottom.x - 1.0, bottom.y - 7.0 * notch_reveal, 2.0,
				6.0 * notch_reveal), Color(0.52, 0.40, 0.30, 0.8 * notch_reveal))
		draw_rect(Rect2(bottom.x - 1.0, bottom.y - 2.0 - 7.0 * notch_reveal, 2.0, 2.0),
				Color(0.68, 0.52, 0.36, 0.9 * notch_reveal))
	# ---- 点燃刻度：旧铁渐冷，最新一枚烧着。
	var n := _ticks.size()
	var today := EmberSigils.today()
	for i in n:
		var per := clampf(reveal * float(n + 2) - float(i), 0.0, 1.0)
		if per <= 0.0:
			continue
		var phi := _tick_phi(i, n)
		var p := _ellipse_point(phi, rx, ry)
		var rec: Dictionary = _ticks[i]
		var age := maxf(0.0, float(today - int(rec.get("d", 0))))
		var cool := clampf(age / COOL_DAYS, 0.0, 1.0)
		var col := HOT.lerp(COLD, cool * 0.92)
		var is_newest := i == n - 1
		if is_newest:
			var flick := 0.72 + 0.28 * sin(_time * 7.3 + sin(_time * 2.9) * 1.7)
			col = MID.lerp(HOT, flick)
		col.a = (0.55 + 0.45 * (1.0 - cool)) * per
		# 沿法线方向的短刻度：外端亮、内端沉。
		var dir := (p - c).normalized()
		var inner := p - dir * 4.0
		var outer := p + dir * 3.0
		draw_line(inner, outer, col, 2.0)
		if is_newest:
			# 一粒 2px 余烬芯 + 十字微光。
			draw_rect(Rect2(p - Vector2(1.0, 1.0), Vector2(2.0, 2.0)),
					Color(1.0, 0.94, 0.72, 0.95 * per))
			draw_rect(Rect2(p - Vector2(3.0, 0.0), Vector2(6.0, 1.0)),
					Color(1.0, 0.7, 0.25, 0.30 * per))
			draw_rect(Rect2(p - Vector2(0.0, 3.0), Vector2(1.0, 6.0)),
					Color(1.0, 0.7, 0.25, 0.30 * per))
		# 悬停高亮：这一枚浮出来一点。
		if i == _hover:
			draw_rect(Rect2(p - Vector2(2.0, 2.0), Vector2(4.0, 4.0)),
					Color(1.0, 0.9, 0.6, 0.9))
	# ---- 殁痕：内圈锈红菱形，最新的一粒更亮。
	var dn := _marks.size()
	for i in dn:
		var per := clampf(reveal * float(dn + 2) - float(i) - 0.5, 0.0, 1.0)
		if per <= 0.0:
			continue
		var phi := _tick_phi(i, dn)
		var p := _ellipse_point(phi, rx - 9.0, ry - 9.0)
		var col := DEATH
		col.a = (0.55 if i < dn - 1 else 0.85) * per
		draw_rect(Rect2(p - Vector2(1.0, 2.0), Vector2(2.0, 4.0)), col)
		draw_rect(Rect2(p - Vector2(2.0, 1.0), Vector2(4.0, 2.0)), col)
		if i == dn - 1:
			draw_rect(Rect2(p - Vector2(0.0, 1.0), Vector2(1.0, 2.0)),
					Color(0.9, 0.5, 0.35, 0.9 * per))


func _cap(p: Vector2) -> void:
	draw_rect(Rect2(p - Vector2(1.0, 1.0), Vector2(3.0, 3.0)), Color(0.30, 0.22, 0.18, 0.8))
