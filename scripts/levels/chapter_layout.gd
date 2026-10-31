class_name ChapterLayout
extends Node2D
## 章节关卡的铺设基类。每一关一个子类（scripts/levels/chapters/levelNN_layout.gd，
## 不要加 class_name），覆写元数据函数与 build(host)，用这里的助手把地形、机关、
## 敌人、装饰和背景放进 host 的 Platforms / Props / Enemies / Hooks / Pickups / Decor。
##
## 约定（LevelSanity 会检查）：
##   · 主地面顶 y = FLOOR_Y (320)；单跳台阶 ≤ 32px 高、≤ 72px 横跨；下落可更远
##   · 所有落地物脚下必须有台面；毒池躺在坑里；出口与每个余烬巢必须从出生点可达
##   · 位置常量写死在子类里；坐标是世界坐标（像素）
##
## 关卡元数据由函数提供（GDScript 常量不能被子类覆写）。

const FLOOR_Y := 320.0
const WORLD := 16.0

const PLATFORM := preload("res://scenes/world/Platform.tscn")
const NEST := preload("res://scenes/interactables/EmberNest.tscn")
const STELE := preload("res://scenes/interactables/LoreStele.tscn")
const TOXIN := preload("res://scenes/interactables/ToxinPool.tscn")
const PLATE := preload("res://scenes/interactables/PressurePlate.tscn")
const DOOR := preload("res://scenes/interactables/Door.tscn")
const GATE := preload("res://scenes/interactables/RustyGate.tscn")
const ANCHOR := preload("res://scenes/interactables/HookAnchor.tscn")
const PICKUP := preload("res://scenes/interactables/CorePickup.tscn")
const TORCH := preload("res://scenes/world/TorchLight.tscn")
const GEAR := preload("res://scenes/world/GearPlatform.tscn")
const DESTRUCTIBLE_PROP := preload("res://scenes/interactables/DestructibleProp.tscn")
const BREAKABLE_SLAB := preload("res://scenes/world/BreakableSlab.tscn")

## 敌人键 → 场景。缺失的场景会被跳过（并 push_warning），关卡照常搭建。
## 新 Boss 先在这里登记占位：章节 agent 可以提前写 `ChapterLayout.boss(..., "capstan_warden", ...)`，
## 场景还没做出来时 Boss + Arena 一起跳过，不会让关卡搭建失败（契约 §4.2）。
const ENEMY_SCENES := {
	"spitter": "res://scenes/enemies/SpitterEnemy.tscn",
	"scrapper": "res://scenes/enemies/ScrapperEnemy.tscn",
	"gear_shield": "res://scenes/enemies/GearShieldEnemy.tscn",
	"flying_demon": "res://scenes/enemies/FlyingDemonEnemy.tscn",
	"ghost": "res://scenes/enemies/GhostEnemy.tscn",
	"executioner": "res://scenes/enemies/ExecutionerBoss.tscn",
	"skeleton": "res://scenes/enemies/SkeletonEnemy.tscn",
	"fire_skull": "res://scenes/enemies/FireSkullEnemy.tscn",
	"nightmare_boss": "res://scenes/enemies/NightmareBoss.tscn",
	# --- 二期新增 Boss 的占位登记（场景由 bosses-a / bosses-b 交付） -----------------
	"capstan_warden": "res://scenes/enemies/CapstanWarden.tscn",
	"silent_choir": "res://scenes/enemies/SilentChoir.tscn",
	"hollow_bell": "res://scenes/enemies/HollowBell.tscn",
	"bell_founder": "res://scenes/enemies/BellFounder.tscn",
	"emberwind_herald": "res://scenes/enemies/EmberwindHerald.tscn",
	"furnace_mother": "res://scenes/enemies/FurnaceMotherBoss.tscn",
}

## Boss 竞技场容器（scripts/world/boss_arena.gd）。
const BOSS_ARENA := preload("res://scripts/world/boss_arena.gd")

## Prop sprites and the per-theme allowlist live in PropCatalog (prop_catalog.gd).
const DECOR := PropCatalog.DECOR
const THEME_PROPS := PropCatalog.THEME_PROPS
## torch() plants a brick hearth instead of a church wall plate here. The core hall
## (forge_core) keeps the gothic sconce: it is a castle hall, not a workshop.
const FURNACE_THEMES: Array[String] = ["industrial", "forge"]

const SIGN_TEX := "res://assets/env/normalized/props/waymark_sign.png"
const SIGN_PLANK := Rect2(0, 3, 35, 20)
const SIGN_FONT_SIZE := 12

var plate_door_pairs: Array = []


