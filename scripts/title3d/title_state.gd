class_name TitleState
extends RefCounted
## The pure, render-free state of the 3D title screen (the forge hall).
##
## Nothing in this file creates a node, touches a renderer or writes a file: the
## 3D title world, the Forward+ lighting rig and the 3D props all read the
## dictionaries built here, and the whole save -> look mapping can be tested
## headless. It is the scene-free half of the retired 2D `TitleWorld`
## (`scripts/ui/title_world.gd`), carried over with the same state semantics:
##
##   cold     no save (or an unreadable save): a cold forge, no lantern lit
##   journey  a save without an ending: colour grade by act, lit lanterns = cleared / 14
##   give     the knight is gone, only the planted greatsword; warm and steady
##   keep     the knight sits at the forge end; the hottest, most alive hall
##   snuff    lanterns dark, one dying red glow where he stood
##   true_break  hidden ending: cool dawn light through the broken roof
##
## Public static API (all pure, all return fresh dictionaries/arrays):
##   peek_save()            read SaveData memory first, then the save file (main, then .bak)
##   build_state(peek)      peek -> the plain state dictionary
##   state_from_save()      peek_save() + build_state() (honours the forced_state override)
##   prop_plan(state)       which living props show up, and how (docs/title-live-scene.md §6.2)
##   grade(state)           the per-variant look: exposure / sun / furnace / fog / glow / props
##   light_plan(state)      the 12-light fixture table (<3D title lighting> consumes it);
##                          pure data, no 3D coordinates — positions belong to the lighting rig
##   grade_id(state)        key into GRADES (cold / act1..act4 / give / keep / snuff / true_break)
##
## Conventions kept from the 2D title: VARIANT_*, GRADES, LANTERN_COUNT, CHAPTERS,
## LIGHT_POOL_FIXTURES, lit_lantern_count(), act_of_index(), rest_facing_for(),
## MODE_* (same ints as the old sword-chain script) and POSE_*.
##
## 3D 标题预算 14/6，替代 2D 的 8 灯预算：灯 ≤ MAX_LIGHTS (14)，投影 ≤ MAX_SHADOWS (6)。
## 这两个是唯一的预算上限；LIGHT_FIXTURES (12) 只是当前实际分配的 fixture 数量。

const CHAPTERS := 14
const LANTERN_COUNT := 14
const ACT_COUNT := 4
## First chapter index of each act: chapters 1-3 / 4-7 / 8-11 / 12-14 (TitleGauge.ACT_STARTS).
const ACT_STARTS: Array[int] = [0, 3, 7, 11]
## The five lanterns that own a physical light pool in the retired 2D scene. The 3D
## rig drives six lantern lights, so this list stays inside LANTERN_LIGHT_FIXTURES.
const LIGHT_POOL_FIXTURES: Array[int] = [1, 4, 7, 10, 13]
## The six of the fourteen hanging lanterns that carry a real light in 3D.
const LANTERN_LIGHT_FIXTURES: Array[int] = [0, 1, 4, 7, 10, 13]
## The lantern lights that cast shadows (the old 2D shadow pair; four shadows in total).
const LANTERN_SHADOW_FIXTURES: Array[int] = [4, 10]
## 3D light budget: 1 sun + 1 shaft spot + 1 furnace omni + 1 pit omni + 6 lanterns + 2 braziers.
const LIGHT_FIXTURES := 12
const MAX_LIGHTS := 14
const MAX_SHADOWS := 6
## Soul-light pool size (docs §6.2 counts souls as a x/16 share).
const SOUL_POOL_SIZE := 16
## Chapters cleared before the first / the second bridge-head brazier is lit.
const BRAZIER_FIRST_AT := 1
const BRAZIER_SECOND_AT := 7

const VARIANT_COLD := &"cold"
const VARIANT_JOURNEY := &"journey"
const VARIANT_GIVE := &"give"
const VARIANT_KEEP := &"keep"
const VARIANT_SNUFF := &"snuff"
const VARIANT_TRUE_BREAK := &"true_break"
const VARIANTS: Array[StringName] = [VARIANT_COLD, VARIANT_JOURNEY, VARIANT_GIVE,
		VARIANT_KEEP, VARIANT_SNUFF, VARIANT_TRUE_BREAK]

