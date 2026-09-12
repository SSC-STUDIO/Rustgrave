extends TestCase
## Level06 "墓园夜雨": authored geometry stays jumpable, mounds are dug into the
## ground, the pressure plate opens the mausoleum door, props/enemies stand on
## solid ground, the tree-top core hangs by its hook, and the bell door leads
## to level07 under the open graveyard sky.

const LAYOUT_PATH := "res://scripts/levels/chapters/level06_layout.gd"
const JUMP_RISE_MAX := 32.0
const JUMP_GAP_MAX := 72.0


func setup() -> void:
	SaveData.flags.clear()


func teardown() -> void:
	SaveData.flags.clear()
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)


func _consts() -> Dictionary:
	return (load(LAYOUT_PATH) as GDScript).get_script_constant_map()


func _host() -> Node2D:
	var host := Node2D.new()
	host.name = "Level06_NightGraveyard"
	host.scene_file_path = GameContext.LEVELS["level06"]
	host.add_to_group("game_world")
	add_child(host)
	return host


func _build() -> Node2D:
	var host := _host()
	var level := (load(LAYOUT_PATH) as GDScript).new() as ChapterLayout
	add_child(level)
	level.build(host)
	return host


func _solids(host: Node2D) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for child in host.get_node("Platforms").get_children():
		if child is SolidPlatform:
			rects.append(Rect2(child.position, child.size))
	return rects


func _standing_on(rects: Array[Rect2], feet: Vector2, slack: float = 0.5) -> bool:
	for r in rects:
		if feet.x >= r.position.x - 0.01 and feet.x <= r.end.x + 0.01 and absf(feet.y - r.position.y) <= slack:
			return true
	return false


func _plat(host: Node2D, plat_name: String) -> SolidPlatform:
	return host.get_node_or_null("Platforms/" + plat_name) as SolidPlatform


func _right(plat: SolidPlatform) -> float:
	return plat.position.x + plat.size.x


func _bottom(plat: SolidPlatform) -> float:
	return plat.position.y + plat.size.y


func _on_top_of(plat: SolidPlatform, feet: Vector2) -> bool:
	return feet.x > plat.position.x and feet.x < _right(plat) and is_equal_approx(feet.y, plat.position.y)


func test_step_chains_are_single_jumps() -> void:
	var host := _build()
	var tops := LevelSanity.top_segments(host)
	for chain in _consts()["CHAINS"]:
		for i in range(1, chain.size()):
			var a := LevelSanity.standing_on(tops, chain[i - 1])
			var b := LevelSanity.standing_on(tops, chain[i])
			ok(a != null and b != null, "authored points stand on actual platforms")
			if a != null and b != null:
				ok(LevelSanity._can_hop(a, b), "edge-to-edge jump %s -> %s" % [a.owner_name, b.owner_name])


func test_chains_land_on_authored_platforms() -> void:
	var host := _build()
	var rects := _solids(host)
	for chain in _consts()["CHAINS"]:
		for p in chain:
			ok(_standing_on(rects, p as Vector2), "chain point %s stands on a platform" % [p])


