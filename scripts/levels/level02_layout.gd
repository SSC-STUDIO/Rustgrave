class_name Level02Layout
extends Node2D
## 锈墓・贰「沉钟地窟」的全部铺设（地形、机关、敌人、装饰、背景）。
## 场景脚本 Level02Undercroft 只负责读档/生成玩家/相机/开场；铺设放在这里，
## 测试可以在一个空 Node2D 上 build() 而不触发关卡的 _ready。
##
## 结构（地面 y=320，一跳台阶 ≤32px）：
##   A 入口竖井 0–448    落点、余烬巢、碑文、路牌
##   B 苔水回廊 448–1120 毒水坑上的三块踏石；喷吐者守着压板高台
##   C 闸门大厅 1120–1600 压板开闸；碎铁犬巡逻；吊台横渡第二个毒水坑
##   D 沉钟前厅 1600–2560 第二余烬巢、锈门（热锻）、齿盾卫、幽魂、沉钟门（出口）

const PLATFORM := preload("res://scenes/world/Platform.tscn")
const NEST := preload("res://scenes/interactables/EmberNest.tscn")
const STELE := preload("res://scenes/interactables/LoreStele.tscn")
const TOXIN := preload("res://scenes/interactables/ToxinPool.tscn")
const PLATE := preload("res://scenes/interactables/PressurePlate.tscn")
const DOOR := preload("res://scenes/interactables/Door.tscn")
const GATE := preload("res://scenes/interactables/RustyGate.tscn")
const ANCHOR := preload("res://scenes/interactables/HookAnchor.tscn")
const SPITTER := preload("res://scenes/enemies/SpitterEnemy.tscn")
const SCRAPPER := preload("res://scenes/enemies/ScrapperEnemy.tscn")
const GEAR_SHIELD := preload("res://scenes/enemies/GearShieldEnemy.tscn")
const GHOST := preload("res://scenes/enemies/GhostEnemy.tscn")
const TORCH := preload("res://scenes/world/TorchLight.tscn")

const LEVEL_TITLE := "锈墓・贰 — 沉钟地窟"
const FLOOR_Y := 320.0
const EAST_LIMIT := 2560
const CAMERA_TOP := -48
const CEILING_Y := -32.0
const CEILING_H := 32.0
## 骑士从炉心下方落进来的竖井口。
const SHAFT_X := 64.0
const SHAFT_W := 64.0
const ENTRY_SPAWN := Vector2(96, 40)
const DEFAULT_SPAWN := Vector2(96, 300)