## Sword-chain modes: same ints as the old scripts/ui/title_sword_chain.gd.
const MODE_RUN := 0
const MODE_EMPTY := 1
const MODE_STILL := 2
## What stands where the knight used to be: he rests, gave the sword, sits, or is gone.
const POSE_STAND := &"stand"
const POSE_PLANTED := &"planted"
const POSE_SEATED := &"seated"
const POSE_ABSENT := &"absent"

## Forced state for capture tools / tests (set before the title is created); mirrors the
## 2D title's TitleWorld.forced_state.
static var forced_state: Dictionary = {}

## The 2D look per variant / act, carried over verbatim: ambient multiplies the lit
## canvas, the rest tune furnace, shaft, particles and machines. `grade()` keeps these
## keys for compatibility and layers the 3D-only keys of GRADES_3D on top.
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
	&"true_break": {
		"ambient": Color(0.58, 0.62, 0.68), "furnace": 0.22, "furnace_color": Color(0.45, 0.82, 0.96),
		"forge": 0.25, "shaft": 1.15, "shaft_color": Color(0.62, 0.86, 0.96), "embers": 0.35, "ash": 0.20,
		"steam": 0.25, "gears": 0.0, "lantern": Color(0.75, 0.92, 1.0), "flicker": 0.12,
	},
}

## The 3D-only half of the look, keyed like GRADES. Numbers carry the story:
## cold -> act1..act4 warms strictly, give is warm and steady, keep is the hottest
## hall, snuff is dark with one residual red glow, true_break is a cool dawn.
const GRADES_3D := {
	&"cold": {
		"exposure": 0.55, "white": 1.00, "sun_color": Color(0.42, 0.55, 0.68), "sun_energy": 0.35,
		"furnace_energy": 0.10, "pit_energy": 0.08, "fog_density": 0.034,
		"fog_albedo": Color(0.30, 0.36, 0.45), "fog_emission": Color(0.02, 0.03, 0.05),
		"glow_intensity": 0.22, "grade_tint": Color(0.58, 0.62, 0.72), "brazier_flicker": 1.00,
	},
	&"act1": {
		"exposure": 0.68, "white": 1.04, "sun_color": Color(0.48, 0.60, 0.72), "sun_energy": 0.55,
		"furnace_energy": 0.40, "pit_energy": 0.30, "fog_density": 0.030,
		"fog_albedo": Color(0.34, 0.36, 0.40), "fog_emission": Color(0.03, 0.03, 0.04),
		"glow_intensity": 0.38, "grade_tint": Color(0.62, 0.64, 0.70), "brazier_flicker": 1.05,
	},
	&"act2": {
		"exposure": 0.80, "white": 1.09, "sun_color": Color(0.55, 0.58, 0.65), "sun_energy": 0.65,
		"furnace_energy": 0.62, "pit_energy": 0.50, "fog_density": 0.028,
		"fog_albedo": Color(0.38, 0.37, 0.38), "fog_emission": Color(0.05, 0.035, 0.03),
		"glow_intensity": 0.52, "grade_tint": Color(0.68, 0.66, 0.66), "brazier_flicker": 1.10,
	},
	&"act3": {
		"exposure": 0.95, "white": 1.14, "sun_color": Color(0.64, 0.60, 0.56), "sun_energy": 0.78,
		"furnace_energy": 0.92, "pit_energy": 0.80, "fog_density": 0.026,
		"fog_albedo": Color(0.44, 0.38, 0.34), "fog_emission": Color(0.08, 0.05, 0.03),
		"glow_intensity": 0.68, "grade_tint": Color(0.78, 0.70, 0.62), "brazier_flicker": 1.15,
	},
	&"act4": {
		"exposure": 1.10, "white": 1.20, "sun_color": Color(0.74, 0.58, 0.48), "sun_energy": 0.92,
		"furnace_energy": 1.30, "pit_energy": 1.15, "fog_density": 0.024,
		"fog_albedo": Color(0.50, 0.38, 0.32), "fog_emission": Color(0.12, 0.06, 0.03),
		"glow_intensity": 0.86, "grade_tint": Color(0.92, 0.74, 0.60), "brazier_flicker": 1.20,
	},
	&"give": {
		"exposure": 1.05, "white": 1.18, "sun_color": Color(0.76, 0.68, 0.56), "sun_energy": 0.85,
		"furnace_energy": 1.05, "pit_energy": 0.85, "fog_density": 0.022,
		"fog_albedo": Color(0.54, 0.48, 0.42), "fog_emission": Color(0.06, 0.05, 0.035),
		"glow_intensity": 0.78, "grade_tint": Color(0.94, 0.84, 0.70), "brazier_flicker": 1.00,
	},
	&"keep": {
		"exposure": 1.22, "white": 1.22, "sun_color": Color(0.72, 0.52, 0.40), "sun_energy": 0.70,
		"furnace_energy": 1.55, "pit_energy": 1.35, "fog_density": 0.021,
		"fog_albedo": Color(0.52, 0.36, 0.30), "fog_emission": Color(0.14, 0.07, 0.03),
		"glow_intensity": 1.00, "grade_tint": Color(0.98, 0.76, 0.58), "brazier_flicker": 1.25,
	},
	&"snuff": {
		"exposure": 0.42, "white": 0.92, "sun_color": Color(0.36, 0.44, 0.54), "sun_energy": 0.16,
		"furnace_energy": 0.03, "pit_energy": 0.0, "fog_density": 0.032,
		"fog_albedo": Color(0.24, 0.28, 0.36), "fog_emission": Color(0.01, 0.005, 0.005),
		"glow_intensity": 0.12, "grade_tint": Color(0.42, 0.38, 0.44), "brazier_flicker": 1.00,
	},
	&"true_break": {
		"exposure": 0.90, "white": 1.08, "sun_color": Color(0.62, 0.86, 0.96), "sun_energy": 0.90,
		"furnace_energy": 0.22, "pit_energy": 0.20, "fog_density": 0.030,
		"fog_albedo": Color(0.42, 0.55, 0.66), "fog_emission": Color(0.03, 0.06, 0.08),
		"glow_intensity": 0.70, "grade_tint": Color(0.70, 0.84, 0.95), "brazier_flicker": 1.00,
	},
}

