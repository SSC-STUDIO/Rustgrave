extends RefCounted
## Final look pass for the 3D title, on top of the modules' own grade.
##
## The kit / lighting / props modules own their data, but a few values still read
## wrong at 640x360 (a blown-out light shaft, a near-black cold hall, exposure
## drifts). This file is the single place where the integration layer applies its
## last multipliers so the frozen modules and their tests stay untouched.
##
## Iterate here with:
##   tools/run_title_peek.ps1 -Variants cold,act2,give,keep,snuff -Shots idle -Bare \
##       -OutDir screenshots/acceptance/title3d/look
## and compare the PNGs (the scene is 640x360 output texels, 2x supersampled).
##
## Calibration: the retired 2D reference frames (scene region x 600..1060, y
## 120..700) sit at cold 0.093 / act2 0.112 / snuff 0.055 / give 0.168 / keep
## 0.174 mean luminance. The 3D hall before this pass: cold 0.044 / act2 0.066
## with almost every non-emissive pixel black. Two separate problems:
##   1. the additive beam card reads as a translucent ribbon with a hot core
##      (it is a blended quad, not fog: its brightness is emission * mask, and
##      the two crossed cards double up along the intersection seam);
##   2. the hall shell only gets a 0.16-energy ambient term, so the cold grades
##      lose every silhouette. Both are fixed here, per grade.

const KIT_PATH := "res://scripts/title3d/kit/title_kit.gd"

## Beam card: the additive quad through the skylight. Keep it *dim*: the soft
## volumetric cone comes from the fog-lit shaft light, the card only tints the
## air directly under the skylight. band_count 0 = smooth gradient (no hard
## stepped edges), wide radial falloff hides the quad/cross seam.
const BEAM_ENERGY := 0.10
const BEAM_OPACITY := 0.65
const BEAM_RADIAL_SOFTNESS := 3.8
const BEAM_END_SOFTNESS := 1.25
const BEAM_CORE_POWER := 0.75
const BEAM_BAND_COUNT := 0.0
const BEAM_DUST := 1.0
const BEAM_NOISE := 1.8
## Tint the shaft toward cold steel on the cold grades (the module blends the
## grade's shaft colour with warm white for the warm halls, keep that).
const BEAM_COLD_COLOR := Color(0.64, 0.78, 1.0)

