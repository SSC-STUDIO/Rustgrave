class_name Level02Layout
extends ChapterLayout
## 锈墓・贰「沉钟地窟」的全部铺设（地形、机关、敌人、装饰、背景）。
## 场景脚本 Level02Undercroft 只负责读档/生成玩家/相机/开场；铺设放在这里，
## 测试可以在一个空 Node2D 上 build() 而不触发关卡的 _ready。
##
## v3 螺旋下探结构（多层高度差 y=136..384 + 坠钟机关 + 单向捷径回环 + 笼状空钟厅）：
##   A 入口竖井 0–448      落点、第一余烬巢（176）、碑文、路牌
##   B 苔水高廊 448–1120   毒水坑踏石；首口坠钟教学（832）；拾级上探压板高台（遭遇战 1）
##   C 竖井闸厅 1120–1600  压板开闸；第二余烬巢（1164）；上下双层钟井与吊台横渡（遭遇战 2）
##   D 沉钟前厅 1600–2360  第三余烬巢（1664）、热锻锈门、三层下沉钟堂（y=224/256/352，遭遇战 3）、
##                         梁顶钩锁可选挑战与骨符奖励（y=136）、上层压板解锁地面单向捷径门（1944）
##   E 坠钟回廊 2360–2700  双口交替坠钟走廊（2432/2528）直抵第四余烬巢（2632）
##   F 空钟笼厅 2700–3620  空钟 Boss 笼状竞技场（920px 连续底板 + 两侧避钟笼台 + 中央击锤高台）

## 空钟 Boss 场景（bosses-a 交付；缺失时本关照常可通、出口保持开放，不软锁）。
const HOLLOW_BELL_PATH := "res://scenes/enemies/HollowBell.tscn"

