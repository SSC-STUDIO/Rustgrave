extends TestCase
## Multi-level & multi-room routing: presentation shell picks the pending level,
## save paths are namespaced per stage + room, legacy Level01 keeps bare paths,
## and Continue returns to the saved stage/room.


func teardown() -> void:
	GameContext.pending_world_path = GameContext.WORLD_PATH
	SaveData.data = {}
	SaveData.consumed.clear()
	SaveData.lit_nests.clear()


func test_levels_are_registered_and_routed_through_the_presentation() -> void:
	ok(GameContext.is_world_scene(GameContext.WORLD_PATH))
	ok(GameContext.is_world_scene(GameContext.LEGACY_WORLD_PATH))
	ok(GameContext.is_world_scene(GameContext.LEVEL02_PATH))
	ok(not GameContext.is_world_scene("res://scenes/ui/TitleScreen.tscn"))
	ok(ResourceLoader.exists(GameContext.WORLD_PATH), "Stage01 scene exists on disk")
	ok(ResourceLoader.exists(String(GameContext.LEVELS["stage02"])), "Stage02 scene exists on disk")
	eq(GameContext.route_scene(String(GameContext.LEVELS["stage02"])), GameContext.PRESENTATION_PATH)
	eq(GameContext.pending_world_path, String(GameContext.LEVELS["stage02"]), "routing remembers pending level")
	eq(GameContext.route_scene(GameContext.WORLD_PATH), GameContext.PRESENTATION_PATH)
	eq(GameContext.pending_world_path, GameContext.WORLD_PATH)
	eq(GameContext.route_scene("res://scenes/ui/TitleScreen.tscn"), "res://scenes/ui/TitleScreen.tscn")
	eq(GameContext.pending_world_path, GameContext.WORLD_PATH, "non-level routes leave pending level alone")


func test_level_ids_keep_legacy_level01_bare_and_namespace_stages() -> void:
	eq(GameContext.level_id(GameContext.LEGACY_WORLD_PATH), "", "legacy Level01 keeps bare paths")
	eq(GameContext.level_id(GameContext.WORLD_PATH), "stage01", "Stage01 uses stage01 namespace")
	eq(GameContext.level_id(GameContext.LEVEL02_PATH), "level02")
	eq(GameContext.level_id("res://nowhere.tscn"), "")


func test_campaign_registry_is_fourteen_nodes_and_internally_consistent() -> void:
	eq(GameContext.LEVEL_ORDER.size(), 14, "campaign has 14 tree nodes")
	eq(GameContext.LEVEL_ORDER[0], "stage01")
	eq(GameContext.LEVEL_ORDER[-1], "stage08_true", "stage08_true is the hidden True Core finale")
	var seen := {}
	for id in GameContext.LEVEL_ORDER:
		ok(not seen.has(id), "%s appears once" % id)
		seen[id] = true
		ok(GameContext.LEVELS.has(id), "%s has a scene" % id)
		ok(ResourceLoader.exists(String(GameContext.LEVELS[id])), "%s scene exists on disk" % id)
		ok(GameContext.STAGE_SCRIPTS.has(id), "%s has a StageRoomBuilder script" % id)
		ok(ResourceLoader.exists(String(GameContext.STAGE_SCRIPTS[id])), "%s builder exists" % id)
		eq(GameContext.level_id(String(GameContext.LEVELS[id])), id, "%s save namespace" % id)

	var main_chain := ["stage01", "stage02", "stage03", "stage04", "stage04b", "stage05", "stage06", "stage07"]
	for i in main_chain.size():
		var expected: String = "" if i + 1 >= main_chain.size() else String(main_chain[i + 1])
		eq(GameContext.next_level_id(main_chain[i]), expected, "main chain next after %s" % main_chain[i])


func _world(scene_path: String, world_name: String) -> Node2D:
	var world := Node2D.new()
	world.name = world_name
	world.scene_file_path = scene_path
	world.add_to_group("game_world")
	add_child(world)
	var props := Node2D.new()
	props.name = "Props"
	world.add_child(props)
	var thing := Node2D.new()
	thing.name = "EmberNest"
	props.add_child(thing)
	return world


func test_save_paths_are_namespaced_across_stages_and_legacy_level01() -> void:
	var world2 := _world(String(GameContext.LEVELS["stage02"]), "Stage02_Conduit")
	var nest2 := world2.get_node("Props/EmberNest")
	eq(SaveData.persist_path(nest2), "stage02:Props/EmberNest")
	eq(SaveData.resolve_saved_node(world2, "stage02:Props/EmberNest"), nest2)
	ok(SaveData.resolve_saved_node(world2, "Props/EmberNest") == null)
	SaveData.mark_consumed(String(nest2.get_path()))
	ok(SaveData.is_consumed("stage02:Props/EmberNest"))
	world2.free()

	var world_legacy := _world(GameContext.LEGACY_WORLD_PATH, "Level01_Static")
	var nest1 := world_legacy.get_node("Props/EmberNest")
	eq(SaveData.persist_path(nest1), "Props/EmberNest", "legacy Level01 stays bare")
	eq(SaveData.resolve_saved_node(world_legacy, "Props/EmberNest"), nest1)
	ok(not SaveData.is_consumed(String(nest1.get_path())))
	world_legacy.free()


func test_saved_scene_falls_back_to_world_path_and_records_arrival() -> void:
	var stage2 := String(GameContext.LEVELS["stage02"])
	SaveData.data = {"meta": {"scene": stage2}}
	eq(SaveData.saved_scene(), stage2)
	SaveData.data = {"meta": {"scene": "res://scenes/levels/Deleted.tscn"}}
	eq(SaveData.saved_scene(), GameContext.WORLD_PATH)
	SaveData.data = {}
	eq(SaveContext_fallback(), GameContext.WORLD_PATH)

	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	var previous_path := SaveData.save_path
	SaveData.save_path = "user://test_level_routing.cfg"
	var entry := Vector2(88.0, 320.0)
	var saved := SaveData.save_game(stage2, player, entry)
	ok(saved)
	eq(SaveData.data["meta"]["scene"], stage2)
	eq(SaveData.data["player"]["pos"], entry)
	ok(SaveData.load_game())
	eq(SaveData.saved_scene(), stage2)
	SaveData.delete_save()
	SaveData.save_path = previous_path
	arena.free()


func SaveContext_fallback() -> String:
	return SaveData.saved_scene()
