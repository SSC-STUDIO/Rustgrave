extends ChapterLayout
## 锈墓・拾 — 铸钟厅 (level07b)：钟楼的井道一直通到城底的铸钟厅。炉温没降过，
## 钟是一炉一炉浇的——名字也是。
##
## 结构（室内 forge；地面 y=320，单跳 ≤32 高 / ≤72 远）：
##   ① 吊包区   0–1240    入口巢、两台横渡的链式吊包（LiftA/LiftB）跨过熔金池；
##                         池深 32，落进去能一跳爬出来（烫，但不锁死）
##   ② 钟模台   1240–1740  钟模坑上的模台：跳上模台压板 → 对岸闸门开；
##                         闸门之后是铸工碑与第二存档点
##   ③ 浇铸坑   1740–2160  两道齿轮（GearPlatform）跨过浇铸坑，Boss 房前存档巢
##   ④ Boss 房  2160–3440  平整的浇铸大厅；Boss「铸钟人」位（场景未交付时跳过）
##   出口 3424 → level08（井道通到渣底）
##
## 可选支路（上层钩锁）：吊包区东侧 FloorB 正上方 — 钩锁锚点 HookMold +
## MoldCatwalk；上面是《铸钟纪事 · 钥》碑文与一枚奖励锈核。主路线不经过它，
## 没有钩锁也能通关（level_sanity 主路线 allow_hook=false）。
##
## 文本全部来自 ChapterText（story-lead 所有）；这里只放几何与位置常量。

const ENTRY_SPAWN := Vector2(96, 300)
const EAST_LIMIT := 3520
const CEILING_Y := -192.0
## 铸钟厅是铸铁车间：地面/浮台用 iron 族，坑床与模台用 basalt 族。
const SKIN := "iron"
const FLOAT_SKIN := "iron_float"
const PIT_SKIN := "basalt"
## 熔金：toxin_sludge.png 本身是暗青绿，红通道接近 0；把红拉到过曝才读成
## 熔化的铜（同 level08 的渣池做法，LDR 帧缓冲会把过曝钳住）。
const MOLTEN_TINT := Color(20.0, 3.2, 0.45)
## 铸钟厅的壁炬是炉口砖膛（FURNACE_THEMES），再压一档暖橙。
const TORCH_TINT := Color(1.0, 0.82, 0.6)
const GIRDER_TINT := Color(0.86, 0.72, 0.6)
const PIPE_TINT := Color(0.8, 0.68, 0.58)
const RUBBLE_TINT := Color(1.0, 0.84, 0.68)
const CHAIN_TINT := Color(0.62, 0.56, 0.52, 0.85)
const VINE_TINT := Color(0.4, 0.3, 0.26, 0.8)

## [name, x0, x1, cap_left, cap_right] —— 主地面（顶 320，80 厚）
const FLOORS: Array = [
	["FloorA", 0.0, 448.0, false, true],
	["FloorB", 720.0, 1240.0, true, true],
	["FloorC", 1240.0, 1500.0, true, true],
	["FloorD", 1740.0, 2000.0, true, true],
	["FloorE", 2080.0, 3520.0, true, false],
]
## [name, x0, x1] —— 熔金/浇铸坑（坑底 352、液面 336..368；坑沿 32px 一跳爬出）
const PITS: Array = [
	["LadlePit", 448.0, 720.0],
	["MoldPit", 1500.0, 1740.0],
	["CastPit", 2000.0, 2080.0],
]
## 吊包区横渡：两台吊包同轨迹、不同高度/相位；甲板顶 y=296 / 264。
const LIFT_A_POS := Vector2(472, 296)
const LIFT_B_POS := Vector2(472, 264)
const LIFT_TRAVEL := Vector2(168, 0)
const LIFT_PERIOD_A := 5.2
const LIFT_PERIOD_B := 6.4
const LIFT_WIDTH := 72.0
const LIFT_CHAIN_TOP := CEILING_Y + 32.0
## 钟模台：模台浮在 MoldPit 上（模台底 320 高于液面 336），压板开对岸闸门。
const MOLD_STEP_POS := Vector2(1500, 288)
const MOLD_STEP_W := 64.0
const MOLD_DECK_POS := Vector2(1564, 256)
const MOLD_DECK_SIZE := Vector2(160, 64)
const PLATE_FEET := Vector2(1608, 256)
const MOLD_DOOR_POS := Vector2(1760, 256)
## 浇铸坑齿轮：两道八角台跨过 CastPit，最后一步落进 Boss 房。
const GEARS: Array = [
	["GearA", Vector2(2020, 304)],
	["GearB", Vector2(2064, 288)],
]
## 上层钩锁支路：FloorB 正上方。从地面起跳点距锚点 192px（≤250），
## 落台在锚点下方 96px（≤110）、横向 0px —— 标准钩锁降落。
const HOOK_MOLD_POS := Vector2(1152, 80)
const CATWALK_POS := Vector2(1080, 176)
const CATWALK_W := 192.0
const STELE_KEY_POS := Vector2(1128, 176)
const REWARD_POS := Vector2(1216, 128)

