extends ChapterLayout
## 锈墓・壹 — 腐液回廊，东半（x≈1100 → 3760）的重建。
##
## 这不是一个注册的章节：level01 仍是手摆场景（Level01_Static.tscn），不在
## GameContext.LAYOUTS 里（level_routing_test 断言这一点）。这里只借 ChapterLayout 的铺设
## 助手，把新增的地形 / 机关 / 敌人 / 装饰写进场景已有的 Platforms / Props / Pickups 文件夹，
## 由 Level01EastWing.build() 调用。**不要加 class_name，也不要登记进 LAYOUTS。**
##
## 持久化节点（压板、闸门、废料堆……）仍在 .tscn 里，路径不变，位置由本文件的常量给出
## （tests/level01_route_test.gd 断言 .tscn 与这里一致）。
##
## 四个乐章（地面 y=320，一跳台阶 ≤32px、横跨 ≤72px；没有一处主线要钩锁 / 余烬步）：
##   ① 压板偏殿  1100–1700  下层是地穴巷（压板门在巷里），上层是楼座（压板在楼座上）：
##        前半的上层路（售货石 Plat_920_248 / Plat_980_180）经 Spitter1 的矮台爬到楼座西头；
##        楼座中段是章节里第一根塌陷锈梁（前后各有 ≥48px 的实心落脚，两只楼座喷吐者的
##        仇恨圈 140px 不够到桥），压板在梁东侧、被高低两只喷吐者夹着（楼座交叉火力）。
##        地穴巷里：装甲碎铁犬 + 齿盾卫守在闸门前（伏击巷）。巷西是第二个余烬巢。
##   ② 锻核工坊  1688–2560  压板门后：工坊（废料堆 + 嵌核台），净化祠与第三个余烬巢（休息龛），
##        三口喷火炉口的炉廊（错相、预警 0.9s），锈门在炉廊尽头。炉廊上方是余烬阁：
##        钩锁锚点 + 余烬核（可选），再往东一根塌陷梁通向奖励台（可选挑战），
##        奖励台两头都是单向落下：西头回到休息龛，东头越过炉口落在锈门前。
##   ③ 中殿长阶  2560–3040  锈门之后：矮石阶降到中殿（320 → 336 → 352），誓言碑，
##        BossGate 前的第四个余烬巢（离门 ≤80px）。
##   ④ 炉厅竞技场 3040–3760 刽子手立在抬高 16px 的石台上，台上两座掩体墩，两口炉龛喷火口
##        只在 Boss 战里喷（二阶段更急、Boss 倒下就停），炉心与炉棚在最东头。
##
## 常量：x/y 是世界坐标。需要测试读的位置全部在这里。

const EAST_LIMIT := 3760
const GROUND := 320.0
## 中殿 / 竞技场底面（比巷面低 32px，两级 16px 石阶下去）。
const NAVE_Y := 352.0
## 刽子手的石台顶：比中殿底面高 16px。
const STAGE_Y := 336.0

## --- ① 前半的上层路：Spitter1 的矮台 → 三块浮石 → 楼座西头 ---------------------------------
## 单跳的真实水平够距：升 16 约 50px，升 24 约 44px，升 32 约 38px（顶点 37px，越高越短）。
## LevelSanity 的 72px 是粗模型；这里每一跳都 ≤36px 横跨、升 ≤24（后两跳升 16），不靠冲刺。
## 前两块是 .tscn 里 Plat_920_248 / Plat_980_180 的新位置，第三块（HighRoadC）由本文件铺。
const GROUND_RIGHT_END := 1168.0
const HIGH_ROAD_A_POS := Vector2(900, 264)
const HIGH_ROAD_B_POS := Vector2(972, 240)
const HIGH_ROAD_C_POS := Vector2(1044, 224)
const HIGH_ROAD_W := 48.0
## Spitter1 的矮台（Plat_760_184，.tscn）顶 y=288；上层路从它的东端起跳。
const SPITTER_PERCH_TOP := 288.0
## 矮台东侧的垫阶（顶 304，16 高）：矮台是 32px 的坎、台下只有 16px，走过头的人从东边落回地面时
## 单跳 32 爬不回去（身体要先升过台面才能横移）。垫阶把它拆成两个 16px 的台阶，两边都能上。
const PERCH_STEP_POS := Vector2(864, 304)
const PERCH_STEP_SIZE := Vector2(32, 16)

