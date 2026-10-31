extends TestCase
## 标题屏版式回归（灯标版）：菜单是左下一列刻字（行动 / 模式 / 系统 / 离开
## 四组、七行、每行 52px 触控高度），光标是 LampCursor 那盏吊灯；右侧是旅程标尺 +
## 数据片（悬停 / Tab 展开完整档案）、
## 底部是打字机墓志与页脚；所有区块在 1280x720 / 1920x1080 / 非 16:9 窗口里互不重叠、
## 都落在内容矩形内。异形板（menu_plate.gd）仍服务暂停菜单等其它屏，这里一并守住它。

const TITLE_SCENE := "res://scenes/ui/TitleScreen.tscn"
const Plate := preload("res://scripts/ui/menu_plate.gd")
const ArenaCatalog := preload("res://scripts/data/arena_catalog.gd")
## 骑士站在 x=640 的光柱下：菜单任何一行都不能越过这条中线。
const KEYART_CENTER := 640.0
const EXPECTED_KINDS := [MenuItem.Kind.PRIMARY, MenuItem.Kind.PRIMARY,
		MenuItem.Kind.SECONDARY, MenuItem.Kind.SECONDARY, MenuItem.Kind.SECONDARY,
		MenuItem.Kind.SECONDARY, MenuItem.Kind.GHOST]
## 三种窗口：设计尺寸、1080p、21:9 带鱼屏（非 16:9，左右留黑边）。
const WINDOWS := [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1080)]
## 一定要互不重叠的区块（设计空间里的节点名）。
const BLOCKS := ["Masthead", "Subtitle", "Menu", "JourneyColumn", "Epitaph", "CreditBand", "UpdateNotice"]


func setup() -> void:
	Director._set_lock(false)
	TitleWorld.forced_state = {}


func teardown() -> void:
	TitleWorld.forced_state = {}
	ArenaRun.use_default_file()


func _open_title() -> TitleScreen:
	var packed := load(TITLE_SCENE) as PackedScene
	var title := packed.instantiate() as TitleScreen
	add_child(title)
	await get_tree().process_frame
	await get_tree().process_frame
	return title


func _items(title: TitleScreen) -> Array:
	var out := []
	for child in title.get_node("Menu").get_children():
		if child is MenuItem:
			out.append(child)
	return out


func test_menu_is_a_left_rail_with_three_tiers() -> void:
	var title: TitleScreen = await _open_title()
	var menu := title.get_node_or_null("Menu") as MenuList
	ok(menu != null, "Menu 存在")
	if menu == null:
		title.queue_free()
		return
	almost(menu.position.x, TitleScreen.RAIL_X, 0.01, "菜单按设计像素挂在左侧")
	almost(menu.position.y, TitleScreen.RAIL_TOP, 0.01, "菜单顶边停在字标下方")

	var items := _items(title)
	ok(items.size() >= 7, "至少七格菜单（点燃 / 继续 / 试炼 / 竞技场 / 设置 / 说明 / 离开）")
	for i in mini(items.size(), EXPECTED_KINDS.size()):
		eq(items[i].kind, EXPECTED_KINDS[i], "第 %d 格的档位" % i)
	for item in items:
		ok(item.lamp, "灯标版式：字刻在场景上")
		ok(not item.strip, "标题屏不再铺铁条")
		ok(item.custom_minimum_size.y >= UiKit.TOUCH_MIN, "行高不低于触控下限 %.0f" % UiKit.TOUCH_MIN)
	# 三档宽度递减：行动 > 模式/系统 > 离开
	ok(items[0].custom_minimum_size.x > items[2].custom_minimum_size.x, "行动条比模式条宽")
	ok(items[2].custom_minimum_size.x > items[6].custom_minimum_size.x, "离开条最窄")

	var lamp := title.find_child("LampCursor", true, false) as TitleLampCursor
	ok(lamp != null, "光标是一盏吊灯")
	title.queue_free()
	await get_tree().process_frame


## 吊灯跟着选中行走：停在离开行时，那一行被照亮，最上面一行不在光照里。
func test_lamp_cursor_follows_the_selected_row() -> void:
	var title: TitleScreen = await _open_title()
	title._skip_intro()
	var lamp := title.find_child("LampCursor", true, false) as TitleLampCursor
	var menu := title.get_node("Menu") as MenuList
	ok(lamp != null, "吊灯存在")
	if lamp == null:
		title.queue_free()
		return
	menu.select(0, false)
	lamp.snap()
	var y_top := lamp.lantern_y()
	var top_light: float = (_items(title)[0] as MenuItem).lamp_light
	ok(top_light > 0.8, "灯停在第一行时，第一行被照亮 (%.2f)" % top_light)
	menu.select(6, false)
	lamp.snap()
	var y_quit := lamp.lantern_y()
	ok(y_quit > y_top + 80.0, "灯从第一行落到离开行 (%.0f -> %.0f)" % [y_top, y_quit])
	var quit_light: float = (_items(title)[6] as MenuItem).lamp_light
	var far_light: float = (_items(title)[0] as MenuItem).lamp_light
	ok(quit_light > 0.8, "离开行被照亮")
	ok(far_light < quit_light, "光照不到的行更暗 (%.2f < %.2f)" % [far_light, quit_light])
	title.queue_free()
	await get_tree().process_frame


## 四组之间有空白（行动 / 模式 / 系统 / 离开）：同组紧挨，跨组隔开一道。
func test_menu_groups_are_separated() -> void:
	var title: TitleScreen = await _open_title()
	var items := _items(title)
	var rects: Array[Rect2] = []
	for item in items:
		rects.append(title.design_rect(item))
	var gap_in_group := rects[1].position.y - rects[0].end.y
	almost(gap_in_group, 0.0, 0.5, "同一组的两行紧挨着")
	for boundary in [1, 3, 5]:
		var gap := rects[boundary + 1].position.y - rects[boundary].end.y
		almost(gap, TitleScreen.GROUP_GAP, 0.5, "第 %d 行之后有一道组间距" % boundary)
	title.queue_free()
	await get_tree().process_frame


