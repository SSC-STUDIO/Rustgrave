extends ChapterLayout
## 锈墓・叁 — 锈城街巷：地窟的门开在地面上的死城里。窗里有锈苔的光，街上没人。
##
## 下沉街巷、市场抬台、两条屋顶环线；详见 docs/level-redesign/level03.md。

const EAST_LIMIT := 4000
const ENTRY_SPAWN := Vector2(96, 300)
const FALLING_TILES := preload("res://scripts/levels/chapters/level03_falling_tiles.gd")
const FLOORS: Array = [
	["StreetA", 0.0, 512.0, 320.0],
	["DrainLane", 512.0, 832.0, 352.0],
	["StreetB", 832.0, 1536.0, 320.0],
	["MarketCourt", 1536.0, 1856.0, 288.0],
	["Plaza", 1856.0, 2112.0, 320.0],
	["Alley", 2112.0, 2432.0, 352.0],
	["StairA", 2432.0, 2496.0, 320.0],
	["StairB", 2496.0, 2560.0, 288.0],
	["Terrace", 2560.0, 2848.0, 256.0],
	["DeadStreet", 2848.0, 3232.0, 320.0],
	["DeadSlope", 3232.0, 3296.0, 288.0],
	["DeadCourt", 3296.0, 3552.0, 256.0],
	["TempleStreet", 3552.0, 4000.0, 320.0],
]
const STEPS: Array = [
	["RoofEntry", Vector2(928, 224), 80.0, "brick"],
	["RoofB", Vector2(1072, 224), 96.0, "brick"],
	["RoofC", Vector2(1232, 224), 96.0, "brick"],
	["TowerRoof", Vector2(1760, 160), 144.0, "brick"],
	["AlleyReturnStep", Vector2(2496, 256), 64.0, "brick"],
	["EaveE", Vector2(2352, 256), 96.0, "brick"],
	["EaveD", Vector2(2192, 256), 80.0, "brick"],
	["DeadRoofA", Vector2(2992, 256), 64.0, "brick"],
	["DeadRidge", Vector2(3056, 224), 128.0, "brick"],
	["DeadRoofB", Vector2(3264, 192), 96.0, "brick"],
	["DeadRoofC", Vector2(3440, 192), 80.0, "brick"],
]
const COLLAPSING_STEPS: Array = [
	["CollapseRoof1", Vector2(1024, 224), 32.0],
	["CollapseRoof2", Vector2(1184, 224), 32.0],
	["CollapseAlley", Vector2(2288, 256), 48.0],
	["CollapseQuarter1", Vector2(3200, 224), 48.0],
	["CollapseQuarter2", Vector2(3376, 192), 48.0],
]
const BLOCKS: Array = [
	["RoofStepLow", Vector2(736, 320), Vector2(64, 32)],
	["RoofStepMidBase", Vector2(800, 320), Vector2(64, 32)],
	["RoofStepMid", Vector2(800, 288), Vector2(64, 32)],
	["RoofStepHighBase", Vector2(864, 288), Vector2(64, 32)],
	["RoofStepHigh", Vector2(864, 256), Vector2(64, 32)],
	# A missed eave jump / Plaza nest reload must still reach the closed gate's plate.
	# Climb east, then jump back west across the open 64px gap onto RoofC.
	["RoofReturnLow", Vector2(1328, 288), Vector2(64, 32)],
	["RoofReturnHighBase", Vector2(1392, 288), Vector2(64, 32)],
	["RoofReturnHigh", Vector2(1392, 256), Vector2(64, 32)],
	# Keep the 64px street gate meaningful beside the new return stair.
	# The brick lintel closes its overhead bypass while leaving the open doorway clear.
	["GateLintel", Vector2(1488, 160), Vector2(48, 96)],
	["DeadStepA", Vector2(2928, 288), Vector2(64, 32)],
]
const DEBRIS: Array = [
	["FallingTileTeach", Vector2(400, 320), 0.0],
	["FallingTileMarket", Vector2(1744, 288), 0.25],
	["FallingTileAlley", Vector2(2336, 352), 0.5],
	["FallingTileQuarter", Vector2(3488, 256), 0.75],
]
const NEST_START_X := 176.0
const NEST_PLAZA_X := 1168.0
const NEST_ALLEY_X := 2160.0
const NEST_QUARTER_X := 3152.0
const STELE_WINDOW_POS := Vector2(248, 320)
const STELE_STAIR_POS := Vector2(2680, 256)
const STELE_TOWER_POS := Vector2(1832, 160)
const SIGN_TOWN_POS := Vector2(328, 320)
const SIGN_TEMPLE_POS := Vector2(3780, 320)
const PLATE_FEET := Vector2(1280, 224)
const GATE_POS := Vector2(1488, 256)
const HOOK_POS := Vector2(1856, 104)
const EMBER_CORE_POS := Vector2(1896, 128)
const REWARD_SCENE := "res://scenes/interactables/EquipmentPickup.tscn"
const REWARD_POS := Vector2(3104, 217)
const REWARD_KIND := "equipment"
const REWARD_REF := "iron_blade"
const EXIT_POS := Vector2(3840, 320)
const ENEMIES: Array = [
	["Scrapper1", "scrapper", Vector2(640, 352), {"patrol_range": 24.0, "aggro_range": 128.0, "lose_range": 256.0}],
	["Spitter1", "spitter", Vector2(752, 320), {"aggro_range": 224.0}],
	["Scrapper2", "scrapper", Vector2(1584, 288), {"patrol_range": 16.0, "alert_radius": 160.0}],
	["Scrapper3", "scrapper", Vector2(1696, 288), {"variant": &"swift_scrapper", "patrol_range": 16.0}],
	["FlyingDemon1", "flying_demon", Vector2(1704, 200), {}],
	["AlleyHound", "scrapper", Vector2(2416, 352), {"variant": &"armored_scrapper", "patrol_range": 16.0, "alert_radius": 180.0}],
	["Ghost1", "ghost", Vector2(2400, 312), {}],
	["Spitter2", "spitter", Vector2(2592, 256), {}],
	["GearShield1", "gear_shield", Vector2(2768, 256), {"patrol_range": 16.0}],
	["Scrapper4", "scrapper", Vector2(3432, 256), {"variant": &"swift_scrapper", "patrol_range": 16.0}],
	["Ghost2", "ghost", Vector2(3408, 156), {}],
	["Spitter3", "spitter", Vector2(3664, 320), {}],
]

