extends TestCase
## Geometry regression for route checks. Physics input checks live below separately.


func setup() -> void:
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.pending_spawn = Vector2.INF
	Director.abort()


func teardown() -> void:
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.pending_spawn = Vector2.INF
	Director.abort()
	Input.action_release("jump")
	Input.action_release("move_right")
	Input.action_release("move_left")


func _solid(host: Node2D, at: Vector2, size: Vector2) -> void:
	var p := SolidPlatform.new()
	p.position = at
	p.size = size
	host.add_child(p)


func test_a_long_floor_does_not_teleport_the_route_through_a_wall() -> void:
	var host := Node2D.new()
	add_child(host)
	_solid(host, Vector2(0, 320), Vector2(640, 80))
	_solid(host, Vector2(300, 120), Vector2(32, 200))
	ok(not LevelSanity.is_reachable(host, Vector2(96, 320), Vector2(480, 320), false),
			"a wall splits an otherwise continuous floor into disconnected regions")


## A solid that has its own walkable top is a step you stand on, not a wall:
## the floor beneath it must stay walkable, or a two-step climb reads as a wall
## and everything east of it becomes unreachable (level03's street to plaza).
func test_a_step_standing_on_the_floor_does_not_split_it() -> void:
	var host := Node2D.new()
	add_child(host)
	_solid(host, Vector2(0, 320), Vector2(640, 80))
	# Two stacked 32px steps on the floor, both with their own top at y=256.
	_solid(host, Vector2(300, 288), Vector2(48, 32))
	_solid(host, Vector2(300, 256), Vector2(48, 32))
	await flush(1)
	ok(LevelSanity.is_reachable(host, Vector2(96, 320), Vector2(560, 320), false),
			"the street under a step pair stays walkable, so the route runs through")


## The tutorial pit's lip→crossing jump must not be sealed by an overhead
## platform: level01 has no hook anchor near the pit, so the east half of the
## graveyard is only reachable on foot. Plat_440_236 was at x=420 and its
## underside sat right on the jump arc's apex.
func test_the_tutorial_pit_crossing_is_not_sealed_by_an_overhead_platform() -> void:
	var packed := load("res://scenes/levels/Level01_Static.tscn") as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await flush(2)
	var tops := LevelSanity.top_segments(level)
	var lip: LevelSanity.TopSeg = null
	var cross: LevelSanity.TopSeg = null
	for seg: LevelSanity.TopSeg in tops:
		if seg.owner_name == "PitLipLeft": lip = seg
		if seg.owner_name == "PitCross": cross = seg
	ok(lip != null and cross != null, "level01 still authors the pit lip and its crossing")
	if lip != null and cross != null:
		ok(TraversalModel.can_hop(lip, cross, LevelSanity._route_blockers(level)),
				"you can hop from the west lip onto the pit crossing without bonking")
	level.free()
	await flush(1)


func test_route_uses_real_gap_and_collision_envelope() -> void:
	var a := LevelSanity.TopSeg.new(0, 64, 320, "A")
	var b := LevelSanity.TopSeg.new(136, 200, 320, "B")
	ok(not LevelSanity._can_hop(a, b), "old 72px magic number is not a jump")
	var near := LevelSanity.TopSeg.new(80, 144, 320, "Near")
	var walls: Array[Rect2] = [Rect2(72, 0, 16, 400)]
	ok(not LevelSanity._can_hop(a, near, walls), "route graph checks body clearance along the arc")


func test_every_checkpoint_can_reach_its_chapter_exit_without_optional_abilities() -> void:
	for id in GameContext.LEVELS:
		var packed := load(String(GameContext.LEVELS[id])) as PackedScene
		var level := packed.instantiate()
		add_child(level)
		await flush(2)
		Director.abort()
		var goals: Array[Vector2] = []
		for node in LevelSanity._descendants(level):
			if node is LevelExit or node is ForgeHeart:
				goals.append(LevelSanity.feet_of(node))
			elif node is RoomGate:
				var gp := (node as RoomGate).walkable_goal_point()
				if gp != Vector2.INF:
					goals.append(gp)
		for nest in get_tree().get_nodes_in_group("ember_nests"):
			var from := LevelSanity.feet_of(nest)
			var reached := LevelSanity.reachable_segments(level, from, false)
			var furthest := -INF
			for seg in reached:
				furthest = maxf(furthest, seg.x1)
			for goal in goals:
				var found := false
				for seg in reached:
					if goal.x >= seg.x0 - 4 and goal.x <= seg.x1 + 4 and absf(goal.y - seg.y) <= 8:
						found = true
				ok(found, "%s/%s can reach exit %s; frontier %.0f" % [id, nest.name, goal, furthest])
		level.free()
		await flush(1)
