extends Node
## VISUAL FIXTURES ONLY. Actors are placed and frozen; this is not a completion run.

var OUT := "res://screenshots/acceptance/display"
const PRESENTATION := preload("res://scenes/ui/GamePresentation.tscn")
const TITLE := preload("res://scenes/ui/TitleScreen.tscn")
const LOGGER := preload("res://tests/error_collector.gd")
const SIZES := [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160), Vector2i(1280, 800), Vector2i(3440, 1440), Vector2i(2560, 1600)]
## Supplement walks the whole corridor west→east; keep in sync with run_render_acceptance.ps1.
const SUPPLEMENT_PLACES := ["start", "pit", "mid", "gate", "east", "boss", "forge"]
## 4 main-loop captures at 2560×1600 + places × 3 weathers
## + pit_submerged + pause + controls + ending_caption + ending_choice.
const SUPPLEMENT_CAPTURES := 4 + 7 * 3 + 5
var _presentation: GamePresentation
var _world: Node
var _player: Player
var _camera: GameCamera
var _errors
var _report: Dictionary = {}
var _deadline: int


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if "--supplement" in OS.get_cmdline_user_args():
		OUT += "/supplement"
	_errors = LOGGER.new()
	OS.add_logger(_errors)
	_deadline = Time.get_ticks_msec() + 300000


