extends TestCase
## Level08 "熔渣深渊": the slag rivers stay jumpable (floating-stone chain, gear
## + stone mix), the two lifts hand the knight over mid-pool, the plate on the
## floating ledge opens the sluice door, a rust gate guards the last river,
## every pool is slag-coloured and lies in a climbable pit, and the exit hops
## to level09.

const LAYOUT_PATH := "res://scripts/levels/chapters/level08_layout.gd"
const JUMP_RISE_MAX := 32.0
const JUMP_GAP_MAX := 72.0
const FLOOR_Y := 320.0


func setup() -> void:
	SaveData.flags.clear()


func teardown() -> void:
	SaveData.flags.clear()
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)


func _consts() -> Dictionary:
	return (load(LAYOUT_PATH) as GDScript).get_script_constant_map()


func _layout() -> ChapterLayout:
	var layout := (load(LAYOUT_PATH) as GDScript).new() as ChapterLayout
	add_child(layout)
	return layout


func _host() -> Node2D:
	var host := Node2D.new()
	host.name = "Level08_SlagDepths"
	host.scene_file_path = GameContext.LEVELS["level08"]
	host.add_to_group("game_world")
	add_child(host)
	return host


func _build() -> Node2D:
	var host := _host()
	_layout().build(host)
	return host

func test_sluice_approach_and_gate_checkpoint_are_outside_skull_ambush() -> void:
	var host := _build()
	var player := await spawn_player(host, Vector2(2440, 300))
	await flush(360)
	eq(player.health.current, player.health.max_hp, "gate nest has a safe recovery window")
	for enemy in host.get_node("Enemies").get_children():
		if str(enemy.name).begins_with("FireSkull"):
			ok(enemy.position.x >= 2160 and enemy.position.x <= 2404, "skulls remain between sluice and safe landing")


func _rect(host: Node2D, plat_name: String) -> Rect2:
	var node := host.get_node_or_null("Platforms/" + plat_name)
	if node is SolidPlatform:
		return Rect2(node.position, node.size)
	if node is GearPlatform:
		var g := node as GearPlatform
		return Rect2(g.position - Vector2(g.radius, g.radius), Vector2(g.radius * 2.0, g.radius * 2.0))
	if node is MovingPlatform:
		var m := node as MovingPlatform
		return Rect2(m.start_position(), Vector2(m.width, MovingPlatform.WORLD))
	return Rect2()


## Mirror of LevelSanity._can_hop with the authoring limit (32) instead of the
## checker's slack (34): rise <= 32, gap <= 72, drops may reach further.
func _hop(a: Rect2, b: Rect2) -> String:
	var gap := 0.0
	if b.position.x > a.end.x:
		gap = b.position.x - a.end.x
	elif a.position.x > b.end.x:
		gap = a.position.x - b.end.x
	var rise := a.position.y - b.position.y
	if rise > JUMP_RISE_MAX + 0.01:
		return "rises %.0f > 32" % rise
	var reach := JUMP_GAP_MAX if rise >= 0.0 else minf(160.0, JUMP_GAP_MAX + (-rise) * 0.5)
	if gap > reach + 0.01:
		return "gap %.0f > %.0f" % [gap, reach]
	return ""


func _chain_ok(host: Node2D, names: Array) -> void:
	for i in range(1, names.size()):
		var a := _rect(host, String(names[i - 1]))
		var b := _rect(host, String(names[i]))
		ok(a.has_area() and b.has_area(), "%s and %s exist" % [names[i - 1], names[i]])
		var why := _hop(a, b)
		ok(why == "", "%s -> %s is a single hop (%s)" % [names[i - 1], names[i], why])


func test_metadata_and_room() -> void:
	var layout := _layout()
	eq(layout.level_id(), "level08")
	ok(layout.title().contains("熔渣深渊"), "title names the slag depths")
	ok(layout.wake_line() != "", "one wake line")
	eq(layout.east_limit(), 4200)
	eq(layout.theme(), "forge")
	ok(layout.indoors(), "forge is an indoor theme")
	var host := _host()
	layout.build(host)
	var platforms := host.get_node("Platforms")
	var wall_r := platforms.get_node("WallRight") as SolidPlatform
	almost(wall_r.position.x, 4200.0, 0.01, "right wall at east_limit")
	var ceiling := platforms.get_node("Ceiling") as SolidPlatform
	ok(ceiling != null and ceiling.size.x >= 4200.0, "sealed ceiling spans the room")
	var tops := LevelSanity.top_segments(host)
	ok(LevelSanity.standing_on(tops, Vector2(layout.entry_spawn().x, FLOOR_Y)) != null, "spawn has FloorA under it")
	for child in platforms.get_children():
		if child is SolidPlatform:
			var r := Rect2(child.position, child.size)
			ok(r.position.x >= -16.0 and r.end.x <= 4216.0, "%s lies inside the room" % child.name)
			ok(r.position.y <= 384.0 or r.size.x < 24.0, "%s top is walkable (<= 384)" % child.name)


