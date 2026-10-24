extends TestCase

const LAYOUT := preload("res://scripts/levels/chapters/level03_layout.gd")

func setup() -> void:
	Director.abort()
	Director._set_lock(false)
	SaveData.consumed.clear()
	SaveData.flags.clear()

func teardown() -> void:
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	Director.abort()
	SaveData.consumed.clear()
	SaveData.flags.clear()

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
	for name_ in ["EmberNestStreet", "EmberNestPlaza", "EmberNestAlley", "EmberNestQuarter", "Exit"]:
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


func _rects(host: Node2D) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for child in host.get_node("Platforms").get_children():
		if child is SolidPlatform:
			rects.append(Rect2((child as SolidPlatform).position, (child as SolidPlatform).size))
	return rects


func _standing_on(rects: Array[Rect2], feet: Vector2, slack: float = 0.5) -> bool:
	for r in rects:
		if feet.x >= r.position.x - 0.01 and feet.x <= r.end.x + 0.01 \
				and absf(feet.y - r.position.y) <= slack:
			return true
	return false


## ⑦ 死城街区：扩到 4000 宽。街道连续、死城支路是可回主路的屋顶环线，
## 支路尽头有 1 个奖励位（EquipmentPickup 接应），主路线不需要钩锁。
func test_dead_quarter_loop_carries_the_reward_slot() -> void:
	var host := _build()
	var rects := _rects(host)
	ok(_standing_on(rects, Vector2(2900, 320)), "dead street continues the main route")
	ok(_standing_on(rects, Vector2(3900, 320)), "dead street reaches the new east wall")
	ok(_standing_on(rects, Vector2(LAYOUT.EXIT_POS.x, 320)), "exit stands on the dead street")
	ok(LAYOUT.EXIT_POS.x <= float(LAYOUT.EAST_LIMIT) - 80.0, "exit keeps clear of the east wall")
	var reward := host.get_node_or_null("Pickups/RewardDeadQuarter") as EquipmentPickup
	ok(reward != null, "the dead-roof branch carries one reward slot")
	if reward != null:
		eq(reward.position, LAYOUT.REWARD_POS)
		eq(String(reward.get("reward_kind")), "equipment", "reward slot walks the LoadoutBridge path")
		ok(String(reward.get("reward_ref")) != "", "reward slot has a roster/equipment ref")
		ok(LevelSanity.standing_on(LevelSanity.top_segments(host), LevelSanity.feet_of(reward)) != null,
				"reward rests on the dead roof ridge")
	var ridge := host.get_node_or_null("Platforms/DeadRidge") as SolidPlatform
	ok(ridge != null, "the branch ridge exists")
	if ridge != null:
		var feet := Vector2(ridge.position.x + ridge.size.x * 0.5, ridge.position.y)
		ok(LevelSanity.is_reachable(host, LAYOUT.ENTRY_SPAWN, feet, false),
				"the dead-roof loop is walkable without the hookshot (and returns to the street)")
		ok(LevelSanity.is_reachable(host, LAYOUT.ENTRY_SPAWN, Vector2(ridge.position.x, 320.0), false),
				"the drop back to the street is on the main route")


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


func test_street_has_sunken_alley_market_and_temple_steps() -> void:
	var host := _build()
	var rects := _rects(host)
	for feet in [Vector2(640, 352), Vector2(1600, 288), Vector2(2464, 320),
			Vector2(2528, 288), Vector2(2680, 256), Vector2(3392, 256)]:
		ok(_standing_on(rects, feet), "a grounded section at %s changes the street height" % feet)
	for row in LAYOUT.ENEMIES:
		var enemy := host.get_node("Enemies/" + String(row[0])) as Node2D
		if enemy is FlyingDemonEnemy or enemy is GhostEnemy:
			ok(not LevelSanity.inside_solid(LevelSanity.solid_rects(host), enemy.position),
					"airborne %s stays outside solid terrain" % enemy.name)
		else:
			ok(LevelSanity.standing_on(LevelSanity.top_segments(host), enemy.position) != null,
					"%s has a fixed landing" % enemy.name)
	# Three encounters have distinct terrain: drain crossfire, raised market, low-eave ambush.
	var market_hound := host.get_node("Enemies/Scrapper3") as ScrapperEnemy
	eq(market_hound.variant, &"swift_scrapper")
	eq((host.get_node("Enemies/AlleyHound") as ScrapperEnemy).variant, &"armored_scrapper")
	ok((host.get_node("Enemies/Scrapper2") as EnemyBase).alert_radius > 0.0)


