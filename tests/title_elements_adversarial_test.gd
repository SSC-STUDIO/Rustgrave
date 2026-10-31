extends TestCase
## 对抗性测试套件：针对 Milestone 1 (Phase 1) 标题屏元素进行极限工况与边界条件压力测试：
##   1. 坩埚铁水折线连续性：全阶段 / 极端倾角 / 炉温波动 / dt 步长变化下的采样点间距（<= 2.0px）
##   2. 吊灯光标与光晕：极速换行激荡 / 弹簧数值稳定性 (NaN/Inf 检查) / 光晕范围与衰减边界
##   3. 光源预算严格执行：UI 层 PointLight2D 绝对为 0，TitleWorld <= 8

const TITLE_SCENE := "res://scenes/ui/TitleScreen.tscn"
const WORLD_SCENE := "res://scenes/ui/TitleWorld.tscn"
const CrucibleScript := preload("res://scripts/ui/title_crucible.gd")
const LampCursorScript := preload("res://scripts/ui/title_lamp_cursor.gd")


func setup() -> void:
	TitleWorld.forced_state = {}


func teardown() -> void:
	TitleWorld.forced_state = {}


func _make_world(state: Dictionary) -> TitleWorld:
	var vp := SubViewport.new()
	vp.size = PresentationMetrics.WORLD_SIZE
	vp.world_2d = World2D.new()
	vp.disable_3d = true
	vp.snap_2d_transforms_to_pixel = true
	add_child(vp)
	var world := (load(WORLD_SCENE) as PackedScene).instantiate() as TitleWorld
	world.state = state
	vp.add_child(world)
	return world


func _free_world(world: TitleWorld) -> void:
	world.get_parent().queue_free()
	await get_tree().process_frame


func _open_title() -> TitleScreen:
	var title := (load(TITLE_SCENE) as PackedScene).instantiate() as TitleScreen
	add_child(title)
	await get_tree().process_frame
	await get_tree().process_frame
	return title


# ------------------------------------------------ 1. 坩埚铁水折线对抗测试 ----

## 验证坩埚在全阶段（LOAD, TO_POUR, TILT, POUR, UNTILT, TO_LOAD）、不同炉温与极端步长下，
## 铁水折线采样点的间距绝不超过 2.0 设计像素。
func test_crucible_stream_polyline_continuity_all_phases_and_heats() -> void:
	var crucible = CrucibleScript.new()
	add_child(crucible)

	var heats := [0.0, 0.05, 0.25, 1.0, 1.3, 2.0]
	var dts := [0.016, 0.05, 0.2]

	var max_gap_overall := 0.0
	var violation_count := 0
	var worst_info := ""

	for h in heats:
		crucible.heat = h
		for dt in dts:
			# 从初始倾倒阶段启动，完整运行 1 个完整周期（约 22 秒）
			crucible._setup()
			crucible.heat = h
			var elapsed := 0.0
			var cycle_limit := 24.0
			while elapsed < cycle_limit:
				crucible.advance(dt)
				elapsed += dt
				var ph: int = crucible.phase()
				var poly: PackedVector2Array = crucible.stream_polyline()
				if ph == CrucibleScript.Phase.POUR or ph == CrucibleScript.Phase.UNTILT:
					if crucible.stream_length() > 0.0:
						ok(poly.size() >= 2, "倾倒或断流阶段铁水点数 >= 2 (当前 %d, len=%.1f)" % [poly.size(), crucible.stream_length()])
						for i in range(1, poly.size()):
							var d := poly[i - 1].distance_to(poly[i])
							if d > max_gap_overall:
								max_gap_overall = d
							if d > 2.0:
								violation_count += 1
								if worst_info == "":
									worst_info = "phase=%d, heat=%.2f, dt=%.3f, p0=%s, p1=%s, dist=%.4f" % [ph, h, dt, poly[i-1], poly[i], d]
				else:
					ok(poly.is_empty(), "非倒铁水阶段折线为空 (phase=%d, size=%d)" % [ph, poly.size()])

	crucible.queue_free()
	await get_tree().process_frame

	print("[ADVERSARIAL] Crucible polyline max gap across all phases/heats: %.4f px" % max_gap_overall)
	if violation_count > 0:
		print("[ADVERSARIAL] Crucible polyline violations (> 2.0px): %d, worst: %s" % [violation_count, worst_info])
	ok(max_gap_overall <= 2.0, "铁水全段采样点间距在全阶段与变温下不超过 2.0px (实测最大值: %.4f px, 违规数: %d)" % [max_gap_overall, violation_count])


