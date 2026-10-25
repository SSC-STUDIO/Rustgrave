extends ChapterLayout
## 锈墓・陆 — 圣殿地窖：中庭的账本末页被人撕走，暗门通到地窖。地窖里有人在唱，没有声音。
##
## v3 重做结构（暗室串联 + 烛光桥 CandleBridge；打破 y=320 单线，下沉墓坑 y=352 + 多层走廊 y=288/256/224/136）：
##   ① 前厅与初火教学 0–880      暗门入口、前厅余烬巢（176）、路牌「地窖」；
##                               第一座烛光桥（512,288）跨越下沉骨槽（y=352，安全石底，两头均可单跳回 320）；
##                               遭遇 1：下沉骨槽起身骸骨 + 爆裂骸骨守窄道，上层画廊散射喷吐者压制。
##   ② 沉棺骨室与唱诗台 880–1760 碑文「唱诗」（960）、骨室余烬巢（1160）；
##                               双路登台：点燃骨室烛台走烛光桥（256）直上唱诗台（224），或下到骨室底（352）乘链吊台升上；
##                               唱诗台压板（1640,224）开启圣物闸门；西侧高台（1184,224）提供单向落回骨室巢的捷径；
##                               遭遇 2：骨室底骸骨 + 爆裂骸骨 + 空中幽魂立体夹击。
##   ③ 圣物暗廊与末页秘龛 1760–2600 圣物闸门（1880）、暗廊余烬巢（2000）；
##                               遭遇 3：烛光桥串联高台（288→256），爆裂骸骨 + 幽魂 + 重盾卫立体驻守；
##                               可选挑战与钩锁支路：登顶唱诗楼座（136）读「地窖纪事 · 末页」并拾取武器奖励「铁斩刃」。
##   ④ 唱诗堂 Boss 场 2600–3680  碑文「伊尔」（2700）、Boss 前余烬巢（2860，距场门 40px）；
##                               无声唱诗班竞技场（2900–3500）：连续主地面 + 两侧阶台/侧龛（288/256）+ 中央高空烛光桥（224）+ 可破坏骨瓮掩体；
##                               出口「工坊暗门」（3592）→ level05。

const EAST_LIMIT := 3680
const CAMERA_TOP := -176
const CEILING_Y := -112.0
const ENTRY_SPAWN := Vector2(96, 300)
const SUNKEN_Y := 352.0

## 圣殿石板压成冷紫（同 level04）；浮台略亮，和地面拉开。
const STONE_TONE := Color(0.9, 0.88, 1.0)
const FLOAT_TONE := Color(0.94, 0.92, 1.0)
## 壁炬墙板压冷一点融进地窖石墙；藤条压成烛泪的黄白（地窖顶上的蜡烛烧了两百年）。
const TORCH_TINT := Color(0.82, 0.84, 1.0)
const WAX_TINT := Color(0.95, 0.87, 0.66, 0.9)

## 地面段 [name, x0, x1, cap_left, cap_right, top_y]：高低错落的暗室地面，352 下沉段皆可单跳回 320。
const FLOORS: Array = [
	["FloorAnte", 0.0, 464.0, false, true, FLOOR_Y],
	["FloorSunkenA", 464.0, 880.0, false, false, SUNKEN_Y],
	["FloorBoneWest", 880.0, 1280.0, true, true, FLOOR_Y],
	["FloorBoneLower", 1280.0, 1760.0, false, false, SUNKEN_Y],
	["FloorCatacomb", 1760.0, 2600.0, true, true, FLOOR_Y],
	["FloorChoir", 2600.0, 3680.0, true, false, FLOOR_Y],
]

## 悬空踏台 [name, pos(左上), width]（16px 厚，nave_float；皆在 Boss 竞技场外）
const STEPS: Array = [
	["StepGalleryA", Vector2(672, 288), 144.0],
	["ShortcutBalcony", Vector2(1184, 224), 80.0],
	["StepBoneEntry", Vector2(1296, 288), 64.0],
	["StepBoneLift", Vector2(1424, 320), 64.0],
	["ChoirLoft", Vector2(1568, 224), 160.0],
	["StepLoftEast", Vector2(1776, 224), 88.0],
	["StepCatacombA", Vector2(2112, 288), 80.0],
	["CatacombUpper", Vector2(2384, 256), 128.0],
	["LedgerGallery", Vector2(2224, 136), 160.0],
]

