extends ChapterLayout
## 铸钟厅：浇铸台160 → 冷却台224 → 钟模坑288 → 钟模场320。
## 两条向下熔注线跟随吊台时钟；固定槽底负责失足回收。

const POUR := preload("res://scripts/levels/chapters/level07b_pour.gd")
const MOULD_RAMP := preload("res://scripts/levels/chapters/level07b_mould_ramp.gd")
const ENTRY_SPAWN := Vector2(96, 140)
const EAST_LIMIT := 4320
const CEILING_Y := -192.0
const SKIN := "iron"
const FLOAT_SKIN := "iron_float"
const TORCH_TINT := Color(1.0, 0.82, 0.6)
const GIRDER_TINT := Color(0.86, 0.72, 0.6)
const PIPE_TINT := Color(0.8, 0.68, 0.58)
const RUBBLE_TINT := Color(1.0, 0.84, 0.68)
const CHAIN_TINT := Color(0.62, 0.56, 0.52, 0.85)

## [name, west, east, top]，槽底不加默认毒池，走错仍能返回下一个接驳点。
const FLOORS: Array = [
	["FloorA", 0.0, 448.0, 160.0],
	["LadleRecovery", 448.0, 768.0, 256.0],
	["FloorB", 768.0, 1408.0, 224.0],
	["CoolStep", 1408.0, 1472.0, 256.0],
	["FloorC", 1472.0, 1856.0, 288.0],
	["MoldRecovery", 1856.0, 2080.0, 320.0],
	["FloorD", 2080.0, 2752.0, 288.0],
	["CastRecovery", 2752.0, 3008.0, 352.0],
	["CastStairA", 3008.0, 3072.0, 320.0],
	["FloorE", 3072.0, 4320.0, 320.0],
]
const STEPS: Array = [
	["MoldStep", Vector2(1504, 256), 64.0],
	["MoldCatwalk", Vector2(1080, 80), 192.0],
	["ReturnEnd", Vector2(2192, 192), 96.0],
	["ReturnB", Vector2(2320, 192), 96.0],
	["ReturnC", Vector2(2448, 192), 96.0],
	["ReturnD", Vector2(2576, 192), 128.0],
	["ReturnLaunch", Vector2(2736, 224), 80.0],
	["ReturnStair", Vector2(2688, 256), 64.0],
	["ArenaSideWest", Vector2(3280, 288), 64.0],
	["ArenaSideEast", Vector2(4048, 288), 64.0],
]
const LIFT_A_POS := Vector2(480, 176)
const LIFT_B_POS := Vector2(1888, 272)
const LIFT_A_TRAVEL := Vector2(176, 32)
const LIFT_B_TRAVEL := Vector2(96, 0)
const LIFT_PERIOD := 8.0
const LIFT_WIDTH := 80.0
const MOLD_DECK_POS := Vector2(1568, 224)
const MOLD_DECK_SIZE := Vector2(160, 32)
const PLATE_FEET := Vector2(1608, 224)
const MOLD_DOOR_POS := Vector2(1808, 224)
const HOOK_MOLD_POS := Vector2(1152, -16)
const STELE_KEY_POS := Vector2(1128, 80)
const REWARD_POS := Vector2(1216, 32)
const NEST_ENTRY_X := 176.0
const NEST_LADLE_X := 1168.0
const NEST_COOLING_X := 2160.0
const NEST_BOSS_X := 3152.0
const STELE_MOLD_POS := Vector2(1328, 224)
const STELE_FOUNDER_POS := Vector2(2240, 288)
const EXIT_X := 4240.0
const BOSS_NAME := "BellFounder"
const BOSS_KIND := "bell_founder"
const BOSS_POS := Vector2(3696, 288)
const ARENA_LEFT := 3216.0
const ARENA_RIGHT := 4144.0

