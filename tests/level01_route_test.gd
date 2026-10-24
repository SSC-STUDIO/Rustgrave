extends TestCase
## 第一章（腐液回廊）东半重建的结构测试（plan P3）：
##   · 持久化节点路径不变（SaveData 用 level01 的裸路径），.tscn 的位置与路线常量一致；
##   · 主线不靠钩锁 / 余烬步：巢、压板、闸门、废料堆、嵌核台、锈门、BossGate、炉心全部可走到；
##     钩锁只通向可选支路（余烬阁、奖励台、炉廊顶板）；
##   · 压板在楼座、闸门在巷里；第一根塌陷梁在安全处教学（前后 ≥48px 实心、没有敌人够得到）；
##   · 炉廊三口炉口守规则、周期错相、每口都有通过的间隙；
##   · 三处场景化遭遇（伏击巷、楼座交叉火力、竞技场）、装甲碎铁犬只在见过普通碎铁犬之后；
##   · 余烬巢间距约 1000px、离每个敌人的仇恨圈之外、BossGate 前的巢离门 ≤80px；
##   · 一条单向捷径（余烬阁的两个落点）与一个带奖励的可选挑战；
##   · 竞技场：石台、掩体墩、炉龛喷火口只在 Boss 战里转（二阶段更急、Boss 倒下就停）。

const ROUTE := preload("res://scripts/levels/chapters/level01_east_layout.gd")
const LEVEL := "res://scenes/levels/Level01_Static.tscn"

## SaveData 里 level01 的裸路径（改名 = 旧存档里的记录失效）。
const PERSISTED_PATHS := [
	"Props/EmberNest", "Props/EmberNestEast", "Props/Door", "Props/RustyGate", "Props/ForgeHeart",
	"Props/ScrapPile", "Pickups/EmberCore", "Props/PressurePlate", "Props/SocketStation",
	"Props/PurificationShrine", "Props/Spitter1", "Props/Spitter2", "Props/Scrapper1",
	"Props/GearShield1", "Props/SteleForge", "Props/SteleCoolant", "Props/SteleExecutioner",
	"Props/ToxinPool", "Hooks/Hook_Ember", "BossGate",
]


func setup() -> void:
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.pending_spawn = Vector2.INF
	SaveData.entering_from_checkpoint = false
	StoryStage.forget()
	Director.abort()
	Director.resume()
	Director.choice_hold = false


func teardown() -> void:
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.pending_spawn = Vector2.INF
	StoryStage.forget()
	Director.abort()
	Director.resume()
	Director.choice_hold = false
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	Engine.time_scale = 1.0
	if get_tree().paused:
		get_tree().paused = false


func _load_level() -> Node:
	var packed := load(LEVEL) as PackedScene
	ok(packed != null, "Level01 scene loads")
	var level := packed.instantiate()
	add_child(level)
	await flush(3)
	Director.abort()
	return level


func _feet(level: Node, path: String) -> Vector2:
	var node := level.get_node_or_null(path)
	ok(node != null, "%s exists" % path)
	return LevelSanity.feet_of(node) if node != null else Vector2.INF


func _spawn_of(_level: Node) -> Vector2:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	return player.global_position if player != null else Vector2.INF


func _free(level: Node) -> void:
	level.free()
	await flush(1)


## 敌人水平仇恨半径（含巡逻幅度）：喷吐者看 2D 距离且只在 |Δy|≤96 时开火。
func _aggro_reach(enemy: Node) -> float:
	if enemy is SpitterEnemy:
		return (enemy as SpitterEnemy).aggro_range
	if enemy is ScrapperEnemy:
		return (enemy as ScrapperEnemy).aggro_range + (enemy as EnemyBase).patrol_range
	if enemy is GearShieldEnemy:
		return (enemy as GearShieldEnemy).aggro_range + (enemy as EnemyBase).patrol_range
	return 0.0


## 敌人够得着 point 吗（粗判：同层才算，喷吐者 96px、碎铁犬 70px）。
func _enemy_reaches(enemy: Node2D, point: Vector2) -> bool:
	var reach := _aggro_reach(enemy)
	if reach <= 0.0:
		return false
	var dy := absf(enemy.global_position.y - point.y)
	if enemy is SpitterEnemy:
		return dy <= 96.0 and enemy.global_position.distance_to(point) <= reach
	if enemy is ScrapperEnemy:
		return dy < 70.0 and absf(enemy.global_position.x - point.x) < reach
	return enemy.global_position.distance_to(point) <= reach


