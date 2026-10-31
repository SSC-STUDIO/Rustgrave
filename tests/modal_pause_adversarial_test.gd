extends TestCase
## 对抗性压力测试套件（Milestone 3 UI 升级：实体化次级界面与暂停树不变性）：
##   1. 物理卡片尺寸与多视口分辨率压力测试（960x540, 1280x720, 1920x1080，水平留白 >= 100px）
##   2. 背景纱幕透明度断言（全次级界面 veil alpha 严格 < 0.8）
##   3. 暂停树语义与不变性测试（PauseMenu 开 -> paused; Settings 打开/关闭 -> 保持 paused; PauseMenu 关 -> unpaused）
##   4. 50 次高频极速开关循环压力测试（实例泄漏、状态错乱、未解除暂停排查）
##   5. 过渡终止整像素对齐断言（所有控件坐标落于整像素点）

const SettingsScreenScript := preload("res://scripts/ui/settings_screen.gd")
const PauseMenuScript := preload("res://scripts/ui/pause_menu.gd")
const ControlsPanelScript := preload("res://scripts/ui/controls_panel.gd")
const TutorialRecallScript := preload("res://scripts/ui/tutorial_recall.gd")
const MapScreenScript := preload("res://scripts/ui/map_screen.gd")
const JournalScript := preload("res://scripts/ui/journal_screen.gd")
const ObjectKit := preload("res://scripts/ui/ui_object.gd")
const Transitions := preload("res://scripts/ui/ui_transition.gd")

const DESIGN_RESOLUTION := Vector2(1280.0, 720.0)
const STRESS_RESOLUTIONS: Array[Vector2i] = [
	Vector2i(960, 540),    # 16:9 半高清 (0.75x)
	Vector2i(1280, 720),   # 16:9 设计基准 (1.0x)
	Vector2i(1920, 1080),  # 16:9 全高清 (1.5x)
]


func setup() -> void:
	Director.choice_hold = false
	if get_tree().paused:
		get_tree().paused = false


func teardown() -> void:
	Director.choice_hold = false
	Director.resume()
	if get_tree().paused:
		get_tree().paused = false
	# 还原视口尺寸基准
	get_tree().root.size = Vector2i(1280, 720)


func _assert_controls_integer_pixels(node: Node, failures_out: Array[String], path_prefix: String = "") -> void:
	if node is Control:
		var c := node as Control
		var p: Vector2 = c.position
		var s: Vector2 = c.size
		if not is_equal_approx(p.x, roundf(p.x)) or not is_equal_approx(p.y, roundf(p.y)):
			failures_out.append("Control %s position (%.3f, %.3f) is not integer pixel aligned" % [path_prefix + c.name, p.x, p.y])
		if not is_equal_approx(s.x, roundf(s.x)) or not is_equal_approx(s.y, roundf(s.y)):
			failures_out.append("Control %s size (%.3f, %.3f) is not integer pixel aligned" % [path_prefix + c.name, s.x, s.y])
	for child in node.get_children():
		_assert_controls_integer_pixels(child, failures_out, path_prefix + node.name + "/")


