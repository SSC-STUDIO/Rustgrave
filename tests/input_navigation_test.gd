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


func test_conveyor_runup_countersteers_world_motion_before_the_workshop_stair() -> void:
	var host := _host()
	var layout := ChapterLayout.new()
	add_child(layout)
	var belt := layout.conveyor(host, "QuenchBelt", Vector2(480, 320), 224.0, 36.0,
			"iron_float", {"hint_id": &""})
	layout.step(host, "FloorB", Vector2(704, 320), 768.0)
	layout.step(host, "StepB1", Vector2(752, 288), 48.0)
	var player := await spawn_player(host, Vector2(640, 296))
	var driver := DRIVER.new()
	driver.world = host
	add_child(driver)
	ok(absf(player.get_platform_velocity().x) > 30.0, "fixture stands on the real moving belt")
	ok(await driver._nv_flat(668, 320, false), "input settles its world position against the belt")
	ok(absf(player.position.x - 668.0) < 4.0)
	driver._nv_goal = Vector2(776, 288)
	ok(not driver._nv_link(_segment(Rect2(480, 320, 224, 16)),
			_segment(Rect2(752, 288, 48, 16))), "graph walks across the existing floor before jumping")
	var route := driver._nv_path(driver._nv_segments(), driver._nv_goal)
	ok(not route.is_empty())
	if route.is_empty(): return
	for i in range(1, route.size()):
		ok(await driver._nv_cross(route[i - 1], route[i]), "belt/stair edge %d uses real input" % i)
	almost(player.position.y, 288.0, 1.0)
	ok(player.is_on_floor())
	ok(not player.controller.extra_jumps_unlocked)
	almost(belt.speed, 36.0, 0.001, "navigation does not stop or alter the conveyor")
	driver._release()


func test_counterflow_belt_positioning_uses_normal_direction_input() -> void:
	var host := _host()
	var layout := ChapterLayout.new()
	add_child(layout)
	layout.conveyor(host, "ReturnBelt", Vector2(0, 320), 512.0, -36.0,
			"iron_float", {"hint_id": &""})
	var player := await spawn_player(host, Vector2(224, 296))
	var driver := DRIVER.new()
	driver.world = host
	add_child(driver)
	ok(await driver._nv_flat(320, 320, false), "walk east against the westbound belt")
	ok(absf(player.position.x - 320.0) < 4.0)
	ok(await driver._nv_flat(160, 320, false), "walk west with the same belt")
	ok(absf(player.position.x - 160.0) < 4.0)
	ok(player.health.current > 0)
	driver._release()


func test_deep_gap_descent_does_not_jump_back_onto_the_overlapping_gallery() -> void:
	var host := _host()
	var layout := ChapterLayout.new()
	add_child(layout)
	layout.step(host, "GalleryWest", Vector2(1008, 192), 432.0)
	layout.step(host, "GalleryEast", Vector2(1496, 192), 440.0)
	layout.step(host, "LowerChoir", Vector2(1152, 320), 280.0)
	var player := await spawn_player(host, Vector2(1559, 168))
	var driver := DRIVER.new()
	driver.world = host
	add_child(driver)
	driver._nv_goal = Vector2(1190, 320)
	var crossed: bool = await driver._nv_cross(_segment(Rect2(1496, 192, 440, 16)),
			_segment(Rect2(1152, 320, 280, 16)))
	ok(crossed, "normal input drops through the 56px gallery opening; feet=%s" % player.position)
	ok(player.is_on_floor(), "knight lands on the lower choir floor")
	almost(player.position.y, 320.0, 1.0)
	ok(not player.controller.extra_jumps_unlocked)
	ok(player.health.current > 0)
	driver._release()


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


func test_cathedral_contiguous_bridge_descends_at_the_real_east_stair() -> void:
	var host := _host()
	var layout := preload("res://scripts/levels/chapters/level04_layout.gd").new()
	add_child(layout)
	layout.build(host)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	for hazard in LevelSanity.hazards(host):
		hazard.queue_free()
	await flush(2)
	var player := await spawn_player(host, Vector2(2168, 232))
	var driver := DRIVER.new()
	driver.world = host
	add_child(driver)
	driver._nv_goal = Vector2(3110, 320)
	var bridge_west := Rect2(1984, 256, 144, 16)
	var bridge_east := Rect2(2128, 256, 240, 16)
	var dry_bed := Rect2(1888, 352, 576, 16)
	ok(driver._nv_edge_blocked(bridge_west, true), "east join continues onto the next bridge piece")
	ok(driver._nv_edge_blocked(bridge_east, false), "west join continues onto the previous bridge piece")
	ok(not driver._nv_link(_segment(bridge_west), _segment(dry_bed)), "neither join invents a drop through the continuous bridge")
	ok(not driver._nv_link(_segment(bridge_east), _segment(dry_bed)), "east descent must visit the actual intermediate stair")
	var route := driver._nv_path(driver._nv_segments(), driver._nv_goal)
	ok(not route.is_empty(), "actual cathedral geometry has a basic-input exit")
	if route.is_empty(): return
	var uses_stair := false
	for edge in route:
		uses_stair = uses_stair or edge.r.position == Vector2(2368, 288)
	ok(uses_stair, "route follows BridgeB4 instead of alternating between bridge pieces")
	for i in range(1, route.size()):
		var crossed: bool = await driver._nv_cross(route[i - 1], route[i])
		ok(crossed, "cathedral edge %d uses real movement; feet=%s" % [i, player.position])
		if not crossed:
			driver._release()
			return
	ok(await driver._nv_flat(3110, 320, false))
	ok(player.is_on_floor() and player.health.current > 0)
	ok(not player.controller.extra_jumps_unlocked)
	ok(not player.inventory.has_ability(AbilityIds.HOOKSHOT_TETHER))
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