## 针对 POUR 与 UNTILT 阶段铁水端点变化的密集细分测试（针对非完整水柱状态的自适应采样）
func test_crucible_stream_dense_subrange_adversarial() -> void:
	var crucible = CrucibleScript.new()
	add_child(crucible)
	crucible._setup()
	crucible.heat = 1.0

	var max_gap := 0.0
	var violation_count := 0
	var worst_info := ""

	# 人工在 [0, stream_max] 范围内密集滑动 _stream_top 与 _stream_bot
	var span: float = crucible.stream_max()
	var bot_steps := 100
	for b in range(1, bot_steps + 1):
		var bot := (float(b) / float(bot_steps)) * span
		crucible._stream_bot = bot
		crucible._stream_top = 0.0
		var pts: PackedVector2Array = crucible.stream_polyline()
		if pts.size() >= 2:
			for i in range(1, pts.size()):
				var d := pts[i - 1].distance_to(pts[i])
				if d > max_gap:
					max_gap = d
				if d > 2.0:
					violation_count += 1
					if worst_info == "":
						worst_info = "bot=%.1f, top=0, p0=%s, p1=%s, dist=%.4f" % [bot, pts[i-1], pts[i], d]

	# 测试断流（UNTILT 阶段）：_stream_top 往下落
	var top_steps := 50
	for t in range(1, top_steps):
		var top := (float(t) / float(top_steps)) * span
		crucible._stream_top = top
		crucible._stream_bot = span
		var pts: PackedVector2Array = crucible.stream_polyline()
		if pts.size() >= 2:
			for i in range(1, pts.size()):
				var d := pts[i - 1].distance_to(pts[i])
				if d > max_gap:
					max_gap = d
				if d > 2.0:
					violation_count += 1
					if worst_info == "":
						worst_info = "bot=%.1f, top=%.1f, p0=%s, p1=%s, dist=%.4f" % [span, top, pts[i-1], pts[i], d]

	crucible.queue_free()
	await get_tree().process_frame

	print("[ADVERSARIAL] Dense subrange max gap: %.4f px (violations: %d)" % [max_gap, violation_count])
	ok(max_gap <= 2.0, "细分测试中铁水连续点间距不超过 2.0px (实测最大值: %.4f px)" % max_gap)


## 针对 (u0, u1) 全二维密集网格扫描（上端点与下端点全排列，>5000 种子区间）
func test_crucible_stream_dense_2d_subrange_sweep() -> void:
	var crucible = CrucibleScript.new()
	add_child(crucible)
	crucible._setup()
	crucible.heat = 1.0

	var span: float = crucible.stream_max()
	var max_gap := 0.0
	var violation_count := 0
	var total_subranges := 0
	var worst_info := ""

	var grid_steps := 100
	for i in range(grid_steps):
		var u0 := float(i) / float(grid_steps)
		for j in range(i + 1, grid_steps + 1):
			var u1 := float(j) / float(grid_steps)
			total_subranges += 1
			crucible._stream_top = u0 * span
			crucible._stream_bot = u1 * span
			var pts: PackedVector2Array = crucible.stream_polyline()
			if pts.size() < 2:
				violation_count += 1
				continue
			for p_idx in range(1, pts.size()):
				var d := pts[p_idx - 1].distance_to(pts[p_idx])
				if d > max_gap:
					max_gap = d
				if d > 2.0:
					violation_count += 1
					if worst_info == "":
						worst_info = "u0=%.3f, u1=%.3f, p0=%s, p1=%s, dist=%.4f" % [u0, u1, pts[p_idx-1], pts[p_idx], d]

	crucible.queue_free()
	await get_tree().process_frame

	print("[ADVERSARIAL] 2D dense sweep (%d subranges) max gap: %.4f px (violations: %d)" % [total_subranges, max_gap, violation_count])
	if worst_info != "":
		print("[ADVERSARIAL] 2D dense sweep worst: %s" % worst_info)
	ok(violation_count == 0, "全二维网格扫描无点距超标或点数不足违规 (违规数: %d)" % violation_count)
	ok(max_gap <= 2.0, "全二维网格密集扫描中点间距不超过 2.0px (实测最大值: %.4f px)" % max_gap)


