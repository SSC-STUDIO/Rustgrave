extends TestCase

func _build(id: String) -> Node:
	var packed := load(GameContext.LEVELS[id]) as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await flush(2)
	Director.abort()
	return level

func test_probe_level06_branch_reachable() -> void:
	var level := await _build("level06")
	var spawn := Vector2(96, 300)
	var reached := LevelSanity.reachable_segments(level, spawn, true)
	var stone := level.get_node_or_null("Platforms/TreeTopStone") as SolidPlatform
	var on_stone := false
	for seg in reached:
		if seg.owner_name == "TreeTopStone":
			on_stone = true
	print("L06 tree-top stone reachable from spawn (allow_hook=true): ", on_stone)
	var anchor := level.get_node_or_null("Hooks/HookTreeTop") as Node2D
	print("L06 anchor pos=", anchor.global_position if anchor != null else "NULL")
	print("L06 stone pos=", stone.global_position if stone != null else "NULL", " size=", stone.size if stone != null else "NULL")
	level.free()

func test_probe_level07_branch_reachable() -> void:
	var level := await _build("level07")
	var spawn := Vector2(96, 300)
	var reached := LevelSanity.reachable_segments(level, spawn, true)
	var nook := level.get_node_or_null("Platforms/NookDeck") as SolidPlatform
	var on_nook := false
	for seg in reached:
		if seg.owner_name == "NookDeck":
			on_nook = true
	print("L07 NookDeck reachable from spawn (allow_hook=true): ", on_nook)
	var anchor := level.get_node_or_null("Hooks/HookUpper") as Node2D
	var pickup := level.get_node_or_null("Pickups/TetherCoreNook") as Node2D
	print("L07 anchor pos=", anchor.global_position if anchor != null else "NULL")
	print("L07 pickup pos=", pickup.global_position if pickup != null else "NULL")
	print("L07 nook pos=", nook.global_position if nook != null else "NULL", " size=", nook.size if nook != null else "NULL")
	level.free()
