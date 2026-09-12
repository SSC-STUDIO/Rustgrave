extends TestCase
const LAYOUT := preload("res://scripts/levels/chapters/level07_layout.gd")

func setup() -> void:
	SaveData.flags.clear()

func teardown() -> void:
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	Director.abort()

func _build() -> Node2D:
	var host := Node2D.new()
	host.scene_file_path = GameContext.LEVELS["level07"]
	host.add_to_group("game_world")
	add_child(host)
	var layout := LAYOUT.new()
	add_child(layout)
	layout.build(host)
	return host

func test_tower_main_route_and_checkpoints_need_no_optional_ability() -> void:
	var host := _build()
	eq(LevelSanity.check(host), [] as Array[String])
	for node in host.get_node("Props").get_children():
		if node is EmberNest or node is LevelExit or node is PressurePlate:
			ok(LevelSanity.is_reachable(host, LAYOUT.ENTRY_SPAWN, LevelSanity.feet_of(node), false), str(node.name))
	eq(host.get_node("Enemies").get_child_count(), 8)
	var exit := host.get_node("Props/Exit") as LevelExit
	eq(exit.position, LAYOUT.EXIT_POS)
	eq(exit.target_scene, GameContext.LEVELS["level08"])
	eq(exit.spawn, ChapterLayout.entry_spawn_of("level08"))

func test_four_lifts_have_clear_shafts_and_boardable_ends() -> void:
	var host := _build()
	var tops := LevelSanity.top_segments(host)
	var boards := ["Floor", "GalleryA", "GalleryB", "GalleryC"]
	var lands := ["GalleryA", "GalleryB", "GalleryC", "Summit"]
	for i in 4:
		var lift := host.get_node("Platforms/" + String(LAYOUT.LIFTS[i][0])) as MovingPlatform
		eq(lift.travel, Vector2(0, -240))
		var swept := Rect2(lift.end_position() + Vector2(0, -32), Vector2(lift.width, 288))
		for p in host.get_node("Platforms").get_children():
			if p is SolidPlatform and p.name != "Floor":
				ok(not swept.intersects(Rect2(p.position, p.size)), "%s rider clears %s" % [lift.name, p.name])
		var board: LevelSanity.TopSeg
		var land: LevelSanity.TopSeg
		var a: LevelSanity.TopSeg
		var b: LevelSanity.TopSeg
		for top in tops:
			if top.owner_name == boards[i]: board = top
			if top.owner_name == lands[i]: land = top
			if top.owner_name == str(lift.name) + "@start": a = top
			if top.owner_name == str(lift.name) + "@end": b = top
		ok(LevelSanity._can_hop(board, a), "boards from lower landing")
		ok(LevelSanity._can_hop(b, land), "steps onto upper landing")

func test_middle_checkpoint_is_safe_after_restore() -> void:
	var host := _build()
	var player := await spawn_player(host, Vector2(544, -160))
	await flush(360)
	eq(player.health.current, player.health.max_hp, "lower and upper enemies cannot attack the restored checkpoint")
	for name_ in ["Ghost1", "Ghost2"]:
		var ghost := host.get_node("Enemies/" + name_) as GhostEnemy
		eq(ghost.state(), GhostEnemy.State.DORMANT, name_ + " waits on its authored combat floor")

func test_entry_checkpoint_does_not_wake_the_first_ambush() -> void:
	var host := _build()
	var player := await spawn_player(host, Vector2(176, 320))
	await flush(360)
	eq(player.health.current, player.health.max_hp, "entry nest permits a quiet rest")
	var skeleton = host.get_node("Enemies/Skeleton1")
	eq(skeleton.state(), skeleton.State.BURIED)
	player.position.x = 240
	ok(await wait_until(func() -> bool: return skeleton.state() != skeleton.State.BURIED), "walking toward the lift still wakes the ambush")

func test_lift_carries_player_up_and_middle_plate_opens_gate() -> void:
	var host := _build()
	for enemy in host.get_node("Enemies").get_children(): enemy.set_physics_process(false)
	var lift := host.get_node("Platforms/LiftA") as MovingPlatform
	lift.set_physics_process(false)
	var player := await spawn_player(host, Vector2(420, 270))
	ok(player.is_on_floor())
	lift.set_physics_process(true)
	await flush(90)
	ok(player.position.y < 270, "rider rises with the first lift")
	player.position = Vector2(732, -192)
	player.velocity = Vector2.ZERO
	var door := host.get_node("Props/BellGateDoor") as ArenaDoor
	ok(await wait_until(func() -> bool: return door.is_open), "normal landing activates the middle plate")
