extends ChapterLayout
## 锈墓・叁 — 锈城街巷：地窟的门开在地面上的死城里。窗里有锈苔的光，街上没人。
##
## 结构（街面 y=320，一跳台阶 ≤32px、横跨 ≤64px）：
##   ① 街道      0–560     出生点、余烬巢、碑文、路牌、水沟石栏，一只碎铁犬教冲锋
##   ② 毒水沟    560–720   断桥两块石板（288/256）踩上屋顶 A（224）
##      屋顶     720–1360  屋顶 A→B（喷吐者）→C（压板）；屋顶 C 东侧两级实心石阶
##                         通街面，走街面的人也能从这里爬上去踩压板
##   ③ 城门      1360      压板在屋顶 C 上，闸门在街面；离最后一级石阶 64px、离屋顶
##                         160px，跳不到门顶上
##   ④ 广场      1360–1936 第二余烬巢；两只碎铁犬 + 一只飞魔；守墓者石像；
##                         塔楼屋顶（y=160）只能钩锁上去，悬着余烬核
##   ⑤ 窄巷      1936–2240 下沉 32px 的巷子，两侧矮屋檐口压顶，幽魂在两屋之间凝出
##   ⑥ 圣殿前阶  2240–2880 三级 32px 石阶（320/288/256）上前台；喷吐者守阶口，
##                         齿盾卫守门；出口「圣殿门」→ level04

const EAST_LIMIT := 2880
const ENTRY_SPAWN := Vector2(96, 300)

## 地面段 [name, x0, x1, top_y]
const FLOORS: Array = [
	["StreetA", 0.0, 560.0, 320.0],
	["StreetB", 720.0, 1360.0, 320.0],
	["Plaza", 1360.0, 1936.0, 320.0],
	["Alley", 1936.0, 2240.0, 352.0],
	["StairA", 2240.0, 2336.0, 320.0],
	["StairB", 2336.0, 2432.0, 288.0],
	["Terrace", 2432.0, 2880.0, 256.0],
]
## 悬空石台 [name, pos(左上), width, skin]
const STEPS: Array = [
	["BridgeA1", Vector2(592, 288), 48.0, "floating"],
	["BridgeA2", Vector2(672, 256), 48.0, "floating"],
	["RoofA", Vector2(760, 224), 128.0, "stone"],
	["RoofB", Vector2(952, 224), 96.0, "stone"],
	["RoofC", Vector2(1104, 224), 96.0, "stone"],
	["TowerRoof", Vector2(1784, 160), 144.0, "stone"],
	["EaveD", Vector2(1952, 256), 96.0, "stone"],
	["EaveE", Vector2(2112, 256), 96.0, "stone"],
]
## 实心石阶 [name, pos(左上), size]：屋顶 C 东侧下到街面的两级。
const BLOCKS: Array = [
	["RoofStepHigh", Vector2(1200, 256), Vector2(48, 64)],
	["RoofStepLow", Vector2(1248, 288), Vector2(48, 32)],
]
const CANAL_X0 := 560.0
const CANAL_X1 := 720.0
## 酸黄绿：夜街的青灰石板旁，原色毒液会读成一条水沟。
const TOXIN_TINT := Color(1.0, 1.25, 0.55)

const NEST_START_X := 176.0
const NEST_PLAZA_X := 1424.0
const STELE_WINDOW_POS := Vector2(248, 320)
const STELE_STAIR_POS := Vector2(2600, 256)
const SIGN_TOWN_POS := Vector2(328, 320)
const SIGN_TEMPLE_POS := Vector2(2288, 320)

## 压板脚点在屋顶 C 上；闸门左上角在街面（门 16×64，底在 320）。
const PLATE_FEET := Vector2(1152, 224)
const GATE_POS := Vector2(1360, 256)
## 钩锁锚点悬在塔楼屋顶上方；余烬核悬在屋顶上方 32px。
const HOOK_POS := Vector2(1856, 104)
const EMBER_CORE_POS := Vector2(1896, 128)
const EXIT_POS := Vector2(2760, 256)

## [name, kind, pos]：落地敌人给脚点，飞行/穿墙敌人给悬停中心。
const ENEMIES: Array = [
	["Scrapper1", "scrapper", Vector2(432, 320)],
	["Spitter1", "spitter", Vector2(1008, 224)],
	["Scrapper2", "scrapper", Vector2(1616, 320)],
	["Scrapper3", "scrapper", Vector2(1808, 320)],
	["FlyingDemon1", "flying_demon", Vector2(1712, 184)],
	["Ghost1", "ghost", Vector2(2096, 312)],
	["Spitter2", "spitter", Vector2(2464, 256)],
	["GearShield1", "gear_shield", Vector2(2656, 256)],
]