func _grounded_enemies(level: Node) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for node in get_tree().get_nodes_in_group("enemies"):
		if not level.is_ancestor_of(node) or node is ExecutionerBoss:
			continue
		if node is SpitterEnemy or node is ScrapperEnemy or node is GearShieldEnemy:
			out.append(node as Node2D)
	return out


# --- 1. 持久化节点与 .tscn / 常量一致 ----------------------------------------------

func test_persisted_node_paths_stay_stable() -> void:
	var level := await _load_level()
	for path in PERSISTED_PATHS:
		ok(level.get_node_or_null(String(path)) != null, "persisted node %s still exists" % path)
	# 压板 / 闸门 / 废料堆 / 嵌核台 / 锈门 / 净化祠 / 喷吐者 / 碎铁犬 / 齿盾卫的位置来自路线常量。
	eq((level.get_node("Props/PressurePlate") as Node2D).position, ROUTE.PLATE_POS)
	eq((level.get_node("Props/Door") as Node2D).position, ROUTE.DOOR_POS)
	eq((level.get_node("Props/ScrapPile") as Node2D).position, ROUTE.SCRAP_PILE_POS)
	eq((level.get_node("Props/SocketStation") as Node2D).position, ROUTE.SOCKET_POS)
	eq((level.get_node("Props/RustyGate") as Node2D).position, ROUTE.GATE_POS)
	eq((level.get_node("Props/PurificationShrine") as Node2D).position, ROUTE.SHRINE_POS)
	eq((level.get_node("Props/Spitter2") as Node2D).position, ROUTE.SPITTER2_POS)
	# 碎铁犬 / 齿盾卫会巡逻：几帧之后离出生点几像素以内就算在位。
	ok((level.get_node("Props/Scrapper1") as Node2D).position.distance_to(ROUTE.SCRAPPER1_POS) <= 8.0,
			"Scrapper1 stands at its authored spot")
	ok((level.get_node("Props/GearShield1") as Node2D).position.distance_to(ROUTE.LANE_SHIELD_POS) <= 8.0,
			"GearShield1 guards the lane door")
	eq((level.get_node("Platforms/Plat_920_248") as Node2D).position, ROUTE.HIGH_ROAD_A_POS)
	eq((level.get_node("Platforms/Plat_980_180") as Node2D).position, ROUTE.HIGH_ROAD_B_POS)
	var ground := level.get_node("Platforms/GroundRight") as SolidPlatform
	almost(ground.position.x + ground.size.x, ROUTE.GROUND_RIGHT_END, 0.01, "grass ends where the crypt floor starts")
	eq(Level01EastWing.EAST_LIMIT, ROUTE.EAST_LIMIT)
	almost(Level01EastWing.EAST_FLOOR_X, ROUTE.EAST_FLOOR_X, 0.01)
	almost(Level01EastWing.NAVE_Y, ROUTE.NAVE_Y, 0.01)
	almost(Level01EastWing.STAGE_Y, ROUTE.STAGE_Y, 0.01)
	almost(Level01EastWing.ARENA_CENTER_X, ROUTE.ARENA_CENTER_X, 0.01)
	await _free(level)


func test_the_route_layout_is_not_a_registered_chapter() -> void:
	for id in GameContext.LAYOUTS:
		ok(String(GameContext.LAYOUTS[id]) != "res://scripts/levels/chapters/level01_east_layout.gd",
				"the east layout helper is not registered as %s" % id)
	ok(not GameContext.LAYOUTS.has("level01"), "level01 stays a hand-authored scene")


# --- 2. 主线可达性（不用钩锁 / 余烬步） ---------------------------------------------

func test_main_route_needs_no_hook() -> void:
	var level := await _load_level()
	var spawn := _spawn_of(level)
	ok(spawn != Vector2.INF, "the knight spawns")
	var gate_pos: Vector2 = (level.get_node("BossGate") as Node2D).position
	var goals := {
		"EmberNest": _feet(level, "Props/EmberNest"),
		"EmberNestMid": _feet(level, "Props/EmberNestMid"),
		"EmberNestForge": _feet(level, "Props/EmberNestForge"),
		"EmberNestEast": _feet(level, "Props/EmberNestEast"),
		"PressurePlate": _feet(level, "Props/PressurePlate"),
		"Door": _feet(level, "Props/Door"),
		"ScrapPile": _feet(level, "Props/ScrapPile"),
		"SocketStation": _feet(level, "Props/SocketStation"),
		"PurificationShrine": _feet(level, "Props/PurificationShrine"),
		"RustyGate": _feet(level, "Props/RustyGate"),
		"BossGate": Vector2(gate_pos.x, ROUTE.NAVE_Y),
		"ExecutionerStele": _feet(level, "Props/SteleExecutioner"),
		"ForgeHeart": _feet(level, "Props/ForgeHeart"),
	}
	for key in goals:
		var feet: Vector2 = goals[key]
		ok(LevelSanity.is_reachable(level, spawn, feet, false),
				"%s is reachable from the spawn without the hook / ember step" % key)
	# 死在任何一个巢：从那里出发炉心仍然走得到（没有重生软锁）。
	for nest_name in ["EmberNest", "EmberNestMid", "EmberNestForge", "EmberNestEast"]:
		var start: Vector2 = goals[nest_name]
		ok(LevelSanity.is_reachable(level, start, goals["ForgeHeart"], false),
				"from %s the forge heart is still reachable on foot" % nest_name)
	await _free(level)


