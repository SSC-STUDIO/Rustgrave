extends ChapterLayout
## 锈墓・伍 — 齿轮工坊。造锈核的工坊：齿轮还在转，没有人给它们上油。
## 全关机关最多：四座链吊台（横渡长冷却池 / 竖向送上压板台 / 相位错开的双吊台接力）、
## 两组压板闸门（第二组的压板只有乘吊台才踩得到）、三块齿轮踏点、一道锈门、一个钩锁锚点。
##
## 结构（地面 y=320，一跳 ≤32px 高、≤72px 远；两条检修走道一律 y=208，比地面高 112，
## 走道上的喷吐者够不到地面上的人，只打爬台阶的人）：
##   A 入口车间     0–480     余烬巢一、碑文一、路牌；一只碎铁犬
##   B 淬火槽       480–1152  两块齿轮踏点跨过淬火坑；三级台阶上检修走道，喷吐者守压板 A，开闸门 A
##   C 长冷却池     1152–1568 吊台 C 横渡；池心一块齿轮石；飞行恶魔盘旋
##   D 压板塔       1568–2112 余烬巢二；竖向吊台 D 送上压板台（碑文二），开闸门 B；幽魂守走廊
##   E 双吊台接力   2112–2512 吊台 E1/E2 相位错开半周，半程换乘
##   F 锈门与运渣道 2512–3040 余烬巢三；台阶上检修走道（喷吐者、钩锁锚点、系核）；齿盾卫守锈门；出口

const EAST := 3040
const CEILING_Y := -32.0
## 暖色石板：工坊是烘过的地面，和地窟的青砖、圣殿的冷紫分开。
const STONE_WARM := Color(1.0, 0.92, 0.82)
## 检修走道用教堂浮石皮肤，抬暖一点，别在暖地面上读成紫色。
const WALK_TONE := Color(1.08, 1.0, 0.86)
## 冷却液：比腐液更青、更亮，暖石板上才认得出是"液体"。
const COOLANT := Color(0.8, 1.1, 1.1)
const TORCH_TINT := Color(1.0, 0.94, 0.86)
## 顶板垂下的旧缆，压成锈色。
const CABLE_TINT := Color(0.85, 0.7, 0.5, 0.9)

const WALK_Y := 208.0
const DECK_Y := 200.0
const STEP_W := 48.0

## A 入口车间
const SPAWN := Vector2(96, 300)
const FLOOR_A := Vector2(0, 480)
const NEST_START_X := 176.0
const STELE_A_POS := Vector2(264, 320)
const SIGN_A_POS := Vector2(352, 320)

## B 淬火槽
const PIT_B := Vector2(480, 688)
const GEAR_B1 := Vector2(536, 312)
const GEAR_B2 := Vector2(616, 312)
const FLOOR_B := Vector2(688, 1152)
const WALK_B := Rect2(720, 208, 160, 16)
## 从东往西爬：地面 → 296 → 264 → 232 → 走道 208。
const STEPS_B: Array = [Vector2(1024, 296), Vector2(960, 264), Vector2(896, 232)]
const PLATE_A_FEET := Vector2(784, 208)
const DOOR_A_POS := Vector2(1104, 256)

## C 长冷却池（两侧矮唇 352，池底 368，液面 352..384）
const LIP_C1 := Vector2(1152, 352)
const LIP_C2 := Vector2(1536, 352)
const POOL_C := Rect2(1184, 352, 352, 32)
const GEAR_C1 := Vector2(1360, 352)
const LIFT_C_POS := Vector2(1168, 296)
const LIFT_C_TRAVEL := Vector2(320, 0)
const LIFT_C_PERIOD := 9.6

## D 压板塔
const FLOOR_C := Vector2(1568, 2112)
const NEST_LIFT_X := 1616.0
const LIFT_D_POS := Vector2(1840, 304)
const LIFT_D_TRAVEL := Vector2(0, -104)
const LIFT_D_PERIOD := 6.4
## 压板台：只有吊台 D 顶点（1840,200）往左跳 16px 能上；地面离它 120px。
const DECK_D := Rect2(1696, 200, 128, 16)
const PLATE_B_FEET := Vector2(1744, 200)
const STELE_B_POS := Vector2(1800, 200)
const DOOR_B_POS := Vector2(2048, 256)

## E 双吊台接力：E1 到东端时 E2 正好回到西端，甲板相隔 16px。
const PIT_E := Vector2(2112, 2512)
const LIFT_E1_POS := Vector2(2128, 296)
const LIFT_E2_POS := Vector2(2320, 296)
const LIFT_E_TRAVEL := Vector2(112, 0)
const LIFT_E_PERIOD := 6.0
const LIFT_E2_PHASE := 0.5