## 壁炬 [x, feet_y]：夜街的路灯。
const TORCHES: Array = [
	[112.0, 320.0], [1328.0, 320.0], [1488.0, 320.0],
	[2384.0, 288.0], [2688.0, 256.0], [2832.0, 256.0],
]
## 门脸：尖窗墙板缩小后当房子正面，屋顶石台压在上沿。[feet, scale]
const FACADES: Array = [
	[Vector2(824, 320), 0.5],
	[Vector2(1000, 320), 0.5],
	[Vector2(1152, 320), 0.5],
	[Vector2(1856, 320), 0.8333333],
	[Vector2(2000, 352), 0.4166667],
	[Vector2(2160, 352), 0.4166667],
]
## 装饰门洞（地窟出口 / 店门）：压暗以免读成机关闸门。
const ARCH_TINT := Color(0.62, 0.6, 0.72)


func level_id() -> String:
	return "level03"


func title() -> String:
	return "锈墓・叁 — 锈城街巷"


func wake_line() -> String:
	return "街上没有人。窗里亮着的，不是灯。"


func entry_spawn() -> Vector2:
	return ENTRY_SPAWN


func east_limit() -> int:
	return EAST_LIMIT


func theme() -> String:
	return "town"


func build(host: Node2D) -> void:
	_build_terrain(host)
	_build_props(host)
	_build_enemies(host)
	_build_decor(host)
	exit_door(host, EXIT_POS.x, "圣殿门", PackedStringArray([
		"圣殿门推开时没有声音。吊灯还亮着。",
		"梁上有什么东西动了一下，数了一个。",
	]), "level03_done", GameContext.next_level_id(level_id()), EXIT_POS.y)
	finish(host)


func _build_terrain(host: Node2D) -> void:
	for f in FLOORS:
		floor_strip(host, String(f[0]), float(f[1]), float(f[2]), "stone",
				float(f[1]) > 0.0, float(f[2]) < float(EAST_LIMIT), float(f[3]))
	toxin_pit(host, "Canal", CANAL_X0, CANAL_X1, 32.0, "stone", TOXIN_TINT)
	for s in STEPS:
		step(host, String(s[0]), s[1], float(s[2]), String(s[3]))
	for b in BLOCKS:
		platform(host, String(b[0]), b[1], b[2], "stone")
	walls(host, "stone")


func _build_props(host: Node2D) -> void:
	nest(host, "EmberNestStreet", NEST_START_X)
	nest(host, "EmberNestPlaza", NEST_PLAZA_X)
	stele(host, "SteleWindow", STELE_WINDOW_POS, "锈城纪事 · 窗",
			"炉火熄的那一夜，人们把门带上，往下走了。窗里现在亮着的不是灯，是锈苔。")
	stele(host, "SteleStair", STELE_STAIR_POS, "锈城纪事 · 阶",
			"圣殿的吊灯一直亮着。门里没有人祈祷，只有石像在数人。")
	waymark(host, SIGN_TOWN_POS, "锈城")
	waymark(host, SIGN_TEMPLE_POS, "圣殿")
	plate_door(host, "Gate", PLATE_FEET, GATE_POS)
	hook(host, "HookTower", HOOK_POS)
	pickup(host, "EmberCoreTower", EMBER_CORE_POS, &"ember_core")


func _build_enemies(host: Node2D) -> void:
	for e in ENEMIES:
		enemy(host, String(e[0]), String(e[1]), e[2])


func _build_decor(host: Node2D) -> void:
	for t in TORCHES:
		torch(host, float(t[0]), float(t[1]))
	for f in FACADES:
		prop(host, "window", f[0], float(f[1]))
	# ① 街道：骑士走出来的地窟门洞、灌木、碎石、水沟两岸的石栏
	prop(host, "door_arch", Vector2(40, 320), 1.0, ARCH_TINT)
	foliage(host, "bush_s", Vector2(368, 320), 1.0)
	prop(host, "rubble", Vector2(464, 320))
	prop(host, "balustrade", Vector2(520, 320))
	prop(host, "balustrade", Vector2(760, 320))
	# ② 屋顶下的街面：屋 A/B 之间的碎石、屋 B/C 之间的店门洞、屋 C 门前的灌木
	prop(host, "rubble", Vector2(920, 320))
	prop(host, "door_arch", Vector2(1072, 320), 1.0, ARCH_TINT)
	foliage(host, "bush_s", Vector2(1108, 320), 1.0)
	# ④ 广场：枯树、碎石、守墓者石像、灌木、塔楼脚下的灌木
	foliage(host, "tree_2", Vector2(1528, 320), 0.46)
	prop(host, "rubble", Vector2(1656, 320))
	prop(host, "statue", Vector2(1712, 320))
	foliage(host, "bush_l", Vector2(1752, 320), 0.6)
	foliage(host, "bush_s", Vector2(1836, 320), 1.0)
	# ⑤ 窄巷：檐口垂下的锈苔藤、巷底碎石
	hanging(host, "vine", Vector2(1960, 272))
	hanging(host, "vine", Vector2(2200, 272))
	prop(host, "rubble", Vector2(2064, 352))
	# ⑥ 圣殿前阶：阶口灌木、碎石、前台石栏
	foliage(host, "bush_s", Vector2(2250, 320), 1.0)
	prop(host, "rubble", Vector2(2352, 288))
	prop(host, "balustrade", Vector2(2528, 256))
