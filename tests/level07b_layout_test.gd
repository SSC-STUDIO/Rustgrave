extends TestCase
## Level07b "铸钟厅": two chain lifts hand the knight across the molten ladle pool,
## the mould deck's pressure plate opens the gate before the casting pit, two gears
## bridge that pit, an upper tether branch holds the last bell stele + a core
## reward the main route cannot read, three checkpoints and a pre-boss nest stand
## on solid floor, and the exit hops to level08.

const LAYOUT_PATH := "res://scripts/levels/chapters/level07b_layout.gd"
const SCENE_PATH := "res://scenes/levels/Level07b_BellFoundry.tscn"
const JUMP_RISE_MAX := 32.0
const JUMP_GAP_MAX := 72.0
const DECK_H := 16.0
const FLOOR_Y := 320.0

var _layout: ChapterLayout
var _host: Node2D


func setup() -> void:
	SaveData.flags.clear()


func teardown() -> void:
	SaveData.flags.clear()
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)


func _consts() -> Dictionary:
	return (load(LAYOUT_PATH) as GDScript).get_script_constant_map()


func _build() -> Node2D:
	_host = Node2D.new()
	_host.name = "Level07b_BellFoundry"
	_host.scene_file_path = SCENE_PATH
	_host.add_to_group("game_world")
	add_child(_host)
	_layout = (load(LAYOUT_PATH) as GDScript).new() as ChapterLayout
	add_child(_layout)
	_layout.build(_host)
	return _host


## Walkable tops as rects: solids (ceilings/walls excluded), lift decks, gear tops.
func _tops(host: Node2D) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for child in host.get_node("Platforms").get_children():
		if child is SolidPlatform:
			var p := child as SolidPlatform
			var name_ := String(p.name)
			if p.size.x < 24.0 or name_.begins_with("Ceiling") or name_.begins_with("Wall"):
				continue
			rects.append(Rect2(p.position, p.size))
		elif child is MovingPlatform:
			var m := child as MovingPlatform
			rects.append(Rect2(m.start_position(), Vector2(m.width, DECK_H)))
			rects.append(Rect2(m.end_position(), Vector2(m.width, DECK_H)))
		elif child is GearPlatform:
			var g := child as GearPlatform
			rects.append(Rect2(g.position - Vector2(g.radius, g.radius), Vector2(g.radius * 2.0, g.radius * 2.0)))
	return rects


func _standing_on(rects: Array[Rect2], feet: Vector2, slack: float = 0.5) -> bool:
	for r in rects:
		if feet.x >= r.position.x - 0.01 and feet.x <= r.end.x + 0.01 and absf(feet.y - r.position.y) <= slack:
			return true
	return false


func _rect_named(host: Node2D, plat_name: String) -> Rect2:
	var node := host.get_node_or_null("Platforms/" + plat_name)
	if node is SolidPlatform:
		return Rect2((node as SolidPlatform).position, (node as SolidPlatform).size)
	if node is GearPlatform:
		var g := node as GearPlatform
		return Rect2(g.position - Vector2(g.radius, g.radius), Vector2(g.radius * 2.0, g.radius * 2.0))
	ok(false, "%s exists" % plat_name)
	return Rect2()


func _deck_rect(m: MovingPlatform, at_end: bool) -> Rect2:
	return Rect2(m.end_position() if at_end else m.start_position(), Vector2(m.width, DECK_H))


## One hop from deck `a` (top-left, size) onto deck `b`: rise <= 32, edge gap <= 72
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


func test_metadata_and_room() -> void:
	var layout := (load(LAYOUT_PATH) as GDScript).new() as ChapterLayout
	eq(layout.level_id(), "level07b")
	eq(layout.title(), ChapterText.title_of("level07b"), "title comes from ChapterText")
	ok(layout.title().contains("铸钟厅"), "title names the bell foundry")
	eq(layout.wake_line(), ChapterText.wake_of("level07b"), "wake line comes from ChapterText")
	ok(layout.wake_line() != "", "one wake line")
	eq(layout.east_limit(), 3520)
	ok(layout.east_limit() >= 3400, "at least 3400px wide")
	eq(layout.theme(), "forge")
	ok(layout.indoors(), "the bell foundry is an indoor theme")
	eq(layout.camera_top(), -224)
	eq(layout.motes(), "embers")
	var host := _build()
	ok(host.get_node_or_null("ParallaxBackdrop") is CanvasLayer, "indoor backdrop built")
	ok(host.get_node_or_null("IndoorZone") is AtmosphereZone, "the whole level is an indoor zone")
	var ceiling := host.get_node_or_null("Platforms/Ceiling") as SolidPlatform
	ok(ceiling != null, "enclosed ceiling (room, not a void)")
	if ceiling != null:
		var room := (FLOOR_Y + 80.0) - ceiling.position.y
		ok(room >= 480.0, "room is at least 480px tall (%.0f)" % room)
	var boss_floor := _rect_named(host, "FloorE")
	ok(boss_floor.size.x >= 600.0, "boss hall is wide enough for an arena (%.0f)" % boss_floor.size.x)
	layout.free()


