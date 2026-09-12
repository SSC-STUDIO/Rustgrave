extends TestCase
## Level10 "炉心深处" (终关): the slag crossing stays single hops, the arena is one
## flat run with nothing but the two end perches, both checkpoints stand before
## the rust gate, and the exit is the ending door (no next scene, boss flag).

const LAYOUT := preload("res://scripts/levels/chapters/level10_layout.gd")
const JUMP_RISE_MAX := 32.0
const JUMP_GAP_MAX := 72.0


func setup() -> void:
	SaveData.flags.clear()


func teardown() -> void:
	SaveData.flags.clear()
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)


func _host() -> Node2D:
	var host := Node2D.new()
	host.name = "Level10_ForgeCore"
	host.scene_file_path = GameContext.LEVELS["level10"]
	host.add_to_group("game_world")
	add_child(host)
	return host


func _build() -> Node2D:
	var host := _host()
	var level := LAYOUT.new() as ChapterLayout
	add_child(level)
	level.build(host)
	return host

func test_arena_checkpoint_and_boss_room_exclude_corridor_pursuers() -> void:
	var host := _build()
	var player := await spawn_player(host, Vector2(880, 300))
	await flush(360)
	eq(player.health.current, player.health.max_hp, "boss checkpoint is safe while resting")
	player.position = Vector2(820, 320)
	await flush(90)
	player.position = Vector2(1180, 288)
	await flush(420)
	for enemy in host.get_node("Enemies").get_children():
		if enemy.name == "Nightmare": continue
		ok(enemy.position.x <= 832, "corridor pursuer stays outside the boss arena")


func _solids(host: Node2D) -> Array[SolidPlatform]:
	var out: Array[SolidPlatform] = []
	for child in host.get_node("Platforms").get_children():
		if child is SolidPlatform:
			out.append(child as SolidPlatform)
	return out


func _rects(host: Node2D) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for p in _solids(host):
		rects.append(Rect2(p.position, p.size))
	return rects


func _standing_on(rects: Array[Rect2], feet: Vector2, slack: float = 0.5) -> bool:
	for r in rects:
		if feet.x >= r.position.x - 0.01 and feet.x <= r.end.x + 0.01 and absf(feet.y - r.position.y) <= slack:
			return true
	return false


func _right(p: SolidPlatform) -> float:
	return p.position.x + p.size.x


func _overlaps_arena(x0: float, x1: float) -> bool:
	return x1 > LAYOUT.ARENA_X0 and x0 < LAYOUT.ARENA_X1


func test_metadata_is_the_final_chapter() -> void:
	var level := LAYOUT.new() as ChapterLayout
	add_child(level)
	eq(level.level_id(), "level10")
	eq(level.title(), "锈墓・拾 — 炉心深处")
	ok(level.wake_line() != "", "the forge core has an opening line")
	eq(level.theme(), "forge")
	ok(level.indoors(), "the forge core is indoors")
	eq(level.east_limit(), 2560)
	eq(GameContext.next_level_id("level10"), "", "nothing comes after level10")
	eq(level.entry_spawn(), LAYOUT.ENTRY_SPAWN)
	eq(level.default_spawn(), level.entry_spawn())