## [name, pos, size, skin, cap_left, cap_right]
const FLOORS: Array = [
	["FloorA", Vector2(0, 320), Vector2(448, 80), "moss", false, true],
	["PitFloorB", Vector2(448, 352), Vector2(272, 48), "moss", false, false],
	["FloorB", Vector2(720, 320), Vector2(400, 80), "moss", true, true],
	["FloorC", Vector2(1120, 320), Vector2(256, 80), "moss", true, true],
	["PitFloorC", Vector2(1376, 384), Vector2(224, 16), "moss", false, false],
	["FloorD", Vector2(1600, 320), Vector2(960, 80), "moss", true, false],
]
## [name, pos, size] — 悬空苔台（16px 厚，一跳 ≤32px 的台阶链）。
const STEPS: Array = [
	["StoneB1", Vector2(496, 288), Vector2(48, 16)],
	["StoneB2", Vector2(576, 264), Vector2(48, 16)],
	["StoneB3", Vector2(656, 288), Vector2(48, 16)],
	["StepB", Vector2(880, 288), Vector2(48, 16)],
	["LedgeB", Vector2(944, 264), Vector2(96, 16)],
	["LipC1", Vector2(1376, 352), Vector2(32, 32)],
	["LipC2", Vector2(1568, 352), Vector2(32, 32)],
	["AlcoveD", Vector2(1760, 208), Vector2(80, 16)],
	["StepD1", Vector2(1936, 288), Vector2(48, 16)],
	["GalleryD", Vector2(2000, 256), Vector2(160, 16)],
]
const TOXIN_B_POS := Vector2(448, 336)
const TOXIN_B_SIZE := Vector2(272, 32)
const TOXIN_C_POS := Vector2(1408, 368)
const TOXIN_C_SIZE := Vector2(160, 32)
## 酸黄绿：青砖苔盖的地窟里，原色毒液会被读成又一层苔地。
const TOXIN_TINT := Color(1.0, 1.25, 0.55)
## 壁炬墙板是墓园的紫石；压成青灰，融进地窟的青砖。
const TORCH_TINT := Color(0.62, 0.88, 0.9)
const NEST_SHAFT_POS := Vector2(176, 306)
const NEST_HALL_POS := Vector2(1664, 306)
## 碑文原点在碑底：直接放在台面 y 上。
const STELE_A_POS := Vector2(264, 320)
## 第二块碑藏在锈门上方的壁龛里：只有乘吊台上去、再往左跳一步的人读得到。
const STELE_D_POS := Vector2(1800, 208)
## 压板精灵 10 高、偏 -2：台面 y - 6 让板面平贴台面（与第一关 314/320 同约定）。
const PLATE_POS := Vector2(1008, 258)
const DOOR_C_POS := Vector2(1120, 256)
const GATE_D_POS := Vector2(1808, 256)
const LIFT_C_POS := Vector2(1392, 296)
const LIFT_C_TRAVEL := Vector2(144, 0)
const LIFT_C_PERIOD := 5.6
## 竖向吊台：从锈门后的地面升到壁龛高度；顶点 (1856,224) 左跳 16px 就是 AlcoveD。
const LIFT_D_POS := Vector2(1856, 304)
const LIFT_D_TRAVEL := Vector2(0, -80)
const LIFT_D_PERIOD := 4.8
const EXIT_POS := Vector2(2440, 320)
const HOOK_D_POS := Vector2(2224, 128)
## [name, scene key, pos]
const ENEMIES: Array = [
	["Ghost1", "ghost", Vector2(800, 236)],
	["Spitter1", "spitter", Vector2(968, 264)],
	["Scrapper1", "scrapper", Vector2(1248, 320)],
	["Ghost2", "ghost", Vector2(2208, 232)],
	["GearShield1", "gear_shield", Vector2(2296, 320)],
]
## 壁炬墙板 64×192 居中于位置：y=224 时板底恰在地面 320。
const TORCHES: Array = [Vector2(412, 224), Vector2(1160, 224), Vector2(1744, 224), Vector2(2392, 224), Vector2(2504, 224)]
const VINES: Array = [Vector2(200, 0), Vector2(304, 0), Vector2(768, 0), Vector2(1216, 0), Vector2(1712, 0), Vector2(2048, 0), Vector2(2352, 0)]
const WAYMARKS: Array = [[Vector2(352, 320), "地窟"], [Vector2(1720, 320), "沉钟"]]
const SIGN_TEX := "res://assets/env/normalized/props/waymark_sign.png"
const SIGN_PLANK := Rect2(0, 3, 35, 20)
const SIGN_FONT_SIZE := 12
const VINE_TEX := "res://assets/env/moss_vine.png"
const ARCH_TEX := "res://assets/env/moss_arch.png"
const RUBBLE_TEX := "res://assets/env/moss_rubble.png"

var _backdrop: Level02Backdrop
var plate: PressurePlate
var door: ArenaDoor


## Everything authored lives here so tests can build the level on a bare host.
func build(host: Node2D) -> void:
	var platforms := _group(host, "Platforms")
	var props := _group(host, "Props")
	var enemies := _group(host, "Enemies")
	var hooks := _group(host, "Hooks")
	_group(host, "Pickups")
	_build_terrain(platforms)
	_build_props(props, hooks)
	_build_enemies(enemies)
	_build_decor(host)
	_backdrop = Level02Backdrop.new()
	_backdrop.name = "Backdrop"
	host.add_child(_backdrop)
	_backdrop.build(host)


func _group(host: Node2D, group_name: String) -> Node2D:
	var node := host.get_node_or_null(group_name) as Node2D
	if node == null:
		node = Node2D.new()
		node.name = group_name
		host.add_child(node)
	return node


