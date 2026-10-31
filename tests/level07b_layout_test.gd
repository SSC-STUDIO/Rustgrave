extends TestCase
## 阶梯铸造线、吊台同步熔注、干槽回收、四巢安全、单向回廊与钟模场。

const LAYOUT := preload("res://scripts/levels/chapters/level07b_layout.gd")
const CHAPTER_ID := "level07b"


func setup() -> void:
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.pending_spawn = Vector2.INF
	Director.abort()
	Director.resume()


func teardown() -> void:
	for action in ["move_right", "move_left", "jump"]:
		Input.action_release(action)
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.pending_spawn = Vector2.INF
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	Director.abort()


func _build() -> Node2D:
	var host := Node2D.new()
	host.name = "Level07bLayoutHost"
	host.scene_file_path = GameContext.LEGACY_LEVELS[CHAPTER_ID]
	host.add_to_group("game_world")
	add_child(host)
	var layout := LAYOUT.new()
	add_child(layout)
	layout.build(host)
	return host


func _quiet_enemies(host: Node2D) -> void:
	for enemy in host.get_node("Enemies").get_children():
		enemy.set_physics_process(false)


func test_metadata_and_descending_terraces() -> void:
	var layout := LAYOUT.new() as ChapterLayout
	eq(layout.level_id(), CHAPTER_ID)
	eq(layout.title(), ChapterText.title_of(CHAPTER_ID))
	eq(layout.wake_line(), ChapterText.wake_of(CHAPTER_ID))
	eq(layout.theme(), "forge")
	eq(layout.motes(), "embers")
	eq(layout.east_limit(), 4320)
	eq(layout.camera_top(), -224)
	eq(layout.entry_spawn(), Vector2(96, 140))
	layout.free()
	var host := _build()
	for row in [["FloorA", 160], ["FloorB", 224], ["FloorC", 288], ["FloorE", 320]]:
		eq((host.get_node("Platforms/" + row[0]) as SolidPlatform).position.y, float(row[1]))
	ok(host.get_node("ParallaxBackdrop") is CanvasLayer, "indoor foundry backdrop")
	ok(host.get_node("IndoorZone") is AtmosphereZone, "indoor atmosphere")
	ok(host.get_node("Platforms/Ceiling") is SolidPlatform, "enclosed foundry")


func test_main_route_support_and_original_persistent_nodes() -> void:
	var host := _build()
	var tops := LevelSanity.top_segments(host)
	for name_ in ["EmberNestEntry", "EmberNestLadle", "EmberNestCooling", "EmberNestCast", "MoldGatePlate", "SteleMold", "SteleFounder", "Exit"]:
		var node := host.get_node("Props/" + name_) as Node2D
		var feet := LevelSanity.feet_of(node)
		ok(LevelSanity.standing_on(tops, feet) != null, "%s has permanent support" % name_)
		ok(LevelSanity.is_reachable(host, LAYOUT.ENTRY_SPAWN, feet, false), "%s is on the basic-jump route" % name_)
	var exit_node := host.get_node("Props/Exit") as LevelExit
	eq(exit_node.flag_id, "level07b_done")
	eq(exit_node.requires_flag, "founder_dead")
	eq(exit_node.target_scene, GameContext.LEGACY_LEVELS["level08"])
	eq(exit_node.spawn, ChapterLayout.entry_spawn_of("level08"))
	ok(LAYOUT.EXIT_X <= LAYOUT.EAST_LIMIT - LevelSanity.EXIT_WALL_CLEAR, "east wall clearance")
	for name_ in ["SteleMold", "SteleFounder", "SteleKey"]:
		var stele := host.get_node("Props/" + name_) as LoreStele
		var original := ChapterText.stele_of(CHAPTER_ID, name_)
		eq(stele.lore_title, original.title)
		eq(stele.lore_text, original.text)