## 三组主线遭遇，加一只只在钩锁猫道唤醒的奖励守卫。
const ENEMIES: Array = [
	["Scrapper1", "scrapper", Vector2(928, 224), {"patrol_range": 16.0, "aggro_range": 80.0, "lose_range": 176.0}],
	["Spitter1", "spitter", Vector2(1040, 224), {"aggro_range": 80.0, "lose_range": 160.0}],
	["Ghost1", "ghost", Vector2(1184, 40), {"wake_range": 72.0, "arena_left": 1080.0, "arena_right": 1272.0}],
	["Ghost2", "ghost", Vector2(1648, 160), {"wake_range": 96.0, "arena_left": 1472.0, "arena_right": 1776.0}],
	["Spitter2", "spitter", Vector2(1760, 288), {"aggro_range": 128.0, "lose_range": 224.0}],
	["Scrapper2", "scrapper", Vector2(1664, 224), {"variant": &"armored_scrapper", "patrol_range": 16.0, "aggro_range": 100.0, "lose_range": 200.0}],
	["GearShield1", "gear_shield", Vector2(2512, 288), {"variant": &"heavy_guard", "aggro_range": 128.0, "patrol_range": 16.0, "lose_range": 224.0}],
	["Scrapper3", "scrapper", Vector2(2816, 352), {"variant": &"armored_scrapper", "patrol_range": 16.0, "aggro_range": 96.0, "lose_range": 192.0}],
	["FlyingDemon1", "flying_demon", Vector2(2896, 264), {"aggro_range": 128.0, "patrol_range": 24.0, "lose_range": 208.0}],
]
const PROPS: Array = [
	["beam", Vector2(256, 160)], ["rubble_dry_b", Vector2(368, 160)],
	["metal_panel", Vector2(864, 224)], ["pipe_valve", Vector2(1000, 224)],
	["rubble_dry_c", Vector2(1376, 224)], ["broken_machine", Vector2(1520, 256)],
	["girder_l", Vector2(1840, 288)], ["bones", Vector2(2128, 288)],
	["pipe_valve", Vector2(2352, 288)], ["girder_r", Vector2(2608, 288)],
	["rubble_dry_b", Vector2(2944, 352)], ["plate", Vector2(3184, 320)],
	["column", Vector2(3264, 320)], ["broken_machine", Vector2(3888, 320)],
	["metal_panel", Vector2(3696, 288)], ["column", Vector2(4096, 320)],
]
const TORCHES: Array = [Vector2(96, 160), Vector2(800, 224), Vector2(1328, 224),
	Vector2(1760, 288), Vector2(2160, 288), Vector2(2640, 288), Vector2(3152, 320),
	Vector2(3456, 320), Vector2(3936, 320), Vector2(4192, 320)]


func level_id() -> String:
	return "level07b"


func title() -> String:
	return ChapterText.title_of(level_id())


func wake_line() -> String:
	return ChapterText.wake_of(level_id())


func entry_spawn() -> Vector2:
	return ENTRY_SPAWN


func east_limit() -> int:
	return EAST_LIMIT


func camera_top() -> int:
	return -224


func theme() -> String:
	return "forge"


func motes() -> String:
	return "embers"


func _stele(host: Node2D, node_name: String, pos: Vector2) -> void:
	var entry := ChapterText.stele_of(level_id(), node_name)
	stele(host, node_name, pos, String(entry.get("title", "")), String(entry.get("text", "")))


func build(host: Node2D) -> void:
	_build_terrain(host)
	_build_mechanics(host)
	_build_props(host)
	for e in ENEMIES:
		enemy(host, String(e[0]), String(e[1]), e[2], e[3])
	_build_decor(host)
	var exit := exit_door(host, EXIT_X, ChapterText.exit_label_of(level_id()),
			ChapterText.exit_captions_of(level_id()), "level07b_done", GameContext.next_level_id(level_id()))
	if ResourceLoader.exists("res://scenes/enemies/BellFounder.tscn"):
		exit.requires_flag = "founder_dead"
		exit.locked_prompt = "钟还没浇完。铸钟人挡着路。"
	_build_boss(host)
	finish(host)


func _build_terrain(host: Node2D) -> void:
	for f in FLOORS:
		floor_strip(host, String(f[0]), float(f[1]), float(f[2]), SKIN, true, true, float(f[3]))
	for s in STEPS:
		step(host, String(s[0]), s[1], float(s[2]), FLOAT_SKIN)
	platform(host, "MoldDeck", MOLD_DECK_POS, MOLD_DECK_SIZE, "basalt")
	# 顶160不可从224压板台跳上；底208与门顶224之间只有16px，不容26px骑士钻过。
	platform(host, "MoldGateLintel", Vector2(1776, 160), Vector2(80, 48), SKIN)
	platform(host, "BellMould", Vector2(3600, 288), Vector2(176, 32), "basalt")
	for row in [["MouldRampWest", Vector2(3536, 288), true], ["MouldRampEast", Vector2(3776, 288), false]]:
		var ramp := MOULD_RAMP.new()
		ramp.name = String(row[0])
		ramp.position = row[1]
		ramp.rises_right = bool(row[2])
		group(host, "Platforms").add_child(ramp)
	enclose(host, SKIN, CEILING_Y)


