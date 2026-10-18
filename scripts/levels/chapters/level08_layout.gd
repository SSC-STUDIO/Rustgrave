extends ChapterLayout
## 锈墓・捌「熔渣深渊」——钟楼底下的渣海。渣还记得剑的形状，火骷髅在上面飘。
## 全关只用 ChapterLayout 的助手铺设；测试可以在一个空 Node2D 上 build()。
##
## 玩法变化（热渣上的跳石 + 火骷髅走廊）：所有主路都架在熔渣池上，
## 跳石间距固定、火焰骷髅只守着两条短渣沟；掉进渣里一定能一跳爬出。
## 支路：渣河 A 上方的排气龛（VentLedge），只有钩锁能上，读一条熔渣纪事。
##
## 结构（地面 y=320，一跳 ≤32 高 / ≤72 远）：
##   ① 落口       0–416      渣口拱、余烬巢、碑「渣」、路牌「渣渊」
##   ② 渣河 A     416–848    四块浮石跨第一条熔渣河（间距 48–56，高差 ≤32）
##   ③ 渣堤       848–1200   碎铁犬、幽魂、高台上的喷吐者
##   ④ 双吊台     1200–1728  两座吊台相位错开 0.5，中间一根渣柱，接力横渡两段熔渣
##   ⑤ 中段巢     1728–2208  第二余烬巢、浮石高台上的压板与喷吐者、渣闸
##   ⑥ 火骷髅回廊 2208–2416  两条短渣沟夹一段窄地，四只火骷髅悬在头顶
##   ⑦ 锈门       2416–2592  第三余烬巢、齿盾卫、锈门（热锻）、路牌「城墙」
##   ⑧ 渣河 B     2592–2880  八角渣台 + 浮石混合的最后一条熔渣河
##   ⑨ 出口       2880–3008  城墙梯、碑「淬」
##   ⑩ 渣河桥     3008–3640  扩章：第三座渣河桥（三块浮石桥面），旧壳区入口
##   ⑪ 旧壳区     3640–4200  半边埋进渣里的旧船壳/旧机械；支路奖励位与余烬巢；
##                          出口「城墙梯」移到旧壳区东端

const EAST_LIMIT := 4200
const CEILING_Y := -32.0
const PIT_DEPTH := 32.0
## 地面是 basalt（tools/gen_theme_tiles.py 的渣岩）。这个琥珀值只剩一个用处：
## 熔渣 tint 的红绿比必须远高于它，池面才和地面分得开（测试按它比较）。
const GROUND_TONE := Color(1.0, 0.8, 0.6)
## 熔渣：视觉 QA Phase A 的 P1（level08 屏幕底部一条高饱和橙带）修复。
## 旧值是 (22.0, 2.2, 0.6) 的过曝红，整条河在 LDR 里钳成纯橙；现在改用
## ToxinPool.set_sludge_ramp 的深渣色 ramp + 温和 tint：近岸亮、河心暗，
## 颜色从「警示橙」退成「炉渣褐」。ramp 只在池子自身上，不动全局 TOXIN 常量。
const SLAG_TINT := Color(1.22, 0.94, 0.74)
const SLAG_RAMP := [
	Color("#100a08"), Color("#2c1b12"), Color("#503125"),
	Color("#7a4c34"), Color("#a3714f"),
]
const SLAG_VAPOR := Color(0.85, 0.55, 0.34)
## 吊台与八角台没有 tone 参数，用 modulate 压成同一族暖色。
const LIFT_TONE := Color(1.0, 0.82, 0.62)
## 八角台原本是偏冷紫的教堂石：压成烤过的渣褐色，别在橙池上飘一块粉石头。
const GEAR_TONE := Color(0.9, 0.62, 0.42)
const TORCH_TINT := Color(1.0, 0.75, 0.55)
## 藤条是青苔绿。浅暖色乘上去仍是黄绿，像墓园的藤爬进熔渣坑。压到深锈才像挂渣的旧缆。
const VINE_TINT := Color(0.45, 0.22, 0.1, 0.85)
const ARCH_TINT := Color(1.0, 0.8, 0.62)
const RUBBLE_TINT := Color(1.0, 0.82, 0.64)
const COLUMN_TINT := Color(0.62, 0.44, 0.32)
## 历史机械件（Kenney 派生的 1x 铁/渣族副本）：压一档炉灰，别比地面还亮。
const GIRDER_TINT := Color(0.86, 0.7, 0.58)
const PIPE_TINT := Color(0.8, 0.66, 0.56)

