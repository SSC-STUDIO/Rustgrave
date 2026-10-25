class_name TitleWorld
extends Node2D
## The title screen's live, lit pixel scene (640x360, rendered in a SubViewport by
## TitleScreen and shown through the `Keyart` TextureRect).
##
## The Ember Knight (current skin) stands on a long iron bridge in a vast forge hall:
## a light shaft from the torn roof, huge slow gears on pre-rendered rotation frames,
## fourteen swaying lanterns (five pooled point lights), a glowing furnace pit/door
## below and beside him, embers / ash / steam. The camera breathes and follows the
## pointer by WHOLE pixels, layer by layer (orbit parallax around the knight plane).
##
## The scene also tells the player's story at a glance (configure / state_from_save):
##
##   cold     no save: a cold forge, rusty and unlit, the ember almost out
##   journey  in progress: colour grade by act, lit lanterns = cleared chapters / 14
##   give     the knight is gone, only the planted greatsword; warm and steady
##   keep     the knight sits at the forge end looking into the fire; nest lit
##   snuff    lanterns dark, one dying red glow where he stood
##
## Living details (docs/title-live-scene.md §4–§6; each is 1-3 nodes, whole-pixel, additive
## light only — the light budget is full, so none of them adds a PointLight2D):
##
##   crucible     a ladle on an overhead rail walks over the pit, tips and pours molten iron
##   hammer       a far trip-hammer strikes a white-hot billet, sparks
##   sword chain  named greatswords ride a chain into the furnace housing (the oath, drawn);
##                the 'give' ending leaves the chain empty and lets the souls rise instead
##   souls        pale-blue lights rising off the molten river
##   banners      two torn banners swaying in the pit's updraft
##   braziers     two fires at the bridge head, lit by progress
##   cloud shade  the light shaft breathes (cloud shadows drifting over the roof gap)
##   ghosts       far lantern-bearing silhouettes walking toward the furnace
##   knight       now and then turns to look at the furnace
##
## `react_to(menu_id)` gives every title menu row its own reaction (see REACTIONS), and
## `prop_plan(state)` is the pure, testable half of "which of these show up in which variant".
##
## Budgets (tests/title_world_test.gd, tests/title_elements_test.gd): <= 8 lights, <= 250
## nodes, no per-frame allocation in the hot paths. Everything is NEAREST and whole-pixel placed.

const CrucibleScript := preload("res://scripts/ui/title_crucible.gd")
const HammerScript := preload("res://scripts/ui/title_hammer.gd")
const SwordChainScript := preload("res://scripts/ui/title_sword_chain.gd")
const BannerScript := preload("res://scripts/ui/title_banner.gd")
const BrazierScript := preload("res://scripts/ui/title_braziers.gd")
const FlameScript := preload("res://scripts/ui/title_flame.gd")
const GhostScript := preload("res://scripts/ui/title_ghosts.gd")
const SoulScript := preload("res://scripts/ui/title_souls.gd")

const WORLD := Vector2(640.0, 360.0)
const CENTER := Vector2(320.0, 180.0)
const DIR := "res://assets/title/"
const MAX_LIGHTS := 8
const LANTERN_COUNT := 14
const CHAPTERS := 14
const LIGHT_POOL_FIXTURES := [1, 4, 7, 10, 13]

const DECK_Y := 266.0
const KNIGHT_X := 326.0
## 'keep': a seated knight beside the furnace, clear of the foreground housing.
const KEEP_X := 420.0
const FEET := Vector2(KNIGHT_X, DECK_Y)
const BRIDGE_POS := Vector2(150.0, DECK_Y - 26.0)
const MASS_LEFT_POS := Vector2(-16.0, -8.0)
const MASS_RIGHT_POS := Vector2(400.0, -8.0)
const MOUTH_IN_MASS := Vector2(50.0, 210.0)
const BEAM_POS := Vector2(146.0, 16.0)

const VARIANT_COLD := &"cold"
const VARIANT_JOURNEY := &"journey"
const VARIANT_GIVE := &"give"
const VARIANT_KEEP := &"keep"
const VARIANT_SNUFF := &"snuff"
const VARIANTS: Array[StringName] = [VARIANT_COLD, VARIANT_JOURNEY, VARIANT_GIVE, VARIANT_KEEP, VARIANT_SNUFF]

## --- living details (see the header) ---
## 对岸细栈桥的桥面高度。比近桥栏杆顶（y≈249）高出一截，才不会被近景的桥面、栏杆和火盆挡住。
## 锻锤的垫墩和亡魂的脚线都站在这一高度上（亡魂见 title_ghosts.gd 的 FLOOR_Y，需同步）。
const FAR_DECK_Y := 215.0
## Where the far trip-hammer stands (its anvil sits on the far catwalk).
const HAMMER_POS := Vector2(392.0, FAR_DECK_Y)
const BANNER_XS: Array[float] = [148.0, 508.0]
const BANNER_TOP := 52.0
## The light shaft is shaded by up to this much while a "cloud" passes (0..1) ...
const CLOUD_DEPTH := 0.30
## ... one slow breath every this many seconds; the 'settings' row slows it to CLOUD_SLOW.
const CLOUD_PERIOD := 11.0
const CLOUD_SLOW := 0.3
## The knight rests facing away from the furnace and turns to look at it now and then
## (the first time after GAZE_FIRST seconds, then every GAZE_PERIOD, for GAZE_HOLD).
const GAZE_FIRST := 7.0
const GAZE_PERIOD := 19.0
const GAZE_HOLD := 4.6
## Chapters cleared before the first / the second bridge-head brazier is lit.
const BRAZIER_FIRST_AT := 1
const BRAZIER_SECOND_AT := 7
## The menu rows that react when focused (ids are TitleScreen.ID_*).
const REACTIONS: Array[StringName] = [&"new", &"continue", &"trial", &"arena", &"settings",
		&"controls", &"quit"]

## Orbit parallax: pointer shift in px at depth 1.0 (masses), half as much vertically.
const PARALLAX := Vector2(9.0, 4.5)
const BREATH_PERIOD := 7.0
const POINTER_EASE := 3.2

## Look per variant / act. ambient multiplies the whole lit canvas; the rest tune the
## furnace, the shaft, the particles and the machines.
const GRADES := {
	&"cold": {
		"ambient": Color(0.50, 0.46, 0.54), "furnace": 0.16, "furnace_color": Color(1.0, 0.30, 0.12),
		"forge": 0.16, "shaft": 0.55, "shaft_color": Color(0.40, 0.56, 0.66), "embers": 0.18, "ash": 0.45,
		"steam": 0.0, "gears": 0.12, "lantern": Color(1.0, 0.62, 0.30), "flicker": 1.0,
	},
	&"act1": {
		"ambient": Color(0.54, 0.50, 0.58), "furnace": 0.40, "furnace_color": Color(1.0, 0.36, 0.14),
		"forge": 0.50, "shaft": 0.95, "shaft_color": Color(0.42, 0.60, 0.70), "embers": 0.45, "ash": 0.5,
		"steam": 0.3, "gears": 0.45, "lantern": Color(1.0, 0.66, 0.34), "flicker": 1.0,
	},
	&"act2": {
		"ambient": Color(0.58, 0.50, 0.50), "furnace": 0.62, "furnace_color": Color(1.0, 0.40, 0.14),
		"forge": 0.75, "shaft": 0.85, "shaft_color": Color(0.50, 0.60, 0.66), "embers": 0.7, "ash": 0.5,
		"steam": 0.55, "gears": 0.75, "lantern": Color(1.0, 0.64, 0.30), "flicker": 1.0,
	},
	&"act3": {
		"ambient": Color(0.60, 0.48, 0.42), "furnace": 0.86, "furnace_color": Color(1.0, 0.44, 0.14),
		"forge": 1.0, "shaft": 0.7, "shaft_color": Color(0.64, 0.60, 0.56), "embers": 1.0, "ash": 0.4,
		"steam": 0.8, "gears": 1.0, "lantern": Color(1.0, 0.60, 0.26), "flicker": 1.0,
	},
	&"act4": {
		"ambient": Color(0.62, 0.42, 0.38), "furnace": 1.1, "furnace_color": Color(1.0, 0.34, 0.12),
		"forge": 1.25, "shaft": 0.5, "shaft_color": Color(0.74, 0.50, 0.44), "embers": 1.35, "ash": 0.3,
		"steam": 1.0, "gears": 1.3, "lantern": Color(1.0, 0.52, 0.22), "flicker": 1.2,
	},
	&"give": {
		"ambient": Color(0.64, 0.52, 0.44), "furnace": 0.95, "furnace_color": Color(1.0, 0.48, 0.18),
		"forge": 1.0, "shaft": 0.8, "shaft_color": Color(0.74, 0.68, 0.58), "embers": 0.55, "ash": 0.25,
		"steam": 0.5, "gears": 0.8, "lantern": Color(1.0, 0.70, 0.38), "flicker": 0.15,
	},
	&"keep": {
		"ambient": Color(0.64, 0.46, 0.38), "furnace": 1.2, "furnace_color": Color(1.0, 0.40, 0.14),
		"forge": 1.3, "shaft": 0.45, "shaft_color": Color(0.72, 0.52, 0.42), "embers": 1.1, "ash": 0.3,
		"steam": 0.7, "gears": 1.0, "lantern": Color(1.0, 0.58, 0.26), "flicker": 1.0,
	},
	&"snuff": {
		"ambient": Color(0.36, 0.32, 0.40), "furnace": 0.05, "furnace_color": Color(0.9, 0.2, 0.1),
		"forge": 0.0, "shaft": 0.28, "shaft_color": Color(0.36, 0.46, 0.54), "embers": 0.0, "ash": 0.6,
		"steam": 0.0, "gears": 0.0, "lantern": Color(1.0, 0.5, 0.25), "flicker": 1.0,
	},
}

