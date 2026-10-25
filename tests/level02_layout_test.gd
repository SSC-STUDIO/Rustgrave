extends TestCase
## Level02 "沉钟地窟": authored geometry stays jumpable, props/enemies stand on
## solid ground, checkpoints and the exit exist, and the level is indoor-only.

const JUMP_RISE_MAX := 32.0
const CHECKPOINT_GAP_MAX := 1000.0


func setup() -> void:
	SaveData.flags.clear()


func teardown() -> void:
	SaveData.flags.clear()
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)


func _host() -> Node2D:
	var host := Node2D.new()
	host.name = "Level02_Undercroft"
	host.scene_file_path = GameContext.LEVEL02_PATH
	host.add_to_group("game_world")
	add_child(host)
	return host


func _build() -> Node2D:
	var host := _host()
	var level := Level02Layout.new()
	add_child(level)
	level.build(host)
	# 测试要直接驱动「空钟倒地」的接线，把布局实例挂在 host 上（Object 引用）。
	host.set_meta("layout", level)
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


func test_step_chains_are_single_jumps() -> void:
	var chains := [
		# pit B: floor A lip -> stones -> floor B
		[Vector2(448, 320), Vector2(496, 288), Vector2(576, 264), Vector2(656, 288), Vector2(720, 320)],
		# spitter ledge + ring 1 balcony: floor -> step -> ledge -> balcony
		[Vector2(880, 320), Vector2(880, 288), Vector2(944, 264)],
		[Vector2(1040, 264), Vector2(1048, 232)],
		# vault catwalk + shaft overlook: floor C -> step C1 -> catwalk
		[Vector2(1200, 320), Vector2(1200, 288), Vector2(1248, 256)],
		# pit C escape: pit floor -> lip -> floor
		[Vector2(1376, 384), Vector2(1376, 352), Vector2(1376, 320)],
		# sunken bell vault spiral: floor D -> step D1 -> gallery D; gallery D -> upper bridge D; upper bridge D -> step D2 -> step D3 -> floor E
		[Vector2(1908, 320), Vector2(1908, 288), Vector2(1976, 256)],
		[Vector2(2136, 256), Vector2(2144, 224)],
		[Vector2(2288, 224), Vector2(2296, 256), Vector2(2352, 288), Vector2(2432, 320)],
		# sunken floor direct climb out to floor E
		[Vector2(2432, 352), Vector2(2432, 320)],
		# alcove: lift D at its top -> hop left onto the alcove's right end
		[Vector2(1856, 224), Vector2(1840, 208)],
		# cage arena west & east belfry steps
		[Vector2(2760, 320), Vector2(2760, 288), Vector2(2840, 256)],
		[Vector2(3272, 320), Vector2(3272, 288), Vector2(3256, 256)],
	]
	for chain in chains:
		for i in range(1, chain.size()):
			var rise: float = (chain[i - 1] as Vector2).y - (chain[i] as Vector2).y
			ok(rise <= JUMP_RISE_MAX + 0.01, "step %s -> %s rises %.0f <= 32" % [chain[i - 1], chain[i], rise])
			var gap: float = absf((chain[i] as Vector2).x - (chain[i - 1] as Vector2).x)
			ok(gap <= 96.0, "horizontal reach %s -> %s is %.0f" % [chain[i - 1], chain[i], gap])


func test_terrain_matches_constants_and_seals_the_room() -> void:
	var host := _build()
	var rects := _solids(host)
	ok(rects.size() >= Level02Layout.FLOORS.size() + Level02Layout.STEPS.size() + 4, "floors, steps, walls, ceiling")
	var platforms := host.get_node("Platforms")
	for f in Level02Layout.FLOORS:
		var plat := platforms.get_node_or_null(String(f[0])) as SolidPlatform
		ok(plat != null, "%s exists" % f[0])
		if plat != null:
			eq(plat.position, f[1])
			eq(plat.size, f[2])
			eq(plat.skin, "moss", "%s wears the undercroft skin" % f[0])
	for s in Level02Layout.STEPS:
		var step := platforms.get_node_or_null(String(s[0])) as SolidPlatform
		ok(step != null, "%s exists" % s[0])
	var wall_r := platforms.get_node("WallRight") as SolidPlatform
	almost(wall_r.position.x, float(Level02Layout.EAST_LIMIT), 0.01)
	var ceiling_w := platforms.get_node("CeilingWest") as SolidPlatform
	var ceiling_e := platforms.get_node("CeilingEast") as SolidPlatform
	almost(ceiling_w.position.x + ceiling_w.size.x, Level02Layout.SHAFT_X, 0.01,
			"shaft opens right after the west ceiling")
	almost(ceiling_e.position.x, Level02Layout.SHAFT_X + Level02Layout.SHAFT_W, 0.01)
	ok(Level02Layout.ENTRY_SPAWN.x > Level02Layout.SHAFT_X
			and Level02Layout.ENTRY_SPAWN.x < Level02Layout.SHAFT_X + Level02Layout.SHAFT_W,
			"the knight drops through the shaft")
	ok(_standing_on(rects, Vector2(Level02Layout.ENTRY_SPAWN.x, 320.0)), "shaft lands on FloorA")