const EAST_LIMIT := 3800
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
	["FloorD", Vector2(1600, 320), Vector2(360, 80), "moss", true, true],
	## D 段下沉钟堂：1960–2432 下沉至 y=352，与上层 y=256/224 构成三层螺旋下探空间。
	["FloorSunken", Vector2(1960, 352), Vector2(472, 48), "moss", false, false],
	["FloorE", Vector2(2432, 320), Vector2(1368, 80), "moss", true, false],
]
## [name, pos, size] — 悬空苔台（16px 厚，一跳 ≤32px 的台阶链）。
const STEPS: Array = [
	["StoneB1", Vector2(496, 288), Vector2(48, 16)],
	["StoneB2", Vector2(576, 264), Vector2(48, 16)],
	["StoneB3", Vector2(656, 288), Vector2(48, 16)],
	["StepB", Vector2(880, 288), Vector2(48, 16)],
	["LedgeB", Vector2(944, 264), Vector2(96, 16)],
	["Ring1Balcony", Vector2(1048, 232), Vector2(56, 16)],
	["StepC1", Vector2(1200, 288), Vector2(40, 16)],
	["VaultCatwalk", Vector2(1248, 256), Vector2(96, 16)],
	["ShaftOverlook", Vector2(1448, 224), Vector2(64, 16)],
	["LipC1", Vector2(1376, 352), Vector2(32, 32)],
	["LipC2", Vector2(1568, 352), Vector2(32, 32)],
	["AlcoveD", Vector2(1760, 208), Vector2(80, 16)],
	["BellRafter", Vector2(1864, 136), Vector2(96, 16)],
	["StepD1", Vector2(1908, 288), Vector2(32, 16)],
	["GalleryD", Vector2(1976, 256), Vector2(160, 16)],
	["UpperBridgeD", Vector2(2144, 224), Vector2(144, 16)],
	["StepD2", Vector2(2296, 256), Vector2(48, 16)],
	# Leave a full body and run-up clear of this overhang so a missed upper
	# gallery jump can recover onto FloorE before opening the shortcut.
	["StepD3", Vector2(2352, 288), Vector2(48, 16)],
	## F 段空钟笼厅：两侧避钟笼台 + 上层悬廊 + 中央击锤高台。
	["CageAlcoveWest", Vector2(2760, 288), Vector2(64, 16)],
	["CageBelfryWest", Vector2(2840, 256), Vector2(56, 16)],
	["CageDais", Vector2(3088, 288), Vector2(80, 16)],
	["CageBelfryEast", Vector2(3200, 256), Vector2(56, 16)],
	["CageAlcoveEast", Vector2(3272, 288), Vector2(64, 16)],
]
const TOXIN_B_POS := Vector2(448, 336)
const TOXIN_B_SIZE := Vector2(272, 32)
const TOXIN_C_POS := Vector2(1408, 368)
const TOXIN_C_SIZE := Vector2(160, 32)
## 酸黄绿：青砖苔盖的地窟里，原色毒液会被读成又一层苔地。
const TOXIN_TINT := Color(1.0, 1.25, 0.55)
## 壁炬墙板是墓园的紫石；压成青灰，融进地窟的青砖。
const TORCH_TINT := Color(0.62, 0.88, 0.9)
## 四座余烬巢间距全部 <=1000px：176 -> 1164 (988px) -> 1664 (500px) -> 2632 (968px)。
const NEST_SHAFT_POS := Vector2(176, 306)
const NEST_VAULT_POS := Vector2(1164, 306)
const NEST_HALL_POS := Vector2(1664, 306)
## E 段 Boss 前巢：门在 2680，竞技场左界 2700 —— 巢到门 48px、到竞技场 68px（契约 ≤80）。
const NEST_BELL_POS := Vector2(2632, 306)
## 碑文原点在碑底：直接放在台面 y 上。
const STELE_A_POS := Vector2(264, 320)
## 第二块碑藏在锈门上方的壁龛里：只有乘吊台上去、再往左跳一步的人读得到。
const STELE_D_POS := Vector2(1800, 208)
## 压板精灵 10 高、偏 -2：台面 y - 6 让板面平贴台面（与第一关 314/320 同约定）。
const PLATE_POS := Vector2(1008, 258)
const DOOR_C_POS := Vector2(1120, 256)
const GATE_D_POS := Vector2(1808, 256)
## D 段单向捷径：从上层钟桥踩下 ShortcutPlate，永久打开地面 ShortcutDoor，直连 EmberNestHall。
const SHORTCUT_PLATE_POS := Vector2(2252, 218)
const SHORTCUT_DOOR_POS := Vector2(1944, 256)
const LIFT_C_POS := Vector2(1392, 296)
const LIFT_C_TRAVEL := Vector2(144, 0)
const LIFT_C_PERIOD := 5.6
## 竖向吊台：从锈门后的地面升到壁龛高度；顶点 (1856,224) 左跳 16px 就是 AlcoveD。
const LIFT_D_POS := Vector2(1856, 304)
const LIFT_D_TRAVEL := Vector2(0, -80)
const LIFT_D_PERIOD := 4.8
## F 段空钟厅（audio-audit 常量）：竞技场 920px 连续平地（2700–3620），Boss 在中东侧；
## 竞技场门 2680、出口门 3560（Boss 倒后开），出口仍指向 level02b。
const ARENA_LEFT := 2700.0
const ARENA_RIGHT := 3620.0
const ARENA_GATE_X := 2680.0
const BOSS_POS := Vector2(3460, 320)
const EXIT_POS := Vector2(3560, 320)
const EXIT_REQUIRES := "hollow_bell_dead"
const EXIT_LOCKED_PROMPT := "钟还在数人。"
## 空钟厅的两个落钟机关（Boss 侧按 id 触发；布局只注册，不主动砸人）。
const BELL_FALL_WEST := 2920.0
const BELL_FALL_EAST := 3380.0
## 梁顶可选分支钩点与骨符奖励点（仅凭钩锁可达；Fill 底边在 +7px，故 y=136-7=129）。
const HOOK_D_POS := Vector2(1912, 112)
const REWARD_RAFTER_POS := Vector2(1912, 129)
const REWARD_RAFTER_ID := "bone_charm"
## 周期性坠钟机关：[name, pos, size, telegraph, active, rest, phase]
const BELL_HAZARDS: Array = [
	["BellTeach", Vector2(832, 320), Vector2(36, 40), 0.9, 0.45, 2.8, 0.25],
	["BellShaftWest", Vector2(1296, 256), Vector2(36, 40), 0.85, 0.45, 2.5, 0.0],
	["BellVaultLower", Vector2(2056, 352), Vector2(36, 40), 0.8, 0.45, 2.4, 0.2],
	["BellVaultUpper", Vector2(2176, 224), Vector2(36, 40), 0.8, 0.45, 2.4, 0.6],
	["BellCorridorWest", Vector2(2480, 320), Vector2(36, 40), 0.75, 0.45, 2.2, 0.0],
	["BellCorridorEast", Vector2(2560, 320), Vector2(36, 40), 0.75, 0.45, 2.2, 0.5],
]
## [name, scene key, pos, variant]
const ENEMIES: Array = [
	["Ghost1", "ghost", Vector2(792, 224), ""],
	["Spitter1", "spitter", Vector2(968, 264), "scatter_spitter"],
	["Scrapper1", "scrapper", Vector2(1288, 320), "armored_scrapper"],
	["GhostShaft", "ghost", Vector2(1480, 184), ""],
	["Scrapper2", "scrapper", Vector2(2040, 256), "swift_scrapper"],
	["Ghost2", "ghost", Vector2(2120, 184), ""],
	["GearShield1", "gear_shield", Vector2(2160, 352), "heavy_guard"],
	["Ghost3", "ghost", Vector2(2260, 184), ""],
	["Spitter2", "spitter", Vector2(2316, 256), ""],
]
## 壁炬墙板 64×192 居中于位置：y=224 时板底恰在地面 320。
const TORCHES: Array = [Vector2(412, 224), Vector2(1160, 224), Vector2(1744, 224), Vector2(2392, 224),
		Vector2(2580, 224), Vector2(2860, 224), Vector2(3320, 224), Vector2(3608, 224)]