## 场景 1：实体卡片尺寸在 1280x720 及多视口配置下均容纳于基准并保持水平留白 >= 100px
func test_card_sizing_across_viewport_resolutions() -> void:
	var screen_factories: Array[Dictionary] = [
		{"name": "PauseMenu (Board)", "create": func(): return PauseMenuScript.new()},
		{"name": "SettingsScreen (Ledger)", "create": func(): return SettingsScreenScript.new()},
		{"name": "ControlsPanel (Notes)", "create": func(): return ControlsPanelScript.new()},
		{"name": "TutorialRecall (Journal)", "create": func(): return TutorialRecallScript.new()},
		{"name": "MapScreen (Plate)", "create": func(): return MapScreenScript.new()},
		{"name": "JournalScreen", "create": func(): return JournalScript.new()},
	]

	for entry in screen_factories:
		var name_str: String = entry["name"]
		var screen: CanvasLayer = entry["create"].call()
		add_child(screen)
		await get_tree().process_frame

		var card := screen.get_node_or_null("ModalRoot/Card") as Control
		ok(card != null, "%s has ModalRoot/Card" % name_str)
		if card != null:
			if screen.has_method("open"):
				screen.call("open")
				await get_tree().process_frame
				await get_tree().process_frame

			var min_size: Vector2 = card.custom_minimum_size
			var live_size: Vector2 = card.size
			var live_pos: Vector2 = card.position
			var comb_min: Vector2 = card.get_combined_minimum_size()
			print("DEBUG Open Screen [%s]: custom_min=%s, comb_min=%s, live_size=%s, pos=%s" % [name_str, min_size, comb_min, live_size, live_pos])
			ok(min_size.x <= DESIGN_RESOLUTION.x, "%s custom_min.x %.1f <= 1280.0" % [name_str, min_size.x])
			ok(min_size.y <= DESIGN_RESOLUTION.y, "%s custom_min.y %.1f <= 720.0" % [name_str, min_size.y])
			ok(live_size.x <= DESIGN_RESOLUTION.x, "%s live_size.x %.1f <= 1280.0" % [name_str, live_size.x])
			ok(live_size.y <= DESIGN_RESOLUTION.y, "%s live_size.y %.1f <= 720.0" % [name_str, live_size.y])
			ok(live_pos.y >= 0.0, "%s live_pos.y %.1f >= 0.0 (not clipped at top)" % [name_str, live_pos.y])
			ok(live_pos.y + live_size.y <= DESIGN_RESOLUTION.y, "%s bottom %.1f <= 720.0 (not clipped at bottom)" % [name_str, live_pos.y + live_size.y])
			if name_str.begins_with("SettingsScreen"):
				ok(live_size.y <= 680.0, "SettingsScreen card height %.1f <= 680px" % live_size.y)
				ok(live_pos.y >= 0.0, "SettingsScreen card top position %.1f >= 0px" % live_pos.y)
			var h_margin: float = DESIGN_RESOLUTION.x - live_size.x
			ok(h_margin >= 100.0, "%s horizontal clearance %.1f >= 100px" % [name_str, h_margin])

			for win_res in STRESS_RESOLUTIONS:
				get_tree().root.size = win_res
				PresentationMetrics.apply_layer(screen)
				await get_tree().process_frame

				var metrics: Dictionary = PresentationMetrics.calculate(win_res)
				var ui_xf: Transform2D = metrics["ui_transform"]
				var scale_factor: float = ui_xf.get_scale().x
				ok(scale_factor > 0.0, "%s @%s scale factor > 0" % [name_str, win_res])

				# 确认实际卡片尺寸未超限
				ok(card.size.x <= DESIGN_RESOLUTION.x + 0.1, "%s @%s live width %.1f <= 1280" % [name_str, win_res, card.size.x])
				ok(card.size.y <= DESIGN_RESOLUTION.y + 0.1, "%s @%s live height %.1f <= 720" % [name_str, win_res, card.size.y])

			if screen.has_method("close"):
				screen.call("close")
				await get_tree().process_frame

		screen.queue_free()
		await get_tree().process_frame




## 场景 2：所有打开的次级界面背景纱幕透明度严格 < 0.8
func test_background_veil_alpha_strictly_less_than_0_8() -> void:
	var screen_factories: Array[Dictionary] = [
		{"name": "PauseMenu", "create": func(): return PauseMenuScript.new()},
		{"name": "SettingsScreen", "create": func(): return SettingsScreenScript.new()},
		{"name": "ControlsPanel", "create": func(): return ControlsPanelScript.new()},
		{"name": "TutorialRecall", "create": func(): return TutorialRecallScript.new()},
		{"name": "MapScreen", "create": func(): return MapScreenScript.new()},
		{"name": "JournalScreen", "create": func(): return JournalScript.new()},
	]

	for entry in screen_factories:
		var name_str: String = entry["name"]
		var screen: CanvasLayer = entry["create"].call()
		add_child(screen)
		await get_tree().process_frame

		if screen.has_method("open"):
			screen.call("open")
			await get_tree().process_frame

		var veil := screen.get_node_or_null("ModalRoot/Veil") as ColorRect
		ok(veil != null, "%s has ModalRoot/Veil" % name_str)
		if veil != null:
			var base_alpha: float = veil.color.a
			ok(base_alpha < 0.8, "%s base veil alpha %.3f < 0.8" % [name_str, base_alpha])
			var effective_alpha: float = veil.color.a * veil.modulate.a
			ok(effective_alpha < 0.8, "%s effective veil alpha %.3f < 0.8" % [name_str, effective_alpha])

		if screen.has_method("close"):
			screen.call("close")
			await get_tree().process_frame

		screen.queue_free()
		await get_tree().process_frame

	# 测试标题屏覆盖确认信笺 (LETTER)
	var title = load("res://scenes/ui/TitleScreen.tscn").instantiate() as TitleScreen
	add_child(title)
	await get_tree().process_frame
	title.open_confirm()
	await get_tree().process_frame
	var title_veil := title.find_child("Veil", true, false) as ColorRect
	ok(title_veil != null, "Title confirm has Veil")
	if title_veil != null:
		ok(title_veil.color.a < 0.8, "Title confirm veil alpha %.3f < 0.8" % title_veil.color.a)
	title.queue_free()
	await get_tree().process_frame


