extends TestCase
## Level06 "墓园夜雨": dual-route central mausoleum (elevated foggy outer roof vs sunken
## dark inner crypt), rust mud mires (`force_zone` mud) with stepping stones, grave-cluster
## skeletons with alert/lose ranges and an exploder skeleton in the crypt, 5 checkpoints
## spaced <= ~1000px, tree-top hookshot branch with core + stele + reward, and exit to level07.

const LAYOUT_PATH := "res://scripts/levels/chapters/level06_layout.gd"
const JUMP_RISE_MAX := 32.0
const JUMP_GAP_MAX := 72.0


func setup() -> void:
	SaveData.flags.clear()
	Director._set_lock(false)


func teardown() -> void:
	SaveData.flags.clear()
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	Director._set_lock(false)


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


func test_terrain_breaks_single_line_with_dual_mausoleum_and_mud_mires() -> void:
	var host := _build()
	var consts := _consts()
	var limit := float(consts["EAST"])
	for f in consts["FLOORS"]:
		var plat := _plat(host, String(f[0]))
		ok(plat != null, "%s exists" % f[0])
		if plat == null:
			continue
		eq(plat.position, Vector2(float(f[1]), float(f[5])), "%s top sits at authored y" % f[0])
		almost(plat.size.x, float(f[2]) - float(f[1]), 0.01, "%s spans its strip" % f[0])
		eq(plat.skin, "ground", "%s wears grass-topped earth" % f[0])
	for m in consts["MOUNDS"]:
		var mound := _plat(host, String(m[0]))
		ok(mound != null, "%s exists" % m[0])
		if mound == null:
			continue
		eq(mound.position, m[1] as Vector2)
		eq(mound.size, m[2] as Vector2)
		eq(mound.skin, "ground", "%s is an earth mound" % m[0])
		almost(mound.size.y, 48.0, 0.01, "%s is one tile thicker than its 32px rise" % m[0])
	var t1 := _plat(host, "TerraceJ1")
	var t2 := _plat(host, "TerraceJ2")
	if t1 != null and t2 != null:
		almost(t1.position.y - t2.position.y, 32.0, 0.01, "second terrace rises one hop above the first")
		ok(t2.position.x > t1.position.x and _right(t2) < _right(t1), "second terrace sits within the first")
		almost(_bottom(t2), t1.position.y + 16.0, 0.01, "second terrace sinks one row into the first")
	for s in consts["STONES"]:
		var stone := _plat(host, String(s[0]))
		ok(stone != null, "%s exists" % s[0])
		if stone == null:
			continue
		eq(stone.skin, "floating", "%s is a hovering slab" % s[0])
		almost(stone.size.y, 16.0, 0.01, "%s is a thin step" % s[0])
		almost(stone.size.x, float(s[2]), 0.01)
	# Rust mud mires: 4 force zones with drag ~0.4 and toxin_per_second 12..16.
	var mud_zones: Array = consts["MUD_ZONES"]
	eq(mud_zones.size(), 4, "four rust mud mires replace generic poison pits")
	for z in mud_zones:
		var node := host.get_node_or_null("Props/" + String(z[0])) as ForceZone
		ok(node != null, "%s mud zone exists" % z[0])
		if node == null:
			continue
		eq(node.skin, "mud")
		eq(node.zone_rect(), z[1] as Rect2)
		almost(node.drag, float(z[2]), 0.01)
		ok(node.toxin_per_second >= 12.0 and node.toxin_per_second <= 16.0,
				"%s toxin_per_second in 12..16 (%.1f)" % [z[0], node.toxin_per_second])
	# First mud mire has >= 48px safe flat landing before and after.
	var intro := host.get_node_or_null("Props/MudIntro") as ForceZone
	var floor_a := _plat(host, "FloorA")
	if intro != null and floor_a != null:
		var r := intro.zone_rect()
		ok(r.position.x - floor_a.position.x >= 48.0, "safe flat ground before MudIntro")
		ok(_right(floor_a) - r.end.x >= 48.0, "safe flat ground after MudIntro")
	var wall_r := _plat(host, "WallRight")
	var wall_l := _plat(host, "WallLeft")
	ok(wall_l != null and wall_r != null, "walls close both ends")
	if wall_r != null:
		almost(wall_r.position.x, limit, 0.01, "east wall stands at the camera limit")
	ok(_plat(host, "Ceiling") == null and _plat(host, "CeilingWest") == null, "open sky: no ceiling")
	for r in _solids(host):
		ok(r.position.x >= -16.01 and r.end.x <= limit + 16.01, "%s lies within the level" % [r])