func test_hooks_only_open_optional_branches() -> void:
	var level := await _load_level()
	var spawn := _spawn_of(level)
	var optional := {
		"EmberCore": level.get_node("Pickups/EmberCore"),
		"RewardEyrie": level.get_node("Props/RewardEyrie"),
	}
	for key in optional:
		var node: Node2D = optional[key]
		var feet := LevelSanity.feet_of(node) if key != "EmberCore" else node.global_position + Vector2(0.0, 16.0)
		ok(not LevelSanity.is_reachable(level, spawn, feet, false), "%s needs the hook (optional branch)" % key)
		ok(LevelSanity.is_reachable(level, spawn, feet, true), "%s is reachable with the hook" % key)
	# 炉廊顶板只有从余烬阁东头落下才踩得到。
	var deck := level.get_node("Platforms/VentDeck") as SolidPlatform
	var deck_feet := deck.global_position + Vector2(deck.size.x * 0.5, 0.0)
	ok(not LevelSanity.is_reachable(level, spawn, deck_feet, false), "the vent deck is not on the main route")
	await _free(level)


# --- 3. 压板偏殿：两层楼 + 第一根塌陷梁 -------------------------------------------

func test_plate_on_the_gallery_door_in_the_lane() -> void:
	var level := await _load_level()
	var plate := level.get_node("Props/PressurePlate") as PressurePlate
	var door := level.get_node("Props/Door") as ArenaDoor
	var plate_feet := LevelSanity.feet_of(plate)
	almost(plate_feet.y, ROUTE.GALLERY_Y, 3.0, "the plate stands on the gallery deck")
	almost(door.position.y + 64.0, ROUTE.GROUND, 0.01, "the door is in the crypt lane (its foot on y=320)")
	ok(door.position.x > plate_feet.x, "the lane door lies east of the plate")
	ok(plate.activated.get_connections().size() > 0, "the plate is wired to the door")
	ok(not door.is_open, "a fresh run starts with the door shut")
	# 压板底下的台面是实心的楼座，不是塌陷梁。
	var tops := LevelSanity.top_segments(level)
	var seg := LevelSanity.standing_on(tops, plate_feet)
	ok(seg != null and seg.kind == "", "the plate stands on solid stone, not a collapsing beam")
	# 楼座上方的净空：下层的巷子（y=320）与楼座面至少 96px 高，两层读得出来。
	ok(ROUTE.GROUND - ROUTE.GALLERY_Y >= 96.0, "two readable tiers")
	await _free(level)


