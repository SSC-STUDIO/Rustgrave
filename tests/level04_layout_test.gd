extends TestCase
## Cathedral acceptance: real circuits, safe resonance cover, persistent paths and return routes.
const L4 := preload("res://scripts/levels/chapters/level04_layout.gd")


func setup() -> void:
	SaveData.flags.clear()
	Director._set_lock(false)


func teardown() -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("jump")
	SaveData.flags.clear()
	Director._set_lock(false)
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)


func _build() -> Node2D:
	var host := Node2D.new()
	host.name = "Level04_Cathedral"
	host.scene_file_path = GameContext.LEVELS["level04"]
	host.add_to_group("game_world")
	add_child(host)
	var layout := L4.new()
	add_child(layout)
	layout.build(host)
	return host


func _rect(host: Node, platform_name: String) -> Rect2:
	var p := host.get_node("Platforms/" + platform_name) as SolidPlatform
	return Rect2(p.position, p.size)


func _still(host: Node2D) -> void:
	for e in host.get_node("Enemies").get_children():
		e.set_physics_process(false)
	for h in LevelSanity.hazards(host):
		h.set_physics_process(false)
		h._set_armed(false)


func test_metadata_and_persistent_v2_paths_are_preserved() -> void:
	var host := _build()
	var layout := L4.new()
	add_child(layout)
	eq(layout.title(), ChapterText.title_of("level04"))
	eq(layout.wake_line(), ChapterText.wake_of("level04"))
	eq(layout.theme(), "cathedral")
	ok(layout.indoors())
	eq(layout.entry_spawn(), Vector2(96, 300))
	for path in ["Props/EmberNestNave", "Props/EmberNestChoir", "Props/EmberNestBridge",
		"Props/EmberNestAltar", "Props/EmberNestCloister", "Props/ChoirPlate", "Props/ChoirDoor",
		"Props/RustyGate", "Props/SteleCompact", "Props/StelePrice", "Props/SteleVault",
		"Pickups/EmberCoreVault", "Pickups/RewardChoir"]:
		ok(host.get_node_or_null(path) != null, "v2 path survives: " + path)
	var exit := host.get_node("Props/Exit") as LevelExit
	eq(exit.flag_id, "level04_done")
	eq(exit.target_scene, GameContext.LEVELS["level04b"])
	eq(exit.spawn, ChapterLayout.entry_spawn_of("level04b"))
	ok(L4.EAST_LIMIT - exit.position.x >= 80)
	for e in host.get_node("Enemies").get_children():
		ok(not e.is_in_group("bosses"), "this chapter has no boss")


func test_terrain_and_every_mainline_goal_pass_sanity_without_hook() -> void:
	var host := _build()
	var problems := LevelSanity.check(host)
	ok(problems.is_empty(), "sanity: %s" % [problems])
	var spawn := Vector2(L4.ENTRY_SPAWN.x, 320)
	for child in host.get_node("Props").get_children():
		if child is EmberNest or child is PressurePlate or child is LevelExit or child is RustyGate:
			ok(LevelSanity.is_reachable(host, spawn, LevelSanity.feet_of(child), false),
				"mainline target requires no hook: %s" % child.name)
	for f in L4.FLOORS:
		var p := host.get_node("Platforms/" + String(f[0])) as SolidPlatform
		eq(p.skin, "nave")
		almost(p.position.y, f[3])
	var dry := _rect(host, "NaveDryBed")
	ok(dry.position.y > 320 and dry.position.y <= 384, "broken vault has a recoverable dry lower circuit")
	var pools := 0
	for n in LevelSanity._descendants(host):
		if n is ToxinPool:
			pools += 1
	eq(pools, 0, "crossings use chapter terrain, rather than another acid pit")


func test_authored_main_and_return_chains_are_single_jumps() -> void:
	var host := _build()
	for chain in [L4.CHOIR_CHAIN, L4.CHOIR_RETURN_CHAIN, L4.GALLERY_CHAIN, L4.BRIDGE_CHAIN, L4.SIDE_CHAIN]:
		for i in range(1, chain.size()):
			var a := _rect(host, chain[i - 1])
			var b := _rect(host, chain[i])
			var rise := a.position.y - b.position.y
			var gap := maxf(0, maxf(b.position.x - a.end.x, a.position.x - b.end.x))
			ok(rise <= 32, "%s → %s rises one jump" % [chain[i - 1], chain[i]])
			ok(gap <= 72 + maxf(0, -rise) * 0.5, "%s → %s spans one jump" % [chain[i - 1], chain[i]])