## 针对 (u0, u1) 随机子区间段的大规模蒙特卡洛压力测试（含微小区间与边界扰动）
func test_crucible_stream_randomized_segments_adversarial() -> void:
	var crucible = CrucibleScript.new()
	add_child(crucible)
	crucible._setup()
	crucible.heat = 1.0

	var span: float = crucible.stream_max()
	var rng := RandomNumberGenerator.new()
	rng.seed = 987654321

	var max_gap := 0.0
	var violation_count := 0
	var sample_count := 5000
	var worst_info := ""

	for trial in sample_count:
		var a := rng.randf_range(0.0, 1.0)
		var b := rng.randf_range(0.0, 1.0)
		var u0 := minf(a, b)
		var u1 := maxf(a, b)
		# 包含微小段与接近重合段的扰动
		if trial % 5 == 0:
			u1 = minf(1.0, u0 + rng.randf_range(0.0001, 0.005))
		if u1 <= u0 + 0.00001:
			continue

		crucible._stream_top = u0 * span
		crucible._stream_bot = u1 * span
		var pts: PackedVector2Array = crucible.stream_polyline()
		if pts.size() < 2:
			violation_count += 1
			continue
		for p_idx in range(1, pts.size()):
			var p0 := pts[p_idx - 1]
			var p1 := pts[p_idx]
			if not p0.is_finite() or not p1.is_finite():
				violation_count += 1
				continue
			var d := p0.distance_to(p1)
			if d > max_gap:
				max_gap = d
			if d > 2.0:
				violation_count += 1
				if worst_info == "":
					worst_info = "trial=%d, u0=%.4f, u1=%.4f, p0=%s, p1=%s, dist=%.4f" % [trial, u0, u1, p0, p1, d]

	crucible.queue_free()
	await get_tree().process_frame

	print("[ADVERSARIAL] Randomized subranges (%d trials) max gap: %.4f px (violations: %d)" % [sample_count, max_gap, violation_count])
	if worst_info != "":
		print("[ADVERSARIAL] Randomized worst: %s" % worst_info)
	ok(violation_count == 0, "随机子区间采样无违规 (违规数: %d)" % violation_count)
	ok(max_gap <= 2.0, "随机子区间采样点间距严格 <= 2.0px (实测最大值: %.4f px)" % max_gap)


