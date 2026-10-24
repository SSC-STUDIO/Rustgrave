extends ChapterLayout
## 锈墓・陆 — 圣殿地窖：中庭的账本末页被人撕走，暗门通到地窖。地窖里有人在唱，没有声音。
##
## 三间暗室、临时烛桥与固定下层回收路；蓝图见 docs/level-redesign/level04b.md。

const EAST_LIMIT := 4000
const CAMERA_TOP := -176
const CEILING_Y := -112.0
const ENTRY_SPAWN := Vector2(96, 300)
const CHOIR_GATE := preload("res://scripts/levels/chapters/level04b_choir_gate.gd")

## 圣殿石板压成冷紫（同 level04）；浮台略亮，和地面拉开。
const STONE_TONE := Color(0.9, 0.88, 1.0)
const FLOAT_TONE := Color(0.94, 0.92, 1.0)
## 壁炬墙板压冷一点融进地窖石墙；藤条压成烛泪的黄白（地窖顶上的蜡烛烧了两百年）。
const TORCH_TINT := Color(0.82, 0.84, 1.0)
const WAX_TINT := Color(0.95, 0.87, 0.66, 0.9)

## 地面段 [name, x0, x1, top_y]：错层暗室由固定下层路回收烛桥失误。
const FLOORS: Array = [
	["FloorAnte", 0.0, 416.0, 320.0],
	["AnteRecovery", 416.0, 928.0, 352.0],
	["AnteRise", 928.0, 1024.0, 320.0],
	["FloorBone", 1024.0, 1472.0, 320.0],
	["BoneRecovery", 1472.0, 1856.0, 352.0],
	["BoneStairA", 1856.0, 1920.0, 320.0],
	["BoneStairB", 1920.0, 1984.0, 288.0],
	["BoneStairC", 1984.0, 2080.0, 256.0],
	["FloorVault", 2080.0, 2432.0, 320.0],
	["VaultRecovery", 2432.0, 2752.0, 352.0],
	["VaultStairA", 2752.0, 2816.0, 320.0],
	["VaultStairB", 2816.0, 2880.0, 288.0],
	["VaultStairC", 2880.0, 3024.0, 256.0],
	["FloorChoir", 3024.0, 4000.0, 320.0],
]
## 悬空踏台 [name, pos(左上), width]（16px 厚，nave_float）
const STEPS: Array = [
	["TeachLanding", Vector2(544, 304), 80.0],
	["ChoirLoft", Vector2(976, 208), 144.0],
	["ReliquaryLintel", Vector2(1424, 224), 80.0],
	["BoneEntry", Vector2(1504, 288), 64.0],
	["BonePerch", Vector2(1744, 224), 96.0],
	["LedgerGallery", Vector2(2240, 136), 128.0],
	["ReturnEnd", Vector2(2192, 224), 96.0],
	["ReturnB", Vector2(2320, 224), 96.0],
	["ReturnC", Vector2(2448, 224), 96.0],
	["ReturnD", Vector2(2576, 224), 96.0],
	["ReturnLaunch", Vector2(2736, 256), 80.0],
	["ArenaSideWest", Vector2(3264, 288), 80.0],
	["ArenaSideEast", Vector2(3696, 288), 80.0],
]
## 临时烛桥 [name, pos(左上), width, candle_feet]；烛台一律放在永久支撑上。
const CANDLE_STEPS: Array = [
	["CandleTeach", Vector2(448, 304), 80.0, Vector2(384, 320)],
	["CandleAnteB", Vector2(688, 272), 80.0, Vector2(600, 304)],
	["CandleAnteC", Vector2(832, 240), 80.0, Vector2(600, 304)],
	["CandleBone", Vector2(1600, 256), 80.0, Vector2(1536, 288)],
	["CandleBoneEast", Vector2(1872, 224), 48.0, Vector2(1808, 224)],
	["CandleVaultA", Vector2(2464, 288), 80.0, Vector2(2384, 320)],
	["CandleVaultB", Vector2(2608, 288), 80.0, Vector2(2384, 320)],
	["CandleArenaWest", Vector2(3416, 256), 64.0, Vector2(3304, 288)],
	["CandleArenaEast", Vector2(3584, 256), 64.0, Vector2(3736, 288)],
]
const FLAMES: Array = [["FlameTeach", 1328.0, 0.0], ["ChoirFlameWest", 3384.0, 0.25], ["ChoirFlameEast", 3656.0, 0.65]]

