extends TestCase

const LAYOUT := preload("res://scripts/levels/chapters/level03_layout.gd")

func setup() -> void:
	Director._set_lock(false)

func teardown() -> void:
	Director._set_lock(false)
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


## 街面 / 屋顶双层环线 + 塌瓦屋檐 + 下水道蒸汽喷口：
## 首处教学机关前后各有 ≥48px 安全落脚区，蒸汽喷口错相，窄巷回程有屋檐单向捷径。
func test_dual_layer_loop_hazards_and_alley_shortcut() -> void:
	var host := _build()
	var hazards := LevelSanity.hazards(host)
	eq(hazards.size(), LAYOUT.COLLAPSING_STEPS.size() + LAYOUT.STEAM_VENTS.size(),
			"all collapsing roof tiles and sewer steam vents are registered hazards")
	# 首处蒸汽教学：前后各有 ≥48px 无判定平地，预警 ≥0.5s。
	var teach_steam := host.get_node_or_null("Props/SteamTeach") as CyclicHazard
	ok(teach_steam != null, "safe teaching steam vent exists on StreetA")
	if teach_steam != null:
		ok(teach_steam.telegraph_time >= 0.5, "steam telegraph >= 0.5s")
		var hrect := teach_steam.hit_rect()
		ok(hrect.position.x - 312.0 >= 48.0, ">=48px safe landing before first steam vent")
		ok(LAYOUT.CANAL_X0 - hrect.end.x >= 48.0, ">=48px safe landing after first steam vent")
	# 首块塌瓦教学：前后各有 ≥48px 实心落脚台，下方是实心 StreetB 而非毒坑。
	var teach_tile := host.get_node_or_null("Platforms/CollapseRoof1") as CollapsingPlatform
	var roof_entry := host.get_node_or_null("Platforms/RoofEntry") as SolidPlatform
	var roof_a := host.get_node_or_null("Platforms/RoofA") as SolidPlatform
	ok(teach_tile != null and roof_entry != null and roof_a != null, "first collapsing roof tile and flanking roofs exist")
	if teach_tile != null and roof_entry != null and roof_a != null:
		ok(roof_entry.size.x >= 48.0 and roof_a.size.x >= 48.0, ">=48px solid landings flank the first collapsing tile")
		ok(_standing_on(_rects(host), Vector2(teach_tile.position.x + 16.0, 320.0)),
				"solid StreetB lies beneath the first collapsing roof tile")
	# 街面蒸汽错相。
	var s1 := host.get_node("Props/SteamStreet1") as CyclicHazard
	var s2 := host.get_node("Props/SteamStreet2") as CyclicHazard
	ok(not is_equal_approx(s1.phase, s2.phase), "street sewer steam vents run out of phase")
	# 窄巷上层屋檐单向捷径：从 StairB 可走上 AlleyReturnStep → EaveE → CollapseAlley → EaveD，
	# EaveD 高出巷底 96px（从巷底单跳不可逆向爬上），西端直接落回 EmberNestAlley。
	var eave_d := host.get_node_or_null("Platforms/EaveD") as SolidPlatform
	ok(eave_d != null, "alley shortcut west eave exists")
	if eave_d != null:
		ok(352.0 - eave_d.position.y >= 96.0, "EaveD sits 96px above the sunken alley (one-way drop)")
		ok(LevelSanity.is_reachable(host, Vector2(2480, 288), Vector2(eave_d.position.x + 24.0, eave_d.position.y), false),
				"upper eave return is walkable westward from StairB")


## ⑥ 死城街区：扩到 4000 宽。街道连续、死城支路是可回主路的屋顶环线，
## 支路尽头有 1 个奖励位（EquipmentPickup 接应），主路线不需要钩锁。
func test_dead_quarter_loop_carries_the_reward_slot() -> void:
	var host := _build()
	eq(LAYOUT.EAST_LIMIT, 4000, "锈城街巷扩到 4000 宽")
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
	var roof_c := host.get_node_or_null("Platforms/DeadRoofC") as SolidPlatform
	ok(ridge != null and roof_c != null, "the dead-quarter rooftop loop exists")
	if ridge != null and roof_c != null:
		var feet := Vector2(ridge.position.x + ridge.size.x * 0.5, ridge.position.y)
		ok(LevelSanity.is_reachable(host, LAYOUT.ENTRY_SPAWN, feet, false),
				"the dead-roof loop is walkable without the hookshot")
		ok(LevelSanity.is_reachable(host, feet, Vector2(roof_c.position.x + 24.0, roof_c.position.y), false),
				"the east rooftop collapsing chain continues from the ridge")
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


## 巷口与死城的余烬巢安全且间距合理，窄巷部署装甲碎铁犬变体与群警戒伏击。
func test_alley_and_quarter_checkpoints_and_ambush_variants() -> void:
	var host := _build()
	var nest := host.get_node_or_null("Props/EmberNestAlley") as EmberNest
	var quarter_nest := host.get_node_or_null("Props/EmberNestQuarter") as EmberNest
	ok(nest != null and quarter_nest != null, "alley and dead-quarter checkpoints exist")
	if nest == null or quarter_nest == null:
		return
	ok(quarter_nest.position.x - nest.position.x <= 1000.0, "alley -> quarter nest spacing <= 1000px")
	ok(LAYOUT.EXIT_POS.x - quarter_nest.position.x <= 1000.0, "quarter nest -> exit spacing <= 1000px")
	var tops := LevelSanity.top_segments(host)
	ok(LevelSanity.standing_on(tops, LevelSanity.feet_of(nest)) != null, "alley nest stands on the sunken lane")
	ok(LevelSanity.standing_on(tops, LevelSanity.feet_of(quarter_nest)) != null, "quarter nest stands on the dead street")
	var hound := host.get_node("Enemies/AlleyHound") as ScrapperEnemy
	eq(hound.variant, &"armored_scrapper", "alley ambush uses an armored scrapper variant")
	ok(hound.alert_radius > 0.0, "alley ambush hound alerts peers")
	for scrapper_name in ["Scrapper2", "Scrapper3", "AlleyHound"]:
		var scrapper := host.get_node("Enemies/" + scrapper_name) as ScrapperEnemy
		var nearest_beat := absf(nest.position.x - scrapper.position.x) - scrapper.patrol_range
		ok(nearest_beat > scrapper.aggro_range, "%s cannot charge the alley nest" % scrapper_name)
	var ghost := host.get_node("Enemies/Ghost1") as GhostEnemy
	ok(nest.position.distance_to(ghost.position) > ghost.wake_range, "the alley ghost sleeps away from the nest")
	var spitter := host.get_node("Enemies/Spitter2") as SpitterEnemy
	ok(absf(nest.position.x - spitter.position.x) > spitter.aggro_range, "the stair spitter cannot reach the alley nest")
	var gs := host.get_node("Enemies/GearShield1") as GearShieldEnemy
	ok(quarter_nest.position.distance_to(gs.position + Vector2(gs.patrol_range, 0.0)) > gs.aggro_range,
			"the terrace shield guard leaves the dead-quarter nest in peace")
	var s4 := host.get_node("Enemies/Scrapper4") as ScrapperEnemy
	ok(absf(quarter_nest.position.x - s4.position.x) - s4.patrol_range > s4.aggro_range,
			"the dead-quarter swift scrapper cannot charge the quarter nest")
