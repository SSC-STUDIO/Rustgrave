extends TestCase
## 竞技场正式界面：大厅 / 倒计时 / 局内 / 结算 / 暂停分支 / 死亡幕。
## 本环境终端被拦，这里只写用例，没有跑过。

const ArenaCatalog := preload("res://scripts/data/arena_catalog.gd")
const ArenaHud := preload("res://scripts/ui/arena_hud.gd")
const HUD_SCENE := preload("res://scenes/ui/HUD.tscn")
const PATH := "user://test_arena_hud.cfg"
const LOCKED_BAR := Color(0.42, 0.42, 0.46, 1.0)


func setup() -> void:
	_quiet()
	ArenaRun.use_file(PATH)
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func teardown() -> void:
	_drop_fake_lanes()
	_quiet()
	ArenaRun.use_default_file()
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_strip_hides_while_ui_is_attached() -> void:
	ArenaRun.activate_for_test()
	eq(ArenaRun.strip_text(), "按 Enter 开战")
	var hud := _hud()
	eq(ArenaRun.strip_text(), "")
	ok(ArenaRun.ui_attached)
	var strip := ArenaRun.strip()
	ok(strip != null and not strip.visible, "正式界面挂上后文字条隐藏")
	hud.queue_free()
	await get_tree().process_frame
	ok(not ArenaRun.ui_attached)
	eq(ArenaRun.strip_text(), "按 Enter 开战")
	if ArenaRun.strip() != null:
		ok(ArenaRun.strip().visible)


func test_lobby_fly_difficulty_records_and_start() -> void:
	var lane := FakeLane.new()
	lane.name = "FakeLane"
	lane.add_to_group("game_world")
	add_child(lane)
	ArenaRun.activate_for_test()
	var hud := _hud()
	ok(not lane.driven, "大厅飞镜头时关掉场馆自己的镜头驱动")
	ok(lane.aims.size() >= 1 and lane.aims[0].x < 900.0, "先看蓝方基地")
	var lobby := hud.find_child("Lobby", true, false) as Control
	var menu := hud.find_child("LobbyMenu", true, false) as MenuList
	ok(lobby.visible)
	ok(not (hud.find_child("PlayChrome", true, false) as Control).visible)
	ok(not (hud.find_child("ResultRoot", true, false) as Control).visible)
	ok(not (hud.find_child("Shop", true, false) as Control).visible)
	ok(not menu.active, "飞镜头时菜单先不接 Enter")
	var roster := (hud.find_child("Roster", true, false) as Label).text
	ok(roster.contains("灰卫") and roster.contains("余烬骑士") and roster.contains("锈誓"))
	var rules := (hud.find_child("Rules", true, false) as Label).text
	ok(rules.contains("水晶") and rules.contains("外塔") and rules.contains("12 分钟"))
	var records := (hud.find_child("Records", true, false) as Label).text
	ok(records.contains("胜 0") and records.contains("负 0") and records.contains("平 0"))
	ok(records.contains("场次 0") and records.contains("最多击杀 0") and records.contains("最快胜利 —"))
	eq(ArenaRun.difficulty_id(), ArenaCatalog.DIFF_VETERAN)
	hud.call("_unhandled_input", _press(&"ui_left"))
	eq(ArenaRun.difficulty_id(), ArenaCatalog.DIFF_APPRENTICE)
	ok(_difficulty_text(menu).contains("见习"))
	hud.call("_unhandled_input", _press(&"ui_right"))
	eq(ArenaRun.difficulty_id(), ArenaCatalog.DIFF_VETERAN)
	hud.call("_unhandled_input", _press(&"ui_right"))
	eq(ArenaRun.difficulty_id(), ArenaCatalog.DIFF_FORGE)
	ok(_difficulty_text(menu).contains("炉火"))
	hud.call("_unhandled_input", _press(&"ui_right"))
	eq(ArenaRun.difficulty_id(), ArenaCatalog.DIFF_APPRENTICE, "难度左右循环")
	hud.call("_unhandled_input", _press(&"ui_accept"))
	ok(menu.active)
	ok(lane.released >= 1, "跳过飞行后松开镜头")
	eq(ArenaRun.phase(), ArenaCatalog.PHASE_LOBBY, "跳过飞行不开战")
	eq(menu.selected_id(), &"start")
	hud.call("_unhandled_input", _press(&"interact"))
	ok(not (hud.find_child("Shop", true, false) as Control).visible, "大厅不能开炉台")
	menu._unhandled_input(_press(&"ui_accept"))
	eq(ArenaRun.phase(), ArenaCatalog.PHASE_COUNTDOWN)
	ok(not lobby.visible)
	var digit := hud.find_child("CountdownText", true, false) as Label
	ok(digit.visible)
	eq(digit.text, "3")
	eq(digit.get_theme_font_size(&"font_size"), 96)
	var frozen := ArenaRun.difficulty_id()
	hud.call("_unhandled_input", _press(&"ui_left"))
	eq(ArenaRun.difficulty_id(), frozen, "倒计时里左右键不改难度")
	await _free(hud)
	lane.queue_free()


