extends TestCase
## Three-tier workshop acceptance with real riders, conveyor motion, steam and safe respawns.
const L5 := preload("res://scripts/levels/chapters/level05_layout.gd")


func setup() -> void:
	SaveData.flags.clear()
	Director._set_lock(false)


func teardown() -> void:
	for action in ["move_left", "move_right", "jump"]:
		Input.action_release(action)
	SaveData.flags.clear()
	Director._set_lock(false)
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)


func _build() -> Node2D:
	var host := Node2D.new()
	host.name = "Level05_Workshop"
	host.scene_file_path = GameContext.LEGACY_LEVELS["level05"]
	host.add_to_group("game_world")
	add_child(host)
	var layout := L5.new()
	add_child(layout)
	layout.build(host)
	return host


func _rect(host: Node, node_name: String) -> Rect2:
	var p := host.get_node("Platforms/" + node_name) as SolidPlatform
	return Rect2(p.position, p.size)


func _deck(lift: MovingPlatform, at_end: bool) -> Rect2:
	return Rect2(lift.end_position() if at_end else lift.start_position(), Vector2(lift.width, 16))


func _hop(a: Rect2, b: Rect2) -> bool:
	var rise := a.position.y - b.position.y
	var gap := maxf(0, maxf(b.position.x - a.end.x, a.position.x - b.end.x))
	return rise <= 32 and gap <= minf(160, 72 + maxf(0, -rise) * 0.5)


func _still(host: Node, stop_lifts: bool = true) -> void:
	for e in host.get_node("Enemies").get_children():
		e.set_physics_process(false)
	for h in LevelSanity.hazards(host):
		h.set_physics_process(false)
		if h is CyclicHazard:
			h._set_armed(false)
	if stop_lifts:
		for p in host.get_node("Platforms").get_children():
			if p is MovingPlatform:
				p.set_physics_process(false)


func test_metadata_story_order_and_v2_paths_survive() -> void:
	var host := _build()
	var layout := L5.new()
	add_child(layout)
	eq(layout.title(), ChapterText.title_of("level05"))
	eq(layout.wake_line(), ChapterText.wake_of("level05"))
	eq(layout.theme(), "industrial")
	ok(layout.indoors())
	eq(layout.entry_spawn(), Vector2(96, 300))
	for path in ["Props/EmberNestStart", "Props/EmberNestLift", "Props/EmberNestGate", "Props/EmberNestHoist",
		"Props/GateAPlate", "Props/GateADoor", "Props/GateBPlate", "Props/GateBDoor", "Props/RustGate",
		"Props/SteleQuench", "Props/SteleChain", "Props/SteleNook", "Pickups/TetherCoreE", "Pickups/RewardHoist"]:
		ok(host.get_node_or_null(path) != null, "stable v2 path: " + path)
	var exit := host.get_node("Props/Exit") as LevelExit
	eq(exit.flag_id, "level05_done")
	eq(exit.target_scene, GameContext.LEGACY_LEVELS["level06"])
	eq(exit.spawn, ChapterLayout.entry_spawn_of("level06"))
	ok(L5.EAST - exit.position.x >= 80)
	for node_name in ["SteleQuench", "SteleChain", "SteleNook"]:
		var stele := host.get_node("Props/" + node_name) as LoreStele
		eq(stele.lore_text, String(ChapterText.stele_of("level05", node_name).get("text")))


func test_sanity_and_every_mainline_target_need_only_basic_moves() -> void:
	var host := _build()
	var problems := LevelSanity.check(host)
	ok(problems.is_empty(), "sanity: %s" % [problems])
	for node in LevelSanity._descendants(host):
		if node is EmberNest or node is PressurePlate or node is LevelExit or node is RustyGate or node is CorePickup:
			ok(LevelSanity.is_reachable(host, L5.SPAWN, LevelSanity.feet_of(node), false),
				"main route needs no hook / extra jump: %s" % node.name)
	var core := host.get_node("Pickups/TetherCoreE") as CorePickup
	eq(core.core.id, &"tether_core")
	ok(_rect(host, "WalkE").has_point(core.position + Vector2(0, 33)), "core sits above the stair-accessible service walk")


func test_three_distinct_floors_are_traversable_and_stairs_work_both_ways() -> void:
	var host := _build()
	for chain in L5.STAIR_CHAINS:
		for i in range(1, chain.size()):
			ok(_hop(_rect(host, chain[i - 1]), _rect(host, chain[i])), "%s → %s is a single jump" % [chain[i - 1], chain[i]])
	for point in [Vector2(1080, 224), Vector2(1480, 112), Vector2(1808, 112), Vector2(2008, 224), Vector2(2768, 224), Vector2(3264, 112)]:
		ok(LevelSanity.is_reachable(host, L5.SPAWN, point, false), "real three-tier route reaches %s" % point)
		ok(LevelSanity.is_reachable(host, point, Vector2(L5.NEST_HOIST_X, 320), false), "every tier returns to the lower route")
	ok(320 - _rect(host, "DeckD").position.y >= 200, "top rail is substantially higher than the machine floor")
	var pools := 0
	for n in LevelSanity._descendants(host):
		if n is ToxinPool:
			pools += 1
	eq(pools, 0, "the old acid-and-stones corridor has been replaced")