## Forced state for capture tools / tests (set before the title is created).
static var forced_state: Dictionary = {}

## The current look (see state_from_save). Set before add_child, or call configure().
var state: Dictionary = {}

var _built := false
var _t := 0.0
var _camera: Camera2D
var _ambient: CanvasModulate
var _glow_layer: CanvasLayer
var _sparks: TitleSparks
var _motes: TitleSparks
var _vignette: Sprite2D
var _flash: Polygon2D
var _beam: Sprite2D
var _river: Sprite2D
var _current: Sprite2D
var _current_mat: ShaderMaterial
## 熔河流动层的累计位移（世界像素，喂给 shader 时取整）。
var _river_scroll := 0.0
## 当前流速（px/s，炉温驱动；0 = 冷死不动）。
var _river_flow := 0.0
var _pit_glow: Sprite2D
var _mouth: Sprite2D
var _stage: Node2D
var _knight: Node2D
var _planted: Sprite2D
var _nest: Node2D
## 巢火（title_flame.gd，粒子火焰道具；无 class_name，按鸭子类型用）。
var _nest_flame
var _quit_sword: Sprite2D
var _gears: Array[TitleGear] = []
var _lanterns: Array[TitleLantern] = []
var _chains: Array[TitleChain] = []
var _pit_light: PointLight2D
var _shaft_light: PointLight2D
var _forge_light: PointLight2D
## Additive spill onto the bridge deck and the knight. Not lights — the budget is full.
var _wash: Sprite2D
var _rim: Sprite2D
var _grade: Dictionary = {}

# parallel arrays for the parallax registry (no per-frame allocation)
var _px_nodes: Array[Node2D] = []
var _px_base := PackedVector2Array()
var _px_depth := PackedFloat32Array()
var _px_dir := PackedVector2Array()

var _pointer := Vector2.ZERO          # target, -1..1
var _shift := Vector2.ZERO            # eased pointer shift in px at depth 1
var _push := 0.0                      # px, outward from the knight (zoom-like)
var _push_kick := 0.0
var _intro_level := 1.0
var _quit_level := 1.0
var _flare := 0.0
var _flash_amount := 0.0
var _breath := 0.0
var _intro_tween: Tween
var _quit_tween: Tween
var _push_tween: Tween
var _frozen_breath := false

# living details (none of these scripts has a class_name: untyped on purpose)
var _far: Node2D
var _crucible
var _hammer
var _ghosts
var _sword_chain
var _banner_host: Node2D
var _banners: Array = []
var _braziers
var _souls
## Everything that wants the furnace heat + the ambient lift pushed in every frame.
var _heat_props: Array = []
var _plan: Dictionary = {}
var _beam_alpha := 0.0
var _cloud := 1.0
var _cloud_phase := 0.0
var _cloud_speed := 1.0
var _cloud_target := 1.0
# menu reactions (react_to) — each decays on its own
var _surge := 0.0
var _brazier_boost := 0.0
var _gust := 0.0
var _soul_boost := 0.0
var _wave := -1.0
var _wave_next := 0
var _last_reaction: StringName = &""
var _reaction_count := 0
# the knight's occasional look at the furnace
var _gaze_wait := GAZE_FIRST
var _gaze_hold := 0.0
var _gaze_enabled := false


func _ready() -> void:
	if state.is_empty():
		state = state_from_save()
	_build()
	_built = true
	_apply_state()
	_apply_parallax(true)
	set_process(true)


# ---------------------------------------------------------------- state -------

## The pure, unit-testable half of the mapping: everything the scene needs, from a
## plain `peek` dictionary {has_save, scene, ending, flags, skin, origin, rank}.
static func build_state(peek: Dictionary) -> Dictionary:
	var order := GameContext.LEVEL_ORDER
	var scene := String(peek.get("scene", ""))
	var chapter_id := ""
	for id in GameContext.LEVELS:
		if String(GameContext.LEVELS[id]) == scene:
			chapter_id = String(id)
			break
	var chapter_index := order.find(chapter_id)
	var flags: PackedStringArray = peek.get("flags", PackedStringArray())
	var ending := String(peek.get("ending", ""))
	var has_save := bool(peek.get("has_save", false))
	var variant := VARIANT_COLD
	if ending != "":
		variant = StringName(ending) if (ending == "give" or ending == "keep" or ending == "snuff") \
				else VARIANT_GIVE
	elif has_save:
		variant = VARIANT_JOURNEY
	var done: Array[bool] = []
	var cleared := 0
	for i in order.size():
		var id := String(order[i])
		var flag := String(StoryFlow.DONE_FLAGS.get(id, id + "_done"))
		var is_done := false
		if variant == VARIANT_JOURNEY:
			is_done = flags.has(flag) or i < chapter_index
		elif variant != VARIANT_COLD:
			is_done = true           # any ending: the whole road is behind him
		done.append(is_done)
		if is_done:
			cleared += 1
	var act_index := chapter_index
	if act_index < 0:
		act_index = mini(cleared, order.size() - 1)
	if ending != "":
		act_index = order.size() - 1
	var act := act_of_index(act_index) if variant != VARIANT_COLD else 0
	var skin := StringName(String(peek.get("skin", "")))
	if not SkinCatalog.has(skin):
		skin = SkinCatalog.default_for_origin(StringName(String(peek.get("origin", ""))))
	var lit := 0
	match variant:
		VARIANT_JOURNEY:
			lit = lit_lantern_count(cleared)
		VARIANT_GIVE, VARIANT_KEEP:
			lit = LANTERN_COUNT
	return {
		"variant": variant,
		"has_save": has_save,
		"ending": ending,
		"chapter_id": chapter_id,
		"chapter_index": chapter_index,
		"done": done,
		"cleared": cleared,
		"act": act,
		"lit": lit,
		"skin": skin,
		"rank": int(peek.get("rank", 1)),
		"points": int(peek.get("points", 0)),
	}


## One visible hanging fixture per cleared chapter; physical light pools are shared.
static func lit_lantern_count(cleared: int) -> int:
	return clampi(cleared, 0, LANTERN_COUNT)


## Acts by chapter index in GameContext.LEVEL_ORDER: 1-3, 4-7, 8-11, 12-14 -> 1..4.
static func act_of_index(index: int) -> int:
	if index <= 2:
		return 1
	if index <= 6:
		return 2
	if index <= 10:
		return 3
	return 4


## Key into GRADES for a state.
static func grade_id(s: Dictionary) -> StringName:
	var variant: StringName = s.get("variant", VARIANT_COLD)
	if variant == VARIANT_JOURNEY:
		return StringName("act%d" % clampi(int(s.get("act", 1)), 1, 4))
	return variant