## 针对快速状态转换、强制倾倒与时间步长激荡的极限压力测试
func test_crucible_rapid_state_transitions_adversarial() -> void:
	var crucible = CrucibleScript.new()
	add_child(crucible)

	var rng := RandomNumberGenerator.new()
	rng.seed = 123456789

	var max_gap := 0.0
	var violation_count := 0
	var worst_info := ""
	var checks := 0

	for cycle in 60:
		crucible._setup()
		crucible.heat = rng.randf_range(0.0, 2.5)

		for step in 50:
			# 随机注入中断或强制倾倒
			if rng.randf() < 0.15:
				crucible.force_pour()
			elif rng.randf() < 0.05:
				crucible.heat = rng.randf_range(0.1, 2.0)

			var dt := rng.randf_range(0.001, 0.3)
			crucible.advance(dt)

			var ph: int = crucible.phase()
			var pts: PackedVector2Array = crucible.stream_polyline()
			if ph == CrucibleScript.Phase.POUR or ph == CrucibleScript.Phase.UNTILT:
				if crucible.stream_length() > 0.0:
					checks += 1
					if pts.size() < 2:
						violation_count += 1
						continue
					for p_idx in range(1, pts.size()):
						var p0 := pts[p_idx - 1]
						var p1 := pts[p_idx]
						if not p0.is_finite() or not p1.is_finite():
							violation_count += 1
							continue
						var d := p0.distance_to(p1)
						if d > max_gap:
							max_gap = d
						if d > 2.0:
							violation_count += 1
							if worst_info == "":
								worst_info = "cycle=%d, step=%d, ph=%d, dt=%.4f, dist=%.4f" % [cycle, step, ph, dt, d]
			else:
				if not pts.is_empty():
					violation_count += 1

	crucible.queue_free()
	await get_tree().process_frame

	print("[ADVERSARIAL] Rapid transitions (%d state checks) max gap: %.4f px (violations: %d)" % [checks, max_gap, violation_count])
	if worst_info != "":
		print("[ADVERSARIAL] Rapid transitions worst: %s" % worst_info)
	ok(violation_count == 0, "快速状态转换与激荡推进无违规 (违规数: %d)" % violation_count)
	ok(max_gap <= 2.0, "快速状态转换中折线点距严格 <= 2.0px (实测最大值: %.4f px)" % max_gap)


# ------------------------------------------------ 2. 吊灯光标与光晕对抗测试 ----

## 快速导航与剧烈激荡测试：高频切换行、极端 delta，检查弹簧是否震荡发散或产生 NaN/Inf
func test_lamp_cursor_rapid_navigation_and_spring_stability() -> void:
	var title: TitleScreen = await _open_title()
	title._skip_intro()
	var lamp := title.find_child("LampCursor", true, false) as TitleLampCursor
	var menu := title.get_node("Menu") as MenuList
	ok(lamp != null and menu != null, "光标与菜单正常初始化")

	var switch_sequence := [0, 5, 1, 4, 6, 2, 3, 0, 6, 1, 5, 2]
	var deltas := [0.001, 0.016, 0.05, 0.1, 0.5, 1.5]

	# 连续高频切换
	for cycle in 20:
		for row_idx in switch_sequence:
			menu.select(row_idx, false)
			var dt: float = deltas[(cycle + row_idx) % deltas.size()]
			lamp.advance(dt, menu)

			var y: float = lamp.lantern_y()
			var pos: Vector2 = lamp.lantern_center()
			ok(not is_nan(y) and not is_inf(y), "光标 Y 坐标数值正常 (未产生 NaN/Inf)")
			ok(pos.is_finite(), "光标中心坐标有效且有限")
			ok(absf(lamp._swing) <= 16.01, "摆幅被限制在 [-16, 16] 内 (实测: %.2f)" % lamp._swing)

	# 给予 1.5 秒平息时间，验证弹簧收敛至目标行
	for i in 60:
		lamp.advance(0.025, menu)

	var target_id := menu.selected_id()
	var target_row: MenuItem
	for it in menu.items():
		var row := it as MenuItem
		if row != null and row.id == target_id:
			target_row = row
			break
	ok(target_row != null, "找到当前选中行")
	if target_row != null:
		var target_center_y: float = (lamp.get_global_transform().affine_inverse() * target_row.get_global_transform() * (target_row.size * 0.5)).y
		almost(lamp.lantern_y(), target_center_y, 1.5, "高频激荡后弹簧稳定收敛至目标行")

	title.queue_free()
	await get_tree().process_frame


