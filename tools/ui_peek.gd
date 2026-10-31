extends Node
## UI PEEK: real render-target captures of every screen the player reads text on —
## title (+ save / overwrite confirm / settings), HUD arrival / calm / peek / cores / alert /
## hint / letterbox, pause, settings (3 pages + key capture), tutorial recall, map,
## controls, caption, chapter card, death.
## Visual review aid, not an acceptance gate. Fixtures only (the world is frozen,
## values are pushed through GameEvents); it uses its own disposable save.
##
##   tools/ui_peek.ps1                      (writes screenshots/ui_peek/*.png)
##   ... -- --out=res://screenshots/x --size=1920x1080 --level=level01 --only=title,hud,menus
##
## --only takes a comma list of groups: title, hud, menus, cine (default: all).

const PRESENTATION := preload("res://scenes/ui/GamePresentation.tscn")
const TITLE := preload("res://scenes/ui/TitleScreen.tscn")

var _out := "res://screenshots/ui_peek"
var _size := Vector2i(1920, 1080)
var _level := "level01"
var _only: PackedStringArray = []
var _shots := 0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("ui_peek needs a render target; run without --headless")
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--size="):
			var parts := arg.trim_prefix("--size=").split("x")
			if parts.size() == 2:
				_size = Vector2i(int(parts[0]), int(parts[1]))
		elif arg.begins_with("--level="):
			_level = arg.trim_prefix("--level=")
		elif arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=").split(",")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	var win := get_tree().root
	win.mode = Window.MODE_WINDOWED
	win.size = _size
	win.position = Vector2i(-12000, -12000)
	SaveData.save_path = _out + "/peek_save.cfg"
	SaveData.delete_save()
	# Disposable settings too: the capture must not read or write the player's file.
	Settings.save_path = _out + "/peek_settings.cfg"
	Settings.load_settings()
	if _wants("title"):
		await _title()
	if _wants("hud") or _wants("menus") or _wants("cine"):
		await _world()
	print("UI_PEEK shots=", _shots)
	get_tree().quit(0)


func _wants(group: String) -> bool:
	return _only.is_empty() or _only.has(group)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	# Capture a settled object, independent of render speed or vsync.
	await get_tree().create_timer(0.55).timeout
	await RenderingServer.frame_post_draw
	var image := get_tree().root.get_texture().get_image()
	var err := image.save_png("%s/%s_%dx%d.png" % [_out, name, _size.x, _size.y])
	_shots += 1
	print("UI_PEEK ", name, " saved=", err == OK)


func _closed(screen: CanvasLayer) -> void:
	var deadline := Time.get_ticks_msec() + 1500
	while screen.visible and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if screen.visible:
		push_error("UI_PEEK screen did not finish closing: " + screen.name)


func _title() -> void:
	var title = TITLE.instantiate()
	add_child(title)
	await _frames(20)
	await get_tree().create_timer(0.8).timeout
	await _shot("title")
	title.queue_free()
	await _frames(3)

	# With a save on disk: cursor starts on 继续 and 点燃余烬 asks before wiping it.
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 1)
	cfg.save(SaveData.save_path)
	title = TITLE.instantiate()
	add_child(title)
	await _frames(20)
	await get_tree().create_timer(0.5).timeout
	await _shot("title_save")
	title.open_confirm()
	await _frames(6)
	await _shot("title_confirm")
	title.close_confirm()
	await _closed(title._confirm)
	title._settings.open()
	await _frames(6)
	await _shot("title_settings")
	title.queue_free()
	await _frames(3)
	SaveData.delete_save()


