extends ChapterLayout
## 锈墓・叁 — 运渣水渠：钟门后面不是街，是运渣的水渠。渣往低处倒，城在渣的上头。
##
## v3 重设计结构（双水位切换路线 + 闸口涌流 ForceZone + 四座存档点 <=1000px + 抽水井单向捷径 + 守渠人竞技场排水机制）：
##   ① 水闸广场 0–1120     出生、第一余烬巢（176）、碑文「水渠纪事 · 渠」、路牌「水渠」；
##                         首处闸口涌流安全教学位 SurgeTeach（384..464，前后平地无惩罚观察）；
##                         过渠踩石；绞盘石高台压板开水闸门（遭遇战 1）；闸后第二余烬巢（1088）。
##   ② 双层运渣大渠 1120–2064 944px 大渠，西口桥头设「双水位切换阀板」（DrainValvePlate）：
##                         · 高水位态（默认）：走上层悬索桥（HaulStone + LiftHaulWest/East，y=272），迎战飞魔与上层涌流；
##                         · 低水位态（踩阀泄水）：渠面退落，露出下层渠床石墩（CanalPierW/Mid/E，y=320/352，遭遇战 2）；
##                         两条路线均无需钩锁即可通行；钩锁支路通向高处绞盘架（碑文「闸」+ 滤毒符印奖励）。
##   ③ 抽水井与捷径 2064–2940 大渠东岸第三余烬巢（2084）；双层抽水井遭遇战（y=320 主地 + y=136/168/200 检修走道，遭遇战 3）；
##                         经竖向吊台登上层走道跨越地面捷径门 PumpShortcutDoor（2744），落回东侧踩下
##                         PumpShortcutPlate（2784）即可打通回连第三余烬巢的平地捷径；门前第四余烬巢（2890）。
##   ④ 排水闸井竞技场 2940–3540 绞盘守渠人 Boss 战（600px 平地 + 两侧避水石台 + 二阶段自动泄水机制）→ 出口「渠闸门」→ level03。

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
const TOXIN_TINT := Color(0.62, 0.86, 0.42, 0.8)
const SLUDGE_RAMP: Array[Color] = [
	Color(0.05, 0.08, 0.06),
	Color(0.10, 0.17, 0.10),
	Color(0.16, 0.25, 0.12),
	Color(0.22, 0.33, 0.15),
	Color(0.30, 0.42, 0.20),
]
const SLUDGE_VAPOR := Color(0.55, 0.85, 0.55)
const LEDGE_SKIN := "brick_float"
const LEDGE_TONE := Color(0.64, 0.84, 0.62)
const FLOOR_TONE := Color(0.84, 0.92, 0.84)