func test_first_collapsing_beam_teaches_in_a_safe_spot() -> void:
	var level := await _load_level()
	var beam := level.get_node("Platforms/GalleryBeam") as CollapsingPlatform
	ok(beam != null, "the gallery bridge has a collapsing rust beam")
	if beam == null:
		await _free(level)
		return
	eq(String(beam.get_meta("hazard_kind", "")), "collapsing")
	eq(beam.skin, "iron_float", "the rust beam looks different from the stone around it")
	var west := level.get_node("Platforms/GalleryW") as SolidPlatform
	var east := level.get_node("Platforms/GalleryE") as SolidPlatform
	ok(west.size.x >= 48.0, "at least 48px of solid stone before the beam")
	ok(east.size.x >= 48.0, "at least 48px of solid stone after the beam")
	almost(west.position.y, beam.position.y, 0.01, "beam and decks share one height")
	almost(east.position.y, beam.position.y, 0.01)
	var gap_west := beam.position.x - (west.position.x + west.size.x)
	var gap_east := east.position.x - (beam.position.x + beam.size.x)
	ok(gap_west >= 0.0 and gap_west <= 24.0, "hop onto the beam is short (%.0fpx)" % gap_west)
	ok(gap_east >= 0.0 and gap_east <= 24.0, "hop off the beam is short (%.0fpx)" % gap_east)
	ok(beam.shake_time >= 0.6, "the beam shakes long enough to run across (%.2fs)" % beam.shake_time)
	# 第一根梁之前没有别的机关；梁周围没有任何敌人够得到（安全处教学）。
	var beam_point := beam.position + Vector2(beam.size.x * 0.5, -12.0)
	for hz in LevelSanity.hazards(level):
		if hz == beam:
			continue
		if hz is CyclicHazard:
			ok(hz.global_position.x > beam.position.x + 500.0, "no vent shares the screen with the first beam")
	for enemy in _grounded_enemies(level):
		ok(not _enemy_reaches(enemy, beam_point), "%s cannot reach the first beam" % enemy.name)
	# 梁不是任何休息点的唯一支撑（LevelSanity 的规则，这里再按名字断言一遍）。
	var tops := LevelSanity.top_segments(level)
	for path in ["Props/PressurePlate", "Props/EmberNestMid", "Props/EmberNestForge", "Props/EmberNestEast"]:
		var seg := LevelSanity.standing_on(tops, LevelSanity.feet_of(level.get_node(path)))
		ok(seg != null and seg.kind != "collapsing", "%s does not stand on a collapsing platform" % path)
	var problems := LevelSanity.check(level, Rect2(0, 0, ROUTE.EAST_LIMIT, 400))
	ok(problems.is_empty(), "LevelSanity is clean: %s" % ", ".join(problems))
	await _free(level)


func test_beam_collapses_and_returns() -> void:
	var level := await _load_level()
	var beam := level.get_node("Platforms/GalleryBeam") as CollapsingPlatform
	ok(beam.trigger(), "stepping on it starts the shake")
	eq(beam.state(), CollapsingPlatform.State.SHAKING)
	beam.tick(beam.shake_time + 0.01)
	ok(beam.is_collapsed(), "it falls after the shake")
	beam.tick(beam.respawn_time + 0.5)
	await flush(2)
	beam.tick(1.0)
	ok(beam.is_solid(), "it grows back")
	await _free(level)


# --- 4. 炉廊：三口炉口 ---------------------------------------------------------------

func test_flame_vents_follow_the_hazard_rules() -> void:
	var level := await _load_level()
	var vents: Array[CyclicHazard] = []
	for i in 3:
		var vent := level.get_node_or_null("Props/FlameVent%d" % (i + 1)) as CyclicHazard
		ok(vent != null, "FlameVent%d exists" % (i + 1))
		if vent != null:
			vents.append(vent)
	eq(vents.size(), 3)
	var nest_forge := level.get_node("Props/EmberNestForge") as Node2D
	var gate := level.get_node("Props/RustyGate") as Node2D
	var phases: Array[float] = []
	var crossing := 0.0
	for i in vents.size():
		var vent := vents[i]
		eq(vent.skin, "flame")
		ok(vent.telegraph_time >= CyclicHazard.MIN_TELEGRAPH + 0.3, "vent %d telegraphs >= 0.8s" % i)
		ok(vent.rest_time + vent.telegraph_time >= LevelSanity.HAZARD_SAFE_SPAN, "vent %d leaves a safe span" % i)
		ok(vent.active_time <= LevelSanity.HAZARD_MAX_ACTIVE)
		ok(not phases.has(vent.phase), "vent %d has its own phase" % i)
		phases.append(vent.phase)
		# 站在判定区里 0.31s 就过得去（宽 20 + 身体 14，跑速 108）：一个周期里必须留够安全间隙。
		crossing = (vent.hit_rect().size.x + 14.0) / 108.0
		ok(vent.period() - vent.active_time > crossing + 0.8,
				"vent %d leaves a crossing window of %.2fs" % [i, vent.period() - vent.active_time - crossing])
		# 出生相位不在判定中（读档 / 进关时不会一头撞上火舌）。
		ok(vent.state() != CyclicHazard.State.ACTIVE, "vent %d is not firing at spawn" % i)
		# 离休息点 / 锈门 ≥ 40px（LevelSanity 的底线）；这里要求更宽：第一口之前有 ≥100px 的净地。
		ok(vent.hit_rect().position.x - nest_forge.global_position.x >= 100.0, "run-up before the first vent")
		ok(gate.global_position.x - vent.hit_rect().end.x >= 48.0, "the last vent is 48px clear of the gate")
	for i in range(1, vents.size()):
		var pocket := vents[i].hit_rect().position.x - vents[i - 1].hit_rect().end.x
		ok(pocket >= 48.0, "a %.0fpx pocket between vents %d and %d fits a standing knight" % [pocket, i - 1, i])
	# 三口不会同时进入判定（不连成一堵火墙）：扫一个周期。
	var period := vents[0].period()
	var t := 0.0
	var overlaps := 0
	while t < period * 3.0:
		var active := 0
		for vent in vents:
			if vent.state_at(t + vent.phase * vent.period()) == CyclicHazard.State.ACTIVE:
				active += 1
		if active > 1:
			overlaps += 1
		t += 0.05
	eq(overlaps, 0, "no two corridor vents fire together")
	# 首遇提示：炉廊第一口带 flame 提示（弹一次，不是每口都弹）。
	ok(vents[0].get_node_or_null("HazardHint") != null, "the first vent carries the first-encounter hint")
	await _free(level)


