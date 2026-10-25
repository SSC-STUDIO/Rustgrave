extends Node2D
## 塔、水晶、精英的像素外观。石头画成浅灰，白标和火被父节点的 self_modulate 染成阵营色。
## 受击闪白走本节点的 modulate，不改 self_modulate。

const ArenaCatalog := preload("res://scripts/data/arena_catalog.gd")

var _unit: Node = null

var _stone := Color(0.72, 0.68, 0.64)
var _dark := Color(0.4, 0.36, 0.34)
var _light := Color(0.86, 0.82, 0.78)
var _mortar := Color(0.2, 0.16, 0.15)
var _ink := Color(0.1, 0.08, 0.09)
var _paper := Color(1.45, 1.45, 1.5)
var _flame := Color(2.3, 1.75, 0.95)


func bind(unit: Node) -> void:
	_unit = unit


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _unit == null:
		return
	var kind := String(_unit.get("unit_kind"))
	var living := bool(_unit.get("alive"))
	if not living:
		_rubble(kind)
		return
	if kind == "crystal":
		_crystal()
	elif kind == "elite":
		_elite()
	else:
		_tower()


func _tower() -> void:
	var blue := String(_unit.get("team")) != "enemy"
	var stone := Color(0.4, 0.5, 0.68) if blue else Color(0.6, 0.3, 0.2)
	var dark := Color(0.2, 0.26, 0.38) if blue else Color(0.3, 0.11, 0.08)
	var light := Color(0.6, 0.72, 0.95) if blue else Color(0.88, 0.45, 0.28)
	var band := Color(0.35, 0.72, 1.45) if blue else Color(1.45, 0.3, 0.12)
	# 三级基座。
	_rect(-36, -8, 72, 8, dark)
	_rect(-32, -14, 64, 6, stone)
	_rect(-36, -8, 72, 2, light)
	_rect(-28, -20, 56, 6, dark)
	# 塔身：右暗左亮，砖缝分层。
	_rect(-24, -68, 48, 48, stone)
	_rect(12, -68, 12, 48, dark)
	_rect(-24, -68, 5, 48, light)
	var course := -62
	while course < -22:
		_rect(-24, course, 48, 1, _mortar)
		course += 6
	# 门洞与门楣辉光。
	_rect(-8, -38, 16, 18, _ink)
	_rect(-8, -40, 16, 3, band)
	# 腰间队伍色带。
	_rect(-24, -52, 48, 5, band)
	_rect(-24, -52, 48, 1, light)
	# 上层收窄。
	_rect(-18, -96, 36, 28, stone)
	_rect(8, -96, 10, 28, dark)
	_rect(-18, -96, 4, 28, light)
	_rect(-18, -76, 36, 1, _mortar)
	# 垛口。
	var merlon := -20
	while merlon <= 12:
		_rect(merlon, -106, 7, 10, stone)
		_rect(merlon, -106, 7, 2, light)
		merlon += 9
	# 火盆与火。
	_rect(-12, -114, 24, 8, dark)
	_rect(-12, -114, 24, 2, band)
	_fire(0, -116, 1.6)
	# 正面挂旗：队伍色，燕尾，徽记。
	var bx := 16 if blue else -30
	_rect(bx, -88, 14, 30, band)
	_rect(bx, -88, 14, 2, light)
	_rect(bx + 3, -80, 8, 8, light)
	draw_colored_polygon(PackedVector2Array([
		Vector2(bx, -58), Vector2(bx + 14, -58), Vector2(bx + 7, -52),
	]), band)


