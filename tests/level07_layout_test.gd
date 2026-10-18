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
	eq(host.get_node("Enemies").get_child_count(), 10)
	var exit := host.get_node("Props/Exit") as LevelExit
	eq(exit.position, LAYOUT.EXIT_POS)
	eq(exit.target_scene, GameContext.LEVELS["level07b"], "the tower base leads to the bell foundry")
	eq(exit.spawn, ChapterLayout.entry_spawn_of("level08"))

func test_four_lifts_have_clear_shafts_and_boardable_ends() -> void:
	var host := _build()
	var tops := LevelSanity.top_segments(host)
	var boards := ["Floor", "GalleryA", "GalleryB", "GalleryC", "Summit", "GalleryD", "GalleryE"]
	var lands := ["GalleryA", "GalleryB", "GalleryC", "Summit", "GalleryD", "GalleryE", "Crown"]
	eq(LAYOUT.LIFTS.size(), boards.size(), "one lift per hop up the tower")
	for i in LAYOUT.LIFTS.size():
		var lift := host.get_node("Platforms/" + String(LAYOUT.LIFTS[i][0])) as MovingPlatform
		ok(lift.travel.y <= -160.0 and lift.travel.x == 0.0, "lift %s climbs straight up" % lift.name)
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
		ok(LevelSanity._can_hop(board, a), "boards from lower landing (%s)" % lift.name)
		ok(LevelSanity._can_hop(b, land), "steps onto upper landing (%s)" % lift.name)


## 竖高扩章：0 → -1280 总高 1600；旧塔顶之上再叠两层画廊 + 新塔顶 Crown，
## 塔顶出口/第三巢搬到 Crown，井底补第二盏壁炬。
func test_vertical_expansion_to_1600px_and_crown_exit() -> void:
	var host := _build()
	eq(LAYOUT.EAST_LIMIT, 1280, "the tower keeps its width")
	eq(int(320.0 - LAYOUT.TOP_Y), 1600, "tower height is now 1600px")
	eq(LAYOUT.CEILING_Y, -1440.0)
	eq(LAYOUT.EXIT_POS.y, LAYOUT.TOP_Y, "the slag-well door sits on the new crown")
	var tops := LevelSanity.top_segments(host)
	var names: Array[String] = []
	for seg in tops:
		names.append(seg.owner_name)
	ok(names.has("GalleryD") and names.has("GalleryE") and names.has("Crown"),
			"two new galleries and a new crown were added above the old summit")
	var exit := host.get_node("Props/Exit") as LevelExit
	ok(exit != null and LevelSanity.is_reachable(host, LAYOUT.ENTRY_SPAWN, LevelSanity.feet_of(exit), false),
			"the crown exit is reachable on the main route (no hookshot)")
	var crown_nest := host.get_node_or_null("Props/EmberNestCrown") as EmberNest
	ok(crown_nest != null, "the new crown carries the pre-exit checkpoint")
	if crown_nest != null:
		ok(crown_nest.position.x < exit.position.x, "checkpoint before the door")
		ok(LevelSanity.is_reachable(host, LAYOUT.ENTRY_SPAWN, LevelSanity.feet_of(crown_nest), false),
				"crown checkpoint reachable on the main route")
	# 井底可见度：入口与东侧各一盏壁炬（Lead 的视觉修复）。
	var decor := host.get_node_or_null("Decor") as Node2D
	var bottom_torches := 0
	if decor != null:
		for child in decor.get_children():
			# torch() 节点原点在墙板中心；墙板底边 = position.y + 96。
			if child is TorchLight and absf((child as Node2D).position.y + 96.0 - 320.0) < 0.01:
				bottom_torches += 1
	ok(bottom_torches >= 2, "the well bottom carries at least two wall torches (%d)" % bottom_torches)

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


func test_hookshot_nook_branch_is_off_main_route() -> void:
	var host := _build()
	var nook := host.get_node("Platforms/NookDeck") as SolidPlatform
	var anchor := host.get_node("Hooks/HookUpper") as HookAnchor
	var stele := host.get_node("Props/SteleNook") as LoreStele
	ok(nook != null and anchor != null and stele != null, "nook deck, hook anchor and branch stele exist")
	if nook == null or anchor == null or stele == null:
		return
	# 锚点在壁龛正上方、Crown（-1280）起跳在 250px 索距内；落台在锚点下方 40px。
	ok(anchor.position.y < nook.position.y, "anchor hangs above the nook ledge")
	ok(nook.position.y - anchor.position.y <= LevelSanity.HOOK_LAND_BELOW, "landing ledge is under the anchor")
	var crown_y := float(LAYOUT.TOP_Y)
	ok(anchor.position.distance_to(Vector2(anchor.position.x, crown_y - 48.0)) <= LevelSanity.HOOK_REACH,
			"anchor is within hookshot reach of the new crown deck")
	ok(nook.position.y < crown_y, "the nook hides above every walkable deck")
	# 支路用钩锁可达（有钩锁时），但主路线不依赖它：allow_hook=false 时不可达。
	var with_hook := LevelSanity.reachable_segments(host, LAYOUT.ENTRY_SPAWN, true)
	var nook_reached_with_hook := false
	for seg in with_hook:
		if seg.owner_name == "NookDeck":
			nook_reached_with_hook = true
	ok(nook_reached_with_hook, "NookDeck reachable when the hookshot is available")
	var no_hook := LevelSanity.reachable_segments(host, LAYOUT.ENTRY_SPAWN, false)
	var nook_reached_without_hook := false
	for seg in no_hook:
		if seg.owner_name == "NookDeck":
			nook_reached_without_hook = true
	ok(not nook_reached_without_hook,
			"NookDeck is NOT required: main route (allow_hook=false) cannot reach it")
