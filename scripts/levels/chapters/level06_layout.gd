extends ChapterLayout
## 锈墓・陆 — 墓园夜雨。从工坊的运渣道爬回地面，是墓园的另一侧：锈雨、幽魂、
## 从土里起来的骸骨。室外，第一关同款天空（graveyard 主题）。
##
## 结构（地面 y=320，一跳 ≤32px 高 / ≤72px 远）：
##   ① 出土口   0–450     运渣道石门洞、余烬巢、墓志、老树、路牌「墓园」
##   ② 坟堆丛   450–928   一座 32px 土坟（顶上十字）、骸骨 ×2、墓碑密集
##   ③ 腐液沟   928–1152  毒坑上两块浮石（288 / 272），落点一只幽魂
##   ④ 陵门     1152–1520 压板在 32px 土丘上，闸门在地面，两侧壁炬石墩；门后守着第二只幽魂
##   ⑤ 高坟台   1520–1900 两级 32px 土台，台顶喷吐者，台下碎铁犬巡逻
##   ⑥ 骸骨林   1900–2304 骸骨 ×2、第二余烬巢、墓志；老树顶上一块浮石，钩锁锚点通向余烬核
##   ⑦ 长毒沟   2304–2608 更长的毒坑，三块浮石（288 / 272 / 288）
##   ⑧ 钟楼门   2608–2880 路牌「钟楼」、两侧壁炬石墩夹着出口
##
## 土台约定：踩在地面上的土丘比上升高度多铺一格（32 高 → 48 厚），底行埋进草皮，
## 读作从土里鼓起来的坟，而不是放在草上的箱子。

const EAST := 2880
const PIT_DEPTH := 32.0
## 毒坑床顶 = FLOOR_Y + PIT_DEPTH；两侧一跳 32px 爬出。
const PIT_BED_Y := FLOOR_Y + PIT_DEPTH
## 墓园里毒液保持原色（第一关同款）；地窟的酸黄绿是给青砖苔盖用的。
const TOXIN_TINT := Color.WHITE

## [name, x0, x1, cap_left, cap_right]
const FLOORS: Array = [
	["FloorA", 0.0, 928.0, false, true],
	["FloorD", 1152.0, 2304.0, true, true],
	["FloorH", 2608.0, 2880.0, true, false],
]
## [name, x0, x1]
const PITS: Array = [
	["PitC", 928.0, 1152.0],
	["PitG", 2304.0, 2608.0],
]
## 土丘 / 土台：[name, pos, size]（ground 皮肤，48 厚 = 32 上升 + 一格埋进下方台面）
const MOUNDS: Array = [
	["MoundB", Vector2(560, 288), Vector2(96, 48)],
	["MoundD", Vector2(1232, 288), Vector2(80, 48)],
	["TerraceE1", Vector2(1632, 288), Vector2(208, 48)],
	["TerraceE2", Vector2(1696, 256), Vector2(96, 48)],
]
## 浮石：[name, pos, width]（floating 皮肤，16 厚）
const STONES: Array = [
	["StoneC1", Vector2(976, 288), 48.0],
	["StoneC2", Vector2(1064, 272), 48.0],
	["TreeTopStone", Vector2(2022, 232), 48.0],
	["StoneG1", Vector2(2352, 288), 48.0],
	["StoneG2", Vector2(2448, 272), 48.0],
	["StoneG3", Vector2(2544, 288), 48.0],
]
## 主路线台阶链（测试用）：每一步上升 ≤32、横跨 ≤72。
const CHAINS: Array = [
	# ② 坟堆：地面 → 土坟顶 → 地面
	[Vector2(556, 320), Vector2(564, 288), Vector2(652, 288), Vector2(660, 320)],
	# ③ 腐液沟：坑沿 → 浮石 → 浮石 → 对岸
	[Vector2(928, 320), Vector2(976, 288), Vector2(1064, 272), Vector2(1152, 320)],
	# ④ 陵门：地面 → 压板土丘
	[Vector2(1228, 320), Vector2(1236, 288)],
	# ⑤ 高坟台：地面 → 一级 → 二级 → 一级 → 地面
	[Vector2(1628, 320), Vector2(1636, 288), Vector2(1700, 256), Vector2(1796, 288), Vector2(1844, 320)],
	# ⑦ 长毒沟：坑沿 → 三块浮石 → 对岸
	[Vector2(2304, 320), Vector2(2352, 288), Vector2(2448, 272), Vector2(2544, 288), Vector2(2608, 320)],
]
const PLATE_FEET := Vector2(1272, 288)
const DOOR_POS := Vector2(1400, 256)
const HOOK_POS := Vector2(2046, 144)
const PICKUP_POS := Vector2(2046, 192)
const NEST_START_X := 176.0
const NEST_GROVE_X := 2120.0
const STELE_A_POS := Vector2(256, 320)
const STELE_B_POS := Vector2(2176, 320)
const EXIT_X := 2760.0
## [name, kind, pos]：落地敌人给脚点，幽魂给悬停中心。
const ENEMIES: Array = [
	["Skeleton1", "skeleton", Vector2(500, 320)],
	["Skeleton2", "skeleton", Vector2(740, 320)],
	["Ghost1", "ghost", Vector2(1192, 240)],
	["Ghost2", "ghost", Vector2(1568, 236)],
	["Scrapper1", "scrapper", Vector2(1592, 320)],
	["Spitter1", "spitter", Vector2(1744, 256)],
	["Skeleton3", "skeleton", Vector2(2020, 320)],
	["Skeleton4", "skeleton", Vector2(2236, 320)],
]
## 壁炬石墩（64×192 墙板，板底贴地）：陵门两侧、钟楼门两侧。
const TORCHES: Array = [1360.0, 1456.0, 2708.0, 2812.0]
const WAYMARKS: Array = [[Vector2(416, 320), "墓园"], [Vector2(2648, 320), "钟楼"]]