const ENTRY_SPAWN := Vector2(96, 300)

## [name, x0, x1] 地面段（顶 320，80 厚）。
const FLOORS: Array = [
	["FloorA", 0.0, 416.0],
	["FloorB", 848.0, 1200.0],
	["FloorC", 1728.0, 2208.0],
	["FloorD", 2272.0, 2352.0],
	["FloorE", 2416.0, 2592.0],
	["FloorG", 2880.0, 3400.0],
	["FloorI", 3640.0, 4200.0],
]
## [name, x0, x1] 熔渣坑：坑底 352、液面 336..368；坑沿到地面 32px，一跳爬得出来。
const PITS: Array = [
	["SlagA", 416.0, 848.0],
	["SlagB1", 1200.0, 1456.0],
	["SlagB2", 1488.0, 1728.0],
	["SlagC1", 2208.0, 2272.0],
	["SlagC2", 2352.0, 2416.0],
	["SlagD", 2592.0, 2880.0],
	["SlagE", 3400.0, 3640.0],
]
## [name, 左上角, 宽] 浮石（16 厚，moss_float）。
const STEPS: Array = [
	["StoneA1", Vector2(464, 288), 48.0],
	["StoneA2", Vector2(568, 264), 48.0],
	["StoneA3", Vector2(672, 280), 48.0],
	["StoneA4", Vector2(768, 296), 48.0],
	["LedgeB", Vector2(1120, 288), 64.0],
	["PlateStepC", Vector2(1888, 288), 48.0],
	["PlateLedgeC", Vector2(1968, 256), 96.0],
	["StoneD1", Vector2(2704, 264), 48.0],
	["StoneD2", Vector2(2832, 288), 32.0],
	## ⑩ 渣河桥：第三座熔渣河上的三块浮石桥面。
	["StoneE1", Vector2(3424, 288), 48.0],
	["StoneE2", Vector2(3512, 264), 48.0],
	["StoneE3", Vector2(3584, 288), 48.0],
	## ⑪ 旧壳区：爬上旧船壳的两级台阶（支路奖励位）。
	["ShellStep", Vector2(3720, 288), 48.0],
	["ShellLedge", Vector2(3768, 256), 96.0],
]
## [name, 中心, 半径] 八角渣台（顶面 = 中心 y - 半径）。
const GEARS: Array = [
	["GearD1", Vector2(2640, 304), 16.0],
	["GearD2", Vector2(2792, 296), 16.0],
]
## 两段熔渣中间的渣柱：吊台接力的落脚点，也是掉下去的人爬出来的地方。
const PILLAR_POS := Vector2(1456, 320)
const PILLAR_SIZE := Vector2(32, 80)
## 可选支路：渣河 A 上方的排气龛。从 StoneA2/A3 起钩（索距 ≤250），
## 落台在锚点下方 56px；没有钩锁时落差 88px，跳不上去。
const VENT_LEDGE := Rect2(672, 176, 96, 16)
const HOOK_VENT_POS := Vector2(720, 120)
const STELE_VENT_POS := Vector2(744, 176)
## 双吊台：A 从渣堤出发向东，B 相位错开 0.5——A 到东端时 B 正好回到渣柱旁。
const LIFT_A_POS := Vector2(1216, 296)
const LIFT_A_TRAVEL := Vector2(168, 0)
const LIFT_B_POS := Vector2(1496, 296)
const LIFT_B_TRAVEL := Vector2(152, 0)
const LIFT_B_PHASE := 0.5
const LIFT_PERIOD := 6.0
const LIFT_WIDTH := 64.0
## 压板在浮石高台 PlateLedgeC 上，闸门在地面（门 16×64，底在 320）。
const PLATE_FEET := Vector2(1992, 256)
const DOOR_POS := Vector2(2160, 256)
const GATE_POS := Vector2(2544, 256)
const EXIT_X := 4080.0
## [name, x] 余烬巢（都在地面 320 上）。
const NESTS: Array = [
	["EmberNestStart", 176.0],
	["EmberNestMid", 1792.0],
	["EmberNestGate", 2440.0],
	## ⑪ 旧壳区：扩章后出口在 4080，最后一段补一口余火（距上一巢 1240px）。
	["EmberNestShell", 3680.0],
]
const STELE_SLAG_POS := Vector2(256, 320)
const STELE_QUENCH_POS := Vector2(4036, 320)
const WAYMARKS: Array = [[Vector2(320, 320), "渣渊"], [Vector2(2576, 320), "城墙"]]
## ⑪ 旧壳区的支路奖励位（EquipmentPickup；Fill 底边在节点 +7px，落在 256 台面）。
const REWARD_SCENE := "res://scenes/interactables/EquipmentPickup.tscn"
const REWARD_POS := Vector2(3816, 249)
const REWARD_KIND := "equipment"
const REWARD_REF := "toxic_ward"
## [name, kind, pos, overrides]。落地敌人给脚点；幽魂/火骷髅给悬停中心。
## 火骷髅悬在头顶上方 40–70px（骑士身高 26 → 中心 y 224..254）。
const ENEMIES: Array = [
	["Scrapper1", "scrapper", Vector2(944, 320), {"patrol_range": 48.0}],
	["Ghost1", "ghost", Vector2(1064, 236), {}],
	["Spitter1", "spitter", Vector2(1152, 288), {}],
	["Spitter2", "spitter", Vector2(2040, 256), {}],
	["FireSkull1", "fire_skull", Vector2(2192, 240), {"aggro_range": 96.0, "patrol_range": 24.0, "arena_left": 2160.0, "arena_right": 2320.0}],
	["FireSkull2", "fire_skull", Vector2(2256, 224), {"aggro_range": 96.0, "patrol_range": 24.0, "arena_left": 2160.0, "arena_right": 2320.0}],
	["FireSkull3", "fire_skull", Vector2(2328, 240), {"aggro_range": 96.0, "patrol_range": 24.0, "arena_left": 2288.0, "arena_right": 2416.0}],
	["FireSkull4", "fire_skull", Vector2(2400, 224), {"aggro_range": 96.0, "patrol_range": 24.0, "arena_left": 2288.0, "arena_right": 2416.0}],
	["GearShield1", "gear_shield", Vector2(2512, 320), {"patrol_range": 8.0, "aggro_range": 48.0}],
	## ⑩⑪ 扩章渣河桥 / 旧壳区：碎铁犬守桥头、幽魂在壳缝里、喷吐者守出口阶。
	["Scrapper2", "scrapper", Vector2(3200, 320), {"patrol_range": 48.0}],
	["Ghost3", "ghost", Vector2(3280, 240), {}],
	["Spitter3", "spitter", Vector2(3984, 320), {}],
]
## 1472 在 32px 渣柱上，64px 墙板两边各悬进熔渣 16px，改到 FloorB。
## 2992 的墙板盖住出口碑，还探出东墙，改到 FloorC 门西侧的实地上。
const TORCHES: Array = [384.0, 940.0, 1004.0, 1848.0, 2088.0, 2312.0, 2480.0,
		3064.0, 3320.0, 3688.0, 4008.0]
