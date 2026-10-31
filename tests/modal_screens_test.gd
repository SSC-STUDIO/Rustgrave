extends TestCase
## 弹窗外壳回归：设置 / 操作说明 / 教程回看 / 地图 / 暂停菜单都必须是
## "居中卡片 + 可见压暗背景"，而不是整屏一张紫板；标签页吃的是同一套异形板样式。

const SettingsScreenScript := preload("res://scripts/ui/settings_screen.gd")
const PauseMenuScript := preload("res://scripts/ui/pause_menu.gd")
const ControlsPanelScript := preload("res://scripts/ui/controls_panel.gd")
const TutorialRecallScript := preload("res://scripts/ui/tutorial_recall.gd")
const MapScreenScript := preload("res://scripts/ui/map_screen.gd")
const JournalScript := preload("res://scripts/ui/journal_screen.gd")
const Plate := preload("res://scripts/ui/menu_plate.gd")

## 卡片必须比设计分辨率小一圈，四周才留得出底下那层（标题屏 keyart / 暂停菜单）。
const DESIGN := Vector2(1280.0, 720.0)


func teardown() -> void:
	# 暂停相关用例会真的暂停 SceneTree；失败中断时也要把树恢复，后面的用例才能跑。
	Director.choice_hold = false
	Director.resume()
	if get_tree().paused:
		get_tree().paused = false


func _instances(pause: PauseMenu) -> Dictionary:
	var counts := {"settings": 0, "tutorial": 0, "map": 0, "controls": 0, "journal": 0}
	for child in pause.get_children():
		if child is SettingsScreen:
			counts["settings"] += 1
		elif child is TutorialRecall:
			counts["tutorial"] += 1
		elif child is MapScreen:
			counts["map"] += 1
		elif child is ControlsPanel:
			counts["controls"] += 1
		elif child.get_script() == JournalScript:
			counts["journal"] += 1
	return counts


## 每个子界面只有一份实例：反复开合不能每次新建一个盖上去（旧弹窗会留在树上）。
func _assert_one_of_each(pause: PauseMenu, label: String) -> void:
	var counts := _instances(pause)
	for key in counts:
		eq(int(counts[key]), 1, "%s: exactly one %s screen instance" % [label, key])


func _card_of(screen: Node) -> Control:
	return screen.get_node_or_null("ModalRoot/Card") as Control


func _veil_of(screen: Node) -> ColorRect:
	return screen.get_node_or_null("ModalRoot/Veil") as ColorRect


func _assert_modal(screen: Node, label: String) -> void:
	var card := _card_of(screen)
	ok(card != null, "%s 有弹窗卡片" % label)
	var veil := _veil_of(screen)
	ok(veil != null, "%s 有背景纱幕" % label)
	if card != null:
		ok(card.custom_minimum_size.x <= DESIGN.x and card.custom_minimum_size.y <= DESIGN.y,
				"%s 卡片装得进设计分辨率" % label)
		ok(card.custom_minimum_size.x < DESIGN.x - 100.0, "%s 卡片两侧留出底下那层" % label)
	if veil != null:
		ok(veil.color.a < 0.8, "%s 背景只是压暗、不铺黑（a=%.2f）" % [label, veil.color.a])
	ok(screen.get_node_or_null("ModalRoot/ModalEmbers") != null, "%s 卡片后面有余烬" % label)


func test_settings_is_a_modal_card_with_plate_tabs() -> void:
	var screen = SettingsScreenScript.new()
	add_child(screen)
	await get_tree().process_frame
	_assert_modal(screen, "设置界面")

	var tab := screen.get_node_or_null("ModalRoot/Card/Content/Body/Column/Tabs/Tab0") as Button
	ok(tab != null, "设置界面有标签页")
	if tab != null:
		eq(tab.theme_type_variation, &"TabButton", "标签页用统一主题变体")
		var sb := tab.get_theme_stylebox("normal")
		ok(sb is StyleBoxTexture, "标签页底是布料书签样式盒")
		if sb is StyleBoxTexture:
			eq((sb as StyleBoxTexture).texture.get_size(),
					Vector2(156.0, 52.0), "标签页底就是书签布条")

	screen.queue_free()
	await get_tree().process_frame


