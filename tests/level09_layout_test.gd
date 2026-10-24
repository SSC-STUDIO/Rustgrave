extends TestCase
const LAYOUT := preload("res://scripts/levels/chapters/level09_layout.gd")
var _flags: PackedStringArray
var _consumed: PackedStringArray


func setup() -> void:
	_flags = SaveData.flags.duplicate()
	SaveData.flags.clear()
	_consumed = SaveData.consumed.duplicate()
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
	Director.abort()
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)


func _build() -> Node2D:
	var host := Node2D.new()
	host.name = "Level09_Ramparts"
	host.scene_file_path = GameContext.LEVELS["level09"]
	host.add_to_group("game_world")
	add_child(host)
	var layout := LAYOUT.new()
	add_child(layout)
	layout.build(host)
	return host


func _rect(host: Node2D, name_: String) -> Rect2:
	var node := host.get_node("Platforms/" + name_) as SolidPlatform
	return Rect2(node.position, node.size)


func test_main_route_and_preserved_props_are_reachable_without_optional_cores() -> void:
	var host := _build()
	var problems := LevelSanity.check(host, Rect2(0, -48, 4200, 448))
	for problem in problems:
		ok(false, problem)
	ok(problems.is_empty(), "sanity passes on the actual masonry")
	var previous := LAYOUT.NEST_GATE_X
	for row in LAYOUT.NESTS:
		var node := host.get_node("Props/" + String(row[0])) as EmberNest
		var feet := LevelSanity.feet_of(node)
		ok(LevelSanity.is_reachable(host, LAYOUT.ENTRY_SPAWN, feet, false), "%s basic route" % row[0])
		ok(float(row[1]) - previous <= 1024.0, "nest gap about 1000px")
		previous = float(row[1])
	for name_ in ["WallGatePlate", "WallGateDoor", "SteleWall", "SteleWind", "Exit"]:
		var node := host.get_node("Props/" + name_) as Node2D
		ok(LevelSanity.is_reachable(host, LAYOUT.ENTRY_SPAWN, LevelSanity.feet_of(node), false), "%s uses basic jumps" % name_)
	var exit := host.get_node("Props/Exit") as LevelExit
	eq(exit.flag_id, "level09_done")
	eq(exit.target_scene, GameContext.LEVELS["level09b"])
	eq(exit.spawn, ChapterLayout.entry_spawn_of("level09b"))
	ok(LAYOUT.EXIT_X - previous < 1000.0)


func test_main_wall_hops_and_tower_branches_have_real_support() -> void:
	var host := _build()
	var tops := LevelSanity.top_segments(host)
	for i in range(1, LAYOUT.MAIN_CHAIN.size()):
		var a := _rect(host, LAYOUT.MAIN_CHAIN[i - 1])
		var b := _rect(host, LAYOUT.MAIN_CHAIN[i])
		ok(a.position.y - b.position.y <= 32.0, "main route only rises one jump")
		ok(maxf(0.0, b.position.x - a.end.x) <= 72.0, "main gap stays within a normal jump")
	for feet in [Vector2(800, 352), Vector2(1400, 192), Vector2(1696, 192), Vector2(3080, 352), Vector2(3888, 224)]:
		ok(LevelSanity.standing_on(tops, feet) != null, "branch has support at %s" % feet)
		ok(LevelSanity.is_reachable(host, LAYOUT.ENTRY_SPAWN, feet, false), "tower branch can be explored at %s" % feet)
	# The gatehouse exits east through an open shaft; no low exit stair traps the player under its lip.
	ok(LevelSanity.is_reachable(host, Vector2(1000, 352), Vector2(1184, 320), false), "lower room climbs out to Mid")
	for y in [288.0, 304.0, 320.0, 336.0]:
		for entry in LevelSanity.solid_entries(host):
			ok(not (entry.rect as Rect2).has_point(Vector2(1120, y)), "east room escape shaft is open")
	for rect in LAYOUT.ROOMS:
		ok((rect as Rect2).size.y >= 64.0, "lower rooms have body and jump clearance")


func test_lookout_drop_returns_to_previous_nest_in_one_direction() -> void:
	var host := _build()
	var tops := LevelSanity.top_segments(host)
	var balcony := LevelSanity.standing_on(tops, Vector2(1368, 192))
	var landing := LevelSanity.standing_on(tops, Vector2(1328, 320))
	ok(balcony != null and landing != null)
	if balcony != null and landing != null:
		ok(LevelSanity._can_hop(balcony, landing), "lookout drops beside Mid nest")
		ok(not LevelSanity._can_hop(landing, balcony), "128px drop cannot be reversed in one hop")
	ok(LevelSanity.is_reachable(host, Vector2(1328, 320), Vector2(1184, 320), false), "landing walks straight to the previous nest")
	for entry in LevelSanity.solid_entries(host):
		ok(not (entry.rect as Rect2).intersects(LAYOUT.RETURN_DROP.grow(-1)), "return shaft is clear")


