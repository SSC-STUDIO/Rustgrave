extends ChapterLayout
## 锈墓・拾 — 炉心深处（终关）。第一关点燃的那颗残芯真正的所在；
## 梦魇——炉火熄灭时最后一匹没被熔掉的战马——守在这里。
##
## 玩法变化（平地 Boss 竞技场）：入口回廊是跳石与火骷髅，门前厅是安全巢；
## 锈门之后 1200px 全平，没有坑、没有台阶，只有两端的窄高台，逼玩家在
## 梦魇的冲锋里用翻滚、弹反与钩锁处理空间。
## 可选支路：入口回廊上方的守夜台（钩锁），碑文「守」讲清门后的两个选择。
##
## 结构（地面 y=320，一跳台阶 ≤32px）：
##   ① 入口回廊 0–800     余烬巢、碑文、路牌、幽魂 ×2 + 火骷髅 ×2、熔渣河（三块浮石）
##   ①b 加长回廊 800–1440 第二道熔渣河（三块浮石）+ 低空火骷髅；炉心回廊再长一屏
##   ② 门前厅 1440–1740   Boss 前的余烬巢（距竞技场门 60px）、第二块碑、锈门（热锻）
##   ③ 竞技场 1740–2940   1200px 连续平地，无坑无台阶；两端各一块 48×32 的小高台；
##      梦魇 Boss + BossArena（统一 boss() 装配：clamp / 锁门 / 相机 limit / 清场）
##   ④ 终局门 2940–3200   炉心祭坛（背景）、炉心之门（需 nightmare_dead；结局字幕后回标题）

const EAST_LIMIT := 3200
const ENTRY_SPAWN := Vector2(96, 300)
const CEILING_Y := -32.0

## 炉心是玄武渣岩（basalt），比熔渣深渊再压暗一档、偏冷一点：终关的地面是焦黑的，
## 光只来自熔渣和炉火。早先把紫石板乘到过曝的赭红，整关像一块红砖。
const TONE := Color(0.9, 0.82, 0.78)
## 浮石与两端高台亮一档：脚要落的地方得从暗底和熔渣里跳出来。
const STONE_TONE := Color(1.12, 1.0, 0.94)
## 熔渣：污泥 (9,32,30) → 橙红，浮沫 (39,112,49) 撞顶成亮橙黄，读成会发光的渣面。
const SLAG_TINT := Color(18.0, 1.6, 0.5)
## 壁炬 / 柱子 / 祭坛的墙板是墓园紫石，压成赭红色石。
const TORCH_TINT := Color(1.4, 0.8, 0.55)
const PLATE_TINT := Color(1.5, 0.85, 0.5, 0.9)
const ALTAR_TINT := Color(1.6, 0.95, 0.6, 0.92)
## 历史机械件（Kenney 派生的 1x 玄武岩族副本）：压成焦黑铁色，和祭坛的红石分开。
const MACHINE_TINT := Color(0.9, 0.72, 0.62)

## ① 入口回廊
const NEST_GATE_X := 176.0
const STELE_A_POS := Vector2(264, 320)
const WAYMARK_POS := Vector2(352, 320)
## 熔渣河：坑底 352（比岸低 32，掉进去一跳爬得出）、液面 336..368、三块浮石。
const SLAG_X0 := 480.0
const SLAG_X1 := 720.0
const SLAG_BED_Y := 352.0
## [name, pos, width] —— 岸 320 → 288 → 264 → 288 → 岸 320，横跨都是 16/32px。
const SLAG_STONES: Array = [
	["SlagStone1", Vector2(496, 288), 48.0],
	["SlagStone2", Vector2(576, 264), 48.0],
	["SlagStone3", Vector2(656, 288), 48.0],
]

## ①b 加长回廊：第二道熔渣河，和第一道同一条单跳链（岸 320 → 288 → 264 → 288 → 岸）。
const SLAG2_X0 := 960.0
const SLAG2_X1 := 1120.0
const SLAG2_STONES: Array = [
	["Slag2Stone1", Vector2(976, 288), 48.0],
	["Slag2Stone2", Vector2(1048, 264), 48.0],
	["Slag2Stone3", Vector2(1112, 288), 48.0],
]

## ② 门前厅
## Boss 前巢挪到竞技场门（1724）前 60px、竞技场左界（1740）前 76px（契约 ≤80px）。
const NEST_ARENA_X := 1664.0
const STELE_B_POS := Vector2(1580, 320)
## 锈门左上角；门 16×64，底在 320，脚点 (1732, 320)。
const ARENA_GATE_POS := Vector2(1724, 256)
## 回廊敌人的活动边界：只追到门前厅西侧，绝不进竞技场。
const CORRIDOR_ENEMY_MAX_X := 1580.0

## ③ 竞技场
const ARENA_X0 := 1740.0
const ARENA_X1 := 2940.0
## 两端的小高台：48 宽 32 高，坐在地面上，顶在 288。
const PERCH_SIZE := Vector2(48, 32)
const PERCH_WEST_POS := Vector2(1792, 288)
const PERCH_EAST_POS := Vector2(2860, 288)
const BOSS_POS := Vector2(2640, 320)