func test_ladle_bay_is_crossed_by_two_lifts_over_molten_metal() -> void:
	var host := _build()
	var props := host.get_node("Props")
	var tops := _tops(host)
	for pit in ["LadlePit", "MoldPit", "CastPit"]:
		var pool := props.get_node_or_null(pit + "Pool") as ToxinPool
		ok(pool != null, "%s river of molten metal" % pit)
		if pool != null:
			ok(pool.tint.r > pool.tint.g * 2.0 and pool.tint.r > pool.tint.b * 2.0,
					"%s is molten (over-tinted red), not green poison" % pit)
			var bed := _rect_named(host, pit + "Bed")
			ok(bed.has_area(), "%s has a pit bed" % pit)
			ok(is_equal_approx(bed.position.y, FLOOR_Y + 32.0), "%s is only 32px deep" % pit)
			# 32px deep: climb back out onto whichever floor lip the pit touches.
			var escaped := false
			for r in tops:
				if absf(r.position.y - FLOOR_Y) > 0.5:
					continue
				if _one_hop(bed, r):
					escaped = true
			ok(escaped, "%s is climbable out of, never a soft lock" % pit)
	var lift_a := host.get_node_or_null("Platforms/LiftA") as MovingPlatform
	var lift_b := host.get_node_or_null("Platforms/LiftB") as MovingPlatform
	ok(lift_a != null and lift_b != null, "two ladle lifts")
	if lift_a == null or lift_b == null:
		return
	ok(lift_a.travel.x >= 160.0 and is_zero_approx(lift_a.travel.y), "ladles run horizontally")
	ok(not is_equal_approx(lift_a.phase, lift_b.phase), "the two ladles are out of phase")
	var floor_a := _rect_named(host, "FloorA")
	var floor_b := _rect_named(host, "FloorB")
	ok(_one_hop(floor_a, _deck_rect(lift_a, false)), "LiftA boards from FloorA within one hop")
	ok(_one_hop(_deck_rect(lift_a, true), floor_b), "LiftA lands on FloorB within one hop")
	ok(_one_hop(_deck_rect(lift_b, true), floor_b), "LiftB also lands on FloorB")
	# Both decks ride above the molten surface (never sit in the pool).
	var pool := props.get_node_or_null("LadlePitPool") as ToxinPool
	if pool != null:
		var surface := pool.surface_rect()
		ok(_deck_rect(lift_a, false).end.y <= surface.position.y, "LiftA deck clears the molten surface")
		ok(_deck_rect(lift_b, false).end.y <= surface.position.y, "LiftB deck clears the molten surface")


func test_mould_plate_opens_gate_and_gears_bridge_the_cast_pit() -> void:
	var host := _build()
	var props := host.get_node("Props")
	var tops := LevelSanity.top_segments(host)
	var plate := props.get_node_or_null("MoldGatePlate") as PressurePlate
	var door := props.get_node_or_null("MoldGateDoor") as ArenaDoor
	ok(plate != null and door != null, "the mould bench has a plate/door pair")
	if plate == null or door == null:
		return
	ok(plate.activated.is_connected(door.open_door), "the mould plate opens the gate")
	ok(not door.is_open, "the gate starts closed")
	ok(LevelSanity.standing_on(tops, LevelSanity.feet_of(plate)) != null,
			"the plate rests on the mould deck")
	ok(LevelSanity.standing_on(tops, door.position + Vector2(0, 64)) != null, "the gate foot meets FloorD")
	plate.slam()
	ok(door.is_open, "pressing the plate rusts the gate open")
	# The mould deck itself is only reachable via the 32px step, not straight up.
	_chain_ok(host, ["FloorC", "MoldStep", "MoldDeck"])
	ok(not _one_hop(_rect_named(host, "FloorC"), _rect_named(host, "MoldDeck")),
			"the mould deck is not a free jump from the floor")
	# Gears carry the route over the cast pit into the boss hall.
	_chain_ok(host, ["FloorD", "GearA", "GearB", "FloorE"])
	var cast := props.get_node_or_null("CastPitPool") as ToxinPool
	ok(cast != null, "the casting pit is molten")
	if cast != null:
		var surface := cast.surface_rect()
		for gear_name in ["GearA", "GearB"]:
			var gear_rect := _rect_named(host, gear_name)
			ok(gear_rect.end.y <= surface.position.y + 0.5, "%s rides above the casting pit" % gear_name)