func _world() -> void:
	if GameContext.LEVELS.has(_level):
		GameContext.pending_world_path = GameContext.LEVELS[_level]
	var presentation := PRESENTATION.instantiate()
	add_child(presentation)
	await _frames(8)
	Director.abort()
	Director.set_letterbox(false, true)
	var player := get_tree().get_first_node_in_group("player") as Player
	var camera := get_tree().get_first_node_in_group("game_camera") as GameCamera
	player.set_physics_process(false)
	player.cutscene_locked = true
	camera.set_physics_process(false)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
		enemy.set_process(false)
	WorldClock.set_time(0.35)
	WorldClock.set_weather(WorldClock.Weather.HAZE, true)
	WorldClock.time_scale = 0.0
	var hud = _find_hud()
	# Story beats (caption + letterbox) would hijack the captures; mark them told.
	for flag in ["wake", "boss_intro", "toxin", "core", "insert", "parry"]:
		SaveData.mark_flag(flag)
	if _wants("hud"):
		# First seconds of a chapter: objective line, weather label and the one-time hint.
		await get_tree().create_timer(1.9).timeout
		await _shot("hud_arrival")
		await get_tree().create_timer(7.5).timeout
		_report_hud(hud)
		await _shot("hud_calm")
		hud.peek_for(60.0)
		await get_tree().create_timer(1.0).timeout
		await _shot("hud_peek")
		hud.peek_for(0.0)
		hud._peek_timer = 0.0
		await get_tree().create_timer(1.0).timeout

		# Cores in both sockets and one in the pouch, so the socket row shows real art.
		# Written straight into the inventory: insert_into_socket() would also fire the
		# cinematic voice lines (letterbox + caption) that belong to another package.
		var inv := player.inventory
		inv.sockets[0] = AbilityCatalog.kiln_core()
		inv.sockets[1] = AbilityCatalog.ember_core()
		inv.pouch.append(AbilityCatalog.tether_core())
		GameEvents.sockets_changed.emit()
		GameEvents.player_health_changed.emit(2, player.health.max_hp)
		GameEvents.toxin_changed.emit(46.0, 100.0)
		GameEvents.interact_prompt.emit("E 点燃余烬巢")
		await get_tree().create_timer(0.9).timeout
		await _shot("hud_prompt")
		hud.peek_for(60.0)
		await get_tree().create_timer(0.8).timeout
		await _shot("hud_peek_cores")
		hud._peek_timer = 0.0

		hud.hint_service().dismiss()
		hud.hint_service().offer(&"core")
		await get_tree().create_timer(3.0).timeout
		await _shot("hud_hint")

		GameEvents.player_health_changed.emit(1, player.health.max_hp)
		GameEvents.toxin_changed.emit(88.0, 100.0)
		GameEvents.interact_prompt.emit("")
		GameEvents.announcement.emit("嵌核 1：窑核（热锻）")
		GameEvents.boss_appeared.emit("炉约刽子手 · 铸渣残躯", 9, 13)
		await get_tree().create_timer(1.1).timeout
		await _shot("hud_alert_boss")
		GameEvents.interact_prompt.emit("E 点燃余烬巢")
		await get_tree().create_timer(0.5).timeout
		await _shot("hud_boss_prompt")
		GameEvents.interact_prompt.emit("")

		# Cinematic letterbox: the HUD must give way instead of being clipped by the bars.
		Director.set_letterbox(true, true)
		await _frames(8)
		await _shot("hud_letterbox")
		Director.set_letterbox(false, true)
		await _frames(4)

		GameEvents.player_health_changed.emit(5, player.health.max_hp)
		GameEvents.toxin_changed.emit(0.0, 100.0)
		GameEvents.boss_defeated.emit()
		await get_tree().create_timer(1.0).timeout

	if _wants("menus"):
		# Mark a few hints as seen so the recall list has content.
		for id in [&"peek", &"swing", &"dash", &"toxin", &"core", &"nest"]:
			HintService.mark_seen(id)
		var pause := hud.get_node("PauseMenu") as PauseMenu
		pause.open()
		await _frames(6)
		await _shot("pause")
		var settings := pause.settings_screen()
		pause._on_chosen(PauseMenu.ID_SETTINGS)
		await _frames(6)
		await _shot("settings_audio")
		settings.show_tab(SettingsScreen.TAB_DISPLAY)
		await _frames(4)
		await _shot("settings_display")
		settings.show_tab(SettingsScreen.TAB_KEYS)
		await _frames(4)
		await _shot("settings_keys")
		settings.begin_capture(&"jump")
		await _frames(4)
		await _shot("settings_capture")
		settings.close()
		await _closed(settings)
		pause._on_chosen(PauseMenu.ID_TUTORIAL)
		await _frames(6)
		await _shot("tutorial")
		pause.tutorial_recall().close()
		await _closed(pause.tutorial_recall())
		pause._on_chosen(PauseMenu.ID_MAP)
		await _frames(6)
		await _shot("map")
		pause.map_screen().close()
		await _closed(pause.map_screen())
		pause._on_chosen(PauseMenu.ID_CONTROLS)
		await _frames(6)
		await _shot("controls")
		pause.controls_panel().close()
		await _closed(pause.controls_panel())
		pause.close()
		await _frames(4)

	if _wants("cine"):
		Director.set_letterbox(true, true)
		Director.caption().enqueue("余烬落回炉灰。骑士也是。", 20.0)
		Director.caption().skip()
		await _frames(10)
		await _shot("caption")
		Director.abort()
		Director.set_letterbox(false, true)

		Director.play([ChapterLevel.chapter_card("锈墓・肆 — 圣殿中庭")])
		await get_tree().create_timer(1.3).timeout
		await _shot("chapter_card")
		Director.abort()

		GameEvents.player_died.emit()
		await get_tree().create_timer(0.9).timeout
		await _shot("death")


## Prints the compact plate geometry (design units and physical pixels) so the
## acceptance numbers come from the render, not from a guess.
func _report_hud(hud) -> void:
	var metrics := PresentationMetrics.for_window(get_tree().root)
	var ui_scale := float(metrics["scale"]) * 0.5
	var plate: Rect2 = hud.plate_rect()
	var cluster: Rect2 = hud.cluster_rect()
	print("UI_PEEK_HUD window=", get_tree().root.size, " ui_scale=", ui_scale,
			" plate_design=", plate.size, " plate_px=", plate.size * ui_scale,
			" plate_pos=", plate.position, " cluster_design=", cluster.size)


func _find_hud() -> CanvasLayer:
	var hud := get_tree().root.find_child("HUD", true, false) as CanvasLayer
	return hud
