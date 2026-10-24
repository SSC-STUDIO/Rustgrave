extends TestCase
const L8 := preload("res://scripts/levels/chapters/level08_layout.gd")


func setup() -> void:
	SaveData.flags.clear()
	Director._set_lock(false)


func teardown() -> void:
	_release()
	SaveData.flags.clear()
	Director._set_lock(false)
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)


func _release() -> void:
	for a in ["move_left", "move_right", "jump", "dash"]:
		Input.action_release(a)


func _build() -> Node2D:
	var host := Node2D.new()
	host.name = "Level08_SlagDepths"
	host.scene_file_path = GameContext.LEVELS["level08"]
	host.add_to_group("game_world")
	add_child(host)
	var layout := L8.new()
	add_child(layout)
	layout.build(host)
	return host


func _still(host: Node) -> void:
	for e in host.get_node("Enemies").get_children():
		e.process_mode = Node.PROCESS_MODE_DISABLED
		for box in e.find_children("*", "", true, false):
			if box is Hitbox:
				(box as Hitbox).disarm()
	for p in host.get_node("Platforms").get_children():
		if p is MovingPlatform:
			p.set_physics_process(false)
	for h in LevelSanity.hazards(host):
		h.set_physics_process(false)
		(h as CyclicHazard)._set_armed(false)


func _top(host: Node, node_name: String) -> LevelSanity.TopSeg:
	for t in LevelSanity.top_segments(host):
		if t.owner_name == node_name:
			return t
	return null


func _walk_to(player: Player, x: float) -> void:
	Input.action_press("move_right")
	ok(await wait_until(func() -> bool: return player.position.x >= x, 450), "walk to %.0f, feet %s" % [x, player.position])
	_release()
	await flush(4)


func _jump_right(frames: int = 50, use_dash: bool = false) -> void:
	Input.action_press("move_right")
	Input.action_press("jump")
	if use_dash:
		await flush(12)
		Input.action_press("dash")
		await flush(frames - 12)
	else:
		await flush(frames)
	_release()
	await flush(20)


func test_story_save_paths_and_indoor_forge_identity_survive() -> void:
	var host := _build()
	var layout := L8.new()
	add_child(layout)
	eq(layout.title(), ChapterText.title_of("level08"))
	eq(layout.wake_line(), ChapterText.wake_of("level08"))
	eq(layout.east_limit(), 4200)
	eq(layout.camera_top(), -48)
	eq(layout.theme(), "forge")
	ok(layout.indoors())
	for path in ["Props/EmberNestStart", "Props/EmberNestMid", "Props/EmberNestGate", "Props/EmberNestShell",
		"Props/SluicePlate", "Props/SluiceDoor", "Props/RustGate", "Props/SteleSlag", "Props/SteleQuench",
		"Props/SteleVent", "Props/Exit", "Hooks/HookVent", "Pickups/RewardOldHull"]:
		ok(host.get_node_or_null(path) != null, "v2 path: " + path)
	for name_ in ["SteleSlag", "SteleQuench", "SteleVent"]:
		eq((host.get_node("Props/" + name_) as LoreStele).lore_text, String(ChapterText.stele_of("level08", name_).get("text")))
	var exit := host.get_node("Props/Exit") as LevelExit
	eq(exit.flag_id, "level08_done")
	eq(exit.target_scene, GameContext.LEVELS["level09"])
	eq(exit.spawn, ChapterLayout.entry_spawn_of("level09"))
	eq(exit.requires_flag, "")
	ok(4200 - exit.position.x >= 80)
	ok(host.get_node("IndoorZone") is AtmosphereZone)
	ok(host.get_node("ParallaxBackdrop") is CanvasLayer)
	ok(host.get_node("Decor").get_child_count() >= 25)


