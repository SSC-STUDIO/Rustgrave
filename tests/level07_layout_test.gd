extends TestCase
const L7 := preload("res://scripts/levels/chapters/level07_layout.gd")
const BOARDS := ["Floor", "GalleryA", "GalleryB", "GalleryC", "Summit", "GalleryD", "GalleryE"]
const LANDS := ["GalleryA", "GalleryB", "GalleryC", "Summit", "GalleryD", "GalleryE", "Crown"]


func setup() -> void:
	SaveData.flags.clear()
	Director._set_lock(false)


func teardown() -> void:
	_release()
	SaveData.flags.clear()
	Director._set_lock(false)
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)


func _release() -> void:
	for action in ["move_left", "move_right", "jump", "dash"]:
		Input.action_release(action)


func _build() -> Node2D:
	var host := Node2D.new()
	host.name = "Level07_Belltower"
	host.scene_file_path = GameContext.LEGACY_LEVELS["level07"]
	host.add_to_group("game_world")
	add_child(host)
	var layout := L7.new()
	add_child(layout)
	layout.build(host)
	return host


func _still(host: Node) -> void:
	for e in host.get_node("Enemies").get_children():
		e.set_physics_process(false)
	for p in host.get_node("Platforms").get_children():
		if p is MovingPlatform:
			p.set_physics_process(false)
	for h in LevelSanity.hazards(host):
		h.set_physics_process(false)
		(h.get_node("PendulumHitbox") as Hitbox).monitoring = false


func _top(host: Node, node_name: String) -> LevelSanity.TopSeg:
	for t in LevelSanity.top_segments(host):
		if t.owner_name == node_name:
			return t
	return null


func test_story_saves_vertical_identity_and_next_chapter_survive() -> void:
	var host := _build()
	var layout := L7.new()
	add_child(layout)
	eq(layout.title(), ChapterText.title_of("level07"))
	eq(layout.wake_line(), ChapterText.wake_of("level07"))
	eq(layout.theme(), "belltower")
	ok(layout.indoors())
	eq(layout.camera_top(), -1472)
	eq(L7.CEILING_Y, -1440.0)
	eq(320 - L7.TOP_Y, 1600.0)
	eq(layout.east_limit(), 1600)
	for path in ["Props/EmberNestEntry", "Props/EmberNestGallery", "Props/EmberNestSummit", "Props/EmberNestCrown",
		"Props/BellGatePlate", "Props/BellGateDoor", "Props/SteleChain", "Props/SteleBell", "Props/SteleNook", "Hooks/HookUpper", "Hooks/HookGallery"]:
		ok(host.get_node_or_null(path) != null, "v2 path: " + path)
	for name_ in ["SteleChain", "SteleBell", "SteleNook"]:
		var s := host.get_node("Props/" + name_) as LoreStele
		eq(s.lore_text, String(ChapterText.stele_of("level07", name_).get("text")))
	var exit := host.get_node("Props/Exit") as LevelExit
	eq(exit.position, L7.EXIT_POS)
	eq(exit.flag_id, "level07_done")
	eq(exit.target_scene, GameContext.LEGACY_LEVELS["level07b"])
	eq(exit.spawn, ChapterLayout.entry_spawn_of("level07b"))
	eq(exit.requires_flag, "")
	eq(host.get_node("Enemies").get_child_count(), 10)


func test_main_route_all_checkpoints_and_plate_are_basic_and_sane() -> void:
	var host := _build()
	var problems := LevelSanity.check(host)
	ok(problems.is_empty(), "sanity: %s" % [problems])
	for n in host.get_node("Props").get_children():
		if n is EmberNest or n is PressurePlate or n is LevelExit:
			ok(LevelSanity.is_reachable(host, L7.ENTRY_SPAWN, LevelSanity.feet_of(n), false), "basic route: " + str(n.name))
	for n in ["WestBellRoom", "EastWatchRoom"]:
		var t := _top(host, n)
		ok(LevelSanity.is_reachable(host, L7.ENTRY_SPAWN, Vector2(t.x0 + 32, t.y), false), "side room has a usable entrance: " + n)
	var gate := host.get_node("Props/BellGateDoor") as ArenaDoor
	var plate := host.get_node("Props/BellGatePlate") as PressurePlate
	ok(plate.activated.is_connected(gate.open_door))


