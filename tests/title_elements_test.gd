extends TestCase
## 标题活景的新增元素（吊运坩埚 / 远处锻锤 / 送剑链 / 魂光 / 破旗 / 桥头火盆 / 光柱云影 /
## 亡魂巡行 / 骑士转身望炉）与菜单聚焦联动（TitleWorld.react_to）：
##   · 预算：每个存档变体下灯 ≤ 8、节点 ≤ 250，新元素不加 PointLight2D、每件 ≤ 3 个节点、光感是加色精灵；
##   · 各变体的状态：give 链停空 + 魂光升出屋顶，snuff 全暗全停，keep 火盆最亮，旅程按进度点亮火盆；
##   · 每个元素真的会动（倒铁水 / 砸坯料 / 送剑进炉 / 亡魂走动 / 骑士转身），整像素；
##   · react_to：七个菜单 id 各有一个看得见的状态变化，未知 id 不报错也不改任何东西；
##   · 页脚说明：每个菜单 id 都有一句 ≤ 24 字的说明，焦点移到哪行就写哪行。

const TITLE_SCENE := "res://scenes/ui/TitleScreen.tscn"
const WORLD_SCENE := "res://scenes/ui/TitleWorld.tscn"
const SwordChain := preload("res://scripts/ui/title_sword_chain.gd")
const Crucible := preload("res://scripts/ui/title_crucible.gd")
const Souls := preload("res://scripts/ui/title_souls.gd")


func setup() -> void:
	TitleWorld.forced_state = {}


func teardown() -> void:
	TitleWorld.forced_state = {}


## A `peek` the way TitleWorld.peek_save() reports it.
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


## 通关 `cleared` 章的旅程（存档停在下一章）。
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
	world.get_parent().queue_free()
	await get_tree().process_frame


## 直接驱动世界的 _process（不等引擎帧）：seconds 秒，每步 step 秒。
func _steps(world: TitleWorld, seconds: float, step: float = 0.05) -> void:
	var t := 0.0
	while t < seconds:
		world._process(step)
		t += step


# ---------------------------------------------------------------- the plan ----

func test_the_plan_for_each_variant() -> void:
	var cold := TitleWorld.prop_plan(_state("cold"))
	eq(cold["chain_mode"], SwordChain.MODE_RUN, "冷炉：链还在（慢）")
	eq(cold["braziers"], [0.0, 0.0], "冷炉：火盆都是冷的")
	eq(cold["ghosts"], 1, "冷炉：只有一个亡魂")
	ok(not bool(cold["souls_escape"]), "冷炉：魂光出不去")
	ok(bool(cold["knight_turns"]), "冷炉：骑士会转身望炉")

	var give := TitleWorld.prop_plan(_state("give"))
	eq(give["chain_mode"], SwordChain.MODE_EMPTY, "还火：链停空")
	eq(give["ghosts"], 0, "还火：亡魂走了")
	ok(bool(give["souls_escape"]), "还火：魂光升出屋顶")
	almost(float(give["souls_rate"]), 1.0, 0.0001, "还火：魂光最多")
	eq(give["braziers"], [0.9, 0.9], "还火：火盆稳稳亮着")
	ok(not bool(give["knight_turns"]), "还火：骑士不在了")

	var keep := TitleWorld.prop_plan(_state("keep"))
	eq(keep["chain_mode"], SwordChain.MODE_RUN, "守炉：链照转")
	eq(keep["ghosts"], 3, "守炉：亡魂还在排队")
	ok(not bool(keep["souls_escape"]), "守炉：魂光还困着")
	eq(keep["braziers"], [1.3, 1.3], "守炉：火盆最亮")
	ok(not bool(keep["knight_turns"]), "守炉：骑士一直看着火")

	var snuff := TitleWorld.prop_plan(_state("snuff"))
	eq(snuff["chain_mode"], SwordChain.MODE_STILL, "熄火：链停住")
	eq(snuff["ghosts"], 0)
	almost(float(snuff["souls_rate"]), 0.0, 0.0001, "熄火：没有魂光")
	eq(snuff["braziers"], [0.0, 0.0], "熄火：火盆全暗")


