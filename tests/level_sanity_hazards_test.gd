extends TestCase
## LevelSanity 的机关体检：预警/安全间隔下限、喷口立在台面上、判定区离休息点 ≥40px、
## 塌陷台/传送带不当休息点支撑、外力区不盖巢、摆锤摆幅上下限。

var _layout: ChapterLayout


func _host() -> Node2D:
	var host := Node2D.new()
	add_child(host)
	_layout = ChapterLayout.new()
	add_child(_layout)
	_layout.floor_strip(host, "Floor", 0.0, 1200.0, "moss")
	return host


func _problems(host: Node2D, needle: String) -> Array[String]:
	var out: Array[String] = []
	for p in LevelSanity.check(host):
		if p.contains(needle):
			out.append(p)
	return out


func test_a_well_placed_set_of_hazards_is_clean() -> void:
	var host := _host()
	_layout.nest(host, "NestA", 100.0)
	_layout.cyclic(host, "Vent", Vector2(400, 320), "steam")
	_layout.cyclic(host, "Bell", Vector2(600, 320), "bell")
	_layout.cyclic(host, "Toll", Vector2(1000, 320), "shock", {"thick": 160.0})
	_layout.collapsing(host, "Beam", Vector2(700, 272), 64.0)
	_layout.pendulum(host, "Swing", Vector2(850, 200), 90.0)
	_layout.force_zone(host, "Gale", Rect2(300, 200, 120, 100), "wind", Vector2(50, 0))
	var bad: Array[String] = []
	for p in LevelSanity.check(host):
		for needle in ["hazard", "pendulum", "force zone", "keep rest points", "collapsing", "conveyor", "vents from"]:
			if p.contains(needle):
				bad.append(p)
				break
	eq(bad, [] as Array[String], "no hazard problems: %s" % [bad])
	eq(LevelSanity.hazards(host).size(), 6, "the registry sees every hazard")


func test_hazard_zone_must_stay_clear_of_a_nest() -> void:
	var host := _host()
	_layout.nest(host, "NestA", 400.0)
	_layout.cyclic(host, "Vent", Vector2(420, 320), "steam")
	ok(not _problems(host, "keep rest points").is_empty(), "a vent beside a nest is rejected")


func test_shock_band_counts_its_whole_width() -> void:
	var host := _host()
	_layout.nest(host, "NestA", 500.0)
	_layout.cyclic(host, "Toll", Vector2(420, 320), "shock", {"thick": 200.0})
	ok(not _problems(host, "keep rest points").is_empty(), "a nest inside the wave's reach is rejected")


func test_short_telegraph_and_short_safe_span_are_rejected() -> void:
	var host := _host()
	var hz := _layout.cyclic(host, "Vent", Vector2(400, 320), "steam")
	hz.telegraph_time = 0.2
	ok(not _problems(host, "telegraphs only").is_empty(), "telegraph below the floor")
	hz.telegraph_time = 0.6
	hz.rest_time = 0.3
	ok(not _problems(host, "safe per cycle").is_empty(), "rest + telegraph below the safe span")
	hz.rest_time = 2.0
	hz.active_time = 3.0
	ok(not _problems(host, "stays active").is_empty(), "an active window longer than the cap")


func test_a_vent_in_thin_air_is_rejected() -> void:
	var host := _host()
	_layout.cyclic(host, "Floating", Vector2(400, 200), "steam")
	ok(not _problems(host, "vents from thin air").is_empty())


func test_a_nest_on_a_conveyor_is_rejected_but_the_belt_is_walkable() -> void:
	var host := _host()
	_layout.conveyor(host, "Belt", Vector2(300, 288), 96.0, 30.0)
	_layout.nest(host, "NestOnBelt", 340.0, 288.0)
	ok(not _problems(host, "conveyor").is_empty(), "belts are not rest points")


func test_a_force_zone_over_a_nest_is_rejected() -> void:
	var host := _host()
	_layout.nest(host, "NestA", 400.0)
	_layout.force_zone(host, "Gale", Rect2(350, 220, 120, 100), "wind", Vector2(50, 0))
	ok(not _problems(host, "keep rest points").is_empty())
	var host2 := _host()
	_layout.nest(host2, "NestB", 100.0)
	_layout.force_zone(host2, "Gale", Rect2(350, 220, 120, 100), "wind", Vector2(50, 0))
	eq(_problems(host2, "keep rest points").size(), 0, "a gale elsewhere is fine")


func test_pendulum_limits_are_checked_after_the_fact() -> void:
	var host := _host()
	var p := _layout.pendulum(host, "Swing", Vector2(500, 200), 90.0)
	p.swing_deg = 85.0
	ok(not _problems(host, "swings outside its limits").is_empty())


func test_collapsing_beams_do_not_hold_enemies() -> void:
	var host := _host()
	_layout.collapsing(host, "Beam", Vector2(300, 272), 96.0)
	_layout.enemy(host, "Crawler", "scrapper", Vector2(340, 272))
	ok(not _problems(host, "collapsing platform").is_empty(), "grounded enemies cannot stand on a beam that falls")