func test_wind_channels_have_opposite_gusts_wide_piers_and_recoverable_falls() -> void:
	var host := _build()
	var tops := LevelSanity.top_segments(host)
	for row in LAYOUT.WINDS:
		var zone := host.get_node("Props/" + String(row[0])) as ForceZone
		eq(zone.skin, "wind")
		ok(absf(zone.push.x) >= 48.0 and absf(zone.push.x) <= 72.0)
		ok(absf(zone.push.x) < ForceZone.MAX_PUSH)
		ok(zone.gust_period >= 4.0 and zone.gust_period <= 6.0)
		almost(zone.gust_duty, 0.5)
		ok(ForceZone.WARN_TIME >= 0.5)
		almost(zone.gust_factor(zone.gust_period * 0.75), 0.0)
		almost(zone.gust_factor(zone.gust_period * 0.25), 1.0)
		ok(zone.get_node_or_null("HazardHint") is HintArea, "wind has its first encounter hint")
	for x in [432.0, 640.0]:
		ok(LevelSanity.standing_on(tops, Vector2(x, 256)) != null, "48px dry wait before/after lesson")
	for name_ in ["WindPierWest", "WindPierEast"]:
		ok(_rect(host, name_).size.x >= 128.0, "broad pier catches gust displacement")
	for feet in [Vector2(2432, 352), Vector2(2600, 352), Vector2(2780, 320)]:
		ok(LevelSanity.standing_on(tops, feet) != null, "fall lands on recovery support")
		ok(LevelSanity.is_reachable(host, feet, Vector2(2208, 320), false)
			or LevelSanity.is_reachable(host, feet, Vector2(2880, 256), false), "fall escapes by ordinary jumps")
	var west := host.get_node("Props/WindChannel") as ForceZone
	var east := host.get_node("Props/WindTurn") as ForceZone
	ok(west.push.x < 0.0 and east.push.x > 0.0, "second pier reverses wind direction")


func test_original_plate_really_opens_the_wall_gate() -> void:
	var host := _build()
	var plate := host.get_node("Props/WallGatePlate") as PressurePlate
	var door := host.get_node("Props/WallGateDoor") as ArenaDoor
	ok(plate.activated.is_connected(door.open_door))
	plate.activated.emit()
	await flush(2)
	ok(door.is_open)
	var tops := LevelSanity.top_segments(host)
	ok(LevelSanity.standing_on(tops, LAYOUT.PLATE_FEET) != null)
	ok(LevelSanity.standing_on(tops, LAYOUT.GATE_DOOR_POS + Vector2(0, 64)) != null)


func test_old_pickups_path_suppresses_the_consumed_arrow_tower_reward() -> void:
	var host := _build()
	var iron := host.get_node("Pickups/RewardEyrie") as EquipmentPickup
	var old_path := String(iron.get_path())
	SaveData.mark_consumed(old_path)
	host.free()
	await flush(1)
	var restored := _build()
	await flush(2)
	ok(restored.get_node_or_null("Pickups/RewardEyrie") == null, "old consumed reward is removed during ready at its original path")
	ok(restored.get_node_or_null("Props/RewardHookEyrie") != null, "new hook reward has its own persistent key")


func test_hook_eyrie_keeps_core_lore_and_a_supported_equipment_reward() -> void:
	var host := _build()
	var tops := LevelSanity.top_segments(host)
	for path in ["Props/SteleEyrie", "Pickups/EmberCore", "Props/RewardHookEyrie"]:
		var node := host.get_node(path) as Node2D
		var feet := LevelSanity.feet_of(node)
		ok(not LevelSanity.is_reachable(host, LAYOUT.ENTRY_SPAWN, feet, false), "eyrie stays optional: %s" % path)
		ok(LevelSanity.is_reachable(host, LAYOUT.ENTRY_SPAWN, feet, true), "hook reaches %s" % path)
	var reward := host.get_node("Props/RewardHookEyrie") as EquipmentPickup
	eq(reward.reward_ref, "bone_charm")
	ok(LevelSanity.standing_on(tops, reward.position + Vector2(0, 7)) != null, "equipment image rests on the eyrie")
	var iron := host.get_node("Pickups/RewardEyrie") as EquipmentPickup
	eq(iron.reward_ref, "iron_blade")
	ok(LevelSanity.standing_on(tops, iron.position + Vector2(0, 7)) != null)
	ok(LevelSanity.is_reachable(host, LAYOUT.ENTRY_SPAWN, iron.position + Vector2(0, 7), false), "arrow tower reward uses normal jumps")
	var stele := host.get_node("Props/SteleEyrie") as LoreStele
	eq(stele.lore_text, String(ChapterText.stele_of("level09", "SteleEyrie").text))


