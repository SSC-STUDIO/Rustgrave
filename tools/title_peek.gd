extends Node
## TITLE PEEK: window-mode captures of the live title screen (TitleScreen + TitleWorld).
## Visual review aid, not an acceptance gate. Fixtures only: it writes its own disposable
## save/settings under --out and forces each look by writing a real save file there, so
## the same peek path the game uses (TitleWorld.peek_save) is what gets rendered.
##
##   tools/run_title_peek.ps1 -Variants cold,act2,give -Sizes 1280x720,1920x1080
##   ... -- --out=res://screenshots/x --sizes=1280x720 --variants=cold,give --bare
##
## --variants  cold | act1..act4 | mid (= act2) | give | keep | snuff     (default: all)
## --sizes     window sizes, e.g. 1280x720,1920x1080,1600x900          (default: 1280x720)
## --shots     boot,idle,focus,all  (default: idle,focus; 'boot' adds the intro frames)
## --bare      hide the UI and show only the live scene (art review)

const TITLE := preload("res://scenes/ui/TitleScreen.tscn")
const CHAPTER_SCENES := {
	"act1": ["level02", 2], "act2": ["level04", 4], "act3": ["level08", 8], "act4": ["level10", 13],
}
const SKIN_BY_VARIANT := {"keep": "skin_fantasy_knight", "cold": "skin_fantasy_knight"}

var _out := "res://screenshots/acceptance/overhaul-v3/title"
var _sizes: Array[Vector2i] = [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080)]
var _variants: PackedStringArray = ["cold", "act1", "act2", "act3", "act4", "give", "keep", "snuff"]
var _shots: PackedStringArray = ["idle", "focus"]
var _bare := false
var _skin := ""
var _count := 0


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
	if _shots.has("all"):
		_shots = ["boot", "idle", "focus"]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	var win := get_tree().root
	win.mode = Window.MODE_WINDOWED
	win.position = Vector2i(-12000, -12000)
	SaveData.save_path = _out + "/peek_save.cfg"
	Settings.save_path = _out + "/peek_settings.cfg"
	Settings.load_settings()
	Engine.max_fps = 60
	for size in _sizes:
		win.size = size
		await _frames(4)
		for variant in _variants:
			await _variant(variant, size)
	print("TITLE_PEEK shots=", _count)
	get_tree().quit(0)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _shot(variant: String, tag: String, size: Vector2i) -> void:
	await RenderingServer.frame_post_draw
	var image := get_tree().root.get_texture().get_image()
	var path := "%s/%s_%s_%dx%d.png" % [_out, variant, tag, size.x, size.y]
	var err := image.save_png(path)
	_count += 1
	print("TITLE_PEEK ", variant, " ", tag, " ", size, " saved=", err == OK)


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
		var spec: Array = CHAPTER_SCENES[key]
		var level := String(spec[0])
		cfg.set_value("meta", "scene", String(GameContext.LEVELS[level]))
		var flags: Array = []
		for i in int(spec[1]):
			var id := String(GameContext.LEVEL_ORDER[i])
			flags.append(String(StoryFlow.DONE_FLAGS[id]))
		cfg.set_value("story", "flags", flags)
	else:
		cfg.set_value("meta", "scene", String(GameContext.LEVELS["level10"]))
		cfg.set_value("meta", "ending", variant)
		var all: Array = []
		for id in GameContext.LEVEL_ORDER:
			all.append(String(StoryFlow.DONE_FLAGS[id]))
		cfg.set_value("story", "flags", all)
	cfg.save(SaveData.save_path)


func _variant(variant: String, size: Vector2i) -> void:
	_write_save(variant)
	var title := TITLE.instantiate() as TitleScreen
	add_child(title)
	if _bare:
		_hide_ui(title)
	if _shots.has("boot"):
		for t in [0.12, 0.45, 0.8, 1.2, 1.7, 2.4]:
			await get_tree().create_timer(t - (0.0 if t == 0.12 else _prev_t(t))).timeout
			await _shot(variant, "boot_%03d" % int(t * 100.0), size)
	await get_tree().create_timer(3.6 if not _shots.has("boot") else 1.2).timeout
	if _shots.has("idle"):
		await _shot(variant, "idle", size)
	if _shots.has("focus"):
		var menu := title.get_node("Menu") as MenuList
		var ids := menu.item_ids()
		for pick in [0, 1, 3, 6]:
			if pick < ids.size():
				menu.select(pick, false)
				await get_tree().create_timer(0.45).timeout
				await _shot(variant, "focus_%s" % String(ids[pick]), size)
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