## 唱诗班 Boss 竞技场内的立体地形（两侧抬高阶台 + 侧龛，不阻碍浮空指挥官 y=254..320 的中场巡弋）
const ARENA_PLATFORMS: Array = [
	["ArenaStepWest", Vector2(2912, 288), 64.0],
	["ArenaAlcoveWest", Vector2(2992, 256), 80.0],
	["ArenaAlcoveEast", Vector2(3328, 256), 80.0],
	["ArenaStepEast", Vector2(3424, 288), 64.0],
]

## 烛光桥 [name, pos(左上), width, candle_pos(脚点), props]
const CANDLE_BRIDGES: Array = [
	["CandleBridgeAnte", Vector2(512, 288), 112.0, Vector2(416, 320),
			{"lit_time": 6.5, "hint_id": &"candle"}],
	["CandleBridgeBone", Vector2(1392, 256), 112.0, Vector2(1240, 320),
			{"lit_time": 6.5, "hint_id": &""}],
	["CandleBridgeShortcut", Vector2(1328, 224), 112.0, Vector2(1584, 224),
			{"lit_time": 7.0, "hint_id": &""}],
	["CandleBridgeCatacomb", Vector2(2232, 256), 112.0, Vector2(2144, 288),
			{"lit_time": 6.5, "hint_id": &""}],
	["CandleBridgeArena", Vector2(3136, 224), 128.0, Vector2(3032, 256),
			{"lit_time": 7.0, "hint_id": &""}],
]

## 唱诗台吊台：从骨室过渡阶（296）把骑士送到唱诗台（224）。
const LIFTS: Array = [
	["ChoirLift", Vector2(1504, 296), Vector2(0.0, -72.0), 6.0, 48.0, 0.0],
]

## 唱诗壳机关：压板装在唱诗台面上（脚点 y=224），闸门立在圣物暗廊入口（门 16×64，底在 320）。
const PLATE_FEET := Vector2(1640, 224)
const GATE_DOOR_POS := Vector2(1880, 256)

## 四个余烬巢：前厅(176) / 骨室西(1160) / 圣物暗廊(2000) / Boss 门前(2860)，间距全部 <1000px。
const NEST_ANTE_X := 176.0
const NEST_BONE_X := 1160.0
const NEST_VAULT_X := 2000.0
const NEST_CHOIR_X := 2860.0

## 碑文：主线「唱诗」与「伊尔」在必经路上；支路「末页」在钩锁秘龛（LedgerGallery）。
const STELE_CHOIR_POS := Vector2(960, 320)
const STELE_YIR_POS := Vector2(2700, 320)
const STELE_LEDGER_POS := Vector2(2264, 136)

## 钩锁支路与可选挑战奖励：锚点悬在圣物暗廊上方，落台在锚点下方 88px。
const HOOK_POS := Vector2(2304, 48)
const REWARD_SCENE := "res://scenes/interactables/EquipmentPickup.tscn"
const REWARD_POS := Vector2(2336, 129)
const REWARD_KIND := "equipment"
const REWARD_REF := "iron_blade"

## 可破坏骨瓮（支路与 Boss 场两侧掩体，打碎掉小回血）
const DESTRUCTIBLES: Array = [
	["LedgerUrn", &"rust_urn", Vector2(2368, 136)],
	["ChoirUrnWest", &"rust_urn", Vector2(3088, 320)],
	["ChoirUrnEast", &"rust_urn", Vector2(3312, 320)],
]

## Boss：无声唱诗班。竞技场 2900–3500，门前巢在 2860（距场门 40px ≤ 80px）。
const ARENA_LEFT := 2900.0
const ARENA_RIGHT := 3500.0
const BOSS_POS := Vector2(3200, 320)
const EXIT_X := 3592.0

const WAYMARKS: Array = [
	[Vector2(280, 320), "地窖"],
	[Vector2(1216, 224), "捷径"],
	[Vector2(2760, 320), "唱诗"],
]

## 三处场景化遭遇（包含 exploder_skeleton、scatter_spitter、heavy_guard 变体），
## 所有余烬巢均在附近敌人 aggro/wake 圈外。
const ENEMIES: Array = [
	# 遭遇 1：前厅下沉骨槽与上层画廊（爆裂骸骨守窄道，西侧留足退路）
	["Skeleton1", "skeleton", Vector2(584, 352), {}],
	["SkeletonExploder1", "skeleton", Vector2(728, 352), {"variant": &"exploder_skeleton"}],
	["Spitter1", "spitter", Vector2(768, 288), {"variant": &"scatter_spitter"}],
	# 遭遇 2：沉棺骨室双层夹击（下层骸骨 + 爆裂骸骨，上层幽魂护唱诗台）
	["Skeleton2", "skeleton", Vector2(1380, 352), {}],
	["Ghost1", "ghost", Vector2(1520, 196), {}],
	["SkeletonExploder2", "skeleton", Vector2(1640, 352), {"variant": &"exploder_skeleton"}],
	# 遭遇 3：圣物暗廊立体猎场（中路爆裂骸骨 + 烛光桥上方幽魂 + 重盾卫守东口）
	["Skeleton3", "skeleton", Vector2(2260, 320), {"variant": &"exploder_skeleton"}],
	["Ghost2", "ghost", Vector2(2360, 212), {}],
	["GearShield1", "gear_shield", Vector2(2480, 320), {"variant": &"heavy_guard", "patrol_range": 16.0}],
]

