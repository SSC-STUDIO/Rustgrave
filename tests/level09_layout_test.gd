extends TestCase
## Level09 "锈城城墙": every drain is bridged by single-jump floating stones,
## towers climb in 32px steps, the plate on tower two opens the walkway gate,
## enemies stand (or hover) where they were placed, and the furnace door
## hands the knight to level10.

const LAYOUT := preload("res://scripts/levels/chapters/level09_layout.gd")
const JUMP_RISE_MAX := 32.0
const JUMP_GAP_MAX := 72.0
const WIND_GAP_MAX := 64.0
const FLOOR_Y := 320.0


func setup() -> void:
	SaveData.flags.clear()


func teardown() -> void:
	SaveData.flags.clear()
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)


func _host() -> Node2D:
	var host := Node2D.new()
	host.name = "Level09_Ramparts"
	host.scene_file_path = GameContext.LEVELS["level09"]
	host.add_to_group("game_world")
	add_child(host)
	return host


func _build() -> Node2D:
	var host := _host()
	var level := LAYOUT.new()
	add_child(level)
	level.build(host)
	return host


func _rect_of(host: Node2D, plat_name: String) -> Rect2:
	var plat := host.get_node_or_null("Platforms/" + plat_name) as SolidPlatform
	ok(plat != null, "%s exists" % plat_name)
	if plat == null:
		return Rect2()
	return Rect2(plat.position, plat.size)


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


func _inside_any(rects: Array[Rect2], point: Vector2) -> bool:
	for r in rects:
		if r.grow(-1.0).has_point(point):
			return true
	return false


## Walk a chain of platform names left to right; every hop must be a single
## jump (rise <= 32) across at most `gap_max` px of air.
func _assert_chain(host: Node2D, chain: Array, gap_max: float) -> void:
	for i in range(1, chain.size()):
		var a := _rect_of(host, String(chain[i - 1]))
		var b := _rect_of(host, String(chain[i]))
		if not a.has_area() or not b.has_area():
			continue
		var rise := a.position.y - b.position.y
		var gap := maxf(0.0, b.position.x - a.end.x)
		ok(rise <= JUMP_RISE_MAX + 0.01, "%s -> %s rises %.0f <= 32" % [chain[i - 1], chain[i], rise])
		ok(gap <= gap_max + 0.01, "%s -> %s spans %.0f <= %.0f" % [chain[i - 1], chain[i], gap, gap_max])
		ok(b.position.x >= a.position.x, "%s lies east of %s" % [chain[i], chain[i - 1]])


func test_drain_crossings_are_single_jumps() -> void:
	var host := _build()
	_assert_chain(host, ["FloorA", "StoneA1", "StoneA2", "StoneA3", "FloorB"], JUMP_GAP_MAX)
	_assert_chain(host, ["FloorB", "StoneB1", "StoneB2", "StoneB3", "FloorC"], JUMP_GAP_MAX)
	# The wind gap is a run of short stones: tighter spacing, never wider than 64.
	_assert_chain(host, ["FloorC", "WindS1", "WindS2", "WindS3", "WindS4", "WindS5", "FloorD"], WIND_GAP_MAX)
	# ⑧ 第四口排水沟：两块浮石。
	_assert_chain(host, ["FloorD", "StoneD1", "StoneD2", "FloorE"], JUMP_GAP_MAX)
	for stone_name in ["WindS1", "WindS2", "WindS3", "WindS4", "WindS5"]:
		var r := _rect_of(host, stone_name)
		almost(r.size.x, 32.0, 0.01, "%s is a short stone" % stone_name)
	for s in LAYOUT.STONES:
		var stone := host.get_node_or_null("Platforms/" + String(s[0])) as SolidPlatform
		ok(stone != null and stone.skin == "rampart_float", "%s wears the rampart ledge skin" % s[0])
		if stone != null:
			almost(stone.size.y, 16.0, 0.01, "%s is a 16px slab" % s[0])