func test_rail_stays_clear_of_the_keyart_center() -> void:
	var title: TitleScreen = await _open_title()
	for item in _items(title):
		var right: float = title.design_rect(item).end.x
		ok(right < KEYART_CENTER, "菜单行右端不越过中线 (%.0f < 640)" % right)
	# 墓志在底部靠右，和左下菜单配重。
	var epitaph := title.get_node_or_null("Inscription/EpitaphRow/Epitaph") as Label
	ok(epitaph != null, "墓志存在")
	if epitaph != null:
		var box: Rect2 = title.design_rect(epitaph)
		ok(box.position.x > TitleScreen.EPITAPH_RECT.position.x - 1.0, "墓志落在墓志区内（避开左侧菜单）")
		ok(box.position.y > 360.0, "墓志在画面下半边")
		ok(box.end.x <= TitleScreen.JOURNEY_X + 1.0, "墓志右端停在旅程列之前")

	title.queue_free()
	await get_tree().process_frame


func test_plate_shapes_differ_and_states_recolour() -> void:
	var primary := Plate.plate_size(Plate.Shape.PRIMARY)
	var secondary := Plate.plate_size(Plate.Shape.SECONDARY)
	var ghost := Plate.plate_size(Plate.Shape.GHOST)
	ok(primary.x > secondary.x and secondary.x > ghost.x, "三类板宽度递减")
	ok(primary.y > secondary.y, "主行动比次行动高一档")
	almost(ghost.y, secondary.y, 0.01, "次行动与幽灵行同高")

	for shape in [Plate.Shape.PRIMARY, Plate.Shape.SECONDARY, Plate.Shape.GHOST]:
		var normal := Plate.texture(shape, Plate.State.NORMAL)
		var selected := Plate.texture(shape, Plate.State.SELECTED)
		ok(normal != null and selected != null, "板贴图生成成功")
		ok(normal != selected, "选中态换了一张板")
		ok(Plate.texture(shape, Plate.State.NORMAL) == normal, "同类板贴图有缓存")


func test_select_walks_the_menu_and_skips_disabled_rows() -> void:
	var title: TitleScreen = await _open_title()
	var menu := title.get_node("Menu") as MenuList
	menu.select(0, false)
	eq(menu.selected_id(), &"new", "第一格是点燃余烬")
	menu.select(6, false)
	eq(menu.selected_id(), &"quit", "最后一格是离开")
	# 上下键从顶部往下走，必须落在可用行上（无存档时"继续旅程"是禁用的）。
	menu.select(0, false)
	menu._step(1)
	var landed: MenuItem = menu._items[menu._index]
	ok(not landed.disabled, "上下键跳过禁用行")

	title.queue_free()
	await get_tree().process_frame


## 鼠标悬停与键盘上下键共用同一条"选中"信号：任何时刻只有一格是选中的，
## 两种输入方式看到的是同一条亮起的铁条（不出现"高亮一格、回车执行另一格"）。
func test_hover_and_keyboard_share_one_selection() -> void:
	var title: TitleScreen = await _open_title()
	var menu := title.get_node("Menu") as MenuList
	var items := _items(title)
	for i in items.size():
		var item: MenuItem = items[i]
		item.hover_requested.emit()
		await get_tree().process_frame
		var selected := 0
		for other in items:
			if other.selected:
				selected += 1
		eq(selected, 1, "hovering row %d leaves exactly one selected row" % i)
		if not item.disabled:
			eq(menu.selected_id(), _id_for(i), "hover selects the row under the mouse")
	menu.select(0, false)
	menu._step(1)
	await get_tree().process_frame
	var count := 0
	for other in items:
		if other.selected:
			count += 1
	eq(count, 1, "keyboard step also leaves exactly one selected row")
	title.queue_free()
	await get_tree().process_frame


## 菜单下标 → 菜单 id（七格顺序与 _build_rail 一致）。
func _id_for(index: int) -> StringName:
	var ids: Array[StringName] = [&"new", &"continue", &"trial", &"arena",
			&"settings", &"controls", &"quit", &"update"]
	return ids[index] if index < ids.size() else &""


## 聚焦一行：场景里的吊灯亮一下 + 镜头轻推（火星由 UI 层负责）。
func test_menu_focus_nudges_the_live_scene() -> void:
	var title: TitleScreen = await _open_title()
	title._skip_intro()
	var world := title.world()
	ok(world != null, "活景存在")
	if world == null:
		title.queue_free()
		return
	var menu := title.get_node("Menu") as MenuList
	menu.select(0, false)
	menu.select(3, false)
	await get_tree().process_frame
	ok(world._push_kick > 0.0, "聚焦时镜头有一小下推力 (%.2f)" % world._push_kick)
	ok(world._flare > 0.0, "聚焦时场景光有一次闪亮")
	title.queue_free()
	await get_tree().process_frame


## 回火试炼入口：未解锁置灰 + 灰态说明；trial_unlocked（或第七章通关 / 结局）后点亮。
func test_trial_entry_is_gated_by_unlock_flag() -> void:
	var saved_flags := SaveData.flags.duplicate()
	var saved_ending := SaveData.ending
	var saved_path := SaveData.save_path
	var gate_path := "user://title_trial_gate_test.cfg"
	SaveData.save_path = gate_path
	if FileAccess.file_exists(gate_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(gate_path))
	SaveData.flags = PackedStringArray()
	SaveData.ending = ""

	var title: TitleScreen = await _open_title()
	var items := _items(title)
	ok(items.size() >= 7, "至少七格菜单")
	eq(items[2].kind, MenuItem.Kind.SECONDARY, "回火试炼是模式组第一格（次档）")
	ok(items[2].disabled, "未解锁时回火试炼置灰")
	ok((title.get_node("Menu") as MenuList).get_child_count() > 0)
	(title.get_node("Menu") as MenuList).select(2, false)
	eq((title.get_node("Menu") as MenuList).selected_id(), &"trial", "第三格是 trial")
	ok(title.find_child("TrialLockHint", true, false) is Label, "灰态旁有解锁说明")
	ok(items[2]._note != null and items[2]._note.visible, "灰态的条上有一行解锁小字")
	title.queue_free()
	await get_tree().process_frame

	SaveData.flags = PackedStringArray()
	SaveData.mark_flag("trial_unlocked")
	title = await _open_title()
	items = _items(title)
	ok(not items[2].disabled, "trial_unlocked 后回火试炼可点")
	ok(title.find_child("TrialLockHint", true, false) == null, "解锁后不再显示灰态说明")
	title.queue_free()
	await get_tree().process_frame

	SaveData.flags = saved_flags
	SaveData.ending = saved_ending
	if FileAccess.file_exists(gate_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(gate_path))
	SaveData.save_path = saved_path