## 场景 3：暂停树语义与不变性测试（PauseMenu 开关、Settings 子界面嵌套开关）
func test_pause_tree_invariants() -> void:
	var pause: PauseMenu = PauseMenuScript.new()
	add_child(pause)
	await get_tree().process_frame

	ok(not get_tree().paused, "Tree starts unpaused")
	ok(not pause.is_open(), "PauseMenu starts closed")

	# 1. 打开 PauseMenu -> tree pauses
	pause.open()
	await get_tree().process_frame
	ok(pause.is_open(), "PauseMenu is open")
	ok(get_tree().paused, "Tree pauses when PauseMenu opens")

	# 2. 从 PauseMenu 打开 SettingsScreen -> tree remains paused
	pause._on_chosen(PauseMenu.ID_SETTINGS)
	await get_tree().process_frame
	await get_tree().process_frame
	var settings: SettingsScreen = pause.settings_screen()
	ok(settings != null and settings.visible, "SettingsScreen is visible")
	ok(pause.sub_screen_open(), "PauseMenu reports sub screen open")
	ok(get_tree().paused, "Tree remains paused when SettingsScreen opens from PauseMenu")

	# 3. 关闭 SettingsScreen 回到 PauseMenu -> tree remains paused
	settings.close()
	await get_tree().process_frame
	await get_tree().process_frame
	ok(not settings.visible, "SettingsScreen is hidden")
	ok(pause.is_open(), "PauseMenu is still open")
	ok(get_tree().paused, "Tree remains paused when SettingsScreen closes back to PauseMenu")
	ok(not pause.sub_screen_open(), "PauseMenu reports no sub screen open")

	# 4. 关闭 PauseMenu -> tree unpauses
	pause.close()
	await get_tree().process_frame
	await get_tree().process_frame
	ok(not pause.is_open(), "PauseMenu is closed")
	ok(not get_tree().paused, "Tree unpauses when PauseMenu closes")

	pause.queue_free()
	await get_tree().process_frame


## 场景 4：50 次高频极速开关循环压力测试
func test_stress_50_rapid_open_close_cycles() -> void:
	var pause: PauseMenu = PauseMenuScript.new()
	add_child(pause)
	await get_tree().process_frame

	var cycles := 50
	var success_cycles := 0

	for i in range(cycles):
		# Open Pause
		pause.open()
		await get_tree().process_frame
		if not pause.is_open() or not get_tree().paused:
			break

		# Open Settings
		pause._on_chosen(PauseMenu.ID_SETTINGS)
		await get_tree().process_frame
		if not pause.settings_screen().visible or not get_tree().paused:
			break

		# Close Settings
		pause.settings_screen().close()
		await get_tree().process_frame
		if pause.settings_screen().visible or not pause.is_open() or not get_tree().paused:
			break

		# Close Pause
		pause.close()
		await get_tree().process_frame
		if pause.is_open() or get_tree().paused:
			break

		success_cycles += 1

	eq(success_cycles, cycles, "Completed 50 rapid open/close cycles without state corruption")
	ok(not get_tree().paused, "Tree cleanly unpaused after 50 cycles")

	# 校验实例数无任何泄漏
	var settings_count := 0
	for child in pause.get_children():
		if child is SettingsScreen:
			settings_count += 1
	eq(settings_count, 1, "Exactly one SettingsScreen child on PauseMenu after 50 cycles")

	pause.queue_free()
	await get_tree().process_frame


