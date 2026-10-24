extends ChapterLayout
## 终章：下探送渣槽与低空回廊 → 环形大殿 → 原炉心门的两种回答。

const CORE_PULSE := preload("res://scripts/levels/chapters/level10_core_pulse.gd")
const EAST_LIMIT := 4160
const ENTRY_SPAWN := Vector2(96, 268)
const CEILING_Y := -96.0
const TONE := Color(0.9, 0.82, 0.78)
const STONE_TONE := Color(1.12, 1.0, 0.94)
const TORCH_TINT := Color(1.4, 0.8, 0.55)
const PLATE_TINT := Color(1.5, 0.85, 0.5, 0.9)
const ALTAR_TINT := Color(1.6, 0.95, 0.6, 0.92)
const MACHINE_TINT := Color(0.9, 0.72, 0.62)
const NEST_GATE_X := 176.0
const NEST_COOLING_X := 1168.0
const NEST_ARENA_X := 2176.0
const STELE_A_POS := Vector2(264, 288)
const STELE_B_POS := Vector2(2048, 320)
const ARENA_GATE_POS := Vector2(2224, 256)
const CORRIDOR_ENEMY_MAX_X := 1920.0
const ARENA_X0 := 2240.0
const ARENA_X1 := 3968.0
const BOSS_POS := Vector2(3504, 320)
const ALTAR_FEET := Vector2(4016, 320)
const EXIT_X := 4080.0
const EXIT_FLAG := "game_complete"
const EXIT_REQUIRES := "nightmare_dead"
const EXIT_LOCKED_PROMPT := "梦魇还在喘。门不开。"
const VIGIL_DECK := Rect2(160, 160, 160, 16)
const HOOK_VIGIL_POS := Vector2(240, 64)
const STELE_VIGIL_POS := Vector2(208, 160)
const VIGIL_REWARD_FEET := Vector2(288, 160)

## [name, west, east, top]，主路两次下探且各有固定32px回收阶梯。
const FLOORS: Array = [
	["FloorEntry", 0.0, 416.0, 288.0],
	["SlagBed", 416.0, 928.0, 352.0],
	["CoolingStep", 928.0, 992.0, 320.0],
	["FloorHallA", 992.0, 1408.0, 288.0],
	["PassageStep", 1408.0, 1472.0, 320.0],
	["Slag2Bed", 1472.0, 1904.0, 352.0],
	["AscendA", 1904.0, 1968.0, 320.0],
	["FloorHallB", 1968.0, 2240.0, 320.0],
	["ArenaFloor", 2240.0, 4160.0, 320.0],
]
const STEPS: Array = [
	["ReturnEnd", Vector2(1088, 224), 112.0],
	["ReturnB", Vector2(1232, 224), 112.0],
	["ReturnC", Vector2(1376, 224), 112.0],
	["ReturnD", Vector2(1520, 224), 112.0],
	["ReturnE", Vector2(1664, 224), 112.0],
	["ReturnStairHigh", Vector2(1776, 256), 64.0],
	# End before AscendA's jump run-up: a 64px canopy traps the knight's head.
	["ReturnStairMid", Vector2(1840, 288), 32.0],
	["ReturnStairLow", Vector2(1904, 320), 64.0],
	["RingStairWestLow", Vector2(2288, 288), 64.0],
	["RingStairWestMid", Vector2(2352, 256), 64.0],
	["RingGalleryWest", Vector2(2416, 224), 288.0],
	["RingGalleryInnerWest", Vector2(2768, 224), 288.0],
	["RingGalleryInnerEast", Vector2(3120, 224), 288.0],
	["RingGalleryEast", Vector2(3472, 224), 288.0],
	["RingStairEastMid", Vector2(3760, 256), 64.0],
	["RingStairEastLow", Vector2(3824, 288), 64.0],
]
const PILLARS: Array = [Vector2(2544, 192), Vector2(2848, 192), Vector2(3264, 192), Vector2(3568, 192)]
const CORE_DAIS := Rect2(2992, 192, 192, 32)
const PULSE_X: Array = [2768.0, 3056.0, 3344.0]