func test_quit_plays_an_exit_sequence_and_can_be_skipped() -> void:
	var title: TitleScreen = await _open_title()
	# 测试里只走动画，不真的退出进程。
	title.quit_on_finish = false
	title._on_chosen(&"quit")
	await get_tree().process_frame
	ok(title.is_quitting(), "离开锈墓先播退场动画")
	ok(not (title.get_node("Menu") as MenuList).active, "退场期间菜单不再吃输入")
	ok(title.find_child("QuitCaption", true, false) is Label, "黑幕上留着那句退场墓志")
	# 任意按键 = 立刻收尾，等人为退场动画不可接受。
	title._finish_quit()
	ok(title.quit_finished(), "退场动画可以被跳过并正常收尾")
	title.queue_free()
	await get_tree().process_frame


## 退场：吊灯一盏盏熄灭，活景自己暗下去（只剩巨剑剪影），而不是被一块黑幕盖掉。
func test_quit_puts_the_lanterns_out_one_by_one() -> void:
	# 中期存档：第三幕，四盏吊灯亮着
	TitleWorld.forced_state = TitleWorld.build_state({"has_save": true,
			"scene": GameContext.LEVELS["level08"], "flags": PackedStringArray(), "ending": "",
			"skin": "", "origin": "", "rank": 3})
	var title: TitleScreen = await _open_title()
	title._skip_intro()
	title.quit_on_finish = false
	var world := title.world()
	var before: int = world.lit_lanterns() if world != null else 0
	ok(before >= 3, "第三幕开着至少三盏灯 (%d)" % before)
	title._on_chosen(&"quit")
	await get_tree().process_frame
	ok(title.is_quitting(), "进入退场")
	if world != null and before > 0:
		# 第一盏在 t=0 就熄；其余按间隔逐盏熄灭。中途还剩几盏，等够时间后应当全熄。
		await get_tree().create_timer(0.2 * 0.5).timeout
		ok(world.lit_lanterns() < before or before == 1, "灯在逐盏熄灭，不是一把全灭")
		await get_tree().create_timer(0.2 * float(before) + 0.4).timeout
		eq(world.lit_lanterns(), 0, "吊灯逐盏熄灭后一盏不剩")
	title._finish_quit()
	ok(title.quit_finished(), "收尾")
	title.queue_free()
	await get_tree().process_frame


## 右侧旅程列：阶位 / 外观 / 试炼记录 / 上次章节在完整档案里（平时收起）。
func test_dossier_shows_profile_summary_with_a_save() -> void:
	var path := "user://title_dossier_test.cfg"
	SaveData.save_path = path
	SaveData.delete_save()
	SaveData.init_new_game(OriginCatalog.ORIGIN_EMBER_VANGUARD)
	SaveData.set_ember_state(4, 812, 3)
	SaveData.set_skin("skin_gothic_hero", "rune_unbroken")
	SaveData.persist_profile()
	var title: TitleScreen = await _open_title()
	ok(title.find_child("Dossier", true, false) is PanelContainer, "档案面板存在")
	var rank := title.find_child("DossierRank", true, false) as Label
	ok(rank != null and rank.text.contains("4 阶"), "阶位摘要：%s" % (rank.text if rank != null else ""))
	ok(rank != null and rank.text.contains("3"), "属性点也被显示")
	var skin := title.find_child("DossierSkin", true, false) as Label
	ok(skin != null and skin.text.contains("哥特猎手"), "当前皮肤")
	ok(title.find_child("DossierTrials", true, false) is Label, "试炼记录行存在")
	ok(title.find_child("DossierArena", true, false) is Label, "竞技场记录行存在")
	ok(title.find_child("DossierChapter", true, false) is Label, "上次行程行存在")
	ok(title.find_child("ChipRank", true, false) == null, "阶位不再折在标题上")
	ok(title.find_child("ChipSkin", true, false) == null, "外观不再折在标题上")
	var count := title.find_child("JourneyCount", true, false) as Label
	ok(count != null and count.text.contains("/"), "短注写着通关数：%s" % (count.text if count != null else ""))
	title.queue_free()
	await get_tree().process_frame
	SaveData.delete_save()
	SaveData.save_path = "user://rustgrave_save.cfg"


func test_dossier_has_placeholders_without_a_save() -> void:
	SaveData.save_path = "user://title_dossier_empty.cfg"
	SaveData.delete_save()
	var arena_path := "user://title_arena_records_test.cfg"
	if FileAccess.file_exists(arena_path):
		DirAccess.remove_absolute(arena_path)
	ArenaRun.use_file(arena_path)
	var title: TitleScreen = await _open_title()
	var rank := title.find_child("DossierRank", true, false) as Label
	ok(rank != null and rank.text.contains("尚无"), "无存档时有占位文案")
	var trials := title.find_child("DossierTrials", true, false) as Label
	ok(trials != null and trials.text.contains("未踏足"))
	var arena := title.find_child("DossierArena", true, false) as Label
	ok(arena != null and arena.text == "胜 0 场", "没有胜场键时档案记胜 0 场")
	ok(title.find_child("ChipArena", true, false) == null, "竞技场不再折成芯片")
	ok(title.find_child("ChipTrials", true, false) == null, "试炼不再折成芯片")
	var legacy := ConfigFile.new()
	legacy.set_value("meta", "best_score", 90)
	legacy.set_value("meta", "runs", 3)
	legacy.save(arena_path)
	title.queue_free()
	await get_tree().process_frame
	title = await _open_title()
	arena = title.find_child("DossierArena", true, false) as Label
	ok(arena != null and arena.text == "胜 0 场", "旧档没有 wins 键时按 0 场")
	legacy.set_value("meta", "wins", 7)
	legacy.save(arena_path)
	title.queue_free()
	await get_tree().process_frame
	title = await _open_title()
	arena = title.find_child("DossierArena", true, false) as Label
	ok(arena != null and arena.text == "胜 7 场", "档案显示胜场")
	var chapter := title.find_child("JourneyChapter", true, false) as Label
	ok(chapter != null and chapter.text.contains("尚无旅程"), "旅程列的章节行有占位")
	var gauge := title.find_child("JourneyGauge", true, false) as TitleGauge
	ok(gauge != null and gauge.lit_count() == 0, "无存档时 14 个刻度全是冷的")
	title.queue_free()
	await get_tree().process_frame
	SaveData.delete_save()
	SaveData.save_path = "user://rustgrave_save.cfg"
	if FileAccess.file_exists(arena_path):
		DirAccess.remove_absolute(arena_path)
	ArenaRun.use_default_file()


