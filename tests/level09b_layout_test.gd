extends TestCase
const LAYOUT := preload("res://scripts/levels/chapters/level09b_layout.gd")
const TRIAL_CATALOG := preload("res://scripts/data/trial_catalog.gd")
var _flags: PackedStringArray
var _consumed: PackedStringArray
var _layout: ChapterLayout


func setup() -> void:
	_flags = SaveData.flags.duplicate()
	_consumed = SaveData.consumed.duplicate()
	SaveData.flags.clear()
	SaveData.consumed.clear()
	Director.abort()
	Director.resume()
	Director._set_lock(false)


func teardown() -> void:
	Input.action_release("move_right")
	Input.action_release("move_left")
	Input.action_release("jump")
	SaveData.flags = _flags
	SaveData.consumed = _consumed
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	Director.abort()


func _build() -> Node2D:
	var host := Node2D.new()
	host.name = "Level09b_EmberwindCliffs"
	host.scene_file_path = GameContext.LEVELS["level09b"]
	host.add_to_group("game_world")
	add_child(host)
	_layout = LAYOUT.new()
	add_child(_layout)
	_layout.build(host)
	return host


func _rect(host: Node2D, name_: String) -> Rect2:
	var p := host.get_node("Platforms/" + name_) as SolidPlatform
	return Rect2(p.position, p.size)


func test_metadata_story_and_basic_route_preserve_the_campaign_contract() -> void:
	var host := _build()
	eq(_layout.entry_spawn(), Vector2(96, -340))
	eq(_layout.camera_top(), -400)
	eq(_layout.theme(), "ramparts")
	eq(_layout.east_limit(), 3400)
	eq(_layout.title(), ChapterText.title_of("level09b"))
	eq(_layout.wake_line(), ChapterText.wake_of("level09b"))
	var problems := LevelSanity.check(host, Rect2(0, -400, 3400, 800))
	for problem in problems:
		ok(false, problem)
	ok(problems.is_empty(), "actual solids, hazards and props pass sanity")
	for name_ in ["WindGatePlate", "WindGateDoor", "SteleAsh", "SteleHerald", "SteleGate", "Exit"]:
		var node := host.get_node("Props/" + name_) as Node2D
		ok(LevelSanity.is_reachable(host, LAYOUT.ENTRY_SPAWN, LevelSanity.feet_of(node), false), "%s uses the basic route" % name_)
	var exit := host.get_node("Props/Exit") as LevelExit
	eq(exit.flag_id, "level09b_done")
	eq(exit.requires_flag, "herald_dead")
	eq(exit.target_scene, GameContext.LEVELS["level10"])
	eq(exit.spawn, ChapterLayout.entry_spawn_of("level10"))
	for name_ in ["SteleAsh", "SteleHerald", "SteleGate"]:
		var stele := host.get_node("Props/" + name_) as LoreStele
		eq(stele.lore_text, String(ChapterText.stele_of("level09b", name_).text))


func test_three_terraces_reverse_direction_and_keep_the_lower_recovery_road() -> void:
	var host := _build()
	var chains := [
		["CliffTop", "EastTurnHigh", "EastTurnLow", "BridgeEast", "BridgeWest"],
		["BridgeWest", "WestTurnHigh", "WestTurnLow", "LowerWest", "CollapseWest", "CollapsePier", "CollapseEast", "OutpostDeck"],
		["OutpostDeck", "Climb1", "Climb2", "GateDeck", "DescentLedge", "FloorLow"],
	]
	for chain in chains:
		for i in range(1, chain.size()):
			var a := _rect(host, chain[i - 1])
			var b := _rect(host, chain[i])
			var gap := maxf(0.0, maxf(b.position.x - a.end.x, a.position.x - b.end.x))
			ok(a.position.y - b.position.y <= 32.0, "route never needs an extra jump")
			ok(gap <= 72.0, "%s -> %s has a normal-jump edge gap" % [chain[i - 1], chain[i]])
	var top := _rect(host, "CliffTop")
	var middle := _rect(host, "BridgeWest")
	var lower := _rect(host, "LowerWest")
	ok(top.position.y == -320.0 and middle.position.y == -160.0 and lower.position.y == 0.0)
	ok(_rect(host, "BridgeEast").position.x > middle.position.x, "middle run travels west from the east bend")
	ok(_rect(host, "OutpostDeck").position.x > lower.end.x, "lower run travels east after west bend")
	ok(middle.position.y - top.end.y >= 128.0 and lower.position.y - middle.end.y >= 128.0, "folds have real body and jumping headroom")
	almost(_rect(host, "FloorLow").size.x, 3400.0)
	almost(_rect(host, "FloorLow").position.y, 320.0)