## 视觉 QA Phase A P1：渣河不再是一条高饱和纯橙带。池面改用深渣 ramp（河心暗、
## 近岸亮），tint 只留温和暖色；岸线由碎石/坏机械压边（见 test_slag_bridge_...）。
func test_slag_rivers_use_a_dark_desaturated_ramp() -> void:
	var host := _build()
	var consts := _consts()
	var pools: Array = []
	for node in host.get_node("Props").get_children():
		if node is ToxinPool:
			pools.append(node)
	ok(pools.size() >= 7, "the hottest level has at least seven slag pools (%d)" % pools.size())
	var ramp: Array = consts["SLAG_RAMP"]
	eq(ramp.size(), 5, "slag pools share one five-stop sludge ramp")
	var top: Color = ramp[4]
	var top_value := maxf(top.r, maxf(top.g, top.b))
	var top_min := minf(top.r, minf(top.g, top.b))
	var saturation := (top_value - top_min) / maxf(top_value, 0.001)
	ok(top_value <= 0.75, "the brightest scum stays below warning-orange (%.2f)" % top_value)
	ok(saturation <= 0.65, "the scum line is desaturated slag-brown (%.2f)" % saturation)
	for pool in pools:
		var p := pool as ToxinPool
		ok(p.sludge_ramp.size() == 5, "%s maps the shared ramp" % p.name)
		var tint := p.tint
		ok(tint.r > tint.g and tint.g > tint.b, "%s keeps a warm slag tint" % p.name)
		ok(tint.r <= 1.6, "%s tint is no longer overexposed (%s)" % [p.name, tint])
		ok(tint.r / maxf(tint.g, 0.001) <= 1.6, "%s tint is desaturated" % p.name)
		var rect := p.surface_rect()
		var bed := host.get_node_or_null("Platforms/" + String(p.name).replace("Pool", "Bed")) as SolidPlatform
		ok(bed != null, "%s has its own bed" % p.name)
		if bed == null:
			continue
		eq(bed.skin, "basalt", "%s bed is the same basalt" % p.name)
		almost(bed.position.y, rect.position.y + 16.0, 0.01, "%s bed top sits 16px under the surface" % p.name)
		almost(bed.position.x, rect.position.x, 0.01)
		almost(bed.size.x, rect.size.x, 0.01)
		ok(bed.position.y - FLOOR_Y <= JUMP_RISE_MAX, "%s pit is one hop deep" % p.name)
		# Both lips are walkable ground so a fallen knight can climb out either way.
		ok(LevelSanity.standing_on(LevelSanity.top_segments(host), Vector2(rect.position.x - 2.0, FLOOR_Y)) != null,
				"%s has a west lip" % p.name)
		ok(LevelSanity.standing_on(LevelSanity.top_segments(host), Vector2(rect.end.x + 2.0, FLOOR_Y)) != null,
				"%s has an east lip" % p.name)


func test_slag_river_a_is_a_floating_stone_chain() -> void:
	var host := _build()
	_chain_ok(host, ["FloorA", "StoneA1", "StoneA2", "StoneA3", "StoneA4", "FloorB"])
	for i in range(1, 5):
		var stone := _rect(host, "StoneA%d" % i)
		almost(stone.size.x, 48.0, 0.01, "StoneA%d is 48 wide" % i)
		almost(stone.size.y, 16.0, 0.01, "StoneA%d is a thin float" % i)
		var pool := host.get_node("Props/SlagAPool") as ToxinPool
		var surface := pool.surface_rect()
		ok(stone.position.x >= surface.position.x and stone.end.x <= surface.end.x, "StoneA%d hangs over the river" % i)
		ok(stone.end.y < surface.position.y, "StoneA%d clears the slag surface" % i)


