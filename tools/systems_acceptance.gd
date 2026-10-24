extends Node
## Rendered UI fixtures, not evidence of a campaign playthrough or controller hardware.
const OUT := "res://screenshots/acceptance/overhaul-v3/systems"
const Recap := preload("res://scripts/ui/ember_recap.gd")
const Records := preload("res://scripts/data/trial_records.gd")
const Catalog := preload("res://scripts/data/trial_catalog.gd")
const Errors := preload("res://tests/error_collector.gd")
var _errors
var _shots: Array[String] = []


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	_errors = Errors.new()
	OS.add_logger(_errors)
	var win := get_tree().root
	win.mode = Window.MODE_WINDOWED
	win.borderless = true
	win.position = Vector2i(-12000, -12000)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	SaveData.save_path = OUT + "/fixture_save.cfg"
	SaveData.flags = PackedStringArray(["wake", "boss_dead", "hollow_bell_dead", "capstan_dead", "choir_dead", "founder_dead", "herald_dead", "nightmare_dead", "trial_unlocked"])
	for id in GameContext.LEVEL_ORDER:
		SaveData.flags.append(StoryFlow.done_flag(id))
	SaveData.ending = "give"
	Records.use_file(OUT + "/fixture_trials.cfg")
	Records.submit(Catalog.Track.BOSS_RUSH, "all", {"elapsed_ms": 135200, "deaths": 1, "rank": "A", "no_hit": false, "score_ms": 180200})
	var title := preload("res://scenes/ui/TitleScreen.tscn").instantiate() as TitleScreen
	add_child(title)
	title._skip_intro()
	for size in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		win.size = size
		DisplayFit.apply_fit_mode(DisplayFit.FitMode.INTEGER)
		await _frames(4)
		title._menu.active = false
		title._settings.open()
		title._settings._select_tab(SettingsScreen.TAB_ASSIST)
		await _capture("settings-assist-%dx%d" % [size.x, size.y])
		Settings.set_value(&"text_scale", 1.35, false)
		await _capture("settings-large-text-%dx%d" % [size.x, size.y])
		Settings.set_value(&"text_scale", 1.0, false)
		title._settings._select_tab(SettingsScreen.TAB_DISPLAY)
		await _capture("settings-display-%dx%d" % [size.x, size.y])
		title._settings.visible = false
		title._recap.open(false)
		await _capture("ember-recap-%dx%d" % [size.x, size.y])
		title._recap.visible = false
	var report := {"purpose": "Rendered UI fixtures; no hardware or campaign completion claim", "shots": _shots,
		"display_server": DisplayServer.get_name(), "gpu": RenderingServer.get_video_adapter_name(), "errors": _errors.errors()}
	var out := FileAccess.open(OUT + "/report.json", FileAccess.WRITE)
	out.store_string(JSON.stringify(report, "  "))
	out.close()
	OS.remove_logger(_errors)
	print("SYSTEMS_RENDER ", _shots.size(), " captures; ", _errors.errors().size(), " engine errors")
	get_tree().quit(0 if _errors.errors().is_empty() else 1)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _capture(label: String) -> void:
	await _frames(5)
	await get_tree().create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	var path := OUT + "/" + label + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	_shots.append(path)
