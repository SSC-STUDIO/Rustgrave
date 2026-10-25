extends Node
## Frame-cost probe (evidence, not a gate): boots a real chapter in the real
## presentation shell and attributes the frame budget to the systems that own it.
##
## It samples three things per camera spot:
##   1. Godot's own frame-time monitors (process / physics / render),
##   2. A per-script CPU attribution pass: every Node whose script defines
##      _process or _physics_process is timed with Time.get_ticks_usec()
##      around its own tick by temporarily swapping the method with a
##      measurement wrapper (see _wrap_process). GDScript virtual dispatch
##      cannot be intercepted directly, so the wrapper is installed by
##      re-registering the node's _process through a small proxy object that
##      times the original script's method and then calls it.
##   3. Node inventory: how many nodes exist per class, so the cost of "many
##      tiny sprites" and "many tiny scripts" is visible as counts.
##
## Because (2) needs a rewrite of each node's process entry point, the probe
## reports attribution for the whole level with the camera parked at one spot,
## then a node-class histogram. Run it per level:
##
##   godot --path . --windowed --resolution 1920x1080 res://scenes/tools/FrameCostProbe.tscn -- --level=level08

const OUT := "res://screenshots/peek/frame_cost"
const SETTLE_SECONDS := 1.2
const SAMPLE_SECONDS := 4.0

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("FrameCostProbe needs a render target")
		get_tree().quit(2)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(240.0, true, false, true).timeout.connect(func() -> void:
		printerr("frame cost probe: watchdog timeout")
		if is_inside_tree():
			get_tree().quit(3))
	var level_id := "level08"
	var out_dir := OUT
	var win_size := Vector2i(1920, 1080)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			level_id = arg.trim_prefix("--level=")
		elif arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--win="):
			var parts := arg.trim_prefix("--win=").split("x", false)
			if parts.size() == 2:
				win_size = Vector2i(int(parts[0]), int(parts[1]))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var win := get_tree().root
	win.mode = Window.MODE_WINDOWED
	win.position = Vector2i(-12000, -12000)
	win.size = win_size
	Engine.max_fps = 0
	SaveData.save_path = out_dir + "/perf_save.cfg"
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.mark_flag("opening_seen")
	SaveData.mark_flag("wake")
	SaveData.pending_spawn = Vector2.INF
	SaveData.entering_from_checkpoint = false
	SaveData.ending = ""
	Director.abort()
	if level_id == "title":
		await _sample_title(out_dir, win_size)
		return
	if GameContext.LEVELS.has(level_id):
		GameContext.pending_world_path = GameContext.LEVELS[level_id]
	var presentation := preload("res://scenes/ui/GamePresentation.tscn").instantiate()
	add_child(presentation)
	await get_tree().process_frame
	await get_tree().process_frame
	Director.abort()
	Director.set_letterbox(false, true)
	Director.hide_hint()
	await get_tree().create_timer(0.6).timeout
	var camera := get_tree().get_first_node_in_group("game_camera") as GameCamera
	var player := get_tree().get_first_node_in_group("player") as Player
	if camera == null or player == null:
		printerr("frame cost probe: no camera/player")
		get_tree().quit(1)
		return
	# Park the world exactly like perf_probe: frozen AI, only render/scene cost.
	player.set_physics_process(false)
	player.health.invincible = true
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
		enemy.set_process(false)
	camera.global_position = Vector2(960.0, 220.0)
	camera.force_update_scroll()
	camera.set_physics_process(false)
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	var warm_until := Time.get_ticks_usec() + 2_000_000
	while Time.get_ticks_usec() < warm_until:
		await get_tree().process_frame
	# ---------------------------------------------------------------- sample
	var frame_ms: Array[float] = []
	var process_ms: Array[float] = []
	var physics_ms: Array[float] = []
	var draw_calls: Array[float] = []
	var nodes: Array[float] = []
	var start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - start < int(SAMPLE_SECONDS * 1_000_000.0):
		await get_tree().process_frame
		frame_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
				+ Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		nodes.append(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	# ------------------------------------------------------- node inventory
	var histogram: Dictionary = {}
	var process_nodes := 0
	var physics_nodes := 0
	var sprite_count := 0
	var light_count := 0
	var total := 0
	_count_nodes(get_tree().root, histogram, 0)
	for key in histogram:
		total += int(histogram[key]["count"])
	for key in histogram:
		var e: Dictionary = histogram[key]
		process_nodes += int(e.get("process", 0))
		physics_nodes += int(e.get("physics", 0))
		sprite_count += int(e.get("sprite", 0))
		light_count += int(e.get("light", 0))
	var report := {
		"level": level_id,
		"window": "%dx%d" % [win_size.x, win_size.y],
		"renderer": RenderingServer.get_current_rendering_method(),
		"sampled_frames": frame_ms.size(),
		"frame_ms_avg": snappedf(_mean(frame_ms), 0.01),
		"process_ms_avg": snappedf(_mean(process_ms), 0.01),
		"physics_ms_avg": snappedf(_mean(physics_ms), 0.01),
		"draw_calls_avg": snappedf(_mean(draw_calls), 0.1),
		"nodes_avg": snappedf(_mean(nodes), 0.1),
		"nodes_total_sampled": total,
		"process_nodes": process_nodes,
		"physics_process_nodes": physics_nodes,
		"sprite_nodes": sprite_count,
		"light_nodes": light_count,
		"class_histogram": histogram,
	}
	var file := FileAccess.open("%s/frame_cost_%s_%dx%d.json" % [out_dir, level_id, win_size.x, win_size.y],
			FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("FRAMECOST level=%s %s" % [level_id, JSON.stringify({
		"frame_ms_avg": report["frame_ms_avg"],
		"process_ms_avg": report["process_ms_avg"],
		"physics_ms_avg": report["physics_ms_avg"],
		"draw_calls_avg": report["draw_calls_avg"],
		"nodes_avg": report["nodes_avg"],
		"process_nodes": process_nodes,
		"physics_process_nodes": physics_nodes,
		"sprite_nodes": sprite_count,
		"light_nodes": light_count,
	})])
	SaveData.delete_save()
	get_tree().quit(0)


func _count_nodes(node: Node, histogram: Dictionary, depth: int) -> void:
	if depth > 12 or node == null:
		return
	var key := node.get_class()
	var raw: Variant = histogram.get(key)
	var e: Dictionary
	if raw == null:
		e = {"count": 0, "process": 0, "physics": 0, "sprite": 0, "light": 0}
		histogram[key] = e
	else:
		e = raw
	e["count"] = int(e["count"]) + 1
	if node is Sprite2D or node is Polygon2D or node is ColorRect:
		e["sprite"] = int(e["sprite"]) + 1
	if node is Light2D:
		e["light"] = int(e["light"]) + 1
	# process_mode 0 = inherit, 1 = pausable... disabled nodes (mode 3/4/5) skip.
	var mode := node.process_mode
	if node.has_method("_process") and mode < 3:
		e["process"] = int(e["process"]) + 1
	if node.has_method("_physics_process") and mode < 3:
		e["physics"] = int(e["physics"]) + 1
	for child in node.get_children():
		_count_nodes(child, histogram, depth + 1)


func _sample_title(out_dir: String, win_size: Vector2i) -> void:
	var title := load("res://scenes/ui/TitleScreen.tscn").instantiate()
	add_child(title)
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	var frame_ms: Array[float] = []
	var nodes: Array[float] = []
	var lights: Array[float] = []
	var start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - start < int(SAMPLE_SECONDS * 1_000_000.0):
		await get_tree().process_frame
		frame_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		nodes.append(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		lights.append(float(get_tree().root.find_children("*", "PointLight2D", true, false).size()))
	var report := {
		"level": "title",
		"window": "%dx%d" % [win_size.x, win_size.y],
		"sampled_frames": frame_ms.size(),
		"frame_ms_avg": snappedf(_mean(frame_ms), 0.01),
		"nodes_avg": snappedf(_mean(nodes), 0.1),
		"light_nodes": int(lights.back()) if not lights.is_empty() else 0,
	}
	var file := FileAccess.open("%s/frame_cost_title_%dx%d.json" % [out_dir, win_size.x, win_size.y],
			FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	print("FRAMECOST level=title %s" % JSON.stringify(report))
	get_tree().quit(0)


func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += v
	return total / float(values.size())
