extends TestCase
## 标题屏版式回归（灯标版）：菜单是左下一列刻字（行动 / 模式 / 系统 / 离开
## 四组、七行、每行 52px 触控高度），光标是 LampCursor 那盏吊灯；右侧是旅程标尺 +
## 数据片（悬停 / Tab 展开完整档案）、
## 底部是打字机墓志与页脚；所有区块在 1280x720 / 1920x1080 / 非 16:9 窗口里互不重叠、
## 都落在内容矩形内。异形板（menu_plate.gd）仍服务暂停菜单等其它屏，这里一并守住它。

const TITLE_SCENE := "res://scenes/ui/TitleScreen.tscn"
const Plate := preload("res://scripts/ui/menu_plate.gd")
const ArenaCatalog := preload("res://scripts/data/arena_catalog.gd")
const MobaRunScript := preload("res://scripts/moba/moba_run.gd")
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


func _continue_row(title: TitleScreen) -> MenuItem:
	for item in _items(title):
		if (item as MenuItem).id == TitleScreen.ID_CONTINUE:
			return item
	return null


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
	almost(menu.position.y, TitleScreen.RAIL_TOP + MenuItem.HEIGHT, 0.01, "无档：隐藏「继续」后整列下移一行")

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
	# 无档时「继续」行隐藏：竞技场与试炼同组紧挨，组界仍在 1/3/5 之后。
	ok(not items[1].visible, "无档：「继续」行隐藏")
	var gap_in_group := rects[3].position.y - rects[2].end.y
	almost(gap_in_group, 0.0, 0.5, "同一组的两行紧挨着")
	almost(rects[2].position.y - rects[0].end.y, TitleScreen.GROUP_GAP, 0.5, "行动组之后有一道组间距")
	for boundary in [3, 5]:
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


## 菜单下标 → 菜单 id（七格顺序与 _build_rail 一致；「更新提示」不在菜单里）。
func _id_for(index: int) -> StringName:
	var ids: Array[StringName] = [&"new", &"continue", &"trial", &"arena",
			&"settings", &"controls", &"quit"]
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
			"scene": GameContext.LEVELS["stage05"], "flags": PackedStringArray(), "ending": "",
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
	ok(arena != null and arena.text == "3D场景试演", "3D原型不展示尚不存在的胜场")
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
	ok(arena != null and arena.text == "3D场景试演", "旧2.5D记录不混入3D场景")
	legacy.set_value("meta", "wins", 7)
	legacy.save(arena_path)
	title.queue_free()
	await get_tree().process_frame
	title = await _open_title()
	arena = title.find_child("DossierArena", true, false) as Label
	ok(arena != null and arena.text == "3D场景试演", "旧2.5D胜场不冒充3D战绩")
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


## 右侧是一列：上半短注（计数、章名、横着的 14 格）+ 中段档案摘要 + 底部回看，
## 与左下菜单块同顶同高，左右两侧视觉重量对等。
func test_journey_note_is_a_short_horizontal_rail() -> void:
	var title: TitleScreen = await _open_title()
	var column := title.find_child("JourneyColumn", true, false) as Control
	var gauge := title.find_child("JourneyGauge", true, false) as TitleGauge
	var chapter := title.find_child("JourneyChapter", true, false) as Label
	var button := title.find_child("RecapButton", true, false) as Control
	ok(column != null and gauge != null and chapter != null and button != null, "短注的四件都在")
	if column != null:
		almost(column.size.y, TitleScreen.JOURNEY_H, 0.5, "旅程列高度等于约定值")
		almost(column.position.y, TitleScreen.RAIL_TOP, 0.5, "和左下菜单同顶")
		ok(column.size.y >= 340.0, "右列拉成与菜单对等的块面（不是一条细注）")
		ok(column.size.y < 420.0, "右列仍短于墓碑，不上到字标")
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
	cfg.set_value("meta", "scene", String(GameContext.LEVELS["stage03"]))
	cfg.set_value("story", "flags", ["stage01_done", "branch01_done", "stage02_done", "branch02_done"])
	cfg.save(path)
	var title: TitleScreen = await _open_title()
	var gauge := title.find_child("JourneyGauge", true, false) as TitleGauge
	ok(gauge != null, "旅程标尺存在")
	if gauge != null:
		eq(gauge.lit_count(), 4, "已通关四章 -> 四个刻度亮")
		eq(gauge.current_index(), 4, "当前章是第五个刻度")
	var chapter := title.find_child("JourneyChapter", true, false) as Label
	ok(chapter != null and chapter.text.contains(ChapterText.name_of("stage03")), "章节行写当前章名：%s" % (chapter.text if chapter != null else ""))
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