func test_pause_menu_is_a_modal_card_with_rail_and_dossier() -> void:
	var pause = PauseMenuScript.new()
	add_child(pause)
	await get_tree().process_frame
	_assert_modal(pause, "暂停菜单")

	var items: Array[MenuItem] = []
	for child in pause.menu().get_children():
		if child is MenuItem:
			items.append(child)
	eq(items.size(), 7, "暂停菜单七格（回到锈墓 / 设置 / 地图 / 故事 / 教程回看 / 操作说明 / 返回标题）")
	if items.size() == 7:
		eq(items[0].kind, MenuItem.Kind.PRIMARY, "第一格是主行动")
		eq(items[6].kind, MenuItem.Kind.GHOST, "最后一格是第三层")
		var ids := pause.menu().item_ids()
		ok(ids.has(PauseMenu.ID_STORY), "有「故事」一格")
		ok(ids.find(PauseMenu.ID_STORY) > ids.find(PauseMenu.ID_MAP), "故事紧跟在地图后面")
		ok(ids.find(PauseMenu.ID_STORY) < ids.find(PauseMenu.ID_TITLE), "故事排在返回标题之前")
	ok(pause.dossier_label("chapter") != null, "右列有行程档案")
	ok(pause.dossier_label("objective") != null, "档案里有当前目标行")
	ok(pause.get_node_or_null("ModalRoot/Card/Content/Body/PauseLayout/Rail/PauseLampCursor") != null, "暂停导轨带吊灯光标")
	var dossier := pause.get_node_or_null("ModalRoot/Card/Content/Body/PauseLayout/DossierColumn/Dossier") as PanelContainer
	ok(dossier != null, "档案底舱存在")
	if dossier != null:
		ok(dossier.get_theme_stylebox("panel") is StyleBoxTexture, "行程档案为行程签样式")

	pause.queue_free()
	await get_tree().process_frame


func test_controls_tutorial_and_map_share_the_shell() -> void:
	var controls = ControlsPanelScript.new()
	add_child(controls)
	await get_tree().process_frame
	_assert_modal(controls, "操作说明")
	eq(ControlsPanel.GROUPS.size(), 4, "操作说明分成四段")
	ok(controls.key_text(0) != "", "键位列能取到当前绑定")
	controls.queue_free()
	await get_tree().process_frame

	var tutorial = TutorialRecallScript.new()
	add_child(tutorial)
	await get_tree().process_frame
	_assert_modal(tutorial, "教程回看")
	tutorial.queue_free()
	await get_tree().process_frame

	var map = MapScreenScript.new()
	add_child(map)
	await get_tree().process_frame
	_assert_modal(map, "地图")
	map.queue_free()
	await get_tree().process_frame


func test_choice_dialogs_use_plate_rows_without_rail_ticks() -> void:
	var title = load("res://scenes/ui/TitleScreen.tscn").instantiate() as TitleScreen
	add_child(title)
	await get_tree().process_frame
	await get_tree().process_frame
	title.open_confirm()
	await get_tree().process_frame
	var menu := title.find_child("ConfirmMenu", true, false) as MenuList
	ok(menu != null, "覆盖确认框有菜单")
	if menu != null:
		var items: Array[MenuItem] = []
		for child in menu.get_children():
			if child is MenuItem:
				items.append(child)
		eq(items.size(), 2, "确认框两格")
		if items.size() == 2:
			eq(items[0].kind, MenuItem.Kind.SECONDARY, "取消是燕尾板")
			eq(items[1].kind, MenuItem.Kind.GHOST, "清档只留角标")
			ok(not items[0].show_tick and not items[1].show_tick, "对话框里不画铁架挂钉")
	title.queue_free()
	await get_tree().process_frame


