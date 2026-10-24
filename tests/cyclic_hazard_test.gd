extends TestCase
## 周期机关：时间线是相位的纯函数、预警有下限、判定体只在判定期武装并跟着画面走、
## 同一窗口只伤一次、过场锁玩家时整条时间线冻结。

const SKINS := ["steam", "flame", "slag", "bell", "shock"]


func setup() -> void:
	# 前序用例可能泄漏过场锁；机关遇到锁会冻结时间线。
	Director._set_lock(false)


func teardown() -> void:
	Director._set_lock(false)


func _host() -> Node2D:
	var host := Node2D.new()
	add_child(host)
	return host


func _make(skin: String = "steam", props: Dictionary = {}, host: Node2D = null,
		pos: Vector2 = Vector2(100, 0)) -> CyclicHazard:
	if host == null:
		host = _host()
	var layout := ChapterLayout.new()
	add_child(layout)
	return layout.cyclic(host, "Hazard_%s" % skin, pos, skin, props)


func test_timeline_is_a_pure_function_of_phase() -> void:
	var hz := _make("steam", {"rest_time": 2.0, "telegraph_time": 0.8, "active_time": 0.7, "phase": 0.0})
	hz.set_physics_process(false)
	almost(hz.period(), 3.5, 0.001)
	eq(hz.state(), CyclicHazard.State.REST)
	almost(hz.seconds_until_active(), 2.8, 0.001)
	eq(hz.state_at(1.9), CyclicHazard.State.REST)
	eq(hz.state_at(2.1), CyclicHazard.State.WARN)
	eq(hz.state_at(2.79), CyclicHazard.State.WARN)
	eq(hz.state_at(2.81), CyclicHazard.State.ACTIVE)
	eq(hz.state_at(3.6), CyclicHazard.State.REST, "the cycle wraps")
	var late := _make("steam", {"phase": 0.85})
	eq(late.state(), CyclicHazard.State.ACTIVE, "phase 0.85 is born inside the active window")
	ok(late.get_node("HazardHitbox").monitoring, "a hazard born active is armed")
	ok(not late.safe_window(0.1), "never safe while active")
	almost(late.seconds_until_active(), 0.0, 0.001)
	ok(late.seconds_until_safe() > 0.0)


func test_minimums_are_enforced() -> void:
	var hz := _make("flame", {"telegraph_time": 0.1, "rest_time": 0.0, "active_time": 0.0})
	almost(hz.telegraph_time, CyclicHazard.MIN_TELEGRAPH, 0.001)
	almost(hz.rest_time, CyclicHazard.MIN_REST, 0.001)
	almost(hz.active_time, CyclicHazard.MIN_ACTIVE, 0.001)
	ok(hz.is_in_group(CyclicHazard.GROUP), "hazards join the shared group")
	eq(String(hz.get_meta("hazard_kind")), "cyclic")


func test_hitbox_arms_only_while_active_and_follows_the_visible_extent() -> void:
	var hz := _make("steam")
	hz.set_physics_process(false)
	var hit := hz.get_node("HazardHitbox") as Hitbox
	var shape := hz.get_node("HazardHitbox/CollisionShape2D") as CollisionShape2D
	ok(not hit.monitoring, "resting: unarmed")
	hz.tick(2.1)
	eq(hz.state(), CyclicHazard.State.WARN)
	ok(not hit.monitoring, "warning: still unarmed — the telegraph always comes first")
	hz.tick(0.75)
	eq(hz.state(), CyclicHazard.State.ACTIVE)
	ok(hit.monitoring, "active: armed")
	var early := (shape.shape as RectangleShape2D).size.y
	hz.tick(0.3)
	var full := (shape.shape as RectangleShape2D).size.y
	ok(full > early, "the hit zone grows with the jet (%.0f -> %.0f)" % [early, full])
	almost(full, hz.reach, 0.5, "mid-window the jet is at full reach")
	almost(shape.position.y, -hz.reach * 0.5, 0.5, "an upward jet's zone rises from the vent")
	hz.tick(0.5)
	eq(hz.state(), CyclicHazard.State.REST)
	ok(not hit.monitoring, "back to rest: unarmed again")


func test_a_large_step_never_leaves_the_hitbox_armed() -> void:
	var hz := _make("steam")
	hz.set_physics_process(false)
	var hit := hz.get_node("HazardHitbox") as Hitbox
	hz.tick(3.0)
	eq(hz.state(), CyclicHazard.State.ACTIVE)
	ok(hit.monitoring)
	# 3.0 + 2.6 = 5.6 -> 2.1 into the next cycle: WARN, with the whole rest skipped.
	hz.tick(2.6)
	eq(hz.state(), CyclicHazard.State.WARN)
	ok(not hit.monitoring, "skipping over the rest period still disarms")