## 唱诗壳机关：压板装在固定唱诗台面（208），闸门底在地面320。
const PLATE_FEET := Vector2(1008, 208)
const GATE_DOOR_POS := Vector2(1456, 256)

## 四个余烬巢：前厅 / 骨室 / 地窖 / Boss 门前，相邻992px。
const NEST_ANTE_X := 176.0
const NEST_BONE_X := 1168.0
const NEST_VAULT_X := 2160.0
const NEST_CHOIR_X := 3152.0

## 碑文：主线「唱诗」讲被割了名字的唱诗班，主线「伊尔」讲她把自己封进剑；
## 支路「末页」是账本最后那页 —— 本章的核心发现，只有钩锁能读到。
const STELE_CHOIR_POS := Vector2(1240, 320)
const STELE_YIR_POS := Vector2(2840, 288)
const STELE_LEDGER_POS := Vector2(2270, 136)

## 钩锁支路：锚点悬在骨室上方，落在唱诗楼座（落台在锚点下方 88px）。
const HOOK_POS := Vector2(2304, 48)
## 支路奖励位：契约 §3.2 的 reward 位（kind ∈ weapon/character/equipment）。
## 保留原 EquipmentPickup 类型和铁斩刃标识，避免改变既有存档拾取路径。
## Fill 底边在节点 +7px，所以 y = 台面 - 7（rest 在台面上，不做悬空奖励）。
const REWARD_SCENE := "res://scenes/interactables/EquipmentPickup.tscn"
const REWARD_POS := Vector2(2330, 129)
const REWARD_KIND := "equipment"
const REWARD_REF := "iron_blade"

## Boss：608px连续回收地面、固定侧龛和短时烛桥；门前巢距入口64px。
const ARENA_LEFT := 3216.0
const ARENA_RIGHT := 3824.0
const BOSS_POS := Vector2(3520, 320)
const EXIT_X := 3920.0

const WAYMARKS: Array = [
	[Vector2(300, 320), "地窖"],
	[Vector2(3056, 320), "唱诗"],
]

## [name, kind, pos, overrides]：落地敌人给脚点，飞行/穿墙敌人给悬停中心。
## 巢与首遇等候台都在敌人的 aggro/wake 圈外；可选楼座幽魂独立守奖励。
const ENEMIES: Array = [
	["Skeleton1", "skeleton", Vector2(720, 352), {"wake_range": 96.0}],
	["Spitter1", "spitter", Vector2(944, 320), {"aggro_range": 160.0}],
	["Ghost1", "ghost", Vector2(900, 296), {"wake_range": 160.0}],
	["Skeleton2", "skeleton", Vector2(1648, 352), {"variant": &"exploder_skeleton", "wake_range": 128.0}],
	["Ghost2", "ghost", Vector2(1784, 296), {"wake_range": 160.0}],
	["GearShield1", "gear_shield", Vector2(1904, 320), {"variant": &"heavy_guard", "patrol_range": 8.0, "aggro_range": 160.0}],
	["Skeleton3", "skeleton", Vector2(2576, 352), {"variant": &"exploder_skeleton", "wake_range": 128.0}],
	["Spitter2", "spitter", Vector2(2944, 256), {"aggro_range": 160.0}],
	["GhostLedger", "ghost", Vector2(2280, 96), {"wake_range": 96.0}],
]

