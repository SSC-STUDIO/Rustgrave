extends TestCase
## Level05 "齿轮工坊": every lift boards from and lands on a real deck within one
## hop, both pressure plates open their doors (the second only via the vertical
## lift), the heat-forge gate and the spare tether core are in place, the three
## checkpoints and the exit stand on solid floor, and the exit hops to level06.

const LAYOUT_PATH := "res://scripts/levels/chapters/level05_layout.gd"
const JUMP_RISE_MAX := 32.0
const JUMP_GAP_MAX := 72.0
const DECK_H := 16.0

var _layout: ChapterLayout


func setup() -> void:
	SaveData.flags.clear()


func teardown() -> void:
	SaveData.flags.clear()
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)


func _build() -> Node2D:
	var host := Node2D.new()
	host.name = "Level05_Workshop"
	host.scene_file_path = GameContext.LEVELS["level05"]
	host.add_to_group("game_world")
	add_child(host)
	_layout = (load(LAYOUT_PATH) as GDScript).new() as ChapterLayout
	add_child(_layout)
	_layout.build(host)
	return host


## Walkable tops as rects: solids, lift decks at both ends, gear tops.
func _tops(host: Node2D) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for child in host.get_node("Platforms").get_children():
		if child is SolidPlatform:
			var p := child as SolidPlatform
			if p.size.x >= 24.0 and not String(p.name).begins_with("Ceiling"):
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
	var p := host.get_node_or_null("Platforms/" + plat_name) as SolidPlatform
	ok(p != null, "%s exists" % plat_name)
	return Rect2(p.position, p.size) if p != null else Rect2()


## One hop from deck `a` (top-left, width) onto deck `b`: rise <= 32, edge gap <= 72
## (drops may reach further, like LevelSanity).
func _one_hop(a: Rect2, b: Rect2) -> bool:
	var gap := 0.0
	if b.position.x > a.end.x:
		gap = b.position.x - a.end.x
	elif a.position.x > b.end.x:
		gap = a.position.x - b.end.x
	var rise := a.position.y - b.position.y
	if rise > JUMP_RISE_MAX:
		return false
	if rise >= 0.0:
		return gap <= JUMP_GAP_MAX
	return gap <= minf(160.0, JUMP_GAP_MAX + (-rise) * 0.5)


func _deck(m: MovingPlatform, at_end: bool) -> Rect2:
	return Rect2(m.end_position() if at_end else m.start_position(), Vector2(m.width, DECK_H))


func test_metadata_names_the_workshop() -> void:
	var layout := (load(LAYOUT_PATH) as GDScript).new() as ChapterLayout
	add_child(layout)
	eq(layout.level_id(), "level05")
	ok(layout.title().contains("齿轮工坊"), "title names the gear workshop")
	ok(layout.wake_line() != "", "an opening line")
	eq(layout.theme(), "industrial")
	ok(layout.indoors(), "the workshop has a roof")
	eq(layout.east_limit(), 3040)
	ok(layout.entry_spawn().x < 200.0, "the knight enters from the west")


func test_quench_pit_has_headroom_below_both_gear_stones() -> void:
	var host := _build()
	for enemy in host.get_node("Enemies").get_children(): enemy.set_physics_process(false)
	var player := await spawn_player(host, Vector2(504, 348))
	Input.action_press("move_right")
	await flush(96)
	Input.action_release("move_right")
	ok(player.position.x > 640, "a fallen knight walks beneath both stones without getting trapped")
	ok(player.health.current > 0, "the short recovery crossing is survivable")


