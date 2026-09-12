extends ChapterLayout
## 锈墓・捌「熔渣深渊」——钟楼底下的渣海。渣还记得剑的形状，火骷髅在上面飘。
## 全关只用 ChapterLayout 的助手铺设；测试可以在一个空 Node2D 上 build()。
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

const EAST_LIMIT := 3008
const CEILING_Y := -32.0
const PIT_DEPTH := 32.0
## 琥珀地面：把地窟苔砖压成被炉火烤过的颜色（地面、浮石、坑底、墙顶同色）。
const GROUND_TONE := Color(1.0, 0.8, 0.6)
## 熔渣：比琥珀地面亮得多、红得多，池面一眼能和地面分开。
## tint 是乘法着色，而 toxin_sludge.png 本身是极暗的青绿（平均 RGB ≈ 8/32/30），
## 红通道接近 0——温和的橙色 tint 乘上去仍是深青。这里把红通道拉到过曝：
## 液体变成 (0.7, 0.27, 0.07) 的暗橙、亮点钳到纯橙，浮沫成为黄热的一线；
## 项目是 gl_compatibility 的 LDR 帧缓冲，过曝会被钳住（受击白闪同理）。
const SLAG_TINT := Color(22.0, 2.2, 0.6)
## 吊台与八角台没有 tone 参数，用 modulate 压成同一族暖色。
const LIFT_TONE := Color(1.0, 0.82, 0.62)
## 八角台原本是偏冷紫的教堂石：压成烤过的渣褐色，别在橙池上飘一块粉石头。
const GEAR_TONE := Color(0.9, 0.62, 0.42)
const TORCH_TINT := Color(1.0, 0.75, 0.55)
const VINE_TINT := Color(1.0, 0.82, 0.6, 0.9)
const ARCH_TINT := Color(1.0, 0.8, 0.62)
const RUBBLE_TINT := Color(1.0, 0.82, 0.64)
const COLUMN_TINT := Color(0.62, 0.44, 0.32)

const ENTRY_SPAWN := Vector2(96, 300)

## [name, x0, x1] 地面段（顶 320，80 厚）。
const FLOORS: Array = [
	["FloorA", 0.0, 416.0],
	["FloorB", 848.0, 1200.0],
	["FloorC", 1728.0, 2208.0],
	["FloorD", 2272.0, 2352.0],
	["FloorE", 2416.0, 2592.0],
	["FloorG", 2880.0, 3008.0],
]
## [name, x0, x1] 熔渣坑：坑底 352、液面 336..368；坑沿到地面 32px，一跳爬得出来。
const PITS: Array = [
	["SlagA", 416.0, 848.0],
	["SlagB1", 1200.0, 1456.0],
	["SlagB2", 1488.0, 1728.0],
	["SlagC1", 2208.0, 2272.0],
	["SlagC2", 2352.0, 2416.0],
	["SlagD", 2592.0, 2880.0],
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
]
## [name, 中心, 半径] 八角渣台（顶面 = 中心 y - 半径）。
const GEARS: Array = [
	["GearD1", Vector2(2640, 304), 16.0],
	["GearD2", Vector2(2792, 296), 16.0],
]
## 两段熔渣中间的渣柱：吊台接力的落脚点，也是掉下去的人爬出来的地方。
const PILLAR_POS := Vector2(1456, 320)
const PILLAR_SIZE := Vector2(32, 80)
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
const EXIT_X := 2920.0
## [name, x] 余烬巢（都在地面 320 上）。
const NESTS: Array = [
	["EmberNestStart", 176.0],
	["EmberNestMid", 1792.0],
	["EmberNestGate", 2440.0],
]
const STELE_SLAG_POS := Vector2(256, 320)
const STELE_QUENCH_POS := Vector2(2968, 320)
const WAYMARKS: Array = [[Vector2(336, 320), "渣渊"], [Vector2(2576, 320), "城墙"]]
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
]
const TORCHES: Array = [384.0, 940.0, 1472.0, 1848.0, 2312.0, 2480.0, 2992.0]
const VINES: Array = [232.0, 560.0, 720.0, 1312.0, 1624.0, 2008.0, 2240.0, 2704.0, 2944.0]
const ARCHES: Array = [72.0, 1752.0]
const RUBBLE: Array = [396.0, 872.0, 2120.0, 2336.0]
const COLUMNS: Array = [1080.0, 2530.0]


