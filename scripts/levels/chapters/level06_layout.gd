extends ChapterLayout
## 墓园夜雨：绕过陵顶的雾路与穿过暗廊的近路，在东墓道重新合流。

const EAST := 4000
const SLAB_TONE := Color(0.98, 0.9, 0.72)
const ROOF_Y := 160.0
const CRYPT_RECT := Rect2(1392, 192, 1008, 128)
const RETURN_DROP := Rect2(1536, 160, 48, 160)
const PLATE_FEET := Vector2(1352, 320)
const DOOR_POS := Vector2(1440, 256)
const HOOK_POS := Vector2(2808, 72)
const PICKUP_POS := Vector2(2792, 128)
const STELE_TREE_POS := Vector2(2756, 176)
const REWARD_FEET := Vector2(2840, 176)
const NEST_START_X := 176.0
const NEST_RAIN_X := 960.0
const NEST_CRYPT_X := 1504.0
const NEST_GROVE_X := 2512.0
const NEST_EAST_X := 3424.0
const EXIT_X := 3840.0
const STELE_A_POS := Vector2(256, 320)
const STELE_B_POS := Vector2(2608, 320)
const NESTS := [
	["EmberNestStart", NEST_START_X], ["EmberNestRain", NEST_RAIN_X],
	["EmberNestCrypt", NEST_CRYPT_X], ["EmberNestGrove", NEST_GROVE_X],
	["EmberNestEast", NEST_EAST_X],
]
const FLOORS := [
	["FloorA", 0.0, 1392.0, "ground"], ["FloorD", 1392.0, 2400.0, "stone"],
	["FloorH", 2400.0, 3360.0, "ground"], ["FloorJ", 3360.0, 4000.0, "ground"],
]
## 上陵阶每阶升32、间隔48；泥石不与余烬巢共用支撑。
const STONES := [
	["MudLessonStone", Vector2(384, 288), 32.0],
	["MausoleumStair1", Vector2(1008, 288), 48.0],
	["MausoleumStair2", Vector2(1104, 256), 48.0],
	["MausoleumStair3", Vector2(1200, 224), 48.0],
	["MausoleumStair4", Vector2(1296, 192), 48.0],
	["MausoleumRoofWest", Vector2(1392, ROOF_Y), 144.0],
	["MausoleumRoofEast", Vector2(1584, ROOF_Y), 816.0],
	["RoofMudStone", Vector2(1872, 128), 64.0],
	["TreeTopStone", Vector2(2744, 176), 128.0],
	["EastMudStone1", Vector2(2768, 288), 48.0],
	["EastMudStone2", Vector2(2848, 272), 48.0],
]
const CHAINS := [
	[Vector2(1000, 320), Vector2(1016, 288), Vector2(1112, 256),
		Vector2(1208, 224), Vector2(1304, 192), Vector2(1400, 160)],
	[Vector2(1528, 160), Vector2(1592, 160)],
	[Vector2(1864, 160), Vector2(1880, 128), Vector2(1944, 160)],
]
const MUD := [
	["MudLesson", Rect2(352, 296, 80, 24), 12.0],
	["RoofMud", Rect2(1840, 136, 160, 24), 14.0],
	["EastMud", Rect2(2736, 296, 160, 24), 16.0],
]
## 三组埋骨（西3/内廊2/东2），不再沿全关均匀撒点。
const ENEMIES := [
	["Skeleton1", "skeleton", Vector2(624, 320), {"wake_range": 112.0, "alert_radius": 160.0, "lose_range": 260.0}],
	["Skeleton2", "skeleton", Vector2(720, 320), {"wake_range": 112.0, "alert_radius": 160.0, "lose_range": 260.0}],
	["Skeleton5", "skeleton", Vector2(816, 320), {"wake_range": 112.0, "alert_radius": 160.0, "lose_range": 260.0}],
	["Ghost1", "ghost", Vector2(800, 240), {"wake_range": 96.0, "lose_range": 220.0}],
	["Skeleton3", "skeleton", Vector2(1792, 320), {"wake_range": 112.0, "alert_radius": 160.0, "lose_range": 260.0}],
	["Skeleton4", "skeleton", Vector2(1888, 320), {"wake_range": 112.0, "alert_radius": 160.0, "lose_range": 260.0, "variant": &"exploder_skeleton"}],
	["Ghost2", "ghost", Vector2(2208, 256), {"wake_range": 112.0, "lose_range": 260.0}],
	["Spitter1", "spitter", Vector2(2208, 160), {"aggro_range": 224.0, "lose_range": 280.0}],
	["Scrapper1", "scrapper", Vector2(2952, 320), {"patrol_range": 16.0, "aggro_range": 128.0, "lose_range": 240.0}],
	["Skeleton6", "skeleton", Vector2(3056, 320), {"wake_range": 112.0, "alert_radius": 160.0, "lose_range": 260.0}],
	["Skeleton7", "skeleton", Vector2(3152, 320), {"wake_range": 112.0, "alert_radius": 160.0, "lose_range": 260.0}],
	["Ghost3", "ghost", Vector2(3696, 240), {"wake_range": 112.0, "lose_range": 200.0}],
	["Scrapper2", "scrapper", Vector2(3784, 320), {"patrol_range": 8.0, "aggro_range": 96.0, "lose_range": 120.0}],
]
const WAYMARKS := [
	[Vector2(352, 320), "墓园"], [Vector2(1248, 320), "陵门"],
	[Vector2(1464, 160), "回巢"], [Vector2(3788, 320), "钟楼"],
]


