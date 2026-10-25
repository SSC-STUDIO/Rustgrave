extends ChapterLayout
## 锈墓・叁 — 运渣水渠：钟门后面不是街，是运渣的水渠。渣往低处倒，城在渣的上头。
##
## 结构（地面 y=320；室内，青苔砖 skin=moss；单跳 ≤32px 高、≤72px 跨）：
##   ① 水闸广场 0–1120   出生、余烬巢、碑文「水渠纪事 · 渠」、路牌「水渠」；
##                       毒水渠横在路中（坑底 352，两岸一跳 32px 爬回），两块过渠踩石；
##                       绞盘石高出地面 32，压板装在石顶 —— 踩住压板，水闸门开（教学）。
##   ② 运渣桥 1120–2064   944px 大渠（渣水，掉下去能沿坑岸跳回）；两座横渡吊台 + 桥石；
##                       钩锁支路：绞盘架（碑文「水渠纪事 · 闸」+ 装备奖励位，主线够不到）。
##   ③ 抽水井 2064–3680   抽水井前厅：链式抽水吊台 + 可选检修走道、Boss 前余烬巢、
##                       绞盘守渠人 Boss 竞技场（600px 平地）→ 出口「渠闸门」→ level03。
##
## 主线（allow_hook=false）从出生点可达出口、三个余烬巢与压板；钩锁只开支路。

const EAST_LIMIT := 3680
const CAMERA_TOP := -112
const CEILING_Y := -48.0
const ENTRY_SPAWN := Vector2(96, 300)

## 地面段 [name, x0, x1, cap_left, cap_right]
const FLOORS: Array = [
	["FloorSluice", 0.0, 560.0, false, true],
	["FloorGate", 720.0, 1120.0, true, true],
	["FloorWell", 2064.0, 3680.0, true, false],
]
## 毒水渠 [name, x0, x1]：坑底 352、液面 336..368；两岸地面 320，掉进去一跳（32px）爬回。
const PITS: Array = [
	["SluiceCanal", 560.0, 720.0],
	["SlagCanal", 1120.0, 2064.0],
]
## 坑底的渣水：视觉 QA Phase A 指出 944px 的渠面被乘成「荧光绿带」（P0）。这一关的池子
## 单独压暗：tint 降饱和降亮度（alpha<1 让浮沫也退下去），再给池子挂一条 5 段暗绿
## sludge_ramp，让渠面从坑底近黑绿过渡到岸边暗苔绿，而不是一整条亮带。
## 全局 TOXIN_TINT 常量没动（别的章在用），这里只改本关实例。
const TOXIN_TINT := Color(0.62, 0.86, 0.42, 0.8)
const SLUDGE_RAMP: Array[Color] = [
	Color(0.05, 0.08, 0.06),
	Color(0.10, 0.17, 0.10),
	Color(0.16, 0.25, 0.12),
	Color(0.22, 0.33, 0.15),
	Color(0.30, 0.42, 0.20),
]
const SLUDGE_VAPOR := Color(0.55, 0.85, 0.55)
## 浮动桥石/吊台改用 brick_float（16px 断砖碴，带断口侧面）；moss_float 只有亮草檐、
## 没有侧面/底暗面，半空里读成一块贴片（视觉 QA P0）。压成苔绿断石，和地窟砖同一族。
const LEDGE_SKIN := "brick_float"
const LEDGE_TONE := Color(0.64, 0.84, 0.62)
## 地面苔砖压暗一档：渠岸的柠檬绿草檐不能和池面连成一条亮带。
const FLOOR_TONE := Color(0.84, 0.92, 0.84)

