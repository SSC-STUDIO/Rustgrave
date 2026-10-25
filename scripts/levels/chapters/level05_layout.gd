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
##                     可选：池面上方的检修龛（钩锁），碑文「吊」——本章支路
##   D 压板塔       1568–2112 余烬巢二；竖向吊台 D 送上压板台（碑文二），开闸门 B；幽魂守走廊
##   E 双吊台接力   2112–2512 吊台 E1/E2 相位错开半周，半程换乘
##   F 锈门与运渣道 2512–3440 余烬巢三；台阶上检修走道（喷吐者、钩锁锚点、系核）；齿盾卫守锈门
##   G 吊装下层     3440–4000 锈门后的吊装下层：吊台 F 横渡第二口冷却槽、吊装检修台
##                     （钩锁支路，带 1 个奖励位）、下层巢；出口「运渣道」→ level06

const EAST := 4000
const CEILING_Y := -32.0
## 暖色石板：工坊是烘过的地面，和地窟的青砖、圣殿的冷紫分开。
const STONE_WARM := Color(1.0, 0.92, 0.82)
## 检修走道用教堂浮石皮肤，抬暖一点，别在暖地面上读成紫色。
const WALK_TONE := Color(1.08, 1.0, 0.86)
## 冷却液：比腐液更青、更亮，暖石板上才认得出是"液体"。
const COOLANT := Color(0.8, 1.1, 1.1)
const TORCH_TINT := Color(1.0, 0.94, 0.86)
## 藤条贴图本身是青苔绿。乘深锈色才不会在工坊顶上长出一蓬墓园藤。
const CABLE_TINT := Color(0.42, 0.26, 0.14, 0.8)
## 立柱压成烘过的石色，和暖石板是一家。
const PILLAR := Color(0.72, 0.62, 0.52)
## 历史机械件（斜撑 / 阀座 / 坏机械 / 断链）：铁族派生副本已经是暖褐色，只压一档灰尘。
const GIRDER_TINT := Color(0.9, 0.78, 0.68)
const PIPE_TINT := Color(0.82, 0.74, 0.66)
const CHAIN_TINT := Color(0.78, 0.66, 0.52, 0.9)

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
const GEAR_B1 := Vector2(536, 304)
const GEAR_B2 := Vector2(616, 304)
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

## 可选支路：长冷却池上方的检修龛（NookDeck）。从 FloorC 东端用钩索拉上去，
## 没有钩锁时从任何踏点都跳不到（落差 144 > 34）。龛里是工坊最后一条遗训。
## 锚点在龛的正上方，落台在锚点下方 48px，是标准钩锁落点。
const NOOK_DECK := Rect2(1456, 152, 96, 16)
const HOOK_NOOK_POS := Vector2(1488, 120)
const STELE_NOOK_POS := Vector2(1520, 152)

## F 锈门与运渣道
const FLOOR_E := Vector2(2512, 3440)
const NEST_GATE_X := 2576.0
const STEPS_E: Array = [Vector2(2624, 296), Vector2(2688, 264), Vector2(2752, 232)]
const WALK_E := Rect2(2816, 208, 192, 16)
const HOOK_POS := Vector2(2936, 136)
const PICKUP_POS := Vector2(2920, 160)
const GATE_POS := Vector2(2872, 256)
const SIGN_F_POS := Vector2(2912, 320)
const EXIT_X := 3900.0

## G 吊装下层：锈门后的第二口冷却槽（坑底 352），吊台 F 横渡；下层检修台是钩锁支路。
const PIT_F := Vector2(3440, 3680)
const LIFT_F_POS := Vector2(3440, 296)
const LIFT_F_TRAVEL := Vector2(240, 0)
const LIFT_F_PERIOD := 7.0
const HOIST_DECK := Rect2(3560, 240, 96, 16)
const HOOK_HOIST_POS := Vector2(3560, 136)
const REWARD_POS := Vector2(3600, 233)
const REWARD_SCENE := "res://scenes/interactables/EquipmentPickup.tscn"
const REWARD_KIND := "equipment"
const REWARD_REF := "iron_carapace"
const NEST_HOIST_X := 3408.0
const FLOOR_G := Vector2(3680, 4000)