func test_ground_encounters_use_variants_and_flying_sentries_are_separated() -> void:
	var host := _build()
	var tops := LevelSanity.top_segments(host)
	var demons: Array[Node2D] = []
	var spitters: Array[Node2D] = []
	for e in host.get_node("Enemies").get_children():
		if e is FlyingDemonEnemy:
			demons.append(e)
		elif e is SpitterEnemy:
			spitters.append(e)
			ok(LevelSanity.standing_on(tops, e.position) != null, "spitter stands on its isolated lookout")
		elif e is ScrapperEnemy:
			ok(LevelSanity.standing_on(tops, e.position) != null, "dog has real support")
			for dx in [-e.patrol_range, e.patrol_range]:
				ok(LevelSanity.standing_on(tops, e.position + Vector2(dx, 0)) != null, "dog patrol stays on floor")
	eq(demons.size(), 2)
	ok(absf(demons[1].position.x - demons[0].position.x) > 1000.0, "two separate airborne encounter points")
	eq(spitters.size(), 2)
	ok(absf(spitters[1].position.x - spitters[0].position.x) > spitters[0].aggro_range + spitters[1].aggro_range,
		"spitters cannot cover the same jump")
	eq(host.get_node("Enemies/Scrapper1").variant, &"armored_scrapper")
	eq(host.get_node("Enemies/Scrapper2").variant, &"swift_scrapper")
	eq(host.get_node("Enemies/Spitter2").variant, &"scatter_spitter")


func test_tower_rooms_have_local_shelter_while_wall_top_keeps_outdoor_weather() -> void:
	var host := _build()
	for row in [["GatehouseLee", LAYOUT.ROOMS[0]], ["TowerLee", LAYOUT.ROOMS[1]]]:
		var zone := host.get_node("Props/" + row[0] + "Indoor") as AtmosphereZone
		eq(zone.position, (row[1] as Rect2).position, "indoor collision is positioned at the room")
		eq(zone.zone, WorldClock.Zone.INDOORS)
		var weather := host.get_node("Props/" + row[0]) as WeatherRegion
		eq(weather.position, zone.position)
		almost(weather.intensity, 0.0)
	ok(host.get_node_or_null("IndoorZone") == null, "top route stays outdoors")
	ok(host.get_node_or_null("WindFx") != null)
	ok(host.get_node_or_null("WeatherFx") != null)


func _quiet(points: Array) -> void:
	for feet in points:
		var host := _build()
		var calls := {"attacks": 0}
		for enemy in host.get_node("Enemies").get_children():
			(enemy as EnemyBase).telegraph_started.connect(func(_kind, _duration) -> void: calls.attacks += 1)
		var player := await spawn_player(host, feet - Vector2(0, 20))
		var hp := player.health.current
		await flush(360)
		eq(player.health.current, hp, "rest stays safe for six seconds at %s" % feet)
		eq(calls.attacks, 0, "rest does not wake encounters at %s" % feet)
		host.free()
		await flush(1)


func test_gate_and_mid_nests_remain_quiet_for_six_seconds() -> void:
	await _quiet([Vector2(182, 320), Vector2(1190, 320)])


func test_east_and_rampart_nests_remain_quiet_for_six_seconds() -> void:
	await _quiet([Vector2(2214, 320), Vector2(3222, 320)])


func test_first_wind_has_safe_reading_space_on_both_sides() -> void:
	await _quiet([Vector2(432, 256), Vector2(640, 256)])


func test_authored_lesson_pushes_the_real_knight_and_the_lower_room_has_a_physical_exit() -> void:
	var host := _build()
	for enemy in host.get_node("Enemies").get_children():
		enemy.queue_free()
	await flush(2)
	var wind := host.get_node("Props/WindLesson") as ForceZone
	wind._t = 0.5
	var player := await spawn_player(host, Vector2(504, 236))
	var start := player.position.x
	await flush(24)
	ok(player.position.x > start + 10.0, "authored gust actually carries a standing knight")
	# Isolate room geometry; no optional movement core or dash is needed for the exit.
	player.position = Vector2(1140, 332)
	player.velocity = Vector2.ZERO
	await flush(24)
	ok(player.is_on_floor(), "escape pad catches a real body")
	Input.action_press("jump")
	Input.action_press("move_right")
	await flush(60)
	Input.action_release("jump")
	Input.action_release("move_right")
	ok(player.position.x > 1184.0 and player.position.y <= 321.0, "one basic jump exits the room to the Mid nest (pos=%s)" % player.position)