## +1 = facing the furnace (right), -1 = facing away (left). The knight rests facing away and turns
## to the furnace now and then; at the forge end ('keep') he is always looking into the fire.
static func rest_facing_for(variant_id: StringName) -> int:
	return 1 if variant_id == VARIANT_KEEP else -1


## Which living details show up, and how, for a state: the pure half of the props (the scene
## reads it in _apply_props, tests read it directly).
##   chain_mode    SwordChainScript.MODE_RUN / MODE_EMPTY / MODE_STILL
##   ghosts        lantern-bearing silhouettes on the far catwalk (0..3)
##   souls_rate    0..1 share of the soul pool; souls_escape = they leave through the roof gap
##   braziers      [first, second] brightness (0 = cold, 1 = lit, > 1 = brightest)
##   knight_turns  whether the knight looks at the furnace now and then
static func prop_plan(s: Dictionary) -> Dictionary:
	var variant: StringName = s.get("variant", VARIANT_COLD)
	var cleared := int(s.get("cleared", 0))
	var act := clampi(int(s.get("act", 1)), 1, 4)
	var plan := {
		"chain_mode": SwordChainScript.MODE_RUN,
		"ghosts": 1,
		"souls_rate": 0.40,
		"souls_escape": false,
		"braziers": [0.0, 0.0],
		"knight_turns": true,
	}
	match variant:
		VARIANT_JOURNEY:
			# brighter with the act; the first brazier at the first cleared chapter, the second at the seventh
			var level := lerpf(0.6, 1.0, float(act - 1) / 3.0)
			plan["ghosts"] = clampi(act, 1, 3)
			plan["souls_rate"] = clampf(0.48 + 0.018 * float(cleared), 0.48, 0.75)
			plan["braziers"] = [level if cleared >= BRAZIER_FIRST_AT else 0.0,
					level if cleared >= BRAZIER_SECOND_AT else 0.0]
		VARIANT_GIVE:
			# the sword is gone: the chain hangs empty and the souls leave through the roof
			plan["chain_mode"] = SwordChainScript.MODE_EMPTY
			plan["ghosts"] = 0
			plan["souls_rate"] = 1.0
			plan["souls_escape"] = true
			plan["braziers"] = [0.9, 0.9]
			plan["knight_turns"] = false
		VARIANT_KEEP:
			# the fire stays lit and so do the oaths: ghosts still queue, braziers burn brightest
			plan["ghosts"] = 3
			plan["souls_rate"] = 0.55
			plan["braziers"] = [1.3, 1.3]
			plan["knight_turns"] = false
		VARIANT_SNUFF:
			plan["chain_mode"] = SwordChainScript.MODE_STILL
			plan["ghosts"] = 0
			plan["souls_rate"] = 0.0
			plan["braziers"] = [0.0, 0.0]
			plan["knight_turns"] = false
	return plan


## What the title reads from the player's save without loading it (a fresh launch
## has not called SaveData.load_game yet): in-memory state wins when a game is
## loaded, otherwise the file on disk is peeked read-only.
static func peek_save() -> Dictionary:
	var in_memory := not SaveData.data.is_empty()
	# Profile fields (skin / rank / points) are only trusted from memory while a game is
	# loaded in it: a fresh launch (nothing loaded yet) shows what the file says.
	var out := {
		"has_save": SaveData.has_save(), "scene": "", "ending": SaveData.peek_ending(),
		"flags": SaveData.flags.duplicate(), "skin": SaveData.skin_id if in_memory else "", "origin": "",
		"rank": SaveData.ember_rank if in_memory else 1,
		"points": SaveData.attribute_points if in_memory else 0,
	}
	if in_memory:
		out["scene"] = String((SaveData.data.get("meta", {}) as Dictionary).get("scene", ""))
		var pl: Variant = SaveData.data.get("player", {})
		if pl is Dictionary:
			out["origin"] = String((pl as Dictionary).get("origin", ""))
	if bool(out["has_save"]):
		var cfg := _read_cfg(SaveData.save_path)
		if cfg == null:
			cfg = _read_cfg(SaveData.save_path + ".bak")
		if cfg != null:
			if String(out["scene"]) == "":
				out["scene"] = String(cfg.get_value("meta", "scene", ""))
			if String(out["origin"]) == "":
				out["origin"] = String(cfg.get_value("player", "origin", ""))
			var merged: PackedStringArray = out["flags"]
			for f in cfg.get_value("story", "flags", []):
				if not merged.has(String(f)):
					merged.append(String(f))
			out["flags"] = merged
			if String(out["skin"]) == "":
				out["skin"] = String(cfg.get_value("profile", "skin_id", ""))
			if not in_memory:
				out["rank"] = clampi(int(cfg.get_value("profile", "ember_rank", 1)), 1, 10)
				out["points"] = maxi(0, int(cfg.get_value("profile", "attribute_points", 0)))
	return out


static func _read_cfg(path: String) -> ConfigFile:
	if not FileAccess.file_exists(path):
		return null
	var cfg := ConfigFile.new()
	return cfg if cfg.load(path) == OK else null


static func state_from_save() -> Dictionary:
	if not forced_state.is_empty():
		return forced_state.duplicate(true)
	return build_state(peek_save())


## Switch the look (also callable after the scene is built).
func configure(new_state: Dictionary) -> void:
	state = new_state
	if _built:
		_apply_state()


func variant() -> StringName:
	return state.get("variant", VARIANT_COLD)


# ----------------------------------------------------------------- build -------

func _tex(file: String) -> Texture2D:
	# 标题屏是主场景：缺一张图就黑屏会连带所有运行验证都跑不了。没有导入的贴图
	# 直接返回 null，调用方各自降级（不建节点 / 空贴图），不要崩在启动上。
	var path := DIR + file
	if not ResourceLoader.exists(path):
		return null
	return DensityTextures.load_texture(path)


func _build() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ambient = CanvasModulate.new()
	_ambient.name = "Ambient"
	add_child(_ambient)

	var void_rect := Polygon2D.new()          # not a Control: nothing UI-ish lives in the world
	void_rect.name = "Void"
	void_rect.color = Color(0.04, 0.03, 0.06)
	void_rect.polygon = _rect_polygon(Rect2(Vector2(-48.0, -40.0), WORLD + Vector2(96.0, 80.0)))
	add_child(void_rect)

	_layer("HallFar", "hall_far.png", Vector2(-32.0, -4.0), -0.30, 0, self)
	# the molten river: emissive (unlit), driven by the furnace level
	_river = _layer("PitRiver", "pit_river.png", Vector2(-32.0, 330.0), -0.30, 0, self)
	var emissive := CanvasItemMaterial.new()
	emissive.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_river.material = emissive
	# 熔河不是静的：一层无缝流纹（tools/gen_river_current.py）用 river_flow.gdshader
	# 整像素地慢慢卷过去，炉越旺流得越急、越亮。
	_current = Sprite2D.new()
	_current.name = "RiverCurrent"
	_current.texture = _tex("river_current.png")
	_current.centered = false
	_current.position = Vector2(-32.0, 330.0)
	_current.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_current_mat = ShaderMaterial.new()
	_current_mat.shader = preload("res://assets/shaders/river_flow.gdshader")
	_current.material = _current_mat
	add_child(_current)
	_register(_current, Vector2(-32.0, 330.0), -0.30, Vector2(-32.0, 330.0) + Vector2(352.0, 20.0))
	_beam = _layer("Beam", "beam.png", BEAM_POS, -0.20, 0, self)
	var beam_mat := CanvasItemMaterial.new()
	beam_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	beam_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_beam.material = beam_mat
	_layer("HallMid", "hall_mid.png", Vector2(-32.0, -4.0), -0.55, 1, self)
	_pit_glow = _layer("PitGlow", "glow.png", Vector2(10.0, 290.0), -0.1, 2, self)
	_pit_glow.scale = Vector2(5.0, 1.1)
	_pit_glow.material = beam_mat
	_pit_glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	_build_gears()
	_build_far_props()

	_stage = Node2D.new()
	_stage.name = "Stage"
	_stage.z_index = 10
	add_child(_stage)
	var bridge := Sprite2D.new()
	bridge.name = "Bridge"
	bridge.texture = _tex("bridge.png")
	bridge.centered = false
	bridge.position = BRIDGE_POS
	bridge.z_index = -5
	bridge.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_stage.add_child(bridge)
	_occluder(_stage, "BridgeShadow", Rect2(150, DECK_Y + 2, 344, 9))
	# 近侧栏杆单独一层画在演员前面（tools/gen_bridge_front.py 从 bridge.png 切出）：
	# 骑士 / 火盆 / 余烬巢都站在栏杆后面，不再是浮在桥上。
	var rail := Sprite2D.new()
	rail.name = "BridgeFront"
	rail.texture = _tex("bridge_front.png")
	rail.centered = false
	rail.position = BRIDGE_POS
	rail.z_index = 5
	rail.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_stage.add_child(rail)
	_build_braziers()
	_build_spill()

	_build_chains()
	_build_overhead_props()

	_layer("Roof", "roof.png", Vector2(-32.0, -10.0), 0.5, 30, self)

	_layer("MassLeft", "mass_left.png", MASS_LEFT_POS, 1.0, 40, self)
	var mass_right := _layer("MassRight", "mass_right.png", MASS_RIGHT_POS, 1.0, 40, self)
	_mouth = Sprite2D.new()
	_mouth.name = "ForgeMouth"
	_mouth.texture = _tex("forge_mouth.png")
	_mouth.hframes = 16
	_mouth.centered = false
	_mouth.position = MOUTH_IN_MASS
	_mouth.show_behind_parent = true
	_mouth.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# the furnace door is a light source itself: emissive, not lit by the scene
	var mouth_mat := CanvasItemMaterial.new()
	mouth_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_mouth.material = mouth_mat
	mass_right.add_child(_mouth)
	_front_gear(mass_right)
	_occluder(mass_right, "FurnacePierShadow", Rect2(32, 144, 14, 114))

	_build_lights()
	_build_glow_layer()