func test_checkpoint_runs_follow_the_switchbacks_and_stay_near_a_thousand_pixels() -> void:
	var host := _build()
	for row in LAYOUT.NESTS:
		var node := host.get_node("Props/" + String(row[0])) as EmberNest
		ok(LevelSanity.is_reachable(host, LAYOUT.ENTRY_SPAWN, LevelSanity.feet_of(node), false), "%s reachable without optional cores" % row[0])
	var runs := [
		[Vector2(176,-320), Vector2(944,-320)],
		[Vector2(944,-320), Vector2(1104,-320), Vector2(1152,-256), Vector2(1216,-224), Vector2(1152,-160), Vector2(592,-160)],
		[Vector2(592,-160), Vector2(488,-160), Vector2(456,-96), Vector2(456,-32), Vector2(504,0), Vector2(1088,0)],
		[Vector2(1088,0), Vector2(1248,0), Vector2(1360,0), Vector2(1472,0), Vector2(1848,0)],
		[Vector2(1848,0), Vector2(2096,0), Vector2(2200,64), Vector2(2328,128), Vector2(2472,192), Vector2(2600,256), Vector2(2680,320)],
	]
	var tops := LevelSanity.top_segments(host)
	for run in runs:
		var distance := 0.0
		for i in range(run.size()):
			ok(LevelSanity.standing_on(tops, run[i], 1.0, 1.0) != null, "checkpoint route sample has support at %s" % run[i])
			if i > 0:
				distance += (run[i] as Vector2).distance_to(run[i-1])
		ok(distance <= 1050.0, "authored run is %.0fpx, including the turnbacks" % distance)


func test_mid_terrace_drop_returns_to_bridge_nest_in_one_direction() -> void:
	var host := _build()
	var tops := LevelSanity.top_segments(host)
	var upper := LevelSanity.standing_on(tops, Vector2(1064,-160))
	var lower := LevelSanity.standing_on(tops, Vector2(1032,0))
	ok(upper != null and lower != null)
	if upper != null and lower != null:
		ok(LevelSanity._can_hop(upper, lower), "48px shaft drops back to the lower checkpoint")
		ok(not LevelSanity._can_hop(lower, upper), "160px drop is not reversible in one jump")
	for entry in LevelSanity.solid_entries(host):
		ok(not (entry.rect as Rect2).intersects(LAYOUT.RETURN_DROP.grow(-1)), "return shaft remains unobstructed")
	ok(LevelSanity.is_reachable(host, Vector2(1032,0), Vector2(1088,0), false))


