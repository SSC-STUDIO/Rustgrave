extends ChapterLayout
## 锈墓・陆 — 圣殿地窖：中庭的账本末页被人撕走，暗门通到地窖。地窖里有人在唱，没有声音。
##
## 结构（地面 y=320；室内，教堂石板 skin=nave；单跳 ≤32px 高、≤72px 跨）：
##   ① 前厅 0–1200       暗门入口、出生、余烬巢、路牌「地窖」、石像鬼与尖窗；
##                       骸骨从土里起身教「先看土再走」，喷吐者守前厅东端。
##   ② 骨室 1200–2600    唱诗壳机关：链吊台升到唱诗台（224），台面压板开地窖闸门；
##                       顶上垂着烛泪藤条（烛雨），骨柱与祭坛是骨室的轮廓；
##                       钩锁支路：唱诗楼座（碑文「地窖纪事 · 末页」+ 武器奖励位，主线够不到）。
##   ③ 唱诗堂 2600–3680  末页碑文后的唱诗堂：Boss 前余烬巢、无声唱诗班竞技场（600px 平地）
##                       → 出口「工坊暗门」→ level05。
##
## 主线（allow_hook=false）从出生点可达出口、三个余烬巢与压板；钩锁只开支路。

const EAST_LIMIT := 3680
const CAMERA_TOP := -176
const CEILING_Y := -112.0
const ENTRY_SPAWN := Vector2(96, 300)

## 圣殿石板压成冷紫（同 level04）；浮台略亮，和地面拉开。
const STONE_TONE := Color(0.9, 0.88, 1.0)
const FLOAT_TONE := Color(0.94, 0.92, 1.0)
## 壁炬墙板压冷一点融进地窖石墙；藤条压成烛泪的黄白（地窖顶上的蜡烛烧了两百年）。
const TORCH_TINT := Color(0.82, 0.84, 1.0)
const WAX_TINT := Color(0.95, 0.87, 0.66, 0.9)

## 地面段 [name, x0, x1, cap_left, cap_right]：一条连续地面，机关与支路都在它上方。
const FLOORS: Array = [
	["FloorAnte", 0.0, 1200.0, false, true],
	["FloorBone", 1200.0, 2600.0, true, true],
	["FloorChoir", 2600.0, 3680.0, true, false],
]
## 悬空踏台 [name, pos(左上), width]（16px 厚，nave_float）
const STEPS: Array = [
	["ChoirLoft", Vector2(1568, 224), 160.0],
	["LedgerGallery", Vector2(2240, 136), 128.0],
]
## 唱诗台吊台：从地面上一层（296）把骑士送到唱诗台（224）；两段都在同一块台面上换乘。
const LIFTS: Array = [
	["ChoirLift", Vector2(1520, 296), Vector2(0.0, -72.0), 6.0, 48.0, 0.0],
]

## 唱诗壳机关：压板装在唱诗台面上（脚点 y=224），闸门立在地窖地面（门 16×64，底在 320）。
const PLATE_FEET := Vector2(1640, 224)
const GATE_DOOR_POS := Vector2(2100, 256)

## 三个余烬巢：前厅 / 骨室东头 / Boss 门前（间距 ≈1200px，死亡回程不重走整关）。
const NEST_ANTE_X := 176.0
const NEST_BONE_X := 1460.0
const NEST_CHOIR_X := 2860.0

## 碑文：主线「唱诗」讲被割了名字的唱诗班，主线「伊尔」讲她把自己封进剑；
## 支路「末页」是账本最后那页 —— 本章的核心发现，只有钩锁能读到。
const STELE_CHOIR_POS := Vector2(1240, 320)
const STELE_YIR_POS := Vector2(2700, 320)
const STELE_LEDGER_POS := Vector2(2270, 136)