static func _rect_polygon(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


## Adds a textured layer and registers it in the parallax list.
func _layer(node_name: String, file: String, pos: Vector2, depth: float, z: int, parent: Node) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.name = node_name
	spr.texture = _tex(file)
	spr.centered = false
	spr.position = pos
	spr.z_index = z
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(spr)
	_register(spr, pos, depth, pos + (spr.texture.get_size() * 0.5 if spr.texture != null else Vector2.ZERO))
	return spr


func _register(node: Node2D, base: Vector2, depth: float, centre: Vector2) -> void:
	_px_nodes.append(node)
	_px_base.append(base)
	_px_depth.append(depth)
	var dir := (centre - FEET)
	_px_dir.append(dir.normalized() if dir.length() > 1.0 else Vector2.UP)


func _build_gears() -> void:
	var gears := Node2D.new()
	gears.name = "Gears"
	gears.z_index = 2
	add_child(gears)
	# [name, file, cols, rows, frames, period, deg/s, position, depth, start]
	for spec in [
		["GearBig", "gear_big.png", 8, 4, 32, 45.0, 4.5, Vector2(80.0, 98.0), 0.55, 0.0],
		["GearSmall", "gear_small.png", 6, 4, 24, 60.0, 6.4, Vector2(160.0, 130.0), 0.55, 20.0],
	]:
		var gear := TitleGear.new()
		gear.name = spec[0]
		gear.setup(DIR + String(spec[1]), int(spec[2]), int(spec[3]), int(spec[4]), float(spec[5]),
				float(spec[6]), float(spec[9]))
		gear.position = spec[7]
		gears.add_child(gear)
		_gears.append(gear)
		_register(gear, spec[7], float(spec[8]), spec[7])


func _front_gear(mass_right: Node2D) -> void:
	var gear := TitleGear.new()
	gear.name = "GearFront"
	gear.setup(DIR + "gear_mid.png", 8, 4, 32, 45.0, 3.4, 10.0)
	gear.position = Vector2(214.0, 300.0)
	mass_right.add_child(gear)
	_gears.append(gear)


func _build_chains() -> void:
	var host := Node2D.new()
	host.name = "Chains"
	host.z_index = 20
	add_child(host)
	# plain chains: [x, top, length, depth, amp, period, phase]
	for spec in [
		[66.0, 40.0, 70.0, 0.35, 1.5, 7.0, 0.4], [186.0, 44.0, 58.0, 0.1, 1.5, 6.4, 2.1],
		[286.0, 44.0, 104.0, -0.1, 2.0, 7.6, 3.3], [372.0, 44.0, 84.0, 0.0, 2.0, 6.8, 4.8],
		[462.0, 42.0, 120.0, 0.3, 1.5, 8.0, 1.2], [578.0, 40.0, 92.0, 0.7, 2.0, 7.2, 5.5],
	]:
		var c := TitleChain.new()
		c.name = "Chain%d" % _chains.size()
		c.length = float(spec[2])
		c.swing_amp = float(spec[4])
		c.swing_period = float(spec[5])
		c.swing_phase = float(spec[6])
		c.position = Vector2(float(spec[0]), float(spec[1]))
		host.add_child(c)
		_chains.append(c)
		_register(c, c.position, float(spec[3]), c.position + Vector2(0.0, c.length * 0.5))
	# All fourteen chapter lamps remain below the logo and above the menu rail.
	for i in LANTERN_COUNT:
		var lantern := TitleLantern.new()
		lantern.name = "Lantern%d" % _lanterns.size()
		# The fourteen progress cages must remain in front of the side machinery.
		lantern.z_index = 25
		lantern.length = 62.0 + float(i % 3) * 4.0
		lantern.swing_amp = 1.0
		lantern.swing_period = 6.2 + float(i % 4) * 0.4
		lantern.swing_phase = float(i) * 0.7
		lantern.light_radius = 84.0
		lantern.emits_light = LIGHT_POOL_FIXTURES.has(i)
		lantern.casts_shadows = i in [4, 10]
		lantern.position = Vector2(80.0 + float(i) * 31.0, 38.0)
		host.add_child(lantern)
		_lanterns.append(lantern)
		_register(lantern, lantern.position, 0.15, lantern.position + Vector2(0.0, lantern.length * 0.5))


## The far hall: the crucible's rail, the trip-hammer and the lantern procession. Same depth as
## HallFar / the pit (-0.30), above HallMid, below the stage (so the bridge and the knight
## stand in front, and the masses at the ends swallow whatever walks behind them).
func _build_far_props() -> void:
	_far = Node2D.new()
	_far.name = "FarProps"
	_far.z_index = 2
	add_child(_far)
	# 对岸细栈桥（tools/gen_far_walkway.py）：锻锤的垫墩顶面与亡魂的脚线都站在 FAR_DECK_Y 上，
	# 没有这条桥它们全是悬空的。先加，垫在坩埚 / 锻锤 / 亡魂后面。
	var walkway := Sprite2D.new()
	walkway.name = "FarWalkway"
	walkway.texture = _tex("far_walkway.png")
	walkway.centered = false
	walkway.position = Vector2(156.0, FAR_DECK_Y - 5.0)
	walkway.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_far.add_child(walkway)
	# 亡魂画在锻锤后面：巡行路线会路过锤位，从锤后面走过去才不像穿模。
	_ghosts = GhostScript.new()
	_ghosts.name = "Ghosts"
	_far.add_child(_ghosts)
	_crucible = CrucibleScript.new()
	_crucible.name = "Crucible"
	_far.add_child(_crucible)
	_crucible.poured.connect(_on_crucible_poured)
	_crucible.splashed.connect(_on_crucible_splash)
	_hammer = HammerScript.new()
	_hammer.name = "Hammer"
	_hammer.position = HAMMER_POS
	# 整数倍放大，落砧的白热在桥上能认出来；原点在砧面，放大后仍踩在栈桥上。
	_hammer.scale = Vector2(2.0, 2.0)
	_far.add_child(_hammer)
	_hammer.struck.connect(_on_hammer_struck)
	_register(_far, Vector2.ZERO, -0.30, CENTER)
	_heat_props.append(_crucible)
	_heat_props.append(_hammer)
	_heat_props.append(_ghosts)


## Furnace light spilled onto the planks and a warm edge on whoever stands on the bridge.
## Additive sprites only — the eight PointLight2D slots are already taken.
func _build_spill() -> void:
	var glow := _tex("glow.png")
	_wash = Sprite2D.new()
	_wash.name = "BridgeWash"
	_wash.texture = glow
	_wash.centered = true
	_wash.position = Vector2(418.0, DECK_Y + 2.0)
	_wash.scale = Vector2(2.6, 0.42)
	_wash.z_index = -4
	_wash.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_wash.material = Fx.additive_mat()
	_stage.add_child(_wash)
	_rim = Sprite2D.new()
	_rim.name = "KnightRim"
	_rim.texture = glow
	_rim.centered = true
	_rim.position = FEET + Vector2(12.0, -20.0)
	_rim.scale = Vector2(0.62, 0.78)
	_rim.z_index = 2
	_rim.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_rim.material = Fx.additive_mat()
	_stage.add_child(_rim)


## Two braziers at the bridge head, on the stage just above the bridge sprite and below the actors.
func _build_braziers() -> void:
	_braziers = BrazierScript.new()
	_braziers.name = "Braziers"
	_braziers.z_index = -1
	_stage.add_child(_braziers)
	_heat_props.append(_braziers)


## Hanging from the roof truss: the sword chain (rides with the roof, depth 0.5, behind the roof
## itself and the furnace housing) and two torn banners (depth 0.3).
func _build_overhead_props() -> void:
	_sword_chain = SwordChainScript.new()
	_sword_chain.name = "SwordChain"
	# 在屋架前面、炉房墙后面：横着送过去的剑能被看见，垂进炉口的那段仍被墙挡住。
	_sword_chain.z_index = 32
	add_child(_sword_chain)
	_sword_chain.delivered.connect(_on_sword_delivered)
	_register(_sword_chain, Vector2.ZERO, 0.5, CENTER)
	_banner_host = Node2D.new()
	_banner_host.name = "Banners"
	_banner_host.z_index = 15
	add_child(_banner_host)
	for i in BANNER_XS.size():
		var banner = BannerScript.new()
		banner.name = "Banner%d" % i
		banner.position = Vector2(BANNER_XS[i], BANNER_TOP)
		banner.phase = float(i) * 2.1
		_banner_host.add_child(banner)
		_banners.append(banner)
		_heat_props.append(banner)
	_register(_banner_host, Vector2.ZERO, 0.3, CENTER)
	_heat_props.append(_sword_chain)


func _make_light(node_name: String, pos: Vector2, radius: float) -> PointLight2D:
	var l := PointLight2D.new()
	l.name = node_name
	l.texture = _tex("glow.png")
	l.texture_scale = radius * 2.0 / 128.0
	l.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	l.position = pos
	l.shadow_enabled = false
	l.energy = 0.0
	add_child(l)
	return l


func _build_lights() -> void:
	_pit_light = _make_light("PitLight", Vector2(340.0, 336.0), 280.0)
	_shaft_light = _make_light("ShaftLight", Vector2(292.0, 150.0), 210.0)
	_forge_light = _make_light("ForgeLight", Vector2(486.0, 246.0), 150.0)
	_shaft_light.shadow_enabled = true
	_forge_light.shadow_enabled = true


func _occluder(parent: Node, node_name: String, rect: Rect2) -> void:
	var blocker := LightOccluder2D.new()
	blocker.name = node_name
	blocker.occluder = OccluderPolygon2D.new()
	blocker.occluder.polygon = _rect_polygon(rect)
	parent.add_child(blocker)


func _build_glow_layer() -> void:
	_glow_layer = CanvasLayer.new()
	_glow_layer.name = "Glow"
	_glow_layer.layer = 1
	add_child(_glow_layer)
	_motes = TitleSparks.new()
	_motes.name = "Motes"
	_motes.beam_origin = BEAM_POS
	_glow_layer.add_child(_motes)
	_register(_motes, Vector2.ZERO, -0.2, CENTER)
	_sparks = TitleSparks.new()
	_sparks.name = "Sparks"
	_sparks.speck_center = FEET + Vector2(0.0, -34.0)
	_glow_layer.add_child(_sparks)
	_register(_sparks, Vector2.ZERO, 0.45, CENTER)
	# soul lights rise off the river: additive, in the unlit glow layer, river depth (-0.30)
	_souls = SoulScript.new()
	_souls.name = "Souls"
	_glow_layer.add_child(_souls)
	_register(_souls, Vector2.ZERO, -0.30, CENTER)
	_vignette = Sprite2D.new()
	_vignette.name = "Vignette"
	_vignette.texture = _tex("vignette.png")
	_vignette.centered = false
	_vignette.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_glow_layer.add_child(_vignette)
	_flash = Polygon2D.new()
	_flash.name = "Flash"
	_flash.color = Color(1.0, 0.86, 0.6, 0.0)
	_flash.polygon = _rect_polygon(Rect2(Vector2.ZERO, WORLD))
	_glow_layer.add_child(_flash)
	_camera = Camera2D.new()
	_camera.name = "Camera"
	_camera.position = CENTER
	add_child(_camera)


# ----------------------------------------------------------------- apply -------

func _apply_state() -> void:
	var gid := grade_id(state)
	_grade = GRADES[gid]
	var var_id := variant()
	# who stands on the bridge
	_clear_actors()
	var skin := StringName(String(state.get("skin", SkinCatalog.DEFAULT_SKIN)))
	match var_id:
		VARIANT_GIVE:
			_place_planted()
		VARIANT_SNUFF:
			pass
		VARIANT_KEEP:
			_place_knight(skin, KEEP_X, true)
			_place_nest(KEEP_X - 40.0)
		_:
			_place_knight(skin, KNIGHT_X)
	# lanterns
	var lit := int(state.get("lit", 0))
	for i in _lanterns.size():
		var lantern := _lanterns[i]
		lantern.tint = _grade["lantern"]
		lantern.flicker = float(_grade["flicker"])
		lantern.set_lit(i < lit, _intro_level >= 1.0)
	# machines + particles
	for g in _gears:
		g.speed_mult = float(_grade["gears"])
	var embers := float(_grade["embers"])
	_sparks.set_rates(embers, float(_grade["ash"]), 0.0, 1.0 if var_id == VARIANT_GIVE else 0.0)
	_motes.set_rates(0.0, 0.0, clampf(float(_grade["shaft"]), 0.0, 1.0), 0.0)
	_sparks.set_vents(PackedVector2Array([Vector2(194.0, 244.0), Vector2(172.0, 204.0), Vector2(470.0, 150.0)]),
			float(_grade["steam"]))
	_apply_props()
	_refresh_grade()


## The living details for the current state (prop_plan): who is lit, who walks, who is gone.
func _apply_props() -> void:
	_plan = prop_plan(state)
	_sword_chain.set_mode(int(_plan["chain_mode"]))
	_ghosts.set_count(int(_plan["ghosts"]))
	var brazier_levels: Array = _plan["braziers"]
	_braziers.set_levels(float(brazier_levels[0]), float(brazier_levels[1]))
	_souls.set_flow(float(_plan["souls_rate"]), bool(_plan["souls_escape"]))
	_gaze_enabled = bool(_plan["knight_turns"]) and knight() != null
	_gaze_wait = GAZE_FIRST
	_gaze_hold = 0.0


func _clear_actors() -> void:
	for n in [_knight, _planted, _nest]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_knight = null
	_planted = null
	_nest = null
	_nest_flame = null
	_gaze_enabled = false
	_gaze_hold = 0.0


func _place_knight(skin: StringName, x: float, seated: bool = false) -> void:
	_knight = Node2D.new()
	_knight.name = "Knight"
	_knight.position = Vector2(x, DECK_Y)
	_stage.add_child(_knight)
	var visual := Node2D.new()
	visual.name = "Visual"
	_knight.add_child(visual)
	# rests facing away from the furnace; looks at it now and then (_update_gaze)
	visual.scale.x = float(rest_facing_for(variant()))
	var frames := SkinCatalog.frames_for(skin, &"idle")
	var anim := FrameAnimSprite.new()
	anim.name = "KnightSprite"
	if seated:
		var pose := load("res://assets/title/seated_%s.png" % SkinCatalog.folder_of(skin)) as Texture2D
		anim.register("seated", [pose], 1.0, true, Vector2(0, -24))
		anim.play("seated")
		_occluder(_knight, "KnightShadow", Rect2(-7, -29, 17, 28))
	elif not frames.is_empty():
		anim.register("idle", frames, 10.0, true, SkinCatalog.offset_for(skin, &"idle"))
		anim.play("idle")
		_occluder(_knight, "KnightShadow", Rect2(-5, -34, 10, 34))
	anim.modulate = SkinCatalog.tint_of(skin)
	visual.add_child(anim)
	var sword := Greatsword.new()
	visual.add_child(sword)
	sword.show_carried()
	if seated:
		sword.hide()


func _place_planted() -> void:
	_planted = Greatsword.spawn_planted(_stage, Vector2(KNIGHT_X - 6.0, DECK_Y + 2.0))


func _place_nest(x: float) -> void:
	_nest = Node2D.new()
	_nest.name = "EmberNest"
	_nest.position = Vector2(x, DECK_Y - 14.0)
	_stage.add_child(_nest)
	var base := Sprite2D.new()
	base.name = "Base"
	base.texture = DensityTextures.load_texture("res://assets/env/ember_nest.png")
	base.centered = false
	base.position = Vector2(-16.0, -20.0)
	base.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_nest.add_child(base)
	var coals := Sprite2D.new()
	coals.name = "Coals"
	coals.texture = DensityTextures.load_texture("res://assets/env/ember_nest_coals.png")
	coals.centered = false
	coals.position = Vector2(-16.0, -20.0)
	coals.material = Fx.additive_mat()
	coals.z_index = 1
	coals.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_nest.add_child(coals)
	# 巢火和桥头火盆同一条粒子火焰（升起 / 受风 / 渐冷），不再是 8 帧贴图条。
	# 守炉结局里它是骑士望着的那团火：体量给到 1.0，比火盆的单口略足。
	var flame := FlameScript.new()
	flame.name = "Flame"
	flame.position = Vector2(6.0, -12.0)
	flame.z_index = 2
	flame.scale01 = 1.0
	_nest.add_child(flame)
	_nest_flame = flame


## Everything that depends on the grade AND the intro / quit levels.
func _refresh_grade() -> void:
	if _grade.is_empty():
		return
	var level := _intro_level * _quit_level
	var ambient: Color = _grade["ambient"]
	_ambient.color = Color(ambient.r, ambient.g, ambient.b).lerp(Color(0.02, 0.015, 0.03), 1.0 - lerpf(0.25, 1.0, level))
	var shaft := float(_grade["shaft"]) * level
	var sc: Color = _grade["shaft_color"]
	# the shaft is additive on the dimmed canvas: lift it by the ambient so it reads true
	_beam_alpha = 0.5 * shaft
	_beam.modulate = Color(sc.r / maxf(ambient.r, 0.2), sc.g / maxf(ambient.g, 0.2),
			sc.b / maxf(ambient.b, 0.2), _beam_alpha * _cloud)
	var fc: Color = _grade["furnace_color"]
	var furnace := float(_grade["furnace"]) * level
	_pit_glow.modulate = Color(fc.r / maxf(ambient.r, 0.2), fc.g / maxf(ambient.g, 0.2),
			fc.b / maxf(ambient.b, 0.2), clampf(0.30 * furnace, 0.0, 0.85))
	var forge := float(_grade["forge"]) * level
	# unlit materials: undo the ambient (1/ambient) and scale by how hot the forge burns
	var heat := Color(0.07, 0.03, 0.03).lerp(Color(1.0, 0.96, 0.9), clampf(forge, 0.0, 1.0))
	# The unshaded fire already carries its colour; ambient compensation clips it yellow-green.
	_mouth.modulate = heat
	var river_heat := Color(0.10, 0.05, 0.045).lerp(Color(1.35, 1.10, 0.88), clampf(furnace, 0.0, 1.0))
	_river.modulate = Color(river_heat.r / maxf(ambient.r, 0.2), river_heat.g / maxf(ambient.g, 0.2),
			river_heat.b / maxf(ambient.b, 0.2))
	# 流纹层：炉温定亮度和流速；冷炉时整层熄掉。
	_current.modulate = Color(1.0, 1.0, 1.0, clampf(furnace, 0.0, 1.0) * 0.6)
	_river_flow = (1.5 + 4.0 * clampf(furnace, 0.0, 1.2)) * (1.0 if furnace > 0.03 else 0.0)
	_pit_light.color = fc
	_shaft_light.color = sc
	_forge_light.color = Color(1.0, 0.5, 0.2)
	if variant() == VARIANT_SNUFF:
		_forge_light.position = FEET + Vector2(0.0, -10.0)
		_forge_light.texture_scale = 90.0 * 2.0 / 128.0
		_forge_light.color = Color(1.0, 0.18, 0.08)
	else:
		_forge_light.position = Vector2(486.0, 246.0)
		_forge_light.texture_scale = 150.0 * 2.0 / 128.0
	_update_lights(0.0)
	_place_rim()
	_apply_spill()
	_vignette.modulate.a = 1.0
	_sparks.modulate.a = clampf(level * 1.2, 0.0, 1.0)
	_motes.modulate.a = clampf(level * 1.2, 0.0, 1.0)
	_push_prop_look()


## Park the warm edge on whoever is standing on the bridge (knight, planted sword, or the empty spot).
func _place_rim() -> void:
	if _rim == null:
		return
	var at := FEET
	var which := variant()
	if which == VARIANT_KEEP:
		at = Vector2(KEEP_X, DECK_Y)
	elif which == VARIANT_GIVE:
		at = Vector2(KNIGHT_X - 6.0, DECK_Y - 8.0)
	_rim.position = Vector2(roundf(at.x + 14.0), roundf(at.y - 22.0))


## Lift the additive spill by 1/ambient so CanvasModulate doesn't swallow it.
func _apply_spill() -> void:
	if _wash == null or _rim == null or _grade.is_empty() or _ambient == null:
		return
	var level := _intro_level * _quit_level
	var hot := float(_grade["furnace"]) * level
	var snuff := variant() == VARIANT_SNUFF
	var wash_a := 0.05 * level if snuff else clampf(0.20 + hot * 0.24 + _flare * 0.28 + _surge * 0.18, 0.0, 0.58)
	var rim_a := 0.07 * level if snuff else clampf(0.30 + hot * 0.32 + _flare * 0.30, 0.0, 0.70)
	var amb := _ambient.color
	var lr := 1.0 / maxf(amb.r, 0.2)
	var lg := 1.0 / maxf(amb.g, 0.2)
	var lb := 1.0 / maxf(amb.b, 0.2)
	var wash_col := Color(1.0, 0.42, 0.14) if not snuff else Color(0.7, 0.16, 0.08)
	var rim_col := Color(1.0, 0.58, 0.24) if not snuff else Color(0.85, 0.22, 0.1)
	_wash.modulate = Color(wash_col.r * lr, wash_col.g * lg, wash_col.b * lb, wash_a)
	_rim.modulate = Color(rim_col.r * lr, rim_col.g * lg, rim_col.b * lb, rim_a)


func _update_lights(_delta: float) -> void:
	if _grade.is_empty():
		return
	var level := _intro_level * _quit_level
	var step := floorf(_t * 10.0)
	var breathe := 1.0 + 0.07 * sin(_t * TAU / 5.4) + 0.03 * sin(step * 2.3)
	var snuff := variant() == VARIANT_SNUFF
	_pit_light.energy = float(_grade["furnace"]) * level * breathe * (1.0 + _flare * 0.5 + _surge * 0.6)
	_shaft_light.energy = 0.32 * float(_grade["shaft"]) * level * _cloud
	if snuff:
		_forge_light.energy = 0.55 * (0.5 + 0.5 * sin(_t * TAU / 3.8)) * level
	else:
		_forge_light.energy = float(_grade["forge"]) * level \
				* (1.0 + 0.10 * sin(step * 1.9) + _flare * 0.4 + _surge * 0.5)
	_apply_spill()


# --------------------------------------------------------------- per frame -----

func _process(delta: float) -> void:
	_t += delta
	if _mouth != null and float(_grade.get("forge", 0.0)) * _intro_level * _quit_level > 0.1:
		_mouth.frame = posmod(int(floor(_t * 12.0)), 16)
	var k := 1.0 - exp(-POINTER_EASE * delta)
	_shift = _shift.lerp(Vector2(_pointer.x * PARALLAX.x, _pointer.y * PARALLAX.y), k)
	_push_kick = move_toward(_push_kick, 0.0, delta * 6.0)
	_flare = move_toward(_flare, 0.0, delta * 1.8)
	_breath = 0.0 if _frozen_breath else sin(_t * TAU / BREATH_PERIOD) * 1.0
	var cam := CENTER + Vector2(0.0, roundf(_breath))
	if _camera.position != cam:
		_camera.position = cam
	_apply_parallax(false)
	_animate_props(delta)
	_update_lights(delta)
	_animate_actors(delta)
	if _flash_amount > 0.0:
		_flash_amount = move_toward(_flash_amount, 0.0, delta * 2.2)
		_flash.color.a = _flash_amount


func _apply_parallax(force: bool) -> void:
	var push := _push + _push_kick
	for i in _px_nodes.size():
		var d := _px_depth[i]
		var off := -_shift * d + _px_dir[i] * (push * d)
		var pos := _px_base[i] + Vector2(roundf(off.x), roundf(off.y))
		var node := _px_nodes[i]
		if force or node.position != pos:
			node.position = pos


func _animate_actors(delta: float) -> void:
	if _knight != null and is_instance_valid(_knight):
		var sword := _knight.get_node_or_null("Visual/Greatsword") as Greatsword
		if sword != null:
			var s := sin(_t * 1.7) * Greatsword.IDLE_SWAY
			sword.rotation = lerpf(sword.rotation, s, 1.0 - exp(-8.0 * delta))
			sword.position.y = Greatsword.BACK_HILT.y + roundf(sin(_t * 0.9) * 0.6)


# ----------------------------------------------------------- living details ----

## 1.0 = the light shaft at full strength; down to 1 - CLOUD_DEPTH while a cloud passes the roof
## gap (two slow sines, so it never repeats exactly).
static func cloud_shade(phase: float) -> float:
	var c := clampf(0.5 + 0.32 * sin(phase) + 0.18 * sin(phase * 0.37 + 1.7), 0.0, 1.0)
	return 1.0 - CLOUD_DEPTH * c


## Per frame: the menu reactions decay, the shaft's cloud shade drifts, the knight's gaze clock
## runs, and every living detail is told how hot the forge is right now.
func _animate_props(delta: float) -> void:
	_surge = move_toward(_surge, 0.0, delta * 0.9)
	_brazier_boost = move_toward(_brazier_boost, 0.0, delta * 0.55)
	_gust = move_toward(_gust, 0.0, delta * 0.5)
	_soul_boost = move_toward(_soul_boost, 0.0, delta * 0.35)
	_cloud_speed = move_toward(_cloud_speed, _cloud_target, delta * 1.2)
	_cloud_phase += delta * TAU / CLOUD_PERIOD * _cloud_speed
	_cloud = cloud_shade(_cloud_phase)
	# 熔河流动：整像素步进（最近邻采样不出灰边），流速由 _refresh_grade 按炉温定。
	if _current_mat != null and _river_flow > 0.0:
		_river_scroll = fposmod(_river_scroll + delta * _river_flow, 704.0)
		_current_mat.set_shader_parameter("scroll_px", floorf(_river_scroll))
	if _beam != null and not _grade.is_empty():
		var alpha_now := _beam_alpha * _cloud
		if absf(_beam.modulate.a - alpha_now) > 0.002:
			_beam.modulate.a = alpha_now
	_update_wave(delta)
	_update_gaze(delta)
	_push_prop_look()


## Tell every living detail how hot the forge is (grade x intro/quit level, plus the 'new' surge)
## and how much to lift its glowing parts to read on the ambient-dimmed canvas.
func _push_prop_look() -> void:
	if _grade.is_empty() or _heat_props.is_empty():
		return
	var level := _intro_level * _quit_level
	var amb := _ambient.color
	var lift := Color(1.0 / maxf(amb.r, 0.2), 1.0 / maxf(amb.g, 0.2), 1.0 / maxf(amb.b, 0.2), 1.0)
	var heat := float(_grade["forge"]) * level * (1.0 + _surge * 0.5)
	for prop in _heat_props:
		prop.set_look(heat, lift)
	_braziers.boost = _brazier_boost
	# 巢火不是 §6.1 的常驻道具（只有守炉结局在）：单独喂炉温与环境色。
	if _nest_flame != null and is_instance_valid(_nest_flame):
		_nest_flame.set_look(heat, lift)
	for banner in _banners:
		banner.gust = _gust
	_souls.boost = _soul_boost
	_souls.modulate.a = clampf(level * 1.2, 0.0, 1.0)


## 'continue': the lanterns flare one after another, nearest the knight first.
func _update_wave(delta: float) -> void:
	if _wave < 0.0:
		return
	_wave += delta
	while _wave_next < _lanterns.size() and _wave >= 0.16 * float(_wave_next):
		_lanterns[_wave_next].flare(0.9)
		_wave_next += 1
	if _wave_next >= _lanterns.size():
		_wave = -1.0


func _update_gaze(delta: float) -> void:
	if not _gaze_enabled or knight() == null:
		return
	if _gaze_hold > 0.0:
		_gaze_hold -= delta
		if _gaze_hold <= 0.0:
			_set_facing(rest_facing_for(variant()))
		return
	_gaze_wait -= delta
	if _gaze_wait <= 0.0:
		_gaze_wait = GAZE_PERIOD
		gaze_at_forge(GAZE_HOLD)


## The knight turns to look at the furnace for `hold` seconds (the forge flares a little as he
## does). Only knights that rest facing away turn: the 'keep' knight is always looking at the fire.
func gaze_at_forge(hold: float = GAZE_HOLD) -> void:
	if knight() == null or not _gaze_enabled:
		return
	_gaze_hold = maxf(hold, 0.1)
	_set_facing(1)
	_flare = maxf(_flare, 0.25)


## +1 = facing the furnace, -1 = facing away, 0 = no knight on the bridge.
func knight_facing() -> int:
	if knight() == null:
		return 0
	var visual := _knight.get_node_or_null("Visual") as Node2D
	if visual == null:
		return 0
	return 1 if visual.scale.x >= 0.0 else -1


func _set_facing(direction: int) -> void:
	if knight() == null:
		return
	var visual := _knight.get_node_or_null("Visual") as Node2D
	if visual != null:
		visual.scale.x = float(direction)


func _mouth_center() -> Vector2:
	return _mouth.global_position + Vector2(28.0, 34.0)


func _on_crucible_poured(at: Vector2) -> void:
	_sparks.burst(_crucible.to_global(at), 20, 78.0)
	_flare = maxf(_flare, 0.85)
	_surge = maxf(_surge, 0.45)


func _on_crucible_splash(at: Vector2) -> void:
	_sparks.burst(_crucible.to_global(at), 8, 56.0)
	_flare = maxf(_flare, 0.35)


func _on_hammer_struck(at: Vector2) -> void:
	_sparks.burst(_hammer.to_global(at), 14, 84.0)
	_flare = maxf(_flare, 0.65)


func _on_sword_delivered(at: Vector2) -> void:
	_sparks.burst(_sword_chain.to_global(at), 8, 52.0)
	_flare = maxf(_flare, 0.4)


## Every menu row has a reaction in the hall (the title calls this when focus lands on a row):
##   new       the furnace surges: lights swell, embers pour out of the furnace mouth
##   continue  the knight turns to the furnace; the lanterns flare one after another
##   trial     the far trip-hammer strikes now
##   arena     the bridge-head braziers flare (even cold ones jump alight for a moment)
##   settings  the cloud shade over the light shaft slows right down (until focus moves on)
##   controls  a gust: the banners snap
##   quit      the souls rise faster / more of them (the hall is letting go)
## Returns false for an id with no reaction (ids outside REACTIONS are ignored).
func react_to(menu_id: StringName) -> bool:
	if not REACTIONS.has(menu_id):
		return false
	_last_reaction = menu_id
	_reaction_count += 1
	# sustained reactions last only while their row has focus
	_cloud_target = 1.0
	match menu_id:
		&"new":
			_surge = 1.0
			_flare = maxf(_flare, 0.6)
			_sparks.burst(_mouth_center(), 14, 72.0)
		&"continue":
			gaze_at_forge(GAZE_HOLD)
			_wave = 0.0
			_wave_next = 0
		&"trial":
			_hammer.strike_now()
		&"arena":
			_brazier_boost = 1.0
		&"settings":
			_cloud_target = CLOUD_SLOW
		&"controls":
			_gust = 1.0
		&"quit":
			_soul_boost = 1.0
			_souls.kick(6)
	return true


func last_reaction() -> StringName:
	return _last_reaction


func reaction_count() -> int:
	return _reaction_count


## Everything a reaction can change, for tests and tools.
func reaction_state() -> Dictionary:
	return {
		"last": _last_reaction,
		"count": _reaction_count,
		"surge": _surge,
		"wave_active": _wave >= 0.0,
		"strike_requests": _hammer.strike_requests(),
		"brazier_boost": _brazier_boost,
		"cloud_target": _cloud_target,
		"cloud_speed": _cloud_speed,
		"gust": _gust,
		"soul_boost": _soul_boost,
		"gazing": _gaze_hold > 0.0,
	}


# ------------------------------------------------------------------- public ----

## Pointer position over the title, -1..1 on both axes (centre = 0).
func set_pointer(norm: Vector2) -> void:
	_pointer = Vector2(clampf(norm.x, -1.0, 1.0), clampf(norm.y, -1.0, 1.0))


## Menu focus: lanterns flare and the whole hall gets a 1-2 px push.
func nudge(strength: float = 1.0) -> void:
	_flare = maxf(_flare, 0.7 * strength)
	_push_kick = maxf(_push_kick, 1.6 * strength)
	for lantern in _lanterns:
		lantern.flare(0.8 * strength)


## Confirm-to-enter: white-hot flash and a push toward the knight (px, seconds).
func enter_push(px: float = 5.0, seconds: float = 0.5) -> void:
	_flash_amount = 1.0
	_flash.color = Color(1.0, 0.9, 0.7, 1.0)
	if _push_tween != null and _push_tween.is_valid():
		_push_tween.kill()
	_push_tween = create_tween()
	_push_tween.tween_property(self, "_push", px, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for lantern in _lanterns:
		lantern.flare(1.0)
	_flare = 1.0


## Spark burst at a world position (menu cursor, confirm).
func burst_at(world_pos: Vector2, count: int = 10) -> void:
	_sparks.burst(world_pos, count)


## Boot: the hall starts dark, lanterns come on one by one. Returns the duration.
func play_intro(stagger: float = 0.16) -> float:
	_intro_level = 0.0
	var lit := int(state.get("lit", 0))
	for i in _lanterns.size():
		_lanterns[i].set_lit(false, true)
	_refresh_grade()
	if _intro_tween != null and _intro_tween.is_valid():
		_intro_tween.kill()
	var tw := create_tween()
	_intro_tween = tw
	tw.tween_property(self, "_intro_level", 1.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var total := 0.9
	for i in mini(lit, _lanterns.size()):
		var at := 0.30 + stagger * float(i)
		tw.parallel().tween_callback(_light_lantern.bind(i)).set_delay(at)
		total = maxf(total, at + 0.3)
	tw.tween_callback(_finish_intro)
	return total


func _light_lantern(i: int) -> void:
	if i < _lanterns.size():
		_lanterns[i].set_lit(true)
		_lanterns[i].flare(0.9)
		_flare = maxf(_flare, 0.4)


func _finish_intro() -> void:
	_intro_level = 1.0
	_refresh_grade()


## Land in the final state at once (skip / tests).
func skip_intro() -> void:
	if _intro_tween != null and _intro_tween.is_valid():
		_intro_tween.kill()
	_intro_level = 1.0
	var lit := int(state.get("lit", 0))
	for i in _lanterns.size():
		_lanterns[i].set_lit(i < lit, true)
	_refresh_grade()


## Quit: lanterns go out one by one, the hall falls dark and only the greatsword's
## silhouette glows on. Returns the duration.
func quit_out(stagger: float = 0.2) -> float:
	_frozen_breath = true
	# the greatsword silhouette that stays lit is the unmirrored one: stop turning, face the furnace
	_gaze_enabled = false
	_gaze_hold = 0.0
	_set_facing(1)
	if _quit_tween != null and _quit_tween.is_valid():
		_quit_tween.kill()
	var tw := create_tween()
	_quit_tween = tw
	var t := 0.0
	var any := false
	for lantern in _lanterns:
		if lantern.is_lit():
			any = true
			tw.parallel().tween_callback(lantern.set_lit.bind(false)).set_delay(t)
			t += stagger
	if not any:
		t = 0.2
	tw.parallel().tween_property(self, "_quit_level", 0.0, 0.8).set_delay(t) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_show_quit_sword(t)
	return t + 0.8


func _show_quit_sword(delay: float) -> void:
	var tex: Texture2D = null
	var pos := FEET
	if _knight != null and is_instance_valid(_knight):
		tex = DensityTextures.load_texture(Greatsword.BACK_PATH)
		var blade := _knight.get_node_or_null("Visual/Greatsword/Blade") as Sprite2D
		if blade != null:
			pos = blade.global_position
	elif _planted != null and is_instance_valid(_planted):
		tex = _planted.texture
		pos = _planted.global_position
	if tex == null:
		return
	if _quit_sword == null:
		_quit_sword = Sprite2D.new()
		_quit_sword.name = "QuitSword"
		_quit_sword.centered = false
		_quit_sword.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_quit_sword.material = Fx.additive_mat()
		_glow_layer.add_child(_quit_sword)
	_quit_sword.texture = tex
	_quit_sword.position = get_viewport().get_canvas_transform() * pos
	_quit_sword.modulate = Color(0.9, 0.42, 0.22, 0.0)
	_quit_tween.parallel().tween_property(_quit_sword, "modulate:a", 0.55, 0.6).set_delay(delay + 0.2)


# ---------------------------------------------------------------- queries -------

func light_count() -> int:
	var n := 0
	for node in find_children("*", "PointLight2D", true, false):
		if node is PointLight2D:
			n += 1
	return n


func node_count() -> int:
	return find_children("*", "", true, false).size() + 1


func lantern_count() -> int:
	return _lanterns.size()


func lit_lanterns() -> int:
	var n := 0
	for lantern in _lanterns:
		if lantern.is_lit():
			n += 1
	return n


func lanterns() -> Array[TitleLantern]:
	return _lanterns


func gears() -> Array[TitleGear]:
	return _gears


func sparks() -> TitleSparks:
	return _sparks


func knight() -> Node2D:
	return _knight if _knight != null and is_instance_valid(_knight) else null


func knight_sprite() -> FrameAnimSprite:
	if knight() == null:
		return null
	return _knight.get_node_or_null("Visual/KnightSprite") as FrameAnimSprite


func planted_sword() -> Sprite2D:
	return _planted if _planted != null and is_instance_valid(_planted) else null


func nest() -> Node2D:
	return _nest if _nest != null and is_instance_valid(_nest) else null


func camera() -> Camera2D:
	return _camera


func camera_offset() -> Vector2:
	return _camera.position - CENTER


func parallax_layers() -> Array[Node2D]:
	return _px_nodes


## Where the knight (or the planted sword) is, in world pixels.
func stage_focus() -> Vector2:
	if knight() != null:
		return _knight.position
	if planted_sword() != null:
		return FEET
	return FEET


func grade() -> Dictionary:
	return _grade


# --- living-detail queries (tests / tools) --------------------------------------

## The prop_plan the scene is currently showing.
func plan() -> Dictionary:
	return _plan


func crucible():
	return _crucible


func hammer():
	return _hammer


func sword_chain():
	return _sword_chain


func braziers():
	return _braziers


func souls():
	return _souls


func ghosts():
	return _ghosts


func banners() -> Array:
	return _banners


## Every living detail that is told the forge heat each frame (crucible, hammer, ghosts,
## braziers, banners, sword chain).
func prop_nodes() -> Array:
	return _heat_props.duplicate()


## The light shaft's current cloud shade (1.0 = full strength) and how fast the clouds drift.
func shaft_cloud() -> float:
	return _cloud


func cloud_speed() -> float:
	return _cloud_speed


func shaft_alpha() -> float:
	return _beam.modulate.a if _beam != null else 0.0