func level_id() -> String: return "level06"
func title() -> String: return ChapterText.title_of(level_id())
func wake_line() -> String: return ChapterText.wake_of(level_id())
func entry_spawn() -> Vector2: return Vector2(96, 300)
func default_spawn() -> Vector2: return entry_spawn()
func east_limit() -> int: return EAST
func camera_top() -> int: return -48
func theme() -> String: return "graveyard"
func ambient() -> Dictionary: return {"time": 0.82, "weather": "rain", "hold": 420.0}


func weather_recipe() -> Dictionary:
	return {"allowed": [WorldClock.Weather.RAIN, WorldClock.Weather.RUST_RAIN, WorldClock.Weather.FOG, WorldClock.Weather.CLEAR],
		"weights": {"night": {"rust_rain": 6, "rain": 3, "fog": 1}, "*": {"rain": 4, "rust_rain": 3, "fog": 2, "clear": 1}},
		"hold": Vector2(220.0, 360.0), "intensity": Vector2(0.75, 1.0)}


func weather_regions() -> Array:
	return [
		{"name": "GraveFog", "rect": Rect2(496, 144, 352, 176), "weather": WorldClock.Weather.FOG, "intensity": 0.9, "wind_scale": 0.35},
		{"name": "RoofFog", "rect": Rect2(1648, -16, 688, 176), "weather": WorldClock.Weather.FOG, "intensity": 0.8, "wind_scale": 0.4},
		{"name": "MausoleumShelter", "rect": CRYPT_RECT, "weather": WorldClock.Weather.CLEAR, "intensity": 0.0, "wind_scale": 0.0, "indoor": true},
		{"name": "EastGraveFog", "rect": Rect2(2960, 144, 304, 176), "weather": WorldClock.Weather.FOG, "intensity": 0.85, "wind_scale": 0.45},
	]