## 原始种类的三组遭遇：渡口、碑廊、低空双头；警戒和高度变化代替不匹配的重盾变体。
const ENEMIES: Array = [
	["Ghost1", "ghost", Vector2(864, 288), {"wake_range": 80.0, "arena_left": 784.0, "arena_right": 928.0}],
	["FireSkull1", "fire_skull", Vector2(816, 272), {"aggro_range": 72.0, "bob_amp": 8.0, "arena_left": 768.0, "arena_right": 928.0}],
	["Ghost2", "ghost", Vector2(1360, 208), {"wake_range": 96.0, "arena_left": 1248.0, "arena_right": 1440.0}],
	["FireSkull2", "fire_skull", Vector2(1296, 240), {"aggro_range": 88.0, "bob_amp": 8.0, "arena_left": 1248.0, "arena_right": 1440.0}],
	["Ghost3", "ghost", Vector2(1776, 320), {"wake_range": 104.0, "arena_left": 1520.0, "arena_right": 1904.0}],
	["FireSkull3", "fire_skull", Vector2(1648, 280), {"aggro_range": 96.0, "alert_radius": 176.0, "bob_amp": 8.0, "arena_left": 1520.0, "arena_right": 1904.0}],
	["FireSkull4", "fire_skull", Vector2(1808, 272), {"aggro_range": 96.0, "alert_radius": 176.0, "bob_amp": 8.0, "arena_left": 1520.0, "arena_right": 1904.0}],
	["GhostVigil", "ghost", Vector2(272, 112), {"wake_range": 64.0, "arena_left": 160.0, "arena_right": 320.0}],
]
const TORCHES: Array = [Vector2(96, 288), Vector2(400, 288), Vector2(944, 320), Vector2(1168, 288),
	Vector2(1440, 320), Vector2(1936, 320), Vector2(2160, 320), Vector2(2448, 320),
	Vector2(2736, 320), Vector2(3088, 320), Vector2(3440, 320), Vector2(3792, 320), Vector2(4128, 320)]
const PROPS: Array = [
	["rubble_dry", Vector2(120, 288)], ["pipe_valve", Vector2(368, 288)],
	["rubble_dry_c", Vector2(752, 352)], ["broken_machine", Vector2(896, 352)],
	["plate", Vector2(1056, 288)], ["warning_plate", Vector2(1376, 288)],
	["fire_vent", Vector2(1568, 352)], ["rubble_dry_c", Vector2(1840, 352)],
	["broken_machine", Vector2(2000, 320)], ["rubble_dry", Vector2(2208, 320)],
]


func level_id() -> String:
	return "level10"


func title() -> String:
	return ChapterText.title_of(level_id())


func wake_line() -> String:
	return ChapterText.wake_of(level_id())


func entry_spawn() -> Vector2:
	return ENTRY_SPAWN


func east_limit() -> int:
	return EAST_LIMIT


func camera_top() -> int:
	return -128


func theme() -> String:
	return "forge_core"


func motes() -> String:
	return "cinders"


func weather_recipe() -> Dictionary:
	return {"allowed": [WorldClock.Weather.EMBER_WIND, WorldClock.Weather.HAZE],
		"weights": {"*": {"ember_wind": 5, "haze": 3}}, "hold": Vector2(300.0, 520.0),
		"intensity": Vector2(0.7, 1.0)}


func _stele(host: Node2D, node_name: String, pos: Vector2) -> void:
	var entry := ChapterText.stele_of(level_id(), node_name)
	stele(host, node_name, pos, String(entry.get("title", "")), String(entry.get("text", "")))


func build(host: Node2D) -> void:
	_build_terrain(host)
	_build_props(host)
	for e in ENEMIES:
		enemy(host, String(e[0]), String(e[1]), e[2], e[3])
	_build_boss(host)
	_build_decor(host)
	finish(host)


func _build_terrain(host: Node2D) -> void:
	for f in FLOORS:
		floor_strip(host, String(f[0]), float(f[1]), float(f[2]), "basalt", true, true, float(f[3]), TONE)
	for s in STEPS:
		step(host, String(s[0]), s[1], float(s[2]), "basalt_float", STONE_TONE)
	step(host, "VigilDeck", VIGIL_DECK.position, VIGIL_DECK.size.x, "basalt_float", STONE_TONE)
	for i in PILLARS.size():
		platform(host, "PillarSeat%d" % (i + 1), PILLARS[i], Vector2(64, 32), "basalt", true, true, STONE_TONE)
	platform(host, "CoreDais", CORE_DAIS.position, CORE_DAIS.size, "basalt", true, true, STONE_TONE)
	# 从地面无法直接跳越的原热锻门；门楣底240与门顶256之间只留16px。
	platform(host, "ArenaGateLintel", Vector2(2192, 192), Vector2(80, 48), "basalt", true, true, TONE)
	enclose(host, "basalt", CEILING_Y, -1.0, 0.0, TONE)


