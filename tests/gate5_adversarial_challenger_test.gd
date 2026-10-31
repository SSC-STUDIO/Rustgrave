extends TestCase
## Gate 5 Empirical Challenger Test Suite (Milestone 3 Phase 3a Remediation):
## 1. SettingsScreen Card height containment across viewports (960x540, 1280x720, 1920x1080)
##    - card height <= 680px (specifically <= 652px)
##    - centered card top y >= 0px (specifically y >= 34px)
##    - ribbon dressing top y >= 0px (not clipped offscreen)
##    - bottom position <= viewport height
##    - horizontal margins >= 100px
## 2. BoardDressing dynamic chain sway:
##    - measurable horizontal displacement during spring settlement
##    - settles to 0 under exponential damping
## 3. Position invariance under rapid open/close cycling

const SettingsScreenScript := preload("res://scripts/ui/settings_screen.gd")
const PauseMenuScript := preload("res://scripts/ui/pause_menu.gd")
const ObjectKit := preload("res://scripts/ui/ui_object.gd")
const Transitions := preload("res://scripts/ui/ui_transition.gd")

const DESIGN_RESOLUTION := Vector2(1280.0, 720.0)
const STRESS_RESOLUTIONS: Array[Vector2i] = [
	Vector2i(960, 540),
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
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
	get_tree().root.size = Vector2i(1280, 720)


## Scope 1: SettingsScreen Card height viewport containment across viewports
func test_settings_screen_card_height_viewport_containment() -> void:
	var settings: SettingsScreen = SettingsScreenScript.new()
	add_child(settings)
	await get_tree().process_frame

	settings.open()
	await get_tree().process_frame
	await get_tree().process_frame

	var card := settings.get_node_or_null("ModalRoot/Card") as Control
	ok(card != null, "SettingsScreen has ModalRoot/Card")
	if card == null:
		settings.queue_free()
		return

	# 1. 验证在基准分辨率 1280x720 下卡片尺寸与居中位置
	var live_size: Vector2 = card.size
	var live_pos: Vector2 = card.position
	var comb_min: Vector2 = card.get_combined_minimum_size()

	# Assert card height <= 680px, specifically <= 652px
	ok(live_size.y <= 680.0, "SettingsScreen live card height %.1f <= 680px" % live_size.y)
	ok(live_size.y <= 652.0, "SettingsScreen live card height %.1f <= 652px (achieved: %.1f)" % [live_size.y, live_size.y])
	# Assert centered card top position y >= 0px, specifically y >= 34px
	ok(live_pos.y >= 0.0, "SettingsScreen card top position y %.1f >= 0px" % live_pos.y)
	ok(live_pos.y >= 34.0, "SettingsScreen card top position y %.1f >= 34px (achieved: %.1f)" % [live_pos.y, live_pos.y])
	# Assert bottom position <= viewport height
	ok(live_pos.y + live_size.y <= DESIGN_RESOLUTION.y, "SettingsScreen bottom position %.1f <= 720px" % (live_pos.y + live_size.y))
	# Assert horizontal margins >= 100px
	var h_margin: float = DESIGN_RESOLUTION.x - live_size.x
	ok(h_margin >= 100.0, "SettingsScreen horizontal margin %.1f >= 100px" % h_margin)

	# Assert ribbon dressing top position y >= 0px across all tabs
	for tab_idx in 4:
		settings.show_tab(tab_idx)
		await get_tree().process_frame

		# LedgerDressing active ribbon extends 22px up from card.position.y + 12px
		# So ribbon top y = card.position.y + 12.0 - 22.0 = card.position.y - 10.0
		var ribbon_top_y := card.position.y + 12.0 - 22.0
		ok(ribbon_top_y >= 0.0, "Tab %d ribbon dressing top y %.1f >= 0px (not clipped)" % [tab_idx, ribbon_top_y])
		ok(ribbon_top_y >= 24.0, "Tab %d ribbon dressing top y %.1f >= 24px clearance" % [tab_idx, ribbon_top_y])

		# Ensure tab page content does not cause card to blow out size
		ok(card.size.y <= 652.0, "Tab %d does not inflate card height beyond 652px (current: %.1f)" % [tab_idx, card.size.y])

	# 2. 验证多视口分辨率 (960x540, 1280x720, 1920x1080)
	for win_res in STRESS_RESOLUTIONS:
		get_tree().root.size = win_res
		PresentationMetrics.apply_layer(settings)
		await get_tree().process_frame

		var metrics: Dictionary = PresentationMetrics.calculate(win_res)
		var ui_xf: Transform2D = metrics["ui_transform"]
		var scale_factor: float = ui_xf.get_scale().x
		ok(scale_factor > 0.0, "@%s scale factor > 0" % win_res)

		# 卡片尺寸与位置在不同视口下保持合法
		ok(card.size.y <= 652.0, "@%s Settings card height %.1f <= 652" % [win_res, card.size.y])
		ok(card.position.y >= 34.0, "@%s Settings card top %.1f >= 34px" % [win_res, card.position.y])
		ok(card.position.y + card.size.y <= DESIGN_RESOLUTION.y, "@%s Settings bottom <= viewport" % win_res)
		ok(DESIGN_RESOLUTION.x - card.size.x >= 100.0, "@%s Settings h_margin >= 100px" % win_res)

	settings.close()
	await get_tree().process_frame
	settings.queue_free()
	await get_tree().process_frame


## Scope 2: BoardDressing dynamic chain sway displacement and exponential damping
func test_board_dressing_dynamic_chain_sway_and_damping() -> void:
	var dummy_card := Control.new()
	dummy_card.position = Vector2(130.0, 40.0)
	dummy_card.size = Vector2(1020.0, 640.0)
	add_child(dummy_card)

	var dressing = ObjectKit.dressing(ObjectKit.Kind.BOARD, dummy_card)
	ok(dressing != null, "BoardDressing created")
	if dressing == null:
		dummy_card.queue_free()
		return
	add_child(dressing)
	await get_tree().process_frame

	# 1. 静态静止状态验证
	dressing.snap()
	eq(dressing.sway_angle, 0.0, "Snap resets sway angle to 0.0")
	var rest_left: Vector2 = dressing.get_anchor_point(0)
	var rest_right: Vector2 = dressing.get_anchor_point(1)
	var expected_x1 := roundf(dummy_card.position.x + dummy_card.size.x * 0.22)
	var expected_x2 := roundf(dummy_card.position.x + dummy_card.size.x * 0.78)
	var expected_y := roundf(dummy_card.position.y + 6.0)
	eq(rest_left, Vector2(expected_x1, expected_y), "Static left anchor correctly aligned")
	eq(rest_right, Vector2(expected_x2, expected_y), "Static right anchor correctly aligned")
	var card_home := dummy_card.position
	dressing.play_spring_settle(true, 0.24)
	dressing._process(0.20)
	eq(dummy_card.position, card_home, "suspended board waits for the drop and rebound before swaying")
	eq(dressing.sway_angle, 0.0, "chains remain still before the board lands")

	# 2. 弹簧回弹激活与摆动位移测量
	dressing.play_spring_settle(true)
	ok(dressing._swaying, "Spring settle activates swaying flag")
	eq(dressing._time, 0.0, "Settling timer starts at 0.0")

	# 步进时间测量水平位移：在 t=0.224s 附近 sin(7*t) 达到峰值 ~1.0
	# sway_angle = 0.008 * sin(t * 7.0) * exp(-t * 2.5)
	var dt := 0.02
	var total_displacement_observed := 0.0
	var max_sway_observed := 0.0
	var prev_angle := 0.0
	var oscillations := 0

	var max_dx_observed := 0.0
	var attachment_error := 0.0
	var non_integer_frames := 0

	for step in range(50): # 1.0 second in 20ms steps
		dressing._process(dt)
		var curr_angle: float = dressing.sway_angle
		if absf(curr_angle) > max_sway_observed:
			max_sway_observed = absf(curr_angle)

		var anchor_left: Vector2 = dressing.get_anchor_point(0)
		var anchor_right: Vector2 = dressing.get_anchor_point(1)
		var dx_left: float = anchor_left.x - rest_left.x
		var dx_right: float = anchor_right.x - rest_right.x
		attachment_error = maxf(attachment_error, absf(dx_left - (dummy_card.position.x - card_home.x)))
		if dummy_card.position != dummy_card.position.round():
			non_integer_frames += 1

		if absf(dx_left) > max_dx_observed:
			max_dx_observed = absf(dx_left)

		# 验证两根链条物理同步平行摆动
		almost(dx_left, dx_right, 0.001, "Left and right chain sway parallel at t=%.2f" % dressing._time)

		# 记录水平位移累积量
		total_displacement_observed += absf(dx_left)

		# 统计振荡过零点 (零交叉验证弹簧振荡行为)
		if (prev_angle < 0.0 and curr_angle >= 0.0) or (prev_angle > 0.0 and curr_angle <= 0.0):
			oscillations += 1
		prev_angle = curr_angle

	ok(max_sway_observed > 0.003, "Dynamic sway produces measurable peak angular displacement (max: %.5f rad)" % max_sway_observed)
	ok(max_dx_observed > 0.15, "Dynamic sway produces measurable peak horizontal displacement (max: %.3f px)" % max_dx_observed)
	ok(total_displacement_observed > 2.0, "Dynamic sway produces measurable accumulated horizontal displacement (total: %.2f px)" % total_displacement_observed)
	ok(oscillations >= 2, "Dynamic sway exhibits harmonic spring oscillation (zero crossings: %d)" % oscillations)
	almost(attachment_error, 0.0, 0.001, "chain ends remain attached to the moving iron board")
	eq(non_integer_frames, 0, "the board and engraved type move only by whole pixels")

	# 3. 指数阻尼衰减验证：比较早期半周期振幅与中后期振幅
	# 推进时间至 > 1.2s，验证完全收敛归零
	dressing._process(0.5) # total time now ~1.5s
	ok(not dressing._swaying, "Swaying flag turned off after decay period (>1.2s)")
	eq(dressing.sway_angle, 0.0, "Sway angle damped strictly to 0.0")
	eq(dressing.get_anchor_point(0), rest_left, "Left anchor point strictly restored to resting position")
	eq(dressing.get_anchor_point(1), rest_right, "Right anchor point strictly restored to resting position")
	eq(dummy_card.position, card_home, "damping restores the actual board as well as its chains")

	dressing.queue_free()
	dummy_card.queue_free()
	await get_tree().process_frame


func test_plate_nails_wait_for_landing_then_drive_in_clockwise() -> void:
	var card := Control.new()
	card.position = Vector2(80.0, 40.0)
	card.size = Vector2(1120.0, 640.0)
	add_child(card)
	var dressing = ObjectKit.dressing(ObjectKit.Kind.PLATE, card)
	add_child(dressing)
	dressing.set_process(false)
	var points: PackedVector2Array = dressing.nail_points()
	eq(points, PackedVector2Array([Vector2(106, 70), Vector2(1168, 70), Vector2(1168, 634), Vector2(106, 634)]),
			"four nails are seated clockwise in the actual plate corner brackets")
	dressing.play_open(0.20)
	eq(dressing.installed_nail_count(), 0, "plate starts with four empty drilled brackets")
	dressing._process(0.199)
	eq(dressing.installed_nail_count(), 0, "no nail appears before the 0.20 second landing")
	dressing._process(0.002)
	eq(dressing.installed_nail_count(), 1, "first nail starts after landing")
	for count in range(2, 5):
		dressing._process(0.08)
		eq(dressing.installed_nail_count(), count, "successive nails are driven every 0.08 seconds")
	dressing._process(0.30)
	eq(dressing.installed_nail_count(), 4, "all corner nails remain after the brief sparks finish")
	dressing.snap()
	eq(dressing.installed_nail_count(), 4, "headless/reduced-motion snap presents a complete mounted plate")
	dressing.queue_free()
	card.queue_free()
	await get_tree().process_frame


## Scope 3: Multi-cycle open/close position invariance (10 cycles)
func test_ten_cycles_open_close_position_invariance() -> void:
	var settings: SettingsScreen = SettingsScreenScript.new()
	add_child(settings)
	await get_tree().process_frame

	settings.open()
	await get_tree().process_frame
	await get_tree().process_frame

	var card := settings.get_node_or_null("ModalRoot/Card") as Control
	ok(card != null, "Settings card exists")
	var original_pos: Vector2 = card.position

	for cycle in range(10):
		settings.close()
		await get_tree().process_frame
		await get_tree().process_frame
		settings.open()
		await get_tree().process_frame
		await get_tree().process_frame
		eq(card.position, original_pos, "Cycle %d: Settings card position strictly invariant at %s" % [cycle + 1, original_pos])

	settings.close()
	await get_tree().process_frame
	settings.queue_free()
	await get_tree().process_frame


## Scope 4: TitleScreen dimming modulates _menu, _lamp, and _menu_shade together
func test_title_screen_dimming_modulates_menu_lamp_and_shade() -> void:
	const TitleScreenScene := preload("res://scenes/ui/TitleScreen.tscn")
	var title: TitleScreen = TitleScreenScene.instantiate()
	add_child(title)
	await get_tree().process_frame

	title.skip_intro()
	await get_tree().process_frame

	var menu: Control = title.get_node_or_null("Menu")
	var lamp: CanvasItem = title.get_node_or_null("LampCursor")
	var shade: CanvasItem = title.get_node_or_null("MenuShade")
	ok(menu != null, "Title Menu exists")
	ok(lamp != null, "Title LampCursor exists")
	ok(shade != null, "Title MenuShade exists")

	# Initial state after intro: full opacity
	eq(menu.modulate.a, 1.0, "Menu starts at alpha 1.0")
	eq(lamp.modulate.a, 1.0, "Lamp starts at alpha 1.0")
	eq(shade.modulate.a, 1.0, "Shade starts at alpha 1.0")

	# Simulate fade out on opening secondary screen (e.g. Settings)
	title.call("_fade_title_menu", 0.0)
	await get_tree().process_frame
	eq(menu.modulate.a, 0.0, "Menu faded to alpha 0.0")
	eq(lamp.modulate.a, 0.0, "Lamp faded to alpha 0.0")
	eq(shade.modulate.a, 0.0, "Shade faded to alpha 0.0")

	# Simulate fade in on closing secondary screen
	title.call("_fade_title_menu", 1.0)
	await get_tree().process_frame
	eq(menu.modulate.a, 1.0, "Menu restored to alpha 1.0")
	eq(lamp.modulate.a, 1.0, "Lamp restored to alpha 1.0")
	eq(shade.modulate.a, 1.0, "Shade restored to alpha 1.0")

	title.queue_free()
	await get_tree().process_frame

