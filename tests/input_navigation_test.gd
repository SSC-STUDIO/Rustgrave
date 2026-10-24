extends TestCase

const DRIVER := preload("res://tests/fixtures/navigation_driver.gd")


func setup() -> void:
	Director.abort()
	Director._set_lock(false)
	Input.action_release(&"move_left")
	Input.action_release(&"move_right")
	Input.action_release(&"jump")
	Input.action_release(&"dash")
	Input.action_release(&"attack")


func teardown() -> void:
	for action in [&"move_left", &"move_right", &"jump", &"dash", &"attack", &"interact"]:
		Input.action_release(action)


func _host() -> Node2D:
	var host := Node2D.new()
	var props := Node2D.new()
	props.name = "Props"
	host.add_child(props)
	add_child(host)
	return host


func _segment(rect: Rect2) -> Dictionary:
	return {"r": rect, "lift": null}


func test_runup_flanks_a_live_shield_guard_on_fixed_ground() -> void:
	var host := _host()
	var layout := ChapterLayout.new()
	add_child(layout)
	layout.step(host, "Floor", Vector2(0, 320), 512.0)
	var guard := layout.enemy(host, "Guard", "gear_shield", Vector2(200, 320)) as GearShieldEnemy
	var player := await spawn_player(host, Vector2(144, 300))
	var driver := DRIVER.new()
	driver.world = host
	add_child(driver)
	ok(await driver._nv_flat(168, 320, false), "ordinary dash and sword attacks clear the blocked run-up")
	ok(not is_instance_valid(guard) or guard._dead, "the guard is defeated through its real rear hurtbox")
	ok(player.health.current > 0)
	driver._release()


func test_walkoff_clears_the_whole_body_before_braking() -> void:
	var host := _host()
	var layout := ChapterLayout.new()
	add_child(layout)
	layout.step(host, "Pillar", Vector2(3292, 304), 24.0)
	layout.step(host, "Stage", Vector2(3316, 336), 208.0)
	var player := await spawn_player(host, Vector2(3304, 280))
	var driver := DRIVER.new()
	driver.world = host
	add_child(driver)
	driver._nv_goal = Vector2(3460, 336)
	ok(await driver._nv_cross(_segment(Rect2(3292, 304, 24, 16)),
			_segment(Rect2(3316, 336, 208, 16))), "input walks off the pillar instead of braking on its last pixel")
	almost(player.position.y, 336.0, 1.0)
	ok(player.is_on_floor())
	driver._release()


func test_walkoff_chooses_the_other_edge_when_a_balcony_blocks_the_head() -> void:
	var host := _host()
	var layout := ChapterLayout.new()
	add_child(layout)
	layout.step(host, "Ledge", Vector2(944, 264), 96.0)
	layout.step(host, "Balcony", Vector2(1048, 232), 56.0)
	layout.step(host, "LowerFloor", Vector2(928, 320), 192.0)
	var player := await spawn_player(host, Vector2(1000, 240))
	var driver := DRIVER.new()
	driver.world = host
	add_child(driver)
	driver._nv_goal = Vector2(1080, 320)
	ok(driver._nv_edge_blocked(Rect2(944, 264, 96, 16), true), "overhang clips head even when waist is clear")
	ok(not driver._nv_edge_blocked(Rect2(944, 264, 96, 16), false))
	ok(await driver._nv_cross(_segment(Rect2(944, 264, 96, 16)),
			_segment(Rect2(928, 320, 192, 16))), "production input crossing takes the clear west edge")
	almost(player.position.y, 320.0, 1.0)
	ok(player.is_on_floor())
	driver._release()


func test_route_uses_the_upper_catwalk_when_the_only_downward_edge_is_blocked() -> void:
	var host := _host()
	var layout := ChapterLayout.new()
	add_child(layout)
	layout.step(host, "Step", Vector2(1200, 288), 40.0)
	layout.step(host, "Catwalk", Vector2(1248, 256), 96.0)
	layout.step(host, "LowerFloor", Vector2(1240, 320), 136.0)
	var player := await spawn_player(host, Vector2(1220, 264))
	var driver := DRIVER.new()
	driver.world = host
	add_child(driver)
	driver._nv_goal = Vector2(1360, 320)
	ok(not driver._nv_link(_segment(Rect2(1200, 288, 40, 16)),
			_segment(Rect2(1240, 320, 136, 16))), "graph rejects walking into the low catwalk edge")
	var route := driver._nv_path(driver._nv_segments(), driver._nv_goal)
	ok(not route.is_empty(), "the upper catwalk is a real alternative")
	for i in range(1, route.size()):
		ok(await driver._nv_cross(route[i - 1], route[i]), "route edge %d uses real jump/movement input" % i)
	almost(player.position.y, 320.0, 1.0)
	ok(player.position.x > 1344.0)
	ok(player.is_on_floor())
	driver._release()