## 右侧是一条短注：计数、章名、横着的 14 格、回看。没有竖排数字，也没有折叠芯片。
func test_journey_note_is_a_short_horizontal_rail() -> void:
	var title: TitleScreen = await _open_title()
	var column := title.find_child("JourneyColumn", true, false) as Control
	var gauge := title.find_child("JourneyGauge", true, false) as TitleGauge
	var chapter := title.find_child("JourneyChapter", true, false) as Label
	var button := title.find_child("RecapButton", true, false) as Control
	ok(column != null and gauge != null and chapter != null and button != null, "短注的四件都在")
	if column != null:
		almost(column.size.y, TitleScreen.JOURNEY_H, 0.5, "旅程列收成一条短注")
		ok(column.size.y < 160.0, "不再是铺满右侧的长列")
	if gauge != null and chapter != null and button != null:
		ok(gauge.horizontal, "刻度是横轨")
		ok(gauge.position.y > chapter.position.y, "横轨在章名下面")
		ok(button.position.y > gauge.position.y, "回看在横轨下面")
	ok(title.get_node_or_null("Inscription/EpitaphRow/EpitaphBacking") == null, "墓志没有底板")
	ok(title.get_node_or_null("Inscription/EpitaphRow/EpitaphRule") == null, "墓志没有顶线")
	ok(title.get_node_or_null("Inscription/EpitaphRow/EpitaphNail") == null, "墓志没有钉子")
	ok(title.find_child("EpitaphShade", true, false) != null, "字后面留一块软暗斑")
	title.queue_free()
	await get_tree().process_frame


## 没停在「继续旅程」上时短注是淡的；停上去才亮，并且跟着厅灯呼吸。
func test_continue_focus_brightens_the_journey_note() -> void:
	var title: TitleScreen = await _open_title()
	title._skip_intro()
	var menu := title.get_node("Menu") as MenuList
	var ink := title.find_child("JourneyInk", true, false) as CanvasItem
	ok(ink != null, "短注有自己的一层墨")
	if ink == null:
		title.queue_free()
		return
	menu.select(6, false)
	await get_tree().process_frame
	var dim: float = ink.modulate.a
	menu.select(1, false)
	await get_tree().process_frame
	ok(ink.modulate.a > dim + 0.25, "继续旅程把短注点亮 (%.2f -> %.2f)" % [dim, ink.modulate.a])
	ok(ink.modulate.a <= 1.0, "亮不过满")
	title.queue_free()
	await get_tree().process_frame


func test_gauge_lights_the_cleared_chapters() -> void:
	var path := "user://title_gauge_test.cfg"
	SaveData.save_path = path
	SaveData.delete_save()
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 3)
	cfg.set_value("meta", "scene", String(GameContext.LEVELS["level04"]))
	cfg.set_value("story", "flags", ["boss_dead", "undercroft_done", "level02b_done", "level03_done"])
	cfg.save(path)
	var title: TitleScreen = await _open_title()
	var gauge := title.find_child("JourneyGauge", true, false) as TitleGauge
	ok(gauge != null, "旅程标尺存在")
	if gauge != null:
		eq(gauge.lit_count(), 4, "已通关四章 -> 四个刻度亮")
		eq(gauge.current_index(), 4, "当前章是第五个刻度")
	var chapter := title.find_child("JourneyChapter", true, false) as Label
	ok(chapter != null and chapter.text.contains(ChapterText.name_of("level04")), "章节行写当前章名：%s" % (chapter.text if chapter != null else ""))
	title.queue_free()
	await get_tree().process_frame
	SaveData.delete_save()
	SaveData.save_path = "user://rustgrave_save.cfg"


## Tab 固定展开完整档案；再按一次收起；悬停也能展开（这里直接走固定的那条）。
func test_tab_pins_and_unpins_the_full_dossier() -> void:
	var title: TitleScreen = await _open_title()
	title._skip_intro()
	ok(not title.dossier_open(), "默认收起")
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	title._unhandled_input(tab)
	ok(title.dossier_open(), "Tab 展开")
	var card := title.find_child("DossierWrap", true, false) as Control
	ok(card != null and card.visible, "档案卡可见")
	title._unhandled_input(tab)
	ok(not title.dossier_open(), "再按一次收起")
	title.queue_free()
	await get_tree().process_frame


## 排版约束：左下"离开锈墓"和底部墓志在同一条中心线上（屏幕底部的两个重音）。
func test_quit_aligns_with_epitaph() -> void:
	var title: TitleScreen = await _open_title()
	var menu := title.get_node("Menu") as MenuList
	var epitaph := title.get_node_or_null("Inscription/EpitaphRow/Epitaph") as Label
	ok(epitaph != null, "墓志句存在")
	if epitaph != null:
		var quit_item: MenuItem = menu.items()[menu.items().size() - 1]
		var quit_center := title.design_rect(quit_item).get_center().y
		var ep_center := title.design_rect(epitaph).get_center().y
		almost(quit_center, ep_center, 2.0, "离开锈墓与墓志同基线")
		almost(quit_center, TitleScreen.QUIT_CENTER_Y, 1.0, "基线就是设计里的 640")
	title.queue_free()
	await get_tree().process_frame