func _crystal() -> void:
	var blue := String(_unit.get("team")) != "enemy"
	var gem := Color(0.4, 0.75, 1.6) if blue else Color(1.55, 0.32, 0.18)
	var edge := Color(0.75, 0.95, 1.8) if blue else Color(1.8, 0.65, 0.3)
	var core := Color(1.5, 1.7, 2.0) if blue else Color(2.0, 0.9, 0.4)
	var step_dark := Color(0.24, 0.27, 0.34) if blue else Color(0.32, 0.15, 0.11)
	var step_light := Color(0.48, 0.55, 0.66) if blue else Color(0.56, 0.27, 0.17)
	# 三级台阶基座。
	_rect(-26, -8, 52, 8, step_dark)
	_rect(-26, -8, 52, 2, step_light)
	_rect(-20, -15, 40, 7, step_dark)
	_rect(-20, -15, 40, 2, step_light)
	_rect(-14, -21, 28, 6, step_dark)
	_rect(-14, -21, 28, 2, step_light)
	# 晶簇：两侧碎晶拱卫主晶。
	draw_colored_polygon(PackedVector2Array([
		Vector2(-16, -21), Vector2(-6, -21), Vector2(-9, -46), Vector2(-14, -40),
	]), gem)
	draw_colored_polygon(PackedVector2Array([
		Vector2(6, -21), Vector2(16, -21), Vector2(14, -40), Vector2(9, -46),
	]), gem)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-7, -21), Vector2(7, -21), Vector2(5, -58), Vector2(0, -68), Vector2(-5, -58),
	]), gem)
	# 主晶受光棱线与内核。
	draw_colored_polygon(PackedVector2Array([
		Vector2(-2, -24), Vector2(3, -24), Vector2(2, -56), Vector2(0, -62), Vector2(-2, -56),
	]), core)
	_rect(-7, -21, 2, 30, edge)
	_rect(-14, -34, 2, 10, edge)
	_rect(12, -34, 2, 10, edge)
	_rect(-1, -74, 3, 6, core)
	var open := false
	if _unit != null:
		var team := String(_unit.get("team"))
		var index := int(_unit.get("structure_index"))
		open = ArenaRun.structure_vulnerable(team, index)
	if open:
		# 护罩碎了：晶簇更亮，顶部溅出火星。
		_rect(-20, -44, 3, 22, core)
		_rect(17, -44, 3, 22, core)
		_rect(-2, -84, 4, 8, core)
		var tick := int(Time.get_ticks_msec() / 90)
		var i := 0
		while i < 4:
			var ox := int(posmod(tick * (2 + i) + i * 7, 28)) - 14
			var oy := -70 - int(posmod(tick * (3 + i) + i * 5, 22))
			_rect(ox, oy, 2, 2, core)
			i += 1
	else:
		draw_arc(Vector2(0, -40), 30.0, 0.0, TAU, 22, Color(edge.r, edge.g, edge.b, 0.8), 2.5)
		draw_arc(Vector2(0, -40), 34.0, 0.0, TAU, 24, Color(edge.r, edge.g, edge.b, 0.3), 1.5)
		_lock(0, -24)


func _elite() -> void:
	var gold := Color(0.95, 0.72, 0.28)
	var dark := Color(0.4, 0.22, 0.1)
	_rect(-10, -6, 20, 6, dark)
	_rect(-9, -32, 18, 26, gold)
	_rect(4, -32, 5, 26, Color(0.55, 0.28, 0.1))
	_rect(-9, -46, 18, 14, Color(1.1, 0.85, 0.4))
	_rect(-4, -40, 8, 5, Color(0.15, 0.08, 0.05))
	_rect(-11, -50, 22, 5, Color(1.4, 0.45, 0.12))
	_rect(10, -62, 3, 36, dark)
	_rect(8, -70, 7, 10, Color(1.8, 0.55, 0.15))
	_rect(-12, -24, 4, 12, dark)
	_rect(8, -24, 4, 12, dark)


func _rubble(kind: String) -> void:
	_rect(-28, -8, 16, 8, _dark)
	_rect(-10, -14, 22, 14, _stone)
	_rect(10, -7, 16, 7, _mortar)
	_rect(-18, -18, 8, 6, _light)
	_rect(4, -20, 6, 6, _dark)
	var tick := int(Time.get_ticks_msec() / 70)
	var i := 0
	while i < 10:
		var ox := int(posmod(tick * (3 + i) + i * 5, 36)) - 18
		var oy := -18 - int(posmod(tick * (4 + i) + i * 7, 36))
		var hot := _flame
		if i % 2 == 0:
			hot = _paper
		_rect(ox, oy, 2, 2, hot)
		i += 1
	if kind == "crystal":
		_rect(-4, -24, 6, 8, _paper)


func _lock(cx: int, cy: int) -> void:
	_rect(cx - 5, cy, 10, 8, Color(0.9, 0.92, 1.0, 0.9))
	_rect(cx - 3, cy - 6, 2, 6, Color(0.95, 0.96, 1.0, 0.85))
	_rect(cx + 1, cy - 6, 2, 6, Color(0.95, 0.96, 1.0, 0.85))
	_rect(cx - 3, cy - 6, 6, 2, Color(0.95, 0.96, 1.0, 0.85))
	_rect(cx - 1, cy + 3, 2, 2, _ink)


func _fire(cx: int, cy: int, scale: float) -> void:
	var h := int(round(8.0 * scale))
	var w := int(round(4.0 * scale))
	var flick := int(Time.get_ticks_msec() / 120) % 3
	_rect(cx - w, cy - h + flick, w * 2, h, _flame)
	_rect(cx - 1, cy - h - 3 + flick, 2, 4, _paper)
	_rect(cx - w - 1, cy - 2, 2, 3, Color(2.0, 0.7, 0.3))
	_rect(cx + w - 1, cy - 3, 2, 3, Color(2.0, 0.7, 0.3))


func _rect(x: int, y: int, w: int, h: int, color: Color) -> void:
	draw_rect(Rect2(x, y, w, h), color)