## 闪烁与耀斑高压测试：极端 flare、光晕尺寸与边界衰减验证
func test_lamp_cursor_flare_and_halo_falloff_adversarial() -> void:
	var title: TitleScreen = await _open_title()
	title._skip_intro()
	var lamp := title.find_child("LampCursor", true, false) as TitleLampCursor
	var menu := title.get_node("Menu") as MenuList

	# 测试极端 flare 注入
	lamp.flare(5.0)
	lamp.advance(0.016, menu)
	var halo := lamp.get_node("Halo") as TextureRect
	ok(halo != null, "光晕节点存在")
	ok(halo.modulate.a <= 0.7201, "光晕 Alpha 受到上限约束 <= 0.72 (实测: %.3f)" % halo.modulate.a)
	ok(halo.size.x > 252.0, "耀斑激发时光晕尺寸明显扩大 (size=%.1f)" % halo.size.x)

	# 验证衰减：推进 4 秒后 flare 彻底衰减回 0
	for i in 100:
		lamp.advance(0.04, menu)
	almost(lamp._flare, 0.0, 0.001, "4秒后耀斑完全衰减归零")
	almost(halo.size.x, 252.0, 1.0, "耀斑归零后光晕恢复基准池尺寸 252px")

	# 验证光照衰减截止：离灯芯超过 FALLOFF (136px) 的行 lamp_light 必须严格为 0
	menu.select(0, false)
	lamp.snap()
	var items := menu.items()
	for i in items.size():
		var row := items[i] as MenuItem
		if row == null or not row.lamp:
			continue
		var to_local := lamp.get_global_transform().affine_inverse() * row.get_global_transform()
		var center_y := (to_local * (row.size * 0.5)).y
		var dist := absf(center_y - lamp.lantern_y())
		if dist >= TitleLampCursor.FALLOFF:
			almost(row.lamp_light, 0.0, 0.0001, "距离超过 FALLOFF (%.1f >= 136) 的第 %d 行光照严格为 0" % [dist, i])
		else:
			ok(row.lamp_light >= 0.0 and row.lamp_light <= 1.0, "FALLOFF 范围内的第 %d 行光照在 [0, 1] 之间 (%.3f)" % [i, row.lamp_light])

	title.queue_free()
	await get_tree().process_frame


# ------------------------------------------------ 3. 光源预算严格执行测试 ----

## 严格审计节点树：UI 层 PointLight2D 必须为 0；TitleWorld <= 8
func test_light_budget_enforcement_adversarial() -> void:
	var title: TitleScreen = await _open_title()
	title._skip_intro()

	# 遍历整个 TitleScreen 节点树
	var world := title.find_child("TitleWorld", true, false)
	var ui_point_lights: Array[Node] = []
	var all_point_lights := title.find_children("*", "PointLight2D", true, false)

	for light in all_point_lights:
		if world == null or not world.is_ancestor_of(light):
			ui_point_lights.append(light)

	eq(ui_point_lights.size(), 0, "UI CanvasLayer / 控件树中严禁出现 PointLight2D (违规数量: %d)" % ui_point_lights.size())

	# 验证全变体下 TitleWorld 的光源数量
	var variants := [&"cold", &"act1", &"act2", &"act3", &"act4", &"give", &"keep", &"snuff"]
	for v in variants:
		var state := TitleWorld.build_state({"has_save": v != &"cold", "scene": "", "ending": str(v) if v in [&"give", &"keep", &"snuff"] else "", "flags": PackedStringArray(), "skin": "", "origin": "", "rank": 1})
		if v in [&"act1", &"act2", &"act3", &"act4"]:
			state["act"] = int(str(v).substr(3))
		var test_world := _make_world(state)
		await flush(2)
		var lights := test_world.find_children("*", "PointLight2D", true, false)
		ok(lights.size() <= TitleWorld.MAX_LIGHTS, "变体 %s 下 TitleWorld 的 PointLight2D 数量 %d <= 8" % [v, lights.size()])
		await _free_world(test_world)

	title.queue_free()
	await get_tree().process_frame
