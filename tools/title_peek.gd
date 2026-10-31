extends Node
## TITLE PEEK: window-mode captures of the live title screen (TitleScreen + TitleWorld).
## Visual review aid, not an acceptance gate. Fixtures only: it writes its own disposable
## save/settings under --out and forces each look by writing a real save file there, so
## the same peek path the game uses (TitleWorld.peek_save) is what gets rendered.
##
##   tools/run_title_peek.ps1 -Variants cold,act2,give -Sizes 1280x720,1920x1080
##   ... -- --out=res://screenshots/x --sizes=1280x720 --variants=cold,give --bare
##
## --sigils=demo   seed a handful of demo ember sigils (visits + deaths) into the
##                 peek's disposable sigil store, so the title's sigil ring /
##                 personal epitaphs / dossier row render (CI screenshots do this)
## --variants  cold | act1..act4 | mid (= act2) | give | keep | snuff | true_break     (default: all but true_break)
## --sizes     window sizes, e.g. 1280x720,1920x1080,1600x900          (default: 1280x720)
## --shots     boot,idle,focus,dossier,recap,all  (default: idle,focus; 'boot' adds the intro frames,
##             'dossier' pins the journey dossier card open, 'recap' opens the recap page)
## --bare      hide the UI and show only the live scene (art review)

const TITLE := preload("res://scenes/ui/TitleScreen.tscn")
## variant -> number of cleared chapters; the save sits in GameContext.LEVEL_ORDER[cleared].
const CHAPTER_SCENES := {"act1": 2, "act2": 4, "act3": 8, "act4": 13}
const SKIN_BY_VARIANT := {"keep": "skin_fantasy_knight", "cold": "skin_fantasy_knight"}

var _out := "res://screenshots/acceptance/overhaul-v3/title"
var _sizes: Array[Vector2i] = [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080)]
var _variants: PackedStringArray = ["cold", "act1", "act2", "act3", "act4", "give", "keep", "snuff"]
var _shots: PackedStringArray = ["idle", "focus"]
var _bare := false
var _skin := ""
var _count := 0
var _keyart := false
var _shadow_pair := false
var _sigils_demo := false
## CI / 低速软件渲染模式（RUSTGRAVE_PEEK_FAST=1）：每尺寸只 settle 一次且不因
## settle 失败退场，并关掉点光阴影（llvmpipe 上阴影是大头）。截图内容不变。
var _fast := false
var _current: TitleScreen


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("title_peek needs a render target; run without --headless")
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--sizes="):
			_sizes.clear()
			for token in arg.trim_prefix("--sizes=").split(",", false):
				var parts := token.split("x", false)
				if parts.size() == 2:
					_sizes.append(Vector2i(int(parts[0]), int(parts[1])))
		elif arg.begins_with("--variants="):
			_variants = arg.trim_prefix("--variants=").split(",", false)
		elif arg.begins_with("--shots="):
			_shots = arg.trim_prefix("--shots=").split(",", false)
		elif arg.begins_with("--skin="):
			_skin = arg.trim_prefix("--skin=")
		elif arg == "--bare":
			_bare = true
		elif arg == "--keyart":
			_keyart = true
		elif arg == "--shadow-pair":
			_shadow_pair = true
		elif arg.begins_with("--sigils="):
			_sigils_demo = arg.trim_prefix("--sigils=") == "demo"
	if OS.get_environment("RUSTGRAVE_PEEK_FAST") == "1":
		_fast = true
	if _shots.has("all"):
		_shots = ["boot", "idle", "focus"]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	var win := get_tree().root
	win.mode = Window.MODE_WINDOWED
	# Windows 上把窗口停在屏幕外截图；Linux（Xvfb）没有 WM，窗口必须留在屏内，
	# 设 RUSTGRAVE_PEEK_ONSCREEN=1 时贴着左上角摆。
	var onscreen := OS.get_environment("RUSTGRAVE_PEEK_ONSCREEN") == "1"
	var park := Vector2i(8, 8) if onscreen else Vector2i(-12000, -12000)
	win.position = park
	SaveData.save_path = _out + "/peek_save.cfg"
	Settings.save_path = _out + "/peek_settings.cfg"
	if _sigils_demo:
		_seed_demo_sigils()
	Settings.load_settings()
	Engine.max_fps = 60
	for size in _sizes:
		if not await _settle_window(size):
			return
		for variant in _variants:
			await _variant(variant, size)
	print("TITLE_PEEK shots=", _count)
	get_tree().quit(0)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _shot(variant: String, tag: String, size: Vector2i) -> void:
	if not _fast:
		if not await _settle_window(size):
			return
	await RenderingServer.frame_post_draw
	var image := get_tree().root.get_texture().get_image()
	var mode := "keyart" if _keyart else "live"
	var path := "%s/%s_%s_%s_%dx%d.png" % [_out, mode, variant, tag, size.x, size.y]
	var err := image.save_png(path)
	var world := _current.world()
	var record := {"mode": mode, "variant": variant, "tag": tag,
		"actual_width": image.get_width(), "actual_height": image.get_height(),
		"window": str(get_tree().root.size), "png": path,
		"has_live_viewport": _current.get_node_or_null("WorldViewport") != null}
	if world != null:
		record["fixtures"] = world.lantern_count()
		record["lit_fixtures"] = world.lit_lanterns()
		record["point_lights"] = world.light_count()
		record["occluders"] = world.find_children("*", "LightOccluder2D", true, false).size()
		record["knight_pose"] = world.knight_sprite().current() if world.knight_sprite() != null else "absent"
	var file := FileAccess.open(path.trim_suffix(".png") + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(record, "\t"))
	_count += 1
	print("TITLE_PEEK ", mode, " ", variant, " ", tag, " ", image.get_size(), " saved=", err == OK)
	if err != OK:
		push_error("title_peek could not save " + path)
		get_tree().quit(1)