func test_towers_climb_in_32px_steps() -> void:
	var host := _build()
	_assert_chain(host, ["FloorB", "TowerAStep", "TowerA"], 0.0)
	_assert_chain(host, ["FloorC", "TowerBStep", "TowerB"], 0.0)
	_assert_chain(host, ["FloorD", "TowerCStep1", "TowerCStep2", "TowerC"], 0.0)
	_assert_chain(host, ["FloorE", "TowerDStep", "TowerDBase1", "TowerD"], 0.0)
	for t in LAYOUT.TOWERS:
		var block := host.get_node_or_null("Platforms/" + String(t[0])) as SolidPlatform
		ok(block != null, "%s exists" % t[0])
		if block == null:
			continue
		eq(block.skin, "rampart", "%s is rampart masonry" % t[0])
		ok(block.position.y + block.size.y <= FLOOR_Y + 0.01, "%s never sinks below the walkway" % t[0])
		ok(is_zero_approx(fmod(FLOOR_Y - block.position.y, 32.0)), "%s top is a multiple of 32 above the floor" % t[0])
		# Stacked tower blocks: every block either stands on the walkway or is
		# supported across its full width by the block directly beneath it.
		if block.position.y + block.size.y < FLOOR_Y - 0.01:
			var supported := false
			for other in LAYOUT.TOWERS:
				if other == t:
					continue
				var o_pos: Vector2 = other[1]
				var o_size: Vector2 = other[2]
				if absf(o_pos.y - (block.position.y + block.size.y)) <= 0.01 \
						and o_pos.x <= block.position.x + 0.01 \
						and o_pos.x + o_size.x >= block.position.x + block.size.x - 0.01:
					supported = true
			ok(supported, "%s rests on the block directly beneath it" % t[0])
	almost(_rect_of(host, "TowerA").position.y, 256.0, 0.01, "tower one is 64 high")
	almost(_rect_of(host, "TowerC").position.y, 224.0, 0.01, "tower three is 96 high")


func test_drains_lie_in_pits_with_climbable_lips() -> void:
	var host := _build()
	var props := host.get_node("Props")
	for p in LAYOUT.PITS:
		var pool := props.get_node_or_null(String(p[0]) + "Pool") as ToxinPool
		var bed := _rect_of(host, String(p[0]) + "Bed")
		ok(pool != null, "%s has a pool" % p[0])
		if pool == null or not bed.has_area():
			continue
		var surface := pool.surface_rect()
		almost(bed.position.y, 352.0, 0.01, "%s bed sits 32 below the walkway" % p[0])
		ok(surface.position.y < bed.position.y and surface.end.y > bed.position.y, "%s liquid laps the bed" % p[0])
		almost(surface.position.x, float(p[1]), 0.01)
		almost(surface.end.x, float(p[2]), 0.01)
		# A knight who falls in walks out either side with one 32px hop.
		var rects := _solids(host)
		ok(_standing_on(rects, Vector2(float(p[1]) - 1.0, FLOOR_Y)), "%s west lip is walkway" % p[0])
		ok(_standing_on(rects, Vector2(float(p[2]) + 1.0, FLOOR_Y)), "%s east lip is walkway" % p[0])
		ok(bed.position.y - FLOOR_Y <= JUMP_RISE_MAX, "%s lip is one hop up" % p[0])


func test_plate_on_tower_two_opens_the_walkway_gate() -> void:
	var host := _build()
	var props := host.get_node("Props")
	var rects := _solids(host)
	var plate := props.get_node_or_null("WallGatePlate") as PressurePlate
	var door := props.get_node_or_null("WallGateDoor") as ArenaDoor
	ok(plate != null and door != null, "plate and gate exist")
	if plate == null or door == null:
		return
	ok(plate.activated.is_connected(door.open_door), "plate opens the gate")
	var tower := _rect_of(host, "TowerB")
	var plate_feet := plate.position + Vector2(12, 8)
	ok(_standing_on(rects, plate_feet, 4.0), "plate rests on tower two's top")
	ok(plate_feet.x > tower.position.x and plate_feet.x < tower.end.x, "plate is on tower two")
	almost(tower.position.y, 256.0, 0.01, "tower two top is one storey up")
	var door_feet := door.position + Vector2(8, 64)
	ok(_standing_on(rects, door_feet), "gate foot meets the walkway")
	almost(door.position.y, 256.0, 0.01, "gate stands on the ground line")
	ok(door.position.x >= tower.end.x + 32.0, "gate leaves a landing strip east of tower two")
	var floor_c := _rect_of(host, "FloorC")
	ok(door.position.x + 16.0 < floor_c.end.x, "gate seals the walkway before the wind gap")
	# Nothing but the tower lets you reach the plate from the west.
	var step := _rect_of(host, "TowerBStep")
	ok(step.end.x <= tower.position.x + 0.01 and step.position.y == 288.0, "west step leads up to the plate")