## 墓志是慢速打字机：开屏结束时第一句已经整句"在"了（不停在打字中途）；
## 之后每次轮换才逐字打出来。
func test_epitaph_first_line_is_complete_after_the_intro() -> void:
	var title: TitleScreen = await _open_title()
	eq(title.epitaph_line(), TitleScreen.EPITAPH, "第一句是 EPITAPH")
	var label := title.get_node("Inscription/EpitaphRow/Epitaph") as Label
	eq(label.text, TitleScreen.EPITAPH, "标签里就是这一句")
	title._skip_intro()
	# A8：跳/播完开屏 = 第一句整句可见 + 进入停留，不再从 0 打字。
	eq(label.visible_characters, -1, "开屏落位后第一句整句可见")
	eq(title._ep_phase, 2, "第一句进入停留阶段，不是打字中")
	# 停留够久 -> 淡出 -> 换下一句（下一句才从 0 开始逐字打）。
	title._update_epitaph(TitleScreen.EPITAPH_HOLD + 0.01)
	title._update_epitaph(TitleScreen.EPITAPH_FADE + 0.01)
	ok(title.epitaph_line() != TitleScreen.EPITAPH, "轮到下一句")
	eq(label.text, title.epitaph_line(), "标签跟着换句")
	eq(label.visible_characters, 0, "下一句从 0 开始")
	title._ep_t = 0.0
	title._update_epitaph(TitleScreen.EPITAPH_CHAR * 3.0 + 0.001)
	eq(label.visible_characters, 3, "后续轮换仍走打字机：打了三个字")
	title._update_epitaph(TitleScreen.EPITAPH_CHAR * 40.0)
	eq(label.visible_characters, -1, "整句打完")
	title.queue_free()
	await get_tree().process_frame


# ------------------------------------------------------------ 回看余烬 ----

const RECAP_SAVE := "user://title_recap_test.cfg"


## 把 SaveData 指到一个临时存档路径，并清空内存里的旗标 / 结局 / 已读档数据
## （标题冷启动时它们还没读档，但同一个测试进程里前面的用例可能留下内存态）。
func _begin_recap_env() -> Dictionary:
	var saved := {"path": SaveData.save_path, "flags": SaveData.flags.duplicate(),
			"ending": SaveData.ending, "data": SaveData.data.duplicate(true)}
	SaveData.save_path = RECAP_SAVE
	SaveData.flags = PackedStringArray()
	SaveData.ending = ""
	SaveData.data = {}
	if FileAccess.file_exists(RECAP_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RECAP_SAVE))
	if FileAccess.file_exists(RECAP_SAVE + ".bak"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RECAP_SAVE + ".bak"))
	return saved


func _end_recap_env(saved: Dictionary) -> void:
	if FileAccess.file_exists(RECAP_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RECAP_SAVE))
	if FileAccess.file_exists(RECAP_SAVE + ".bak"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RECAP_SAVE + ".bak"))
	SaveData.save_path = String(saved["path"])
	SaveData.flags = saved["flags"]
	SaveData.ending = String(saved["ending"])
	SaveData.data = saved.get("data", {})


func _write_recap_save(ending: String, flags: Array) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 3)
	cfg.set_value("meta", "scene", String(GameContext.LEVELS["stage04"]))
	if ending != "":
		cfg.set_value("meta", "ending", ending)
	cfg.set_value("player", "origin", "ember_vanguard")
	cfg.set_value("story", "flags", flags)
	cfg.save(RECAP_SAVE)


## 直接写一份存档（自定义场景路径 / 损坏内容用）。
func _write_raw_save(scene: String, ending: String = "", flags: Array = []) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 3)
	cfg.set_value("meta", "scene", scene)
	if ending != "":
		cfg.set_value("meta", "ending", ending)
	cfg.set_value("player", "origin", "ember_vanguard")
	cfg.set_value("story", "flags", flags)
	cfg.save(RECAP_SAVE)


## 有结局时菜单行写着「回看余烬」：选它必须打开总结页，而不是直接读档进关。
func test_continue_row_with_an_ending_opens_the_recap_page() -> void:
	var saved := _begin_recap_env()
	_write_recap_save("give", [StoryFlow.done_flag("stage01"), StoryFlow.done_flag("stage02")])
	var title: TitleScreen = await _open_title()
	title._skip_intro()
	var items := _items(title)
	ok(_continue_row(title)._text.contains("回 看 余 烬"), "有结局：这一行写「回看余烬」")
	eq(items[0], _continue_row(title), "有存档：「继续」排第一格")
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
	ok(recap.row_ids().has(&"chapter_stage01") and recap.row_ids().has(&"chapter_stage02"),
			"第一、二章能再入")
	ok(not recap.row_ids().has(&"chapter_stage03"), "没通关的章不列")
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
	_write_recap_save("", [StoryFlow.done_flag("stage01")])
	var title: TitleScreen = await _open_title()
	title._skip_intro()
	ok(not title._continue_opens_recap, "没结局：继续就是继续")
	ok(_continue_row(title)._text.contains("继 续 旅 程"), "行文案是继续旅程")
	eq((title.get_node("Menu") as MenuList).selected_id(), TitleScreen.ID_CONTINUE, "有存档：默认停在「继续」")
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
	eq(TitleScreen.chapter_entry_spawn("stage01"), Level01Static.DEFAULT_SPAWN, "首节点入口出生点对齐默认落点")
	for id in GameContext.LEVEL_ORDER:
		var spawn := TitleScreen.chapter_entry_spawn(id)
		ok(spawn != Vector2(176, 240), "%s 的落点不再是写死的 (176,240)" % id)
		if id != "level01":
			eq(spawn, ChapterLayout.entry_spawn_of(id), "%s：和出口门送人过来的是同一个点" % id)
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


## 默认接线：同一竞技场菜单进入3D场景，不启动旧大厅或2D世界视口。
func test_arena_entry_default_wiring_starts_a_real_run() -> void:
	var saved_world := GameContext.pending_world_path
	var title: TitleScreen = await _open_title()
	title._on_chosen(TitleScreen.ID_ARENA)
	await get_tree().process_frame
	ok(MobaRunScript.active(), "3D竞技场会话已经拉起")
	ok(not ArenaRun.active(), "旧2.5D会话不启动")
	eq(GameContext.pending_world_path, saved_world, "3D入口不改战役世界路径")
	eq(Director.last_fade_target, MobaRunScript.SCENE, "直接进入3D场景")
	MobaRunScript.abandon()
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