func test_countdown_fight_call_score_and_crystal_lock() -> void:
	ArenaRun.activate_for_test()
	var hud := _hud()
	ArenaRun.begin_match()
	_tick(1.0)
	hud.call("_advance", 0.0)
	eq((hud.find_child("CountdownText", true, false) as Label).text, "2")
	_tick(2.1)
	var digit := hud.find_child("CountdownText", true, false) as Label
	eq(digit.text, "开战")
	ok(digit.is_visible_in_tree(), "开战数字还在")
	var play := hud.find_child("PlayChrome", true, false) as Control
	ok(play.visible, "对局界面已打开")
	hud.call("_advance", 0.8)
	ok(not digit.is_visible_in_tree(), "开战字样在 0.8 秒后收起")
	var score := (hud.find_child("ScoreText", true, false) as RichTextLabel).text
	ok(score.contains("12:00") and score.contains("灰卫") and score.contains("锈誓") and score.contains("塔2"),
			"记分条应有双方、时间和两座塔：%s" % score)
	var lock := hud.find_child("BlueLock2", true, false) as Label
	ok(lock.visible and lock.text == "锁", "没露出的水晶显示锁")
	var fill := hud.find_child("BlueFill2", true, false) as ColorRect
	eq(fill.color, LOCKED_BAR)
	var outer := hud.find_child("BlueLock0", true, false) as Label
	ok(not outer.visible, "外塔没有锁")
	ok((hud.find_child("Minimap", true, false) as Control).is_visible_in_tree(), "小地图在树上")
	ok((hud.find_child("LevelText", true, false) as Label).text.contains("等级 1"), "等级行")
	ok((hud.find_child("EmberText", true, false) as Label).text.contains("余烬"), "余烬行")
	await _free(hud)


func test_kill_feed_caps_at_five_and_fades() -> void:
	var hud := _play_hud()
	for i in 6:
		ArenaRun.report_death({
			"victim_id": "m%d" % i,
			"victim_team": ArenaCatalog.TEAM_ENEMY,
			"victim_kind": "minion",
			"victim_label": "兵%d" % i,
			"killer_id": "player",
			"xp": 1,
			"ember": 1,
		})
	ArenaRun.apply_structure_damage(ArenaCatalog.TEAM_ENEMY, 0, 200, "player")
	var lines := _feed_lines(hud)
	eq(lines.size(), 5, "击杀播报最多 5 条")
	var blob := ""
	var broke := false
	for line in lines:
		var text := (line as RichTextLabel).text
		blob += text
		if text.contains("被摧毁"):
			broke = true
			ok(not text.contains("击败"), "拆塔不是普通击杀句式")
	ok(broke, "拆塔有单独播报")
	ok(blob.contains("兵5") and not blob.contains("兵0"))
	ok(blob.contains("[color="), "击杀者和被击杀者按队伍着色")
	hud.call("_advance", 2.5)
	almost((lines[0] as RichTextLabel).modulate.a, 0.5, 0.08)
	hud.call("_advance", 2.5)
	eq(_feed_lines(hud).size(), 0, "5 秒后播报淡出")
	await _free(hud)


