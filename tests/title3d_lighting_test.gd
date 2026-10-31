extends TestCase
## Headless tests for the Forward+ title lighting rig (`scripts/title3d/title_lighting.gd`)
## and the two title shaders (`assets/shaders/title3d/beam.gdshader`, `molten.gdshader`).
##
## The rig is loaded through `preload` instead of its `class_name`, because a fresh
## headless checkout may not have the global class cache entry yet (the same reason
## `TitleWorld3D` loads it dynamically).
##
## What is covered:
##   - the 12-fixture light budget (<= 14 lights, <= 6 shadow casters) and the fixture mix;
##   - the Forward+ environment contract (ACES, Glow, SSAO, SSR, volumetric fog, depth fog,
##     SDFGI/SSIL off) and that every grade value reaches the environment;
##   - the three quality tiers (SSR only high, shadow casters decrease, SSAO/Glow kept);
##   - `apply()` idempotence: identical parameters and no node churn on a second apply;
##   - missing / mistyped grade keys fall back to the safe defaults (never NaN);
##   - all save-variant looks survive `apply()` + `advance()` without NaN, and the real
##     `TitleState.grade()` / `light_plan()` contract (guarded: only when that file exists);
##   - the N/14 lantern mapping, surge / flicker / quit_out / slow_clouds reactions;
##   - `advance()` determinism: same total delta => same state, bad deltas are ignored;
##   - shader existence, uniforms and the materials the rig exposes.

const TitleLightingScript := preload("res://scripts/title3d/title_lighting.gd")
const Layout := preload("res://scripts/title3d/kit/layout.gd")
const STATE_PATH := "res://scripts/title3d/title_state.gd"

const BEAM_SHADER_PATH := "res://assets/shaders/title3d/beam.gdshader"
const MOLTEN_SHADER_PATH := "res://assets/shaders/title3d/molten.gdshader"

const MAX_LIGHTS := 14
const MAX_SHADOW_CASTERS := 6
const FIXTURES := 12
const LANTERN_FIXTURES: Array[int] = [0, 1, 4, 7, 10, 13]

var _root: Node3D
var _lighting: Node3D


func setup() -> void:
	_root = Node3D.new()
	_root.name = "LightingTestRoot"
	add_child(_root)
	_lighting = _make_rig(_root)


func teardown() -> void:
	if is_instance_valid(_root):
		_root.queue_free()
	_root = null
	_lighting = null


# --------------------------------------------------------------------------- helpers --

func _make_rig(host: Node3D) -> Node3D:
	var node := TitleLightingScript.new() as Node3D
	node.name = "Lighting"
	host.add_child(node)
	node.call("build", host)
	return node


func _env() -> Environment:
	return _lighting.call("environment") as Environment


func _lights() -> Array:
	return _lighting.call("lights")


func _shadow_casters() -> Array:
	return _lighting.call("shadow_casters")


func _lantern_lights() -> Array:
	return _lighting.call("lantern_lights")


func _apply(grade: Dictionary, quality: StringName = &"high") -> void:
	_lighting.call("apply", grade, quality)


func _advance(dt: float) -> void:
	_lighting.call("advance", dt)