func test_all_seven_shafts_have_rider_clearance_and_boardable_endpoints() -> void:
	var host := _build()
	eq(L7.LIFTS.size(), 7)
	for i in L7.LIFTS.size():
		var lift := host.get_node("Platforms/" + String(L7.LIFTS[i][0])) as MovingPlatform
		var a := lift.start_position()
		var b := lift.end_position()
		var swept := Rect2(b + Vector2(0, -32), Vector2(lift.width, a.y - b.y + 48))
		for p in host.get_node("Platforms").get_children():
			if p is SolidPlatform:
				ok(not swept.grow(-0.1).intersects(Rect2(p.position, p.size)), "%s rider never passes through %s" % [lift.name, p.name])
		ok(LevelSanity._can_hop(_top(host, BOARDS[i]), _top(host, str(lift.name) + "@start")), "board " + str(lift.name))
		ok(LevelSanity._can_hop(_top(host, str(lift.name) + "@end"), _top(host, LANDS[i])), "disembark " + str(lift.name))
		ok(lift.sync_to_physics)


func _ride_lifts(first: int, end: int) -> void:
	for i in range(first, end):
		var host := _build()
		_still(host)
		var lift := host.get_node("Platforms/" + String(L7.LIFTS[i][0])) as MovingPlatform
		var player := await spawn_player(host, lift.start_position() + Vector2(40, -24))
		player.controller.extra_jumps_unlocked = false
		ok(player.is_on_floor(), "boards real deck: " + str(lift.name))
		lift.set_physics_process(true)
		await flush(266)
		ok(player.position.y < lift.start_position().y - 140, "native physics carry: " + str(lift.name))
		var action := "move_left" if i in [1, 4] else "move_right"
		Input.action_press(action)
		Input.action_press("jump")
		await flush(46)
		_release()
		await flush(20)
		var land := _top(host, LANDS[i])
		ok(player.is_on_floor() and player.position.x >= land.x0 and player.position.x <= land.x1 and absf(player.position.y - land.y) < 2,
			"real single jump lands on %s from %s; feet %s" % [LANDS[i], lift.name, player.position])
		host.free()
		await flush(1)


func test_real_knight_rides_and_disembarks_lifts_A_B_with_single_jumps() -> void:
	await _ride_lifts(0, 2)


func test_real_knight_rides_and_disembarks_lifts_C_D_with_single_jumps() -> void:
	await _ride_lifts(2, 4)


func test_real_knight_rides_and_disembarks_lifts_E_F_with_single_jumps() -> void:
	await _ride_lifts(4, 6)


func test_real_knight_rides_and_disembarks_lift_G_with_a_single_jump() -> void:
	await _ride_lifts(6, 7)


func test_side_room_roofs_do_not_trap_the_east_retreat() -> void:
	var host := _build()
	_still(host)
	ok(host.get_node_or_null("Platforms/CeilingWestRoom") != null and host.get_node_or_null("Platforms/EastRoomWall") != null)
	# Jump at the doorway edge rather than spending the short jump over its floor.
	var player := await spawn_player(host, Vector2(1032, -424))
	player.controller.extra_jumps_unlocked = false
	Input.action_press("move_left")
	Input.action_press("jump")
	await flush(55)
	_release()
	await flush(20)
	ok(player.is_on_floor() and absf(player.position.y + 416) < 2, "east chamber retreats to LiftD's lower dock: %s" % player.position)
	Input.action_press("move_left")
	Input.action_press("jump")
	await flush(45)
	_release()
	await flush(20)
	ok(player.is_on_floor() and player.position.x < 912 and absf(player.position.y + 400) < 2,
		"retreat continues onto GalleryC without hook or extra jump: %s" % player.position)


func _check_nests(first: int, end: int) -> void:
	for index in range(first, end):
		var n: Array = L7.NESTS[index]
		var host := _build()
		var player := await spawn_player(host, Vector2(n[1], n[2] - 20))
		var hp := player.health.current
		for second in 6:
			await flush(60)
			eq(player.health.current, hp, "%s safe at second %d" % [n[0], second + 1])
			for e in host.get_node("Enemies").get_children():
				ok(e.position.distance_to(player.position) > 96, "%s remains outside %s" % [n[0], e.name])
		host.free()
		await flush(1)