func test_five_lifts_dock_and_relay_without_passing_through_solids() -> void:
	var host := _build()
	var d := host.get_node("Platforms/LiftD") as MovingPlatform
	var c := host.get_node("Platforms/LiftC") as MovingPlatform
	var f := host.get_node("Platforms/LiftF") as MovingPlatform
	var e1 := host.get_node("Platforms/LiftE1") as MovingPlatform
	var e2 := host.get_node("Platforms/LiftE2") as MovingPlatform
	ok(_hop(_rect(host, "FloorB"), _deck(d, false)), "D boards from the machine floor")
	ok(_hop(_deck(d, true), _rect(host, "DeckD")), "D lands beside pressure plate B")
	ok(_hop(_rect(host, "DeckD"), _deck(c, false)), "drop from top deck boards C")
	ok(_hop(_deck(c, true), _rect(host, "MidLanding")), "C delivers to the middle dock")
	ok(_hop(_rect(host, "WalkE"), _deck(f, false)), "F boards from the core walkway")
	ok(_hop(_deck(f, true), _deck(e1, false)), "F connects to the top relay")
	ok(_hop(_deck(e1, true), _deck(e2, false)), "relay decks meet across a 16px gap")
	ok(_hop(_deck(e2, true), _rect(host, "HoistRailEnd")), "relay lands on its static return deck")
	almost(absf(e1.phase - e2.phase), 0.5)
	almost(e1.period, e2.period)
	for lift in [c, d, f, e1, e2]:
		ok(lift.sync_to_physics, "%s carries riders" % lift.name)
		var a: Vector2 = lift.start_position()
		var b: Vector2 = lift.end_position()
		var swept := Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), Vector2(absf(a.x - b.x) + lift.width, absf(a.y - b.y) + 16))
		for p in host.get_node("Platforms").get_children():
			if p is SolidPlatform:
				ok(not swept.grow(-0.1).intersects(Rect2(p.position, p.size)), "%s never cuts through %s" % [lift.name, p.name])


func test_real_player_rides_D_and_jumps_to_the_upper_plate_deck() -> void:
	var host := _build()
	_still(host, false)
	var player := await spawn_player(host, Vector2(1272, 270))
	player.controller.extra_jumps_unlocked = false
	await flush(158)
	ok(player.position.y < 150, "native platform carrying lifts the real knight to the upper tier")
	Input.action_press("move_right")
	Input.action_press("jump")
	await flush(30)
	Input.action_release("jump")
	Input.action_release("move_right")
	await flush(18)
	ok(player.is_on_floor() and player.position.x >= 1312 and player.position.y < 118,
		"single jump disembarks onto DeckD without hook / extra jump")


func test_plate_wiring_is_independent_and_core_walk_has_east_return_steps() -> void:
	var host := _build()
	_still(host)
	for pair in ["GateA", "GateB"]:
		var plate := host.get_node("Props/" + pair + "Plate") as PressurePlate
		var door := host.get_node("Props/" + pair + "Door") as ArenaDoor
		ok(plate.activated.is_connected(door.open_door))
		plate.activated.emit()
		ok(door.is_open)
	var a := host.get_node("Props/GateAPlate") as PressurePlate
	var b := host.get_node("Props/GateBDoor") as ArenaDoor
	ok(not a.activated.is_connected(b.open_door), "A does not silently open B")
	var player := await spawn_player(host, Vector2(3384, 300))
	player.controller.extra_jumps_unlocked = false
	Input.action_press("move_left")
	Input.action_press("jump")
	await flush(26)
	Input.action_release("jump")
	Input.action_release("move_left")
	await flush(16)
	ok(player.is_on_floor() and player.position.y < 292, "falling east of the service walk retains a physical recovery stair")


func test_conveyor_teaching_has_real_motion_and_warned_reversal() -> void:
	var host := _build()
	_still(host)
	var belt := host.get_node("Platforms/QuenchBelt") as ConveyorBelt
	var player := await spawn_player(host, Vector2(552, 300))
	var start_x := player.position.x
	await flush(45)
	ok(player.position.x > start_x + 16, "the authored belt carries a standing real knight")
	var reverse := host.get_node("Platforms/ReturnBelt") as ConveyorBelt
	almost(reverse.velocity_at(1.0), -36)
	almost(reverse.velocity_at(5.0), 0, 0.001, "0.6s stop telegraphs reversal")
	almost(reverse.velocity_at(5.5), 36)
	ok(absf(reverse.speed) <= ConveyorBelt.MAX_SPEED)
	ok(belt.get_node_or_null("HazardHint") is HintArea)


