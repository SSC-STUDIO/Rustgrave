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

## 敌人键 → 场景。缺失的场景会被跳过（并 push_warning），关卡照常搭建。
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
}

## 可用的装饰贴图（都已导入）。键 → 路径。
const DECOR := {
	"vine": "res://assets/env/moss_vine.png",           # 16×64，从顶板垂下（不接地）
	"arch": "res://assets/env/moss_arch.png",           # 96×48 排水拱，接地
	"rubble": "res://assets/env/moss_rubble.png",       # 32×30 苔石堆，接地
	"stair": "res://assets/env/moss_stair.png",         # 32×41 苔阶（装饰，接地）
	"wall_block": "res://assets/env/moss_wall_block.png", # 160×83 苔墙块，接地
	"door": "res://assets/env/moss_door.png",           # 48×64 木门（装饰用，接地）
	"balustrade": "res://assets/env/balustrade.png",    # 80×52 石栏，接地
	"column": "res://assets/env/column_big.png",        # 114×190 大柱，接地（背景）
	"gargoyle": "res://assets/env/bg_gargoyle.png",     # 石像鬼墙板（背景，接地）
	"altar": "res://assets/env/bg_altar.png",           # 祭坛墙板（背景，接地）
	"window": "res://assets/env/bg_wall_window.png",    # 尖窗墙板（背景，接地）
	"skull_column": "res://assets/env/bg_column_skulls.png", # 骷髅柱（背景，接地）
	"statue": "res://assets/env/statue_keeper.png",     # 守墓者石像，接地
	"grave_cross": "res://assets/env/grave_cross.png",  # 十字墓碑，接地
	"door_arch": "res://assets/env/door_arch.png",      # 32×64 石门洞（装饰），接地
	"stone_1": Level01Env.DECOR_STONE_1,
	"stone_2": Level01Env.DECOR_STONE_2,
	"stone_3": Level01Env.DECOR_STONE_3,
	"stone_4": Level01Env.DECOR_STONE_4,
	"tree_1": Level01Env.DECOR_TREE_1,
	"tree_2": Level01Env.DECOR_TREE_2,
	"bush_l": Level01Env.DECOR_BUSH_L,
	"bush_s": Level01Env.DECOR_BUSH_S,
}

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


## ThemeBackdrop 主题：undercroft / forge / cathedral / town / industrial / graveyard。
func theme() -> String:
	return "undercroft"


func indoors() -> bool:
	return ThemeBackdrop.is_indoor_theme(theme())


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


## 压板 + 闸门。plate_feet = 压板所在台面（x, y）；door_pos = 门左上角（门 16×64，底在 y+64）。
func plate_door(host: Node2D, pair_name: String, plate_feet: Vector2, door_pos: Vector2) -> Array:
	var plate := PLATE.instantiate()
	plate.name = pair_name + "Plate"
	plate.position = plate_feet + Vector2(0.0, -6.0)
	group(host, "Props").add_child(plate)
	var door := DOOR.instantiate()
	door.name = pair_name + "Door"
	door.position = door_pos
	group(host, "Props").add_child(door)
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
	if next_level_id != "" and GameContext.LEVELS.has(next_level_id):
		e.target_scene = GameContext.LEVELS[next_level_id]
		e.spawn = ChapterLayout.entry_spawn_of(next_level_id)
	group(host, "Props").add_child(e)
	return e


## 下一关的落点（读它的 layout）。
static func entry_spawn_of(next_level_id: String) -> Vector2:
	var path: String = GameContext.LAYOUTS.get(next_level_id, "")
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


## ---------------------------------------------------------------- decor --

## 壁炬（墙板 64×192 居中于 pos；y = 台面 - 96 时板底贴台面）。
func torch(host: Node2D, x: float, feet_y: float = FLOOR_Y, tint: Color = Color.WHITE) -> Node2D:
	var t := TORCH.instantiate() as Node2D
	t.position = Vector2(x, feet_y - 96.0)
	t.modulate = tint
	decor_layer(host).add_child(t)
	return t


## 接地装饰：feet = 脚点（底边中点）。用 DECOR 键或直接给路径。
func prop(host: Node2D, key_or_path: String, feet: Vector2, scale_k: float = 1.0, tint: Color = Color.WHITE,
		z: int = 0) -> Sprite2D:
	var path: String = DECOR.get(key_or_path, key_or_path)
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.scale = Vector2(scale_k, scale_k)
	var w := float(tex.get_width()) * scale_k
	var h := float(tex.get_height()) * scale_k
	spr.position = Vector2(feet.x - w * 0.5, feet.y - h)
	spr.modulate = tint
	spr.z_index = z
	spr.set_meta("feet", feet)
	spr.add_to_group("grounded")
	decor_layer(host).add_child(spr)
	return spr


## 会随风摆的树/灌木（用 Level01Env.plant，自动接地检查）。
func foliage(host: Node2D, key: String, feet: Vector2, scale_k: float, shed_leaves: bool = false) -> Sprite2D:
	var path: String = DECOR.get(key, key)
	return Level01Env.plant(decor_layer(host), path, feet, scale_k, Color.WHITE, shed_leaves)


## 悬挂装饰（藤蔓等）：top = 顶部中点，不做接地检查。
func hanging(host: Node2D, key_or_path: String, top: Vector2, tint: Color = Color(0.9, 1.0, 0.9, 0.95)) -> Sprite2D:
	var path: String = DECOR.get(key_or_path, key_or_path)
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.position = Vector2(top.x - float(tex.get_width()) * 0.5, top.y)
	spr.modulate = tint
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
		spr.texture = load(SIGN_TEX) as Texture2D
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


## 整关气氛区（室内主题）+ 背景。build() 末尾调一次。
func finish(host: Node2D) -> void:
	var backdrop := ThemeBackdrop.new()
	backdrop.name = "Backdrop"
	host.add_child(backdrop)
	backdrop.build(host, theme(), camera_top())
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