const NEST_ENTRY_X := 176.0
const NEST_LADLE_X := 800.0
const NEST_BOSS_X := 2096.0
const STELE_MOLD_POS := Vector2(1264, 320)
const STELE_FOUNDER_POS := Vector2(1880, 320)
const EXIT_X := 3424.0
## Boss 位：铸钟人。场景由 bosses-b 交付，缺失时 boss() 返回 null（不报错）。
const BOSS_NAME := "BellFounder"
const BOSS_KIND := "bell_founder"
const BOSS_POS := Vector2(2800, 320)
const ARENA_LEFT := 2160.0
const ARENA_RIGHT := 3440.0

## [name, kind, pos, overrides]
const ENEMIES: Array = [
	["Ghost1", "ghost", Vector2(600, 200), {}],
	["Spitter1", "spitter", Vector2(960, 320), {}],
	["Scrapper1", "scrapper", Vector2(1160, 320), {"patrol_range": 40.0}],
	["Ghost2", "ghost", Vector2(1540, 180), {}],
	["Spitter2", "spitter", Vector2(1808, 320), {}],
	["GearShield1", "gear_shield", Vector2(2360, 320), {}],
	["Scrapper2", "scrapper", Vector2(2460, 320), {"patrol_range": 24.0}],
	["FlyingDemon1", "flying_demon", Vector2(2680, 200), {"patrol_range": 72.0}],
]
## [key, feet] —— forge 白名单内的历史件：炉膛件、机械残骸、铸工遗物。
const PROPS: Array = [
	["beam", Vector2(256, 320)],
	["rubble_dry_b", Vector2(368, 320)],
	["metal_panel", Vector2(816, 320)],
	["pipe_valve", Vector2(1056, 320)],
	["rubble_dry_c", Vector2(1296, 320)],
	["broken_machine", Vector2(1816, 320)],
	["girder_l", Vector2(1936, 320)],
	["bones", Vector2(2144, 320)],
	["fire_vent", Vector2(2320, 320)],
	["girder_r", Vector2(2600, 320)],
	["plate", Vector2(3168, 320)],
	["column", Vector2(3264, 320)],
]
## 壁炬（炉口砖膛）：板底贴台面。
const TORCHES: Array = [96.0, 880.0, 1336.0, 1968.0, 2528.0, 3376.0]
const WAYMARKS: Array = [[Vector2(336, 320), "吊包"], [Vector2(2500, 320), "浇铸"]]


func level_id() -> String:
	return "level07b"


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
	return -224


func theme() -> String:
	return "forge"


func motes() -> String:
	return "embers"


func build(host: Node2D) -> void:
	_build_terrain(host)
	_build_mechanics(host)
	_build_props(host)
	_build_enemies(host)
	_build_decor(host)
	var exit := exit_door(host, EXIT_X, ChapterText.exit_label_of(level_id()),
			ChapterText.exit_captions_of(level_id()), "level07b_done",
			GameContext.next_level_id(level_id()))
	if ResourceLoader.exists("res://scenes/enemies/BellFounder.tscn"):
		exit.requires_flag = "founder_dead"
		exit.locked_prompt = "钟还没浇完。铸钟人挡着路。"
	_build_boss(host)
	finish(host)