## --- ② 压板偏殿 ----------------------------------------------------------------
## 楼座：西头落脚（上层路到这里）、塌陷锈梁、东头压板台 + 高低两处喷吐者。
const GALLERY_Y := 208.0
const GALLERY_W_POS := Vector2(1120, GALLERY_Y)
const GALLERY_W_SIZE := Vector2(128, 32)
const GALLERY_BEAM_POS := Vector2(1264, GALLERY_Y)
const GALLERY_BEAM_W := 48.0
const GALLERY_E_POS := Vector2(1328, GALLERY_Y)
const GALLERY_E_SIZE := Vector2(240, 32)
## 东头高墩（顶 176）：Spitter3 站在上面，和楼座面上的 Spitter2 一高一低夹住压板。
const GALLERY_PERCH_POS := Vector2(1512, 176)
const GALLERY_PERCH_SIZE := Vector2(56, 32)
## 压板节点原点（PressurePlate 脚点 = x+12, y+8）。压板在楼座上，闸门在巷里。
const PLATE_POS := Vector2(1412, 202)
const DOOR_POS := Vector2(1664, 256)
## 第二个余烬巢：楼座西头的下面是它的光柱，巢要让开楼板（体检的「埋进实心」≥25%），
## 又要在 Spitter1（仇恨圈 260）与 GearShield1（190）够不到的地方。
const NEST_MID_X := 1096.0
const SPITTER2_POS := Vector2(1472, 208)
const SPITTER3_POS := Vector2(1540, 176)
## 楼座喷吐者只盯压板：仇恨圈收到 140px，够不到 160px 外的塌陷梁（第一根梁在安全处教学）。
const GALLERY_SPITTER_AGGRO := 140.0
const LANE_SCRAPPER_POS := Vector2(1400, 320)
## 齿盾卫是 .tscn 里的 GearShield1（从前半挪到巷里守闸门）；第一次见盾卫就是在伏击巷。
const LANE_SHIELD_POS := Vector2(1568, 320)
## 前半唯一的碎铁犬（Scrapper1，.tscn）：仇恨圈收到 140px、巡逻 16px，站在矮台垫阶东边，
## 离第二个余烬巢（1096）的 215px 默认仇恨圈之外。
const SCRAPPER1_POS := Vector2(930, 320)

## --- ③ 锻核工坊 / 炉廊 / 余烬阁 ---------------------------------------------------------
const SCRAP_PILE_POS := Vector2(1744, 302)
const SOCKET_POS := Vector2(1840, 296)
const SHRINE_POS := Vector2(2024, 288)
const NEST_FORGE_X := 2112.0
## 炉口：x 是喷口中心。相位错开 1/3 周期，三口不会同时喷，也不会连成一堵火墙。
const VENT_X: Array[float] = [2288.0, 2376.0, 2464.0]
const VENT_PHASE: Array[float] = [0.0, 0.34, 0.67]
const VENT_PROPS := {"rest_time": 2.4, "telegraph_time": 0.9, "active_time": 0.6}
## 炉廊的顶板（也是一条栈道）：盖住三口炉口，读作有顶的炉廊；火舌尖离板底 16px。
## 站不上去（主线不经过），只有余烬阁东头的单向落下能落在它上面：
## 从板西头落下 = 回到休息龛一侧的巢，从东头落下 = 越过炉口落在锈门前。
const VENT_DECK_POS := Vector2(2256, 208)
const VENT_DECK_SIZE := Vector2(296, 32)
const GATE_POS := Vector2(2584, 256)
## 余烬阁：EmberLedge / Hook_Ember / EmberCore 的位置在 Level01EastWing 里。
const EYRIE_BEAM_POS := Vector2(2328, 112)
const EYRIE_BEAM_W := 48.0
const EYRIE_EAST_POS := Vector2(2392, 112)
const EYRIE_EAST_W := 88.0
## 奖励位：节点原点在台面上方 7px（Fill 底边贴台面）。耐酸头罩——腐液章的可选奖励。
const REWARD_POS := Vector2(2436, 105)
const REWARD_KIND := "equipment"
const REWARD_REF := "scholar_cowl"
const SPITTER4_POS := Vector2(2464, 112)