## 悬空踏台 [name, pos(左上), width]：16px 断砖碴的浮动石 skin（见 LEDGE_SKIN）。
const STEPS: Array = [
	["CanalStoneW", Vector2(576, 288), 48.0],
	["CanalStoneE", Vector2(656, 288), 48.0],
	["HaulStoneW", Vector2(1120, 288), 48.0],
	["HaulStoneMid", Vector2(1208, 272), 48.0],
	["HaulStoneE", Vector2(1648, 272), 48.0],
	["CapstanGallery", Vector2(1472, 120), 96.0],
	["PumpCatwalk", Vector2(2448, 136), 96.0],
]
## 实心台 [name, pos, size]：绞盘石比地面高一层（32px），压板装在它顶上。
const BLOCKS: Array = [
	["CapstanStep", Vector2(800, 288), Vector2(48, 32)],
]
## 吊台 [name, pos, travel, period, width, phase, chain_top_y]：
## 西/东两座横渡运渣桥；抽水井的竖吊台从地面上一层（296）升到检修走道（152）。
## chain_top_y = 顶板底边 → 吊台的吊索/链条真的从天花垂下来（原先链条整段隐藏，
## 半空的吊台只剩一块亮绿薄板）。
const CHAIN_TOP := CEILING_Y + 32.0
const LIFTS: Array = [
	["LiftHaulWest", Vector2(1320, 272), Vector2(264.0, 0.0), 5.4, 64.0, 0.0, CHAIN_TOP],
	["LiftHaulEast", Vector2(1760, 272), Vector2(240.0, 0.0), 5.0, 64.0, 0.5, CHAIN_TOP],
	["PumpLift", Vector2(2500, 296), Vector2(0.0, -144.0), 6.0, 48.0, 0.0, CHAIN_TOP],
]

## 三个余烬巢：起点 / 运渣桥前 / Boss 门前（间距 <1000px，死亡回程不重走整关）。
const NEST_SLUICE_X := 176.0
const NEST_BRIDGE_X := 1060.0
const NEST_PUMP_X := 2890.0

## 碑文：主线「渠」讲渣里捞出的剑，支路「闸」讲守渠人绞了八百下闸。
const STELE_SLUICE_POS := Vector2(300, 320)
const STELE_CAPSTAN_POS := Vector2(1500, 120)

## 钩锁支路：锚点悬在运渣桥上方，落在绞盘架（只有钩锁够得到，落台在锚点下方 72px）。
const HOOK_POS := Vector2(1548, 48)
## 支路奖励位：契约 §3.2 的 reward 位（kind ∈ weapon/character/equipment）。
## ChapterLayout.reward() 在本分支尚未落地，先用同源的 EquipmentPickup 场景直接挂；
## kind=equipment 走现有装备系统，roster 缺席也不会空转/软锁。奖励是滤毒符印——
## 这一章的水全是毒，支路把「怎么活得久一点」交到玩家手里。
## Fill 底边在节点 +7px，所以 y = 台面 - 7（rest 在台面上，不做悬空奖励）。
const REWARD_SCENE := "res://scenes/interactables/EquipmentPickup.tscn"
const REWARD_POS := Vector2(1540, 113)
const REWARD_KIND := "equipment"
const REWARD_REF := "toxic_ward"
## 水闸门：压板装在绞盘石顶（脚点 y=288），门立在广场东端（门 16×64，底在 320）。
const PLATE_FEET := Vector2(824, 288)
const GATE_DOOR_POS := Vector2(1008, 256)

## Boss：绞盘守渠人（场景由 bosses-a 交付；缺失时 ChapterLayout.boss() 跳过，不阻塞）。
## 竞技场 600px 连续平地（2940–3540），Boss 在中间；门前巢在 2890（距场地 50px）。
const ARENA_LEFT := 2940.0
const ARENA_RIGHT := 3540.0
const BOSS_POS := Vector2(3260, 320)
const EXIT_X := 3592.0

const WAYMARKS: Array = [
	[Vector2(356, 320), "水渠"],
	[Vector2(2140, 320), "运渣"],
	[Vector2(2810, 320), "井口"],
]