const VINES: Array = [Vector2(200, 0), Vector2(304, 0), Vector2(768, 0), Vector2(1216, 0),
		Vector2(1712, 0), Vector2(2048, 0), Vector2(2352, 0), Vector2(2520, 0), Vector2(2900, 0),
		Vector2(3200, 0), Vector2(3500, 0)]
const WAYMARKS: Array = [[Vector2(352, 320), "地窟"], [Vector2(1720, 320), "沉钟"],
		[Vector2(2448, 320), "回廊"], [Vector2(2748, 320), "空钟"]]
const VINE_TEX := "res://assets/env/moss_vine.png"
const ARCH_TEX := "res://assets/env/moss_arch.png"
const RUBBLE_TEX := "res://assets/env/moss_rubble.png"

var _backdrop: Level02Backdrop
var plate: PressurePlate
var door: ArenaDoor
var shortcut_plate: PressurePlate
var shortcut_door: ArenaDoor
## F 段 Boss / 竞技场（场景未交付时都为 null；出口保持开放）。
var boss_node: Node2D
var arena: BossArena


func level_id() -> String:
	return "level02"


func title() -> String:
	return ChapterText.title_of(level_id())


func wake_line() -> String:
	return ChapterText.wake_of(level_id())


func theme() -> String:
	return "undercroft"


func east_limit() -> int:
	return EAST_LIMIT


func camera_top() -> int:
	return CAMERA_TOP


func entry_spawn() -> Vector2:
	return ENTRY_SPAWN


func default_spawn() -> Vector2:
	return DEFAULT_SPAWN


## Everything authored lives here so tests can build the level on a bare host.
func build(host: Node2D) -> void:
	var platforms := group(host, "Platforms")
	var props := group(host, "Props")
	group(host, "Enemies")
	var hooks := group(host, "Hooks")
	group(host, "Pickups")
	_build_terrain(platforms)
	_build_props(host, props, hooks)
	_build_hazards(host)
	_build_enemies(host)
	_build_boss(host)
	_build_decor(host)
	_backdrop = Level02Backdrop.new()
	_backdrop.name = "Backdrop"
	host.add_child(_backdrop)
	_backdrop.build(host)
	# Pale spores lift off the acid pools: the undercroft breathes, the forge burns.
	if host.get_node_or_null("ThemeMotes") == null:
		var specks := ThemeMotes.new()
		specks.name = "ThemeMotes"
		specks.flavor = "spores"
		host.add_child(specks)


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