func test_lift_endpoints_and_full_cycle_rider_envelopes_clear_the_pours() -> void:
	var host := _build()
	for row in [["LiftA", "PourLadle", "FloorA", "FloorB"], ["LiftB", "PourCool", "FloorC", "FloorD"]]:
		var lift := host.get_node("Platforms/" + row[0]) as MovingPlatform
		var pour := host.get_node("Props/" + row[1]) as CyclicHazard
		almost(lift.period, pour.period())
		ok(lift.phase == 0.0 if row[0] == "LiftA" else lift.phase == 0.5, "authored initial phase")
		ok(pour.facing == Vector2.DOWN and pour.skin == "slag", "molten metal pours down")
		ok(pour.telegraph_time >= 0.5 and pour.rest_time >= 1.2, "readable warning and crossing time")
		ok(LevelSanity.is_reachable(host, LAYOUT.ENTRY_SPAWN, lift.start_position() + Vector2(40, 0), false), "lift boarding endpoint reachable")
		ok(LevelSanity.is_reachable(host, lift.end_position() + Vector2(40, 0), (host.get_node("Platforms/" + row[3]) as SolidPlatform).position + Vector2(24, 0), false), "lift disembarking endpoint reaches permanent floor")
		var active_samples := 0
		for i in range(961):
			var t := float(i) / 120.0
			if pour.state_at(t) == CyclicHazard.State.ACTIVE:
				active_samples += 1
				# Include both deck edges, knight half-width8 and full body26.
				var rider := Rect2(lift.position_at(t) + Vector2(-8, -26), Vector2(lift.width + 16, 42))
				ok(not rider.intersects(pour.hit_rect()), "%s full deck and knight clear the entire active pour at %.3f" % [lift.name, t])
		ok(active_samples > 100, "samples cover the active second, not only safe endpoints")


func test_pour_resynchronizes_after_director_lock_without_clock_drift() -> void:
	var host := _build()
	for row in [["LiftA", "PourLadle"], ["LiftB", "PourCool"]]:
		var lift := host.get_node("Platforms/" + row[0]) as MovingPlatform
		var pour := host.get_node("Props/" + row[1]) as CyclicHazard
		lift.set_physics_process(false)
		pour.set_physics_process(false)
		lift._t = 6.8
		pour._physics_process(1.0 / 60)
		almost(pour.clock(), lift._t, 0.0001, "warning follows the lift clock")
		ok(pour.is_warning(), "pre-lock warning")
		Director._set_lock(true)
		lift._t = 23.5
		pour._physics_process(1.0 / 60)
		almost(pour.clock(), 6.8, 0.0001, "the pour freezes while input is locked")
		ok(not pour._hitbox.monitoring, "director lock disarms the real hitbox")
		Director._set_lock(false)
		pour._physics_process(1.0 / 60)
		almost(pour.clock(), lift._t, 0.0001, "unlock reattaches to the continuing lift, including multiple cycles")
		ok(pour.is_active(), "resumed state matches current lift phase")
		var rider := Rect2(lift.position_at(lift._t) + Vector2(-8, -26), Vector2(lift.width + 16, 42))
		ok(not rider.intersects(pour.hit_rect()), "resumed active pour still clears all rider positions")


func _ride_cycle(lift_name: String) -> void:
	var host := _build()
	_quiet_enemies(host)
	var lift := host.get_node("Platforms/" + lift_name) as MovingPlatform
	await flush(2) # Let AnimatableBody2D register its nonzero initial phase before boarding.
	var player := await spawn_player(host, lift.position + Vector2(40, -20))
	var hp := player.health.current
	var start_x := player.position.x
	var max_x := start_x
	var min_x := start_x
	for _i in range(480):
		await flush(1)
		max_x = maxf(max_x, player.position.x)
		min_x = minf(min_x, player.position.x)
		ok(player.is_on_floor(), "the actual knight remains aboard the moving deck")
	eq(player.health.current, hp, "full real physics cycle causes no forced molten hit")
	ok(max_x - min_x >= lift.travel.x * 0.8, "the knight traverses the actual moving route (%.1f..%.1f, y%.1f)" % [min_x, max_x, player.position.y])
	host.free()
	await flush(1)


func test_actual_knight_rides_ladle_lift_through_a_full_cycle() -> void:
	await _ride_cycle("LiftA")


func test_actual_knight_rides_cooling_lift_through_a_full_cycle() -> void:
	await _ride_cycle("LiftB")


func test_falls_land_on_dry_recoverable_fixed_floors() -> void:
	var host := _build()
	_quiet_enemies(host)
	for row in [[Vector2(576, 190), 256.0, Vector2(800, 224)], [Vector2(1920, 295), 320.0, Vector2(2128, 288)], [Vector2(2944, 320), 352.0, Vector2(3104, 320)]]:
		var player := await spawn_player(host, row[0])
		await flush(24)
		ok(player.is_on_floor(), "missed transport lands on permanent floor")
		almost(player.position.y, float(row[1]), 1.0, "expected lower recovery terrace")
		ok(LevelSanity.is_reachable(host, player.position, row[2], false), "basic jump leaves the recovery floor")
		player.free()
		await flush(1)