## ------------------------------------------------------------- metadata --

## 注册表里的 id（"level03"…）。
func level_id() -> String:
	return "level00"


func title() -> String:
	return "锈墓"


## 第一次进关的开场字幕（标题之后再来一句）。
func wake_line() -> String:
	return ""


## 从上一关掉/走进来的落点。
func entry_spawn() -> Vector2:
	return Vector2(96, 300)


## 没有存档、没有 pending spawn 时的落点。
func default_spawn() -> Vector2:
	return entry_spawn()


## 镜头右界（世界 x）。左界 0，下界 400。
func east_limit() -> int:
	return 1280


## 镜头上界（负数允许镜头抬到顶板以上）。
func camera_top() -> int:
	return -48


## ThemeBackdrop 主题：undercroft / forge / forge_core / cathedral / belltower / town /
## ramparts / industrial / graveyard。
func theme() -> String:
	return "undercroft"


func indoors() -> bool:
	return ThemeBackdrop.is_indoor_theme(theme())


## 这一关的飘浮微粒风味（ThemeMotes.FLAVORS 的 id；"" = 不加）。
func motes() -> String:
	return ""


## 第一次进关时设定的天时与天气（只对室外关生效，见 ChapterLevel）。{} = 沿用全局时钟。
## time：0..1（0.62 起是夜，见 WorldClock.phase_at）；weather：WorldClock.weather_id 的 id；
## hold：天气保持的秒数，免得进关十秒就换天。
func ambient() -> Dictionary:
	return {}


## 这一关的天气配方（见 WorldClock.set_weather_profile）。{} = 沿用全局阶段权重表。
##   allowed:   Array[int]               本章只会出现这些天气
##   weights:   Dictionary               {阶段 id: {天气 id: 权重}}，缺的阶段回落全局表
##   hold:      float | Vector2(min,max) 一次天气持续多久
##   intensity: float | Vector2(min,max) 强度区间
## 例：墓园夜雨 {"allowed": [4, 2], "intensity": Vector2(0.7, 1.0), "hold": 180.0}
func weather_recipe() -> Dictionary:
	return {}


## 关卡里的局部天气区域。每项：
##   {"name": "RampartGale", "rect": Rect2(1200, 0, 480, 384),
##    "weather": WorldClock.Weather.RAIN, "intensity": 1.0, "wind_scale": 1.4,
##    "indoor": true}      # indoor=true 时同时把玩家切进室内（炉口/天井）
## 不给 `weather` 就沿用当前基础天气，只改强度和风力。
func weather_regions() -> Array:
	return []


## 子类在这里铺关卡。
func build(_host: Node2D) -> void:
	pass


## --------------------------------------------------------------- groups --

func group(host: Node2D, group_name: String) -> Node2D:
	var node := host.get_node_or_null(group_name) as Node2D
	if node == null:
		node = Node2D.new()
		node.name = group_name
		host.add_child(node)
	return node


func decor_layer(host: Node2D) -> Node2D:
	var layer := host.get_node_or_null("Decor") as Node2D
	if layer == null:
		layer = Node2D.new()
		layer.name = "Decor"
		layer.z_index = -2
		host.add_child(layer)
	return layer


## -------------------------------------------------------------- terrain --

## 实心平台。pos = 左上角，size 以像素计（16 的倍数最好看）。
## skin: ground / floating / stone / moss / moss_float（"auto" 会把薄而宽的当悬浮台）。
func platform(host: Node2D, plat_name: String, pos: Vector2, sz: Vector2, skin: String = "moss",
		cap_left: bool = true, cap_right: bool = true, tone: Color = Color.WHITE) -> SolidPlatform:
	var plat: SolidPlatform = PLATFORM.instantiate()
	plat.name = plat_name
	plat.skin = skin
	plat.position = pos
	plat.size = sz
	plat.cap_left = cap_left
	plat.cap_right = cap_right
	plat.tone = tone
	group(host, "Platforms").add_child(plat)
	return plat


## 一段地面（80px 厚，顶在 FLOOR_Y）。
func floor_strip(host: Node2D, plat_name: String, x0: float, x1: float, skin: String = "moss",
		cap_left: bool = true, cap_right: bool = true, top_y: float = FLOOR_Y, tone: Color = Color.WHITE) -> SolidPlatform:
	return platform(host, plat_name, Vector2(x0, top_y), Vector2(x1 - x0, FLOOR_Y + 80.0 - top_y), skin, cap_left, cap_right, tone)


## 悬空踏台（16px 厚）。
func step(host: Node2D, plat_name: String, pos: Vector2, width: float, skin: String = "moss_float",
		tone: Color = Color.WHITE) -> SolidPlatform:
	return platform(host, plat_name, pos, Vector2(width, WORLD), skin, true, true, tone)


