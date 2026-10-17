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
	for name_ in ["EmberNestStreet", "EmberNestPlaza", "EmberNestAlley", "Exit"]:
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


## 支路不能只是「多一枚核」：塔顶还有一块只有钩锁能读到的碑文，
## 主路线（allow_hook=false）够不到它，钩锁路线（allow_hook=true）够得到。
func test_tower_branch_rewards_world_information() -> void:
	var host := _build()
	var stele := host.get_node_or_null("Props/SteleTower") as LoreStele
	ok(stele != null, "tower branch carries a stele")
	if stele == null:
		return
	ok(String(stele.lore_title).begins_with("锈城纪事"), "tower stele is a town chronicle")
	ok(String(stele.lore_text) != "", "tower stele says something")
	var tops := LevelSanity.top_segments(host)
	ok(LevelSanity.standing_on(tops, LevelSanity.feet_of(stele)) != null, "stele stands on the tower roof")
	var feet := LevelSanity.feet_of(stele)
	ok(not LevelSanity.is_reachable(host, LAYOUT.ENTRY_SPAWN, feet, false),
			"main route cannot read the tower stele")
	ok(LevelSanity.is_reachable(host, LAYOUT.ENTRY_SPAWN, feet, true),
			"hookshot brings the knight to the tower stele")


## 巷口的第三巢：死后回程从约 1300px 缩到约 800px。巢位必须在附近的
## 碎铁犬冲锋圈、幽魂唤醒圈和喷吐者射程之外，否则「安全点」只是换个地方死。
func test_alley_checkpoint_is_safe_and_reachable() -> void:
	var host := _build()
	var nest := host.get_node_or_null("Props/EmberNestAlley") as EmberNest
	ok(nest != null, "the alley has a third checkpoint")
	if nest == null:
		return
	var tops := LevelSanity.top_segments(host)
	ok(LevelSanity.standing_on(tops, LevelSanity.feet_of(nest)) != null, "alley nest stands on the sunken lane")
	ok(LevelSanity.is_reachable(host, LAYOUT.ENTRY_SPAWN, LevelSanity.feet_of(nest), false),
			"alley nest is reachable without optional abilities")
	for scrapper_name in ["Scrapper2", "Scrapper3"]:
		var scrapper := host.get_node("Enemies/" + scrapper_name) as ScrapperEnemy
		var nearest_beat := absf(nest.position.x - scrapper.position.x) - scrapper.patrol_range
		ok(nearest_beat > scrapper.aggro_range, "%s cannot charge the alley nest" % scrapper_name)
	var ghost := host.get_node("Enemies/Ghost1") as GhostEnemy
	ok(nest.position.distance_to(ghost.position) > ghost.wake_range, "the alley ghost sleeps away from the nest")
	var spitter := host.get_node("Enemies/Spitter2") as SpitterEnemy
	ok(absf(nest.position.x - spitter.position.x) > spitter.aggro_range, "the terrace spitter cannot reach the nest")