func test_slag_crossing_is_single_hops() -> void:
	var host := _build()
	var rects := _rects(host)
	# bank -> three floating stones -> far bank, all in one-jump reach
	var chain := [Vector2(LAYOUT.SLAG_X0, 320.0)]
	for s in LAYOUT.SLAG_STONES:
		chain.append(s[1] as Vector2)
	chain.append(Vector2(LAYOUT.SLAG_X1, 320.0))
	for i in range(1, chain.size()):
		var a: Vector2 = chain[i - 1]
		var b: Vector2 = chain[i]
		var rise := a.y - b.y
		ok(rise <= JUMP_RISE_MAX + 0.01, "hop %s -> %s rises %.0f <= 32" % [a, b, rise])
		var prev_w: float = 0.0
		if i >= 2:
			prev_w = float(LAYOUT.SLAG_STONES[i - 2][2])
		var gap := b.x - (a.x + prev_w)
		ok(gap <= JUMP_GAP_MAX + 0.01, "gap %s -> %s is %.0f <= 72" % [a, b, gap])
	for s in LAYOUT.SLAG_STONES:
		var stone := host.get_node_or_null("Platforms/" + String(s[0])) as SolidPlatform
		ok(stone != null, "%s exists" % s[0])
		if stone != null:
			eq(stone.skin, "moss_float", "%s is a floating stone" % s[0])
			eq(stone.tone, LAYOUT.STONE_TONE, "%s wears the brighter footing tone" % s[0])
	# the pit floor is one hop below the banks so a fall is survivable
	var bed := host.get_node_or_null("Platforms/SlagBed") as SolidPlatform
	ok(bed != null, "slag bed exists")
	if bed != null:
		ok(bed.position.y - 320.0 <= JUMP_RISE_MAX, "climbing out of the slag is one hop")
		almost(bed.position.x, LAYOUT.SLAG_X0, 0.01)
		almost(_right(bed), LAYOUT.SLAG_X1, 0.01)
		eq(bed.tone, LAYOUT.TONE, "the bed is tinted like the rest of the forge")
	var pool := host.get_node_or_null("Props/SlagPool") as ToxinPool
	ok(pool != null, "slag pool exists")
	if pool != null and bed != null:
		var surface := pool.surface_rect()
		almost(surface.position.x, LAYOUT.SLAG_X0, 0.01)
		almost(surface.end.x, LAYOUT.SLAG_X1, 0.01)
		ok(bed.position.y >= surface.position.y and bed.position.y <= surface.end.y + 16.0, "pool lies on its bed")
		ok(pool.tint.r > pool.tint.b, "slag is orange-red, not the undercroft's green")
	ok(_standing_on(rects, Vector2(LAYOUT.SLAG_X0 - 1.0, 320.0)), "west bank is floor")
	ok(_standing_on(rects, Vector2(LAYOUT.SLAG_X1 + 1.0, 320.0)), "east bank is floor")


func test_arena_is_one_flat_run_with_only_end_perches() -> void:
	var host := _build()
	var floor_covers_arena := false
	for p in _solids(host):
		if absf(p.position.y - 320.0) <= 0.01 and p.position.x <= LAYOUT.ARENA_X0 and _right(p) >= LAYOUT.ARENA_X1:
			floor_covers_arena = true
	ok(floor_covers_arena, "one floor platform spans the whole arena 1100..2300 at y=320")
	var perches := 0
	for p in _solids(host):
		var n := String(p.name)
		if n == "Ceiling" or n == "WallLeft" or n == "WallRight":
			continue
		if not _overlaps_arena(p.position.x, _right(p)):
			continue
		if absf(p.position.y - 320.0) <= 0.01:
			continue
		ok(p.position.y < 320.0, "%s inside the arena is not a pit" % n)
		ok(n == "PerchWest" or n == "PerchEast", "%s is the only kind of raised solid allowed in the arena" % n)
		eq(p.size, LAYOUT.PERCH_SIZE, "%s is a 48x32 block" % n)
		almost(p.position.y, 288.0, 0.01, "%s stands 32px above the floor" % n)
		var near_end := p.position.x - LAYOUT.ARENA_X0 <= 100.0 or LAYOUT.ARENA_X1 - _right(p) <= 100.0
		ok(near_end, "%s hugs an arena end" % n)
		perches += 1
	eq(perches, 2, "exactly two perches, one per end")
	for child in host.get_node("Platforms").get_children():
		ok(not child is MovingPlatform, "no lifts in the boss room (%s)" % child.name)
	for child in host.get_node("Props").get_children():
		if child is ToxinPool:
			var r := (child as ToxinPool).surface_rect()
			ok(not _overlaps_arena(r.position.x, r.end.x), "%s stays out of the arena" % child.name)
	# nothing grounded but background columns inside the arena (nothing to mislead a landing)
	var column_tex := load(ChapterLayout.DECOR["column"]) as Texture2D
	for node in host.get_node("Decor").get_children():
		if not node.is_in_group("grounded"):
			continue
		var feet: Vector2 = node.get_meta("feet")
		if feet.x > LAYOUT.ARENA_X0 + 48.0 and feet.x < LAYOUT.ARENA_X1 - 48.0:
			ok(node is Sprite2D and (node as Sprite2D).texture == column_tex,
					"grounded decor at %.0f inside the arena is a background column" % feet.x)
	ok(LAYOUT.BOSS_POS.x > LAYOUT.ARENA_X0 + 200.0 and LAYOUT.BOSS_POS.x < LAYOUT.ARENA_X1 - 200.0, "the Nightmare waits well inside the arena")
	almost(LAYOUT.BOSS_POS.y, 320.0, 0.01, "the Nightmare stands on the arena floor")


