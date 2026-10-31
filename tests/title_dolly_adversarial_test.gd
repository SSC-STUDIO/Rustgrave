extends TestCase
## 对抗性测试套件：针对 Phase 2 摄像机推轨（Camera Dolly）与即时跳过（Immediate Skip）实施极限工况与边界条件压力测试：
##   1. 在任意浮点/分段时间偏移调用 skip_intro()（t=0, 0.001s, 0.01s, 0.05s, 0.1s, 0.4s, 0.8s, 1.2s, 1.59s, 1.60s, 1.61s, 2.0s, 3.0s）
##   2. 校验每次 skip 后 _dolly 绝对归零（Vector2.ZERO），且所有视差图层严格位于整像素坐标（无亚像素浮点泄漏）
##   3. 极速连续调用 skip_intro()（50+ 次连续瞬发、交替 play_intro 与 skip_intro 震荡测试）
##   4. 检验全变体（cold, act1, act2, act3, act4, give, keep, snuff）总开屏时长严格 <= 3.0s
##   5. 鼠标剧烈晃动（极端 Pointer）下的视差整像素不变性与帧后持续稳定性

const TITLE_SCENE := "res://scenes/ui/TitleScreen.tscn"
const WORLD_SCENE := "res://scenes/ui/TitleWorld.tscn"


func setup() -> void:
	TitleWorld.forced_state = {}


func teardown() -> void:
	TitleWorld.forced_state = {}


func _peek(level_id: String = "", flags: Array = [], ending: String = "", has_save: bool = true) -> Dictionary:
	return {
		"has_save": has_save,
		"scene": String(GameContext.LEVELS[level_id]) if level_id != "" else "",
		"flags": PackedStringArray(flags),
		"ending": ending,
		"skin": "",
		"origin": "",
		"rank": 3,
		"points": 1,
	}


func _done_flags(count: int) -> Array:
	var out: Array = []
	for i in count:
		out.append(String(StoryFlow.DONE_FLAGS[GameContext.LEVEL_ORDER[i]]))
	return out


func _journey(cleared: int) -> Dictionary:
	var scene := String(GameContext.LEVEL_ORDER[mini(cleared, GameContext.LEVEL_ORDER.size() - 1)])
	return TitleWorld.build_state(_peek(scene, _done_flags(cleared)))


func _state(variant_id: String) -> Dictionary:
	match variant_id:
		"cold":
			return TitleWorld.build_state(_peek("", [], "", false))
		"act1":
			return _journey(2)
		"act2":
			return _journey(4)
		"act3":
			return _journey(8)
		"act4":
			return _journey(13)
	return TitleWorld.build_state(_peek("level10", _done_flags(14), variant_id))


func _all_variants() -> Array:
	return ["cold", "act1", "act2", "act3", "act4", "give", "keep", "snuff"]


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
	if world != null and is_instance_valid(world):
		var parent := world.get_parent()
		if parent != null and is_instance_valid(parent):
			parent.queue_free()
		else:
			world.queue_free()
	await get_tree().process_frame


func _open_title() -> TitleScreen:
	var title := (load(TITLE_SCENE) as PackedScene).instantiate() as TitleScreen
	add_child(title)
	await get_tree().process_frame
	await get_tree().process_frame
	return title


func _free_title(title: TitleScreen) -> void:
	if title != null and is_instance_valid(title):
		title.queue_free()
	await get_tree().process_frame


func _assert_layers_integer_snapped(world: TitleWorld, context: String) -> void:
	var layers := world.parallax_layers()
	ok(layers.size() >= 10, "%s: 视差图层数量正常 (当前 %d)" % [context, layers.size()])
	for layer in layers:
		var pos := layer.position
		var rx := roundf(pos.x)
		var ry := roundf(pos.y)
		var is_int_x := (pos.x == rx)
		var is_int_y := (pos.y == ry)
		ok(is_int_x, "%s: 图层 '%s' pos.x 为整数 (实际 %f, 四舍五入 %f)" % [context, layer.name, pos.x, rx])
		ok(is_int_y, "%s: 图层 '%s' pos.y 为整数 (实际 %f, 四舍五入 %f)" % [context, layer.name, pos.y, ry])
		ok(is_finite(pos.x) and is_finite(pos.y), "%s: 图层 '%s' 坐标数值有效 (非 NaN/Inf)" % [context, layer.name])
		ok(absf(pos.x - rx) < 0.00001, "%s: 图层 '%s' x 坐标无亚像素泄漏" % [context, layer.name])
		ok(absf(pos.y - ry) < 0.00001, "%s: 图层 '%s' y 坐标无亚像素泄漏" % [context, layer.name])


