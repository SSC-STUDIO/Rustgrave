extends Node
## Windowed stills for the story boards, the live title, the pause story page and the
## ember-recap card. Not an acceptance gate. Writes under --out (an absolute directory).
## Isolated save path: the player's user:// save is never the target.
##
##   tools/run_story_shots.ps1
##   ... -- --out=C:/Temp/rustgrave_shots

const TITLE := preload("res://scenes/ui/TitleScreen.tscn")
const BOARDS := preload("res://scripts/data/storyboards.gd")
const BOARD_SCRIPT := preload("res://scripts/ui/storyboard_player.gd")
const JOURNAL := preload("res://scripts/ui/journal_screen.gd")

const CHAPTER_SCENES := {
	"act1": ["level02", 2],
	"act3": ["level08", 8],
}
const VARIANTS: Array[String] = ["cold", "act1", "act3", "give", "keep", "snuff"]
const BARE: Array[String] = ["cold", "act3", "give", "keep", "snuff"]

var _out := ""
var _count := 0
var _misses: Array[String] = []
var _deadline := 0
var _only := ""
var _sequence := ""
var _seq_frames := 10
var _seq_step := 0.5


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		printerr("STORY_SHOTS needs a window; headless has no render target")
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=").replace("\\", "/").trim_suffix("/")
		elif arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=")
		elif arg.begins_with("--sequence="):
			_sequence = arg.trim_prefix("--sequence=")
		elif arg.begins_with("--frames="):
			_seq_frames = clampi(int(arg.trim_prefix("--frames=")), 1, 24)
		elif arg.begins_with("--step="):
			_seq_step = clampf(float(arg.trim_prefix("--step=")), 0.1, 2.0)
	if _out == "":
		printerr("STORY_SHOTS missing --out")
		get_tree().quit(2)
		return
	_deadline = Time.get_ticks_msec() + 180000
	DirAccess.make_dir_recursive_absolute(_out)
	var win := get_tree().root
	win.mode = Window.MODE_WINDOWED
	win.position = Vector2i(-12000, -12000)
	win.size = Vector2i(1280, 720)
	Engine.max_fps = 60
	SaveData.save_path = _out + "/fixture_save.cfg"
	Settings.save_path = _out + "/fixture_settings.cfg"
	SaveData.delete_save()
	_clear_memory()
	Director.abort()
	Director.resume()
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.04, 0.03, 0.06)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	await _frames(2)
	if _sequence != "":
		await _title_sequence()
	else:
		if _only == "" or _only == "title":
			await _titles()
		if _only == "" or _only == "boards":
			await _boards()
		if _only == "" or _only == "journal":
			await _journal()
		if _only == "" or _only == "recap":
			if _only == "recap":
				await _recap_only()
	print("STORY_SHOTS shots=", _count, " misses=", _misses.size())
	for miss in _misses:
		printerr("STORY_SHOTS MISS ", miss)
	get_tree().quit(0 if _misses.is_empty() else 1)


