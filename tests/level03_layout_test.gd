extends TestCase

const LAYOUT := preload("res://scripts/levels/chapters/level03_layout.gd")

func teardown() -> void:
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)

func _build() -> Node2D:
	var host := Node2D.new()
	host.scene_file_path = GameContext.LEVELS["level03"]
	host.add_to_group("game_world")
	add_child(host)
	var layout := LAYOUT.new()
	add_child(layout)
	layout.build(host)
	return host

func test_rooftop_plate_and_main_route_work_without_optional_cores() -> void:
	var host := _build()
	eq(LevelSanity.check(host), [] as Array[String])
	var plate := host.get_node("Props/GatePlate") as PressurePlate
	var door := host.get_node("Props/GateDoor") as ArenaDoor
	ok(plate.activated.is_connected(door.open_door))
	ok(LevelSanity.is_reachable(host, LAYOUT.ENTRY_SPAWN, LevelSanity.feet_of(plate), false))
	var player := await spawn_player(host, Vector2(plate.position.x + 12, 200))
	ok(await wait_until(func() -> bool: return door.is_open), "landing on the roof presses the plate")
	for name_ in ["EmberNestStreet", "EmberNestPlaza", "Exit"]:
		var goal := host.get_node("Props/" + name_)
		ok(LevelSanity.is_reachable(host, LAYOUT.ENTRY_SPAWN, LevelSanity.feet_of(goal), false), name_)
	ok(not player.inventory.has_ability(AbilityIds.HOOKSHOT_TETHER))

func test_tower_reward_is_optional_and_exit_reaches_the_cathedral() -> void:
	var host := _build()
	var exit := host.get_node("Props/Exit") as LevelExit
	eq(exit.target_scene, GameContext.LEVELS["level04"])
	eq(exit.spawn, ChapterLayout.entry_spawn_of("level04"))
	eq(exit.position, LAYOUT.EXIT_POS)
	eq(host.get_node("Enemies").get_child_count(), LAYOUT.ENEMIES.size())
	ok(not LevelSanity.is_reachable(host, LAYOUT.ENTRY_SPAWN, Vector2(1856, 160), false), "tower reward needs the optional hook")
	ok(LevelSanity.is_reachable(host, LAYOUT.ENTRY_SPAWN, Vector2(1856, 160)), "hook makes the reward reachable")