const ARCH_TINT := Color(0.82, 0.8, 0.84)
## 死城街上没有春天的新叶：灌木压成干枯的灰橄榄，别在锈砖上跳一块鲜绿。
const DRY_BUSH := Color(0.72, 0.7, 0.5)


func level_id() -> String:
	return "level03"


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


func theme() -> String:
	return "town"


## 灭火那夜：黄昏转夜，起浓雾。
func ambient() -> Dictionary:
	return {"time": 0.6, "weather": "fog", "hold": 300.0}


## 死城的天只会起雾、落雨、放晴 —— 锈雨是墓园的招牌，不搬到这里来。
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


## 窄巷两侧矮屋檐口压顶：风被墙吃掉，雾沉在巷底。
## 死城街区也是一片沉雾：死屋之间连风都懒得走。
func weather_regions() -> Array:
	return [
		{"name": "AlleyCalm", "rect": Rect2(2112, 224, 320, 176),
			"weather": WorldClock.Weather.FOG, "intensity": 1.0, "wind_scale": 0.35},
		{"name": "DeadQuarter", "rect": Rect2(2848, 160, 1152, 240),
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
	for c in COLLAPSING_STEPS:
		collapsing(host, String(c[0]), c[1], float(c[2]), "brick", {"shake_time": 0.7, "respawn_time": 3.0})
	for s in STEPS:
		step(host, String(s[0]), s[1], float(s[2]), String(s[3]))
	for b in BLOCKS:
		platform(host, String(b[0]), b[1], b[2], "brick")
	walls(host, "brick")


func _build_props(host: Node2D) -> void:
	nest(host, "EmberNestStreet", NEST_START_X)
	nest(host, "EmberNestPlaza", NEST_PLAZA_X)
	nest(host, "EmberNestAlley", NEST_ALLEY_X, 352.0)
	nest(host, "EmberNestQuarter", NEST_QUARTER_X)
	for d in DEBRIS:
		var hazard := FALLING_TILES.new()
		hazard.name = String(d[0])
		hazard.position = d[1]
		hazard.phase = float(d[2])
		group(host, "Props").add_child(hazard)
	_stele(host, "SteleWindow", STELE_WINDOW_POS)
	_stele(host, "SteleStair", STELE_STAIR_POS)
	waymark(host, SIGN_TOWN_POS, "锈城")
	waymark(host, SIGN_TEMPLE_POS, "圣殿")
	plate_door(host, "Gate", PLATE_FEET, GATE_POS)
	hook(host, "HookTower", HOOK_POS)
	pickup(host, "EmberCoreTower", EMBER_CORE_POS, &"ember_core")
	# 塔顶支路：只有钩锁能读到的城市纪事。奖励是解释「窗里的灯」的世界信息。
	_stele(host, "SteleTower", STELE_TOWER_POS)
	# ⑦ 死屋檐脊上的奖励位：支路尽头的一件锈城遗物（EquipmentPickup 接应）。
	_reward(host)
	# ⑧ 可破坏道具（M2）：街边两只可砍碎的锈堆，放在支路/角落，不挡主线。
	destructible(host, "ScrapHeapStreet", &"scrap_heap", Vector2(1040, 320))
	destructible(host, "RustUrnStreet", &"rust_urn", Vector2(1400, 320))
	# 死屋檐道西口的裂石板：打通近路拿屋脊奖励，东侧也可经塌瓦绕回。
	# 会话内破坏（persist=false），重载恢复，主路线不经过它。
	breakable(host, "RubbleRoofB", Vector2(2992, 192), Vector2(48, 64), "brick")


## 奖励位：EquipmentPickup 的 reward_kind/reward_ref 走 LoadoutBridge（roster 缺失
## 时回退「一点余温」，不死锁）。位置在支路屋脊上，Fill 底边（节点 +7px）贴台面。
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
	for p in [["door_arch_town", Vector2(40, 320)], ["rubble_dry", Vector2(464, 320)],
		["balustrade_town", Vector2(688, 352)], ["door_arch_town", Vector2(1080, 320)],
		["rubble_dry", Vector2(1440, 320)], ["balustrade_town", Vector2(1552, 288)],
		["rubble_dry_c", Vector2(1808, 288)], ["balustrade_town", Vector2(2016, 320)],
		["rock_pile", Vector2(2240, 352)], ["rubble_dry_b", Vector2(2480, 320)],
		["balustrade_town", Vector2(2816, 256)], ["door_arch_town", Vector2(2880, 320)],
		["rubble_dry", Vector2(3192, 320)], ["rubble_dry_b", Vector2(3320, 256)],
		["balustrade_town", Vector2(3528, 256)], ["rubble_dry_c", Vector2(3806, 320)]]:
		prop(host, String(p[0]), p[1], 1.0, ARCH_TINT if p[0] == "door_arch_town" else Color.WHITE)
	for pos in [Vector2(352, 320), Vector2(1328, 320), Vector2(1952, 320), Vector2(2720, 256), Vector2(3584, 320)]:
		foliage(host, "bush_s", pos, 1.0, false, DRY_BUSH)
	for pos in [Vector2(1640, 288), Vector2(2960, 320), Vector2(3728, 320)]:
		prop(host, "brick_house", pos, 1.0, Color(0.38, 0.42, 0.52))
	for pos in [Vector2(2208, 272), Vector2(2384, 272), Vector2(3096, 240)]:
		hanging(host, "vine", pos, Color(0.4, 0.42, 0.4, 0.7))
