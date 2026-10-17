extends TestCase
## Phase-2 route audit across all chapters (pure geometry via LevelSanity, no input):
##   · respawn soft-locks: from every Ember Nest the exit / forge heart is still reachable
##   · every placed Rust-Core pickup can be reached from the spawn (grapple allowed)
##   · every chapter has a checkpoint; checkpoint spacing is printed as an audit line
## Chapters 3+ must be finishable without the grapple (same rule as level_sanity_test).


func setup() -> void:
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.pending_spawn = Vector2.INF


func teardown() -> void:
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.pending_spawn = Vector2.INF
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	Director.abort()


func _load_level(path: String) -> Node:
	var packed := load(path) as PackedScene
	ok(packed != null, "%s loads" % path)
	if packed == null:
		return null
	var level := packed.instantiate()
	add_child(level)
	await flush(2)
	Director.abort()
	return level


func test_no_respawn_soft_locks_and_cores_reachable() -> void:
	for id in GameContext.LEVELS.keys():
		var level := await _load_level(String(GameContext.LEVELS[id]))
		if level == null:
			continue
		var player := get_tree().get_first_node_in_group("player") as Node2D
		var spawn := player.global_position if player != null else Vector2.INF
		var allow_hook := not GameContext.LAYOUTS.has(id)
		var goals: Array[Node2D] = []
		var nests: Array[Node2D] = []
		var cores: Array[Node2D] = []
		for node in LevelSanity._descendants(level):
			if node is LevelExit or node is ForgeHeart:
				goals.append(node as Node2D)
			elif node is EmberNest:
				nests.append(node as Node2D)
			elif node is CorePickup:
				cores.append(node as Node2D)
		ok(not nests.is_empty(), "%s has at least one checkpoint" % id)
		for nest in nests:
			var feet := LevelSanity.feet_of(nest)
			for goal in goals:
				ok(LevelSanity.is_reachable(level, feet, LevelSanity.feet_of(goal), allow_hook),
						"%s: respawning at %s can still reach %s" % [id, nest.name, goal.name])
		for core in cores:
			var feet := LevelSanity.feet_of(core)
			ok(LevelSanity.is_reachable(level, spawn, feet, true) or _hook_near(level, feet),
					"%s: core %s can be reached" % [id, core.name])
		# Audit line: checkpoint spacing along the route (for the report, not a gate).
		var xs: Array[float] = [spawn.x]
		for nest in nests:
			xs.append(nest.global_position.x)
		for goal in goals:
			xs.append(goal.global_position.x)
		xs.sort()
		var widest := 0.0
		for i in range(1, xs.size()):
			widest = maxf(widest, xs[i] - xs[i - 1])
		print("[ROUTE AUDIT] %s nests=%d cores=%d goals=%d widest_gap_px=%d hook_allowed=%s" % [
				id, nests.size(), cores.size(), goals.size(), int(widest), str(allow_hook)])
		level.free()
		await flush(1)


func _hook_near(level: Node, point: Vector2) -> bool:
	for node in LevelSanity._descendants(level):
		if node is HookAnchor and (node as Node2D).global_position.distance_to(point) <= LevelSanity.PICKUP_HOOK_REACH:
			return true
	return false


func test_cathedral_has_a_checkpoint_past_the_choir_door() -> void:
	var level := await _load_level(String(GameContext.LEVELS["level04"]))
	if level == null:
		return
	var nest := level.get_node_or_null("Props/EmberNestChoir") as EmberNest
	ok(nest != null, "mid-nave checkpoint exists")
	if nest != null:
		var door := level.find_child("ChoirDoor", true, false) as Node2D
		ok(door != null, "choir door found")
		ok(door == null or nest.global_position.x > door.global_position.x, "it sits past the choir door")
		var player := get_tree().get_first_node_in_group("player") as Node2D
		ok(LevelSanity.is_reachable(level, player.global_position, LevelSanity.feet_of(nest), false), "reachable on foot")
	level.free()
	await flush(1)