## 壁炬：前厅 3 盏、骨室 3 盏、唱诗堂 3 盏。位置躲开尖窗/祭坛/石柱墙板（同层墙板
## 叠在一起会把中景家具读成黑块），照不到的家具带另有 WARM_FILLS 的暖光补。
const TORCHES: Array = [Vector2(352, 320), Vector2(1100, 320), Vector2(1400, 320),
	Vector2(2040, 256), Vector2(2304, 320), Vector2(2800, 320), Vector2(3088, 320),
	Vector2(3520, 320), Vector2(3860, 320)]
## 暖烛光补 [name, x, y, radius, energy]：视觉 QA Phase A 指出本关中景（1700/2050/3100
## 一带的祭坛、石柱、骷髅柱）被 cathedral grade 压成黑剪影（平均亮度 0.088–0.107）。
## 小范围 ADD 底光与烛台暖池点出固定落脚，暗室之间保留冷暗过渡。
const WARM_COLOR := Color(1.0, 0.72, 0.42)
const WARM_FILLS: Array = [
	["WarmWashAnte", 400.0, 240.0, 300.0, 0.7],
	["WarmWashBone", 1650.0, 240.0, 320.0, 0.7],
	["WarmWashChoir", 3520.0, 240.0, 340.0, 0.75],
	["WarmTeach", 384.0, 280.0, 128.0, 0.95],
	["WarmAnte", 600.0, 264.0, 144.0, 1.1],
	["WarmBoneNest", 1168.0, 250.0, 130.0, 1.1],
	["WarmGate", 1440.0, 280.0, 144.0, 1.1],
	["WarmBoneRoom", 1808.0, 190.0, 140.0, 1.1],
	["WarmVaultNest", 2160.0, 250.0, 150.0, 1.1],
	["WarmVault", 2384.0, 280.0, 144.0, 1.1],
	["WarmChoirHall", 3152.0, 250.0, 150.0, 1.1],
	["WarmBossColumn", 3310.0, 250.0, 144.0, 1.1],
	["WarmChoirAltar", 3740.0, 250.0, 144.0, 1.1],
]
## 接地装饰 [key, feet]：每件都写清「用途 + 叙事锚点」，只种 PropCatalog 里
## cathedral 白名单的键（prop_fit_test 会复查主题、族变体、整数缩放与贴地）。
const PROPS: Array = [
	# 中庭下来的暗门：玩家从 level04 的账本间走进地窖。
	["door_arch", Vector2(56, 320)],
	["balustrade", Vector2(420, 352)],
	["rubble_dry", Vector2(500, 352)],
	# 前厅的尖窗与守门石像鬼：地窖最初也是按圣殿修的。
	["window", Vector2(700, 352)],
	["gargoyle", Vector2(1000, 320)],
	# 骨室的骷髅柱：唱诗班把名字留在了柱子上（碑文「唱诗」就在柱脚旁）。
	["skull_column", Vector2(1240, 320)],
	# 骨室中段的祭坛：末页原本供在这里，现在只剩空台；台脚压一块石板当基座。
	["altar", Vector2(1800, 352)],
	["slab", Vector2(1800, 352)],
	["column", Vector2(2000, 256)],
	["rubble_dry_b", Vector2(2140, 320)],
	# 骨室东端的骷髅柱与碎石：唱诗楼座就悬在这根柱子上方。
	["skull_column", Vector2(2350, 320)],
	["rubble_dry_c", Vector2(2620, 352)],
	# 唱诗堂（Boss 房）：两端的石柱/石栏是临时地标，中间塌下来的石板是合唱席残座；
	# 全部纯装饰、无碰撞，不挡 Boss 走位（BossArena 落地后由它接管场地）。
	["column", Vector2(3256, 320)],
	["balustrade", Vector2(3272, 288)],
	["slab", Vector2(3420, 320)],
	# 尖窗与祭坛是 Boss 房的两个可读光源地标；祭坛台脚也有石板基座。
	["window", Vector2(3480, 320)],
	["altar", Vector2(3760, 288)],
	["slab", Vector2(3760, 288)],
	["balustrade", Vector2(3816, 320)],
]
## 顶板下挂着的烛泪：唱诗班点过的蜡烛烧了两百年，蜡沿着顶石垂下来（藤条压成蜡色）。
const VINES: Array = [500.0, 1200.0, 1700.0, 2100.0, 2500.0, 2900.0, 3300.0]


