extends ChapterLayout
## 三层工坊：机房 / 检修道 / 吊轨；传送带与静态蒸汽廊分区。

const EAST := 4000
const CEILING_Y := -48.0
const SPAWN := Vector2(96, 300)
const STONE_WARM := Color(1.0, 0.92, 0.82)
const WALK_TONE := Color(1.08, 1.0, 0.86)
const TORCH_TINT := Color(1.0, 0.94, 0.86)
const CABLE_TINT := Color(0.42, 0.26, 0.14, 0.8)
const PIPE_TINT := Color(0.82, 0.74, 0.66)
const NEST_START_X := 176.0
const NEST_LIFT_X := 1168.0
const NEST_GATE_X := 2160.0
const NEST_HOIST_X := 3152.0
const PLATE_A_FEET := Vector2(1104, 224)
const DOOR_A_POS := Vector2(1424, 256)
const PLATE_B_FEET := Vector2(1384, 112)
const DOOR_B_POS := Vector2(2288, 256)
const GATE_POS := Vector2(3576, 256)
const HOOK_POS := Vector2(2736, 160)
const PICKUP_POS := Vector2(2736, 192)
const HOOK_NOOK_POS := Vector2(2296, 48)
const STELE_NOOK_POS := Vector2(2320, 96)
const HOOK_HOIST_POS := Vector2(3456, 64)
const REWARD_POS := Vector2(3656, 121)
const EXIT_X := 3900.0

## Every lower-floor section has a purpose; two machine bays change the floor height.
const FLOORS: Array = [
	["FloorA", 0.0, 480.0, 320.0], ["FloorB", 704.0, 1472.0, 320.0],
	["FloorC", 1472.0, 2016.0, 288.0], ["FloorD", 2016.0, 2432.0, 320.0],
	["FloorE", 2720.0, 4000.0, 320.0],
]
const STEPS: Array = [
	["StepB1", Vector2(752, 288), 48.0], ["StepB2", Vector2(824, 256), 48.0],
	["StepB3", Vector2(896, 224), 48.0], ["WalkB", Vector2(944, 224), 256.0],
	["UpperReturn", Vector2(400, 112), 832.0], ["DeckD", Vector2(1312, 112), 400.0],
	["RailD", Vector2(1760, 112), 272.0], ["MidLanding", Vector2(1968, 224), 112.0],
	["NookDeck", Vector2(2240, 96), 112.0],
	["StepE1", Vector2(2240, 288), 48.0], ["StepE2", Vector2(2312, 256), 48.0],
	["StepE3", Vector2(2384, 224), 48.0], ["WalkE", Vector2(2456, 224), 360.0],
	["SteamWalk", Vector2(2864, 224), 352.0],
	["ReturnStepE2", Vector2(3248, 256), 48.0], ["ReturnStepE1", Vector2(3320, 288), 48.0],
	["HoistRailEnd", Vector2(3248, 112), 48.0],
	["HoistDeck", Vector2(3392, 128), 320.0],
]
const BELTS: Array = [
	["QuenchBelt", Vector2(480, 320), 224.0, 36.0, 0.0],
	["ReturnBelt", Vector2(2432, 320), 288.0, -36.0, 5.2],
]
const VENTS: Array = [
	["SteamQuench", Vector2(1648, 288), 0.0, 48.0],
	["SteamService", Vector2(3056, 224), 0.4, 56.0],
	["SteamHoist", Vector2(3504, 128), 0.2, 48.0],
]
## [name, start, travel, period, width, phase]
const LIFTS: Array = [
	["LiftD", Vector2(1248, 296), Vector2(0, -184), 6.4, 48.0, 0.0],
	["LiftC", Vector2(1536, 224), Vector2(352, 0), 9.6, 64.0, 0.0],
	["LiftF", Vector2(2816, 208), Vector2(0, -96), 5.6, 48.0, 0.0],
	["LiftE1", Vector2(2880, 112), Vector2(112, 0), 6.0, 64.0, 0.0],
	["LiftE2", Vector2(3072, 112), Vector2(112, 0), 6.0, 64.0, 0.5],
]
const STAIR_CHAINS: Array = [
	["FloorB", "StepB1", "StepB2", "StepB3", "WalkB"],
	["FloorD", "StepE1", "StepE2", "StepE3", "WalkE"],
	["FloorE", "ReturnStepE1", "ReturnStepE2", "SteamWalk"],
]
const ENEMIES: Array = [
	["Scrapper1", "scrapper", Vector2(928, 320), {"variant": &"armored_scrapper", "aggro_range": 128.0, "patrol_range": 8.0, "lose_range": 180.0}],
	["Ghost1", "ghost", Vector2(1008, 176), {"wake_range": 96.0, "lose_range": 160.0}],
	["GearShield1", "gear_shield", Vector2(1600, 112), {"variant": &"heavy_guard", "aggro_range": 160.0, "patrol_range": 16.0, "lose_range": 240.0}],
	["Spitter1", "spitter", Vector2(1648, 112), {"aggro_range": 240.0, "lose_range": 280.0}],
	["FlyingDemon1", "flying_demon", Vector2(1840, 176), {"aggro_range": 140.0, "lose_range": 220.0}],
	["Scrapper2", "scrapper", Vector2(1904, 288), {"aggro_range": 128.0, "patrol_range": 8.0, "lose_range": 180.0}],
	["Spitter2", "spitter", Vector2(2896, 224), {"aggro_range": 200.0, "lose_range": 240.0}],
	["Ghost2", "ghost", Vector2(2960, 176), {"wake_range": 100.0, "lose_range": 200.0}],
	["GearShield2", "gear_shield", Vector2(3520, 320), {"variant": &"heavy_guard", "aggro_range": 160.0, "patrol_range": 16.0, "lose_range": 240.0}],
	["Scrapper3", "scrapper", Vector2(3720, 320), {"aggro_range": 140.0, "patrol_range": 16.0, "lose_range": 200.0}],
]
const PROPS: Array = [
	["rubble_dry", Vector2(384, 320)], ["warning_plate", Vector2(432, 320)],
	["pipe_valve", Vector2(736, 320)], ["fence", Vector2(1080, 112)],
	["plate", Vector2(1040, 224)], ["broken_machine", Vector2(1336, 320)],
	["girder_l", Vector2(1504, 112)], ["pipe_valve", Vector2(1728, 288)],
	["fence", Vector2(1840, 112)], ["rubble_dry_c", Vector2(2016, 224)],
	["plate", Vector2(2224, 320)], ["rubble_dry", Vector2(2592, 224)],
	["girder_l", Vector2(2768, 224)], ["pipe_valve", Vector2(2992, 224)],
	["fence", Vector2(3192, 224)], ["broken_machine", Vector2(3240, 320)],
	["warning_plate", Vector2(3424, 128)], ["pipe_valve", Vector2(3600, 128)],
	["girder_r", Vector2(3648, 320)], ["rubble_dry_c", Vector2(3808, 320)],
]
const TORCHES: Array = [320.0, 800.0, 1200.0, 1400.0, 2080.0, 2800.0, 3104.0, 3392.0, 3840.0]


