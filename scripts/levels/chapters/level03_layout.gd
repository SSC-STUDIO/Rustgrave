extends ChapterLayout
## 锈墓・肆 — 锈城街巷：地窟的门开在地面上的死城里。窗里有锈苔的光，街上没人。
##
## 结构（街面/屋顶双层环线 + 塌瓦屋檐 + 下水道蒸汽喷口，单跳 ≤32px 高、≤72px 跨）：
##   ① 巷口街面  0–560     出生点、余烬巢、碑文「窗」、路牌「锈城」；首处安全教学蒸汽喷口
##                         （前后 ≥60px 平地，无敌人干扰）
##   ② 运河与双层街区 560–1360
##      · 运河坑   560–720   断桥石板（288/256），分流至屋顶线（y=224）或街面线（y=320）
##      · 屋顶线   736–1224  首块安全塌瓦（下方为实心街面）→ 屋顶 A（喷吐者）→ 塌瓦 2 →
##                           屋顶 C（压板）→ 东侧石阶落回街面
##      · 街面线   720–1360  两处错相下水道蒸汽喷口 + 巡逻碎铁犬 + 可破坏锈堆/锈瓮，
##                           东侧石阶同样可爬上屋顶 C 踩压板开闸门
##   ③ 城门与广场 1360–1936  第二余烬巢；高低台庭院遭遇（普通碎铁犬 + 疾行碎铁犬变体 + 飞魔）；
##                           塔楼屋顶（y=160）钩锁支路（碑文「塔」+ 余烬核）
##   ④ 窄巷伏击与屋檐捷径 1936–2528
##      · 下层窄巷 1936–2368 下沉 y=352；西端第三余烬巢；东端装甲碎铁犬（群警戒）+ 幽魂伏击
##      · 上层屋檐 2048–2432 从前阶（StairB/Terrace）可走上屋檐与塌瓦向西横跨，单向落回巷口巢
##   ⑤ 圣殿前阶  2528–2880 蒸汽喷口 + 高低台掩体 + 齿盾卫守阶 + 碑文「阶」
##   ⑥ 死城双层环线 2880–4000
##      · 第四余烬巢（2920）；街面错相蒸汽喷口 + 疾行碎铁犬 + 街尾喷吐者
##      · 屋脊环线：裂石板 RubbleRoofB 守卫奖励位（iron_blade），向东经两段塌瓦与幽魂落回街尾
##      · 出口「圣殿门」→ level04

const EAST_LIMIT := 4000
const ENTRY_SPAWN := Vector2(96, 300)