func _process(_delta: float) -> void:
	if Time.get_ticks_msec() > _deadline:
		printerr("render acceptance timeout")
		get_tree().quit(2)


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Rendering acceptance requires a Windows/OpenGL render target, not --headless.")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var win := get_tree().root
	win.mode = Window.MODE_WINDOWED
	win.borderless = true
	win.position = Vector2i(-12000, -12000)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	seed(4096)
	WorldClock._rng.seed = 4096
	SaveData.save_path = OUT + "/fixture_save.cfg"
	SaveData.delete_save() # Dedicated fixture file; never the player's normal save.
	_presentation = PRESENTATION.instantiate()
	add_child(_presentation)
	_world = GameContext.world_root()
	_player = get_tree().get_first_node_in_group("player") as Player
	_camera = get_tree().get_first_node_in_group("game_camera") as GameCamera
	await _frames(5)
	Director.abort()
	Director.set_letterbox(false, true)
	WorldClock.time_scale = 0.0
	_player.set_physics_process(false)
	_player.cutscene_locked = true
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
	for area in _world.find_children("*", "Area2D", true, false):
		if area is AtmosphereZone:
			area.set_deferred("monitoring", false)
	_camera.set_physics_process(false)
	_report = {
		"captured_at_utc": Time.get_datetime_string_from_system(true),
		"purpose": "VISUAL FIXTURES: actor placement and clock/weather overrides; NOT a playthrough or completion proof",
		"capture_type": "native root render-target PNG from a window positioned offscreen; not a desktop screenshot",
		"display_server": DisplayServer.get_name(),
		"screen_size": _v(DisplayServer.screen_get_size()),
		"gpu": RenderingServer.get_video_adapter_name(),
		"gpu_vendor": RenderingServer.get_video_adapter_vendor(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"vsync": "disabled; wall frame timing includes driver/compositor/CPU scheduling",
		"resolutions": [], "title_screens": [], "timings": [], "errors": [],
	}
	var quick := "--quick" in OS.get_cmdline_user_args()
	var supplement := "--supplement" in OS.get_cmdline_user_args()
	var sizes := [Vector2i(1366, 768), Vector2i(1920, 1080)] if quick else SIZES
	if supplement:
		sizes = [Vector2i(2560, 1600)]
	_report["supplement"] = supplement
	_report["expected_capture_count"] = SUPPLEMENT_CAPTURES if supplement else sizes.size() * 4
	for requested in sizes:
		win.size = requested
		win.position = Vector2i(-12000, -12000)
		await _frames(20)
		_fixture("start", false)
		await get_tree().create_timer(0.6).timeout
		await _frames(45)
		await _capture(requested, "start_day")
		if requested == Vector2i(1920, 1080):
			await _capture_wing_pair()
		_fixture("start", true)
		await get_tree().create_timer(0.6).timeout
		await _frames(90)
		await _capture(requested, "start_night_rain")
		if requested in [Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]:
			await _benchmark(requested, 24 if quick else 180)
		_fixture("boss", true)
		await get_tree().create_timer(0.6).timeout
		await _frames(90)
		await _capture(requested, "boss_night_rain")
		_fixture("boss", false)
		await get_tree().create_timer(0.6).timeout
		await _frames(60)
		await _capture(requested, "boss_day")
	if supplement:
		await _supplement_captures()
	_presentation.queue_free()
	await _frames(3)
	var title := TITLE.instantiate() as TitleScreen
	add_child(title)
	for requested in sizes:
		win.size = requested
		win.position = Vector2i(-12000, -12000)
		await _frames(5)
		var image := win.get_texture().get_image()
		var actual := image.get_size()
		var name := "title_%dx%d.png" % [actual.x, actual.y]
		var png_error := image.save_png(OUT + "/" + name)
		var expected: Rect2 = PresentationMetrics.for_window(win)["physical_rect"]
		var bounds := _physical_bounds(title)
		var entry := {
			"requested": _v(requested), "rendered_image_size": _v(actual),
			"physical_content_rect": _rect(expected), "actual_title_rect": _rect(bounds),
			"png": name, "passed": (actual == requested or actual == Vector2i(1280, 720)) and png_error == OK,
		}
		_report["title_screens"].append(entry)
		print("TITLE_CAPTURE ", name, " passed=", entry["passed"])
	title.queue_free()
	await _frames(3)
	_report["errors"] = _errors.errors()
	_report["passed"] = (_report["errors"] as Array).is_empty()
	for entry in _report["resolutions"]:
		if not entry["passed"]:
			_report["passed"] = false
	for entry in _report["title_screens"]:
		if not entry["passed"]:
			_report["passed"] = false
	if not _report.get("wing_animation", {}).get("passed", false):
		_report["passed"] = false
	_report["completed"] = true
	var file := FileAccess.open(OUT + "/report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(_report, "\t"))
	file.close()
	print("ACCEPTANCE_REPORT ", ProjectSettings.globalize_path(OUT + "/report.json"), " passed=", _report["passed"])
	get_tree().quit(0 if _report["passed"] else 1)


func _fixture(place: String, night: bool, fog: bool = false) -> void:
	Director.abort()
	Director.set_letterbox(false, true)
	var player_x: Dictionary = {"start": 180, "pit": 376, "mid": 700, "gate": 1100, "east": 1470, "boss": 1770, "forge": 2052}
	var camera_x: Dictionary = {"start": 320, "pit": 460, "mid": 800, "gate": 1200, "east": 1460, "boss": 1920, "forge": 2112}
	_player.global_position = Vector2(float(player_x[place]), 320)
	_player.velocity = Vector2.ZERO
	_camera.global_position = Vector2(float(camera_x[place]), 220)
	_camera.offset = Vector2.ZERO
	_camera.rotation = 0.0
	_camera.zoom = Vector2.ONE
	_camera.force_update_scroll()
	WorldClock.set_time(0.85 if night else 0.35)
	WorldClock.set_weather(WorldClock.Weather.FOG if fog else (WorldClock.Weather.RAIN if night else WorldClock.Weather.HAZE), true)
	WorldClock.set_zone(WorldClock.Zone.INDOORS if place == "forge" else WorldClock.Zone.OUTDOORS)
	WorldClock.time_scale = 0.0
	var atmosphere := WorldAtmosphere.for_node(_player)
	if atmosphere != null:
		atmosphere.advance(10.0)
	for weather in _world.find_children("*", "CanvasLayer", true, false):
		if weather is WeatherFx:
			weather.set("_alpha", WorldClock.rain_opacity())
	GameEvents.interact_prompt.emit("")
	if place == "boss":
		GameEvents.boss_appeared.emit("炉约刽子手 · 视觉验收摆位", 13, 13)
	else:
		GameEvents.boss_defeated.emit()


func _frames(count: int) -> void:
	for i in count:
		await RenderingServer.frame_post_draw


func _capture(requested: Vector2i, fixture: String, overlays: Array[Control] = []) -> void:
	await RenderingServer.frame_post_draw
	var win := get_tree().root
	var image := win.get_texture().get_image()
	var actual := image.get_size()
	var name := "%s_%dx%d.png" % [fixture, actual.x, actual.y]
	var png_error := image.save_png(OUT + "/" + name)
	var metrics := PresentationMetrics.for_window(win)
	var expected: Rect2 = metrics["physical_rect"]
	var world_image_rect := _physical_bounds(_presentation.world_image)
	var hud := _presentation.find_child("HUD", true, false) as CanvasLayer
	if hud == null:
		hud = _world.find_child("HUD", true, false) as CanvasLayer
	var hud_root := hud.get_node("Root") as Control
	# HUD is authored inside the 640x360 world viewport and is rasterized into
	# WorldImage. Avoid applying the root-window transform a second time.
	var ui_bounds := expected if hud.get_viewport() == _presentation.world_viewport else _physical_bounds(hud_root)
	var widgets: Dictionary = {}
	for child_name in ["StatPanel", "BossBar", "Prompt", "Banner"]:
		var child := hud_root.get_node_or_null(child_name) as Control
		if child != null:
			widgets[child_name] = {"rect": _rect(_physical_bounds(child)), "visible": child.is_visible_in_tree()}
	var physics_world := _presentation.world_viewport.world_2d
	var overlay_bounds: Array = []
	var overlays_fit := true
	for overlay in overlays:
		var controls: Array[Node] = [overlay]
		controls.append_array(overlay.find_children("*", "Control", true, false))
		for node in controls:
			var control := node as Control
			if not control.is_visible_in_tree():
				continue
			var rect := _physical_bounds(control)
			var fits := expected.grow(0.5).encloses(rect)
			overlays_fit = overlays_fit and fits
			overlay_bounds.append({"node": String(control.get_path()), "rect": _rect(rect), "inside_content": fits})
	var bodies := _world.find_children("*", "CollisionObject2D", true, false)
	var wrong_world: Array[String] = []
	for body in bodies:
		if body.get_world_2d() != physics_world:
			wrong_world.append(String(body.get_path()))
	var render_target_ok := actual == requested or actual == Vector2i(1280, 720)
	var logical_world_size: Vector2i = metrics["world_size"]
	var passed := render_target_ok and win.size == requested and png_error == OK \
			and _presentation.world_viewport.size == PresentationMetrics.world_render_size(metrics) \
			and _presentation.world_viewport.size_2d_override == logical_world_size \
			and wrong_world.is_empty() and physics_world != win.world_2d \
			and overlays_fit
	var entry := {
		"fixture": fixture, "requested": _v(requested), "window_size": _v(win.size),
		"window_position": _v(win.position), "rendered_image_size": _v(actual),
		"world_viewport": _v(_presentation.world_viewport.size),
		"world_logical_view": _v(logical_world_size), "world_scale": metrics["scale"],
		"physical_content_rect": _rect(expected), "actual_world_image_rect": _rect(world_image_rect),
		"actual_hud_root_rect": _rect(ui_bounds), "hud_design_size": _v(hud_root.size),
		"widgets": widgets, "physics_body_count": bodies.size(), "wrong_world_nodes": wrong_world,
		"overlay_controls": overlay_bounds, "clock_time": WorldClock.time_of_day,
		"weather": WorldClock.weather, "zone": WorldClock.zone,
		"offscreen_positioned": true, "png": name, "passed": passed,
	}
	_report["resolutions"].append(entry)
	print("CAPTURE ", name, " passed=", passed, " world=", world_image_rect, " ui=", ui_bounds)


func _physical_bounds(control: Control) -> Rect2:
	return get_tree().root.get_final_transform() * control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)


func _supplement_captures() -> void:
	var size := Vector2i(1920, 1080)
	get_tree().root.size = size
	get_tree().root.position = Vector2i(-12000, -12000)
	await _frames(12)
	for place in SUPPLEMENT_PLACES:
		for weather in ["day", "night_rain", "fog"]:
			_fixture(place, weather == "night_rain", weather == "fog")
			await get_tree().create_timer(0.6).timeout
			await _frames(20)
			await _capture(size, "%s_%s" % [place, weather])
			if place == "start" and weather == "day":
				await _capture_wing_pair()
	_fixture("pit", false)
	_player.position = Vector2(456, 352)
	await _frames(8)
	await _capture(size, "pit_submerged")
	_fixture("forge", true)
	await _frames(10)
	var hud := _presentation.find_child("HUD", true, false) as CanvasLayer
	if hud == null:
		hud = _world.find_child("HUD", true, false) as CanvasLayer
	var pause := hud.get_node("PauseMenu") as PauseMenu
	pause.open()
	await _frames(5)
	await _capture(size, "pause_menu", [pause._root])
	pause._controls.open()
	await _frames(5)
	await _capture(size, "controls_menu", [pause._controls._root])
	pause._controls.close()
	pause.close()
	Director.set_letterbox(true, true)
	Director.caption().enqueue("余烬落回炉灰。骑士也是。", 20.0)
	Director.caption().skip()
	await _frames(8)
	await _capture(size, "ending_caption", [Director.caption()._panel])
	Director.abort()
	Director.set_letterbox(false, true)
	var heart := _world.find_child("ForgeHeart", true, false) as ForgeHeart
	if heart == null:
		heart = _presentation.find_child("ForgeHeart", true, false) as ForgeHeart
	heart._open_choice()
	await _frames(8)
	await _capture(size, "ending_choice", [heart._layer.get_node("ChoiceRoot") as Control])
	heart._layer.queue_free()
	heart._layer = null
	Director.choice_hold = false
	get_tree().paused = false
	Director.resume()


func _capture_wing_pair() -> void:
	var demon: FlyingDemonEnemy
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is FlyingDemonEnemy:
			demon = enemy
			break
	if demon == null or demon._anim == null:
		_report["wing_animation"] = {"passed": false, "reason": "visible flying demon missing"}
		return
	var frames: Array = []
	for index in 2:
		if index > 0:
			await get_tree().create_timer(0.15).timeout
		await RenderingServer.frame_post_draw
		var image := get_tree().root.get_texture().get_image()
		var name := "wing_%s_1920x1080.png" % ("a" if index == 0 else "b")
		var result := image.save_png(OUT + "/" + name)
		frames.append({"png": name, "texture": demon._anim.texture.resource_path,
			"animation": demon._anim.current(), "wall_ms": Time.get_ticks_msec(), "saved": result == OK})
	_report["wing_animation"] = {"frames": frames, "passed": frames[0]["texture"] != frames[1]["texture"] and frames[0]["saved"] and frames[1]["saved"],
		"note": "unmodified animation process at one frozen actor position; not combat acceptance"}


func _benchmark(requested: Vector2i, samples: int) -> void:
	await _frames(60)
	var frame_ms: Array[float] = []
	var last := Time.get_ticks_usec()
	for i in samples:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		frame_ms.append(float(now - last) / 1000.0)
		last = now
	frame_ms.sort()
	var sum := 0.0
	for value in frame_ms:
		sum += value
	_report["timings"].append({
		"fixture": "start_night_rain", "requested": _v(requested),
		"window_size": _v(get_tree().root.size), "world_viewport": [640, 360],
		"root_render_target": _v(get_tree().root.get_texture().get_image().get_size()),
		"texture_reported_size": _v(get_tree().root.get_texture().get_size()),
		"offscreen_positioned": true, "samples": samples, "warmup_frames": 150,
		"wall_frame_mean_ms": sum / samples, "wall_frame_median_ms": frame_ms[samples / 2],
		"wall_frame_p95_ms": frame_ms[mini(samples - 1, int(ceil(samples * 0.95)) - 1)],
		"wall_frame_max_ms": frame_ms.back(),
		"note": "warmup/loading and PNG encoding excluded; timings are wall frames, not isolated GPU time",
	})


func _v(value: Vector2) -> Array:
	return [value.x, value.y]


func _rect(value: Rect2) -> Array:
	return [value.position.x, value.position.y, value.size.x, value.size.y]
