extends Node
## 诊断探针：在水边检查雨滴溅落特效在"非雨天"到底是谁在生成，并截图对比。
##   godot --path . --windowed --resolution 1920x1080 res://scenes/tools/WeatherSplashProbe.tscn

const OUT := "res://screenshots/peek/weather-probe"


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("needs render target")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var win := get_tree().root
	win.mode = Window.MODE_WINDOWED
	win.position = Vector2i(-12000, -12000)
	win.size = Vector2i(1920, 1080)
	SaveData.save_path = OUT + "/probe_save.cfg"
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.mark_flag("opening_seen")
	SaveData.mark_flag("wake")
	GameContext.pending_world_path = GameContext.WORLD_PATH
	var pres := preload("res://scenes/ui/GamePresentation.tscn").instantiate()
	add_child(pres)
	for _i in 10:
		await get_tree().process_frame
	Director.abort()
	Director.set_letterbox(false, true)
	Director.hide_hint()
	await get_tree().create_timer(0.6).timeout
	var camera := get_tree().get_first_node_in_group("game_camera") as GameCamera
	var player := get_tree().get_first_node_in_group("player") as Player
	if camera == null or player == null:
		printerr("no camera/player")
		get_tree().quit(1)
		return
	camera.set_physics_process(false)
	player.set_physics_process(false)
	player.health.invincible = true
	camera.global_position = Vector2(470.0, 250.0)
	camera.force_update_scroll()
	# 清成薄雾（默认"没下雨"）
	WorldClock.set_weather(WorldClock.Weather.HAZE, true)
	await get_tree().create_timer(8.0).timeout
	_report("haze-after-8s")
	await _capture("haze")
	# 下雨 4 秒，再放晴 1 秒 / 8 秒，观察残留
	WorldClock.set_weather(WorldClock.Weather.RAIN, true)
	await get_tree().create_timer(4.0).timeout
	_report("rain-4s")
	await _capture("rain")
	WorldClock.set_weather(WorldClock.Weather.HAZE, true)
	await get_tree().create_timer(1.0).timeout
	_report("haze-1s-after-rain")
	await _capture("haze_1s")
	await get_tree().create_timer(8.0).timeout
	_report("haze-9s-after-rain")
	await _capture("haze_9s")
	# 近景对照：3 倍放大池面，确认气泡读作"上浮的泡"而不是白色雨点/扩散环。
	if camera.has_method("set_zoom"):
		camera.call("set_zoom", Vector2(3.0, 3.0))
	else:
		camera.zoom = Vector2(3.0, 3.0)
	camera.global_position = Vector2(456.0, 316.0)
	camera.force_update_scroll()
	WorldClock.set_weather(WorldClock.Weather.HAZE, true)
	await get_tree().create_timer(4.0).timeout
	await _capture("closeup_haze")
	WorldClock.set_weather(WorldClock.Weather.RAIN, true)
	await get_tree().create_timer(3.0).timeout
	await _capture("closeup_rain")
	SaveData.delete_save()
	get_tree().quit(0)


func _report(tag: String) -> void:
	var world := get_tree().get_first_node_in_group("game_world")
	var wx := world.get_node_or_null("WeatherFx") as WeatherFx
	var rain_fx := world.get_node_or_null("RainGroundFx")
	var tox := world.get_node_or_null("Props/ToxinPool") as ToxinPool
	print("=== PROBE ", tag, " ===")
	print("weather=", WorldClock.weather_label(), " rain_opacity=%.3f" % WorldClock.rain_opacity(),
			" zone=", WorldClock.zone, " intensity=%.2f" % WorldClock.weather_intensity())
	if wx != null:
		print("WeatherFx splash_count=", wx.splash_count(), " ripple_count=", wx.ripple_count(),
				" wet=", wx.wet_mark_count())
	if rain_fx != null:
		for group in rain_fx.get_children():
			print("  RainGroundFx/", group.name, " children=", group.get_child_count())
	if tox != null:
		var vapor := tox.get_node_or_null("Vapor")
		print("ToxinPool vapor=", vapor.get_child_count() if vapor != null else -1,
				" children=", tox.get_child_count())
		for c in tox.get_children():
			if c is Sprite2D:
				print("  toxin sprite=", c.name, " tex=",
						(c as Sprite2D).texture.resource_path.get_file() if (c as Sprite2D).texture else "null",
						" alpha=", (c as Sprite2D).modulate.a)


func _capture(id: String) -> void:
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT, id])
	print("PROBE capture ", id, " err=", err)
