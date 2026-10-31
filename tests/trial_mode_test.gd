extends TestCase
## 回火试炼运行时：解锁门 / pending 载入 / 计时单调 / 死亡重试 / 连战推进 /
## 结算记录 / 暂停重开与退出 / 战役档零写入 / HUD 试炼条 / 三分辨率与菜单布局。

const Catalog := preload("res://scripts/data/trial_catalog.gd")
const Records := preload("res://scripts/data/trial_records.gd")
const RunScript := preload("res://scripts/autoload/trial_run.gd")
const Results := preload("res://scripts/ui/trial_results.gd")
const MenuScene := preload("res://scenes/ui/TrialMenu.tscn")

const SAVE_TEST_PATH := "user://trial_mode_test_save.cfg"
const RECORDS_TEST_PATH := "user://trial_mode_test_records.cfg"
const TITLE_PATH := "res://scenes/ui/TitleScreen.tscn"

var _run: Node
var _owns_run := false
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
	RequestedReset()
	Director.abort()
	Director.resume()
	Director.choice_hold = false
	Director.set_letterbox(false, true)
	if get_tree().paused:
		get_tree().paused = false
	# 主树已注册 TrialRun autoload：直接用它，避免第二个实例重复接 GameEvents
	# （重复连接会让一次 boss_defeated 推进两场）。没有 autoload 时（合并前）才自建 fixture。
	_run = get_tree().root.get_node_or_null("TrialRun")
	if _run == null:
		_run = RunScript.new()
		_run.name = "TrialRunFixture"
		add_child(_run)
		_owns_run = true
	else:
		_owns_run = false


func teardown() -> void:
	RunScript.abandon()
	RunScript.clear_scene_requester()
	Results.close_all()
	Director.abort()
	Director.resume()
	Director.choice_hold = false
	if get_tree().paused:
		get_tree().paused = false
	if _owns_run and _run != null and is_instance_valid(_run):
		_run.queue_free()
	_run = null
	_owns_run = false
	SaveData.flags = _orig_flags
	SaveData.ending = _orig_ending
	SaveData.save_path = _orig_save_path
	_delete_save()
	Records.delete_file()
	Records.use_default_file()


func _on_scene_requested(path: String) -> void:
	_requested.append(path)


func RequestedReset() -> void:
	_requested = PackedStringArray()
	RunScript.set_scene_requester(_on_scene_requested)