func test_ember_wind_is_a_real_gust_with_safe_first_encounter_landings() -> void:
	var host := _build()
	var tops := LevelSanity.top_segments(host)
	for row in LAYOUT.WINDS:
		var zone := host.get_node("Props/" + row[0]) as ForceZone
		eq(zone.skin, "ember")
		ok(absf(zone.push.x) >= 72.0 and absf(zone.push.x) <= 80.0)
		ok(absf(zone.push.x) < ForceZone.MAX_PUSH)
		almost(zone.gust_duty, 0.5)
		ok(zone.gust_period >= 4.0 and zone.gust_period <= 6.0)
		ok(ForceZone.WARN_TIME >= 0.5)
		ok(zone.get_node_or_null("HazardHint") is HintArea)
	for x in [304.0, 512.0]:
		ok(LevelSanity.standing_on(tops, Vector2(x,-320)) != null, "first wind has 48px reading area on both sides")
	for enemy in host.get_node("Enemies").get_children():
		enemy.queue_free()
	await flush(2)
	var wind := host.get_node("Props/EmberLesson") as ForceZone
	wind._t = 0.5
	var player := await spawn_player(host, Vector2(376,-340))
	var start := player.position.x
	await flush(24)
	ok(player.position.x > start + 14.0, "authored ember wind physically pushes the real knight")


func test_collapsing_bridge_is_separate_from_rockfall_and_has_fixed_safe_spaces() -> void:
	var host := _build()
	var tops := LevelSanity.top_segments(host)
	for row in LAYOUT.COLLAPSES:
		var bridge := host.get_node("Platforms/" + row[0]) as CollapsingPlatform
		ok(bridge.shake_time >= 1.4, "96px slab gives a full run and acceleration window")
		ok(bridge.respawn_time >= 4.0)
		ok(bridge.get_node_or_null("HazardHint") is HintArea)
		for spot in LAYOUT.ROCKFALL_SPOTS:
			ok(not _rect(host, row[0]).grow(40).has_point(spot), "rocks do not cover collapse bridge")
	for feet in [Vector2(1152,0), Vector2(1360,0), Vector2(1584,0)]:
		var seg := LevelSanity.standing_on(tops, feet)
		ok(seg != null and seg.kind == "", "permanent read/rest surface at %s" % feet)
	for feet in [Vector2(1248,96), Vector2(1440,96)]:
		ok(LevelSanity.standing_on(tops, feet) != null)
		ok(LevelSanity.is_reachable(host, feet, Vector2(1584,0), false), "fall climbs out in ordinary 32px steps")


func test_actual_collapse_lands_on_the_recovery_shelf_and_a_basic_jump_exits() -> void:
	var host := _build()
	for enemy in host.get_node("Enemies").get_children():
		enemy.queue_free()
	await flush(2)
	var bridge := host.get_node("Platforms/CollapseWest") as CollapsingPlatform
	var player := await spawn_player(host, Vector2(1248,-20))
	ok(bridge.state() == CollapsingPlatform.State.SHAKING, "real player starts the shake")
	await flush(120)
	ok(bridge.is_collapsed())
	ok(player.is_on_floor() and absf(player.position.y - 96.0) < 1.0, "a real body lands on the 96px recovery shelf")
	player.position = Vector2(1476,76)
	player.velocity = Vector2.ZERO
	await flush(24)
	Input.action_press("move_right")
	Input.action_press("jump")
	await flush(25)
	Input.action_release("jump")
	Input.action_release("move_right")
	ok(player.position.y < 96.0, "first ordinary jump climbs the escape staircase")


func test_bridge_rockfall_keeps_its_timer_three_spots_and_readable_telegraph() -> void:
	var host := _build()
	var timer := host.get_node("Props/RockfallTimer") as Timer
	var rig := host.get_node("Arenas/BridgeRockfallRig") as BossArena
	almost(timer.wait_time, 3.2)
	ok(not timer.one_shot)
	ok(not rig.start_on_intro and not rig.start_immediately)
	ok(not rig.clamp_player and not rig.clamp_boss)
	eq(LAYOUT.ROCKFALL_SPOTS.size(), 3)
	for i in 3:
		timer.timeout.emit()
		var rock := rig.get_child(i) as Node2D
		eq(rock.position, LAYOUT.ROCKFALL_SPOTS[i])
		ok(float(rock.get("telegraph")) >= 0.55, "rock warning remains readable")