## Per-grade-id look. Exposure is a multiplier on the grade's tonemap exposure;
## `ambient`/`ambient_energy` replace the kit's ambient term (the surface shader
## adds it once per directional light, so this is the only way to fill a hall
## that has no practical light); `fog_*` lift the far wall into readable haze;
## `vol_energy` scales the volumetric-fog light energy (the soft glow around the
## shaft); `beam` scales the card energy; `tint` is the post-process tint.
const LOOKS := {
	&"cold": {
		"exposure": 2.05,
		"ambient": Color(0.56, 0.60, 0.70), "ambient_energy": 0.42,
		"fog_density": 2.2, "fog_light": Color(0.34, 0.39, 0.50),
		"fog_energy": 0.50, "fog_aerial": 0.45,
		"vol_energy": 2.6, "beam": 1.0,
		"vol_emission": Color(0.02, 0.026, 0.038), "vol_emission_energy": 0.40,
		"glow": 1.15, "glow_threshold": 1.05,
		"tint": Color(0.94, 0.97, 1.0), "vignette": 0.32, "saturation": 1.10,
	},
	&"snuff": {
		"exposure": 2.4,
		"ambient": Color(0.50, 0.50, 0.60), "ambient_energy": 0.58,
		"fog_density": 2.2, "fog_light": Color(0.26, 0.26, 0.34),
		"fog_energy": 0.46, "fog_aerial": 0.40,
		"vol_energy": 2.0, "beam": 0.6,
		"vol_emission": Color(0.022, 0.012, 0.012), "vol_emission_energy": 0.28,
		"glow": 1.25, "glow_threshold": 1.05,
		"tint": Color(0.97, 0.95, 1.0), "vignette": 0.34, "saturation": 1.08,
	},
	&"act1": {
		"exposure": 1.7,
		"ambient": Color(0.55, 0.59, 0.69), "ambient_energy": 0.34,
		"fog_density": 1.9, "fog_light": Color(0.35, 0.40, 0.50),
		"fog_energy": 0.46, "fog_aerial": 0.42,
		"vol_energy": 2.3, "beam": 1.0,
		"vol_emission": Color(0.024, 0.028, 0.036), "vol_emission_energy": 0.38,
		"glow": 1.10, "glow_threshold": 1.05,
		"tint": Color(0.95, 0.98, 1.0), "vignette": 0.32, "saturation": 1.10,
	},
	&"act2": {
		"exposure": 1.33,
		"ambient": Color(0.56, 0.57, 0.64), "ambient_energy": 0.27,
		"fog_density": 1.5, "fog_light": Color(0.38, 0.40, 0.46),
		"fog_energy": 0.44, "fog_aerial": 0.40,
		"vol_energy": 2.0, "beam": 1.0,
		"vol_emission": Color(0.030, 0.032, 0.040), "vol_emission_energy": 0.40,
		"glow": 1.05, "glow_threshold": 1.10,
		"tint": Color(0.98, 0.99, 1.0), "vignette": 0.32, "saturation": 1.10,
	},
	&"act3": {
		"exposure": 1.15,
		"ambient": Color(0.60, 0.57, 0.55), "ambient_energy": 0.26,
		"fog_density": 1.1, "fog_light": Color(0.44, 0.40, 0.37),
		"fog_energy": 0.38, "fog_aerial": 0.34,
		"vol_energy": 1.6, "beam": 0.95,
		"vol_emission": Color(0.055, 0.038, 0.030), "vol_emission_energy": 0.46,
		"glow": 0.95, "glow_threshold": 1.10,
		"tint": Color(1.0, 0.98, 0.95), "vignette": 0.34, "saturation": 1.10,
	},
	&"act4": {
		"exposure": 1.05,
		"ambient": Color(0.62, 0.55, 0.48), "ambient_energy": 0.24,
		"fog_density": 0.9, "fog_light": Color(0.50, 0.42, 0.36),
		"fog_energy": 0.36, "fog_aerial": 0.30,
		"vol_energy": 1.4, "beam": 0.95,
		"vol_emission": Color(0.075, 0.045, 0.030), "vol_emission_energy": 0.52,
		"glow": 0.92, "glow_threshold": 1.10,
		"tint": Color(1.0, 0.97, 0.93), "vignette": 0.34, "saturation": 1.10,
	},
	&"give": {
		"exposure": 0.90,
		"ambient": Color(0.64, 0.57, 0.49), "ambient_energy": 0.22,
		"fog_density": 0.9, "fog_light": Color(0.52, 0.47, 0.41),
		"fog_energy": 0.36, "fog_aerial": 0.28,
		"vol_energy": 1.4, "beam": 0.95,
		"vol_emission": Color(0.060, 0.050, 0.035), "vol_emission_energy": 0.48,
		"glow": 0.90, "glow_threshold": 1.10,
		"tint": Color(1.0, 0.97, 0.93), "vignette": 0.34, "saturation": 1.08,
	},
	&"keep": {
		"exposure": 0.88,
		"ambient": Color(0.64, 0.54, 0.45), "ambient_energy": 0.22,
		"fog_density": 0.9, "fog_light": Color(0.52, 0.40, 0.33),
		"fog_energy": 0.36, "fog_aerial": 0.28,
		"vol_energy": 1.5, "beam": 0.95,
		"vol_emission": Color(0.080, 0.045, 0.026), "vol_emission_energy": 0.52,
		"glow": 0.90, "glow_threshold": 1.10,
		"tint": Color(1.0, 0.97, 0.92), "vignette": 0.34, "saturation": 1.08,
	},
	&"true_break": {
		"exposure": 1.15,
		"ambient": Color(0.56, 0.66, 0.80), "ambient_energy": 0.34,
		"fog_density": 1.2, "fog_light": Color(0.45, 0.56, 0.66),
		"fog_energy": 0.44, "fog_aerial": 0.38,
		"vol_energy": 2.0, "beam": 1.0,
		"vol_emission": Color(0.024, 0.042, 0.055), "vol_emission_energy": 0.44,
		"glow": 1.05, "glow_threshold": 1.05,
		"tint": Color(0.95, 0.99, 1.0), "vignette": 0.32, "saturation": 1.10,
	},
}