func test_vent_deck_covers_the_vents_and_only_the_eyrie_drops_onto_it() -> void:
	var level := await _load_level()
	var deck := level.get_node("Platforms/VentDeck") as SolidPlatform
	var v1 := level.get_node("Props/FlameVent1") as CyclicHazard
	var v3 := level.get_node("Props/FlameVent3") as CyclicHazard
	ok(deck.position.x < v1.global_position.x and deck.position.x + deck.size.x > v3.global_position.x,
			"the deck roofs all three vents")
	ok(deck.position.y + deck.size.y <= v1.hit_rect().position.y - 8.0, "flame tips stop short of the deck")
	# 钩锁线要净空：锚点正上方的 x 范围里没有顶板。
	var hook := level.get_node("Hooks/Hook_Ember") as Node2D
	ok(hook.global_position.x < deck.position.x, "the deck does not cross the ember hook's pull line")
	await _free(level)


# --- 5. 遭遇：伏击巷 / 楼座交叉火力 / 竞技场 -------------------------------------------

func test_set_piece_encounters() -> void:
	var level := await _load_level()
	var door := level.get_node("Props/Door") as Node2D
	var nest_mid := level.get_node("Props/EmberNestMid") as Node2D
	var scrapper1 := level.get_node("Props/Scrapper1") as ScrapperEnemy
	var scrapper2 := level.get_node("Props/Scrapper2") as ScrapperEnemy
	var shield := level.get_node("Props/GearShield1") as GearShieldEnemy
	# ① 伏击巷：装甲碎铁犬 + 齿盾卫，都在巷里（y=320）、巢与闸门之间，互相惊动。
	eq(scrapper2.variant, &"armored_scrapper")
	ok(scrapper2.alert_radius > 0.0 and shield.alert_radius > 0.0, "the lane pair alerts each other")
	for enemy in [scrapper2, shield]:
		almost(enemy.global_position.y, ROUTE.GROUND, 0.5, "%s stands in the lane" % enemy.name)
		ok(enemy.global_position.x > nest_mid.global_position.x + 200.0 and enemy.global_position.x < door.global_position.x,
				"%s lies between the nest and the door" % enemy.name)
	ok(absf(shield.global_position.x - scrapper2.global_position.x) <= 200.0, "the pair works as one ambush")
	# 装甲碎铁犬只在见过普通碎铁犬之后出现。
	eq(scrapper1.variant, &"", "the first scrapper is the plain one")
	ok(scrapper1.global_position.x < scrapper2.global_position.x, "the plain scrapper comes first")
	# ② 楼座交叉火力：压板东侧一低一高两只喷吐者，覆盖压板、够不到塌陷梁。
	var plate := LevelSanity.feet_of(level.get_node("Props/PressurePlate"))
	var low := level.get_node("Props/Spitter2") as SpitterEnemy
	var high := level.get_node("Props/Spitter3") as SpitterEnemy
	ok(high.global_position.y < low.global_position.y - 16.0, "one high, one low")
	for sp in [low, high]:
		ok(sp.global_position.x > plate.x, "%s sits east of the plate" % sp.name)
		ok(_enemy_reaches(sp, plate + Vector2(0.0, -12.0)), "%s covers the plate" % sp.name)
		almost(sp.aggro_range, ROUTE.GALLERY_SPITTER_AGGRO, 0.01)
	# 楼座喷吐者不会隔着楼板打巷子里的人（|Δy| > 96）。
	ok(ROUTE.GROUND - low.global_position.y > 96.0, "gallery spitters cannot fire down into the lane")
	# ③ 竞技场：刽子手在石台上。
	var boss: ExecutionerBoss = null
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is ExecutionerBoss and level.is_ancestor_of(node):
			boss = node
	ok(boss != null, "the Executioner waits in the arena")
	if boss != null:
		almost(boss.global_position.y, ROUTE.STAGE_Y, 0.5, "he stands on the stage")
		almost(boss.global_position.x, ROUTE.ARENA_CENTER_X, 0.5)
	# 敌人总数克制：前半 3 + 巷 2 + 楼座 2 + 阁 1 + 飞魔 1 + Boss。
	var total := 0
	for node in get_tree().get_nodes_in_group("enemies"):
		if level.is_ancestor_of(node):
			total += 1
	ok(total >= 9 and total <= 12, "the chapter keeps a moderate enemy count (%d)" % total)
	await _free(level)


