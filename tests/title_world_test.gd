extends TestCase
## 标题活景（TitleWorld）：每种变体都能无报错地在 headless 里搭起来、灯 / 节点预算、
## 存档 → 变体的映射（无存档 / 每一幕 / 每个结局）、骑士穿着当前外观、齿轮循环无缝、
## 视差只走整数像素、USE_LIVE_SCENE 回退仍显示 keyart。

const TITLE_SCENE := "res://scenes/ui/TitleScreen.tscn"
const WORLD_SCENE := "res://scenes/ui/TitleWorld.tscn"
const SAVE_PATH := "user://title_world_test.cfg"


func setup() -> void:
	TitleWorld.forced_state = {}


func teardown() -> void:
	TitleWorld.forced_state = {}
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	SaveData.save_path = "user://rustgrave_save.cfg"


## A `peek` the way TitleWorld.peek_save() reports it.
func _peek(level_id: String = "", flags: Array = [], ending: String = "", has_save: bool = true,
		skin: String = "", origin: String = "") -> Dictionary:
	return {
		"has_save": has_save,
		"scene": String(GameContext.LEVELS[level_id]) if level_id != "" else "",
		"flags": PackedStringArray(flags),
		"ending": ending,
		"skin": skin,
		"origin": origin,
		"rank": 3,
		"points": 1,
	}


func _done_flags(count: int) -> Array:
	var out: Array = []
	for i in count:
		out.append(String(StoryFlow.DONE_FLAGS[GameContext.LEVEL_ORDER[i]]))
	return out


## Builds a TitleWorld inside its own SubViewport (the way TitleScreen hosts it).
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
	var vp := world.get_parent()
	vp.queue_free()
	await get_tree().process_frame


func _all_states() -> Array:
	var out: Array = []
	out.append(["cold", TitleWorld.build_state(_peek("", [], "", false))])
	for entry in [["act1", "level02", 2], ["act2", "level04", 4], ["act3", "level08", 8], ["act4", "level10", 13]]:
		out.append([entry[0], TitleWorld.build_state(_peek(entry[1], _done_flags(entry[2])))])
	for ending in ["give", "keep", "snuff"]:
		out.append([ending, TitleWorld.build_state(_peek("level10", _done_flags(14), ending))])
	return out


# --------------------------------------------------------------- the mapping ----

func test_acts_split_the_fourteen_chapters_as_1_3_4_7_8_11_12_14() -> void:
	var expected := [1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4]
	eq(GameContext.LEVEL_ORDER.size(), 14, "战役 14 章")
	for i in 14:
		eq(TitleWorld.act_of_index(i), int(expected[i]), "第 %d 章在第 %d 幕" % [i + 1, int(expected[i])])


func test_lit_lanterns_follow_cleared_chapters() -> void:
	var table := {0: 0, 1: 1, 2: 2, 3: 3, 5: 5, 6: 6, 8: 8, 9: 9, 11: 11, 12: 12, 14: 14}
	for cleared in table:
		eq(TitleWorld.lit_lantern_count(int(cleared)), int(table[cleared]), "通关 %d 章点亮几盏" % int(cleared))
	var previous := 0
	for cleared in 15:
		var n := TitleWorld.lit_lantern_count(cleared)
		ok(n >= previous and n <= TitleWorld.LANTERN_COUNT, "通关 %d 章：%d 盏，不倒退不超额" % [cleared, n])
		previous = n


func test_state_for_no_save_is_a_cold_forge() -> void:
	var s := TitleWorld.build_state(_peek("", [], "", false))
	eq(s["variant"], TitleWorld.VARIANT_COLD, "无存档 = 冷炉")
	eq(s["lit"], 0, "冷炉一盏灯都不亮")
	eq(s["cleared"], 0)
	eq(TitleWorld.grade_id(s), &"cold")