## 重叠防线：展开的档案卡（含底注）必须停在墓志上方、停在菜单右侧、停在字标下方。
func test_no_overlap_between_dossier_and_epitaph() -> void:
	var title: TitleScreen = await _open_title()
	var dossier := title.find_child("Dossier", true, false) as Control
	var epitaph := title.get_node_or_null("Inscription/EpitaphRow/Epitaph") as Control
	var foot := title.find_child("DossierFoot", true, false) as Control
	ok(dossier != null and epitaph != null, "档案与墓志都存在")
	if dossier != null and epitaph != null:
		var panel_rect := title.design_rect(dossier)
		var ep_rect := title.design_rect(epitaph)
		ok(panel_rect.end.y <= ep_rect.position.y + 1.0,
				"档案底 %.0f 不越过墓志顶 %.0f" % [panel_rect.end.y, ep_rect.position.y])
		var menu_rect := title.design_rect(title.get_node("Menu") as Control)
		ok(panel_rect.position.x >= menu_rect.end.x, "档案卡在菜单右侧")
		var logo_rect := title.design_rect(title.find_child("Subtitle", true, false) as Control)
		ok(panel_rect.position.y >= logo_rect.end.y, "档案卡在字标副题下方")
		if foot != null:
			var foot_rect := title.design_rect(foot)
			ok(panel_rect.encloses(foot_rect), "底注完整落在档案内")
	title.queue_free()
	await get_tree().process_frame


## 主要区块（字标 / 副题 / 菜单 / 旅程列 / 墓志 / 页脚 / 更新按钮）在三种窗口里互不重叠，
## 并且都落在窗口内容矩形里。UI 设计空间永远是 1280x720，窗口只改变缩放与留边，
## 所以这里把每个窗口的变换套上再量物理像素。
func test_blocks_do_not_overlap_and_stay_inside_at_three_window_shapes() -> void:
	var title: TitleScreen = await _open_title()
	title._skip_intro()
	var notice := title.find_child("UpdateNotice", true, false) as Control
	if notice != null:
		notice.visible = true         # 有新版本时它也要有自己的位置
	await get_tree().process_frame
	for win in WINDOWS:
		var metrics := PresentationMetrics.calculate(win)
		var xf: Transform2D = metrics["ui_transform"]
		title.position = xf.origin
		title.scale = xf.get_scale()
		await get_tree().process_frame
		var root_scale := Vector2(win) / Vector2(PresentationMetrics.UI_SIZE)
		var content: Rect2 = metrics["physical_rect"]
		var rects := {}
		for block in BLOCKS:
			var node := title.find_child(block, true, false) as Control
			if node == null:
				ok(false, "区块 %s 存在 (%s)" % [block, win])
				continue
			var gxf := node.get_global_transform()
			var a: Vector2 = gxf * Vector2.ZERO
			var b: Vector2 = gxf * node.size
			var phys := Rect2(a * root_scale, (b - a) * root_scale).abs()
			rects[block] = phys
			ok(content.grow(0.6).encloses(phys), "%s 落在内容矩形内 @%s %s vs %s" % [block, win, phys, content])
		var names := rects.keys()
		for i in names.size():
			for j in range(i + 1, names.size()):
				var ra: Rect2 = rects[names[i]]
				var rb: Rect2 = rects[names[j]]
				ok(not ra.grow(-0.6).intersects(rb.grow(-0.6)), "%s 与 %s 不重叠 @%s" % [names[i], names[j], win])
	title.queue_free()
	await get_tree().process_frame


## 墓志是慢速打字机：第一句永远是 EPITAPH；打完整句后停一会儿再换下一句。
func test_epitaph_types_slowly_and_starts_with_the_epitaph_line() -> void:
	var title: TitleScreen = await _open_title()
	eq(title.epitaph_line(), TitleScreen.EPITAPH, "第一句是 EPITAPH")
	var label := title.get_node("Inscription/EpitaphRow/Epitaph") as Label
	eq(label.text, TitleScreen.EPITAPH, "标签里就是这一句")
	title._skip_intro()
	title._ep_t = 0.0
	title._update_epitaph(TitleScreen.EPITAPH_CHAR * 3.0 + 0.001)
	eq(label.visible_characters, 3, "打了三个字")
	title._update_epitaph(TitleScreen.EPITAPH_CHAR * 40.0)
	eq(label.visible_characters, -1, "整句打完")
	# 停留够久 -> 淡出 -> 换下一句
	title._update_epitaph(TitleScreen.EPITAPH_HOLD + 0.01)
	title._update_epitaph(TitleScreen.EPITAPH_FADE + 0.01)
	ok(title.epitaph_line() != TitleScreen.EPITAPH, "轮到下一句")
	ok(label.text == title.epitaph_line(), "标签跟着换句")
	title.queue_free()
	await get_tree().process_frame


# ------------------------------------------------------------ 回看余烬 ----

const RECAP_SAVE := "user://title_recap_test.cfg"


## 把 SaveData 指到一个临时存档路径，并清空内存里的旗标 / 结局（标题冷启动时它们还没读档）。
func _begin_recap_env() -> Dictionary:
	var saved := {"path": SaveData.save_path, "flags": SaveData.flags.duplicate(),
			"ending": SaveData.ending}
	SaveData.save_path = RECAP_SAVE
	SaveData.flags = PackedStringArray()
	SaveData.ending = ""
	if FileAccess.file_exists(RECAP_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RECAP_SAVE))
	return saved


func _end_recap_env(saved: Dictionary) -> void:
	if FileAccess.file_exists(RECAP_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RECAP_SAVE))
	SaveData.save_path = String(saved["path"])
	SaveData.flags = saved["flags"]
	SaveData.ending = String(saved["ending"])