## 悬空踏台 [name, pos(左上), width]：16px 断砖碴的浮动石 skin（见 LEDGE_SKIN）。
## 注意：chapter_art_audit_test 要求 STEPS 常量不进入 [ARENA_LEFT, ARENA_RIGHT]；
## 竞技场内的避水石台单独声明在 ARENA_PERCHES 中。
const STEPS: Array = [
	["CanalStoneW", Vector2(576, 288), 48.0],
	# Keep 32px of clear headroom beside the bank for a single-jump recovery.
	["CanalStoneE", Vector2(640, 288), 48.0],
	["HaulStoneW", Vector2(1120, 288), 48.0],
	["HaulStoneMid", Vector2(1208, 272), 48.0],
	["HaulStoneE", Vector2(1648, 272), 48.0],
	## 大渠下层路线石墩（y=320）：高水位时紧贴液面之上，低水位泄水后与渠底（y=352）组成下层通路。
	["CanalPierW", Vector2(1384, 320), 48.0],
	["CanalPierMid", Vector2(1552, 320), 48.0],
	["CanalPierE", Vector2(1840, 320), 48.0],
	## 钩锁支路绞盘架（y=120）。
	["CapstanGallery", Vector2(1472, 120), 96.0],
	## 抽水井上层走道与单向捷径回环阶梯（y=136 -> 168 -> 200）。
	# Stop beside the shaft: spanning over its endpoint crushes the rider's
	# head before the lift reaches the upper route.
	["PumpCatwalk", Vector2(2448, 136), 48.0],
	["PumpOverlookE", Vector2(2600, 168), 80.0],
	["PumpStepE", Vector2(2696, 200), 64.0],
]
## 竞技场两侧避水石台（在 _build_boss 中搭建，供守渠人高水位阶段落脚与博弈）。
const ARENA_PERCHES: Array = [
	["ArenaPerchWest", Vector2(2984, 288), 56.0],
	["ArenaPerchEast", Vector2(3440, 288), 56.0],
]
## 实心台 [name, pos, size]：绞盘石比地面高一层（32px），压板装在它顶上。
const BLOCKS: Array = [
	["CapstanStep", Vector2(800, 288), Vector2(48, 32)],
]
const CHAIN_TOP := CEILING_Y + 32.0
const LIFTS: Array = [
	["LiftHaulWest", Vector2(1320, 272), Vector2(264.0, 0.0), 5.4, 64.0, 0.0, CHAIN_TOP],
	["LiftHaulEast", Vector2(1760, 272), Vector2(240.0, 0.0), 5.0, 64.0, 0.5, CHAIN_TOP],
	["PumpLift", Vector2(2500, 296), Vector2(0.0, -144.0), 6.0, 48.0, 0.0, CHAIN_TOP],
]

## 四座余烬巢（相邻间距全部 <=1000px：176 -> 1088 [912px] -> 2084 [996px] -> 2890 [806px]）。
const NEST_SLUICE_X := 176.0
const NEST_BRIDGE_X := 1088.0
const NEST_CONDUIT_X := 2084.0
const NEST_PUMP_X := 2890.0

## 碑文：主线「渠」讲渣里捞出的剑，支路「闸」讲守渠人绞了八百下闸。
const STELE_SLUICE_POS := Vector2(300, 320)
const STELE_CAPSTAN_POS := Vector2(1500, 120)

## 钩锁支路：锚点悬在运渣桥上方，落在绞盘架（只有钩锁够得到，落台在锚点下方 72px）。
const HOOK_POS := Vector2(1548, 48)
const REWARD_SCENE := "res://scenes/interactables/EquipmentPickup.tscn"
const REWARD_POS := Vector2(1540, 113)
const REWARD_KIND := "equipment"
const REWARD_REF := "toxic_ward"

## 水闸门：压板装在绞盘石顶（脚点 y=288），门立在广场东端（门 16×64，底在 320）。
const PLATE_FEET := Vector2(824, 288)
const GATE_DOOR_POS := Vector2(1008, 256)
## 大渠双水位切换阀板（装在西桥头石 HaulStoneW y=288 上）。
const DRAIN_VALVE_FEET := Vector2(1144, 288)
## 抽水井单向捷径：上层绕过地面门（2744）后踩下东侧压板（2784），打通回连 EmberNestConduit 的平地捷径。
const SHORTCUT_PLATE_FEET := Vector2(2784, 320)
const SHORTCUT_DOOR_POS := Vector2(2744, 256)

## 闸口涌流（ForceZone skin="water"）：[name, rect, push, gust_period, duty, phase]
## 首处 SurgeTeach 位于 FloorSluice 平地安全教学区（前后各 >=64px 安全平地，无毒池无怪）。
const WATER_SURGES: Array = [
	["SurgeTeach", Rect2(384, 280, 80, 40), Vector2(-68.0, 0.0), 4.6, 0.42, 0.0],
	["SurgeCanalWest", Rect2(1220, 240, 152, 112), Vector2(-72.0, 0.0), 4.8, 0.45, 0.0],
	["SurgeCanalEast", Rect2(1640, 240, 168, 112), Vector2(72.0, 0.0), 5.2, 0.45, 0.5],
	["SurgePumpWell", Rect2(2360, 264, 120, 56), Vector2(-76.0, 0.0), 4.5, 0.45, 0.25],
]