func level_id() -> String:
	return "level04b"


func title() -> String:
	return ChapterText.title_of(level_id())


func wake_line() -> String:
	return ChapterText.wake_of(level_id())


## 碑文文本只从 ChapterText 取；位置常量留在这里（几何归关卡，文本归注册表）。
func _stele(host: Node2D, node_name: String, pos: Vector2) -> void:
	var entry := ChapterText.stele_of(level_id(), node_name)
	stele(host, node_name, pos, String(entry.get("title", "")), String(entry.get("text", "")))


## 支路奖励位：保留原名、类型与目录标识，rest在楼座台面上。
func _reward(host: Node2D) -> Node:
	if not ResourceLoader.exists(REWARD_SCENE):
		return null
	var scene := load(REWARD_SCENE) as PackedScene
	if scene == null:
		return null
	var pick := scene.instantiate()
	if pick == null:
		return null
	pick.name = "RewardLedger"
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
	return "cathedral"


## 地窖里的烛尘：唱诗班不在了，烛还在烧（室内光/尘层次）。
func motes() -> String:
	return "candle"


## 圣殿有顶：天只走薄雾/晴，地窖里看不到天，全章用固定冷紫气氛。
func weather_recipe() -> Dictionary:
	return {
		"allowed": [WorldClock.Weather.HAZE, WorldClock.Weather.CLEAR],
		"hold": Vector2(320.0, 520.0),
		"intensity": Vector2(0.4, 0.8),
	}


func build(host: Node2D) -> void:
	_build_terrain(host)
	_build_props(host)
	_build_branch(host)
	_build_enemies(host)
	_build_boss(host)
	_build_decor(host)
	var exit := exit_door(host, EXIT_X, ChapterText.exit_label_of(level_id()),
			ChapterText.exit_captions_of(level_id()), "level04b_done",
			GameContext.next_level_id(level_id()))
	if ResourceLoader.exists("res://scenes/enemies/SilentChoir.tscn"):
		exit.requires_flag = "choir_dead"
		exit.locked_prompt = "唱诗班的合声还没停。"
	finish(host)


func _build_terrain(host: Node2D) -> void:
	for f in FLOORS:
		floor_strip(host, String(f[0]), float(f[1]), float(f[2]), "nave",
				float(f[1]) > 0.0, float(f[2]) < EAST_LIMIT, float(f[3]), STONE_TONE)
	for s in STEPS:
		step(host, String(s[0]), s[1], float(s[2]), "nave_float", FLOAT_TONE)
	for c in CANDLE_STEPS:
		candle_bridge(host, String(c[0]), c[1], float(c[2]), c[3],
				{"lit_time": 6.0, "warn_time": 1.2}, "nave_float", FLOAT_TONE)
	enclose(host, "nave", CEILING_Y, -1.0, 0.0, STONE_TONE)


func _build_props(host: Node2D) -> void:
	nest(host, "EmberNestAnte", NEST_ANTE_X)
	nest(host, "EmberNestBone", NEST_BONE_X)
	nest(host, "EmberNestVault", NEST_VAULT_X)
	nest(host, "EmberNestChoir", NEST_CHOIR_X)
	for flame in FLAMES:
		cyclic(host, String(flame[0]), Vector2(float(flame[1]), FLOOR_Y), "flame",
				{"reach": 48.0, "rest_time": 3.0, "telegraph_time": 0.9,
				"active_time": 0.55, "phase": float(flame[2])})
	# 唱诗壳机关：踩住唱诗台的压板，地窖闸门打开（骨室通唱诗堂的门）。
	plate_door(host, "ReliquaryGate", PLATE_FEET, GATE_DOOR_POS)
	_stele(host, "SteleChoir", STELE_CHOIR_POS)
	_stele(host, "SteleYir", STELE_YIR_POS)
	for w in WAYMARKS:
		waymark(host, w[0], String(w[1]))


