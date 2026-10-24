extends ChapterLayout
## 炉风崖道：上层东行顶余烬风，中层西返穿落石，下层东行跨塌桥和前哨。
## 最后一折降到先驱门前；灰道320继续兜底。故事、Boss本体和存档协议保持。

const ENTRY_SPAWN := Vector2(96, -340)
const EAST_LIMIT := 3400
const CAMERA_TOP := -400
const SKIN := "rampart"
const FLOAT_SKIN := "rampart_float"
## 城墙上的草是风干的：鲜绿灌木压成冷灰橄榄（同 level09）。
const DRY_BUSH := Color(0.74, 0.78, 0.7)
const DECK_TINT := Color(0.94, 0.92, 0.9)
const RUBBLE_TINT := Color(0.92, 0.88, 0.82)
const MACHINE_TINT := Color(0.82, 0.78, 0.74)
const CHAIN_TINT := Color(0.58, 0.55, 0.54, 0.85)

## 崖底灰道：整条 y=320，失足兜底 + 下层遭遇走道。
const FLOOR_LOW := ["FloorLow", 0.0, 3400.0]
## 三折：上层向东，中层向西，西折口落到下层再向东。永久薄台不堵低层。
const STEPS: Array = [
	["CliffTop", Vector2(0, -320), 1120.0],
	["EastTurnHigh", Vector2(1120, -256), 64.0],
	["EastTurnLow", Vector2(1184, -224), 64.0],
	["BridgeEast", Vector2(1056, -160), 128.0],
	["BridgeWest", Vector2(480, -160), 528.0],
	["WestTurnHigh", Vector2(432, -96), 48.0],
	["WestTurnLow", Vector2(432, -32), 48.0],
	["LowerWest", Vector2(480, 0), 720.0],
	["CollapsePier", Vector2(1328, 0), 64.0],
	["CollapseRecovery", Vector2(1120, 96), 432.0],
	["CollapseEscape1", Vector2(1488, 64), 32.0],
	["CollapseEscape2", Vector2(1520, 32), 32.0],
	["Climb1", Vector2(2152, 64), 96.0],
	["Climb2", Vector2(2280, 128), 96.0],
	["GateDeck", Vector2(2408, 192), 128.0],
	["DescentLedge", Vector2(2568, 256), 64.0],
	["LeeLedge", Vector2(1328, -320), 160.0],
	["HeraldWestPerch", Vector2(2800, 288), 96.0],
	["HeraldEastPerch", Vector2(3232, 288), 64.0],
]
## [name, pos(左上角), size] —— 前哨平台（厚 32，直接压在灰道上方的岩壁）
const OUTPOST := ["OutpostDeck", Vector2(1552, 0), Vector2(568, 32)]
## 风口闸：压板和闸门都落在前哨台面，先踩板再进入重盾卫驻地。
const PLATE_FEET := Vector2(1584, 0)
const WIND_DOOR_POS := Vector2(1776, -64)
const RETURN_DROP := Rect2(1008, -160, 48, 160)
const COLLAPSES: Array = [["CollapseWest", Vector2(1200, 0), 96.0], ["CollapseEast", Vector2(1424, 0), 96.0]]
const WINDS: Array = [
	["EmberLesson", Rect2(352, -424, 112, 104), Vector2(72, 0), 4.8],
	["EmberDescent", Rect2(2184, -32, 192, 192), Vector2(-80, 0), 5.2],
]
## 顺序按实际路程：折返后x会减小，不能只按横坐标算复跑距离。
const NESTS: Array = [["EmberNestCliff", 176.0, -320.0], ["EmberNestWind", 944.0, -320.0],
	["EmberNestFold", 592.0, -160.0], ["EmberNestBridge", 1088.0, 0.0],
	["EmberNestOutpost", 1848.0, 0.0], ["EmberNestGate", 2680.0, 320.0]]

const NEST_CLIFF_X := 176.0
const NEST_OUTPOST_X := 1848.0
const NEST_GATE_X := 2680.0
const STELE_ASH_POS := Vector2(240, -320)
const STELE_HERALD_POS := Vector2(1936, 0)
const STELE_GATE_POS := Vector2(2440, 192)
## 钩锁支路：从东折口起钩（索距 ≤250），落台在锚点下方56px；锚体留在镜头内。
const HOOK_LEE_POS := Vector2(1384, -376)
const REWARD_POS := Vector2(1368, -344)
const EQUIPMENT_FEET := Vector2(1440, -320)
const EXIT_X := 3320.0