## T2: 锁定说明贴在试炼题字右侧、同一行内，不与其他菜单行相交，也不越过画面中线。
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
		var trial: MenuItem = items[2]
		var trial_rect := title.design_rect(trial)
		ok(tag_rect.position.y >= trial_rect.position.y - 1.0, "锁定说明与试炼行同一行")
		ok(tag_rect.end.y <= trial_rect.end.y + 1.0, "锁定说明不落到下一行")
		ok(tag_rect.position.x > trial_rect.position.x + 80.0, "锁定说明在题字右侧")
		ok(tag_rect.end.x < 640.0, "锁定说明停在画面中线左侧 (%.0f)" % tag_rect.end.x)
		for item in items:
			if item.id == &"trial":
				continue
			var item_rect: Rect2 = title.design_rect(item)
			ok(not tag_rect.intersects(item_rect),
					"LockTag 不与菜单行 %s 重叠 (tag=%s, row=%s)" % [item.id, tag_rect, item_rect])
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


## T5 + B2: 页脚渐变暗斑（截止在熔河上方）与完整署名（全员 + 字体，≥4.5:1 暖灰）。
## 旧版为了 35 字上限删掉了作者/字体名；现在完整列出，并用字宽证明最后一位没被省略号吃掉。
func test_footer_shade_and_complete_credits() -> void:
	var original_scale := Settings.assist(&"text_scale")
	Settings.set_value(&"text_scale", 1.0, false)
	var title: TitleScreen = await _open_title()
	title._skip_intro()
	var shade := title.find_child("FooterShade", true, false) as Control
	ok(shade != null, "FooterShade 节点存在")
	if shade != null:
		ok(shade.position.y <= 660.0, "暗渐变顶端截止在熔河上方 (y=%.0f <= 660)" % shade.position.y)
		ok(shade.position.y + shade.size.y >= 716.0, "暗渐变覆盖整个页脚高度")
		ok(shade.mouse_filter == Control.MOUSE_FILTER_IGNORE, "FooterShade 忽略鼠标事件")
	var credits := title.find_child("Credits", true, false) as Label
	ok(credits != null, "致谢文本存在")
	var hint := title.find_child("FooterHint", true, false) as Label
	ok(hint != null, "导航提示存在")
	if credits != null:
		eq(credits.text, TitleScreen.CREDITS, "页脚列的是完整署名")
		for name in ["ansimuz", "aamatniekss", "Kronovi", "CodeManu", "Kenney", "Jacquard 24"]:
			ok(credits.text.contains(name), "署名包含 %s" % name)
		ok(credits.text.contains("Jacquard 24"), "最后一位署名 Jacquard 24 在文案里")
		eq(credits.get_theme_color("font_color"), TitleScreen.CREDITS_INK,
				"署名叫暖灰，不是压暗的灰（对比度 ≥4.5:1）")
		var credits_rect := title.design_rect(credits)
		# 没有被省略号截断：整串字形宽度放得进标签（最后一位 Jacquard 24 的右缘也在标签内）。
		var font := credits.get_theme_font(&"font")
		var font_size := credits.get_theme_font_size(&"font_size")
		var glyph_w := 0.0
		if font != null:
			glyph_w = font.get_string_size(credits.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		ok(glyph_w <= credits_rect.size.x + 0.5,
				"整串字形宽 %.0f 放得进署名条 %.0f：最后一位没被省略" % [glyph_w, credits_rect.size.x])
		# 设计空间里：署名右端 < 页脚提示左端（band 坐标 736，绝对坐标 72+736=808）。
		var hint_rect := title.design_rect(hint)
		ok(credits_rect.end.x < hint_rect.position.x + 0.5,
				"署名右端 %.0f 停在导航提示左端 %.0f 之前" % [credits_rect.end.x, hint_rect.position.x])
		ok(credits_rect.end.x < TitleScreen.FOOTER_RECT.position.x + 736.0 + 0.5, "署名右端 < 736（band 坐标）")
	Settings.set_value(&"text_scale", original_scale, false)
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


# ------------------------------------------------------- continue row (A1/A3) ----

## 「继续旅程」行的行内注与页脚说明：无档 / 有档 / 有结局 / 章节认不出，四种都说真话。
## 行内注是 10px、不撑高 52px 行；无档时禁用行再压暗一档（描边保留）。
func test_continue_row_note_and_hint_are_honest() -> void:
	var saved := _begin_recap_env()
	# 1) 冷启动：没有存档
	var title: TitleScreen = await _open_title()
	title._skip_intro()
	var item := _continue_row(title)
	ok(not item.visible, "无档：「继续」行不占位")
	eq(TitleScreen.continue_note(title.look()), "尚无存档", "无档：行内注写「尚无存档」")
	eq(TitleScreen.continue_hint(title.look()), "继续旅程 · 尚无存档，先点燃余烬", "无档：页脚说先点燃余烬")
	ok(item.disabled, "无档：「继续旅程」置灰")
	ok(item._note != null and item._note.visible, "行内注可见")
	eq(item._note.text, "尚无存档", "行内注就是这句")
	eq(item._note.get_theme_font_size("font_size"), 10, "行内注 10px 小字")
	almost(title.design_rect(item).size.y, MenuItem.HEIGHT, 0.5, "小注不撑高行：仍是 52px")
	ok(item._label.get_theme_color("font_color").a <= 0.6,
			"无档时禁用行再压暗一档 (alpha %.2f <= 0.6)" % item._label.get_theme_color("font_color").a)
	ok(item._label.get_theme_constant("outline_size") >= 1, "描边保留，压暗仍可读")
	ok(not (title._recap_button as Control).visible, "无档：旅程列的「回看余烬」不出现")
	title.queue_free()
	await get_tree().process_frame

	# 2) 有档无结局：章节 + 进度
	_write_recap_save("", [StoryFlow.done_flag("stage01"), StoryFlow.done_flag("stage02")])
	title = await _open_title()
	title._skip_intro()
	item = _continue_row(title)
	var look := title.look()
	eq(String(look.get("chapter_id", "")), "stage04", "存档停在第四幕（stage04）")
	var expected_note := "%s章 · %02d/%02d" % [ChapterText.number_of("stage04"),
			int(look.get("cleared", 1)), ChapterText.order().size()]
	eq(TitleScreen.continue_note(look), expected_note, "有档：行内注写章节 + 进度")
	eq(item._note.text, expected_note, "行内注同步到菜单行")
	eq(TitleScreen.continue_hint(look), "继续旅程 · %s · %02d/%02d" % [ChapterText.name_of("stage04"),
			int(look.get("cleared", 1)), ChapterText.order().size()], "有档：页脚写章节 + 进度")
	ok(not item.disabled, "有档：继续可点")
	ok((title._recap_button as Control).visible, "有档无结局：旅程列的「回看余烬」是唯一回看入口")
	title.queue_free()
	await get_tree().process_frame

	# 3) 有结局：结局名 + 回看说明；旅程列按钮收起（菜单行就是一步入口）
	_write_recap_save("give", [StoryFlow.done_flag("stage01")])
	title = await _open_title()
	title._skip_intro()
	item = _continue_row(title)
	look = title.look()
	eq(TitleScreen.continue_note(look), "结局 · 还火", "有结局：行内注写结局名")
	eq(TitleScreen.continue_hint(look), TitleScreen.RECAP_HINT, "有结局：页脚是回看说明")
	ok(item._text.contains("回 看 余 烬"), "有结局：行文案是回看余烬")
	ok(not (title._recap_button as Control).visible, "有结局：旅程列表按钮不再重复出现")
	title.queue_free()
	await get_tree().process_frame

	# 4) 有档但章节认不出：继续上次旅程
	_write_raw_save("res://scenes/levels/RemovedLevel.tscn")
	title = await _open_title()
	title._skip_intro()
	look = title.look()
	eq(String(look.get("chapter_id", "")), "", "认不出的场景没有章节 id")
	eq(TitleScreen.continue_note(look), "继续上次旅程", "认不出章节：行内注不猜")
	eq(TitleScreen.continue_hint(look), TitleScreen.MENU_HINTS[TitleScreen.ID_CONTINUE],
			"认不出章节：页脚退回旧说明")
	title.queue_free()
	await get_tree().process_frame
	_end_recap_env(saved)


## A3：继续读档失败（损坏存档）—— 不开始、不淡出、不删文件；菜单保留，页脚说清楚。
func test_continue_load_failure_keeps_the_menu_and_the_file() -> void:
	var saved := _begin_recap_env()
	if FileAccess.file_exists(RECAP_SAVE + ".bak"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RECAP_SAVE + ".bak"))
	var file := FileAccess.open(RECAP_SAVE, FileAccess.WRITE)
	file.store_string("this is not a config file\n[[[ broken ]]]\n")
	file.close()
	ok(SaveData.has_save(), "损坏的存档文件仍然被检测到（has_save）")
	var title: TitleScreen = await _open_title()
	title._skip_intro()
	var menu := title.get_node("Menu") as MenuList
	title._on_chosen(TitleScreen.ID_CONTINUE)
	await get_tree().process_frame
	ok(not title._started, "读档失败：没有开始游戏（_started 仍 false）")
	ok(menu.active, "读档失败：菜单保留可操作")
	ok(not title.character_select_screen().is_open(), "读档失败：没有误开角色选择")
	eq(title.footer_hint_text(), TitleScreen.LOAD_FAILED_HINT,
			"读档失败：页脚说「存档读不出来 · 已保留原文件，可点燃余烬」")
	ok(FileAccess.file_exists(RECAP_SAVE), "读档失败：原存档文件没有被删除")
	ok(not title.is_quitting(), "读档失败：没有进入退场")
	title.queue_free()
	await get_tree().process_frame
	_end_recap_env(saved)