func test_state_for_a_journey_grades_by_act_and_counts_lanterns() -> void:
	# 刚开局（存档在第一章、什么都没通）
	var fresh := TitleWorld.build_state(_peek("level01"))
	eq(fresh["variant"], TitleWorld.VARIANT_JOURNEY)
	eq(fresh["act"], 1)
	eq(fresh["lit"], 0, "没通关任何一章，灯还没亮")
	eq(TitleWorld.grade_id(fresh), &"act1")
	# 每一幕取一个章：存档章节决定幕，通关旗标决定灯
	var cases := [["level02b", 2, 2, &"act1"], ["level03", 3, 3, &"act2"], ["level05", 6, 6, &"act2"],
			["level07", 8, 8, &"act3"], ["level08", 10, 10, &"act3"], ["level09", 11, 11, &"act4"],
			["level10", 13, 13, &"act4"]]
	for c in cases:
		var s := TitleWorld.build_state(_peek(String(c[0]), _done_flags(int(c[1]))))
		eq(s["cleared"], int(c[1]), "%s: 通关章数" % String(c[0]))
		eq(s["lit"], int(c[2]), "%s: 亮灯数" % String(c[0]))
		eq(TitleWorld.grade_id(s), c[3], "%s: 调色" % String(c[0]))
	# 通关旗标缺失时，存档章节之前的章也算通关（读档回到第五章，前四章必然过了）
	var inferred := TitleWorld.build_state(_peek("level04"))
	eq(inferred["cleared"], 4, "第五章之前的四章视为通关")
	var done: Array = inferred["done"]
	eq(done.size(), 14, "每章一个通关标记")
	ok(done[3] and not done[4], "第四个亮、第五个（当前章）不亮")


func test_state_for_each_ending() -> void:
	for ending in ["give", "keep", "snuff"]:
		var s := TitleWorld.build_state(_peek("level10", _done_flags(14), ending))
		eq(s["variant"], StringName(ending), "%s 变体" % ending)
		eq(s["act"], 4, "结局都在第四幕的终点")
		eq(s["cleared"], 14, "全部通关")
		eq(TitleWorld.grade_id(s), StringName(ending), "%s 有自己的调色" % ending)
	eq(TitleWorld.build_state(_peek("level10", [], "give"))["lit"], 14, "送剑：灯全亮")
	eq(TitleWorld.build_state(_peek("level10", [], "keep"))["lit"], 14, "守火：灯全亮")
	eq(TitleWorld.build_state(_peek("level10", [], "snuff"))["lit"], 0, "熄灭：灯全暗")
	# 没见过的结局 id（旧测试里写过 "purified"）按已完成处理，不崩
	eq(TitleWorld.build_state(_peek("level10", [], "purified"))["variant"], TitleWorld.VARIANT_GIVE)


func test_state_picks_the_saved_skin_or_the_origin_default() -> void:
	eq(TitleWorld.build_state(_peek("level01", [], "", true, "skin_gothic_hero"))["skin"], &"skin_gothic_hero")
	eq(TitleWorld.build_state(_peek("level01", [], "", true, "not_a_skin"))["skin"], SkinCatalog.DEFAULT_SKIN,
			"未知外观退回默认")
	eq(TitleWorld.build_state(_peek("level01", [], "", true, "", "rust_automaton"))["skin"],
			&"skin_cemetery_hero", "没选外观时跟随起源的默认外观")
	eq(TitleWorld.build_state(_peek("", [], "", false))["skin"], SkinCatalog.DEFAULT_SKIN, "无存档默认骑士")