## 场景 5：所有控件在过渡结束时必须落在整像素位置（无半像素模糊）
func test_all_controls_land_on_whole_integer_pixels_on_transition_end() -> void:
	# 检查 PauseMenu 及其全部控件节点
	var pause: PauseMenu = PauseMenuScript.new()
	add_child(pause)
	await get_tree().process_frame
	pause.open()
	await get_tree().process_frame
	await get_tree().process_frame

	var pause_failures: Array[String] = []
	var pause_card := pause.get_node_or_null("ModalRoot/Card") as Control
	ok(pause_card != null, "Pause card exists")
	if pause_card != null:
		_assert_controls_integer_pixels(pause_card, pause_failures)



	var pause_dressing := pause.get_node_or_null("ModalRoot/Dressing") as CanvasItem
	ok(pause_dressing != null, "Pause dressing exists")
	if pause_dressing is Control:
		_assert_controls_integer_pixels(pause_dressing, pause_failures)

	eq(pause_failures.size(), 0, "All PauseMenu controls land on integer pixels: %s" % (", ".join(pause_failures) if pause_failures.size() > 0 else "OK"))

	pause.close()
	await get_tree().process_frame
	pause.queue_free()
	await get_tree().process_frame

	# 检查 SettingsScreen 全部标签页下的控件节点
	var settings: SettingsScreen = SettingsScreenScript.new()
	add_child(settings)
	await get_tree().process_frame
	settings.open()
	await get_tree().process_frame
	await get_tree().process_frame

	var settings_card := settings.get_node_or_null("ModalRoot/Card") as Control
	ok(settings_card != null, "Settings card exists")

	for tab_idx in [0, 1, 2, 3]:
		settings.show_tab(tab_idx)
		await get_tree().process_frame
		var settings_failures: Array[String] = []
		if settings_card != null:
			_assert_controls_integer_pixels(settings_card, settings_failures)
		eq(settings_failures.size(), 0, "Settings tab %d controls land on integer pixels: %s" % [tab_idx, ", ".join(settings_failures) if settings_failures.size() > 0 else "OK"])

	settings.close()
	await get_tree().process_frame
	settings.queue_free()
	await get_tree().process_frame


## 场景 6：多次开关循环位置无累积漂移（3 次完整循环后卡片位置严格不变）
func test_multi_cycle_open_close_position_invariance() -> void:
	for factory in [
		{"name": "PauseMenu", "create": func(): return PauseMenuScript.new()},
		{"name": "SettingsScreen", "create": func(): return SettingsScreenScript.new()},
	]:
		var name_str: String = factory["name"]
		var screen: CanvasLayer = factory["create"].call()
		add_child(screen)
		await get_tree().process_frame

		screen.call("open")
		await get_tree().process_frame
		await get_tree().process_frame
		var card := screen.get_node_or_null("ModalRoot/Card") as Control
		ok(card != null, "%s Card exists" % name_str)
		var initial_pos: Vector2 = card.position

		# 循环 3 次关闭再打开，验证 card.position 零漂移
		for cycle in range(3):
			screen.call("close")
			await get_tree().process_frame
			await get_tree().process_frame
			screen.call("open")
			await get_tree().process_frame
			await get_tree().process_frame
			eq(card.position, initial_pos, "%s cycle %d card position preserves initial position without drift" % [name_str, cycle + 1])

		screen.call("close")
		await get_tree().process_frame
		screen.queue_free()
		await get_tree().process_frame

	# 显式校验 Transitions.object_out 动画执行完成时，卡片位置必重置回 home
	var test_root := Control.new()
	add_child(test_root)
	var test_card := Control.new()
	test_card.position = Vector2(200.0, 100.0)
	var test_home := test_card.position
	test_root.add_child(test_card)
	await get_tree().process_frame

	for cycle in range(3):
		var done_called := [false]
		var tw: Tween = Transitions.object_out(ObjectKit.Kind.BOARD, test_root, test_card, null, null, func(): done_called[0] = true, true)
		ok(tw != null, "Tween created for cycle %d" % cycle)
		if tw != null:
			await tw.finished
		ok(done_called[0], "on_done called for cycle %d" % cycle)
		eq(test_card.position, test_home, "Cycle %d: test_card.position restored to exact home after tween completion" % cycle)

	test_root.queue_free()
	await get_tree().process_frame


