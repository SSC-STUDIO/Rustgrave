extends Node
## Performance probe (evidence, not a gate): boots a real chapter in the real
## presentation shell, parks the camera at a few spots and samples Godot's own
## performance monitors. Reports avg/p95 FPS and draw calls per spot so the final
## report can say what was measured instead of guessing.
##
##   godot --path . --windowed --resolution 1920x1080 res://scenes/tools/PerfProbe.tscn -- --level=level01
##   ... -- --level=level08 --out=res://screenshots/peek/perf
##
## It is a measurement fixture: the knight is parked (no input), enemies are left
## running, weather/clock are live. Desktop window only, never headless.

const OUT := "res://screenshots/peek/perf"
const SPOTS := {
	"level01": [320.0, 640.0, 1200.0, 1750.0, 2350.0, 3250.0],
	"level02": [240.0, 960.0, 1760.0, 2360.0],
}
const DEFAULT_SPOTS: Array[float] = [320.0, 960.0, 1600.0, 2240.0]
const SETTLE_SECONDS := 1.2
const SAMPLE_SECONDS := 3.0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("PerfProbe needs a render target")
		get_tree().quit(2)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 兜底：任何情况下 3 分钟内退出，避免探针挂成后台僵尸进程。
	get_tree().create_timer(180.0, true, false, true).timeout.connect(func() -> void:
		printerr("perf probe: watchdog timeout")
		if is_inside_tree():
			get_tree().quit(3))
	var level_id := "level01"
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
	Engine.max_fps = 0  # measure what the renderer actually produces
	SaveData.save_path = out_dir + "/perf_save.cfg"
	SaveData.delete_save()
	SaveData.flags.clear()
	# 跳过开场分镜：性能测量要的是可操作的游戏世界，不是过场。
	SaveData.mark_flag("opening_seen")
	SaveData.mark_flag("wake")
	SaveData.pending_spawn = Vector2.INF
	SaveData.entering_from_checkpoint = false
	SaveData.ending = ""
	Director.abort()
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
	# 硬超时：测量夹具自己卡住时要失败退出，不能变成挂起的后台进程。
	var deadline := Time.get_ticks_msec() + 60000
	var camera := get_tree().get_first_node_in_group("game_camera") as GameCamera
	var player := get_tree().get_first_node_in_group("player") as Player
	if camera == null or player == null:
		printerr("perf probe: no camera/player")
		get_tree().quit(1)
		return
	var spots: Array = SPOTS.get(level_id, DEFAULT_SPOTS)
	# 测量时冻结 AI 与玩家物理：只量渲染/场景开销，避免"骑士被 Boss 打死→死亡重载
	# 换场景"把探针节点一起释放（那会让本轮测量崩在 await 上）。
	player.set_physics_process(false)
	player.health.invincible = true
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
		enemy.set_process(false)
	var rows: Array = []
	for x in spots:
		if Time.get_ticks_msec() > deadline:
			printerr("perf probe: deadline hit")
			break
		if not is_inside_tree():
			printerr("perf probe: scene replaced, stopping")
			break
		camera.global_position = Vector2(x, 220.0)
		camera.force_update_scroll()
		camera.set_physics_process(false)
		# 玩家停在安全区：镜头取景靠 camera，不让人走进 Boss 战场。
		player.global_position = Vector2(96.0, 320.0)
		await get_tree().create_timer(SETTLE_SECONDS).timeout
		if not is_inside_tree():
			break
		# 丢弃 2 秒预热：首次进入镜头会触发贴图懒加载 / 着色器编译，
		# 把它算进平均帧时间会得到"第一个机位总是最卡"的假结论。
		var warm_until := Time.get_ticks_usec() + 2_000_000
		while Time.get_ticks_usec() < warm_until:
			await get_tree().process_frame
		var frame_ms: Array[float] = []
		var draw_calls: Array[float] = []
		var nodes: Array[float] = []
		var start := Time.get_ticks_usec()
		while Time.get_ticks_usec() - start < int(SAMPLE_SECONDS * 1_000_000.0):
			await get_tree().process_frame
			if Time.get_ticks_msec() > deadline:
				break
			frame_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
					+ Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
			draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			nodes.append(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		camera.set_physics_process(true)
		rows.append(_summarize(x, frame_ms, draw_calls, nodes))
		print("PERF spot=%.0f %s" % [x, JSON.stringify(rows[rows.size() - 1])])
	var report := {
		"level": level_id,
		"window": "%dx%d" % [win_size.x, win_size.y],
		"world_viewport": "640x360",
		"renderer": RenderingServer.get_current_rendering_method(),
		"purpose": "desktop frame-time probe fixture, not a playthrough",
		"spots": rows,
	}
	var file := FileAccess.open("%s/perf_%s_%dx%d.json" % [out_dir, level_id, win_size.x, win_size.y],
			FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	SaveData.delete_save()
	get_tree().quit(0)


func _summarize(x: float, frame_ms: Array[float], draw_calls: Array[float],
		nodes: Array[float]) -> Dictionary:
	if frame_ms.is_empty():
		return {"x": x}
	var sorted: Array[float] = frame_ms.duplicate()
	sorted.sort()
	var total := 0.0
	for v in frame_ms:
		total += v
	var avg := total / float(frame_ms.size())
	var idx := int(clampf(roundf(float(sorted.size() - 1) * 0.95), 0.0,
			float(sorted.size() - 1)))
	var p95: float = float(sorted[idx])
	return {
		"x": x,
		"frames": frame_ms.size(),
		"fps_avg": snappedf(1000.0 / maxf(avg, 0.001), 0.1),
		"fps_from_p95": snappedf(1000.0 / maxf(p95, 0.001), 0.1),
		"frame_ms_avg": snappedf(avg, 0.01),
		"frame_ms_p95": snappedf(p95, 0.01),
		"draw_calls_avg": snappedf(_mean(draw_calls), 0.1),
		"nodes_avg": snappedf(_mean(nodes), 0.1),
	}


func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += v
	return total / float(values.size())
