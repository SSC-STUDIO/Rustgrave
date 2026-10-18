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
##                         塔楼屋顶（y=160）只能钩锁上去：碑文「灯」+ 悬着的余烬核，
##                         是本章的支路。屋顶东侧的瓦面可以顺势跳回街面。
##                         塔楼本身是最高的剪影，钩点悬在它上面，站在广场就能看见。
##   ⑤ 窄巷      1936–2240 下沉 32px 的巷子，两侧矮屋檐口压顶，幽魂在巷东凝出；
##                         巷口第三巢在碎铁犬/幽魂的仇恨圈外，死亡回程约 800px
##   ⑥ 圣殿前阶  2240–2880 三级 32px 石阶（320/288/256）上前台；喷吐者守阶口，
##                         齿盾卫守门；出口「圣殿门」→ level04
##   ⑦ 死城街区  2880–4000 前台落地回到街面；死城支路（屋顶环线，可回主路）带
##                         1 个奖励位；街尾是新的圣殿门（出口）

const EAST_LIMIT := 4000
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
	["DeadStreet", 2880.0, 4000.0, 320.0],
]
const STEPS: Array = [
	["BridgeA1", Vector2(592, 288), 48.0, "brick_float"],
	["BridgeA2", Vector2(672, 256), 48.0, "brick_float"],
	["RoofA", Vector2(760, 224), 128.0, "brick"],
	["RoofB", Vector2(952, 224), 96.0, "brick"],
	["RoofC", Vector2(1104, 224), 96.0, "brick"],
	["TowerRoof", Vector2(1784, 160), 144.0, "brick"],
	["EaveD", Vector2(1952, 256), 96.0, "brick"],
	["EaveE", Vector2(2112, 256), 96.0, "brick"],
	## ⑦ 死城支路：从街面爬上死屋檐口（288→256→224），沿屋脊走到奖励位，
	## 再从屋脊直接落回街面——可回主路的环线，不需要钩锁也能走通。
	["DeadStepA", Vector2(2952, 288), 48.0, "brick_float"],
	["DeadRoofA", Vector2(3000, 256), 120.0, "brick"],
	["DeadRidge", Vector2(3120, 224), 140.0, "brick"],
]
## 实心石阶 [name, pos(左上), size]：屋顶 C 东侧下到街面的两级。
## 每级至多 32 高；64 高的落差拆成上下两块，LevelSanity 的净空检查才把
## 它读成「两级台阶」，而不是一堵压在街面上的墙。
const BLOCKS: Array = [
	["RoofStepHighBase", Vector2(1200, 288), Vector2(48, 32)],
	["RoofStepHigh", Vector2(1200, 256), Vector2(48, 32)],
	["RoofStepLow", Vector2(1248, 288), Vector2(48, 32)],
]
const CANAL_X0 := 560.0
const CANAL_X1 := 720.0
## 酸黄绿：夜街的青灰石板旁，原色毒液会读成一条水沟。
const TOXIN_TINT := Color(1.0, 1.25, 0.55)

const NEST_START_X := 176.0
const NEST_PLAZA_X := 1424.0
## 巷口的第三巢：广场两只碎铁犬的巡逻范围收窄到巢的 215px 仇恨圈之外，
## 巷里的幽魂也退到东端。死亡回程从 1300px 缩到约 800px，且巢位在战斗圈外。
const NEST_ALLEY_X := 2000.0
const STELE_WINDOW_POS := Vector2(248, 320)
const STELE_STAIR_POS := Vector2(2600, 256)
const SIGN_TOWN_POS := Vector2(328, 320)
const SIGN_TEMPLE_POS := Vector2(3780, 320)

## 压板脚点在屋顶 C 上；闸门左上角在街面（门 16×64，底在 320）。
const PLATE_FEET := Vector2(1152, 224)
const GATE_POS := Vector2(1360, 256)
## 钩锁锚点悬在塔楼屋顶上方；余烬核悬在屋顶上方 32px。
## 支路碑文站在屋顶东端，和核错开：读碑的人不会把核挤进字里。
const HOOK_POS := Vector2(1856, 104)
const EMBER_CORE_POS := Vector2(1896, 128)
## 支路奖励：世界信息（锈城为什么熄灯），不是第二枚可收集核。
const STELE_TOWER_POS := Vector2(1832, 160)
## ⑦ 死城街区：奖励位在死屋檐脊上（EquipmentPickup 的 Fill 底边在节点 +7px）。
const REWARD_SCENE := "res://scenes/interactables/EquipmentPickup.tscn"
const REWARD_POS := Vector2(3176, 217)
const REWARD_KIND := "equipment"
const REWARD_REF := "iron_blade"
const EXIT_POS := Vector2(3840, 320)

## [name, kind, pos, overrides]：落地敌人给脚点，飞行/穿墙敌人给悬停中心。
## 广场两只碎铁犬的 beat 收在 16px：plaza 巢和巷口巢都在 215px 冲锋圈之外。
const ENEMIES: Array = [
	["Scrapper1", "scrapper", Vector2(432, 320), {}],
	["Spitter1", "spitter", Vector2(1008, 224), {}],
	["Scrapper2", "scrapper", Vector2(1664, 320), {"patrol_range": 16.0}],
	["Scrapper3", "scrapper", Vector2(1760, 320), {"patrol_range": 16.0}],
	["FlyingDemon1", "flying_demon", Vector2(1712, 184), {}],
	# 幽魂退到窄巷东端，巷口巢（2000）距它 228px > 210px 唤醒距离。
	["Ghost1", "ghost", Vector2(2228, 312), {}],
	["Spitter2", "spitter", Vector2(2464, 256), {}],
	["GearShield1", "gear_shield", Vector2(2656, 256), {}],
	## ⑦ 死城街区：碎铁犬守在支路入口、幽魂在屋脊东侧、喷吐者守街尾圣殿门。
	["Scrapper4", "scrapper", Vector2(2900, 320), {}],
	["Ghost2", "ghost", Vector2(3420, 268), {}],
	["Spitter3", "spitter", Vector2(3640, 320), {}],
]