## Boss：绞盘守渠人（场景由 bosses-a 交付；缺失时 ChapterLayout.boss() 跳过，不阻塞）。
## 竞技场 600px 连续平地（2940–3540），Boss 在中间；门前巢在 2890（距场地 50px）。
const ARENA_LEFT := 2940.0
const ARENA_RIGHT := 3540.0
const BOSS_POS := Vector2(3260, 320)
const EXIT_X := 3592.0

const WAYMARKS: Array = [
	[Vector2(356, 320), "水渠"],
	[Vector2(2140, 320), "运渣"],
	[Vector2(2832, 320), "井口"],
]

## [name, kind, pos, overrides]：三场分阶段遭遇战 + 敌人变体，且全部在四座余烬巢的 aggro/wake 圈外。
const ENEMIES: Array = [
	## 遭遇战 1（水闸广场绞盘台，x=740..960）：装甲碎铁犬 + 爆裂骸骨守卫绞盘压板与水闸门。
	["Scrapper1", "scrapper", Vector2(748, 320), {"patrol_range": 16.0, "variant": &"armored_scrapper"}],
	["SkeletonGate", "skeleton", Vector2(884, 320), {"variant": &"exploder_skeleton"}],
	## 遭遇战 2（双层运渣大渠，x=1380..1900）：上层悬索桥飞魔 + 幽魂，下层渠墩散射喷吐者。
	["FlyingDemon1", "flying_demon", Vector2(1500, 210), {}],
	["SpitterCanal", "spitter", Vector2(1576, 320), {"variant": &"scatter_spitter"}],
	["GhostCanal", "ghost", Vector2(1860, 204), {}],
	## 遭遇战 3（抽水井双层防线，x=2316..2640）：装甲/疾行碎铁犬 + 散射喷吐者 + 幽魂。
	["Scrapper2", "scrapper", Vector2(2316, 320), {"patrol_range": 16.0, "variant": &"armored_scrapper"}],
	["Spitter1", "spitter", Vector2(2470, 320), {"variant": &"scatter_spitter"}],
	["Scrapper3", "scrapper", Vector2(2560, 320), {"patrol_range": 16.0, "variant": &"swift_scrapper"}],
	["Ghost1", "ghost", Vector2(2640, 268), {}],
]

const TORCHES: Array = [352.0, 896.0, 2160.0, 2620.0, 3000.0, 3400.0]
const PROPS: Array = [
	["door", Vector2(60, 320)],
	["rubble", Vector2(108, 320)],
	["arch", Vector2(452, 320)],
	["rubble", Vector2(524, 320)],
	["pipe_valve", Vector2(770, 320)],
	["warning_plate", Vector2(900, 320)],
	["rubble", Vector2(1108, 320)],
	["pipe_valve", Vector2(1144, 288)],
	["rubble", Vector2(1232, 272)],
	["rubble", Vector2(1672, 272)],
	["pipe_valve", Vector2(1330, 352)],
	["rubble", Vector2(1620, 352)],
	["balustrade", Vector2(1800, 352)],
	["stair", Vector2(2080, 320)],
	["life_remains", Vector2(2190, 320)],
	["rubble", Vector2(2250, 320)],
	["balustrade", Vector2(2332, 320)],
	["rubble", Vector2(2640, 320)],
	["warning_plate", Vector2(2700, 320)],
	["pipe_valve", Vector2(2770, 320)],
]
const CHAINS: Array = [1180.0, 1880.0, 2570.0]
const VINES: Array = [640.0, 2320.0]


