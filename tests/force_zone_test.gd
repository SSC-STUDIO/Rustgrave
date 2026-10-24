extends TestCase
## 外力区：阵风包络、骑士被风推着走、冲刺不受风、泥沼拖慢并带毒、
## 控制器的外力读数在没人写入后自己过期。

func setup() -> void:
	# 前序用例可能泄漏过场锁；外力区遇到锁会停止推人。
	Director._set_lock(false)


func _host() -> Node2D:
	var host := Node2D.new()
	add_child(host)
	return host


func _zone(host: Node2D, rect: Rect2, skin: String, push: Vector2, props: Dictionary = {}) -> ForceZone:
	var layout := ChapterLayout.new()
	add_child(layout)
	var merged := {"auto_hint": false}
	for key in props:
		merged[key] = props[key]
	return layout.force_zone(host, "Zone", rect, skin, push, merged)


func test_gust_envelope_ramps_in_and_out() -> void:
	var zone := ForceZone.new()
	zone.gust_period = 4.0
	zone.gust_duty = 0.5
	almost(zone.gust_factor(0.0), 0.0, 0.001, "a gust starts from nothing")
	almost(zone.gust_factor(0.15), 0.5, 0.001, "ramping in")
	almost(zone.gust_factor(1.0), 1.0, 0.001, "full force mid-gust")
	almost(zone.gust_factor(1.9), 0.333, 0.01, "ramping out")
	almost(zone.gust_factor(2.5), 0.0, 0.001, "calm between gusts")
	almost(zone.gust_factor(4.15), 0.5, 0.001, "periodic")
	zone.gust_period = 0.0
	almost(zone.gust_factor(123.0), 1.0, 0.001, "a steady wind never drops")
	zone.free()


func test_the_clock_reports_when_the_next_gust_comes() -> void:
	var host := _host()
	var zone := _zone(host, Rect2(0, -100, 100, 100), "wind", Vector2(60, 0),
			{"gust_period": 4.0, "gust_duty": 0.5, "phase": 0.0})
	zone.set_physics_process(false)
	almost(zone.seconds_until_gust(), 0.0, 0.001, "a gust is blowing at t=0")
	zone.tick(2.5)
	almost(zone.seconds_until_gust(), 1.5, 0.01)
	ok(not zone.is_gusting())
	zone.tick(1.6)
	ok(zone.is_gusting())


func test_push_is_capped_below_the_run_speed() -> void:
	var host := _host()
	var zone := _zone(host, Rect2(0, -100, 100, 100), "wind", Vector2(500, 0))
	ok(zone.push.x <= ForceZone.MAX_PUSH + 0.001, "a wind you cannot walk against is not allowed")
	ok(ForceZone.MAX_PUSH < 108.0)


func test_wind_carries_a_standing_knight_and_a_dash_ignores_it() -> void:
	var host := _host()
	build_floor(host)
	var player := await spawn_player(host, Vector2(320, -24))
	_zone(host, Rect2(180, -140, 280, 140), "wind", Vector2(70, 0))
	await flush(3)
	var x0 := player.global_position.x
	await flush(36)
	ok(player.global_position.x > x0 + 15.0,
			"wind carries a knight who is standing still (%.0f -> %.0f)" % [x0, player.global_position.x])
	ok(player.velocity.x > 30.0, "at roughly the wind speed (%.0f)" % player.velocity.x)


func test_drag_lowers_the_target_speed() -> void:
	var host := _host()
	build_floor(host)
	var player := await spawn_player(host, Vector2(100, -24))
	Input.action_press("move_right")
	for i in 40:
		player.controller.add_environment(Vector2.ZERO, 0.5)
		await flush(1)
	Input.action_release("move_right")
	ok(player.velocity.x > 20.0 and player.velocity.x < 70.0,
			"half-drag caps a full run at about half speed (%.0f)" % player.velocity.x)


func test_environment_reading_expires_without_a_zone() -> void:
	var host := _host()
	build_floor(host)
	var player := await spawn_player(host, Vector2(100, -24))
	player.controller.add_environment(Vector2(50, 0), 0.3)
	almost(player.controller.environment_push().x, 50.0, 0.001)
	almost(player.controller.environment_drag(), 0.3, 0.001)
	player.controller.add_environment(Vector2(10, -20), 0.6)
	almost(player.controller.environment_push().x, 60.0, 0.001, "zones in the same frame add up")
	almost(player.controller.environment_drag(), 0.6, 0.001, "drag takes the strongest")
	await flush(5)
	almost(player.controller.environment_push().x, 0.0, 0.001, "nobody writing = out of the zone")
	almost(player.controller.environment_drag(), 0.0, 0.001)


func test_mud_adds_toxin_while_the_knight_stands_in_it() -> void:
	var host := _host()
	build_floor(host)
	var player := await spawn_player(host, Vector2(320, -24))
	_zone(host, Rect2(220, -60, 200, 60), "mud", Vector2.ZERO, {"drag": 0.4, "toxin_per_second": 16.0})
	var before := player.toxin.toxin
	await flush(40)
	ok(player.toxin.toxin > before, "standing in rust mud builds toxin (%.3f -> %.3f)" % [before, player.toxin.toxin])


func test_safe_window_covers_the_whole_calm_interval_without_advancing_the_gust() -> void:
	var zone := _zone(_host(), Rect2(0, -100, 100, 100), "wind", Vector2(60, 0),
			{"gust_period": 4.0, "gust_duty": 0.5})
	zone.set_physics_process(false)
	ok(not zone.safe_window(0.1), "zero force at the ramp origin is not a calm interval")
	zone.tick(2.5)
	var time := zone.clock()
	ok(zone.safe_window(1.4))
	ok(not zone.safe_window(1.5), "the next gust must not start before the crossing finishes")
	almost(zone.clock(), time, 0.0001, "query leaves the deterministic phase alone")
	zone.tick(1.6)
	ok(not zone.safe_window())
	zone.gust_period = 0.0
	ok(not zone.safe_window(), "a steady wind never advertises a calm window")
	zone.push = Vector2.ZERO
	ok(zone.safe_window(100.0), "an inert zone is clear for any crossing")
	zone.drag = 0.3
	ok(not zone.safe_window(), "mud drag persists even without wind")
	zone.drag = 0.0
	zone.toxin_per_second = 12.0
	ok(not zone.safe_window(), "toxin exposure also persists during calm")