func test_the_braziers_light_with_progress_and_keep_is_the_brightest() -> void:
	var previous: Array = [0.0, 0.0]
	var ghosts_before := 0
	var souls_before := 0.0
	for cleared in 15:
		var plan := TitleWorld.prop_plan(_journey(mini(cleared, 14)))
		var levels: Array = plan["braziers"]
		if cleared == 0:
			eq(levels, [0.0, 0.0], "一章没通：火盆没点")
		if cleared >= TitleWorld.BRAZIER_FIRST_AT:
			ok(float(levels[0]) > 0.0, "通关 %d 章：第一座亮" % cleared)
		if cleared >= TitleWorld.BRAZIER_SECOND_AT:
			ok(float(levels[1]) > 0.0, "通关 %d 章：第二座也亮" % cleared)
		elif cleared > 0:
			almost(float(levels[1]), 0.0, 0.0001, "通关 %d 章：第二座还没亮" % cleared)
		ok(float(levels[0]) >= float(previous[0]) and float(levels[1]) >= float(previous[1]),
				"火盆随进度只增不减 (%d)" % cleared)
		ok(int(plan["ghosts"]) >= ghosts_before, "亡魂数只增不减 (%d)" % cleared)
		ok(float(plan["souls_rate"]) >= souls_before - 0.0001, "魂光只增不减 (%d)" % cleared)
		previous = levels
		ghosts_before = int(plan["ghosts"])
		souls_before = float(plan["souls_rate"])
	var keep_levels: Array = TitleWorld.prop_plan(_state("keep"))["braziers"]
	for other in ["cold", "act1", "act2", "act3", "act4", "give", "snuff"]:
		var levels: Array = TitleWorld.prop_plan(_state(other))["braziers"]
		ok(float(keep_levels[0]) >= float(levels[0]) and float(keep_levels[1]) >= float(levels[1]),
				"守炉的火盆不暗于 %s 的" % other)
	ok(float(keep_levels[0]) > 1.0, "守炉的火盆在「最亮」一档（> 1）")


# ----------------------------------------------------------------- budgets ----

func test_every_variant_stays_inside_the_budget_with_the_new_elements() -> void:
	for variant_id in _all_variants():
		var world := _make_world(_state(variant_id))
		await flush(4)
		ok(world.light_count() <= TitleWorld.MAX_LIGHTS, "%s: 灯 %d <= 8" % [variant_id, world.light_count()])
		ok(world.node_count() <= 250, "%s: 节点 %d <= 250" % [variant_id, world.node_count()])
		ok(world.node_count() <= 150, "%s: 新元素之后仍留有余量 (%d)" % [variant_id, world.node_count()])
		eq(world.lantern_count(), 14, "%s: 十四盏可见吊灯" % variant_id)
		var props := world.prop_nodes()
		eq(props.size(), 7, "%s: 坩埚 / 锻锤 / 亡魂 / 火盆 / 两面旗 / 送剑链" % variant_id)
		for prop in props:
			var count: int = prop.find_children("*", "", true, false).size() + 1
			ok(count <= 3, "%s: %s 只用 %d 个节点（<= 3）" % [variant_id, String(prop.name), count])
			ok(prop.find_children("*", "PointLight2D", true, false).is_empty(),
					"%s: %s 不加 PointLight2D" % [variant_id, String(prop.name)])
			var glow: Node2D = prop.glow_node()
			if glow != null:
				ok(glow.material == Fx.additive_mat(), "%s: %s 的光感是加色精灵" % [variant_id, String(prop.name)])
		ok(world.souls().material == Fx.additive_mat(), "%s: 魂光是加色的" % variant_id)
		await _free_world(world)


func test_the_scene_matches_the_plan_for_every_variant() -> void:
	for variant_id in _all_variants():
		var state := _state(variant_id)
		var plan := TitleWorld.prop_plan(state)
		var world := _make_world(state)
		await flush(3)
		eq(world.plan(), plan, "%s: 场景用的就是 prop_plan" % variant_id)
		eq(world.ghosts().count(), int(plan["ghosts"]), "%s: 亡魂数" % variant_id)
		eq(world.sword_chain().mode(), int(plan["chain_mode"]), "%s: 链的模式" % variant_id)
		eq(world.braziers().levels(), [float(plan["braziers"][0]), float(plan["braziers"][1])],
				"%s: 火盆亮度" % variant_id)
		eq(world.souls().target_count(), int(roundf(float(plan["souls_rate"]) * float(Souls.CAP))),
				"%s: 魂光名额" % variant_id)
		eq(world.souls().is_escaping(), bool(plan["souls_escape"]), "%s: 魂光是否逃出屋顶" % variant_id)
		await _free_world(world)