## Light-plan tuning (energy units per fixture; the lighting rig scales these further).
const SHAFT_ENERGY_SCALE := 0.85
const FURNACE_ENERGY_SCALE := 2.4
const PIT_ENERGY_SCALE := 1.6
const LANTERN_ENERGY := 1.5
const BRAZIER_ENERGY_SCALE := 2.0
const SHAFT_RANGE := 24.0
const FURNACE_RANGE := 16.0
const PIT_RANGE := 12.0
const LANTERN_RANGE := 7.5
const BRAZIER_RANGE := 5.0
const SHAFT_FLICKER := 0.12
const WARM_WHITE := Color(1.0, 0.96, 0.88)
const BRAZIER_COLOR := Color(1.0, 0.45, 0.17)


# ------------------------------------------------------------------ state ------

## The pure half of the save -> scene mapping: everything the 3D title needs, from a
## plain `peek` dictionary {has_save, scene, ending, flags, skin, origin, rank, points}.
static func build_state(peek: Dictionary) -> Dictionary:
	var order := GameContext.LEVEL_ORDER
	var scene := String(peek.get("scene", ""))
	var chapter_id := ""
	for id in GameContext.LEVELS:
		if String(GameContext.LEVELS[id]) == scene:
			chapter_id = String(id)
			break
	if chapter_id == "":
		for leg_id in GameContext.LEGACY_LEVELS:
			if String(GameContext.LEGACY_LEVELS[leg_id]) == scene:
				chapter_id = String(GameContext.LEGACY_TO_STAGE.get(leg_id, ""))
				break
	var chapter_index := order.find(chapter_id)
	var flags := _as_flags(peek.get("flags", PackedStringArray()))
	var ending := String(peek.get("ending", ""))
	var has_save := bool(peek.get("has_save", false))
	var variant := VARIANT_COLD
	if ending != "":
		variant = StringName(ending) if (ending == "give" or ending == "keep" \
				or ending == "snuff" or ending == "true_break") else VARIANT_GIVE
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
		VARIANT_GIVE, VARIANT_KEEP, VARIANT_TRUE_BREAK:
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
	var act := 1
	for i in ACT_STARTS.size():
		if index >= ACT_STARTS[i]:
			act = i + 1
	return act


