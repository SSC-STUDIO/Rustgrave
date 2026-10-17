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
	"stone_1": Level01Env.DECOR_STONE_1,
	"stone_2": Level01Env.DECOR_STONE_2,
	"stone_3": Level01Env.DECOR_STONE_3,
	"stone_4": Level01Env.DECOR_STONE_4,
	"tree_1": Level01Env.DECOR_TREE_1,
	"tree_2": Level01Env.DECOR_TREE_2,
	"bush_l": Level01Env.DECOR_BUSH_L,
	"bush_s": Level01Env.DECOR_BUSH_S,
}

## Per-theme prop allowlist. Do not cross-plant cathedral wall plates into
## outdoor graveyard/town skies, or moss undercroft pieces into forge slag.
## TorchLight (bg_wall_torch) is indoor-only — see torch().
const THEME_PROPS := {
	"graveyard": [
		"balustrade", "door_arch", "grave_cross", "statue",
		"stone_1", "stone_2", "stone_3", "stone_4",
		"tree_1", "tree_2", "bush_l", "bush_s",
	],
	"undercroft": [
		"vine", "arch", "rubble", "stair", "wall_block", "door", "balustrade",
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
	],
	# 钟楼沿用圣殿的墙板族。
	"belltower": [
		"balustrade", "column", "gargoyle", "altar", "window", "skull_column",
		"vine", "door_arch", "slab", "rubble_dry", "rubble_dry_b", "rubble_dry_c",
	],
	"industrial": [
		"beam", "beam_bolts", "beam_narrow", "metal_panel",
		"plate", "slab", "rubble_dry", "rubble_dry_b", "rubble_dry_c", "vine",
		"rock_pile", "bones", "skull_arch",
	],
	# Level10 forge-core keeps altar / column / skull_column as ending setpieces.
	# Level08 slag uses plate/slab/rubble only — do not reintroduce cathedral columns there.
	"forge": [
		"beam", "beam_bolts", "beam_narrow", "metal_panel",
		"plate", "slab", "rubble_dry", "rubble_dry_b", "rubble_dry_c",
		"column", "altar", "skull_column", "vine", "rock_pile", "bones", "skull_arch",
	],
	"forge_core": [
		"plate", "slab", "rubble_dry", "rubble_dry_b", "rubble_dry_c",
		"column", "altar", "skull_column", "vine", "rock_pile", "bones", "skull_arch",
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