func _build_props(host: Node2D) -> void:
	nest(host, "EmberNestGate", NEST_GATE_X, 288)
	nest(host, "EmberNestCooling", NEST_COOLING_X, 288)
	nest(host, "EmberNestArena", NEST_ARENA_X, 320)
	_stele(host, "SteleNightmare", STELE_A_POS)
	_stele(host, "SteleCompact", STELE_B_POS)
	waymark(host, Vector2(336, 288), "炉心")
	waymark(host, Vector2(1888, 352), "回炉")
	rusty_gate(host, "ArenaGate", ARENA_GATE_POS)
	hook(host, "HookVigil", HOOK_VIGIL_POS)
	_stele(host, "SteleVigil", STELE_VIGIL_POS)
	reward(host, "RewardVigil", VIGIL_REWARD_FEET - Vector2(0, 7), "equipment", "iron_carapace",
		EquipmentCatalog.iron_carapace().display_name)
	for row in [["SlagTeachWest", Vector2(528, 352), 0.0], ["SlagTeachEast", Vector2(656, 352), 0.45],
		["SlagHallWest", Vector2(1504, 352), 0.2], ["SlagHallEast", Vector2(1712, 352), 0.65]]:
		cyclic(host, String(row[0]), row[1], "slag", {"reach": 56.0, "thick": 24.0,
			"rest_time": 2.8, "telegraph_time": 0.9, "active_time": 0.7, "phase": float(row[2])})
	var door := exit_door(host, EXIT_X, ChapterText.exit_label_of(level_id()),
		ChapterText.exit_captions_of(level_id()), EXIT_FLAG, "", FLOOR_Y, EXIT_REQUIRES, EXIT_LOCKED_PROMPT)
	door.ending_choice = true
	door.give_captions = ChapterText.ending_lines_of("give")
	door.keep_captions = ChapterText.ending_lines_of("keep")


func _build_boss(host: Node2D) -> void:
	if not TrialRun.forces_boss_spawn() and SaveData.has_flag(EXIT_REQUIRES):
		return
	var nightmare := boss(host, "Nightmare", "nightmare_boss", BOSS_POS, ARENA_X0, ARENA_X1)
	if nightmare == null:
		return
	var arena := boss_arena(host, "Nightmare") as BossArena
	for i in PULSE_X.size():
		var pulse := CORE_PULSE.new()
		pulse.name = "CorePulse%d" % (i + 1)
		pulse.position = Vector2(float(PULSE_X[i]), 320)
		pulse.skin = "shock"
		pulse.thick = 288.0
		pulse.reach = 16.0
		pulse.rest_time = 4.5
		pulse.telegraph_time = 0.9
		pulse.active_time = 0.8
		pulse.hint_id = &"shock"
		group(host, "Props").add_child(pulse)
		pulse.bind_encounter(nightmare, arena, i)


func _build_decor(host: Node2D) -> void:
	for feet in TORCHES:
		torch(host, feet.x, feet.y, TORCH_TINT)
	for p in PROPS:
		prop(host, String(p[0]), p[1], 1.0, MACHINE_TINT)
	for feet in PILLARS:
		prop(host, "column", feet + Vector2(32, 0), 1.0, PLATE_TINT)
	_altar(host, Vector2(3088, 192), ALTAR_TINT, "CoreAltar")
	_altar(host, ALTAR_FEET, ALTAR_TINT, "ForgeAltar")


func _altar(host: Node2D, feet: Vector2, tint: Color, node_name: String) -> Node2D:
	var path: String = DECOR["altar"]
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	var root := Node2D.new()
	root.name = node_name
	root.position = Vector2(feet.x - float(tex.get_width()) * 0.5, feet.y - float(tex.get_height()))
	root.modulate = tint
	root.set_meta("feet", feet)
	root.add_to_group("grounded")
	decor_layer(host).add_child(root)
	RuinPlate.build(root, tex, root.position)
	return root