## 钩锁支路：锚点 → 唱诗楼座。主线（allow_hook=false）够不到，只有钩锁能读末页。
func _build_branch(host: Node2D) -> void:
	hook(host, "HookLedger", HOOK_POS)
	_stele(host, "SteleLedger", STELE_LEDGER_POS)
	_reward(host)


func _build_enemies(host: Node2D) -> void:
	for e in ENEMIES:
		enemy(host, String(e[0]), String(e[1]), e[2], e[3])


## 保留原Boss与BossArena；章节入场边界避免它在巢前移动和提前唤醒。
func _build_boss(host: Node2D) -> void:
	var choir := boss(host, "SilentChoir", "silent_choir", BOSS_POS, ARENA_LEFT, ARENA_RIGHT)
	if choir == null:
		return
	choir.set_physics_process(false)
	var gate := CHOIR_GATE.new()
	gate.name = "ChoirWakeGate"
	gate.boss_ref = choir
	gate.arena_left = ARENA_LEFT
	gate.arena_right = ARENA_RIGHT
	group(host, "Props").add_child(gate)


func _build_decor(host: Node2D) -> void:
	# 先铺中景暖雾（背景板照不到世界灯），再点壁炬与烛光暖池。
	_build_warm_veil(host)
	for feet in TORCHES:
		torch(host, feet.x, feet.y, TORCH_TINT)
	# 暖光补：宽半径 ADD 底光抬环境，再用贴家具带的烛光暖池点出陈设轮廓。
	for spec in WARM_FILLS:
		_warm_fill(host, String(spec[0]), Vector2(float(spec[1]), float(spec[2])),
				float(spec[3]), float(spec[4]))
	for item in PROPS:
		prop(host, String(item[0]), item[1])
	# 顶板底边在 CEILING_Y + 32；烛泪从这条线上挂下来。
	var ceiling_bottom := CEILING_Y + 32.0
	for x in VINES:
		hanging(host, "vine", Vector2(x, ceiling_bottom), WAX_TINT)


## 中景暖雾：cathedral 的背景板在 ParallaxBackdrop（CanvasLayer −10），世界里的 2D 灯
## 照不到它——所以中景家具（祭坛/石柱/骷髅柱）永远是黑剪影。这里在 world 画布最底层
## （z=−8）加一层极淡的暖色纱：只盖背景板，不盖角色/道具（它们 z≥−3），等效于
## 「本关更暖的雾/环境色」，不改全局 cathedral grade。这是氛围面纱，不是场景细节。
func _build_warm_veil(host: Node2D) -> void:
	var veil := ColorRect.new()
	veil.name = "WarmVeil"
	veil.color = Color(0.52, 0.33, 0.20, 0.16)
	veil.position = Vector2(-64, CEILING_Y - 96.0)
	veil.size = Vector2(float(east_limit()) + 128.0, 464.0 - CEILING_Y + 96.0)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.z_index = -8
	group(host, "Props").add_child(veil)


## 场景暖光（WorldLight follow=authored + ADD）：参数口径与 level01 的
## AmbientLighting 一致——authored_radius 是像素半径，base_energy 是基础亮度，
## 时钟不改它。只补中景家具带的光，不加碰撞、不挡玩法。
func _warm_fill(host: Node2D, light_name: String, pos: Vector2, radius: float,
		energy: float) -> WorldLight:
	var light := WorldLight.new()
	light.name = light_name
	light.position = pos
	light.color = WARM_COLOR
	light.follow = &"authored"
	light.authored_radius = radius
	light.flicker = false
	light.lit = true
	light.set_base_energy(energy)
	decor_layer(host).add_child(light)
	# 氛围灯不为这点光算遮挡（和 AmbientLighting 一个口径）。
	light.shadow_enabled = false
	return light