func test_checkpoints_stand_before_the_gate() -> void:
	var host := _build()
	var rects := _rects(host)
	var props := host.get_node("Props")
	var nest_gate := props.get_node_or_null("EmberNestGate") as EmberNest
	var nest_arena := props.get_node_or_null("EmberNestArena") as EmberNest
	ok(nest_gate != null and nest_arena != null, "two checkpoints")
	if nest_gate == null or nest_arena == null:
		return
	ok(_standing_on(rects, nest_gate.position + Vector2(6, 14)), "entry nest stands on FloorEntry")
	ok(_standing_on(rects, nest_arena.position + Vector2(6, 14)), "arena nest stands on FloorHall")
	var gate := props.get_node_or_null("ArenaGate") as RustyGate
	ok(gate != null, "the rust gate is the arena door")
	if gate == null:
		return
	ok(nest_arena.position.x < gate.position.x, "the pre-boss nest comes before the rust gate")
	ok(nest_arena.position.x > LAYOUT.SLAG_X1, "the pre-boss nest is past the slag river")
	ok(_standing_on(rects, gate.position + Vector2(8, 64)), "gate foot meets the floor")
	ok(gate.position.x + 16.0 <= LAYOUT.ARENA_X0, "the gate closes the arena off from the west")
	ok(nest_gate.position.x < LAYOUT.SLAG_X0, "the entry nest sits before the slag river")


func test_exit_is_the_ending_door() -> void:
	var host := _build()
	var rects := _rects(host)
	var exit := host.get_node_or_null("Props/Exit") as LevelExit
	ok(exit != null, "the forge core has an exit door")
	if exit == null:
		return
	eq(exit.target_scene, "", "the ending door leads nowhere but the title")
	eq(exit.requires_flag, "nightmare_dead", "the door waits for the Nightmare's death")
	eq(exit.flag_id, "game_complete", "walking through completes the game")
	eq(exit.door_label, "炉心之门")
	eq(exit.locked_prompt, "梦魇还在喘。门不开。")
	eq(exit.captions.size(), 3, "three ending captions")
	ok(String(exit.captions[exit.captions.size() - 1]).contains("完"), "the last caption closes the book")
	ok(exit.is_locked(), "locked while the Nightmare lives")
	SaveData.mark_flag("nightmare_dead")
	ok(not exit.is_locked(), "opens once the Nightmare is dead")
	ok(_standing_on(rects, exit.position), "exit door stands on FloorHall")
	ok(exit.position.x > LAYOUT.ARENA_X1, "the door is past the arena")
	ok(exit.position.x <= LAYOUT.EAST_LIMIT - 80.0, "the door keeps clear of the east wall")
	var altar := host.get_node_or_null("Decor/ForgeAltar") as Node2D
	ok(altar != null, "the forge altar is placed")
	if altar != null:
		ok(altar.is_in_group("grounded") and altar.has_meta("feet"), "the altar is checked for footing like any prop")
		var feet: Vector2 = altar.get_meta("feet")
		eq(feet, LAYOUT.ALTAR_FEET)
		ok(_standing_on(rects, feet), "the altar stands on FloorHall")
		ok(absf(feet.x - exit.position.x) < 160.0, "the forge altar stands beside the ending door")
		ok(feet.x > LAYOUT.ARENA_X1 - 64.0, "the altar belongs to the ending, not the arena")
		var altar_tex := load(ChapterLayout.DECOR["altar"]) as Texture2D
		var strips := 0
		var crown_broken := false
		for strip in altar.get_children():
			if strip is Sprite2D and (strip as Sprite2D).texture == altar_tex:
				strips += 1
				if (strip as Sprite2D).position.y > 0.0:
					crown_broken = true
		ok(strips >= 8, "the altar plate is sliced into ruin strips (%d)" % strips)
		ok(crown_broken, "the altar's crown crumbles instead of a ruler edge")