func test_mould_plate_physically_opens_the_gate_and_closed_gate_cannot_be_jumped() -> void:
	var host := _build()
	_quiet_enemies(host)
	var plate := host.get_node("Props/MoldGatePlate") as PressurePlate
	var door := host.get_node("Props/MoldGateDoor") as ArenaDoor
	var lintel := host.get_node("Platforms/MoldGateLintel") as SolidPlatform
	ok(plate.activated.is_connected(door.open_door), "original plate-door connection")
	ok(not door.is_open, "starts closed")
	var gap := door.position.y - (lintel.position.y + lintel.size.y)
	ok(gap >= 0 and gap < 26, "no knight-sized hole above the closed gate")
	var player := await spawn_player(host, Vector2(1760, 268))
	Input.action_press("move_right")
	Input.action_press("jump")
	await flush(60)
	Input.action_release("jump")
	Input.action_release("move_right")
	ok(player.position.x < door.position.x, "jump cannot bypass the closed gate")
	player.position = LAYOUT.PLATE_FEET - Vector2(0, 20)
	player.velocity = Vector2.ZERO
	ok(await wait_until(func() -> bool: return door.is_open), "landing on mould plate opens the gate")
	player.position = Vector2(1760, 268)
	player.velocity = Vector2.ZERO
	await flush(24)
	Input.action_press("move_right")
	await flush(60)
	Input.action_release("move_right")
	ok(player.position.x > door.position.x + 20, "the knight walks through the opened original gate")


func test_optional_hook_catwalk_keeps_original_lore_and_core_reward() -> void:
	var host := _build()
	var anchor := host.get_node("Hooks/HookMold") as HookAnchor
	var stele := host.get_node("Props/SteleKey") as LoreStele
	var reward := host.get_node("Pickups/CoreReward") as CorePickup
	ok(anchor != null and reward != null, "persistent hook and reward remain")
	for node in [stele, reward]:
		var feet := LevelSanity.feet_of(node)
		ok(LevelSanity.standing_on(LevelSanity.top_segments(host), feet, 64.0, 4.0) != null, "branch content stands on or hovers just above its catwalk")
		ok(not LevelSanity.is_reachable(host, LAYOUT.ENTRY_SPAWN, feet, false), "branch remains optional and hook-only")
		ok(LevelSanity.is_reachable(host, LAYOUT.ENTRY_SPAWN, feet, true), "hook reaches branch content")
	eq(reward.core.id, &"kiln_core")
	eq((host.get_node("Enemies/Ghost1") as GhostEnemy).wake_range, 72.0, "reward guard wakes on the branch")


func _quiet_nests(names: Array) -> void:
	for name_ in names:
		var host := _build()
		var calls := {"attacks": 0}
		for enemy in host.get_node("Enemies").get_children():
			(enemy as EnemyBase).telegraph_started.connect(func(_kind, _duration) -> void: calls.attacks += 1)
		var nest := host.get_node("Props/" + String(name_)) as EmberNest
		var player := await spawn_player(host, LevelSanity.feet_of(nest) - Vector2(0, 20))
		var hp := player.health.current
		await flush(360)
		eq(player.health.current, hp, "%s remains safe for six seconds with live AI" % name_)
		eq(calls.attacks, 0, "%s does not wake an encounter" % name_)
		host.free()
		await flush(1)


func test_west_checkpoint_ai_stays_quiet_for_six_seconds() -> void:
	await _quiet_nests(["EmberNestEntry", "EmberNestLadle"])


func test_east_checkpoint_ai_stays_quiet_for_six_seconds() -> void:
	await _quiet_nests(["EmberNestCooling", "EmberNestCast"])


func test_first_mechanism_fixed_waiting_landings_allow_safe_reading() -> void:
	for feet in [Vector2(400, 160), Vector2(800, 224)]:
		var host := _build()
		var calls := {"attacks": 0}
		for enemy in host.get_node("Enemies").get_children():
			(enemy as EnemyBase).telegraph_started.connect(func(_kind, _duration) -> void: calls.attacks += 1)
		var player := await spawn_player(host, feet - Vector2(0, 20))
		var hp := player.health.current
		await flush(360)
		eq(player.health.current, hp, "fixed read-and-wait landing stays safe for six seconds")
		eq(calls.attacks, 0, "first mechanism is taught before combat")
		ok(player.is_on_floor(), "waiting does not require balancing on the moving deck")
		host.free()
		await flush(1)