const VINES: Array = [232.0, 560.0, 720.0, 1312.0, 1624.0, 2008.0, 2240.0, 2704.0, 2944.0,
		3144.0, 3464.0, 3864.0]
## 1752 的石板（48×1.15）左缘探进 FloorC 以西的渣坑，收到坑沿里面。
const ARCHES: Array = [72.0, 1764.0]
## 396 叠在入口火把上；2336 叠在 FloorD 的火把上，窄台放不下。
const RUBBLE: Array = [296.0, 872.0, 2120.0, 2432.0]
const COLUMNS: Array = [1080.0, 2530.0]


func level_id() -> String:
	return "level08"


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


func default_spawn() -> Vector2:
	return entry_spawn()


func east_limit() -> int:
	return EAST_LIMIT


func camera_top() -> int:
	return -48


func theme() -> String:
	return "forge"


func motes() -> String:
	return "embers"


## 熔渣深渊在岩层下面：不下雨，只有热雾和一阵阵余烬风。
func weather_recipe() -> Dictionary:
	return {
		"allowed": [WorldClock.Weather.EMBER_WIND, WorldClock.Weather.HAZE, WorldClock.Weather.CLEAR],
		"weights": {"*": {"ember_wind": 5, "haze": 3, "clear": 1}},
		"hold": Vector2(240.0, 400.0),
		"intensity": Vector2(0.6, 1.0),
	}


