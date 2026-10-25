extends Node2D
## 基地泉水。治疗由单位自己按距离结算；这个节点画水盆 / 火盆和治疗圈。

const ArenaCatalog := preload("res://scripts/data/arena_catalog.gd")
const FlameScript := preload("res://scripts/levels/arena_flame.gd")

var team: String = "player"


func configure(cfg: Dictionary) -> void:
	team = String(cfg.get("team", team))
	var pos_v: Variant = cfg.get("pos", position)
	if pos_v is Vector2:
		position = pos_v as Vector2
	set_name("Fountain_" + team)
	z_index = -2
	var flame: Sprite2D = FlameScript.new()
	flame.name = "WellFlame"
	flame.position = Vector2(0, -18)
	flame.scale = Vector2(2, 2)
	if team == ArenaCatalog.TEAM_ENEMY:
		flame.modulate = Color(1.45, 0.62, 0.28, 1.0)
	else:
		flame.modulate = Color(0.62, 0.82, 1.35, 1.0)
	add_child(flame)
	queue_redraw()


func contains_point(world_point: Vector2) -> bool:
	return ArenaCatalog.near_fountain(world_point, global_position)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var cool := team != ArenaCatalog.TEAM_ENEMY
	var water := Color(0.45, 0.75, 1.15, 0.85)
	var stone := Color(0.46, 0.5, 0.58)
	var rim := Color(0.72, 0.8, 0.95)
	if not cool:
		water = Color(1.15, 0.38, 0.18, 0.9)
		stone = Color(0.48, 0.26, 0.18)
		rim = Color(0.95, 0.55, 0.28)
	var rx := ArenaCatalog.FOUNTAIN_RADIUS
	# 治疗圈：呼吸脉冲，单位走进这个半径就回血。
	var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.0035)
	draw_arc(Vector2(0, 6), rx, 0.0, TAU, 40, Color(water.r, water.g, water.b, 0.28 + pulse * 0.25), 1.5)
	draw_arc(Vector2(0, 6), rx * (0.55 + pulse * 0.3), 0.0, TAU, 28, Color(water.r, water.g, water.b, 0.35 * (1.0 - pulse)), 1.0)
	# 水盆：宽沿浅盆。
	draw_colored_polygon(PackedVector2Array([
		Vector2(-56, -8), Vector2(56, -8), Vector2(68, 10), Vector2(-68, 10),
	]), stone)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-44, -3), Vector2(44, -3), Vector2(50, 7), Vector2(-50, 7),
	]), water)
	draw_rect(Rect2(-60, -10, 120, 3), rim)
	draw_rect(Rect2(-60, -10, 4, 14), Color(rim.r * 0.7, rim.g * 0.7, rim.b * 0.7))
	draw_rect(Rect2(56, -10, 4, 14), Color(rim.r * 0.55, rim.g * 0.55, rim.b * 0.55))
	draw_rect(Rect2(-16, -16, 32, 6), stone)
	draw_rect(Rect2(-16, -16, 32, 2), rim)


func _ellipse(center: Vector2, rx: float, ry: float, color: Color) -> void:
	var pts := PackedVector2Array()
	var steps := 14
	for i in steps:
		var ang := TAU * float(i) / float(steps)
		pts.append(center + Vector2(cos(ang) * rx, sin(ang) * ry))
	draw_colored_polygon(pts, color)
