extends ChapterLayout
## 钟舌竖井：交替上升的吊台、独立侧室与回到中段的单向坠井。

const ENTRY_SPAWN := Vector2(96, 300)
const EAST_LIMIT := 1600
const TOP_Y := -1280.0
const CEILING_Y := -1440.0
const NOOK_Y := -1360.0
const HOOK_UPPER_POS := Vector2(1096, -1400)
const STELE_NOOK_POS := Vector2(1144, NOOK_Y)
const WINDOW_TINT := Color(0.66, 0.68, 0.86)
const TORCH_TINT := Color(0.8, 0.82, 1.0)
const PLATE_FEET := Vector2(720, -160)
const DOOR_POS := Vector2(480, -224)
const EXIT_POS := Vector2(1240, TOP_Y)
const REWARD_FEET := Vector2(88, 80)
const DECKS: Array = [
	["GalleryA", Vector2(480, 80), 432.0], ["GalleryB", Vector2(480, -160), 432.0],
	["GalleryC", Vector2(480, -400), 432.0], ["Summit", Vector2(1024, -640), 512.0],
	["GalleryD", Vector2(480, -880), 432.0], ["GalleryE", Vector2(480, -1120), 432.0],
	["Crown", Vector2(1024, TOP_Y), 336.0], ["NookDeck", Vector2(1056, NOOK_Y), 128.0],
	["WestBellRoom", Vector2(64, 80), 288.0], ["EastWatchRoom", Vector2(1024, -400), 512.0],
]
## Old seven lift names remain; shafts stay at x384..464 / 928..1008.
const LIFTS: Array = [
	["LiftA", Vector2(384, 304)], ["LiftB", Vector2(928, 64)],
	["LiftC", Vector2(384, -176)], ["LiftD", Vector2(928, -416)],
	["LiftE", Vector2(928, -656)], ["LiftF", Vector2(384, -896)],
	["LiftG", Vector2(928, -1136)],
]
const LIFT_TRAVEL := Vector2(0, -240)
const LIFT_G_TRAVEL := Vector2(0, -160)
const LIFT_WIDTH := 80.0
const LIFT_PERIOD := 9.6
## [name, x, floor y]. Added rests bound the actual alternating path, not just altitude.
const NESTS: Array = [
	["EmberNestEntry", 176.0, 320.0], ["EmberNestLower", 608.0, 80.0],
	["EmberNestGallery", 544.0, -160.0], ["EmberNestClapper", 544.0, -400.0],
	["EmberNestSummit", 1264.0, -640.0], ["EmberNestHigh", 544.0, -880.0],
	["EmberNestUpper", 544.0, -1120.0], ["EmberNestCrown", 1052.0, TOP_Y],
]
const CLAPPERS: Array = [
	["ClapperLesson", Vector2(736, -32), 96.0, 40.0, 5.6, 0.25],
	["ClapperWest", Vector2(208, -32), 96.0, 40.0, 5.6, 0.25],
	["ClapperMiddle", Vector2(736, -512), 96.0, 44.0, 4.8, 0.0],
	["ClapperUpper", Vector2(736, -1232), 96.0, 44.0, 4.8, 0.5],
]
const ENEMIES: Array = [
	["Skeleton1", "skeleton", Vector2(312, 320), {"wake_range": 96.0, "lose_range": 180.0}],
	# First full encounter is on GalleryB, a floor above the clapper lesson.
	["Spitter2", "spitter", Vector2(832, -160), {"aggro_range": 160.0, "lose_range": 200.0}],
	["Ghost2", "ghost", Vector2(848, -208), {"wake_range": 100.0, "lose_range": 180.0}],
	["Demon1", "flying_demon", Vector2(848, -272), {"aggro_range": 128.0, "patrol_range": 16.0, "lose_range": 200.0}],
	# East room is a separate fight with an open western retreat.
	["Skeleton2", "skeleton", Vector2(1240, -400), {"variant": &"exploder_skeleton", "wake_range": 112.0, "lose_range": 180.0}],
	["Ghost1", "ghost", Vector2(1320, -448), {"wake_range": 100.0, "lose_range": 180.0}],
	["Spitter1", "spitter", Vector2(1456, -400), {"aggro_range": 160.0, "lose_range": 200.0}],
	# Third encounter spans the old empty bell frame and upper gallery.
	["Skeleton3", "skeleton", Vector2(800, -880), {"wake_range": 112.0, "lose_range": 180.0}],
	["Demon2", "flying_demon", Vector2(816, -980), {"aggro_range": 128.0, "patrol_range": 16.0, "lose_range": 200.0}],
	["Ghost3", "ghost", Vector2(848, -1168), {"wake_range": 100.0, "lose_range": 180.0}],
]
const PROPS: Array = [
	["window", Vector2(800, 320)], ["rubble_dry", Vector2(288, 320)],
	["balustrade", Vector2(112, 80)], ["window", Vector2(304, 80)],
	["rubble_dry_b", Vector2(496, 80)], ["window", Vector2(864, 80)],
	["balustrade", Vector2(864, -160)], ["window", Vector2(640, -160)],
	["balustrade", Vector2(520, -400)], ["window", Vector2(864, -400)],
	["altar", Vector2(1392, -400)], ["rubble_dry_c", Vector2(1072, -400)],
	["window", Vector2(1168, -400)], ["balustrade", Vector2(1488, -640)],
	["window", Vector2(1152, -640)], ["rubble_dry", Vector2(1392, -640)],
	["altar", Vector2(720, -880)], ["rubble_dry_b", Vector2(856, -880)],
	["window", Vector2(640, -880)], ["balustrade", Vector2(520, -1120)],
	["window", Vector2(864, -1120)],
]
const TORCHES: Array = [
	Vector2(80, 320), Vector2(400, 320), Vector2(1200, 320),
	Vector2(320, 80), Vector2(544, 80), Vector2(784, -160),
	Vector2(608, -400), Vector2(1504, -400), Vector2(1344, -640),
	Vector2(608, -880), Vector2(608, -1120), Vector2(1328, TOP_Y),
]


