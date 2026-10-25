extends ChapterLayout
## 熔渣喷泉宽岛 → 低空火骷髅廊 → 高台回巢环线 → 第二节奏渣河。

const EAST_LIMIT := 4200
const CEILING_Y := -32.0
const PIT_DEPTH := 32.0
const ENTRY_SPAWN := Vector2(96, 300)
const GROUND_TONE := Color(1.0, 0.8, 0.6)
const SLAG_TINT := Color(1.22, 0.94, 0.74)
const SLAG_RAMP := [Color("#100a08"), Color("#2c1b12"), Color("#503125"), Color("#7a4c34"), Color("#a3714f")]
const SLAG_VAPOR := Color(0.85, 0.55, 0.34)
const LIFT_TONE := Color(1.0, 0.82, 0.62)
const TORCH_TINT := Color(1.0, 0.75, 0.55)
const VINE_TINT := Color(0.45, 0.22, 0.1, 0.85)
const GIRDER_TINT := Color(0.86, 0.7, 0.58)
const FLOORS: Array = [
	["FloorA", 0.0, 416.0, 320.0], ["FloorB", 1056.0, 1664.0, 320.0],
	["Climb1", 1664.0, 1712.0, 288.0], ["Climb2", 1712.0, 1760.0, 256.0],
	["Climb3", 1760.0, 1808.0, 224.0], ["Climb4", 1808.0, 1856.0, 192.0],
	["Climb5", 1856.0, 1904.0, 160.0], ["FloorC", 1904.0, 2400.0, 128.0],
	["FloorE", 2400.0, 2848.0, 320.0], ["FloorG", 3424.0, 3600.0, 320.0],
	["FloorI", 3664.0, 4200.0, 320.0],
]
const PITS: Array = [["SlagA", 416.0, 1056.0], ["SlagD", 2848.0, 3424.0], ["SlagE", 3600.0, 3664.0]]
const ISLANDS: Array = [
	["FountainIslandA", Vector2(464, 304), 224.0], ["FountainIslandB", Vector2(744, 304), 264.0],
	["FountainIslandC", Vector2(2896, 304), 208.0], ["FountainIslandD", Vector2(3160, 304), 216.0],
]
## [name, feet, supporting island, rest, warn, active, phase].
const FOUNTAINS: Array = [
	["FountainLesson", Vector2(576, 304), "FountainIslandA", 2.8, 0.9, 0.8, 0.0],
	["FountainAnswer", Vector2(872, 304), "FountainIslandB", 2.8, 0.9, 0.8, 0.5],
	["FountainFastA", Vector2(3000, 304), "FountainIslandC", 1.5, 0.6, 1.2, 0.0],
	["FountainFastB", Vector2(3264, 304), "FountainIslandD", 1.5, 0.6, 1.2, 0.5],
]
const NESTS: Array = [
	["EmberNestStart", 176.0, 320.0], ["EmberNestRiver", 1120.0, 320.0],
	["EmberNestMid", 1920.0, 128.0], ["EmberNestGate", 2608.0, 320.0],
	["EmberNestFountain", 3504.0, 320.0], ["EmberNestShell", 4048.0, 320.0],
]
const VENT_LEDGE := Rect2(672, 160, 128, 16)
const HOOK_VENT_POS := Vector2(736, 104)
const STELE_VENT_POS := Vector2(768, 160)
const REWARD_VENT_FEET := Vector2(704, 160)
const RETURN_LEDGE := Rect2(1280, 64, 1120, 16)
const RETURN_LIFT_POS := Vector2(2400, 128)
const RETURN_LIFT_TRAVEL := Vector2(0, -64)
const RETURN_LIFT_PERIOD := 8.0
const PLATE_FEET := Vector2(2056, 128)
const DOOR_POS := Vector2(2688, 256)
const GATE_POS := Vector2(2800, 256)
const EXIT_X := 4120.0
const STELE_SLAG_POS := Vector2(256, 320)
const STELE_QUENCH_POS := Vector2(2480, 320)
const REWARD_POS := Vector2(3968, 249)
const REWARD_KIND := "equipment"
const REWARD_REF := "toxic_ward"
const ENEMIES: Array = [
	# Low-air corridor is between the two fountain rivers; both nests stay outside its patrol.
	["FireSkull1", "fire_skull", Vector2(1352, 240), {"aggro_range": 96.0, "patrol_range": 16.0, "arena_left": 1280.0, "arena_right": 1648.0}],
	["FireSkull2", "fire_skull", Vector2(1432, 224), {"aggro_range": 96.0, "patrol_range": 16.0, "arena_left": 1280.0, "arena_right": 1648.0}],
	["FireSkull3", "fire_skull", Vector2(1512, 240), {"aggro_range": 96.0, "patrol_range": 16.0, "arena_left": 1280.0, "arena_right": 1648.0}],
	["FireSkull4", "fire_skull", Vector2(1592, 224), {"aggro_range": 96.0, "patrol_range": 16.0, "arena_left": 1280.0, "arena_right": 1648.0}],
	# High foundry shelf: an armoured rush, a shooter and a rear apparition.
	["Scrapper1", "scrapper", Vector2(2112, 128), {"variant": &"armored_scrapper", "aggro_range": 128.0, "patrol_range": 16.0, "lose_range": 160.0}],
	["Spitter1", "spitter", Vector2(2224, 128), {"aggro_range": 128.0, "lose_range": 160.0}],
	["Ghost1", "ghost", Vector2(2288, 104), {"wake_range": 96.0, "lose_range": 160.0}],
	# Old hull: the heavy guard has a wide floor rather than a tiny pit-side perch.
	["Scrapper2", "scrapper", Vector2(3760, 320), {"aggro_range": 112.0, "patrol_range": 16.0, "lose_range": 144.0}],
	["GearShield1", "gear_shield", Vector2(3840, 320), {"variant": &"heavy_guard", "aggro_range": 112.0, "patrol_range": 16.0, "lose_range": 144.0}],
	["Ghost3", "ghost", Vector2(3872, 224), {"wake_range": 96.0, "lose_range": 144.0}],
	["Spitter3", "spitter", Vector2(3904, 288), {"aggro_range": 96.0, "lose_range": 128.0}],
]
const TORCHES: Array = [
	Vector2(112, 320), Vector2(384, 320), Vector2(1088, 320), Vector2(1248, 320),
	Vector2(1624, 320), Vector2(1984, 128), Vector2(2352, 128), Vector2(2544, 320),
	Vector2(2752, 320), Vector2(3472, 320), Vector2(3792, 320), Vector2(4160, 320),
]
const PROPS: Array = [
	["skull_arch", Vector2(48, 320)], ["rubble_dry", Vector2(304, 320)],
	["pipe_valve", Vector2(496, 304)], ["rubble_dry_c", Vector2(976, 304)],
	["rubble_dry", Vector2(1184, 320)], ["bones", Vector2(1440, 320)],
	["girder_l", Vector2(1552, 64)], ["slab", Vector2(1784, 224)],
	["pipe_valve", Vector2(2160, 128)], ["rubble_dry_c", Vector2(2368, 128)],
	["rubble_dry", Vector2(2432, 320)], ["girder_l", Vector2(2440, 320)],
	["rubble_dry", Vector2(2928, 304)], ["rubble_dry_c", Vector2(3344, 304)],
	["broken_machine", Vector2(3552, 320)], ["girder_r", Vector2(3768, 320)],
	["skull_arch", Vector2(3888, 320)], ["rubble_dry", Vector2(4144, 320)],
]