# -----------------------------------------------------------------------------------------
# 1. 全变体开屏总时长严格 <= 3.0s 契约断言
# -----------------------------------------------------------------------------------------

func test_total_intro_duration_bounds_across_all_variants() -> void:
	for variant_id in _all_variants():
		var world := _make_world(_state(variant_id))
		await flush(2)
		var duration := world.play_intro(0.16)
		ok(duration >= TitleWorld.DOLLY_TIME,
				"%s: play_intro 时长 >= DOLLY_TIME (%.2f >= %.2f)" % [variant_id, duration, TitleWorld.DOLLY_TIME])
		ok(duration <= 3.0,
				"%s: play_intro 时长 <= 3.0s 契约边界 (实际 %.2fs)" % [variant_id, duration])
		await _free_world(world)

	# 校验 TitleScreen 整体开屏总耗时
	var title: TitleScreen = await _open_title()
	var menu_rows := 0
	for child in title.get_node("Menu").get_children():
		if child is MenuItem:
			menu_rows += 1
	var total_screen_time := TitleScreen.MENU_AT + TitleScreen.MENU_STAGGER * float(menu_rows) + TitleScreen.MENU_LAND + 0.1
	ok(total_screen_time <= 3.0, "TitleScreen 整体开屏动画总耗时 (%.2fs) <= 3.0s" % total_screen_time)
	ok(TitleScreen.LOGO_AT >= TitleWorld.DOLLY_TIME - 0.1, "字标落位与推轨落地同步")
	await _free_title(title)


# -----------------------------------------------------------------------------------------
# 2. 任意分段时间偏移 skip_intro() 对抗测试 (TitleWorld 仿真步进)
# -----------------------------------------------------------------------------------------

func test_world_skip_intro_at_arbitrary_fractional_offsets() -> void:
	var offsets := [0.0, 0.001, 0.01, 0.05, 0.1, 0.25, 0.4, 0.8, 1.2, 1.59, 1.60, 1.61, 2.0, 2.8, 3.0, 3.5]
	var test_variants := ["cold", "act2", "keep", "snuff"]

	for variant_id in test_variants:
		for t_offset in offsets:
			var world := _make_world(_state(variant_id))
			await flush(2)
			world.play_intro(0.16)

			# 推进到指定的时间偏移点
			var elapsed := 0.0
			var step := 0.016
			while elapsed < t_offset:
				var dt := minf(step, t_offset - elapsed)
				world._process(dt)
				elapsed += dt

			# 在精确时间偏移点执行即时跳过
			world.skip_intro()

			eq(world._dolly, Vector2.ZERO,
					"%s @ t=%.3fs: skip_intro 后 _dolly 绝对归零" % [variant_id, t_offset])
			almost(world._intro_level, 1.0, 0.001,
					"%s @ t=%.3fs: 环境光 _intro_level 恢复满值 1.0" % [variant_id, t_offset])

			# 验证所有视差图层严格对齐整像素
			_assert_layers_integer_snapped(world, "%s @ t=%.3fs" % [variant_id, t_offset])

			# 步进后续 15 帧，验证跳过终态无漂移与持续整像素
			for i in 15:
				world._process(0.016)
				eq(world._dolly, Vector2.ZERO,
						"%s @ t=%.3fs 帧 %d: 后续帧 _dolly 维持 ZERO" % [variant_id, t_offset, i])
				for layer in world.parallax_layers():
					var pos := layer.position
					eq(pos, pos.round(),
							"%s @ t=%.3fs 帧 %d: 图层 '%s' 持续保持整像素" % [variant_id, t_offset, i, layer.name])

			await _free_world(world)


# -----------------------------------------------------------------------------------------
# 3. 真实引擎时间推进下 TitleScreen skip_intro() 真实场景测试
# -----------------------------------------------------------------------------------------

func test_title_screen_skip_intro_fractional_timer_offsets() -> void:
	var offsets := [0.0, 0.01, 0.1, 0.4, 0.8, 1.2, 1.59, 1.60, 2.0]

	for t_offset in offsets:
		var title: TitleScreen = await _open_title()
		if t_offset > 0.0:
			var timer := get_tree().create_timer(t_offset)
			while timer.time_left > 0.0:
				await get_tree().process_frame

		# 执行标题屏 skip_intro
		title.skip_intro()

		ok(not title.intro_playing(), "t=%.2fs: intro_playing 置为 false" % t_offset)
		var world := title.world()
		ok(world != null, "t=%.2fs: TitleWorld 引用有效" % t_offset)
		if world != null:
			eq(world._dolly, Vector2.ZERO, "t=%.2fs: world._dolly 绝对为 Vector2.ZERO" % t_offset)
			_assert_layers_integer_snapped(world, "TitleScreen @ t=%.2fs" % t_offset)

		# 验证 UI 控件状态已全部落位
		var mat: ShaderMaterial = title._logo.material as ShaderMaterial
		if mat != null:
			almost(float(mat.get_shader_parameter("progress")), 1.0, 0.001,
					"t=%.2fs: 字标着色器 progress 已跳至 1.0" % t_offset)

		for child in title.get_node("Menu").get_children():
			if child is MenuItem:
				almost((child as MenuItem).modulate.a, 1.0, 0.01, "菜单项 alpha 为 1.0")
				almost((child as MenuItem).land, 0.0, 0.01, "菜单项 land 落地为 0.0")

		await _free_title(title)