## 地面段 [name, x0, x1, top_y]
const FLOORS: Array = [
	["StreetA", 0.0, 560.0, 320.0],
	["StreetB", 720.0, 1360.0, 320.0],
	["Plaza", 1360.0, 1936.0, 320.0],
	["Alley", 1936.0, 2368.0, 352.0],
	["StairA", 2368.0, 2448.0, 320.0],
	["StairB", 2448.0, 2528.0, 288.0],
	["Terrace", 2528.0, 2880.0, 256.0],
	["DeadStreet", 2880.0, 4000.0, 320.0],
]
const STEPS: Array = [
	["BridgeA1", Vector2(592, 288), 48.0, "brick_float"],
	["BridgeA2", Vector2(664, 256), 48.0, "brick_float"],
	["RoofEntry", Vector2(736, 224), 64.0, "brick"],
	["RoofA", Vector2(912, 224), 112.0, "brick"],
	["RoofC", Vector2(1128, 224), 96.0, "brick"],
	["PlazaStage", Vector2(1584, 288), 80.0, "brick_float"],
	["PlazaEave", Vector2(1760, 256), 64.0, "brick_float"],
	["TowerRoof", Vector2(1784, 160), 144.0, "brick"],
	## ④ 窄巷上层屋檐：从东侧 StairB/Terrace 踏上 AlleyReturnStep 向西走，在 EaveD 西端单向落回巷口巢。
	["EaveD", Vector2(2048, 256), 88.0, "brick"],
	["EaveE", Vector2(2248, 256), 96.0, "brick"],
	["AlleyReturnStep", Vector2(2368, 256), 64.0, "brick_float"],
	## ⑤ 圣殿前阶高台：跳过蒸汽口或居高绕盾卫。
	["TerraceStep", Vector2(2664, 224), 64.0, "brick_float"],
	["TerraceEave", Vector2(2752, 192), 80.0, "brick"],
	## ⑥ 死城支路与屋顶环线：从街面爬上死屋檐口（288→256→224），打碎裂石板拿奖励，
	## 继续沿东段塌瓦屋脊绕回街尾，也可直接落回街面。
	["DeadStepA", Vector2(2968, 288), 32.0, "brick_float"],
	["DeadRoofA", Vector2(3000, 256), 120.0, "brick"],
	["DeadRidge", Vector2(3120, 224), 140.0, "brick"],
	["DeadRoofB", Vector2(3376, 224), 96.0, "brick"],
	["DeadRoofC", Vector2(3584, 256), 80.0, "brick"],
	["DeadStepEast", Vector2(3680, 288), 48.0, "brick_float"],
]
## 塌瓦屋檐 [name, pos, width, skin]：踩上抖动 0.6s 后塌落，4s 后复原。
## 首块 CollapseRoof1 下方是 StreetB 实心街面，失手只落回街面，零陷阱教学。
const COLLAPSING_STEPS: Array = [
	["CollapseRoof1", Vector2(824, 224), 64.0, "brick_float"],
	["CollapseRoof2", Vector2(1048, 224), 56.0, "brick_float"],
	["CollapseAlley", Vector2(2160, 256), 64.0, "brick_float"],
	["CollapseDead1", Vector2(3288, 224), 64.0, "brick_float"],
	["CollapseDead2", Vector2(3496, 224), 64.0, "brick_float"],
]
## 下水道蒸汽喷口 [name, pos, props]：错相喷发，首处 SteamTeach 前后留足 ≥60px 安全落脚区。
const STEAM_VENTS: Array = [
	["SteamTeach", Vector2(400, 320), {"phase": 0.0}],
	["SteamStreet1", Vector2(792, 320), {"phase": 0.0}],
	["SteamStreet2", Vector2(968, 320), {"phase": 0.5}],
	["SteamTerrace", Vector2(2560, 256), {"phase": 0.25, "reach": 48.0}],
	["SteamDead1", Vector2(3320, 320), {"phase": 0.15}],
	["SteamDead2", Vector2(3528, 320), {"phase": 0.65}],
]
## 实心石阶 [name, pos(左上), size]：屋顶 C 东侧下到街面的两级。
const BLOCKS: Array = [
	["RoofStepHighBase", Vector2(1224, 288), Vector2(48, 32)],
	["RoofStepHigh", Vector2(1224, 256), Vector2(48, 32)],
	["RoofStepLow", Vector2(1272, 288), Vector2(48, 32)],
]
const CANAL_X0 := 560.0
const CANAL_X1 := 720.0
const TOXIN_TINT := Color(1.0, 1.25, 0.55)

const NEST_START_X := 176.0
const NEST_PLAZA_X := 1424.0
const NEST_ALLEY_X := 2000.0
const NEST_QUARTER_X := 2936.0
const STELE_WINDOW_POS := Vector2(248, 320)
const STELE_STAIR_POS := Vector2(2776, 256)
const SIGN_TOWN_POS := Vector2(312, 320)
const SIGN_TEMPLE_POS := Vector2(3780, 320)

## 压板脚点在屋顶 C 上；闸门左上角在街面（门 16×64，底在 320）。
const PLATE_FEET := Vector2(1168, 224)
const GATE_POS := Vector2(1360, 256)
## 钩锁锚点悬在塔楼屋顶上方；余烬核悬在屋顶上方 32px。
const HOOK_POS := Vector2(1856, 104)
const EMBER_CORE_POS := Vector2(1896, 128)
const STELE_TOWER_POS := Vector2(1832, 160)
## 死城街区奖励位在死屋檐脊上（EquipmentPickup 的 Fill 底边在节点 +7px）。
const REWARD_SCENE := "res://scenes/interactables/EquipmentPickup.tscn"
const REWARD_POS := Vector2(3176, 217)
const REWARD_KIND := "equipment"
const REWARD_REF := "iron_blade"
const EXIT_POS := Vector2(3840, 320)

