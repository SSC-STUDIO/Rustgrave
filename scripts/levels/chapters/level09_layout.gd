extends ChapterLayout
## 锈墓・玖 — 锈城城墙：城墙顶上的长路，风从熔炉那边吹来，通往炉心大门。
## 室外（town），石板步道 + 三座塔楼；步道之间的缺口是积着腐液的排水沟，
## 用浮石架桥。主角敌人是缺口上空巡逻的飞行恶魔与塔顶的喷吐者。
##
## 结构（地面 y=320，一跳台阶 ≤32px、横跨 ≤72px）：
##   ① 城墙梯口   0–448     巢、碑、路牌、栏杆
##   ② 第一段步道 448–720   排水沟 A 上的三块浮石
##   ③ 塔楼一     720–1152  两级 32px 台阶上 64px 塔顶，喷吐者；碎铁犬守塔东
##   ④ 长缺口     1152–1472 排水沟 B：三块浮石 + 两只飞行恶魔
##   ⑤ 中段       1472–2048 第二巢、碑；塔楼二顶上的压板开步道上的闸门
##   ⑥ 风口       2048–2512 排水沟 C：五块短浮石（间距 48）+ 飞行恶魔
##   ⑦ 塔楼三     2512–3200 第三巢；96px 塔顶喷吐者；钩锁捷径接余烬核 + 碑文「鹰」
##                         ——本章支路；幽魂与碎铁犬守着炉心大门

const EAST_LIMIT := 3200
const ENTRY_SPAWN := Vector2(96, 300)
const SKIN := "rampart"
## 城墙缝里的草是风干的：鲜绿灌木压成冷灰橄榄，和雾青石墙同温。
const DRY_BUSH := Color(0.74, 0.78, 0.7)
const PIT_DEPTH := 32.0

## [name, x0, x1, cap_left, cap_right] —— 墙顶步道（80px 厚，顶在 320）
const FLOORS: Array = [
	["FloorA", 0.0, 448.0, false, true],
	["FloorB", 720.0, 1152.0, true, true],
	["FloorC", 1472.0, 2048.0, true, true],
	["FloorD", 2512.0, 3200.0, true, false],
]
## [name, x0, x1] —— 排水沟：坑底 352，液面 336..368，两侧 32px 一跳爬出
const PITS: Array = [
	["PitA", 448.0, 720.0],
	["PitB", 1152.0, 1472.0],
	["PitC", 2048.0, 2512.0],
]
## [name, pos, size] —— 塔楼与台阶：stone 方块，每级抬 32px。
## 64/96 高的塔身拆成 32px 的叠石：LevelSanity 的净空检查会把一整块
## 从地面砌到塔顶的实心读成「没有净空的墙」；叠成每层 32 后，
## 每一层都只是上一层的台阶，墙顶仍能站人。
const TOWERS: Array = [
	["TowerAStep", Vector2(832, 288), Vector2(64, 32)],
	["TowerABase", Vector2(896, 288), Vector2(96, 32)],
	["TowerA", Vector2(896, 256), Vector2(96, 32)],
	["TowerBStep", Vector2(1744, 288), Vector2(64, 32)],
	["TowerBBase", Vector2(1808, 288), Vector2(128, 32)],
	["TowerB", Vector2(1808, 256), Vector2(128, 32)],
	["TowerCStep1", Vector2(2736, 288), Vector2(64, 32)],
	["TowerCStep2Base", Vector2(2800, 288), Vector2(64, 32)],
	["TowerCStep2", Vector2(2800, 256), Vector2(64, 32)],
	["TowerCBase2", Vector2(2864, 288), Vector2(96, 32)],
	["TowerCBase1", Vector2(2864, 256), Vector2(96, 32)],
	["TowerC", Vector2(2864, 224), Vector2(96, 32)],
]
## [name, pos, width] —— 浮石（16px 厚，教堂浮石皮肤）
const STONES: Array = [
	["StoneA1", Vector2(496, 288), 48.0],
	["StoneA2", Vector2(576, 264), 48.0],
	["StoneA3", Vector2(656, 288), 48.0],
	["StoneB1", Vector2(1200, 288), 48.0],
	["StoneB2", Vector2(1296, 256), 48.0],
	["StoneB3", Vector2(1392, 288), 48.0],
	["WindS1", Vector2(2096, 288), 32.0],
	["WindS2", Vector2(2176, 264), 32.0],
	["WindS3", Vector2(2256, 288), 32.0],
	["WindS4", Vector2(2336, 264), 32.0],
	["WindS5", Vector2(2416, 288), 32.0],
	# 塔楼三旁的哨台：只有钩锁能上去，上面悬着余烬核
	["EyrieC", Vector2(2960, 160), 64.0],
]
## 主路线上每一段跳跃链的脚点（测试用）：台面 y 与 x 的落点
const CHAIN_A: Array = [Vector2(448, 320), Vector2(496, 288), Vector2(576, 264), Vector2(656, 288), Vector2(720, 320)]
const CHAIN_B: Array = [Vector2(1152, 320), Vector2(1200, 288), Vector2(1296, 256), Vector2(1392, 288), Vector2(1472, 320)]
const CHAIN_WIND: Array = [Vector2(2048, 320), Vector2(2096, 288), Vector2(2176, 264), Vector2(2256, 288),
		Vector2(2336, 264), Vector2(2416, 288), Vector2(2512, 320)]