func test_lifts_shuttle_between_their_ends() -> void:
	var host := _build()
	var lift_c := host.get_node("Platforms/LiftC") as MovingPlatform
	var lift_d := host.get_node("Platforms/LiftD") as MovingPlatform
	ok(lift_c != null and lift_d != null)
	eq(lift_c.start_position(), Level02Layout.LIFT_C_POS)
	eq(lift_c.end_position(), Level02Layout.LIFT_C_POS + Level02Layout.LIFT_C_TRAVEL)
	almost(lift_c.position_at(0.0).x, Level02Layout.LIFT_C_POS.x, 0.01)
	almost(lift_c.position_at(lift_c.period * 0.5).x, lift_c.end_position().x, 0.01, "half a period reaches the far end")
	almost(lift_c.position_at(lift_c.period).x, Level02Layout.LIFT_C_POS.x, 0.01, "a full period returns")
	ok(Level02Layout.LIFT_C_POS.x >= 1376.0 and Level02Layout.LIFT_C_POS.x <= 1408.0, "lift C boards from FloorC's lip")
	ok(320.0 - Level02Layout.LIFT_C_POS.y <= JUMP_RISE_MAX, "lift C deck is a single hop up")
	ok(lift_c.end_position().x + lift_c.width >= 1600.0 - 32.0, "lift C reaches FloorD")
	var alcove := host.get_node("Platforms/AlcoveD") as SolidPlatform
	ok(lift_d.end_position().y - alcove.position.y <= JUMP_RISE_MAX, "lift D's top is one hop below the alcove")
	ok(lift_d.end_position().x - (alcove.position.x + alcove.size.x) <= 32.0, "alcove is within a short hop of the lift")
	ok(lift_c.sync_to_physics, "riders inherit lift velocity")
	var stele := host.get_node_or_null("Props/SteleGallery") as LoreStele
	ok(stele != null and stele.position.x > alcove.position.x and stele.position.x < alcove.position.x + alcove.size.x,
			"the hidden stele sits on the alcove")