# ------------------------------------------------------ quit guard (A4) --------

## 退场跳过：只认"按下"；宽限期内的按下/松开都不跳；宽限期后按下立即收尾。
func test_quit_ignores_release_and_grants_a_grace_window() -> void:
	var title: TitleScreen = await _open_title()
	title.quit_on_finish = false
	title._skip_intro()
	title._on_chosen(TitleScreen.ID_QUIT)
	await get_tree().process_frame
	ok(title.is_quitting(), "进入退场")
	var key_up := InputEventKey.new()
	key_up.keycode = KEY_ENTER
	key_up.pressed = false
	var key_down := InputEventKey.new()
	key_down.keycode = KEY_ENTER
	key_down.pressed = true
	# 选中「离开锈墓」的那次按下，以及它的 release：都不该跳过退场。
	title._unhandled_input(key_up)
	ok(not title.quit_finished(), "release 不能跳过退场（旧 bug）")
	title._unhandled_input(key_down)
	ok(not title.quit_finished(), "宽限期内的按下也不跳（不是拒绝服务）")
	# 宽限期过后：新的按下立即收尾。
	title._time += title.quit_skip_grace + 0.01
	var later := InputEventKey.new()
	later.keycode = KEY_SPACE
	later.pressed = true
	title._unhandled_input(later)
	ok(title.quit_finished(), "宽限期过后的按下立即收尾")
	title.queue_free()
	await get_tree().process_frame

	# 宽限为 0 时：release 仍然永远不跳过（只认按下），按下立即收尾。
	title = await _open_title()
	title.quit_on_finish = false
	title._skip_intro()
	title.quit_skip_grace = 0.0
	title._on_chosen(TitleScreen.ID_QUIT)
	await get_tree().process_frame
	title._unhandled_input(key_up)
	ok(not title.quit_finished(), "宽限为 0 时 release 也不跳")
	title._unhandled_input(key_down)
	ok(title.quit_finished(), "宽限为 0 时按下立即收尾")
	title.queue_free()
	await get_tree().process_frame


