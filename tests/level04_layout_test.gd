extends TestCase
## Level04 "圣殿中庭": every authored step chain is a single jump, the choir
## plate opens the nave door, gear shields / spitter stand where they guard,
## the rust gate sits before the workshop door, and the exit hops to level05.

const LAYOUT_PATH := "res://scripts/levels/chapters/level04_layout.gd"
const L4 := preload("res://scripts/levels/chapters/level04_layout.gd")

const JUMP_RISE_MAX := 32.0
const JUMP_GAP_MAX := 72.0


func setup() -> void:
	SaveData.flags.clear()


func teardown() -> void:
	SaveData.flags.clear()
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)


func _host() -> Node2D:
	var host := Node2D.new()
	host.name = "Level04_Cathedral"
	host.scene_file_path = GameContext.LEVELS["level04"]
	host.add_to_group("game_world")
	add_child(host)
	return host


func _build() -> Node2D:
	var host := _host()
	var level := load(LAYOUT_PATH).new() as ChapterLayout
	add_child(level)
	level.build(host)
	return host


func _rects(host: Node2D) -> Dictionary:
	var by_name := {}
	for child in host.get_node("Platforms").get_children():
		if child is SolidPlatform:
			by_name[String(child.name)] = Rect2(child.position, child.size)
	return by_name


func _solids(host: Node2D) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for r in _rects(host).values():
		rects.append(r)
	return rects


func _standing_on(rects: Array[Rect2], feet: Vector2, slack: float = 0.5) -> bool:
	for r in rects:
		if feet.x >= r.position.x - 0.01 and feet.x <= r.end.x + 0.01 and absf(feet.y - r.position.y) <= slack:
			return true
	return false


func _on_named(rects: Dictionary, plat_name: String, feet: Vector2, slack: float = 0.5) -> bool:
	if not rects.has(plat_name):
		return false
	var r: Rect2 = rects[plat_name]
	return feet.x >= r.position.x - 0.01 and feet.x <= r.end.x + 0.01 and absf(feet.y - r.position.y) <= slack


func _edge_gap(a: Rect2, b: Rect2) -> float:
	if b.position.x > a.end.x:
		return b.position.x - a.end.x
	if a.position.x > b.end.x:
		return a.position.x - b.end.x
	return 0.0


func test_metadata_matches_the_registry() -> void:
	var level := load(LAYOUT_PATH).new() as ChapterLayout
	add_child(level)
	eq(level.level_id(), "level04")
	eq(level.title(), "锈墓・肆 — 圣殿中庭")
	ok(level.wake_line() != "", "the cathedral has an opening line")
	eq(level.theme(), "cathedral")
	ok(level.indoors(), "cathedral is an indoor theme")
	eq(level.east_limit(), L4.EAST_LIMIT)
	ok(level.camera_top() <= -96, "camera may lift toward the vault")
	eq(level.entry_spawn(), L4.ENTRY_SPAWN)
	eq(level.default_spawn(), level.entry_spawn())
	eq(GameContext.next_level_id(level.level_id()), "level05")


func test_step_chains_are_single_jumps() -> void:
	var host := _build()
	var rects := _rects(host)
	for chain in [L4.FONT_CHAIN, L4.CHOIR_CHAIN, L4.PULPIT_CHAIN, L4.BRIDGE_CHAIN]:
		for i in range(1, chain.size()):
			var a_name := String(chain[i - 1])
			var b_name := String(chain[i])
			ok(rects.has(a_name) and rects.has(b_name), "%s and %s exist" % [a_name, b_name])
			if not rects.has(a_name) or not rects.has(b_name):
				continue
			var a: Rect2 = rects[a_name]
			var b: Rect2 = rects[b_name]
			var rise := a.position.y - b.position.y
			var gap := _edge_gap(a, b)
			ok(rise <= JUMP_RISE_MAX + 0.01, "%s -> %s rises %.0f <= 32" % [a_name, b_name, rise])
			var reach := JUMP_GAP_MAX if rise >= 0.0 else JUMP_GAP_MAX + (-rise) * 0.5
			ok(gap <= reach + 0.01, "%s -> %s spans %.0f (allowed %.0f)" % [a_name, b_name, gap, reach])
			ok(b.position.x > a.position.x, "%s -> %s heads east" % [a_name, b_name])
	# The nave bridge is the long one: six hops over acid, its crest at least a full step up.
	var crest: Rect2 = rects["BridgeB3"]
	ok(320.0 - crest.position.y >= 64.0, "bridge crest hangs well above the pit")
	eq(L4.BRIDGE_CHAIN.size(), 7, "corridor -> five stones -> altar floor")