func test_lifts_board_and_land_within_one_hop() -> void:
	var host := _build()
	var floor_b := _rect_named(host, "FloorB")
	var floor_c := _rect_named(host, "FloorC")
	var floor_e := _rect_named(host, "FloorE")
	var deck_d := _rect_named(host, "DeckD")
	var lift_c := host.get_node_or_null("Platforms/LiftC") as MovingPlatform
	var lift_d := host.get_node_or_null("Platforms/LiftD") as MovingPlatform
	var e1 := host.get_node_or_null("Platforms/LiftE1") as MovingPlatform
	var e2 := host.get_node_or_null("Platforms/LiftE2") as MovingPlatform
	ok(lift_c != null and lift_d != null and e1 != null and e2 != null, "four chain lifts")
	if lift_c == null or lift_d == null or e1 == null or e2 == null:
		return
	# C: the long crossing — boards off FloorB's east lip, lands on FloorC.
	ok(_one_hop(floor_b, _deck(lift_c, false)), "lift C start deck is one hop off FloorB")
	ok(_one_hop(_deck(lift_c, true), floor_c), "lift C end deck drops onto FloorC")
	ok(lift_c.travel.y == 0.0 and lift_c.travel.x >= 256.0, "lift C rides across the whole coolant pool")
	var pool_c := host.get_node_or_null("Props/PoolC") as ToxinPool
	ok(pool_c != null, "coolant pool C under lift C")
	if pool_c != null:
		var pr := pool_c.surface_rect()
		ok(lift_c.start_position().x <= pr.position.x and lift_c.end_position().x + lift_c.width >= pr.end.x,
				"lift C spans pool C from lip to lip")
	# D: vertical — boards from FloorC, tops out level with the plate deck.
	ok(_one_hop(floor_c, _deck(lift_d, false)), "lift D start deck is a low step off FloorC")
	ok(lift_d.travel.x == 0.0 and lift_d.travel.y <= -96.0, "lift D climbs at least 96px straight up")
	ok(_one_hop(_deck(lift_d, true), deck_d), "lift D top deck is one hop from the plate deck")
	ok(not _one_hop(floor_c, deck_d), "the plate deck cannot be jumped to from the floor")
	# E1/E2: the relay — E1 boards off FloorC, hands over to E2, E2 lands on FloorE.
	ok(_one_hop(floor_c, _deck(e1, false)), "lift E1 start deck is one hop off FloorC")
	ok(_one_hop(_deck(e1, true), _deck(e2, false)), "E1's east end meets E2's west end")
	ok(_one_hop(_deck(e2, true), floor_e), "lift E2 end deck drops onto FloorE")
	almost(e1.period, e2.period, 0.001, "relay lifts share a period")
	almost(absf(e2.phase - e1.phase), 0.5, 0.001, "relay lifts run half a period apart")
	# Half a period after E1 leaves its west end it is at its east end while E2 is back west.
	var half := e1.period * 0.5
	almost(e1.position_at(half).x, e1.end_position().x, 0.01, "E1 reaches its east end at half period")
	almost(e2.position_at(half + e2.phase * e2.period).x, e2.start_position().x, 0.01,
			"E2 is at its west end when E1 arrives")
	ok(e1.end_position().x + e1.width < e2.start_position().x, "relay decks never overlap")
	for m in [lift_c, lift_d, e1, e2]:
		ok((m as MovingPlatform).sync_to_physics, "%s carries its rider" % m.name)