func build(host: Node2D) -> void:
	_build_terrain(host)
	_build_props(host)
	_build_enemies(host)
	_build_decor(host)
	exit_door(host, EXIT_X, ChapterText.exit_label_of(level_id()),
			ChapterText.exit_captions_of(level_id()), "level08_done",
			GameContext.next_level_id(level_id()))
	finish(host)


func _build_terrain(host: Node2D) -> void:
	for f in FLOORS:
		var x0: float = f[1]
		var x1: float = f[2]
		floor_strip(host, String(f[0]), x0, x1, "basalt", x0 > 0.0, x1 < float(EAST_LIMIT), FLOOR_Y)
	for p in PITS:
		_slag_pit(host, String(p[0]), p[1], p[2])
	for s in STEPS:
		step(host, String(s[0]), s[1], s[2], "basalt_float")
	# 排气龛：悬在渣河 A 上方，只有钩锁能到，钩锁之外不影响主路。
	step(host, "VentLedge", VENT_LEDGE.position, VENT_LEDGE.size.x, "basalt_float")
	platform(host, "SlagPillar", PILLAR_POS, PILLAR_SIZE, "basalt", true, true)
	for g in GEARS:
		var octagon := gear(host, String(g[0]), g[1], g[2])
		octagon.modulate = LIFT_TONE
	enclose(host, "basalt", CEILING_Y)
	var lift_a := lift(host, "LiftA", LIFT_A_POS, LIFT_A_TRAVEL, LIFT_PERIOD, LIFT_WIDTH, 0.0)
	lift_a.modulate = LIFT_TONE
	var lift_b := lift(host, "LiftB", LIFT_B_POS, LIFT_B_TRAVEL, LIFT_PERIOD, LIFT_WIDTH, LIFT_B_PHASE)
	lift_b.modulate = LIFT_TONE


## 熔渣坑：toxin_pit() 不给坑底上色，青苔坑底会在琥珀地面里露出一截青砖；
## 这里自己铺坑底（同 tone）再盖熔渣液面。命名沿用 <name>Bed / <name>Pool。
func _slag_pit(host: Node2D, pit_name: String, x0: float, x1: float) -> ToxinPool:
	var bed_y := FLOOR_Y + PIT_DEPTH
	platform(host, pit_name + "Bed", Vector2(x0, bed_y), Vector2(x1 - x0, FLOOR_Y + 80.0 - bed_y),
			"basalt", false, false)
	var pool := toxin(host, pit_name + "Pool", Vector2(x0, bed_y - 16.0),
			Vector2(x1 - x0, 32.0), SLAG_TINT)
	if pool != null:
		# 深渣 ramp：河心暗、近岸亮，不再是整条纯橙的高饱和带（视觉 QA P1）。
		pool.set_sludge_ramp(SLAG_RAMP, SLAG_VAPOR)
	return pool


func _build_props(host: Node2D) -> void:
	for n in NESTS:
		nest(host, String(n[0]), n[1])
	_stele(host, "SteleSlag", STELE_SLAG_POS)
	_stele(host, "SteleQuench", STELE_QUENCH_POS)
	for w in WAYMARKS:
		waymark(host, w[0], String(w[1]))
	plate_door(host, "Sluice", PLATE_FEET, DOOR_POS)
	rusty_gate(host, "RustGate", GATE_POS)
	# 支路：从渣河 A 的跳石上钩进排气龛。奖励是世界信息，不是又一枚核。
	hook(host, "HookVent", HOOK_VENT_POS)
	_stele(host, "SteleVent", STELE_VENT_POS)
	# ⑪ 旧壳区：旧船壳上的奖励位（支路）。
	_reward(host)


## ⑪ 旧壳区支路奖励位：EquipmentPickup 走 LoadoutBridge（roster 缺失回退余温，不死锁）。
func _reward(host: Node2D) -> Node:
	if not ResourceLoader.exists(REWARD_SCENE):
		return null
	var scene := load(REWARD_SCENE) as PackedScene
	if scene == null:
		return null
	var pick := scene.instantiate()
	pick.name = "RewardOldHull"
	pick.position = REWARD_POS
	pick.set("reward_kind", REWARD_KIND)
	pick.set("reward_ref", REWARD_REF)
	var item := EquipmentCatalog.for_id(StringName(REWARD_REF))
	pick.set("reward_name", item.display_name if item != null else "")
	group(host, "Pickups").add_child(pick)
	return pick