## 钩锁支路：锚点悬在骨室上方，落在唱诗楼座（落台在锚点下方 88px）。
const HOOK_POS := Vector2(2304, 48)
## 支路奖励位：契约 §3.2 的 reward 位（kind ∈ weapon/character/equipment）。
## ChapterLayout.reward() 在本分支尚未落地，先用同源的 EquipmentPickup 场景直接挂。
## 奖励位是武器（铁斩刃）；WeaponRoster 落地后只需把 REWARD_KIND 改成 "weapon"、
## REWARD_REF 换成 roster 的武器 id，拾取逻辑与位置都不用动。
## Fill 底边在节点 +7px，所以 y = 台面 - 7（rest 在台面上，不做悬空奖励）。
const REWARD_SCENE := "res://scenes/interactables/EquipmentPickup.tscn"
const REWARD_POS := Vector2(2330, 129)
const REWARD_KIND := "equipment"
const REWARD_REF := "iron_blade"

## Boss：无声唱诗班（场景由 bosses-a 交付；缺失时 ChapterLayout.boss() 跳过，不阻塞）。
## 竞技场 600px 连续平地（2900–3500），Boss 在中间；门前巢在 2860（距场地 40px）。
const ARENA_LEFT := 2900.0
const ARENA_RIGHT := 3500.0
const BOSS_POS := Vector2(3200, 320)
const EXIT_X := 3592.0

const WAYMARKS: Array = [
	[Vector2(300, 320), "地窖"],
	[Vector2(2760, 320), "唱诗"],
]

## [name, kind, pos, overrides]：落地敌人给脚点，飞行/穿墙敌人给悬停中心。
## 巢位都在 nearby 敌人的 aggro/wake 圈外：前厅巢离骸骨 384px、喷吐者 644px；
## 骨室巢离骸骨 180px（>150 唤醒）；Boss 前巢离齿盾卫 344px（>300 射程）。
const ENEMIES: Array = [
	["Skeleton1", "skeleton", Vector2(560, 320), {}],
	["Spitter1", "spitter", Vector2(820, 320), {}],
	["Ghost1", "ghost", Vector2(980, 236), {}],
	["Skeleton2", "skeleton", Vector2(1280, 320), {}],
	["Ghost2", "ghost", Vector2(2050, 236), {}],
	["Skeleton3", "skeleton", Vector2(2380, 320), {}],
	["GearShield1", "gear_shield", Vector2(2500, 320), {"patrol_range": 16.0}],
]

