extends Node
## Real OpenGL render-target captures of the opening, never a desktop screenshot.
## Uses its own disposable save; the player's save is never loaded or modified.

const OUT := "res://screenshots/acceptance/cinematics"
const Opening := preload("res://scripts/levels/opening_cinematic.gd")
const ERRORS := preload("res://tests/error_collector.gd")
var errors
var shots: Array[String] = []
var deadline := 0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	errors = ERRORS.new()
	OS.add_logger(errors)
	deadline = Time.get_ticks_msec() + 60000
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var win := get_tree().root
	win.mode = Window.MODE_WINDOWED
	win.position = Vector2i(-12000, -12000)
	win.size = Vector2i(1280, 720)
	Engine.max_fps = 60
	SaveData.save_path = OUT + "/fixture-save.cfg"
	SaveData.delete_save()
	SaveData.mark_flag("wake")
	var world := preload("res://scenes/ui/GamePresentation.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame
	Director.abort()
	SaveData.flags.clear()
	SaveData.pending_spawn = Vector2.INF
	SaveData.entering_from_checkpoint = false
	Opening.reset()
	Director.step_started.connect(_step)
	Opening.try_start()
	await Director.finished
	await get_tree().create_timer(0.9).timeout
	await _capture("04-world")
	# Explicit visual fixtures for chapter and boss cards over the live world.
	Director.play([
		{"kind": "lock"},
		{"kind": "tableau", "id": "chapter", "title": "沉钟地窟", "subtitle": "锈墓 · 贰"},
		{"kind": "wait", "seconds": 1.8}, {"kind": "unlock"},
	])
	await Director.finished
	await get_tree().create_timer(0.8).timeout
	Director.play([
		{"kind": "lock"},
		{"kind": "tableau", "id": "boss", "title": "炉约的刽子手", "subtitle": "守 芯 者"},
		{"kind": "wait", "seconds": 1.8}, {"kind": "unlock"},
	])
	await Director.finished
	await get_tree().create_timer(0.8).timeout
	# Check the narrow mobile design size using the same presentation binding.
	win.size = Vector2i(640, 360)
	await get_tree().process_frame
	Director.play([{"kind": "tableau", "id": "furnace"}, {"kind": "wait", "seconds": 1.8}])
	await Director.finished
	await get_tree().create_timer(0.8).timeout
	Director.abort()
	var seen := SaveData.has_flag(Opening.FLAG)
	world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	SaveData.delete_save()
	var report := {"captures": shots, "engine_errors": errors.errors(), "opening_seen": seen, "renderer": RenderingServer.get_current_rendering_method(), "purpose": "Opening playback and visual fixtures, not a campaign playthrough"}
	var file := FileAccess.open(OUT + "/report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	OS.remove_logger(errors)
	print("CINEMATIC ACCEPTANCE: ", JSON.stringify(report))
	get_tree().quit(0 if errors.errors().is_empty() and shots.size() == 7 and seen else 1)


func _process(_delta: float) -> void:
	if deadline > 0 and Time.get_ticks_msec() > deadline:
		get_tree().quit(2)


func _step(_index: int, step: Dictionary) -> void:
	if step.get("kind", "") != "tableau" or step.get("id", "") == "world":
		return
	var id := String(step["id"])
	await get_tree().create_timer(1.2 if id == "boss" or id == "chapter" else 2.0).timeout
	await _capture("%s-%dx%d" % [id, get_tree().root.size.x, get_tree().root.size.y])


func _capture(id: String) -> void:
	await RenderingServer.frame_post_draw
	var path := OUT + "/" + id + ".png"
	var error := get_viewport().get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Could not save cinematic capture: " + path)
	shots.append(path)
