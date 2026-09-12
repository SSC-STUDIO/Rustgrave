extends TestCase
## Scene integration fixtures may position players directly. The separate campaign
## acceptance driver uses only input and proves the actual route is playable.

func setup() -> void:
	SaveData.delete_save()

func teardown() -> void:
	SaveData.delete_save()
	Director.abort()
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)

func _load_level(id: String) -> Node2D:
	var level := (load(GameContext.LEVELS[id]) as PackedScene).instantiate() as Node2D
	add_child(level)
	await flush(2)
	Director.abort()
	for enemy in level.get_node("Enemies").get_children(): enemy.set_physics_process(false)
	return level

func _player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player

func _exit_of(level: Node) -> LevelExit:
	for node in level.get_node("Props").get_children():
		if node is LevelExit: return node
	return null

func test_every_chapter_exit_saves_the_next_arrival_and_keeps_heat_forge() -> void:
	var level := await _load_level("level02")
	_player().inventory.add_to_pouch(AbilityCatalog.kiln_core())
	_player().inventory.insert_into_socket(0)
	for n in range(2, 10):
		var next_id := "level%02d" % (n + 1)
		var exit := _exit_of(level)
		exit.interact(_player())
		await flush(1)
		Director.abort()
		ok(await wait_until(func() -> bool: return SaveData.saved_scene() == GameContext.LEVELS[next_id]), "exit saves " + next_id)
		ok(SaveData.has_flag(exit.flag_id), "exit records its chapter flag")
		level.free()
		await flush(1)
		level = await _load_level(next_id)
		ok(_player().position.distance_to(ChapterLayout.entry_spawn_of(next_id)) < 12, "next scene uses arrival point")
		ok(_player().inventory.has_ability(AbilityIds.HEAT_FORGE), "heat forge survives transition")
		eq(_player().health.current, _player().health.max_hp)
		ok(_player()._resolve_lit_nest() == null, "earlier chapter checkpoint is not a respawn here")

func test_each_chapter_restores_its_checkpoint_and_open_mechanisms() -> void:
	for n in range(3, 11):
		SaveData.delete_save()
		var id := "level%02d" % n
		var level := await _load_level(id)
		var player := _player()
		player.inventory.add_to_pouch(AbilityCatalog.kiln_core())
		player.inventory.insert_into_socket(0)
		var nest: EmberNest
		var opened: Array[String] = []
		var melted: Array[String] = []
		for node in level.get_node("Props").get_children():
			if node is EmberNest and nest == null: nest = node
			if node is ArenaDoor:
				node.open_door()
				opened.append(str(node.name))
			if node is RustyGate:
				melted.append(str(node.name))
				node.interact(player)
		await flush(2)
		player.position = LevelSanity.feet_of(nest) - Vector2(6, 2)
		var checkpoint := player.position
		nest.interact(player)
		var path := SaveData.persist_path(nest)
		ok(path.begins_with(id + ":"))
		level.free()
		await flush(1)
		level = await _load_level(id)
		ok(_player().position.distance_to(checkpoint) < 12, "continue restores " + id)
		eq(SaveData.persist_path(_player()._resolve_lit_nest()), path)
		for name_ in opened: ok(level.get_node("Props/" + name_).is_open, "opened gate stays open")
		for name_ in melted: ok(level.get_node_or_null("Props/" + name_) == null, "melted gate stays absent")
		SaveData.respawn(GameContext.LEVELS[id], checkpoint)
		level.free()
		await flush(2)
		level = await _load_level(id)
		eq(_player().health.current, _player().health.max_hp)
		ok(_player().position.distance_to(checkpoint) < 12, "death arrival consumes pending spawn")
		level.free()
		await flush(1)

func test_nightmare_death_survives_reload_and_final_exit_saves_completion() -> void:
	var level := await _load_level("level10")
	var player := _player()
	var nest := level.get_node("Props/EmberNestArena") as EmberNest
	player.position = Vector2(880, 320)
	nest.interact(player)
	var boss = level.get_node("Enemies/Nightmare")
	var exit := _exit_of(level)
	ok(exit.is_locked())
	boss.health.take_damage(99, player)
	await flush(2)
	SaveData.flags.clear()
	level.free()
	await flush(1)
	level = await _load_level("level10")
	ok(level.get_node_or_null("Enemies/Nightmare") == null, "disk flag prevents boss respawn")
	exit = _exit_of(level)
	ok(not exit.is_locked())
	exit.interact(_player())
	await flush(1)
	Director.abort()
	await flush(3)
	ok(SaveData.load_game())
	ok(SaveData.has_flag("game_complete"))
	ok(SaveData.has_flag("nightmare_dead"))
	ok(await wait_until(func() -> bool:
		return not Director.is_fading() and Director.last_fade_target == "res://scenes/ui/TitleScreen.tscn"
	), "finale fade completes at the title")