# ------------------------------------------------- modal arbitration (A5) -----

## 模态仲裁：总结页开着时其它弹窗/档案/确认不能叠上来；打开时释放 GUI 焦点，
## 旅程列两个辅助按钮暂时不收焦点，关闭后恢复。
func test_modals_arbitrate_and_restore_aux_focus() -> void:
	var saved := _begin_recap_env()
	var title: TitleScreen = await _open_title()
	title._skip_intro()
	var recap_button := title.find_child("RecapButton", true, false) as Button
	var notice := title.find_child("UpdateNotice", true, false) as Button
	ok(recap_button != null and notice != null, "回看按钮与更新按钮都在")
	eq(recap_button.focus_mode, Control.FOCUS_ALL, "平时回看按钮收焦点")
	eq(notice.focus_mode, Control.FOCUS_ALL, "平时更新按钮收焦点")
	# 先把焦点放到回看按钮上，验证打开模态会释放它。
	recap_button.grab_focus()
	await get_tree().process_frame
	var had_focus := title.get_viewport().gui_get_focus_owner() == recap_button
	title.open_recap()
	ok(title.recap_open(), "总结页打开")
	eq(title._recap_button.focus_mode, Control.FOCUS_NONE, "总结页开着：回看按钮不收焦点")
	eq(notice.focus_mode, Control.FOCUS_NONE, "总结页开着：更新按钮不收焦点")
	if had_focus:
		eq(title.get_viewport().gui_get_focus_owner(), null, "打开模态时释放了 GUI 焦点")
	# 叠窗仲裁：确认信 / 更新提示 / 档案都不许叠在总结页上。
	title.open_confirm()
	ok(not title.confirm_open(), "总结页开着时覆盖确认不叠上来")
	title._open_update_prompt()
	ok(not title._update_prompt.is_open(), "总结页开着时更新提示不打开")
	title._toggle_dossier_pinned()
	ok(not title.dossier_open(), "总结页开着时点按/手柄不展开档案")
	title.recap_page().close()
	await get_tree().process_frame
	ok(not title.recap_open(), "总结页关闭")
	eq(title._recap_button.focus_mode, Control.FOCUS_ALL, "关闭后回看按钮恢复焦点")
	eq(notice.focus_mode, Control.FOCUS_ALL, "关闭后更新按钮恢复焦点")
	# 确认信同样仲裁并恢复。
	title.open_confirm()
	ok(title.confirm_open(), "确认信打开")
	eq(title._recap_button.focus_mode, Control.FOCUS_NONE, "确认信开着：回看按钮不收焦点")
	title.close_confirm()
	await get_tree().process_frame
	ok(not title.confirm_open(), "确认信关闭")
	eq(title._recap_button.focus_mode, Control.FOCUS_ALL, "确认信关闭后回看按钮恢复焦点")
	eq(notice.focus_mode, Control.FOCUS_ALL, "确认信关闭后更新按钮恢复焦点")
	title.queue_free()
	await get_tree().process_frame
	_end_recap_env(saved)


## A5：总结页 / 确认信关闭后，页脚说明回到当前焦点行（而不是停在被弹窗打断的那句）。
func test_footer_hint_returns_after_closing_a_modal() -> void:
	var saved := _begin_recap_env()
	var title: TitleScreen = await _open_title()
	title._skip_intro()
	var menu := title.get_node("Menu") as MenuList
	menu.select(3, false)   # 余烬竞技场
	await get_tree().process_frame
	var expected := title.footer_hint_text()
	eq(expected, TitleScreen.MENU_HINTS[TitleScreen.ID_ARENA], "焦点行是竞技场说明")
	title.open_recap()
	await get_tree().process_frame
	title._on_recap_attention(true)
	eq(title.footer_hint_text(), TitleScreen.RECAP_HINT, "回看悬停会临时改写页脚")
	title.recap_page().close()
	await get_tree().process_frame
	eq(title.footer_hint_text(), expected, "关掉总结页后页脚回到当前焦点行")
	title.open_confirm()
	await get_tree().process_frame
	title._set_footer_hint("被打断的说明")
	eq(title.footer_hint_text(), "被打断的说明")
	title.close_confirm()
	await get_tree().process_frame
	eq(title.footer_hint_text(), expected, "关掉确认信后页脚回到当前焦点行")
	title.queue_free()
	await get_tree().process_frame
	_end_recap_env(saved)


