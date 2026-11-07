extends "res://scripts/title3d/props/title_prop3d.gd"
## Two torn banners hanging over the stage (2D: scripts/ui/title_banner.gd,
## docs/title-live-scene.md §6.1).
##
## Each banner is a cloth mesh from title-kit's shapes (`TitleShapes.cloth`: top-centre
## origin, UV v = 0 at the rod, double sided, folds baked into vertex colours) bent by a
## small inline vertex shader: the hem swings most, the pole edge stays put. The swing
## amplitude follows the forge heat, and `gust()` (the 'controls' menu reaction) adds a
## one-shot snap that decays like the 2D prop.
##
## The cloth is LIT exactly like the hall (same vertex-colour convention and the same
## three-band toon ramp as assets/shaders/title3d/surface.gdshader): the palette's dark
## rust red (`CLOTH=#5C2A26`, top hem `CLOTH_LIGHT=#7C3A30`) is shaded by the light rig,
## not self-lit, so a cold/snuffed hall reads near-black. The furnace breath only warms
## the hem (`warm` uniform, gated by heat) and is fully off at cold/snuff.
##
## Coordinates: TitleLayout BANNER_LEFT/RIGHT and BANNER_SIZE; the cloth's local
## origin is the top-centre of the pole, hanging downward.
##
## Node contract: two banner rigs (pole + cloth) built once; advance() only writes the
## shader uniforms. No nodes are created or freed after setup.

const BANNER_LEFT := Vector3(-8.6, 10.8, -5.5)
const BANNER_RIGHT := Vector3(8.6, 10.8, -5.5)
const BANNER_SIZE := Vector2(2.4, 6.2)
const COLS := 6
const ROWS := 11
## 2D: 0.8..3.0 px swing + 3 px gust -> in metres on the 0.0375 m/texel contract.
const SWING_MIN := 0.05
const SWING_MAX := 0.18
const GUST_SWING := 0.30
const SWAY_PERIOD := 5.4
## Furnace-breath gate: heat at/below this is a cold (or snuffed) hall -> no hem glow;
## it ramps to full by `WARM_MIN_HEAT + WARM_RAMP` (act4 / keep).
const WARM_MIN_HEAT := 0.35
const WARM_RAMP := 0.90
## Additive strength of the hem ember glow at full heat.
const HEM_EMISSION := 0.35
## Strength of the per-grade ambient term (the hall's stone ambient is ~1.2 in the kit).
const AMBIENT_ENERGY := 1.10

## The cloth is a lit surface, not an unshaded card: vertex colour = dark rust palette,
## `light()` = the same three-band toon ramp the hall material uses, ambient added once
## from the grade's ambient colour. Only the bottom hem ever emits, and only while
## `warm > 0` (a burning furnace), so cold/snuff banners stay dark red.
const CLOTH_SHADER := """shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, ambient_light_disabled;

uniform float wave_time = 0.0;
uniform float amplitude = 0.10;
uniform float gust_amount = 0.0;
uniform float phase = 0.0;
// 0..1 furnace breath on the hem; the prop clamps this to 0 for cold/snuff grades.
uniform float warm = 0.0;
uniform float hem_emission = 0.35;
uniform vec3 ambient_light = vec3(0.096, 0.206, 0.206);
uniform float band_high : hint_range(0.0, 1.0) = 0.55;
uniform float band_low : hint_range(0.0, 1.0) = 0.12;
uniform float mid_level : hint_range(0.0, 1.0) = 0.6;
uniform float shadow_level : hint_range(0.0, 1.0) = 0.22;

varying vec3 v_tint;
varying float v_k;

void vertex() {
	float k = clamp(UV.y, 0.0, 1.0);
	float a = amplitude * (0.10 + k * 0.90) + gust_amount * k * k;
	VERTEX.x += sin(wave_time * 1.9 + phase + k * 3.1) * a;
	VERTEX.z += cos(wave_time * 1.45 + phase * 1.7 + k * 2.2) * a * 0.55;
	v_tint = COLOR.rgb;
	v_k = k;
}

void fragment() {
	// Same raw-vertex-colour convention as title3d/surface.gdshader. Slight vertical
	// grading keeps the sheet from reading as one flat tone; the folds are baked in the
	// mesh colours by TitleShapes.cloth.
	vec3 base = v_tint * (1.0 - 0.10 * v_k);
	ALBEDO = base;
	ROUGHNESS = 0.96;
	METALLIC = 0.0;
	// the furnace breath only reaches the bottom hem while the hall actually burns
	EMISSION = vec3(1.0, 0.42, 0.16) * hem_emission * warm * warm * v_k * v_k;
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float reach = clamp(ATTENUATION, 0.0, 1.0);
	float level;
	if (LIGHT_IS_DIRECTIONAL) {
		level = ndl > band_high ? 1.0 : (ndl > band_low ? mid_level : shadow_level);
		// the title ambient is added exactly once, by the sun (same as the hall material)
		DIFFUSE_LIGHT += ambient_light;
	} else {
		level = ndl > band_high ? 1.0 : (ndl > band_low ? mid_level : 0.0);
	}
	DIFFUSE_LIGHT += level * LIGHT_COLOR * reach / PI;
}
"""

var _rigs: Array[Node3D] = []
var _materials: Array[ShaderMaterial] = []
var _phase: Array[float] = []
var _gust := 0.0


