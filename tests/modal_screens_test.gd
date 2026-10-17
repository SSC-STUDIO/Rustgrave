extends TestCase
## 弹窗外壳回归：设置 / 操作说明 / 教程回看 / 地图 / 暂停菜单都必须是
## "居中卡片 + 可见压暗背景"，而不是整屏一张紫板；标签页吃的是同一套异形板样式。

const SettingsScreenScript := preload("res://scripts/ui/settings_screen.gd")
const PauseMenuScript := preload("res://scripts/ui/pause_menu.gd")
const ControlsPanelScript := preload("res://scripts/ui/controls_panel.gd")
const TutorialRecallScript := preload("res://scripts/ui/tutorial_recall.gd")
const MapScreenScript := preload("res://scripts/ui/map_screen.gd")
const Plate := preload("res://scripts/ui/menu_plate.gd")

## 卡片必须比设计分辨率小一圈，四周才留得出底下那层（标题屏 keyart / 暂停菜单）。
const DESIGN := Vector2(1280.0, 720.0)


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
		ok(sb is StyleBoxTexture, "标签页底是异形板样式盒")
		if sb is StyleBoxTexture:
			eq((sb as StyleBoxTexture).texture.get_size(),
					Plate.plate_size(Plate.Shape.TAG), "标签页底就是 TAG 板")

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
	eq(items.size(), 6, "暂停菜单六格")
	if items.size() == 6:
		eq(items[0].kind, MenuItem.Kind.PRIMARY, "第一格是主行动")
		eq(items[5].kind, MenuItem.Kind.GHOST, "最后一格是第三层")
	ok(pause.dossier_label("chapter") != null, "右列有行程档案")
	ok(pause.dossier_label("objective") != null, "档案里有当前目标行")

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
