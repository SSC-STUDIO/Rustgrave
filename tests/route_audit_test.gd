extends TestCase
## Phase-2 route audit across all chapters (pure geometry via LevelSanity, no input):
##   · respawn soft-locks: from every Ember Nest / room checkpoint the exit / room gate / forge heart is still reachable
##   · every placed Rust-Core pickup can be reached from the spawn (grapple allowed)
##   · every chapter has a checkpoint (EmberNest or StageLevel room checkpoint)
## Chapters must be finishable from checkpoints without soft-locks.


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
		var goal_pts: Array[Vector2] = []
		var nests: Array[Node2D] = []
		var cores: Array[Node2D] = []
		for node in LevelSanity._descendants(level):
			if node is LevelExit or node is ForgeHeart:
				goal_pts.append(LevelSanity.feet_of(node))
			elif node is RoomGate:
				var gp := (node as RoomGate).walkable_goal_point()
				if gp != Vector2.INF:
					goal_pts.append(gp)
			elif node is EmberNest:
				nests.append(node as Node2D)
			elif node is CorePickup:
				cores.append(node as Node2D)
		var has_room_ckpt := level is StageLevel and (level as StageLevel).room_checkpoint_spawn() != Vector2.INF
		ok(not nests.is_empty() or has_room_ckpt, "%s has at least one checkpoint" % id)
		for nest in nests:
			var feet := LevelSanity.feet_of(nest)
			for gp in goal_pts:
				ok(LevelSanity.is_reachable(level, feet, gp, allow_hook),
						"%s: respawning at %s can still reach %s" % [id, nest.name, str(gp)])
		if has_room_ckpt:
			var ckpt := (level as StageLevel).room_checkpoint_spawn()
			for gp in goal_pts:
				ok(LevelSanity.is_reachable(level, ckpt, gp, allow_hook),
						"%s: respawning at room checkpoint can reach %s" % [id, str(gp)])
		for core in cores:
			var feet := LevelSanity.feet_of(core)
			ok(LevelSanity.is_reachable(level, spawn, feet, true) or _hook_near(level, feet),
					"%s: core %s can be reached" % [id, core.name])
		var xs: Array[float] = [spawn.x]
		for nest in nests:
			xs.append(nest.global_position.x)
		for gp in goal_pts:
			xs.append(gp.x)
		xs.sort()
		var widest := 0.0
		for i in range(1, xs.size()):
			widest = maxf(widest, xs[i] - xs[i - 1])
		print("[ROUTE AUDIT] %s nests=%d cores=%d goals=%d widest_gap_px=%d hook_allowed=%s" % [
				id, nests.size(), cores.size(), goal_pts.size(), int(widest), str(allow_hook)])
		level.free()
		await flush(1)


func _hook_near(level: Node, point: Vector2) -> bool:
	for node in LevelSanity._descendants(level):
		if node is HookAnchor and (node as Node2D).global_position.distance_to(point) <= LevelSanity.PICKUP_HOOK_REACH:
			return true
	return false


func test_cathedral_has_a_checkpoint_past_the_choir_door() -> void:
	var level := await _load_level(String(GameContext.LEGACY_LEVELS["level04"]))
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