func test_roof_return_drops_to_the_previous_nest_without_optional_abilities() -> void:
	var host := _build()
	var terrace := host.get_node("Platforms/AlleyReturnStep") as SolidPlatform
	var eave := host.get_node("Platforms/EaveD") as SolidPlatform
	var nest := host.get_node("Props/EmberNestAlley") as EmberNest
	var start := terrace.position + Vector2(terrace.size.x * 0.5, 0)
	var last_roof := eave.position + Vector2(eave.size.x * 0.5, 0)
	var landing := LevelSanity.feet_of(nest)
	ok(LevelSanity.is_reachable(host, start, last_roof, false), "westbound roof chain uses basic jumps")
	ok(LevelSanity.is_reachable(host, last_roof, landing, false), "roof end returns to the previous nest")
	ok(landing.y - last_roof.y > LevelSanity.JUMP_RISE_MAX, "return lip cannot be climbed directly from the alley")
	# Test the local reverse edge, not the full graph: the long route around the temple stairs remains open.
	var low := LevelSanity.standing_on(LevelSanity.top_segments(host), landing)
	var high := LevelSanity.standing_on(LevelSanity.top_segments(host), last_roof)
	ok(not LevelSanity._can_hop(low, high), "the final return drop is one way")
	ok(LevelSanity._can_hop(high, low), "the same lip permits a safe descent")
	for i in range(1, 4):
		var names := ["EmberNestStreet", "EmberNestPlaza", "EmberNestAlley", "EmberNestQuarter"]
		var previous := host.get_node("Props/" + names[i - 1]) as Node2D
		var current := host.get_node("Props/" + names[i]) as Node2D
		ok(current.position.x - previous.position.x <= 1000.0, "checkpoints cap the death run")


func test_first_hazards_leave_fixed_safe_landings() -> void:
	var host := _build()
	var tops := LevelSanity.top_segments(host)
	var tile := host.get_node("Props/FallingTileTeach") as CyclicHazard
	var zone := tile.hit_rect()
	for side in [-1.0, 1.0]:
		var safe_x := zone.position.x - 48.0 if side < 0 else zone.end.x + 48.0
		ok(LevelSanity.standing_on(tops, Vector2(safe_x, tile.position.y)) != null,
				"first falling tile has a fixed 48px safe side")
	var first := host.get_node("Platforms/CollapseRoof1") as CollapsingPlatform
	for feet in [Vector2(first.position.x - 48, first.position.y),
			Vector2(first.position.x + first.size.x + 48, first.position.y)]:
		var segment := LevelSanity.standing_on(tops, feet)
		ok(segment != null and segment.kind == "", "first collapsing eave has a fixed waiting roof")
	ok(LevelSanity.standing_on(tops, first.position + Vector2(first.size.x * 0.5, 96)) != null,
			"first roof collapse falls onto safe street instead of a pit")
	ok(tile.telegraph_time >= 0.5)
	var hint := tile.get_node("TileHint") as HintArea
	ok(hint.text.contains("瓦") and not hint.text.contains("钟"), "falling tile teaches its own visual cue")


func test_every_checkpoint_remains_quiet_for_six_seconds() -> void:
	for name_ in ["EmberNestStreet", "EmberNestPlaza", "EmberNestAlley", "EmberNestQuarter"]:
		var host := _build()
		var nest := host.get_node("Props/" + name_) as EmberNest
		var calls := {"attacks": 0}
		for enemy in host.get_node("Enemies").get_children():
			(enemy as EnemyBase).telegraph_started.connect(func(_kind, _duration) -> void: calls.attacks += 1)
		var player := await spawn_player(host, LevelSanity.feet_of(nest) - Vector2(0, 20))
		var hp := player.health.current
		await flush(360)
		eq(player.health.current, hp, "%s is safe while resting for six seconds" % name_)
		eq(calls.attacks, 0, "%s does not wake surrounding encounters" % name_)
		host.free()
		await flush(1)


func test_first_falling_tile_can_be_read_without_the_drain_encounter() -> void:
	for x in [332.0, 468.0]:
		var host := _build()
		var tile := host.get_node("Props/FallingTileTeach") as CyclicHazard
		tile.set_physics_process(false)
		var calls := {"attacks": 0}
		for enemy in host.get_node("Enemies").get_children():
			(enemy as EnemyBase).telegraph_started.connect(func(_kind, _duration) -> void: calls.attacks += 1)
		var player := await spawn_player(host, Vector2(x, tile.position.y - 20))
		var hp := player.health.current
		await flush(360)
		eq(calls.attacks, 0, "the first tile's waiting area at x%.0f leaves the encounter asleep" % x)
		eq(player.health.current, hp, "the teaching landing is safe from enemy damage")
		host.free()
		await flush(1)