func test_plate_on_the_mound_opens_the_mausoleum_and_crypt_shortcut() -> void:
	var host := _build()
	var rects := _solids(host)
	var consts := _consts()
	var plate := host.get_node_or_null("Props/MausoleumPlate") as PressurePlate
	var door := host.get_node_or_null("Props/MausoleumDoor") as ArenaDoor
	ok(plate != null and door != null, "mausoleum plate and door exist")
	if plate != null and door != null:
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
	var short_plate := host.get_node_or_null("Props/CryptShortcutPlate") as PressurePlate
	var short_door := host.get_node_or_null("Props/CryptShortcutDoor") as ArenaDoor
	ok(short_plate != null and short_door != null, "crypt shortcut plate and door exist")
	if short_plate != null and short_door != null:
		ok(short_plate.activated.is_connected(short_door.open_door), "shortcut plate opens shortcut door")
		ok(_standing_on(rects, short_plate.position + Vector2(12, 8), 4.0), "shortcut plate stands on FloorD")
		ok(_standing_on(rects, short_door.position + Vector2(0, 64)), "shortcut door stands on FloorD")


func test_props_checkpoints_reward_and_exit_are_placed() -> void:
	var host := _build()
	var rects := _solids(host)
	var consts := _consts()
	var props := host.get_node("Props")
	var nest_names := ["EmberNestStart", "EmberNestCrypt", "EmberNestGrove", "EmberNestMire", "EmberNestEast"]
	var xs: Array[float] = []
	for n_name in nest_names:
		var n := props.get_node_or_null(n_name) as EmberNest
		ok(n != null, "%s exists" % n_name)
		if n != null:
			ok(_standing_on(rects, n.position + Vector2(6, 14)), "%s stands on solid ground" % n_name)
			xs.append(n.position.x)
	xs.sort()
	for i in range(1, xs.size()):
		ok(xs[i] - xs[i - 1] <= 1020.0, "checkpoint spacing %.0f..%.0f stays around <=1000px" % [xs[i - 1], xs[i]])
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
		ok(_standing_on(rects, exit.position), "exit door stands on FloorJ")
		ok(float(consts["EAST"]) - exit.position.x >= 80.0, "exit keeps clear of the east wall")
	var pickup := host.get_node_or_null("Pickups/EmberCoreTreeTop") as CorePickup
	var anchor := host.get_node_or_null("Hooks/HookTreeTop") as HookAnchor
	var stone := _plat(host, "TreeTopStone")
	var rew := props.get_node_or_null("RewardTreeTop") as EquipmentPickup
	ok(pickup != null and anchor != null and stone != null and rew != null,
			"tree-top core, hook, stone and optional challenge reward exist")
	if pickup != null and anchor != null and stone != null and rew != null:
		ok(pickup.position.x > stone.position.x and pickup.position.x < _right(stone), "core hangs over the stone")
		var hover := stone.position.y - pickup.position.y
		ok(hover > 0.0 and hover <= 64.0, "core hovers %.0f <= 64 above the stone" % hover)
		ok(anchor.position.y < pickup.position.y and anchor.position.distance_to(pickup.position) <= 96.0,
				"hook anchor hangs right above the core")
		ok(320.0 - stone.position.y > JUMP_RISE_MAX, "the tree-top stone needs the hook, not a plain jump")
		ok(320.0 - anchor.position.y <= 250.0, "anchor is within hookshot reach of the ground")
		ok(stone.position.y - anchor.position.y <= 110.0, "landing stone is under the anchor")
		ok(_standing_on(rects, LevelSanity.feet_of(rew)), "reward rests on TreeTopStone")
		eq(rew.reward_ref, "toxic_ward")
	for w in consts["WAYMARKS"]:
		var sign := host.get_node_or_null("Waymarks/Sign_%s" % w[1]) as Node2D
		ok(sign != null, "sign %s exists" % w[1])
		if sign != null:
			ok(_standing_on(rects, sign.position), "sign %s stands on the ground" % w[1])
			eq(String(w[1]).length(), 2, "sign %s is two characters" % w[1])


