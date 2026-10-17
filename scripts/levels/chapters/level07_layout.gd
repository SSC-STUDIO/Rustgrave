extends ChapterLayout
## 四段吊台沿两侧竖井交替上升；薄楼板接住失足者，给吊台和骑士留出净空。

const ENTRY_SPAWN := Vector2(96, 300)
const EAST_LIMIT := 1280
const TOP_Y := -640.0
const CEILING_Y := -800.0
const DECKS: Array = [
	["GalleryA", Vector2(480, 80), 432.0],
	["GalleryB", Vector2(480, -160), 432.0],
	["GalleryC", Vector2(480, -400), 432.0],
	["Summit", Vector2(1024, TOP_Y), 256.0],
]
const LIFTS: Array = [
	["LiftA", Vector2(384, 304)], ["LiftB", Vector2(928, 64)],
	["LiftC", Vector2(384, -176)], ["LiftD", Vector2(928, -416)],
]
const LIFT_TRAVEL := Vector2(0, -240)
const LIFT_WIDTH := 80.0
const LIFT_PERIOD := 9.6
const PLATE_FEET := Vector2(720, -160)
const DOOR_POS := Vector2(480, -224)
const EXIT_POS := Vector2(1172, TOP_Y)
const ENEMIES: Array = [
	["Skeleton1", "skeleton", Vector2(312, 320), {"wake_range": 96.0}],
	["Skeleton2", "skeleton", Vector2(720, 80)],
	["Spitter1", "spitter", Vector2(848, 80)],
	["Ghost1", "ghost", Vector2(576, 32), {"wake_range": 160.0}],
	["Demon1", "flying_demon", Vector2(848, -272)],
	["Ghost2", "ghost", Vector2(808, -192)],
	["Spitter2", "spitter", Vector2(848, -400)],
	["Demon2", "flying_demon", Vector2(608, -496)],
]


func level_id() -> String:
	return "level07"


func title() -> String:
	return "锈墓・柒 — 钟楼"


func wake_line() -> String:
	return "钟舌被熔掉，铸成最后一枚核。你背上的，是它的回声。"


func entry_spawn() -> Vector2:
	return ENTRY_SPAWN


func east_limit() -> int:
	return EAST_LIMIT


func camera_top() -> int:
	return -832


func theme() -> String:
	return "belltower"


func motes() -> String:
	return "dust"


func build(host: Node2D) -> void:
	floor_strip(host, "Floor", 0, EAST_LIMIT, "castle", false, false)
	enclose(host, "castle", CEILING_Y)
	for deck in DECKS:
		step(host, deck[0], deck[1], deck[2], "castle_float")
	for item in LIFTS:
		lift(host, item[0], item[1], LIFT_TRAVEL, LIFT_PERIOD, LIFT_WIDTH, 0.0, CEILING_Y + 32)
	plate_door(host, "BellGate", PLATE_FEET, DOOR_POS)
	nest(host, "EmberNestEntry", 176)
	nest(host, "EmberNestGallery", 544, -160)
	nest(host, "EmberNestSummit", 1052, TOP_Y)
	stele(host, "SteleChain", Vector2(248, 320), "守钟人 · 链", "钟不响，链不停。钟舌不在了。它被熔成一枚核。")
	stele(host, "SteleBell", Vector2(624, -160), "守钟人 · 舌", "他们熔掉钟舌，铸了最后一枚锈核。你剑上的回声，就是它。")
	waymark(host, Vector2(336, 320), "上行")
	# 塔顶只有 256px：栏杆让出来，巢、路牌、门、火把才排得开。
	# 巢视觉 1036..1084，牌 1099..1134，门 1148..1196，火把 1216..1280。
	waymark(host, Vector2(1116, TOP_Y), "渣井")
	hook(host, "HookGallery", Vector2(940, -216))
	hook(host, "HookUpper", Vector2(396, -456))
	exit_door(host, EXIT_POS.x, "运渣井门", PackedStringArray([
		"井下的渣还热。", "它记得每一把剑，包括你这一把。",
	]), "level07_done", "level08", TOP_Y)
	for e in ENEMIES:
		enemy(host, e[0], e[1], e[2], e[3] if e.size() > 3 else {})
	# 塔顶火把原在 1232，墙板从 1200 起，和出口门叠在一起。现在门右缘 1196，火把左缘 1216。
	for feet in [Vector2(80, 320), Vector2(656, 80), Vector2(784, -160), Vector2(656, -400), Vector2(1248, TOP_Y)]:
		torch(host, feet.x, feet.y, Color(0.8, 0.82, 1.0))
	for feet in [Vector2(520, 80), Vector2(888, -160), Vector2(520, -400)]:
		prop(host, "balustrade", feet, 0.7)
	for feet in [Vector2(800, 320), Vector2(736, 80), Vector2(688, -160), Vector2(736, -400)]:
		prop(host, "window", feet, 0.65, Color(0.65, 0.65, 0.85))
	# 鲜绿苔藤是地窟的。钟楼里压成灰，才像梁上的积尘。
	for x in [256.0, 672.0, 1120.0]:
		hanging(host, "vine", Vector2(x, CEILING_Y + 32), Color(0.5, 0.5, 0.56, 0.7))
	finish(host)