func test_preserved_plate_opens_the_outpost_gate_and_lore_has_support() -> void:
	var host := _build()
	var plate := host.get_node("Props/WindGatePlate") as PressurePlate
	var door := host.get_node("Props/WindGateDoor") as ArenaDoor
	ok(plate.activated.is_connected(door.open_door))
	plate.slam()
	ok(door.is_open)
	var tops := LevelSanity.top_segments(host)
	ok(LevelSanity.standing_on(tops, LAYOUT.PLATE_FEET) != null)
	ok(LevelSanity.standing_on(tops, LAYOUT.WIND_DOOR_POS + Vector2(0,64)) != null)
	for name_ in ["SteleAsh", "SteleHerald", "SteleGate"]:
		ok(LevelSanity.standing_on(tops, LevelSanity.feet_of(host.get_node("Props/"+name_))) != null)


func test_hook_lee_branch_retains_the_core_and_adds_a_supported_equipment_reward() -> void:
	var host := _build()
	var anchor := host.get_node("Hooks/HookLee") as HookAnchor
	ok(anchor.position.y >= LAYOUT.CAMERA_TOP + 24, "hook body remains readable inside the camera ceiling")
	for path in ["Pickups/CoreReward", "Props/RewardLee"]:
		var node := host.get_node(path) as Node2D
		var feet := LevelSanity.feet_of(node)
		ok(not LevelSanity.is_reachable(host, LAYOUT.ENTRY_SPAWN, feet, false), "branch is optional")
		ok(LevelSanity.is_reachable(host, LAYOUT.ENTRY_SPAWN, feet, true), "hook reaches the lee reward")
	var equipment := host.get_node("Props/RewardLee") as EquipmentPickup
	eq(equipment.reward_ref, "bone_charm")
	ok(LevelSanity.standing_on(LevelSanity.top_segments(host), equipment.position+Vector2(0,7)) != null)
	var core := host.get_node("Pickups/CoreReward") as CorePickup
	eq(core.core.id, &"ember_core")


func test_authored_encounters_and_arena_terrain_keep_enemy_support_and_boss_contract() -> void:
	var host := _build()
	var tops := LevelSanity.top_segments(host)
	for row in LAYOUT.ENEMIES:
		var enemy := host.get_node("Enemies/"+row[0]) as EnemyBase
		if not (enemy is FlyingDemonEnemy or enemy is GhostEnemy):
			ok(LevelSanity.standing_on(tops, enemy.position) != null, "ground combatant is supported")
	eq(host.get_node("Enemies/Spitter1").variant, &"scatter_spitter")
	eq(host.get_node("Enemies/Scrapper1").variant, &"armored_scrapper")
	eq(host.get_node("Enemies/GearShield1").variant, &"heavy_guard")
	var arena := host.get_node("Arenas/EmberwindHeraldArena") as BossArena
	ok(bool(arena.checkpoint_report().ok), "old Gate nest is within 80px")
	almost(arena.arena_left, 2740.0)
	almost(arena.arena_right, 3400.0)
	ok(arena.registered_hazard_ids().has(&"herald_rockfall"))
	ok(arena.registered_hazard_ids().has(&"herald_furnace"))
	for name_ in ["HeraldWestPerch", "HeraldEastPerch"]:
		var r := _rect(host, name_)
		ok(r.position.y == 288.0 and r.size.x >= 64.0, "arena side perch is only one jump high")
		ok(not r.intersects(LevelSanity.node_aabb(host.get_node("Props/Exit"))), "perches leave the furnace doorway clear")
	var boss := host.get_node("Enemies/EmberwindHerald") as Node2D
	ok(not boss.is_physics_processing(), "boss waits until player crosses the arena threshold")
	var kit := boss.call("boss_kit") as BossKit
	eq(kit.validate().size(), 0)
	eq(kit.max_phases(), 2)


