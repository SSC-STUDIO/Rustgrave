extends ChapterLayout
## 锈墓・肆 — 圣殿中庭：炉约的圣殿。吊灯还亮着，石像鬼在数进来的人。
##
## 结构（地面 y=320，一跳 ≤32px 高、≤72px 跨；室内，冷紫石板）：
##   ① 前厅      0–544     出生、余烬巢、碑文「圣殿铭」、路牌「圣殿」
##   ② 洗礼池    544–864   毒池上的三块浮石；幽魂守着落点
##   ③ 唱诗台    864–1360  两级石阶 → 唱诗台（压板）；闸门锁在中殿地面；幽魂在台上，碎铁犬在台下
##   ④ 齿盾卫走廊 1360–1856 第一只齿盾卫守窄路；走廊尽头是讲坛，喷吐者站在上面
##   ⑤ 廊桥      1856–2336 六跳悬空石链，下方毒池；第四块石上有中段余烬巢
##   ⑥ 祭坛区    2336–3008 第二余烬巢、碑文「炉约」、祭坛、第二只齿盾卫、锈门（热锻）、工坊暗门
##   可选：祭坛上方拱顶下有钩锁锚点 + 高台，台上悬着一枚余烬核；
##         高台东端还有一块碑文（世界信息），让支路不只是多一枚核。

const EAST_LIMIT := 3008
const CAMERA_TOP := -96
const CEILING_Y := -32.0
const ENTRY_SPAWN := Vector2(96, 300)

## 圣殿石板压成冷紫；浮石略亮一点，和地面拉开。
const STONE_TONE := Color(0.9, 0.88, 1.0)
const FLOAT_TONE := Color(0.94, 0.92, 1.0)
## 壁炬墙板是墓园紫石，压冷一点融进殿墙；藤蔓当成落灰的帷幔。
const TORCH_TINT := Color(0.8, 0.82, 1.0)
const VINE_TINT := Color(0.62, 0.62, 0.8, 0.85)
## Phase 3: the spec's orange coolant (GDD: 橙色腐液) instead of acid green. The cold slate
## nave makes orange the most readable hazard colour; the tint stays neutral and the sludge
## art is ramp-mapped onto orange (ToxinPool.set_sludge_ramp).
const TOXIN_TINT := Color.WHITE
const TOXIN_RAMP := [Color("#1a0702"), Color("#5a1d06"), Color("#a8410c"), Color("#e8761c"), Color("#ffc067")]
const TOXIN_VAPOR := Color(1.7, 0.62, 0.3)

## [name, x0, x1, cap_left, cap_right]
const FLOORS: Array = [
	["FloorA", 0.0, 544.0, false, true],
	["FloorB", 864.0, 1360.0, true, true],
	["FloorC", 1360.0, 1856.0, true, true],
	["FloorD", 2336.0, 3008.0, true, false],
]
## [name, x0, x1] —— 坑底 352，液面 336..368，两侧一跳（32）爬出。
const PITS: Array = [
	["Font", 544.0, 864.0],
	["Nave", 1856.0, 2336.0],
]
## 悬空浮石 [name, pos, width]（16 厚，floating 皮肤）。
const STEPS: Array = [
	["StoneF1", Vector2(592, 288), 48.0],
	["StoneF2", Vector2(688, 264), 48.0],
	["StoneF3", Vector2(784, 288), 48.0],
	["BridgeB1", Vector2(1904, 288), 48.0],
	["BridgeB2", Vector2(2000, 264), 48.0],
	["BridgeB3", Vector2(2088, 240), 64.0],
	["BridgeB4", Vector2(2200, 264), 48.0],
	["BridgeB5", Vector2(2272, 288), 48.0],
	["VaultLedge", Vector2(2432, 152), 96.0],
]
## 实心石台 [name, pos, size]（stone 皮肤）：唱诗台的两级台阶与台面、讲坛与它的台阶。
## 64 高的台面拆成两块 32 高的叠石：LevelSanity 会把整块 64 高的实心读成
## 压在地面上的墙（没有净空），拆开后每一级都只是一步台阶。
const BLOCKS: Array = [
	["ChoirStep1", Vector2(976, 288), Vector2(48, 32)],
	["ChoirStep2Base", Vector2(1056, 288), Vector2(48, 32)],
	["ChoirStep2", Vector2(1056, 256), Vector2(48, 32)],
	["ChoirRecoveryStep", Vector2(1104, 288), Vector2(32, 32)],
	["ChoirLoft", Vector2(1136, 224), Vector2(160, 32)],
	["PulpitStep", Vector2(1728, 288), Vector2(48, 32)],
	["PulpitBase", Vector2(1776, 288), Vector2(64, 32)],
	["Pulpit", Vector2(1776, 256), Vector2(64, 32)],
]
## 台阶链（平台名），测试逐段验证一跳可达。
const FONT_CHAIN: Array = ["FloorA", "StoneF1", "StoneF2", "StoneF3", "FloorB"]
const CHOIR_CHAIN: Array = ["FloorB", "ChoirStep1", "ChoirStep2", "ChoirLoft"]
const PULPIT_CHAIN: Array = ["FloorC", "PulpitStep", "Pulpit"]
const BRIDGE_CHAIN: Array = ["FloorC", "BridgeB1", "BridgeB2", "BridgeB3", "BridgeB4", "BridgeB5", "FloorD"]

