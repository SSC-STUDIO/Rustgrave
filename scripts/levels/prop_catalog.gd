class_name PropCatalog
extends RefCounted
## Single source of truth for chapter set dressing: what each prop key draws, which
## themes may plant it, and which material family (iron, basalt, ...) recolors it.
## ChapterLayout.prop()/foliage()/hanging() resolve everything through here, so a
## chapter can never plant a lavender church slab on a workshop floor again.
##
## Recolored copies live at res://assets/env/props/<family>/<key>.png and are written
## by tools/gen_theme_tiles.py. They replace the base sprite automatically.

## 可用的装饰贴图（都已导入）。键 → 路径。
const DECOR := {
	"vine": "res://assets/env/moss_vine.png",           # 16×64，从顶板垂下（不接地）
	"arch": "res://assets/env/moss_arch.png",           # 96×48 排水拱，接地
	"rubble": "res://assets/env/moss_rubble.png",       # 32×30 苔石堆，接地
	"stair": "res://assets/env/moss_stair.png",         # 32×41 苔阶（装饰，接地）
	"wall_block": "res://assets/env/moss_wall_block.png", # 160×83 苔墙块，接地
	"door": "res://assets/env/moss_door.png",           # 48×64 木门（装饰用，接地）
	"balustrade": "res://assets/env/balustrade.png",    # 80×52 石栏，接地
	"balustrade_wall": "res://assets/env/balustrade_wall.png", # 冷灰石栏（城墙顶）
	"balustrade_town": "res://assets/env/balustrade_town.png", # 暖石栏（街巷）
	"column": "res://assets/env/column_big_cut.png",        # 114×190 大柱，接地（背景）
	"gargoyle": "res://assets/env/bg_gargoyle_cut.png",     # 石像鬼墙板（背景，接地）
	"altar": "res://assets/env/bg_altar_cut.png",           # 祭坛墙板（背景，接地）
	"window": "res://assets/env/bg_wall_window_cut.png",    # 尖窗墙板（背景，接地）
	"skull_column": "res://assets/env/bg_column_skulls_cut.png", # 骷髅柱（背景，接地）
	# 工业/熔炉：Kenney Request pack + 干石渣（避免苔拱/教堂柱串味）
	"beam": "res://assets/external/kenney/Art (5190 files)/Platformer assets (1330 assets)/Request pack (100 assets)/PNG/beam.png",
	"beam_bolts": "res://assets/external/kenney/Art (5190 files)/Platformer assets (1330 assets)/Request pack (100 assets)/PNG/beamBolts.png",
	"beam_narrow": "res://assets/external/kenney/Art (5190 files)/Platformer assets (1330 assets)/Request pack (100 assets)/PNG/beamNarrow.png",
	"metal_panel": "res://assets/external/kenney/Art (5190 files)/Platformer assets (1330 assets)/Request pack (100 assets)/PNG/metal.png",
	"rubble_dry": "res://assets/env/rubble_a.png",
	"rubble_dry_b": "res://assets/env/rubble_b.png",
	"rubble_dry_c": "res://assets/env/rubble_c.png",
	"slab": "res://assets/env/slab_a.png",
	"plate": "res://assets/env/plate_stone.png",
	"statue": "res://assets/env/statue_keeper.png",     # 守墓者石像，接地
	"grave_cross": "res://assets/env/grave_cross.png",  # 十字墓碑，接地
	"door_arch": "res://assets/env/door_arch.png",      # 32×64 石门洞（装饰），接地
	"door_arch_wall": "res://assets/env/door_arch_wall.png", # 冷灰门洞（城墙塔门）
	"door_arch_town": "res://assets/env/door_arch_town.png", # 暖石门洞（街巷）
	# Gothic Horror 砖城件（tools/gen_theme_tiles.py 切出）
	"brick_house": "res://assets/env/gh_brick_house.png", # 384×176 砖屋立面（背景，接地）
	"ruin_tower": "res://assets/env/gh_ruin_tower.png",   # 254×154 倾倒的塔身（背景，接地）
	"rock_pile": "res://assets/env/gh_rock_pile.png",     # 32×45 碎石堆，接地
	"bones": "res://assets/env/gh_bones.png",             # 32×16 骨渣，接地
	"skull_arch": "res://assets/env/gh_skull_arch.png",   # 32×48 骷髅炉口，接地
	# 世界历史细节（docs/art-spec.md「世界历史细节」）：损坏机械、生活残留、
	# 锈蚀管道、炉火。全部复用仓库里已入库的素材（可溯），不新下载：
	#   pipe_valve — 锈阀管道：Kenney Request pack 的 beamBoltsHoles 裁片
	#     （CC0，assets/external/kenney）。法兰 + 螺栓孔，是「锈蚀管道」的
	#     可读符号。
	"pipe_valve": "res://assets/external/kenney/Art (5190 files)/Platformer assets (1330 assets)/Request pack (100 assets)/PNG/beamBoltsHoles.png",
	#   broken_machine — 损坏机械：Kenney Request pack 的 beamHoles 裁片
	#     （CC0）。断裂的工字梁断面，工坊 / 熔渣的坏机械。
	"broken_machine": "res://assets/external/kenney/Art (5190 files)/Platformer assets (1330 assets)/Request pack (100 assets)/PNG/beamHoles.png",
	#   life_remains — 生活残留：Gothic Horror 的骨渣裁片（gh_bones.png，
	#     tools/gen_theme_tiles.py 的 set_pieces 写入，OGA CC0）。木箱与陶罐
	#     之外，骨渣是「上一班人没回来」的直接证据。
	"life_remains": "res://assets/env/gh_bones.png",
	#   fire_vent — 炉火 / 排渣口：Gothic Horror 的矮烟囱裁片（gh_furnace.png，
	#     tools/gen_theme_tiles.py 的 set_pieces 写入，OGA CC0）。熔炉边
	#     的排气口，和壁炬的炉膛同一族。
	"fire_vent": "res://assets/env/gh_furnace.png",
	#   以下是第二组「世界历史」符号，同样只复用仓库已入库的 Kenney CC0 素材
	#   （assets/external/kenney，许可证见 kenney/LICENSE.md）：
	#   chain — 垂链：Base pack Items/chain.png。钟楼吊钟、工坊吊装、废井的
	#     遗弃设施；用 hanging() 挂、或盘在 prop() 的地面上。
	"chain": "res://assets/external/kenney/Art (5190 files)/Platformer assets (1330 assets)/Base pack (360 assets)/Items/chain.png",
	#   girder_l / girder_r — 断裂的斜撑钢梁：Request pack beamDiagonalLeft/Right。
	#     塌掉一半的厂房 / 矿道支架，比水平 beam 更像「坏在这里」。
	"girder_l": "res://assets/external/kenney/Art (5190 files)/Platformer assets (1330 assets)/Request pack (100 assets)/PNG/beamDiagonalLeft.png",
	"girder_r": "res://assets/external/kenney/Art (5190 files)/Platformer assets (1330 assets)/Request pack (100 assets)/PNG/beamDiagonalRight.png",
	#   warning_plate — 褪色的危险告示板：Request pack metalCenterWarning.png。
	#     遗弃设施上最后一条人写的字，颜色压到锈灰。
	"warning_plate": "res://assets/external/kenney/Art (5190 files)/Platformer assets (1330 assets)/Request pack (100 assets)/PNG/metalCenterWarning.png",
	#   fence — 拆掉一半的铁栏：Request pack metalFence.png。城垛 / 工坊平台
	#     边缘的遗弃护栏。
	"fence": "res://assets/external/kenney/Art (5190 files)/Platformer assets (1330 assets)/Request pack (100 assets)/PNG/metalFence.png",
	"stone_1": Level01Env.DECOR_STONE_1,
	"stone_2": Level01Env.DECOR_STONE_2,
	"stone_3": Level01Env.DECOR_STONE_3,
	"stone_4": Level01Env.DECOR_STONE_4,
	"tree_1": Level01Env.DECOR_TREE_1,
	"tree_2": Level01Env.DECOR_TREE_2,
	"bush_l": Level01Env.DECOR_BUSH_L,
	"bush_s": Level01Env.DECOR_BUSH_S,
	# 1x 像素裁切（tools/normalize_art.py 已入库的派生图）：章节里的树/大灌木要按
	# 整数比例种，不能再拿原图乘 0.5/0.62 的小数缩放（docs/art-spec.md「像素密度与对齐」）。
	# 键名保留 tree_/bush_ 前缀，Level01Env.hardness_of() 才能认出会摆动的植被。
	"tree_1_px": "res://assets/env/normalized/props/tree-1_48.png",   # 38×27（48%）
	"tree_2_px": "res://assets/env/normalized/props/tree-2_46.png",   # 34×25（46%）
	"bush_l_px": "res://assets/env/normalized/props/bush-large_62.png", # 47×40（62%）
}