func test_terrain_is_graveyard_ground_with_two_pits() -> void:
	var host := _build()
	var consts := _consts()
	var limit := float(consts["EAST"])
	for f in consts["FLOORS"]:
		var plat := _plat(host, String(f[0]))
		ok(plat != null, "%s exists" % f[0])
		if plat == null:
			continue
		eq(plat.position, Vector2(float(f[1]), 320.0), "%s top sits on the floor line" % f[0])
		almost(plat.size.x, float(f[2]) - float(f[1]), 0.01, "%s spans its strip" % f[0])
		eq(plat.skin, "ground", "%s wears grass-topped earth" % f[0])
	for p in consts["PITS"]:
		var bed := _plat(host, String(p[0]) + "Bed")
		var pool := host.get_node_or_null("Props/%sPool" % p[0]) as ToxinPool
		ok(bed != null and pool != null, "%s has a bed and a pool" % p[0])
		if bed == null or pool == null:
			continue
		almost(bed.position.y, 352.0, 0.01, "%s bed is one hop (32) below the floor" % p[0])
		almost(pool.position.y, 336.0, 0.01, "%s liquid sits below the grass lips" % p[0])
		almost(pool.surface_rect().size.x, float(p[2]) - float(p[1]), 0.01, "%s liquid fills the pit" % p[0])
		eq(bed.skin, "ground", "%s bed is dug into the same earth" % p[0])
	for m in consts["MOUNDS"]:
		var mound := _plat(host, String(m[0]))
		ok(mound != null, "%s exists" % m[0])
		if mound == null:
			continue
		eq(mound.position, m[1] as Vector2)
		eq(mound.size, m[2] as Vector2)
		eq(mound.skin, "ground", "%s is an earth mound" % m[0])
		# One row buried into the surface below: 32 rise + 16 sunk = 48 thick.
		almost(mound.size.y, 48.0, 0.01, "%s is one tile thicker than its 32px rise" % m[0])
	var t1 := _plat(host, "TerraceE1")
	var t2 := _plat(host, "TerraceE2")
	if t1 != null and t2 != null:
		almost(t1.position.y - t2.position.y, 32.0, 0.01, "second terrace rises one hop above the first")
		ok(t2.position.x > t1.position.x and _right(t2) < _right(t1), "second terrace sits within the first")
		almost(_bottom(t2), t1.position.y + 16.0, 0.01, "second terrace sinks one row into the first")
	for s in consts["STONES"]:
		var stone := _plat(host, String(s[0]))
		ok(stone != null, "%s exists" % s[0])
		if stone == null:
			continue
		eq(stone.skin, "floating", "%s is a hovering church slab" % s[0])
		almost(stone.size.y, 16.0, 0.01, "%s is a thin step" % s[0])
		almost(stone.size.x, float(s[2]), 0.01)
	var wall_r := _plat(host, "WallRight")
	var wall_l := _plat(host, "WallLeft")
	ok(wall_l != null and wall_r != null, "walls close both ends")
	if wall_r != null:
		almost(wall_r.position.x, limit, 0.01, "east wall stands at the camera limit")
	ok(_plat(host, "Ceiling") == null and _plat(host, "CeilingWest") == null, "open sky: no ceiling")
	for r in _solids(host):
		ok(r.position.x >= -16.01 and r.end.x <= limit + 16.01, "%s lies within the level" % [r])


func test_plate_on_the_mound_opens_the_mausoleum_door() -> void:
	var host := _build()
	var rects := _solids(host)
	var consts := _consts()
	var plate := host.get_node_or_null("Props/MausoleumPlate") as PressurePlate
	var door := host.get_node_or_null("Props/MausoleumDoor") as ArenaDoor
	ok(plate != null and door != null, "plate and door exist")
	if plate == null or door == null:
		return
	ok(plate.activated.is_connected(door.open_door), "plate opens the door")
	var plate_feet: Vector2 = consts["PLATE_FEET"]
	ok(_standing_on(rects, plate.position + Vector2(12, 8), 4.0), "plate rests on the mound top")
	var mound := _plat(host, "MoundD")
	ok(mound != null and plate_feet.x > mound.position.x and plate_feet.x < _right(mound)
			and is_equal_approx(plate_feet.y, mound.position.y), "plate stands on MoundD")
	almost(320.0 - plate_feet.y, 32.0, 0.01, "the plate mound is a single hop up")
	ok(_standing_on(rects, door.position + Vector2(0, 64)), "door foot meets the floor")
	ok(door.position.x > plate_feet.x, "the door stands east of the plate, on the way forward")
	almost(door.position.y, 256.0, 0.01, "door is 64 tall and grounded")