func _build_terrain(platforms: Node2D) -> void:
	for f in FLOORS:
		_platform(platforms, f[0], f[1], f[2], f[3], f[4], f[5])
	for s in STEPS:
		_platform(platforms, s[0], s[1], s[2], "moss_float" if (s[2] as Vector2).y <= 16.0 else "moss", true, true)
	_platform(platforms, "WallLeft", Vector2(-16, CEILING_Y), Vector2(16, FLOOR_Y + 80.0 - CEILING_Y), "moss", false, false)
	_platform(platforms, "WallRight", Vector2(EAST_LIMIT, CEILING_Y), Vector2(16, FLOOR_Y + 80.0 - CEILING_Y), "moss", false, false)
	# 顶板：留出竖井口，其余封死；镜头抬高时露出的是苔砖底面而不是虚空。
	_platform(platforms, "CeilingWest", Vector2(0, CEILING_Y), Vector2(SHAFT_X, CEILING_H), "moss", false, false)
	_platform(platforms, "CeilingEast", Vector2(SHAFT_X + SHAFT_W, CEILING_Y),
			Vector2(float(EAST_LIMIT) - SHAFT_X - SHAFT_W, CEILING_H), "moss", false, false)
	var lift_c := MovingPlatform.new()
	lift_c.name = "LiftC"
	lift_c.position = LIFT_C_POS
	lift_c.travel = LIFT_C_TRAVEL
	lift_c.period = LIFT_C_PERIOD
	lift_c.width = 64.0
	lift_c.chain_top_y = CEILING_Y + CEILING_H
	platforms.add_child(lift_c)
	var lift_d := MovingPlatform.new()
	lift_d.name = "LiftD"
	lift_d.position = LIFT_D_POS
	lift_d.travel = LIFT_D_TRAVEL
	lift_d.period = LIFT_D_PERIOD
	lift_d.phase = 0.5
	lift_d.width = 48.0
	lift_d.chain_top_y = CEILING_Y + CEILING_H
	platforms.add_child(lift_d)


func _platform(parent: Node2D, plat_name: String, pos: Vector2, sz: Vector2, skin: String,
		cap_l: bool, cap_r: bool) -> SolidPlatform:
	var plat: SolidPlatform = PLATFORM.instantiate()
	plat.name = plat_name
	plat.skin = skin
	plat.position = pos
	plat.size = sz
	plat.cap_left = cap_l
	plat.cap_right = cap_r
	parent.add_child(plat)
	return plat


func _build_props(props: Node2D, hooks: Node2D) -> void:
	var nest_a := NEST.instantiate()
	nest_a.name = "EmberNestShaft"
	nest_a.position = NEST_SHAFT_POS
	props.add_child(nest_a)
	var nest_b := NEST.instantiate()
	nest_b.name = "EmberNestHall"
	nest_b.position = NEST_HALL_POS
	props.add_child(nest_b)
	var toxin_b := TOXIN.instantiate() as ToxinPool
	toxin_b.name = "ToxinPoolB"
	toxin_b.position = TOXIN_B_POS
	toxin_b.tint = TOXIN_TINT
	props.add_child(toxin_b)
	toxin_b.configure(TOXIN_B_SIZE)
	var toxin_c := TOXIN.instantiate() as ToxinPool
	toxin_c.name = "ToxinPoolC"
	toxin_c.position = TOXIN_C_POS
	toxin_c.tint = TOXIN_TINT
	props.add_child(toxin_c)
	toxin_c.configure(TOXIN_C_SIZE)
	_add_stele(props, "SteleShaft", STELE_A_POS, "沉钟纪事 · 地窟",
			"陵墓醒来的头一件事，是把沉在苔水里的钟捞起来。听见钟响的人，就得走下去。")
	_add_stele(props, "SteleGallery", STELE_D_POS, "工坊遗训 · 吊台",
			"吊台的链子是用旧剑熔的。它们还记得怎么等一个人站稳。")
	plate = PLATE.instantiate()
	plate.name = "Plate"
	plate.position = PLATE_POS
	props.add_child(plate)
	door = DOOR.instantiate()
	door.name = "Door"
	door.position = DOOR_C_POS
	props.add_child(door)
	if not plate.activated.is_connected(door.open_door):
		plate.activated.connect(door.open_door)
	var gate := GATE.instantiate()
	gate.name = "RustyGate"
	gate.position = GATE_D_POS
	props.add_child(gate)
	var hook := ANCHOR.instantiate()
	hook.name = "Hook_Gallery"
	hook.position = HOOK_D_POS
	hooks.add_child(hook)
	var exit := LevelExit.new()
	exit.name = "BellDoor"
	exit.position = EXIT_POS
	exit.door_label = "沉钟门"
	exit.flag_id = "undercroft_done"
	exit.captions = PackedStringArray([
		"钟声从更深处传来。锈墓还没醒透。",
		"门后是风——地窟通到了地面上的锈城。",
	])
	# 沉钟门通向第三关（锈城街巷）；注册表里没有下一关时退回「章节结局」。
	var next_id := GameContext.next_level_id("level02")
	if next_id != "" and GameContext.LEVELS.has(next_id):
		exit.target_scene = GameContext.LEVELS[next_id]
		exit.spawn = ChapterLayout.entry_spawn_of(next_id)
	props.add_child(exit)