func level_id() -> String:
	return "level06"


func title() -> String:
	return "锈墓・陆 — 墓园夜雨"


func wake_line() -> String:
	return "锈雨在下。土里的骸骨还记得剑的形状。"


func entry_spawn() -> Vector2:
	return Vector2(96, 300)


func default_spawn() -> Vector2:
	return entry_spawn()


func east_limit() -> int:
	return EAST


func camera_top() -> int:
	return -48


func theme() -> String:
	return "graveyard"


func build(host: Node2D) -> void:
	_build_terrain(host)
	_build_props(host)
	_build_enemies(host)
	_build_decor(host)
	exit_door(host, EXIT_X, "钟楼门", PackedStringArray([
		"钟声很近了。雨把土里的骸骨又埋回去。",
		"门后是向上的楼梯。每一级都在响。",
	]), "level06_done", GameContext.next_level_id(level_id()))
	finish(host)


func _build_terrain(host: Node2D) -> void:
	for f in FLOORS:
		floor_strip(host, String(f[0]), float(f[1]), float(f[2]), "ground", bool(f[3]), bool(f[4]))
	for p in PITS:
		toxin_pit(host, String(p[0]), float(p[1]), float(p[2]), PIT_DEPTH, "ground", TOXIN_TINT)
	# 先铺低的再铺高的：后加的画在前面，二级台才盖住一级台的草皮。
	for m in MOUNDS:
		platform(host, String(m[0]), m[1] as Vector2, m[2] as Vector2, "ground")
	for s in STONES:
		step(host, String(s[0]), s[1] as Vector2, float(s[2]), "floating")
	walls(host, "ground")


func _build_props(host: Node2D) -> void:
	nest(host, "EmberNestStart", NEST_START_X)
	nest(host, "EmberNestGrove", NEST_GROVE_X)
	stele(host, "SteleHallen", STELE_A_POS, "墓志 · 哈伦",
			"锻工哈伦，葬于此土，无剑。剑被拆去做了钟楼的门闩。")
	stele(host, "SteleVeil", STELE_B_POS, "墓志 · 薇尔",
			"锻工薇尔，与三把剑同葬。土里只剩下她；剑自己走了。")
	plate_door(host, "Mausoleum", PLATE_FEET, DOOR_POS)
	hook(host, "HookTreeTop", HOOK_POS)
	pickup(host, "EmberCoreTreeTop", PICKUP_POS, &"ember_core")
	for w in WAYMARKS:
		waymark(host, w[0] as Vector2, String(w[1]))


func _build_enemies(host: Node2D) -> void:
	for e in ENEMIES:
		enemy(host, String(e[0]), String(e[1]), e[2] as Vector2)


## foliage(): feet.x 是贴图左下角；prop(): feet.x 是底边中点。
func _build_decor(host: Node2D) -> void:
	# ① 出土口：运渣道的石门洞压暗成背景，读作「刚从这里爬出来」。
	prop(host, "door_arch", Vector2(40, 320), 1.0, Color(0.62, 0.6, 0.72))
	foliage(host, "bush_s", Vector2(112, 320), 1.0)
	prop(host, "stone_1", Vector2(222, 320))
	foliage(host, "tree_2", Vector2(296, 320), 0.55, true)
	prop(host, "stone_3", Vector2(452, 320))
	# ② 坟堆丛
	foliage(host, "bush_l", Vector2(508, 320), 0.62)
	prop(host, "grave_cross", Vector2(608, 288))
	prop(host, "stone_4", Vector2(688, 320))
	foliage(host, "tree_1", Vector2(776, 320), 0.5, true)
	prop(host, "grave_cross", Vector2(888, 320))
	# ④ 陵门：石墩 + 闸门 + 守墓者
	prop(host, "stone_1", Vector2(1216, 320))
	prop(host, "statue", Vector2(1512, 320))
	# ⑤ 高坟台：台上两块小碑，台下一段石栏
	prop(host, "stone_2", Vector2(1648, 288))
	prop(host, "stone_4", Vector2(1816, 288))
	prop(host, "balustrade", Vector2(1900, 320))
	# ⑥ 骸骨林：浮石压在老树的树冠上
	foliage(host, "tree_1", Vector2(1996, 320), 0.6, true)
	prop(host, "stone_3", Vector2(2080, 320))
	foliage(host, "tree_2", Vector2(2184, 320), 0.5, true)
	foliage(host, "bush_s", Vector2(2270, 320), 1.0)
	# ⑧ 钟楼门
	prop(host, "stone_2", Vector2(2632, 320))
	for x in TORCHES:
		torch(host, float(x))