func test_configure_switches_the_new_elements_too() -> void:
	var world := _make_world(_state("act2"))
	await flush(3)
	eq(world.sword_chain().mode(), SwordChain.MODE_RUN)
	world.configure(_state("give"))
	await flush(2)
	eq(world.sword_chain().mode(), SwordChain.MODE_EMPTY, "切到还火：链停空")
	eq(world.ghosts().count(), 0, "切到还火：亡魂走了")
	ok(world.souls().is_escaping(), "切到还火：魂光升出屋顶")
	world.configure(_state("snuff"))
	await flush(2)
	eq(world.braziers().lit_count(), 0, "切到熄火：火盆全暗")
	eq(world.souls().live_count(), 0, "切到熄火：魂光一个不剩")
	world.configure(_state("keep"))
	await flush(2)
	eq(world.ghosts().count(), 3, "切到守炉：亡魂排起队")
	await _free_world(world)


# ----------------------------------------------------------- the variants ----

func test_give_hangs_the_chain_empty_and_the_souls_rise_out_through_the_roof() -> void:
	var give := _make_world(_state("give"))
	var journey := _make_world(_state("act2"))
	await flush(3)
	var chain = give.sword_chain()
	eq(chain.visible_swords(), 0, "还火：链上一把剑也没有")
	ok(not chain.is_moving(), "还火：链不再转")
	var roll: float = chain.roll()
	chain.advance(12.0)
	almost(chain.roll(), roll, 0.0001, "还火：链停空，位置不变")
	# 魂光：还火的魂一路升出屋顶，旅程里的魂只浮起一小段就淡掉。
	give.souls().advance(14.0)
	journey.souls().advance(14.0)
	ok(give.souls().live_count() > 0, "还火：有魂光在升")
	ok(journey.souls().live_count() > 0, "旅程中：也有魂光（只是出不去）")
	ok(give.souls().highest_y() < 200.0, "还火：最高的魂光已经升到半空以上 (y=%.0f)" % give.souls().highest_y())
	ok(journey.souls().highest_y() > 215.0, "旅程中：魂光只浮起一小段 (y=%.0f)" % journey.souls().highest_y())
	await _free_world(give)
	await _free_world(journey)


func test_snuff_is_dark_and_still() -> void:
	var world := _make_world(_state("snuff"))
	await flush(3)
	world._process(0.1)
	var crucible = world.crucible()
	var hammer = world.hammer()
	almost(crucible.speed(), 0.0, 0.0001, "熄火：坩埚不动")
	ok(hammer.is_frozen(), "熄火：锻锤不动")
	ok(not world.sword_chain().is_moving(), "熄火：送剑链停住")
	eq(world.sword_chain().visible_swords(), 3, "熄火：剑还挂着")
	eq(world.braziers().lit_count(), 0, "熄火：火盆全暗")
	eq(world.ghosts().count(), 0, "熄火：没有亡魂")
	eq(world.souls().live_count(), 0, "熄火：没有魂光")
	var phase: int = crucible.phase()
	var x: float = crucible.trolley_x()
	crucible.advance(30.0)
	hammer.advance(30.0)
	eq(crucible.phase(), phase, "熄火：坩埚停在原地（阶段）")
	almost(crucible.trolley_x(), x, 0.0001, "熄火：坩埚停在原地（位置）")
	eq(hammer.strikes(), 0, "熄火：锻锤一下也没砸")
	eq(crucible.pour_count(), 0, "熄火：没倒过铁水")
	hammer.strike_now()
	hammer.advance(5.0)
	eq(hammer.strikes(), 0, "熄火：叫它敲也敲不动（炉子是冷的）")
	eq(hammer.strike_requests(), 1, "熄火：但请求记下了")
	await _free_world(world)


func test_keep_has_the_brightest_braziers_and_the_knight_always_looks_at_the_fire() -> void:
	var keep := _make_world(_state("keep"))
	var give := _make_world(_state("give"))
	var act4 := _make_world(_state("act4"))
	await flush(3)
	var best: float = keep.braziers().brightest()
	ok(best > float(give.braziers().brightest()), "守炉的火盆比还火的亮")
	ok(best > float(act4.braziers().brightest()), "守炉的火盆比第四幕的亮")
	eq(keep.knight_facing(), 1, "守炉：骑士一直朝着炉火")
	keep._gaze_wait = 0.0
	keep._process(0.1)
	eq(keep.knight_facing(), 1, "守炉：不会转开")
	eq(give.knight_facing(), 0, "还火：桥上没有骑士")
	await _free_world(keep)
	await _free_world(give)
	await _free_world(act4)