func _build_props(host: Node2D, props: Node2D, hooks: Node2D) -> void:
	var nest_a := NEST.instantiate()
	nest_a.name = "EmberNestShaft"
	nest_a.position = NEST_SHAFT_POS
	props.add_child(nest_a)
	var nest_vault := NEST.instantiate()
	nest_vault.name = "EmberNestVault"
	nest_vault.position = NEST_VAULT_POS
	props.add_child(nest_vault)
	var nest_b := NEST.instantiate()
	nest_b.name = "EmberNestHall"
	nest_b.position = NEST_HALL_POS
	props.add_child(nest_b)
	## E 段 Boss 前巢：空钟门（2680）前最后一口余火；死一次不用从沉钟前厅重跑。
	var nest_c := NEST.instantiate()
	nest_c.name = "EmberNestBell"
	nest_c.position = NEST_BELL_POS
	props.add_child(nest_c)
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
	_add_registry_stele(props, "SteleShaft", STELE_A_POS)
	_add_registry_stele(props, "SteleGallery", STELE_D_POS)
	plate = PLATE.instantiate()
	plate.name = "Plate"
	plate.position = PLATE_POS
	props.add_child(plate)
	_harmonize_fill(plate, "plate")
	door = DOOR.instantiate()
	door.name = "Door"
	door.position = DOOR_C_POS
	props.add_child(door)
	_harmonize_fill(door, "door_arch")
	if not plate.activated.is_connected(door.open_door):
		plate.activated.connect(door.open_door)
	## D 段单向捷径回环：从上层钟桥踩下 ShortcutPlate，永久打开地面 ShortcutDoor。
	shortcut_plate = PLATE.instantiate()
	shortcut_plate.name = "ShortcutPlate"
	shortcut_plate.position = SHORTCUT_PLATE_POS
	props.add_child(shortcut_plate)
	_harmonize_fill(shortcut_plate, "plate")
	shortcut_door = DOOR.instantiate()
	shortcut_door.name = "ShortcutDoor"
	shortcut_door.position = SHORTCUT_DOOR_POS
	props.add_child(shortcut_door)
	_harmonize_fill(shortcut_door, "door_arch")
	if not shortcut_plate.activated.is_connected(shortcut_door.open_door):
		shortcut_plate.activated.connect(shortcut_door.open_door)
	var gate := GATE.instantiate()
	gate.name = "RustyGate"
	gate.position = GATE_D_POS
	props.add_child(gate)
	_harmonize_fill(gate, "door_arch")
	var hook_anchor := ANCHOR.instantiate()
	hook_anchor.name = "Hook_Gallery"
	hook_anchor.position = HOOK_D_POS
	hooks.add_child(hook_anchor)
	## 梁顶可选奖励位（骨符）+ 可破坏补给罐。
	var item := EquipmentCatalog.for_id(StringName(REWARD_RAFTER_ID))
	var item_label := item.display_name if item != null else ""
	var pick := reward(host, "RewardUndercroft", REWARD_RAFTER_POS, "equipment", REWARD_RAFTER_ID, item_label)
	if pick != null:
		pick.item_id = StringName(REWARD_RAFTER_ID)
	destructible(host, "RafterUrn", &"rust_urn", Vector2(1880, 136))
	destructible(host, "ArenaCacheWest", &"rust_urn", Vector2(2732, 320))
	destructible(host, "ArenaCacheEast", &"scrap_heap", Vector2(3356, 320))
	var exit := LevelExit.new()
	exit.name = "BellDoor"
	exit.position = EXIT_POS
	exit.door_label = ChapterText.exit_label_of("level02")
	exit.flag_id = "undercroft_done"
	exit.captions = ChapterText.exit_captions_of("level02")
	## 空钟 Boss 场景存在 -> 门锁到 hollow_bell_dead（空钟死在门前）；场景缺失 ->
	## 不挂条件，出口保持开放（M3b 交付后自动生效，绝不软锁）。
	if ResourceLoader.exists(HOLLOW_BELL_PATH):
		exit.requires_flag = EXIT_REQUIRES
		exit.locked_prompt = EXIT_LOCKED_PROMPT
	var next_id := GameContext.next_level_id("level02")
	if next_id != "" and GameContext.LEVELS.has(next_id):
		exit.target_scene = GameContext.LEVELS[next_id]
		exit.spawn = ChapterLayout.entry_spawn_of(next_id)
	props.add_child(exit)