func test_props_checkpoints_and_exit_are_placed() -> void:
	var host := _build()
	var rects := _solids(host)
	var consts := _consts()
	var props := host.get_node("Props")
	var nest_a := props.get_node_or_null("EmberNestStart") as EmberNest
	var nest_b := props.get_node_or_null("EmberNestGrove") as EmberNest
	ok(nest_a != null and nest_b != null, "two checkpoints")
	if nest_a != null and nest_b != null:
		ok(_standing_on(rects, nest_a.position + Vector2(6, 14)), "start nest stands on FloorA")
		ok(_standing_on(rects, nest_b.position + Vector2(6, 14)), "grove nest stands on FloorD")
		var long_pit: Array = consts["PITS"][1]
		ok(nest_b.position.x < float(long_pit[1]), "grove checkpoint comes before the long toxin ditch")
	for stele_name in ["SteleHallen", "SteleVeil"]:
		var stele := props.get_node_or_null(stele_name) as LoreStele
		ok(stele != null, "%s exists" % stele_name)
		if stele != null:
			ok(_standing_on(rects, stele.position), "%s stands on the ground" % stele_name)
			ok(String(stele.lore_title).begins_with("墓志"), "%s is an epitaph" % stele_name)
			ok(String(stele.lore_text) != "", "%s says something" % stele_name)
	var exit := props.get_node_or_null("Exit") as LevelExit
	ok(exit != null, "the bell door ends the level")
	if exit != null:
		eq(exit.target_scene, GameContext.LEVELS["level07"], "bell door hops to level07")
		eq(exit.flag_id, "level06_done")
		eq(exit.door_label, "钟楼门")
		ok(_standing_on(rects, exit.position), "exit door stands on FloorH")
		ok(float(consts["EAST"]) - exit.position.x >= 80.0, "exit keeps clear of the east wall")
	var pickup := host.get_node_or_null("Pickups/EmberCoreTreeTop") as CorePickup
	var anchor := host.get_node_or_null("Hooks/HookTreeTop") as HookAnchor
	var stone := _plat(host, "TreeTopStone")
	ok(pickup != null and anchor != null and stone != null, "tree-top core, hook and stone exist")
	if pickup != null and anchor != null and stone != null:
		ok(pickup.position.x > stone.position.x and pickup.position.x < _right(stone), "core hangs over the stone")
		var hover := stone.position.y - pickup.position.y
		ok(hover > 0.0 and hover <= 64.0, "core hovers %.0f <= 64 above the stone" % hover)
		ok(anchor.position.y < pickup.position.y and anchor.position.distance_to(pickup.position) <= 96.0,
				"hook anchor hangs right above the core")
		ok(320.0 - stone.position.y > JUMP_RISE_MAX, "the tree-top stone needs the hook, not a plain jump")
		ok(320.0 - anchor.position.y <= 250.0, "anchor is within hookshot reach of the ground")
		ok(stone.position.y - anchor.position.y <= 110.0, "landing stone is under the anchor")
	for w in consts["WAYMARKS"]:
		var sign := host.get_node_or_null("Waymarks/Sign_%s" % w[1]) as Node2D
		ok(sign != null, "sign %s exists" % w[1])
		if sign != null:
			ok(_standing_on(rects, sign.position), "sign %s stands on the ground" % w[1])
			eq(String(w[1]).length(), 2, "sign %s is two characters" % w[1])