## 左右墙 + 顶板（顶板留 shaft_x..shaft_x+shaft_w 的竖井口；shaft_w <= 0 则封死）。
func enclose(host: Node2D, skin: String = "moss", ceiling_y: float = -32.0, shaft_x: float = -1.0,
		shaft_w: float = 0.0, tone: Color = Color.WHITE) -> void:
	var limit := float(east_limit())
	platform(host, "WallLeft", Vector2(-16, ceiling_y), Vector2(16, FLOOR_Y + 80.0 - ceiling_y), skin, false, false, tone)
	platform(host, "WallRight", Vector2(limit, ceiling_y), Vector2(16, FLOOR_Y + 80.0 - ceiling_y), skin, false, false, tone)
	if shaft_w <= 0.0 or shaft_x < 0.0:
		platform(host, "Ceiling", Vector2(0, ceiling_y), Vector2(limit, 32), skin, false, false, tone)
	else:
		platform(host, "CeilingWest", Vector2(0, ceiling_y), Vector2(shaft_x, 32), skin, false, false, tone)
		platform(host, "CeilingEast", Vector2(shaft_x + shaft_w, ceiling_y), Vector2(limit - shaft_x - shaft_w, 32), skin, false, false, tone)


## 只有左右墙、不封顶（室外关）。
func walls(host: Node2D, skin: String = "ground", top_y: float = -160.0) -> void:
	var limit := float(east_limit())
	platform(host, "WallLeft", Vector2(-16, top_y), Vector2(16, FLOOR_Y + 80.0 - top_y), skin, false, false)
	platform(host, "WallRight", Vector2(limit, top_y), Vector2(16, FLOOR_Y + 80.0 - top_y), skin, false, false)


## 链吊台：从 pos 出发，位移 travel，往返 period 秒。
func lift(host: Node2D, lift_name: String, pos: Vector2, travel: Vector2, period: float,
		width: float = 64.0, phase: float = 0.0, chain_top_y: float = 0.0) -> MovingPlatform:
	var m := MovingPlatform.new()
	m.name = lift_name
	m.position = pos
	m.travel = travel
	m.period = period
	m.width = width
	m.phase = phase
	m.chain_top_y = chain_top_y
	group(host, "Platforms").add_child(m)
	return m


## 八角石台（GearPlatform），中心 pos。
func gear(host: Node2D, gear_name: String, pos: Vector2, radius: float = 16.0) -> Node2D:
	var g := GEAR.instantiate() as Node2D
	g.name = gear_name
	g.position = pos
	g.set("radius", radius)
	g.set("family", skin_family())
	group(host, "Platforms").add_child(g)
	return g


## ---------------------------------------------------------------- props --

## 余烬巢（存档点）。feet_y = 台面 y；巢原点在台面上方 14px。
func nest(host: Node2D, nest_name: String, x: float, feet_y: float = FLOOR_Y) -> Node:
	var n := NEST.instantiate()
	n.name = nest_name
	n.position = Vector2(x, feet_y - 14.0)
	group(host, "Props").add_child(n)
	return n


## 碑文。原点在碑底：直接给台面 y。
func stele(host: Node2D, stele_name: String, pos: Vector2, lore_title: String, lore_text: String) -> Node:
	var s := STELE.instantiate()
	s.name = stele_name
	s.position = pos
	s.set("lore_title", lore_title)
	s.set("lore_text", lore_text)
	group(host, "Props").add_child(s)
	return s


## 毒池：pos = 液面左上角，size = 池面尺寸；坑底平台需另铺（顶 ≤ 池底+16）。
func toxin(host: Node2D, pool_name: String, pos: Vector2, size: Vector2, tint: Color = Color(1.0, 1.25, 0.55)) -> ToxinPool:
	var pool := TOXIN.instantiate() as ToxinPool
	pool.name = pool_name
	pool.position = pos
	pool.tint = tint
	group(host, "Props").add_child(pool)
	pool.configure(size)
	return pool


## 一个「毒水坑」：把 x0..x1 挖成 depth 深的坑（坑底铺台、液面覆盖）。
func toxin_pit(host: Node2D, pit_name: String, x0: float, x1: float, depth: float = 32.0,
		skin: String = "moss", tint: Color = Color(1.0, 1.25, 0.55)) -> ToxinPool:
	var bed_y := FLOOR_Y + depth
	platform(host, pit_name + "Bed", Vector2(x0, bed_y), Vector2(x1 - x0, FLOOR_Y + 80.0 - bed_y), skin, false, false)
	return toxin(host, pit_name + "Pool", Vector2(x0, bed_y - 16.0), Vector2(x1 - x0, 32.0), tint)