func test_lifts_relay_across_the_long_pool() -> void:
	var host := _build()
	var lift_a := host.get_node_or_null("Platforms/LiftA") as MovingPlatform
	var lift_b := host.get_node_or_null("Platforms/LiftB") as MovingPlatform
	ok(lift_a != null and lift_b != null, "two lifts")
	if lift_a == null or lift_b == null:
		return
	almost(lift_a.period, lift_b.period, 0.001, "same period so the hand-over repeats")
	almost(absf(lift_b.phase - lift_a.phase), 0.5, 0.001, "half a period apart")
	ok(lift_a.sync_to_physics and lift_b.sync_to_physics, "riders inherit lift velocity")
	var floor_b := _rect(host, "FloorB")
	var floor_c := _rect(host, "FloorC")
	var pillar := _rect(host, "SlagPillar")
	var a_start := Rect2(lift_a.start_position(), Vector2(lift_a.width, MovingPlatform.WORLD))
	var a_end := Rect2(lift_a.end_position(), Vector2(lift_a.width, MovingPlatform.WORLD))
	var b_start := Rect2(lift_b.start_position(), Vector2(lift_b.width, MovingPlatform.WORLD))
	var b_end := Rect2(lift_b.end_position(), Vector2(lift_b.width, MovingPlatform.WORLD))
	eq(_hop(floor_b, a_start), "", "lift A boards from the dike's lip")
	eq(_hop(a_end, pillar), "", "lift A's far end drops onto the slag pillar")
	eq(_hop(pillar, b_start), "", "the pillar hops onto lift B")
	eq(_hop(a_end, b_start), "", "direct hand-over A -> B is also a single hop")
	eq(_hop(b_end, floor_c), "", "lift B lands on FloorC")
	ok(pillar.position.y == FLOOR_Y and pillar.end.y >= 400.0, "pillar rises from the pit bed to the floor line")
	# Timing: when A rests at its far end (half a period), B rests at its start.
	var half := lift_a.period * 0.5
	var a_at := lift_a.position_at(half)
	var b_at := lift_b.position_at(half + lift_b.phase * lift_b.period)
	almost(a_at.x, lift_a.end_position().x, 0.01, "A sits at its far end at half period")
	almost(b_at.x, lift_b.start_position().x, 0.01, "B sits at its near end at the same moment")
	ok(b_at.x - (a_at.x + lift_a.width) <= JUMP_GAP_MAX, "the decks are within one hop when they meet")
	ok(lift_a.chain_top_y <= lift_a.position.y, "chains hang from the ceiling")
	# The lift decks never sweep through the pillar (a rider there is not shoved).
	ok(a_end.end.x < pillar.position.x and b_start.position.x > pillar.end.x, "decks stop short of the pillar")


func test_plate_ledge_opens_the_sluice() -> void:
	var host := _build()
	var props := host.get_node("Props")
	var plate := props.get_node_or_null("SluicePlate") as PressurePlate
	var door := props.get_node_or_null("SluiceDoor") as ArenaDoor
	ok(plate != null and door != null, "plate and sluice door exist")
	if plate == null or door == null:
		return
	ok(plate.activated.is_connected(door.open_door), "plate opens the sluice")
	var tops := LevelSanity.top_segments(host)
	var plate_seg := LevelSanity.standing_on(tops, LevelSanity.feet_of(plate))
	ok(plate_seg != null and plate_seg.owner_name == "PlateLedgeC", "plate rests on the floating ledge")
	var door_seg := LevelSanity.standing_on(tops, LevelSanity.feet_of(door))
	ok(door_seg != null and door_seg.owner_name == "FloorC", "door foot meets the ground")
	ok(door.position.x > plate.position.x, "the door is east of the plate")
	almost(door.position.y + 64.0, FLOOR_Y, 0.01, "door bottom sits on the floor line")
	_chain_ok(host, ["FloorC", "PlateStepC", "PlateLedgeC"])
	var ledge := _rect(host, "PlateLedgeC")
	ok(door.position.x - ledge.end.x > JUMP_GAP_MAX, "the ledge is too far to hop onto the door's top")
	var spitter := host.get_node_or_null("Enemies/Spitter2") as Node2D
	if spitter != null:
		var seg := LevelSanity.standing_on(tops, spitter.position, 4.0, 4.0)
		ok(seg != null and seg.owner_name == "PlateLedgeC", "a spitter guards the plate ledge")