const NEST_NAVE_X := 176.0
const NEST_ALTAR_X := 2384.0
## 廊桥第四块浮石上的小巢：桥中段唯一一处落在喷吐者 380px 射程外的平面。
## 死在中段的人从 2224 重来，而不是走回 176。
const NEST_BRIDGE_X := 2224.0
const NEST_BRIDGE_Y := 264.0
const STELE_A_POS := Vector2(248, 320)
const STELE_B_POS := Vector2(2496, 320)
## 压板在唱诗台面上（脚点 y=224）；闸门立在中殿地面，门顶 256、门底 320。
const PLATE_FEET := Vector2(1168, 224)
const DOOR_POS := Vector2(1328, 256)
const GATE_POS := Vector2(2800, 256)
## 拱顶锚点：从祭坛区地面（起跳面 320-48）到锚点 176px，落到 VaultLedge（152）在锚点下方 56px。
const HOOK_POS := Vector2(2416, 96)
const PICKUP_POS := Vector2(2480, 136)
## 支路碑文：拱顶高台东端，和余烬核错开。只有钩锁能读，是本章的支路奖励。
## 它说的是「灯照不到的地方」——炉约的代价被谁收走了。
const STELE_VAULT_POS := Vector2(2504, 152)
const EXIT_X := 2928.0
const WAYMARKS: Array = [[Vector2(300, 320), "圣殿"], [Vector2(2440, 320), "祭坛"]]

## [name, kind, pos, overrides]
## 齿盾卫的巡逻范围收窄：一只离唱诗台/闸门西侧 ≥300（否则隔着门朝台上放弹），
## 一只离第二个巢 ≥300（点巢的人不该挨弹）。
const ENEMIES: Array = [
	["Ghost1", "ghost", Vector2(944, 232), {}],
	["Scrapper1", "scrapper", Vector2(1216, 320), {"patrol_range": 48.0}],
	["Ghost2", "ghost", Vector2(1208, 176), {}],
	["GearShield1", "gear_shield", Vector2(1664, 320), {"patrol_range": 40.0}],
	["Spitter1", "spitter", Vector2(1808, 256), {}],
	["GearShield2", "gear_shield", Vector2(2736, 320), {"patrol_range": 16.0}],
]

## 壁炬 x（64px 墙板以 x 为中心，板底贴地面）。
## 880 的左缘在 848，洗礼池铺到 864，有一截悬在毒液上。896 起整块落在 FloorB。
const TORCHES: Array = [352.0, 896.0, 1544.0, 2768.0]
## 接地装饰 [key, feet]。墙板都是背景层，避开浮石落点正上方。
## 洗礼池（544–864）与廊桥坑（1856–2336）是毒液：装饰只立在两侧岸上。
const PROPS: Array = [
	["window", Vector2(72, 320)],
	["gargoyle", Vector2(424, 320)],
	["balustrade", Vector2(504, 320)],
	# 壁炬 896 的墙板铺到 928。柱心再往西，128px 的骷髅柱会吞掉火把。
	["skull_column", Vector2(1008, 320)],
	["column", Vector2(1176, 320)],
	["balustrade", Vector2(1256, 224)],
	["window", Vector2(1440, 320)],
	["skull_column", Vector2(1752, 320)],
	["balustrade", Vector2(2560, 320)],
	["altar", Vector2(2672, 320)],
	["gargoyle", Vector2(2868, 320)],
	# 前厅与洗礼池东岸：柱影、残碑、塌下来的碎渣。
	["column", Vector2(160, 320)],
	["window", Vector2(248, 320)],
	["slab", Vector2(880, 320)],
	["rubble_dry", Vector2(944, 320)],
	["rubble_dry_b", Vector2(1336, 320)],
	["rubble_dry_c", Vector2(1616, 320)],
	# 廊桥西侧走廊与祭坛区东端：桥头散座、桥尾的碎渣。
	["rubble_dry", Vector2(1824, 320)],
	# 岩架下方留空：VaultLedge 的钩锁落点在 2432，装饰别贴到落点下面。
	["slab", Vector2(2360, 320)],
	["rubble_dry_c", Vector2(2960, 320)],
	# 唱诗台与讲坛的踏步旁：阶缝里的碎石。
	["rubble_dry", Vector2(952, 320)],
	["rubble_dry_b", Vector2(1080, 288)],
	["slab", Vector2(1720, 320)],
	["rubble_dry", Vector2(1792, 320)],
]
const VINES: Array = [248.0, 656.0, 1096.0, 1320.0, 1600.0, 2040.0, 2280.0, 2600.0]
## 前厅与中殿之间垂下来的帷幔：祭坛区的纱幔比别处厚（烛火 mote 同源）。
const DRAPES: Array = [
	[Vector2(336, 0), Color(0.62, 0.62, 0.8, 0.8)],
	[Vector2(1504, 0), Color(0.62, 0.62, 0.8, 0.8)],
	[Vector2(2720, 0), Color(0.62, 0.62, 0.8, 0.8)],
]


