extends TestCase
## 回火试炼 × 战役系统的集成守卫：
##   P2 SaveData 写入锁（试炼中 save_game / mark_flag / consumed / lit_nests 全 no-op）
##   P5 HUD 不弹战役死亡幕
##   P6 player 死亡不走战役重燃
##   P7 试炼中不播章节卡 / 间幕剧本
##   P8 LevelExit 在试炼里 = 到达终点（reach_goal），不换场
##   P4 暂停菜单试炼左列（重开本场 / 退出试炼）
## 这些用例依赖主树已注册 TrialRun autoload（project.godot）。

const Catalog := preload("res://scripts/data/trial_catalog.gd")
const Records := preload("res://scripts/data/trial_records.gd")
const RunScript := preload("res://scripts/autoload/trial_run.gd")
const Results := preload("res://scripts/ui/trial_results.gd")
const LevelExitScript := preload("res://scripts/interactables/level_exit.gd")
const HUD_SCENE := preload("res://scenes/ui/HUD.tscn")

const SAVE_TEST_PATH := "user://trial_integration_save.cfg"
const RECORDS_TEST_PATH := "user://trial_integration_records.cfg"
const TITLE_PATH := "res://scenes/ui/TitleScreen.tscn"

var _requested: PackedStringArray
var _orig_flags: PackedStringArray
var _orig_ending := ""
var _orig_save_path := ""


func setup() -> void:
	_orig_flags = SaveData.flags.duplicate()
	_orig_ending = SaveData.ending
	_orig_save_path = SaveData.save_path
	SaveData.save_path = SAVE_TEST_PATH
	_delete_save()
	SaveData.flags = PackedStringArray()
	SaveData.ending = ""
	Records.use_file(RECORDS_TEST_PATH)
	Records.delete_file()
	_requested = PackedStringArray()
	RunScript.set_scene_requester(_on_scene_requested)
	Director.abort()
	Director.resume()
	Director.choice_hold = false
	Director.set_letterbox(false, true)
	if get_tree().paused:
		get_tree().paused = false


func teardown() -> void:
	RunScript.abandon()
	RunScript.clear_scene_requester()
	Results.close_all()
	Director.abort()
	Director.resume()
	Director.choice_hold = false
	if get_tree().paused:
		get_tree().paused = false
	SaveData.flags = _orig_flags
	SaveData.ending = _orig_ending
	SaveData.save_path = _orig_save_path
	_delete_save()
	Records.delete_file()
	Records.use_default_file()


func _on_scene_requested(path: String) -> void:
	_requested.append(path)