func test_enemies_stand_in_grave_clusters_with_alerts_and_variants() -> void:
	var host := _build()
	var rects := _solids(host)
	var enemies := host.get_node("Enemies")
	var kinds := {}
	var alerted_skeletons := 0
	var exploders := 0
	for e in _consts()["ENEMIES"]:
		var kind := String(e[1])
		var enemy := enemies.get_node_or_null(String(e[0])) as Node2D
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
		if enemy is SkeletonEnemy:
			var sk := enemy as SkeletonEnemy
			if sk.alert_radius >= 150.0 and sk.lose_range >= 240.0:
				alerted_skeletons += 1
			if sk.get_meta("variant", &"") == &"exploder_skeleton":
				exploders += 1
	ok(int(kinds.get("skeleton", 0)) >= 7, "graveyard packs buried skeletons (%d)" % int(kinds.get("skeleton", 0)))
	eq(int(kinds.get("ghost", 0)), 3, "three ghosts haunt the graveyard")
	eq(int(kinds.get("spitter", 0)), 1, "one spitter on the mausoleum roof peak")
	eq(int(kinds.get("scrapper", 0)), 2, "two scrappers on the grave-road")
	ok(alerted_skeletons >= 7, "skeletons wake nearby peers and lose target when far (%d)" % alerted_skeletons)
	eq(exploders, 1, "one exploder_skeleton in the narrow crypt corridor")
	var spitter := enemies.get_node_or_null("Spitter1") as Node2D
	var roof_top := _plat(host, "MausoleumRoofTop")
	if spitter != null and roof_top != null:
		ok(spitter.position.x > roof_top.position.x and spitter.position.x < _right(roof_top)
				and is_equal_approx(spitter.position.y, roof_top.position.y), "spitter holds the mausoleum roof peak")


func test_level_passes_sanity_and_both_mausoleum_routes_reach_exit() -> void:
	var host := _build()
	var level := (load(LAYOUT_PATH) as GDScript).new() as ChapterLayout
	var spawn: Vector2 = level.entry_spawn()
	level.free()
	var problems := LevelSanity.check(host)
	for p in problems:
		ok(false, p)
	ok(problems.is_empty(), "LevelSanity clean on a bare host (%d problems)" % problems.size())
	var props := host.get_node("Props")
	for nest_name in ["EmberNestStart", "EmberNestCrypt", "EmberNestGrove", "EmberNestMire", "EmberNestEast"]:
		var nest := props.get_node_or_null(nest_name)
		ok(nest != null and LevelSanity.is_reachable(host, spawn, LevelSanity.feet_of(nest), false),
				"%s reachable from spawn without hook" % nest_name)
	var exit := props.get_node_or_null("Exit")
	ok(exit != null and LevelSanity.is_reachable(host, spawn, LevelSanity.feet_of(exit), false),
			"bell door reachable from spawn without hook")
	# Both the Outer Roof route (y=192) and Inner Crypt route (y=352) are reachable without hook
	# and can reach the exit from their midpoints.
	ok(LevelSanity.is_reachable(host, spawn, Vector2(1500, 192), false), "outer mausoleum roof reachable")
	ok(LevelSanity.is_reachable(host, Vector2(1500, 192), LevelSanity.feet_of(exit), false),
			"outer mausoleum roof reaches the exit")
	ok(LevelSanity.is_reachable(host, spawn, Vector2(1500, 352), false), "inner mausoleum crypt reachable")
	ok(LevelSanity.is_reachable(host, Vector2(1500, 352), LevelSanity.feet_of(exit), false),
			"inner mausoleum crypt reaches the exit")


