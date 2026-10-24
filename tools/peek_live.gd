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
##   ... -- --layers                    (also save live_<spot>_noback.png: the same frame with the
##                                       backdrop CanvasLayers hidden and time frozen, so a script can
##                                       mask play-layer pixels and measure play vs backdrop contrast)

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
	var win_size := Vector2i(1920, 1080)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			level_id = arg.trim_prefix("--level=")
		elif arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--cam_y="):
			cam_y = float(arg.trim_prefix("--cam_y="))
		elif arg.begins_with("--win="):
			var parts := arg.trim_prefix("--win=").split("x", false)
			if parts.size() == 2:
				win_size = Vector2i(int(parts[0]), int(parts[1]))
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
	var layers := false
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
		elif arg == "--layers":
			layers = true
	if GameContext.LEVELS.has(level_id):
		GameContext.pending_world_path = GameContext.LEVELS[level_id]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var win := get_tree().root
	win.mode = Window.MODE_WINDOWED
	win.size = win_size
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
	player.health.invincible = true # Parked render fixture, never an input run.
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
		# Camera fixtures must also respect rebuilt terrain. The old fixed y320
		# buried the actor in raised floors and left him floating over sunken ones.
		var feet := park_feet(GameContext.world_root(player), Vector2(x - 120.0, cam_y + 100.0))
		if not feet.is_finite():
			push_error("peek_live: no clear fixed support at camera " + str(spot))
			get_tree().quit(1)
			return
		player.global_position = feet
		GameEvents.interact_prompt.emit("")
		print("PEEK park ", spot, " feet=", feet, " (camera fixture)")
		await get_tree().create_timer(hold).timeout
		# Entering a boss trigger may stage an intro after the initial abort.
		# Capture the terrain after that presentation, and refresh the prompt
		# because the parked player does not run its usual physics interaction tick.
		Director.abort()
		Director.set_letterbox(false, true)
		player.cutscene_locked = true
		camera.global_position = Vector2(x, cam_y)
		camera.force_update_scroll()
		var focus := player.sensor.get_focus()
		GameEvents.interact_prompt.emit(focus.get_prompt(player) if focus != null else "")
		if layers:
			# Freeze motion so the two captures differ only where the backdrop shows through.
			Engine.time_scale = 0.0
			for i in 3:
				await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var image := win.get_texture().get_image()
		var tag := "" if is_equal_approx(cam_y, 220.0) else "_y%d" % int(cam_y)
		var err := image.save_png("%s/live_%s%s%s.png" % [out_dir, spot, tag, suffix])
		print("PEEK ", spot, suffix, " saved=", err == OK)
		if layers:
			var hidden := _hide_backdrops()
			for i in 3:
				await RenderingServer.frame_post_draw
			var bare := win.get_texture().get_image()
			bare.save_png("%s/live_%s%s%s_noback.png" % [out_dir, spot, tag, suffix])
			for layer in hidden:
				layer.visible = true
			Engine.time_scale = 1.0
	get_tree().quit(0)


## Nearest fixed support with room for the whole 14x26 knight body. Moving and
## temporary platform endpoints are unsuitable for a parked, physics-disabled actor.
static func park_feet(world: Node, wanted: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_score := INF
	var solids := LevelSanity.solid_rects(world)
	for top in LevelSanity.top_segments(world):
		if top.owner_name.contains("@") or top.kind in ["collapsing", "conveyor", "candle"]:
			continue
		if top.x1 - top.x0 < 16.0 or absf(top.y - wanted.y) > 160.0:
			continue
		var px := clampf(wanted.x, top.x0 + 8.0, top.x1 - 8.0)
		if absf(px - wanted.x) > 96.0:
			continue
		var body := Rect2(px - 7.0, top.y - 26.0, 14.0, 26.0)
		var clear := true
		for solid in solids:
			if solid.grow(-0.1).intersects(body):
				clear = false
				break
		if not clear:
			continue
		var score := absf(top.y - wanted.y) + absf(px - wanted.x) * 2.0
		if score < best_score:
			best_score = score
			best = Vector2(px, top.y)
	return best


## Backdrop = every CanvasLayer drawn under the world (layer < 0) that is visible.
func _hide_backdrops() -> Array:
	var hidden: Array = []
	for node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var layer := node as CanvasLayer
		if layer.layer < 0 and layer.visible:
			layer.visible = false
			hidden.append(layer)
	return hidden