func test_mainline_props_are_sane_and_need_no_hook_or_extra_jump() -> void:
	var host := _build()
	var problems := LevelSanity.check(host)
	ok(problems.is_empty(), "sanity: %s" % [problems])
	var tops := LevelSanity.top_segments(host)
	for n in host.get_node("Props").get_children():
		if n is EmberNest or n is PressurePlate or n is LevelExit or n is RustyGate:
			var feet := LevelSanity.feet_of(n)
			ok(LevelSanity.standing_on(tops, feet) != null, "support: " + str(n.name))
			ok(LevelSanity.is_reachable(host, L8.ENTRY_SPAWN, feet, false), "basic route: " + str(n.name))
	eq(host.get_node("Enemies").get_child_count(), 11)
	eq((host.get_node("Enemies/Scrapper1") as EnemyBase).variant, &"armored_scrapper")
	eq((host.get_node("Enemies/GearShield1") as EnemyBase).variant, &"heavy_guard")
	for e in host.get_node("Enemies").get_children():
		if not (e is GhostEnemy or e is FireSkullEnemy):
			ok(LevelSanity.standing_on(tops, e.position, 4, 4) != null, "enemy support: " + str(e.name))


func test_three_dark_slag_rivers_have_two_open_shallow_recovery_lips() -> void:
	var host := _build()
	eq(L8.PITS.size(), 3, "seven repetitive pits become three rivers")
	for spec in L8.PITS:
		var pool := host.get_node("Props/" + String(spec[0]) + "Pool") as ToxinPool
		var bed := host.get_node("Platforms/" + String(spec[0]) + "Bed") as SolidPlatform
		var r := pool.surface_rect()
		eq(pool.sludge_ramp.size(), 5)
		ok(pool.tint.r <= 1.6 and pool.tint.r > pool.tint.g and pool.tint.g > pool.tint.b)
		almost(bed.position.y, r.position.y + 16)
		eq(bed.skin, "basalt")
		for x in [r.position.x - 2, r.end.x + 2]:
			var lip := LevelSanity.standing_on(LevelSanity.top_segments(host), Vector2(x, 320))
			ok(lip != null and bed.position.y - lip.y <= 32, "each bank is one recovery jump: " + str(pool.name))
	var top: Color = L8.SLAG_RAMP[4]
	ok(maxf(top.r, maxf(top.g, top.b)) <= 0.75, "scum is dark slag brown")


func test_fountains_have_distinct_readable_rhythms_and_safe_island_pads() -> void:
	var host := _build()
	eq(L8.ISLANDS.size(), 4, "wide timed islands replace short stone chains")
	for spec in L8.FOUNTAINS:
		var h := host.get_node("Props/" + String(spec[0])) as CyclicHazard
		var island := _top(host, spec[2])
		eq(h.skin, "slag")
		ok(h.get_node_or_null("HazardHint") is HintArea)
		ok(h.telegraph_time >= 0.5 and h.rest_time + h.telegraph_time >= 1.2)
		ok(h.hit_rect().position.x - island.x0 >= 48 and island.x1 - h.hit_rect().end.x >= 48, "two waiting pads: " + str(h.name))
		ok(island.x1 - island.x0 >= 128)
	var lesson := host.get_node("Props/FountainLesson") as CyclicHazard
	var fast := host.get_node("Props/FountainFastA") as CyclicHazard
	ok(lesson.rest_time > fast.rest_time and lesson.active_time < fast.active_time, "second river asks for a shorter opening after a longer eruption")
	for e in host.get_node("Enemies").get_children():
		ok(e.position.distance_to(lesson.position) > 240, "first fountain is taught outside enemy pressure")


func test_checkpoint_route_lengths_include_ascent_and_island_banks() -> void:
	var host := _build()
	var vertical_cost := [32.0, 192.0, 192.0, 32.0, 0.0]
	for i in range(L8.NESTS.size() - 1):
		var a: Array = L8.NESTS[i]
		var b: Array = L8.NESTS[i + 1]
		var cost: float = float(b[1]) - float(a[1]) + float(vertical_cost[i])
		ok(cost <= 1000, "%s to %s including height changes: %.0fpx" % [a[0], b[0], cost])
	for i in range(1, 6):
		var before := _top(host, "FloorB" if i == 1 else "Climb%d" % (i - 1))
		var after := _top(host, "Climb%d" % i)
		ok(LevelSanity._can_hop(before, after), "single step climb %d" % i)
	ok(LevelSanity._can_hop(_top(host, "Climb5"), _top(host, "FloorC")))