func build(host: Node2D) -> void:
	for f in FLOORS:
		floor_strip(host, f[0], f[1], f[2], f[3], false, false)
	for s in STONES:
		if String(s[0]).begins_with("MausoleumRoof"):
			platform(host, s[0], s[1], Vector2(s[2], 32), "stone", true, true, SLAB_TONE)
		else:
			step(host, s[0], s[1], s[2], "floating", SLAB_TONE)
	walls(host, "ground")
	for n in NESTS:
		nest(host, n[0], n[1])
	_stele(host, "SteleHallen", STELE_A_POS)
	_stele(host, "SteleVeil", STELE_B_POS)
	_stele(host, "SteleTree", STELE_TREE_POS)
	plate_door(host, "Mausoleum", PLATE_FEET, DOOR_POS)
	hook(host, "HookTreeTop", HOOK_POS)
	pickup(host, "EmberCoreTreeTop", PICKUP_POS, &"ember_core")
	var item := EquipmentCatalog.bone_charm()
	reward(host, "RewardTreeTop", REWARD_FEET - Vector2(0, 7), "equipment", "bone_charm", item.display_name)
	for w in WAYMARKS:
		waymark(host, w[0], w[1])
	for m in MUD:
		force_zone(host, m[0], m[1], "mud", Vector2.ZERO, {"drag": 0.4, "toxin_per_second": m[2]})
	for e in ENEMIES:
		enemy(host, e[0], e[1], e[2], e[3])
	_build_decor(host)
	exit_door(host, EXIT_X, ChapterText.exit_label_of(level_id()), ChapterText.exit_captions_of(level_id()),
			"level06_done", GameContext.next_level_id(level_id()))
	finish(host)
	var zone := host.get_node_or_null("Props/MausoleumShelterIndoor") as AtmosphereZone
	if zone != null:
		zone.position = CRYPT_RECT.position


func _stele(host: Node2D, node_name: String, pos: Vector2) -> void:
	var entry := ChapterText.stele_of(level_id(), node_name)
	stele(host, node_name, pos, String(entry.get("title", "")), String(entry.get("text", "")))


func _build_decor(host: Node2D) -> void:
	var wall := MausoleumRelief.new()
	wall.name = "MausoleumRelief"
	wall.position = CRYPT_RECT.position
	decor_layer(host).add_child(wall)
	for p in [["door_arch", Vector2(40, 320)], ["stone_1", Vector2(304, 320)],
		["grave_cross", Vector2(576, 320)], ["stone_3", Vector2(680, 320)],
		["grave_cross", Vector2(848, 320)], ["stone_2", Vector2(912, 320)],
		["statue", Vector2(1408, 320)], ["balustrade", Vector2(1648, 320)],
		["grave_cross", Vector2(1808, 320)], ["stone_4", Vector2(1992, 320)],
		["statue", Vector2(2352, 320)], ["grave_cross", Vector2(1648, 160)],
		["stone_1", Vector2(1752, 160)], ["grave_cross", Vector2(2064, 160)],
		["balustrade", Vector2(2352, 160)], ["stone_2", Vector2(2448, 320)],
		["stone_4", Vector2(2664, 320)], ["grave_cross", Vector2(3024, 320)],
		["stone_1", Vector2(3208, 320)], ["balustrade", Vector2(3352, 320)],
		["grave_cross", Vector2(3520, 320)], ["stone_3", Vector2(3616, 320)],
		["statue", Vector2(3744, 320)], ["balustrade", Vector2(3896, 320)]]:
		prop(host, p[0], p[1])
	for pos in [Vector2(112, 320), Vector2(496, 320), Vector2(1088, 320), Vector2(2912, 320), Vector2(3304, 320)]:
		foliage(host, "bush_s", pos, 1.0)
	for pos in [Vector2(752, 320), Vector2(2704, 320), Vector2(3576, 320)]:
		foliage(host, "tree_1_px", pos, 1.0, true)
	foliage(host, "tree_2_px", Vector2(2848, 320), 1.0, true)


## 复用既有苔石填充作背墙；装饰无碰撞，拱口/柱线明确区分两条路线。
class MausoleumRelief extends Node2D:
	var FILL := ArtTexture.load_texture("res://assets/env/moss_fill.png")
	func _draw() -> void:
		draw_texture_rect(FILL, Rect2(0, 0, 1008, 128), true, Color(0.36, 0.35, 0.4))
		for x in [32, 272, 512, 752]:
			draw_rect(Rect2(x, 24, 176, 104), Color(0.035, 0.035, 0.05, 0.82))
			draw_rect(Rect2(x + 16, 8, 144, 16), Color(0.04, 0.04, 0.055, 0.82))
		for x in [0, 232, 472, 712, 976]:
			draw_texture_rect(FILL, Rect2(x, 0, 32, 128), true, Color(0.62, 0.59, 0.62))
			draw_line(Vector2(x, 0), Vector2(x, 128), Color(0.36, 0.35, 0.4), 1.0)