## ④ 终局门
const ALTAR_FEET := Vector2(2984, 320)
const EXIT_X := 3080.0

const EXIT_LABEL := "炉心之门"
const EXIT_FLAG := "game_complete"
const EXIT_REQUIRES := "nightmare_dead"
const EXIT_LOCKED_PROMPT := "梦魇还在喘。门不开。"
## 可选支路：入口回廊上方的守夜台。从巢旁的地面起钩（152px 索距），
## 落台在锚点下方 72px；没有钩锁时落差 128px，跳不上去。
const VIGIL_DECK := Rect2(160, 192, 96, 16)
const HOOK_VIGIL_POS := Vector2(208, 120)
const STELE_VIGIL_POS := Vector2(232, 192)

## [name, kind, pos]；落地敌人给脚点，飞行/穿墙敌人给悬停中心。
## 回廊敌人的活动限制在门前厅西侧，余烬巢和梦魇竞技场不受前一战追击干扰。
## 幽魂一只守第一道渣河西岸、一只守东岸落点；火骷髅低空守着两道渣河的渡口。
const ENEMIES: Array = [
	["Ghost1", "ghost", Vector2(424, 232)],
	["FireSkull1", "fire_skull", Vector2(560, 192)],
	["FireSkull2", "fire_skull", Vector2(688, 176)],
	["Ghost2", "ghost", Vector2(816, 236)],
	["FireSkull3", "fire_skull", Vector2(1024, 192)],
	["FireSkull4", "fire_skull", Vector2(1240, 208)],
	["Ghost3", "ghost", Vector2(1360, 236)],
	["Nightmare", "nightmare_boss", BOSS_POS],
]

## 装饰。竞技场里只有壁炬和背景柱子，不放任何落地装饰，免得误导落点。
## 壁炬板 64 宽、柱子 114 宽，两者横向错开——柱子在壁炬前面一层，叠上会把火吞掉。
const TORCHES: Array = [316.0, 848.0, 1264.0, 1584.0, 1800.0, 1880.0, 2224.0, 2568.0, 2880.0, 2904.0, 3120.0]
const COLUMNS: Array = [64.0, 1900.0, 2340.0, 2780.0]
## 十字形碎石是墓园符号，炉心地面只用普通碎渣。
const RUBBLE: Array = [120.0, 792.0, 1240.0, 1520.0, 3020.0]
const RUBBLE_KEYS: Array = ["rubble_dry", "rubble_dry_c"]
const SKULL_COLUMN_X := 776.0


func level_id() -> String:
	return "level10"


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


func theme() -> String:
	return "forge_core"


func motes() -> String:
	return "cinders"


## 炉心最深处：不下雨，只有被炉膛抽着走的余烬风，和一层压得人喘不过气的热雾。
func weather_recipe() -> Dictionary:
	return {
		"allowed": [WorldClock.Weather.EMBER_WIND, WorldClock.Weather.HAZE],
		"weights": {"*": {"ember_wind": 5, "haze": 3}},
		"hold": Vector2(300.0, 520.0),
		"intensity": Vector2(0.7, 1.0),
	}


func build(host: Node2D) -> void:
	_build_terrain(host)
	_build_props(host)
	_build_enemies(host)
	_build_decor(host)
	finish(host)


func _build_terrain(host: Node2D) -> void:
	floor_strip(host, "FloorEntry", 0.0, SLAG_X0, "basalt", false, true, FLOOR_Y, TONE)
	# 熔渣河手工铺（toxin_pit 不吃 tone，坑底会露出一截青苔色）。
	platform(host, "SlagBed", Vector2(SLAG_X0, SLAG_BED_Y),
			Vector2(SLAG_X1 - SLAG_X0, FLOOR_Y + 80.0 - SLAG_BED_Y), "basalt", false, false, TONE)
	toxin(host, "SlagPool", Vector2(SLAG_X0, SLAG_BED_Y - 16.0), Vector2(SLAG_X1 - SLAG_X0, 32.0), SLAG_TINT)
	for s in SLAG_STONES:
		step(host, String(s[0]), s[1], float(s[2]), "basalt_float", STONE_TONE)
	# 守夜台：悬在入口回廊上方，只有钩锁能上；不在竞技场里，不误导 Boss 落点。
	step(host, "VigilDeck", VIGIL_DECK.position, VIGIL_DECK.size.x, "basalt_float", STONE_TONE)
	# ①b 加长回廊：第二道熔渣河，和第一道同一套单跳渡石。
	floor_strip(host, "FloorHallA", SLAG_X1, SLAG2_X0, "basalt", true, true, FLOOR_Y, TONE)
	platform(host, "Slag2Bed", Vector2(SLAG2_X0, SLAG_BED_Y),
			Vector2(SLAG2_X1 - SLAG2_X0, FLOOR_Y + 80.0 - SLAG_BED_Y), "basalt", false, false, TONE)
	toxin(host, "Slag2Pool", Vector2(SLAG2_X0, SLAG_BED_Y - 16.0),
			Vector2(SLAG2_X1 - SLAG2_X0, 32.0), SLAG_TINT)
	for s in SLAG2_STONES:
		step(host, String(s[0]), s[1], float(s[2]), "basalt_float", STONE_TONE)
	# 门前厅 + 竞技场 + 终局门共用一块地：竞技场必须是连续平地，Boss 来回冲锋。
	floor_strip(host, "FloorHallB", SLAG2_X1, float(EAST_LIMIT), "basalt", true, false, FLOOR_Y, TONE)
	platform(host, "PerchWest", PERCH_WEST_POS, PERCH_SIZE, "basalt", true, true, STONE_TONE)
	platform(host, "PerchEast", PERCH_EAST_POS, PERCH_SIZE, "basalt", true, true, STONE_TONE)
	enclose(host, "basalt", CEILING_Y, -1.0, 0.0, TONE)