## --- ④ 中殿长阶 ------------------------------------------------------------------
const STAIR_X := 2672.0
const STAIR_W := 64.0
const STAIR_Y := 336.0
const EAST_FLOOR_X := STAIR_X + STAIR_W
const STELE_POS := Vector2(2800, NAVE_Y)

## --- ⑤ 炉厅竞技场（Boss 在 Level01EastWing 里放；这里只铺地形） ----------------------------
const ARENA_CENTER_X := 3420.0
const STAGE_POS := Vector2(3256, STAGE_Y)
const STAGE_SIZE := Vector2(328, 16)
const PIER_W_POS := Vector2(3292, STAGE_Y - 32.0)
const PIER_E_POS := Vector2(3524, STAGE_Y - 32.0)
const PIER_SIZE := Vector2(24, 32)
## 两口炉龛喷火口（只在 Boss 战里喷）。离刽子手的身体 ≥ 40px，不压在近战站位上。
## 一阶段 COOL；二阶段（boss_phase_changed ≥ 2）HOT：休止更短、喷得更高。预警都 ≥ 0.7s。
const ARENA_VENT_OFFSET := 88.0
const ARENA_VENT_COOL := {"rest_time": 2.6, "telegraph_time": 0.9, "active_time": 0.6, "reach": 64.0}
const ARENA_VENT_HOT := {"rest_time": 1.5, "telegraph_time": 0.7, "active_time": 0.7, "reach": 76.0}

## 各处的装饰（接地装饰：键、脚点 x、脚点 y、色调）。键必须在 ALLOWED_DECOR 里。
const ALLOWED_DECOR := [
	"balustrade", "door_arch", "grave_cross", "statue", "stone_1", "stone_2", "stone_3", "stone_4",
	"rubble_dry", "rubble_dry_b", "rubble_dry_c", "rock_pile", "bones", "pipe_valve",
	"broken_machine", "girder_l", "girder_r", "warning_plate", "fence", "chain", "fire_vent",
	"life_remains", "skull_arch", "brick_house", "ruin_tower", "slab", "plate",
]
const DUSK_STONE := Color(0.78, 0.74, 0.82)
const DARK_FACADE := Color(0.5, 0.46, 0.5)
const WRECK_TINT := Color(0.62, 0.55, 0.52)

## [键, 脚点 x, 脚点 y, 色调]
const DECOR_ROWS := [
	# 巷：入口的残柱栏杆、倒下的碑、骨渣；楼座下垂着断链。
	["balustrade", 1264.0, GROUND, DUSK_STONE],
	["rubble_dry", 1296.0, GROUND, Color.WHITE],
	["stone_4", 1344.0, GROUND, Color.WHITE],
	["bones", 1472.0, GROUND, Color.WHITE],
	["balustrade", 1520.0, GROUND, DUSK_STONE],
	["rubble_dry_c", 1624.0, GROUND, Color.WHITE],
	# 工坊：砖屋立面是背景；前景是停了工的活。
	["fire_vent", 1708.0, GROUND, Color(0.78, 0.62, 0.48)],
	["broken_machine", 1784.0, GROUND, WRECK_TINT],
	["pipe_valve", 1888.0, GROUND, WRECK_TINT],
	["girder_r", 1960.0, GROUND, WRECK_TINT],
	# 休息龛：净化祠旁的守墓者石像与栏杆。
	["statue", 2072.0, GROUND, Color.WHITE],
	["balustrade", 2160.0, GROUND, DUSK_STONE],
	# 炉廊：两侧的炉口与碎石。
	["skull_arch", 2236.0, GROUND, Color(0.82, 0.7, 0.62)],
	["rock_pile", 2520.0, GROUND, Color.WHITE],
	["rubble_dry_b", 2552.0, GROUND, Color.WHITE],
	# 中殿：长阶两侧的栏杆，两排守墓者石像，误入的骨渣。
	["balustrade", 2628.0, GROUND, DUSK_STONE],
	["statue", 2848.0, NAVE_Y, Color.WHITE],
	["balustrade", 2990.0, NAVE_Y, DUSK_STONE],
	["statue", 3004.0, NAVE_Y, Color.WHITE],
	["rubble_dry", 2780.0, NAVE_Y, Color.WHITE],
	["bones", 2890.0, NAVE_Y, Color.WHITE],
	# 竞技场前后的栏杆与碎石。
	["balustrade", 3204.0, NAVE_Y, DUSK_STONE],
	["rubble_dry_b", 3236.0, NAVE_Y, Color.WHITE],
	["rubble_dry_c", 3610.0, NAVE_Y, Color.WHITE],
]