# --------------------------------------------------------- things that move ----

func test_the_crucible_walks_pours_and_goes_back() -> void:
	var world := _make_world(_state("act3"))
	await flush(3)
	world._process(0.05)
	var crucible = world.crucible()
	ok(crucible.speed() > 0.9, "第三幕：坩埚按标称速度走 (%.2f)" % crucible.speed())
	var landed := [0]
	var flare_at_landing := [0.0]
	crucible.poured.connect(func(_at: Vector2) -> void:
		landed[0] += 1
		flare_at_landing[0] = world._flare)
	var seen := {}
	var lo := 100000.0
	var hi := -100000.0
	for i in 400:
		crucible.advance(0.1)
		seen[crucible.phase()] = true
		lo = minf(lo, crucible.trolley_x())
		hi = maxf(hi, crucible.trolley_x())
		if crucible.is_pouring():
			ok(crucible.stream_length() <= crucible.stream_max() + 0.001, "铁水柱不会长过河面")
	ok(landed[0] >= 1, "倒过铁水（%d 次）" % landed[0])
	eq(crucible.pour_count(), landed[0], "poured 信号与计数一致")
	ok(float(flare_at_landing[0]) >= 0.5, "铁水落到河面时炉光闪了一下 (%.2f)" % float(flare_at_landing[0]))
	for phase in [Crucible.Phase.LOAD, Crucible.Phase.TO_POUR, Crucible.Phase.TILT, Crucible.Phase.POUR,
			Crucible.Phase.UNTILT, Crucible.Phase.TO_LOAD]:
		ok(seen.has(phase), "走过了阶段 %d" % phase)
	almost(lo, Crucible.POUR_X, 0.5, "最近走到倒铁水的位置")
	almost(hi, Crucible.LOAD_X, 0.5, "最远回到装料位")
	# force_pour：不在倒的时候直接跳到倾转
	var guard := 0
	while guard < 100 and crucible.phase() in [Crucible.Phase.TILT, Crucible.Phase.POUR, Crucible.Phase.UNTILT]:
		crucible.advance(0.1)
		guard += 1
	crucible.force_pour()
	eq(crucible.phase(), Crucible.Phase.TILT, "force_pour 直接倾转")
	await _free_world(world)


func test_the_hammer_strikes_throws_sparks_and_heats_the_billet() -> void:
	var world := _make_world(_state("act3"))
	await flush(3)
	world._process(0.05)
	var hammer = world.hammer()
	ok(not hammer.is_frozen(), "第三幕：锻锤在动")
	var flare_at_strike := [0.0]
	hammer.struck.connect(func(_at: Vector2) -> void: flare_at_strike[0] = world._flare)
	var guard := 0
	while hammer.strikes() == 0 and guard < 400:
		hammer.advance(0.05)
		guard += 1
	eq(hammer.strikes(), 1, "第一下砸下去了")
	ok(hammer.billet_level() > 0.9, "砸完坯料是白热的 (%.2f)" % hammer.billet_level())
	ok(float(flare_at_strike[0]) >= 0.3, "落砧时炉光闪了一下")
	hammer.advance(2.5)
	ok(hammer.billet_level() < 0.95, "之后慢慢暗下去")
	ok(hammer.head() >= 0.0 and hammer.head() <= 1.0, "锤头位置在 0..1")
	hammer.advance(12.0)
	ok(hammer.strikes() >= 3, "周期性地砸（%d 下）" % hammer.strikes())
	await _free_world(world)