## Key into GRADES / GRADES_3D for a state.
static func grade_id(s: Dictionary) -> StringName:
	var variant := StringName(String(s.get("variant", VARIANT_COLD)))
	if variant == VARIANT_JOURNEY:
		return StringName("act%d" % clampi(int(s.get("act", 1)), 1, ACT_COUNT))
	return variant


## +1 = facing the furnace (right), -1 = facing away (left). The knight rests facing away
## and turns to the furnace now and then; at the forge end ('keep') he always looks into it.
static func rest_facing_for(variant_id: StringName) -> int:
	return 1 if variant_id == VARIANT_KEEP else -1


## Which living details show up, and how, for a state: the pure half of the props
## (docs/title-live-scene.md §6.2; the 3D prop nodes read this).
##   chain_mode    MODE_RUN / MODE_EMPTY / MODE_STILL
##   ghosts        lantern-bearing silhouettes on the far catwalk (0..3)
##   souls_rate    0..1 share of the soul pool; souls_escape = they leave through the roof gap
##   braziers      [first, second] brightness (0 = cold, 1 = lit, > 1 = brightest)
##   knight_turns  whether the knight looks at the furnace now and then
static func prop_plan(s: Dictionary) -> Dictionary:
	var variant := StringName(String(s.get("variant", VARIANT_COLD)))
	if not VARIANTS.has(variant):
		variant = VARIANT_GIVE
	var cleared := clampi(int(s.get("cleared", 0)), 0, CHAPTERS)
	var act := clampi(int(s.get("act", 1)), 1, ACT_COUNT)
	var plan := {
		"chain_mode": MODE_RUN,
		"ghosts": 1,
		"souls_rate": 0.15,
		"souls_escape": false,
		"braziers": [0.0, 0.0],
		"knight_turns": true,
	}
	match variant:
		VARIANT_JOURNEY:
			# brighter with the act; the first brazier at the first cleared chapter, the second at the seventh
			var level := lerpf(0.6, 1.0, float(act - 1) / 3.0)
			plan["ghosts"] = clampi(act, 1, 3)
			plan["souls_rate"] = minf(0.70, 0.20 + 0.035 * float(cleared))
			plan["braziers"] = [level if cleared >= BRAZIER_FIRST_AT else 0.0,
					level if cleared >= BRAZIER_SECOND_AT else 0.0]
		VARIANT_GIVE:
			# the sword is gone: the chain hangs empty and the souls leave through the roof
			plan["chain_mode"] = MODE_EMPTY
			plan["ghosts"] = 0
			plan["souls_rate"] = 1.0
			plan["souls_escape"] = true
			plan["braziers"] = [0.9, 0.9]
			plan["knight_turns"] = false
		VARIANT_KEEP:
			# the fire stays lit and so do the oaths: ghosts still queue, braziers burn brightest
			plan["ghosts"] = 3
			plan["souls_rate"] = 0.30
			plan["braziers"] = [1.3, 1.3]
			plan["knight_turns"] = false
		VARIANT_TRUE_BREAK:
			plan["chain_mode"] = MODE_EMPTY
			plan["ghosts"] = 0
			plan["souls_rate"] = 1.0
			plan["souls_escape"] = true
			plan["braziers"] = [0.6, 0.6]
			plan["knight_turns"] = false
		VARIANT_SNUFF:
			plan["chain_mode"] = MODE_STILL
			plan["ghosts"] = 0
			plan["souls_rate"] = 0.0
			plan["braziers"] = [0.0, 0.0]
			plan["knight_turns"] = false
	return plan


## Which pose the knight actor takes for a variant.
static func knight_pose_for(variant_id: StringName) -> StringName:
	match variant_id:
		VARIANT_GIVE:
			return POSE_PLANTED
		VARIANT_KEEP:
			return POSE_SEATED
		VARIANT_SNUFF:
			return POSE_ABSENT
		_:
			return POSE_STAND