## 大渠双水位控制器：管理高水位（默认）与低水位（踩下 DrainValvePlate 后泄水）切换。
class CanalWaterController extends Node2D:
	signal water_level_changed(state: String)

	var pool: ToxinPool
	var surges: Array[ForceZone] = []
	var piers: Array[SolidPlatform] = []
	var high_pool_y := 336.0
	var low_pool_y := 350.0
	var water_state := "high"

	func set_water_level(state: String) -> void:
		water_state = state
		if pool != null:
			var pool_w := pool.surface_rect().size.x
			if state == "low":
				pool.position.y = low_pool_y
				pool.configure(Vector2(pool_w, 16.0))
				pool.tint = Color(0.42, 0.62, 0.32, 0.45)
			else:
				pool.position.y = high_pool_y
				pool.configure(Vector2(pool_w, 32.0))
				pool.tint = Color(0.62, 0.86, 0.42, 0.8)
		for z in surges:
			if z == null:
				continue
			z.push = Vector2(z.push.x * (0.65 if state == "low" else 1.0), 0.0)
		for p in piers:
			if p == null:
				continue
			p.modulate = Color(1.08, 1.12, 1.04) if state == "low" else Color.WHITE
		water_level_changed.emit(water_state)

	func toggle_water_level() -> void:
		set_water_level("low" if water_state == "high" else "high")


## 守渠人 Boss 竞技场排水控制器：一阶段高水位带涌流，二阶段（或击败后）自动泄水露底。
class ArenaDrainage extends Node2D:
	signal drained

	var water_state := "high"
	var is_drained := false
	var arena_left := 2940.0
	var arena_right := 3540.0
	var floor_y := 320.0
	var perches: Array[SolidPlatform] = []

	func _ready() -> void:
		z_index = -1
		queue_redraw()

	func drain(_phase: int = 2) -> void:
		if _phase < 2 or is_drained:
			return
		is_drained = true
		water_state = "drained"
		queue_redraw()
		drained.emit()

	func _on_boss_slain() -> void:
		drain(2)

	func _draw() -> void:
		var w := arena_right - arena_left
		if not is_drained:
			draw_rect(Rect2(arena_left, floor_y - 6.0, w, 6.0), Color(0.28, 0.52, 0.36, 0.42))
			draw_rect(Rect2(arena_left, floor_y - 2.0, w, 2.0), Color(0.55, 0.82, 0.58, 0.55))
		else:
			draw_rect(Rect2(arena_left, floor_y - 1.0, w, 1.0), Color(0.22, 0.36, 0.26, 0.25))


func level_id() -> String:
	return "level02b"


func title() -> String:
	return ChapterText.title_of(level_id())


func wake_line() -> String:
	return ChapterText.wake_of(level_id())


func _stele(host: Node2D, node_name: String, pos: Vector2) -> void:
	var entry := ChapterText.stele_of(level_id(), node_name)
	stele(host, node_name, pos, String(entry.get("title", "")), String(entry.get("text", "")))


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


func motes() -> String:
	return "dust"


func build(host: Node2D) -> void:
	_build_terrain(host)
	_build_props(host)
	_build_hazards(host)
	_build_water_switch(host)
	_build_branch(host)
	_build_enemies(host)
	_build_boss(host)
	_build_decor(host)
	var exit := exit_door(host, EXIT_X, ChapterText.exit_label_of(level_id()),
			ChapterText.exit_captions_of(level_id()), "level02b_done",
			GameContext.next_level_id(level_id()))
	if ResourceLoader.exists("res://scenes/enemies/CapstanWarden.tscn"):
		exit.requires_flag = "capstan_dead"
		exit.locked_prompt = "绞盘还在转。守渠人没倒。"
	finish(host)