## 把交互物的纯色/教堂紫贴片换成当前主题的材质族变体。门与压板是共享场景，
## 贴图路径写死在 interactable 脚本里；一个工坊地面上的教堂紫门板读起来像另一关的
## 素材（docs/art-spec.md「每章身份色」「世界历史细节」）。只在当前主题确实有派生
## 副本时替换，贴图尺寸保持一致，所以碰撞/像素缩放都不变。
func _harmonize_fill(node: Node, key: String) -> void:
	var fill := node.get_node_or_null("Fill") as Sprite2D
	if fill == null or fill.texture == null or not DECOR.has(key):
		return
	var path: String = PropCatalog.path_for(key, theme())
	if path == String(DECOR[key]) or not ResourceLoader.exists(path):
		return
	var tex := DensityTextures.load_texture(path)
	if tex != null:
		fill.texture = tex


## 压板 + 闸门。plate_feet = 压板所在台面（x, y）；door_pos = 门左上角（门 16×64，底在 y+64）。
func plate_door(host: Node2D, pair_name: String, plate_feet: Vector2, door_pos: Vector2) -> Array:
	var plate := PLATE.instantiate()
	plate.name = pair_name + "Plate"
	plate.position = plate_feet + Vector2(0.0, -6.0)
	group(host, "Props").add_child(plate)
	_harmonize_fill(plate, "plate")
	var door := DOOR.instantiate()
	door.name = pair_name + "Door"
	door.position = door_pos
	group(host, "Props").add_child(door)
	_harmonize_fill(door, "door_arch")
	if not plate.activated.is_connected(door.open_door):
		plate.activated.connect(door.open_door)
	plate_door_pairs.append([plate, door])
	return [plate, door]


## 锈门（需要热锻）。pos = 左上角，底在 y+64。
func rusty_gate(host: Node2D, gate_name: String, pos: Vector2) -> Node:
	var g := GATE.instantiate()
	g.name = gate_name
	g.position = pos
	group(host, "Props").add_child(g)
	_harmonize_fill(g, "door_arch")
	return g


func hook(host: Node2D, hook_name: String, pos: Vector2) -> Node:
	var h := ANCHOR.instantiate()
	h.name = hook_name
	h.position = pos
	group(host, "Hooks").add_child(h)
	return h


## 锈核拾取：core_id = kiln_core / tether_core / ember_core。悬在台面上方 ≤64px 或钩点旁。
func pickup(host: Node2D, pickup_name: String, pos: Vector2, core_id: StringName) -> Node:
	var p := PICKUP.instantiate()
	p.name = pickup_name
	p.position = pos
	var core := AbilityCatalog.for_id(core_id)
	if core != null:
		p.set("core", core)
	group(host, "Pickups").add_child(p)
	return p


## 出口门。next_level_id 为空 = 本关是结局（字幕后回标题）。
## requires_flag：先点亮这个旗标（如 Boss 死亡）门才开。
func exit_door(host: Node2D, x: float, label: String, captions: PackedStringArray, flag_id: String,
		next_level_id: String = "", feet_y: float = FLOOR_Y, requires_flag: String = "",
		locked_prompt: String = "门还锁着") -> LevelExit:
	var e := LevelExit.new()
	e.name = "Exit"
	e.position = Vector2(x, feet_y)
	e.door_label = label
	e.captions = captions
	e.flag_id = flag_id
	e.requires_flag = requires_flag
	e.locked_prompt = locked_prompt
	if next_level_id != "" and GameContext.scene_for(next_level_id) != "":
		e.target_scene = GameContext.scene_for(next_level_id)
		e.spawn = ChapterLayout.entry_spawn_of(next_level_id)
	group(host, "Props").add_child(e)
	return e


## 下一关的落点（读它的 layout）。
static func entry_spawn_of(next_level_id: String) -> Vector2:
	var path: String = GameContext.STAGE_SCRIPTS.get(next_level_id, GameContext.LAYOUTS.get(next_level_id, ""))
	if path == "" or not ResourceLoader.exists(path):
		return Vector2(96, 300)
	var script := load(path) as GDScript
	if script == null:
		return Vector2(96, 300)
	var probe := script.new() as Node
	var spawn: Vector2 = probe.call("entry_spawn") if probe.has_method("entry_spawn") else Vector2(96, 300)
	probe.free()
	return spawn


## -------------------------------------------------------------- enemies --