## [name, kind, pos, overrides]：落地敌人给脚点，飞行/穿墙敌人给悬停中心。
## 巢位都在 nearby 敌人的 aggro/wake 圈外：Scrapper1 的战圈收在 16px，喷吐者离
## Boss 前巢 420px（>380 射程），幽魂离巢 250px（>210 唤醒距离）。
const ENEMIES: Array = [
	["Scrapper1", "scrapper", Vector2(432, 320), {"patrol_range": 16.0}],
	["FlyingDemon1", "flying_demon", Vector2(1500, 210), {}],
	["Scrapper2", "scrapper", Vector2(2160, 320), {"patrol_range": 16.0}],
	["Scrapper3", "scrapper", Vector2(2340, 320), {"patrol_range": 16.0}],
	["Spitter1", "spitter", Vector2(2470, 320), {}],
	["Ghost1", "ghost", Vector2(2640, 268), {}],
]

## 壁炬：室内关的光点，压板 / 吊台 / 井口各有一盏（火在墙上，不占路面）。
const TORCHES: Array = [352.0, 896.0, 2160.0, 2620.0, 3000.0, 3400.0]
## 接地装饰 [key, feet]：每件都写清「用途 + 叙事锚点」，只种 PropCatalog 里
## undercroft 白名单的键（prop_fit_test 会复查主题、贴图族变体与整数缩放）。
## 视觉 QA Phase A：渠面曾是一条荧光绿直边带。下面三类压边件负责打断它：
##   · 渠口（两岸地面）：残阶 / 碎石，让水面直边有个「出口」；
##   · 桥石上：断管 / 落石，卡在横渡踏台上，也说明桥不是贴片；
##   · 渠底（feet=352，半沉在渣水里）：断管 / 落石 / 断石栏，只露一截在水面上。
const PROPS: Array = [
	# 钟门后的下行门洞：玩家从 level02 的钟门走进来。
	["door", Vector2(60, 320)],
	["rubble", Vector2(108, 320)],
	# 水闸广场的排水拱：渠水从这道拱里排出去，拱脚落在广场地面上。
	["arch", Vector2(452, 320)],
	["rubble", Vector2(524, 320)],
	# 水闸管件：绞盘石西侧的锈管，告诉玩家「这里在绞什么」。
	["pipe_valve", Vector2(770, 320)],
	# 毒水告示：立在渠西岸，读得懂的字只剩「毒」。
	["warning_plate", Vector2(900, 320)],
	# 大渠西口：塌下来的碎石压在渠口，水线不至于是凭空切断的一条亮边。
	["rubble", Vector2(1103, 320)],
	# 运渣桥：卡在横渡桥石上的断管与落石（桥石 48px 宽，件件站得下）。
	["pipe_valve", Vector2(1144, 288)],
	["rubble", Vector2(1232, 272)],
	["rubble", Vector2(1672, 272)],
	# 大渠底（床面 352，半沉）：断管、落石、一截断石栏——只露一尺在水面以上。
	["pipe_valve", Vector2(1330, 352)],
	["rubble", Vector2(1620, 352)],
	["balustrade", Vector2(1800, 352)],
	# 大渠东口：运渣工的残阶与骨渣（上一班人从这里下去）。
	["stair", Vector2(2080, 320)],
	["life_remains", Vector2(2190, 320)],
	["rubble", Vector2(2250, 320)],
	# 抽水井口两侧：石栏 + 抽水管件。
	["balustrade", Vector2(2332, 320)],
	["rubble", Vector2(2640, 320)],
	["warning_plate", Vector2(2700, 320)],
	["pipe_valve", Vector2(2770, 320)],
]
## 顶板下悬着的东西：断链（运渣吊具）和苔藤。
const CHAINS: Array = [1180.0, 1880.0, 2570.0]
const VINES: Array = [640.0, 2320.0]


func level_id() -> String:
	return "level02b"


func title() -> String:
	return ChapterText.title_of(level_id())


func wake_line() -> String:
	return ChapterText.wake_of(level_id())


## 碑文文本只从 ChapterText 取；位置常量留在这里（几何归关卡，文本归注册表）。
func _stele(host: Node2D, node_name: String, pos: Vector2) -> void:
	var entry := ChapterText.stele_of(level_id(), node_name)
	stele(host, node_name, pos, String(entry.get("title", "")), String(entry.get("text", "")))


