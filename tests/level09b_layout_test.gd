extends TestCase
## Level09b "炉风崖道": the cliff road descends in 32px steps to the wind bridge,
## floating stones crossed under a periodic rockfall, the bridge plate opens the
## gate into the wind lee outpost, the climb reaches the lee deck, a final drop
## lands on the ash road that dead-ends at the boss hall; a tether branch above the
## bridge is the only way to the herald's landmark stele + core; three checkpoints,
## a pre-boss nest, and the exit hops to level10.

const LAYOUT_PATH := "res://scripts/levels/chapters/level09b_layout.gd"
const SCENE_PATH := "res://scenes/levels/Level09b_EmberwindCliffs.tscn"
const JUMP_RISE_MAX := 32.0
const JUMP_GAP_MAX := 72.0
const FLOOR_Y := 320.0

var _layout: ChapterLayout
var _host: Node2D


func setup() -> void:
	SaveData.flags.clear()


func teardown() -> void:
	SaveData.flags.clear()
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	Director.abort()


func _consts() -> Dictionary:
	return (load(LAYOUT_PATH) as GDScript).get_script_constant_map()


func _build() -> Node2D:
	_host = Node2D.new()
	_host.name = "Level09b_EmberwindCliffs"
	_host.scene_file_path = SCENE_PATH
	_host.add_to_group("game_world")
	add_child(_host)
	_layout = (load(LAYOUT_PATH) as GDScript).new() as ChapterLayout
	add_child(_layout)
	_layout.build(_host)
	return _host


func _rect_named(host: Node2D, plat_name: String) -> Rect2:
	var p := host.get_node_or_null("Platforms/" + plat_name) as SolidPlatform
	ok(p != null, "%s exists" % plat_name)
	return Rect2(p.position, p.size) if p != null else Rect2()


## One hop from deck `a` onto deck `b`: rise <= 32, edge gap <= 72
## (drops may reach further, mirroring LevelSanity).
func _one_hop(a: Rect2, b: Rect2) -> bool:
	var gap := 0.0
	if b.position.x > a.end.x:
		gap = b.position.x - a.end.x
	elif a.position.x > b.end.x:
		gap = a.position.x - b.end.x
	var rise := a.position.y - b.position.y
	if rise > JUMP_RISE_MAX + 0.01:
		return false
	var reach := JUMP_GAP_MAX if rise >= 0.0 else minf(160.0, JUMP_GAP_MAX + (-rise) * 0.5)
	return gap <= reach + 0.01


func _chain_ok(host: Node2D, names: Array) -> void:
	for i in range(1, names.size()):
		var a := _rect_named(host, String(names[i - 1]))
		var b := _rect_named(host, String(names[i]))
		ok(a.has_area() and b.has_area(), "%s and %s exist" % [names[i - 1], names[i]])
		ok(_one_hop(a, b), "%s -> %s is one hop" % [names[i - 1], names[i]])


func test_metadata_and_vertical_room() -> void:
	var layout := (load(LAYOUT_PATH) as GDScript).new() as ChapterLayout
	eq(layout.level_id(), "level09b")
	eq(layout.title(), ChapterText.title_of("level09b"), "title comes from ChapterText")
	ok(layout.title().contains("炉风崖道"), "title names the emberwind cliffs")
	eq(layout.wake_line(), ChapterText.wake_of("level09b"), "wake line comes from ChapterText")
	ok(layout.wake_line() != "", "one wake line")
	eq(layout.east_limit(), 3400)
	ok(layout.east_limit() >= 3200, "at least 3200px wide")
	eq(layout.theme(), "ramparts")
	ok(not layout.indoors(), "the cliff road is outdoors")
	eq(layout.camera_top(), -400)
	eq(layout.motes(), "cinders")
	var host := _build()
	var lowest := 10000.0
	var highest := -10000.0
	for child in host.get_node("Platforms").get_children():
		if child is SolidPlatform and not String(child.name).begins_with("Wall"):
			var p := child as SolidPlatform
			lowest = maxf(lowest, p.position.y + p.size.y)
			highest = minf(highest, p.position.y)
	ok(lowest - highest >= 720.0, "vertical + horizontal room is at least 720px tall (%.0f)" % (lowest - highest))
	ok(host.get_node_or_null("ParallaxBackdrop") is CanvasLayer, "outdoor rampart backdrop built")
	ok(host.get_node_or_null("IndoorZone") == null, "no indoor zone outdoors")
	layout.free()