## Unknown grade id: stay close to the module's own values (no surprise lift).
const LOOK_DEFAULT := {
	"exposure": 1.05,
	"ambient": Color(0.56, 0.58, 0.66), "ambient_energy": 0.28,
	"fog_density": 1.2, "fog_light": Color(0.40, 0.42, 0.48),
	"fog_energy": 0.40, "fog_aerial": 0.32,
	"vol_energy": 1.6, "beam": 1.0,
	"vol_emission": Color(0.035, 0.036, 0.042), "vol_emission_energy": 0.42,
	"glow": 1.0, "glow_threshold": 1.05,
	"tint": Color(0.98, 0.98, 1.0), "vignette": 0.32, "saturation": 1.08,
}


static func apply(world: Node, grade: Dictionary) -> void:
	if world == null:
		return
	var grade_id := StringName(String(grade.get("grade_id", grade.get("variant", &"cold"))))
	var look: Dictionary = LOOKS.get(grade_id, LOOK_DEFAULT)
	var lighting: Node = world.get("_lighting")

	apply_beam(lighting, look)

	var env: Environment = null
	if lighting != null and lighting.has_method("environment"):
		env = lighting.call("environment") as Environment
	if env != null:
		apply_environment(env, look)
	if lighting != null and lighting.has_method("set_volumetric_light_energy"):
		lighting.call("set_volumetric_light_energy", float(look.get("vol_energy", 1.0)))

	apply_ambient(lighting, look.get("ambient", Color(0.56, 0.58, 0.66)),
			float(look.get("ambient_energy", 0.28)))
	apply_post(world, look)


## The additive skylight card: dim, smooth (unquantised) gradient, wide soft
## edges. Its colour follows the grade's shaft light so the warm halls keep a warm
## shaft; the cold halls are pushed back toward steel blue.
static func apply_beam(lighting: Node, look: Dictionary) -> void:
	if lighting == null or not lighting.has_method("beam_material"):
		return
	var beam: ShaderMaterial = lighting.call("beam_material")
	if beam == null:
		return
	var color: Color = BEAM_COLD_COLOR
	var is_cold := true
	if lighting.has_method("shaft_light"):
		var shaft: SpotLight3D = lighting.call("shaft_light")
		if shaft != null:
			color = shaft.light_color
			# A warm shaft colour (act3/4, give, keep) already carries the grade
			# tint; only the cold family gets pulled toward the steel blue.
			is_cold = color.b <= color.r + 0.06
	if is_cold:
		color = color.lerp(BEAM_COLD_COLOR, 0.55)
	beam.set_shader_parameter("emission_energy", BEAM_ENERGY * float(look.get("beam", 1.0)))
	beam.set_shader_parameter("opacity", BEAM_OPACITY)
	beam.set_shader_parameter("radial_softness", BEAM_RADIAL_SOFTNESS)
	beam.set_shader_parameter("end_softness", BEAM_END_SOFTNESS)
	beam.set_shader_parameter("core_power", BEAM_CORE_POWER)
	beam.set_shader_parameter("band_count", BEAM_BAND_COUNT)
	beam.set_shader_parameter("dust_density", BEAM_DUST)
	beam.set_shader_parameter("noise_scale", BEAM_NOISE)
	beam.set_shader_parameter("beam_color", color)


## Environment: exposure, glow, depth fog, volumetrics. Multipliers apply to the
## values the lighting rig just wrote, so repeated grade applies stay identical.
static func apply_environment(env: Environment, look: Dictionary) -> void:
	env.tonemap_exposure = clampf(env.tonemap_exposure * float(look.get("exposure", 1.0)),
			0.05, 8.0)
	env.glow_intensity = clampf(env.glow_intensity * float(look.get("glow", 1.0)), 0.0, 2.0)
	if look.has("glow_threshold"):
		env.glow_hdr_threshold = float(look["glow_threshold"])

	# Depth fog: the far wall / hall shell needs to read through the dark. This
	# is the aerial haze of the 2D reference; it must not touch the bridge, so it
	# starts well behind the knight.
	env.fog_density = clampf(env.fog_density * float(look.get("fog_density", 1.0)), 0.0, 0.05)
	env.fog_light_color = look.get("fog_light", env.fog_light_color)
	env.fog_light_energy = float(look.get("fog_energy", env.fog_light_energy))
	env.fog_aerial_perspective = clampf(float(look.get("fog_aerial", env.fog_aerial_perspective)),
			0.0, 1.0)

	if look.has("vol_emission"):
		env.volumetric_fog_emission = look["vol_emission"]
	if look.has("vol_emission_energy"):
		env.volumetric_fog_emission_energy = float(look["vol_emission_energy"])

	env.adjustment_contrast = clampf(float(look.get("contrast", env.adjustment_contrast)), 0.5, 2.0)
	env.adjustment_saturation = clampf(float(look.get("saturation", env.adjustment_saturation)),
			0.0, 3.0)