## 支路奖励位：挂一件装备拾取（rest 在支路台面上）。等 ChapterLayout.reward() 合入后
## 换成 reward(host, "RewardCapstan", REWARD_POS, REWARD_KIND, REWARD_REF)。
func _reward(host: Node2D) -> Node:
	if not ResourceLoader.exists(REWARD_SCENE):
		return null
	var scene := load(REWARD_SCENE) as PackedScene
	if scene == null:
		return null
	var pick := scene.instantiate()
	if pick == null:
		return null
	pick.name = "RewardCapstan"
	pick.position = REWARD_POS
	pick.set("reward_kind", REWARD_KIND)
	pick.set("reward_ref", REWARD_REF)
	# 显示名从装备目录取，物品名不抄进关卡（数据层是唯一来源）。
	var item := EquipmentCatalog.for_id(StringName(REWARD_REF))
	pick.set("reward_name", item.display_name if item != null else "")
	group(host, "Pickups").add_child(pick)
	return pick


func entry_spawn() -> Vector2:
	return ENTRY_SPAWN


func east_limit() -> int:
	return EAST_LIMIT


func camera_top() -> int:
	return CAMERA_TOP


func theme() -> String:
	return "undercroft"


## 运渣渠里飘的是渣尘，不是墓园的落叶。
func motes() -> String:
	return "dust"


func build(host: Node2D) -> void:
	_build_terrain(host)
	_build_props(host)
	_build_branch(host)
	_build_enemies(host)
	_build_boss(host)
	_build_decor(host)
	var exit := exit_door(host, EXIT_X, ChapterText.exit_label_of(level_id()),
			ChapterText.exit_captions_of(level_id()), "level02b_done",
			GameContext.next_level_id(level_id()))
	# Boss 场景已交付才挂门禁；缺失时保持开放，绝不软锁。
	if ResourceLoader.exists("res://scenes/enemies/CapstanWarden.tscn"):
		exit.requires_flag = "capstan_dead"
		exit.locked_prompt = "绞盘还在转。守渠人没倒。"
	finish(host)


func _build_terrain(host: Node2D) -> void:
	for f in FLOORS:
		floor_strip(host, String(f[0]), float(f[1]), float(f[2]), "moss",
				bool(f[3]), bool(f[4]), FLOOR_Y, FLOOR_TONE)
	# 渠面单独压暗：tint + 5 段暗绿 sludge_ramp，944px 的渣渠不能是一条荧光带。
	for p in PITS:
		var pool := toxin_pit(host, String(p[0]), float(p[1]), float(p[2]), 32.0, "moss", TOXIN_TINT)
		if pool != null:
			pool.set_sludge_ramp(SLUDGE_RAMP, SLUDGE_VAPOR)
	for s in STEPS:
		step(host, String(s[0]), s[1], float(s[2]), LEDGE_SKIN, LEDGE_TONE)
	for b in BLOCKS:
		platform(host, String(b[0]), b[1], b[2], "moss", true, true, FLOOR_TONE)
	for l in LIFTS:
		var deck := lift(host, String(l[0]), l[1], l[2], float(l[3]), float(l[4]),
				float(l[5]), float(l[6]))
		_restyle_lift(deck, LEDGE_TONE)
	enclose(host, "moss", CEILING_Y, -1.0, 0.0, FLOOR_TONE)


## 吊台换皮：MovingPlatform 的默认视觉是 moss_float（亮草檐薄板），半空里读成贴片。
## 关掉它自带的木板 Sprite，按 16px 补一层和桥石同族的断砖碴（brick_float：左右收边 +
## 中段随机），调成苔绿断石；碰撞、吊索和可站立判定都不动（吊索由 chain_top_y 控制）。
const LIFT_CAP_LEFT := "res://assets/env/brick_float_left.png"
const LIFT_CAP_RIGHT := "res://assets/env/brick_float_right.png"
const LIFT_MIDS: Array[String] = [
	"res://assets/env/brick_float_mid_a.png",
	"res://assets/env/brick_float_mid_b.png",
	"res://assets/env/brick_float_mid_c.png",
]