## 壁炬：前厅 3 盏、骨室 3 盏、唱诗堂 3 盏。位置躲开尖窗/祭坛/石柱墙板（同层墙板
## 叠在一起会把中景家具读成黑块），照不到的家具带另有 WARM_FILLS 的暖光补。
const TORCHES: Array = [352.0, 820.0, 1100.0, 1500.0, 1650.0, 2450.0, 2680.0, 3200.0, 3480.0]
## 暖烛光补 [name, x, y, radius, energy]：视觉 QA Phase A 指出本关中景（1700/2050/3100
## 一带的祭坛、石柱、骷髅柱）被 cathedral grade 压成黑剪影（平均亮度 0.088–0.107）。
## 只加光、不加碰撞：三盏宽半径 ADD 底光 + 一排贴着家具带的烛光暖池，把整章中景从
## 黑里抬起来（不改全局 cathedral grade；室内 MIX 填充只会把画布乘暗，这里不用）。
const WARM_COLOR := Color(1.0, 0.72, 0.42)
const WARM_FILLS: Array = [
	["WarmWashAnte", 400.0, 180.0, 520.0, 1.3],
	["WarmWashBone", 1100.0, 180.0, 500.0, 1.0],
	["WarmWashWest", 1900.0, 180.0, 540.0, 1.2],
	["WarmWashGate", 2700.0, 180.0, 500.0, 1.1],
	["WarmWashChoir", 3300.0, 180.0, 440.0, 1.1],
	["WarmAnte", 900.0, 250.0, 160.0, 0.95],
	["WarmBoneRoom", 1700.0, 250.0, 170.0, 1.15],
	["WarmGate", 2050.0, 250.0, 160.0, 1.1],
	["WarmSkull", 2320.0, 240.0, 150.0, 1.0],
	["WarmChoirHall", 3100.0, 240.0, 170.0, 1.15],
	["WarmBossColumn", 3260.0, 190.0, 140.0, 1.25],
	["WarmChoirAltar", 3420.0, 250.0, 150.0, 1.05],
]
## 接地装饰 [key, feet]：每件都写清「用途 + 叙事锚点」，只种 PropCatalog 里
## cathedral 白名单的键（prop_fit_test 会复查主题、族变体、整数缩放与贴地）。
const PROPS: Array = [
	# 中庭下来的暗门：玩家从 level04 的账本间走进地窖。
	["door_arch", Vector2(56, 320)],
	["balustrade", Vector2(420, 320)],
	["rubble_dry", Vector2(500, 320)],
	# 前厅的尖窗与守门石像鬼：地窖最初也是按圣殿修的。
	["window", Vector2(700, 320)],
	["gargoyle", Vector2(1000, 320)],
	# 骨室的骷髅柱：唱诗班把名字留在了柱子上（碑文「唱诗」就在柱脚旁）。
	["skull_column", Vector2(1240, 320)],
	# 骨室中段的祭坛：末页原本供在这里，现在只剩空台；台脚压一块石板当基座。
	["altar", Vector2(1800, 320)],
	["slab", Vector2(1800, 320)],
	["column", Vector2(2000, 320)],
	["rubble_dry_b", Vector2(2140, 320)],
	# 骨室东端的骷髅柱与碎石：唱诗楼座就悬在这根柱子上方。
	["skull_column", Vector2(2350, 320)],
	["rubble_dry_c", Vector2(2620, 320)],
	# 唱诗堂（Boss 房）：两端的石柱/石栏是临时地标，中间塌下来的石板是合唱席残座；
	# 全部纯装饰、无碰撞，不挡 Boss 走位（BossArena 落地后由它接管场地）。
	["column", Vector2(2950, 320)],
	["balustrade", Vector2(2920, 320)],
	["slab", Vector2(3050, 320)],
	# 尖窗与祭坛是 Boss 房的两个可读光源地标；祭坛台脚也有石板基座。
	["window", Vector2(3080, 320)],
	["altar", Vector2(3380, 320)],
	["slab", Vector2(3380, 320)],
	["balustrade", Vector2(3490, 320)],
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


## 支路奖励位：挂一件装备拾取（rest 在楼座台面上）。等 ChapterLayout.reward() 合入后
## 换成 reward(host, "RewardLedger", REWARD_POS, REWARD_KIND, REWARD_REF)。
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
				bool(f[3]), bool(f[4]), FLOOR_Y, STONE_TONE)
	for s in STEPS:
		step(host, String(s[0]), s[1], float(s[2]), "nave_float", FLOAT_TONE)
	for l in LIFTS:
		lift(host, String(l[0]), l[1], l[2], float(l[3]), float(l[4]), float(l[5]))
	enclose(host, "nave", CEILING_Y, -1.0, 0.0, STONE_TONE)


func _build_props(host: Node2D) -> void:
	nest(host, "EmberNestAnte", NEST_ANTE_X)
	nest(host, "EmberNestBone", NEST_BONE_X)
	nest(host, "EmberNestChoir", NEST_CHOIR_X)
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


## Boss 位：统一走 ChapterLayout.boss()。场景缺失时它返回 null 并跳过竞技场，
## 关卡照常可通；出口旗标先不挂 Boss 死亡条件，等 bosses-a 交付后由 Lead 决定
## 死亡旗标名再接上（避免现在就把出口锁死成软锁）。
func _build_boss(host: Node2D) -> void:
	boss(host, "SilentChoir", "silent_choir", BOSS_POS, ARENA_LEFT, ARENA_RIGHT)


func _build_decor(host: Node2D) -> void:
	# 先铺中景暖雾（背景板照不到世界灯），再点壁炬与烛光暖池。
	_build_warm_veil(host)
	for x in TORCHES:
		torch(host, x, FLOOR_Y, TORCH_TINT)
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
