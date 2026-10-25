extends ChapterLayout
## 锈墓・拾叁 — 炉风崖道 (level09b)：翻过城墙，炉心就在崖下。这一段是城墙外壁的
## 崖道：上层的风口桥被炉风吹得晃，下层是被风刮下来的灰道。
##
## 尺寸 ≥3200×720（竖向+横向混合）。主题用城墙的 ramparts（室外）；结构：
##   ① 崖道      0–1120    崖顶台地（起点）→ 三段落差踏台 → 风口桥前的狭台
##   ② 风口桥    1120–1720 浮石跨过风口：风把余烬吹成横的，桥上有周期落石
##                          （BossArena.HazardNode 的 ROCKFALL，0.55s 预警）；
##                          桥东压板开「风口闸」，闸后才进得了前哨
##   ③ 炉门前哨  1760–2120 安全的余烬巢（GaleLee：风被岩壁挡掉大半），碑文
##   ④ 上攀段    2120–2528 三段踏台爬上风口台（GateDeck），碑「门」
##   ⑤ 下崖      2528–2680 从风口台跳下崖底灰道
##   ⑥ Boss 房   2680–3400 炉门前的石台；Boss「炉风先驱」位（缺失时跳过）
##   出口 3320 → level10（炉门，门下就是炉心）
##
## 崖底灰道（FloorLow，整条 y=320）是失足者的兜底，也是下层遭遇的走道：
## 从崖道或风口桥掉下去不会摔死/锁死，可以沿灰道走回风口台下的落点。
## 上层还有一条钩锁支路：风口桥正上方的 LeeLedge，只有钩锁上得去（碑文/奖励）。
##
## 文本全部来自 ChapterText（story-lead 所有）；这里只放几何与位置常量。

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
## [name, pos(左上角), width] —— 上层崖道踏台（16 厚，全部浮在灰道上方）
const STEPS: Array = [
	["CliffTop", Vector2(0, -320), 400.0],
	["StepA1", Vector2(432, -288), 48.0],
	["StepA2", Vector2(512, -256), 48.0],
	["StepA3", Vector2(592, -224), 48.0],
	["LedgeB", Vector2(656, -192), 304.0],
	["StepB1", Vector2(992, -160), 48.0],
	["StepB2", Vector2(1072, -128), 48.0],
	["BridgeWest", Vector2(1120, -96), 96.0],
	["Stone1", Vector2(1264, -96), 48.0],
	["Stone2", Vector2(1344, -80), 48.0],
	["Stone3", Vector2(1424, -64), 48.0],
	["Stone4", Vector2(1504, -48), 48.0],
	["BridgeEast", Vector2(1552, -32), 168.0],
	["Climb1", Vector2(2144, -32), 48.0],
	["Climb2", Vector2(2224, -64), 48.0],
	["Climb3", Vector2(2304, -96), 48.0],
	["GateDeck", Vector2(2384, -128), 144.0],
	["DescentLedge", Vector2(2560, -32), 64.0],
	# 风口桥正上方的钩锁支路台面（只有钩锁上得来）。
	["LeeLedge", Vector2(1360, -224), 112.0],
]
## [name, pos(左上角), size] —— 前哨平台（厚 32，直接压在灰道上方的岩壁）
const OUTPOST := ["OutpostDeck", Vector2(1760, 0), Vector2(360, 32)]
## 风口闸：压板在桥东（BridgeEast 台面），闸门立在前哨入口（前哨台面上）。
const PLATE_FEET := Vector2(1600, -32)
const WIND_DOOR_POS := Vector2(1776, -64)

const NEST_CLIFF_X := 176.0
const NEST_OUTPOST_X := 1848.0
const NEST_GATE_X := 2680.0
const STELE_ASH_POS := Vector2(240, -320)
const STELE_HERALD_POS := Vector2(1936, 0)
const STELE_GATE_POS := Vector2(2416, -128)
## 钩锁支路：从 Stone2/Stone3 起钩（索距 ≤250），落台在锚点下方 96px。
const HOOK_LEE_POS := Vector2(1416, -320)
const REWARD_POS := Vector2(1416, -256)
const EXIT_X := 3320.0

## Boss 位：炉风先驱。场景由 bosses-b 交付，缺失时 boss() 跳过（不报错）。
const BOSS_NAME := "EmberwindHerald"
const BOSS_KIND := "emberwind_herald"
const BOSS_POS := Vector2(3050, 320)
const ARENA_LEFT := 2740.0
const ARENA_RIGHT := 3400.0
## 风口桥落石：三个落点轮换，预警 0.55s（契约 §4.1 可读性下限 0.35s）。
const ROCKFALL_SPOTS: Array = [
	Vector2(1188, -144),
	Vector2(1368, -128),
	Vector2(1608, -80),
]
const ROCKFALL_PERIOD := 3.2