func test_respawn_countdown_and_blessing_banner() -> void:
	var hud := _play_hud()
	ArenaRun.report_death({
		"victim_id": "player",
		"victim_team": ArenaCatalog.TEAM_PLAYER,
		"victim_kind": "hero",
		"victim_label": "余烬骑士",
		"killer_id": "enemy_0",
		"xp": 10,
		"ember": 4,
	})
	hud.call("_advance", 0.0)
	var respawn := hud.find_child("RespawnText", true, false) as Label
	ok(respawn.visible)
	ok(respawn.text.contains("复活倒计时") and respawn.text.contains("秒"))
	ArenaRun.grant_blessing(ArenaCatalog.TEAM_PLAYER)
	var banner := hud.find_child("BlessingBanner", true, false) as Label
	ok(banner.visible and banner.text.contains("炉火祝福"))
	ok((hud.find_child("BlessText", true, false) as Label).text.contains("炉火"))
	hud.call("_advance", 3.0)
	ok(not banner.visible)
	await _free(hud)


func test_shop_reports_ember_and_range() -> void:
	var host := Node2D.new()
	add_child(host)
	var player := await spawn_player(host, ArenaCatalog.BLUE_FOUNTAIN)
	player.global_position = ArenaCatalog.fountain_for(ArenaCatalog.TEAM_PLAYER)
	var hud := _play_hud()
	ok((hud.find_child("NearText", true, false) as Label).text.contains("炉台"))
	hud.call("_unhandled_input", _press(&"interact"))
	var shop := hud.find_child("Shop", true, false) as Control
	ok(shop.visible)
	var menu := hud.find_child("ShopMenu", true, false) as MenuList
	ok(menu.active)
	menu._unhandled_input(_press(&"ui_accept"))
	var status := hud.find_child("ShopStatus", true, false) as Label
	ok(status.text.contains("余烬不足"))
	ArenaRun.grant_ember("player", 40)
	menu._unhandled_input(_press(&"ui_accept"))
	ok(status.text.contains("已强化"))
	player.global_position = Vector2(2000, 312)
	menu._unhandled_input(_press(&"ui_accept"))
	ok(status.text.contains("泉水"))
	hud.call("_unhandled_input", _press(&"ui_cancel"))
	ok(not shop.visible)
	hud.call("_unhandled_input", _press(&"interact"))
	ok(not shop.visible, "离开泉水不能打开炉台")
	await _free(hud)
	host.queue_free()
	await get_tree().process_frame


func test_result_esc_focuses_exit_and_buttons_work() -> void:
	var hud := _play_hud()
	ArenaRun.finish(true)
	var result := hud.find_child("ResultRoot", true, false) as Control
	ok(result.visible)
	ok((hud.find_child("Title", true, false) as Label).text.contains("胜"))
	ok((hud.find_child("ResultMeta", true, false) as Label).text.contains("时长"))
	ok((hud.find_child("ResultScore", true, false) as Label).text.contains("击杀"))
	ok((hud.find_child("ResultPlayer", true, false) as Label).text.contains("K "))
	ok((hud.find_child("ResultMvp", true, false) as Label).text.contains("MVP"))
	ok((hud.find_child("NewRecord", true, false) as Label).visible)
	var menu := hud.find_child("ResultMenu", true, false) as MenuList
	eq(menu.selected_id(), &"rematch")
	hud.call("_unhandled_input", _press(&"ui_cancel"))
	eq(menu.selected_id(), &"title", "Esc 把焦点移到返回标题")
	eq(ArenaRun.phase(), ArenaCatalog.PHASE_RESULT)
	ok(ArenaRun.active(), "Esc 不直接退出")
	menu.select(0, false)
	menu._unhandled_input(_press(&"ui_accept"))
	eq(ArenaRun.phase(), ArenaCatalog.PHASE_COUNTDOWN)
	ok(not result.visible)
	ArenaRun.finish(true)
	ok(result.visible)
	var back := menu.item_ids().find(&"title")
	menu.select(back, false)
	menu._unhandled_input(_press(&"ui_accept"))
	eq(ArenaRun.phase(), ArenaCatalog.PHASE_IDLE)
	ok(not ArenaRun.active())
	ok(not result.is_visible_in_tree())
	_stop_fade()
	await _free(hud)