func test_high_gap_uses_the_available_basic_dash() -> void:
	var host := _host()
	var layout := ChapterLayout.new()
	add_child(layout)
	layout.step(host, "Launch", Vector2(1908, 288), 32.0)
	layout.step(host, "Gallery", Vector2(1976, 256), 160.0)
	layout.step(host, "CatchFloor", Vector2(1960, 352), 400.0)
	var player := await spawn_player(host, Vector2(1920, 264))
	var driver := DRIVER.new()
	driver.world = host
	add_child(driver)
	driver._nv_goal = Vector2(2040, 256)
	ok(await driver._nv_cross(_segment(Rect2(1908, 288, 32, 16)),
			_segment(Rect2(1976, 256, 160, 16))), "single jump and normal dash reach the high gallery")
	almost(player.position.y, 256.0, 1.0)
	ok(not player.controller.extra_jumps_unlocked, "fixture never unlocks double jump")
	driver._release()


func test_full_height_contiguous_riser_is_jumped_before_touching_the_face() -> void:
	var host := _host()
	var layout := ChapterLayout.new()
	add_child(layout)
	layout.step(host, "Launch", Vector2(720, 320), 80.0)
	layout.step(host, "Riser", Vector2(800, 288), 48.0)
	var player := await spawn_player(host, Vector2(736, 296))
	var driver := DRIVER.new()
	driver.world = host
	add_child(driver)
	driver._nv_goal = Vector2(824, 288)
	ok(await driver._nv_cross(_segment(Rect2(720, 320, 80, 16)),
			_segment(Rect2(800, 288, 48, 16))), "normal input clears a 32px riser without dashing into its wall")
	almost(player.position.y, 288.0, 1.0)
	ok(not player.controller.extra_jumps_unlocked)
	driver._release()


func test_closed_pressure_gate_uses_the_upper_route_until_it_is_open() -> void:
	var host := _host()
	var layout := ChapterLayout.new()
	add_child(layout)
	layout.step(host, "Floor", Vector2(0, 320), 320.0)
	layout.step(host, "Step", Vector2(64, 288), 32.0)
	layout.step(host, "Gallery", Vector2(104, 256), 32.0)
	layout.step(host, "Bridge", Vector2(144, 224), 72.0)
	var gate := ArenaDoor.new()
	gate.position = Vector2(144, 256)
	host.get_node("Props").add_child(gate)
	var player := await spawn_player(host, Vector2(32, 296))
	var driver := DRIVER.new()
	driver.world = host
	add_child(driver)
	driver._nv_goal = Vector2(248, 320)
	ok(not driver._nv_link(_segment(Rect2(96, 320, 48, 16)),
			_segment(Rect2(160, 320, 160, 16))), "closed gate blocks a direct floor hop")
	var route := driver._nv_path(driver._nv_segments(), driver._nv_goal)
	ok(not route.is_empty(), "upper gallery is reachable with a single jump")
	if route.is_empty(): return
	var used_bridge := false
	for edge in route:
		used_bridge = used_bridge or edge.r.position.y == 224.0
	ok(used_bridge, "route climbs over the gate instead of walking into it")
	for i in range(1, route.size()):
		var crossed: bool = await driver._nv_cross(route[i - 1], route[i])
		ok(crossed, "gate detour edge %d uses real input; feet=%s" % [i, player.position])
		if not crossed:
			driver._release()
			return
	almost(player.position.y, 320.0, 1.0)
	gate.open_door()
	ok(driver._nv_link(_segment(Rect2(96, 320, 48, 16)),
			_segment(Rect2(160, 320, 160, 16))), "opening the real gate restores its direct floor hop")
	driver._release()
