extends TestCase
## 摆锤：摆动数学、上下限、判定体跟着球走、过最低点重新武装、会伤到站在下面的骑士。

func setup() -> void:
	# 前序用例可能泄漏过场锁；机关遇到锁会冻结时间线。
	Director._set_lock(false)


func teardown() -> void:
	Director._set_lock(false)


func _host() -> Node2D:
	var host := Node2D.new()
	add_child(host)
	return host


func _pendulum(host: Node2D, pivot: Vector2, length: float, props: Dictionary = {}) -> PendulumHazard:
	var layout := ChapterLayout.new()
	add_child(layout)
	var merged := {"hint_id": &""}
	for key in props:
		merged[key] = props[key]
	return layout.pendulum(host, "Swing", pivot, length, merged)


func test_swing_math() -> void:
	var p := PendulumHazard.new()
	p.length = 96.0
	p.swing_deg = 50.0
	p.period = 3.0
	almost(p.angle_at(0.0), 0.0, 0.0001, "straight down at t=0")
	almost(p.angle_at(0.75), deg_to_rad(50.0), 0.0001, "full swing at a quarter period")
	almost(p.angle_at(2.25), -deg_to_rad(50.0), 0.0001, "full swing the other way")
	almost(p.head_local_at(0.0).y, 96.0, 0.001)
	almost(p.head_local_at(0.0).x, 0.0, 0.001)
	var end := p.head_local_at(0.75)
	ok(end.x > 70.0 and end.y < 96.0 and end.y > 50.0, "the arc lifts the head at the ends (%s)" % [end])
	ok(p.danger_local_rect().has_point(end), "the danger rect contains the end of the arc")
	ok(p.danger_local_rect().has_point(p.head_local_at(0.0)), "and the bottom")
	ok(p.head_over(-5.0, 5.0, 0.0), "the head is over a narrow strip under the pivot at the bottom")
	ok(not p.head_over(-5.0, 5.0, 0.75), "and well away from it at the end of the swing")
	p.free()


func test_limits_clamp_the_swing_and_the_period() -> void:
	var host := _host()
	var p := _pendulum(host, Vector2(200, -100), 90.0, {"swing_deg": 200.0, "period": 0.5})
	ok(p.swing_deg <= PendulumHazard.MAX_SWING_DEG + 0.001, "swing is capped")
	ok(p.period >= PendulumHazard.MIN_PERIOD - 0.001, "period has a floor so there is always a window")
	ok(p.is_in_group(PendulumHazard.GROUP))
	eq(String(p.get_meta("hazard_kind")), "pendulum")


func test_hitbox_follows_the_head_and_rearms_at_the_bottom() -> void:
	var host := _host()
	var p := _pendulum(host, Vector2(200, -100), 90.0, {"period": 3.0, "phase": 0.0})
	p.set_physics_process(false)
	var hit := p.get_node("PendulumHitbox") as Hitbox
	ok(hit.monitoring, "armed from birth")
	almost(hit.position.y, 90.0, 0.01, "at the bottom of the arc")
	var passes := [0]
	p.passed_bottom.connect(func() -> void: passes[0] += 1)
	p.tick(0.5)
	almost(hit.position.x, p.head_local_at(p.clock()).x, 0.01, "the hitbox is where the head is drawn")
	hit.already_hit.append(self)
	p.tick(1.0)   # t=1.5: the bottom crossing at half period
	eq(passes[0], 1, "passed the bottom once")
	ok(hit.already_hit.is_empty(), "each pass re-arms the hit list")


func test_the_head_hurts_a_knight_standing_under_it() -> void:
	var host := _host()
	build_floor(host)
	var player := await spawn_player(host, Vector2(320, -24))
	var before := player.health.current
	_pendulum(host, Vector2(320, -90), 90.0, {"period": 3.0, "phase": 0.0})
	await flush(12)
	ok(player.health.current < before, "a swinging head at floor level hurts (%d -> %d)" % [before, player.health.current])


func test_the_timeline_freezes_during_a_cutscene() -> void:
	var host := _host()
	var p := _pendulum(host, Vector2(200, -100), 90.0)
	p.set_physics_process(false)
	var t0 := p.clock()
	Director._set_lock(true)
	p.tick(1.0)
	almost(p.clock(), t0, 0.0001)
	ok(not (p.get_node("PendulumHitbox") as Hitbox).monitoring, "locked knight cannot be hit")
	Director._set_lock(false)
	p.tick(0.02)
	ok((p.get_node("PendulumHitbox") as Hitbox).monitoring)


func test_safe_window_detects_an_intermediate_sweep_and_never_changes_the_clock() -> void:
	var swing := _pendulum(_host(), Vector2(200, -100), 96.0,
			{"period": 3.2, "phase": 0.25})
	swing.set_physics_process(false)
	var before := swing.clock()
	ok(swing.safe_window(0.2), "the central corridor is clear near a swing end")
	ok(not swing.safe_window(0.8), "the head returns through the central corridor")
	ok(not swing.safe_window(1.6), "clear endpoints cannot hide a crossing in the middle")
	ok(swing.safe_window(9.6, 600.0, 640.0), "a corridor outside the entire arc stays clear")
	ok(not swing.safe_window(9.6), "a full cycle always sweeps under the pivot")
	almost(swing.clock(), before, 0.0001, "query does not alter the swing phase")
	ok((swing.get_node("PendulumHitbox") as Hitbox).monitoring, "query does not disarm damage")