func _write_recap_save(ending: String, flags: Array) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 3)
	cfg.set_value("meta", "scene", String(GameContext.LEVELS["level05"]))
	if ending != "":
		cfg.set_value("meta", "ending", ending)
	cfg.set_value("player", "origin", "ember_vanguard")
	cfg.set_value("story", "flags", flags)
	cfg.save(RECAP_SAVE)


## 有结局时菜单行写着「回看余烬」：选它必须打开总结页，而不是直接读档进关。
func test_continue_row_with_an_ending_opens_the_recap_page() -> void:
	var saved := _begin_recap_env()
	_write_recap_save("give", [StoryFlow.done_flag("level01"), StoryFlow.done_flag("level02")])
	var title: TitleScreen = await _open_title()
	title._skip_intro()
	var items := _items(title)
	ok((items[1] as MenuItem)._text.contains("回 看 余 烬"), "有结局：这一行写「回看余烬」")
	ok(title._continue_opens_recap, "写着回看，行为就是回看")
	var menu := title.get_node("Menu") as MenuList
	title._on_chosen(TitleScreen.ID_CONTINUE)
	await get_tree().process_frame
	ok(title.recap_open(), "选「回看余烬」打开总结页")
	ok(not title._started, "没有直接读档进关")
	ok(not menu.active, "总结页开着：左下菜单不吃输入")
	var recap = title.recap_page()
	eq(recap.heading_text(), "结局 · 还火", "标题写结局名")
	eq(recap.count_text(), "已过 2 / 14 章",
			"前两章的完成旗标是 boss_dead / undercroft_done：按 DONE_FLAGS 数，冷启动（存档还没读进内存）也数得对")
	ok(recap.row_ids().has(&"continue"), "总结页里仍有「继续旅程」")
	ok(recap.row_ids().has(&"chapter_level01") and recap.row_ids().has(&"chapter_level02"),
			"第一、二章能再入")
	ok(not recap.row_ids().has(&"chapter_level03"), "没通关的章不列")
	recap.close()
	await get_tree().process_frame
	ok(not title.recap_open(), "Esc / 返回关掉总结页")
	ok(menu.active, "菜单重新吃输入")
	title.queue_free()
	await get_tree().process_frame
	_end_recap_env(saved)


## 没有结局时「继续旅程」仍然是直接读档；旅程列里的「回看余烬」按钮随时能开同一页。
func test_without_an_ending_continue_stays_a_load_and_the_button_opens_the_page() -> void:
	var saved := _begin_recap_env()
	_write_recap_save("", [StoryFlow.done_flag("level01")])
	var title: TitleScreen = await _open_title()
	title._skip_intro()
	ok(not title._continue_opens_recap, "没结局：继续就是继续")
	ok((_items(title)[1] as MenuItem)._text.contains("继 续 旅 程"), "行文案是继续旅程")
	var button := title.find_child("RecapButton", true, false) as Button
	ok(button != null, "旅程列里有回看按钮")
	button.pressed.emit()
	await get_tree().process_frame
	ok(title.recap_open(), "按钮打开总结页")
	var recap = title.recap_page()
	eq(recap.heading_text(), "尚无结局")
	eq(recap.count_text(), "已过 1 / 14 章")
	ok(recap.row_ids().has(&"continue"), "有存档就有继续旅程")
	recap.close()
	await get_tree().process_frame
	title.queue_free()
	await get_tree().process_frame
	_end_recap_env(saved)


## 再入某章的落点是该章入口出生点，不再是写死的 (176, 240)。
func test_chapter_entry_spawns_come_from_the_levels() -> void:
	eq(TitleScreen.chapter_entry_spawn("level01"), Level01Static.DEFAULT_SPAWN,
			"第一章：Level01Static.DEFAULT_SPAWN（表里的数值没漂移）")
	eq(TitleScreen.chapter_entry_spawn("level02"), Level02Layout.ENTRY_SPAWN,
			"第二章：Level02Layout.ENTRY_SPAWN")
	eq(TitleScreen.chapter_entry_spawn("level09b"), Vector2(96, -340), "风口崖道的入口在高处")
	for id in GameContext.LEVEL_ORDER:
		var spawn := TitleScreen.chapter_entry_spawn(id)
		ok(spawn != Vector2(176, 240), "%s 的落点不再是写死的 (176,240)" % id)
		if id != "level01" and id != "level02":
			eq(spawn, ChapterLayout.entry_spawn_of(id), "%s：和出口门送人过来的是同一个点" % id)


## ID_ARENA 以前没有分支（按了没反应）：现在走 ArenaRun.start()，和试炼入口同样的待遇。
func test_arena_entry_dispatches_to_the_arena_run() -> void:
	var title: TitleScreen = await _open_title()
	title.quit_on_finish = false
	var started := [0]
	title.arena_start = func() -> bool:
		started[0] += 1
		return true
	var menu := title.get_node("Menu") as MenuList
	title._on_chosen(TitleScreen.ID_ARENA)
	await get_tree().process_frame
	eq(started[0], 1, "确认竞技场格会调用 ArenaRun.start 一次")
	ok(not menu.active, "进场期间菜单不再吃输入")
	# 再按（进场动画里重复确认）不会重复开局：菜单已不接收
	title.queue_free()
	await get_tree().process_frame

	# 开局失败（例如竞技场没就绪）：菜单要还给玩家，而不是卡死。
	title = await _open_title()
	title.arena_start = func() -> bool: return false
	title._on_chosen(TitleScreen.ID_ARENA)
	await get_tree().process_frame
	ok((title.get_node("Menu") as MenuList).active, "失败时菜单重新可用")
	title.queue_free()
	await get_tree().process_frame


## 默认接线：不替换接缝时真的走 ArenaRun.start（会话拉起、世界路径指向竞技场）。
func test_arena_entry_default_wiring_starts_a_real_run() -> void:
	var saved_world := GameContext.pending_world_path
	var title: TitleScreen = await _open_title()
	title._on_chosen(TitleScreen.ID_ARENA)
	await get_tree().process_frame
	ok(ArenaRun.active(), "竞技场会话已经拉起")
	eq(GameContext.pending_world_path, ArenaCatalog.SCENE, "待载入的世界是竞技场")
	ArenaRun.abandon()
	GameContext.pending_world_path = saved_world
	title.queue_free()
	await flush(4)
	Director.choice_hold = false
	Director._fading = false