## [name, kind, pos]；落地敌人给脚点，飞行/穿墙给悬停中心。
const ENEMIES: Array = [
	["Scrapper1", "scrapper", Vector2(400, 320)],
	["Spitter1", "spitter", Vector2(736, 208)],
	["Scrapper2", "scrapper", Vector2(830, 320)],
	["FlyingDemon1", "flying_demon", Vector2(1360, 208)],
	["Ghost1", "ghost", Vector2(1968, 256)],
	["GearShield1", "gear_shield", Vector2(2816, 320)],
	["Spitter2", "spitter", Vector2(2984, 208)],
	## G 吊装下层：幽魂在吊台渡口上方，碎铁犬守下层出口前的地面。
	["Ghost2", "ghost", Vector2(3180, 256)],
	["Scrapper3", "scrapper", Vector2(3840, 320)],
]


func level_id() -> String:
	return "level05"


func title() -> String:
	return ChapterText.title_of(level_id())


func wake_line() -> String:
	return ChapterText.wake_of(level_id())


## 碑文文本只从 ChapterText 取；位置常量留在这里（几何归关卡，文本归注册表）。
func _stele(host: Node2D, node_name: String, pos: Vector2) -> void:
	var entry := ChapterText.stele_of(level_id(), node_name)
	stele(host, node_name, pos, String(entry.get("title", "")), String(entry.get("text", "")))


func entry_spawn() -> Vector2:
	return SPAWN


func east_limit() -> int:
	return EAST


func theme() -> String:
	return "industrial"


func motes() -> String:
	return "sparks"


## 工坊有顶：淬火槽冒的是热汽不是雨；炉口附近起余烬风，别处只是薄雾。
func weather_recipe() -> Dictionary:
	return {
		"allowed": [WorldClock.Weather.HAZE, WorldClock.Weather.EMBER_WIND, WorldClock.Weather.CLEAR],
		"weights": {"*": {"haze": 4, "ember_wind": 3, "clear": 1}},
		"hold": Vector2(220.0, 380.0),
		"intensity": Vector2(0.45, 0.85),
	}


func build(host: Node2D) -> void:
	_build_terrain(host)
	_build_mechanisms(host)
	_build_props(host)
	_build_enemies(host)
	_build_decor(host)
	exit_door(host, EXIT_X, ChapterText.exit_label_of(level_id()),
			ChapterText.exit_captions_of(level_id()), "level05_done",
			GameContext.next_level_id(level_id()))
	finish(host)


## ------------------------------------------------------------------ terrain --

func _build_terrain(host: Node2D) -> void:
	floor_strip(host, "FloorA", FLOOR_A.x, FLOOR_A.y, "iron", false, true, FLOOR_Y)
	_coolant_pit(host, "PitB", PIT_B.x, PIT_B.y, FLOOR_Y + 32.0)
	floor_strip(host, "FloorB", FLOOR_B.x, FLOOR_B.y, "iron", true, true, FLOOR_Y)
	# 长冷却池：矮唇让掉下去的人两跳爬回来（368 → 352 → 320）。
	platform(host, "LipC1", LIP_C1, Vector2(32, 48), "iron", false, false)
	platform(host, "BedC", Vector2(POOL_C.position.x, POOL_C.position.y + 16.0),
			Vector2(POOL_C.size.x, FLOOR_Y + 80.0 - POOL_C.position.y - 16.0), "iron", false, false)
	platform(host, "LipC2", LIP_C2, Vector2(32, 48), "iron", false, false)
	toxin(host, "PoolC", POOL_C.position, POOL_C.size, COOLANT)
	floor_strip(host, "FloorC", FLOOR_C.x, FLOOR_C.y, "iron", true, true, FLOOR_Y)
	_coolant_pit(host, "PitE", PIT_E.x, PIT_E.y, FLOOR_Y + 32.0)
	floor_strip(host, "FloorE", FLOOR_E.x, FLOOR_E.y, "iron", true, true, FLOOR_Y)
	# G 吊装下层：第二口冷却槽 + 对岸地面；吊台 F 横渡。
	_coolant_pit(host, "PitF", PIT_F.x, PIT_F.y, FLOOR_Y + 32.0)
	floor_strip(host, "FloorG", FLOOR_G.x, FLOOR_G.y, "iron", true, false, FLOOR_Y)
	enclose(host, "iron", CEILING_Y)

	# 齿轮踏点：淬火坑上两块，长池池心一块（半截泡在液里，掉下去的人踩它歇口气）。
	gear(host, "GearB1", GEAR_B1)
	gear(host, "GearB2", GEAR_B2)
	gear(host, "GearC1", GEAR_C1)

	# 检修走道 B 与它的三级台阶（从闸门这头往西爬）。
	# 走道用和地面同一套暖石板。floating 是教堂紫石，搁在工坊里像另一关的台子。
	step(host, "WalkB", WALK_B.position, WALK_B.size.x, "iron_float")
	for i in STEPS_B.size():
		step(host, "StepB%d" % (i + 1), STEPS_B[i], STEP_W, "iron_float")
	# 压板台：只有吊台 D 送得上去。
	step(host, "DeckD", DECK_D.position, DECK_D.size.x, "iron_float")
	# 可选检修龛：长冷却池上方，只有钩锁能上。走道/吊台都够不到它。
	step(host, "NookDeck", NOOK_DECK.position, NOOK_DECK.size.x, "iron_float")
	# 检修走道 E 与它的三级台阶（从余烬巢这头往东爬）。
	for i in STEPS_E.size():
		step(host, "StepE%d" % (i + 1), STEPS_E[i], STEP_W, "iron_float")
	step(host, "WalkE", WALK_E.position, WALK_E.size.x, "iron_float")
	# G 吊装下层：吊装检修台悬在第二口冷却槽上方，只有钩锁能从坑边拉上去。
	step(host, "HoistDeck", HOIST_DECK.position, HOIST_DECK.size.x, "iron_float")