func _delete_save() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path: String = SAVE_TEST_PATH + String(suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _unlock() -> void:
	SaveData.mark_flag("trial_unlocked")


func _campaign_save_bytes() -> String:
	if not FileAccess.file_exists(SAVE_TEST_PATH):
		return ""
	return FileAccess.get_file_as_string(SAVE_TEST_PATH)


# --- 生命周期 / 载入 -----------------------------------------------------------

func test_start_routes_through_the_presentation_pending_mechanism() -> void:
	_unlock()
	SaveData.mark_flag("stage03_done")
	ok(RunScript.start(Catalog.Track.TIME_ATTACK, "stage03"), "已解锁且章节通关时能开赛")
	ok(RunScript.active(), "试炼会话进行中")
	ok(RunScript.running(), "正在跑（未结算）")
	eq(_requested.size(), 1, "只请求了一次场景加载")
	eq(_requested[0], GameContext.PRESENTATION_PATH, "走 GamePresentation 表现层，不新建加载器")
	eq(GameContext.pending_world_path, GameContext.LEVELS["stage03"], "pending 机制被复用")
	eq(RunScript.stage_scene_path(), GameContext.LEVELS["stage03"])
	eq(RunScript.track(), Catalog.Track.TIME_ATTACK)
	eq(RunScript.target_id(), "stage03")
	eq(RunScript.stage_count(), 1, "章节赛道一场")
	eq(RunScript.deaths(), 0)
	RunScript.abandon()
	ok(not RunScript.active(), "中止后不活跃")


func test_start_refused_when_locked_or_chapter_not_cleared() -> void:
	ok(not RunScript.start(Catalog.Track.TIME_ATTACK, "stage03"), "未解锁拒绝开赛")
	ok(not RunScript.active())
	eq(_requested.size(), 0, "拒绝时不会切场景")
	_unlock()
	ok(not RunScript.start(Catalog.Track.TIME_ATTACK, "stage03"), "章节未通关拒绝开赛")
	SaveData.mark_flag("stage03_done")
	ok(RunScript.start(Catalog.Track.TIME_ATTACK, "stage03"), "章节通关后可开")
	RunScript.abandon()
	eq(RunScript.start(99, "stage03"), false, "未知赛道拒绝")


# --- 计时 ---------------------------------------------------------------------

func test_timer_is_monotonic_and_paused_time_does_not_count() -> void:
	_unlock()
	SaveData.mark_flag("stage03_done")
	RunScript.start(Catalog.Track.TIME_ATTACK, "stage03")
	var t0 := RunScript.elapsed_ms()
	ok(t0 >= 0, "开赛计时从 0 起（实际 %d）" % t0)
	RunScript.tick(1.0)
	var t1 := RunScript.elapsed_ms()
	ok(t1 >= t0 + 900, "1 秒后计时增加（%d → %d）" % [t0, t1])
	RunScript.tick(0.5)
	var t2 := RunScript.elapsed_ms()
	ok(t2 >= t1 + 400, "继续单调递增（%d → %d）" % [t1, t2])
	get_tree().paused = true
	RunScript.tick(2.0)
	eq(RunScript.elapsed_ms(), t2, "暂停期间计时冻结")
	get_tree().paused = false
	RunScript.tick(0.25)
	ok(RunScript.elapsed_ms() >= t2 + 200, "恢复后继续计时")
	ok(RunScript.display_time().contains(":"), "显示成 mm:ss.d")
	RunScript.abandon()


# --- 死亡 / 重试 ----------------------------------------------------------------

func test_death_counts_and_retry_reloads_the_same_stage_quickly() -> void:
	_unlock()
	SaveData.mark_flag("stage03_done")
	RunScript.start(Catalog.Track.TIME_ATTACK, "stage03")
	eq(_requested.size(), 1)
	GameEvents.player_died.emit()
	eq(RunScript.deaths(), 1, "死亡记数")
	eq(RunScript.no_hit(), false, "死亡即失去无伤")
	RunScript.tick(0.4)
	eq(_requested.size(), 1, "重试有短暂停顿（不是立刻闪回）")
	RunScript.tick(0.6)
	eq(_requested.size(), 2, "0.9s 后自动重开本场")
	eq(_requested[1], GameContext.PRESENTATION_PATH, "重试仍走表现层 pending 机制")
	eq(RunScript.stage_index(), 0, "重试同一场")
	ok(RunScript.running(), "重试后仍在跑")
	# 再死一次：死亡数累计，重试同样的场。
	GameEvents.player_died.emit()
	eq(RunScript.deaths(), 2)
	RunScript.tick(1.0)
	eq(_requested.size(), 3, "第二次死亡同样快速重试")
	ok(RunScript.elapsed_ms() > 0, "重试不清空计时")
	RunScript.abandon()


# --- Boss 连战 -----------------------------------------------------------------

func test_boss_rush_advances_between_bosses_then_finishes() -> void:
	_unlock()
	SaveData.mark_flag("stage01_done")
	SaveData.mark_flag("boss_dead")
	SaveData.mark_flag("nightmare_dead")
	# Boss 表随二期交付增长：按 catalog 实际可连战列表推进，测试不写死场次。
	var bosses := Catalog.available_bosses()
	ok(bosses.size() >= 2, "至少两位已通关 Boss 可连战（实际 %d）" % bosses.size())
	ok(RunScript.start(Catalog.Track.BOSS_RUSH, Catalog.ALL_BOSSES_ID), "连战开赛")
	var total := RunScript.stage_count()
	eq(total, bosses.size(), "场次 = 可连战 Boss 数（%d）" % total)
	eq(RunScript.stage_index(), 0)
	for i in total:
		var expected_scene := String(GameContext.LEVELS.get(
				String((bosses[i] as Dictionary).get("level_id", "")), ""))
		eq(RunScript.stage_scene_path(), expected_scene, "第 %d 场按 BOSS_TABLE 顺序" % (i + 1))
		eq(_requested.size(), i + 1, "第 %d 场只载入一次" % (i + 1))
		RunScript.tick(12.0)
		GameEvents.boss_defeated.emit()
		if i < total - 1:
			eq(RunScript.stage_index(), i + 1, "胜一场推进到下一场")
			ok(RunScript.running(), "还没结算")
		else:
			ok(RunScript.finished(), "最后一位 Boss 倒下即结算")
	var result := RunScript.result()
	eq(int(result.get("stage_count", 0)), total)
	eq(int(result.get("deaths", -1)), 0)
	eq(String(result.get("track_name", "")), "Boss 连战")
	var record := Records.best(Catalog.Track.BOSS_RUSH, Catalog.ALL_BOSSES_ID)
	ok(int(record.get("ms", 0)) >= total * 10000,
			"完整用时写进记录（%d ms）" % int(record.get("ms", 0)))
	ok(Records.has_no_hit(Catalog.Track.BOSS_RUSH, Catalog.ALL_BOSSES_ID), "无伤记录")
	Results.close_all()
	RunScript.abandon()


# --- 结算 ---------------------------------------------------------------------

func test_goal_finish_writes_records_and_shows_the_result_overlay() -> void:
	_unlock()
	SaveData.mark_flag("stage03_done")
	RunScript.start(Catalog.Track.TIME_ATTACK, "stage03")
	RunScript.tick(65.0)
	RunScript.reach_goal()
	ok(RunScript.finished(), "到达出口即结算")
	var result := RunScript.result()
	eq(int(result.get("track", -1)), Catalog.Track.TIME_ATTACK)
	eq(int(result.get("deaths", -1)), 0)
	ok(absf(float(result.get("elapsed_ms", 0)) - 65000.0) <= 2000.0,
			"结算用时接近 65s（%d）" % int(result.get("elapsed_ms", 0)))
	eq(String(result.get("rank", "")), "S", "基准时间内 S")
	ok(bool(result.get("is_first", false)), "首通标记")
	var record := Records.best(Catalog.Track.TIME_ATTACK, "stage03")
	eq(int(record.get("runs", 0)), 1, "记录写入独立文件")
	await flush(1)
	await get_tree().process_frame
	var overlay := Results.open_instance()
	ok(overlay != null, "结算 overlay 打开")
	if overlay != null:
		eq(overlay.rank_text(), "S", "结算显示评级")
		eq(overlay.time_text().substr(0, 2), "01", "结算显示用时（01:0x.x）")
		ok(overlay.record_text().contains("首 次 通 过"), "首通文案")
		ok(overlay.stats_text().contains("死亡 0"), "结算显示死亡数")
		ok(overlay.menu() != null and overlay.menu().get_child_count() >= 3,
				"结算有三个出口")
		ok(get_tree().paused, "结算时暂停世界")
	Results.close_all()
	ok(not get_tree().paused, "关闭结算恢复世界")
	RunScript.abandon()


# --- 暂停 / 退出 / 战役档只读 ---------------------------------------------------

func test_pause_retry_exit_and_zero_campaign_writes() -> void:
	_unlock()
	SaveData.mark_flag("stage05_done")
	var campaign_before := _campaign_save_bytes()
	var flags_before := SaveData.flags.duplicate()
	RunScript.start(Catalog.Track.TIME_ATTACK, "stage05")
	ok(RunScript.blocks_campaign_save(), "试炼中 SaveData 写入锁生效")
	ok(RunScript.suppresses_cinematics(), "试炼中不播间幕 / 章节卡")
	RunScript.tick(5.0)
	GameEvents.player_died.emit()
	RunScript.tick(1.0)
	eq(_requested.size(), 2, "自动重试一次")
	# 暂停菜单的「重开本场」：不记死亡、计时继续、重新载入当前场。
	var deaths_before := RunScript.deaths()
	RunScript.retry_stage()
	eq(RunScript.deaths(), deaths_before, "重开本场不算新死亡")
	eq(_requested.size(), 3, "重开本场重新载入")
	# 「退出试炼」：回标题，不碰战役档。
	RunScript.exit_to_title()
	ok(not RunScript.active(), "退出后不再是试炼会话")
	eq(_requested[_requested.size() - 1], TITLE_PATH, "退出回标题")
	eq(_campaign_save_bytes(), campaign_before, "战役档一个字节都没写")
	eq(SaveData.flags, flags_before, "战役剧情旗标一个都没写")
	ok(not FileAccess.file_exists(SAVE_TEST_PATH), "没有生成战役存档")
	ok(not RunScript.blocks_campaign_save(), "退出后写入锁解除")


func test_exit_to_menu_goes_back_to_the_trial_menu() -> void:
	_unlock()
	SaveData.mark_flag("stage03_done")
	RunScript.start(Catalog.Track.TIME_ATTACK, "stage03")
	RunScript.exit_to_menu()
	eq(_requested[_requested.size() - 1], "res://scenes/ui/TrialMenu.tscn",
			"换赛道回到试炼菜单")
	ok(not RunScript.active())


# --- HUD 试炼条 / 固定装载 -----------------------------------------------------

func test_trial_hud_strip_is_out_of_the_play_band_and_loadout_is_fixed() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	_unlock()
	SaveData.mark_flag("stage05_done")
	ok(RunScript.start(Catalog.Track.TIME_ATTACK, "stage05"), "开赛")
	await flush(4)
	ok(RunScript.strip_visible(), "HUD 试炼条出现")
	var rect := RunScript.strip_rect()
	ok(rect.size.x >= 180.0 and rect.size.x <= 300.0, "试炼条宽度紧凑（%s）" % rect)
	ok(rect.position.x >= 700.0, "贴右上角（不压左侧骑士）")
	ok(rect.position.y <= 80.0, "顶部天气行下方")
	ok(rect.end.x <= 1280.0, "不越出设计画布")
	ok(rect.position.y + rect.size.y <= 160.0, "只占顶部一条")
	ok(not rect.intersects(Rect2(120.0, 180.0, 1040.0, 400.0)),
			"不与骑士 / 敌人预警区重叠")
	var text := RunScript.strip_text()
	ok(text.contains("00:0") or text.contains("00:1"), "试炼条显示计时")
	ok(text.contains("死亡 0"), "试炼条显示死亡数")
	ok(text.contains("Esc 暂停"), "试炼条带暂停提示")
	# 固定装载：限时赛道两枚锈核镶满插座 + 口袋里第三枚，毒素清零。
	eq(player.inventory.sockets[0].id, &"kiln_core", "插座 1 固定热锻核")
	eq(player.inventory.sockets[1].id, &"tether_core", "插座 2 固定钩锁核")
	eq(player.inventory.pouch.size(), 1, "口袋里放第三枚核")
	eq(player.inventory.pouch[0].id, &"ember_core", "口袋核是余烬步")
	almost(player.toxin.toxin, 0.0, 0.001, "毒素清零")
	# 禁核锈行：剑鞘全空、无钩锁。
	RunScript.abandon()
	SaveData.mark_flag("trial_unlocked")
	SaveData.mark_flag("stage05_done")
	ok(RunScript.start(Catalog.Track.BARE_STEEL, "stage05"), "禁核开赛")
	await flush(4)
	for core in player.inventory.sockets:
		eq(core, null, "禁核锈行插座全空")
	eq(player.inventory.pouch.size(), 0)
	RunScript.abandon()
	player.queue_free()
	arena.queue_free()
	await flush(1)


# --- 试炼菜单 -----------------------------------------------------------------

func _open_menu():
	var menu = MenuScene.instantiate()
	add_child(menu)
	await flush(2)
	await get_tree().process_frame
	return menu


func test_trial_menu_lists_cleared_targets_records_and_sizes() -> void:
	_unlock()
	SaveData.mark_flag("stage01_done")
	SaveData.mark_flag("boss_dead")
	SaveData.mark_flag("stage05_done")
	var menu = await _open_menu()
	ok(not menu.locked(), "已解锁时菜单可用")
	eq(menu.track(), Catalog.Track.BOSS_RUSH, "默认停在 Boss 连战")
	eq(menu.target_count(), 1, "连战只有全部 Boss 一格")
	eq(menu.selected_target_id(), Catalog.ALL_BOSSES_ID)
	menu.select_track(Catalog.Track.TIME_ATTACK)
	await get_tree().process_frame
	eq(menu.target_count(), 2, "限时列表 = 已通关章节")
	menu.select_track(Catalog.Track.BARE_STEEL)
	await get_tree().process_frame
	eq(menu.target_count(), 2, "禁核列表同样按已通关章节")
	ok(menu.loadout_text().contains("无锈核"), "右侧写明固定装载")
	ok(menu.record_text().contains("尚 无"), "没有记录时说明")
	# 触控 / 键盘可达：所有可点元素 ≥52 设计像素且在设计画布内。
	var controls: Array[Control] = []
	controls.append_array(menu.track_tabs())
	controls.append(menu.start_button())
	controls.append(menu.back_button())
	for child in menu.target_menu().get_children():
		if child is MenuItem:
			controls.append(child)
	ok(controls.size() >= 6, "菜单有 tab / 目标行 / 开始 / 返回")
	for control in controls:
		var rect := control.get_global_rect()
		ok(rect.size.y >= UiKit.TOUCH_MIN,
				"%s 触控高度够（%.1f）" % [control.name, rect.size.y])
		ok(rect.position.x >= -0.5 and rect.end.x <= 1280.5,
				"%s 在设计画布内（%s）" % [control.name, rect])
	# 记录会显示在右侧档案里。
	Records.submit(Catalog.Track.TIME_ATTACK, "stage01",
			{"elapsed_ms": 95000, "deaths": 0, "rank": "A"})
	menu.select_track(Catalog.Track.TIME_ATTACK)
	await get_tree().process_frame
	menu.target_menu().select(0, false)
	await get_tree().process_frame
	ok(menu.record_text().contains("01:35.0"), "档案显示最佳记录（%s）" % menu.record_text())
	RunScript.abandon()
	menu.queue_free()
	await flush(1)


func test_trial_menu_locked_state_and_start_flow() -> void:
	# 未解锁：入口只给条件说明，开始键禁用。
	var locked_menu = await _open_menu()
	ok(locked_menu.locked(), "新档菜单是锁定态")
	eq(locked_menu.target_count(), 0, "锁定态没有目标")
	ok(locked_menu.start_button().disabled, "锁定态开始键禁用")
	locked_menu.queue_free()
	await flush(1)


func test_trial_menu_start_keyboard_flow_and_esc() -> void:
	_unlock()
	SaveData.mark_flag("stage03_done")
	var menu = await _open_menu()
	menu.select_track(Catalog.Track.TIME_ATTACK)
	await get_tree().process_frame
	eq(menu.track(), Catalog.Track.TIME_ATTACK)
	# 列表第一行 Enter = 开始（MenuList 的 chosen → start）。
	menu.target_menu().select(0, false)
	var started: bool = menu.start_selected()
	ok(started, "开始键启动试炼")
	eq(_requested[_requested.size() - 1], GameContext.PRESENTATION_PATH, "开始后走表现层")
	eq(RunScript.track(), Catalog.Track.TIME_ATTACK)
	RunScript.abandon()
	RequestedReset()
	# Esc = 回标题。
	menu._back_to_title()
	eq(_requested[_requested.size() - 1], TITLE_PATH, "Esc 回标题")
	menu.queue_free()
	await flush(1)


func test_menu_fits_three_design_resolutions() -> void:
	_unlock()
	SaveData.mark_flag("stage03_done")
	var menu = await _open_menu()
	var design := Vector2(PresentationMetrics.UI_SIZE)
	var card := menu.get_node_or_null("ModalRoot/Card") as Control
	ok(card != null, "菜单是居中卡片")
	if card != null:
		ok(card.custom_minimum_size.x <= design.x and card.custom_minimum_size.y <= design.y,
				"卡片装得进 1280×720 设计画布（%s）" % card.custom_minimum_size)
	for size in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		var metrics := PresentationMetrics.calculate(size)
		var scale := int(metrics.scale)
		eq(metrics.physical_rect.size, Vector2(PresentationMetrics.WORLD_SIZE) * scale,
				"%s 用最大整数倍世界内容矩形" % str(size))
		var ui: Transform2D = metrics["ui_transform"]
		var canvas_rect: Rect2 = metrics["canvas_rect"]
		ok(ui.origin.is_equal_approx(canvas_rect.position),
				"%s：UI 与世界图共用同一内容矩形" % str(size))
		ok((ui * design).is_equal_approx(canvas_rect.end),
				"%s：设计画布映射到内容矩形右/下边" % str(size))
		var physical_scale := Vector2(size) / design
		ok((canvas_rect.size * physical_scale).is_equal_approx(metrics.physical_rect.size),
				"%s：只按整数世界倍率伸缩" % str(size))
	menu.queue_free()
	await flush(1)