func test_props_checkpoints_and_exit_are_placed() -> void:
	var host := _build()
	var props := host.get_node("Props")
	var rects := _solids(host)
	var nest_a := props.get_node_or_null("EmberNestShaft") as EmberNest
	var nest_v := props.get_node_or_null("EmberNestVault") as EmberNest
	var nest_b := props.get_node_or_null("EmberNestHall") as EmberNest
	var nest_c := props.get_node_or_null("EmberNestBell") as EmberNest
	ok(nest_a != null and nest_v != null and nest_b != null and nest_c != null, "four checkpoints")
	ok(_standing_on(rects, nest_a.position + Vector2(6, 14)), "shaft nest stands on FloorA")
	ok(_standing_on(rects, nest_v.position + Vector2(6, 14)), "vault nest stands on FloorC")
	ok(_standing_on(rects, nest_b.position + Vector2(6, 14)), "hall nest stands on FloorD")
	ok(nest_b.position.x < Level02Layout.GATE_D_POS.x, "hall checkpoint comes before the rust gate")
	# 四座存档点相邻间距全部 <= 1000px。
	var xs := [nest_a.position.x, nest_v.position.x, nest_b.position.x, nest_c.position.x]
	for i in range(1, xs.size()):
		ok(xs[i] - xs[i - 1] <= CHECKPOINT_GAP_MAX,
				"checkpoint gap %.0f -> %.0f is <= 1000px" % [xs[i - 1], xs[i]])
	# Boss 前存档点：门前 2680 / 竞技场左界 2700 —— 巢必须 <=80px。
	ok(nest_c.position.x < Level02Layout.ARENA_GATE_X, "bell checkpoint comes before the bell gate")
	ok(absf(nest_c.position.x - Level02Layout.ARENA_GATE_X) <= 80.0,
			"bell checkpoint is <=80px from the arena gate")
	ok(absf(nest_c.position.x - Level02Layout.ARENA_LEFT) <= 80.0,
			"bell checkpoint is <=80px from the arena edge (BossArena contract)")
	ok(_standing_on(rects, nest_c.position + Vector2(6, 14)), "bell nest stands on FloorE")
	var exit := props.get_node_or_null("BellDoor") as LevelExit
	ok(exit != null, "the bell door ends the level")
	if exit != null:
		eq(exit.target_scene, GameContext.LEVELS["level02b"], "bell door hops to the slag conduit")
		eq(exit.flag_id, "undercroft_done")
		eq(exit.position, Level02Layout.EXIT_POS, "bell door sits at the authored arena exit")
		ok(_standing_on(rects, exit.position), "exit door stands on FloorE")
		ok(Level02Layout.EAST_LIMIT - exit.position.x >= 80.0, "exit keeps its distance from the east wall")
	var door := props.get_node_or_null("Door") as ArenaDoor
	var plate := props.get_node_or_null("Plate") as PressurePlate
	ok(door != null and plate != null)
	ok(plate.activated.is_connected(door.open_door), "plate opens the door")
	ok(LevelSanity.standing_on(LevelSanity.top_segments(host), LevelSanity.feet_of(plate)) != null, "plate rests on the spitter ledge")
	ok(_standing_on(rects, door.position + Vector2(0, 64)), "door foot meets the floor")
	var gate := props.get_node_or_null("RustyGate")
	ok(gate != null, "heat forge gate before the bell hall")
	for pool_name in ["ToxinPoolB", "ToxinPoolC"]:
		ok(props.get_node_or_null(pool_name) is ToxinPool, "%s exists" % pool_name)
	ok(host.get_node_or_null("UndercroftZone") is AtmosphereZone, "whole level is an indoor zone")
	eq((host.get_node("UndercroftZone") as AtmosphereZone).zone, WorldClock.Zone.INDOORS)