func test_finale_bed_riser_has_real_single_jump_headroom_under_the_return_stair() -> void:
	var host := _host()
	var layout := ChapterLayout.new()
	add_child(layout)
	var spec: Array = []
	for step in preload("res://scripts/levels/chapters/level10_layout.gd").STEPS:
		if step[0] == "ReturnStairMid": spec = step
	ok(not spec.is_empty())
	if spec.is_empty(): return
	layout.step(host, "Bed", Vector2(1472,352),432.0)
	layout.step(host, "AscendA", Vector2(1904,320),64.0)
	layout.step(host, "ReturnStairMid", spec[1],spec[2])
	var player := await spawn_player(host, Vector2(1856,328))
	var driver := DRIVER.new()
	driver.world = host
	add_child(driver)
	driver._nv_goal = Vector2(1936,320)
	ok(await driver._nv_cross(_segment(Rect2(1472,352,432,16)),
			_segment(Rect2(1904,320,64,16))), "authored canopy leaves room for the full jump")
	almost(player.position.y,320.0,1.0)
	ok(not player.controller.extra_jumps_unlocked)
	driver._release()


func test_finale_east_stair_has_headroom_on_the_post_boss_exit_route() -> void:
	var host := _host()
	var layout := ChapterLayout.new()
	add_child(layout)
	var spec: Array=[]
	for step in preload("res://scripts/levels/chapters/level10_layout.gd").STEPS:
		if step[0] == "RingStairEastMid": spec=step
	ok(not spec.is_empty())
	if spec.is_empty(): return
	layout.step(host,"ArenaFloor",Vector2(2352,320),1472.0)
	layout.step(host,"EastMid",spec[1],spec[2])
	layout.step(host,"EastLow",Vector2(3824,288),64.0)
	var player := await spawn_player(host,Vector2(3776,296))
	var driver := DRIVER.new()
	driver.world=host
	add_child(driver)
	driver._nv_goal=Vector2(3850,288)
	ok(await driver._nv_cross(_segment(Rect2(2352,320,1472,16)),
			_segment(Rect2(3824,288,64,16))),"single jump clears the authored east stair canopy")
	almost(player.position.y,288.0,1.0)
	ok(not player.controller.extra_jumps_unlocked)
	driver._release()


func test_finale_gallery_does_not_claim_a_drop_through_the_stair_below_it() -> void:
	var host := _host()
	var layout := ChapterLayout.new()
	add_child(layout)
	layout.step(host,"Floor",Vector2(2352,320),1472.0)
	layout.step(host,"MidStair",Vector2(2352,256),64.0)
	layout.step(host,"Gallery",Vector2(2416,224),288.0)
	layout.step(host,"Pillar",Vector2(2544,192),64.0)
	var player := await spawn_player(host,Vector2(2432,200))
	var driver := DRIVER.new()
	driver.world=host
	add_child(driver)
	driver._nv_goal=Vector2(2800,320)
	ok(not driver._nv_drop_side_clear(Rect2(2416,224,128,16),Rect2(2352,320,1472,16),false),
			"west stair catches the body before the claimed lower floor")
	var route := driver._nv_path(driver._nv_segments(),driver._nv_goal)
	ok(not route.is_empty(),"real stair/pillar route exists")
	for i in range(1,route.size()):
		var crossed: bool=await driver._nv_cross(route[i-1],route[i])
		ok(crossed,"normal input follows actual landing %d" % i)
		if not crossed:
			driver._release()
			return
	almost(player.position.y,320.0,1.0)
	driver._release()


func test_slag_return_lift_walks_off_its_clear_edge_onto_the_lower_floor() -> void:
	var host := _host()
	var layout := ChapterLayout.new()
	add_child(layout)
	layout.step(host, "FoundryShelf", Vector2(1904,128),496.0)
	layout.step(host, "QuenchFloor", Vector2(2400,320),448.0)
	var lift := layout.lift(host, "ReturnLift",Vector2(2400,128),Vector2(0,-64),8.0,64.0,0.0,0.0)
	var player := await spawn_player(host,Vector2(2432,104))
	var driver := DRIVER.new()
	driver.world = host
	add_child(driver)
	driver._nv_goal = Vector2(2614,320)
	var from := {"r":Rect2(2400,128,64,16),"lift":lift}
	var to := _segment(Rect2(2400,320,448,16))
	ok(driver._nv_link(from,to),"real lift has a clear east walk-off")
	ok(await driver._nv_cross(from,to),"normal input leaves the live lift instead of jumping in place")
	almost(player.position.y,320.0,1.0)
	ok(player.position.x > 2464.0)
	ok(not player.controller.extra_jumps_unlocked)
	almost(lift.period,8.0,0.001,"navigation never freezes the live lift")
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