func _settle_window(wanted: Vector2i) -> bool:
	var win := get_tree().root
	var park := Vector2i(-12000, -12000)
	if OS.get_environment("RUSTGRAVE_PEEK_ONSCREEN") == "1":
		park = Vector2i(8, 8)
	var stable := 0
	var limit := 45 if _fast else 120
	for frame in limit:
		if win.mode != Window.MODE_WINDOWED or win.size != wanted:
			win.mode = Window.MODE_WINDOWED
			win.size = wanted
			win.position = park
			stable = 0
		await RenderingServer.frame_post_draw
		stable = stable + 1 if win.get_texture().get_image().get_size() == wanted and win.size == wanted else 0
		if stable >= 3:
			return true
	if _fast:
		# 快速模式：窗口尺寸认不齐也照拍（CI 上比直接退场强）。
		push_warning("title_peek fast: size did not settle at %s" % wanted)
		return true
	push_error("title_peek render size did not settle at " + str(wanted))
	get_tree().quit(1)
	return false


## Writes the save that makes the title show `variant` (or none for 'cold').
func _write_save(variant: String) -> void:
	SaveData.delete_save()
	SaveData.ending = ""
	if variant == "cold":
		return
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 3)
	cfg.set_value("player", "origin", "ember_vanguard")
	cfg.set_value("profile", "ember_rank", 4)
	cfg.set_value("profile", "skin_id", _skin if _skin != "" else "skin_fantasy_knight")
	var key := "act2" if variant == "mid" else variant
	if CHAPTER_SCENES.has(key):
		var cleared := int(CHAPTER_SCENES[key])
		var level := String(GameContext.LEVEL_ORDER[cleared])
		cfg.set_value("meta", "scene", String(GameContext.LEVELS[level]))
		var flags: Array = []
		for i in cleared:
			var id := String(GameContext.LEVEL_ORDER[i])
			flags.append(String(StoryFlow.DONE_FLAGS[id]))
		cfg.set_value("story", "flags", flags)
	else:
		cfg.set_value("meta", "scene", String(GameContext.LEVELS[GameContext.LEVEL_ORDER.back()]))
		cfg.set_value("meta", "ending", variant)
		var all: Array = []
		for id in GameContext.LEVEL_ORDER:
			all.append(String(StoryFlow.DONE_FLAGS[id]))
		cfg.set_value("story", "flags", all)
	cfg.save(SaveData.save_path)


