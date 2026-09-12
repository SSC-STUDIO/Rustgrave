extends Node
## LIVE PEEK: the real presentation with the clock running, parked at a few
## camera spots for a few seconds each, then one PNG per spot. Unlike
## RenderAcceptance this does not freeze WorldClock, so ambient motion (vapor,
## leaves, sway, rain) shows up. Not an acceptance gate; no report.
##
##   tools/run_peek_live.ps1            (writes screenshots/peek/live_<spot>.png)
##   ... -- --spots=start,pit --hold=6  (subset / longer settle)
##   ... -- --lit                       (light every EmberNest first)
##   ... -- --night                     (night + rain instead of hazy day)
##   ... -- --weather=fog               (haze / rain / fog / ember_wind / rust_rain / clear)
##   ... -- --active                    (leave enemy AI / physics running)
##   ... -- --level=level02             (peek Level02; spots: shaft,pitb,ledge,hall,lift,nest2,bell)

const PRESENTATION := preload("res://scenes/ui/GamePresentation.tscn")
const OUT := "res://screenshots/peek"
const SPOTS := {
	"start": 320.0, "pit": 460.0, "mid": 800.0, "gate": 1200.0,
	"east": 1460.0, "boss": 1920.0, "forge": 2112.0,
}
const SPOTS_L2 := {
	"shaft": 240.0, "pitb": 600.0, "ledge": 960.0, "hall": 1260.0,
	"lift": 1490.0, "nest2": 1760.0, "gallery": 2080.0, "bell": 2360.0,
}


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("peek_live needs a render target; run without --headless")
		get_tree().quit(2)
		return
	var level_id := "level01"
	var out_dir := OUT
	var cam_y := 220.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			level_id = arg.trim_prefix("--level=")
		elif arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--cam_y="):
			cam_y = float(arg.trim_prefix("--cam_y="))
	var table: Dictionary = SPOTS
	if level_id == "level02":
		table = SPOTS_L2
	elif level_id != "level01":
		# Chapters: one spot per 640px screen unless --spots gives numbers.
		table = {}
		for i in 6:
			table["x%d" % (320 + i * 640)] = float(320 + i * 640)
	var spots: Array = table.keys()
	var hold := 4.0
	var lit := false
	var night := false
	var active := false
	var weather_id := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spots="):
			spots = arg.trim_prefix("--spots=").split(",", false)
		elif arg.begins_with("--hold="):
			hold = maxf(0.5, float(arg.trim_prefix("--hold=")))
		elif arg.begins_with("--weather="):
			weather_id = arg.trim_prefix("--weather=")
		elif arg == "--lit":
			lit = true
		elif arg == "--night":
			night = true
		elif arg == "--active":
			active = true
	if GameContext.LEVELS.has(level_id):
		GameContext.pending_world_path = GameContext.LEVELS[level_id]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var win := get_tree().root
	win.mode = Window.MODE_WINDOWED
	win.size = Vector2i(1920, 1080)
	win.position = Vector2i(-12000, -12000)
	SaveData.save_path = out_dir + "/peek_save.cfg"
	SaveData.delete_save()
	var presentation := PRESENTATION.instantiate()
	add_child(presentation)
	for i in 5:
		await RenderingServer.frame_post_draw
	Director.abort()
	Director.set_letterbox(false, true)
	var player := get_tree().get_first_node_in_group("player") as Player
	var camera := get_tree().get_first_node_in_group("game_camera") as GameCamera
	player.set_physics_process(false)
	player.cutscene_locked = true
	camera.set_physics_process(false)
	if not active:
		for enemy in get_tree().get_nodes_in_group("enemies"):
			enemy.set_physics_process(false)
			enemy.set_process(false)
	WorldClock.set_time(0.85 if night else 0.35)
	var weather := WorldClock.Weather.RAIN if night else WorldClock.Weather.HAZE
	if weather_id != "":
		weather = WorldClock.weather_from_id(weather_id)
	WorldClock.set_weather(weather, true)
	WorldClock.wind_heading = 1.0
	WorldClock._heading_target = 1.0
	WorldClock._snap_wind_speed()
	if lit:
		for nest in get_tree().get_nodes_in_group("ember_nests"):
			nest.apply_persistent_state({"lit": true})
	var suffix := ("_lit" if lit else "") + ("_night" if night else "") + ("_active" if active else "")
	if weather_id != "":
		suffix += "_" + weather_id
	if level_id != "level01":
		suffix = "_" + level_id + suffix
	for spot in spots:
		var x: float
		if table.has(spot):
			x = table[spot]
		elif String(spot).is_valid_float():
			x = float(spot)
		else:
			printerr("peek_live: unknown spot ", spot)
			continue
		camera.global_position = Vector2(x, cam_y)
		camera.force_update_scroll()
		# Park the knight at the camera height (vertical levels): floor y when cam_y is default.
		player.global_position = Vector2(x - 120.0, 320.0 if is_equal_approx(cam_y, 220.0) else cam_y + 100.0)
		await get_tree().create_timer(hold).timeout
		await RenderingServer.frame_post_draw
		var image := win.get_texture().get_image()
		var tag := "" if is_equal_approx(cam_y, 220.0) else "_y%d" % int(cam_y)
		var err := image.save_png("%s/live_%s%s%s.png" % [out_dir, spot, tag, suffix])
		print("PEEK ", spot, suffix, " saved=", err == OK)
	get_tree().quit(0)
