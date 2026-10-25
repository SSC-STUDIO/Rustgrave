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
## Budgets (tests/title_world_test.gd): <= 8 lights, <= 250 nodes, no per-frame
## allocation in the hot paths. Everything is NEAREST and whole-pixel placed.

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
var _pit_glow: Sprite2D
var _mouth: Sprite2D
var _stage: Node2D
var _knight: Node2D
var _planted: Sprite2D
var _nest: Node2D
var _nest_flame: Sprite2D
var _quit_sword: Sprite2D
var _gears: Array[TitleGear] = []
var _lanterns: Array[TitleLantern] = []
var _chains: Array[TitleChain] = []
var _pit_light: PointLight2D
var _shaft_light: PointLight2D
var _forge_light: PointLight2D
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
var _nest_frame_t := 0.0


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
	return load(DIR + file) as Texture2D


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

	_build_chains()

	_layer("Roof", "roof.png", Vector2(-32.0, -10.0), 0.5, 30, self)

	_layer("MassLeft", "mass_left.png", MASS_LEFT_POS, 1.0, 40, self)
	var mass_right := _layer("MassRight", "mass_right.png", MASS_RIGHT_POS, 1.0, 40, self)
	_mouth = Sprite2D.new()
	_mouth.name = "ForgeMouth"
	_mouth.texture = ArtTexture.load_texture(DIR + "forge_fire.png")
	_mouth.hframes = 8
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
	_refresh_grade()


func _clear_actors() -> void:
	for n in [_knight, _planted, _nest]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_knight = null
	_planted = null
	_nest = null
	_nest_flame = null


func _place_knight(skin: StringName, x: float, seated: bool = false) -> void:
	_knight = Node2D.new()
	_knight.name = "Knight"
	_knight.position = Vector2(x, DECK_Y)
	_stage.add_child(_knight)
	var visual := Node2D.new()
	visual.name = "Visual"
	_knight.add_child(visual)
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
	base.texture = load("res://assets/env/ember_nest.png") as Texture2D
	base.centered = false
	base.position = Vector2(-16.0, -20.0)
	base.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_nest.add_child(base)
	var coals := Sprite2D.new()
	coals.name = "Coals"
	coals.texture = load("res://assets/env/ember_nest_coals.png") as Texture2D
	coals.centered = false
	coals.position = Vector2(-16.0, -20.0)
	coals.material = Fx.additive_mat()
	coals.z_index = 1
	coals.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_nest.add_child(coals)
	_nest_flame = Sprite2D.new()
	_nest_flame.name = "Flame"
	_nest_flame.texture = ArtTexture.load_texture("res://assets/fx/shrine_flame.png")
	_nest_flame.hframes = 8
	_nest_flame.centered = false
	_nest_flame.offset = Vector2(-8.0, -24.0)
	_nest_flame.position = Vector2(6.0, -14.0)
	_nest_flame.z_index = 2
	_nest_flame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_nest.add_child(_nest_flame)


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
	_beam.modulate = Color(sc.r / maxf(ambient.r, 0.2), sc.g / maxf(ambient.g, 0.2),
			sc.b / maxf(ambient.b, 0.2), 0.5 * shaft)
	var fc: Color = _grade["furnace_color"]
	var furnace := float(_grade["furnace"]) * level
	_pit_glow.modulate = Color(fc.r / maxf(ambient.r, 0.2), fc.g / maxf(ambient.g, 0.2),
			fc.b / maxf(ambient.b, 0.2), clampf(0.30 * furnace, 0.0, 0.85))
	var forge := float(_grade["forge"]) * level
	# unlit materials: undo the ambient (1/ambient) and scale by how hot the forge burns
	var heat := Color(0.07, 0.03, 0.03).lerp(Color(1.0, 0.96, 0.9), clampf(forge, 0.0, 1.0))
	_mouth.modulate = Color(heat.r / maxf(ambient.r, 0.2), heat.g / maxf(ambient.g, 0.2),
			heat.b / maxf(ambient.b, 0.2))
	var river_heat := Color(0.05, 0.02, 0.02).lerp(Color(1.0, 0.92, 0.84), clampf(furnace, 0.0, 1.0))
	_river.modulate = Color(river_heat.r / maxf(ambient.r, 0.2), river_heat.g / maxf(ambient.g, 0.2),
			river_heat.b / maxf(ambient.b, 0.2))
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
	_vignette.modulate.a = 1.0
	_sparks.modulate.a = clampf(level * 1.2, 0.0, 1.0)
	_motes.modulate.a = clampf(level * 1.2, 0.0, 1.0)


func _update_lights(_delta: float) -> void:
	if _grade.is_empty():
		return
	var level := _intro_level * _quit_level
	var step := floorf(_t * 10.0)
	var breathe := 1.0 + 0.07 * sin(_t * TAU / 5.4) + 0.03 * sin(step * 2.3)
	var snuff := variant() == VARIANT_SNUFF
	_pit_light.energy = float(_grade["furnace"]) * level * breathe * (1.0 + _flare * 0.5)
	_shaft_light.energy = 0.32 * float(_grade["shaft"]) * level
	if snuff:
		_forge_light.energy = 0.55 * (0.5 + 0.5 * sin(_t * TAU / 3.8)) * level
	else:
		_forge_light.energy = float(_grade["forge"]) * level * (1.0 + 0.10 * sin(step * 1.9) + _flare * 0.4)


# --------------------------------------------------------------- per frame -----

func _process(delta: float) -> void:
	_t += delta
	var k := 1.0 - exp(-POINTER_EASE * delta)
	_shift = _shift.lerp(Vector2(_pointer.x * PARALLAX.x, _pointer.y * PARALLAX.y), k)
	_push_kick = move_toward(_push_kick, 0.0, delta * 6.0)
	_flare = move_toward(_flare, 0.0, delta * 1.8)
	_breath = 0.0 if _frozen_breath else sin(_t * TAU / BREATH_PERIOD) * 1.0
	var cam := CENTER + Vector2(0.0, roundf(_breath))
	if _camera.position != cam:
		_camera.position = cam
	_apply_parallax(false)
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
	if _mouth != null:
		_mouth.frame = int(_t * 12.0) % 8
	if _knight != null and is_instance_valid(_knight):
		var sword := _knight.get_node_or_null("Visual/Greatsword") as Greatsword
		if sword != null:
			var s := sin(_t * 1.7) * Greatsword.IDLE_SWAY
			sword.rotation = lerpf(sword.rotation, s, 1.0 - exp(-8.0 * delta))
			sword.position.y = Greatsword.BACK_HILT.y + roundf(sin(_t * 0.9) * 0.6)
	if _nest_flame != null and is_instance_valid(_nest_flame):
		_nest_frame_t += delta
		if _nest_frame_t >= 1.0 / 12.0:
			_nest_frame_t = 0.0
			_nest_flame.frame = (_nest_flame.frame + 1) % 8


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
		tex = load(Greatsword.BACK_PATH) as Texture2D
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