## 螺旋下探结构、坠钟走廊、单向捷径、钩锁可选奖励与笼状竞技场几何。
func test_spiral_descent_hazards_shortcut_and_cage_arena() -> void:
	var host := _build()
	var rects := _solids(host)
	eq(Level02Layout.EAST_LIMIT, 3800, "沉钟地窟扩到 3800 宽")
	var platforms := host.get_node("Platforms")
	var props := host.get_node("Props")
	# 1) 多层高度差：y=136（梁顶）、y=208/224（上层桥）、y=256（中层廊）、y=320（主地）、y=352（下沉钟堂）。
	var sunken := platforms.get_node_or_null("FloorSunken") as SolidPlatform
	ok(sunken != null and _standing_on(rects, Vector2(2160, 352)), "sunken bell vault floor at y=352")
	# 2) 周期性坠钟机关：首口教学钟前后各有 >=48px 安全平地，E 段改为双口坠钟走廊。
	for h in Level02Layout.BELL_HAZARDS:
		var hz := props.get_node_or_null(String(h[0])) as CyclicHazard
		ok(hz != null, "falling bell %s exists" % h[0])
		if hz != null:
			eq(hz.skin, "bell")
			ok(hz.telegraph_time >= CyclicHazard.MIN_TELEGRAPH, "%s telegraph >= 0.45s" % h[0])
	var teach := props.get_node("BellTeach") as CyclicHazard
	ok(_standing_on(rects, teach.position + Vector2(-48, 0)) and _standing_on(rects, teach.position + Vector2(48, 0)),
			"BellTeach has >=48px flat safe landing before and after")
	# 3) 单向捷径回环：上层 ShortcutPlate 打开地面 ShortcutDoor，连通 EmberNestHall 与下沉钟堂。
	var s_plate := props.get_node_or_null("ShortcutPlate") as PressurePlate
	var s_door := props.get_node_or_null("ShortcutDoor") as ArenaDoor
	ok(s_plate != null and s_door != null, "shortcut plate and door exist")
	if s_plate != null and s_door != null:
		ok(s_plate.activated.is_connected(s_door.open_door), "shortcut plate unlocks the ground shortcut door")
		ok(s_plate.position.y < s_door.position.y, "shortcut plate sits on the upper bridge above the shortcut door")
	# 4) 梁顶可选挑战与骨符奖励（仅凭钩锁可达）。
	var rafter := platforms.get_node_or_null("BellRafter") as SolidPlatform
	var reward_node := props.get_node_or_null("RewardUndercroft") as EquipmentPickup
	ok(rafter != null and reward_node != null, "optional rafter and equipment reward exist")
	if reward_node != null:
		eq(reward_node.reward_ref, Level02Layout.REWARD_RAFTER_ID)
		var reward_feet := LevelSanity.feet_of(reward_node)
		ok(not LevelSanity.is_reachable(host, Level02Layout.ENTRY_SPAWN, reward_feet, false),
				"rafter reward requires the hookshot")
		ok(LevelSanity.is_reachable(host, Level02Layout.ENTRY_SPAWN, reward_feet, true),
				"rafter reward is reachable with the hookshot")
	# 5) 空钟笼状竞技场：连续底板 + 两侧避钟笼台 + 中央击锤高台。
	ok(Level02Layout.ARENA_LEFT < Level02Layout.BOSS_POS.x and Level02Layout.BOSS_POS.x < Level02Layout.ARENA_RIGHT)
	ok(Level02Layout.ARENA_RIGHT - Level02Layout.ARENA_LEFT >= 600.0, "空钟竞技场 >= 600px 宽（契约）")
	var x := Level02Layout.ARENA_LEFT
	while x <= Level02Layout.ARENA_RIGHT:
		ok(_standing_on(rects, Vector2(x, 320.0)), "arena floor is continuous at x=%.0f" % x)
		x += 80.0
	for cage_step in ["CageAlcoveWest", "CageBelfryWest", "CageDais", "CageBelfryEast", "CageAlcoveEast"]:
		ok(platforms.get_node_or_null(cage_step) is SolidPlatform, "arena cage platform %s exists" % cage_step)
	ok(_standing_on(rects, Level02Layout.BOSS_POS), "boss stands on the arena floor")
	ok(_standing_on(rects, Level02Layout.EXIT_POS), "exit stands on the arena floor")
	ok(Level02Layout.EXIT_POS.x < Level02Layout.ARENA_RIGHT, "exit is inside the east end of the arena")
	ok(host.get_node_or_null("Waymarks/Sign_回廊") != null, "corridor waymark")
	ok(host.get_node_or_null("Waymarks/Sign_空钟") != null, "bell-hall waymark")
	# 6) LevelSanity 全量几何与主线无钩锁可达性。
	var problems := LevelSanity.check(host, Rect2(0, Level02Layout.CAMERA_TOP, Level02Layout.EAST_LIMIT, 480))
	ok(problems.is_empty(), "LevelSanity clean: %s" % "; ".join(problems))
	ok(LevelSanity.is_reachable(host, Level02Layout.ENTRY_SPAWN, Level02Layout.EXIT_POS, false),
			"main route from shaft entry to BellDoor is reachable without hookshot")


## 空钟门是章节出口：站到门前交互会开演、写 undercroft_done、并保存到 level02b。
## 这里在布局层验证接线（场景级走查在 level02_scene_test 里，两处都保留）。
func test_bell_door_wiring_plays_captions_and_writes_the_chapter_flag() -> void:
	var host := _build()
	var exit := host.get_node("Props/BellDoor") as LevelExit
	var player := await spawn_player(host, exit.position + Vector2(-16, 0))
	var previous_path := SaveData.save_path
	SaveData.save_path = "user://test_level02_bell_door_cfg.cfg"
	SaveData.delete_save()
	ok(player != null, "player spawns for the door beat")
	ok(exit != null and exit.can_interact(player), "bell door accepts interaction")
	ok(player is Player, "actor is a Player")
	if exit.is_locked():
		SaveData.mark_flag(Level02Layout.EXIT_REQUIRES)
		ok(not exit.is_locked(), "boss flag opens the bell door")
	exit.interact(player)
	await flush(2)
	ok(Director.playing, "bell door starts its caption beat")
	Director.abort()
	await flush(3)
	ok(SaveData.has_flag("undercroft_done"), "bell door writes the chapter flag")
	SaveData.delete_save()
	SaveData.save_path = previous_path