func test_enemies_sit_where_they_are_placed() -> void:
	var host := _build()
	var rects := _rects(host)
	var enemies := host.get_node("Enemies")
	var expected := 0
	for e in LAYOUT.ENEMIES:
		var path: String = ChapterLayout.ENEMY_SCENES.get(String(e[1]), "")
		var available := path != "" and ResourceLoader.exists(path)
		var enemy := enemies.get_node_or_null(String(e[0])) as Node2D
		if not available:
			ok(enemy == null, "%s is skipped while its scene is missing" % e[0])
			continue
		expected += 1
		ok(enemy != null, "%s spawned" % e[0])
		if enemy == null:
			continue
		eq(enemy.position, e[2] as Vector2, "%s sits at its authored point" % e[0])
		if enemy is GhostEnemy:
			ok(not _standing_on(rects, enemy.position, 8.0), "%s floats free of the floor" % e[0])
		elif String(e[1]) == "fire_skull":
			ok(not LevelSanity.inside_solid(rects, enemy.position), "%s hovers in open air" % e[0])
		else:
			ok(_standing_on(rects, enemy.position, 4.0), "%s stands on a platform" % e[0])
	eq(enemies.get_child_count(), expected, "every available enemy is placed, nothing else")
	# the boss and the entry-corridor fights do not share a room
	for e in LAYOUT.ENEMIES:
		var pos: Vector2 = e[2]
		if String(e[1]) == "nightmare_boss":
			ok(pos.x > LAYOUT.ARENA_X0 and pos.x < LAYOUT.ARENA_X1, "the boss is inside the arena")
		else:
			ok(pos.x < LAYOUT.ARENA_X0, "%s stays out of the boss arena" % e[0])


func test_slain_nightmare_does_not_respawn_and_ending_stays_open() -> void:
	SaveData.mark_flag("nightmare_dead")
	var host := _build()
	ok(host.get_node_or_null("Enemies/Nightmare") == null)
	ok(not (host.get_node("Props/Exit") as LevelExit).is_locked())


func test_room_is_sealed_and_reads_as_a_forge() -> void:
	var host := _build()
	var platforms := host.get_node("Platforms")
	var ceiling := platforms.get_node_or_null("Ceiling") as SolidPlatform
	ok(ceiling != null, "the forge core is roofed")
	if ceiling != null:
		almost(ceiling.position.y, LAYOUT.CEILING_Y, 0.01)
		almost(ceiling.size.x, float(LAYOUT.EAST_LIMIT), 0.01, "roof spans the whole level")
	var wall_r := platforms.get_node_or_null("WallRight") as SolidPlatform
	ok(wall_r != null and absf(wall_r.position.x - float(LAYOUT.EAST_LIMIT)) <= 0.01, "east wall at the camera limit")
	for p in _solids(host):
		ok(p.position != Vector2.ZERO or String(p.name) == "FloorEntry", "%s keeps its position" % p.name)
		ok(_right(p) <= float(LAYOUT.EAST_LIMIT) + 16.0, "%s stays inside the east limit" % p.name)
		if String(p.name) != "SlagBed":
			ok(p.position.y <= 320.0, "%s is not walkable ground below the floor line" % p.name)
		var footing := String(p.name).begins_with("SlagStone") or String(p.name).begins_with("Perch")
		eq(p.tone, LAYOUT.STONE_TONE if footing else LAYOUT.TONE, "%s is pressed into amber" % p.name)
		ok(p.tone.r > p.tone.g and p.tone.g > p.tone.b, "%s tone is warm (r > g > b)" % p.name)
	var mood := host.get_node_or_null("MoodTint") as CanvasModulate
	ok(mood != null)
	if mood != null:
		ok(mood.color.r > mood.color.b, "forge mood is amber, not the undercroft's teal")
	ok(host.get_node_or_null("IndoorZone") is AtmosphereZone, "whole level is an indoor zone")
	ok(host.get_node_or_null("Waymarks/Sign_炉心") != null, "entry sign says 炉心")
	ok(host.get_node_or_null("ParallaxBackdrop") is CanvasLayer, "themed backdrop built")
	var props := host.get_node("Props")
	var steles := 0
	for child in props.get_children():
		if child is LoreStele:
			steles += 1
			ok(String((child as LoreStele).lore_title).begins_with("炉心铭"), "%s is a forge-core inscription" % child.name)
	eq(steles, 2, "two inscriptions")
	# torches every screen, none missing from the arena; grounded decor never floats
	var decor := host.get_node("Decor")
	var torches := 0
	var arena_torches := 0
	for node in decor.get_children():
		if node is TorchLight:
			torches += 1
			if node.position.x > LAYOUT.ARENA_X0 and node.position.x < LAYOUT.ARENA_X1:
				arena_torches += 1
	ok(torches >= 6, "enough wall torches (%d)" % torches)
	ok(arena_torches >= 3, "the arena is lit by wall torches (%d)" % arena_torches)
	var problems := LevelSanity.check(host)
	for p in problems:
		ok(false, p)
	ok(problems.is_empty(), "LevelSanity clean on the bare host (%d problems)" % problems.size())
