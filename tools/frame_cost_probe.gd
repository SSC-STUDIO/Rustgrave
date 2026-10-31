extends Node
## Off-screen render-callback cadence is separate from CPU monitors and physical
## presentation FPS. No GPU timer or per-script attribution is implemented.
const OUT := "res://screenshots/acceptance/overhaul-v3/title-perf/probes"

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("FrameCostProbe needs a render target")
		get_tree().quit(2)
		return
	get_tree().create_timer(180.0, true, false, true).timeout.connect(func() -> void:
		push_error("frame cost probe watchdog timeout")
		get_tree().quit(3))
	var level_id := "level08"
	var variant := "cold"
	var out_dir := OUT
	var win_size := Vector2i(1920, 1080)
	var active := false
	var keyart := false
	var seconds := 4.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			level_id = arg.trim_prefix("--level=")
		elif arg.begins_with("--variant="):
			variant = arg.trim_prefix("--variant=")
		elif arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--sample="):
			seconds = maxf(1.0, float(arg.trim_prefix("--sample=")))
		elif arg.begins_with("--win="):
			var parts := arg.trim_prefix("--win=").split("x", false)
			if parts.size() == 2:
				win_size = Vector2i(int(parts[0]), int(parts[1]))
		elif arg == "--active":
			active = true
		elif arg == "--keyart":
			keyart = true
	if level_id != "title" and not GameContext.LEVELS.has(level_id):
		push_error("unknown probe level: " + level_id)
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	SaveData.save_path = out_dir + "/probe_save.cfg"
	Settings.save_path = out_dir + "/probe_settings.cfg"
	SaveData.delete_save()
	SaveData.flags = PackedStringArray(["opening_seen", "wake", "boss_intro"])
	SaveData.pending_spawn = Vector2.INF
	SaveData.entering_from_checkpoint = false
	SaveData.ending = ""
	Director.abort()
	var win := get_tree().root
	win.mode = Window.MODE_WINDOWED
	win.position = Vector2i(-12000, -12000)
	win.size = win_size
	var camera_position := Vector2.ZERO
	var player_feet := Vector2.ZERO
	var title_state: Dictionary = {}
	if level_id == "title":
		var flags: Array = []
		for id in GameContext.LEVEL_ORDER:
			flags.append(String(StoryFlow.DONE_FLAGS[id]))
		TitleWorld.forced_state = {}
		if variant != "cold":
			var fixture := ConfigFile.new()
			fixture.set_value("meta", "version", 3)
			fixture.set_value("meta", "scene", GameContext.LEVELS["level10"])
			fixture.set_value("meta", "ending", variant)
			fixture.set_value("story", "flags", flags)
			fixture.set_value("player", "origin", "ember_vanguard")
			fixture.set_value("profile", "ember_rank", 4)
			fixture.set_value("profile", "skin_id", "skin_fantasy_knight")
			fixture.save(SaveData.save_path)
		title_state = TitleWorld.state_from_save()
		var title := preload("res://scenes/ui/TitleScreen.tscn").instantiate() as TitleScreen
		title.live_scene_enabled = not keyart
		add_child(title)
		await get_tree().process_frame
		title._skip_intro()
	else:
		GameContext.pending_world_path = GameContext.LEVELS[level_id]
		add_child(preload("res://scenes/ui/GamePresentation.tscn").instantiate())
		await get_tree().create_timer(0.6).timeout
		Director.abort()
		Director.set_letterbox(false, true)
		Director.hide_hint()
		var camera := get_tree().get_first_node_in_group("game_camera") as GameCamera
		var player := get_tree().get_first_node_in_group("player") as Player
		if camera == null or player == null:
			push_error("frame cost probe: missing camera/player")
			get_tree().quit(1)
			return
		player.set_physics_process(false)
		player.health.invincible = true
		camera.set_physics_process(false)
		camera_position = camera.global_position
		player_feet = player.global_position
		if not active:
			for enemy in get_tree().get_nodes_in_group("enemies"):
				enemy.process_mode = Node.PROCESS_MODE_DISABLED
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if not await _settle_window(win_size):
		return
	await get_tree().create_timer(2.0).timeout
	# No texture readback in the sample loop. CPU monitors are not added together.
	var intervals: Array[float] = []
	var cpu: Array[float] = []
	var physics: Array[float] = []
	var draws: Array[float] = []
	var fps: Array[float] = []
	await RenderingServer.frame_post_draw
	var start := Time.get_ticks_usec()
	var previous := start
	var drawn_start := Engine.get_frames_drawn()
	while Time.get_ticks_usec() - start < int(seconds * 1_000_000.0):
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		intervals.append(float(now - previous) / 1000.0)
		previous = now
		cpu.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		fps.append(Performance.get_monitor(Performance.TIME_FPS))
	var elapsed := float(previous - start) / 1_000_000.0
	var histogram: Dictionary = {}
	_count_nodes(get_tree().root, histogram)
	var image := win.get_texture().get_image()
	var mode := "keyart" if keyart else "live"
	var label := level_id + ("_" + variant + "_" + mode if level_id == "title" else "_active" if active else "_frozen")
	var stem := "%s/frame_cost_%s_%dx%d" % [out_dir, label, win_size.x, win_size.y]
	image.save_png(stem + ".png")
	var report := {"level": level_id, "variant": variant if level_id == "title" else "entry_camera",
		"mode": mode if level_id == "title" else "active_ai" if active else "frozen_ai",
		"limitations": "Off-screen render callbacks, not physical presentation FPS; no GPU timer or per-script attribution. Fixed entry camera, no traversal or worst-case guarantee.",
		"window": [win.size.x, win.size.y], "actual_render_size": [image.get_width(), image.get_height()],
		"renderer": RenderingServer.get_current_rendering_method(), "display_server": DisplayServer.get_name(),
		"vsync_mode": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps,
		"sample_seconds": elapsed, "sampled_callbacks": intervals.size(),
		"rendered_frames_delta": Engine.get_frames_drawn() - drawn_start,
		"render_callbacks_per_second": float(intervals.size()) / maxf(elapsed, 0.001),
		"callback_interval_ms_mean": _mean(intervals), "callback_interval_ms_p50": _percentile(intervals, 0.5),
		"callback_interval_ms_p95": _percentile(intervals, 0.95), "callback_interval_ms_max": intervals.max(),
		"process_monitor_ms_mean": _mean(cpu), "physics_monitor_ms_mean": _mean(physics),
		"engine_fps_monitor_mean": _mean(fps), "draw_calls_mean": _mean(draws),
		"object_node_monitor": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"camera_position": [camera_position.x, camera_position.y], "player_feet": [player_feet.x, player_feet.y],
		"title_state": title_state,
		"class_histogram": histogram, "callback_intervals_ms": intervals}
	var file := FileAccess.open(stem + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("FRAMECOST ", label, " callbacks_per_sec=", report["render_callbacks_per_second"],
		" interval_p95_ms=", report["callback_interval_ms_p95"], " actual=", image.get_size())
	SaveData.delete_save()
	get_tree().quit(0)

func _settle_window(wanted: Vector2i) -> bool:
	var win := get_tree().root
	var stable := 0
	for frame in 120:
		if win.mode != Window.MODE_WINDOWED or win.size != wanted:
			win.mode = Window.MODE_WINDOWED
			win.size = wanted
			win.position = Vector2i(-12000, -12000)
			stable = 0
		await RenderingServer.frame_post_draw
		stable = stable + 1 if win.size == wanted and win.get_texture().get_image().get_size() == wanted else 0
		if stable >= 3:
			return true
	push_error("frame cost probe render size did not settle")
	get_tree().quit(1)
	return false

func _count_nodes(node: Node, histogram: Dictionary) -> void:
	var key := node.get_class()
	if not histogram.has(key):
		histogram[key] = {"count": 0, "process": 0, "physics": 0}
	histogram[key]["count"] += 1
	if node.is_processing() and node.can_process():
		histogram[key]["process"] += 1
	if node.is_physics_processing() and node.can_process():
		histogram[key]["physics"] += 1
	for child in node.get_children():
		_count_nodes(child, histogram)

func _mean(values: Array[float]) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total / maxf(1.0, float(values.size()))

func _percentile(values: Array[float], quantile: float) -> float:
	var ordered := values.duplicate()
	ordered.sort()
	return ordered[clampi(ceili(float(ordered.size()) * quantile) - 1, 0, ordered.size() - 1)]