## 背景立面 / 地标（接地，画在最底层）：[键, 脚点 x, 脚点 y, 色调, 取图区域]。
## gh_brick_house.png 的左右 48px 是切图时带进来的碎砖，只取中间 308px 的屋身。
const BACKDROP_ROWS := [
	["brick_house", 1860.0, GROUND, DARK_FACADE, Rect2(48, 0, 308, 176)],
	["ruin_tower", 2040.0, GROUND, Color(0.52, 0.5, 0.58), Rect2()],
]

## 楼座 / 炉廊顶板下垂的断链：[挂点 x, 挂点 y]
const CHAIN_ROWS := [
	[1196.0, GALLERY_Y + 32.0],
	[1388.0, GALLERY_Y + 32.0],
	[1480.0, GALLERY_Y + 32.0],
	[2330.0, 240.0],
	[2420.0, 240.0],
	[2510.0, 240.0],
]

## 中殿甬道的落地火膛（TorchLight 的炉膛样式，和竞技场两座同一族），给长阶下面一点火光。
const NAVE_HEARTH_X: Array[float] = [2752.0, 2932.0]


func level_id() -> String:
	return "level01"


func east_limit() -> int:
	return EAST_LIMIT


func theme() -> String:
	return "graveyard"


## 东半的装饰在 SceneDetails / Level01Env 的同一套锈灰调色里（CathedralDecor 在
## Level01Parallax.PLAY_GRADE_FOLDERS 里）。装饰图层归 Level01EastWing 建。
func decor_layer(host: Node2D) -> Node2D:
	var layer := host.get_node_or_null("CathedralDecor") as Node2D
	if layer == null:
		layer = Node2D.new()
		layer.name = "CathedralDecor"
		layer.z_index = -3
		host.add_child(layer)
	return layer


## 墓园白名单之外，东半还能种工坊残骸 / 砖屋立面（SceneDetails.ALLOWED_KEYS 的同源清单）。
func prop_allowed(key: String) -> bool:
	return ALLOWED_DECOR.has(key)


## 唯一入口。Level01EastWing.build() 在放完持久化节点之后调它。
func build(host: Node2D) -> void:
	_build_terrain(host)
	_build_hazards(host)
	_build_props(host)
	_build_enemies(host)
	_build_decor(host)