func test_the_sword_chain_feeds_named_swords_into_the_furnace() -> void:
	var world := _make_world(_state("act3"))
	await flush(3)
	world._process(0.05)
	var chain = world.sword_chain()
	ok(chain.is_moving(), "第三幕：链在转")
	eq(chain.visible_swords(), 3, "三把剑挂在链上")
	var length: float = SwordChain.path_length()
	var delivered := [0]
	chain.delivered.connect(func(_at: Vector2) -> void: delivered[0] += 1)
	var flare_seen := [0.0]
	for i in 1500:
		chain.advance(0.1)
		flare_seen[0] = maxf(float(flare_seen[0]), world._flare)
		if i % 50 == 0:
			for k in 3:
				var s: float = chain.sword_s(k)
				ok(s >= 0.0 and s < length, "剑的路程在一圈之内")
	ok(delivered[0] >= 2, "送进炉里的剑 >= 2 把 (%d)" % delivered[0])
	eq(chain.deliveries(), delivered[0], "计数与信号一致")
	ok(float(flare_seen[0]) >= 0.4, "每把剑进炉，炉光闪一下")
	var gap := fposmod(chain.sword_s(1) - chain.sword_s(0), length)
	almost(gap, length / 3.0, 0.01, "剑与剑等距")
	# 路线：先水平后垂直，拐角在炉口上方
	var corner := SwordChain.point_at(SwordChain.X_END - SwordChain.X_START)
	almost(corner.x, SwordChain.X_END, 0.001, "拐角在炉口上方")
	almost(corner.y, SwordChain.RAIL_Y, 0.001)
	await _free_world(world)


func test_the_banners_sway_in_whole_pixels_and_a_gust_widens_the_swing() -> void:
	var world := _make_world(_state("act3"))
	var snuff := _make_world(_state("snuff"))
	await flush(3)
	world._process(0.05)
	snuff._process(0.05)
	var banners := world.banners()
	eq(banners.size(), 2, "两面破旗")
	var calm: float = banners[0].amplitude()
	var moved := {}
	for i in 60:
		banners[0].advance(0.1)
		for row in 11:
			var shift = banners[0].shift_of(row)
			ok(shift is int, "横向位移是整数像素")
			moved[shift] = true
	ok(moved.size() > 1, "旗布真的在摆")
	world.react_to(&"controls")
	world._process(0.05)
	ok(banners[0].amplitude() > calm + 1.5, "一阵风：摆幅变大 (%.1f -> %.1f)" % [calm, banners[0].amplitude()])
	ok(snuff.banners()[0].amplitude() < calm * 0.6, "熄火：旗布是软的 (%.1f)" % snuff.banners()[0].amplitude())
	await _free_world(world)
	await _free_world(snuff)


func test_the_ghosts_walk_toward_the_furnace_along_the_far_catwalk() -> void:
	var world := _make_world(_state("keep"))
	var give := _make_world(_state("give"))
	await flush(3)
	var ghosts = world.ghosts()
	eq(ghosts.count(), 3)
	var loop: float = ghosts.loop_length()
	for i in 3:
		var x: float = ghosts.ghost_x(i)
		ok(x >= ghosts.X_LEFT and x < ghosts.X_RIGHT, "亡魂 %d 在栈桥上 (%.0f)" % [i, x])
	var before: float = ghosts.ghost_x(0)
	ghosts.advance(10.0)
	var moved := fposmod(float(ghosts.ghost_x(0)) - before, loop)
	ok(moved > 30.0 and moved < 200.0, "10 秒往炉口方向挪了一小段 (%.0f px)" % moved)
	almost(fposmod(float(ghosts.ghost_x(1)) - float(ghosts.ghost_x(0)), loop), loop / 3.0, 0.01, "亡魂等距排队")
	var still: float = give.ghosts().walked()
	give.ghosts().advance(10.0)
	almost(float(give.ghosts().walked()), still, 0.0001, "没有亡魂的变体不走动")
	await _free_world(world)
	await _free_world(give)


func test_the_knight_turns_to_look_at_the_furnace_now_and_then() -> void:
	var world := _make_world(_state("act2"))
	await flush(3)
	eq(world.knight_facing(), -1, "平时背朝炉火站着")
	world._gaze_wait = 0.1
	world._process(0.2)
	eq(world.knight_facing(), 1, "到点了转身望炉")
	ok(bool(world.reaction_state()["gazing"]), "状态里记着他在望")
	_steps(world, TitleWorld.GAZE_HOLD + 0.5)
	eq(world.knight_facing(), -1, "望够了转回去")
	# 聚焦「继续」时也会转
	world.react_to(&"continue")
	eq(world.knight_facing(), 1, "聚焦继续：转身望炉")
	# 退场：转回朝右（留着的巨剑剪影是没镜像的那一幅）
	world.quit_out(0.1)
	eq(world.knight_facing(), 1, "退场：朝着炉火")
	await _free_world(world)