func _nest_safety(first: int, end: int) -> void:
	for i in range(first, end):
		var n: Array = L8.NESTS[i]
		var host := _build()
		var p := await spawn_player(host, Vector2(n[1], n[2] - 20))
		var hp := p.health.current
		eq(hp, p.health.max_hp, "%s also starts its rest unharmed" % n[0])
		for second in 6:
			await flush(60)
			eq(p.health.current, hp, "%s HP after second %d" % [n[0], second + 1])
			for e in host.get_node("Enemies").get_children():
				ok(e.position.distance_to(p.position) > 96, "%s outside %s at second %d" % [n[0], e.name, second + 1])
		host.free()
		await flush(1)


func test_start_and_river_nests_are_safe_for_six_seconds_each() -> void:
	await _nest_safety(0, 2)


func test_mid_and_gate_nests_are_safe_for_six_seconds_each() -> void:
	await _nest_safety(2, 4)


func test_fountain_and_shell_nests_are_safe_for_six_seconds_each() -> void:
	await _nest_safety(4, 6)


func test_fire_skulls_stay_in_the_low_corridor_and_away_from_rest_points() -> void:
	var host := _build()
	var floor_b := _top(host, "FloorB")
	for name_ in ["FireSkull1", "FireSkull2", "FireSkull3", "FireSkull4"]:
		var skull := host.get_node("Enemies/" + name_) as FireSkullEnemy
		var above_head := 320 - 26 - skull.position.y
		ok(above_head >= 40 and above_head <= 70)
		ok(skull.arena_left >= 1280 and skull.arena_right <= floor_b.x1)
		ok(skull.position.x - skull.patrol_range > 1120 + 160, "patrol never crowds the river nest")
		ok(skull.arena_right < L8.NESTS[3][1] - 160, "skulls cannot crowd the gate or exit nests")


func test_real_knight_crosses_first_river_with_single_jump_and_dash() -> void:
	var host := _build()
	_still(host)
	var p := await spawn_player(host, Vector2(400, 300))
	p.controller.extra_jumps_unlocked = false
	var hp := p.health.current
	await _jump_right(50, true)
	ok(p.is_on_floor() and p.position.x >= 464 and absf(p.position.y - 304) < 2, "first island: %s" % p.position)
	await _walk_to(p, 672)
	await _jump_right(50, true)
	ok(p.is_on_floor() and p.position.x >= 744 and absf(p.position.y - 304) < 2, "second wide island: %s" % p.position)
	await _walk_to(p, 992)
	await _jump_right(50, true)
	ok(p.is_on_floor() and p.position.x >= 1056 and absf(p.position.y - 320) < 2, "river bank: %s" % p.position)
	eq(p.health.current, hp)


func test_real_knight_crosses_second_river_with_single_jump_and_dash() -> void:
	var host := _build()
	_still(host)
	var p := await spawn_player(host, Vector2(2832, 300))
	p.controller.extra_jumps_unlocked = false
	var hp := p.health.current
	await _jump_right(50, true)
	ok(p.is_on_floor() and p.position.x >= 2896 and absf(p.position.y - 304) < 2, "fast island one: %s" % p.position)
	await _walk_to(p, 3088)
	await _jump_right(50, true)
	ok(p.is_on_floor() and p.position.x >= 3160 and absf(p.position.y - 304) < 2, "fast island two: %s" % p.position)
	await _walk_to(p, 3360)
	await _jump_right(50, true)
	ok(p.is_on_floor() and p.position.x >= 3424 and absf(p.position.y - 320) < 2, "fast river bank: %s" % p.position)
	eq(p.health.current, hp)