# ------------------------------------------------- journey shade (B1/A2) ------

## 旅程短注垫了一块静态径向暗斑（比注大一圈）；短注 96 高、回看条 30/14px，
## 基础小字 13px；高亮只推墨层 alpha，暗斑不跟着呼吸。
func test_journey_shade_tokens_and_static_layer() -> void:
	var title: TitleScreen = await _open_title()
	title._skip_intro()
	var shade := title.find_child("JourneyShade", true, false) as Control
	ok(shade != null, "JourneyShade 存在")
	var ink := title.find_child("JourneyInk", true, false) as CanvasItem
	ok(ink != null, "JourneyInk 存在")
	if shade != null and ink != null:
		var rect := title.design_rect(shade)
		almost(rect.position.x, TitleScreen.JOURNEY_X - 14.0, 0.5, "暗斑左缘外扩 14")
		almost(rect.position.y, TitleScreen.JOURNEY_Y - 12.0, 0.5, "暗斑上缘外扩 12")
		almost(rect.size.x, TitleScreen.JOURNEY_W + 28.0, 0.5, "暗斑宽 +28")
		almost(rect.size.y, TitleScreen.JOURNEY_H + 24.0, 0.5, "暗斑高 +24")
		eq(shade.mouse_filter, Control.MOUSE_FILTER_IGNORE, "暗斑不吃鼠标")
		almost(TitleScreen.JOURNEY_H, 396.0, 0.01, "右列与菜单同顶、同块高度 396")
		almost(TitleScreen.JOURNEY_DIM, 0.62, 0.001, "暗态 0.62")
		almost(TitleScreen.JOURNEY_LIT, 1.0, 0.001, "亮态 1.0")
		almost(TitleScreen.RecapStrip.HEIGHT, 30.0, 0.01, "回看条高 30")
		eq(TitleScreen.RecapStrip.FONT_SIZE, 14, "回看条 14px")
		var chapter := title.find_child("JourneyChapter", true, false) as Label
		eq(chapter.get_theme_font_size("font_size"), 13, "短注基础小字 13px")
		var shade_alpha := shade.modulate.a
		(title.get_node("Menu") as MenuList).select(1, false)
		await get_tree().process_frame
		ok(ink.modulate.a > TitleScreen.JOURNEY_DIM, "焦点在「继续」时短注点亮")
		almost(shade.modulate.a, shade_alpha, 0.0001, "暗斑是静态的，不跟高亮呼吸")
	title.queue_free()
	await get_tree().process_frame


# ------------------------------------------------- confirm letter (B3) --------

## 确认信：羊皮纸上的 kicker/正文/提示/返回用深墨、标题深锈；蜡封按钮 48px 正对火漆，
## 上方有 12px 墨色"按住火漆 · 确认覆盖"；确认覆盖行压暗、取消仍是默认主行动。
func test_confirm_letter_ink_and_seal_inset() -> void:
	var saved := _begin_recap_env()
	var title: TitleScreen = await _open_title()
	title._skip_intro()
	title.open_confirm()
	await get_tree().process_frame
	ok(title.confirm_open(), "确认信打开")
	var root := title._confirm_shell["root"] as Control
	ok(root != null, "确认信根节点存在")
	for node_name in ["Kicker", "Hint", "Back", "ConfirmBody"]:
		var label := root.find_child(node_name, true, false) as Label
		ok(label != null, "%s 存在" % node_name)
		if label != null:
			eq(label.get_theme_color("font_color"), TitleScreen.LETTER_INK, "%s 用深墨" % node_name)
	var title_label := root.find_child("Title", true, false) as Label
	ok(title_label != null, "标题存在")
	if title_label != null:
		eq(title_label.get_theme_color("font_color"), TitleScreen.LETTER_RUST, "标题保持深锈")
	var seal_button := root.find_child("SealButton", true, false) as Button
	ok(seal_button != null, "蜡封按钮存在")
	var hint := root.find_child("SealHint", true, false) as Label
	ok(hint != null, "蜡封上方有可见操作说明")
	if seal_button != null and hint != null:
		almost(seal_button.size.x, 48.0, 0.5, "蜡封按钮 48px")
		almost(seal_button.size.y, 48.0, 0.5, "蜡封按钮 48px 高")
		eq(hint.text, TitleScreen.SEAL_HOLD_LABEL, "说明文案是「按住火漆 · 确认覆盖」")
		eq(hint.get_theme_font_size("font_size"), 12, "说明 12px")
		eq(hint.get_theme_color("font_color"), TitleScreen.LETTER_INK, "说明用深墨")
		ok(hint.position.y + hint.size.y <= seal_button.position.y,
				"说明在蜡封按钮上方 (%.0f <= %.0f)" % [hint.position.y + hint.size.y, seal_button.position.y])
		var dressing := title._confirm_shell["dressing"] as Node2D
		ok(dressing != null, "信笺蜡封绘制层存在")
		if dressing != null:
			var center: Vector2 = dressing.call("seal_center")
			almost(seal_button.position.x + seal_button.size.x * 0.5, center.x, 1.0, "按钮中心对齐蜡封中心 x")
			almost(seal_button.position.y + seal_button.size.y * 0.5, center.y, 1.0, "按钮中心对齐蜡封中心 y")
	ok(title._confirm_overwrite_item != null, "确认覆盖行存在")
	if title._confirm_overwrite_item != null:
		ok(title._confirm_overwrite_item.tint.r <= 0.87,
				"确认覆盖行压暗（tint %.2f <= 0.87）" % title._confirm_overwrite_item.tint.r)
	var keep_item := title._confirm_menu.items()[0] as MenuItem
	ok(keep_item.selected, "取消仍是默认选中项（安全出口）")
	ok(not (title._confirm_overwrite_item as MenuItem).selected, "默认不选中确认覆盖")
	title.close_confirm()
	await get_tree().process_frame
	title.queue_free()
	await get_tree().process_frame
	_end_recap_env(saved)