## F 锈门与运渣道
const FLOOR_E := Vector2(2512, 3040)
const NEST_GATE_X := 2576.0
const STEPS_E: Array = [Vector2(2624, 296), Vector2(2688, 264), Vector2(2752, 232)]
const WALK_E := Rect2(2816, 208, 192, 16)
const HOOK_POS := Vector2(2936, 136)
const PICKUP_POS := Vector2(2920, 160)
const GATE_POS := Vector2(2872, 256)
const SIGN_F_POS := Vector2(2912, 320)
const EXIT_X := 2960.0

## [name, kind, pos]；落地敌人给脚点，飞行/穿墙给悬停中心。
const ENEMIES: Array = [
	["Scrapper1", "scrapper", Vector2(400, 320)],
	["Spitter1", "spitter", Vector2(736, 208)],
	["Scrapper2", "scrapper", Vector2(830, 320)],
	["FlyingDemon1", "flying_demon", Vector2(1360, 208)],
	["Ghost1", "ghost", Vector2(1968, 256)],
	["GearShield1", "gear_shield", Vector2(2816, 320)],
	["Spitter2", "spitter", Vector2(2984, 208)],
]


func level_id() -> String:
	return "level05"


func title() -> String:
	return "锈墓・伍 — 齿轮工坊"


func wake_line() -> String:
	return "齿轮还在转。没有人给它们上油。"


func entry_spawn() -> Vector2:
	return SPAWN


func east_limit() -> int:
	return EAST


func theme() -> String:
	return "industrial"


func build(host: Node2D) -> void:
	_build_terrain(host)
	_build_mechanisms(host)
	_build_props(host)
	_build_enemies(host)
	_build_decor(host)
	exit_door(host, EXIT_X, "运渣道", PackedStringArray([
		"运渣道一路向下。渣里还有没烧透的火星。",
		"尽头有雨声。墓园在另一侧等着。",
	]), "level05_done", GameContext.next_level_id(level_id()))
	finish(host)


## ------------------------------------------------------------------ terrain --

func _build_terrain(host: Node2D) -> void:
	floor_strip(host, "FloorA", FLOOR_A.x, FLOOR_A.y, "stone", false, true, FLOOR_Y, STONE_WARM)
	_coolant_pit(host, "PitB", PIT_B.x, PIT_B.y, FLOOR_Y + 32.0)
	floor_strip(host, "FloorB", FLOOR_B.x, FLOOR_B.y, "stone", true, true, FLOOR_Y, STONE_WARM)
	# 长冷却池：矮唇让掉下去的人两跳爬回来（368 → 352 → 320）。
	platform(host, "LipC1", LIP_C1, Vector2(32, 48), "stone", false, false, STONE_WARM)
	platform(host, "BedC", Vector2(POOL_C.position.x, POOL_C.position.y + 16.0),
			Vector2(POOL_C.size.x, FLOOR_Y + 80.0 - POOL_C.position.y - 16.0), "stone", false, false, STONE_WARM)
	platform(host, "LipC2", LIP_C2, Vector2(32, 48), "stone", false, false, STONE_WARM)
	toxin(host, "PoolC", POOL_C.position, POOL_C.size, COOLANT)
	floor_strip(host, "FloorC", FLOOR_C.x, FLOOR_C.y, "stone", true, true, FLOOR_Y, STONE_WARM)
	_coolant_pit(host, "PitE", PIT_E.x, PIT_E.y, FLOOR_Y + 32.0)
	floor_strip(host, "FloorE", FLOOR_E.x, FLOOR_E.y, "stone", true, false, FLOOR_Y, STONE_WARM)
	enclose(host, "stone", CEILING_Y, -1.0, 0.0, STONE_WARM)

	# 齿轮踏点：淬火坑上两块，长池池心一块（半截泡在液里，掉下去的人踩它歇口气）。
	gear(host, "GearB1", GEAR_B1)
	gear(host, "GearB2", GEAR_B2)
	gear(host, "GearC1", GEAR_C1)

	# 检修走道 B 与它的三级台阶（从闸门这头往西爬）。
	step(host, "WalkB", WALK_B.position, WALK_B.size.x, "floating", WALK_TONE)
	for i in STEPS_B.size():
		step(host, "StepB%d" % (i + 1), STEPS_B[i], STEP_W, "floating", WALK_TONE)
	# 压板台：只有吊台 D 送得上去。
	step(host, "DeckD", DECK_D.position, DECK_D.size.x, "floating", WALK_TONE)
	# 检修走道 E 与它的三级台阶（从余烬巢这头往东爬）。
	for i in STEPS_E.size():
		step(host, "StepE%d" % (i + 1), STEPS_E[i], STEP_W, "floating", WALK_TONE)
	step(host, "WalkE", WALK_E.position, WALK_E.size.x, "floating", WALK_TONE)


## 冷却液坑：坑底铺暖石板，液面（32 厚）压在坑底上方 16px。
func _coolant_pit(host: Node2D, pit_name: String, x0: float, x1: float, bed_y: float) -> void:
	platform(host, pit_name + "Bed", Vector2(x0, bed_y), Vector2(x1 - x0, FLOOR_Y + 80.0 - bed_y),
			"stone", false, false, STONE_WARM)
	toxin(host, pit_name + "Pool", Vector2(x0, bed_y - 16.0), Vector2(x1 - x0, 32.0), COOLANT)