func test_the_light_shaft_breathes_with_cloud_shade() -> void:
	var lo := 10.0
	var hi := -10.0
	for i in 400:
		var shade := TitleWorld.cloud_shade(float(i) * 0.05)
		lo = minf(lo, shade)
		hi = maxf(hi, shade)
		ok(shade >= 1.0 - TitleWorld.CLOUD_DEPTH - 0.0001 and shade <= 1.0 + 0.0001, "遮蔽系数在范围内")
	ok(lo < 0.85 and hi > 0.95, "云影有明有暗 (%.2f..%.2f)" % [lo, hi])
	var world := _make_world(_state("act2"))
	await flush(3)
	var seen_lo := 10.0
	var seen_hi := -10.0
	for i in 60:
		_steps(world, 0.5, 0.1)
		seen_lo = minf(seen_lo, world.shaft_alpha())
		seen_hi = maxf(seen_hi, world.shaft_alpha())
	ok(seen_hi - seen_lo > 0.02, "光柱的明暗真的在变 (%.3f..%.3f)" % [seen_lo, seen_hi])
	await _free_world(world)


func test_everything_new_is_placed_on_whole_pixels() -> void:
	var world := _make_world(_state("act3"))
	await flush(3)
	world.set_pointer(Vector2(0.37, -0.81))
	_steps(world, 3.0, 0.05)
	for layer in world.parallax_layers():
		ok(layer.position == layer.position.round(), "%s 位置是整数像素 %s" % [String(layer.name), layer.position])
	for banner in world.banners():
		ok(banner.position == banner.position.round(), "旗的位置是整数像素")
	ok(world.hammer().position == world.hammer().position.round(), "锻锤的位置是整数像素")
	await _free_world(world)


# ---------------------------------------------------------------- reactions ----

func test_every_menu_id_has_a_reaction_with_an_observable_change() -> void:
	for variant_id in ["act2", "snuff"]:
		for id in TitleWorld.REACTIONS:
			var world := _make_world(_state(variant_id))
			await flush(3)
			world._process(0.05)
			var before := world.reaction_state()
			ok(world.react_to(id), "%s / %s: 认得这个菜单 id" % [variant_id, String(id)])
			var after := world.reaction_state()
			eq(after["last"], id, "%s / %s: 记下了最近一次反应" % [variant_id, String(id)])
			eq(int(after["count"]), int(before["count"]) + 1, "%s / %s: 计数 +1" % [variant_id, String(id)])
			match id:
				&"new":
					ok(float(after["surge"]) > 0.9 and float(before["surge"]) < 0.5, "炉火一涌")
				&"continue":
					ok(bool(after["wave_active"]) and not bool(before["wave_active"]), "吊灯依次闪亮")
				&"trial":
					eq(int(after["strike_requests"]), int(before["strike_requests"]) + 1, "锻锤收到敲一下的请求")
				&"arena":
					ok(float(after["brazier_boost"]) > 0.9 and float(before["brazier_boost"]) < 0.5, "火盆加亮")
				&"settings":
					ok(float(after["cloud_target"]) < 0.5 and float(before["cloud_target"]) > 0.9,
							"云影的目标速度放缓")
				&"controls":
					ok(float(after["gust"]) > 0.9 and float(before["gust"]) < 0.5, "一阵风")
				&"quit":
					ok(float(after["soul_boost"]) > 0.9 and float(before["soul_boost"]) < 0.5, "魂光加亮")
					ok(world.souls().target_count() > 0, "再多放几个魂光")
			await _free_world(world)
	var probe := _make_world(_state("act2"))
	await flush(3)
	var count_before := int(probe.reaction_state()["count"])
	ok(not probe.react_to(&"no_such_row"), "不认识的 id：返回 false")
	ok(not probe.react_to(&""), "空 id 也一样")
	eq(int(probe.reaction_state()["count"]), count_before, "不认识的 id：什么都不改")
	await _free_world(probe)


func test_reactions_fade_on_their_own_and_the_slow_clouds_last_only_while_focused() -> void:
	var world := _make_world(_state("act3"))
	await flush(3)
	world.react_to(&"new")
	world.react_to(&"controls")
	world.react_to(&"arena")
	_steps(world, 3.0)
	var state := world.reaction_state()
	almost(float(state["surge"]), 0.0, 0.0001, "炉火一涌会退")
	almost(float(state["gust"]), 0.0, 0.0001, "一阵风会停")
	almost(float(state["brazier_boost"]), 0.0, 0.0001, "火盆的加亮会回落")
	# 设置：云影放缓，且只在这一行有焦点时
	world.react_to(&"settings")
	_steps(world, 3.0)
	ok(world.cloud_speed() < 0.5, "停在设置：云影慢下来 (%.2f)" % world.cloud_speed())
	world.react_to(&"controls")
	_steps(world, 3.0)
	ok(world.cloud_speed() > 0.9, "焦点移走：云影恢复 (%.2f)" % world.cloud_speed())
	await _free_world(world)