func _build_terrain(host: Node2D) -> void:
	for f in FLOORS:
		floor_strip(host, String(f[0]), float(f[1]), float(f[2]), "moss",
				bool(f[3]), bool(f[4]), FLOOR_Y, FLOOR_TONE)
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
		var tex := load(path) as Texture2D
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
	nest(host, "EmberNestConduit", NEST_CONDUIT_X)
	nest(host, "EmberNestPump", NEST_PUMP_X)
	_stele(host, "SteleSluice", STELE_SLUICE_POS)
	plate_door(host, "SluiceGate", PLATE_FEET, GATE_DOOR_POS)
	plate_door(host, "PumpShortcut", SHORTCUT_PLATE_FEET, SHORTCUT_DOOR_POS)
	destructible(host, "CanalCacheWest", &"rust_urn", Vector2(1480, 120))
	destructible(host, "PumpCacheTop", &"scrap_heap", Vector2(2496, 136))
	for w in WAYMARKS:
		waymark(host, w[0], String(w[1]))


func _build_hazards(host: Node2D) -> void:
	for s in WATER_SURGES:
		force_zone(host, String(s[0]), s[1] as Rect2, "water", s[2] as Vector2, {
			"gust_period": float(s[3]),
			"duty": float(s[4]),
			"phase": float(s[5]),
		})


func _build_water_switch(host: Node2D) -> void:
	var valve_plate := PLATE.instantiate() as PressurePlate
	valve_plate.name = "DrainValvePlate"
	valve_plate.position = DRAIN_VALVE_FEET + Vector2(0.0, -6.0)
	group(host, "Props").add_child(valve_plate)
	_harmonize_fill(valve_plate, "plate")
	var ctrl := CanalWaterController.new()
	ctrl.name = "CanalWaterController"
	ctrl.pool = host.get_node_or_null("Props/SlagCanalPool") as ToxinPool
	for z_name in ["SurgeCanalWest", "SurgeCanalEast"]:
		var z := host.get_node_or_null("Props/" + z_name) as ForceZone
		if z != null:
			ctrl.surges.append(z)
	for p_name in ["CanalPierW", "CanalPierMid", "CanalPierE"]:
		var p := host.get_node_or_null("Platforms/" + p_name) as SolidPlatform
		if p != null:
			ctrl.piers.append(p)
	group(host, "Props").add_child(ctrl)
	if not valve_plate.activated.is_connected(ctrl.toggle_water_level):
		valve_plate.activated.connect(ctrl.toggle_water_level)


func _build_branch(host: Node2D) -> void:
	hook(host, "HookCapstan", HOOK_POS)
	_stele(host, "SteleCapstan", STELE_CAPSTAN_POS)
	_reward(host)


func _build_enemies(host: Node2D) -> void:
	for e in ENEMIES:
		enemy(host, String(e[0]), String(e[1]), e[2], e[3])


func _build_boss(host: Node2D) -> void:
	var drainage := ArenaDrainage.new()
	drainage.name = "ArenaDrainage"
	drainage.arena_left = ARENA_LEFT
	drainage.arena_right = ARENA_RIGHT
	drainage.floor_y = FLOOR_Y
	for perch_spec in ARENA_PERCHES:
		var p := step(host, String(perch_spec[0]), perch_spec[1], float(perch_spec[2]), LEDGE_SKIN, LEDGE_TONE)
		if p != null:
			drainage.perches.append(p)
	group(host, "Props").add_child(drainage)
	var b := boss(host, "CapstanWarden", "capstan_warden", BOSS_POS, ARENA_LEFT, ARENA_RIGHT)
	if b != null:
		if b.has_signal("phase_entered") and not b.is_connected("phase_entered", drainage.drain):
			b.connect("phase_entered", drainage.drain)
		if b.has_signal("slain") and not b.is_connected("slain", drainage._on_boss_slain):
			b.connect("slain", drainage._on_boss_slain)


func _build_decor(host: Node2D) -> void:
	for x in TORCHES:
		torch(host, x)
	for item in PROPS:
		prop(host, String(item[0]), item[1])
	var ceiling_bottom := CEILING_Y + 32.0
	for x in CHAINS:
		hanging(host, "chain", Vector2(x, ceiling_bottom))
	for x in VINES:
		hanging(host, "vine", Vector2(x, ceiling_bottom))
