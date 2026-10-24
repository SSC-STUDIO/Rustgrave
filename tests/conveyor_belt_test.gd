extends TestCase
## 传送带：反向周期与停转、速度上限、骑士被带着走。

func _host() -> Node2D:
	var host := Node2D.new()
	add_child(host)
	return host


func test_flip_cycle_stops_before_reversing() -> void:
	var belt := ConveyorBelt.new()
	belt.speed = 40.0
	belt.flip_period = 3.0
	almost(belt.velocity_at(0.5), 40.0, 0.001)
	almost(belt.velocity_at(2.7), 0.0, 0.001, "the last 0.6s of each half cycle is a stop")
	almost(belt.velocity_at(3.5), -40.0, 0.001, "then it runs the other way")
	almost(belt.velocity_at(5.8), 0.0, 0.001)
	almost(belt.velocity_at(6.5), 40.0, 0.001, "and around again")
	belt.flip_period = 0.0
	almost(belt.velocity_at(99.0), 40.0, 0.001, "no flip period = a steady belt")
	belt.free()


func test_speed_is_capped_below_the_run_speed() -> void:
	var host := _host()
	var layout := ChapterLayout.new()
	add_child(layout)
	var belt := layout.conveyor(host, "Belt", Vector2(100, 0), 96.0, 500.0)
	ok(absf(belt.speed) <= ConveyorBelt.MAX_SPEED + 0.001, "a belt faster than half the run speed is clamped")
	almost(belt.constant_linear_velocity.x, belt.speed, 0.001)
	ok(belt.is_in_group(ConveyorBelt.GROUP))
	eq(String(belt.get_meta("hazard_kind")), "conveyor")


func test_the_belt_is_a_normal_platform_for_the_sanity_checker() -> void:
	var host := _host()
	var layout := ChapterLayout.new()
	add_child(layout)
	layout.floor_strip(host, "Floor", 0.0, 600.0, "iron")
	layout.conveyor(host, "Belt", Vector2(200, 288), 96.0, 30.0)
	var tops := LevelSanity.top_segments(host)
	var found := false
	for seg in tops:
		if seg.owner_name == "Belt":
			found = true
			eq(seg.kind, "conveyor")
	ok(found, "the belt counts as a walkable top")


func test_a_knight_is_carried_along() -> void:
	var host := _host()
	build_floor(host)
	var layout := ChapterLayout.new()
	add_child(layout)
	var belt := layout.conveyor(host, "Belt", Vector2(240, -16), 200.0, 40.0, "iron_float",
			{"hint_id": &""})
	var player := await spawn_player(host, Vector2(300, -50))
	await flush(4)
	ok(player.is_on_floor(), "the knight stands on the belt")
	var x0 := player.global_position.x
	await flush(40)
	ok(player.global_position.x > x0 + 12.0,
			"a belt moving right carries the knight right (%.0f -> %.0f)" % [x0, player.global_position.x])
	belt.speed = -40.0
	belt.constant_linear_velocity = Vector2(-40.0, 0.0)
	var x1 := player.global_position.x
	await flush(40)
	ok(player.global_position.x < x1 - 8.0, "reversing the belt carries the knight back")