# --- 6. 余烬巢：间距、仇恨圈、门前 ≤80px ---------------------------------------------

func test_nests_are_spaced_and_outside_every_aggro_circle() -> void:
	var level := await _load_level()
	var nests: Array[Node2D] = []
	for path in ["Props/EmberNest", "Props/EmberNestMid", "Props/EmberNestForge", "Props/EmberNestEast"]:
		nests.append(level.get_node(path) as Node2D)
	for i in range(1, nests.size()):
		var gap := nests[i].global_position.x - nests[i - 1].global_position.x
		ok(gap >= 700.0 and gap <= 1150.0, "nests %d and %d are ~1000px apart (%.0f)" % [i - 1, i, gap])
	var gate := level.get_node("BossGate") as Node2D
	var run_back := gate.global_position.x - nests[3].global_position.x
	ok(run_back > 0.0 and run_back <= 80.0, "the death run-back to the BossGate is %.0fpx" % run_back)
	for nest in nests:
		var point := LevelSanity.feet_of(nest) + Vector2(0.0, -14.0)
		for enemy in _grounded_enemies(level):
			ok(not _enemy_reaches(enemy, point), "%s cannot aggro %s" % [enemy.name, nest.name])
	# Boss 的 360px 仇恨圈也够不到 BossGate 前的巢（站在巢边不会被点名）。
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is ExecutionerBoss and level.is_ancestor_of(node):
			var boss := node as ExecutionerBoss
			ok(boss.global_position.distance_to(nests[3].global_position) > boss.aggro_range,
					"the boss cannot see the east nest")
	await _free(level)


# --- 7. 捷径与奖励 ---------------------------------------------------------------------

func test_eyrie_drops_are_the_one_way_shortcut() -> void:
	var level := await _load_level()
	var reward := level.get_node("Props/RewardEyrie") as EquipmentPickup
	var reward_feet := LevelSanity.feet_of(reward)
	var nest_forge := LevelSanity.feet_of(level.get_node("Props/EmberNestForge"))
	var gate := LevelSanity.feet_of(level.get_node("Props/RustyGate"))
	var deck := level.get_node("Platforms/VentDeck") as SolidPlatform
	var deck_feet := deck.global_position + Vector2(deck.size.x * 0.5, 0.0)
	# 从奖励台往下落：回休息龛的巢（单向落下）、越过炉口到锈门前（东头）。
	ok(LevelSanity.is_reachable(level, reward_feet, nest_forge, false), "the eyrie drops back to the forge nest")
	ok(LevelSanity.is_reachable(level, reward_feet, deck_feet, false), "the east drop lands on the vent deck")
	ok(LevelSanity.is_reachable(level, reward_feet, gate, false), "and from the deck you can step down by the gate")
	# 单向：从巢出发不用钩锁上不去阁，也踩不到顶板；有钩锁时顶板只能经余烬阁（上阁 → 过梁 →
	# 东头落下）到达，没有一条直接爬上去的路。
	ok(not LevelSanity.is_reachable(level, nest_forge, reward_feet, false), "no way back up without the hook")
	ok(not LevelSanity.is_reachable(level, nest_forge, deck_feet, false), "the deck is a drop-only perch")
	ok(LevelSanity.is_reachable(level, nest_forge, deck_feet, true), "with the hook the deck is reached through the eyrie")
	await _free(level)