func test_choir_plate_wiring_and_east_return_do_not_trap_a_fallen_player() -> void:
	var host := _build()
	_still(host)
	var plate := host.get_node("Props/ChoirPlate") as PressurePlate
	var door := host.get_node("Props/ChoirDoor") as ArenaDoor
	ok(plate.activated.is_connected(door.open_door))
	var east_ground := Vector2(1168, 320)
	ok(LevelSanity.is_reachable(host, east_ground, LevelSanity.feet_of(plate), false),
		"falling east of the choir retains a route to its plate")
	var player := await spawn_player(host, Vector2(1160, 300))
	player.controller.extra_jumps_unlocked = false
	Input.action_press("move_left")
	Input.action_press("jump")
	await flush(25)
	Input.action_release("jump")
	Input.action_release("move_left")
	await flush(18)
	ok(player.is_on_floor() and player.position.y < 290, "real single jump lands on the eastern recovery stair")
	plate.activated.emit()
	ok(door.is_open, "the plate opens the original persistent door")


func test_upper_gallery_completes_a_ring_and_has_one_way_drop_to_nave_nest() -> void:
	var host := _build()
	var upper_west := Vector2(1040, 192)
	var upper_east := Vector2(1904, 192)
	var lower_west := Vector2(1216, 320)
	var lower_east := Vector2(1824, 320)
	ok(LevelSanity.is_reachable(host, lower_west, upper_east, false), "west stair reaches the upper circuit")
	ok(LevelSanity.is_reachable(host, upper_west, lower_east, false), "upper circuit returns to the lower east")
	ok(LevelSanity.is_reachable(host, lower_east, lower_west, false), "lower circuit returns west")
	var shortcut := _rect(host, "GalleryReturn")
	var landing := Vector2(shortcut.position.x - 24, 320)
	ok(LevelSanity.is_reachable(host, Vector2(720, 224), Vector2(432, 192), false), "choir opens westbound shortcut")
	ok(320 - shortcut.position.y > 96, "shortcut ledge is too high to jump back onto")
	var lower_seg := LevelSanity.standing_on(LevelSanity.top_segments(host), landing)
	var upper_seg := LevelSanity.standing_on(LevelSanity.top_segments(host), Vector2(432, 192))
	ok(LevelSanity._can_hop(upper_seg, lower_seg) and not LevelSanity._can_hop(lower_seg, upper_seg),
		"the drop is one way; returning to the gallery requires going around the choir stairs")
	ok(absf(landing.x - L4.NEST_NAVE_X) <= 240, "drop returns near the previous nest")


func test_dry_bridge_bed_has_physical_jump_clearance_at_both_ends() -> void:
	var host := _build()
	_still(host)
	var player := await spawn_player(host, Vector2(2448, 332))
	player.controller.extra_jumps_unlocked = false
	Input.action_press("move_right")
	Input.action_press("jump")
	await flush(26)
	Input.action_release("jump")
	Input.action_release("move_right")
	await flush(16)
	ok(player.is_on_floor() and player.position.x >= 2464 and player.position.y < 325,
		"east end has open headroom to jump out of the dry bed")
	player.position = Vector2(1912, 332)
	player.velocity = Vector2.ZERO
	await flush(20)
	Input.action_press("move_left")
	Input.action_press("jump")
	await flush(26)
	Input.action_release("jump")
	Input.action_release("move_left")
	await flush(16)
	ok(player.is_on_floor() and player.position.x <= 1888 and player.position.y < 325,
		"west end also allows a basic jump out of the bed")


func test_bells_warn_before_shock_and_share_the_visual_timeline() -> void:
	var host := _build()
	_still(host)
	eq(LevelSanity.hazards(host).size(), 4)
	for spec in L4.BELLS:
		var wave := host.get_node("Props/" + String(spec[0])) as CyclicHazard
		var bell := host.get_node("Decor/" + String(spec[0]) + "Bell")
		eq(bell.get("wave"), wave)
		ok(wave.telegraph_time >= 0.5)
		ok(wave.rest_time + wave.telegraph_time >= 1.2)
		almost(wave.reach, 16)
		ok(wave.get_node_or_null("HazardHint") is HintArea, "first meeting uses the shock hint")
	var first := host.get_node("Props/FontResonance") as CyclicHazard
	var bell := host.get_node("Decor/FontResonanceBell")
	ok(first.safe_window(1.0))
	ok(not bell.call("ringing"))
	first.tick(3.1)
	ok(first.is_warning() and bell.call("ringing"), "bell rings during the warning")
	ok(not (first.get_node("HazardHitbox") as Hitbox).monitoring)
	first.tick(0.9)
	ok(first.is_active() and bell.call("ringing"), "bell and wave enter attack together")
	var hit := first.hit_rect()
	ok(hit.position.x >= 384 + 48 and hit.end.x <= 704 - 48, "first wave has at least 48px safe entry and exit")
	for enemy in host.get_node("Enemies").get_children():
		ok(enemy.position.x > hit.end.x + 120, "no enemy overlaps the first bell lesson")