## 真的存档文件 -> state_from_save()（标题启动时还没 load_game，必须自己读盘）。
func test_state_from_save_peeks_the_file_on_disk() -> void:
	var saved_flags := SaveData.flags.duplicate()
	var saved_skin := SaveData.skin_id
	SaveData.save_path = SAVE_PATH
	SaveData.delete_save()
	SaveData.ending = ""
	SaveData.flags = PackedStringArray()
	SaveData.skin_id = ""
	var empty := TitleWorld.state_from_save()
	eq(empty["variant"], TitleWorld.VARIANT_COLD, "没有存档文件 -> 冷炉")

	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 3)
	cfg.set_value("meta", "scene", String(GameContext.LEVELS["level05"]))
	cfg.set_value("player", "origin", "scrap_scavenger")
	cfg.set_value("story", "flags", _done_flags(6))
	cfg.set_value("profile", "ember_rank", 5)
	cfg.set_value("profile", "attribute_points", 2)
	cfg.set_value("profile", "skin_id", "skin_ash_runner")
	cfg.save(SAVE_PATH)
	var s := TitleWorld.state_from_save()
	eq(s["variant"], TitleWorld.VARIANT_JOURNEY, "读盘：旅程中")
	eq(s["chapter_id"], "level05", "读盘：存档章节")
	eq(s["cleared"], 6, "读盘：旗标里的通关数")
	eq(s["skin"], &"skin_ash_runner", "读盘：外观")
	eq(s["rank"], 5, "读盘：阶位")
	eq(s["points"], 2, "读盘：属性点")

	cfg.set_value("meta", "ending", "keep")
	cfg.save(SAVE_PATH)
	var ended := TitleWorld.state_from_save()
	eq(ended["variant"], TitleWorld.VARIANT_KEEP, "读盘：守火结局")

	# 强制状态（工具 / 测试用）压过存档
	TitleWorld.forced_state = TitleWorld.build_state(_peek("", [], "", false))
	eq(TitleWorld.state_from_save()["variant"], TitleWorld.VARIANT_COLD, "forced_state 优先")
	SaveData.flags = saved_flags
	SaveData.skin_id = saved_skin


# ------------------------------------------------------------------- building ----

func test_every_variant_builds_within_the_light_and_node_budget() -> void:
	for entry in _all_states():
		var label := String(entry[0])
		var world := _make_world(entry[1])
		await flush(6)
		ok(world.light_count() <= TitleWorld.MAX_LIGHTS, "%s: 灯 %d <= %d" % [label, world.light_count(), TitleWorld.MAX_LIGHTS])
		ok(world.node_count() <= 250, "%s: 节点 %d <= 250" % [label, world.node_count()])
		eq(world.lantern_count(), 14, "%s: 十四盏可见吊灯" % label)
		eq(world.lit_lanterns(), int(entry[1]["lit"]), "%s: 亮着的灯数 = 状态里的 lit" % label)
		ok(world.camera() != null, "%s: 活景自带 Camera2D" % label)
		var enabled := 0
		for lantern in world.lanterns():
			var light := lantern.light_node()
			if light == null:
				continue
			if light.enabled:
				enabled += 1
			ok(light.enabled == lantern.is_lit(), "%s: 灯亮 <=> 点光源开着" % label)
		ok(enabled <= 5, "%s: 十四盏灯共享不超过五个点光池" % label)
		ok(world.find_children("*", "LightOccluder2D", true, false).size() >= 2)
		ok((world.get_node("ShaftLight") as PointLight2D).shadow_enabled)
		ok((world.get_node("ForgeLight") as PointLight2D).shadow_enabled)
		await _free_world(world)


## 骑士穿着当前外观（帧、染色、巨剑）；每套皮肤都试一遍。
func test_the_knight_wears_the_current_skin() -> void:
	for skin in SkinCatalog.ids():
		var world := _make_world(TitleWorld.build_state(_peek("level04", _done_flags(4), "", true, String(skin))))
		await flush(3)
		var sprite := world.knight_sprite()
		ok(sprite != null, "%s: 骑士精灵存在" % String(skin))
		if sprite == null:
			await _free_world(world)
			continue
		var frames := SkinCatalog.frames_for(skin, &"idle")
		ok(not frames.is_empty(), "%s: 有待机帧" % String(skin))
		ok(frames.has(sprite.texture), "%s: 显示的是这套皮肤的待机帧" % String(skin))
		eq(sprite.modulate, SkinCatalog.tint_of(skin), "%s: 染色一致" % String(skin))
		almost(sprite.position.y, SkinCatalog.offset_for(skin, &"idle").y, 0.01, "%s: 基线偏移一致" % String(skin))
		var sword := world.knight().get_node_or_null("Visual/Greatsword") as Greatsword
		ok(sword != null and sword.is_showing(), "%s: 背着巨剑" % String(skin))
		await _free_world(world)