func test_hook_branch_reads_the_last_bell_stele_and_reward() -> void:
	var host := _build()
	var props := host.get_node("Props")
	var hooks := host.get_node("Hooks")
	var anchor := hooks.get_node_or_null("HookMold") as HookAnchor
	var catwalk := _rect_named(host, "MoldCatwalk")
	var stele := props.get_node_or_null("SteleKey") as LoreStele
	var reward := host.get_node_or_null("Pickups/CoreReward") as CorePickup
	ok(anchor != null, "tether anchor over the ladle bay")
	ok(catwalk.has_area() and stele != null and reward != null, "catwalk, last stele and reward exist")
	if anchor == null or not catwalk.has_area() or stele == null or reward == null:
		return
	# Standard tether geometry: reach from FloorB, drop below the anchor.
	var floor_b := _rect_named(host, "FloorB")
	var launch := Vector2(clampf(anchor.position.x, floor_b.position.x, floor_b.end.x), floor_b.position.y - 48.0)
	ok(launch.distance_to(anchor.position) <= LevelSanity.HOOK_REACH, "anchor is within tether reach of FloorB")
	var drop := catwalk.position.y - anchor.position.y
	ok(drop > 0.0 and drop <= LevelSanity.HOOK_LAND_BELOW, "catwalk is a tether drop under the anchor")
	ok(absf((catwalk.position.x + catwalk.size.x * 0.5) - anchor.position.x) <= LevelSanity.HOOK_LAND_X,
			"catwalk is centred under the anchor")
	var spawn: Vector2 = _consts()["ENTRY_SPAWN"]
	ok(not LevelSanity.is_reachable(host, spawn, LevelSanity.feet_of(stele), false),
			"the main route cannot read the last bell stele")
	ok(LevelSanity.is_reachable(host, spawn, LevelSanity.feet_of(stele), true),
			"the hookshot reaches the last bell stele")
	ok(not LevelSanity.is_reachable(host, spawn, LevelSanity.feet_of(reward), false),
			"the branch reward is hook-only (no main-route freebie)")
	ok(LevelSanity.is_reachable(host, spawn, LevelSanity.feet_of(reward), true),
			"the hookshot reaches the branch reward")
	var entry := ChapterText.stele_of("level07b", "SteleKey")
	ok(String(stele.lore_title) == String(entry.get("title", "")), "SteleKey text comes from ChapterText")
	ok(String(stele.lore_text) != "", "SteleKey says something")


func test_checkpoints_exit_and_boss_slot() -> void:
	var host := _build()
	var props := host.get_node("Props")
	var tops := LevelSanity.top_segments(host)
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
	ok(exit != null, "the well door exists")
	if exit != null:
		eq(exit.door_label, ChapterText.exit_label_of("level07b"))
		eq(exit.captions, ChapterText.exit_captions_of("level07b"))
		eq(exit.flag_id, "level07b_done")
		eq(exit.target_scene, String(GameContext.LEVELS["level08"]), "the well drops to level08")
		eq(exit.spawn, ChapterLayout.entry_spawn_of("level08"))
		ok(LevelSanity.standing_on(tops, LevelSanity.feet_of(exit)) != null, "exit stands on the boss hall floor")
		ok(exit.position.x <= float(_consts()["EAST_LIMIT"]) - LevelSanity.EXIT_WALL_CLEAR,
				"exit keeps clear of the east wall")
		ok(LevelSanity.is_reachable(host, spawn, LevelSanity.feet_of(exit), false),
				"the exit is reachable without optional abilities")
	var arena_left := float(_consts()["ARENA_LEFT"])
	var pre_boss := props.get_node_or_null("EmberNestCast") as Node2D
	ok(pre_boss != null, "pre-boss checkpoint exists")
	if pre_boss == null:
		return
	ok(LevelSanity.feet_of(pre_boss).x < arena_left, "pre-boss nest sits before the arena gate")
	ok(ChapterLayout.ENEMY_SCENES.has("bell_founder"), "BellFounder is registered in the boss-slot table")
	var boss_scene := String(ChapterLayout.ENEMY_SCENES.get("bell_founder", ""))
	if not ResourceLoader.exists(boss_scene):
		ok(true, "BellFounder scene not delivered yet — the arena slot is skipped by feature detection")
		return
	var boss_node := host.get_node_or_null("Enemies/BellFounder") as Node2D
	ok(boss_node != null, "the BellFounder slot spawns the boss")
	var arena := _layout.boss_arena(host, "BellFounder") as BossArena
	ok(arena != null, "the boss arena is attached")
	if arena != null:
		ok(arena.arena_right - arena.arena_left >= 600.0, "arena is at least 600px wide")
		var report := arena.checkpoint_report()
		ok(bool(report["ok"]), "pre-boss checkpoint sits within 80px of the gate (nearest: %s)" % str(report["nest"]))
		ok(arena.registered_hazard_ids().size() >= 2, "arena carries >=2 readable hazards")


func test_decor_follows_the_forge_allowlist() -> void:
	var host := _build()
	ok(_layout.prop_allowed("skull_arch"), "forge allows furnace setpieces")
	ok(not _layout.prop_allowed("grave_cross"), "forge never plants graveyard crosses")
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
		ok(PropCatalog.allowed("forge", key), "'%s' is allowed in forge" % key)
		if spr.is_in_group("grounded"):
			grounded += 1
			almost(spr.scale.x, 1.0, 0.001, "%s is planted at 1x" % key)
	ok(grounded >= 5, "enough grounded set dressing (%d)" % grounded)
	for child in decor.get_children():
		ok(not (child is ColorRect), "no ColorRect placeholder in the decor")