func _variant(variant: String, size: Vector2i) -> void:
	_write_save(variant)
	var title := TITLE.instantiate() as TitleScreen
	_current = title
	title.live_scene_enabled = not _keyart
	add_child(title)
	if _fast:
		_llvmpipe_relief(title)
	if _bare:
		_hide_ui(title)
	if _shots.has("boot"):
		for t in [0.12, 0.45, 0.8, 1.2, 1.7, 2.4]:
			await get_tree().create_timer(t - (0.0 if t == 0.12 else _prev_t(t))).timeout
			await _shot(variant, "boot_%03d" % int(t * 100.0), size)
	await get_tree().create_timer(3.6 if not _shots.has("boot") else 1.2).timeout
	if _shots.has("idle"):
		await _shot(variant, "idle", size)
	if _shadow_pair and title.world() != null:
		Engine.time_scale = 0.0
		await _shot(variant, "shadows_on", size)
		var changed: Array[PointLight2D] = []
		for node in title.world().find_children("*", "PointLight2D", true, false):
			var light := node as PointLight2D
			if light.shadow_enabled:
				changed.append(light)
				light.shadow_enabled = false
		await _shot(variant, "shadows_off", size)
		for light in changed:
			light.shadow_enabled = true
		Engine.time_scale = 1.0
	if _shots.has("focus"):
		var menu := title.get_node("Menu") as MenuList
		var ids := menu.item_ids()
		for pick in [0, 1, 3, 6]:
			if pick < ids.size():
				menu.select(pick, false)
				await get_tree().create_timer(0.45).timeout
				await _shot(variant, "focus_%s" % String(ids[pick]), size)
	if _shots.has("dossier"):
		title.set("_dossier_pinned", true)
		title._set_dossier_open(true)
		await get_tree().create_timer(0.5).timeout
		await _shot(variant, "dossier", size)
	if _shots.has("recap"):
		title.open_recap()
		await get_tree().create_timer(0.6).timeout
		await _shot(variant, "recap", size)
		title.recap_page().dismiss()
	title.queue_free()
	await _frames(3)


func _prev_t(t: float) -> float:
	var times := [0.12, 0.45, 0.8, 1.2, 1.7, 2.4]
	var i := times.find(t)
	return float(times[i - 1]) if i > 0 else 0.0


func _hide_ui(title: Control) -> void:
	for child in title.get_children():
		if child is CanvasItem and String(child.name) not in ["Keyart"]:
			(child as CanvasItem).visible = false


## 软件渲染减负：关掉所有点光阴影（llvmpipe 上阴影贴图是大头），画面布局不变。
func _llvmpipe_relief(title: TitleScreen) -> void:
	for node in title.find_children("*", "PointLight2D", true, false):
		(node as PointLight2D).shadow_enabled = false


## 演示印记：几次点燃 + 两次殁，落在隔离仓库（peek_sigils.cfg），生产记录不动。
## 章节跨一~四幕，日龄拉开，让环上的冷却梯度看得出来。
func _seed_demo_sigils() -> void:
	EmberSigils.store_path = _out + "/peek_sigils.cfg"
	EmberSigils.clear()
	var today := EmberSigils.today()
	var visits := [["stage01", 46, "new"], ["branch01", 38, "continue"], ["stage02", 30, "continue"],
		["stage03", 21, "continue"], ["branch03", 13, "continue"], ["stage04", 8, "continue"],
		["stage05", 5, "continue"], ["branch04", 2, "continue"], ["stage07", 0, "continue"]]
	for v in visits:
		EmberSigils.append_raw(today - int(v[1]), String(v[2]), String(v[0]))
	EmberSigils.append_raw(today - 33, "death", "stage02")
	EmberSigils.append_raw(today - 6, "death", "stage05")