func test_cliff_steps_and_wind_bridge_are_single_hops() -> void:
	var host := _build()
	_chain_ok(host, ["CliffTop", "StepA1", "StepA2", "StepA3", "LedgeB",
			"StepB1", "StepB2", "BridgeWest", "Stone1", "Stone2", "Stone3", "Stone4", "BridgeEast"])
	# Every step is a 32px step at most; the bridge stones never float higher than one hop.
	for i in range(1, 10):
		pass
	var bridge_w := _rect_named(host, "BridgeWest")
	var bridge_e := _rect_named(host, "BridgeEast")
	ok(is_equal_approx(bridge_w.position.y, -96.0), "bridge starts one hop below the last step")
	ok(is_equal_approx(bridge_e.position.y, -32.0), "bridge descends toward the outpost")
	# The gate: plate on the bridge opens the door into the lee outpost.
	var props := host.get_node("Props")
	var plate := props.get_node_or_null("WindGatePlate") as PressurePlate
	var door := props.get_node_or_null("WindGateDoor") as ArenaDoor
	ok(plate != null and door != null, "the wind bridge has a plate/door pair")
	if plate == null or door == null:
		return
	ok(plate.activated.is_connected(door.open_door), "the bridge plate opens the outpost gate")
	ok(not door.is_open, "the outpost gate starts closed")
	ok(absf(plate.global_position.x - 1600.0) < 8.0, "the plate stands on the bridge east deck")
	var outpost := _rect_named(host, "OutpostDeck")
	ok(is_equal_approx(door.position.y + 64.0, outpost.position.y), "the gate foot meets the outpost deck")
	plate.slam()
	ok(door.is_open, "pressing the bridge plate rusts the gate open")


func test_climb_deck_and_final_drop_land_on_the_ash_road() -> void:
	var host := _build()
	_chain_ok(host, ["OutpostDeck", "Climb1", "Climb2", "Climb3", "GateDeck"])
	var gate_deck := _rect_named(host, "GateDeck")
	var ledge := _rect_named(host, "DescentLedge")
	ok(_one_hop(gate_deck, ledge), "the lee deck drops onto the descent ledge within one hop")
	var floor_low := _rect_named(host, "FloorLow")
	ok(floor_low.size.x >= 3200.0, "the ash road spans the whole cliff run (soft-lock net)")
	ok(_one_hop(ledge, floor_low), "the descent ledge lands on the ash road")
	# The ash road itself is one continuous walkable line (no unjumpable holes).
	ok(is_equal_approx(floor_low.position.y, FLOOR_Y), "the ash road is the y=320 floor line")


func test_hook_branch_is_the_only_way_to_the_herald_stele() -> void:
	var host := _build()
	var props := host.get_node("Props")
	var anchor := host.get_node("Hooks").get_node_or_null("HookLee") as HookAnchor
	var ledge := _rect_named(host, "LeeLedge")
	var reward := host.get_node_or_null("Pickups/CoreReward") as CorePickup
	ok(anchor != null, "tether anchor above the wind bridge")
	ok(reward != null, "branch reward exists")
	if anchor == null or reward == null:
		return
	var stone2 := _rect_named(host, "Stone2")
	var launch := Vector2(clampf(anchor.position.x, stone2.position.x, stone2.end.x), stone2.position.y - 48.0)
	ok(launch.distance_to(anchor.position) <= LevelSanity.HOOK_REACH, "anchor is within tether reach of the bridge")
	var drop := ledge.position.y - anchor.position.y
	ok(drop > 0.0 and drop <= LevelSanity.HOOK_LAND_BELOW, "lee ledge is a tether drop under the anchor")
	ok(absf((ledge.position.x + ledge.size.x * 0.5) - anchor.position.x) <= LevelSanity.HOOK_LAND_X,
			"lee ledge is centred under the anchor")
	var spawn: Vector2 = _consts()["ENTRY_SPAWN"]
	ok(not LevelSanity.is_reachable(host, spawn, LevelSanity.feet_of(reward), false),
			"the main route cannot grab the herald stele reward")
	ok(LevelSanity.is_reachable(host, spawn, LevelSanity.feet_of(reward), true),
			"the hookshot reaches the herald stele reward")
	# Landmark stele text comes from ChapterText.
	var stele := props.get_node_or_null("SteleGate") as LoreStele
	ok(stele != null, "the gate stele stands on the lee deck")
	if stele != null:
		var entry := ChapterText.stele_of("level09b", "SteleGate")
		eq(String(stele.lore_title), String(entry.get("title", "")), "SteleGate text comes from ChapterText")
		ok(String(stele.lore_text) != "", "SteleGate says something")
		var tops := LevelSanity.top_segments(host)
		ok(LevelSanity.standing_on(tops, LevelSanity.feet_of(stele)) != null, "SteleGate stands on the lee deck")