func _process(_delta: float) -> void:
	if _deadline > 0 and Time.get_ticks_msec() > _deadline:
		printerr("STORY_SHOTS timeout")
		get_tree().quit(2)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _timer(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


func _clear_memory() -> void:
	SaveData.ending = ""
	SaveData.flags = PackedStringArray()
	if SaveData.data != null:
		SaveData.data.clear()


func _shot(theme: String, shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var dir := "%s/%s" % [_out, theme]
	DirAccess.make_dir_recursive_absolute(dir)
	var path := "%s/%s.png" % [dir, shot_name]
	var err := get_tree().root.get_texture().get_image().save_png(path)
	_count += 1
	print("STORY_SHOT ", path, " saved=", err == OK)
	if err != OK:
		_misses.append(path)


func _write_save(variant: String) -> void:
	SaveData.delete_save()
	_clear_memory()
	if variant == "cold":
		return
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 3)
	cfg.set_value("player", "origin", "ember_vanguard")
	cfg.set_value("profile", "ember_rank", 4)
	cfg.set_value("profile", "skin_id", "skin_fantasy_knight")
	if CHAPTER_SCENES.has(variant):
		var spec: Array = CHAPTER_SCENES[variant]
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
	var err := cfg.save(SaveData.save_path)
	if err != OK:
		_misses.append("save " + variant)


## Time series of the live title so the pour, the hammer flash and the souls can be judged in motion.
## --sequence=cold|keep|give|all  --frames=10 --step=0.5
func _title_sequence() -> void:
	var names: Array[String] = []
	if _sequence == "all":
		names.append("cold")
		names.append("keep")
		names.append("give")
	else:
		names.append(_sequence)
	for variant in names:
		_write_save(variant)
		var title := TITLE.instantiate() as TitleScreen
		add_child(title)
		await _frames(2)
		title._skip_intro()
		await _frames(2)
		var hidden := _hide_ui(title)
		await _frames(2)
		for i in _seq_frames:
			await _shot("seq", "%s_%02d" % [variant, i])
			if i + 1 < _seq_frames:
				await _timer(_seq_step)
		_restore_ui(hidden)
		title.queue_free()
		await _frames(2)


func _recap_only() -> void:
	for variant in ["give", "act3"]:
		_write_save(variant)
		var title := TITLE.instantiate() as TitleScreen
		add_child(title)
		await _frames(2)
		title._skip_intro()
		title.open_recap()
		await _timer(0.4)
		await _shot("recap", variant)
		title.queue_free()
		await _frames(2)


func _titles() -> void:
	for variant in VARIANTS:
		_write_save(variant)
		var title := TITLE.instantiate() as TitleScreen
		add_child(title)
		await _timer(3.8)
		var keyart := title.get_node_or_null("Keyart") as CanvasItem
		if keyart != null and keyart.modulate.a < 0.85:
			title._skip_intro()
			await _timer(0.3)
		await _shot("title", variant + "_idle")
		if BARE.has(variant):
			var hidden := _hide_ui(title)
			await _frames(3)
			await _shot("title", variant + "_bare")
			_restore_ui(hidden)
			await _frames(2)
		if variant == "cold":
			await _focus(title, variant, [0, 3, 4])
		elif variant == "give":
			await _focus(title, variant, [1])
		if variant == "act3" or variant == "give":
			title.open_recap()
			await _timer(0.55)
			await _shot("recap", variant)
			if title.recap_open():
				(title.recap_page() as Object).call("dismiss")
			await _frames(2)
		title.queue_free()
		await _frames(3)


func _focus(title: TitleScreen, variant: String, picks: Array) -> void:
	var menu := title.get_node("Menu") as MenuList
	var ids := menu.item_ids()
	for pick in picks:
		var index := int(pick)
		if index < ids.size():
			menu.select(index, false)
			await _timer(0.5)
			await _shot("title", "%s_focus_%s" % [variant, String(ids[index])])


func _hide_ui(title: Control) -> Dictionary:
	var saved := {}
	for child in title.get_children():
		if child is CanvasItem and String(child.name) != "Keyart":
			saved[child] = (child as CanvasItem).visible
			(child as CanvasItem).visible = false
	return saved


func _restore_ui(saved: Dictionary) -> void:
	for node in saved:
		if is_instance_valid(node):
			(node as CanvasItem).visible = bool(saved[node])


func _boards() -> void:
	var player: Object = Director.board()
	if player == null:
		_misses.append("no storyboard player")
		return
	await _prologue(player)
	await _fallback(player, "prologue", 0, "fallback_prologue")
	for from_id in ["level01", "level04", "level09b"]:
		await _interlude(player, from_id)
	for kind in ["give", "keep", "snuff"]:
		await _ending(player, kind)
	await _fallback(player, "ending_give", _art_index("ending_give"), "fallback_ending_give")
	await _credits(player)


func _prologue(player: Object) -> void:
	if not bool(player.call("play_board", BOARDS.PROLOGUE)):
		_misses.append("prologue start")
		return
	var shots: Array = BOARDS.shots(BOARDS.PROLOGUE)
	for i in shots.size():
		var lines: Array = (shots[i] as Dictionary).get("lines", [])
		var line_i := maxi(lines.size() - 1, 0)
		if not await _await_line(player, i, line_i):
			_misses.append("prologue_%02d" % i)
			break
		print("STORY_SHOT info prologue ", i, " ", player.call("stage_info"))
		await _shot("boards", "prologue_%02d" % i)
	player.call("abort")
	await _frames(2)


func _interlude(player: Object, from_id: String) -> void:
	var id := BOARDS.interlude_id(from_id)
	if not bool(player.call("play_board", id)):
		_misses.append(id)
		return
	if await _await_line(player, 0, 0):
		print("STORY_SHOT info ", id, " ", player.call("stage_info"))
		await _shot("boards", id)
	else:
		_misses.append(id)
	player.call("abort")
	await _frames(2)


func _ending(player: Object, kind: String) -> void:
	var id := BOARDS.ending_id(kind)
	var where := _art_line(id)
	if not bool(player.call("play_board", id)):
		_misses.append(id)
		return
	if await _await_line(player, where.x, where.y):
		print("STORY_SHOT info ", id, " ", player.call("stage_info"))
		await _shot("boards", id)
	else:
		_misses.append(id)
	player.call("abort")
	await _frames(2)


func _credits(player: Object) -> void:
	if not bool(player.call("play_board", BOARDS.CREDITS)):
		_misses.append("credits")
		return
	var limit := Time.get_ticks_msec() + 20000
	var scroll := int(BOARD_SCRIPT.Phase.SCROLL)
	while Time.get_ticks_msec() < limit:
		if int(player.get("phase")) == scroll and float(player.call("age")) >= 7.0:
			break
		if not bool(player.get("playing")):
			break
		await _timer(0.1)
	if int(player.get("phase")) == scroll:
		await _shot("boards", "credits")
	else:
		_misses.append("credits")
	player.call("abort")
	await _frames(2)


## Same shot with the illustration id removed, so the live collage stands in.
func _fallback(player: Object, board_id: String, shot_i: int, shot_name: String) -> void:
	if not bool(player.call("play_board", board_id)):
		_misses.append(shot_name)
		return
	if not await _await_line(player, shot_i, 0):
		_misses.append(shot_name)
		player.call("abort")
		return
	var shot: Dictionary = (player.get("_shot") as Dictionary).duplicate(true)
	shot["art"] = "missing_art"
	var stage: Object = player.get("_stage")
	stage.call("show_shot", shot, 6.0)
	stage.call("set_black", 0.0)
	await _timer(0.4)
	print("STORY_SHOT info ", shot_name, " ", stage.call("info"))
	await _shot("boards", shot_name)
	player.call("abort")
	await _frames(2)


func _art_index(board_id: String) -> int:
	return _art_line(board_id).x


func _art_line(board_id: String) -> Vector2i:
	var shots: Array = BOARDS.shots(board_id)
	for i in shots.size():
		var shot: Dictionary = shots[i]
		if String(shot.get("art", "")) == "":
			continue
		var lines: Array = shot.get("lines", [])
		for j in lines.size():
			var line := String(lines[j])
			if line.contains("铁屑") or line.contains("散成") or line.contains("守下去") or line.contains("一点红"):
				return Vector2i(i, j)
		return Vector2i(i, maxi(lines.size() - 1, 0))
	return Vector2i(0, 0)


func _await_line(player: Object, shot_i: int, line_i: int) -> bool:
	var hold := int(BOARD_SCRIPT.Phase.HOLD)
	var typing := int(BOARD_SCRIPT.Phase.TYPING)
	var tail := int(BOARD_SCRIPT.Phase.TAIL)
	var limit := Time.get_ticks_msec() + 25000
	while Time.get_ticks_msec() < limit and Time.get_ticks_msec() < _deadline:
		if not bool(player.get("playing")):
			return false
		var si := int(player.call("current_shot_index"))
		var li := int(player.get("_line_index"))
		var phase := int(player.get("phase"))
		if si == shot_i and li == line_i and phase == hold:
			return true
		if si > shot_i or (si == shot_i and li > line_i):
			return false
		if not bool(player.get("skip_all_on_accept")) and float(player.call("age")) >= 0.40:
			if phase == typing or phase == hold or phase == tail:
				player.call("press_accept")
				await _timer(0.05)
				continue
		await get_tree().process_frame
	return false


func _journal() -> void:
	_clear_memory()
	var order := ChapterText.order()
	for i in mini(8, order.size()):
		var flag := StoryFlow.done_flag(String(order[i]))
		if flag != "":
			SaveData.mark_flag(flag)
	SaveData.mark_flag("opening_seen")
	SaveData.mark_flag(BOARDS.seen_flag(BOARDS.PROLOGUE))
	SaveData.mark_flag(StoryFlow.interlude_flag("level01"))
	SaveData.mark_flag(StoryFlow.interlude_flag("level04"))
	SaveData.mark_flag(StoryFlow.interlude_flag("level07"))
	SaveData.mark_flag(BOARDS.seen_flag(BOARDS.ending_id("give")))
	var journal: CanvasLayer = JOURNAL.new()
	journal.layer = 21
	add_child(journal)
	journal.call("set_chapter", "level08")
	journal.call("open", "level08")
	await _timer(0.5)
	await _shot("journal", "now")
	journal.call("show_tab", 1)
	await _timer(0.25)
	await _shot("journal", "cast")
	journal.call("show_tab", 2)
	await _timer(0.25)
	await _shot("journal", "terms")
	journal.call("show_tab", 3)
	await _timer(0.25)
	await _shot("journal", "replay")
	journal.call("dismiss")
	journal.queue_free()