func test_pressure_plates_open_their_doors() -> void:
	var host := _build()
	var props := host.get_node("Props")
	var tops := _tops(host)
	var plate_a := props.get_node_or_null("GateAPlate") as PressurePlate
	var door_a := props.get_node_or_null("GateADoor") as ArenaDoor
	var plate_b := props.get_node_or_null("GateBPlate") as PressurePlate
	var door_b := props.get_node_or_null("GateBDoor") as ArenaDoor
	ok(plate_a != null and door_a != null and plate_b != null and door_b != null, "two plate/door pairs")
	if plate_a == null or door_a == null or plate_b == null or door_b == null:
		return
	ok(plate_a.activated.is_connected(door_a.open_door), "plate A opens door A")
	ok(plate_b.activated.is_connected(door_b.open_door), "plate B opens door B")
	ok(not plate_a.activated.is_connected(door_b.open_door), "plate A does not open door B")
	ok(_standing_on(tops, LevelSanity.feet_of(plate_a), LevelSanity.FOOT_SLACK_DOWN), "plate A rests on walkway B")
	ok(_standing_on(tops, LevelSanity.feet_of(plate_b), LevelSanity.FOOT_SLACK_DOWN), "plate B rests on the lift-only deck")
	ok(_standing_on(tops, door_a.position + Vector2(0, 64)), "door A foot meets the floor")
	ok(_standing_on(tops, door_b.position + Vector2(0, 64)), "door B foot meets the floor")
	# Plate A sits on the walkway whose stairs climb from the door side, west of door A.
	var walk_b := _rect_named(host, "WalkB")
	ok(plate_a.position.x > walk_b.position.x and plate_a.position.x < walk_b.end.x, "plate A on walkway B")
	ok(walk_b.end.x < door_a.position.x, "walkway B lies before door A")
	ok(walk_b.position.y <= 320.0 - 100.0, "walkway B is high enough that its spitter cannot hit the floor")
	# Plate B's deck is reachable only from lift D's top: no other top hops onto it.
	var deck_d := _rect_named(host, "DeckD")
	var lift_d := host.get_node("Platforms/LiftD") as MovingPlatform
	var lift_top := _deck(lift_d, true)
	for r in tops:
		if r == deck_d or r == lift_top:
			continue
		ok(not _one_hop(r, deck_d), "only lift D reaches the plate deck (not %s)" % r)
	ok(deck_d.end.x < lift_d.start_position().x and lift_d.start_position().x < door_b.position.x,
			"plate deck, lift D and door B run west to east")


func test_gate_hook_and_spare_tether_core() -> void:
	var host := _build()
	var tops := _tops(host)
	var gate := host.get_node_or_null("Props/RustGate") as RustyGate
	ok(gate != null, "a heat-forge gate guards the slag road")
	if gate != null:
		ok(_standing_on(tops, gate.position + Vector2(8, 64)), "rust gate foot meets FloorE")
	var hook := host.get_node_or_null("Hooks/HookE") as HookAnchor
	var pick := host.get_node_or_null("Pickups/TetherCoreE") as CorePickup
	ok(hook != null and pick != null, "hook anchor and spare tether core")
	if hook == null or pick == null:
		return
	ok(pick.core != null and pick.core.id == &"tether_core", "the spare core is a tether core")
	ok(hook.position.distance_to(pick.position) <= 96.0, "the core hangs within reach of the anchor")
	var walk_e := _rect_named(host, "WalkE")
	ok(pick.position.x >= walk_e.position.x and pick.position.x <= walk_e.end.x
			and walk_e.position.y - pick.position.y <= 64.0 and walk_e.position.y > pick.position.y,
			"the core floats just above walkway E")
	ok(hook.position.y < walk_e.position.y, "the anchor hangs above the walkway")
	# Without the hookshot the walkway is still climbable: FloorE -> three steps -> walkway.
	var chain: Array[Rect2] = [_rect_named(host, "FloorE"), _rect_named(host, "StepE1"),
			_rect_named(host, "StepE2"), _rect_named(host, "StepE3"), walk_e]
	for i in range(1, chain.size()):
		ok(_one_hop(chain[i - 1], chain[i]), "stair E hop %d is a single jump" % i)
	ok(gate.position.x > _rect_named(host, "FloorE").position.x and gate.position.x < 2960.0,
			"the gate stands between the relay landing and the exit")