## What the title reads from the player's save without loading it (a fresh launch has not
## called SaveData.load_game yet): in-memory state wins when a game is loaded, otherwise the
## file on disk is peeked read-only (main save first, then the .bak recovery copy). A save
## file that exists but cannot be parsed (and has no usable backup) is reported as no save,
## which lands the title on the cold forge. Nothing here writes to disk.
static func peek_save() -> Dictionary:
	var in_memory := not SaveData.data.is_empty()
	var has_save := SaveData.has_save()
	# Profile fields (skin / rank / points) are only trusted from memory while a game is
	# loaded in it: a fresh launch (nothing loaded yet) shows what the file says.
	var out := {
		"has_save": has_save, "scene": "", "ending": String(SaveData.ending),
		"flags": SaveData.flags.duplicate(), "skin": SaveData.skin_id if in_memory else "",
		"origin": "", "rank": SaveData.ember_rank if in_memory else 1,
		"points": SaveData.attribute_points if in_memory else 0,
	}
	if in_memory:
		var meta: Dictionary = SaveData.data.get("meta", {})
		out["scene"] = String(meta.get("scene", ""))
		var pl: Variant = SaveData.data.get("player", {})
		if pl is Dictionary:
			out["origin"] = String((pl as Dictionary).get("origin", ""))
	var cfg: ConfigFile = null
	if has_save:
		cfg = _read_cfg(SaveData.save_path)
		if cfg == null:
			cfg = _read_cfg(SaveData.save_path + ".bak")
		if cfg == null and not in_memory:
			# Damaged save with no usable backup: show the cold forge instead of a phantom journey.
			out["has_save"] = false
			out["scene"] = ""
			out["ending"] = ""
			return out
	if cfg != null:
		if String(out["scene"]) == "":
			out["scene"] = String(cfg.get_value("meta", "scene", ""))
		if String(out["origin"]) == "":
			out["origin"] = String(cfg.get_value("player", "origin", ""))
		if String(out["ending"]) == "":
			out["ending"] = String(cfg.get_value("meta", "ending", ""))
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
	if path == "" or not FileAccess.file_exists(path):
		return null
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK or not _cfg_is_usable(cfg):
		return null
	return cfg


## A real save always carries at least one of these sections (see SaveData.save_game /
## init_new_game). A damaged file that happens to parse as an empty ConfigFile must not
## masquerade as a journey.
static func _cfg_is_usable(cfg: ConfigFile) -> bool:
	return cfg.has_section("meta") or cfg.has_section("player") or cfg.has_section("equipment")


static func state_from_save() -> Dictionary:
	if not forced_state.is_empty():
		return forced_state.duplicate(true)
	return build_state(peek_save())


static func _as_flags(raw: Variant) -> PackedStringArray:
	if raw is PackedStringArray:
		var packed: PackedStringArray = raw
		return packed
	var out := PackedStringArray()
	if raw is Array:
		for f in raw:
			out.append(String(f))
	return out


# ---------------------------------------------------------------- grade --------

## The per-variant look for the 3D hall: the legacy 2D GRADES keys plus the 3D-only
## exposure / sun / furnace / fog / glow values and the prop/animation rates the 3D
## scene consumes. Always returns a fresh deep copy; unknown variants fall back to give.
static func grade(s: Dictionary) -> Dictionary:
	var variant := StringName(String(s.get("variant", VARIANT_COLD)))
	if not VARIANTS.has(variant):
		variant = VARIANT_GIVE
	var gid := _grade_id_for(variant, s)
	var out: Dictionary = GRADES[gid].duplicate(true)
	out["variant"] = variant
	out["grade_id"] = gid
	var three: Dictionary = GRADES_3D[gid]
	for key in three:
		out[key] = three[key]
	# 3D aliases of the legacy tuning keys, so consumers read one spelling.
	out["gear_speed"] = float(out["gears"])
	out["ember_rate"] = float(out["embers"])
	out["steam_rate"] = float(out["steam"])
	out["lantern_flicker"] = float(out["flicker"])
	var plan: Dictionary = prop_plan(s)
	var souls_rate := float(plan["souls_rate"])
	out["souls_rate"] = souls_rate
	out["souls_goal"] = clampi(int(round(souls_rate * float(SOUL_POOL_SIZE))), 0, SOUL_POOL_SIZE)
	out["souls_escape"] = bool(plan["souls_escape"])
	out["ghost_count"] = int(plan["ghosts"])
	var braziers: Array = plan["braziers"]
	out["brazier_left"] = float(braziers[0])
	out["brazier_right"] = float(braziers[1])
	out["chain_mode"] = int(plan["chain_mode"])
	out["knight_turns"] = bool(plan["knight_turns"])
	out["knight_pose"] = knight_pose_for(variant)
	out["planted_sword"] = variant == VARIANT_GIVE
	out["lantern_lit"] = _lantern_lit_for(variant, s)
	return out