func _build_hazards(host: Node2D) -> void:
	for h in BELL_HAZARDS:
		cyclic(host, String(h[0]), h[1], "bell", {
			"size": h[2],
			"telegraph_time": float(h[3]),
			"active_time": float(h[4]),
			"rest_time": float(h[5]),
			"phase": float(h[6]),
		})


func _add_stele(parent: Node2D, stele_name: String, pos: Vector2, lore_title: String, lore_text: String) -> void:
	var s := STELE.instantiate() as LoreStele
	s.name = stele_name
	s.position = pos
	s.lore_title = lore_title
	s.lore_text = lore_text
	parent.add_child(s)


## 碑文文本从 ChapterText 取；位置常量留在本文件（几何归关卡，文本归注册表）。
func _add_registry_stele(parent: Node2D, stele_name: String, pos: Vector2) -> void:
	var entry := ChapterText.stele_of(level_id(), stele_name)
	_add_stele(parent, stele_name, pos, String(entry.get("title", "")), String(entry.get("text", "")))


func _build_enemies(host: Node2D) -> void:
	for e in ENEMIES:
		var overrides := {}
		if e.size() >= 4 and String(e[3]) != "":
			overrides["variant"] = StringName(String(e[3]))
		enemy(host, String(e[0]), String(e[1]), e[2], overrides)


## F 段空钟厅：Boss 场景（bosses-a 交付）存在才放 Boss + 竞技场 + 落钟机关；
## 场景缺失时整段保持空厅、出口开放，关卡照常可通（不软锁）。
## 落钟机关 id 交给 Boss 侧按招触发（bell_fall_west / bell_fall_east）。
## 空钟死在门前 -> hollow_bell_dead，写进存档；出口 requires_flag 与之一致。
func _build_boss(host: Node2D) -> void:
	if SaveData.has_flag(EXIT_REQUIRES):
		return
	if not ResourceLoader.exists(HOLLOW_BELL_PATH):
		return
	var scene := load(HOLLOW_BELL_PATH) as PackedScene
	if scene == null:
		return
	boss_node = scene.instantiate() as Node2D
	if boss_node == null:
		return
	boss_node.name = "HollowBell"
	boss_node.position = BOSS_POS
	boss_node.set("arena_left", ARENA_LEFT)
	boss_node.set("arena_right", ARENA_RIGHT)
	group(host, "Enemies").add_child(boss_node)
	arena = BOSS_ARENA.attach(host, "HollowBellArena", boss_node, ARENA_LEFT, ARENA_RIGHT, FLOOR_Y)
	if arena != null:
		arena.register_hazard(&"bell_fall_west", arena.make_hazard(BossArena.HazardKind.ROCKFALL,
				Vector2(BELL_FALL_WEST, FLOOR_Y),
				{"size": Vector2(48, 32), "offset": Vector2(0, -16), "telegraph": 0.45}))
		arena.register_hazard(&"bell_fall_east", arena.make_hazard(BossArena.HazardKind.ROCKFALL,
				Vector2(BELL_FALL_EAST, FLOOR_Y),
				{"size": Vector2(48, 32), "offset": Vector2(0, -16), "telegraph": 0.45}))
	if boss_node.has_signal("slain") and not boss_node.is_connected("slain", _on_boss_slain):
		boss_node.slain.connect(_on_boss_slain)