func test_checkpoint_spacing_variants_and_one_way_return_gallery() -> void:
	var host := _build()
	var tops := LevelSanity.top_segments(host)
	var names := ["EmberNestEntry", "EmberNestLadle", "EmberNestCooling", "EmberNestCast"]
	for i in range(1, names.size()):
		var west := host.get_node("Props/" + names[i - 1]) as Node2D
		var east := host.get_node("Props/" + names[i]) as Node2D
		eq(east.position.x - west.position.x, 992.0, "death run between nests remains under1000px")
	ok(LAYOUT.ARENA_LEFT - LAYOUT.NEST_BOSS_X <= 80, "checkpoint sits64px before arena")
	var low := LevelSanity.standing_on(tops, Vector2(2160, 288))
	var high := LevelSanity.standing_on(tops, Vector2(2240, 192))
	ok(LevelSanity._can_hop(high, low) and not LevelSanity._can_hop(low, high), "westward gallery drop is one-way")
	ok(LevelSanity.is_reachable(host, Vector2(2768, 224), Vector2(2240, 192), false), "return gallery is a basic-jump chain")
	eq((host.get_node("Enemies/GearShield1") as EnemyBase).variant, &"heavy_guard")
	eq((host.get_node("Enemies/Scrapper2") as EnemyBase).variant, &"armored_scrapper")
	eq((host.get_node("Enemies/Scrapper3") as EnemyBase).variant, &"armored_scrapper")


func test_actual_founder_body_can_walk_over_both_mould_ramps() -> void:
	var host := _build()
	_quiet_enemies(host)
	var founder := host.get_node("Enemies/BellFounder") as EnemyBase
	founder.position = Vector2(3496, 320)
	founder.velocity = Vector2.ZERO
	for direction in [1.0, -1.0]:
		for _i in range(270):
			await flush(1)
			founder.velocity.x = direction * 90.0
			if not founder.is_on_floor():
				founder.velocity.y += 900.0 / 60.0
			founder.move_and_slide()
		if direction > 0:
			ok(founder.position.x > 3840, "unchanged30x78 Boss body climbs and descends eastward")
		else:
			ok(founder.position.x < 3536, "the same Boss body returns westward without jumping")
		almost(founder.position.y, 320, 1.0, "Boss returns to the arena recovery floor")


func test_boss_phases_ignite_side_pours_and_death_unlocks_original_exit() -> void:
	var host := _build()
	var founder := host.get_node("Enemies/BellFounder") as EnemyBase
	var arena := host.get_node("Arenas/BellFounderArena") as BossArena
	var west := host.get_node("Props/CastPillarWest") as CyclicHazard
	var east := host.get_node("Props/CastPillarEast") as CyclicHazard
	var exit_node := host.get_node("Props/Exit") as LevelExit
	ok(exit_node.is_locked(), "original death flag locks exit")
	ok(not west.get("ignited") and not east.get("ignited"), "arena pours wait for Boss phase events")
	ok(bool(arena.checkpoint_report().ok), "original BossArena checkpoint contract")
	founder.call("announce")
	await flush(2)
	Director.abort()
	ok(west.get("ignited") and not east.get("ignited"), "phase1 ignites only west pour")
	ok(west.is_warning(), "ignition starts with full warning")
	founder.health.take_damage(11, null)
	await flush(2)
	ok(east.get("ignited") and east.is_warning(), "phase2 ignites east pour with warning")
	await flush(84) # Real phase transition and damage iframe expire before the finishing blow.
	ok(west.is_active() and east.is_active(), "both real pours are active before clear")
	ok(await wait_until(func() -> bool: return not founder.health.is_invincible()), "Boss completes its original phase transition before the finishing blow")
	founder.health.take_damage(99, null)
	await flush(2)
	ok(SaveData.has_flag("founder_dead"), "original persistent Boss death flag")
	ok(arena.is_cleared() and not exit_node.is_locked(), "Boss death clears arena and original exit")
	ok(not west.get("ignited") and not east.get("ignited"), "both pours extinguish on arena clear")
	ok(not west._armed and not east._armed, "cleared pours have no residual damage")


func test_forge_decor_support_and_scene_wiring() -> void:
	var host := _build()
	var count := 0
	for child in host.get_node("Decor").get_children():
		if child is Sprite2D and child.has_meta("prop_key"):
			count += 1
			ok(PropCatalog.allowed("forge", child.get_meta("prop_key")), "foundry uses forge art whitelist")
			if child.is_in_group("grounded"):
				eq(child.scale, Vector2.ONE, "grounded art at integer1x")
				ok(LevelSanity.standing_on(LevelSanity.top_segments(host), child.get_meta("feet")) != null, "decor foot matches a platform")
	ok(count >= 16, "each foundry beat carries grounded set dressing")
	var level := (load(GameContext.LEGACY_LEVELS[CHAPTER_ID]) as PackedScene).instantiate()
	add_child(level)
	await flush(2)
	Director.abort()
	ok(level.get_node_or_null("Platforms/BellMould") != null, "actual chapter scene builds the mould arena")
	ok(level.get_node_or_null("Props/PourLadle") != null, "actual chapter scene builds synchronized pours")