func test_props_checkpoints_and_exit_are_placed() -> void:
	var host := _build()
	var props := host.get_node("Props")
	var rects := _solids(host)
	for nest_name in ["EmberNestGate", "EmberNestMid", "EmberNestEast", "EmberNestRampart"]:
		var nest := props.get_node_or_null(nest_name) as EmberNest
		ok(nest != null, "%s exists" % nest_name)
		if nest != null:
			ok(_standing_on(rects, nest.position + Vector2(6, 14)), "%s stands on the walkway" % nest_name)
	var nest_east := props.get_node_or_null("EmberNestEast") as Node2D
	var tower_c := _rect_of(host, "TowerC")
	ok(nest_east != null and nest_east.position.x < tower_c.position.x, "a checkpoint precedes the last tower")
	for stele_name in ["SteleWall", "SteleWind"]:
		var stele := props.get_node_or_null(stele_name) as LoreStele
		ok(stele != null, "%s exists" % stele_name)
		if stele != null:
			ok(_standing_on(rects, stele.position), "%s stands on the walkway" % stele_name)
			ok(stele.lore_title.begins_with("城墙铭"), "%s is a rampart inscription" % stele_name)
	var exit := props.get_node_or_null("Exit") as LevelExit
	ok(exit != null, "the furnace door ends the level")
	if exit != null:
		eq(exit.target_scene, GameContext.LEVELS["level09b"], "furnace door leads to the emberwind cliffs")
		eq(exit.flag_id, "level09_done")
		eq(exit.door_label, "炉心门")
		eq(exit.spawn, ChapterLayout.entry_spawn_of("level09b"), "arrival point is the emberwind cliffs entry spawn")
		ok(_standing_on(rects, exit.position), "exit door stands on the arrow-tower floor")
		ok(exit.position.x + 24.0 <= float(LAYOUT.EAST_LIMIT) - 80.0, "exit keeps clear of the east wall")
	var hook := host.get_node_or_null("Hooks/HookTower") as HookAnchor
	var core := host.get_node_or_null("Pickups/EmberCore") as CorePickup
	ok(hook != null and core != null, "hook shortcut and ember core exist")
	if hook != null and core != null:
		var eyrie := _rect_of(host, "EyrieC")
		ok(core.position.x >= eyrie.position.x and core.position.x <= eyrie.end.x, "core hangs over the eyrie")
		var hover := eyrie.position.y - core.position.y
		ok(hover > 0.0 and hover <= 64.0, "core hovers %.0f px above the eyrie" % hover)
		ok(hook.position.distance_to(core.position) <= 96.0, "hook is within reach of the core")
		ok(hook.position.y < tower_c.position.y, "anchor hangs above tower three")
		ok(eyrie.position.y < tower_c.position.y - JUMP_RISE_MAX, "eyrie is out of plain jumping reach (optional shortcut)")
		var rust_core := core.get("core") as RustCore
		ok(rust_core != null and rust_core.id == &"ember_core", "the reward is the ember core")
	for w in LAYOUT.WAYMARKS:
		ok(host.get_node_or_null("Waymarks/Sign_%s" % w[1]) != null, "sign %s" % w[1])