func test_real_knight_climbs_six_steps_and_drops_back_to_the_valley() -> void:
	var host := _build()
	_still(host)
	var p := await spawn_player(host, Vector2(1648, 300))
	p.controller.extra_jumps_unlocked = false
	for i in 6:
		await _walk_to(p, 1656 + i * 48)
		await _jump_right(50)
		ok(p.is_on_floor(), "climb %d feet %s" % [i + 1, p.position])
	ok(absf(p.position.y - 128) < 2 and p.position.x >= 1904, "main path really reaches the high shelf: %s" % p.position)
	(host.get_node("Props/SluiceDoor") as ArenaDoor).open_door()
	await _walk_to(p, 2488)
	await flush(90)
	ok(p.is_on_floor() and absf(p.position.y - 320) < 2, "falls back into the lower valley: %s" % p.position)


func test_real_return_lift_and_drop_land_near_the_previous_nest() -> void:
	var host := _build()
	_still(host)
	var lift := host.get_node("Platforms/ReturnLift") as MovingPlatform
	var p := await spawn_player(host, Vector2(2392, 108))
	p.controller.extra_jumps_unlocked = false
	var hp := p.health.current
	await _walk_to(p, 2432)
	ok(p.is_on_floor() and p.position.x > 2400 and p.position.x < 2464, "walk onto the flush high return dock: %s" % p.position)
	lift.set_physics_process(true)
	await flush(240)
	ok(p.position.y < 80, "real moving deck raises the rider onto the return route: %s" % p.position)
	Input.action_press("move_left")
	Input.action_press("jump")
	await flush(12)
	Input.action_press("dash")
	await flush(38)
	_release()
	await flush(20)
	ok(p.is_on_floor() and absf(p.position.y - 64) < 2, "lands on return gallery: %s" % p.position)
	Input.action_press("move_left")
	ok(await wait_until(func() -> bool: return p.position.x <= 1256, 750))
	_release()
	await flush(90)
	ok(p.is_on_floor() and absf(p.position.y - 320) < 2, "western edge drops to the river bank: %s" % p.position)
	ok(p.position.distance_to(Vector2(1120, 320)) <= 180, "shortcut returns close to the previous nest")
	eq(p.health.current, hp)
	ok(not LevelSanity._can_hop(_top(host, "FloorB"), _top(host, "ReturnGallery")), "the drop cannot be jumped backwards")


func test_first_fountain_safe_pad_survives_a_complete_live_cycle() -> void:
	var host := _build()
	_still(host)
	var p := await spawn_player(host, Vector2(512, 284))
	var hp := p.health.current
	var h := host.get_node("Props/FountainLesson") as CyclicHazard
	h.set_physics_process(true)
	await flush(300)
	eq(p.health.current, hp)
	ok(p.is_on_floor(), "wait on the island rather than in the river")


func _timed_cross(name_: String, x: float) -> void:
	var host := _build()
	_still(host)
	var p := await spawn_player(host, Vector2(x - 56, 284))
	p.controller.extra_jumps_unlocked = false
	var hp := p.health.current
	var h := host.get_node("Props/" + name_) as CyclicHazard
	h._t = h.rest_time
	h._enter(CyclicHazard.State.WARN)
	h.set_physics_process(true)
	ok(await wait_until(func() -> bool: return h.is_active(), 90), "read the visible warning")
	ok(await wait_until(func() -> bool: return h.safe_window(1.2), 120), "wait for the eruption to stop")
	await _walk_to(p, x + 56)
	ok(p.position.x > h.hit_rect().end.x + 8)
	eq(p.health.current, hp, "timing clears the real plume without damage")


func test_real_knight_reads_the_slow_fountain_then_crosses() -> void:
	await _timed_cross("FountainLesson", 576)


func test_real_knight_reads_the_fast_fountain_then_crosses() -> void:
	await _timed_cross("FountainFastA", 3000)


