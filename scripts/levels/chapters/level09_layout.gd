extends ChapterLayout
## 锈城城墙：墙顶是主道，塔室、瞭望台和鹰巢从塔楼辐射出去。
const EAST_LIMIT := 4200
const ENTRY_SPAWN := Vector2(96, 300)
const SKIN := "rampart"
const DRY_BUSH := Color(0.74, 0.78, 0.7)
const RETURN_DROP := Rect2(1312, 192, 48, 128)
const ROOMS: Array = [Rect2(416, 288, 672, 64), Rect2(2864, 288, 336, 64)]

## [name, left/top, size]，32px屋面使下层至少有64px净空。
const TERRAIN: Array = [
	["FloorA", Vector2(0, 320), Vector2(352, 80)],
	["EntryStep", Vector2(352, 288), Vector2(64, 32)],
	["TowerAWest", Vector2(416, 256), Vector2(288, 32)],
	["TowerA", Vector2(752, 256), Vector2(336, 32)],
	["GatehouseRoom", Vector2(352, 352), Vector2(736, 48)],
	["GatehouseEscape", Vector2(1120, 352), Vector2(32, 48)],
	["FloorB", Vector2(1152, 320), Vector2(256, 80)],
	["TowerBEntry", Vector2(1408, 288), Vector2(64, 32)],
	["TowerB", Vector2(1472, 256), Vector2(544, 32)],
	["TowerBStep", Vector2(1840, 224), Vector2(64, 16)],
	["LookoutB", Vector2(1648, 192), Vector2(160, 16)],
	["ReturnBalcony", Vector2(1360, 192), Vector2(240, 16)],
	["TowerBExit", Vector2(2016, 288), Vector2(64, 32)],
	["FloorC", Vector2(2080, 320), Vector2(224, 80)],
	["WindEntry", Vector2(2304, 288), Vector2(96, 32)],
	["WindPierWest", Vector2(2448, 288), Vector2(128, 32)],
	["WindPierEast", Vector2(2624, 256), Vector2(128, 32)],
	["WindRecovery", Vector2(2304, 352), Vector2(496, 48)],
	["WindEscape", Vector2(2752, 320), Vector2(48, 32)],
	["TowerCEntry", Vector2(2800, 288), Vector2(64, 32)],
	["TowerC", Vector2(2864, 256), Vector2(336, 32)],
	["EastTowerRoom", Vector2(2864, 352), Vector2(336, 48)],
	["FloorD", Vector2(3200, 320), Vector2(256, 80)],
	["StoneD", Vector2(3488, 288), Vector2(64, 16)],
	["ArrowRecovery", Vector2(3456, 352), Vector2(128, 48)],
	["FloorE", Vector2(3584, 320), Vector2(616, 80)],
	["TowerDStep", Vector2(3648, 288), Vector2(64, 32)],
	["TowerDBase1", Vector2(3744, 256), Vector2(64, 16)],
	["TowerD", Vector2(3840, 224), Vector2(128, 32)],
	["EyrieC", Vector2(2960, 160), Vector2(128, 32)],
]
const MAIN_CHAIN: Array = ["FloorA", "EntryStep", "TowerAWest", "TowerA", "FloorB",
	"TowerBEntry", "TowerB", "TowerBExit", "FloorC", "WindEntry", "WindPierWest", "WindPierEast",
	"TowerCEntry", "TowerC", "FloorD", "StoneD", "FloorE"]
const NESTS: Array = [["EmberNestGate", 176.0, 320.0], ["EmberNestMid", 1184.0, 320.0],
	["EmberNestEast", 2208.0, 320.0], ["EmberNestRampart", 3216.0, 320.0]]
const NEST_GATE_X := 176.0
const NEST_MID_X := 1184.0
const NEST_EAST_X := 2208.0
const NEST_RAMPART_X := 3216.0
const STELE_WALL_POS := Vector2(264, 320)
const STELE_WIND_POS := Vector2(1696, 192)
const PLATE_FEET := Vector2(1920, 256)
const GATE_DOOR_POS := Vector2(1984, 192)
const HOOK_POS := Vector2(2992, 80)
const EMBER_CORE_POS := Vector2(2992, 136)
const STELE_EYRIE_POS := Vector2(2968, 160)
const EXIT_X := 4080.0
const REWARD_POS := Vector2(3888, 217)
const REWARD_REF := "iron_blade"
const EYRIE_REWARD_FEET := Vector2(3056, 160)

