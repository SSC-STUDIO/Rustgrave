extends ChapterLayout
## 鸣钟环廊：下层绕柱，上层唱诗楼；断顶桥下是可回行的干沟。

const BELL_VISUAL := preload("res://scripts/levels/chapters/cathedral_bell.gd")
const EAST_LIMIT := 4200
const CAMERA_TOP := -96
const CEILING_Y := -32.0
const ENTRY_SPAWN := Vector2(96, 300)
const STONE_TONE := Color(0.9, 0.88, 1.0)
const FLOAT_TONE := Color(0.94, 0.92, 1.0)
const TORCH_TINT := Color(0.8, 0.82, 1.0)
const VINE_TINT := Color(0.62, 0.62, 0.8, 0.85)

## [name, x0, x1, top] — the lower cloister changes level at the open vault.
const FLOORS: Array = [
	["FloorA", 0.0, 1088.0, 320.0],
	["FloorB", 1088.0, 1888.0, 320.0],
	["NaveDryBed", 1888.0, 2464.0, 352.0],
	["FloorD", 2464.0, 3296.0, 320.0],
	["FloorE", 3296.0, 4200.0, 320.0],
]
## Thin galleries leave the lower circuit open.
const STEPS: Array = [
	["ChoirStep1", Vector2(640, 288), 48.0],
	["ChoirStep2", Vector2(712, 256), 48.0],
	["ChoirLoft", Vector2(784, 224), 224.0],
	["ChoirRecoveryUpper", Vector2(1032, 256), 48.0],
	["ChoirRecoveryStep", Vector2(1104, 288), 48.0],
	# Leave the final choir-stair jump clear of the return gallery's underside.
	["GalleryReturn", Vector2(400, 192), 336.0],
	["GalleryWest", Vector2(1008, 192), 432.0],
	["GalleryEast", Vector2(1496, 192), 440.0],
	["BridgeB1", Vector2(1936, 288), 48.0],
	["BridgeB2", Vector2(1984, 256), 144.0],
	["BridgeB3", Vector2(2128, 256), 240.0],
	["BridgeB4", Vector2(2368, 288), 64.0],
	["VaultLedge", Vector2(2400, 104), 144.0],
	["SideStep1", Vector2(2528, 288), 48.0],
	["SideStep2", Vector2(2600, 256), 48.0],
	["SideStep3", Vector2(2672, 224), 48.0],
	["SideLoft", Vector2(2744, 192), 288.0],
]
## Low column plinths are physical refuges: the floor wave is only 16px high.
const COVERS: Array = [
	["FontColumnWest", Vector2(448, 288), 64.0],
	["FontNicheEast", Vector2(592, 288), 48.0],
	["NaveColumnWest", Vector2(1432, 288), 64.0],
	["NaveNicheEast", Vector2(1624, 288), 64.0],
	["ChoirColumn", Vector2(2808, 160), 48.0],
	["ApseColumnWest", Vector2(3488, 288), 64.0],
	["ApseNicheEast", Vector2(3680, 288), 64.0],
]
const CHOIR_CHAIN := ["FloorA", "ChoirStep1", "ChoirStep2", "ChoirLoft"]
const CHOIR_RETURN_CHAIN := ["FloorB", "ChoirRecoveryStep", "ChoirRecoveryUpper", "ChoirLoft"]
const GALLERY_CHAIN := ["ChoirLoft", "GalleryWest", "GalleryEast", "BridgeB2", "BridgeB3"]
const BRIDGE_CHAIN := ["FloorB", "BridgeB1", "BridgeB2", "BridgeB3", "BridgeB4", "FloorD"]
const SIDE_CHAIN := ["FloorD", "SideStep1", "SideStep2", "SideStep3", "SideLoft"]
const NEST_NAVE_X := 176.0
const NEST_CHOIR_X := 1184.0
const NEST_BRIDGE_X := 2160.0
const NEST_BRIDGE_Y := 256.0
const NEST_ALTAR_X := 3104.0
const NEST_CLOISTER_X := 3904.0
const PLATE_FEET := Vector2(912, 224)
const DOOR_POS := Vector2(1072, 256)
const GATE_POS := Vector2(3328, 256)
const HOOK_POS := Vector2(2448, 48)
const PICKUP_POS := Vector2(2448, 88)
const STELE_VAULT_POS := Vector2(2512, 104)
const REWARD_POS := Vector2(2976, 185)
const EXIT_X := 4048.0
## Three staged encounters; the first bell's teaching area has no enemies.
const ENEMIES: Array = [
	["Ghost1", "ghost", Vector2(824, 176), {"wake_range": 120.0, "lose_range": 260.0}],
	["Scrapper1", "scrapper", Vector2(880, 320), {"patrol_range": 16.0, "aggro_range": 180.0, "alert_radius": 112.0}],
	["GearShield1", "gear_shield", Vector2(1560, 320), {"variant": &"heavy_guard", "patrol_range": 16.0, "aggro_range": 220.0, "lose_range": 300.0}],
	["Ghost2", "ghost", Vector2(1584, 144), {"wake_range": 120.0, "lose_range": 260.0}],
	["Spitter1", "spitter", Vector2(1808, 192), {"aggro_range": 280.0, "lose_range": 320.0}],
	["Ghost3", "ghost", Vector2(2784, 128), {"wake_range": 112.0, "lose_range": 240.0}],
	["GearShield2", "gear_shield", Vector2(3576, 320), {"variant": &"heavy_guard", "patrol_range": 16.0, "aggro_range": 220.0, "lose_range": 280.0}],
	["Scrapper2", "scrapper", Vector2(3768, 320), {"patrol_range": 8.0, "aggro_range": 96.0, "lose_range": 120.0}],
]
const BELLS: Array = [
	["FontResonance", Vector2(544, 320), 208.0, 0.0],
	["NaveResonance", Vector2(1560, 320), 220.0, 0.35],
	["ChoirResonance", Vector2(2840, 192), 192.0, 0.6],
	["ApseResonance", Vector2(3600, 320), 220.0, 0.15],
]
const TORCHES: Array = [320.0, 1248.0, 1728.0, 2576.0, 3184.0, 3408.0, 3840.0, 4120.0]
const PROPS: Array = [
	["window", Vector2(72, 320)], ["gargoyle", Vector2(352, 320)],
	["column", Vector2(480, 288)], ["balustrade", Vector2(600, 192)],
	["balustrade", Vector2(976, 224)], ["window", Vector2(1312, 320)],
	["column", Vector2(1464, 288)], ["balustrade", Vector2(1648, 192)],
	["window", Vector2(1840, 192)], ["balustrade", Vector2(2072, 256)],
	["gargoyle", Vector2(2304, 256)], ["altar", Vector2(2480, 320)],
	["balustrade", Vector2(2784, 192)], ["column", Vector2(2832, 160)],
	["window", Vector2(3008, 320)], ["altar", Vector2(3248, 320)],
	["column", Vector2(3520, 288)], ["gargoyle", Vector2(3712, 288)],
	["window", Vector2(3976, 320)],
]
const VINES: Array = [248.0, 656.0, 1096.0, 1320.0, 1600.0, 2040.0, 2280.0, 2600.0, 3104.0, 3424.0, 3744.0]