func test_real_slag_plume_damages_an_exposed_knight() -> void:
	var host := _build()
	_still(host)
	var p := await spawn_player(host, Vector2(576, 284))
	var hp := p.health.current
	var h := host.get_node("Props/FountainLesson") as CyclicHazard
	h._t = h.rest_time + h.telegraph_time + h.active_time * 0.5
	h._enter(CyclicHazard.State.ACTIVE)
	await flush(12)
	eq(p.health.current, hp - 1, "actual slag hitbox inflicts damage")


func test_real_pit_recovery_jumps_out_of_all_three_rivers() -> void:
	for spec in L8.PITS:
		for west in [true, false]:
			var host := _build()
			_still(host)
			var x := float(spec[1]) + 8 if west else float(spec[2]) - 8
			var p := await spawn_player(host, Vector2(x, 348))
			p.controller.extra_jumps_unlocked = false
			Input.action_press("move_left" if west else "move_right")
			Input.action_press("jump")
			await flush(50)
			_release()
			await flush(20)
			var outside: bool = p.position.x < float(spec[1]) if west else p.position.x > float(spec[2])
			ok(p.is_on_floor() and outside and absf(p.position.y - 320) < 2, "one recovery hop from %s west=%s: %s" % [spec[0], west, p.position])
			host.free()
			await flush(1)


func test_real_knight_crosses_the_old_hull_gap_and_climbs_to_its_reward() -> void:
	var host := _build()
	_still(host)
	var p := await spawn_player(host, Vector2(3584, 300))
	p.controller.extra_jumps_unlocked = false
	var hp := p.health.current
	await _jump_right(50, true)
	ok(p.is_on_floor() and p.position.x >= 3664 and absf(p.position.y - 320) < 2, "third river is one ordinary jump / dash gap: %s" % p.position)
	eq(p.health.current, hp, "third river crossing itself is damage-free")
	await _walk_to(p, 3864)
	eq(p.health.current, hp, "the ground route stops before the reward steps")
	await _jump_right()
	await _walk_to(p, 3912)
	await _jump_right()
	ok(p.is_on_floor() and p.position.x >= 3920 and absf(p.position.y - 256) < 2, "basic jumps reach the preserved old hull reward: %s" % p.position)
	eq(p.health.current, hp)


func test_real_landing_opens_the_original_sluice_and_heat_forge_gate_remains() -> void:
	var host := _build()
	_still(host)
	var p := await spawn_player(host, L8.PLATE_FEET - Vector2(0, 24))
	var door := host.get_node("Props/SluiceDoor") as ArenaDoor
	ok(await wait_until(func() -> bool: return door.is_open), "normal landing opens original sluice")
	var gate := host.get_node("Props/RustGate") as RustyGate
	ok(not gate._melted)
	ok(gate.get_prompt(p).contains("锈门"))
	ok(L8.NESTS[3][1] < gate.position.x)
	p.inventory.add_to_pouch(AbilityCatalog.kiln_core())
	p.inventory.insert_first_available()
	gate.interact(p)
	await flush(2)
	ok(not is_instance_valid(gate), "equipped heat forge melts the authored gate")


func test_vent_reward_is_hook_only_and_old_hull_reward_keeps_its_path() -> void:
	var host := _build()
	var vent := host.get_node("Props/RewardVent") as EquipmentPickup
	var old := host.get_node("Pickups/RewardOldHull") as EquipmentPickup
	eq(vent.reward_ref, "bone_amulet")
	eq(old.reward_ref, "toxic_ward")
	for p in [vent, old]:
		ok(LevelSanity.standing_on(LevelSanity.top_segments(host), LevelSanity.feet_of(p)) != null, "reward support: " + str(p.name))
	ok(not LevelSanity.is_reachable(host, L8.ENTRY_SPAWN, LevelSanity.feet_of(vent), false))
	ok(LevelSanity.is_reachable(host, L8.ENTRY_SPAWN, LevelSanity.feet_of(vent), true))
	ok(LevelSanity.is_reachable(host, L8.ENTRY_SPAWN, LevelSanity.feet_of(old), false))