## 墓志和右下"回看余烬"条不能压在一起：水平方向必须留出安全缝。
func test_epitaph_clears_recap_button() -> void:
	var title: TitleScreen = await _open_title()
	var epitaph := title.get_node_or_null("Inscription/EpitaphRow/Epitaph") as Control
	var recap := title.find_child("RecapButton", true, false) as Control
	ok(epitaph != null and recap != null, "墓志与回看条都存在")
	if epitaph != null and recap != null:
		title._update_epitaph(TitleScreen.EPITAPH_CHAR * 40.0)
		var ep := title.design_rect(epitaph)
		var rc := title.design_rect(recap)
		ok(ep.end.x <= rc.position.x - 8.0,
				"墓志右端 %.0f 与回看条左端 %.0f 至少留 8px" % [ep.end.x, rc.position.x])
	title.queue_free()
	await get_tree().process_frame


## T1: 菜单可读性暗斑存在，且中心和边缘严格停在画面中线（x=640）左侧。
func test_menu_shade_exists_and_stays_left_of_midline() -> void:
	var title: TitleScreen = await _open_title()
	var shade := title.find_child("MenuShade", true, false) as Control
	ok(shade != null, "MenuShade 节点存在")
	if shade != null:
		var rect := title.design_rect(shade)
		var center_x := rect.position.x + rect.size.x * 0.5
		ok(center_x < KEYART_CENTER, "MenuShade 中心在屏幕中线左侧 (%.1f < 640)" % center_x)
		ok(rect.end.x <= KEYART_CENTER, "MenuShade 右边缘在中线左侧 (%.1f <= 640)" % rect.end.x)
		ok(rect.position.x >= 0.0, "MenuShade 落在屏幕内")
		var menu := title.get_node_or_null("Menu") as Control
		if menu != null:
			ok(shade.get_index() < menu.get_index(), "MenuShade 在菜单底层渲染")
		ok(shade.mouse_filter == Control.MOUSE_FILTER_IGNORE, "MenuShade 忽略鼠标事件")
	title.queue_free()
	await get_tree().process_frame


## T2: 锁定铁签悬挂在锁定项下方，不与其他任何菜单行矩形相交，且避开右侧场景告示牌。
func test_lock_tag_exists_and_does_not_intersect_other_rows() -> void:
	var saved_flags := SaveData.flags.duplicate()
	var saved_ending := SaveData.ending
	var saved_path := SaveData.save_path
	var gate_path := "user://title_lock_tag_test.cfg"
	SaveData.save_path = gate_path
	if FileAccess.file_exists(gate_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(gate_path))
	SaveData.flags = PackedStringArray()
	SaveData.ending = ""

	var title: TitleScreen = await _open_title()
	var tag := title.find_child("LockTag", true, false) as Control
	ok(tag != null, "锁定提示 LockTag 节点存在")
	if tag != null:
		ok(tag.visible, "未解锁时 LockTag 可见")
		var tag_rect := title.design_rect(tag)
		var items := _items(title)
		for item in items:
			if item.id == &"trial":
				continue
			var item_rect: Rect2 = title.design_rect(item)
			ok(not tag_rect.intersects(item_rect),
					"LockTag 不与菜单行 %s 重叠 (tag=%s, row=%s)" % [item.id, tag_rect, item_rect])
		ok(tag_rect.end.x < 240.0, "锁定铁签避开场景右侧告示牌 (%.0f < 240)" % tag_rect.end.x)
	title.queue_free()
	await get_tree().process_frame

	SaveData.flags = saved_flags
	SaveData.ending = saved_ending
	if FileAccess.file_exists(gate_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(gate_path))
	SaveData.save_path = saved_path


## T3: 灯笼光标放大至 3x (36x51) 且光晕扩大。
func test_lamp_cursor_dimensions_and_halo() -> void:
	var title: TitleScreen = await _open_title()
	var lamp := title.find_child("LampCursor", true, false) as TitleLampCursor
	ok(lamp != null, "LampCursor 存在")
	if lamp != null:
		var body := lamp.get_node_or_null("Lantern") as Control
		ok(body != null, "Lantern 灯身节点存在")
		if body != null:
			almost(body.custom_minimum_size.x, 36.0, 0.5, "灯身宽度为 36px (3x 比例)")
			almost(body.custom_minimum_size.y, 51.0, 0.5, "灯身高度为 51px (3x 比例)")
		var halo := lamp.get_node_or_null("Halo") as TextureRect
		ok(halo != null, "Halo 光晕节点存在")
		if halo != null:
			ok(halo.size.x >= 200.0, "光晕尺寸扩大 (%.0f >= 200)" % halo.size.x)
			ok(halo.material is CanvasItemMaterial, "光晕使用材质")
			if halo.material is CanvasItemMaterial:
				eq((halo.material as CanvasItemMaterial).blend_mode,
						CanvasItemMaterial.BLEND_MODE_ADD, "光晕材质为加色模式")
			ok(halo.modulate.r > halo.modulate.b, "光晕色调为暖色")
	title.queue_free()
	await get_tree().process_frame


## T5: 页脚渐变暗斑（截止在熔河上方）与精简致谢文案。
func test_footer_shade_and_shortened_credits() -> void:
	var title: TitleScreen = await _open_title()
	var shade := title.find_child("FooterShade", true, false) as Control
	ok(shade != null, "FooterShade 节点存在")
	if shade != null:
		ok(shade.position.y <= 660.0, "暗渐变顶端截止在熔河上方 (y=%.0f <= 660)" % shade.position.y)
		ok(shade.position.y + shade.size.y >= 716.0, "暗渐变覆盖整个页脚高度")
		ok(shade.mouse_filter == Control.MOUSE_FILTER_IGNORE, "FooterShade 忽略鼠标事件")
	var credits := title.find_child("Credits", true, false) as Label
	if credits == null:
		var band := title.find_child("CreditBand", true, false)
		if band != null and band.get_child_count() > 1:
			credits = band.get_child(1) as Label
	ok(credits != null, "致谢文本存在")
	if credits != null:
		ok(credits.text.length() <= 35, "致谢文案已精简为短句 (长 %d <= 35): %s" % [credits.text.length(), credits.text])
		var credits_right := title.design_rect(credits).end.x
		ok(credits_right < 480.0, "致谢文字右端停在左侧暗区 (%.0f < 480)" % credits_right)
	title.queue_free()
	await get_tree().process_frame