func test_safe_window_reads_the_timeline() -> void:
	var hz := _make("steam", {"rest_time": 2.0, "telegraph_time": 0.8, "active_time": 0.7})
	hz.set_physics_process(false)
	ok(hz.safe_window(1.0), "2.8s before the next jet: a 1s crossing is safe")
	ok(not hz.safe_window(3.0), "a 3s stay would run into it")
	hz.tick(2.5)
	ok(hz.safe_window(0.2))
	ok(not hz.safe_window(0.5), "0.3s before it fires, a 0.5s crossing is not safe")


func test_active_hazard_hurts_the_knight_once_per_window() -> void:
	var host := _host()
	build_floor(host)
	var player := await spawn_player(host, Vector2(320, -24))
	var hz := _make("steam", {"phase": 0.0}, host, Vector2(320, 0))
	hz.set_physics_process(false)
	var before := player.health.current
	hz.tick(hz.seconds_until_active() + 0.3)
	await flush(8)
	eq(player.health.current, before - 1, "the jet hurt the knight")
	await flush(50)
	eq(player.health.current, before - 1, "the same window never hits twice")


func test_every_skin_builds_and_draws_in_every_state() -> void:
	for skin in SKINS:
		var hz := _make(skin)
		hz.set_physics_process(false)
		var seen := {}
		var steps := [0.05, hz.rest_time, hz.telegraph_time * 0.5, hz.telegraph_time * 0.6,
				hz.active_time * 0.3, hz.active_time * 0.4, hz.active_time * 0.5, 0.2]
		for step in steps:
			hz.tick(float(step))
			seen[hz.state()] = true
			hz.queue_redraw()
			await flush(1)
		ok(seen.has(CyclicHazard.State.WARN) and seen.has(CyclicHazard.State.ACTIVE),
				"%s walked through WARN and ACTIVE" % skin)
		var rect := hz.hit_rect()
		ok(rect.size.x > 0.0 and rect.size.y > 0.0, "%s has a hit rect" % skin)


func test_shock_hurts_only_at_the_travelling_front() -> void:
	var hz := _make("shock", {"thick": 200.0})
	hz.set_physics_process(false)
	var shapes: Array[CollisionShape2D] = []
	for child in hz.get_node("HazardHitbox").get_children():
		if child is CollisionShape2D:
			shapes.append(child as CollisionShape2D)
	eq(shapes.size(), 2, "one band per side")
	hz.tick(hz.seconds_until_active() + hz.active_time * 0.5)
	eq(hz.state(), CyclicHazard.State.ACTIVE)
	var left := shapes[0].position.x
	var right := shapes[1].position.x
	ok(left < -20.0 and right > 20.0, "the two fronts have left the centre (%.0f / %.0f)" % [left, right])
	almost(left, -right, 0.5, "symmetric")
	ok(right <= hz.thick * 0.5 + 0.5, "never past the full width")


func test_the_timeline_freezes_while_the_knight_is_locked() -> void:
	var hz := _make("flame")
	hz.set_physics_process(false)
	hz.tick(hz.seconds_until_active() + 0.1)
	var hit := hz.get_node("HazardHitbox") as Hitbox
	ok(hit.monitoring)
	var t0 := hz.clock()
	Director._set_lock(true)
	hz.tick(1.0)
	almost(hz.clock(), t0, 0.0001, "no time passes during a cutscene")
	ok(not hit.monitoring, "and nothing can hurt a locked knight")
	Director._set_lock(false)
	hz.tick(0.05)
	ok(hit.monitoring, "an active window resumes armed")


func test_layout_helper_applies_presets_overrides_and_hint() -> void:
	var hz := _make("slag", {"reach": 90.0})
	almost(hz.reach, 90.0, 0.001, "props override the preset")
	almost(hz.thick, float(CyclicHazard.preset("slag")["thick"]), 0.001, "the rest comes from the preset")
	var hint := hz.get_node_or_null("HazardHint") as HintArea
	ok(hint != null and hint.hint_id == &"slag", "first-encounter hint is attached")
	ok(HintService.CATALOG.has(&"slag"), "and its text lives in the hint catalog")
	eq(hz.get_parent().name, "Props")
