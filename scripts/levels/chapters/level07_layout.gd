extends ChapterLayout
## 锈墓・柒 — 钟楼：竖向塔身，四段吊台沿两侧竖井交替上升；薄楼板接住失足者。
##
## 玩法变化（竖向关）：主路线是「吊台 + 跳」的节奏循环，两侧竖井交替使用；
## 塔顶窄台（Summit 只有 256px）把存档点、路牌、出口门、火把挤在一起，
## 是一关里唯一「一步都不能走错」的高潮。
##
## 有奖励支路（HookUpper 支线）：GalleryC 正上方的钩锁锚点把骑士拉进 NookDeck
## （贴着顶板的壁龛，只有钩锁能上）。壁龛里是守钟人最后一句碑文——
## 全章都在说「钟舌铸成最后一枚核、又被系在链尾」，这里就是那枚核的归处与收束。
## 支路奖励是「世界信息 + 一个选择」（上去读最后一句 / 不上去），不是「第二插座」：
## 玩家到第七章一定有钩锁，再给一枚系核只是同名能力，无新增空间许可。
## 主路线不经过这里，没有钩锁也能通关（level_sanity 主路线 allow_hook=false）。
##
## 结构（竖向；单跳 ≤32px 高、≤72px 跨）：
##   ① 井底   y=320    地面 Floor、入口巢、入口碑、骸骨伏击、第一座吊台
##   ② 一层   y=80     GalleryA；中层巢；吊台 B 把骑士送到东侧
##   ③ 二层   y=-160   GalleryB；中层压板开「BellGate」；上层巢
##   ④ 三层   y=-400   GalleryC；吊台 D；守钟人碑文
##   ⑤ 旧塔顶 y=-640   旧 Summit（256px）：中段落脚，吊台 E 继续向上
##   ⑥ 四层   y=-880   GalleryD：空钟残响层（旧钟架/断链的氛围层）
##   ⑦ 五层   y=-1120  GalleryE：更高的窄台，吊台 G 送进新塔顶
##   ⑧ 塔顶   y=-1280  Crown（256px）：第三巢、路牌、出口「运渣井门」；总高 1600
##   可选：顶板壁龛 NookDeck（y=-560）——钩锁锚点 HookUpper + 碑文（仍在 GalleryC 上方）

const ENTRY_SPAWN := Vector2(96, 300)
const EAST_LIMIT := 1280
const TOP_Y := -1280.0
const CEILING_Y := -1440.0
## 顶板壁龛（NookDeck）：藏在新塔顶 Crown 上方的顶板缝里。
## 钩锁锚点（HookUpper）悬在壁龛正上方：从 Crown（-1280）起跳在 250px 索距内，
## 落台 NookDeck 在锚点下方 40px、横向 0px，是标准钩锁降落。
## 它比所有可站立台面都高，主路线没有任何落脚面能在 160px 内落到它上面 ——
## 只能钩锁上去（level_sanity 主路线 allow_hook=false 不可达）。
const NOOK_Y := -1360.0
const HOOK_UPPER_POS := Vector2(1040, -1400)
## 支路碑文：站在壁龛台面上读（台面顶 -1360，碑底贴着它）。
const STELE_NOOK_POS := Vector2(1104, NOOK_Y)
const DECKS: Array = [
	["GalleryA", Vector2(480, 80), 432.0],
	["GalleryB", Vector2(480, -160), 432.0],
	["GalleryC", Vector2(480, -400), 432.0],
	["Summit", Vector2(1024, -640), 256.0],
	# 竖高扩章：旧塔顶之上再叠三层（总高 1600）。
	["GalleryD", Vector2(480, -880), 432.0],
	["GalleryE", Vector2(480, -1120), 432.0],
	["Crown", Vector2(1024, -1280), 256.0],
	# 可选支路台面：藏在塔顶 Crown 上方的顶板缝里，宽 96，钩锁落点。
	# 名字不能以 Ceiling 开头：LevelSanity.top_segments() 会把顶板类平台
	# 当不可站立的屋顶跳过，支路台面必须叫 NookDeck。
	["NookDeck", Vector2(1008, NOOK_Y), 96.0],
]
## 六座吊台：A→GalleryA→B→GalleryB→C→GalleryC→D→旧Summit→E→GalleryD→F→GalleryE→G→Crown。
const LIFTS: Array = [
	["LiftA", Vector2(384, 304)], ["LiftB", Vector2(928, 64)],
	["LiftC", Vector2(384, -176)], ["LiftD", Vector2(928, -416)],
	["LiftE", Vector2(928, -656)], ["LiftF", Vector2(384, -896)],
	["LiftG", Vector2(928, -1136)],
]
const LIFT_TRAVEL := Vector2(0, -240)
## 最后一部吊台只升 160：把骑士送到 Crown（-1280）比 GalleryE 高一层。
const LIFT_G_TRAVEL := Vector2(0, -160)
const LIFT_WIDTH := 80.0
const LIFT_PERIOD := 9.6
## 钟楼是橄榄城砖 + 冷光的室内；尖窗玻璃压成月光色，不是教堂的紫窗。
const WINDOW_TINT := Color(0.66, 0.68, 0.86)
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
	## ⑯ 竖高扩章：旧钟架层（GalleryD）的骸骨与更上层（GalleryE）的幽魂。
	["Skeleton3", "skeleton", Vector2(700, -880)],
	["Ghost3", "ghost", Vector2(808, -1104)],
]