func test_terrain_seals_the_cathedral_and_pits_are_escapable() -> void:
	var host := _build()
	var rects := _rects(host)
	var platforms := host.get_node("Platforms")
	for f in L4.FLOORS:
		var plat := platforms.get_node_or_null(String(f[0])) as SolidPlatform
		ok(plat != null, "%s exists" % f[0])
		if plat == null:
			continue
		eq(plat.skin, "stone", "%s is paved with cathedral flagstone" % f[0])
		almost(plat.position.y, 320.0, 0.01, "%s top is the floor line" % f[0])
		almost(plat.position.x, float(f[1]), 0.01)
		almost(plat.size.x, float(f[2]) - float(f[1]), 0.01)
		ok(plat.tone.b >= plat.tone.r, "%s tone leans cold" % f[0])
	for s in L4.STEPS:
		var step := platforms.get_node_or_null(String(s[0])) as SolidPlatform
		ok(step != null and step.skin == "floating", "%s is a floating cathedral slab" % s[0])
	for b in L4.BLOCKS:
		var block := platforms.get_node_or_null(String(b[0])) as SolidPlatform
		ok(block != null and block.skin == "stone", "%s is a solid stone block" % b[0])
		if block != null:
			ok(block.position.y + block.size.y <= 320.0 + 0.01, "%s never sinks below the floor" % b[0])
	var wall_r := platforms.get_node_or_null("WallRight") as SolidPlatform
	ok(wall_r != null and absf(wall_r.position.x - float(L4.EAST_LIMIT)) < 0.01, "right wall on the east limit")
	var ceiling := platforms.get_node_or_null("Ceiling") as SolidPlatform
	ok(ceiling != null, "the nave is roofed (no shaft)")
	if ceiling != null:
		almost(ceiling.position.y, L4.CEILING_Y, 0.01)
		almost(ceiling.size.x, float(L4.EAST_LIMIT), 0.01)
	ok(_on_named(rects, "FloorA", Vector2(L4.ENTRY_SPAWN.x, 320.0)), "the knight arrives on FloorA")
	var props := host.get_node("Props")
	for p in L4.PITS:
		var pool := props.get_node_or_null(String(p[0]) + "Pool") as ToxinPool
		var bed := platforms.get_node_or_null(String(p[0]) + "Bed") as SolidPlatform
		ok(pool != null and bed != null, "%s pit has liquid and a bed" % p[0])
		if pool == null or bed == null:
			continue
		var surface := pool.surface_rect()
		almost(surface.position.x, float(p[1]), 0.01)
		almost(surface.size.x, float(p[2]) - float(p[1]), 0.01)
		ok(bed.position.y >= surface.position.y and bed.position.y <= surface.end.y + 16.0, "%s bed lies under the scum" % p[0])
		# Both lips are one jump (<= 32) above the bed.
		ok(_standing_on(_solids(host), Vector2(float(p[1]) - 8.0, 320.0)), "%s west lip is floor" % p[0])
		ok(_standing_on(_solids(host), Vector2(float(p[2]) + 8.0, 320.0)), "%s east lip is floor" % p[0])
		ok(bed.position.y - 320.0 <= JUMP_RISE_MAX, "%s can be climbed out of" % p[0])
	ok(LevelSanity.check(host).is_empty(), "LevelSanity finds nothing floating or buried: %s" % [LevelSanity.check(host)])