## 敌人。pos：落地敌人给脚点（台面 y）；飞行/穿墙敌人给悬停中心。
func enemy(host: Node2D, enemy_name: String, kind: String, pos: Vector2, overrides: Dictionary = {}) -> Node2D:
	var path: String = ENEMY_SCENES.get(kind, "")
	if path == "" or not ResourceLoader.exists(path):
		push_warning("ChapterLayout: enemy kind '%s' unavailable, skipped (%s)" % [kind, enemy_name])
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var e := scene.instantiate() as Node2D
	e.name = enemy_name
	e.position = pos
	for key in overrides:
		e.set(key, overrides[key])
	group(host, "Enemies").add_child(e)
	return e


## 统一生成 Boss + 竞技场（契约 §4.1）。返回 Boss 节点（场景缺失时 null，不报错）；
## 竞技场挂在 host/Arenas/<boss_name>Arena，用 boss_arena() 或 boss_after 取。
##   1. Boss 走 ENEMY_SCENES，带 arena_left/right 覆盖（Boss 自己也要知道边界）；
##   2. BossArena 负责 clamp / 锁门 / 相机 limit / 机关注册 / 存档点校验 / 战后解锁；
##   3. 存档点校验延后一帧（余烬巢可能在本函数之后才铺），只 warning 不阻塞。
func boss(host: Node2D, boss_name: String, kind: String, pos: Vector2,
		arena_left: float, arena_right: float) -> Node2D:
	var b := enemy(host, boss_name, kind, pos, {"arena_left": arena_left, "arena_right": arena_right})
	if b == null:
		return null
	var arena = BOSS_ARENA.attach(host, boss_name + "Arena", b, arena_left, arena_right, pos.y)
	if arena != null:
		b.set_meta("boss_arena_name", String(arena.name))
		arena.call_deferred("validate_checkpoint")
	return b


## 取某场 Boss 的竞技场（host/Arenas/<boss_name>Arena）。
func boss_arena(host: Node2D, boss_name: String) -> Node:
	var folder := host.get_node_or_null("Arenas") as Node2D
	if folder == null:
		return null
	return folder.get_node_or_null(boss_name + "Arena")




## 关卡奖励位（契约 §3）：角色/武器/装备奖励。roster 不存在时 EquipmentPickup
## 自己回退为"一点余温"（回血 + 消耗），绝不空转也绝不死锁；奖励文案由 ChapterText 提供。
func reward(host: Node2D, node_name: String, feet: Vector2, kind: String, reward_id: String,
		display_name: String = "") -> EquipmentPickup:
	var pickup := EquipmentPickup.new()
	pickup.name = node_name
	pickup.reward_kind = kind
	pickup.reward_ref = reward_id
	pickup.reward_name = display_name
	pickup.position = feet
	var layer := group(host, "Props")
	layer.add_child(pickup)
	return pickup


## ------------------------------------------------------------- hazards --
## 机关工具箱（scripts/hazards/，规则见 docs/level_authoring.md §8）。位置约定与
## platform()/step() 一致；props 可覆盖机关脚本的任何导出属性。LevelSanity 会检查预警、
## 安全间隔、与巢/压板/出口的净空，以及塌陷台 / 传送带不得当休息点的支撑。

## 周期机关（蒸汽 / 喷火 / 渣喷 / 坠钟 / 冲击波）。pos = 喷口（坠钟 / 冲击波 = 落点地面中心）。
## 缺省参数取 CyclicHazard.preset(skin)，props 里给的覆盖它。
func cyclic(host: Node2D, node_name: String, pos: Vector2, skin: String,
		props: Dictionary = {}) -> CyclicHazard:
	var hazard := CyclicHazard.new()
	hazard.name = node_name
	hazard.skin = skin
	hazard.position = pos
	var merged := CyclicHazard.preset(skin)
	for key in props:
		merged[key] = props[key]
	for key in merged:
		hazard.set(key, merged[key])
	group(host, "Props").add_child(hazard)
	return hazard


## 塌陷台（16px 厚的悬空踏台，踩上去抖、抖完塌、隔一会儿长回来）。pos = 左上角。
func collapsing(host: Node2D, plat_name: String, pos: Vector2, width: float,
		skin: String = "moss_float", props: Dictionary = {},
		tone: Color = Color.WHITE) -> CollapsingPlatform:
	var plat := CollapsingPlatform.new()
	plat.name = plat_name
	plat.skin = skin
	plat.position = pos
	plat.size = Vector2(width, WORLD)
	plat.tone = tone
	for key in props:
		plat.set(key, props[key])
	group(host, "Platforms").add_child(plat)
	return plat


