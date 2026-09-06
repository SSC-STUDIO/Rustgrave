extends TestCase
## Every registered level passes LevelSanity: nothing floats, nothing is
## buried, nothing overlaps, and the exit / checkpoints are reachable.


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


## RUSTGRAVE_LEVEL_FILTER=level05 (environment) restricts both tests to one level,
## so concurrent level authors only see their own problems.
func _level_ids() -> Array:
	var only := OS.get_environment("RUSTGRAVE_LEVEL_FILTER")
	if only != "" and GameContext.LEVELS.has(only):
		return [only]
	return GameContext.LEVELS.keys()


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


func _spawn_of(level: Node) -> Vector2:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	return player.global_position if player != null else Vector2.INF


func _camera_limits(level: Node) -> Rect2:
	var cam := get_tree().get_first_node_in_group("game_camera") as Camera2D
	if cam == null:
		return Rect2()
	return Rect2(Vector2(cam.limit_left, cam.limit_top), Vector2(cam.limit_right - cam.limit_left, cam.limit_bottom - cam.limit_top))


func test_every_registered_level_is_sane() -> void:
	for id in _level_ids():
		var path: String = GameContext.LEVELS[id]
		var level := await _load_level(path)
		if level == null:
			continue
		var problems := LevelSanity.check(level, _camera_limits(level))
		for p in problems:
			ok(false, "%s: %s" % [id, p])
		ok(problems.is_empty(), "%s: LevelSanity clean (%d problems)" % [id, problems.size()])
		level.free()
		await flush(1)


func test_exit_and_checkpoints_are_reachable_from_spawn() -> void:
	for id in _level_ids():
		var path: String = GameContext.LEVELS[id]
		var level := await _load_level(path)
		if level == null:
			continue
		var spawn := _spawn_of(level)
		ok(spawn != Vector2.INF, "%s spawns a knight" % id)
		for nest in get_tree().get_nodes_in_group("ember_nests"):
			var feet := LevelSanity.feet_of(nest)
			ok(LevelSanity.is_reachable(level, spawn, feet), "%s: nest %s is reachable from spawn" % [id, nest.name])
		var goals: Array[Node2D] = []
		for node in LevelSanity._descendants(level):
			if node is LevelExit or node is ForgeHeart:
				goals.append(node as Node2D)
		ok(not goals.is_empty(), "%s has an exit or a forge heart" % id)
		for goal in goals:
			ok(LevelSanity.is_reachable(level, spawn, LevelSanity.feet_of(goal)), "%s: %s is reachable from spawn" % [id, goal.name])
		level.free()
		await flush(1)
