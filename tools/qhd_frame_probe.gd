extends Node
## Real-renderer stationary-scene probe. Frame intervals include scheduling and
## rendering; CPU monitors are separate. This is not a full combat benchmark.

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	var level := "title"
	var size := Vector2i(2560, 1440)
	var out := "res://screenshots/acceptance/qhd-materials-20261025/performance"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			level = arg.trim_prefix("--level=")
		elif arg.begins_with("--win="):
			var parts := arg.trim_prefix("--win=").split("x")
			size = Vector2i(int(parts[0]), int(parts[1]))
		elif arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	get_tree().create_timer(60.0).timeout.connect(func() -> void: get_tree().quit(3))
	var window := get_tree().root
	window.mode = Window.MODE_WINDOWED
	window.position = Vector2i(-12000, -12000)
	window.size = size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	SaveData.save_path = out + "/probe_save.cfg"
	SaveData.flags.clear()
	SaveData.mark_flag("opening_seen")
	SaveData.mark_flag("wake")
	SaveData.pending_spawn = Vector2.INF
	SaveData.entering_from_checkpoint = false
	SaveData.ending = ""
	Director.abort()
	var raster: SubViewport
	if level == "title":
		var title := load("res://scenes/ui/TitleScreen.tscn").instantiate() as TitleScreen
		add_child(title)
		title._world.configure(TitleWorld.build_state({"has_save": true, "scene": GameContext.LEVELS["level10"]}))
		raster = title._world_viewport
	else:
		GameContext.pending_world_path = GameContext.LEVELS[level]
		var shell := load("res://scenes/ui/GamePresentation.tscn").instantiate() as GamePresentation
		add_child(shell)
		raster = shell.world_viewport
		await get_tree().process_frame
		Director.abort()
		Director.set_letterbox(false, true)
		var player := get_tree().get_first_node_in_group("player") as Player
		player.set_physics_process(false)
		player.health.invincible = true
		for enemy in get_tree().get_nodes_in_group("enemies"):
			enemy.set_physics_process(false)
			enemy.set_process(false)
		var camera := get_tree().get_first_node_in_group("game_camera") as GameCamera
		camera.set_physics_process(false)
		camera.global_position = Vector2(960, 220)
		camera.force_update_scroll()
	await get_tree().create_timer(2.0).timeout
	var intervals: Array[float] = []
	var cpu: Array[float] = []
	var draws: Array[float] = []
	var last := Time.get_ticks_usec()
	var start := last
	while Time.get_ticks_usec() - start < 4_000_000:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		intervals.append(float(now - last) / 1000.0)
		last = now
		cpu.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	intervals.sort()
	var report := {
		"level": level, "window": [size.x, size.y], "raster": [raster.size.x, raster.size.y],
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"frames": intervals.size(), "sample_seconds": 4,
		"frame_interval_mean_ms": _mean(intervals),
		"frame_interval_p95_ms": intervals[int(intervals.size() * 0.95)],
		"cpu_process_mean_ms": _mean(cpu), "draw_calls_mean": _mean(draws),
		"texture_memory_mib": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		"conditions": "offscreen window, vsync disabled, stationary camera, AI disabled; title act4; no combat or full-campaign guarantee",
	}
	var file := FileAccess.open("%s/%s_%dx%d.json" % [out, level, size.x, size.y], FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	print("QHD_PERFORMANCE ", JSON.stringify(report))
	get_tree().quit()


func _mean(values: Array[float]) -> float:
	var sum := 0.0
	for value in values:
		sum += value
	return sum / maxf(1.0, values.size())