## [name, kind, pos, overrides]：三处场景化遭遇（双层街区、广场高低台、窄巷伏击 + 死城环线）。
const ENEMIES: Array = [
	["Scrapper1", "scrapper", Vector2(1080, 320), {"patrol_range": 40.0}],
	["Spitter1", "spitter", Vector2(984, 224), {}],
	["Scrapper2", "scrapper", Vector2(1624, 288), {"patrol_range": 16.0, "alert_radius": 160.0}],
	["Scrapper3", "scrapper", Vector2(1712, 320),
			{"variant": &"swift_scrapper", "patrol_range": 16.0}],
	["FlyingDemon1", "flying_demon", Vector2(1704, 184), {}],
	["AlleyHound", "scrapper", Vector2(2264, 352),
			{"variant": &"armored_scrapper", "patrol_range": 16.0, "alert_radius": 180.0, "lose_range": 320.0}],
	["Ghost1", "ghost", Vector2(2248, 304), {}],
	["Spitter2", "spitter", Vector2(2488, 288), {}],
	["GearShield1", "gear_shield", Vector2(2616, 256), {"patrol_range": 16.0}],
	["Scrapper4", "scrapper", Vector2(3224, 320),
			{"variant": &"swift_scrapper", "patrol_range": 24.0, "alert_radius": 180.0}],
	["Ghost2", "ghost", Vector2(3424, 184), {}],
	["Spitter3", "spitter", Vector2(3640, 320), {}],
]

const ARCH_TINT := Color(0.82, 0.8, 0.84)
const DRY_BUSH := Color(0.72, 0.7, 0.5)


func level_id() -> String:
	return "level03"


func title() -> String:
	return ChapterText.title_of(level_id())


func wake_line() -> String:
	return ChapterText.wake_of(level_id())


func _stele(host: Node2D, node_name: String, pos: Vector2) -> void:
	var entry := ChapterText.stele_of(level_id(), node_name)
	stele(host, node_name, pos, String(entry.get("title", "")), String(entry.get("text", "")))


func entry_spawn() -> Vector2:
	return ENTRY_SPAWN


func east_limit() -> int:
	return EAST_LIMIT


func theme() -> String:
	return "town"


func ambient() -> Dictionary:
	return {"time": 0.6, "weather": "fog", "hold": 300.0}


func weather_recipe() -> Dictionary:
	return {
		"allowed": [WorldClock.Weather.FOG, WorldClock.Weather.HAZE, WorldClock.Weather.RAIN,
				WorldClock.Weather.CLEAR],
		"weights": {
			"night": {"fog": 5, "haze": 2, "rain": 1},
			"dusk": {"fog": 5, "haze": 2, "rain": 1},
			"*": {"fog": 4, "haze": 2, "rain": 2, "clear": 1},
		},
		"hold": Vector2(150.0, 260.0),
		"intensity": Vector2(0.55, 1.0),
	}


func weather_regions() -> Array:
	return [
		{"name": "AlleyCalm", "rect": Rect2(1936, 224, 432, 176),
			"weather": WorldClock.Weather.FOG, "intensity": 1.0, "wind_scale": 0.35},
		{"name": "DeadQuarter", "rect": Rect2(2880, 224, 1120, 176),
			"weather": WorldClock.Weather.FOG, "intensity": 0.85, "wind_scale": 0.5},
	]


func build(host: Node2D) -> void:
	_build_terrain(host)
	_build_props(host)
	_build_enemies(host)
	_build_decor(host)
	exit_door(host, EXIT_POS.x, ChapterText.exit_label_of(level_id()),
			ChapterText.exit_captions_of(level_id()), "level03_done",
			GameContext.next_level_id(level_id()), EXIT_POS.y)
	finish(host)


func _build_terrain(host: Node2D) -> void:
	for f in FLOORS:
		floor_strip(host, String(f[0]), float(f[1]), float(f[2]), "brick",
				float(f[1]) > 0.0, float(f[2]) < float(EAST_LIMIT), float(f[3]))
	toxin_pit(host, "Canal", CANAL_X0, CANAL_X1, 32.0, "brick", TOXIN_TINT)
	for s in STEPS:
		step(host, String(s[0]), s[1], float(s[2]), String(s[3]))
	for c in COLLAPSING_STEPS:
		collapsing(host, String(c[0]), c[1], float(c[2]), String(c[3]))
	for b in BLOCKS:
		platform(host, String(b[0]), b[1], b[2], "brick")
	walls(host, "brick")