func _delete_save() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path: String = SAVE_TEST_PATH + String(suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _start_timed_trial() -> bool:
	SaveData.mark_flag("trial_unlocked")
	SaveData.mark_flag("level03_done")
	return RunScript.start(Catalog.Track.TIME_ATTACK, "level03")


## P2：试炼会话中战役档只读——所有写入口 no-op，且不产生存档文件。
func test_campaign_save_is_read_only_during_a_trial() -> void:
	ok(RunScript.active() == false, "开始前不在试炼")
	ok(_start_timed_trial(), "开一局限时试炼")
	ok(RunScript.blocks_campaign_save(), "写入锁生效")
	var flags_before := SaveData.flags.duplicate()
	var consumed_before := SaveData.consumed.size()
	var nests_before := SaveData.lit_nests.size()
	eq(SaveData.save_game("res://scenes/levels/Level03_RustTown.tscn", null), false,
			"试炼中 save_game 拒绝写档")
	eq(SaveData.persist_progress(null), false, "试炼中 persist_progress 拒绝")
	SaveData.persist_story()  # void：守卫让它什么都不做，下一行断言旗标/文件未动
	SaveData.mark_flag("trial_leak_flag")
	SaveData.mark_consumed("/root/Level/Props/CorePickup")
	SaveData.register_lit_nest("Props/EmberNest")
	ok(not SaveData.flags.has("trial_leak_flag"), "剧情旗标不写入")
	eq(SaveData.flags.size(), flags_before.size(), "旗标数量不变")
	eq(SaveData.consumed.size(), consumed_before, "消耗物不写入")
	eq(SaveData.lit_nests.size(), nests_before, "余烬巢不写入")
	ok(not FileAccess.file_exists(SAVE_TEST_PATH), "没有生成战役存档文件")
	# 退出试炼后写入恢复正常（同一个进程里不能一直锁着）。
	RunScript.abandon()
	eq(SaveData.persist_progress(null), false, "退出后没有存档文件时 persist 仍返回 false")
	SaveData.mark_flag("trial_after_flag")
	ok(SaveData.flags.has("trial_after_flag"), "退出试炼后 mark_flag 恢复正常")


## P7：试炼中 Director 剧本（章节卡 / 间幕 / 出口字幕）不播；Boss 名号不走这里，保留。
func test_cinematic_scripts_are_suppressed_during_a_trial() -> void:
	ok(_start_timed_trial(), "开一局试炼")
	ok(RunScript.suppresses_cinematics(), "试炼中抑制间幕")
	Director.play([{"kind": "caption", "text": "这段不该出现", "hold": 0.5},
			{"kind": "unlock"}])
	ok(not Director.playing, "章节卡 / 间幕剧本被直接丢弃")
	ok(not Director.is_input_locked(), "也不会锁输入")
	RunScript.abandon()
	Director.play([{"kind": "caption", "text": "战役里正常", "hold": 0.1},
			{"kind": "unlock"}])
	ok(Director.playing, "退出试炼后剧本恢复正常")
	Director.abort()


## P5：试炼死亡不弹战役死亡幕（重试提示由 TrialRun 的 HUD 条负责）。
func test_hud_hides_the_campaign_death_overlay_in_a_trial() -> void:
	var hud: CanvasLayer = HUD_SCENE.instantiate()
	add_child(hud)
	await flush(2)
	ok(_start_timed_trial(), "开一局试炼")
	GameEvents.player_died.emit()
	await flush(2)
	var death_overlay := hud.find_child("DeathOverlay", true, false) as Control
	ok(death_overlay != null, "HUD 有战役死亡幕节点")
	ok(death_overlay != null and not death_overlay.visible,
			"试炼中死亡幕不出现（否则会盖住重试提示）")
	eq(RunScript.deaths(), 1, "死亡仍被试炼记下")
	RunScript.abandon()
	GameEvents.player_died.emit()
	await flush(2)
	ok(death_overlay != null and death_overlay.visible, "战役中死亡幕照常出现")
	hud.queue_free()
	await flush(1)


## P6：试炼中 player 死亡不走"回最近余烬巢重燃"，也不写 pending_spawn / 存档。
func test_player_death_does_not_campaign_respawn_in_a_trial() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	SaveData.pending_spawn = Vector2.INF
	SaveData.entering_from_checkpoint = false
	ok(_start_timed_trial(), "开一局试炼")
	player._on_died()
	await flush(2)
	ok(not SaveData.has_pending_spawn(), "试炼死亡不排战役重生点")
	eq(SaveData.entering_from_checkpoint, false, "也不会进入 checkpoint 读档流程")
	eq(RunScript.deaths(), 1, "死亡计入试炼")
	ok(not FileAccess.file_exists(SAVE_TEST_PATH), "没有写战役档")
	RunScript.abandon()
	player.queue_free()
	arena.queue_free()
	await flush(1)


## P8：LevelExit 在试炼里 = 到达终点；不执行战役换场、不写旗标/存档。
func test_level_exit_reaches_goal_instead_of_travelling() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	var exit: Node = LevelExitScript.new()
	exit.name = "TrialExit"
	arena.add_child(exit)
	await flush(1)
	ok(_start_timed_trial(), "开一局试炼")
	var requested_before := _requested.size()
	var flags_before := SaveData.flags.duplicate()
	exit.interact(player)
	await flush(1)
	ok(RunScript.finished(), "推门 = 到达终点并结算")
	eq(_requested.size(), requested_before, "不载入下一关（试炼没有战役换场）")
	eq(SaveData.flags, flags_before, "不写章节完成旗标")
	ok(not FileAccess.file_exists(SAVE_TEST_PATH), "没有写战役档")
	var record := Records.best(Catalog.Track.TIME_ATTACK, "level03")
	ok(not record.is_empty(), "结算写进试炼记录")
	Results.close_all()
	RunScript.abandon()
	player.queue_free()
	arena.queue_free()
	await flush(1)


## P4：暂停菜单在试炼中换成「重开本场 / 退出试炼」，退出回标题不写战役档。
func test_pause_menu_offers_trial_restart_and_exit() -> void:
	var pause := PauseMenu.new()
	add_child(pause)
	await get_tree().process_frame
	ok(_start_timed_trial(), "开一局试炼")
	pause.open()
	await get_tree().process_frame
	eq(pause.menu().visible, false, "试炼中普通左列隐藏")
	var trial_list := pause.find_child("TrialMenu", true, false) as MenuList
	ok(trial_list != null and trial_list.visible, "试炼左列出现")
	if trial_list != null:
		var rows: Array[MenuItem] = []
		for child in trial_list.get_children():
			if child is MenuItem:
				rows.append(child)
		eq(rows.size(), 2, "只有重开本场 / 退出试炼两格")
		ok(pause.is_open() and get_tree().paused, "暂停状态照常")
	# 重开本场：关闭菜单、恢复暂停、重载当前场。
	var before := _requested.size()
	pause._on_chosen(&"trial_restart")
	await get_tree().process_frame
	ok(not pause.is_open(), "重开本场后菜单收起")
	ok(not get_tree().paused, "重开本场后世界恢复")
	eq(_requested.size(), before + 1, "重开本场重新载入当前场")
	ok(RunScript.active(), "仍是试炼会话")
	eq(RunScript.deaths(), 0, "重开本场不算死亡")
	# 退出试炼：回标题、结束会话、不写战役档。
	pause.open()
	await get_tree().process_frame
	pause._on_chosen(&"trial_exit")
	await get_tree().process_frame
	ok(not pause.is_open(), "退出试炼后菜单收起")
	ok(not RunScript.active(), "退出后不是试炼会话")
	eq(_requested[_requested.size() - 1], TITLE_PATH, "退出回标题")
	ok(not FileAccess.file_exists(SAVE_TEST_PATH), "全程没有战役存档写入")
	pause.queue_free()
	await get_tree().process_frame