func test_rust_gate_and_exit() -> void:
	var host := _build()
	var props := host.get_node("Props")
	var tops := LevelSanity.top_segments(host)
	var gate := props.get_node_or_null("RustGate") as RustyGate
	ok(gate != null, "heat forge gate before the last river")
	if gate != null:
		var seg := LevelSanity.standing_on(tops, LevelSanity.feet_of(gate))
		ok(seg != null and seg.owner_name == "FloorE", "gate stands on FloorE")
		var nest := props.get_node_or_null("EmberNestGate") as EmberNest
		ok(nest != null and nest.position.x < gate.position.x, "a checkpoint sits before the gate")
		var shield := host.get_node_or_null("Enemies/GearShield1") as Node2D
		ok(shield != null and shield.position.x < gate.position.x and gate.position.x - shield.position.x < 96.0,
				"the gear shield guards the gate")
	var exit := props.get_node_or_null("Exit") as LevelExit
	ok(exit != null, "the rampart ladder ends the level")
	if exit != null:
		eq(exit.target_scene, GameContext.LEVELS["level09"], "exit hops to level09")
		eq(exit.flag_id, "level08_done")
		eq(exit.door_label, "城墙梯")
		var seg := LevelSanity.standing_on(tops, LevelSanity.feet_of(exit))
		ok(seg != null and seg.owner_name == "FloorI", "exit stands on the old-hull floor")
		ok(4200.0 - exit.position.x >= 80.0, "exit keeps its distance from the east wall")
		ok(exit.spawn != Vector2.ZERO, "exit knows where level09 drops the knight")


## ⑩⑪ 扩章：3008 → 4200。渣河桥（三块浮石）横渡第三座熔渣河，旧壳区里
## 有支路奖励位、余烬巢和新出口；渣河两岸有碎石/坏机械压边（视觉 QA P1）。
func test_slag_bridge_and_old_hull_extension() -> void:
	var host := _build()
	eq(_consts()["EAST_LIMIT"], 4200, "熔渣深渊扩到 4200 宽")
	_chain_ok(host, ["FloorG", "StoneE1", "StoneE2", "StoneE3", "FloorI"])
	var pool := host.get_node_or_null("Props/SlagEPool") as ToxinPool
	ok(pool != null, "the third slag river has its own pool")
	if pool != null:
		var surface := pool.surface_rect()
		for stone_name in ["StoneE1", "StoneE2", "StoneE3"]:
			var r := _rect(host, stone_name)
			ok(r.position.x >= surface.position.x and r.end.x <= surface.end.x,
					"%s hangs over the new river" % stone_name)
			ok(r.position.y < surface.position.y, "%s top clears the slag" % stone_name)
		ok(LevelSanity.standing_on(LevelSanity.top_segments(host), Vector2(surface.position.x - 2.0, FLOOR_Y)) != null)
		ok(LevelSanity.standing_on(LevelSanity.top_segments(host), Vector2(surface.end.x + 2.0, FLOOR_Y)) != null)
	var reward := host.get_node_or_null("Pickups/RewardOldHull") as EquipmentPickup
	ok(reward != null, "the old hull carries one reward slot")
	if reward != null:
		eq(reward.position, _consts()["REWARD_POS"])
		eq(String(reward.get("reward_kind")), "equipment", "reward slot walks the LoadoutBridge path")
		ok(String(reward.get("reward_ref")) != "")
		ok(LevelSanity.standing_on(LevelSanity.top_segments(host), LevelSanity.feet_of(reward)) != null,
				"reward rests on the old hull ledge")
		ok(LevelSanity.is_reachable(host, _consts()["ENTRY_SPAWN"], LevelSanity.feet_of(reward), false),
				"the hull ledge is a walkable side branch")
	var nest := host.get_node_or_null("Props/EmberNestShell") as EmberNest
	ok(nest != null, "the old hull district has a checkpoint")
	if nest != null:
		ok(LevelSanity.standing_on(LevelSanity.top_segments(host), nest.position + Vector2(6, 14)) != null,
				"shell nest stands on FloorI")
		ok(_consts()["EXIT_X"] - nest.position.x <= 1400.0, "checkpoint spacing stays <= 1400px")
		ok(LevelSanity.is_reachable(host, _consts()["ENTRY_SPAWN"], nest.position + Vector2(6, 14), false),
				"shell nest is reachable on the main route")
	# 岸线压边：渣河两岸真的有碎石/机械，而不是一条几何直边。
	var decor := host.get_node_or_null("Decor") as Node2D
	var shore_dressing := 0
	if decor != null:
		for child in decor.get_children():
			if child is Sprite2D and child.has_meta("feet") and (child as Node2D).position.y != 0.0:
				var feet: Vector2 = child.get_meta("feet")
				if absf(feet.y - FLOOR_Y) < 0.01 and feet.x in [400.0, 864.0, 2896.0, 3376.0, 3664.0]:
					shore_dressing += 1
	ok(shore_dressing >= 4, "slag rivers are pressed by shore rubble/machinery (%d)" % shore_dressing)