func level_id() -> String: return "level05"
func title() -> String: return ChapterText.title_of(level_id())
func wake_line() -> String: return ChapterText.wake_of(level_id())
func entry_spawn() -> Vector2: return SPAWN
func east_limit() -> int: return EAST
func camera_top() -> int: return -112
func theme() -> String: return "industrial"
func motes() -> String: return "sparks"


func weather_recipe() -> Dictionary:
	return {"allowed": [WorldClock.Weather.HAZE, WorldClock.Weather.EMBER_WIND, WorldClock.Weather.CLEAR],
		"weights": {"*": {"haze": 4, "ember_wind": 3, "clear": 1}},
		"hold": Vector2(220.0, 380.0), "intensity": Vector2(0.45, 0.85)}


func build(host: Node2D) -> void:
	for f in FLOORS:
		floor_strip(host, f[0], f[1], f[2], "iron", true, true, f[3], STONE_WARM)
	for s in STEPS:
		step(host, s[0], s[1], s[2], "iron_float", WALK_TONE)
	for b in BELTS:
		conveyor(host, b[0], b[1], b[2], b[3], "iron", {"flip_period": b[4]}, 80.0, STONE_WARM)
	for v in VENTS:
		cyclic(host, v[0], v[1], "steam", {"phase": v[2], "reach": v[3]})
	for m in LIFTS:
		lift(host, m[0], m[1], m[2], m[3], m[4], m[5], CEILING_Y + 32)
	enclose(host, "iron", CEILING_Y)
	_build_props(host)
	for e in ENEMIES:
		enemy(host, e[0], e[1], e[2], e[3])
	for x in TORCHES:
		torch(host, x, FLOOR_Y, TORCH_TINT)
	for p in PROPS:
		prop(host, p[0], p[1], 1.0, PIPE_TINT)
	for x in [300.0, 1008.0, 1584.0, 2240.0, 2720.0, 3280.0, 3760.0]:
		hanging(host, "chain", Vector2(x, CEILING_Y + 32), CABLE_TINT)
	exit_door(host, EXIT_X, ChapterText.exit_label_of(level_id()), ChapterText.exit_captions_of(level_id()),
		"level05_done", GameContext.next_level_id(level_id()))
	finish(host)


func _build_props(host: Node2D) -> void:
	nest(host, "EmberNestStart", NEST_START_X)
	nest(host, "EmberNestLift", NEST_LIFT_X)
	nest(host, "EmberNestGate", NEST_GATE_X)
	nest(host, "EmberNestHoist", NEST_HOIST_X)
	_stele(host, "SteleQuench", Vector2(264, 320))
	_stele(host, "SteleChain", Vector2(1464, 112))
	_stele(host, "SteleNook", STELE_NOOK_POS)
	plate_door(host, "GateA", PLATE_A_FEET, DOOR_A_POS)
	plate_door(host, "GateB", PLATE_B_FEET, DOOR_B_POS)
	rusty_gate(host, "RustGate", GATE_POS)
	hook(host, "HookE", HOOK_POS)
	pickup(host, "TetherCoreE", PICKUP_POS, &"tether_core")
	hook(host, "HookNook", HOOK_NOOK_POS)
	hook(host, "HookHoist", HOOK_HOIST_POS)
	var pick := load("res://scenes/interactables/EquipmentPickup.tscn").instantiate() as EquipmentPickup
	pick.name = "RewardHoist"
	pick.position = REWARD_POS
	pick.reward_kind = "equipment"
	pick.reward_ref = "iron_carapace"
	var item := EquipmentCatalog.for_id(&"iron_carapace")
	pick.reward_name = item.display_name if item != null else ""
	group(host, "Pickups").add_child(pick)
	waymark(host, Vector2(352, 320), "工坊")
	waymark(host, Vector2(512, 112), "回巢")
	waymark(host, Vector2(3872, 320), "渣道")


func _stele(host: Node2D, node_name: String, pos: Vector2) -> void:
	var entry := ChapterText.stele_of(level_id(), node_name)
	stele(host, node_name, pos, String(entry.get("title", "")), String(entry.get("text", "")))