## 壁炬 [x, feet_y]：按所在暗室地面高度贴齐。
const TORCHES: Array = [
	[352.0, 320.0], [640.0, 352.0], [1060.0, 320.0],
	[1460.0, 352.0], [1680.0, 352.0], [2180.0, 320.0],
	[2680.0, 320.0], [3200.0, 320.0], [3480.0, 320.0],
]

const WARM_COLOR := Color(1.0, 0.72, 0.42)
const WARM_FILLS: Array = [
	["WarmWashAnte", 400.0, 180.0, 520.0, 1.3],
	["WarmWashBone", 1100.0, 180.0, 500.0, 1.0],
	["WarmWashWest", 1900.0, 180.0, 540.0, 1.2],
	["WarmWashGate", 2700.0, 180.0, 500.0, 1.1],
	["WarmWashChoir", 3300.0, 180.0, 440.0, 1.1],
	["WarmAnte", 600.0, 250.0, 180.0, 1.05],
	["WarmBoneRoom", 1450.0, 240.0, 190.0, 1.15],
	["WarmGate", 2050.0, 250.0, 160.0, 1.1],
	["WarmSkull", 2320.0, 220.0, 170.0, 1.05],
	["WarmChoirHall", 3060.0, 230.0, 180.0, 1.15],
	["WarmBossColumn", 3200.0, 185.0, 160.0, 1.25],
	["WarmChoirAltar", 3400.0, 240.0, 160.0, 1.05],
]

## 接地装饰 [key, feet]：全部踩在对应高度层的实心台面上。
const PROPS: Array = [
	["door_arch", Vector2(56, 320)],
	["balustrade", Vector2(368, 320)],
	["rubble_dry", Vector2(520, 352)],
	["window", Vector2(660, 352)],
	["gargoyle", Vector2(820, 352)],
	["skull_column", Vector2(1020, 320)],
	["rubble_dry_b", Vector2(1320, 352)],
	["altar", Vector2(1580, 352)],
	["slab", Vector2(1580, 352)],
	["column", Vector2(1820, 320)],
	["rubble_dry_c", Vector2(1930, 320)],
	["skull_column", Vector2(2320, 320)],
	["rubble_dry", Vector2(2560, 320)],
	# 唱诗堂（Boss 房）地标
	["column", Vector2(2950, 320)],
	["balustrade", Vector2(2944, 288)],
	["slab", Vector2(3050, 320)],
	["window", Vector2(3140, 320)],
	["altar", Vector2(3380, 320)],
	["slab", Vector2(3380, 320)],
	["balustrade", Vector2(3456, 288)],
]

const VINES: Array = [500.0, 1200.0, 1700.0, 2100.0, 2500.0, 2900.0, 3300.0]


func level_id() -> String:
	return "level04b"


func title() -> String:
	return ChapterText.title_of(level_id())


func wake_line() -> String:
	return ChapterText.wake_of(level_id())


func _stele(host: Node2D, node_name: String, pos: Vector2) -> void:
	var entry := ChapterText.stele_of(level_id(), node_name)
	stele(host, node_name, pos, String(entry.get("title", "")), String(entry.get("text", "")))


## 支路奖励位：同时用 ChapterLayout.reward() 并在 Pickups 下保留原引用名或直接挂在 Pickups。
func _reward(host: Node2D) -> EquipmentPickup:
	var item := EquipmentCatalog.for_id(StringName(REWARD_REF))
	var display := item.display_name if item != null else ""
	var pick := reward(host, "RewardLedger", REWARD_POS, REWARD_KIND, REWARD_REF, display)
	if pick != null and pick.get_parent() != group(host, "Pickups"):
		pick.get_parent().remove_child(pick)
		group(host, "Pickups").add_child(pick)
	return pick


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


func weather_recipe() -> Dictionary:
	return {
		"allowed": [WorldClock.Weather.HAZE, WorldClock.Weather.CLEAR],
		"hold": Vector2(320.0, 520.0),
		"intensity": Vector2(0.4, 0.8),
	}