func test_optional_challenge_reward() -> void:
	var level := await _load_level()
	var reward := level.get_node_or_null("Props/RewardEyrie") as EquipmentPickup
	ok(reward != null, "the eyrie holds a reward pickup")
	if reward == null:
		await _free(level)
		return
	eq(reward.reward_kind, "equipment")
	ok(EquipmentCatalog.for_id(StringName(reward.reward_ref)) != null, "the reward id is a catalogued item")
	eq(reward.reward_ref, ROUTE.REWARD_REF)
	var tops := LevelSanity.top_segments(level)
	var seg := LevelSanity.standing_on(tops, LevelSanity.feet_of(reward))
	ok(seg != null and seg.kind == "", "the reward stands on a solid ledge")
	# 挑战 = 钩锁上阁 + 越过第二根塌陷梁，守台的喷吐者够得到梁。
	var beam := level.get_node("Platforms/EyrieBeam") as CollapsingPlatform
	var guard := level.get_node("Props/Spitter4") as SpitterEnemy
	ok(beam != null and guard != null, "a beam and a guard stand between the ledge and the reward")
	if beam != null and guard != null:
		ok(_enemy_reaches(guard, beam.position + Vector2(beam.size.x * 0.5, -12.0)), "the guard covers the beam")
	await _free(level)


# --- 8. 竞技场地形与喷火口 ----------------------------------------------------------------

func test_arena_geometry_has_a_stage_cover_and_hearths() -> void:
	var level := await _load_level()
	var stage := level.get_node("Platforms/ArenaStage") as SolidPlatform
	almost(stage.position.y, ROUTE.STAGE_Y, 0.01)
	ok(ROUTE.NAVE_Y - stage.position.y <= 20.0, "the stage is one low step above the nave")
	ok(stage.position.x < ROUTE.ARENA_CENTER_X - 140.0 and stage.position.x + stage.size.x > ROUTE.ARENA_CENTER_X + 140.0,
			"the stage holds the boss and the finale pillar spots (centre +-140)")
	var cover := 0
	for pier_name in ["PierW", "PierE"]:
		var pier := level.get_node("Platforms/%s" % pier_name) as SolidPlatform
		var base := level.get_node("Platforms/%sBase" % pier_name) as SolidPlatform
		almost(pier.position.y, ROUTE.STAGE_Y - 32.0, 0.01, "%s tops 32px above the stage (a bolt-blocking cover)" % pier_name)
		almost(base.position.y + base.size.y, ROUTE.STAGE_Y, 0.01)
		ok(pier.size.x >= 24.0)
		ok(pier.position.x > stage.position.x and pier.position.x + pier.size.x < stage.position.x + stage.size.x)
		cover += 1
	eq(cover, 2, "two cover piers")
	# 两座落地火膛夹着刽子手，喷火口在火膛外侧，离刽子手的身体 ≥ 28px。
	var wing := level.get_node("EastWing") as Level01EastWing
	eq(wing.arena_hearth_count(), 2)
	var vents := wing.arena_vents()
	eq(vents.size(), 2, "two hearth vents")
	for vent in vents:
		var zone := vent.hit_rect()
		var body_half := ExecutionerBoss.BOSS_BODY_SIZE.x * 0.5
		ok(absf(zone.get_center().x - ROUTE.ARENA_CENTER_X) - zone.size.x * 0.5 >= body_half + 28.0 - 1.0,
				"%s keeps clear of the boss's body" % vent.name)
		almost(vent.global_position.y, ROUTE.STAGE_Y, 0.01, "%s vents from the stage" % vent.name)
	# 地面：BossGate 前的巢到炉心，脚下没有断口（没有黑洞）。
	var tops := LevelSanity.top_segments(level)
	var x := 0.0
	while x < float(ROUTE.EAST_LIMIT):
		if not (x >= Level01EastWing.PIT_X0 and x <= Level01EastWing.PIT_X1):
			var covered := false
			for seg in tops:
				if x >= seg.x0 - 4.0 and x <= seg.x1 + 4.0 and seg.y >= ROUTE.GROUND - 0.5:
					covered = true
					break
			if not covered:
				ok(false, "no floor under x=%.0f (black void)" % x)
				break
		x += 8.0
	var wall := level.get_node("Platforms/WallRight") as Node2D
	almost(wall.position.x, float(ROUTE.EAST_LIMIT), 0.01, "WallRight sits at the east limit")
	var cam := get_tree().get_first_node_in_group("game_camera") as Camera2D
	ok(cam != null and cam.limit_right == ROUTE.EAST_LIMIT, "the camera limit follows the new width")
	var shelter := level.get_node("ForgeShelter") as AtmosphereZone
	ok(shelter.position.x + Level01EastWing.FORGE_SHELTER_SIZE.x * 0.5 <= float(ROUTE.EAST_LIMIT) + 0.01,
			"the forge shelter fits inside the wall")
	var heart := level.get_node("Props/ForgeHeart") as Node2D
	ok(absf(heart.position.x - Level01EastWing.HEART_POS.x) < 0.01)
	await _free(level)