func test_enemies_stand_where_they_are_placed() -> void:
	var host := _build()
	var rects := _solids(host)
	var enemies := host.get_node("Enemies")
	eq(enemies.get_child_count(), LAYOUT.ENEMIES.size(), "every enemy kind is available")
	var demons := 0
	var spitters := 0
	var scrappers := 0
	var ghosts := 0
	var pits: Array[Rect2] = []
	for p in LAYOUT.PITS:
		pits.append(Rect2(float(p[1]), 0.0, float(p[2]) - float(p[1]), FLOOR_Y))
	for e in LAYOUT.ENEMIES:
		var enemy := enemies.get_node_or_null(String(e[0])) as Node2D
		ok(enemy != null, "%s spawned" % e[0])
		if enemy == null:
			continue
		eq(enemy.position, e[2], "%s sits at its authored point" % e[0])
		if enemy is FlyingDemonEnemy:
			demons += 1
			ok(not _inside_any(rects, enemy.position), "%s hovers in open air" % e[0])
			var over_pit := false
			for pit in pits:
				if pit.has_point(enemy.position):
					over_pit = true
			ok(over_pit, "%s patrols above a drain" % e[0])
			almost(float(enemy.get("patrol_range")), 72.0, 0.01, "%s patrol range" % e[0])
		elif enemy is GhostEnemy:
			ghosts += 1
			ok(not _inside_any(rects, enemy.position), "%s floats free of the masonry" % e[0])
			ok(enemy.position.x > _rect_of(host, "TowerC").end.x, "%s haunts the landing behind the last tower" % e[0])
		elif enemy is SpitterEnemy:
			spitters += 1
			ok(_standing_on(rects, enemy.position, 4.0), "%s stands on a platform" % e[0])
			ok(enemy.position.y < FLOOR_Y, "%s perches on a tower top" % e[0])
		elif enemy is ScrapperEnemy:
			scrappers += 1
			ok(_standing_on(rects, enemy.position, 4.0), "%s stands on a platform" % e[0])
			almost(enemy.position.y, FLOOR_Y, 0.01, "%s patrols the walkway" % e[0])
			var reach := float(enemy.get("patrol_range"))
			ok(_standing_on(rects, Vector2(enemy.position.x - reach, FLOOR_Y))
					and _standing_on(rects, Vector2(enemy.position.x + reach, FLOOR_Y)),
					"%s's beat stays on one floor" % e[0])
	eq(demons, 4, "four flying demons")
	eq(spitters, 4, "four spitters")
	eq(scrappers, 2, "two scrappers")
	eq(ghosts, 2, "two ghosts")
	# Spitters never share a jump: each tower top is at least 380px (their
	# aggro range) from the previous crossing's last stone.
	var spitter_xs: Array[float] = []
	for child in enemies.get_children():
		if child is SpitterEnemy:
			spitter_xs.append((child as Node2D).position.x)
	spitter_xs.sort()
	ok(spitter_xs.size() == 4 and spitter_xs[1] - spitter_xs[0] > 380.0 and spitter_xs[2] - spitter_xs[1] > 380.0
			and spitter_xs[3] - spitter_xs[2] > 380.0,
			"spitters are spread out along the wall")


## ⑧ 墙顶箭楼（3200 → 4200）：第四口排水沟由两块浮石横渡，箭楼顶是可选支路，
## 上面有 1 个奖励位；箭楼前补一个余烬巢，出口在旧墙东端。
func test_arrow_tower_branch_and_rampart_checkpoint() -> void:
	var host := _build()
	eq(LAYOUT.EAST_LIMIT, 4200, "锈城城墙扩到 4200 宽")
	var rects := _solids(host)
	ok(_standing_on(rects, Vector2(3300, 320)), "FloorD continues the wall top")
	ok(_standing_on(rects, Vector2(4100, 320)), "FloorE reaches the new east wall")
	var tower_d := _rect_of(host, "TowerD")
	almost(tower_d.position.y, 224.0, 0.01, "the arrow tower is three storeys tall")
	var reward := host.get_node_or_null("Pickups/RewardEyrie") as EquipmentPickup
	ok(reward != null, "the arrow tower carries one reward slot")
	if reward != null:
		eq(reward.position, LAYOUT.REWARD_POS)
		eq(String(reward.get("reward_kind")), "equipment")
		ok(String(reward.get("reward_ref")) != "")
		ok(_standing_on(rects, LevelSanity.feet_of(reward)), "reward rests on the arrow tower top")
		ok(LevelSanity.is_reachable(host, LAYOUT.ENTRY_SPAWN, LevelSanity.feet_of(reward), false),
				"the arrow tower is a walkable side branch")
	var nest := host.get_node_or_null("Props/EmberNestRampart") as EmberNest
	ok(nest != null, "a new checkpoint waits before the arrow tower")
	if nest != null:
		ok(_standing_on(rects, nest.position + Vector2(6, 14)), "rampart nest stands on FloorD")
		ok(nest.position.x < LAYOUT.EXIT_X and LAYOUT.EXIT_X - nest.position.x <= 1400.0,
				"checkpoint spacing to the furnace door stays <= 1400px")
		ok(LevelSanity.is_reachable(host, LAYOUT.ENTRY_SPAWN, nest.position + Vector2(6, 14), false),
				"rampart nest is reachable on the main route")
	var exit := host.get_node_or_null("Props/Exit") as LevelExit
	ok(exit != null and _standing_on(rects, exit.position), "the furnace door stands on FloorE")