## 空钟倒地：写旗标 + 落盘，钟门开。Boss 侧自己写同名旗标也兼容（幂等）。
func _on_boss_slain() -> void:
	SaveData.mark_flag(EXIT_REQUIRES)
	SaveData.persist_story()


func _build_decor(host: Node2D) -> void:
	var decor := decor_layer(host)
	for pos in TORCHES:
		var t := TORCH.instantiate() as Node2D
		t.position = pos
		t.modulate = TORCH_TINT
		decor.add_child(t)
	for pos in VINES:
		_sprite(decor, VINE_TEX, pos, Color(0.9, 1.0, 0.9, 0.95))
	_sprite(decor, ARCH_TEX, Vector2(24, FLOOR_Y - 48.0), Color(0.85, 0.95, 0.95), true)
	_sprite(decor, ARCH_TEX, Vector2(1216, FLOOR_Y - 48.0), Color(0.85, 0.95, 0.95), true)
	_sprite(decor, RUBBLE_TEX, Vector2(560, FLOOR_Y - 30.0 + 32.0), Color.WHITE, true)
	_sprite(decor, RUBBLE_TEX, Vector2(1980, 352.0 - 30.0), Color.WHITE, true)
	## E 段沉钟回廊：门洞、碎石、垂链——沉钟的回声从头顶数下来。
	_sprite(decor, ARCH_TEX, Vector2(ARENA_GATE_X - 22.0, FLOOR_Y - 48.0),
			Color(0.8, 0.92, 0.92), true)
	_sprite(decor, RUBBLE_TEX, Vector2(2464, FLOOR_Y - 30.0), Color.WHITE, true)
	_sprite(decor, RUBBLE_TEX, Vector2(2656, FLOOR_Y - 30.0), Color.WHITE, true)
	## F 段空钟厅：两处落钟位的垂链 + 场地边缘的碎石，读得出「钟是从上面下来的」。
	_sprite(decor, RUBBLE_TEX, Vector2(2880, FLOOR_Y - 30.0), Color.WHITE, true)
	_sprite(decor, RUBBLE_TEX, Vector2(3520, FLOOR_Y - 30.0), Color.WHITE, true)
	var chain_path: String = PropCatalog.path_for("chain", "undercroft")
	if ResourceLoader.exists(chain_path):
		for x in [832.0, 1296.0, 2056.0, 2176.0, 2432.0, 2528.0, BELL_FALL_WEST, BELL_FALL_EAST, 2700.0, 3100.0]:
			_sprite(decor, chain_path, Vector2(x - 4.0, CEILING_Y + CEILING_H), Color(0.78, 0.9, 0.9, 0.95))
	# F 段舞台地标：沉钟被拆下来的两座钟架（青苔拱门）+ 悬梁垂链，两侧各点一座落地炉膛。
	_sprite(decor, ARCH_TEX, Vector2(2752, FLOOR_Y - 48.0), Color(0.74, 0.86, 0.86), true)
	_sprite(decor, ARCH_TEX, Vector2(3568, FLOOR_Y - 48.0), Color(0.74, 0.86, 0.86), true)
	_sprite(decor, RUBBLE_TEX, Vector2(2960, FLOOR_Y - 30.0), Color.WHITE, true)
	for x in [2792.0, 3528.0]:
		var hearth := TORCH.instantiate() as Node2D
		hearth.name = "BellHearth%d" % int(x)
		hearth.set("style", "furnace")
		hearth.set("light_color", Color(1.0, 0.66, 0.36, 1.0))
		hearth.set("base_energy", 0.8)
		hearth.set("light_radius", 72.0)
		hearth.position = Vector2(x, FLOOR_Y - 96.0)
		decor.add_child(hearth)
	for item in WAYMARKS:
		waymark(host, item[0], String(item[1]))
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
		spr.set_meta("feet", (pos + Vector2(float(tex.get_width()) * 0.5, float(tex.get_height()))).round())
		spr.set_meta("foot_anchor", "bottom_center")
		spr.add_to_group("grounded")
	parent.add_child(spr)
