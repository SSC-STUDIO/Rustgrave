extends Node2D
## 脚底椭圆阴影。挂在单位或玩家下面，不跟跳跃高度 z 一起抬走。

const ArenaCatalog := preload("res://scripts/data/arena_catalog.gd")


func _ready() -> void:
	show_behind_parent = true
	z_index = 0


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var host := get_parent()
	var height := 0.0
	if host != null and host.has_method(&"arena_z"):
		height = float(host.call(&"arena_z"))
	var metrics: Dictionary = ArenaCatalog.shadow_metrics(height)
	var rx := float(metrics.get("rx", 11.0))
	var ry := float(metrics.get("ry", 4.0))
	var alpha := minf(0.88, float(metrics.get("alpha", 0.5)) * 1.6)
	var pts := PackedVector2Array()
	var soft := PackedVector2Array()
	var steps := 12
	for i in steps:
		var ang := TAU * float(i) / float(steps)
		pts.append(Vector2(cos(ang) * rx, sin(ang) * ry))
		soft.append(Vector2(cos(ang) * rx * 1.4, sin(ang) * ry * 1.3))
	draw_colored_polygon(soft, Color(0.01, 0.004, 0.008, alpha * 0.5))
	draw_colored_polygon(pts, Color(0.015, 0.006, 0.01, alpha))