# -----------------------------------------------------------------------------------------
# 4. 连续 50 次极速瞬发 skip_intro() 压力测试（零延迟连续冲击与防重入）
# -----------------------------------------------------------------------------------------

func test_rapid_consecutive_skip_intro_invocations_stress() -> void:
	var world := _make_world(_state("act2"))
	await flush(2)
	world.play_intro(0.16)

	# 在同单帧内连续调用 50 次 skip_intro()
	for i in 50:
		world.skip_intro()
		eq(world._dolly, Vector2.ZERO, "单帧连续第 %d 次 skip 后 _dolly 为 ZERO" % (i + 1))

	_assert_layers_integer_snapped(world, "50次连续瞬发 skip 后")

	# 跨帧穿插多次 skip
	for i in 20:
		world.skip_intro()
		world._process(0.005)
		eq(world._dolly, Vector2.ZERO, "微步穿插第 %d 次 skip 后 _dolly 为 ZERO" % (i + 1))
		for layer in world.parallax_layers():
			eq(layer.position, layer.position.round(), "微步穿插图层整像素")

	await _free_world(world)


# -----------------------------------------------------------------------------------------
# 5. play_intro 与 skip_intro 剧烈交替震荡与重入测试 (Thrashing)
# -----------------------------------------------------------------------------------------

func test_play_and_skip_thrashing_reentrancy() -> void:
	var world := _make_world(_state("keep"))
	await flush(2)

	# 剧烈反复触发 play 与 skip，验证 tween 杀灭逻辑与无残留状态泄漏
	for i in 30:
		world.play_intro(0.16)
		# 随即在极短时间点调用 skip
		if i % 2 == 0:
			world._process(0.02)
		world.skip_intro()
		eq(world._dolly, Vector2.ZERO, "震荡第 %d 轮 skip 后 _dolly 为 ZERO" % (i + 1))
		for layer in world.parallax_layers():
			eq(layer.position, layer.position.round(), "震荡第 %d 轮图层整像素" % (i + 1))

	# 震荡后静置多帧，确保无延迟回调复活已杀灭的 tween
	for frame in 30:
		world._process(0.016)
		eq(world._dolly, Vector2.ZERO, "震荡后稳定帧 %d: _dolly 为 ZERO" % frame)

	_assert_layers_integer_snapped(world, "震荡测试完全落位后")
	await _free_world(world)


# -----------------------------------------------------------------------------------------
# 6. 剧烈鼠标偏移（Pointer Shift）联动推轨下的整像素绝对不变性
# -----------------------------------------------------------------------------------------

func test_pointer_shift_and_dolly_combined_integer_invariance() -> void:
	var world := _make_world(_state("cold"))
	await flush(2)

	var extreme_pointers := [
		Vector2(-1.0, -1.0),
		Vector2(1.0, 1.0),
		Vector2(-0.73, 0.42),
		Vector2(0.123, -0.891),
		Vector2(0.999, -0.001),
		Vector2.ZERO,
	]

	for ptr in extreme_pointers:
		world.play_intro(0.16)
		world.set_pointer(ptr)

		# 模拟几帧非零 pointer 移动
		for step in 5:
			world._process(0.033)

		# 运行中途跳过
		world.skip_intro()
		eq(world._dolly, Vector2.ZERO, "Pointer %s 下 skip 后 _dolly 归零" % str(ptr))
		_assert_layers_integer_snapped(world, "Pointer %s 跳过瞬间" % str(ptr))

		# 维持此 pointer 跑 20 帧，视差图层必须全程严格整像素
		for step in 20:
			world._process(0.016)
			for layer in world.parallax_layers():
				var pos := layer.position
				eq(pos, pos.round(),
						"Pointer %s 持续第 %d 帧图层 '%s' 保持整像素" % [str(ptr), step, layer.name])

	await _free_world(world)