func level_id() -> String:
	return "level08"


func title() -> String:
	return "锈墓・捌 — 熔渣深渊"


func wake_line() -> String:
	return "钟楼底下，渣还没凉。它记得每一把剑的形状。"


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


func build(host: Node2D) -> void:
	_build_terrain(host)
	_build_props(host)
	_build_enemies(host)
	_build_decor(host)
	exit_door(host, EXIT_X, "城墙梯", PackedStringArray([
		"梯子往上，热气也往上。",
		"风灌进来。锈城的城墙在头顶等着。",
	]), "level08_done", GameContext.next_level_id(level_id()))
	finish(host)


func _build_terrain(host: Node2D) -> void:
	for f in FLOORS:
		var x0: float = f[1]
		var x1: float = f[2]
		floor_strip(host, String(f[0]), x0, x1, "stone", x0 > 0.0, x1 < float(EAST_LIMIT), FLOOR_Y, GROUND_TONE)
	for p in PITS:
		_slag_pit(host, String(p[0]), p[1], p[2])
	for s in STEPS:
		step(host, String(s[0]), s[1], s[2], "floating", GROUND_TONE)
	platform(host, "SlagPillar", PILLAR_POS, PILLAR_SIZE, "stone", true, true, GROUND_TONE)
	for g in GEARS:
		var octagon := gear(host, String(g[0]), g[1], g[2])
		octagon.modulate = LIFT_TONE
	enclose(host, "stone", CEILING_Y, -1.0, 0.0, GROUND_TONE)
	var lift_a := lift(host, "LiftA", LIFT_A_POS, LIFT_A_TRAVEL, LIFT_PERIOD, LIFT_WIDTH, 0.0)
	lift_a.modulate = LIFT_TONE
	var lift_b := lift(host, "LiftB", LIFT_B_POS, LIFT_B_TRAVEL, LIFT_PERIOD, LIFT_WIDTH, LIFT_B_PHASE)
	lift_b.modulate = LIFT_TONE


## 熔渣坑：toxin_pit() 不给坑底上色，青苔坑底会在琥珀地面里露出一截青砖；
## 这里自己铺坑底（同 tone）再盖熔渣液面。命名沿用 <name>Bed / <name>Pool。
func _slag_pit(host: Node2D, pit_name: String, x0: float, x1: float) -> ToxinPool:
	var bed_y := FLOOR_Y + PIT_DEPTH
	platform(host, pit_name + "Bed", Vector2(x0, bed_y), Vector2(x1 - x0, FLOOR_Y + 80.0 - bed_y),
			"stone", false, false, GROUND_TONE)
	return toxin(host, pit_name + "Pool", Vector2(x0, bed_y - 16.0), Vector2(x1 - x0, 32.0), SLAG_TINT)


func _build_props(host: Node2D) -> void:
	for n in NESTS:
		nest(host, String(n[0]), n[1])
	stele(host, "SteleSlag", STELE_SLAG_POS, "熔渣纪事 · 渣",
			"渣记得每一把剑。铁熔了，形状沉在底下。")
	stele(host, "SteleQuench", STELE_QUENCH_POS, "熔渣纪事 · 淬",
			"有人把自己也淬了进去。渣面上至今浮着一层灰。")
	for w in WAYMARKS:
		waymark(host, w[0], String(w[1]))
	plate_door(host, "Sluice", PLATE_FEET, DOOR_POS)
	rusty_gate(host, "RustGate", GATE_POS)


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
		prop(host, "slab", Vector2(x, FLOOR_Y), 1.15, ARCH_TINT)
	var rubble_keys := ["rubble_dry", "rubble_dry_b", "rubble_dry_c"]
	for i in range(RUBBLE.size()):
		prop(host, rubble_keys[i % rubble_keys.size()], Vector2(RUBBLE[i], FLOOR_Y), 1.0, RUBBLE_TINT)
	for x in COLUMNS:
		prop(host, "beam_bolts", Vector2(x, FLOOR_Y), 1.2, COLUMN_TINT)
