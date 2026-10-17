extends TestCase
## 跳跃包络：体检里的"跳得过去吗"必须和玩家真的手感对得上。
##
## TraversalModel 从 PlayerController 的导出值积分出包络，不是手写魔数。
## 这条测试量两件事：
##   · 包络数值落在实测区间（控制器一改，这里立刻红）
##   · can_hop 认弧线上的障碍，而不是只比 x 间距


func test_envelope_matches_the_measured_jump() -> void:
	var rise := TraversalModel.max_rise()
	var air := float(TraversalModel.envelope()["air_time"])
	var gap := TraversalModel.max_gap_level()
	# jump_velocity -268 + apex_gravity_scale 0.62 ⇒ 上升约 36.7px。
	ok(rise > 34.0 and rise < 39.0, "max rise %.1f is the real jump height" % rise)
	ok(air > 0.45 and air < 0.60, "air time %.2fs" % air)
	# 同高满速横跨 ≈ 55px 位移 + 两侧半宽 ≈ 66px。
	ok(gap > 60.0 and gap < 72.0, "level gap %.1fpx" % gap)
	# 手册写 32px 上升 / 72px 横跨；物理只给 ~36.7 / ~66，所以体检的硬上限
	# 必须比物理更保守，否则会放过玩家跳不上去的落差。
	ok(TraversalModel.max_rise() > LevelSanity.JUMP_RISE_MAX,
			"the manual's 32px rise stays inside the real jump")
	ok(TraversalModel.max_gap_level() < LevelSanity.JUMP_GAP_MAX + 8.0,
			"the manual's 72px gap is within reach of the real jump")


func test_a_drop_buys_horizontal_room() -> void:
	var level_gap := TraversalModel.max_gap_level()
	var dropped := TraversalModel.gap_for_drop(96.0)
	ok(dropped > level_gap + 10.0, "falling 96px buys %.1fpx more reach" % (dropped - level_gap))
	almost(TraversalModel.gap_for_drop(0.0), level_gap, 0.01, "no drop means no bonus")


func test_can_hop_rejects_gaps_the_player_cannot_clear() -> void:
	var solids: Array[Rect2] = []
	var a := LevelSanity.TopSeg.new(0.0, 64.0, 320.0, "A")
	var near := LevelSanity.TopSeg.new(120.0, 184.0, 320.0, "Near")   # gap 56
	ok(TraversalModel.can_hop(a, near, solids), "a 56px same-height gap is a jump")
	var far := LevelSanity.TopSeg.new(136.0, 200.0, 320.0, "Far")     # gap 72
	ok(not TraversalModel.can_hop(a, far, solids),
			"a 72px same-height gap is past the real envelope")
	var high := LevelSanity.TopSeg.new(64.0, 128.0, 272.0, "High")    # rise 48
	ok(not TraversalModel.can_hop(a, high, solids), "a 48px rise is not a single jump")


func test_can_hop_sees_a_wall_inside_the_arc() -> void:
	# 两块同高的台子只隔 16px，中间立一根通天的柱：看得到，走不过去。
	var solids: Array[Rect2] = [Rect2(72.0, -400.0, 16.0, 900.0)]
	var a := LevelSanity.TopSeg.new(0.0, 64.0, 320.0, "A")
	var b := LevelSanity.TopSeg.new(80.0, 144.0, 320.0, "B")
	ok(not TraversalModel.can_hop(a, b, solids), "a pillar inside the arc blocks the hop")
	ok(TraversalModel.can_hop(a, b, [] as Array[Rect2]), "without the pillar it is a hop")


func test_headroom_is_measured_from_the_underside() -> void:
	# 天花板底面在 232 ⇒ 台面 320 之上有 88px，站得下。
	var high: Array[Rect2] = [Rect2(0.0, 200.0, 200.0, 32.0)]
	ok(TraversalModel.headroom_ok(high, 100.0, 140.0, 320.0), "88px of clearance is fine")
	# 天花板底面在 308 ⇒ 只剩 12px，比骑士 26px 还矮，站不进去。
	var low: Array[Rect2] = [Rect2(0.0, 300.0, 200.0, 8.0)]
	ok(not TraversalModel.headroom_ok(low, 100.0, 140.0, 320.0), "12px is not enough to stand")
	# 一级压在地面上的台阶不是天花板：那是能踩上去的东西，不能算成"没净空"。
	var step: Array[Rect2] = [Rect2(0.0, 288.0, 200.0, 48.0)]
	ok(TraversalModel.headroom_ok(step, 100.0, 140.0, 320.0),
			"a 32px step standing on the floor is not a headroom problem")
	# 只有压在头顶上方的那一段 x 才算：这根梁只盖住 x 0..80。
	var beam: Array[Rect2] = [Rect2(0.0, 300.0, 80.0, 8.0)]
	ok(TraversalModel.headroom_ok(beam, 100.0, 140.0, 320.0), "clear to the right of the beam")
	ok(not TraversalModel.headroom_ok(beam, 10.0, 60.0, 320.0), "but not under it")