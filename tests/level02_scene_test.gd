extends TestCase
## Level02 as a live scene: arrival spawn, namespaced checkpoints, and the
## indoor clock zone.

const SCENE := preload("res://scenes/levels/Level02_Undercroft.tscn")


func setup() -> void:
	SaveData.delete_save()
	SaveData.flags.clear()


func teardown() -> void:
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.pending_spawn = Vector2.INF
	SaveData.entering_from_checkpoint = false
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	Director.abort()


func test_arrival_from_the_forge_drops_the_knight_into_the_shaft() -> void:
	SaveData.pending_spawn = Level02Layout.ENTRY_SPAWN
	var level := SCENE.instantiate()
	add_child(level)
	await flush(2)
	var player := get_tree().get_first_node_in_group("player") as Player
	ok(player != null)
	ok(player.global_position.distance_to(Level02Layout.ENTRY_SPAWN) < 40.0,
			"knight starts in the shaft (%s)" % player.global_position)
	eq(WorldClock.zone, WorldClock.Zone.INDOORS, "the undercroft is indoors")
	ok(SaveData.has_flag("l2_wake"), "first entry plays the level title beat")
	ok(level.get_node_or_null("Props/EmberNestShaft") != null)
	ok(level.get_node_or_null("Platforms/LiftC") is MovingPlatform)
	ok(level.get_node_or_null("Enemies/Ghost1") is GhostEnemy)
	# Falling: the shaft has no floor until FloorA.
	for i in 90:
		await flush(1)
		if player.is_on_floor():
			break
	ok(player.is_on_floor(), "knight lands")
	almost(player.global_position.y, 320.0, 2.0, "lands on FloorA")


func _live_level() -> Node:
	SaveData.pending_spawn = Vector2.INF
	var level := SCENE.instantiate()
	add_child(level)
	await flush(2)
	Director.abort()  # skip the level-title beat so input/physics run
	return level


func test_ledge_plate_opens_the_hall_door() -> void:
	var level := await _live_level()
	var player := get_tree().get_first_node_in_group("player") as Player
	var door := level.get_node("Props/Door") as ArenaDoor
	var plate := level.get_node("Props/Plate") as PressurePlate
	ok(not door.is_open, "door starts shut")
	player.global_position = plate.global_position + Vector2(8, -8)
	player.velocity = Vector2.ZERO
	await flush(12)
	ok(door.is_open, "standing on the ledge plate opens the door")


func test_rusty_gate_needs_and_takes_heat_forge() -> void:
	var level := await _live_level()
	var player := get_tree().get_first_node_in_group("player") as Player
	var gate := level.get_node("Props/RustyGate") as RustyGate
	player.global_position = gate.global_position + Vector2(-24, 64)
	ok(not gate.get_prompt(player).begins_with("E"), "without the kiln core the gate only explains itself")
	player.inventory.add_to_pouch(AbilityCatalog.kiln_core())
	ok(player.inventory.insert_into_socket(0))
	ok(player.inventory.has_ability(AbilityIds.HEAT_FORGE))
	ok(gate.get_prompt(player).begins_with("E"), "with heat forge the gate offers to melt")
	gate.interact(player)
	await flush(2)
	ok(not is_instance_valid(gate) or gate.is_queued_for_deletion() or not gate.can_interact(player), "gate melts")
	ok(SaveData.is_consumed("level02:Props/RustyGate"), "melt is recorded under the level namespace")


func test_lift_carries_the_knight_across_pit_c() -> void:
	var level := await _live_level()
	var player := get_tree().get_first_node_in_group("player") as Player
	var lift := level.get_node("Platforms/LiftC") as MovingPlatform
	# Board at the lift's current deck position, then ride for a while.
	player.global_position = lift.global_position + Vector2(lift.width * 0.5, 0)
	player.velocity = Vector2.ZERO
	await flush(3)
	var start_x := player.global_position.x
	var lift_start := lift.global_position.x
	await flush(60)
	var lift_moved := lift.global_position.x - lift_start
	var player_moved := player.global_position.x - start_x
	ok(absf(lift_moved) > 8.0, "lift actually moved (%.1f)" % lift_moved)
	ok(absf(player_moved - lift_moved) < 6.0, "knight rides along (lift %.1f, knight %.1f)" % [lift_moved, player_moved])
	ok(player.is_on_floor(), "knight still on the deck")


func test_bell_door_ends_the_chapter() -> void:
	var level := await _live_level()
	var player := get_tree().get_first_node_in_group("player") as Player
	var exit := level.get_node("Props/BellDoor") as LevelExit
	eq(exit.target_scene, GameContext.LEVELS["level03"], "the bell door leads on to the rust town")
	player.global_position = exit.global_position + Vector2(-16, 0)
	var previous_path := SaveData.save_path
	SaveData.save_path = "user://test_level02_finale.cfg"
	exit.interact(player)
	await flush(2)
	ok(Director.playing, "door captions are playing")
	Director.abort()
	await flush(3)
	ok(SaveData.has_flag("undercroft_done"), "chapter flag is written")
	# last_fade_target is written when the fade-out completes, not when it starts.
	for i in 120:
		if Director.last_fade_target == GameContext.LEVELS["level03"]:
			break
		await flush(1)
	eq(Director.last_fade_target, GameContext.LEVELS["level03"], "the door fades into level03")
	ok(SaveData.load_game(), "the door left a save")
	eq(SaveData.saved_scene(), GameContext.LEVELS["level03"], "continue reopens level03 at its entry")
	eq(SaveData.data["player"]["pos"], ChapterLayout.entry_spawn_of("level03"))
	SaveData.delete_save()
	SaveData.save_path = previous_path


func test_level02_checkpoint_saves_under_its_own_namespace() -> void:
	SaveData.pending_spawn = Vector2.INF
	var level := SCENE.instantiate()
	add_child(level)
	await flush(2)
	var player := get_tree().get_first_node_in_group("player") as Player
	var nest := level.get_node("Props/EmberNestShaft") as EmberNest
	eq(SaveData.persist_path(nest), "level02:Props/EmberNestShaft")
	# A Level01 checkpoint recorded earlier must not be used as a spawn here.
	SaveData.lit_nests.clear()
	SaveData.lit_nests.append("Props/EmberNestEast")
	ok(player._resolve_lit_nest() == null, "Level01's nest does not resolve in the undercroft")
	nest.apply_persistent_state({"lit": true})
	SaveData.register_lit_nest(SaveData.persist_path(nest))
	eq(SaveData.last_lit_nest(), "level02:Props/EmberNestShaft")
	eq(player._resolve_lit_nest(), nest, "the shaft nest is the respawn point")
	ok(SaveData.lit_nests.has("Props/EmberNestEast"), "Level01's record is kept for when the knight returns")