func test_physical_column_cover_avoids_the_active_shock() -> void:
	var host := _build()
	_still(host)
	var player := await spawn_player(host, Vector2(484, 270))
	var wave := host.get_node("Props/FontResonance") as CyclicHazard
	var hp := player.health.current
	wave.tick(wave.seconds_until_active() + wave.active_time * 0.6)
	await flush(12)
	eq(player.health.current, hp, "standing on the column plinth avoids the live floor wave")
	ok(player.is_on_floor() and player.position.y < 290)


func test_physical_jump_avoids_the_same_wave_that_hits_ground_level() -> void:
	var host := _build()
	_still(host)
	var player := await spawn_player(host, Vector2(552, 300))
	var wave := host.get_node("Props/FontResonance") as CyclicHazard
	var hp := player.health.current
	Input.action_press("jump")
	await flush(10)
	Input.action_release("jump")
	wave.tick(wave.seconds_until_active() + wave.active_time * 0.1)
	await flush(5)
	eq(player.health.current, hp, "jump clears the wave front")
	wave.tick(wave.active_time)
	await flush(70)
	player.position = Vector2(552, 320)
	player.velocity = Vector2.ZERO
	await flush(4)
	wave.tick(wave.seconds_until_active() + wave.active_time * 0.1)
	await flush(8)
	ok(player.health.current < hp, "the exact same wave damages an exposed grounded knight")


func test_checkpoints_are_spaced_and_do_not_wake_nearby_enemies() -> void:
	var host := _build()
	var xs: Array[float] = []
	for child in host.get_node("Props").get_children():
		if not child is EmberNest:
			continue
		xs.append(child.position.x)
		for enemy in host.get_node("Enemies").get_children():
			var radius := float(enemy.get("wake_range")) if enemy is GhostEnemy else float(enemy.get("aggro_range"))
			var patrol: Variant = enemy.get("patrol_range")
			if patrol != null:
				radius += float(patrol)
			ok(LevelSanity.feet_of(child).distance_to(enemy.position) > radius,
				"%s is outside %s's detection and patrol" % [child.name, enemy.name])
	xs.sort()
	eq(xs.size(), 5)
	for i in range(1, xs.size()):
		ok(xs[i] - xs[i - 1] <= 1010, "nest interval stays around 1000px")
	ok(L4.EXIT_X - xs.back() < 200, "last nest is close to the crypt door")
	var player := await spawn_player(host, Vector2(L4.NEST_CHOIR_X + 6, 300))
	await flush(360)
	for enemy in host.get_node("Enemies").get_children():
		ok(enemy.position.distance_to(player.position) > 96, "six seconds at choir nest never attracts %s" % enemy.name)


func test_reward_challenge_is_optional_and_hook_vault_stays_hook_only() -> void:
	var host := _build()
	var spawn := Vector2(L4.ENTRY_SPAWN.x, 320)
	var reward := host.get_node("Pickups/RewardChoir") as EquipmentPickup
	eq(reward.reward_ref, "bone_charm")
	ok(LevelSanity.is_reachable(host, spawn, LevelSanity.feet_of(reward), false), "bell challenge is reachable with basic moves")
	var top := LevelSanity.standing_on(LevelSanity.top_segments(host), LevelSanity.feet_of(reward))
	ok(top != null and top.owner_name == "SideLoft", "reward stands on a stable challenge gallery")
	var vault := host.get_node("Props/SteleVault") as LoreStele
	ok(not LevelSanity.is_reachable(host, spawn, LevelSanity.feet_of(vault), false), "vault remains unreachable without hook")
	ok(LevelSanity.is_reachable(host, spawn, LevelSanity.feet_of(vault), true), "hook reaches vault lore and core")
	eq(vault.lore_text, String(ChapterText.stele_of("level04", "SteleVault").get("text")))
	var core := host.get_node("Pickups/EmberCoreVault") as CorePickup
	eq(core.core.id, &"ember_core")
	var guard := host.get_node("Enemies/GearShield1") as EnemyBase
	eq(guard.variant, &"heavy_guard")
	eq(host.get_node("Enemies").get_child_count(), 8)