func test_each_variant_puts_the_right_actors_on_the_bridge() -> void:
	var cold := _make_world(TitleWorld.build_state(_peek("", [], "", false)))
	await flush(3)
	ok(cold.knight() != null and cold.planted_sword() == null and cold.nest() == null, "冷炉：只有骑士")
	await _free_world(cold)

	var give := _make_world(TitleWorld.build_state(_peek("level10", [], "give")))
	await flush(3)
	ok(give.knight() == null, "送剑：骑士不在了")
	ok(give.planted_sword() != null, "送剑：桥上只剩插着的巨剑")
	eq(give.sparks().active_count(TitleSparks.Kind.SPECK), TitleSparks.CAPS[TitleSparks.Kind.SPECK],
			"送剑：飘着一些锈屑")
	await _free_world(give)

	var keep := _make_world(TitleWorld.build_state(_peek("level10", [], "keep")))
	await flush(3)
	ok(keep.knight() != null, "守火：骑士在")
	ok(keep.knight().position.x > TitleWorld.KNIGHT_X + 40.0, "守火：骑士位于炉口那一端")
	eq(keep.knight_sprite().current(), "seated", "守火：专用坐姿，不再复用站立idle")
	ok(keep.knight_sprite().texture.resource_path.contains("seated_"))
	ok(keep.nest() != null, "守火：余烬巢点着")
	await _free_world(keep)

	var snuff := _make_world(TitleWorld.build_state(_peek("level10", [], "snuff")))
	await flush(3)
	ok(snuff.knight() == null and snuff.planted_sword() == null, "熄灭：桥上空了")
	eq(snuff.lit_lanterns(), 0, "熄灭：灯全暗")
	ok(snuff.get_node("ForgeLight").color.r > snuff.get_node("ForgeLight").color.g * 2.0, "熄灭：只剩一点将熄的红光")
	await _free_world(snuff)


## configure() 在搭好之后也能切换变体：旧演员被收走、新演员上场。
func test_configure_swaps_the_actors() -> void:
	var world := _make_world(TitleWorld.build_state(_peek("", [], "", false)))
	await flush(3)
	ok(world.knight() != null, "起初骑士在")
	world.configure(TitleWorld.build_state(_peek("level10", [], "give")))
	await flush(3)
	ok(world.knight() == null, "切到送剑后骑士被收走")
	ok(world.planted_sword() != null, "巨剑插上了")
	world.configure(TitleWorld.build_state(_peek("level04", _done_flags(4))))
	await flush(3)
	ok(world.knight() != null and world.planted_sword() == null, "回到旅程：骑士回来，巨剑收走")
	eq(world.lit_lanterns(), 4, "亮灯数跟着状态走")
	await _free_world(world)


# ----------------------------------------------------------------- the motion ----

## 齿轮的帧覆盖整整一个辐条周期：转满一个周期正好回到起始帧（循环无缝），且不越界。
func test_gears_loop_seamlessly_over_one_spoke_period() -> void:
	var world := _make_world(TitleWorld.build_state(_peek("level04", _done_flags(4))))
	await flush(2)
	ok(world.gears().size() >= 3, "至少三个齿轮")
	for gear in world.gears():
		var start := gear.frame
		var seconds := gear.period_degrees / (gear.speed * gear.speed_mult) if gear.speed_mult > 0.0 else 0.0
		ok(seconds > 0.0, "%s 在转" % String(gear.name))
		var seen := {}
		var t := 0.0
		var angle0 := gear.angle()
		while t < seconds - 0.001:
			gear._process(0.05)
			t += 0.05
			seen[gear.frame] = true
			ok(gear.frame >= 0 and gear.frame < gear.frame_count(), "%s 帧不越界" % String(gear.name))
		gear._process(seconds - t)
		# compare modulo the period: landing a hair either side of the wrap is still a closed loop
		var diff := fposmod(gear.angle() - angle0 + gear.period_degrees * 0.5, gear.period_degrees) \
				- gear.period_degrees * 0.5
		almost(diff, 0.0, 0.05, "%s 转满一周期回到原角度" % String(gear.name))
		var dframe := posmod(gear.frame - start, gear.frame_count())
		ok(dframe == 0 or dframe == 1 or dframe == gear.frame_count() - 1,
				"%s 转满一周期回到起始帧（差 %d）" % [String(gear.name), dframe])
		ok(seen.size() >= gear.frame_count() - 2, "%s 走遍了各帧 (%d/%d)" % [String(gear.name), seen.size(), gear.frame_count()])
		ok(gear.hframes * gear.vframes >= gear.frame_count(), "%s 的网格装得下全部帧" % String(gear.name))
		ok(gear.texture.get_width() <= 2048 and gear.texture.get_height() <= 2048, "%s 贴图尺寸友好" % String(gear.name))
	await _free_world(world)