func test_enemies_stand_where_they_are_placed() -> void:
	var host := _build()
	var rects := _solids(host)
	var enemies := host.get_node("Enemies")
	var kinds := {}
	for e in _consts()["ENEMIES"]:
		var kind := String(e[1])
		var available := ResourceLoader.exists(ChapterLayout.ENEMY_SCENES[kind])
		var enemy := enemies.get_node_or_null(String(e[0])) as Node2D
		if not available:
			# 骸骨还在制作中：被 enemy() 跳过，但脚点必须已经踩在台面上，等它来了就能站。
			ok(enemy == null, "%s is skipped while its scene is missing" % e[0])
			ok(_standing_on(rects, e[2] as Vector2), "%s has ground waiting at %s" % [e[0], e[2]])
			continue
		ok(enemy != null, "%s spawned" % e[0])
		if enemy == null:
			continue
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		eq(enemy.position, e[2] as Vector2, "%s stands where authored" % e[0])
		if enemy is GhostEnemy:
			ok(not _standing_on(rects, enemy.position, 8.0), "%s floats free of the floor" % e[0])
			ok(not LevelSanity.inside_solid(rects, enemy.position), "%s is not buried" % e[0])
		else:
			ok(_standing_on(rects, enemy.position, 4.0), "%s stands on a platform" % e[0])
	eq(int(kinds.get("ghost", 0)), 2, "two ghosts haunt the graveyard")
	eq(int(kinds.get("spitter", 0)), 1, "one spitter on the tomb terrace")
	eq(int(kinds.get("scrapper", 0)), 1, "one scrapper below it")
	var spitter := enemies.get_node_or_null("Spitter1") as Node2D
	var terrace := _plat(host, "TerraceE2")
	if spitter != null and terrace != null:
		ok(spitter.position.x > terrace.position.x and spitter.position.x < _right(terrace)
				and is_equal_approx(spitter.position.y, terrace.position.y), "spitter holds the upper terrace")
	var scrapper := enemies.get_node_or_null("Scrapper1") as Node2D
	var t1 := _plat(host, "TerraceE1")
	if scrapper != null and t1 != null:
		ok(scrapper.position.y > t1.position.y and scrapper.position.x < t1.position.x, "scrapper patrols the ground west of the terrace")
	var ghost2 := enemies.get_node_or_null("Ghost2") as Node2D
	var door := host.get_node_or_null("Props/MausoleumDoor") as Node2D
	if ghost2 != null and door != null:
		ok(ghost2.position.x > door.position.x, "second ghost waits behind the mausoleum door")


func test_level_passes_sanity_and_goals_are_reachable() -> void:
	var host := _build()
	var level := (load(LAYOUT_PATH) as GDScript).new() as ChapterLayout
	var spawn: Vector2 = level.entry_spawn()
	level.free()
	var problems := LevelSanity.check(host)
	for p in problems:
		ok(false, p)
	ok(problems.is_empty(), "LevelSanity clean on a bare host (%d problems)" % problems.size())
	var props := host.get_node("Props")
	for nest_name in ["EmberNestStart", "EmberNestGrove"]:
		var nest := props.get_node_or_null(nest_name)
		ok(nest != null and LevelSanity.is_reachable(host, spawn, LevelSanity.feet_of(nest)), "%s reachable from spawn" % nest_name)
	var exit := props.get_node_or_null("Exit")
	ok(exit != null and LevelSanity.is_reachable(host, spawn, LevelSanity.feet_of(exit)), "bell door reachable from spawn")
	# 主路线不靠钩锁：拿掉锚点后仍然走得通。
	for hook in host.get_node("Hooks").get_children():
		hook.free()
	ok(exit != null and LevelSanity.is_reachable(host, spawn, LevelSanity.feet_of(exit)), "bell door reachable without the hookshot")


func test_backdrop_is_the_open_graveyard_night() -> void:
	var host := _build()
	var level := (load(LAYOUT_PATH) as GDScript).new() as ChapterLayout
	eq(level.theme(), "graveyard")
	ok(not level.indoors(), "graveyard is outdoors: rain and wind allowed")
	eq(level.level_id(), "level06")
	eq(level.title(), "锈墓・陆 — 墓园夜雨")
	ok(level.wake_line() != "", "an opening line")
	eq(level.east_limit(), 2880)
	level.free()
	var backdrop := host.get_node_or_null("ParallaxBackdrop") as CanvasLayer
	ok(backdrop != null, "Level01's sky stack")
	if backdrop != null:
		for plate_name in ["Far", "Mid", "Hills"]:
			ok(backdrop.get_node_or_null(plate_name) is Parallax2D, "%s sky plate" % plate_name)
	ok(host.get_node_or_null("ParallaxForeground") != null, "foreground silhouette strip")
	ok(host.get_node_or_null("IndoorZone") == null, "no indoor atmosphere zone")
	var decor := host.get_node_or_null("Decor")
	ok(decor != null)
	if decor != null:
		var grounded := 0
		var torches := 0
		for child in decor.get_children():
			if child.is_in_group("grounded"):
				grounded += 1
			if child is TorchLight:
				torches += 1
		ok(grounded >= 18, "graveyard dressing is dense (%d grounded pieces)" % grounded)
		eq(torches, 4, "torch plates flank the mausoleum gate and the bell door")