## 外力区（风道 / 涌流 / 泥沼 / 余烬风）。rect = 区域矩形（世界坐标），push：x 速度偏移、y 竖向加速度。
func force_zone(host: Node2D, node_name: String, rect: Rect2, skin: String, push: Vector2,
		props: Dictionary = {}) -> ForceZone:
	var zone := ForceZone.new()
	zone.name = node_name
	zone.skin = skin
	zone.size = rect.size
	zone.position = rect.position + rect.size * 0.5
	zone.push = push
	for key in props:
		zone.set(key, props[key])
	group(host, "Props").add_child(zone)
	return zone


## 传送带。pos = 左上角；height 16 = 悬空踏台，80 = 整段地面。speed 正 = 向右。
func conveyor(host: Node2D, plat_name: String, pos: Vector2, width: float, speed: float,
		skin: String = "iron_float", props: Dictionary = {}, height: float = WORLD,
		tone: Color = Color.WHITE) -> ConveyorBelt:
	var belt := ConveyorBelt.new()
	belt.name = plat_name
	belt.skin = skin
	belt.position = pos
	belt.size = Vector2(width, height)
	belt.speed = speed
	belt.tone = tone
	for key in props:
		belt.set(key, props[key])
	group(host, "Platforms").add_child(belt)
	return belt


## 摆锤。pivot = 吊点（顶端）；length 链长；props 可给 swing_deg / period / phase / skin / damage。
func pendulum(host: Node2D, node_name: String, pivot: Vector2, length: float,
		props: Dictionary = {}) -> PendulumHazard:
	var swing := PendulumHazard.new()
	swing.name = node_name
	swing.position = pivot
	swing.length = length
	for key in props:
		swing.set(key, props[key])
	group(host, "Props").add_child(swing)
	return swing


## 烛光桥（16px 厚悬空踏台，平时无碰撞半透明，靠近或挥砍 candle_pos 处的烛台后实心 lit_time 秒）。
## pos = 左上角；candle_pos = 烛台脚点（世界坐标）。
func candle_bridge(host: Node2D, plat_name: String, pos: Vector2, width: float,
		candle_pos: Vector2, props: Dictionary = {}, skin: String = "nave_float",
		tone: Color = Color.WHITE) -> CandleBridge:
	var bridge := CandleBridge.new()
	bridge.name = plat_name
	bridge.skin = skin
	bridge.position = pos
	bridge.size = Vector2(width, WORLD)
	bridge.candle_pos = candle_pos
	bridge.tone = tone
	for key in props:
		bridge.set(key, props[key])
	group(host, "Platforms").add_child(bridge)
	return bridge


## ---------------------------------------------------------------- decor --

## 壁炬（墙板 64×192 居中于 pos；y = 台面 - 96 时板底贴台面）。
## Outdoor themes refuse these plates — bg_wall_torch is a flat indoor slab.
## 可破坏道具：脚点放置，掉碎屑 + 小回血，destroyed 写世界状态。
## 只许放在支路/角落；主线必经路径不允许只靠打碎它通过。
func destructible(host: Node2D, node_name: String, prop_id: StringName,
		feet: Vector2) -> Node2D:
	var prop := DESTRUCTIBLE_PROP.instantiate() as Node2D
	if prop == null:
		return null
	prop.name = node_name
	prop.position = feet
	prop.set("prop_id", prop_id)
	group(host, "Props").add_child(prop)
	return prop


## 可破坏地形：pos 是左上角（和 platform/step 一致），size 允许 32px 分块破坏。
## persist=false 时重载恢复；只有秘道墙才传 true。
func breakable(host: Node2D, node_name: String, pos: Vector2,
		slab_size: Vector2 = Vector2(64, 32), skin: String = "stone",
		persist_break: bool = false) -> Node2D:
	var slab := BREAKABLE_SLAB.instantiate() as Node2D
	if slab == null:
		return null
	slab.name = node_name
	slab.position = pos
	slab.set("size", slab_size)
	slab.set("skin", skin)
	slab.set("persist_break", persist_break)
	group(host, "Props").add_child(slab)
	return slab


func torch(host: Node2D, x: float, feet_y: float = FLOOR_Y, tint: Color = Color.WHITE) -> Node2D:
	if not indoors():
		push_warning("ChapterLayout: torch wall plate blocked outdoors (theme=%s)" % theme())
		return null
	var t := TORCH.instantiate() as Node2D
	# Church wall plates belong to chapels. Workshops and forges get a brick hearth.
	if theme() in FURNACE_THEMES:
		t.set("style", "furnace")
	t.position = Vector2(x, feet_y - 96.0)
	t.modulate = tint
	decor_layer(host).add_child(t)
	return t