func level_id() -> String: return "level07"
func title() -> String: return ChapterText.title_of(level_id())
func wake_line() -> String: return ChapterText.wake_of(level_id())
func entry_spawn() -> Vector2: return ENTRY_SPAWN
func east_limit() -> int: return EAST_LIMIT
func camera_top() -> int: return -1472
func theme() -> String: return "belltower"
func motes() -> String: return "dust"


func build(host: Node2D) -> void:
	floor_strip(host, "Floor", 0, EAST_LIMIT, "castle", false, false)
	enclose(host, "castle", CEILING_Y)
	for d in DECKS:
		step(host, d[0], d[1], d[2], "castle_float")
	# Side rooms have their own roof and outer wall; their entrances face the shafts.
	platform(host, "CeilingWestRoom", Vector2(64, -64), Vector2(288, 16), "castle", false, false)
	platform(host, "WestRoomWall", Vector2(48, -64), Vector2(16, 160), "castle", false, false)
	platform(host, "CeilingEastRoom", Vector2(1024, -576), Vector2(512, 16), "castle", false, false)
	platform(host, "EastRoomWall", Vector2(1536, -576), Vector2(16, 192), "castle", false, false)
	for m in LIFTS:
		var travel := LIFT_G_TRAVEL if String(m[0]) == "LiftG" else LIFT_TRAVEL
		lift(host, m[0], m[1], travel, LIFT_PERIOD, LIFT_WIDTH, 0.0, CEILING_Y + 32)
	for c in CLAPPERS:
		pendulum(host, c[0], c[1], c[2], {"skin": "clapper", "swing_deg": c[3], "period": c[4], "phase": c[5]})
	plate_door(host, "BellGate", PLATE_FEET, DOOR_POS)
	for n in NESTS:
		nest(host, n[0], n[1], n[2])
	_stele(host, "SteleChain", Vector2(248, 320))
	_stele(host, "SteleBell", Vector2(624, -160))
	_stele(host, "SteleNook", STELE_NOOK_POS)
	# EquipmentPickup's 14px icon is centred at the node, so its bottom is +7px.
	reward(host, "RewardClapper", REWARD_FEET - Vector2(0, 7), "equipment", "bone_amulet", EquipmentCatalog.bone_amulet().display_name)
	waymark(host, Vector2(336, 320), "上行")
	waymark(host, Vector2(328, 80), "侧室")
	waymark(host, Vector2(1072, -400), "钟室")
	waymark(host, Vector2(1192, TOP_Y), "渣井")
	waymark(host, Vector2(1344, TOP_Y), "回巢")
	hook(host, "HookGallery", Vector2(940, -216))
	hook(host, "HookUpper", HOOK_UPPER_POS)
	exit_door(host, EXIT_POS.x, ChapterText.exit_label_of(level_id()), ChapterText.exit_captions_of(level_id()),
		"level07_done", GameContext.next_level_id(level_id()), TOP_Y)
	for e in ENEMIES:
		enemy(host, e[0], e[1], e[2], e[3])
	for p in TORCHES:
		torch(host, p.x, p.y, TORCH_TINT)
	for p in PROPS:
		prop(host, p[0], p[1], 1.0, WINDOW_TINT if p[0] == "window" else Color.WHITE)
	for x in [208.0, 736.0, 1280.0]:
		hanging(host, "chain", Vector2(x, CEILING_Y + 32), Color(0.62, 0.64, 0.78, 0.85))
	for x in [256.0, 1120.0]:
		hanging(host, "vine", Vector2(x, CEILING_Y + 32), Color(0.5, 0.5, 0.56, 0.7))
	finish(host)


func _stele(host: Node2D, node_name: String, pos: Vector2) -> void:
	var entry := ChapterText.stele_of(level_id(), node_name)
	stele(host, node_name, pos, String(entry.get("title", "")), String(entry.get("text", "")))