func _build() -> void:
	_banner("BannerLeft", LV3("BANNER_LEFT", BANNER_LEFT), 0.0)
	_banner("BannerRight", LV3("BANNER_RIGHT", BANNER_RIGHT), 2.3)
	_apply_grade()
	_sync()


func _banner(node_name: String, at: Vector3, phase: float) -> void:
	var size := LV2("BANNER_SIZE", BANNER_SIZE)
	var rig := Node3D.new()
	rig.name = node_name
	rig.position = at
	add_child(rig)
	_rigs.append(rig)
	_phase.append(phase)
	# pole: a sagging bar with two hanger straps and end caps
	var half := size.x * 0.5 + 0.35
	var parts: Array = []
	parts.append(GEO.box(Vector3(half * 2.0, 0.14, 0.14), Vector3(0.0, 0.10, 0.0), IRON_DARK))
	parts.append(GEO.box(Vector3(half * 2.0, 0.05, 0.08), Vector3(0.0, 0.19, 0.0), IRON_LIGHT))
	for sx in [-1.0, 1.0]:
		parts.append(GEO.box(Vector3(0.16, 0.16, 0.16), Vector3(half * sx, 0.10, 0.0), IRON))
		parts.append(GEO.box(Vector3(0.08, 0.55, 0.08), Vector3(half * 0.72 * sx, 0.50, 0.0), IRON))
	var pole := add_mesh(parts, GEO.mat(0), "Pole", Vector3.ZERO, rig)
	GEO.outline(pole, 1.0)
	# cloth: title-kit shapes' hanging sheet (top-centre origin, UV v = 0 at the rod,
	# double sided). The 2D palette's dark rust red, lit like the hall; the vertex
	# shader only bends it, the bottom band is warmed by the furnace (`warm` uniform).
	# The local fallback keeps the torn edge when title-kit is absent.
	var cloth_mesh: ArrayMesh = GEO.shape_cloth(size.x, size.y, COLS, ROWS,
			CLOTH, CLOTH_LIGHT)
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = CLOTH_SHADER
	material.shader = shader
	material.set_shader_parameter("phase", phase)
	material.set_shader_parameter("amplitude", SWING_MIN)
	material.set_shader_parameter("gust_amount", 0.0)
	material.set_shader_parameter("wave_time", 0.0)
	material.set_shader_parameter("warm", 0.0)
	material.set_shader_parameter("hem_emission", HEM_EMISSION)
	_materials.append(material)
	var cloth := MeshInstance3D.new()
	cloth.name = "Cloth"
	cloth.mesh = cloth_mesh
	cloth.material_override = material
	cloth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rig.add_child(cloth)


func _apply_grade() -> void:
	if is_built():
		_sync()


## 'controls' menu reaction: one gust, decaying at 0.5/s like the 2D prop.
func gust() -> void:
	_gust = 1.0
	if is_built():
		_sync()


func _tick(dt: float) -> void:
	_gust = move_toward(_gust, 0.0, dt * 0.5)


func _sync() -> void:
	if _materials.is_empty():
		return
	var hot := clampf(eff_heat(), 0.0, 1.35)
	var amplitude := lerpf(SWING_MIN, SWING_MAX, hot / 1.3)
	var gust_amount := GUST_SWING * _gust
	# Furnace breath on the hem: 0 for cold (0.16) / snuff (0.0), ramps with the acts,
	# full at act4 / keep. This is what the 2D prop called the warm bottom hem.
	var warm := clampf((eff_heat() - WARM_MIN_HEAT) / WARM_RAMP, 0.0, 1.0)
	# Per-grade ambient (the 2D GRADES ambient colour, linearised like TitleKit.set_ambient)
	# so cold reads blue-grey and the warm acts read rust without the cloth self-lighting.
	var ambient_srgb := g_color("ambient", Color(0.50, 0.46, 0.54))
	var ambient_lin := ambient_srgb.srgb_to_linear()
	var ambient_vec := Vector3(ambient_lin.r, ambient_lin.g, ambient_lin.b) * AMBIENT_ENERGY
	for i in _materials.size():
		var material := _materials[i]
		material.set_shader_parameter("wave_time", t)
		material.set_shader_parameter("amplitude", amplitude)
		material.set_shader_parameter("gust_amount", gust_amount)
		material.set_shader_parameter("warm", warm)
		material.set_shader_parameter("ambient_light", ambient_vec)


# ------------------------------------------------------------ test helpers ----

func banner_count() -> int:
	return _rigs.size()


## Current hem swing amplitude in metres (heat + gust, what the shader gets).
func amplitude() -> float:
	return lerpf(SWING_MIN, SWING_MAX, clampf(eff_heat(), 0.0, 1.35) / 1.3) + GUST_SWING * _gust


## Furnace breath on the hem (0 cold/snuff .. 1 act4/keep).
func warm_level() -> float:
	return clampf((eff_heat() - WARM_MIN_HEAT) / WARM_RAMP, 0.0, 1.0)


func gust_level() -> float:
	return _gust


func _snapshot_into(out: Dictionary) -> void:
	out["amplitude"] = snappedf(amplitude(), 0.000001)
	out["gust"] = snappedf(_gust, 0.000001)
	out["warm"] = snappedf(warm_level(), 0.000001)