func test_pause_menu_arena_branch_keeps_campaign_items() -> void:
	var pause := PauseMenu.new()
	add_child(pause)
	await get_tree().process_frame
	eq(pause.menu().items().size(), 7, "战役暂停菜单仍是七格")
	var ids := pause.menu().item_ids()
	ok(ids.has(PauseMenu.ID_RESUME) and ids.has(PauseMenu.ID_STORY))
	ok(ids.has(PauseMenu.ID_MAP) and ids.has(PauseMenu.ID_TITLE))
	ok(not ids.has(PauseMenu.ID_ARENA_RESTART))
	pause.open()
	ok(pause.is_open() and pause.menu().visible)
	ok(not pause.arena_menu().visible)
	pause.close()
	await get_tree().process_frame
	ok(not get_tree().paused)

	ArenaRun.activate_for_test()
	pause.open()
	ok(not pause.is_open(), "大厅不能打开暂停菜单")
	ok(not get_tree().paused)
	ArenaRun.begin_match()
	pause.open()
	ok(not pause.is_open(), "倒计时不能打开暂停菜单")

	_tick(3.1)
	pause.open()
	ok(pause.is_open() and get_tree().paused)
	ok(pause.arena_menu().visible)
	ok(not pause.menu().visible)
	eq(pause.arena_menu().items().size(), 3)
	eq(pause.menu().items().size(), 7, "藏起来的战役菜单格子还在")
	var arena_ids := pause.arena_menu().item_ids()
	eq(arena_ids.size(), 3)
	ok(arena_ids.has(PauseMenu.ID_RESUME))
	ok(arena_ids.has(PauseMenu.ID_ARENA_RESTART))
	ok(arena_ids.has(PauseMenu.ID_ARENA_EXIT))
	var dossier := pause.find_child("DossierColumn", true, false) as CanvasItem
	ok(dossier != null and not dossier.visible)
	pause._on_chosen(PauseMenu.ID_ARENA_RESTART)
	ok(not get_tree().paused, "重开前先恢复暂停")
	ok(not Director.is_suspended())
	ok(not pause.is_open())
	eq(ArenaRun.phase(), ArenaCatalog.PHASE_COUNTDOWN)

	_tick(3.1)
	pause.open()
	pause._on_chosen(PauseMenu.ID_ARENA_EXIT)
	ok(not get_tree().paused)
	ok(not ArenaRun.active())
	_stop_fade()
	pause.queue_free()
	await get_tree().process_frame


func test_result_blocks_pause_and_campaign_death_overlay_stays_down() -> void:
	var pause := PauseMenu.new()
	add_child(pause)
	await get_tree().process_frame
	var hud := _play_hud()
	ArenaRun.finish(true)
	pause.open()
	ok(not pause.is_open(), "结算页不能打开暂停菜单")
	ok(not get_tree().paused)
	pause.queue_free()

	var campaign: Node = HUD_SCENE.instantiate()
	add_child(campaign)
	await get_tree().process_frame
	var objective := campaign.find_child("ObjectiveLabel", true, false) as Label
	var atmos := campaign.find_child("AtmosphereHint", true, false) as Label
	var sockets := campaign.find_child("Sockets", true, false) as Control
	var banner := campaign.find_child("Banner", true, false) as Control
	var plate := campaign.find_child("HintPlate", true, false) as Control
	var hearts := campaign.find_child("Hearts", true, false) as Control
	objective.text = "去东厢"
	atmos.text = "灰时"
	sockets.visible = true
	banner.visible = true
	plate.visible = true
	campaign.call("peek_for", 5.0)
	campaign.call("_process", 0.2)
	ok(not objective.visible, "竞技场里不显示战役目标")
	ok(not atmos.visible, "竞技场里不显示章节/天气")
	ok(not sockets.visible)
	ok(not banner.visible)
	ok(not plate.visible)
	ok(hearts.visible, "血量心还在")
	var death := campaign.find_child("DeathOverlay", true, false) as Control
	GameEvents.player_died.emit()
	await get_tree().process_frame
	ok(death != null and not death.visible, "竞技场死亡不弹死亡幕")
	ArenaRun.abandon()
	campaign.call("_process", 0.2)
	ok(objective.visible, "离开竞技场后目标还能显示")
	GameEvents.player_died.emit()
	await get_tree().process_frame
	ok(death.visible, "战役死亡幕仍然会弹出")
	await _free(hud)
	campaign.queue_free()
	await get_tree().process_frame