func test_choir_plate_opens_the_nave_door() -> void:
	var host := _build()
	var rects := _rects(host)
	var props := host.get_node("Props")
	var plate := props.get_node_or_null("ChoirPlate") as PressurePlate
	var door := props.get_node_or_null("ChoirDoor") as ArenaDoor
	ok(plate != null and door != null, "choir plate and nave door exist")
	if plate == null or door == null:
		return
	ok(plate.activated.is_connected(door.open_door), "stepping on the choir plate opens the nave door")
	ok(_on_named(rects, "ChoirLoft", plate.position + Vector2(12, 8), 2.5), "plate rests on the choir loft")
	ok(_on_named(rects, "FloorB", door.position + Vector2(0, 64)), "door foot meets the nave floor")
	var loft: Rect2 = rects["ChoirLoft"]
	ok(door.position.x >= loft.end.x, "door stands east of the loft, so the loft is the way to the plate")
	ok(door.position.x + 16.0 <= 1360.0 + 0.01, "door closes the nave before the corridor floor")
	ok(door.get_node_or_null("Solid") is StaticBody2D, "closed door is solid")
	ok(not door.is_open)
	# The loft is high enough that the plate is not reachable by a stray hop from the floor.
	ok(320.0 - loft.position.y >= 96.0 - 0.01, "loft sits three steps above the nave floor")
	# Two steps up, each a single jump.
	var s1: Rect2 = rects["ChoirStep1"]
	var s2: Rect2 = rects["ChoirStep2"]
	almost(320.0 - s1.position.y, 32.0, 0.01, "first step is one hop")
	almost(s1.position.y - s2.position.y, 32.0, 0.01, "second step is one hop")
	almost(s2.position.y - loft.position.y, 32.0, 0.01, "loft is one hop above the second step")


func test_enemies_hold_their_posts() -> void:
	var host := _build()
	var rects := _rects(host)
	var solids := _solids(host)
	var enemies := host.get_node("Enemies")
	eq(enemies.get_child_count(), L4.ENEMIES.size(), "every authored enemy spawned")
	var gear_shields := 0
	var ghosts := 0
	var spitters := 0
	var scrappers := 0
	for e in L4.ENEMIES:
		var enemy := enemies.get_node_or_null(String(e[0])) as Node2D
		ok(enemy != null, "%s spawned" % e[0])
		if enemy == null:
			continue
		if enemy is GhostEnemy:
			ghosts += 1
			ok(not _standing_on(solids, enemy.position, 8.0), "%s floats free of the floor" % e[0])
		else:
			ok(_standing_on(solids, enemy.position, 4.0), "%s stands on a platform" % e[0])
		if enemy is GearShieldEnemy:
			gear_shields += 1
		elif enemy is SpitterEnemy:
			spitters += 1
		elif enemy is ScrapperEnemy:
			scrappers += 1
		var overrides: Dictionary = e[3]
		for key in overrides:
			eq(enemy.get(key), overrides[key], "%s.%s override applied" % [e[0], key])
	eq(gear_shields, 2, "two gear shields, one per narrow passage")
	eq(ghosts, 2, "two ghosts")
	eq(spitters, 1, "one spitter")
	eq(scrappers, 1, "one scrapper")
	var gs1 := enemies.get_node("GearShield1") as Node2D
	var gs2 := enemies.get_node("GearShield2") as Node2D
	var spitter := enemies.get_node("Spitter1") as Node2D
	var ghost_font := enemies.get_node("Ghost1") as Node2D
	var ghost_loft := enemies.get_node("Ghost2") as Node2D
	ok(_on_named(rects, "FloorC", gs1.position, 4.0), "first gear shield holds the corridor floor")
	ok(_on_named(rects, "FloorD", gs2.position, 4.0), "second gear shield holds the altar floor")
	ok(_on_named(rects, "Pulpit", spitter.position, 4.0), "spitter preaches from the pulpit")
	ok(spitter.position.y < 320.0, "pulpit is raised above the nave")
	var gate := host.get_node("Props/RustyGate") as Node2D
	ok(gs2.position.x < gate.position.x, "second gear shield guards the approach to the rust gate")
	var door := host.get_node("Props/ChoirDoor") as Node2D
	ok(gs1.position.x > door.position.x, "first gear shield waits beyond the nave door")
	# Ranged guards stay out of aggro range of the plate loft and of the altar checkpoint.
	var loft: Rect2 = rects["ChoirLoft"]
	var loft_east := Vector2(loft.end.x, loft.position.y)
	var gs1_west := gs1.position - Vector2(float(gs1.get("patrol_range")), 0.0)
	ok(gs1_west.distance_to(loft_east) >= 300.0, "gear shield 1 cannot be aggroed from the choir loft")
	ok(gs1_west.distance_to(Vector2(door.position.x - 16.0, 300.0)) >= 300.0, "gear shield 1 cannot be aggroed from the locked door")
	var nest_altar := host.get_node("Props/EmberNestAltar") as Node2D
	var gs2_west := gs2.position - Vector2(float(gs2.get("patrol_range")), 0.0)
	ok(gs2_west.distance_to(nest_altar.position + Vector2(16, 14)) >= 300.0, "gear shield 2 leaves the altar checkpoint in peace")
	# Ghosts haunt the font landing and the choir loft.
	var floor_b: Rect2 = rects["FloorB"]
	ok(ghost_font.position.x > floor_b.position.x and ghost_font.position.x < floor_b.position.x + 160.0,
			"font ghost hovers over the landing lip of FloorB")
	ok(ghost_loft.position.x > loft.position.x and ghost_loft.position.x < loft.end.x
			and ghost_loft.position.y < loft.position.y, "loft ghost hovers above the choir loft")