const NEST_GATE_X := 176.0
const NEST_MID_X := 1544.0
const NEST_EAST_X := 2536.0
const STELE_WALL_POS := Vector2(264, 320)
const STELE_WIND_POS := Vector2(1624, 320)
## 压板在塔楼二顶上；闸门封住塔楼二东侧的步道（门 16×64，底在 320）
const PLATE_FEET := Vector2(1904, 256)
const GATE_DOOR_POS := Vector2(1984, 256)
const HOOK_POS := Vector2(2992, 80)
const EMBER_CORE_POS := Vector2(2992, 136)
## 支路碑文站在哨台西端：和核、锚点错开，只有钩锁上得来。
const STELE_EYRIE_POS := Vector2(2968, 160)
const EXIT_X := 3096.0

## [name, kind, pos, overrides]
const ENEMIES: Array = [
	["Spitter1", "spitter", Vector2(944, 256), {}],
	["Scrapper1", "scrapper", Vector2(1072, 320), {"patrol_range": 40.0}],
	["Demon1", "flying_demon", Vector2(1232, 208), {"patrol_range": 72.0}],
	["Demon2", "flying_demon", Vector2(1400, 192), {"patrol_range": 72.0}],
	["Spitter2", "spitter", Vector2(1832, 256), {}],
	["Demon3", "flying_demon", Vector2(2272, 200), {"patrol_range": 72.0}],
	["Spitter3", "spitter", Vector2(2912, 224), {}],
	["Ghost1", "ghost", Vector2(3000, 244), {}],
	["Scrapper2", "scrapper", Vector2(3032, 320), {"patrol_range": 24.0}],
]

## [key, feet, z] —— 女墙、残碑、塔门；z=1 让塔门画在塔身石板之上
## 室外城墙不用壁炬墙板（bg_wall_torch 是室内板）。
const PROPS: Array = [
	# 城墙用女墙、门洞、干石。墓碑（stone_*）立在墙顶上，读成墓园搬进城里。
	["balustrade_wall", Vector2(72, 320), 0],
	["rubble_dry", Vector2(232, 320), 0],
	["rubble_dry_c", Vector2(776, 320), 0],
	["balustrade_wall", Vector2(944, 256), 0],
	["door_arch_wall", Vector2(944, 320), 1],
	["balustrade_wall", Vector2(1032, 320), 0],
	["rubble_dry_c", Vector2(1504, 320), 0],
	# 中段：一座倒在城墙上的塔身，墙上唯一的大剪影。
	["ruin_tower", Vector2(1700, 320), -3],
	["balustrade_wall", Vector2(1872, 256), 0],
	["door_arch_wall", Vector2(1872, 320), 1],
	["balustrade_wall", Vector2(2696, 320), 0],
	["rubble_dry", Vector2(2764, 288), 0],
	["balustrade_wall", Vector2(2912, 224), 0],
	["door_arch_wall", Vector2(2912, 320), 1],
]
## [feet(左脚点), scale] —— 墙缝里长出来的几丛灌木
const BUSHES: Array = [
	[Vector2(300, 320), 1.0],
	[Vector2(1592, 320), 1.0],
	[Vector2(2640, 320), 1.0],
]
const WAYMARKS: Array = [[Vector2(352, 320), "城墙"], [Vector2(3048, 320), "炉心"]]


func level_id() -> String:
	return "level09"


func title() -> String:
	return "锈墓・玖 — 锈城城墙"


func wake_line() -> String:
	return "这墙挡的是炉风。灰是守墙的人。"