## Per-theme prop allowlist. Do not cross-plant cathedral wall plates into
## outdoor graveyard/town skies, or moss undercroft pieces into forge slag.
## TorchLight (bg_wall_torch) is indoor-only — see torch().
const THEME_PROPS := {
	"graveyard": [
		"balustrade", "door_arch", "grave_cross", "statue",
		"stone_1", "stone_2", "stone_3", "stone_4",
		"tree_1", "tree_2", "bush_l", "bush_s",
		# 1x 像素裁切的植被（整数缩放；小数缩放会把树冠的像素拉成半格）。
		"tree_1_px", "tree_2_px", "bush_l_px",
		# 锈炉城埋在墓园下：断梁 / 断链 / 骨渣走 ground 族 1x 变体，不是教堂件。
		"rubble_dry", "rubble_dry_b", "rubble_dry_c", "rock_pile", "bones",
		"pipe_valve", "broken_machine", "girder_l", "girder_r", "fence", "chain",
		"fire_vent", "life_remains", "skull_arch",
	],
	# 地窟：青黑苔砖、拱窗壁龛（Level02 同款）。管道与遗弃设施属于「城沉下去之前」
	# 的生活残留。
	"undercroft": [
		"vine", "arch", "rubble", "stair", "wall_block", "door", "balustrade",
		"life_remains", "pipe_valve", "chain", "warning_plate",
	],
	"cathedral": [
		"balustrade", "column", "gargoyle", "altar", "window", "skull_column",
		"vine", "door_arch", "slab", "rubble_dry", "rubble_dry_b", "rubble_dry_c",
	],
	"town": [
		"balustrade_town", "door_arch_town", "balustrade", "door_arch", "rubble_dry", "rubble_dry_b", "rubble_dry_c",
		"bush_s", "vine", "slab", "plate", "brick_house", "ruin_tower", "rock_pile", "bones",
	],
	# 城墙顶：女墙、门洞、碎石、倾塔剪影。没有砖屋——墙上不住人。
	"ramparts": [
		"balustrade_wall", "door_arch_wall", "balustrade", "door_arch", "rubble_dry", "rubble_dry_b", "rubble_dry_c",
		"bush_s", "slab", "plate", "ruin_tower", "rock_pile",
		# 城墙脚下的遗弃设施与生活残留（砖石城垛族同源重着色）。
		"life_remains", "broken_machine", "fence", "warning_plate", "chain",
	],
	# 钟楼沿用圣殿的墙板族；吊钟链是它唯一「还在用的机械」。
	"belltower": [
		"balustrade", "column", "gargoyle", "altar", "window", "skull_column",
		"vine", "door_arch", "slab", "rubble_dry", "rubble_dry_b", "rubble_dry_c",
		"chain",
	],
	"industrial": [
		"beam", "beam_bolts", "beam_narrow", "metal_panel",
		"plate", "slab", "rubble_dry", "rubble_dry_b", "rubble_dry_c", "vine",
		"rock_pile", "bones", "skull_arch",
		# 工坊：锈蚀管道、损坏机械、生活残留、炉火排气口——造锈核的车间要有
		# 「上一班没干完的活」的痕迹。斜梁 / 铁栏 / 告示牌是停工那天的现场。
		"pipe_valve", "broken_machine", "life_remains", "fire_vent",
		"girder_l", "girder_r", "warning_plate", "fence", "chain",
	],
	# Level10 forge-core keeps altar / column / skull_column as ending setpieces.
	# Level08 slag uses plate/slab/rubble only — do not reintroduce cathedral columns there.
	"forge": [
		"beam", "beam_bolts", "beam_narrow", "metal_panel",
		"plate", "slab", "rubble_dry", "rubble_dry_b", "rubble_dry_c",
		"column", "altar", "skull_column", "vine", "rock_pile", "bones", "skull_arch",
		# 熔渣深渊：坏在炉边的机械与排渣口，比工坊更焦。
		"pipe_valve", "broken_machine", "fire_vent",
		"girder_l", "girder_r", "warning_plate", "chain",
	],
	"forge_core": [
		"plate", "slab", "rubble_dry", "rubble_dry_c",
		"column", "altar", "skull_column", "vine", "rock_pile", "bones", "skull_arch",
		"chain", "warning_plate",
		# 炉心入口回廊的送渣机械（Kenney 派生的 1x 玄武岩族副本）。
		"pipe_valve", "broken_machine", "girder_l", "girder_r", "fence",
	],
}