func _build_terrain(host: Node2D) -> void:
	# ① 上层路的第三块浮石（前两块在 .tscn）+ 矮台东侧的垫阶。
	step(host, "HighRoadC", HIGH_ROAD_C_POS, HIGH_ROAD_W, "floating")
	platform(host, "PerchStep", PERCH_STEP_POS, PERCH_STEP_SIZE, "ground", false, true)
	# ② 地穴巷 → 工坊 → 休息龛 → 炉廊 → 锈门，一条连续的石板地（y=320）。
	floor_strip(host, "CryptFloor", GROUND_RIGHT_END, STAIR_X, "stone", false, false)
	# 楼座：厚 32 的石板，读作砖石楼板而不是悬浮石。
	platform(host, "GalleryW", GALLERY_W_POS, GALLERY_W_SIZE, "stone", false, false)
	platform(host, "GalleryE", GALLERY_E_POS, GALLERY_E_SIZE, "stone", false, false)
	platform(host, "GalleryPerch", GALLERY_PERCH_POS, GALLERY_PERCH_SIZE, "stone", false, false)
	# 第一根塌陷锈梁：iron_float 的锈铁皮和周围的石板不一样，一眼读出"这块不一样"。
	collapsing(host, "GalleryBeam", GALLERY_BEAM_POS, GALLERY_BEAM_W, "iron_float",
			{"shake_time": 0.8})
	# 炉廊顶板 + 余烬阁东段：塌陷梁 + 奖励台（EmberLedge 在 Level01EastWing）。
	platform(host, "VentDeck", VENT_DECK_POS, VENT_DECK_SIZE, "stone", false, false)
	collapsing(host, "EyrieBeam", EYRIE_BEAM_POS, EYRIE_BEAM_W, "iron_float")
	step(host, "EyrieEast", EYRIE_EAST_POS, EYRIE_EAST_W, "floating")
	# ④ 中殿长阶：第一级（EastFloor 在 Level01EastWing）。
	floor_strip(host, "StairA", STAIR_X, EAST_FLOOR_X, "stone", false, false, STAIR_Y)
	# ⑤ 竞技场：石台 + 两座掩体墩。
	platform(host, "ArenaStage", STAGE_POS, STAGE_SIZE, "stone", false, false)
	# 掩体墩 32 高，拆成上下两层 16px 叠石（体检把一整块 48px 的实心读成"压在中殿底面上的墙"；
	# 拆开后每一层都只是上一层的台阶，顶面坐标与碰撞外形不变）。
	for pier in [["PierW", PIER_W_POS], ["PierE", PIER_E_POS]]:
		var at: Vector2 = pier[1]
		platform(host, String(pier[0]) + "Base", at + Vector2(0.0, 16.0), Vector2(PIER_SIZE.x, 16.0),
				"stone", false, false)
		platform(host, String(pier[0]), at, Vector2(PIER_SIZE.x, 16.0), "stone", false, false)


## 炉廊的三口炉口（常开循环）。竞技场的两口由 Level01EastWing 建（只在 Boss 战里转）。
func _build_hazards(host: Node2D) -> void:
	for i in VENT_X.size():
		var props := VENT_PROPS.duplicate()
		props["phase"] = VENT_PHASE[i]
		cyclic(host, "FlameVent%d" % (i + 1), Vector2(VENT_X[i], GROUND), "flame", props)
	# 竞技场的两口炉龛喷火口：Level01EastWing 接管（平时熄着，只在 Boss 战里转）。
	# 不放首遇提示（炉廊的炉口先教过；进场演出里不弹教学）。
	for side in [-1.0, 1.0]:
		var vent_props := ARENA_VENT_COOL.duplicate()
		vent_props["phase"] = 0.0 if side < 0.0 else 0.25
		vent_props["hint_id"] = &""
		cyclic(host, "ArenaVentW" if side < 0.0 else "ArenaVentE",
				Vector2(ARENA_CENTER_X + side * ARENA_VENT_OFFSET, STAGE_Y), "flame", vent_props)


func _build_props(host: Node2D) -> void:
	nest(host, "EmberNestMid", NEST_MID_X)
	nest(host, "EmberNestForge", NEST_FORGE_X)
	var item := EquipmentCatalog.for_id(StringName(REWARD_REF))
	reward(host, "RewardEyrie", REWARD_POS, REWARD_KIND, REWARD_REF,
			item.display_name if item != null else "")


## 敌人全放在 Props 下：和 Spitter1 / Scrapper1 同一父节点，TetherDrop_* 的存档路径一致。
func _build_enemies(host: Node2D) -> void:
	# 伏击巷：装甲碎铁犬（头顶蓝菱形）冲锋，齿盾卫守在闸门前；一只被惊动，另一只同时警觉。
	_spawn(host, "Scrapper2", "scrapper", LANE_SCRAPPER_POS,
			{"variant": &"armored_scrapper", "patrol_range": 24.0, "alert_radius": 150.0})
	# 楼座交叉火力：压板东侧一低一高两只（Spitter2 在 .tscn 里，位置见 SPITTER2_POS）。
	_spawn(host, "Spitter3", "spitter", SPITTER3_POS, {"aggro_range": GALLERY_SPITTER_AGGRO})
	# 余烬阁的奖励台：一只喷吐者守着梁的另一头。
	_spawn(host, "Spitter4", "spitter", SPITTER4_POS, {"aggro_range": 170.0})