func test_backdrop_is_the_open_graveyard_night() -> void:
	var host := _build()
	var level := (load(LAYOUT_PATH) as GDScript).new() as ChapterLayout
	eq(level.theme(), "graveyard")
	ok(not level.indoors(), "graveyard is outdoors: rain and wind allowed")
	eq(level.level_id(), "level06")
	eq(level.title(), "锈墓・捌 — 墓园夜雨")
	ok(level.wake_line() != "", "an opening line")
	eq(level.east_limit(), 4000)
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
		eq(torches, 0, "open graveyard has no indoor torch wall plates")


func test_visibility_pockets_and_tree_branch() -> void:
	var layout := (load(LAYOUT_PATH) as GDScript).new() as ChapterLayout
	var regions := layout.weather_regions()
	ok(regions.size() >= 4, "visibility pockets cover graves, roof, crypt and squall")
	var fog: Dictionary = {}
	var roof_fog: Dictionary = {}
	var squall: Dictionary = {}
	var east_fog: Dictionary = {}
	for spec in regions:
		var s: Dictionary = spec
		match String(s.get("name", "")):
			"GraveFog": fog = s
			"RoofFog": roof_fog = s
			"DitchSquall": squall = s
			"EastGraveFog": east_fog = s
	ok(not fog.is_empty() and not roof_fog.is_empty() and not squall.is_empty() and not east_fog.is_empty(),
			"all local weather pockets are named")
	if not east_fog.is_empty():
		var east_rect: Rect2 = east_fog["rect"]
		eq(int(east_fog["weather"]), WorldClock.Weather.FOG, "the east graves sit under fog")
		ok(east_rect.position.x <= 2880.0 and east_rect.end.x >= 4000.0, "east fog covers the widened stretch")
	if not fog.is_empty():
		var fog_rect: Rect2 = fog["rect"]
		eq(int(fog["weather"]), WorldClock.Weather.FOG, "the graves sit under fog")
		almost(float(fog["intensity"]), 1.0, 0.01, "the fog pocket is thick")
		ok(float(fog["wind_scale"]) < 1.0, "the fog pocket is still air")
		ok(fog_rect.position.x <= 448.0 and fog_rect.end.x >= 832.0, "fog covers the west mound stretch")
	if not squall.is_empty():
		var squall_rect: Rect2 = squall["rect"]
		eq(int(squall["weather"]), WorldClock.Weather.RUST_RAIN, "the long ditch is under rust rain")
		almost(float(squall["intensity"]), 1.0, 0.01, "the squall is at full strength")
		ok(float(squall["wind_scale"]) > 1.0, "the squall is windier than the rest of the graveyard")
		ok(squall_rect.position.x <= 2304.0 and squall_rect.end.x >= 2608.0, "the squall covers the long ditch")
	layout.free()
	var host := _build()
	var stele := host.get_node_or_null("Props/SteleTree") as LoreStele
	var rew := host.get_node_or_null("Props/RewardTreeTop") as EquipmentPickup
	ok(stele != null and rew != null, "the tree branch carries a stele and a reward")
	if stele != null and rew != null:
		ok(String(stele.lore_title).begins_with("墓志"), "tree stele is an epitaph")
		ok(_standing_on(_solids(host), LevelSanity.feet_of(stele)), "tree stele stands on the tree-top stone")
		var feet := LevelSanity.feet_of(stele)
		ok(not LevelSanity.is_reachable(host, Vector2(96, 300), feet, false),
				"the main route cannot read the tree stele")
		ok(LevelSanity.is_reachable(host, Vector2(96, 300), feet, true),
				"the hookshot reaches the tree stele")
		var rew_feet := LevelSanity.feet_of(rew)
		ok(not LevelSanity.is_reachable(host, Vector2(96, 300), rew_feet, false),
				"the main route cannot reach the tree reward")
		ok(LevelSanity.is_reachable(host, Vector2(96, 300), rew_feet, true),
				"the hookshot reaches the tree reward")
	var skeleton := host.get_node_or_null("Enemies/Skeleton5") as SkeletonEnemy
	ok(skeleton != null, "the fog pocket has its buried skeleton")
	if skeleton != null:
		var fog_center := Rect2(448, 0, 480, 324)
		ok(fog_center.has_point(skeleton.position), "it rises inside the fog pocket")
		ok(_standing_on(_solids(host), skeleton.position, 4.0), "it has ground under its feet")
