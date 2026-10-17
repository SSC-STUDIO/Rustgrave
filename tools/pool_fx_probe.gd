extends Node2D
## 近距离检查毒池气泡/涟漪的读感（不加载关卡）：
##   godot --path . --windowed --resolution 1280x720 res://scenes/tools/PoolFxProbe.tscn

const OUT := "res://screenshots/peek/pool-fx"
var _pool: ToxinPool


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var win := get_tree().root
	win.mode = Window.MODE_WINDOWED
	win.position = Vector2i(-12000, -12000)
	win.size = Vector2i(1280, 720)
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.08, 0.12)
	bg.size = Vector2(640, 360)
	add_child(bg)
	var cam := Camera2D.new()
	cam.position = Vector2(0, 0)
	cam.zoom = Vector2(2, 2)
	add_child(cam)
	cam.make_current()
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	WorldClock.set_weather(WorldClock.Weather.HAZE, true)
	_pool = ToxinPool.new()
	_pool.position = Vector2(0, 20)
	_pool.sludge_ramp = []
	add_child(_pool)
	_pool.configure(Vector2(120, 36))
	await get_tree().create_timer(4.0).timeout
	await _capture("pool_haze")
	WorldClock.set_weather(WorldClock.Weather.RAIN, true)
	await get_tree().create_timer(3.0).timeout
	await _capture("pool_rain")
	# 气泡计数
	var bubbles := 0
	for c in _pool.get_children():
		if c is Fx.ToxinBubble:
			bubbles += 1
	print("POOLFX bubbles=", bubbles, " vapor=",
			(_pool.get_node_or_null("Vapor").get_child_count() if _pool.get_node_or_null("Vapor") else -1))
	get_tree().quit(0)


func _capture(id: String) -> void:
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT, id])
	print("POOLFX capture ", id, " err=", err)
