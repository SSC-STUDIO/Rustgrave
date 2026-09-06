extends TestCase
## Level02 "沉钟地窟": authored geometry stays jumpable, props/enemies stand on
## solid ground, checkpoints and the exit exist, and the level is indoor-only.

const JUMP_RISE_MAX := 32.0


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
		# spitter ledge: floor -> step -> ledge
		[Vector2(880, 320), Vector2(880, 288), Vector2(944, 264)],
		# pit C escape: pit floor -> lip -> floor
		[Vector2(1376, 384), Vector2(1376, 352), Vector2(1376, 320)],
		# gallery D: floor -> step -> gallery
		[Vector2(1936, 320), Vector2(1936, 288), Vector2(2000, 256)],
		# alcove: lift D at its top -> hop left onto the alcove's right end
		[Vector2(1856, 224), Vector2(1840, 208)],
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
	# Nothing else spans the floor line under the shaft: the drop lands on FloorA.
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
	# Boarding: the lift's start is one hop above FloorC's edge, its end meets FloorD.
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
	var nest_b := props.get_node_or_null("EmberNestHall") as EmberNest
	ok(nest_a != null and nest_b != null, "two checkpoints")
	ok(_standing_on(rects, nest_a.position + Vector2(6, 14)), "shaft nest stands on FloorA")
	ok(_standing_on(rects, nest_b.position + Vector2(6, 14)), "hall nest stands on FloorD")
	ok(nest_b.position.x < Level02Layout.GATE_D_POS.x, "hall checkpoint comes before the rust gate")
	var exit := props.get_node_or_null("BellDoor") as LevelExit
	ok(exit != null, "the bell door ends the level")
	if exit != null:
		eq(exit.target_scene, GameContext.LEVELS["level03"], "bell door hops to level03")
		eq(exit.flag_id, "undercroft_done")
		ok(_standing_on(rects, exit.position), "exit door stands on FloorD")
	var door := props.get_node_or_null("Door") as ArenaDoor
	var plate := props.get_node_or_null("Plate") as PressurePlate
	ok(door != null and plate != null)
	ok(plate.activated.is_connected(door.open_door), "plate opens the door")
	ok(_standing_on(rects, plate.position + Vector2(12, 8)), "plate rests on the spitter ledge")
	ok(_standing_on(rects, door.position + Vector2(0, 64)), "door foot meets the floor")
	var gate := props.get_node_or_null("RustyGate")
	ok(gate != null, "heat forge gate before the bell hall")
	for pool_name in ["ToxinPoolB", "ToxinPoolC"]:
		ok(props.get_node_or_null(pool_name) is ToxinPool, "%s exists" % pool_name)
	ok(host.get_node_or_null("UndercroftZone") is AtmosphereZone, "whole level is an indoor zone")
	eq((host.get_node("UndercroftZone") as AtmosphereZone).zone, WorldClock.Zone.INDOORS)


func test_enemies_stand_where_they_are_placed() -> void:
	var host := _build()
	var rects := _solids(host)
	var enemies := host.get_node("Enemies")
	eq(enemies.get_child_count(), Level02Layout.ENEMIES.size())
	for e in Level02Layout.ENEMIES:
		var enemy := enemies.get_node_or_null(String(e[0])) as Node2D
		ok(enemy != null, "%s spawned" % e[0])
		if enemy == null:
			continue
		if enemy is GhostEnemy:
			ok(not _standing_on(rects, enemy.position, 8.0), "%s floats free of the floor" % e[0])
		else:
			ok(_standing_on(rects, enemy.position, 4.0), "%s stands on a platform" % e[0])


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