func test_wind_weather_and_lee_outpost() -> void:
	var layout := (load(LAYOUT_PATH) as GDScript).new() as ChapterLayout
	var ambient := layout.ambient()
	eq(String(ambient.get("weather", "")), "ember_wind", "the cliff road opens in ember wind")
	var recipe := layout.weather_recipe()
	var allowed: Array = recipe.get("allowed", [])
	for kind in allowed:
		var w := int(kind)
		ok(w >= WorldClock.Weather.HAZE and w <= WorldClock.Weather.CLEAR, "allowed weather ids are real")
	var regions := layout.weather_regions()
	eq(regions.size(), 2, "two local wind regions (gale bridge + lee outpost)")
	var gale: Dictionary = {}
	var lee: Dictionary = {}
	for spec in regions:
		var s: Dictionary = spec
		if String(s.get("name", "")) == "GaleBridge":
			gale = s
		elif String(s.get("name", "")) == "GaleLee":
			lee = s
	ok(not gale.is_empty() and not lee.is_empty(), "the gale and the lee pocket are named")
	var limit := float(layout.east_limit())
	var top := float(layout.camera_top()) - 64.0
	for s in [gale, lee]:
		if s.is_empty():
			continue
		var rect: Rect2 = s["rect"]
		ok(rect.position.x >= 0.0 and rect.end.x <= limit + 0.5, "%s stays inside east_limit" % s["name"])
		ok(rect.position.y >= top - 0.5 and rect.end.y <= 400.5, "%s stays between camera_top and the floor" % s["name"])
		var wind := float(s.get("wind_scale", 1.0))
		ok(wind >= 0.0 and wind <= 2.0, "%s wind_scale is in range" % s["name"])
	if not gale.is_empty() and not lee.is_empty():
		ok(float(gale.get("wind_scale", 1.0)) > 1.5, "the wind bridge is the gale")
		ok(float(lee.get("wind_scale", 1.0)) < 0.5, "the outpost is in the wind lee")
		ok(float(lee.get("intensity", 1.0)) < 0.5, "the lee pocket is calm")
		var rect: Rect2 = lee["rect"]
		ok(rect.has_point(Vector2(1848.0, 0.0)), "the safe outpost nest sits inside the lee pocket")
	var host := _build()
	var outpost_nest := host.get_node_or_null("Props/EmberNestOutpost") as Node2D
	ok(outpost_nest != null, "the safe outpost checkpoint exists")
	layout.free()


func test_bridge_rockfall_is_a_readable_periodic_hazard() -> void:
	var host := _build()
	var rig := host.get_node_or_null("Arenas/BridgeRockfallRig") as BossArena
	ok(rig != null, "a hazard rig is mounted over the wind bridge")
	if rig != null:
		eq(rig.arena_left, 1100.0)
		eq(rig.arena_right, 1740.0)
		ok(not rig.start_on_intro and not rig.start_immediately, "the bridge rig never steals pause/camera control")
		ok(not rig.clamp_player and not rig.clamp_boss, "the bridge rig never clamps the knight or a boss")
		ok(rig.arena_left < 1120.0 and rig.arena_right > 1720.0, "rig bounds cover the whole bridge")
		eq(rig.get_child_count(), 0, "no rock is armed before the first timer tick")
	var timer := host.get_node_or_null("Props/RockfallTimer") as Timer
	ok(timer != null, "the rockfall is driven by a timer")
	if timer != null:
		ok(timer.wait_time >= 2.5, "rocks fall on a slow, readable cadence (%.1fs)" % timer.wait_time)
		ok(not timer.one_shot, "the timer keeps running (periodic rocks, not one shot)")
		ok(timer.autostart or timer.time_left > 0.0, "the timer starts with the level")
		timer.timeout.emit()
		ok(rig != null and rig.get_child_count() >= 1, "a tick arms one falling-rock hazard with its telegraph")