## --------------------------------------------------------------- mechanisms --

func _build_mechanisms(host: Node2D) -> void:
	# 吊台 C：横渡长冷却池。上船 FloorB 东沿（1152,320）→ 甲板（1168,296）；下船 FloorC（1568,320）。
	lift(host, "LiftC", LIFT_C_POS, LIFT_C_TRAVEL, LIFT_C_PERIOD, 64.0)
	# 吊台 D：竖向，从地面上方 16px 升到压板台高度；顶点往左 16px 就是 DeckD。
	lift(host, "LiftD", LIFT_D_POS, LIFT_D_TRAVEL, LIFT_D_PERIOD, 48.0)
	# 吊台 E1/E2：相位差半周。E1 到东端（2304）时 E2 正在西端（2320），换乘一步。
	lift(host, "LiftE1", LIFT_E1_POS, LIFT_E_TRAVEL, LIFT_E_PERIOD, 64.0, 0.0)
	lift(host, "LiftE2", LIFT_E2_POS, LIFT_E_TRAVEL, LIFT_E_PERIOD, 64.0, LIFT_E2_PHASE)

	# 闸门 A：压板在检修走道 B 西端，喷吐者身后；闸门堵在吊台 C 上船点前。
	plate_door(host, "GateA", PLATE_A_FEET, DOOR_A_POS)
	# 闸门 B：压板在只有吊台 D 能到的高台上；闸门堵在双吊台接力前。
	plate_door(host, "GateB", PLATE_B_FEET, DOOR_B_POS)
	# 锈门：到这一关的人一定有热锻。
	rusty_gate(host, "RustGate", GATE_POS)
	# 钩锁锚点悬在走道 E 上方：有钩锁的人从地面直接上走道；没有的人爬台阶去拿系核。
	hook(host, "HookE", HOOK_POS)
	pickup(host, "TetherCoreE", PICKUP_POS, &"tether_core")


## -------------------------------------------------------------------- props --

func _build_props(host: Node2D) -> void:
	nest(host, "EmberNestStart", NEST_START_X)
	nest(host, "EmberNestLift", NEST_LIFT_X)
	nest(host, "EmberNestGate", NEST_GATE_X)
	stele(host, "SteleQuench", STELE_A_POS, "工坊遗训 · 淬火",
			"他们把剑淬进冷却液，换出一枚锈核。剑从此不再认主。")
	stele(host, "SteleChain", STELE_B_POS, "工坊遗训 · 吊链",
			"吊台的链子是旧剑熔的。每一环都曾有过名字。")
	waymark(host, SIGN_A_POS, "工坊")
	waymark(host, SIGN_F_POS, "渣道")


## ------------------------------------------------------------------ enemies --

func _build_enemies(host: Node2D) -> void:
	for e in ENEMIES:
		enemy(host, String(e[0]), String(e[1]), e[2])


## -------------------------------------------------------------------- decor --

func _build_decor(host: Node2D) -> void:
	# A 入口车间：来路的门洞、壁炬、碎石。
	prop(host, "door_arch", Vector2(96, FLOOR_Y))
	torch(host, 440.0, FLOOR_Y, TORCH_TINT)
	prop(host, "rubble", Vector2(456, FLOOR_Y))
	# B 淬火槽：坑沿石栏，走道下的壁炬（火焰在走道底下 16px），台阶靠着一根大柱。
	prop(host, "balustrade", Vector2(728, FLOOR_Y))
	torch(host, 760.0, FLOOR_Y, TORCH_TINT)
	prop(host, "balustrade", Vector2(840, WALK_Y))
	prop(host, "rubble", Vector2(900, FLOOR_Y))
	prop(host, "column", Vector2(990, FLOOR_Y))
	# D 压板塔：巢边壁炬、盲门洞、碎石；压板台上一段石栏；走廊尽头一根大柱。
	torch(host, 1688.0, FLOOR_Y, TORCH_TINT)
	prop(host, "balustrade", Vector2(1736, DECK_Y))
	prop(host, "door_arch", Vector2(1760, FLOOR_Y))
	prop(host, "rubble", Vector2(1808, FLOOR_Y))
	prop(host, "column", Vector2(1990, FLOOR_Y))
	# F 锈门与运渣道：落点碎石、台阶靠柱、走道西端石栏、锈门前壁炬。
	prop(host, "rubble", Vector2(2536, FLOOR_Y))
	prop(host, "column", Vector2(2672, FLOOR_Y))
	prop(host, "balustrade", Vector2(2856, WALK_Y))
	torch(host, 2832.0, FLOOR_Y, TORCH_TINT)
	# 顶板垂下的旧缆：少量，避开吊台链子扫过的范围。
	for x in [300.0, 600.0, 1560.0, 2090.0, 2596.0]:
		hanging(host, "vine", Vector2(x, 0), CABLE_TINT)