## True when key is allowed for this layout's theme() (unknown themes: allow all).
func prop_allowed(key: String) -> bool:
	return PropCatalog.allowed(theme(), key)


## Material family of this chapter's theme: "iron", "basalt", "rampart", ... (SolidPlatform skin).
func skin_family() -> String:
	return PropCatalog.family_for(theme())


## 接地装饰：feet = 脚点（底边中点，四舍五入到整像素）。用 DECOR 键或直接给路径。
## 贴图的「最后一行不透明像素」坐在 feet 上，而不是画布底边——Kenney / 墓园素材
## 底部常有 1–8px 透明留白，按画布底边摆会看起来悬空（docs/art-spec.md「角色接地」）。
func prop(host: Node2D, key_or_path: String, feet: Vector2, scale_k: float = 1.0, tint: Color = Color.WHITE,
		z: int = 0) -> Sprite2D:
	if DECOR.has(key_or_path) and not prop_allowed(key_or_path):
		push_warning("ChapterLayout: prop '%s' not in theme '%s' allowlist" % [key_or_path, theme()])
		return null
	var path := PropCatalog.path_for(key_or_path, theme())
	if not ResourceLoader.exists(path):
		return null
	var tex := DensityTextures.load_texture(path)
	if tex == null:
		return null
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.scale = Vector2(scale_k, scale_k)
	var pinned := feet.round()
	var w := float(tex.get_width()) * scale_k
	var opaque_bottom := Level01Env.opaque_bottom_px(tex)
	var land := float(opaque_bottom + 1) * scale_k
	spr.position = Vector2(roundf(pinned.x - w * 0.5), pinned.y - land)
	spr.modulate = tint
	# 尖窗、石像鬼、祭坛、立柱是墙，不是路上的道具。画在角色后面，才不会
	# 变成一块竖在街心或台面上的板子。
	if z == 0 and key_or_path in ["window", "gargoyle", "altar", "skull_column", "column",
			"brick_house", "ruin_tower"]:
		z = -3
	spr.z_index = z
	spr.set_meta("feet", pinned)
	spr.set_meta("foot_anchor", "bottom_center")
	spr.set_meta("opaque_bottom", opaque_bottom)
	# 贴图可以按主题换成族变体，键名才是「种下的是什么」：prop_fit_test 用它
	# 反查白名单、透明底和「不在原点」。
	spr.set_meta("prop_key", key_or_path)
	spr.set_meta("prop_theme", theme())
	spr.add_to_group("grounded")
	decor_layer(host).add_child(spr)
	return spr


## 会随风摆的树/灌木（用 Level01Env.plant，自动接地检查）。
## `tint` 用来把墓园的鲜绿压成本章该有的干色（锈城/城墙上的草不是春天）。
func foliage(host: Node2D, key: String, feet: Vector2, scale_k: float, shed_leaves: bool = false,
		tint: Color = Color.WHITE) -> Sprite2D:
	if DECOR.has(key) and not prop_allowed(key):
		push_warning("ChapterLayout: foliage '%s' not in theme '%s' allowlist" % [key, theme()])
		return null
	var path := PropCatalog.path_for(key, theme())
	var spr := Level01Env.plant(decor_layer(host), path, feet, scale_k, tint, shed_leaves)
	if spr != null:
		spr.set_meta("prop_key", key)
		spr.set_meta("prop_theme", theme())
		var pivot := spr.get_parent()
		if pivot != null and pivot != decor_layer(host):
			pivot.set_meta("prop_key", key)
			pivot.set_meta("prop_theme", theme())
	return spr


## 悬挂装饰（藤蔓等）：top = 顶部中点，不做接地检查。
func hanging(host: Node2D, key_or_path: String, top: Vector2, tint: Color = Color(0.9, 1.0, 0.9, 0.95)) -> Sprite2D:
	if DECOR.has(key_or_path) and not prop_allowed(key_or_path):
		push_warning("ChapterLayout: hanging '%s' not in theme '%s' allowlist" % [key_or_path, theme()])
		return null
	var path := PropCatalog.path_for(key_or_path, theme())
	if not ResourceLoader.exists(path):
		return null
	var tex := DensityTextures.load_texture(path)
	if tex == null:
		return null
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.position = Vector2(roundf(top.x - float(tex.get_width()) * 0.5), roundf(top.y))
	spr.modulate = tint
	spr.set_meta("hang_top", top.round())
	spr.set_meta("foot_anchor", "top_center")
	spr.set_meta("prop_key", key_or_path)
	spr.set_meta("prop_theme", theme())
	decor_layer(host).add_child(spr)
	return spr