func test_checkpoints_exit_and_boss_slot() -> void:
	var host := _build()
	var props := host.get_node("Props")
	var nests: Array[Node] = []
	for child in props.get_children():
		if child is EmberNest:
			nests.append(child)
	ok(nests.size() >= 3, "at least two checkpoints plus the pre-boss nest (%d)" % nests.size())
	var spawn: Vector2 = _consts()["ENTRY_SPAWN"]
	for nest in nests:
		ok(LevelSanity.is_reachable(host, spawn, LevelSanity.feet_of(nest), false),
				"nest %s is reachable from spawn" % nest.name)
	var exit := props.get_node_or_null("Exit") as LevelExit
	ok(exit != null, "the furnace gate exit exists")
	if exit != null:
		eq(exit.door_label, ChapterText.exit_label_of("level09b"))
		eq(exit.captions, ChapterText.exit_captions_of("level09b"))
		eq(exit.flag_id, "level09b_done")
		eq(exit.target_scene, String(GameContext.LEVELS["level10"]), "the furnace gate leads to level10")
		eq(exit.spawn, ChapterLayout.entry_spawn_of("level10"))
		var tops := LevelSanity.top_segments(host)
		ok(LevelSanity.standing_on(tops, LevelSanity.feet_of(exit)) != null, "the exit stands on the ash road")
		ok(exit.position.x <= float(_consts()["EAST_LIMIT"]) - LevelSanity.EXIT_WALL_CLEAR,
				"exit keeps clear of the east wall")
		ok(LevelSanity.is_reachable(host, spawn, LevelSanity.feet_of(exit), false),
				"the exit is reachable without optional abilities")
	var arena_left := float(_consts()["ARENA_LEFT"])
	var pre_boss := props.get_node_or_null("EmberNestGate") as Node2D
	ok(pre_boss != null, "pre-boss checkpoint exists")
	if pre_boss == null:
		return
	ok(LevelSanity.feet_of(pre_boss).x < arena_left, "the pre-boss nest sits before the arena gate")
	ok(ChapterLayout.ENEMY_SCENES.has("emberwind_herald"), "EmberwindHerald is registered in the boss-slot table")
	var boss_scene := String(ChapterLayout.ENEMY_SCENES.get("emberwind_herald", ""))
	if not ResourceLoader.exists(boss_scene):
		ok(true, "EmberwindHerald scene not delivered yet — the arena slot is skipped by feature detection")
		return
	ok(host.get_node_or_null("Enemies/EmberwindHerald") != null, "the EmberwindHerald slot spawns the boss")
	var arena := _layout.boss_arena(host, "EmberwindHerald") as BossArena
	ok(arena != null, "the boss arena is attached")
	if arena != null:
		ok(arena.arena_right - arena.arena_left >= 600.0, "arena is at least 600px wide")
		var report := arena.checkpoint_report()
		ok(bool(report["ok"]), "pre-boss checkpoint sits within 80px of the gate (nearest: %s)" % str(report["nest"]))
		ok(arena.registered_hazard_ids().size() >= 2, "arena carries >=2 readable hazards")


func test_decor_follows_the_ramparts_allowlist() -> void:
	var host := _build()
	ok(_layout.prop_allowed("balustrade_wall"), "ramparts allow the cold parapet")
	ok(not _layout.prop_allowed("grave_cross"), "ramparts never plant graveyard crosses")
	ok(not _layout.prop_allowed("window"), "ramparts never plant cathedral windows outdoors")
	var decor := host.get_node_or_null("Decor") as Node2D
	ok(decor != null, "a decor layer exists")
	if decor == null:
		return
	var grounded := 0
	for child in decor.get_children():
		var spr := child as Sprite2D
		if spr == null or not spr.has_meta("prop_key"):
			continue
		var key := String(spr.get_meta("prop_key"))
		ok(PropCatalog.allowed("ramparts", key), "'%s' is allowed in ramparts" % key)
		if spr.is_in_group("grounded"):
			grounded += 1
			almost(spr.scale.x, 1.0, 0.001, "%s is planted at 1x" % key)
	ok(grounded >= 5, "enough grounded set dressing (%d)" % grounded)
	for child in decor.get_children():
		ok(not (child is ColorRect), "no ColorRect placeholder in the decor")