func test_cold_forge_gears_barely_turn_and_a_snuffed_one_stops() -> void:
	var cold := _make_world(TitleWorld.build_state(_peek("", [], "", false)))
	var snuff := _make_world(TitleWorld.build_state(_peek("level10", [], "snuff")))
	var act3 := _make_world(TitleWorld.build_state(_peek("level08", _done_flags(8))))
	await flush(2)
	ok(cold.gears()[0].speed_mult < act3.gears()[0].speed_mult * 0.5, "冷炉的齿轮比第三幕慢得多")
	almost(snuff.gears()[0].speed_mult, 0.0, 0.0001, "熄灭的炉：齿轮不转")
	await _free_world(cold)
	await _free_world(snuff)
	await _free_world(act3)


## 视差走整数像素：指针推到边上，每一层的位置和摄像机偏移都是整数，且不超出振幅。
func test_parallax_and_camera_move_in_whole_pixels() -> void:
	var world := _make_world(TitleWorld.build_state(_peek("level04", _done_flags(4))))
	await flush(2)
	for pointer in [Vector2(1, 1), Vector2(-1, 0.4), Vector2(0.37, -0.81)]:
		world.set_pointer(pointer)
		for i in 90:
			world._process(1.0 / 60.0)
		world.nudge(1.0)
		world._process(1.0 / 60.0)
		for layer in world.parallax_layers():
			ok(layer.position == layer.position.round(), "%s 位置是整数像素 %s" % [String(layer.name), layer.position])
		var cam := world.camera_offset()
		ok(cam == cam.round(), "摄像机偏移是整数像素 %s" % cam)
		ok(absf(cam.y) <= 1.0, "摄像机呼吸不超过 1px")
	# 指针居中、没有推力 -> 回到基准位置（呼吸除外）
	world.set_pointer(Vector2.ZERO)
	world._push_kick = 0.0
	for i in 400:
		world._process(1.0 / 60.0)
	var roof := world.get_node("Roof") as Node2D
	ok(roof.position.is_equal_approx(Vector2(-32.0, -10.0)), "指针归中后屋顶回到基准位 %s" % roof.position)
	# 近景（山体）比远景（厅尾）动得多
	world.set_pointer(Vector2(1, 0))
	for i in 240:
		world._process(1.0 / 60.0)
	var near_shift: float = absf((world.get_node("MassLeft") as Node2D).position.x - TitleWorld.MASS_LEFT_POS.x)
	var far_shift: float = absf((world.get_node("HallFar") as Node2D).position.x - (-32.0))
	ok(near_shift > far_shift * 1.5, "近景位移 %.0f 大于远景 %.0f" % [near_shift, far_shift])
	await _free_world(world)