func test_overlays_do_not_stick_after_abandon() -> void:
	var hud := _play_hud()
	ArenaRun.finish(true)
	var result := hud.find_child("ResultRoot", true, false) as Control
	var veil := result.find_child("Veil", true, false) as CanvasItem
	ok(result.is_visible_in_tree())
	ok(veil != null and veil.is_visible_in_tree())
	ArenaRun.abandon()
	ok(not result.is_visible_in_tree())
	ok(not veil.is_visible_in_tree(), "放弃对局后结算纱幕不留在树上")
	ok(not (hud.find_child("Lobby", true, false) as Control).visible)
	ok(not (hud.find_child("Shop", true, false) as Control).visible)
	ok(not (hud.find_child("Countdown", true, false) as Control).visible)
	ok(not (hud.find_child("PlayChrome", true, false) as Control).visible)
	await _free(hud)
	ok(not ArenaRun.ui_attached)


func test_lobby_buttons_fit_720_and_540() -> void:
	var win := get_tree().root
	var saved := win.size
	ArenaRun.activate_for_test()
	var hud := _hud()
	await get_tree().process_frame
	await get_tree().process_frame
	var sizes: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(960, 540)]
	for view_size in sizes:
		win.size = view_size
		await get_tree().process_frame
		await get_tree().process_frame
		var view := get_viewport().get_visible_rect()
		var menu := hud.find_child("LobbyMenu", true, false) as MenuList
		ok(menu != null)
		var seen := 0
		for child in menu.items():
			var item := child as Control
			var rect := item.get_global_rect()
			ok(rect.size.x > 8.0 and rect.size.y > 8.0, "按钮有尺寸 %s" % rect)
			ok(rect.position.x >= view.position.x - 1.0, "%s 左 %s" % [view_size, rect])
			ok(rect.position.y >= view.position.y - 1.0, "%s 上 %s" % [view_size, rect])
			ok(rect.end.x <= view.end.x + 1.0, "%s 右 %s 视口 %s" % [view_size, rect, view])
			ok(rect.end.y <= view.end.y + 1.0, "%s 下 %s 视口 %s" % [view_size, rect, view])
			seen += 1
		eq(seen, 3, "难度、开战、返回标题")
	win.size = saved
	await get_tree().process_frame
	await _free(hud)


# --------------------------------------------------------------------- helpers

func _hud() -> Node:
	var hud: Node = ArenaHud.new()
	hud.name = "ArenaInterface"
	add_child(hud)
	return hud


func _play_hud() -> Node:
	ArenaRun.auto_begin = true
	ArenaRun.activate_for_test()
	return _hud()


func _free(hud: Node) -> void:
	if hud != null and is_instance_valid(hud):
		hud.queue_free()
	await get_tree().process_frame


func _press(action: StringName) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	return ev


func _tick(seconds: float) -> void:
	var host := get_tree().root.get_node("ArenaRun")
	host._process(seconds)


func _difficulty_text(menu: MenuList) -> String:
	for child in menu.items():
		if not (child is MenuItem) or (child as MenuItem).id != &"difficulty":
			continue
		var item := child as MenuItem
		for node in item.get_children():
			if node is Label:
				return (node as Label).text
		return String(item.get("_text"))
	return ""


func _feed_lines(hud: Node) -> Array:
	var out: Array = []
	var box := hud.find_child("KillFeed", true, false)
	if box == null:
		return out
	for child in box.get_children():
		if child is RichTextLabel and (child as RichTextLabel).visible and (child as RichTextLabel).text != "":
			out.append(child)
	return out


func _stop_fade() -> void:
	Director._fading = false
	Director._queued_fade_path = ""


func _drop_fake_lanes() -> void:
	var nodes := get_tree().get_nodes_in_group("game_world")
	for node in nodes:
		if node != null and str(node.name) == "FakeLane":
			node.remove_from_group("game_world")
			node.queue_free()


func _quiet() -> void:
	ArenaRun.auto_begin = false
	ArenaRun.shop_ignore_range = false
	ArenaRun.set_ui_attached(false)
	if Director.is_suspended():
		Director.resume()
	if Director.playing:
		Director.abort()
	_stop_fade()
	if get_tree() != null and get_tree().paused:
		get_tree().paused = false
	ArenaRun.abandon()
	ArenaRun.set_difficulty(ArenaCatalog.DEFAULT_DIFFICULTY)


class FakeLane extends Node2D:
	var driven := true
	var released := 0
	var aims: Array[Vector2] = []

	func set_camera_driver(enabled: bool) -> void:
		driven = enabled

	func camera() -> Node:
		return self

	func focus(at: Vector2, _zoom: float = 1.0, _duration: float = 0.5) -> void:
		aims.append(at)

	func release() -> void:
		released += 1