## Boss 位：炉风先驱。场景由 bosses-b 交付，缺失时 boss() 跳过（不报错）。
const BOSS_NAME := "EmberwindHerald"
const BOSS_KIND := "emberwind_herald"
const BOSS_POS := Vector2(3050, 320)
const ARENA_LEFT := 2740.0
const ARENA_RIGHT := 3400.0
## 风口桥落石：三个落点轮换，预警 0.55s（契约 §4.1 可读性下限 0.35s）。
const ROCKFALL_SPOTS: Array = [
	Vector2(736, -192),
	Vector2(880, -192),
	Vector2(1120, -192),
]
const ROCKFALL_PERIOD := 3.2

## [name, kind, pos, overrides]
const ENEMIES: Array = [
	["Spitter1", "spitter", Vector2(672, -320), {"variant": &"scatter_spitter", "aggro_range": 128.0}],
	["Scrapper1", "scrapper", Vector2(784, -320), {"variant": &"armored_scrapper", "patrol_range": 16.0, "aggro_range": 96.0, "lose_range": 192.0}],
	["FlyingDemon1", "flying_demon", Vector2(832, -224), {"patrol_range": 16.0, "aggro_range": 80.0, "lose_range": 192.0}],
	["Ghost1", "ghost", Vector2(1672, -40), {"wake_range": 96.0, "arena_left": 1552.0, "arena_right": 1760.0}],
	["GearShield1", "gear_shield", Vector2(1648, 0), {"variant": &"heavy_guard", "patrol_range": 16.0, "aggro_range": 112.0, "lose_range": 200.0}],
	["Skeleton1", "skeleton", Vector2(2384, 320), {"variant": &"exploder_skeleton", "alert_radius": 96.0, "lose_range": 160.0}],
	["Ghost2", "ghost", Vector2(2464, 272), {"wake_range": 96.0, "arena_left": 2304.0, "arena_right": 2528.0}],
]
## [key, feet] —— ramparts 白名单：女墙、门洞、风化石、机械残骸、生活残留。
const PROPS: Array = [
	["balustrade_wall", Vector2(40, -320)],
	["rubble_dry", Vector2(300, -320)],
	["ruin_tower", Vector2(704, -320)],
	["balustrade", Vector2(1160, -160)],
	["balustrade", Vector2(1568, 0)],
	["door_arch_wall", Vector2(2088, 0)],
	["rubble_dry", Vector2(520, 320)],
	["rock_pile", Vector2(1344, 0)],
	["life_remains", Vector2(2250, 320)],
	["broken_machine", Vector2(2480, 192)],
	["fence", Vector2(2500, 320)],
	["warning_plate", Vector2(2620, 320)],
	["rubble_dry_c", Vector2(2820, 320)],
	["balustrade_wall", Vector2(3200, 320)],
]
const BUSHES: Array = [
	[Vector2(920, -320), 1.0],
	[Vector2(2144, 320), 1.0],
]
const WAYMARKS: Array = [
	[Vector2(352, -320), "风口"],
	[Vector2(1000, -320), "折返"],
	[Vector2(520, -160), "下崖"],
	[Vector2(1168, 0), "断桥"],
	[Vector2(2024, 0), "前哨"],
	[Vector2(2632, 320), "炉门"],
]

var _rock_rig: BossArena
var _rock_cycle := 0


func level_id() -> String:
	return "level09b"


func title() -> String:
	return ChapterText.title_of(level_id())


func wake_line() -> String:
	return ChapterText.wake_of(level_id())


## 碑文文本只从 ChapterText 取；位置常量留在这里（几何归关卡，文本归注册表）。
func _stele(host: Node2D, node_name: String, pos: Vector2) -> void:
	var entry := ChapterText.stele_of(level_id(), node_name)
	stele(host, node_name, pos, String(entry.get("title", "")), String(entry.get("text", "")))


func entry_spawn() -> Vector2:
	return ENTRY_SPAWN


func east_limit() -> int:
	return EAST_LIMIT


func camera_top() -> int:
	return CAMERA_TOP


func theme() -> String:
	return "ramparts"