func build(host: Node2D) -> void:
	_build_terrain(host)
	_build_props(host)
	_build_branch(host)
	_build_enemies(host)
	_build_boss(host)
	_build_decor(host)
	var exit := exit_door(host, EXIT_X, ChapterText.exit_label_of(level_id()),
			ChapterText.exit_captions_of(level_id()), "level04b_done",
			GameContext.next_level_id(level_id()))
	if ResourceLoader.exists("res://scenes/enemies/SilentChoir.tscn"):
		exit.requires_flag = "choir_dead"
		exit.locked_prompt = "唱诗班的合声还没停。"
	finish(host)


func _build_terrain(host: Node2D) -> void:
	for f in FLOORS:
		var top_y: float = float(f[5]) if f.size() > 5 else FLOOR_Y
		floor_strip(host, String(f[0]), float(f[1]), float(f[2]), "nave",
				bool(f[3]), bool(f[4]), top_y, STONE_TONE)
	for s in STEPS:
		step(host, String(s[0]), s[1], float(s[2]), "nave_float", FLOAT_TONE)
	for ap in ARENA_PLATFORMS:
		step(host, String(ap[0]), ap[1], float(ap[2]), "nave_float", FLOAT_TONE)
	for cb in CANDLE_BRIDGES:
		candle_bridge(host, String(cb[0]), cb[1], float(cb[2]), cb[3], cb[4],
				"nave_float", FLOAT_TONE)
	for l in LIFTS:
		lift(host, String(l[0]), l[1], l[2], float(l[3]), float(l[4]), float(l[5]))
	enclose(host, "nave", CEILING_Y, -1.0, 0.0, STONE_TONE)


func _build_props(host: Node2D) -> void:
	nest(host, "EmberNestAnte", NEST_ANTE_X)
	nest(host, "EmberNestBone", NEST_BONE_X)
	nest(host, "EmberNestVault", NEST_VAULT_X)
	nest(host, "EmberNestChoir", NEST_CHOIR_X)
	plate_door(host, "ReliquaryGate", PLATE_FEET, GATE_DOOR_POS)
	_stele(host, "SteleChoir", STELE_CHOIR_POS)
	_stele(host, "SteleYir", STELE_YIR_POS)
	for d in DESTRUCTIBLES:
		destructible(host, String(d[0]), d[1], d[2])
	for w in WAYMARKS:
		waymark(host, w[0], String(w[1]))


func _build_branch(host: Node2D) -> void:
	hook(host, "HookLedger", HOOK_POS)
	_stele(host, "SteleLedger", STELE_LEDGER_POS)
	_reward(host)


func _build_enemies(host: Node2D) -> void:
	for e in ENEMIES:
		enemy(host, String(e[0]), String(e[1]), e[2], e[3])


func _build_boss(host: Node2D) -> void:
	boss(host, "SilentChoir", "silent_choir", BOSS_POS, ARENA_LEFT, ARENA_RIGHT)


func _build_decor(host: Node2D) -> void:
	_build_warm_veil(host)
	for t in TORCHES:
		torch(host, float(t[0]), float(t[1]), TORCH_TINT)
	for spec in WARM_FILLS:
		_warm_fill(host, String(spec[0]), Vector2(float(spec[1]), float(spec[2])),
				float(spec[3]), float(spec[4]))
	for item in PROPS:
		prop(host, String(item[0]), item[1])
	var ceiling_bottom := CEILING_Y + 32.0
	for x in VINES:
		hanging(host, "vine", Vector2(x, ceiling_bottom), WAX_TINT)


func _build_warm_veil(host: Node2D) -> void:
	var veil := ColorRect.new()
	veil.name = "WarmVeil"
	veil.color = Color(0.52, 0.33, 0.20, 0.16)
	veil.position = Vector2(-64, CEILING_Y - 96.0)
	veil.size = Vector2(float(east_limit()) + 128.0, 464.0 - CEILING_Y + 96.0)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.z_index = -8
	group(host, "Props").add_child(veil)


func _warm_fill(host: Node2D, light_name: String, pos: Vector2, radius: float,
		energy: float) -> WorldLight:
	var light := WorldLight.new()
	light.name = light_name
	light.position = pos
	light.color = WARM_COLOR
	light.follow = &"authored"
	light.authored_radius = radius
	light.flicker = false
	light.lit = true
	light.set_base_energy(energy)
	decor_layer(host).add_child(light)
	light.shadow_enabled = false
	return light
