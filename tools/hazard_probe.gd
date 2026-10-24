extends Node2D
## 机关外观检查（不加载关卡）：每种机关在 休止 / 预警 / 判定早 / 中 / 晚 五个时刻的画面。
## 时间由本脚本逐步推进（机关 tick 直接驱动），不依赖实时：
##   godot --path . --windowed --resolution 1280x720 res://scenes/tools/HazardProbe.tscn -- --out=res://screenshots/...

const DEFAULT_OUT := "res://screenshots/acceptance/overhaul-v3/p1/hazards"
const VIEWS := [Vector2(260, 220), Vector2(900, 220), Vector2(1240, 220)]
## 目标时刻（秒）：与 common 里的 rest 2.0 / warn 0.8 / active 0.7 对齐。
const MOMENTS := [["rest", 1.2], ["warn", 2.5], ["active_early", 2.95], ["active_mid", 3.2], ["active_late", 3.45]]

var _out := DEFAULT_OUT
var _cyclics: Array[CyclicHazard] = []
var _others: Array = []
var _beam: CollapsingPlatform
var _cam: Camera2D


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	var win := get_tree().root
	win.mode = Window.MODE_WINDOWED
	win.position = Vector2i(-12000, -12000)
	win.size = Vector2i(1280, 720)
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.07, 0.08)
	bg.position = Vector2(-400, -200)
	bg.size = Vector2(2400, 800)
	bg.z_index = -20
	add_child(bg)
	_cam = Camera2D.new()
	_cam.zoom = Vector2(2, 2)
	add_child(_cam)
	_cam.make_current()
	WorldClock.set_zone(WorldClock.Zone.INDOORS)
	_build()
	await get_tree().process_frame
	await _run()
	get_tree().quit(0)


func _build() -> void:
	var host := Node2D.new()
	host.name = "Host"
	add_child(host)
	var layout := ChapterLayout.new()
	add_child(layout)
	layout.floor_strip(host, "Floor", -200.0, 1700.0, "iron")
	var common := {"rest_time": 2.0, "telegraph_time": 0.8, "active_time": 0.7, "hint_id": &""}
	_cyclics.append(layout.cyclic(host, "Steam", Vector2(80, 320), "steam", common))
	_cyclics.append(layout.cyclic(host, "Flame", Vector2(200, 320), "flame", common))
	_cyclics.append(layout.cyclic(host, "Slag", Vector2(320, 320), "slag", common))
	_cyclics.append(layout.cyclic(host, "Bell", Vector2(440, 320), "bell", common))
	var shock_props := common.duplicate()
	shock_props["thick"] = 200.0
	_cyclics.append(layout.cyclic(host, "Shock", Vector2(700, 320), "shock", shock_props))
	var side := common.duplicate()
	side["facing"] = Vector2.RIGHT
	side["reach"] = 72.0
	side["thick"] = 18.0
	_cyclics.append(layout.cyclic(host, "SideFlame", Vector2(580, 296), "flame", side))
	_others.append(layout.pendulum(host, "Swing", Vector2(830, 200), 100.0, {"hint_id": &""}))
	_beam = layout.collapsing(host, "Beam", Vector2(900, 272), 64.0, "iron_float", {"hint_id": &""})
	_others.append(_beam)
	_others.append(layout.conveyor(host, "Belt", Vector2(990, 288), 96.0, 36.0, "iron_float",
			{"hint_id": &""}))
	_others.append(layout.force_zone(host, "Gale", Rect2(1160, 200, 180, 120), "wind", Vector2(60, 0),
			{"auto_hint": false, "gust_period": 4.0, "gust_duty": 0.6}))
	for h in _cyclics:
		h.set_physics_process(false)
	for o in _others:
		o.set_physics_process(false)


func _run() -> void:
	var now := 0.0
	for moment in MOMENTS:
		var target: float = moment[1]
		var step := target - now
		now = target
		_advance(step)
		if moment[0] == "warn":
			_beam.trigger()
		await get_tree().process_frame
		for v in VIEWS.size():
			_cam.position = VIEWS[v]
			await get_tree().process_frame
			await _capture("%s_%d" % [moment[0], v])


func _advance(dt: float) -> void:
	# 小步推进，状态切换与动画都按真实节奏走一遍。
	var left := dt
	while left > 0.0:
		var s := minf(left, 0.05)
		for h in _cyclics:
			h.tick(s)
		for o in _others:
			o.tick(s)
		left -= s


func _capture(id: String) -> void:
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, id])
	print("HAZARDPROBE capture ", id, " err=", err)