func test_layout_passes_sanity_on_a_bare_host() -> void:
	var host := _build()
	var limits := Rect2(0.0, -48.0, float(LAYOUT.EAST_LIMIT), 448.0)
	var problems := LevelSanity.check(host, limits)
	for p in problems:
		ok(false, p)
	ok(problems.is_empty(), "LevelSanity clean (%d problems)" % problems.size())
	var spawn: Vector2 = LAYOUT.ENTRY_SPAWN
	var exit := host.get_node("Props/Exit") as LevelExit
	ok(LevelSanity.is_reachable(host, spawn, exit.position), "exit reachable from spawn")
	for nest_name in ["EmberNestGate", "EmberNestMid", "EmberNestEast", "EmberNestRampart"]:
		var nest := host.get_node("Props/" + nest_name)
		ok(LevelSanity.is_reachable(host, spawn, LevelSanity.feet_of(nest)), "%s reachable from spawn" % nest_name)
	# The eyrie is a hook-only bonus: without the anchor it must be out of reach.
	var eyrie := host.get_node("Platforms/EyrieC") as SolidPlatform
	var hook := host.get_node("Hooks/HookTower")
	hook.get_parent().remove_child(hook)
	ok(not LevelSanity.is_reachable(host, spawn, eyrie.position + Vector2(32, 0)), "eyrie needs the hookshot")
	hook.free()


func test_backdrop_is_the_windy_outdoor_town() -> void:
	var host := _build()
	var level := LAYOUT.new()
	eq(level.level_id(), "level09")
	eq(level.title(), "锈墓・拾贰 — 锈城城墙")
	ok(level.wake_line() != "", "an opening line")
	eq(level.theme(), "ramparts")
	ok(not level.indoors(), "ramparts are open to the sky")
	eq(level.east_limit(), 4200)
	level.free()
	var backdrop := host.get_node_or_null("ParallaxBackdrop") as CanvasLayer
	ok(backdrop != null)
	if backdrop != null:
		ok(backdrop.get_node_or_null("Void") is ColorRect, "solid void behind everything")
		ok(backdrop.get_node_or_null("Layer0") is Parallax2D, "town sky layer")
		ok(backdrop.get_node_or_null("Layer3") is Parallax2D, "the town below the wall")
	ok(host.get_node_or_null("MoodTint") is CanvasModulate)
	ok(host.get_node_or_null("IndoorZone") == null, "no indoor zone on the wall top")
	ok(host.get_node_or_null("WindFx") != null, "wind blows across the ramparts")
	ok(host.get_node_or_null("WeatherFx") != null, "weather reaches the wall top")
	var platforms := host.get_node("Platforms")
	ok(platforms.get_node_or_null("Ceiling") == null, "no ceiling outdoors")
	var wall_r := platforms.get_node("WallRight") as SolidPlatform
	almost(wall_r.position.x, float(LAYOUT.EAST_LIMIT), 0.01, "east wall at the camera limit")
	for f in LAYOUT.FLOORS:
		var plat := platforms.get_node_or_null(String(f[0])) as SolidPlatform
		ok(plat != null, "%s exists" % f[0])
		if plat != null:
			eq(plat.skin, "rampart", "%s is wall-top walkway" % f[0])
			almost(plat.position.y, FLOOR_Y, 0.01)
	for child in platforms.get_children():
		if child is SolidPlatform:
			var r := Rect2(child.position, child.size)
			ok(r.position.x >= -16.0 and r.end.x <= float(LAYOUT.EAST_LIMIT) + 16.0, "%s within the camera bounds" % child.name)
	var decor := host.get_node_or_null("Decor")
	ok(decor != null and decor.get_child_count() >= LAYOUT.PROPS.size() + LAYOUT.BUSHES.size(),
			"balustrades, door arches, rubble and bushes were planted")


## 塔楼三旁的哨台（EyrieC）是本章支路：只有钩锁上得去，余烬核之外还有
## 一块城墙铭（世界信息），主路线（allow_hook=false）够不到它。
func test_eyrie_branch_carries_world_information() -> void:
	var host := _build()
	var stele := host.get_node_or_null("Props/SteleEyrie") as LoreStele
	ok(stele != null, "the eyrie carries a stele")
	if stele == null:
		return
	ok(String(stele.lore_title).begins_with("城墙铭"), "eyrie stele is a rampart inscription")
	ok(String(stele.lore_text) != "", "eyrie stele says something")
	var eyrie := _rect_of(host, "EyrieC")
	var feet := LevelSanity.feet_of(stele)
	ok(feet.x >= eyrie.position.x and feet.x <= eyrie.end.x, "stele stands within the eyrie ledge")
	ok(_standing_on(_solids(host), feet), "stele has masonry under its feet")
	ok(not LevelSanity.is_reachable(host, LAYOUT.ENTRY_SPAWN, feet, false),
			"the main route cannot read the eyrie stele")
	ok(LevelSanity.is_reachable(host, LAYOUT.ENTRY_SPAWN, feet, true),
			"the hookshot reaches the eyrie stele")