## [name, world rect, push, period]，第一处在完整墙顶教学，后两处相反风向。
const WINDS: Array = [
	["WindLesson", Rect2(480, 152, 112, 104), Vector2(48, 0), 4.0],
	["WindChannel", Rect2(2352, 144, 224, 160), Vector2(-64, 0), 5.0],
	["WindTurn", Rect2(2624, 144, 128, 144), Vector2(64, 0), 5.0],
]
## 三处地面遭遇：门楼内室、中塔高低台、箭楼；两只空哨分别在西塔和风墩。
const ENEMIES: Array = [
	["Scrapper1", "scrapper", Vector2(800, 352), {"variant": &"armored_scrapper", "patrol_range": 24.0, "aggro_range": 128.0, "lose_range": 240.0}],
	["Ghost1", "ghost", Vector2(960, 320), {"wake_range": 100.0, "arena_left": 752.0, "arena_right": 1088.0}],
	["Demon1", "flying_demon", Vector2(912, 160), {"patrol_range": 32.0, "aggro_range": 128.0, "lose_range": 240.0}],
	["Spitter2", "spitter", Vector2(1760, 192), {"variant": &"scatter_spitter", "aggro_range": 200.0}],
	["Scrapper2", "scrapper", Vector2(1616, 256), {"variant": &"swift_scrapper", "patrol_range": 24.0, "lose_range": 280.0}],
	["Demon3", "flying_demon", Vector2(2608, 160), {"patrol_range": 32.0, "aggro_range": 160.0, "lose_range": 240.0}],
	["Ghost2", "ghost", Vector2(2944, 320), {"wake_range": 100.0, "arena_left": 2864.0, "arena_right": 3168.0}],
	["ArrowScrapper", "scrapper", Vector2(3616, 320), {"patrol_range": 16.0, "aggro_range": 160.0, "lose_range": 240.0}],
	["Spitter4", "spitter", Vector2(3920, 224), {"aggro_range": 180.0}],
]
const PROPS: Array = [
	["balustrade_wall", Vector2(72, 320)], ["rubble_dry", Vector2(232, 320)],
	["balustrade_wall", Vector2(464, 256)], ["rubble_dry_c", Vector2(656, 256)],
	["door_arch_wall", Vector2(896, 352)], ["balustrade_wall", Vector2(1008, 256)],
	["rubble_dry_c", Vector2(1328, 320)], ["ruin_tower", Vector2(1512, 256)],
	["balustrade_wall", Vector2(1680, 192)], ["door_arch_wall", Vector2(1920, 256)],
	["rubble_dry", Vector2(2120, 320)], ["balustrade_wall", Vector2(2336, 288)],
	["balustrade_wall", Vector2(2496, 288)], ["balustrade_wall", Vector2(2704, 256)],
	["door_arch_wall", Vector2(3072, 352)], ["balustrade_wall", Vector2(3136, 256)],
	["rubble_dry_c", Vector2(3344, 320)], ["balustrade_wall", Vector2(3424, 320)],
	["balustrade_wall", Vector2(3632, 320)], ["door_arch_wall", Vector2(3888, 320)],
	["balustrade_wall", Vector2(3872, 224)], ["rubble_dry", Vector2(4008, 320)],
]
const WAYMARKS: Array = [[Vector2(320, 320), "城墙"], [Vector2(640, 256), "回巢"],
	[Vector2(1520, 256), "瞭望"], [Vector2(2920, 352), "塔室"], [Vector2(4020, 320), "炉心"]]


func level_id() -> String:
	return "level09"


func title() -> String:
	return ChapterText.title_of(level_id())


func wake_line() -> String:
	return ChapterText.wake_of(level_id())


func entry_spawn() -> Vector2:
	return ENTRY_SPAWN


func east_limit() -> int:
	return EAST_LIMIT


func theme() -> String:
	return "ramparts"


func ambient() -> Dictionary:
	return {"time": 0.56, "weather": "ember_wind", "hold": 360.0}


func weather_recipe() -> Dictionary:
	return {
		"allowed": [WorldClock.Weather.EMBER_WIND, WorldClock.Weather.CLEAR,
			WorldClock.Weather.HAZE, WorldClock.Weather.RAIN],
		"weights": {
			"dusk": {"ember_wind": 5, "rain": 3, "clear": 1, "haze": 1},
			"night": {"rain": 4, "ember_wind": 3, "clear": 2, "haze": 1},
			"*": {"ember_wind": 4, "clear": 3, "haze": 2, "rain": 1},
		},
		"hold": Vector2(90.0, 170.0), "intensity": Vector2(0.7, 1.0),
	}