func test_last_river_mixes_gears_and_stones() -> void:
	var host := _build()
	_chain_ok(host, ["FloorE", "GearD1", "StoneD1", "GearD2", "StoneD2", "FloorG"])
	var g1 := host.get_node_or_null("Platforms/GearD1") as GearPlatform
	var g2 := host.get_node_or_null("Platforms/GearD2") as GearPlatform
	ok(g1 != null and g2 != null, "two octagon footholds")
	var pool := host.get_node("Props/SlagDPool") as ToxinPool
	var surface := pool.surface_rect()
	for plat_name in ["GearD1", "StoneD1", "GearD2", "StoneD2"]:
		var r := _rect(host, plat_name)
		ok(r.position.x >= surface.position.x and r.end.x <= surface.end.x, "%s hangs over the last river" % plat_name)
		ok(r.position.y < surface.position.y, "%s top clears the slag" % plat_name)


func test_skull_corridor_is_narrow_ground_with_skulls_overhead() -> void:
	var host := _build()
	_chain_ok(host, ["FloorC", "FloorD", "FloorE"])
	var floor_d := _rect(host, "FloorD")
	ok(floor_d.size.x <= 96.0, "the corridor floor is a narrow strip")
	var skulls: Array = []
	for e in _consts()["ENEMIES"]:
		if String(e[1]) == "fire_skull":
			skulls.append(e)
	eq(skulls.size(), 4, "four fire skulls")
	var solids := LevelSanity.solid_rects(host)
	var head_y := FLOOR_Y - 26.0
	for i in skulls.size():
		var pos: Vector2 = skulls[i][2]
		var above := head_y - pos.y
		ok(above >= 40.0 and above <= 70.0, "%s hovers %.0fpx above the knight's head" % [skulls[i][0], above])
		ok(not LevelSanity.inside_solid(solids, pos), "%s is not embedded" % skulls[i][0])
		ok(pos.x >= floor_d.position.x - 96.0 and pos.x <= floor_d.end.x + 96.0, "%s haunts the corridor" % skulls[i][0])
		if i > 0:
			ok(pos.distance_to(skulls[i - 1][2]) >= 24.0, "skulls keep their distance")


func test_checkpoints_props_and_enemies_stand() -> void:
	var host := _build()
	var props := host.get_node("Props")
	var tops := LevelSanity.top_segments(host)
	var solids := LevelSanity.solid_rects(host)
	var nests: Array = []
	for n in ["EmberNestStart", "EmberNestMid", "EmberNestGate", "EmberNestShell"]:
		var nest := props.get_node_or_null(n) as EmberNest
		ok(nest != null, "%s exists" % n)
		if nest != null:
			ok(LevelSanity.standing_on(tops, LevelSanity.feet_of(nest)) != null, "%s stands on ground" % n)
			nests.append(nest)
	ok(nests.size() == 4 and nests[0].position.x < nests[1].position.x \
			and nests[1].position.x < nests[2].position.x and nests[2].position.x < nests[3].position.x,
			"four checkpoints west to east")
	var door := props.get_node("SluiceDoor") as ArenaDoor
	ok(nests.size() == 4 and nests[1].position.x < door.position.x, "the middle nest comes before the sluice")
	for stele_name in ["SteleSlag", "SteleQuench"]:
		var stele := props.get_node_or_null(stele_name) as LoreStele
		ok(stele != null and stele.lore_title.begins_with("熔渣纪事"), "%s carries the slag chronicle" % stele_name)
		if stele != null:
			ok(LevelSanity.standing_on(tops, LevelSanity.feet_of(stele)) != null, "%s stands" % stele_name)
	var expected := 0
	for e in _consts()["ENEMIES"]:
		if ResourceLoader.exists(ChapterLayout.ENEMY_SCENES[String(e[1])]):
			expected += 1
	var enemies := host.get_node("Enemies")
	eq(enemies.get_child_count(), expected, "every available enemy kind spawned")
	for e in _consts()["ENEMIES"]:
		var enemy := enemies.get_node_or_null(String(e[0])) as Node2D
		if enemy == null:
			continue
		var airborne := enemy is GhostEnemy or (enemy.has_method("is_airborne") and bool(enemy.call("is_airborne"))) \
				or String(e[1]) == "fire_skull"
		if airborne:
			ok(not LevelSanity.inside_solid(solids, enemy.position), "%s floats free" % e[0])
		else:
			ok(LevelSanity.standing_on(tops, enemy.position, 4.0, 4.0) != null, "%s stands on a platform" % e[0])
	var scrapper := enemies.get_node_or_null("Scrapper1") as EnemyBase
	if scrapper != null:
		var floor_b := _rect(host, "FloorB")
		ok(scrapper.position.x - scrapper.patrol_range >= floor_b.position.x + 32.0, "the scrapper's beat stays clear of the slag lip")
	var shield := enemies.get_node_or_null("GearShield1") as EnemyBase
	if shield != null:
		var floor_e := _rect(host, "FloorE")
		ok(shield.position.x - shield.patrol_range >= floor_e.position.x + 24.0, "the shield's beat stays on FloorE")


