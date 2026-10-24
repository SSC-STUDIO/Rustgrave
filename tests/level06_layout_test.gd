extends TestCase
const LAYOUT := preload("res://scripts/levels/chapters/level06_layout.gd")
var _flags: PackedStringArray


func setup() -> void:
	_flags = SaveData.flags.duplicate()
	SaveData.flags.clear()
	Director.abort()
	Director.resume()
	Director._set_lock(false)


func teardown() -> void:
	SaveData.flags = _flags
	Director.abort()
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)


func _build() -> Node2D:
	var host := Node2D.new()
	host.name = "Level06_NightGraveyard"
	host.scene_file_path = GameContext.LEVELS["level06"]
	host.add_to_group("game_world")
	add_child(host)
	var layout := LAYOUT.new()
	add_child(layout)
	layout.build(host)
	return host


func test_main_route_and_all_checkpoints_remain_reachable_without_optional_cores() -> void:
	var host := _build()
	var problems := LevelSanity.check(host)
	for problem in problems:
		ok(false, problem)
	ok(problems.is_empty(), "LevelSanity passes")
	var previous := LAYOUT.NEST_START_X
	for row in LAYOUT.NESTS:
		var node := host.get_node("Props/" + String(row[0])) as EmberNest
		var feet := LevelSanity.feet_of(node)
		ok(LevelSanity.is_reachable(host, Vector2(96, 300), feet, false), "%s is on the basic route" % row[0])
		ok(float(row[1]) - previous <= 1010.0, "death run stays close to 1000px")
		previous = float(row[1])
	for name_ in ["MausoleumPlate", "MausoleumDoor", "Exit", "SteleHallen", "SteleVeil"]:
		var node := host.get_node("Props/" + name_) as Node2D
		ok(LevelSanity.is_reachable(host, Vector2(96, 300), LevelSanity.feet_of(node), false), "%s is reachable" % name_)
	var exit := host.get_node("Props/Exit") as LevelExit
	eq(exit.flag_id, "level06_done")
	eq(exit.target_scene, GameContext.LEVELS["level07"])
	eq(exit.spawn, ChapterLayout.entry_spawn_of("level07"))


func test_mausoleum_has_two_walkable_routes_and_a_one_way_return_drop() -> void:
	var host := _build()
	var tops := LevelSanity.top_segments(host)
	for chain in LAYOUT.CHAINS:
		for i in range(1, chain.size()):
			var a := LevelSanity.standing_on(tops, chain[i - 1])
			var b := LevelSanity.standing_on(tops, chain[i])
			ok(a != null and b != null, "route points have real support")
			if a != null and b != null:
				ok(LevelSanity._can_hop(a, b), "outer route uses only ordinary jumps")
	for feet in [Vector2(1504, 320), Vector2(2304, 320), Vector2(1648, 160), Vector2(2368, 160)]:
		ok(LevelSanity.is_reachable(host, Vector2(96, 300), feet, false), "both routes reachable at %s" % feet)
	var roof := LevelSanity.standing_on(tops, Vector2(1592, 160))
	var crypt := LevelSanity.standing_on(tops, Vector2(1552, 320))
	ok(roof != null and crypt != null)
	if roof != null and crypt != null:
		ok(LevelSanity._can_hop(roof, crypt), "return drops straight to the previous crypt nest")
		ok(not LevelSanity._can_hop(crypt, roof), "160px drop cannot be reversed by one jump")
	var rect := LAYOUT.RETURN_DROP
	for node in host.get_node("Platforms").get_children():
		if node is SolidPlatform:
			ok(not Rect2(node.position, node.size).intersects(Rect2(rect.position + Vector2(1, 0), Vector2(46, 159))), "return shaft stays clear")


func test_mausoleum_plate_opens_the_preserved_door() -> void:
	var host := _build()
	var plate := host.get_node("Props/MausoleumPlate") as PressurePlate
	var door := host.get_node("Props/MausoleumDoor") as ArenaDoor
	ok(plate.activated.is_connected(door.open_door))
	plate.activated.emit()
	await flush(2)
	ok(door.is_open, "the existing plate opens the real door")
	var tops := LevelSanity.top_segments(host)
	ok(LevelSanity.standing_on(tops, LAYOUT.PLATE_FEET) != null)
	ok(LevelSanity.standing_on(tops, LAYOUT.DOOR_POS + Vector2(0, 64)) != null)


func test_mud_is_skippable_and_the_first_patch_has_safe_reading_space() -> void:
	var host := _build()
	var tops := LevelSanity.top_segments(host)
	for row in LAYOUT.MUD:
		var mud := host.get_node("Props/" + String(row[0])) as ForceZone
		eq(mud.skin, "mud")
		almost(mud.drag, 0.4)
		ok(mud.toxin_per_second >= 12.0 and mud.toxin_per_second <= 16.0)
		eq(mud.push, Vector2.ZERO)
	var lesson := host.get_node("Props/MudLesson") as ForceZone
	var r := lesson.zone_rect()
	for feet in [Vector2(r.position.x - 48, 320), Vector2(r.end.x + 48, 320), Vector2(400, 288)]:
		ok(LevelSanity.standing_on(tops, feet) != null, "first mud has dry landing at %s" % feet)
		ok(not r.has_point(feet - Vector2(0, 2)), "dry wait is outside the toxic drag")
	for row in LAYOUT.NESTS:
		var feet := LevelSanity.feet_of(host.get_node("Props/" + String(row[0])))
		for spec in LAYOUT.MUD:
			ok(not (spec[1] as Rect2).grow(24).has_point(feet), "nest does not share the mud")