func weather_regions() -> Array:
	return [
		{"name": "GaleGap", "rect": Rect2(2304, 112, 496, 272), "weather": WorldClock.Weather.RAIN, "intensity": 1.0, "wind_scale": 1.5},
		{"name": "TowerLee", "rect": ROOMS[1], "weather": WorldClock.Weather.CLEAR, "intensity": 0.0, "wind_scale": 0.0, "indoor": true},
		{"name": "GatehouseLee", "rect": ROOMS[0], "weather": WorldClock.Weather.CLEAR, "intensity": 0.0, "wind_scale": 0.0, "indoor": true},
	]


func build(host: Node2D) -> void:
	for t in TERRAIN:
		platform(host, String(t[0]), t[1], t[2], SKIN)
	walls(host, SKIN)
	for row in NESTS:
		nest(host, String(row[0]), float(row[1]), float(row[2]))
	for row in [["SteleWall", STELE_WALL_POS], ["SteleWind", STELE_WIND_POS], ["SteleEyrie", STELE_EYRIE_POS]]:
		var entry := ChapterText.stele_of(level_id(), String(row[0]))
		stele(host, String(row[0]), row[1], String(entry.get("title", "")), String(entry.get("text", "")))
	plate_door(host, "WallGate", PLATE_FEET, GATE_DOOR_POS)
	hook(host, "HookTower", HOOK_POS)
	pickup(host, "EmberCore", EMBER_CORE_POS, &"ember_core")
	# 保留旧奖励父级/名字；节点上移7使Fill底边正好落在台面。
	var iron := EquipmentPickup.new()
	iron.name = "RewardEyrie"
	iron.position = REWARD_POS
	iron.reward_kind = "equipment"
	iron.reward_ref = REWARD_REF
	iron.reward_name = EquipmentCatalog.for_id(&"iron_blade").display_name
	group(host, "Pickups").add_child(iron)
	reward(host, "RewardHookEyrie", EYRIE_REWARD_FEET - Vector2(0, 7), "equipment", "bone_charm")
	for row in WINDS:
		force_zone(host, String(row[0]), row[1], "wind", row[2], {"gust_period": float(row[3]), "gust_duty": 0.5, "phase": 0.5})
	for e in ENEMIES:
		enemy(host, String(e[0]), String(e[1]), e[2], e[3])
	_build_decor(host)
	for row in WAYMARKS:
		waymark(host, row[0], String(row[1]))
	exit_door(host, EXIT_X, ChapterText.exit_label_of(level_id()), ChapterText.exit_captions_of(level_id()),
		"level09_done", GameContext.next_level_id(level_id()))
	finish(host)
	# 共享_add_zone_rect只设置形状局部位移，本章显式补区域世界位置。
	for row in [["GatehouseLeeIndoor", ROOMS[0]], ["TowerLeeIndoor", ROOMS[1]]]:
		var zone := host.get_node_or_null("Props/" + String(row[0])) as AtmosphereZone
		if zone != null:
			zone.position = (row[1] as Rect2).position


func _build_decor(host: Node2D) -> void:
	for rect in ROOMS:
		var wall := TowerRelief.new()
		wall.position = (rect as Rect2).position
		wall.width = (rect as Rect2).size.x
		decor_layer(host).add_child(wall)
	for row in PROPS:
		prop(host, row[0], row[1], 1.0, Color(0.8, 0.86, 0.9) if row[0] == "ruin_tower" else Color.WHITE)
	for feet in [Vector2(304, 320), Vector2(1280, 320), Vector2(2264, 320), Vector2(3280, 320), Vector2(4128, 320)]:
		foliage(host, "bush_s", feet, 1.0, false, DRY_BUSH)


## 复用城墙填充作无碰撞背墙，门洞和石柱标出可下探的塔室。
class TowerRelief extends Node2D:
	const FILL := preload("res://assets/env/rampart_fill.png")
	var width := 336.0
	func _draw() -> void:
		draw_texture_rect(FILL, Rect2(0, 0, width, 64), true, Color(0.38, 0.43, 0.48))
		for x in range(48, int(width) - 48, 160):
			draw_rect(Rect2(x, 8, 80, 56), Color(0.035, 0.045, 0.055, 0.88))
		for x in range(0, int(width), 160):
			draw_texture_rect(FILL, Rect2(x, 0, 16, 64), true, Color(0.6, 0.66, 0.7))