## 街屋已经在夜城视差里。不再把圣殿尖窗板竖在街心当第二排房子。
## 也不竖 bg_wall_torch：那是室内墙板，会挡掉夜城远山。
## 装饰门洞（地窟出口 / 店门）：压暗以免读成机关闸门。
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


## ⑤ 窄巷（1936–2240）两侧矮屋檐口压顶：风被墙吃掉，雾沉在巷底。
## ⑦ 死城街区（2880–4000）也是一片沉雾：死屋之间连风都懒得走。
func weather_regions() -> Array:
	return [
		{"name": "AlleyCalm", "rect": Rect2(1936, 224, 304, 176),
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
	for b in BLOCKS:
		platform(host, String(b[0]), b[1], b[2], "brick")
	walls(host, "brick")


func _build_props(host: Node2D) -> void:
	nest(host, "EmberNestStreet", NEST_START_X)
	nest(host, "EmberNestPlaza", NEST_PLAZA_X)
	nest(host, "EmberNestAlley", NEST_ALLEY_X, 352.0)
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
	destructible(host, "ScrapHeapStreet", &"scrap_heap", Vector2(880, 320))
	destructible(host, "RustUrnStreet", &"rust_urn", Vector2(1140, 320))
	# ⑨ 可破坏地形（M2）：死屋檐道上的裂石板。重击两下打碎，才能走上屋脊拿奖励；
	#    会话内破坏（persist=false），重载恢复，主路线不经过它。
	breakable(host, "RubbleRoofB", Vector2(3024, 192), Vector2(64, 64), "brick")


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
	# ① 街道：地窟门洞、一丛杂草、干石渣、水沟两岸的石栏。不用墓园树和苔石。
	prop(host, "door_arch_town", Vector2(40, 320), 1.0, ARCH_TINT)
	foliage(host, "bush_s", Vector2(368, 320), 1.0, false, DRY_BUSH)
	prop(host, "rubble_dry", Vector2(464, 320))
	prop(host, "balustrade_town", Vector2(520, 320))
	prop(host, "balustrade_town", Vector2(760, 320))
	# ② 屋顶下的街面：干石、店门洞、门前杂草
	prop(host, "rubble_dry", Vector2(920, 320))
	prop(host, "door_arch_town", Vector2(1072, 320), 1.0, ARCH_TINT)
	foliage(host, "bush_s", Vector2(1108, 320), 1.0, false, DRY_BUSH)
	# ④ 广场：一栋还立着的砖屋当地标（压暗压冷，退到夜城后面），石栏和干石。
	# 枯树、守墓者石像是墓园的，不搬到街上。
	prop(host, "brick_house", Vector2(1660, 320), 1.0, Color(0.42, 0.46, 0.54))
	prop(host, "balustrade_town", Vector2(1544, 320))
	prop(host, "rubble_dry", Vector2(1656, 320))
	prop(host, "rubble_dry_c", Vector2(1744, 320))
	foliage(host, "bush_s", Vector2(1836, 320), 1.0, false, DRY_BUSH)
	# ⑤ 窄巷：檐下是灰藤，不是鲜苔；巷底干石
	hanging(host, "vine", Vector2(1960, 272), Color(0.4, 0.42, 0.4, 0.75))
	hanging(host, "vine", Vector2(2200, 272), Color(0.4, 0.42, 0.4, 0.75))
	prop(host, "rock_pile", Vector2(2064, 352), 1.0, Color(0.6, 0.62, 0.7))
	# ⑥ 圣殿前阶：阶口杂草、干石、前台石栏
	foliage(host, "bush_s", Vector2(2250, 320), 1.0, false, DRY_BUSH)
	prop(host, "rubble_dry", Vector2(2352, 288))
	prop(host, "balustrade_town", Vector2(2528, 256))
	# ⑦ 死城街区：塌了半边的砖屋、门洞、干石与栏杆；支路屋脊下一盏残窗灯。
	prop(host, "brick_house", Vector2(2960, 320), 1.0, Color(0.36, 0.4, 0.5))
	prop(host, "door_arch_town", Vector2(3260, 320), 1.0, ARCH_TINT)
	prop(host, "rubble_dry", Vector2(3304, 320))
	prop(host, "rubble_dry_b", Vector2(3384, 320))
	prop(host, "balustrade_town", Vector2(3480, 320))
	foliage(host, "bush_s", Vector2(3540, 320), 1.0, false, DRY_BUSH)
	prop(host, "brick_house", Vector2(3700, 320), 1.0, Color(0.4, 0.44, 0.54))
	prop(host, "rubble_dry_c", Vector2(3806, 320))
	hanging(host, "vine", Vector2(3096, 224), Color(0.4, 0.42, 0.4, 0.7))