func level_id() -> String: return "level04"
func title() -> String: return ChapterText.title_of(level_id())
func wake_line() -> String: return ChapterText.wake_of(level_id())
func entry_spawn() -> Vector2: return ENTRY_SPAWN
func east_limit() -> int: return EAST_LIMIT
func camera_top() -> int: return CAMERA_TOP
func theme() -> String: return "cathedral"
func motes() -> String: return "candle"


func weather_recipe() -> Dictionary:
	return {"allowed": [WorldClock.Weather.HAZE, WorldClock.Weather.CLEAR],
		"hold": Vector2(320.0, 520.0), "intensity": Vector2(0.4, 0.8)}


func weather_regions() -> Array:
	return [{"name": "BrokenVault", "rect": Rect2(1856, -32, 480, 432),
		"weather": WorldClock.Weather.RAIN, "intensity": 0.85, "outdoor": true}]


func build(host: Node2D) -> void:
	for f in FLOORS:
		floor_strip(host, f[0], f[1], f[2], "nave", true, true, f[3], STONE_TONE)
	for s in STEPS:
		step(host, s[0], s[1], s[2], "nave_float", FLOAT_TONE)
	for c in COVERS:
		platform(host, c[0], c[1], Vector2(c[2], 32), "nave", true, true, STONE_TONE)
	enclose(host, "nave", CEILING_Y, 1856.0, 480.0, STONE_TONE)
	_build_props(host)
	_build_bells(host)
	for e in ENEMIES:
		enemy(host, e[0], e[1], e[2], e[3])
	for x in TORCHES:
		torch(host, x, FLOOR_Y, TORCH_TINT)
	for p in PROPS:
		prop(host, p[0], p[1])
	for x in VINES:
		hanging(host, "vine", Vector2(x, 0), VINE_TINT)
	exit_door(host, EXIT_X, ChapterText.exit_label_of(level_id()),
		ChapterText.exit_captions_of(level_id()), "level04_done", GameContext.next_level_id(level_id()))
	finish(host)