func test_checkpoints_exit_and_lore_are_placed() -> void:
	var host := _build()
	var props := host.get_node("Props")
	var tops := _tops(host)
	var nests: Array[EmberNest] = []
	for nest_name in ["EmberNestStart", "EmberNestLift", "EmberNestGate"]:
		var n := props.get_node_or_null(nest_name) as EmberNest
		ok(n != null, "%s exists" % nest_name)
		if n != null:
			nests.append(n)
			ok(_standing_on(tops, n.position + Vector2(6, 14)), "%s stands on a floor" % nest_name)
	if nests.size() == 3:
		var lift_c := host.get_node("Platforms/LiftC") as MovingPlatform
		var gate := props.get_node("RustGate") as Node2D
		ok(nests[0].position.x < 480.0, "first nest in the entry hall")
		ok(nests[1].position.x > lift_c.end_position().x, "second nest waits after the long crossing")
		ok(nests[2].position.x > 2512.0 and nests[2].position.x < gate.position.x,
				"third nest after the relay, before the rust gate")
	var exit := props.get_node_or_null("Exit") as LevelExit
	ok(exit != null, "the slag road ends the level")
	if exit != null:
		eq(exit.target_scene, GameContext.LEVELS["level06"], "the slag road hops to level06")
		eq(exit.flag_id, "level05_done")
		eq(exit.door_label, "运渣道")
		ok(_standing_on(tops, exit.position), "exit door stands on FloorE")
		ok(exit.position.x <= 3040.0 - 80.0, "exit keeps clear of the east wall")
		eq(exit.spawn, ChapterLayout.entry_spawn_of("level06"), "arrives at level06's entry spawn")
	var quench := props.get_node_or_null("SteleQuench") as LoreStele
	var chain_stele := props.get_node_or_null("SteleChain") as LoreStele
	ok(quench != null and chain_stele != null, "two workshop steles")
	if quench != null and chain_stele != null:
		ok(quench.lore_title.begins_with("工坊遗训") and chain_stele.lore_title.begins_with("工坊遗训"),
				"both steles carry the workshop precepts")
		ok(_standing_on(tops, quench.position), "quench stele on FloorA")
		var deck_d := _rect_named(host, "DeckD")
		ok(chain_stele.position.x > deck_d.position.x and chain_stele.position.x < deck_d.end.x
				and absf(chain_stele.position.y - deck_d.position.y) < 0.5, "chain stele hides on the lift-only deck")
	for pool_name in ["PitBPool", "PoolC", "PitEPool"]:
		ok(props.get_node_or_null(pool_name) is ToxinPool, "%s exists" % pool_name)
	ok(host.get_node_or_null("Waymarks/Sign_工坊") != null, "entry sign")
	ok(host.get_node_or_null("Waymarks/Sign_渣道") != null, "slag road sign")
	ok(host.get_node_or_null("IndoorZone") is AtmosphereZone, "whole level is an indoor zone")
	ok(host.get_node_or_null("ParallaxBackdrop") is CanvasLayer, "industrial backdrop built")


func test_step_chains_are_single_jumps() -> void:
	var host := _build()
	var chains := [
		# quench pit: FloorA lip -> two gear stones -> FloorB
		["FloorA", "GearB1", "GearB2", "FloorB"],
		# walkway B stairs, climbed westward from the door side
		["FloorB", "StepB1", "StepB2", "StepB3", "WalkB"],
		# coolant pool C escape: bed -> lip -> floor, both sides
		["BedC", "LipC1", "FloorB"],
		["BedC", "LipC2", "FloorC"],
		# quench / relay pits climb straight out
		["PitBBed", "FloorA"], ["PitBBed", "FloorB"],
		["PitEBed", "FloorC"], ["PitEBed", "FloorE"],
	]
	var platforms := host.get_node("Platforms")
	for chain in chains:
		for i in range(1, chain.size()):
			var a := _named_rect(platforms, String(chain[i - 1]))
			var b := _named_rect(platforms, String(chain[i]))
			ok(a.has_area() and b.has_area(), "%s and %s exist" % [chain[i - 1], chain[i]])
			ok(_one_hop(a, b), "%s -> %s is a single hop" % [chain[i - 1], chain[i]])