func _build_enemies(host: Node2D) -> void:
	for e in ENEMIES:
		enemy(host, String(e[0]), String(e[1]), e[2], e[3])


func _build_decor(host: Node2D) -> void:
	for x in TORCHES:
		torch(host, x, FLOOR_Y, TORCH_TINT)
	# 旧缆减半，染成炉渣锈色；地面用干石/石板，支柱用工字梁。
	var cable_xs: Array = []
	for i in range(VINES.size()):
		if i % 2 == 0:
			cable_xs.append(VINES[i])
	for x in cable_xs:
		hanging(host, "vine", Vector2(x, CEILING_Y + 32.0), VINE_TINT)
	for x in ARCHES:
		prop(host, "slab", Vector2(x, FLOOR_Y), 1.0, ARCH_TINT)
	# 十字形碎石是墓园符号；渣地上只留普通碎渣。
	var rubble_keys := ["rubble_dry", "rubble_dry_c"]
	for i in range(RUBBLE.size()):
		prop(host, rubble_keys[i % rubble_keys.size()], Vector2(RUBBLE[i], FLOOR_Y), 1.0, RUBBLE_TINT)
	# 熔渣支柱用本主题干石板，不用圣殿 column_big（背景已是工业剪影）。
	for x in COLUMNS:
		prop(host, "slab", Vector2(x, FLOOR_Y), 1.0, COLUMN_TINT)
	# 渣口：骷髅炉口立在落口和锈门边；骨渣散在渣堤上——渣记得剑，也记得人。
	prop(host, "skull_arch", Vector2(24, FLOOR_Y))
	# 坏在这里的机械：渣堤上那台不转了，断掉的斜撑倒在渣河边上，排气管还立着。
	prop(host, "broken_machine", Vector2(1088, FLOOR_Y), 1.0, GIRDER_TINT)
	prop(host, "girder_l", Vector2(1168, FLOOR_Y), 1.0, GIRDER_TINT)
	prop(host, "pipe_valve", Vector2(2072, FLOOR_Y), 1.0, PIPE_TINT)
	prop(host, "bones", Vector2(1016, FLOOR_Y), 1.0, RUBBLE_TINT)
	prop(host, "bones", Vector2(2232 + 64, FLOOR_Y), 1.0, RUBBLE_TINT)
	# ⑩⑪ 渣河桥 / 旧壳区：旧船壳、断梁与压边的碎石；桥头一台坏机械。
	prop(host, "broken_machine", Vector2(3064, FLOOR_Y), 1.0, GIRDER_TINT)
	prop(host, "girder_l", Vector2(3136, FLOOR_Y), 1.0, GIRDER_TINT)
	prop(host, "rubble_dry", Vector2(3656, FLOOR_Y), 1.0, RUBBLE_TINT)
	prop(host, "skull_arch", Vector2(3904, FLOOR_Y))
	prop(host, "broken_machine", Vector2(3952, FLOOR_Y), 1.0, GIRDER_TINT)
	prop(host, "girder_r", Vector2(4024, FLOOR_Y), 1.0, GIRDER_TINT)
	# 视觉 QA P1：渣河两岸压边——碎石 / 坏机械 / 断梁压住几条直边，别让液面
	# 在屏幕底部露出一整条几何直边；scum 只在近岸（ramp 的最高一档）亮。
	var shore: Array = [
		["rubble_dry", Vector2(400, FLOOR_Y)],
		["rubble_dry_c", Vector2(864, FLOOR_Y)],
		["broken_machine", Vector2(1184, FLOOR_Y)],
		["girder_l", Vector2(2576, FLOOR_Y)],
		["rubble_dry", Vector2(2896, FLOOR_Y)],
		["broken_machine", Vector2(3376, FLOOR_Y)],
		["girder_r", Vector2(3664, FLOOR_Y)],
	]
	for s in shore:
		prop(host, String(s[0]), s[1], 1.0, GIRDER_TINT if String(s[0]) != "rubble_dry" \
				and String(s[0]) != "rubble_dry_c" else RUBBLE_TINT)