## B3：火漆按住 0.45s 才确认；按住中途松手取消（不开角色选择）；按满了才进选人。
func test_seal_hold_cancels_early_and_completes() -> void:
	var saved := _begin_recap_env()
	var title: TitleScreen = await _open_title()
	title._skip_intro()
	title.open_confirm()
	await get_tree().process_frame
	var char_select := title.character_select_screen()
	ok(title.confirm_open() and not char_select.is_open(), "确认信开着，角色选择还没开")
	# 短按：按下 -> 进到一半 -> 松开。不开选人，信笺仍开着。
	title._confirm_seal_button.button_down.emit()
	title._update_seal_hold(0.2)
	var mid := title.seal_hold_progress()
	ok(mid > 0.0 and mid < 1.0, "按住中段有进度 (%.2f)" % mid)
	title._confirm_seal_button.button_up.emit()
	ok(not char_select.is_open(), "没按满松手：不打开角色选择")
	ok(title.confirm_open(), "没按满松手：信笺仍然开着")
	almost(title.seal_hold_progress(), 0.0, 0.01, "松手清空按住进度")
	# 长按：按住满 0.45s -> 真的确认。
	title._begin_seal_hold()
	title._update_seal_hold(TitleScreen.SEAL_HOLD_TIME + 0.02)
	await get_tree().process_frame
	ok(not title.confirm_open(), "按满后确认信收起")
	ok(char_select.is_open(), "按满后进入角色选择")
	title.queue_free()
	await get_tree().process_frame
	_end_recap_env(saved)


# ------------------------------------------------- text scale layout (C2) -----

## 85/100/135% 三档字号：字标/副题/菜单/旅程/墓志/页脚互不重叠且都在内容矩形内；
## 135% 档案卡内容最小高不超过卡身；副题行高、墓志底边也跟着重排。
func test_title_blocks_do_not_overlap_at_three_text_scales() -> void:
	var original_scale := Settings.assist(&"text_scale")
	var title: TitleScreen = await _open_title()
	title._skip_intro()
	var notice := title.find_child("UpdateNotice", true, false) as Control
	if notice != null:
		notice.visible = true
	var blocks := ["Masthead", "Subtitle", "Menu", "JourneyColumn", "Epitaph", "CreditBand"]
	var content := Rect2(Vector2.ZERO, PresentationMetrics.UI_SIZE)
	var masthead_column := title.find_child("MastheadColumn", true, false) as Control
	for text_scale in [0.85, 1.0, 1.35]:
		Settings.set_value(&"text_scale", text_scale, false)
		await flush(3)
		var rects := {}
		for block in blocks:
			var node := title.find_child(block, true, false) as Control
			ok(node != null, "区块 %s 存在 @%.2f" % [block, text_scale])
			if node == null:
				continue
			var rect := title.design_rect(node)
			rects[block] = rect
			ok(content.grow(0.6).encloses(rect),
					"%s 落在内容矩形内 @%.2f：%s" % [block, text_scale, rect])
		var names := rects.keys()
		for i in names.size():
			for j in range(i + 1, names.size()):
				var ra: Rect2 = rects[names[i]]
				var rb: Rect2 = rects[names[j]]
				ok(not ra.grow(-0.6).intersects(rb.grow(-0.6)),
						"%s 与 %s 不重叠 @%.2f" % [names[i], names[j], text_scale])
		# 字标列底边跟着副题行高，但停在菜单顶（RAIL_TOP）上方。
		if masthead_column != null:
			var col := title.design_rect(masthead_column)
			ok(col.end.y <= TitleScreen.RAIL_TOP, "字标列底不压菜单顶 @%.2f (%.0f)" % [text_scale, col.end.y])
		# 墓志：字号封顶 30、底边停在 656。
		var epitaph := title.find_child("Epitaph", true, false) as Control
		ok(epitaph.get_theme_font_size("font_size") <= 30, "墓志字号封顶 30 @%.2f" % text_scale)
		almost(title.design_rect(epitaph).end.y, 656.0, 1.0, "墓志底边停在 656 @%.2f" % text_scale)
		# 档案卡：135% 收紧行距、底注封顶，内容最小高不超过卡身。
		var dossier := title.find_child("Dossier", true, false) as Control
		var contents := title._dossier_contents as Control
		if contents != null and dossier != null:
			var sep: int = contents.get_theme_constant("separation")
			# 印记行加入后 135% 收到 6（v3.1）：内容最小高才停得进 440 的卡身。
			eq(sep, 6 if text_scale >= 1.3 else 12, "档案卡行距 @%.2f" % text_scale)
			var min_h: float = contents.get_combined_minimum_size().y
			var body_h := TitleScreen.CARD_RECT.size.y - 44.0
			print("DOSSIER-DEBUG scale=%.2f min=%.1f body=%.1f size=%.1f sep=%d" % [text_scale, min_h, body_h, dossier.size.y, sep])
			ok(min_h <= body_h + 0.5,
					"%.2f 档案内容最小高 %.0f <= 卡身 %.0f" % [text_scale, min_h, body_h])
			ok(dossier.size.y <= body_h + 0.5, "%.2f 档案卡身没被内容撑大 (%.0f)" % [text_scale, dossier.size.y])
	Settings.set_value(&"text_scale", original_scale, false)
	title.queue_free()
	await get_tree().process_frame