## The kit's surface shader owns the ambient term (Environment ambient is unused),
## so the hall shell is filled from here: a graded cool/warm ambient that lifts the
## silhouettes without touching the emissive fixtures.
static func apply_ambient(lighting: Node, color: Color, energy: float) -> void:
	var kit_script: GDScript = null
	if ResourceLoader.exists(KIT_PATH):
		kit_script = load(KIT_PATH) as GDScript
	if kit_script == null or not kit_script.has_method("set_ambient"):
		return
	kit_script.call("set_ambient", color, maxf(energy, 0.0))


## Title-only post pass (the title screen's own defaults are overridden here so the
## vignette/tint can follow the grade). The arena never sees these.
static func apply_post(world: Node, look: Dictionary) -> void:
	var stage: Node = null
	if world.has_method("pixel_stage"):
		stage = world.call("pixel_stage")
	if stage == null or not stage.has_method("set_post_params"):
		return
	stage.call("set_post_params", {
		"vignette_strength": float(look.get("vignette", 0.30)),
		"grain_strength": 0.05,
		"dither_strength": 0.16,
		"tint": look.get("tint", Color(0.98, 0.98, 1.0)),
	})

# --------------------------------------------------------------- composition ---
## The hero shots come from the frozen shot table, which frames the hall dead-on.
## A dead-on camera is what makes a 3D set read as a flat backdrop, so the
## integration layer turns every sampled shot into a diorama 3/4 angle: orbit the
## camera around the look target, pull in slightly and rise a little, and aim at a
## touch above the deck. Intro/confirm/quit samples go through the same transform,
## so the whole title keeps one consistent camera language.
const CAMERA_YAW_DEG := -10.0
const CAMERA_DISTANCE_SCALE := 0.95
const CAMERA_RISE := 1.8
const CAMERA_TARGET_RISE := 0.5
const CAMERA_FOV_SCALE := 1.0
## The kit's window glass has its own material; the module's gain still blooms the
## centre window out to near-white, so the look pass pins it to a calmer value.
const WINDOW_EMISSION_GAIN := 0.85


## Rewrite a TitleShots sample into the diorama composition.
static func adjust_sample(sample: Dictionary) -> Dictionary:
	if sample.is_empty():
		return sample
	var pos: Vector3 = sample.get("pos", Vector3.ZERO)
	var target: Vector3 = sample.get("target", Vector3.ZERO)
	var offset := pos - target
	offset = offset.rotated(Vector3.UP, deg_to_rad(CAMERA_YAW_DEG))
	offset *= CAMERA_DISTANCE_SCALE
	offset.y += CAMERA_RISE
	var aimed := target + Vector3(0.0, CAMERA_TARGET_RISE, 0.0)
	var out := sample.duplicate()
	out["pos"] = aimed + offset
	out["target"] = aimed
	out["fov"] = clampf(float(sample.get("fov", 30.0)) * CAMERA_FOV_SCALE, 1.0, 179.0)
	return out


## Keep the leaded window glass a cool backlight instead of a white block.
static func apply_windows() -> void:
	var builder: GDScript = null
	var path := "res://scripts/title3d/kit/hall_builder.gd"
	if ResourceLoader.exists(path):
		builder = load(path) as GDScript
	if builder == null or not builder.has_method("window_material"):
		return
	var window: ShaderMaterial = builder.call("window_material")
	if window != null:
		window.set_shader_parameter("emission_gain", WINDOW_EMISSION_GAIN)
