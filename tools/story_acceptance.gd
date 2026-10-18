extends Node
## 只读渲染夹具：章节卡、章间间幕（带布景）、开场前段、暂停菜单「前情提要」。
##
## 不读也不写玩家存档：用独立的 user:// 临时档；不跑通关，只把演出各拍在真实渲染里
## 抓下来。输出优先 res://screenshots/acceptance/story（gitignored）；若运行环境不允许
## 写仓库目录，则退到 user://story_acceptance 并在 report.json 里写实际路径。
##
## 运行（PS 沙箱不允许 Start-Process，用直接调用）：
##   & 'C:\Program Files\Godot\Godot_v4.7.1-stable_win64_console.exe' --headless --path . res://scenes/tools/StoryAcceptance.tscn
##   & ... --windowed --position -12000,-12000 --resolution 1280x720 --rendering-method gl_compatibility res://scenes/tools/StoryAcceptance.tscn

const OUT_RES := "res://screenshots/acceptance/story"
const OUT_USER := "user://story_acceptance"
const ERRORS := preload("res://tests/error_collector.gd")

var errors
var shots: Array[String] = []
var out_dir := OUT_RES
var deadline := 0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("StoryAcceptance: 需要窗口渲染（headless 退出）")
		get_tree().quit(2)
		return
	errors = ERRORS.new()
	OS.add_logger(errors)
	deadline = Time.get_ticks_msec() + 120000
	var win := get_tree().root
	win.mode = Window.MODE_WINDOWED
	win.position = Vector2i(-12000, -12000)
	win.size = Vector2i(1280, 720)
	Engine.max_fps = 60
	_prepare_save()
	await get_tree().process_frame
	# 1) 真的把第一章载进画面壳，让开场自己播；抓处境一拍后跳到目标前。
	GameContext.pending_world_path = GameContext.WORLD_PATH
	var world := preload("res://scenes/ui/GamePresentation.tscn").instantiate()
	add_child(world)
	var started := false
	for _i in 60:
		await get_tree().process_frame
		if Director.playing:
			started = true
			break
	if not started:
		await _finish("opening never started", 1)
		return
	await get_tree().create_timer(3.2).timeout
	await _capture("01-opening-situation")
	await get_tree().create_timer(9.0).timeout
	await _capture("02-opening-world")
	await get_tree().create_timer(16.0).timeout
	await _capture("03-opening-obstacle")
	_skip_script()
	await get_tree().create_timer(1.2).timeout
	await _capture("04-handoff")

	# 2) 章节卡：第十四章的卡（14 章重编后的「拾肆」）。
	Director.play([
		{"kind": "lock"},
		ChapterLevel.chapter_card(ChapterText.title_of("level03")),
		{"kind": "unlock"},
	])
	await get_tree().create_timer(1.4).timeout
	await _capture("05-chapter-card")
	await get_tree().create_timer(1.8).timeout

	# 3) 章间间幕：level01→level02 的 door 布景 + epilogue/teaser/目标。
	var transition := ChapterTransition.new()
	transition.test_enabled = true
	add_child(transition)
	await get_tree().process_frame
	transition.preview("level01")
	await get_tree().create_timer(2.4).timeout
	await _capture("06-interlude-door")
	await get_tree().create_timer(3.2).timeout
	await _capture("07-interlude-epilogue")
	await get_tree().create_timer(4.0).timeout
	await _capture("08-interlude-objective")
	Director.abort()
	transition.reset_view()
	await get_tree().create_timer(0.4).timeout

	# 4) 暂停菜单「前情提要」：写两个已通关旗标，打开暂停看档案卡那一行。
	SaveData.mark_flag("boss_dead")
	SaveData.mark_flag("undercroft_done")
	var menu := PauseMenu.new()
	GameContext.ui_host(self).add_child(menu)
	await get_tree().process_frame
	menu.open()
	await get_tree().create_timer(0.5).timeout
	await _capture("09-pause-recap")
	menu.close()
	await get_tree().process_frame

	world.queue_free()
	await get_tree().process_frame
	await _finish("", 0)


func _prepare_save() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_USER))
	# 先探一次仓库目录能不能写：不能写就直接用 user://，避免 save_png 打一条引擎错误
	# （只读导出/沙箱里 res:// 不可写是预期），报告里写实际输出目录。
	out_dir = OUT_RES
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_RES)) != OK \
			or not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(OUT_RES)):
		out_dir = OUT_USER
	SaveData.save_path = OUT_USER + "/fixture-save.cfg"
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.ending = ""
	SaveData.pending_spawn = Vector2.INF
	SaveData.entering_from_checkpoint = false
	StoryStage.forget()
	OpeningCinematic.reset()
	Director.abort()
	Director.resume()
	Director.choice_hold = false
	if get_tree().paused:
		get_tree().paused = false


func _skip_script() -> void:
	var event := InputEventAction.new()
	event.action = "ui_accept"
	event.pressed = true
	Director._unhandled_input(event)


func _capture(id: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, id]
	var error := image.save_png(path)
	if error != OK and out_dir != OUT_USER:
		# 仓库目录不可写（沙箱/只读导出）：换到 user://，报告里写实际路径。
		out_dir = OUT_USER
		path = "%s/%s.png" % [out_dir, id]
		error = image.save_png(path)
	if error != OK:
		push_error("StoryAcceptance: could not save " + path)
		return
	shots.append(path)


func _finish(reason: String, code: int) -> void:
	var report := {
		"captures": shots,
		"out_dir": out_dir,
		"reason": reason,
		"engine_errors": errors.errors(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"purpose": "Read-only render fixture: chapter card, chapter interlude, opening beats, pause recap. Not a playthrough.",
	}
	var report_path := out_dir + "/report.json"
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	OS.remove_logger(errors)
	print("STORY ACCEPTANCE: ", JSON.stringify(report))
	var failed: bool = code != 0 or not errors.errors().is_empty() or shots.size() != 9
	get_tree().quit(0 if not failed else 1)


func _process(_delta: float) -> void:
	if deadline > 0 and Time.get_ticks_msec() > deadline:
		print("StoryAcceptance: deadline")
		get_tree().quit(2)