func test_checkpoints_gate_and_exit() -> void:
	var host := _build()
	var rects := _rects(host)
	var props := host.get_node("Props")
	var nest_nave := props.get_node_or_null("EmberNestNave") as EmberNest
	var nest_altar := props.get_node_or_null("EmberNestAltar") as EmberNest
	ok(nest_nave != null and nest_altar != null, "two checkpoints")
	if nest_nave == null or nest_altar == null:
		return
	ok(_on_named(rects, "FloorA", nest_nave.position + Vector2(6, 14)), "nave nest stands on FloorA")
	ok(_on_named(rects, "FloorD", nest_altar.position + Vector2(6, 14)), "altar nest stands on FloorD")
	var floor_d: Rect2 = rects["FloorD"]
	ok(nest_altar.position.x - floor_d.position.x <= 64.0, "altar nest greets you right after the bridge")
	var gate := props.get_node_or_null("RustyGate") as RustyGate
	ok(gate != null, "heat forge gate before the workshop door")
	var exit := props.get_node_or_null("Exit") as LevelExit
	ok(exit != null, "the workshop door ends the level")
	if gate == null or exit == null:
		return
	ok(_on_named(rects, "FloorD", gate.position + Vector2(8, 64)), "gate foot meets the altar floor")
	ok(nest_altar.position.x < gate.position.x and gate.position.x < exit.position.x,
			"checkpoint -> rust gate -> exit, in that order")
	ok(_on_named(rects, "FloorD", exit.position), "exit door stands on FloorD")
	ok(float(L4.EAST_LIMIT) - exit.position.x >= 80.0, "exit keeps clear of the east wall")
	eq(exit.door_label, "工坊暗门")
	eq(exit.flag_id, "level04_done")
	eq(exit.target_scene, GameContext.LEVELS["level05"], "workshop door hops to level05")
	eq(exit.spawn, ChapterLayout.entry_spawn_of("level05"), "arrives at level05's entry spawn")
	ok(exit.captions.size() >= 1, "the door has something to say")
	for stele_name in ["SteleCompact", "StelePrice"]:
		var stele := props.get_node_or_null(stele_name) as LoreStele
		ok(stele != null, "%s exists" % stele_name)
		if stele != null:
			ok(_standing_on(_solids(host), stele.position), "%s stands on the floor" % stele_name)
			ok(stele.lore_title != "" and stele.lore_text != "", "%s carries lore" % stele_name)
	# Route check: spawn reaches both nests and the exit without hook or ember step
	# (LevelSanity's hop model; the only anchor in this level leads to an optional ledge).
	var spawn := Vector2(L4.ENTRY_SPAWN.x, 320.0)
	ok(LevelSanity.is_reachable(host, spawn, LevelSanity.feet_of(nest_nave)), "nave nest reachable")
	ok(LevelSanity.is_reachable(host, spawn, LevelSanity.feet_of(nest_altar)), "altar nest reachable")
	ok(LevelSanity.is_reachable(host, spawn, LevelSanity.feet_of(exit)), "exit reachable")