static func _grade_id_for(variant: StringName, s: Dictionary) -> StringName:
	if variant == VARIANT_JOURNEY:
		return StringName("act%d" % clampi(int(s.get("act", 1)), 1, ACT_COUNT))
	return variant


static func _lantern_lit_for(variant: StringName, s: Dictionary) -> int:
	if s.has("lit"):
		return clampi(int(s["lit"]), 0, LANTERN_COUNT)
	match variant:
		VARIANT_JOURNEY:
			return lit_lantern_count(int(s.get("cleared", 0)))
		VARIANT_GIVE, VARIANT_KEEP, VARIANT_TRUE_BREAK:
			return LANTERN_COUNT
		_:
			return 0


# ------------------------------------------------------------ light plan ------

## The 3D light fixtures for a state, as pure data (<3D title lighting> consumes it).
## Budget: LIGHT_FIXTURES fixtures (<= MAX_LIGHTS) and at most MAX_SHADOWS shadow casters:
##   sun      1 directional, the roof-gap key light        shadow
##   shaft    1 spot, the light shaft through the torn roof (no shadow: volumetric fog)
##   furnace  1 omni, the forge mouth                       shadow
##   pit      1 omni, the molten river under the bridge
##   lanterns 6 omni, one per LANTERN_LIGHT_FIXTURES        shadows on LANTERN_SHADOW_FIXTURES
##   braziers 2 omni, the bridge-head fires
## Each entry: {id, kind, shadow, energy, color, flicker, range, fixture}; `fixture` is the
## lantern index (-1 for non-lanterns). No 3D coordinates: placement belongs to title_lighting.
static func light_plan(s: Dictionary) -> Array[Dictionary]:
	var g := grade(s)
	var lit := int(g["lantern_lit"])
	var sun: Color = g["sun_color"]
	var furnace_color: Color = g["furnace_color"]
	var lantern_color: Color = g["lantern"]
	var lantern_flicker := float(g["lantern_flicker"])
	var out: Array[Dictionary] = []
	out.append(_light(&"sun", &"directional", true, float(g["sun_energy"]),
			sun, 0.0, 0.0, -1))
	out.append(_light(&"shaft", &"spot", false, float(g["sun_energy"]) * SHAFT_ENERGY_SCALE,
			sun.lerp(WARM_WHITE, 0.30), SHAFT_FLICKER, SHAFT_RANGE, -1))
	out.append(_light(&"furnace", &"omni", true, float(g["furnace_energy"]) * FURNACE_ENERGY_SCALE,
			furnace_color, 1.0, FURNACE_RANGE, -1))
	out.append(_light(&"pit", &"omni", false, float(g["pit_energy"]) * PIT_ENERGY_SCALE,
			furnace_color, 0.6, PIT_RANGE, -1))
	for fixture in LANTERN_LIGHT_FIXTURES:
		var index := int(fixture)
		var is_lit := index < lit
		out.append(_light(StringName("lantern_%d" % index), &"omni",
				LANTERN_SHADOW_FIXTURES.has(index),
				LANTERN_ENERGY if is_lit else 0.0,
				lantern_color, lantern_flicker, LANTERN_RANGE, index))
	out.append(_light(&"brazier_left", &"omni", false,
			float(g["brazier_left"]) * BRAZIER_ENERGY_SCALE, BRAZIER_COLOR,
			float(g["brazier_flicker"]), BRAZIER_RANGE, -1))
	out.append(_light(&"brazier_right", &"omni", false,
			float(g["brazier_right"]) * BRAZIER_ENERGY_SCALE, BRAZIER_COLOR,
			float(g["brazier_flicker"]), BRAZIER_RANGE, -1))
	return out


static func _light(id: StringName, kind: StringName, shadow: bool, energy: float,
		color: Color, flicker: float, reach: float, fixture: int) -> Dictionary:
	return {
		"id": id,
		"kind": kind,
		"shadow": shadow,
		"energy": energy,
		"color": color,
		"flicker": flicker,
		"range": reach,
		"fixture": fixture,
	}