func _add_stele(parent: Node2D, stele_name: String, pos: Vector2, title: String, text: String) -> void:
	var stele := STELE.instantiate() as LoreStele
	stele.name = stele_name
	stele.position = pos
	stele.lore_title = title
	stele.lore_text = text
	parent.add_child(stele)


func _build_enemies(enemies: Node2D) -> void:
	var scenes := {"ghost": GHOST, "spitter": SPITTER, "scrapper": SCRAPPER, "gear_shield": GEAR_SHIELD}
	for e in ENEMIES:
		var scene := scenes.get(String(e[1])) as PackedScene
		if scene == null:
			continue
		var enemy := scene.instantiate() as Node2D
		enemy.name = String(e[0])
		enemy.position = e[2]
		enemies.add_child(enemy)


func _build_decor(host: Node2D) -> void:
	var decor := Node2D.new()
	decor.name = "Decor"
	decor.z_index = -2
	host.add_child(decor)
	for pos in TORCHES:
		var torch := TORCH.instantiate() as Node2D
		torch.position = pos
		torch.modulate = TORCH_TINT
		decor.add_child(torch)
	for pos in VINES:
		_sprite(decor, VINE_TEX, pos, Color(0.9, 1.0, 0.9, 0.95))
	_sprite(decor, ARCH_TEX, Vector2(24, FLOOR_Y - 48.0), Color(0.85, 0.95, 0.95), true)
	_sprite(decor, ARCH_TEX, Vector2(1216, FLOOR_Y - 48.0), Color(0.85, 0.95, 0.95), true)
	_sprite(decor, RUBBLE_TEX, Vector2(560, FLOOR_Y - 30.0 + 32.0), Color.WHITE, true)
	_sprite(decor, RUBBLE_TEX, Vector2(1980, FLOOR_Y - 30.0), Color.WHITE, true)
	var signs := Node2D.new()
	signs.name = "Waymarks"
	signs.z_index = 2
	host.add_child(signs)
	for item in WAYMARKS:
		_waymark(signs, item[0], String(item[1]))
	var zone := AtmosphereZone.new()
	zone.name = "UndercroftZone"
	zone.zone = WorldClock.Zone.INDOORS
	var shape := RectangleShape2D.new()
	shape.size = Vector2(float(EAST_LIMIT) + 64.0, FLOOR_Y + 160.0 - CEILING_Y)
	var col := CollisionShape2D.new()
	col.shape = shape
	col.position = Vector2(float(EAST_LIMIT) * 0.5, (CEILING_Y + FLOOR_Y + 160.0) * 0.5)
	zone.add_child(col)
	host.add_child(zone)


## `grounded`: the sprite's bottom edge is its foot line (LevelSanity checks it
## stands on a platform). Hanging vines are not grounded.
func _sprite(parent: Node2D, path: String, pos: Vector2, tint: Color, grounded: bool = false) -> void:
	if not ResourceLoader.exists(path):
		return
	var tex := load(path) as Texture2D
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.position = pos
	spr.modulate = tint
	if grounded:
		spr.set_meta("feet", pos + Vector2(float(tex.get_width()) * 0.5, float(tex.get_height())))
		spr.add_to_group("grounded")
	parent.add_child(spr)


func _waymark(parent: Node2D, feet: Vector2, text: String) -> void:
	var root := Node2D.new()
	root.name = "Sign_%s" % text
	root.position = feet
	parent.add_child(root)
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