## 路牌：feet = 牌柱脚点。
func waymark(host: Node2D, feet: Vector2, text: String) -> Node2D:
	var signs := host.get_node_or_null("Waymarks") as Node2D
	if signs == null:
		signs = Node2D.new()
		signs.name = "Waymarks"
		signs.z_index = 2
		host.add_child(signs)
	var root := Node2D.new()
	root.name = "Sign_%s" % text
	root.position = feet
	signs.add_child(root)
	var origin := Vector2(-17.0, -35.0)
	if ResourceLoader.exists(SIGN_TEX):
		var spr := Sprite2D.new()
		spr.name = "Board"
		spr.texture = DensityTextures.load_texture(SIGN_TEX)
		spr.centered = false
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.position = origin
		root.add_child(spr)
	var lab := Label.new()
	lab.name = "Text"
	lab.text = text
	lab.add_theme_font_size_override("font_size", SIGN_FONT_SIZE)
	lab.add_theme_color_override("font_color", Palette.PALE)
	lab.add_theme_color_override("font_outline_color", Palette.VOID)
	lab.add_theme_constant_override("outline_size", 1)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(lab)
	lab.position = (origin + SIGN_PLANK.position).round()
	lab.size = SIGN_PLANK.size
	return root


const _OVERHAUL := preload("res://scripts/levels/chapter_overhaul.gd")


## 整关气氛区（室内主题）+ 背景。build() 末尾调一次。
func finish(host: Node2D) -> void:
	_OVERHAUL.dress(self, host)
	var backdrop := ThemeBackdrop.new()
	backdrop.name = "Backdrop"
	host.add_child(backdrop)
	backdrop.build(host, theme(), camera_top())
	var flavor := motes()
	if flavor != "" and ThemeMotes.has_flavor(flavor) and host.get_node_or_null("ThemeMotes") == null:
		var specks := ThemeMotes.new()
		specks.name = "ThemeMotes"
		specks.flavor = flavor
		host.add_child(specks)
	if indoors():
		var zone := AtmosphereZone.new()
		zone.name = "IndoorZone"
		zone.zone = WorldClock.Zone.INDOORS
		var shape := RectangleShape2D.new()
		var zone_top := minf(-320.0, float(camera_top()) - 64.0)
		shape.size = Vector2(float(east_limit()) + 64.0, 464.0 - zone_top)
		var col := CollisionShape2D.new()
		col.shape = shape
		col.position = Vector2(float(east_limit()) * 0.5, (zone_top + 464.0) * 0.5)
		zone.add_child(col)
		host.add_child(zone)
	for spec in weather_regions():
		_add_weather_region(host, spec as Dictionary)


## 局部天气区域：位置取 rect 左上角，形状从原点铺到 +size。
func _add_weather_region(host: Node2D, spec: Dictionary) -> WeatherRegion:
	var rect: Rect2 = spec.get("rect", Rect2())
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return null
	var region := WeatherRegion.new()
	region.name = String(spec.get("name", "WeatherRegion"))
	region.position = rect.position
	region.rect = rect.size
	if spec.has("weather_id"):
		region.weather = WorldClock.weather_from_id(String(spec["weather_id"]))
	elif spec.has("weather"):
		region.weather = int(spec["weather"])
	else:
		# 没指定天气 = 这一片只改强度/风力，天气跟着基础态走。
		region.weather = -1
	region.intensity = clampf(float(spec.get("intensity", 1.0)), 0.0, 1.0)
	region.wind_scale = maxf(float(spec.get("wind_scale", 1.0)), 0.0)
	group(host, "Props").add_child(region)
	if bool(spec.get("outdoor", false)):
		# 室内关里挖出来的露天中庭：站进去真的会淋到雨，走出来回到室内。
		_add_zone_rect(host, String(region.name) + "Open", rect, WorldClock.Zone.OUTDOORS, WorldClock.Zone.INDOORS)
	elif bool(spec.get("indoor", false)):
		_add_zone_rect(host, String(region.name) + "Indoor", rect, WorldClock.Zone.INDOORS, WorldClock.Zone.OUTDOORS)
	return region


func _add_zone_rect(host: Node2D, zone_name: String, rect: Rect2, zone_kind: int,
		restore_kind: int) -> AtmosphereZone:
	var zone := AtmosphereZone.new()
	zone.name = zone_name
	zone.zone = zone_kind
	zone.restore_zone = restore_kind
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var col := CollisionShape2D.new()
	col.shape = shape
	col.position = rect.size * 0.5
	zone.add_child(col)
	group(host, "Props").add_child(zone)
	return zone