func test_clustered_skeletons_wake_peers_and_the_exploder_has_retreat_room() -> void:
	var host := _build()
	for names in [["Skeleton1", "Skeleton2", "Skeleton5"], ["Skeleton3", "Skeleton4"], ["Skeleton6", "Skeleton7"]]:
		var lead := host.get_node("Enemies/" + String(names[0])) as SkeletonEnemy
		var peer := host.get_node("Enemies/" + String(names[1])) as SkeletonEnemy
		almost(lead.alert_radius, 160.0)
		almost(lead.lose_range, 260.0)
		eq(peer.state(), SkeletonEnemy.State.BURIED)
		lead.alert_peers()
		eq(peer.state(), SkeletonEnemy.State.RISE, "nearby buried skeleton answers its peer")
	var blast := host.get_node("Enemies/Skeleton4") as SkeletonEnemy
	eq(blast.variant, &"exploder_skeleton")
	ok(blast.has_meta("variant_blast"))
	var tops := LevelSanity.top_segments(host)
	for dx in [-80.0, 80.0]:
		ok(LevelSanity.standing_on(tops, blast.position + Vector2(dx, 0)) != null, "blast can be escaped in either direction")
	for row in LAYOUT.ENEMIES:
		var enemy := host.get_node("Enemies/" + String(row[0])) as Node2D
		eq(enemy.position, row[2])
		if not enemy is GhostEnemy:
			ok(LevelSanity.standing_on(tops, enemy.position) != null, "ground enemy is supported")


func test_tree_branch_keeps_lore_core_and_an_equipment_reward_optional() -> void:
	var host := _build()
	for name_ in ["SteleTree", "RewardTreeTop"]:
		var feet := LevelSanity.feet_of(host.get_node("Props/" + name_))
		ok(LevelSanity.standing_on(LevelSanity.top_segments(host), feet) != null)
		ok(not LevelSanity.is_reachable(host, Vector2(96, 300), feet, false), "tree reward requires the optional hook")
		ok(LevelSanity.is_reachable(host, Vector2(96, 300), feet, true), "hook reaches the reward")
	var reward := host.get_node("Props/RewardTreeTop") as EquipmentPickup
	eq(reward.reward_kind, "equipment")
	eq(reward.reward_ref, "bone_charm")
	var core := host.get_node("Pickups/EmberCoreTreeTop") as CorePickup
	var hook := host.get_node("Hooks/HookTreeTop") as HookAnchor
	ok(core.position.distance_to(hook.position) <= 96.0)
	var tree := host.get_node("Props/SteleTree") as LoreStele
	ok(tree.lore_text != "")


func test_local_interior_matches_the_mausoleum_and_weather_leaves_checkpoints_clear() -> void:
	var host := _build()
	var zone := host.get_node("Props/MausoleumShelterIndoor") as AtmosphereZone
	eq(zone.world_rect(), LAYOUT.CRYPT_RECT)
	ok(zone.contains_point(Vector2(1800, 300)))
	ok(not zone.contains_point(Vector2(1800, 144)), "roof stays outdoors")
	var shelter := host.get_node("Props/MausoleumShelter") as WeatherRegion
	eq(shelter.weather, WorldClock.Weather.CLEAR)
	almost(shelter.intensity, 0.0)
	for fog in ["GraveFog", "RoofFog", "EastGraveFog"]:
		var region := host.get_node("Props/" + fog) as WeatherRegion
		for row in LAYOUT.NESTS:
			ok(not Rect2(region.position, region.rect).has_point(Vector2(row[1], 300)), "fog does not cover the checkpoint")
	var layout := LAYOUT.new()
	eq(layout.theme(), "graveyard")
	ok(not layout.indoors())
	eq(layout.title(), ChapterText.title_of("level06"))
	layout.free()


func _check_rest(names: Array) -> void:
	for name_ in names:
		var host := _build()
		var nest := host.get_node("Props/" + name_) as EmberNest
		var calls := {"attacks": 0}
		for enemy in host.get_node("Enemies").get_children():
			(enemy as EnemyBase).telegraph_started.connect(func(_kind, _duration) -> void: calls.attacks += 1)
		var player := await spawn_player(host, LevelSanity.feet_of(nest) - Vector2(0, 20))
		var hp := player.health.current
		await flush(360)
		eq(player.health.current, hp, "%s stays safe for six seconds" % name_)
		eq(calls.attacks, 0, "%s does not wake an encounter" % name_)
		host.free()
		await flush(1)


func test_start_rain_and_crypt_checkpoints_remain_quiet_for_six_seconds() -> void:
	await _check_rest(["EmberNestStart", "EmberNestRain", "EmberNestCrypt"])


func test_grove_and_east_checkpoints_remain_quiet_for_six_seconds() -> void:
	await _check_rest(["EmberNestGrove", "EmberNestEast"])


func test_first_mud_can_be_read_from_either_dry_side_without_an_ambush() -> void:
	for x in [304.0, 480.0]:
		var host := _build()
		var calls := {"attacks": 0}
		for enemy in host.get_node("Enemies").get_children():
			(enemy as EnemyBase).telegraph_started.connect(func(_kind, _duration) -> void: calls.attacks += 1)
		var player := await spawn_player(host, Vector2(x, 300))
		var hp := player.health.current
		var toxin: float = player.toxin.toxin
		await flush(360)
		eq(player.health.current, hp, "first mud wait remains safe at %s" % x)
		eq(calls.attacks, 0, "first mud wait does not awaken the grave cluster")
		almost(player.toxin.toxin, toxin, 0.01, "dry wait does not gain toxin")
		host.free()
		await flush(1)