## [name, kind, pos, overrides]
const ENEMIES: Array = [
	["Spitter1", "spitter", Vector2(780, -192), {}],
	["FlyingDemon1", "flying_demon", Vector2(1200, -220), {"patrol_range": 72.0}],
	["FlyingDemon2", "flying_demon", Vector2(1480, -180), {"patrol_range": 72.0}],
	["Ghost1", "ghost", Vector2(1984, 40), {}],
	["Scrapper1", "scrapper", Vector2(900, 320), {"patrol_range": 40.0}],
	["GearShield1", "gear_shield", Vector2(2000, 320), {}],
	["Skeleton1", "skeleton", Vector2(2440, 320), {}],
	["Ghost2", "ghost", Vector2(2620, 240), {}],
]
## [key, feet] —— ramparts 白名单：女墙、门洞、风化石、机械残骸、生活残留。
const PROPS: Array = [
	["balustrade_wall", Vector2(40, -320)],
	["rubble_dry", Vector2(300, -320)],
	["ruin_tower", Vector2(720, -192)],
	["balustrade", Vector2(1160, -96)],
	["balustrade", Vector2(1656, -32)],
	["door_arch_wall", Vector2(2088, 0)],
	["rubble_dry", Vector2(520, 320)],
	["rock_pile", Vector2(1500, 320)],
	["life_remains", Vector2(2250, 320)],
	["broken_machine", Vector2(2360, 320)],
	["fence", Vector2(2500, 320)],
	["warning_plate", Vector2(2620, 320)],
	["rubble_dry_c", Vector2(2820, 320)],
	["balustrade_wall", Vector2(3200, 320)],
]
const BUSHES: Array = [
	[Vector2(920, -192), 1.0],
	[Vector2(2144, 320), 1.0],
]
const WAYMARKS: Array = [
	[Vector2(352, -320), "风口"],
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
		{"name": "GaleBridge", "rect": Rect2(1120, -240, 600, 560),
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
	platform(host, String(OUTPOST[0]), OUTPOST[1], OUTPOST[2], SKIN, true, true)
	walls(host, SKIN, CAMERA_TOP)


func _build_mechanics(host: Node2D) -> void:
	plate_door(host, "WindGate", PLATE_FEET, WIND_DOOR_POS)
	hook(host, "HookLee", HOOK_LEE_POS)
	for w in WAYMARKS:
		waymark(host, w[0], String(w[1]))


func _build_props(host: Node2D) -> void:
	nest(host, "EmberNestCliff", NEST_CLIFF_X, -320.0)
	nest(host, "EmberNestOutpost", NEST_OUTPOST_X, 0.0)
	nest(host, "EmberNestGate", NEST_GATE_X)
	_stele(host, "SteleAsh", STELE_ASH_POS)
	_stele(host, "SteleHerald", STELE_HERALD_POS)
	_stele(host, "SteleGate", STELE_GATE_POS)
	pickup(host, "CoreReward", REWARD_POS, &"ember_core")


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
	# 风口桥两端垂下的旧铁链：挂在 BridgeWest / BridgeEast 的底沿（顶面 -96/-32，
	# 16 厚，底沿 -80/-16），不接地。旧坐标（x,-96）悬在半空。
	for pair in [[1208.0, -80.0], [1696.0, -16.0]]:
		hanging(host, "chain", Vector2(pair[0], pair[1]), CHAIN_TINT)


## 风口桥落石：独立的 BossArena 机关架（不激活、不锁门、不夹相机），
## 每 3.2s 在三个落点之一生成一次 ROCKFALL——预警 0.55s，命中 1 点伤害。
## 只有真实游玩才走 Timer；裸 Node2D 的构建测试里不会提前生成机关。
func _build_bridge_rockfall(host: Node2D) -> void:
	_rock_rig = BossArena.new()
	_rock_rig.name = "BridgeRockfallRig"
	_rock_rig.arena_left = 1100.0
	_rock_rig.arena_right = 1740.0
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
	var rock: Node2D = arena.make_hazard(BossArena.HazardKind.ROCKFALL, Vector2(2860, 168),
			{"name": "HeraldRockfall", "telegraph": 0.6, "active": 0.3, "damage": 1,
			"size": Vector2(56, 40)})
	arena.register_hazard(&"herald_rockfall", rock)
	var fire: Node2D = arena.make_hazard(BossArena.HazardKind.FIRE_PILLAR, Vector2(3220, 320),
			{"name": "HeraldFurnace", "telegraph": 0.55, "active": 0.3, "damage": 1})
	arena.register_hazard(&"herald_furnace", fire)