func _build_mechanics(host: Node2D) -> void:
	var a := lift(host, "LiftA", LIFT_A_POS, LIFT_A_TRAVEL, LIFT_PERIOD, LIFT_WIDTH, 0.0, CEILING_Y + 32)
	var b := lift(host, "LiftB", LIFT_B_POS, LIFT_B_TRAVEL, LIFT_PERIOD, LIFT_WIDTH, 0.5, CEILING_Y + 32)
	# 吊台共用苔石素材，这里压成铸铁暖褐，避免炉厅里出现绿色台面。
	a.modulate = Color(1.5, 0.68, 0.42)
	b.modulate = a.modulate
	_pour(host, "PourLadle", Vector2(632, 80), 176.0, a)
	_pour(host, "PourCool", Vector2(2032, 176), 144.0, b)
	plate_door(host, "MoldGate", PLATE_FEET, MOLD_DOOR_POS)
	hook(host, "HookMold", HOOK_MOLD_POS)
	waymark(host, Vector2(368, 160), "吊包")
	waymark(host, Vector2(2680, 288), "回炉")
	waymark(host, Vector2(3096, 320), "浇铸")


func _pour(host: Node2D, node_name: String, pos: Vector2, length: float,
		linked_lift: MovingPlatform = null, ignited: bool = true) -> CyclicHazard:
	var hazard := POUR.new()
	hazard.name = node_name
	hazard.position = pos
	hazard.skin = "slag"
	hazard.facing = Vector2.DOWN
	hazard.reach = length
	hazard.thick = 24.0
	hazard.rest_time = 6.2 if linked_lift != null else 3.2
	hazard.telegraph_time = 0.8
	hazard.active_time = 1.0
	hazard.hint_id = &"slag" if linked_lift != null else &""
	hazard.lift_ref = linked_lift
	hazard.ignited = ignited
	group(host, "Props").add_child(hazard)
	return hazard


func _build_props(host: Node2D) -> void:
	nest(host, "EmberNestEntry", NEST_ENTRY_X, 160)
	nest(host, "EmberNestLadle", NEST_LADLE_X, 224)
	nest(host, "EmberNestCooling", NEST_COOLING_X, 288)
	nest(host, "EmberNestCast", NEST_BOSS_X, 320)
	_stele(host, "SteleMold", STELE_MOLD_POS)
	_stele(host, "SteleFounder", STELE_FOUNDER_POS)
	_stele(host, "SteleKey", STELE_KEY_POS)
	pickup(host, "CoreReward", REWARD_POS, &"kiln_core")


func _build_decor(host: Node2D) -> void:
	for item in PROPS:
		var tint := RUBBLE_TINT
		if String(item[0]) in ["girder_l", "girder_r", "broken_machine"]:
			tint = GIRDER_TINT
		elif String(item[0]) == "pipe_valve":
			tint = PIPE_TINT
		prop(host, String(item[0]), item[1], 1.0, tint)
	for feet in TORCHES:
		torch(host, feet.x, feet.y, TORCH_TINT)
	for x in [632.0, 2032.0, 3376.0, 4016.0]:
		hanging(host, "chain", Vector2(x, CEILING_Y + 32.0), CHAIN_TINT)


func _build_boss(host: Node2D) -> void:
	var b := boss(host, BOSS_NAME, BOSS_KIND, BOSS_POS, ARENA_LEFT, ARENA_RIGHT)
	if b == null:
		return
	var arena := boss_arena(host, BOSS_NAME) as BossArena
	if arena == null:
		return
	arena.floor_y = 320.0
	var west := _pour(host, "CastPillarWest", Vector2(3376, 160), 160.0, null, false)
	var east := _pour(host, "CastPillarEast", Vector2(4016, 160), 160.0, null, false)
	arena.register_hazard(&"cast_pillar_west", west)
	arena.register_hazard(&"cast_pillar_east", east)
	arena.arena_cleared.connect(west.stop)
	arena.arena_cleared.connect(east.stop)