func test_backdrop_is_forge_and_indoor() -> void:
	var host := _build()
	var mood := host.get_node_or_null("MoodTint") as CanvasModulate
	ok(mood != null and mood.color.r > mood.color.b, "forge mood is amber, not the undercroft's teal")
	ok(host.get_node_or_null("ParallaxBackdrop") is CanvasLayer, "themed backdrop")
	var zone := host.get_node_or_null("IndoorZone") as AtmosphereZone
	ok(zone != null and zone.zone == WorldClock.Zone.INDOORS, "whole level is an indoor zone")
	ok(host.get_node_or_null("Waymarks/Sign_渣渊") != null, "entry sign")
	ok(host.get_node_or_null("Waymarks/Sign_城墙") != null, "sign toward the ramparts")
	var decor := host.get_node_or_null("Decor")
	ok(decor != null and decor.get_child_count() >= 20, "torches, vines, slabs and rubble dress the room")
	var torches := 0
	for child in decor.get_children():
		if child is TorchLight:
			torches += 1
			ok((child as Node2D).modulate.r > (child as Node2D).modulate.b, "torch plates are warmed")
	ok(torches >= 6, "a torch every few hundred pixels (%d)" % torches)


## 渣河 A 上方的排气龛：本章支路。主路线跳不上去，钩锁从 StoneA2/A3 拉上去；
## 龛里是一条熔渣纪事（世界信息），不是第二枚核。
func test_vent_branch_is_an_optional_lore_ledge() -> void:
	var host := _build()
	var ledge := host.get_node_or_null("Platforms/VentLedge") as SolidPlatform
	var anchor := host.get_node_or_null("Hooks/HookVent") as HookAnchor
	var stele := host.get_node_or_null("Props/SteleVent") as LoreStele
	ok(ledge != null and anchor != null and stele != null, "vent ledge, anchor and stele exist")
	if ledge == null or anchor == null or stele == null:
		return
	ok(anchor.position.y < ledge.position.y, "anchor hangs above the vent ledge")
	ok(ledge.position.y - anchor.position.y <= LevelSanity.HOOK_LAND_BELOW, "ledge is a tether drop under the anchor")
	var stone_a2 := _rect(host, "StoneA2")
	var launch := Vector2(clampf(anchor.position.x, stone_a2.position.x, stone_a2.end.x), stone_a2.position.y - 48.0)
	ok(launch.distance_to(anchor.position) <= LevelSanity.HOOK_REACH, "anchor is within tether reach of StoneA2")
	var tops := LevelSanity.top_segments(host)
	ok(LevelSanity.standing_on(tops, LevelSanity.feet_of(stele)) != null, "stele stands on the vent ledge")
	ok(String(stele.lore_title).begins_with("熔渣纪事"), "vent stele is slag lore")
	ok(String(stele.lore_text) != "", "vent stele says something")
	var feet := LevelSanity.feet_of(stele)
	var spawn: Vector2 = _consts()["ENTRY_SPAWN"]
	ok(not LevelSanity.is_reachable(host, spawn, feet, false),
			"the main route cannot read the vent stele")
	ok(LevelSanity.is_reachable(host, spawn, feet, true),
			"the hookshot reaches the vent stele")