func level_id() -> String: return "level08"
func title() -> String: return ChapterText.title_of(level_id())
func wake_line() -> String: return ChapterText.wake_of(level_id())
func entry_spawn() -> Vector2: return ENTRY_SPAWN
func east_limit() -> int: return EAST_LIMIT
func camera_top() -> int: return -48
func theme() -> String: return "forge"
func motes() -> String: return "embers"


func weather_recipe() -> Dictionary:
	return {"allowed": [WorldClock.Weather.EMBER_WIND, WorldClock.Weather.HAZE, WorldClock.Weather.CLEAR],
		"weights": {"*": {"ember_wind": 5, "haze": 3, "clear": 1}},
		"hold": Vector2(240, 400), "intensity": Vector2(0.6, 1.0)}


func build(host: Node2D) -> void:
	for f in FLOORS:
		floor_strip(host, f[0], f[1], f[2], "basalt", f[1] > 0, f[2] < EAST_LIMIT, f[3])
	for p in PITS:
		_slag_pit(host, p[0], p[1], p[2])
	for i in ISLANDS:
		step(host, i[0], i[1], i[2], "basalt_float")
	step(host, "VentLedge", VENT_LEDGE.position, VENT_LEDGE.size.x, "basalt_float")
	step(host, "ReturnGallery", RETURN_LEDGE.position, RETURN_LEDGE.size.x, "basalt_float")
	step(host, "ShellStep", Vector2(3872, 288), 48, "basalt_float")
	step(host, "ShellLedge", Vector2(3920, 256), 96, "basalt_float")
	var back := lift(host, "ReturnLift", RETURN_LIFT_POS, RETURN_LIFT_TRAVEL, RETURN_LIFT_PERIOD, 64, 0, 0)
	back.modulate = LIFT_TONE
	enclose(host, "basalt", CEILING_Y)
	for f in FOUNTAINS:
		cyclic(host, f[0], f[1], "slag", {"reach": 72.0, "thick": 32.0,
			"rest_time": f[3], "telegraph_time": f[4], "active_time": f[5], "phase": f[6]})
	for n in NESTS:
		nest(host, n[0], n[1], n[2])
	_stele(host, "SteleSlag", STELE_SLAG_POS)
	_stele(host, "SteleQuench", STELE_QUENCH_POS)
	_stele(host, "SteleVent", STELE_VENT_POS)
	hook(host, "HookVent", HOOK_VENT_POS)
	plate_door(host, "Sluice", PLATE_FEET, DOOR_POS)
	rusty_gate(host, "RustGate", GATE_POS)
	reward(host, "RewardVent", REWARD_VENT_FEET - Vector2(0, 7), "equipment", "bone_amulet", EquipmentCatalog.bone_amulet().display_name)
	# Preserve the old v2 pickup path; the icon bottom lies seven pixels below its node.
	var old_reward := reward(host, "RewardOldHull", REWARD_POS, REWARD_KIND, REWARD_REF, EquipmentCatalog.toxic_ward().display_name)
	old_reward.reparent(group(host, "Pickups"))
	for w in [[Vector2(336, 320), "渣渊"], [Vector2(1312, 64), "回巢"], [Vector2(2768, 320), "城墙"]]:
		waymark(host, w[0], w[1])
	for e in ENEMIES:
		enemy(host, e[0], e[1], e[2], e[3])
	for t in TORCHES:
		torch(host, t.x, t.y, TORCH_TINT)
	for p in PROPS:
		prop(host, p[0], p[1], 1.0, GIRDER_TINT)
	for x in [224.0, 736.0, 1376.0, 2032.0, 2688.0, 3216.0, 3904.0]:
		hanging(host, "vine", Vector2(x, 0), VINE_TINT)
	exit_door(host, EXIT_X, ChapterText.exit_label_of(level_id()), ChapterText.exit_captions_of(level_id()),
		"level08_done", GameContext.next_level_id(level_id()))
	finish(host)


func _slag_pit(host: Node2D, pit_name: String, x0: float, x1: float) -> void:
	var bed_y := FLOOR_Y + PIT_DEPTH
	platform(host, pit_name + "Bed", Vector2(x0, bed_y), Vector2(x1 - x0, 400 - bed_y), "basalt", false, false)
	var pool := toxin(host, pit_name + "Pool", Vector2(x0, bed_y - 16), Vector2(x1 - x0, 32), SLAG_TINT)
	pool.set_sludge_ramp(SLAG_RAMP, SLAG_VAPOR)


func _stele(host: Node2D, node_name: String, pos: Vector2) -> void:
	var entry := ChapterText.stele_of(level_id(), node_name)
	stele(host, node_name, pos, String(entry.get("title", "")), String(entry.get("text", "")))