func _build_props(host: Node2D) -> void:
	nest(host, "EmberNestStreet", NEST_START_X)
	nest(host, "EmberNestPlaza", NEST_PLAZA_X)
	nest(host, "EmberNestAlley", NEST_ALLEY_X, 352.0)
	nest(host, "EmberNestQuarter", NEST_QUARTER_X)
	_stele(host, "SteleWindow", STELE_WINDOW_POS)
	_stele(host, "SteleStair", STELE_STAIR_POS)
	waymark(host, SIGN_TOWN_POS, "锈城")
	waymark(host, SIGN_TEMPLE_POS, "圣殿")
	plate_door(host, "Gate", PLATE_FEET, GATE_POS)
	hook(host, "HookTower", HOOK_POS)
	pickup(host, "EmberCoreTower", EMBER_CORE_POS, &"ember_core")
	_stele(host, "SteleTower", STELE_TOWER_POS)
	for v in STEAM_VENTS:
		cyclic(host, String(v[0]), v[1], "steam", v[2] as Dictionary)
	_reward(host)
	destructible(host, "ScrapHeapStreet", &"scrap_heap", Vector2(880, 320))
	destructible(host, "RustUrnStreet", &"rust_urn", Vector2(1140, 320))
	breakable(host, "RubbleRoofB", Vector2(3024, 192), Vector2(64, 64), "brick")


func _reward(host: Node2D) -> Node:
	if not ResourceLoader.exists(REWARD_SCENE):
		return null
	var scene := load(REWARD_SCENE) as PackedScene
	if scene == null:
		return null
	var pick := scene.instantiate()
	pick.name = "RewardDeadQuarter"
	pick.position = REWARD_POS
	pick.set("reward_kind", REWARD_KIND)
	pick.set("reward_ref", REWARD_REF)
	var item := EquipmentCatalog.for_id(StringName(REWARD_REF))
	pick.set("reward_name", item.display_name if item != null else "")
	group(host, "Pickups").add_child(pick)
	return pick


func _build_enemies(host: Node2D) -> void:
	for e in ENEMIES:
		enemy(host, String(e[0]), String(e[1]), e[2], e[3] if e.size() > 3 else {})


func _build_decor(host: Node2D) -> void:
	# ① 巷口街道
	prop(host, "door_arch_town", Vector2(40, 320), 1.0, ARCH_TINT)
	foliage(host, "bush_s", Vector2(352, 320), 1.0, false, DRY_BUSH)
	prop(host, "rubble_dry", Vector2(464, 320))
	prop(host, "balustrade_town", Vector2(520, 320))
	prop(host, "balustrade_town", Vector2(744, 320))
	# ② 双层街区下层
	prop(host, "rubble_dry", Vector2(920, 320))
	prop(host, "door_arch_town", Vector2(1040, 320), 1.0, ARCH_TINT)
	foliage(host, "bush_s", Vector2(1184, 320), 1.0, false, DRY_BUSH)
	# ③ 广场高低台
	prop(host, "brick_house", Vector2(1660, 320), 1.0, Color(0.42, 0.46, 0.54))
	prop(host, "balustrade_town", Vector2(1544, 320))
	prop(host, "rubble_dry", Vector2(1656, 320))
	prop(host, "rubble_dry_c", Vector2(1744, 320))
	foliage(host, "bush_s", Vector2(1856, 320), 1.0, false, DRY_BUSH)
	# ④ 窄巷与上层屋檐
	hanging(host, "vine", Vector2(2064, 272), Color(0.4, 0.42, 0.4, 0.75))
	hanging(host, "vine", Vector2(2280, 272), Color(0.4, 0.42, 0.4, 0.75))
	prop(host, "rock_pile", Vector2(2120, 352), 1.0, Color(0.6, 0.62, 0.7))
	prop(host, "rubble_dry_b", Vector2(2312, 352))
	# ⑤ 圣殿前阶
	foliage(host, "bush_s", Vector2(2392, 320), 1.0, false, DRY_BUSH)
	prop(host, "rubble_dry", Vector2(2464, 288))
	prop(host, "balustrade_town", Vector2(2808, 256))
	# ⑥ 死城街区
	prop(host, "brick_house", Vector2(3020, 320), 1.0, Color(0.36, 0.4, 0.5))
	prop(host, "door_arch_town", Vector2(3260, 320), 1.0, ARCH_TINT)
	prop(host, "rubble_dry", Vector2(3368, 320))
	prop(host, "rubble_dry_b", Vector2(3440, 320))
	prop(host, "balustrade_town", Vector2(3480, 320))
	foliage(host, "bush_s", Vector2(3580, 320), 1.0, false, DRY_BUSH)
	prop(host, "brick_house", Vector2(3700, 320), 1.0, Color(0.4, 0.44, 0.54))
	prop(host, "rubble_dry_c", Vector2(3806, 320))
	hanging(host, "vine", Vector2(3096, 224), Color(0.4, 0.42, 0.4, 0.7))
