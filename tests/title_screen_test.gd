extends TestCase
## 标题屏版式回归：菜单架在左下、五格分三档、每格不低于触控下限，
## 且不再压住 keyart 中轴（骑士与光柱）。异形板的形状/状态由 menu_plate.gd 现画，
## 这里一并守住"三类板宽度递减、选中态确实换板、贴图有缓存"。

const TITLE_SCENE := "res://scenes/ui/TitleScreen.tscn"
const Plate := preload("res://scripts/ui/menu_plate.gd")
## keyart 的骑士站在 x=640 的光柱下：菜单架任何一行都不能越过这条中线。
const KEYART_CENTER := 640.0
const EXPECTED_KINDS := [MenuItem.Kind.PRIMARY, MenuItem.Kind.PRIMARY,
		MenuItem.Kind.SECONDARY, MenuItem.Kind.SECONDARY, MenuItem.Kind.GHOST]


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
	almost(menu.position.x, TitleScreen.RAIL_X, 0.01, "菜单架按设计像素挂在左侧")
	almost(menu.position.y, TitleScreen.RAIL_TOP, 0.01, "菜单架顶边停在墓志上方")

	var items := _items(title)
	eq(items.size(), 5, "五格菜单")
	for i in mini(items.size(), EXPECTED_KINDS.size()):
		eq(items[i].kind, EXPECTED_KINDS[i], "第 %d 格的档位" % i)
	for item in items:
		ok(item.custom_minimum_size.y >= UiKit.TOUCH_MIN, "每格都够触控最小高度")

	title.queue_free()
	await get_tree().process_frame


func test_rail_stays_clear_of_the_keyart_center() -> void:
	var title: TitleScreen = await _open_title()
	for item in _items(title):
		var right: float = item.get_global_rect().end.x
		ok(right < KEYART_CENTER, "菜单行右端不越过中线 (%.0f < 640)" % right)
	# 墓志搬到右下角，和左下菜单架配重。
	var epitaph := title.get_node_or_null("Inscription/EpitaphRow/Epitaph") as Label
	ok(epitaph != null, "墓志在右下角")
	if epitaph != null:
		var box: Rect2 = epitaph.get_global_rect()
		ok(box.position.x > KEYART_CENTER, "墓志在画面右半边")
		ok(box.position.y > 360.0, "墓志在画面下半边")

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
	menu.select(4, false)
	eq(menu.selected_id(), &"quit", "最后一格是离开")
	# 上下键从顶部往下走，必须落在可用行上（无存档时"继续旅程"是禁用的）。
	menu.select(0, false)
	menu._step(1)
	var landed: MenuItem = menu._items[menu._index]
	ok(not landed.disabled, "上下键跳过禁用行")

	title.queue_free()
	await get_tree().process_frame


## 鼠标悬停与键盘上下键共用同一条"选中"信号：任何时刻只有一格是选中的，
## 两种输入方式看到的是同一块金框板（不出现"高亮一格、回车执行另一格"）。
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


## 菜单下标 → 菜单 id（五格顺序与 _build_rail 一致）。
func _id_for(index: int) -> StringName:
	return [&"new", &"continue", &"settings", &"controls", &"quit"][index]

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