## 空钟 Boss 房：场景存在才安置 Boss + 竞技场 + 落钟机关，并把出口锁到
## hollow_bell_dead；场景缺失时保持空厅 + 出口开放（不软锁）。两种状态都要测。
func test_hollow_bell_room_is_conditional_and_never_softlocks() -> void:
	var host := _build()
	var props := host.get_node("Props")
	var exit := props.get_node_or_null("BellDoor") as LevelExit
	ok(exit != null, "bell door exists")
	var has_scene: bool = ResourceLoader.exists(Level02Layout.HOLLOW_BELL_PATH)
	if not has_scene:
		eq(host.get_node_or_null("Enemies/HollowBell"), null, "no boss scene -> no boss node")
		eq(host.get_node_or_null("Arenas/HollowBellArena"), null, "no boss scene -> no arena")
		eq(exit.requires_flag, "", "no boss scene -> exit stays open (never softlock)")
		return
	var boss := host.get_node_or_null("Enemies/HollowBell") as Node2D
	ok(boss != null, "HollowBell spawns in the bell hall")
	if boss != null:
		eq(boss.name, "HollowBell")
		eq(boss.position, Level02Layout.BOSS_POS)
	var arena := host.get_node_or_null("Arenas/HollowBellArena") as BossArena
	ok(arena != null, "bell-hall arena is assembled by BossArena.attach")
	if arena != null:
		almost(arena.arena_left, Level02Layout.ARENA_LEFT, 0.01)
		almost(arena.arena_right, Level02Layout.ARENA_RIGHT, 0.01)
		eq(arena.boss, boss)
		var hazards := arena.registered_hazard_ids()
		ok(hazards.has(&"bell_fall_west") and hazards.has(&"bell_fall_east"),
				"two falling-bell hazards are registered for the boss side")
		ok(arena.nearest_nest() != null, "arena sees the boss-pre checkpoint")
		if arena.nearest_nest() != null:
			ok(arena.checkpoint_report().ok, "checkpoint report passes (<=80px)")
	eq(exit.requires_flag, "hollow_bell_dead", "boss scene -> bell door waits for the kill flag")
	var owner = host.get_meta("layout", null)
	if owner != null:
		owner.call("_on_boss_slain")
	ok(SaveData.has_flag("hollow_bell_dead"), "slain writes the flag that unlocks the door")
	ok(not exit.is_locked(), "the bell door opens once the bell falls")


func test_enemies_stand_where_they_are_placed() -> void:
	var host := _build()
	var rects := _solids(host)
	var enemies := host.get_node("Enemies")
	var expected := Level02Layout.ENEMIES.size()
	if ResourceLoader.exists(Level02Layout.HOLLOW_BELL_PATH):
		expected += 1
	eq(enemies.get_child_count(), expected)
	var variants_seen := 0
	for e in Level02Layout.ENEMIES:
		var enemy := enemies.get_node_or_null(String(e[0])) as Node2D
		ok(enemy != null, "%s spawned" % e[0])
		if enemy == null:
			continue
		if e.size() >= 4 and String(e[3]) != "":
			variants_seen += 1
			eq(String(enemy.get_meta("variant", &"")), String(e[3]), "%s applies variant %s" % [e[0], e[3]])
		if enemy is GhostEnemy:
			ok(not _standing_on(rects, enemy.position, 8.0), "%s floats free of the floor" % e[0])
		else:
			ok(_standing_on(rects, enemy.position, 4.0), "%s stands on a platform" % e[0])
	ok(variants_seen >= 4, "staged encounters use enemy variants")


func test_backdrop_and_mood_are_indoor() -> void:
	var host := _build()
	var backdrop := host.get_node_or_null("ParallaxBackdrop") as CanvasLayer
	ok(backdrop != null)
	ok(backdrop.get_node_or_null("Void") is ColorRect, "solid void behind everything")
	var wall := backdrop.get_node_or_null("Wall") as Parallax2D
	ok(wall != null, "castle interior wall layer")
	if wall != null:
		ok(wall.repeat_times >= 4, "wall repeats enough copies for the 640 view")
		ok(wall.scroll_scale.x < 1.0 and wall.scroll_scale.x > 0.0)
	ok(backdrop.get_node_or_null("Columns") is Parallax2D)
	var mood := host.get_node_or_null("MoodTint") as CanvasModulate
	ok(mood != null)
	if mood != null:
		ok(mood.color.b > mood.color.r, "undercroft mood is cool, not the forge's amber")
	ok(host.get_node_or_null("Waymarks/Sign_地窟") != null, "entry sign")
	ok(host.get_node_or_null("Decor") != null)
