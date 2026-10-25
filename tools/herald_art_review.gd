extends Node
## Staged art review in the actual level; deliberately NOT input acceptance.
## AI is frozen and real attack-step selectors are driven directly for portraits.

const ERRORS := preload("res://tests/error_collector.gd")
const OUT := "res://screenshots/acceptance/overhaul-v3/original-bosses/herald-portraits"


func _ready() -> void:
	var errors = ERRORS.new()
	OS.add_logger(errors)
	SaveData.save_path = "user://herald_art_review.cfg"
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.mark_flag("wake")
	SaveData.mark_flag("opening_seen")
	GameContext.pending_world_path = GameContext.LEVELS["level09b"]
	add_child(load(GameContext.PRESENTATION_PATH).instantiate())
	for i in 10: await get_tree().process_frame
	if not await _settle_window():
		get_tree().quit(1)
		return
	Director.abort()
	Director.set_letterbox(false, true)
	var player := get_tree().get_first_node_in_group("player") as Player
	var world := GameContext.world_root(player)
	var boss := world.find_child("EmberwindHerald", true, false) as Node2D
	var camera := get_tree().get_first_node_in_group("game_camera") as GameCamera
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
		enemy.set_process(false)
	(boss.call("boss_director") as BossDirector).set_physics_process(false)
	player.set_physics_process(false)
	player.health.invincible = true
	player.cutscene_locked = true
	camera.set_physics_process(false)
	camera.limit_left = -100000
	camera.limit_right = 100000
	camera.limit_top = -100000
	camera.limit_bottom = 100000
	camera.position_smoothing_enabled = false
	var origin := boss.global_position
	var floor_y := float(boss.get("_floor_y"))
	player.global_position = Vector2(origin.x - 150.0, floor_y)
	WorldClock.set_time(0.35)
	WorldClock.set_weather(WorldClock.Weather.HAZE, true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var records: Array = []
	for hot in [false, true]:
		for action in ["idle", "dive", "wind_push", "feather_blades", "updraft", "downed"]:
			boss.call("_interrupt_attack")
			boss.set("_state", 0)
			boss.set("_downed_left", 0.0)
			boss.set("_enraged", hot)
			boss.set("_facing", -1.0)
			boss.global_position = origin
			if action == "downed":
				boss.call("yank_to", Vector2(origin.x,floor_y))
			elif action != "idle":
				boss.call("_begin_attack", StringName(action))
				boss.set("_step", 1)
			else:
				boss.set("_state", 0)
			boss.call("_update_visuals", 0.18)
			for marker in get_tree().get_nodes_in_group("combat_markers"):
				if marker is CanvasItem: marker.visible = false
			Director.abort()
			Director.set_letterbox(false, true)
			camera.global_position = Vector2(origin.x - 35.0, floor_y - 115.0)
			camera.offset = Vector2.ZERO
			camera.reset_smoothing()
			camera.force_update_scroll()
			for i in 3: await RenderingServer.frame_post_draw
			var key: String = ("hot_" if hot else "") + action
			var im := get_viewport().get_texture().get_image()
			var result := im.save_png(OUT + "/" + key + ".png")
			records.append({"pose":key,"size":str(im.get_size()),"saved":result == OK})
	var report := {"purpose":"staged original art review, not input acceptance", "captures":records,
		"engine_errors":errors.errors(),"completed":true}
	FileAccess.open(OUT + "/report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("HERALD ART REVIEW ",JSON.stringify(report))
	get_tree().quit(0 if errors.errors().is_empty() else 1)


func _settle_window() -> bool:
	var win := get_tree().root
	var stable := 0
	for i in 120:
		if win.mode != Window.MODE_WINDOWED or win.size != Vector2i(1280,720):
			win.mode = Window.MODE_WINDOWED
			win.size = Vector2i(1280,720)
			win.position = Vector2i(-12000,-12000)
			stable = 0
		await RenderingServer.frame_post_draw
		stable = stable + 1 if win.get_texture().get_image().get_size() == Vector2i(1280,720) else 0
		if stable >= 3: return true
	push_error("Herald art review window failed to settle at 1280x720")
	return false