## 冷却液坑：坑底铺暖石板，液面（32 厚）压在坑底上方 16px。
func _coolant_pit(host: Node2D, pit_name: String, x0: float, x1: float, bed_y: float) -> void:
	platform(host, pit_name + "Bed", Vector2(x0, bed_y), Vector2(x1 - x0, FLOOR_Y + 80.0 - bed_y),
			"iron", false, false)
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
	# 支路锚点：从 FloorC 东端起跳在 250px 索距内，落台在锚点下方 48px。
	hook(host, "HookNook", HOOK_NOOK_POS)
	_stele(host, "SteleNook", STELE_NOOK_POS)
	# G 吊装下层：吊台 F 横渡第二口冷却槽；吊装检修台（钩锁支路）与它的锚点。
	lift(host, "LiftF", LIFT_F_POS, LIFT_F_TRAVEL, LIFT_F_PERIOD, 64.0)
	hook(host, "HookHoist", HOOK_HOIST_POS)
	_reward(host)


## -------------------------------------------------------------------- props --

func _build_props(host: Node2D) -> void:
	nest(host, "EmberNestStart", NEST_START_X)
	nest(host, "EmberNestLift", NEST_LIFT_X)
	nest(host, "EmberNestGate", NEST_GATE_X)
	nest(host, "EmberNestHoist", NEST_HOIST_X)
	_stele(host, "SteleQuench", STELE_A_POS)
	_stele(host, "SteleChain", STELE_B_POS)
	waymark(host, SIGN_A_POS, "工坊")
	waymark(host, SIGN_F_POS, "渣道")
	# 可破坏道具（M3）：全部在钩锁支路台面上，主线不靠打碎任何东西通过。
	# 检修龛（NookDeck，顶面 y=152）：遗训碑文西侧一只锈罐。
	destructible(host, "RustUrnNook", &"rust_urn", Vector2(1476, 152))
	# 吊装检修台（HoistDeck，顶面 y=240）：奖励位两侧——西端碎铁堆、东端余烬窖
	# （掉 3 点余烬经验）。
	destructible(host, "ScrapHeapHoist", &"scrap_heap", Vector2(3572, 240))
	destructible(host, "EmberCacheHoist", &"ember_cache", Vector2(3640, 240))


## G 吊装下层的奖励位：吊装检修台（钩锁支路）上的一件工坊遗物。
func _reward(host: Node2D) -> Node:
	if not ResourceLoader.exists(REWARD_SCENE):
		return null
	var scene := load(REWARD_SCENE) as PackedScene
	if scene == null:
		return null
	var pick := scene.instantiate()
	pick.name = "RewardHoist"
	pick.position = REWARD_POS
	pick.set("reward_kind", REWARD_KIND)
	pick.set("reward_ref", REWARD_REF)
	var item := EquipmentCatalog.for_id(StringName(REWARD_REF))
	pick.set("reward_name", item.display_name if item != null else "")
	group(host, "Pickups").add_child(pick)
	return pick


## ------------------------------------------------------------------ enemies --