func _restyle_lift(deck: Node2D, tone: Color) -> void:
	if deck == null:
		return
	var world := SolidPlatform.WORLD
	var width: float = maxf(float(deck.get("width")), world)
	for child in deck.get_children():
		if child is Sprite2D:
			(child as Sprite2D).visible = false
	var x := 0.0
	var index := 0
	while x < width - 0.01:
		var path := LIFT_MIDS[index % LIFT_MIDS.size()]
		if x <= 0.01:
			path = LIFT_CAP_LEFT
		elif x + world >= width - 0.01:
			path = LIFT_CAP_RIGHT
		var tex := DensityTextures.load_texture(path)
		if tex != null:
			var spr := Sprite2D.new()
			spr.texture = tex
			spr.centered = false
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			spr.position = Vector2(x, 0.0)
			spr.modulate = tone
			spr.z_index = -1
			deck.add_child(spr)
		x += world
		index += 1


func _build_props(host: Node2D) -> void:
	nest(host, "EmberNestSluice", NEST_SLUICE_X)
	nest(host, "EmberNestBridge", NEST_BRIDGE_X)
	nest(host, "EmberNestPump", NEST_PUMP_X)
	_stele(host, "SteleSluice", STELE_SLUICE_POS)
	plate_door(host, "SluiceGate", PLATE_FEET, GATE_DOOR_POS)
	for w in WAYMARKS:
		waymark(host, w[0], String(w[1]))
	# 可破坏道具（M3）：全部在支路台面/角落，主线不靠打碎任何东西通过。
	# 爆破罐连锁演示：抽水井检修走道（PumpCatwalk，顶面 y=136）上两只相距 34px
	# （< 44 引爆半径），打碎一只连锁引爆另一只。
	destructible(host, "BlastUrnCatwalkA", &"blast_urn", Vector2(2466, 136))
	destructible(host, "BlastUrnCatwalkB", &"blast_urn", Vector2(2500, 136))
	# 绞盘架支路（CapstanGallery，顶面 y=120，只有钩锁够得到）：碑文西侧一只锈罐，
	# 装备奖励位东侧一只余烬窖（掉 3 点余烬经验）。
	destructible(host, "RustUrnCapstan", &"rust_urn", Vector2(1480, 120))
	destructible(host, "EmberCacheCapstan", &"ember_cache", Vector2(1554, 120))


## 钩锁支路：锚点 → 绞盘架台面。主线（allow_hook=false）够不到，只有钩锁能读碑拿奖励。
func _build_branch(host: Node2D) -> void:
	hook(host, "HookCapstan", HOOK_POS)
	_stele(host, "SteleCapstan", STELE_CAPSTAN_POS)
	_reward(host)


func _build_enemies(host: Node2D) -> void:
	for e in ENEMIES:
		enemy(host, String(e[0]), String(e[1]), e[2], e[3])


## Boss 位：统一走 ChapterLayout.boss()。场景缺失时它返回 null 并跳过竞技场，
## 关卡照常可通；出口旗标先不挂 Boss 死亡条件，等 bosses-a 交付后由 Lead 决定
## 死亡旗标名再接上（避免现在就把出口锁死成软锁）。
func _build_boss(host: Node2D) -> void:
	boss(host, "CapstanWarden", "capstan_warden", BOSS_POS, ARENA_LEFT, ARENA_RIGHT)


func _build_decor(host: Node2D) -> void:
	for x in TORCHES:
		torch(host, x)
	for item in PROPS:
		prop(host, String(item[0]), item[1])
	# 顶板底边在 CEILING_Y + 32；链条/苔藤从这条线上挂下来。
	var ceiling_bottom := CEILING_Y + 32.0
	for x in CHAINS:
		hanging(host, "chain", Vector2(x, ceiling_bottom))
	for x in VINES:
		hanging(host, "vine", Vector2(x, ceiling_bottom))