func test_herald_starts_after_crossing_the_actual_arena_threshold() -> void:
	var host := _build()
	var boss := host.get_node("Enemies/EmberwindHerald") as Node2D
	var player := await spawn_player(host, Vector2(2690,300))
	ok(not boss.call("is_announced"), "nest approach does not auto-start a boss")
	player.position = Vector2(2760,300)
	await flush(12)
	ok(boss.is_physics_processing())
	ok(boss.call("is_announced"), "original boss AI starts inside its arena")


func test_herald_kill_survives_disk_reload_and_leaves_the_exit_unlocked() -> void:
	var original_path := SaveData.save_path
	SaveData.save_path = "user://level09b_herald_persistence_test.cfg"
	SaveData.delete_save()
	var host := _build()
	var player := await spawn_player(host, Vector2(LAYOUT.NEST_GATE_X, 300))
	var nest := host.get_node("Props/EmberNestGate") as EmberNest
	nest.interact(player)
	ok(SaveData.has_save(), "real nest writes the checkpoint")
	var boss = host.get_node("Enemies/EmberwindHerald")
	boss.health.take_damage(999, player) # Unit-only kill; input fixture fights normally.
	await flush(3)
	ok(SaveData.has_flag("herald_dead"))
	host.free()
	await flush(1)
	SaveData.flags.clear()
	ok(SaveData.load_game(), "reloads the real story write from disk")
	ok(SaveData.has_flag("herald_dead"))
	host = _build()
	ok(host.get_node_or_null("Enemies/EmberwindHerald") == null, "disk flag prevents Herald resurrection")
	ok(host.get_node_or_null("Arenas/EmberwindHeraldArena") == null, "cleared Boss hazards are not rebuilt")
	ok(host.get_node_or_null("Props/HeraldApproach") == null)
	ok(not (host.get_node("Props/Exit") as LevelExit).is_locked(), "saved kill leaves the real exit open")
	SaveData.delete_save()
	SaveData.save_path = original_path


func test_herald_can_still_spawn_for_its_unlocked_boss_rush_rematch() -> void:
	var original_pending := GameContext.pending_world_path
	SaveData.mark_flag("trial_unlocked")
	SaveData.mark_flag("herald_dead")
	TrialRun.set_scene_requester(func(_path: String) -> void: pass)
	ok(TrialRun.start(TRIAL_CATALOG.Track.BOSS_RUSH, "emberwind_herald"))
	ok(TrialRun.forces_boss_spawn())
	var host := _build()
	ok(host.get_node_or_null("Enemies/EmberwindHerald") != null, "trial gets its real rematch Boss")
	ok(host.get_node_or_null("Arenas/EmberwindHeraldArena") != null)
	TrialRun.abandon()
	TrialRun.clear_scene_requester()
	GameContext.pending_world_path = original_pending
	ok(SaveData.flags.has("herald_dead"), "trial preserves the stored campaign kill")


func _quiet(rows: Array) -> void:
	for row in rows:
		var host := _build()
		var calls := {"attacks": 0}
		for enemy in host.get_node("Enemies").get_children():
			(enemy as EnemyBase).telegraph_started.connect(func(_kind, _duration) -> void: calls.attacks += 1)
		var player := await spawn_player(host, Vector2(float(row[1])+6,float(row[2])-20))
		var hp := player.health.current
		await flush(360)
		eq(player.health.current, hp, "%s is safe for six seconds" % row[0])
		eq(calls.attacks, 0, "%s does not wake combat" % row[0])
		var boss := host.get_node("Enemies/EmberwindHerald") as Node2D
		ok(not boss.call("is_announced"), "rest does not announce the Herald")
		host.free()
		await flush(1)


func test_cliff_wind_and_fold_nests_remain_quiet_for_six_seconds() -> void:
	await _quiet(LAYOUT.NESTS.slice(0,3))


func test_bridge_outpost_and_gate_nests_remain_quiet_for_six_seconds() -> void:
	await _quiet(LAYOUT.NESTS.slice(3,6))
