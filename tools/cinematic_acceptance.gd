extends Node
## Real OpenGL render-target captures of the opening, never a desktop screenshot.
## Uses its own disposable save; the player's save is never loaded or modified.
##
## Opening frames are keyed to the script's own step tags, so they follow the piece
## when its timing changes: prone knight, stand-up, the first line, the pull-back to the
## nest and graves, the bell, the graves answering along the corridor, the forge at the
## end of it, the chapter card, and the gameplay hand-off with the move prompt.
## Run with `--write-movie <file>.avi --fixed-fps 30` to record the same run.

const OUT := "res://screenshots/acceptance/cinematics"
const Opening := preload("res://scripts/levels/opening_cinematic.gd")
const ERRORS := preload("res://tests/error_collector.gd")
## step tag (or caption text) -> [[capture name, seconds after the step starts], ...]
const OPENING_SHOTS := {
	"rouse": [["01-prone", 0.35]],
	"stand": [["02-stand", 0.4], ["03-sword", 1.3]],
	"pullback": [["04-pullback", 1.9]],
	"toll": [["05-bell", 0.4], ["06-graves", 1.5], ["07-corridor", 2.5]],
	"line_forge": [["08-forge", 1.3]],
	"card": [["09-card", 1.3]],
}
const FIXTURE_SHOTS := 4  # world, chapter card, boss card, 640x360 chapter card
var errors
var shots: Array[String] = []
var deadline := 0
var _capture_cards := false


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	errors = ERRORS.new()
	OS.add_logger(errors)
	deadline = Time.get_ticks_msec() + 120000
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var win := get_tree().root
	win.mode = Window.MODE_WINDOWED
	win.position = Vector2i(-12000, -12000)
	win.size = Vector2i(1280, 720)
	Engine.max_fps = 60
	SaveData.save_path = OUT + "/fixture-save.cfg"
	SaveData.delete_save()
	SaveData.pending_spawn = Vector2.INF
	SaveData.entering_from_checkpoint = false
	SaveData.ending = ""
	Opening.reset()
	Director.abort()
	GameContext.pending_world_path = GameContext.WORLD_PATH
	Director.step_started.connect(_step)
	var world := preload("res://scenes/ui/GamePresentation.tscn").instantiate()
	add_child(world)
	var started := false
	for _i in 30:
		await get_tree().process_frame
		if Director.playing:
			started = true
			break
	if not started:
		push_error("opening did not start on the cemetery")
		OS.remove_logger(errors)
		get_tree().quit(1)
		return
	await Director.finished
	# The hand-off frame: control is back, the move prompt is up.
	await get_tree().create_timer(1.0).timeout
	await _capture("10-handoff-prompt")
	var prompt_up: bool = Director.get_node("CinematicPresentation").hint_visible()
	await get_tree().create_timer(0.6).timeout
	await _capture("11-world")
	_capture_cards = true
	# Chapter and boss cards over the live cemetery. No drawn furnace slide.
	Director.play([
		{"kind": "lock"},
		ChapterLevel.chapter_card("锈墓・贰 — 沉钟地窟"),
		{"kind": "unlock"},
	])
	await Director.finished
	await get_tree().create_timer(0.8).timeout
	Director.play([
		{"kind": "lock"},
		{"kind": "tableau", "id": "boss", "title": "炉约刽子手", "subtitle": "守 芯 者", "seconds": 1.8},
		{"kind": "unlock"},
	])
	await Director.finished
	await get_tree().create_timer(0.8).timeout
	win.size = Vector2i(640, 360)
	await get_tree().process_frame
	Director.play([
		{"kind": "lock"},
		ChapterLevel.chapter_card("锈墓・壹 — 腐液回廊"),
		{"kind": "unlock"},
	])
	await Director.finished
	await get_tree().create_timer(0.5).timeout
	Director.abort()
	var seen := SaveData.has_flag(Opening.FLAG)
	world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	SaveData.delete_save()
	var expected := _expected_opening_shots() + FIXTURE_SHOTS
	var report := {
		"captures": shots, "expected": expected, "engine_errors": errors.errors(),
		"opening_seen": seen, "move_prompt_visible": prompt_up,
		"renderer": RenderingServer.get_current_rendering_method(),
		"purpose": "Opening playback and visual fixtures, not a campaign playthrough",
	}
	var file := FileAccess.open(OUT + "/report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	OS.remove_logger(errors)
	print("CINEMATIC ACCEPTANCE: ", JSON.stringify(report))
	get_tree().quit(0 if errors.errors().is_empty() and shots.size() == expected and seen and prompt_up else 1)


func _process(_delta: float) -> void:
	if deadline > 0 and Time.get_ticks_msec() > deadline:
		get_tree().quit(2)


func _expected_opening_shots() -> int:
	var n := 1  # 10-handoff-prompt
	for key in OPENING_SHOTS:
		n += (OPENING_SHOTS[key] as Array).size()
	return n


func _step(_index: int, step: Dictionary) -> void:
	var kind := String(step.get("kind", ""))
	if not _capture_cards:
		# 只认步骤自己的 tag。以前这里还按"第 3 句字幕文本"兜底认 line_forge，
		# 分镜调整后那句已经不带 tag，于是 08-forge 被抓了两次、门禁假失败。
		# tag 是剧本的一部分（opening_cinematic_test 会锁住顺序），够稳定。
		var key := String(step.get("tag", ""))
		if OPENING_SHOTS.has(key):
			for shot in OPENING_SHOTS[key]:
				_capture_later(String(shot[0]), float(shot[1]))
		return
	if kind != "tableau":
		return
	var id := String(step.get("id", ""))
	if id != "chapter" and id != "boss":
		return
	await get_tree().create_timer(1.2).timeout
	await _capture("%s-%dx%d" % [id, get_tree().root.size.x, get_tree().root.size.y])


func _capture_later(id: String, seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	await _capture(id)


func _capture(id: String) -> void:
	await RenderingServer.frame_post_draw
	var path := OUT + "/" + id + ".png"
	var error := get_viewport().get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Could not save cinematic capture: " + path)
	shots.append(path)