func motes() -> String:
	return "cinders"


## 城墙外壁的风口：黄昏、余烬风（同 level09 的墙头天色，但更靠近炉心，风更热）。
func ambient() -> Dictionary:
	return {"time": 0.62, "weather": "ember_wind", "hold": 360.0}


## 崖道上只有炉风、放晴、雨和薄雾：风是主调，换天比城里快。
func weather_recipe() -> Dictionary:
	return {
		"allowed": [WorldClock.Weather.EMBER_WIND, WorldClock.Weather.HAZE,
				WorldClock.Weather.RAIN, WorldClock.Weather.CLEAR],
		"weights": {
			"dusk": {"ember_wind": 6, "haze": 2, "rain": 2, "clear": 1},
			"night": {"ember_wind": 5, "rain": 3, "haze": 2, "clear": 1},
			"*": {"ember_wind": 5, "haze": 3, "clear": 2, "rain": 1},
		},
		"hold": Vector2(80.0, 150.0),
		"intensity": Vector2(0.75, 1.0),
	}


## 风口桥那段是整关最敞的：雨横着打、风把余烬吹成流线。
## 炉门前哨被岩壁挡住大半炉风：只剩慢慢飘的灰（intensity/wind 都压低）。
func weather_regions() -> Array:
	return [
		{"name": "GaleBridge", "rect": Rect2(640, -288, 608, 160),
			"weather": WorldClock.Weather.RAIN, "intensity": 1.0, "wind_scale": 1.8},
		{"name": "GaleLee", "rect": Rect2(1760, -96, 360, 432),
			"intensity": 0.4, "wind_scale": 0.35},
	]


func build(host: Node2D) -> void:
	_build_terrain(host)
	_build_mechanics(host)
	_build_props(host)
	_build_enemies(host)
	_build_decor(host)
	_build_bridge_rockfall(host)
	var exit := exit_door(host, EXIT_X, ChapterText.exit_label_of(level_id()),
			ChapterText.exit_captions_of(level_id()), "level09b_done",
			GameContext.next_level_id(level_id()))
	if ResourceLoader.exists("res://scenes/enemies/EmberwindHerald.tscn"):
		exit.requires_flag = "herald_dead"
		exit.locked_prompt = "炉风还压着门。先驱没让开。"
	_build_boss(host)
	finish(host)


func _build_terrain(host: Node2D) -> void:
	floor_strip(host, String(FLOOR_LOW[0]), float(FLOOR_LOW[1]), float(FLOOR_LOW[2]), SKIN, false, false)
	for s in STEPS:
		step(host, String(s[0]), s[1], float(s[2]), FLOAT_SKIN, DECK_TINT)
	for row in COLLAPSES:
		collapsing(host, row[0], row[1], float(row[2]), FLOAT_SKIN, {"shake_time": 1.4, "respawn_time": 4.0}, DECK_TINT)
	platform(host, String(OUTPOST[0]), OUTPOST[1], OUTPOST[2], SKIN, true, true)
	walls(host, SKIN, CAMERA_TOP)


func _build_mechanics(host: Node2D) -> void:
	plate_door(host, "WindGate", PLATE_FEET, WIND_DOOR_POS)
	hook(host, "HookLee", HOOK_LEE_POS)
	for row in WINDS:
		force_zone(host, row[0], row[1], "ember", row[2], {"gust_period": float(row[3]), "gust_duty": 0.5, "phase": 0.5})
	for w in WAYMARKS:
		waymark(host, w[0], String(w[1]))


func _build_props(host: Node2D) -> void:
	for row in NESTS:
		nest(host, row[0], float(row[1]), float(row[2]))
	_stele(host, "SteleAsh", STELE_ASH_POS)
	_stele(host, "SteleHerald", STELE_HERALD_POS)
	_stele(host, "SteleGate", STELE_GATE_POS)
	pickup(host, "CoreReward", REWARD_POS, &"ember_core")
	reward(host, "RewardLee", EQUIPMENT_FEET - Vector2(0, 7), "equipment", "bone_charm")


func _build_enemies(host: Node2D) -> void:
	for e in ENEMIES:
		enemy(host, String(e[0]), String(e[1]), e[2], e[3] if e.size() > 3 else {})