func _build_enemies(host: Node2D) -> void:
	for e in ENEMIES:
		enemy(host, String(e[0]), String(e[1]), e[2])


## -------------------------------------------------------------------- decor --

func _build_decor(host: Node2D) -> void:
	# 工坊地面只用本主题像素石板/碎渣；Kenney 的机械件只种派生过的 1x 族副本
	# （girder / pipe_valve / broken_machine / chain，见 tools/gen_theme_tiles.py
	# 的 history_prop_variants），不再把 70×70 的平滑灰板直接贴进关里。
	torch(host, 440.0, FLOOR_Y, TORCH_TINT)
	# 456 整块落在 440 的壁炬墙板里。收到路牌和火把之间。
	prop(host, "rubble_dry", Vector2(390, FLOOR_Y))
	prop(host, "plate", Vector2(728, FLOOR_Y), 1.0, Color(0.7, 0.62, 0.55))
	torch(host, 760.0, FLOOR_Y, TORCH_TINT)
	prop(host, "plate", Vector2(848, WALK_Y), 1.0, Color(0.72, 0.66, 0.58))
	# 十字形碎石是墓园符号，工坊地上换普通碎渣。
	prop(host, "rubble_dry_c", Vector2(900, FLOOR_Y))
	# 工坊支柱用本主题石板/金属板，不用圣殿 column_big。
	prop(host, "plate", Vector2(990, FLOOR_Y), 1.0, PILLAR)
	# 「上一班没干完的活」：倒下的斜撑还靠在闸门西侧，阀座留在原地。
	prop(host, "girder_l", Vector2(1040, FLOOR_Y), 1.0, GIRDER_TINT)
	prop(host, "pipe_valve", Vector2(1080, FLOOR_Y), 1.0, PIPE_TINT)
	torch(host, 1688.0, FLOOR_Y, TORCH_TINT)
	prop(host, "plate", Vector2(1744, DECK_Y), 1.0, Color(0.72, 0.66, 0.58))
	prop(host, "slab", Vector2(1784, FLOOR_Y), 1.0, Color(0.7, 0.6, 0.52))
	prop(host, "rubble_dry_c", Vector2(1848, FLOOR_Y))
	prop(host, "slab", Vector2(1968, FLOOR_Y), 1.0, PILLAR)
	prop(host, "rubble_dry", Vector2(2524, FLOOR_Y))
	# 台阶从 2624 起。石板收在台阶西侧的空地上，不立在踏步中间。
	prop(host, "plate", Vector2(2588, FLOOR_Y), 1.0, PILLAR)
	prop(host, "broken_machine", Vector2(2696, FLOOR_Y), 1.0, GIRDER_TINT)
	prop(host, "plate", Vector2(2856, WALK_Y), 1.0, Color(0.7, 0.62, 0.55))
	torch(host, 2832.0, FLOOR_Y, TORCH_TINT)
	# G 吊装下层：锈门后的第二段运渣道，吊装机械与断缆更密。
	torch(host, 3080.0, FLOOR_Y, TORCH_TINT)
	prop(host, "girder_l", Vector2(3128, FLOOR_Y), 1.0, GIRDER_TINT)
	prop(host, "pipe_valve", Vector2(3208, FLOOR_Y), 1.0, PIPE_TINT)
	prop(host, "plate", Vector2(3288, FLOOR_Y), 1.0, PILLAR)
	prop(host, "broken_machine", Vector2(3392, FLOOR_Y), 1.0, GIRDER_TINT)
	torch(host, 3400.0, FLOOR_Y, TORCH_TINT)
	torch(host, 3760.0, FLOOR_Y, TORCH_TINT)
	prop(host, "slab", Vector2(3728, FLOOR_Y), 1.0, Color(0.68, 0.58, 0.5))
	prop(host, "rubble_dry", Vector2(3808, FLOOR_Y))
	prop(host, "girder_r", Vector2(3880, FLOOR_Y), 1.0, GIRDER_TINT)
	# 顶板垂下的旧缆：仍用窄藤条资源，但染成锈缆色，数量更少。
	for x in [300.0, 1560.0, 2596.0, 3352.0, 3856.0]:
		hanging(host, "vine", Vector2(x, 0), CABLE_TINT)
	# 吊装的残链：工坊的核心机械是吊链，断掉的那半截还挂在顶板下。
	for x in [640.0, 1904.0, 3184.0, 3560.0]:
		hanging(host, "chain", Vector2(x, 0), CHAIN_TINT)