func level_id() -> String:
	return "level07"


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


func camera_top() -> int:
	return -1472


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
		var travel := LIFT_G_TRAVEL if String(item[0]) == "LiftG" else LIFT_TRAVEL
		lift(host, item[0], item[1], travel, LIFT_PERIOD, LIFT_WIDTH, 0.0, CEILING_Y + 32)
	plate_door(host, "BellGate", PLATE_FEET, DOOR_POS)
	nest(host, "EmberNestEntry", 176)
	nest(host, "EmberNestGallery", 544, -160)
	nest(host, "EmberNestSummit", 1052, -640)
	nest(host, "EmberNestCrown", 1052, TOP_Y)
	_stele(host, "SteleChain", Vector2(248, 320))
	_stele(host, "SteleBell", Vector2(624, -160))
	# 支路碑文：贴顶板的壁龛里，只有钩锁上去的人读得到。
	_stele(host, "SteleNook", STELE_NOOK_POS)
	waymark(host, Vector2(336, 320), "上行")
	# 塔顶只有 256px：巢、路牌、门、火把排得开（门右缘 1196，火把左缘 1216）。
	waymark(host, Vector2(1116, TOP_Y), "渣井")
	hook(host, "HookGallery", Vector2(940, -216))
	# 支路锚点：从 GalleryC（-400）起跳在 250px 索距内，落点 NookDeck 在锚点下方
	# 40px、横向 0px，是标准钩锁降落。没有钩锁也能通关（主路线不依赖它）。
	hook(host, "HookUpper", HOOK_UPPER_POS)
	exit_door(host, EXIT_POS.x, ChapterText.exit_label_of(level_id()),
			ChapterText.exit_captions_of(level_id()), "level07_done",
			GameContext.next_level_id(level_id()), TOP_Y)
	for e in ENEMIES:
		enemy(host, e[0], e[1], e[2], e[3] if e.size() > 3 else {})
	# 塔底两盏 + 每层一盏：井底不再是近黑，竖井每一层都有可见的落点边线。
	var torch_tint := Color(0.8, 0.82, 1.0)
	for feet in [Vector2(80, 320), Vector2(400, 320), Vector2(1200, 320),
			Vector2(656, 80), Vector2(784, -160), Vector2(656, -400),
			Vector2(656, -880), Vector2(784, -1120), Vector2(1248, TOP_Y)]:
		torch(host, feet.x, feet.y, torch_tint)
	# 1x 整数缩放：0.7 / 0.65 会把像素拉成半格，近看是软边（docs/art-spec.md）。
	for feet in [Vector2(520, 80), Vector2(520, -400), Vector2(520, -880), Vector2(520, -1120)]:
		prop(host, "balustrade", feet, 1.0)
	# GalleryB 东端 912：80px 石栏在 888 会探出台面 16px，收到 864。
	prop(host, "balustrade", Vector2(864, -160), 1.0)
	# 尖窗是墙面装饰（z=-3），让开 64px 宽的壁炬墙板（624..688 / 752..816），
	# 否则窗框会被火盘吞掉一半。
	for feet in [Vector2(800, 320), Vector2(768, 80), Vector2(640, -160), Vector2(768, -400),
			Vector2(768, -880), Vector2(640, -1120)]:
		prop(host, "window", feet, 1.0, WINDOW_TINT)
	# GalleryD（旧塔顶之上）是「空钟残响」氛围层：拆下来的钟架基座、断链与碎石，
	# 没有钟，只剩钟被搬走以后留下的一圈刮痕。
	prop(host, "altar", Vector2(700, -880), 1.0, Color(0.74, 0.76, 0.9))
	prop(host, "rubble_dry", Vector2(560, -880))
	prop(host, "rubble_dry_b", Vector2(820, -880))
	for x in [640.0, 760.0]:
		hanging(host, "chain", Vector2(x, CEILING_Y + 32), Color(0.62, 0.64, 0.78, 0.85))
	# 鲜绿苔藤是地窟的。钟楼里压成灰，才像梁上的积尘。
	for x in [256.0, 672.0, 1120.0]:
		hanging(host, "vine", Vector2(x, CEILING_Y + 32), Color(0.5, 0.5, 0.56, 0.7))
	finish(host)