func test_entry_and_lower_nests_are_safe_for_six_seconds_each() -> void:
	await _check_nests(0, 2)


func test_gallery_and_clapper_nests_are_safe_for_six_seconds_each() -> void:
	await _check_nests(2, 4)


func test_summit_and_high_nests_are_safe_for_six_seconds_each() -> void:
	await _check_nests(4, 6)


func test_upper_and_crown_nests_are_safe_for_six_seconds_each() -> void:
	await _check_nests(6, 8)


func test_real_landing_activates_the_middle_pressure_plate() -> void:
	var host := _build()
	_still(host)
	var door := host.get_node("Props/BellGateDoor") as ArenaDoor
	ok(not door.is_open)
	var player := await spawn_player(host, L7.PLATE_FEET - Vector2(0, 24))
	ok(player.is_on_floor() and door.is_open, "a basic landing on the original plate opens the original door")


func test_actual_alternating_checkpoint_paths_are_at_most_one_thousand_pixels() -> void:
	var host := _build()
	for i in 7:
		var from := Vector2(L7.NESTS[i][1], L7.NESTS[i][2])
		var to := Vector2(L7.NESTS[i + 1][1], L7.NESTS[i + 1][2])
		var lift := host.get_node("Platforms/" + String(L7.LIFTS[i][0])) as MovingPlatform
		var a := lift.start_position()
		var b := lift.end_position()
		var board_x := clampf(from.x, a.x + 8, a.x + lift.width - 8)
		var land_x := clampf(to.x, b.x + 8, b.x + lift.width - 8)
		var route := absf(from.x - board_x) + absf(from.y - a.y) + absf(a.y - b.y) + absf(board_x - land_x) + absf(to.x - land_x) + absf(to.y - b.y)
		ok(route <= 1000, "%s to %s including lift approaches: %.0fpx" % [L7.NESTS[i][0], L7.NESTS[i + 1][0], route])


func test_clappers_stay_clear_of_docks_and_have_generous_waiting_pads() -> void:
	var host := _build()
	for spec in L7.CLAPPERS:
		var p := host.get_node("Props/" + String(spec[0])) as PendulumHazard
		eq(p.skin, "clapper")
		ok(p.get_node_or_null("HazardHint") is HintArea)
		for m in L7.LIFTS:
			var lift := host.get_node("Platforms/" + String(m[0])) as MovingPlatform
			for feet in [lift.start_position(), lift.end_position()]:
				var rider := Rect2(feet + Vector2(0, -32), Vector2(lift.width, 48))
				ok(not p.danger_rect().grow(8).intersects(rider), "%s leaves the entire %s dock and rider clear" % [p.name, lift.name])
	for pair in [["ClapperLesson", "GalleryA"], ["ClapperWest", "WestBellRoom"]]:
		var p := host.get_node("Props/" + pair[0]) as PendulumHazard
		var t := _top(host, pair[1])
		ok(p.danger_rect().position.x - t.x0 >= 48 and t.x1 - p.danger_rect().end.x >= 48, "first lesson has two safe waiting pads")
		for e in host.get_node("Enemies").get_children():
			if e is SpitterEnemy and absf(e.position.y - t.y) > 96:
				continue
			var radius := float(e.get("wake_range")) if e is GhostEnemy or e is SkeletonEnemy else float(e.get("aggro_range"))
			ok(e.position.distance_to(Vector2(p.position.x, t.y)) > radius, "lesson is outside " + str(e.name))


func test_real_knight_can_wait_beside_a_full_live_swing_without_damage() -> void:
	var host := _build()
	_still(host)
	var player := await spawn_player(host, Vector2(632, 60))
	var hp := player.health.current
	var p := host.get_node("Props/ClapperLesson") as PendulumHazard
	p._arm(1)
	p.set_physics_process(true)
	await flush(360)
	eq(player.health.current, hp, "a full swing cycle leaves the authored waiting pad safe")
	ok(player.is_on_floor())