func _build_props(host: Node2D) -> void:
	nest(host, "EmberNestNave", NEST_NAVE_X)
	nest(host, "EmberNestChoir", NEST_CHOIR_X)
	nest(host, "EmberNestBridge", NEST_BRIDGE_X, NEST_BRIDGE_Y)
	nest(host, "EmberNestAltar", NEST_ALTAR_X)
	nest(host, "EmberNestCloister", NEST_CLOISTER_X)
	_stele(host, "SteleCompact", Vector2(248, 320))
	_stele(host, "StelePrice", Vector2(3056, 320))
	plate_door(host, "Choir", PLATE_FEET, DOOR_POS)
	rusty_gate(host, "RustyGate", GATE_POS)
	hook(host, "Hook_Vault", HOOK_POS)
	pickup(host, "EmberCoreVault", PICKUP_POS, &"ember_core")
	_stele(host, "SteleVault", STELE_VAULT_POS)
	# Preserve the v2 reward path and its Fill-based foot point.
	var pick := load("res://scenes/interactables/EquipmentPickup.tscn").instantiate() as EquipmentPickup
	pick.name = "RewardChoir"
	pick.position = REWARD_POS
	pick.reward_kind = "equipment"
	pick.reward_ref = "bone_charm"
	var item := EquipmentCatalog.for_id(&"bone_charm")
	pick.reward_name = item.display_name if item != null else ""
	group(host, "Pickups").add_child(pick)
	waymark(host, Vector2(304, 320), "圣殿")
	waymark(host, Vector2(1120, 192), "回巢")
	waymark(host, Vector2(2960, 320), "祭坛")
	waymark(host, Vector2(3944, 320), "侧廊")


func _stele(host: Node2D, node_name: String, pos: Vector2) -> void:
	var entry := ChapterText.stele_of(level_id(), node_name)
	stele(host, node_name, pos, String(entry.get("title", "")), String(entry.get("text", "")))


func _build_bells(host: Node2D) -> void:
	for b in BELLS:
		var wave := cyclic(host, b[0], b[1], "shock", {"thick": b[2], "phase": b[3]})
		var bell := BELL_VISUAL.new() as Node2D
		bell.name = String(b[0]) + "Bell"
		bell.set("wave", wave)
		bell.position = b[1]
		group(host, "Decor").add_child(bell)