func _build_decor(host: Node2D) -> void:
	for key in PROPS:
		var tint := RUBBLE_TINT
		if String(key[0]) == "broken_machine":
			tint = MACHINE_TINT
		prop(host, String(key[0]), key[1], 1.0, tint)
	for bush in BUSHES:
		foliage(host, "bush_s", bush[0], float(bush[1]), false, DRY_BUSH)
	# 风口台与灰道边垂下的旧铁链（挂在风口台沿下方，不接地）。
	for point in [Vector2(736, -144), Vector2(1120, -144), Vector2(1328, 16)]:
		hanging(host, "chain", point, CHAIN_TINT)


## 风口桥落石：独立的 BossArena 机关架（不激活、不锁门、不夹相机），
## 每 3.2s 在三个落点之一生成一次 ROCKFALL——预警 0.55s，命中 1 点伤害。
## 只有真实游玩才走 Timer；裸 Node2D 的构建测试里不会提前生成机关。
func _build_bridge_rockfall(host: Node2D) -> void:
	_rock_rig = BossArena.new()
	_rock_rig.name = "BridgeRockfallRig"
	_rock_rig.arena_left = 640.0
	_rock_rig.arena_right = 1248.0
	_rock_rig.arena_top = -400.0
	_rock_rig.arena_bottom = 400.0
	_rock_rig.floor_y = FLOOR_Y
	_rock_rig.start_on_intro = false
	_rock_rig.start_immediately = false
	_rock_rig.clamp_player = false
	_rock_rig.clamp_boss = false
	_rock_rig.solid_walls = false
	group(host, "Arenas").add_child(_rock_rig)
	var timer := Timer.new()
	timer.name = "RockfallTimer"
	timer.wait_time = ROCKFALL_PERIOD
	timer.one_shot = false
	timer.autostart = true
	timer.timeout.connect(_tick_bridge_rockfall)
	group(host, "Props").add_child(timer)


func _tick_bridge_rockfall() -> void:
	if _rock_rig == null or not is_instance_valid(_rock_rig):
		return
	var spot: Vector2 = ROCKFALL_SPOTS[_rock_cycle % ROCKFALL_SPOTS.size()]
	_rock_cycle += 1
	var rock := _rock_rig.make_hazard(BossArena.HazardKind.ROCKFALL, spot,
			{"name": "BridgeRock", "telegraph": 0.55, "active": 0.3, "damage": 1})
	if rock != null:
		rock.call("trigger")


## Boss 位：统一入口。场景缺失时完全不搭竞技场；交付后自动出现，并补上
## 契约 §4.1 要求的两个可读场地机关（炉风先驱：落石 + 炉口火柱）。
func _build_boss(host: Node2D) -> void:
	var b := boss(host, BOSS_NAME, BOSS_KIND, BOSS_POS, ARENA_LEFT, ARENA_RIGHT)
	if b == null:
		return
	var arena := boss_arena(host, BOSS_NAME)
	if arena == null:
		return
	# 420px自动唤醒本来会覆盖门前巢；本章在跨场门后才交回原Boss物理。
	# 不改Boss尺寸、攻击、导演或旗标，Area也不夹住玩家。
	b.set_physics_process(false)
	var approach := Area2D.new()
	approach.name = "HeraldApproach"
	approach.position = Vector2(ARENA_LEFT, -64)
	approach.collision_layer = 0
	approach.collision_mask = 2
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(ARENA_RIGHT - ARENA_LEFT, 448)
	col.position = shape.size * 0.5
	col.shape = shape
	approach.add_child(col)
	approach.body_entered.connect(func(body: Node2D) -> void:
		if body is Player and is_instance_valid(b):
			b.set_physics_process(true))
	group(host, "Props").add_child(approach)
	var rock: Node2D = arena.make_hazard(BossArena.HazardKind.ROCKFALL, Vector2(2860, 168),
			{"name": "HeraldRockfall", "telegraph": 0.6, "active": 0.3, "damage": 1,
			"size": Vector2(56, 40)})
	arena.register_hazard(&"herald_rockfall", rock)
	var fire: Node2D = arena.make_hazard(BossArena.HazardKind.FIRE_PILLAR, Vector2(3220, 320),
			{"name": "HeraldFurnace", "telegraph": 0.55, "active": 0.3, "damage": 1})
	arena.register_hazard(&"herald_furnace", fire)