## 场景 7：BoardDressing 摆动对吊链与锁扣绘制的动态影响断言
func test_board_dressing_sway_affects_chain_drawing() -> void:
	var dummy_card := Control.new()
	dummy_card.position = Vector2(100.0, 80.0)
	dummy_card.size = Vector2(1000.0, 600.0)
	add_child(dummy_card)

	var dressing = ObjectKit.dressing(ObjectKit.Kind.BOARD, dummy_card)
	ok(dressing != null, "BoardDressing instantiated")
	if dressing == null:
		dummy_card.queue_free()
		return
	add_child(dressing)
	await get_tree().process_frame

	# 1. 初始静态状态：sway_angle 为 0，左/右锚点处于垂直标准位置
	dressing.snap()
	eq(dressing.sway_angle, 0.0, "Initial sway angle is 0.0")
	var static_anchor_left: Vector2 = dressing.get_anchor_point(0)
	var static_anchor_right: Vector2 = dressing.get_anchor_point(1)
	var expected_x1 := roundf(dummy_card.position.x + dummy_card.size.x * 0.22)
	var expected_x2 := roundf(dummy_card.position.x + dummy_card.size.x * 0.78)
	var expected_y := roundf(dummy_card.position.y + 6.0)
	eq(static_anchor_left, Vector2(expected_x1, expected_y), "Static left anchor aligns with card top shackle")
	eq(static_anchor_right, Vector2(expected_x2, expected_y), "Static right anchor aligns with card top shackle")

	# 2. 推进真实弹簧：板体与链底必须一起移动，避免只有链条在摆。
	var static_card_position := dummy_card.position
	dressing.play_spring_settle(true)
	ok(dressing._swaying, "Spring settle activates swaying state")
	dressing._process(0.15)
	var swayed_anchor_left: Vector2 = dressing.get_anchor_point(0)
	var swayed_anchor_right: Vector2 = dressing.get_anchor_point(1)
	var board_offset := dummy_card.position - static_card_position
	ok(absf(board_offset.x) > 1.0, "Iron board moves horizontally during spring settlement")
	eq(board_offset, board_offset.round(), "Board sway stays on integer pixels")
	ok(absf(swayed_anchor_left.x - static_anchor_left.x) > 1.0, "Left anchor displaced horizontally under sway")
	ok(absf(swayed_anchor_right.x - static_anchor_right.x) > 1.0, "Right anchor displaced horizontally under sway")
	eq(swayed_anchor_left - static_anchor_left, board_offset, "Left chain end remains attached to the moving board")
	eq(swayed_anchor_right - static_anchor_right, board_offset, "Right chain end remains attached to the moving board")
	eq(swayed_anchor_left.x, swayed_anchor_right.x - (expected_x2 - expected_x1), "Chains swing parallel in sync")

	# 3. 延续同一次回弹，验证摆动阻尼收敛，板体与链底一起回到原位。
	ok(absf(dressing.sway_angle) > 0.0, "Sway angle active during spring oscillation")
	# 推进时间超过 1.2s，验证摆动收敛终止
	dressing._process(1.5)
	ok(not dressing._swaying, "Swaying settles to false after decay interval")
	eq(dressing.sway_angle, 0.0, "Sway angle settles back to 0.0")
	eq(dummy_card.position, static_card_position, "Iron board returns to its exact resting position")
	eq(dressing.get_anchor_point(0), static_anchor_left, "Anchor points return to static resting coordinates")
	eq(dressing.get_anchor_point(1), static_anchor_right, "Right chain end returns to its exact resting coordinates")

	dressing.queue_free()
	dummy_card.queue_free()
	await get_tree().process_frame