func test_vault_hook_and_ember_core_are_an_optional_detour() -> void:
	var host := _build()
	var rects := _rects(host)
	var hook := host.get_node_or_null("Hooks/Hook_Vault") as HookAnchor
	var core := host.get_node_or_null("Pickups/EmberCoreVault") as CorePickup
	ok(hook != null and core != null, "vault anchor and core exist")
	if hook == null or core == null:
		return
	var ledge: Rect2 = rects["VaultLedge"]
	ok(core.position.x >= ledge.position.x and core.position.x <= ledge.end.x, "core hangs over the vault ledge")
	ok(ledge.position.y - core.position.y > 0.0 and ledge.position.y - core.position.y <= 64.0, "core floats within reach above the ledge")
	ok(hook.position.y < ledge.position.y, "anchor hangs above the ledge")
	ok(ledge.position.y - hook.position.y <= 110.0, "ledge is within a tether drop of the anchor")
	ok(320.0 - ledge.position.y > 96.0, "ledge is far higher than any step chain: hookshot only")
	ok(core.core != null and core.core.id == &"ember_core", "the vault keeps an ember core")
	# The floor below is where the pull starts; the anchor is within tether reach of it.
	var floor_d: Rect2 = rects["FloorD"]
	var from := Vector2(clampf(hook.position.x, floor_d.position.x, floor_d.end.x), floor_d.position.y - 48.0)
	ok(from.distance_to(hook.position) <= 250.0, "anchor is within tether reach of the altar floor")


func test_backdrop_decor_and_mood_are_cathedral() -> void:
	var host := _build()
	var backdrop := host.get_node_or_null("ParallaxBackdrop") as CanvasLayer
	ok(backdrop != null)
	if backdrop != null:
		ok(backdrop.get_node_or_null("Void") is ColorRect, "solid void behind everything")
		ok(backdrop.get_node_or_null("Layer0") is Parallax2D, "gothic hall wall layer")
	var mood := host.get_node_or_null("MoodTint") as CanvasModulate
	ok(mood != null)
	if mood != null:
		ok(mood.color.b > mood.color.r, "cathedral mood is cold violet, not forge amber")
	ok(host.get_node_or_null("IndoorZone") is AtmosphereZone, "whole nave is an indoor zone")
	if host.get_node_or_null("IndoorZone") != null:
		eq((host.get_node("IndoorZone") as AtmosphereZone).zone, WorldClock.Zone.INDOORS)
	ok(host.get_node_or_null("Waymarks/Sign_圣殿") != null, "entry sign")
	ok(host.get_node_or_null("Waymarks/Sign_祭坛") != null, "altar sign")
	var decor := host.get_node_or_null("Decor")
	ok(decor != null)
	if decor == null:
		return
	var torches := 0
	var grounded := 0
	var xs: Array[float] = []
	for child in decor.get_children():
		if child is TorchLight:
			torches += 1
			xs.append((child as Node2D).position.x)
		elif child.is_in_group("grounded"):
			grounded += 1
			xs.append((child.get_meta("feet") as Vector2).x)
	eq(torches, L4.TORCHES.size(), "every wall torch placed")
	eq(grounded, L4.PROPS.size(), "every grounded prop found its texture")
	# Nests, steles and signs dress the floor too.
	for child in host.get_node("Props").get_children():
		if child is EmberNest or child is LoreStele:
			xs.append((child as Node2D).position.x)
	for sign in host.get_node("Waymarks").get_children():
		xs.append((sign as Node2D).position.x)
	# Nothing on the floors goes bare for long: dressed stretches never exceed ~260px,
	# except over the two acid pits where nothing can stand.
	xs.sort()
	var worst := 0.0
	for i in range(1, xs.size()):
		var gap := xs[i] - xs[i - 1]
		var over_pit := false
		for p in L4.PITS:
			if xs[i - 1] <= float(p[1]) + 8.0 and xs[i] >= float(p[2]) - 8.0:
				over_pit = true
		if not over_pit:
			worst = maxf(worst, gap)
	ok(worst <= 260.0, "longest undressed stretch of floor is %.0f px" % worst)
	# No big wall panel is centred above a floating stone's landing.
	var rects := _rects(host)
	for p in L4.PROPS:
		var key := String(p[0])
		if key == "balustrade":
			continue
		var feet: Vector2 = p[1]
		for s in L4.STEPS:
			var r: Rect2 = rects[String(s[0])]
			var clear := feet.x + 40.0 <= r.position.x or feet.x - 40.0 >= r.end.x or feet.y != 320.0
			ok(clear, "%s at %s stays clear of landing %s" % [key, feet, s[0]])