func entry_spawn() -> Vector2:
	return ENTRY_SPAWN


func east_limit() -> int:
	return EAST_LIMIT


func theme() -> String:
	return "ramparts"


## 墙挡的是炉风：黄昏，余烬风。
func ambient() -> Dictionary:
	return {"time": 0.56, "weather": "ember_wind", "hold": 360.0}


## 城墙上没有"随便什么天"：要么炉风，要么放晴，要么被风推着下雨。
## 换天比城里快 —— 站在风口上，天就是一阵一阵的。
func weather_recipe() -> Dictionary:
	return {
		"allowed": [WorldClock.Weather.EMBER_WIND, WorldClock.Weather.CLEAR,
				WorldClock.Weather.HAZE, WorldClock.Weather.RAIN],
		"weights": {
			"dusk": {"ember_wind": 5, "rain": 3, "clear": 1, "haze": 1},
			"night": {"rain": 4, "ember_wind": 3, "clear": 2, "haze": 1},
			"*": {"ember_wind": 4, "clear": 3, "haze": 2, "rain": 1},
		},
		"hold": Vector2(90.0, 170.0),
		"intensity": Vector2(0.7, 1.0),
	}


## ⑥ 风口（2048–2512）是三塔之间最敞的一段：雨直接打进来，风把余烬吹成横的。
## ⑦ 塔楼三的墙根（2512–2800）挡住大半炉风，只剩慢慢飘的灰 —— 不指定天气，
## 跟着基础态走，只把强度和风力压下来。
func weather_regions() -> Array:
	return [
		{"name": "GaleGap", "rect": Rect2(2048, 232, 464, 168),
			"weather": WorldClock.Weather.RAIN, "intensity": 1.0, "wind_scale": 1.5},
		{"name": "TowerLee", "rect": Rect2(2512, 236, 288, 164),
			"intensity": 0.4, "wind_scale": 0.35},
	]


func build(host: Node2D) -> void:
	_build_terrain(host)
	_build_props(host)
	_build_enemies(host)
	_build_decor(host)
	exit_door(host, EXIT_X, "炉心大门", PackedStringArray([
		"门后没有风，只有热。",
		"有一匹马不肯进炉，还守在芯前。",
	]), "level09_done", GameContext.next_level_id(level_id()))
	finish(host)


func _build_terrain(host: Node2D) -> void:
	for f in FLOORS:
		floor_strip(host, String(f[0]), float(f[1]), float(f[2]), SKIN, bool(f[3]), bool(f[4]))
	for p in PITS:
		toxin_pit(host, String(p[0]), float(p[1]), float(p[2]), PIT_DEPTH, SKIN)
	for t in TOWERS:
		platform(host, String(t[0]), t[1], t[2], SKIN)
	for s in STONES:
		step(host, String(s[0]), s[1], float(s[2]), "rampart_float")
	walls(host, SKIN)


func _build_props(host: Node2D) -> void:
	nest(host, "EmberNestGate", NEST_GATE_X)
	nest(host, "EmberNestMid", NEST_MID_X)
	nest(host, "EmberNestEast", NEST_EAST_X)
	stele(host, "SteleWall", STELE_WALL_POS, "城墙铭 · 挡",
			"这墙不挡人，挡风。风从炉心来。灰是守过这墙的人。")
	stele(host, "SteleWind", STELE_WIND_POS, "城墙铭 · 风",
			"风里有铁锈和烧焦的油味。墙下的灰，曾经会走路。")
	plate_door(host, "WallGate", PLATE_FEET, GATE_DOOR_POS)
	hook(host, "HookTower", HOOK_POS)
	pickup(host, "EmberCore", EMBER_CORE_POS, &"ember_core")
	stele(host, "SteleEyrie", STELE_EYRIE_POS, "城墙铭 · 鹰",
			"哨位空着。风替守墙人看路，看久了，把眼睛也磨成了灰。")
	for w in WAYMARKS:
		waymark(host, w[0], String(w[1]))


func _build_enemies(host: Node2D) -> void:
	for e in ENEMIES:
		enemy(host, String(e[0]), String(e[1]), e[2], e[3])


func _build_decor(host: Node2D) -> void:
	for p in PROPS:
		var tint := Color(0.8, 0.86, 0.9) if String(p[0]) == "ruin_tower" else Color.WHITE
		prop(host, String(p[0]), p[1], 1.0, tint, int(p[2]))
	for b in BUSHES:
		foliage(host, "bush_s", b[0], float(b[1]), false, DRY_BUSH)