## 暂停菜单里打开设置 / 教程回看 / 地图 / 操作说明：各自只有一份实例，打开时
## 暂停菜单仍在、树仍暂停；关闭后回到菜单、菜单重新吃输入，但暂停只在最后解除。
func test_pause_sub_screens_open_close_without_duplicating_or_unpausing() -> void:
	var pause := PauseMenu.new()
	add_child(pause)
	await get_tree().process_frame
	pause.open()
	await get_tree().process_frame
	ok(pause.is_open(), "pause opens")
	ok(get_tree().paused, "pause pauses the tree")
	_assert_one_of_each(pause, "fresh pause menu")
	# 每块子界面：走真实的菜单入口（点/回车那一行）→ 暂停菜单还在且不解除暂停 →
	# 子界面关闭 → 菜单重新接收输入。开合几轮后实例数不变 = 没有叠起来的旧弹窗。
	var subs: Array = [
		[&"settings", pause.settings_screen()],
		[&"tutorial", pause.tutorial_recall()],
		[&"map", pause.map_screen()],
		[&"story", pause.journal_screen()],
		[&"controls", pause.controls_panel()],
	]
	for entry in subs:
		var chosen_id: StringName = entry[0]
		var sub: CanvasLayer = entry[1]
		pause._on_chosen(chosen_id)
		await get_tree().process_frame
		await get_tree().process_frame
		ok(sub.visible, "%s opens over the pause menu" % sub.name)
		ok(pause.is_open() and get_tree().paused, "%s keeps the pause state" % sub.name)
		ok(pause.sub_screen_open(), "pause reports a sub screen is open")
		ok(not pause.menu().active, "menu input stays disabled under %s" % sub.name)
		sub.call("close")
		await get_tree().process_frame
		ok(not pause.sub_screen_open(), "%s closes without leaving a modal behind" % sub.name)
		ok(pause.is_open() and get_tree().paused,
				"%s close keeps the pause menu paused" % sub.name)
		ok(pause.menu().active, "menu input returns after %s closes" % sub.name)
	_assert_one_of_each(pause, "after open/close cycles")
	pause.close()
	await get_tree().process_frame
	ok(not pause.is_open(), "pause closes")
	ok(not get_tree().paused, "closing the pause menu resumes the tree")
	pause.queue_free()
	await get_tree().process_frame


func test_object_kit_physical_objects_and_transitions() -> void:
	var pause = PauseMenuScript.new()
	add_child(pause)
	await get_tree().process_frame
	pause.open()
	await get_tree().process_frame
	var p_card := pause.get_node_or_null("ModalRoot/Card") as Control
	ok(p_card != null, "pause card exists")
	if p_card != null:
		eq(p_card.position, p_card.position.round(), "pause card is integer pixel aligned")
		var dressing := pause.get_node_or_null("ModalRoot/Dressing")
		ok(dressing != null, "pause card has iron chain dressing")
		var wash := p_card.get_node_or_null("LightWash")
		ok(wash != null, "pause card has lantern light wash")
	pause.close()
	await get_tree().process_frame
	pause.queue_free()
	await get_tree().process_frame

	var settings = SettingsScreenScript.new()
	add_child(settings)
	await get_tree().process_frame
	settings.open()
	await get_tree().process_frame
	var s_card := settings.get_node_or_null("ModalRoot/Card") as Control
	ok(s_card != null, "settings card exists")
	if s_card != null:
		eq(s_card.position, s_card.position.round(), "settings card is integer pixel aligned")
		var dressing := settings.get_node_or_null("ModalRoot/Dressing")
		ok(dressing != null, "settings card has ledger ribbon dressing")
		var wash := s_card.get_node_or_null("LightWash")
		ok(wash != null, "settings card has overhead wash")
	settings.close()
	await get_tree().process_frame
	settings.queue_free()
	await get_tree().process_frame