func level_id() -> String:
	return "level04"


func title() -> String:
	return "锈墓・肆 — 圣殿中庭"


func wake_line() -> String:
	return "灯还亮着。签过名的手，已经成灰。"


func entry_spawn() -> Vector2:
	return ENTRY_SPAWN


func east_limit() -> int:
	return EAST_LIMIT


func camera_top() -> int:
	return CAMERA_TOP


func theme() -> String:
	return "cathedral"


func motes() -> String:
	return "candle"


## 圣殿有顶：天上是什么只在破顶的天窗那一片算数，整关的天气就压在薄雾/晴之间。
func weather_recipe() -> Dictionary:
	return {
		"allowed": [WorldClock.Weather.HAZE, WorldClock.Weather.CLEAR],
		"hold": Vector2(320.0, 520.0),
		"intensity": Vector2(0.4, 0.8),
	}


## ⑤ 廊桥（1856–2336）：拱顶在这里塌了，是整座圣殿唯一淋得到雨的地方。
## 站上桥面，室内感就地让位给雨；走回走廊或祭坛区，又是干燥的室内。
func weather_regions() -> Array:
	return [
		{"name": "BrokenVault", "rect": Rect2(1856, -32, 480, 432),
			"weather": WorldClock.Weather.RAIN, "intensity": 0.85, "outdoor": true},
	]


func build(host: Node2D) -> void:
	_build_terrain(host)
	_build_props(host)
	_build_enemies(host)
	_build_decor(host)
	exit_door(host, EXIT_X, "工坊暗门", PackedStringArray([
		"暗门后是工坊。",
		"剑上的插座，是在那里切开的。",
	]), "level04_done", GameContext.next_level_id(level_id()))
	finish(host)


func _build_terrain(host: Node2D) -> void:
	for f in FLOORS:
		floor_strip(host, f[0], f[1], f[2], "nave", f[3], f[4], FLOOR_Y, STONE_TONE)
	for p in PITS:
		var pool := toxin_pit(host, p[0], p[1], p[2], 32.0, "nave", TOXIN_TINT)
		if pool != null:
			pool.set_sludge_ramp(TOXIN_RAMP, TOXIN_VAPOR)
	for s in STEPS:
		step(host, s[0], s[1], s[2], "nave_float", FLOAT_TONE)
	for b in BLOCKS:
		platform(host, b[0], b[1], b[2], "nave", true, true, STONE_TONE)
	enclose(host, "nave", CEILING_Y, -1.0, 0.0, STONE_TONE)


func _build_props(host: Node2D) -> void:
	nest(host, "EmberNestNave", NEST_NAVE_X)
	nest(host, "EmberNestBridge", NEST_BRIDGE_X, NEST_BRIDGE_Y)
	nest(host, "EmberNestAltar", NEST_ALTAR_X)
	stele(host, "SteleCompact", STELE_A_POS, "圣殿铭 · 炉约誓",
			"以剑饲炉，以火养城。一百年的灯，是用签过名的剑换的。")
	stele(host, "StelePrice", STELE_B_POS, "炉约 · 代价",
			"灯还亮着。握过剑的手早已锈成灰。名字还刻在石上。")
	plate_door(host, "Choir", PLATE_FEET, DOOR_POS)
	rusty_gate(host, "RustyGate", GATE_POS)
	hook(host, "Hook_Vault", HOOK_POS)
	pickup(host, "EmberCoreVault", PICKUP_POS, &"ember_core")
	stele(host, "SteleVault", STELE_VAULT_POS, "炉约 · 顶",
			"吊灯照不到拱顶。签过名的人把名字留在下面，把剑举到上面。")
	for w in WAYMARKS:
		waymark(host, w[0], String(w[1]))


func _build_enemies(host: Node2D) -> void:
	for e in ENEMIES:
		enemy(host, String(e[0]), String(e[1]), e[2], e[3])


func _build_decor(host: Node2D) -> void:
	for x in TORCHES:
		torch(host, x, FLOOR_Y, TORCH_TINT)
	for p in PROPS:
		prop(host, String(p[0]), p[1])
	for x in VINES:
		hanging(host, "vine", Vector2(x, 0.0), VINE_TINT)
	# 帷幔：同一张贴图染成更暗的紫灰，和藤蔓的落灰感分开。
	for d in DRAPES:
		hanging(host, "vine", d[0], d[1])