## 开屏：黑起 -> 灯逐盏亮；跳过 = 直接落到终态；退场 = 灯逐盏灭。
func test_intro_lights_come_on_one_by_one_and_skip_lands_the_final_state() -> void:
	var state := TitleWorld.build_state(_peek("level08", _done_flags(8)))
	var world := _make_world(state)
	await flush(2)
	var want: int = state["lit"]
	ok(want >= 3, "测试用例有足够多的亮灯")
	eq(world.lit_lanterns(), want, "搭好即终态")
	var duration := world.play_intro(0.2)
	ok(duration > 0.8, "开屏有时长 (%.2f)" % duration)
	eq(world.lit_lanterns(), 0, "开屏一开始灯全是暗的")
	# one by one: frame by frame we must see an in-between count (not 0 -> all at once)
	var seen := {}
	var intro_wait := get_tree().create_timer(duration + 0.4)
	while intro_wait.time_left > 0.0:
		await get_tree().process_frame
		seen[world.lit_lanterns()] = true
	var intermediate := false
	for n in seen:
		if int(n) >= 1 and int(n) < want:
			intermediate = true
	ok(intermediate, "开屏是逐盏点亮的，看到过的亮灯数：%s" % str(seen.keys()))
	eq(world.lit_lanterns(), want, "开屏结束时灯数 = 状态里的 lit")
	world.skip_intro()
	eq(world.lit_lanterns(), want, "跳过开屏直接落到终态")
	ok(world._intro_level >= 1.0, "环境光回到满")
	var out := world.quit_out(0.1)
	ok(out > 0.5, "退场有时长")
	var seen_out := {}
	var outro_wait := get_tree().create_timer(out + 0.4)
	while outro_wait.time_left > 0.0:
		await get_tree().process_frame
		seen_out[world.lit_lanterns()] = true
	var intermediate_out := false
	for n in seen_out:
		if int(n) >= 1 and int(n) < want:
			intermediate_out = true
	ok(intermediate_out, "退场是逐盏熄灭的，看到过的亮灯数：%s" % str(seen_out.keys()))
	eq(world.lit_lanterns(), 0, "退场后灯全灭")
	await _free_world(world)


func test_particles_stay_inside_their_pools() -> void:
	var world := _make_world(TitleWorld.build_state(_peek("level10", _done_flags(13))))
	await flush(30)
	var nodes_before := world.node_count()
	for _i in 300:
		world._process(1.0 / 60.0)
	eq(world.node_count(), nodes_before, "连续跑 300 帧节点数不增长")
	var sparks := world.sparks()
	var total := 0
	for cap in TitleSparks.CAPS:
		total += int(cap)
	ok(sparks.live_count() <= total, "活着的粒子 %d <= 池容量 %d" % [sparks.live_count(), total])
	ok(sparks.active_count(TitleSparks.Kind.EMBER) > 0, "第四幕有余烬")
	sparks.burst(Vector2(320, 200), 500)
	ok(sparks.live_count() <= total, "一次大迸发也不超出池 (%d)" % sparks.live_count())
	ok(sparks.puff_count() <= TitleSparks.MAX_PUFFS, "蒸汽不超出池")
	await _free_world(world)


# --------------------------------------------------------------- the screen -----

func _open_title(live: bool = true) -> TitleScreen:
	var packed := load(TITLE_SCENE) as PackedScene
	var title := packed.instantiate() as TitleScreen
	title.live_scene_enabled = live
	add_child(title)
	await get_tree().process_frame
	await get_tree().process_frame
	return title