func test_arena_focus_brightens_the_braziers_even_cold_ones() -> void:
	var world := _make_world(_state("cold"))
	var act4 := _make_world(_state("act4"))
	await flush(3)
	var braziers = world.braziers()
	almost(braziers.level_of(0), 0.0, 0.0001, "冷炉：火盆是冷的")
	world.react_to(&"arena")
	world._process(0.05)
	ok(braziers.level_of(0) > 0.2, "聚焦竞技场：冷盆也跳起一点火 (%.2f)" % braziers.level_of(0))
	var calm: float = act4.braziers().level_of(0)
	act4.react_to(&"arena")
	act4._process(0.05)
	ok(act4.braziers().level_of(0) > calm + 0.3, "亮着的火盆更旺")
	await _free_world(world)
	await _free_world(act4)


func test_the_hammer_strikes_on_the_trial_row() -> void:
	var world := _make_world(_state("act2"))
	await flush(3)
	world._process(0.05)
	var hammer = world.hammer()
	hammer.advance(3.0)       # 先让它这一轮砸完，停在砧上
	var before: int = hammer.strikes()
	world.react_to(&"trial")
	hammer.advance(1.5)
	ok(hammer.strikes() > before, "聚焦回火试炼：锻锤马上敲了一下（%d -> %d）" % [before, hammer.strikes()])
	await _free_world(world)


# ----------------------------------------------------------- the title wiring ----

func _open_title() -> TitleScreen:
	var title := (load(TITLE_SCENE) as PackedScene).instantiate() as TitleScreen
	add_child(title)
	await get_tree().process_frame
	await get_tree().process_frame
	return title


func test_every_menu_row_has_a_short_footer_hint() -> void:
	var title: TitleScreen = await _open_title()
	title._skip_intro()
	var menu := title.get_node("Menu") as MenuList
	var ids := menu.item_ids()
	eq(ids.size(), 7, "菜单七行")
	for id in ids:
		var hint := TitleScreen.hint_for(id)
		ok(hint != "", "%s 有说明" % String(id))
		ok(hint.length() <= 24, "%s 的说明 <= 24 字 (%d)" % [String(id), hint.length()])
		ok(TitleWorld.REACTIONS.has(id), "%s 在炉厅里有反应" % String(id))
	eq(TitleScreen.hint_for(&"arena"), "余烬竞技场 · 3v3 推线，摧毁敌方水晶", "竞技场行的说明")
	ok(TitleScreen.RECAP_HINT.length() <= 24, "回看余烬的说明 <= 24 字")
	eq(TitleScreen.hint_for(&"no_such_row"), "", "不认识的 id 没有说明")
	title.queue_free()
	await get_tree().process_frame


func test_the_footer_and_the_hall_follow_the_menu_focus() -> void:
	var title: TitleScreen = await _open_title()
	title._skip_intro()
	var menu := title.get_node("Menu") as MenuList
	var world := title.world()
	ok(world != null, "活景在")
	var ids := menu.item_ids()
	eq(ids[3], &"arena", "竞技场在第 4 行（索引 3）")
	# 每一步都换行（默认选中的那一行搭菜单时就聚焦过了，不会再发一次焦点变化）：
	# 有存档时默认停在第 2 行、没存档时停在第 1 行，这个顺序两种情况下都是真换行。
	for i in [2, 3, 4, 5, 6, 0, 1]:
		menu.select(i, false)
		eq(menu.selected_id(), ids[i])
		eq(title.footer_hint_text(), TitleScreen.hint_for(ids[i], title._continue_opens_recap),
				"页脚写的是 %s 这一行的说明" % String(ids[i]))
		eq(world.last_reaction(), ids[i], "炉厅对 %s 有反应" % String(ids[i]))
	menu.select(3, false)
	ok(title.footer_hint_text().contains("3v3"), "竞技场行：页脚说 3v3 推线")
	title.queue_free()
	await get_tree().process_frame