func test_arena_vents_fire_only_during_the_fight() -> void:
	var level := await _load_level()
	var wing := level.get_node("EastWing") as Level01EastWing
	var vents := wing.arena_vents()
	eq(vents.size(), 2)
	var boss: ExecutionerBoss = null
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is ExecutionerBoss and level.is_ancestor_of(node):
			boss = node
	ok(boss != null, "the boss is alive in a fresh run")
	# 开战之前：熄着，自己的物理帧关了，时钟不走。
	var clocks: Array[float] = []
	for vent in vents:
		ok(not vent.is_physics_processing(), "%s does not run on its own" % vent.name)
		eq(vent.state(), CyclicHazard.State.REST)
		clocks.append(vent.clock())
	ok(not wing.arena_vents_live(), "the vents are dormant before the fight")
	await flush(20)
	for i in vents.size():
		almost(vents[i].clock(), clocks[i], 0.0001, "%s does not advance without a fight" % vents[i].name)
	# 开战：boss_intro_started 之后由东翼逐帧推进，走完一个预警就喷出来。
	GameEvents.boss_intro_started.emit(ExecutionerBoss.BOSS_TITLE)
	ok(wing.arena_vents_live(), "the fight starts the vents")
	var fired := false
	for i in 80:
		wing._physics_process(0.1)
		for vent in vents:
			if vent.state() == CyclicHazard.State.ACTIVE:
				fired = true
		if fired:
			break
	ok(fired, "a vent reaches its active window during phase one")
	ok(not wing.arena_vents_hot())
	var cool_rest: float = vents[0].rest_time
	# 二阶段更热：休止更短、喷得更高，重新对齐到休止期（不会没预警就喷）。
	GameEvents.boss_phase_changed.emit(ExecutionerBoss.BOSS_TITLE, 2)
	ok(wing.arena_vents_hot(), "phase two heats the vents")
	ok(vents[0].rest_time < cool_rest, "the hot vents rest less")
	ok(vents[0].reach > 64.0, "and reach higher")
	ok(vents[0].telegraph_time >= CyclicHazard.MIN_TELEGRAPH, "the hot telegraph stays readable")
	ok(vents[0].state() != CyclicHazard.State.ACTIVE, "re-timing never leaves a vent firing without warning")
	# Boss 倒下：喷火口立刻收刀、停转。
	boss.health.take_damage(99, null)
	ok(not wing.arena_vents_live(), "the vents stop the moment he falls")
	for vent in vents:
		ok(vent.state() == CyclicHazard.State.REST, "%s is back at rest" % vent.name)
	var after: Array[float] = []
	for vent in vents:
		after.append(vent.clock())
	for i in 40:
		wing._physics_process(0.1)
	for i in vents.size():
		almost(vents[i].clock(), after[i], 0.0001, "%s stays dead after the fight" % vents[i].name)
	Engine.time_scale = 1.0
	await _free(level)


func test_a_cleared_run_never_starts_the_vents() -> void:
	SaveData.mark_flag("boss_dead")
	var level := await _load_level()
	var wing := level.get_node("EastWing") as Level01EastWing
	GameEvents.boss_intro_started.emit(ExecutionerBoss.BOSS_TITLE)
	ok(not wing.arena_vents_live(), "no boss, no vents")
	await _free(level)


# --- 9. 东半的装饰：真实贴图、接地 ----------------------------------------------------------

func test_east_dressing_is_real_grounded_props() -> void:
	var level := await _load_level()
	var decor := level.get_node_or_null("CathedralDecor") as Node2D
	ok(decor != null, "the east decor layer exists")
	var props := 0
	var tops := LevelSanity.top_segments(level)
	for node in LevelSanity._descendants(decor):
		ok(not (node is ColorRect), "%s is not a colour block" % node.name)
		var spr := node as Sprite2D
		if spr == null or not spr.has_meta("prop_key"):
			continue
		props += 1
		eq(spr.scale, Vector2.ONE, "%s is drawn at 1x" % spr.name)
		if spr.is_in_group("grounded") and spr.has_meta("feet"):
			ok(LevelSanity.standing_on(tops, spr.get_meta("feet")) != null, "%s stands on a platform top" % spr.name)
	ok(props >= 20, "the east half is dressed (%d props)" % props)
	for key in ROUTE.ALLOWED_DECOR:
		ok(PropCatalog.DECOR.has(String(key)), "'%s' is a catalogued decor key" % key)
	await _free(level)