func test_real_knight_crosses_the_clapper_with_basic_jump_and_dash() -> void:
	var host := _build()
	_still(host)
	var player := await spawn_player(host, Vector2(648, 60))
	player.controller.extra_jumps_unlocked = false
	var hp := player.health.current
	var p := host.get_node("Props/ClapperLesson") as PendulumHazard
	# Read the bottom pass toward the near side, then jump / dash through it.
	p._t = p.period * 0.5
	p._sync_head()
	p._arm(1)
	p.set_physics_process(true)
	Input.action_press("move_right")
	await flush(20)
	Input.action_press("jump")
	await flush(12)
	Input.action_press("dash")
	await flush(73)
	_release()
	await flush(12)
	ok(player.position.x > p.danger_rect().end.x + 8, "jump / dash reaches the far waiting pad: %s" % player.position)
	eq(player.health.current, hp, "reading the visible swing permits a damage-free crossing")


func test_real_west_room_return_jumps_from_the_dock_back_to_the_main_gallery() -> void:
	var host := _build()
	_still(host)
	var lift := host.get_node("Platforms/LiftA") as MovingPlatform
	# This case parks the authored endpoint; the separate rider tests run all seven lifts live.
	lift.position = lift.end_position()
	var player := await spawn_player(host, Vector2(348, 60))
	player.controller.extra_jumps_unlocked = false
	Input.action_press("move_right")
	Input.action_press("jump")
	await flush(43)
	_release()
	await flush(20)
	ok(player.is_on_floor() and absf(player.position.y - 64) < 2, "single jump leaves the western reward chamber: %s" % player.position)
	Input.action_press("move_right")
	Input.action_press("jump")
	await flush(46)
	_release()
	await flush(20)
	ok(player.is_on_floor() and player.position.x >= 480 and absf(player.position.y - 80) < 2, "the same dock returns to the main gallery: %s" % player.position)


func test_real_clapper_head_damages_an_exposed_knight() -> void:
	var host := _build()
	_still(host)
	var player := await spawn_player(host, Vector2(736, 60))
	var hp := player.health.current
	var p := host.get_node("Props/ClapperLesson") as PendulumHazard
	p._t = 0
	p._sync_head()
	p._arm(1)
	await flush(12)
	eq(player.health.current, hp - 1, "the drawn bell tongue uses its real hitbox")


func test_crown_drop_really_lands_near_the_previous_summit_nest() -> void:
	var host := _build()
	_still(host)
	var player := await spawn_player(host, Vector2(1336, -1300))
	var hp := player.health.current
	Input.action_press("move_right")
	await flush(35)
	_release()
	await flush(180)
	ok(player.is_on_floor() and absf(player.position.y + 640) < 2, "open eastern fall shaft lands on Summit, not a room roof: %s" % player.position)
	ok(player.position.distance_to(Vector2(1264, -640)) <= 200, "shortcut lands close to the old Summit nest")
	eq(player.health.current, hp)
	ok(LevelSanity._can_hop(_top(host, "Crown"), _top(host, "Summit")) and not LevelSanity._can_hop(_top(host, "Summit"), _top(host, "Crown")), "shortcut only descends")


func test_west_reward_and_hook_only_roof_nook_are_optional() -> void:
	var host := _build()
	var reward := host.get_node("Props/RewardClapper") as EquipmentPickup
	eq(reward.reward_ref, "bone_amulet")
	var support := LevelSanity.standing_on(LevelSanity.top_segments(host), LevelSanity.feet_of(reward))
	ok(support != null and support.owner_name == "WestBellRoom")
	var p := host.get_node("Props/ClapperWest") as PendulumHazard
	ok(reward.position.x + 48 <= p.danger_rect().position.x, "reward lies beyond the clapper on a safe pad")
	var nook := host.get_node("Props/SteleNook") as LoreStele
	ok(not LevelSanity.is_reachable(host, L7.ENTRY_SPAWN, LevelSanity.feet_of(nook), false))
	ok(LevelSanity.is_reachable(host, L7.ENTRY_SPAWN, LevelSanity.feet_of(nook), true))
	eq((host.get_node("Enemies/Skeleton2") as EnemyBase).variant, &"exploder_skeleton")
	var chamber := _top(host, "EastWatchRoom")
	ok(1240 - chamber.x0 > 160 and chamber.x1 - 1240 > 160, "exploder has room to retreat on both sides")