func test_steam_is_separate_from_belts_and_first_meet_has_safe_landing_pads() -> void:
	var host := _build()
	var first := host.get_node("Props/SteamQuench") as CyclicHazard
	var band := first.hit_rect()
	ok(band.position.x - 1568 >= 48 and 1728 - band.end.x >= 48, "first vent has at least 48px clear pads on both sides")
	for vent_spec in L5.VENTS:
		var vent := host.get_node("Props/" + String(vent_spec[0])) as CyclicHazard
		ok(vent.telegraph_time >= 0.5 and vent.rest_time + vent.telegraph_time >= 1.2)
		ok(vent.get_node_or_null("HazardHint") is HintArea)
		for belt_spec in L5.BELTS:
			var belt_rect := _rect(host, belt_spec[0])
			ok(vent.hit_rect().end.x + 48 <= belt_rect.position.x or vent.hit_rect().position.x - 48 >= belt_rect.end.x,
				"vent %s and belt %s are in separate horizontal sections" % [vent.name, belt_spec[0]])
	for e in host.get_node("Enemies").get_children():
		if e is SpitterEnemy and absf(e.position.y - 288) > 96:
			continue
		var radius := float(e.get("wake_range")) if e is GhostEnemy else float(e.get("aggro_range"))
		ok(e.position.distance_to(Vector2(1648, 288)) > radius, "first steam lesson is outside %s's wake / fire range" % e.name)


func test_real_player_can_cross_the_first_steam_during_its_safe_window() -> void:
	var host := _build()
	_still(host)
	var player := await spawn_player(host, Vector2(1584, 268))
	var hp := player.health.current
	var wave := host.get_node("Props/SteamQuench") as CyclicHazard
	ok(wave.safe_window(1.4), "the safe interval covers a normal walk across")
	wave.set_physics_process(true)
	Input.action_press("move_right")
	await flush(76)
	Input.action_release("move_right")
	ok(player.position.x > 1704, "normal movement crosses the authored steam corridor")
	eq(player.health.current, hp, "the timed crossing is damage free")


func test_exposed_player_is_hurt_by_active_steam_but_safe_pad_is_clear() -> void:
	var host := _build()
	_still(host)
	var player := await spawn_player(host, Vector2(1648, 268))
	var hp := player.health.current
	var wave := host.get_node("Props/SteamQuench") as CyclicHazard
	wave.tick(wave.seconds_until_active() + 0.3)
	await flush(8)
	eq(player.health.current, hp - 1, "the steam uses its real hitbox")
	var safe := Vector2(1584, 288)
	ok(not wave.hit_rect().grow(16).has_point(safe), "the nearby waiting pad stays outside damage")


func test_all_four_nests_remain_safe_with_six_seconds_of_live_enemy_AI() -> void:
	for x in [L5.NEST_START_X, L5.NEST_LIFT_X, L5.NEST_GATE_X, L5.NEST_HOIST_X]:
		var host := _build()
		var player := await spawn_player(host, Vector2(x + 6, 300))
		var hp := player.health.current
		await flush(360)
		eq(player.health.current, hp, "nest x=%s remains unharmed for six seconds" % x)
		for e in host.get_node("Enemies").get_children():
			ok(e.position.distance_to(player.position) > 96, "nest %s never attracts %s" % [x, e.name])
		host.free()
		await flush(1)
	var gaps := [L5.NEST_LIFT_X - L5.NEST_START_X, L5.NEST_GATE_X - L5.NEST_LIFT_X, L5.NEST_HOIST_X - L5.NEST_GATE_X]
	for gap in gaps:
		ok(gap <= 1000, "checkpoint spacing stays under 1000px")
	ok(L5.EXIT_X - L5.NEST_HOIST_X < 1000)


func test_top_return_drop_and_hook_reward_branches_are_optional() -> void:
	var host := _build()
	var tops := LevelSanity.top_segments(host)
	var rail := LevelSanity.standing_on(tops, Vector2(432, 112))
	var floor_seg := LevelSanity.standing_on(tops, Vector2(376, 320))
	ok(LevelSanity._can_hop(rail, floor_seg) and not LevelSanity._can_hop(floor_seg, rail), "western rail drops one way near the previous nest")
	ok(absf(376 - L5.NEST_START_X) <= 240)
	for path in ["Props/SteleNook", "Pickups/RewardHoist"]:
		var node := host.get_node(path)
		ok(not LevelSanity.is_reachable(host, L5.SPAWN, LevelSanity.feet_of(node), false), "optional route remains hook only: " + path)
		ok(LevelSanity.is_reachable(host, L5.SPAWN, LevelSanity.feet_of(node), true), "hook reaches " + path)
	var reward := host.get_node("Pickups/RewardHoist") as EquipmentPickup
	eq(reward.reward_ref, "iron_carapace")
	var support := LevelSanity.standing_on(tops, LevelSanity.feet_of(reward))
	ok(support != null and support.owner_name == "HoistDeck", "reward sits on stable challenge support")
	var vent := host.get_node("Props/SteamHoist") as CyclicHazard
	ok(reward.position.x > vent.hit_rect().end.x + 48, "the reward waits beyond the optional vent with a safe landing")
	eq((host.get_node("Enemies/Scrapper1") as EnemyBase).variant, &"armored_scrapper")
	eq((host.get_node("Enemies/GearShield1") as EnemyBase).variant, &"heavy_guard")
	eq(host.get_node("Enemies").get_child_count(), 10)