func _build_props(host: Node2D) -> void:
	nest(host, "EmberNestGate", NEST_GATE_X)
	nest(host, "EmberNestArena", NEST_ARENA_X)
	_stele(host, "SteleNightmare", STELE_A_POS)
	_stele(host, "SteleCompact", STELE_B_POS)
	waymark(host, WAYMARK_POS, "炉心")
	rusty_gate(host, "ArenaGate", ARENA_GATE_POS)
	# 支路：入口回廊的守夜台。只有钩锁能读，碑文把门后的选择先摆在玩家面前。
	hook(host, "HookVigil", HOOK_VIGIL_POS)
	_stele(host, "SteleVigil", STELE_VIGIL_POS)
	var door := exit_door(host, EXIT_X, ChapterText.exit_label_of(level_id()),
			ChapterText.exit_captions_of(level_id()), EXIT_FLAG, "",
			FLOOR_Y, EXIT_REQUIRES, EXIT_LOCKED_PROMPT)
	door.ending_choice = true
	door.give_captions = ChapterText.ending_lines_of("give")
	door.keep_captions = ChapterText.ending_lines_of("keep")


func _build_enemies(host: Node2D) -> void:
	for e in ENEMIES:
		if String(e[1]) == "nightmare_boss":
			# 统一 boss() 装配：Boss + BossArena（clamp / 锁门 / 相机 limit / 清场）；
			# 场景存在（本仓已交付）才锁终局门，`nightmare_dead` 后清场解锁。
			if TrialRun.forces_boss_spawn() or not SaveData.has_flag(EXIT_REQUIRES):
				boss(host, String(e[0]), String(e[1]), e[2], ARENA_X0, ARENA_X1)
		else:
			enemy(host, String(e[0]), String(e[1]), e[2],
					{"arena_left": 300.0, "arena_right": CORRIDOR_ENEMY_MAX_X})


func _build_decor(host: Node2D) -> void:
	for x in TORCHES:
		torch(host, float(x), FLOOR_Y, TORCH_TINT)
	# 炉心支柱用殿里那根石柱，压成赭石。平滑工字梁和终关的像素墙不是一套。
	# 1x 整数缩放（0.9 会把石柱的像素拉成半格）。
	for x in COLUMNS:
		prop(host, "column", Vector2(float(x), FLOOR_Y), 1.0, PLATE_TINT)
	prop(host, "skull_column", Vector2(SKULL_COLUMN_X, FLOOR_Y), 1.0, PLATE_TINT)
	_altar(host, ALTAR_FEET, ALTAR_TINT)
	# 入口回廊的炉前机械：把渣送进炉心的那台坏了，阀座还开着。竞技场里不放。
	prop(host, "broken_machine", Vector2(420, FLOOR_Y), 1.0, MACHINE_TINT)
	prop(host, "pipe_valve", Vector2(452, FLOOR_Y), 1.0, MACHINE_TINT)
	# ①b 加长回廊：第二道渣河旁的送渣机械与警示牌，读得出「这里也坏在一半」。
	prop(host, "broken_machine", Vector2(1400, FLOOR_Y), 1.0, MACHINE_TINT)
	prop(host, "fire_vent", Vector2(1168, FLOOR_Y), 1.0, MACHINE_TINT)
	prop(host, "warning_plate", Vector2(928, FLOOR_Y), 1.0, TONE)
	for i in range(RUBBLE.size()):
		prop(host, RUBBLE_KEYS[i % RUBBLE_KEYS.size()], Vector2(float(RUBBLE[i]), FLOOR_Y), 1.0, TONE)


## 炉心祭坛：终局门旁的背景墙板，残芯的所在。顶 64px 是素墙，走 RuinPlate 塌成残垣，
## 不然 128×192 的板子在墙前是一块硬边矩形。feet 元数据 + grounded 组让体检照常查脚。
func _altar(host: Node2D, feet: Vector2, tint: Color) -> Node2D:
	var path: String = DECOR["altar"]
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	var root := Node2D.new()
	root.name = "ForgeAltar"
	root.position = Vector2(feet.x - float(tex.get_width()) * 0.5, feet.y - float(tex.get_height()))
	root.modulate = tint
	root.set_meta("feet", feet)
	root.add_to_group("grounded")
	decor_layer(host).add_child(root)
	RuinPlate.build(root, tex, root.position)
	return root