## Keyart 节点（名字、类、拉伸模式是测试和工具依赖的）显示的是活景的视口贴图，
## 视口按世界视口的写法搭：640x360、整数像素、最近邻。
func test_the_keyart_node_shows_the_live_viewport() -> void:
	var title: TitleScreen = await _open_title(true)
	var keyart := title.get_node_or_null("Keyart") as TextureRect
	ok(keyart != null, "Keyart 还在")
	eq(int(keyart.stretch_mode), int(TextureRect.STRETCH_KEEP_ASPECT_COVERED), "任何比例都铺满")
	ok(keyart.texture is ViewportTexture, "Keyart 显示的是视口贴图")
	var vp := title.get_node_or_null("WorldViewport") as SubViewport
	ok(vp != null, "世界视口存在")
	if vp != null:
		var metrics := PresentationMetrics.for_window(get_tree().root)
		eq(vp.size, PresentationMetrics.world_render_size(metrics), "视口使用原生物理采样")
		eq(vp.size_2d_override, metrics["world_size"], "逻辑视野与分辨率适配保持一致")
		ok(vp.snap_2d_transforms_to_pixel, "整数像素对齐")
		eq(int(vp.canvas_item_default_texture_filter), int(Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST), "最近邻")
		eq(int(vp.render_target_update_mode), int(SubViewport.UPDATE_ALWAYS), "可见时每帧渲染")
		ok(vp.world_2d != get_viewport().world_2d, "自己的 World2D（灯光不会漏进别处）")
	ok(keyart.material is ShaderMaterial, "套着像素平滑着色器")
	var material := keyart.material as ShaderMaterial
	eq(int(material.get_shader_parameter("scale_hint")), 1, "原生采样不再执行低分辨率重建")
	ok(title.world() != null, "标题持有活景")
	# 看不见时不再渲染
	title.visible = false
	await get_tree().process_frame
	eq(int(vp.render_target_update_mode), int(SubViewport.UPDATE_DISABLED), "隐藏后停止渲染")
	title.visible = true
	await get_tree().process_frame
	eq(int(vp.render_target_update_mode), int(SubViewport.UPDATE_ALWAYS), "再显示就恢复")
	title.queue_free()
	await get_tree().process_frame


## USE_LIVE_SCENE=false：回到旧的静态 keyart，同一个 Keyart 节点，不建视口。
func test_without_the_live_scene_the_old_keyart_is_shown() -> void:
	ok(TitleScreen.USE_LIVE_SCENE, "默认开着活景")
	var title: TitleScreen = await _open_title(false)
	var keyart := title.get_node_or_null("Keyart") as TextureRect
	ok(keyart != null, "回退模式也有 Keyart")
	ok(keyart.texture != null and not (keyart.texture is ViewportTexture), "显示的是静态贴图")
	eq(keyart.texture.resource_path, TitleScreen.KEYART_PATH, "就是旧 keyart")
	eq(int(keyart.stretch_mode), int(TextureRect.STRETCH_KEEP_ASPECT_COVERED), "拉伸模式不变")
	ok(title.get_node_or_null("WorldViewport") == null, "回退模式不建世界视口")
	ok(title.world() == null, "回退模式没有活景")
	ok(title.get_node("Menu") is MenuList and title.find_child("Masthead", true, false) != null, "版式照常")
	# 回退模式下开屏 / 跳过 / 离开都照走
	title.quit_on_finish = false
	title._skip_intro()
	ok(not title.intro_playing(), "回退模式可跳过开屏")
	title._on_chosen(&"quit")
	title._finish_quit()
	ok(title.quit_finished(), "回退模式可退出")
	title.queue_free()
	await get_tree().process_frame


func test_the_title_hands_its_look_to_the_world() -> void:
	TitleWorld.forced_state = TitleWorld.build_state(_peek("level10", [], "snuff"))
	var title: TitleScreen = await _open_title(true)
	eq(title.world().variant(), TitleWorld.VARIANT_SNUFF, "活景按存档状态搭起来")
	eq(title.look()["variant"], TitleWorld.VARIANT_SNUFF, "标题也持有同一份状态")
	title.queue_free()
	await get_tree().process_frame


## 音频钩子：有 set_title_bed / Sfx.LIBRARY[&"bed_title"] 就启动（别的 agent 会加）；没有就什么都不做，不报错。
func test_the_title_bed_hook_is_feature_detected() -> void:
	var title: TitleScreen = await _open_title(true)
	if Sfx.has_method(&"set_title_bed") or Sfx.LIBRARY.has(&"bed_title"):
		ok(true, "音频包已提供 bed_title / set_title_bed")
	else:
		ok(true, "音频包还没有 bed_title：标题照常打开")
	title.queue_free()
	await get_tree().process_frame
	ok(true, "关闭也不报错")