# --------------------------------------------- dossier input parity (C3) ------

## 档案三路径：点按旅程短注（触屏）/ 手柄 Y / Tab 都能开合；点按区不盖「回看余烬」，
## 不抢键盘焦点；页脚默认提示写明 Tab/Y。
func test_dossier_input_parity_gamepad_and_touch() -> void:
	var title: TitleScreen = await _open_title()
	title._skip_intro()
	ok(not title.dossier_open(), "默认收起")
	var tap := title.find_child("JourneyButton", true, false) as Button
	ok(tap != null, "旅程短注有点按区")
	if tap != null:
		eq(tap.mouse_filter, Control.MOUSE_FILTER_STOP, "点按区收鼠标/触屏")
		eq(tap.focus_mode, Control.FOCUS_NONE, "点按区不抢 Tab / 键盘焦点")
		var recap := title.find_child("RecapButton", true, false) as Control
		if recap != null:
			ok(tap.position.y + tap.size.y <= recap.position.y + 0.5,
					"点按区不盖「回看余烬」按钮")
		tap.pressed.emit()
		await get_tree().process_frame
		ok(title.dossier_open(), "点按旅程短注展开档案（触屏路径）")
		tap.pressed.emit()
		await get_tree().process_frame
		ok(not title.dossier_open(), "再点一下收起")
	# 手柄 Y
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_Y
	pad.pressed = true
	(title.get_node("Menu") as MenuList).active = true
	title._unhandled_input(pad)
	await get_tree().process_frame
	ok(title.dossier_open(), "手柄 Y 展开档案")
	title._unhandled_input(pad)
	await get_tree().process_frame
	ok(not title.dossier_open(), "再按 Y 收起")
	# Tab 仍是键盘路径
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	title._unhandled_input(tab)
	await get_tree().process_frame
	ok(title.dossier_open(), "Tab 仍然展开档案")
	title._dossier_pinned = false
	title._set_dossier_open(false)
	eq(TitleScreen.FOOTER_DEFAULT, "↑↓ 选择 · Enter 确认 · Tab/Y 档案", "页脚默认提示写明 Tab/Y")
	title.queue_free()
	await get_tree().process_frame


# ------------------------------------------------- menu cursor / lamp (A7) ----

## A7：可点的菜单行是手形光标、禁用行是箭头（在 _refresh 里同步）；
## 选中行下划线是这一行字的真实宽度（不再是写死的 148px 上限）。
func test_menu_rows_use_hand_cursor_and_lamp_underline() -> void:
	var title: TitleScreen = await _open_title()
	title._skip_intro()
	var items := _items(title)
	for i in items.size():
		var expected := Control.CURSOR_ARROW if items[i].disabled else Control.CURSOR_POINTING_HAND
		eq(items[i].mouse_default_cursor_shape, expected, "第 %d 行光标形状（禁用=%s）" % [i, items[i].disabled])
	# 禁用行改状态后光标跟着变（_refresh 同步，不是构造时定死）。
	var continue_item := items[1] as MenuItem
	ok(continue_item.disabled, "无档时继续行是禁用的")
	continue_item.disabled = false
	eq(continue_item.mouse_default_cursor_shape, Control.CURSOR_POINTING_HAND, "解禁后变手形")
	continue_item.disabled = true
	eq(continue_item.mouse_default_cursor_shape, Control.CURSOR_ARROW, "再禁用变回箭头")
	# 下划线 = 字的实际宽度：挑最长的一行（竞技场），旧上限 148 会截短它。
	var menu := title.get_node("Menu") as MenuList
	menu.select(3, false)
	await get_tree().process_frame
	var arena := items[3] as MenuItem
	var font := arena._label.get_theme_font(&"font")
	var font_size := arena._label.get_theme_font_size(&"font_size")
	var text_w := 0.0
	if font != null:
		text_w = font.get_string_size(arena._label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	ok(text_w > 148.0, "竞技场行的字比旧上限 148px 长 (%.0f)" % text_w)
	almost(arena.underline_span(), text_w, 1.0, "选中下划线等于整行字的宽度")
	title.queue_free()
	await get_tree().process_frame


## A6：版本提示按钮右对齐页脚右缘（x = 1208 - 宽），高 22，不压导航提示。
func test_update_notice_is_right_aligned_in_the_footer() -> void:
	var title: TitleScreen = await _open_title()
	title._skip_intro()
	var notice := title.find_child("UpdateNotice", true, false) as Control
	ok(notice != null, "版本提示按钮存在")
	var hint := title.find_child("FooterHint", true, false) as Control
	if notice != null:
		notice.visible = true
		var rect := title.design_rect(notice)
		almost(rect.size.y, 22.0, 0.5, "版本提示高 22")
		almost(rect.end.x, TitleScreen.FOOTER_RECT.end.x, 0.5, "右对齐页脚右缘 1208")
		almost(rect.position.y, 661.0, 0.5, "停在页脚带上方")
		if hint != null:
			ok(rect.position.x > title.design_rect(hint).position.x,
					"不压导航提示（提示从 %.0f 起）" % title.design_rect(hint).position.x)
	title.queue_free()
	await get_tree().process_frame