func _count_nodes(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count_nodes(child)
	return total


func _all_light_energies() -> Array[float]:
	var out: Array[float] = []
	for light in _lights():
		out.append(float((light as Light3D).light_energy))
	return out


func _snapshot() -> Dictionary:
	var env := _env()
	var snapshot := {
		"exposure": env.tonemap_exposure,
		"white": env.tonemap_white,
		"background": env.background_color,
		"ambient_energy": env.ambient_light_energy,
		"ambient_color": env.ambient_light_color,
		"glow": env.glow_intensity,
		"glow_threshold": env.glow_hdr_threshold,
		"glow_bloom": env.glow_bloom,
		"ssao": env.ssao_enabled,
		"ssao_intensity": env.ssao_intensity,
		"ssr": env.ssr_enabled,
		"ssr_steps": env.ssr_max_steps,
		"vol_fog_density": env.volumetric_fog_density,
		"vol_fog_albedo": env.volumetric_fog_albedo,
		"vol_fog_temporal": env.volumetric_fog_temporal_reprojection_amount,
		"quality": String(_lighting.call("quality")),
		"grade_id": String(_lighting.call("grade_id")),
		"lantern_lit": int(_lighting.call("lantern_lit")),
		"light_count": _lights().size(),
		"shadow_count": _shadow_casters().size(),
	}
	var energies: Array[float] = []
	for light in _lights():
		energies.append(float((light as Light3D).light_energy))
	snapshot["energies"] = energies
	return snapshot


## A representative grade per save variant, built from the `TitleState.grade()` contract
## ranges (cold -> act4 strictly warms, keep is hottest, snuff is dark with residual red).
func _variant_grades() -> Dictionary:
	return {
		&"cold": {
			"variant": &"cold", "grade_id": &"cold", "exposure": 0.55, "white": 1.00,
			"sun_color": Color(0.42, 0.55, 0.68), "sun_energy": 0.35,
			"furnace_color": Color(1.0, 0.30, 0.12), "furnace_energy": 0.10,
			"pit_energy": 0.08, "fog_density": 0.034,
			"fog_albedo": Color(0.30, 0.36, 0.45), "fog_emission": Color(0.02, 0.03, 0.05),
			"glow_intensity": 0.22, "grade_tint": Color(0.58, 0.62, 0.72),
			"lantern_lit": 0, "lantern_flicker": 1.0, "brazier_flicker": 1.0,
		},
		&"act1": {
			"variant": &"journey", "grade_id": &"act1", "exposure": 0.68, "white": 1.04,
			"sun_color": Color(0.48, 0.60, 0.72), "sun_energy": 0.55,
			"furnace_color": Color(1.0, 0.36, 0.14), "furnace_energy": 0.40,
			"pit_energy": 0.30, "fog_density": 0.030,
			"fog_albedo": Color(0.34, 0.36, 0.40), "fog_emission": Color(0.03, 0.03, 0.04),
			"glow_intensity": 0.38, "grade_tint": Color(0.62, 0.64, 0.70),
			"lantern_lit": 3, "brazier_left": 0.6, "brazier_right": 0.0,
		},
		&"act4": {
			"variant": &"journey", "grade_id": &"act4", "exposure": 1.10, "white": 1.20,
			"sun_color": Color(0.74, 0.58, 0.48), "sun_energy": 0.92,
			"furnace_color": Color(1.0, 0.34, 0.12), "furnace_energy": 1.30,
			"pit_energy": 1.15, "fog_density": 0.024,
			"fog_albedo": Color(0.50, 0.38, 0.32), "fog_emission": Color(0.12, 0.06, 0.03),
			"glow_intensity": 0.86, "grade_tint": Color(0.92, 0.74, 0.60),
			"lantern_lit": 14, "brazier_left": 1.0, "brazier_right": 1.0,
		},
		&"give": {
			"variant": &"give", "grade_id": &"give", "exposure": 1.05, "white": 1.18,
			"sun_color": Color(0.76, 0.68, 0.56), "sun_energy": 0.85,
			"furnace_color": Color(1.0, 0.48, 0.18), "furnace_energy": 1.05,
			"pit_energy": 0.85, "fog_density": 0.022,
			"fog_albedo": Color(0.54, 0.48, 0.42), "fog_emission": Color(0.06, 0.05, 0.035),
			"glow_intensity": 0.78, "grade_tint": Color(0.94, 0.84, 0.70),
			"lantern_lit": 14, "lantern_flicker": 0.15, "brazier_flicker": 1.0,
			"brazier_left": 0.9, "brazier_right": 0.9,
		},
		&"keep": {
			"variant": &"keep", "grade_id": &"keep", "exposure": 1.22, "white": 1.22,
			"sun_color": Color(0.72, 0.52, 0.40), "sun_energy": 0.70,
			"furnace_color": Color(1.0, 0.40, 0.14), "furnace_energy": 1.55,
			"pit_energy": 1.35, "fog_density": 0.021,
			"fog_albedo": Color(0.52, 0.36, 0.30), "fog_emission": Color(0.14, 0.07, 0.03),
			"glow_intensity": 1.0, "grade_tint": Color(0.98, 0.76, 0.58),
			"lantern_lit": 14, "lantern_flicker": 1.0, "brazier_flicker": 1.25,
			"brazier_left": 1.3, "brazier_right": 1.3,
		},
		&"snuff": {
			"variant": &"snuff", "grade_id": &"snuff", "exposure": 0.42, "white": 0.92,
			"sun_color": Color(0.36, 0.44, 0.54), "sun_energy": 0.16,
			"furnace_color": Color(0.9, 0.2, 0.1), "furnace_energy": 0.03,
			"pit_energy": 0.0, "fog_density": 0.032,
			"fog_albedo": Color(0.24, 0.28, 0.36), "fog_emission": Color(0.01, 0.005, 0.005),
			"glow_intensity": 0.12, "grade_tint": Color(0.42, 0.38, 0.44),
			"lantern_lit": 0, "brazier_left": 0.0, "brazier_right": 0.0,
		},
		&"true_break": {
			"variant": &"true_break", "grade_id": &"true_break", "exposure": 0.90,
			"white": 1.08, "sun_color": Color(0.62, 0.86, 0.96), "sun_energy": 0.90,
			"furnace_color": Color(0.45, 0.82, 0.96), "furnace_energy": 0.22,
			"pit_energy": 0.20, "fog_density": 0.030,
			"fog_albedo": Color(0.42, 0.55, 0.66), "fog_emission": Color(0.03, 0.06, 0.08),
			"glow_intensity": 0.70, "grade_tint": Color(0.70, 0.84, 0.95),
			"lantern_lit": 14, "lantern_flicker": 0.12, "brazier_flicker": 1.0,
			"brazier_left": 0.6, "brazier_right": 0.6,
		},
	}


func _is_finite_color(color: Color) -> bool:
	return is_finite(color.r) and is_finite(color.g) and is_finite(color.b)


# ------------------------------------------------------------------------------ tests --

func test_build_creates_environment_and_light_budget() -> void:
	var env := _env()
	ok(env != null, "build() must create an Environment")
	ok(_lighting.call("built"), "build() must report built")
	var world_env := _lighting.call("world_environment") as WorldEnvironment
	ok(world_env != null, "a WorldEnvironment node must exist")
	ok(world_env != null and world_env.environment == env, "WorldEnvironment must own the rig Environment")

	var lights := _lights()
	eq(lights.size(), FIXTURES, "the rig is the 12-fixture plan")
	ok(lights.size() <= MAX_LIGHTS, "lights must stay inside the 14-light budget")

	var directional := 0
	var spot := 0
	var omni := 0
	var names := {}
	for node in lights:
		var light := node as Light3D
		ok(light != null, "every fixture must be a Light3D")
		ok(is_instance_valid(light), "every fixture must be alive")
		if light is DirectionalLight3D:
			directional += 1
		elif light is SpotLight3D:
			spot += 1
		elif light is OmniLight3D:
			omni += 1
		ok(not names.has(light.name), "light names must be unique: %s" % light.name)
		names[light.name] = true
	eq(directional, 1, "one directional skylight")
	eq(spot, 1, "one shaft spotlight")
	eq(omni, FIXTURES - 2, "the rest are omni lights")

	var casters := _shadow_casters()
	ok(casters.size() > 0, "the high tier keeps shadows on")
	ok(casters.size() <= MAX_SHADOW_CASTERS, "shadow casters must stay inside the 6 budget")
	for node in casters:
		ok((node as Light3D).shadow_enabled, "every reported caster must actually cast")
	for node in lights:
		var light := node as Light3D
		if light.shadow_enabled and not casters.has(light):
			ok(false, "%s casts a shadow but is not in shadow_casters()" % light.name)
	eq(casters.size(), 4, "high tier: sun + furnace + the two shadow lanterns")

	var budget := _lighting.call("light_budget") as Dictionary
	eq(int(budget.get("max_lights", 0)), MAX_LIGHTS)
	eq(int(budget.get("max_shadow_casters", 0)), MAX_SHADOW_CASTERS)
	eq(int(budget.get("planned_fixtures", 0)), FIXTURES)

	var lanterns := _lantern_lights()
	eq(lanterns.size(), LANTERN_FIXTURES.size(), "six lantern fixtures")
	for i in lanterns.size():
		var light := lanterns[i] as OmniLight3D
		var position := light.position
		ok(position.y > 0.0, "lantern lights hang above the deck")
		ok(absf(position.z - Layout.LANTERN_FRONT_Z) < 0.001 \
				or absf(position.z - Layout.LANTERN_BACK_Z) < 0.001,
				"lantern light %d must sit on a lantern row" % i)


func test_environment_forward_plus_contract() -> void:
	var grade := (_variant_grades() as Dictionary)[&"act4"] as Dictionary
	_apply(grade, &"high")
	var env := _env()

	eq(env.tonemap_mode, Environment.TONE_MAPPER_ACES, "ACES tonemap")
	almost(env.tonemap_exposure, float(grade["exposure"]), 0.0001, "exposure is grade driven")
	almost(env.tonemap_white, float(grade["white"]), 0.0001, "white is grade driven")
	eq(env.background_mode, Environment.BG_COLOR, "BG_COLOR background")
	ok(env.background_color.r < 0.2 and env.background_color.g < 0.2 \
			and env.background_color.b < 0.2, "the background stays deep dark")
	ok(env.ambient_light_energy > 0.0 and env.ambient_light_energy <= 0.3,
			"ambient light stays low energy")
	eq(env.ambient_light_source, Environment.AMBIENT_SOURCE_COLOR, "colored ambient, not sky")
	almost(float(_lighting.call("ambient_energy")), env.ambient_light_energy, 1e-6,
			"the kit-sync ambient energy matches the Environment")
	ok((_lighting.call("ambient_color") as Color) == env.ambient_light_color,
			"the kit-sync ambient colour matches the Environment")

	ok(env.glow_enabled, "Glow is on")
	almost(env.glow_intensity, float(grade["glow_intensity"]), 0.0001, "glow intensity from grade")
	almost(env.glow_hdr_threshold, 0.9, 0.0001, "glow threshold 0.9")
	almost(env.glow_bloom, 0.15, 0.0001, "glow bloom 0.15")
	eq(env.glow_blend_mode, Environment.GLOW_BLEND_MODE_ADDITIVE, "additive glow")
	for level in 5:
		ok(float(env.get("glow_levels/%d" % (level + 1))) > 0.0,
				"glow level %d is enabled" % (level + 1))

	ok(env.ssao_enabled, "SSAO is on")
	almost(env.ssao_radius, 0.7, 0.0001, "ssao radius 0.7")
	almost(env.ssao_intensity, 1.4, 0.0001, "ssao intensity 1.4")
	almost(env.ssao_power, 1.2, 0.0001, "ssao power 1.2")

	ok(env.ssr_enabled, "SSR is on at the high tier")
	eq(env.ssr_max_steps, 32, "ssr max steps 32")
	ok(env.ssr_depth_tolerance > 0.0, "ssr depth tolerance must be sane")

	ok(not env.sdfgi_enabled, "SDFGI stays off")
	ok(not env.ssil_enabled, "SSIL stays off")

	ok(env.volumetric_fog_enabled, "volumetric fog is on")
	almost(env.volumetric_fog_density, float(grade["fog_density"]), 0.0001,
			"fog density from grade at the high tier")
	almost(env.volumetric_fog_anisotropy, 0.3, 0.0001, "fog anisotropy 0.3")
	almost(env.volumetric_fog_length, 48.0, 0.0001, "fog length 48")
	ok(env.volumetric_fog_temporal_reprojection_enabled, "temporal reprojection is on")
	ok(env.volumetric_fog_temporal_reprojection_amount > 0.0,
			"temporal reprojection amount must be > 0")
	ok(env.volumetric_fog_sky_affect <= 0.001, "the BG_COLOR background must not be fogged")

	ok(env.fog_enabled, "near depth fog is on (barely)")
	eq(env.fog_mode, Environment.FOG_MODE_DEPTH, "depth fog mode")
	ok(env.fog_density > 0.0 and env.fog_density < 0.02, "the near fog stays subtle")
	ok(env.fog_depth_end > env.fog_depth_begin, "depth fog must have a valid range")

	ok(env.adjustment_enabled, "adjustment is enabled")
	almost(env.adjustment_contrast, 1.04, 0.001, "micro contrast")
	almost(env.adjustment_saturation, 1.06, 0.001, "micro saturation")


func test_quality_tiers_switch_effects() -> void:
	var grade := (_variant_grades() as Dictionary)[&"keep"] as Dictionary
	var env := _env()

	_apply(grade, &"high")
	var high_shadows := _shadow_casters().size()
	ok(env.ssr_enabled, "high tier keeps SSR")
	ok(env.ssao_enabled, "high tier keeps SSAO")
	ok(env.glow_enabled, "high tier keeps Glow")
	ok(env.volumetric_fog_enabled, "high tier keeps volumetric fog")
	var high_density := env.volumetric_fog_density
	var high_temporal := env.volumetric_fog_temporal_reprojection_amount
	eq(high_shadows, 4, "high tier: 4 shadow casters")

	_apply(grade, &"balanced")
	ok(not env.ssr_enabled, "balanced tier disables SSR")
	ok(env.ssao_enabled, "balanced tier keeps SSAO (half size)")
	ok(env.glow_enabled, "balanced tier keeps Glow")
	ok(env.volumetric_fog_enabled, "balanced tier keeps volumetric fog")
	ok(env.volumetric_fog_density < high_density, "balanced tier lowers fog density")
	ok(env.volumetric_fog_temporal_reprojection_amount <= high_temporal,
			"balanced tier lowers temporal quality")
	var balanced_shadows := _shadow_casters().size()
	ok(balanced_shadows < high_shadows, "balanced tier drops shadow casters")
	ok(balanced_shadows <= MAX_SHADOW_CASTERS, "balanced tier shadow budget")

	_apply(grade, &"low")
	ok(not env.ssr_enabled, "low tier disables SSR")
	ok(env.ssao_enabled, "low tier keeps SSAO")
	ok(env.glow_enabled, "low tier keeps Glow")
	ok(env.volumetric_fog_enabled, "low tier keeps volumetric fog")
	var low_shadows := _shadow_casters().size()
	ok(low_shadows <= balanced_shadows, "low tier <= balanced tier shadow casters")
	eq(low_shadows, 1, "low tier keeps the sun shadow only")
	ok(env.volumetric_fog_density < high_density, "low tier lowers fog density further")

	# An unknown tier must degrade to the safe default, never crash or leave effects off.
	_apply(grade, &"nonsense")
	eq(String(_lighting.call("quality")), "high", "unknown quality falls back to high")
	ok(env.ssr_enabled, "unknown quality still reaches the high-tier look")


func test_apply_is_idempotent_and_keeps_node_count() -> void:
	var grade := (_variant_grades() as Dictionary)[&"act4"] as Dictionary
	var root_nodes_before := _count_nodes(_root)
	var lighting_nodes_before := _lighting.get_child_count()
	var env := _env()

	_apply(grade, &"high")
	var first := _snapshot()
	_apply(grade, &"high")
	var second := _snapshot()
	eq(first, second, "applying the same grade twice must be parameter-identical")
	eq(_count_nodes(_root), root_nodes_before, "apply() must not create nodes")
	eq(_lighting.get_child_count(), lighting_nodes_before,
			"apply() must not move nodes under the rig either")
	ok(_lighting.call("environment") == env, "the Environment resource is reused")

	# Quality-only changes are also churn-free.
	_apply(grade, &"balanced")
	_apply(grade, &"balanced")
	var third := _snapshot()
	_apply(grade, &"balanced")
	eq(_snapshot(), third, "quality re-apply must be identical")
	eq(_count_nodes(_root), root_nodes_before, "quality changes create no nodes")

	# An empty grade is a valid (safe default) apply and repeated applies stay equal.
	_apply({}, &"high")
	var empty_first := _snapshot()
	_apply({}, &"high")
	eq(_snapshot(), empty_first, "empty grade apply is idempotent")
	eq(_count_nodes(_root), root_nodes_before, "empty grade apply creates no nodes")

	# Restoring the renderer-wide defaults (title released) must be safe and idempotent.
	_apply(grade, &"low")
	_lighting.call("restore_renderer_defaults")
	_lighting.call("restore_renderer_defaults")
	eq(_count_nodes(_root), root_nodes_before, "restore_renderer_defaults creates no nodes")
	almost(env.tonemap_exposure, float(grade["exposure"]), 1e-6,
			"restoring the renderer defaults never rewrites the grade look")


func test_apply_before_build_and_double_build() -> void:
	var host := Node3D.new()
	host.name = "PreBuildHost"
	add_child(host)
	var rig := TitleLightingScript.new() as Node3D
	rig.name = "PreBuildRig"
	host.add_child(rig)

	# apply() before build() only records the grade: no Environment exists yet.
	rig.call("apply", {"exposure": 1.4, "lantern_lit": 7}, &"low")
	ok(rig.call("environment") == null, "environment() is null before build()")
	ok(not bool(rig.call("built")), "built() is false before build()")

	rig.call("build", host)
	var env := rig.call("environment") as Environment
	ok(env != null, "build() creates the Environment")
	almost(env.tonemap_exposure, 1.4, 1e-6, "build() applies the pre-build grade")
	eq(int(rig.call("lantern_lit")), 7, "the pre-build lantern count survives build()")
	eq(String(rig.call("quality")), "low", "the pre-build quality survives build()")
	ok(not env.ssr_enabled, "the pre-build low tier is honoured")

	var node_count := _count_nodes(host)
	rig.call("build", host)
	rig.call("build", host)
	eq(_count_nodes(host), node_count, "a second build() is a no-op")
	host.queue_free()


func test_missing_and_mistyped_grade_keys_use_safe_defaults() -> void:
	_apply({}, &"high")
	var env := _env()
	var defaults := TitleLightingScript.default_grade() as Dictionary
	almost(env.tonemap_exposure, float(defaults["exposure"]), 0.0001,
			"missing exposure falls back to the safe default")
	almost(env.tonemap_white, float(defaults["white"]), 0.0001, "missing white defaults")
	almost(env.volumetric_fog_density, float(defaults["fog_density"]), 0.0001,
			"missing fog density defaults")
	almost(env.glow_intensity, float(defaults["glow_intensity"]), 0.0001,
			"missing glow intensity defaults")
	ok(env.ssao_enabled and env.glow_enabled and env.volumetric_fog_enabled,
			"the effect stack is complete for an empty grade")
	for light in _lights():
		var value := float((light as Light3D).light_energy)
		ok(is_finite(value) and value >= 0.0, "default light energies must be finite and >= 0")
	eq(int(_lighting.call("lantern_lit")), 0, "no lantern is lit without a grade value")

	# A single present key only moves that key.
	_apply({"exposure": 0.5}, &"high")
	almost(env.tonemap_exposure, 0.5, 0.0001, "a present key is applied")
	almost(env.tonemap_white, float(defaults["white"]), 0.0001, "the rest keeps its default")

	# Wrong types / NaN are ignored instead of poisoning the rig.
	_apply({
		"exposure": "not a number",
		"white": NAN,
		"sun_energy": NAN,
		"furnace_energy": INF,
		"fog_density": null,
		"lantern_lit": "x",
		"glow_intensity": [],
	}, &"high")
	almost(env.tonemap_exposure, float(defaults["exposure"]), 0.0001,
			"mistyped exposure falls back")
	almost(env.tonemap_white, float(defaults["white"]), 0.0001, "NaN white falls back")
	ok(_is_finite_color(env.background_color), "background stays finite")
	ok(is_finite(env.volumetric_fog_density), "fog density stays finite")
	eq(int(_lighting.call("lantern_lit")), 0, "mistyped lantern count falls back to 0")
	for light in _lights():
		var value := float((light as Light3D).light_energy)
		ok(is_finite(value) and value >= 0.0, "no NaN/inf light energies from bad input")

	# Vector3 colours are tolerated as Color input (the toolkit writes vectors).
	_apply({"sun_color": Vector3(1.0, 0.0, 0.0)}, &"high")
	var sun := _lighting.call("sun_light") as DirectionalLight3D
	almost(sun.light_color.r, 1.0, 0.0001, "Vector3 sun_color is accepted")
	almost(sun.light_color.g, 0.0, 0.0001, "Vector3 sun_color is accepted")


func test_all_variants_apply_and_advance_without_nan() -> void:
	var grades := _variant_grades() as Dictionary
	var node_count := _count_nodes(_root)
	for variant_id in grades:
		var grade := grades[variant_id] as Dictionary
		_apply(grade, &"high")
		var env := _env()
		ok(is_finite(env.tonemap_exposure), "%s exposure finite" % variant_id)
		ok(is_finite(env.volumetric_fog_density), "%s fog density finite" % variant_id)
		ok(_is_finite_color(env.volumetric_fog_albedo), "%s fog albedo finite" % variant_id)
		eq(_lights().size(), FIXTURES, "%s: fixture count never changes" % variant_id)
		ok(_shadow_casters().size() <= MAX_SHADOW_CASTERS,
				"%s: shadow budget respected" % variant_id)
		eq(int(_lighting.call("lantern_lit")), int(grade["lantern_lit"]),
				"%s: lantern count from the grade" % variant_id)
		_advance(0.016)
		for i in 120:
			_advance(1.0 / 60.0)
		ok(_is_finite_float(_lighting.call("time")), "%s: clock stays finite" % variant_id)
		for energy in _all_light_energies():
			ok(is_finite(energy) and energy >= 0.0,
					"%s: advance() must not produce NaN/negative energies" % variant_id)
		eq(_count_nodes(_root), node_count, "%s: no node churn" % variant_id)

	# The story beats that the lighting must keep readable.
	_apply((grades[&"snuff"] as Dictionary), &"high")
	ok(float((_lighting.call("furnace_light") as OmniLight3D).light_energy) < 0.25,
			"snuff: the forge is nearly out")
	ok(float((_lighting.call("pit_light") as OmniLight3D).light_energy) <= 0.001,
			"snuff: the molten river is dark")
	_apply((grades[&"keep"] as Dictionary), &"high")
	var keep_furnace := float((_lighting.call("furnace_light") as OmniLight3D).light_energy)
	_apply((grades[&"act1"] as Dictionary), &"high")
	var act1_furnace := float((_lighting.call("furnace_light") as OmniLight3D).light_energy)
	ok(keep_furnace > act1_furnace, "keep is the hottest hall")


func _is_finite_float(value: Variant) -> bool:
	return value is float and is_finite(value)


func test_lantern_lit_mapping() -> void:
	var grade := (_variant_grades() as Dictionary)[&"keep"] as Dictionary
	_apply(grade, &"high")
	eq(int(_lighting.call("lantern_lit")), 14, "keep lights all 14 lanterns")
	for light in _lantern_lights():
		ok(float((light as OmniLight3D).light_energy) > 0.0, "all six lantern lights are on")

	_lighting.call("set_lantern_lit", 0)
	eq(int(_lighting.call("lantern_lit")), 0, "set_lantern_lit(0)")
	for light in _lantern_lights():
		almost(float((light as OmniLight3D).light_energy), 0.0, 0.0001,
				"a dark lantern fixture emits nothing")

	# fixture < lit rule: fixtures [0, 1, 4] are lit at 5/14.
	_lighting.call("set_lantern_lit", 5)
	var lit_count := 0
	for i in _lantern_lights().size():
		var fixture := int(LANTERN_FIXTURES[i])
		var energy := float((_lantern_lights()[i] as OmniLight3D).light_energy)
		if fixture < 5:
			lit_count += 1
			ok(energy > 0.0, "fixture %d must be lit at 5/14" % fixture)
		else:
			almost(energy, 0.0, 0.0001, "fixture %d must be dark at 5/14" % fixture)
	eq(lit_count, 3, "5/14 lights three of the six fixtures")

	_lighting.call("set_lantern_lit", -3)
	eq(int(_lighting.call("lantern_lit")), 0, "negative counts clamp to 0")
	_lighting.call("set_lantern_lit", 99)
	eq(int(_lighting.call("lantern_lit")), 14, "counts above 14 clamp to 14")

	# apply() is authoritative over a manual override.
	_lighting.call("set_lantern_lit", 0)
	_apply(grade, &"high")
	eq(int(_lighting.call("lantern_lit")), 14, "apply() restores the grade lantern count")


func test_advance_determinism_and_bad_deltas() -> void:
	var grade := (_variant_grades() as Dictionary)[&"act4"] as Dictionary
	_apply(grade, &"high")

	# Bad deltas are ignored entirely (no NaN, no clock movement).
	var time_before := float(_lighting.call("time"))
	_advance(-1.0)
	_advance(0.0)
	_advance(NAN)
	_advance(INF)
	almost(float(_lighting.call("time")), time_before, 1e-9, "bad deltas must not move the clock")

	# Same total delta in one step vs many steps must agree.
	for i in 200:
		_advance(1.0 / 60.0)
	var stepped := _all_light_energies()
	var stepped_time := float(_lighting.call("time"))

	var host := Node3D.new()
	add_child(host)
	var other := _make_rig(host)
	other.call("apply", grade, &"high")
	other.call("advance", 200.0 / 60.0)
	var single := other.call("lights") as Array
	ok(is_finite(float(other.call("time"))), "single-step clock finite")
	almost(float(other.call("time")), stepped_time, 1e-3,
			"same total delta gives the same clock")
	for i in single.size():
		var a := float((single[i] as Light3D).light_energy)
		var b := stepped[i]
		almost(a, b, 1e-3,
				"light %d: splitting the delta must not change the flicker" % i)
	host.queue_free()

	# A second identical run reproduces the same state exactly.
	var host2 := Node3D.new()
	add_child(host2)
	var twin := _make_rig(host2)
	twin.call("apply", grade, &"high")
	for i in 200:
		twin.call("advance", 1.0 / 60.0)
	var twin_lights := twin.call("lights") as Array
	for i in twin_lights.size():
		almost(float((twin_lights[i] as Light3D).light_energy), stepped[i], 1e-6,
				"light %d: identical input must give identical output" % i)
	host2.queue_free()


func test_flicker_functions_are_pure() -> void:
	var a := float(TitleLightingScript.flicker01(1.25, 0.4))
	var b := float(TitleLightingScript.flicker01(1.25, 0.4))
	almost(a, b, 1e-9, "flicker01 is a pure function of (time, seed)")
	ok(a >= 0.0 and a <= 1.0, "flicker01 stays inside 0..1")
	var different := float(TitleLightingScript.flicker01(1.25, 0.9))
	ok(absf(a - different) > 1e-6, "different seeds give different noise")
	almost(float(TitleLightingScript.flicker01(2.0, 0.4)),
			float(TitleLightingScript.flicker01(2.0, 0.4)), 1e-9,
			"flicker01 is repeatable across calls")
	almost(float(TitleLightingScript.flicker01(NAN, 0.4)), 0.5, 1e-6,
			"flicker01 tolerates a NaN clock")
	var swell_a := float(TitleLightingScript.swell01(3.5, 1.7))
	var swell_b := float(TitleLightingScript.swell01(3.5, 1.7))
	almost(swell_a, swell_b, 1e-9, "swell01 is pure")
	ok(swell_a >= 0.0 and swell_a <= 1.0, "swell01 stays inside 0..1")

	# surge()/flicker_now() act immediately and decay deterministically.
	var grade := (_variant_grades() as Dictionary)[&"keep"] as Dictionary
	_apply(grade, &"high")
	var base := float((_lighting.call("furnace_light") as OmniLight3D).light_energy)
	_lighting.call("surge")
	var surged := float((_lighting.call("furnace_light") as OmniLight3D).light_energy)
	ok(surged > base, "surge() must brighten the forge immediately")
	for i in 90:
		_advance(1.0 / 60.0)
	var settled := float((_lighting.call("furnace_light") as OmniLight3D).light_energy)
	ok(absf(settled - base) <= maxf(base * 0.40, 0.1),
			"the surge decays back to the base fire (base %f, settled %f)" % [base, settled])
	var lantern_before := float((_lantern_lights()[0] as OmniLight3D).light_energy)
	_lighting.call("flicker_now", 1.5)
	ok(float((_lantern_lights()[0] as OmniLight3D).light_energy) > lantern_before,
			"flicker_now() must brighten the lanterns immediately")
	for i in 120:
		_advance(1.0 / 60.0)
	ok(float((_lantern_lights()[0] as OmniLight3D).light_energy) <= lantern_before * 1.6,
			"the one-shot flick decays")


func test_quit_out_and_slow_clouds() -> void:
	var grade := (_variant_grades() as Dictionary)[&"give"] as Dictionary
	_apply(grade, &"high")
	var before := _all_light_energies()
	var env := _env()
	var density_before := env.volumetric_fog_density

	_lighting.call("quit_out", 2.0)
	ok(not bool(_lighting.call("is_dark")), "quit_out() starts a fade, not a hard cut")
	_advance(1.0)
	ok(not bool(_lighting.call("is_dark")), "half-way through the fade the hall is not dark")
	for i in 120:
		_advance(1.0 / 60.0)
	ok(bool(_lighting.call("is_dark")), "after the fade the rig reports dark")
	var after := _all_light_energies()
	for i in after.size():
		ok(after[i] <= before[i] * 0.10,
				"quit_out() must douse light %d (got %f, base %f)" % [i, after[i], before[i]])

	# slow_clouds() eases the cloud-shadow clock, never snapping it.
	_apply(grade, &"high")
	_lighting.call("slow_clouds", 0.3)
	ok(float(_lighting.call("cloud_scale")) > 0.3, "cloud scale eases toward the target")
	for i in 180:
		_advance(1.0 / 60.0)
	almost(float(_lighting.call("cloud_scale")), 0.3, 0.05,
			"cloud scale reaches the requested slowdown")
	_lighting.call("slow_clouds", 1.0)
	for i in 180:
		_advance(1.0 / 60.0)
	almost(float(_lighting.call("cloud_scale")), 1.0, 0.05, "cloud scale returns to normal")
	almost(env.volumetric_fog_density, density_before, 1e-9,
			"speed reactions never rewrite the environment")


func test_shaders_and_emissive_materials() -> void:
	for path in [BEAM_SHADER_PATH, MOLTEN_SHADER_PATH]:
		ok(ResourceLoader.exists(path), "%s must exist" % path)
		if not ResourceLoader.exists(path):
			continue
		var shader := load(path) as Shader
		ok(shader != null, "%s must load as a Shader" % path)
		if shader == null:
			continue
		ok(shader.code.length() > 300, "%s must carry a real shader body" % path)
		var uniforms: Array[String] = []
		for uniform in shader.get_shader_uniform_list():
			uniforms.append(String(uniform.get("name", "")))
		ok(uniforms.has("emission_energy"), "%s exposes emission_energy" % path)

	var beam := load(BEAM_SHADER_PATH) as Shader
	ok(beam.code.contains("blend_add"), "the beam card is additive")
	ok(beam.code.contains("unshaded"), "the beam card is unshaded")
	ok(beam.code.contains("world_pos"), "the beam card uses world-space UVs")
	ok(beam.code.contains("beam_time"), "the beam card has a time uniform")
	var beam_uniforms: Array[String] = []
	for uniform in beam.get_shader_uniform_list():
		beam_uniforms.append(String(uniform.get("name", "")))
	for name in ["beam_color", "emission_energy", "beam_time", "cloud", "opacity"]:
		ok(beam_uniforms.has(name), "beam uniform %s" % name)

	var molten := load(MOLTEN_SHADER_PATH) as Shader
	ok(molten.code.contains("unshaded"), "the molten river is self lit")
	ok(molten.code.contains("river_bounds"), "the molten river knows its world bounds")
	var molten_uniforms: Array[String] = []
	for uniform in molten.get_shader_uniform_list():
		molten_uniforms.append(String(uniform.get("name", "")))
	for name in ["molten_time", "heat", "emission_energy", "river_bounds", "hot_color"]:
		ok(molten_uniforms.has(name), "molten uniform %s" % name)

	# The rig owns both materials and wires them to the grade + the deterministic clock.
	var grade := (_variant_grades() as Dictionary)[&"act4"] as Dictionary
	_apply(grade, &"high")
	var beam_material := _lighting.call("beam_material") as ShaderMaterial
	ok(beam_material != null, "the rig exposes the beam material")
	if beam_material != null:
		ok(float(beam_material.get_shader_parameter("emission_energy")) > 0.0,
				"beam emission follows the grade")
		almost(float(beam_material.get_shader_parameter("beam_time")), 0.0, 1e-6,
				"beam time starts at 0")
		_advance(0.5)
		almost(float(beam_material.get_shader_parameter("beam_time")), 0.5, 1e-3,
				"advance() drives the beam clock")
	var molten_material := _lighting.call("molten_material") as ShaderMaterial
	ok(molten_material != null, "the rig exposes the molten material")
	if molten_material != null:
		var bounds := molten_material.get_shader_parameter("river_bounds") as Vector4
		almost(bounds.x, -Layout.PIT_HALF_X, 0.0001, "molten river min x")
		almost(bounds.y, Layout.PIT_HALF_X, 0.0001, "molten river max x")
		almost(bounds.z, minf(Layout.LAVA_Z_FRONT, Layout.LAVA_Z_BACK), 0.0001,
				"molten river min z")
		almost(bounds.w, maxf(Layout.LAVA_Z_FRONT, Layout.LAVA_Z_BACK), 0.0001,
				"molten river max z")
		_advance(0.5)
		almost(float(molten_material.get_shader_parameter("molten_time")), 1.0, 1e-3,
				"advance() drives the molten clock")

	# The emissive surfaces exist exactly once (the kit builders leave them to us).
	var cards := 0
	var rivers := 0
	for child in _root.get_children():
		if String(child.name).begins_with("ShaftCard"):
			cards += 1
		elif String(child.name) == "MoltenRiver":
			rivers += 1
	eq(cards, 2, "two crossed additive shaft cards")
	eq(rivers, 1, "exactly one molten river plane")


func test_grade_contract_via_title_state() -> void:
	if not ResourceLoader.exists(STATE_PATH):
		return
	var state_script := load(STATE_PATH) as GDScript
	ok(state_script != null, "TitleState loads")
	if state_script == null:
		return
	var states: Array[Dictionary] = [
		{"variant": &"cold"},
		{"variant": &"journey", "act": 1, "cleared": 1},
		{"variant": &"journey", "act": 2, "cleared": 5},
		{"variant": &"journey", "act": 3, "cleared": 9},
		{"variant": &"journey", "act": 4, "cleared": 13},
		{"variant": &"give"},
		{"variant": &"keep"},
		{"variant": &"snuff"},
		{"variant": &"true_break"},
	]
	var required := [
		"variant", "grade_id", "exposure", "white", "sun_color", "sun_energy",
		"furnace_color", "furnace_energy", "pit_energy", "fog_density", "fog_albedo",
		"fog_emission", "glow_intensity", "grade_tint", "lantern_lit",
	]
	for state in states:
		var grade := state_script.call("grade", state) as Dictionary
		for key in required:
			ok(grade.has(key), "TitleState.grade must expose %s (%s)" % [key, state["variant"]])
		_apply(grade, &"high")
		eq(_lights().size(), FIXTURES, "fixture count with %s" % state["variant"])
		ok(_shadow_casters().size() <= MAX_SHADOW_CASTERS, "shadow budget with %s" % state["variant"])
		eq(int(_lighting.call("lantern_lit")), int(grade["lantern_lit"]),
				"lanterns follow TitleState.grade (%s)" % state["variant"])
		_advance(0.25)
		for energy in _all_light_energies():
			ok(is_finite(energy) and energy >= 0.0,
					"%s: real grade energies stay finite" % state["variant"])

	# The real light plan and this rig must agree on the budget and the shadow set.
	var cold_state := {"variant": &"give"}
	var plan := state_script.call("light_plan", cold_state) as Array
	eq(plan.size(), FIXTURES, "TitleState.light_plan size matches the rig")
	var plan_shadows := 0
	for entry in plan:
		if bool((entry as Dictionary).get("shadow", false)):
			plan_shadows += 1
	eq(plan_shadows, _shadow_casters().size(),
			"TitleState.light_plan shadow count matches the high-tier rig")
	var plan_has_shaft := false
	var plan_has_pit := false
	for entry in plan:
		var spec := entry as Dictionary
		if StringName(spec.get("id", &"")) == &"shaft":
			plan_has_shaft = true
			ok(not bool(spec.get("shadow", true)), "the shaft spotlight never casts a shadow")
		if StringName(spec.get("id", &"")) == &"pit":
			plan_has_pit = true
	ok(plan_has_shaft, "light_plan has the shaft fixture")
	ok(plan_has_pit, "light_plan has the pit fixture")