func _named_rect(platforms: Node, plat_name: String) -> Rect2:
	var node := platforms.get_node_or_null(plat_name)
	if node is SolidPlatform:
		return Rect2((node as SolidPlatform).position, (node as SolidPlatform).size)
	if node is GearPlatform:
		var g := node as GearPlatform
		return Rect2(g.position - Vector2(g.radius, g.radius), Vector2(g.radius * 2.0, g.radius * 2.0))
	return Rect2()


func test_enemies_stand_where_they_are_placed() -> void:
	var host := _build()
	var tops := _tops(host)
	var enemies := host.get_node("Enemies")
	eq(enemies.get_child_count(), 7, "seven enemies")
	var kinds := {}
	for child in enemies.get_children():
		var e := child as Node2D
		var cls := (e.get_script() as Script).get_global_name()
		kinds[cls] = int(kinds.get(cls, 0)) + 1
		if e is GhostEnemy or e is FlyingDemonEnemy:
			ok(not _standing_on(tops, e.position, 8.0), "%s floats free of any deck" % e.name)
		else:
			ok(_standing_on(tops, e.position, 4.0), "%s stands on a platform" % e.name)
	eq(int(kinds.get("SpitterEnemy", 0)), 2, "two spitters")
	eq(int(kinds.get("ScrapperEnemy", 0)), 2, "two scrappers")
	eq(int(kinds.get("GearShieldEnemy", 0)), 1, "one gear shield")
	eq(int(kinds.get("GhostEnemy", 0)), 1, "one ghost")
	eq(int(kinds.get("FlyingDemonEnemy", 0)), 1, "one flying demon")
	# Spitters hold opposite ends of the two walkways, too high to hit anyone on the floor,
	# and face different stair climbs.
	var s1 := enemies.get_node_or_null("Spitter1") as Node2D
	var s2 := enemies.get_node_or_null("Spitter2") as Node2D
	var walk_b := _rect_named(host, "WalkB")
	var walk_e := _rect_named(host, "WalkE")
	if s1 != null and s2 != null:
		ok(s1.position.x - walk_b.position.x <= 24.0, "spitter 1 holds walkway B's west end")
		ok(walk_e.end.x - s2.position.x <= 24.0, "spitter 2 holds walkway E's east end")
		ok(320.0 - s1.position.y > 96.0 and 320.0 - s2.position.y > 96.0, "walkway spitters cannot fire at the floor")
		ok(s2.position.x - s1.position.x > 380.0 * 2.0, "the two spitters never cover the same jump")
	var demon := enemies.get_node_or_null("FlyingDemon1") as Node2D
	var pool_c := host.get_node_or_null("Props/PoolC") as ToxinPool
	if demon != null and pool_c != null:
		var pr := pool_c.surface_rect()
		ok(demon.position.x > pr.position.x and demon.position.x < pr.end.x and demon.position.y < pr.position.y,
				"the demon circles above the long coolant pool")
	var guard := enemies.get_node_or_null("GearShield1") as Node2D
	var gate := host.get_node_or_null("Props/RustGate") as Node2D
	if guard != null and gate != null:
		ok(guard.position.x < gate.position.x and gate.position.x - guard.position.x <= 96.0,
				"the gear shield stands just before the rust gate")


func test_level_sanity_is_clean_on_a_bare_host() -> void:
	var host := _build()
	await flush(2)
	var problems := LevelSanity.check(host)
	for p in problems:
		ok(false, p)
	ok(problems.is_empty(), "LevelSanity clean (%d problems)" % problems.size())
	var spawn := _layout.entry_spawn()
	for nest in host.get_node("Props").get_children():
		if nest is EmberNest:
			ok(LevelSanity.is_reachable(host, spawn, LevelSanity.feet_of(nest)), "%s reachable from spawn" % nest.name)
	var exit := host.get_node("Props/Exit") as Node2D
	ok(LevelSanity.is_reachable(host, spawn, LevelSanity.feet_of(exit)), "exit reachable from spawn")