## Theme -> material family: the SolidPlatform skin family and the folder of recolored props.
const FAMILY := {
	"graveyard": "ground",
	"undercroft": "moss",
	"cathedral": "stone",
	"belltower": "castle",
	"town": "brick",
	"industrial": "iron",
	"forge": "basalt",
	"forge_core": "basalt",
	"ramparts": "rampart",
}
## 「世界历史细节」的显式分类（docs/art-spec.md）。不是新贴图，而是把已有
## 装饰键按叙事功能分组，关卡作者和测试都从这里取。
const HISTORY_KEYS := {
	"graves": ["grave_cross", "statue", "stone_1", "stone_2", "stone_3", "stone_4", "bones"],
	"machines": ["beam", "beam_bolts", "beam_narrow", "metal_panel",
			"broken_machine", "girder_l", "girder_r"],
	"pipes": ["pipe_valve", "vine"],
	"fire": ["fire_vent", "skull_arch"],
	"ruins": ["door_arch", "door_arch_wall", "door_arch_town", "balustrade",
			"balustrade_wall", "balustrade_town", "window", "fence", "warning_plate"],
	"debris": ["rubble", "rubble_dry", "rubble_dry_b", "rubble_dry_c", "rock_pile",
			"plate", "slab", "stair", "life_remains", "chain"],
}
## 必须用 hanging() 挂起来、不能 prop() 接地的键（测试会检查它们没有 feet 元数据）。
const HANGING_KEYS := ["vine", "chain"]

const PROPS_DIR := "res://assets/env/props/"


static func family_for(theme: String) -> String:
	return String(FAMILY.get(theme, ""))


## True when `key` may be planted in `theme` (unknown themes and raw paths: allowed).
static func allowed(theme: String, key: String) -> bool:
	if not DECOR.has(key) or not THEME_PROPS.has(theme):
		return true
	return key in THEME_PROPS[theme]


## Sprite path for `key_or_path` in `theme`: the family recolor when one exists,
## else the base sprite; raw paths pass through.
static func path_for(key_or_path: String, theme: String) -> String:
	if not DECOR.has(key_or_path):
		return key_or_path
	var family := family_for(theme)
	if family != "":
		var variant := "%s%s/%s.png" % [PROPS_DIR, family, key_or_path]
		if ResourceLoader.exists(variant):
			return variant
	return String(DECOR[key_or_path])