func _spawn(host: Node2D, enemy_name: String, kind: String, pos: Vector2,
		overrides: Dictionary = {}) -> Node2D:
	var path: String = ENEMY_SCENES.get(kind, "")
	if path == "" or not ResourceLoader.exists(path):
		push_warning("Level01EastLayout: enemy kind '%s' unavailable (%s)" % [kind, enemy_name])
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var e := scene.instantiate() as Node2D
	e.name = enemy_name
	e.position = pos
	for key in overrides:
		e.set(key, overrides[key])
	group(host, "Props").add_child(e)
	return e


func _build_decor(host: Node2D) -> void:
	for row in BACKDROP_ROWS:
		var region: Rect2 = row[4]
		var feet := Vector2(float(row[1]), float(row[2]))
		if region.has_area():
			_facade(host, String(row[0]), feet, region, row[3] as Color)
		else:
			prop(host, String(row[0]), feet, 1.0, row[3] as Color, -2)
	for row in DECOR_ROWS:
		prop(host, String(row[0]), Vector2(float(row[1]), float(row[2])), 1.0, row[3] as Color)
	for row in CHAIN_ROWS:
		hanging(host, "chain", Vector2(float(row[0]), float(row[1])), WRECK_TINT)
	for x in NAVE_HEARTH_X:
		_nave_hearth(host, x)


## 带取图区域的接地背景（砖屋立面）。和 prop() 同一套接地约定（脚点元数据、最后一行不透明像素
## 坐在脚点上），只是不画切图时带进来的碎边。区域必须从第 0 行画到贴图底（脚点按贴图底算）。
func _facade(host: Node2D, key: String, feet: Vector2, region: Rect2, tint: Color) -> Sprite2D:
	var path := PropCatalog.path_for(key, theme())
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = false
	spr.region_enabled = true
	spr.region_rect = region
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var pinned := feet.round()
	var opaque_bottom := Level01Env.opaque_bottom_px(tex)
	var land := float(opaque_bottom + 1) - region.position.y
	spr.position = Vector2(roundf(pinned.x - region.size.x * 0.5), pinned.y - land)
	spr.modulate = tint
	spr.z_index = -2
	spr.set_meta("feet", pinned)
	spr.set_meta("foot_anchor", "bottom_center")
	spr.set_meta("opaque_bottom", opaque_bottom)
	spr.set_meta("prop_key", key)
	spr.set_meta("prop_theme", theme())
	spr.add_to_group("grounded")
	decor_layer(host).add_child(spr)
	return spr


## 落地火膛：gh_furnace 32×96，节点原点在贴图中心（和竞技场火膛同一约定）。
func _nave_hearth(host: Node2D, x: float) -> TorchLight:
	var scene := load("res://scenes/world/TorchLight.tscn") as PackedScene
	if scene == null:
		return null
	var hearth := scene.instantiate() as TorchLight
	hearth.name = "NaveHearth%d" % int(x)
	hearth.style = "furnace"
	hearth.light_color = Color(1.0, 0.62, 0.33)
	hearth.base_energy = 0.55
	hearth.light_radius = 80.0
	hearth.position = Vector2(x, NAVE_Y - 96.0)
	hearth.set_meta("feet", Vector2(x, NAVE_Y))
	hearth.add_to_group("grounded")
	# 灯与墙板分开管：CathedralDecor 里的 TorchLight 被「墙板落在地面上」的审计当作壁炬计数。
	var lights := host.get_node_or_null("NaveLights") as Node2D
	if lights == null:
		lights = Node2D.new()
		lights.name = "NaveLights"
		host.add_child(lights)
	lights.add_child(hearth)
	return hearth