## 光源预算：UI 层不增加任何 PointLight2D，TitleWorld 光源不超过预算 8。
func test_ui_light_budget_has_zero_point_lights() -> void:
	var title: TitleScreen = await _open_title()
	var ui_lights: Array[Node] = []
	var world := title.find_child("TitleWorld", true, false)
	for light in title.find_children("*", "PointLight2D", true, false):
		if world == null or not world.is_ancestor_of(light):
			ui_lights.append(light)
	eq(ui_lights.size(), 0, "TitleScreen UI 层中不新增任何 PointLight2D 节点 (当前 %d)" % ui_lights.size())
	if world != null and world.has_method(&"light_count"):
		ok(world.light_count() <= TitleWorld.MAX_LIGHTS, "TitleWorld 光源不超过预算 8 (当前 %d)" % world.light_count())
	title.queue_free()
	await get_tree().process_frame


## R3: 标题屏开屏时间线顺延与推镜完成同步，总长 <= 3.0s
func test_title_screen_intro_timing_and_skip_integration() -> void:
	var title: TitleScreen = await _open_title()
	ok(TitleScreen.LOGO_AT >= TitleWorld.DOLLY_TIME - 0.1,
			"字标锻入时间 (%.2f) 与推镜落位 (1.6s) 同步" % TitleScreen.LOGO_AT)
	ok(TitleScreen.MENU_AT > TitleScreen.LOGO_AT,
			"菜单在字标锻入后落位 (MENU_AT=%.2f > LOGO_AT=%.2f)" % [TitleScreen.MENU_AT, TitleScreen.LOGO_AT])
	# 校验开屏总时长 <= 3.0s
	var menu_rows_count := 0
	for child in title.get_node("Menu").get_children():
		if child is MenuItem:
			menu_rows_count += 1
	var expected_total := TitleScreen.MENU_AT + TitleScreen.MENU_STAGGER * float(menu_rows_count) + TitleScreen.MENU_LAND + 0.1
	ok(expected_total <= 3.0, "标题开屏总时长 (%.2f) <= 3.0s" % expected_total)
	var world := title.world()
	if world != null:
		# 测试 title.skip_intro() 会同步联动 world.skip_intro()
		title.skip_intro()
		eq(world._dolly, Vector2.ZERO, "标题跳过开屏联动活景 _dolly 归零")
		for layer in world.parallax_layers():
			eq(layer.position, layer.position.round(), "标题跳过后视差层全部对齐整像素")
	title.queue_free()
	await get_tree().process_frame


func test_any_pressed_input_skips_intro_without_starting_a_run() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	for event in [key, mouse, pad]:
		var title: TitleScreen = await _open_title()
		ok(title.intro_playing(), "按键前仍在播放开屏")
		title._input(event)
		ok(not title.intro_playing(), "按下键盘、鼠标或手柄会立即跳过")
		ok(not title._started, "跳过本身不启动游戏")
		if title.world() != null:
			eq(title.world()._dolly, Vector2.ZERO, "输入跳过同步清除推镜")
		title.queue_free()
		await get_tree().process_frame


func test_footer_labels_fit_at_every_supported_text_scale() -> void:
	var original_scale := Settings.assist(&"text_scale")
	for text_scale in [0.85, 1.0, 1.35]:
		Settings.set_value(&"text_scale", text_scale, false)
		var title: TitleScreen = await _open_title()
		title.skip_intro()
		# Also exercise the live path used when returning from settings.
		Settings.set_value(&"text_scale", 1.35 if text_scale < 1.35 else 0.85, false)
		Settings.set_value(&"text_scale", text_scale, false)
		await flush(3)
		for node_name in ["Credits", "FooterHint"]:
			var label := title.get_node("CreditBand/" + node_name) as Label
			var rect := title.design_rect(label)
			ok(TitleScreen.FOOTER_RECT.encloses(rect),
					"%s 在字体比例 %.2f 时完整落在页脚带内：%s" % [node_name, text_scale, rect])
			ok(rect.end.y <= PresentationMetrics.UI_SIZE.y, "%s 不超过窗口底边" % node_name)
			ok(label.get_theme_font_size(&"font_size") <= 16, "%s 页脚字号不超过 16px" % node_name)
		title.queue_free()
		await get_tree().process_frame
	Settings.set_value(&"text_scale", original_scale, false)


func test_journey_note_rows_do_not_overlap_at_any_text_scale() -> void:
	var original_scale := Settings.assist(&"text_scale")
	var title: TitleScreen = await _open_title()
	title.skip_intro()
	var ink := title.get_node("JourneyColumn/JourneyInk") as Control
	var node_names := ["JourneyHeader", "JourneyCount", "JourneyChapter", "JourneyGauge", "RecapButton"]
	for text_scale in [0.85, 1.0, 1.35]:
		Settings.set_value(&"text_scale", text_scale, false)
		await flush(3)
		var bounds := title.design_rect(ink)
		var rectangles: Array[Rect2] = []
		for node_name in node_names:
			var node := ink.get_node(node_name) as Control
			var rect := title.design_rect(node)
			rectangles.append(rect)
			ok(bounds.encloses(rect), "%s 在字号比例 %.2f 时落在旅程短注内" % [node_name, text_scale])
		for i in rectangles.size():
			for j in range(i + 1, rectangles.size()):
				ok(not rectangles[i].intersects(rectangles[j]),
						"字号比例 %.2f 时 %s 和 %s 不重叠" % [text_scale, node_names[i], node_names[j]])
	title.queue_free()
	await get_tree().process_frame
	Settings.set_value(&"text_scale", original_scale, false)