func _build_terrain(host: Node2D) -> void:
	for f in FLOORS:
		floor_strip(host, String(f[0]), float(f[1]), float(f[2]), SKIN, bool(f[3]), bool(f[4]))
	for p in PITS:
		toxin_pit(host, String(p[0]), float(p[1]), float(p[2]), 32.0, PIT_SKIN, MOLTEN_TINT)
	# 钟模台：台面浮在模坑上，两级 32px 台阶接地面；模台占满模坑上方。
	step(host, "MoldStep", MOLD_STEP_POS, MOLD_STEP_W, "basalt_float")
	platform(host, "MoldDeck", MOLD_DECK_POS, MOLD_DECK_SIZE, "basalt", true, true)
	# 上层支路台面：FloorB 正上方，只有钩锁上得来。
	step(host, "MoldCatwalk", CATWALK_POS, CATWALK_W, FLOAT_SKIN)
	enclose(host, SKIN, CEILING_Y)


func _build_mechanics(host: Node2D) -> void:
	lift(host, "LiftA", LIFT_A_POS, LIFT_TRAVEL, LIFT_PERIOD_A, LIFT_WIDTH, 0.0, LIFT_CHAIN_TOP)
	lift(host, "LiftB", LIFT_B_POS, LIFT_TRAVEL, LIFT_PERIOD_B, LIFT_WIDTH, 0.5, LIFT_CHAIN_TOP)
	plate_door(host, "MoldGate", PLATE_FEET, MOLD_DOOR_POS)
	for g in GEARS:
		gear(host, String(g[0]), g[1], 16.0)
	hook(host, "HookMold", HOOK_MOLD_POS)
	for w in WAYMARKS:
		waymark(host, w[0], String(w[1]))


func _build_props(host: Node2D) -> void:
	nest(host, "EmberNestEntry", NEST_ENTRY_X)
	nest(host, "EmberNestLadle", NEST_LADLE_X)
	nest(host, "EmberNestCast", NEST_BOSS_X)
	_stele(host, "SteleMold", STELE_MOLD_POS)
	_stele(host, "SteleFounder", STELE_FOUNDER_POS)
	_stele(host, "SteleKey", STELE_KEY_POS)
	pickup(host, "CoreReward", REWARD_POS, &"kiln_core")


func _build_enemies(host: Node2D) -> void:
	for e in ENEMIES:
		enemy(host, String(e[0]), String(e[1]), e[2], e[3] if e.size() > 3 else {})


func _build_decor(host: Node2D) -> void:
	for key in PROPS:
		var tint := RUBBLE_TINT
		if String(key[0]) in ["girder_l", "girder_r", "broken_machine"]:
			tint = GIRDER_TINT
		elif String(key[0]) == "pipe_valve":
			tint = PIPE_TINT
		prop(host, String(key[0]), key[1], 1.0, tint)
	for x in TORCHES:
		torch(host, x, FLOOR_Y, TORCH_TINT)
	# 顶架垂下的旧吊索 / 挂渣的缆：挂在顶板下沿（顶板 -192..-160）。
	for x in [1184.0, 2192.0]:
		hanging(host, "chain", Vector2(x, CEILING_Y + 32.0), CHAIN_TINT)
	for x in [1408.0, 3008.0]:
		hanging(host, "vine", Vector2(x, CEILING_Y + 32.0), VINE_TINT)


## Boss 位：统一入口。场景缺失时完全不搭竞技场；交付后自动出现，
## 并补上契约 §4.1 要求的两个可读场地机关（铸钟厅：两侧浇铸口火柱）。
func _build_boss(host: Node2D) -> void:
	var b := boss(host, BOSS_NAME, BOSS_KIND, BOSS_POS, ARENA_LEFT, ARENA_RIGHT)
	if b == null:
		return
	var arena := boss_arena(host, BOSS_NAME)
	if arena == null:
		return
	var pillar_w: Node2D = arena.make_hazard(BossArena.HazardKind.FIRE_PILLAR, Vector2(2420, 320),
			{"name": "CastPillarWest", "telegraph": 0.55, "active": 0.3, "damage": 1})
	arena.register_hazard(&"cast_pillar_west", pillar_w)
	var pillar_e: Node2D = arena.make_hazard(BossArena.HazardKind.FIRE_PILLAR, Vector2(3180, 320),
			{"name": "CastPillarEast", "telegraph": 0.55, "active": 0.3, "damage": 1})
	arena.register_hazard(&"cast_pillar_east", pillar_e)
