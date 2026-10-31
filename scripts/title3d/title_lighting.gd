class_name TitleLighting
extends Node3D
## Forward+ lighting master for the 3D forge-hall title screen.
##
## Owns the one `WorldEnvironment` of the title (ACES tonemap, additive Glow, SSAO,
## SSR on the high tier, volumetric fog, a barely-there near depth fog and a small
## adjustment) plus the 12-light rig of the hall:
##
##   Sun          DirectionalLight3D   roof-gap / far-window key light, shadow
##   ShaftSpot    SpotLight3D          the visible skylight shaft, volumetric, no shadow
##   FurnaceLight OmniLight3D          the forge mouth, shadow
##   PitLight     OmniLight3D          the molten river under the bridge
##   LanternLight x6 OmniLight3D       the six lit lantern fixtures (2 of them shadowed)
##   BrazierLight x2 OmniLight3D       the two bridge-head fires
##
## 12 fixtures <= MAX_LIGHTS (14) and at most 4 shadow casters at the high tier
## (<= MAX_SHADOW_CASTERS = 6); the other tiers drop casters instead of adding any.
## Positions come from the shared coordinate contract in `scripts/title3d/kit/layout.gd`
## (`TitleLayout`) — this file owns no geometry coordinates of its own except the
## tuning constants at the top.
##
## The rig also owns the two emissive surfaces that are pure lighting:
##   - two crossed additive beam cards through the skylight shaft (beam.gdshader),
##   - the molten river plane over the chasm (molten.gdshader).
## `beam_material()` / `molten_material()` hand those materials to other modules.
##
## Public API (all called by `TitleWorld3D`, see scripts/title3d/title_world3d.gd):
##   build(parent)                      one-time construction of env + lights + emissive cards
##   apply(grade, quality)              push a `TitleState.grade()` dictionary + a quality tier
##   advance(dt)                        deterministic clock for fire / river / shaft flicker
##   set_lantern_lit(n)                 N of 14 progress lanterns are lit
##   surge()                            'new' menu row: the forge flares for a moment
##   flicker_now(strength)              a one-shot lamp flick (menu focus)
##   slow_clouds(scale)                 'settings' menu row: shaft cloud-shadow slows to 0.3x
##   quit_out(seconds)                  douse every light over `seconds` (quit sequence)
##   environment() / lights() / shadow_casters() / light_budget()
##   beam_material() / molten_material() / sun_light() / shaft_light() / furnace_light()
##   pit_light() / lantern_lights() / brazier_lights()
##
## Contract notes for Forward+:
##   - `apply()` is idempotent and never creates or deletes a node; `build()` is the only
##     place nodes are created (a second `build()` is a no-op).
##   - Every flicker/noise value is a pure function of (time, seed); `advance(dt)` only
##     accumulates time and decays impulses — splitting a delta gives the same result.
##   - SDFGI stays off (slow convergence + camera-motion trails) and SSIL stays off.
##   - Godot has no per-light shadow-map size in Forward+ (directional + positional
##     atlases are project settings). SHADOW_MAP_HINTS records the intended budgets;
##     the rig only decides *which* lights cast.
##   - `Environment.ssr_enabled` is the only tier-gated effect (high); SSAO keeps
##     half-size in every tier through RenderingServer (see `_apply_ssao_quality`),
##     volumetric fog lowers its density/temporal quality and Glow is never dropped.
##   - `apply()` deliberately does NOT reset the quit fade: `quit_out()` is a terminal
##     sequence and the title screen builds a fresh title world (and therefore a fresh
##     rig) for every visit, so an already-doused rig is never reused. A caller that
##     wants to reopen the hall on the same rig must build a new one instead of
##     re-applying a grade.
##
## Grades: every key of `TitleState.grade()` is consumed; a missing or mistyped key
## falls back to the safe cold-forge defaults below (never to NaN). The legacy 2D
## GRADES keys are kept as fallbacks for the keys that only exist there
## (`ambient`, `shaft`, `shaft_color`, `forge`, `lantern`, `flicker`).

const Layout := preload("res://scripts/title3d/kit/layout.gd")
const BEAM_SHADER_PATH := "res://assets/shaders/title3d/beam.gdshader"
const MOLTEN_SHADER_PATH := "res://assets/shaders/title3d/molten.gdshader"

# ---------------------------------------------------------------------------
# Budget (mirrors TitleState.light_plan; kept local so this module stands alone)
# ---------------------------------------------------------------------------
const LANTERN_COUNT := 14
## The six of the fourteen lanterns that carry a real light (front row first).
const LANTERN_LIGHT_FIXTURES: Array[int] = [0, 1, 4, 7, 10, 13]
## The lantern lights that cast a shadow (the old 2D shadow pair).
const LANTERN_SHADOW_FIXTURES: Array[int] = [4, 10]
## 1 sun + 1 shaft + 1 furnace + 1 pit + 6 lanterns + 2 braziers.
const LIGHT_FIXTURES := 12
const MAX_LIGHTS := 14
const MAX_SHADOW_CASTERS := 6
## Intended shadow-map budgets. These are project-wide atlases in Forward+, so the
## rig only reports them (Lead owns project.godot); per-light sizes do not exist.
const SHADOW_MAP_HINTS := {"directional": 2048, "positional": 512}

# ---------------------------------------------------------------------------
# Energy / range tuning (same units as TitleState.light_plan, so the numbers add up)
# ---------------------------------------------------------------------------
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
const PIT_COLOR := Color(1.0, 0.55, 0.18)
## The river glows from below the bridge; lift the omni a little off the surface.
const PIT_LIGHT_LIFT := 0.85
## Brazier omni sits just above the bowl, not at its feet.
const BRAZIER_LIGHT_LIFT := 0.85

# ---------------------------------------------------------------------------
# Emissive surfaces (the light shaft card and the molten river plane)
# ---------------------------------------------------------------------------
const SHAFT_CARD_WIDTH := 3.4
const SHAFT_CARD_COUNT := 2
const MOLTEN_SURFACE_SCALE := 1.0

# ---------------------------------------------------------------------------
# Deterministic clock / reaction tuning
# ---------------------------------------------------------------------------
const MAX_STEP := 0.1
## Hard clamp so a pathological delta can never grow the per-frame loop; anything up
## to ten seconds is still split into fixed steps, so `advance(a) + advance(b)` and
## `advance(a + b)` stay identical (deterministic clock).
const MAX_ADVANCE := 10.0
const MAX_STEPS := 1000
const SURGE_DECAY := 0.9
const FLICKER_DECAY := 2.2
const SURGE_FIRE_GAIN := 0.60
const SURGE_FLICKER_GAIN := 0.25
const CLOUD_EASE := 1.2

# ---------------------------------------------------------------------------
# Quality tiers
# ---------------------------------------------------------------------------
const QUALITY_HIGH := &"high"
const QUALITY_BALANCED := &"balanced"
const QUALITY_LOW := &"low"
const DEFAULT_QUALITY := QUALITY_HIGH
const QUALITIES: Array[StringName] = [QUALITY_HIGH, QUALITY_BALANCED, QUALITY_LOW]
## `shadow_budget` counts shadow-casting fixtures (sun + furnace + 2 lanterns = 4 at most).
## `ssao_quality` maps to RenderingServer's SSAO quality enum (2 high / 1 medium / 0 low);
## half-size stays on in every tier, the renderer's own project default.
const QUALITY_CONFIG := {
	QUALITY_HIGH: {
		"ssr": true, "ssao_quality": 2, "ssao_half_size": true, "ssao_detail": 0.50,
		"fog_density_scale": 1.00, "fog_detail_spread": 1.50, "fog_temporal": 0.90,
		"shadow_budget": 4,
	},
	QUALITY_BALANCED: {
		"ssr": false, "ssao_quality": 1, "ssao_half_size": true, "ssao_detail": 0.36,
		"fog_density_scale": 0.85, "fog_detail_spread": 2.00, "fog_temporal": 0.70,
		"shadow_budget": 2,
	},
	QUALITY_LOW: {
		"ssr": false, "ssao_quality": 0, "ssao_half_size": true, "ssao_detail": 0.25,
		"fog_density_scale": 0.70, "fog_detail_spread": 2.50, "fog_temporal": 0.50,
		"shadow_budget": 1,
	},
}

# ---------------------------------------------------------------------------
# Safe defaults: what `apply({})` must produce. Used verbatim for missing grade keys.
# ---------------------------------------------------------------------------
const DEF_VARIANT := &"cold"
const DEF_GRADE_ID := &"cold"
const DEF_EXPOSURE := 0.85
const DEF_WHITE := 1.06
const DEF_SUN_COLOR := Color(0.55, 0.66, 0.82)
const DEF_SUN_ENERGY := 0.55
const DEF_FURNACE_COLOR := Color(1.0, 0.42, 0.16)
const DEF_FURNACE_ENERGY := 0.45
const DEF_PIT_ENERGY := 0.35
const DEF_FOG_DENSITY := 0.024
const DEF_FOG_ALBEDO := Color(0.38, 0.42, 0.50)
const DEF_FOG_EMISSION := Color(0.05, 0.05, 0.06)
const DEF_GLOW_INTENSITY := 0.55
const DEF_GRADE_TINT := Color(0.82, 0.86, 0.95)
const DEF_LANTERN_LIT := 0
const DEF_AMBIENT := Color(0.50, 0.46, 0.54)
const DEF_SHAFT := 0.55
const DEF_SHAFT_COLOR := Color(0.40, 0.56, 0.66)
const DEF_FORGE := 0.16
const DEF_LANTERN_COLOR := Color(1.0, 0.62, 0.30)
const DEF_FLICKER := 1.0

const BG_COLOR_BASE := Color(0.030, 0.026, 0.045)
const GLOW_LEVEL_WEIGHTS: Array[float] = [1.0, 0.88, 0.70, 0.50, 0.30, 0.0, 0.0]
const SSAO_RADIUS := 0.7
const SSAO_INTENSITY := 1.4
const SSAO_POWER := 1.2
const SSR_MAX_STEPS := 32
const SSR_FADE_IN := 0.15
const SSR_FADE_OUT := 2.0
const SSR_DEPTH_TOLERANCE := 0.3
const VOLUMETRIC_FOG_LENGTH := 48.0
const VOLUMETRIC_FOG_ANISOTROPY := 0.3
const FOG_DEPTH_BEGIN := 26.0
const FOG_DEPTH_END := 92.0
const FOG_DEPTH_CURVE := 1.1

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var _built := false
var _root: Node3D
var _env: Environment
var _world_env: WorldEnvironment

var _sun: DirectionalLight3D
var _shaft: SpotLight3D
var _furnace: OmniLight3D
var _pit: OmniLight3D
## One light per LANTERN_LIGHT_FIXTURES entry, in that order.
var _lantern_lights: Array[OmniLight3D] = []
var _brazier_lights: Array[OmniLight3D] = []
## The two lantern lights that own a shadow (fixtures 4 and 10), in light order.
var _lantern_shadow_lights: Array[OmniLight3D] = []
var _lights: Array[Light3D] = []
var _shadow_lights: Array[Light3D] = []

var _beam_cards: Array[MeshInstance3D] = []
var _beam_material: ShaderMaterial
var _molten_surface: MeshInstance3D
var _molten_material: ShaderMaterial

var _grade: Dictionary = {}
var _quality: StringName = &""
var _grade_id: StringName = DEF_GRADE_ID
var _variant: StringName = DEF_VARIANT
var _lantern_lit := DEF_LANTERN_LIT
var _time := 0.0
## Accumulated cloud-shadow clock; `slow_clouds()` scales its rate (never its phase).
var _cloud_time := 0.0
var _cloud_scale := 1.0
var _cloud_target := 1.0
var _surge := 0.0
var _flicker_boost := 0.0
var _quit_total := 0.0
var _quit_t := 0.0
var _volumetric_light_energy := 1.0

# Per-light baselines, rebuilt by apply().
var _sun_base := 0.0
var _shaft_base := 0.0
var _furnace_base := 0.0
var _pit_base := 0.0
## Two braziers, in brazier order.
var _brazier_base: Array[float] = [0.0, 0.0]
var _sun_color := DEF_SUN_COLOR
var _shaft_color := DEF_SHAFT_COLOR
## The grade's ambient term, exposed so the kit's unshaded surfaces (which opt out of
## the Environment ambient with `ambient_light_disabled`) can be synced by the world:
## `TitleKit.set_ambient(lighting.ambient_color(), lighting.ambient_energy())`.
var _ambient_color := DEF_AMBIENT
var _ambient_energy := 0.16
# Flicker amplitudes (0 = steady light).
var _sun_amp := 0.05
var _shaft_amp := 0.10
var _furnace_amp := 0.30
var _pit_amp := 0.08
var _lantern_amp := 0.16
var _brazier_amp := 0.26

# Renderer-side SSAO quality args (read once; the renderer call is global in Forward+).
var _ssao_adaptive_target := 0.5
var _ssao_blur_passes := 2
var _ssao_fade_from := 50.0
var _ssao_fade_to := 300.0
## Project defaults of the renderer-wide SSAO knobs, restored when the rig leaves the
## tree so a low/balanced title tier never leaks into a gameplay level.
var _ssao_project_quality := 2
var _ssao_project_half_size := true
var _ssao_touched := false


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

## Build the whole rig once, parented under `parent` (the title world root). When
## `parent` is null the rig becomes a child of this node. Calling it again is a no-op:
## nodes are never rebuilt (and never by `apply()`).
func build(parent: Node3D = null) -> void:
	if _built:
		return
	_root = parent if parent != null else self
	_read_renderer_defaults()
	_build_environment(_root)
	_build_lights(_root)
	_build_emissive_surfaces(_root)
	_built = true
	# Push whatever grade/quality was handed to apply() before build() (or the defaults).
	apply(_grade, _quality if _quality != &"" else DEFAULT_QUALITY)


func _build_environment(root: Node3D) -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = BG_COLOR_BASE
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_energy = 0.16
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.0
	_env.tonemap_white = 1.0
	_env.glow_enabled = true
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	_env.glow_intensity = DEF_GLOW_INTENSITY
	_env.glow_strength = 1.0
	_env.glow_bloom = 0.15
	_env.glow_hdr_threshold = 0.9
	_env.glow_hdr_scale = 2.0
	_env.glow_hdr_luminance_cap = 16.0
	_env.glow_normalized = false
	_env.ssao_enabled = true
	_env.ssao_radius = SSAO_RADIUS
	_env.ssao_intensity = SSAO_INTENSITY
	_env.ssao_power = SSAO_POWER
	_env.ssil_enabled = false
	_env.sdfgi_enabled = false
	_env.ssr_enabled = false
	_env.ssr_max_steps = SSR_MAX_STEPS
	_env.ssr_fade_in = SSR_FADE_IN
	_env.ssr_fade_out = SSR_FADE_OUT
	_env.ssr_depth_tolerance = SSR_DEPTH_TOLERANCE
	_env.volumetric_fog_enabled = true
	_env.volumetric_fog_density = DEF_FOG_DENSITY
	_env.volumetric_fog_albedo = DEF_FOG_ALBEDO
	_env.volumetric_fog_emission = DEF_FOG_EMISSION
	_env.volumetric_fog_emission_energy = 0.5
	_env.volumetric_fog_anisotropy = VOLUMETRIC_FOG_ANISOTROPY
	_env.volumetric_fog_length = VOLUMETRIC_FOG_LENGTH
	_env.volumetric_fog_ambient_inject = 0.12
	_env.volumetric_fog_sky_affect = 0.0
	_env.volumetric_fog_gi_inject = 0.0
	_env.volumetric_fog_temporal_reprojection_enabled = true
	_env.volumetric_fog_temporal_reprojection_amount = 0.9
	_env.fog_enabled = true
	_env.fog_mode = Environment.FOG_MODE_DEPTH
	_env.fog_light_color = DEF_FOG_ALBEDO
	_env.fog_light_energy = 0.35
	_env.fog_density = 0.004
	_env.fog_depth_begin = FOG_DEPTH_BEGIN
	_env.fog_depth_end = FOG_DEPTH_END
	_env.fog_depth_curve = FOG_DEPTH_CURVE
	_env.fog_sun_scatter = 0.12
	_env.fog_aerial_perspective = 0.30
	_env.fog_sky_affect = 0.0
	_env.adjustment_enabled = true
	_env.adjustment_brightness = 1.0
	_env.adjustment_contrast = 1.04
	_env.adjustment_saturation = 1.06
	for i in GLOW_LEVEL_WEIGHTS.size():
		_env.set("glow_levels/%d" % (i + 1), GLOW_LEVEL_WEIGHTS[i])
	_world_env = WorldEnvironment.new()
	_world_env.name = "WorldEnvironment"
	_world_env.environment = _env
	root.add_child(_world_env)


func _read_renderer_defaults() -> void:
	_ssao_adaptive_target = float(ProjectSettings.get_setting(
			"rendering/environment/ssao/adaptive_target", 0.5))
	_ssao_blur_passes = int(ProjectSettings.get_setting(
			"rendering/environment/ssao/blur_passes", 2))
	_ssao_fade_from = float(ProjectSettings.get_setting(
			"rendering/environment/ssao/fadeout_from", 50.0))
	_ssao_fade_to = float(ProjectSettings.get_setting(
			"rendering/environment/ssao/fadeout_to", 300.0))
	_ssao_project_quality = int(ProjectSettings.get_setting(
			"rendering/environment/ssao/quality", 2))
	_ssao_project_half_size = bool(ProjectSettings.get_setting(
			"rendering/environment/ssao/half_size", true))


func _exit_tree() -> void:
	restore_renderer_defaults()


func _build_lights(root: Node3D) -> void:
	# --- the skylight / far-window key light ---------------------------------
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.position = Layout.SKYLIGHT_CENTER
	_sun.rotation_degrees = Layout.SUN_ROTATION_DEG
	_sun.light_color = DEF_SUN_COLOR
	_sun.light_energy = DEF_SUN_ENERGY
	_sun.light_volumetric_fog_energy = 0.9
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = 60.0
	_sun.directional_shadow_fade_start = 0.85
	_sun.shadow_bias = 0.02
	_sun.shadow_normal_bias = 1.4
	_sun.shadow_blur = 1.0
	_sun.distance_fade_enabled = false
	root.add_child(_sun)
	_lights.append(_sun)

	# --- the visible shaft: a spot aimed down BEAM_FROM -> BEAM_TO -----------
	_shaft = SpotLight3D.new()
	_shaft.name = "ShaftSpot"
	_shaft.light_color = DEF_SHAFT_COLOR.lerp(WARM_WHITE, 0.30)
	_shaft.light_energy = 2.0
	_shaft.light_volumetric_fog_energy = 2.0
	_shaft.shadow_enabled = false
	_shaft.spot_range = SHAFT_RANGE
	# The visible shaft card is SHAFT_CARD_WIDTH wide at the bridge 20.3 m below the
	# roof gap, so a narrow cone keeps the volumetric god ray matching the card
	# instead of flooding the whole hall.
	_shaft.spot_angle = 10.0
	_shaft.spot_angle_attenuation = 1.15
	_shaft.spot_attenuation = 1.0
	root.add_child(_shaft)
	_shaft.position = Layout.BEAM_FROM
	# Node3D.look_at after entering the tree so the parent transform is honoured.
	_shaft.look_at(Layout.BEAM_TO, Vector3.UP)
	_lights.append(_shaft)

	# --- the forge mouth ----------------------------------------------------
	_furnace = OmniLight3D.new()
	_furnace.name = "FurnaceLight"
	_furnace.position = Layout.FORGE_LIGHT_POS
	_furnace.light_color = DEF_FURNACE_COLOR
	_furnace.light_energy = 1.0
	_furnace.light_volumetric_fog_energy = 1.2
	_furnace.omni_range = FURNACE_RANGE
	_furnace.omni_attenuation = 1.0
	_furnace.shadow_enabled = true
	_furnace.shadow_bias = 0.05
	_furnace.shadow_normal_bias = 1.5
	root.add_child(_furnace)
	_lights.append(_furnace)

	# --- the molten river glow from under the bridge ------------------------
	_pit = OmniLight3D.new()
	_pit.name = "PitLight"
	_pit.position = Layout.PIT_CENTER + Vector3(0.0, PIT_LIGHT_LIFT, 0.0)
	_pit.light_color = DEF_FURNACE_COLOR.lerp(PIT_COLOR, 0.25)
	_pit.light_energy = 1.0
	_pit.light_volumetric_fog_energy = 1.6
	_pit.omni_range = PIT_RANGE
	_pit.omni_attenuation = 1.0
	_pit.shadow_enabled = false
	root.add_child(_pit)
	_lights.append(_pit)

	# --- the six lantern fixtures ------------------------------------------
	var lantern_positions := Layout.lantern_positions()
	for index in LANTERN_LIGHT_FIXTURES.size():
		var fixture := int(LANTERN_LIGHT_FIXTURES[index])
		var light := OmniLight3D.new()
		light.name = "LanternLight%d" % index
		if fixture < lantern_positions.size():
			light.position = lantern_positions[fixture]
		else:
			light.position = Vector3(0.0, Layout.LANTERN_HANG_Y, Layout.LANTERN_FRONT_Z)
		light.light_color = DEF_LANTERN_COLOR
		light.light_energy = 0.0
		light.light_volumetric_fog_energy = 0.7
		light.omni_range = LANTERN_RANGE
		light.omni_attenuation = 1.0
		light.shadow_enabled = false
		light.shadow_bias = 0.05
		light.shadow_normal_bias = 1.5
		root.add_child(light)
		_lantern_lights.append(light)
		_lights.append(light)
		if LANTERN_SHADOW_FIXTURES.has(fixture):
			_lantern_shadow_lights.append(light)

	# --- the two bridge-head braziers --------------------------------------
	var brazier_positions := Layout.braziers()
	for index in 2:
		var light := OmniLight3D.new()
		light.name = "BrazierLight%d" % index
		if index < brazier_positions.size():
			light.position = brazier_positions[index] + Vector3(0.0, BRAZIER_LIGHT_LIFT, 0.0)
		else:
			light.position = Vector3(0.0, BRAZIER_LIGHT_LIFT, Layout.BRAZIER_LEFT.z)
		light.light_color = BRAZIER_COLOR
		light.light_energy = 0.0
		light.light_volumetric_fog_energy = 1.0
		light.omni_range = BRAZIER_RANGE
		light.omni_attenuation = 1.0
		light.shadow_enabled = false
		root.add_child(light)
		_brazier_lights.append(light)
		_lights.append(light)


func _build_emissive_surfaces(root: Node3D) -> void:
	# The visible skylight shaft: crossed additive cards, one shared material.
	var beam_shader := _load_shader(BEAM_SHADER_PATH)
	if beam_shader != null:
		_beam_material = ShaderMaterial.new()
		_beam_material.shader = beam_shader
		var from := Layout.BEAM_FROM
		var to := Layout.BEAM_TO
		var axis := to - from
		var length := axis.length()
		if length > 0.001:
			var up := axis / length
			var normal := Vector3(0.0, 0.0, 1.0)
			normal -= up * normal.dot(up)
			if normal.length_squared() < 0.0001:
				normal = Vector3(0.0, 1.0, 0.0) - up * up.y
			normal = normal.normalized()
			var right := up.cross(normal).normalized()
			var mid := from + axis * 0.5
			for i in SHAFT_CARD_COUNT:
				var card := MeshInstance3D.new()
				card.name = "ShaftCard%d" % i
				var quad := QuadMesh.new()
				quad.size = Vector2(SHAFT_CARD_WIDTH, length)
				card.mesh = quad
				card.material_override = _beam_material
				card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				card.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
				var basis := Basis(right, up, normal)
				if i > 0:
					basis = basis.rotated(up, PI * 0.5)
				card.transform = Transform3D(basis, mid)
				root.add_child(card)
				_beam_cards.append(card)

	# The molten river: one unshaded plane over the chasm, self-lit by molten.gdshader.
	var molten_shader := _load_shader(MOLTEN_SHADER_PATH)
	if molten_shader != null:
		_molten_material = ShaderMaterial.new()
		_molten_material.shader = molten_shader
		var half_x := Layout.PIT_HALF_X
		var z_near := maxf(Layout.LAVA_Z_FRONT, Layout.LAVA_Z_BACK)
		var z_far := minf(Layout.LAVA_Z_FRONT, Layout.LAVA_Z_BACK)
		var depth := (z_near - z_far) * MOLTEN_SURFACE_SCALE
		var width := half_x * 2.0 * MOLTEN_SURFACE_SCALE
		var surface := MeshInstance3D.new()
		surface.name = "MoltenRiver"
		var plane := PlaneMesh.new()
		plane.size = Vector2(width, depth)
		plane.subdivide_width = 0
		plane.subdivide_depth = 0
		surface.mesh = plane
		surface.material_override = _molten_material
		surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		surface.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		surface.position = Vector3(0.0, Layout.LAVA_Y, (z_near + z_far) * 0.5)
		root.add_child(surface)
		_molten_surface = surface
		_molten_material.set_shader_parameter("river_bounds",
				Vector4(-half_x, half_x, z_far, z_near))


static func _load_shader(path: String) -> Shader:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Shader


# ---------------------------------------------------------------------------
# apply(grade, quality)
# ---------------------------------------------------------------------------

## Push a `TitleState.grade()` dictionary and a quality tier onto the rig.
##
## Idempotent: the same (grade, quality) pair applied twice leaves every parameter
## identical and never creates or deletes a node. Grade keys that are missing or of
## the wrong type fall back to the cold-forge defaults, so `apply({})` is safe.
func apply(grade: Dictionary, quality: StringName = DEFAULT_QUALITY) -> void:
	_quality = _normalize_quality(quality)
	_grade = grade.duplicate(true)
	_grade_id = _key(_grade, ["grade_id", "variant"], DEF_GRADE_ID)
	_variant = _key(_grade, ["variant"], _grade_id)
	_lantern_lit = clampi(int(_num(_grade, ["lantern_lit"], float(DEF_LANTERN_LIT))),
			0, LANTERN_COUNT)
	_volumetric_light_energy = clampf(_num(_grade, ["volumetric_light_energy"],
			_volumetric_light_energy), 0.0, 4.0)
	if not _built:
		return
	_apply_environment(_grade)
	_apply_lights(_grade)
	_apply_shadow_budget()
	_refresh_energies()
	_refresh_shader_parameters(true)


func _apply_environment(grade: Dictionary) -> void:
	if _env == null:
		return
	var quality: Dictionary = QUALITY_CONFIG[_quality]
	var exposure := clampf(_num(grade, ["exposure"], DEF_EXPOSURE), 0.05, 8.0)
	var white := clampf(_num(grade, ["white"], DEF_WHITE), 0.10, 8.0)
	var tint := _col(grade, ["grade_tint"], DEF_GRADE_TINT)
	var fog_density := clampf(_num(grade, ["fog_density"], DEF_FOG_DENSITY), 0.0, 0.12)
	var fog_albedo := _col(grade, ["fog_albedo"], DEF_FOG_ALBEDO)
	var fog_emission := _col(grade, ["fog_emission"], DEF_FOG_EMISSION)
	var glow_intensity := clampf(_num(grade, ["glow_intensity"], DEF_GLOW_INTENSITY), 0.0, 2.0)
	var ambient := _col(grade, ["ambient"], DEF_AMBIENT)
	var fog_scale := float(quality["fog_density_scale"])

	# Tonemap: ACES, exposure/white strictly grade driven.
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = exposure
	_env.tonemap_white = white

	# Background: deep hall darkness (the geometry covers almost all of it).
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = _scale_color(BG_COLOR_BASE, tint)
	_env.background_energy_multiplier = 1.0

	# Ambient: low energy, cold and tinted; it only shapes the shadows.
	_ambient_color = _scale_color(ambient, tint)
	_ambient_energy = clampf(0.10 + 0.10 * exposure, 0.05, 0.30)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = _ambient_color
	_env.ambient_light_energy = _ambient_energy
	_env.ambient_light_sky_contribution = 0.0

	# Glow: always on, every tier. HDR threshold 0.9 catches only the hot cores.
	_env.glow_enabled = true
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	_env.glow_intensity = glow_intensity
	_env.glow_strength = 1.0
	_env.glow_bloom = 0.15
	_env.glow_hdr_threshold = 0.9
	_env.glow_hdr_scale = 2.0
	_env.glow_hdr_luminance_cap = 16.0
	_env.glow_normalized = false
	for i in GLOW_LEVEL_WEIGHTS.size():
		_env.set("glow_levels/%d" % (i + 1), GLOW_LEVEL_WEIGHTS[i])

	# SSAO: every tier, half size; only the renderer quality enum and detail change.
	_env.ssao_enabled = true
	_env.ssao_radius = SSAO_RADIUS
	_env.ssao_intensity = SSAO_INTENSITY
	_env.ssao_power = SSAO_POWER
	_env.ssao_detail = float(quality["ssao_detail"])
	_env.ssao_horizon = 0.06
	_env.ssao_sharpness = 0.98
	_env.ssao_light_affect = 0.18
	_env.ssao_ao_channel_affect = 0.0

	# SSR: high tier only (wet iron and the molten river reflections).
	var ssr := bool(quality["ssr"])
	_env.ssr_enabled = ssr
	_env.ssr_max_steps = SSR_MAX_STEPS
	_env.ssr_fade_in = SSR_FADE_IN
	_env.ssr_fade_out = SSR_FADE_OUT
	_env.ssr_depth_tolerance = SSR_DEPTH_TOLERANCE

	# SDFGI is deliberately off (slow convergence + camera-motion trails) and SSIL
	# never paid for itself at 640x360.
	_env.sdfgi_enabled = false
	_env.ssil_enabled = false

	# Volumetric fog: the light shafts live here. The tier lowers density,
	# detail spread and temporal reprojection, never switches the effect off.
	_env.volumetric_fog_enabled = true
	_env.volumetric_fog_density = clampf(fog_density * fog_scale, 0.0, 0.12)
	_env.volumetric_fog_albedo = _scale_color(fog_albedo, tint)
	_env.volumetric_fog_emission = _scale_color(fog_emission, tint)
	_env.volumetric_fog_emission_energy = 0.5
	_env.volumetric_fog_anisotropy = VOLUMETRIC_FOG_ANISOTROPY
	_env.volumetric_fog_length = VOLUMETRIC_FOG_LENGTH
	_env.volumetric_fog_detail_spread = float(quality["fog_detail_spread"])
	_env.volumetric_fog_ambient_inject = 0.12
	_env.volumetric_fog_sky_affect = 0.0
	_env.volumetric_fog_gi_inject = 0.0
	_env.volumetric_fog_temporal_reprojection_enabled = true
	_env.volumetric_fog_temporal_reprojection_amount = float(quality["fog_temporal"])

	# Near depth fog: barely there, keeps the bridge crisp and the far wall hazy.
	_env.fog_enabled = true
	_env.fog_mode = Environment.FOG_MODE_DEPTH
	_env.fog_light_color = _scale_color(fog_albedo, tint)
	_env.fog_light_energy = 0.35
	_env.fog_density = clampf(fog_density * 0.16 * fog_scale, 0.0, 0.05)
	_env.fog_depth_begin = FOG_DEPTH_BEGIN
	_env.fog_depth_end = FOG_DEPTH_END
	_env.fog_depth_curve = FOG_DEPTH_CURVE
	_env.fog_sun_scatter = 0.12
	_env.fog_aerial_perspective = 0.30
	_env.fog_sky_affect = 0.0

	# Adjustment: a micro-contrast/saturation lift only; exposure does the rest.
	_env.adjustment_enabled = true
	_env.adjustment_brightness = 1.0
	_env.adjustment_contrast = 1.04
	_env.adjustment_saturation = 1.06

	_apply_ssao_quality(quality)
	_apply_volumetric_light_energy()


func _apply_lights(grade: Dictionary) -> void:
	var sun_color := _col(grade, ["sun_color"], DEF_SUN_COLOR)
	var furnace_color := _col(grade, ["furnace_color"], DEF_FURNACE_COLOR)
	var lantern_color := _col(grade, ["lantern"], DEF_LANTERN_COLOR)
	var shaft_color := _col(grade, ["shaft_color"], sun_color).lerp(WARM_WHITE, 0.30)
	var sun_energy := clampf(_num(grade, ["sun_energy"], DEF_SUN_ENERGY), 0.0, 8.0)
	var furnace_energy := clampf(_num(grade, ["furnace_energy", "furnace"], DEF_FURNACE_ENERGY),
			0.0, 8.0)
	var pit_energy := clampf(_num(grade, ["pit_energy"], DEF_PIT_ENERGY), 0.0, 8.0)
	var shaft := clampf(_num(grade, ["shaft"], DEF_SHAFT), 0.0, 4.0)
	var forge := clampf(_num(grade, ["forge"], DEF_FORGE), 0.0, 4.0)
	var flicker := clampf(_num(grade, ["flicker"], DEF_FLICKER), 0.0, 2.5)
	var lantern_flicker := clampf(_num(grade, ["lantern_flicker"], flicker), 0.0, 2.5)
	var brazier_flicker := clampf(_num(grade, ["brazier_flicker"], flicker), 0.0, 2.5)

	# Baselines (energies exactly as TitleState.light_plan scales them).
	_sun_base = sun_energy
	_shaft_base = sun_energy * SHAFT_ENERGY_SCALE
	# The spot is the *visible* enhancement of the shaft, so the legacy `shaft`
	# factor (0.28..1.15) lifts it a little without changing the plan's budget.
	_shaft_base *= clampf(0.55 + 0.45 * shaft, 0.1, 2.0)
	_furnace_base = furnace_energy * FURNACE_ENERGY_SCALE
	_pit_base = pit_energy * PIT_ENERGY_SCALE
	var brazier_left := _num(grade, ["brazier_left"], -1.0)
	var brazier_right := _num(grade, ["brazier_right"], -1.0)
	_brazier_base[0] = (brazier_left if brazier_left >= 0.0 else forge) * BRAZIER_ENERGY_SCALE
	_brazier_base[1] = (brazier_right if brazier_right >= 0.0 else forge) * BRAZIER_ENERGY_SCALE
	_brazier_base[0] = clampf(_brazier_base[0], 0.0, 32.0)
	_brazier_base[1] = clampf(_brazier_base[1], 0.0, 32.0)

	# Flicker amplitudes: the tier never touches them, the variant does.
	_sun_amp = 0.05
	_shaft_amp = clampf(0.10 + SHAFT_FLICKER, 0.0, 0.4)
	_furnace_amp = clampf(0.30 * flicker, 0.0, 0.7)
	_pit_amp = clampf(0.08 * flicker, 0.0, 0.25)
	_lantern_amp = clampf(0.16 * lantern_flicker, 0.0, 0.55)
	_brazier_amp = clampf(0.26 * brazier_flicker, 0.0, 0.75)

	# Colours.
	_sun_color = sun_color
	_shaft_color = shaft_color
	if _sun != null:
		_sun.light_color = sun_color
	if _shaft != null:
		_shaft.light_color = shaft_color
		_shaft.spot_range = SHAFT_RANGE
	if _furnace != null:
		_furnace.light_color = furnace_color
		_furnace.omni_range = FURNACE_RANGE
	if _pit != null:
		_pit.light_color = furnace_color.lerp(PIT_COLOR, 0.25)
		_pit.omni_range = PIT_RANGE
	for light in _lantern_lights:
		light.light_color = lantern_color
		light.omni_range = LANTERN_RANGE
	for light in _brazier_lights:
		light.light_color = BRAZIER_COLOR
		light.omni_range = BRAZIER_RANGE


func _apply_shadow_budget() -> void:
	var budget := int(QUALITY_CONFIG[_quality]["shadow_budget"])
	var priority: Array[Light3D] = []
	if _sun != null:
		priority.append(_sun)
	if _furnace != null:
		priority.append(_furnace)
	for light in _lantern_shadow_lights:
		priority.append(light)
	for i in priority.size():
		priority[i].shadow_enabled = i < budget
	_shadow_lights.clear()
	for i in mini(budget, priority.size()):
		_shadow_lights.append(priority[i])


func _apply_ssao_quality(quality: Dictionary) -> void:
	# Environment has no half-size/quality property: in Forward+ this is the
	# renderer-wide SSAO quality (defaults come from project settings, half size is
	# the project default). Guarded so a future headless stub without the method
	# still runs.
	if not RenderingServer.has_method("environment_set_ssao_quality"):
		return
	RenderingServer.environment_set_ssao_quality(
			int(quality["ssao_quality"]),
			bool(quality["ssao_half_size"]),
			_ssao_adaptive_target,
			_ssao_blur_passes,
			_ssao_fade_from,
			_ssao_fade_to)
	_ssao_touched = true


## Put the renderer-wide SSAO quality back to the project defaults (called when the
## rig leaves the tree, i.e. the title screen is released, so a non-high tier cannot
## leak into the next scene). Safe to call at any time.
func restore_renderer_defaults() -> void:
	if not _ssao_touched:
		return
	_ssao_touched = false
	if not RenderingServer.has_method("environment_set_ssao_quality"):
		return
	var current_quality := int(QUALITY_CONFIG[_quality]["ssao_quality"])
	var current_half := bool(QUALITY_CONFIG[_quality]["ssao_half_size"])
	if current_quality == _ssao_project_quality and current_half == _ssao_project_half_size:
		return
	RenderingServer.environment_set_ssao_quality(
			_ssao_project_quality,
			_ssao_project_half_size,
			_ssao_adaptive_target,
			_ssao_blur_passes,
			_ssao_fade_from,
			_ssao_fade_to)


func _apply_volumetric_light_energy() -> void:
	var energy := clampf(_volumetric_light_energy, 0.0, 4.0)
	if _sun != null:
		_sun.light_volumetric_fog_energy = 0.9 * energy
	if _shaft != null:
		_shaft.light_volumetric_fog_energy = 2.0 * energy
	if _furnace != null:
		_furnace.light_volumetric_fog_energy = 1.2 * energy
	if _pit != null:
		_pit.light_volumetric_fog_energy = 1.6 * energy
	for light in _lantern_lights:
		light.light_volumetric_fog_energy = 0.7 * energy
	for light in _brazier_lights:
		light.light_volumetric_fog_energy = 1.0 * energy


# ---------------------------------------------------------------------------
# Deterministic animation
# ---------------------------------------------------------------------------

## Advance the deterministic clock. Fire, river and shaft values are pure functions
## of (time, seed); this only accumulates time and decays the one-shot impulses, so
## the same total delta split differently produces the same state. Non-finite or
## negative deltas are ignored.
func advance(dt: float) -> void:
	if not _built:
		return
	if not is_finite(dt) or dt <= 0.0:
		return
	var left := minf(dt, MAX_ADVANCE)
	var steps := 0
	while left > 0.0 and steps < MAX_STEPS:
		var step := minf(left, MAX_STEP)
		left -= step
		steps += 1
		_time += step
		_cloud_scale = move_toward(_cloud_scale, _cloud_target, step * CLOUD_EASE)
		_cloud_time += step * _cloud_scale
		if _quit_total > 0.0:
			_quit_t = minf(_quit_t + step, _quit_total)
		_surge = maxf(0.0, _surge - step * SURGE_DECAY)
		_flicker_boost = maxf(0.0, _flicker_boost - step * FLICKER_DECAY)
	_refresh_energies()
	_refresh_shader_parameters(false)


## `n` of the 14 progress lanterns are lit: the six lantern fixtures light up while
## `fixture < n` (the exact N/14 mapping of the 2D title). Clamped to 0..14.
func set_lantern_lit(n: int) -> void:
	_lantern_lit = clampi(n, 0, LANTERN_COUNT)
	if _built:
		_refresh_energies()


## 'new' menu row: the forge flares for a moment; the bonus decays in `advance()`.
func surge() -> void:
	_surge = maxf(_surge, 1.0)
	_flicker_boost = maxf(_flicker_boost, 0.35)
	if _built:
		_refresh_energies()


## One-shot lamp flick (menu focus / gate). `strength` 0..4, decays in `advance()`.
func flicker_now(strength: float = 1.0) -> void:
	var amount := strength if is_finite(strength) else 1.0
	_flicker_boost = clampf(maxf(_flicker_boost, amount), 0.0, 4.0)
	if _built:
		_refresh_energies()


## 'settings' menu row: the shaft's cloud shadow slows down (1.0 = normal). The
## eased scale is applied to the cloud clock, never to a random source.
func slow_clouds(scale: float = 1.0) -> void:
	_cloud_target = clampf(scale if is_finite(scale) else 1.0, 0.0, 2.0)


## Quit sequence: every light fades out over `seconds` and keeps a 4% silhouette
## ember. The title screen schedules its sound/caption off the same duration.
func quit_out(seconds: float = 0.9) -> void:
	_quit_total = clampf(seconds if is_finite(seconds) else 0.9, 0.05, 30.0)
	_quit_t = 0.0
	if _built:
		_refresh_energies()


func _refresh_energies() -> void:
	if not _built:
		return
	var t := _time
	var fire_boost := 1.0 + _surge * SURGE_FIRE_GAIN + _flicker_boost * SURGE_FLICKER_GAIN
	var lamp_boost := 1.0 + _flicker_boost * 0.35 + _surge * 0.10
	var fade := _fade_factor()

	if _sun != null:
		var sun_n := flicker01(t, 0.17)
		_sun.light_energy = _clamp_energy(
				_sun_base * (1.0 + _sun_amp * (sun_n - 0.5) * 2.0) * fade)
	if _shaft != null:
		# One slow cloud-shadow breath per ~11 s, 1.0 down to 0.70 (2D title contract).
		var cloud := 0.70 + 0.30 * swell01(_cloud_time, 1.7)
		var shaft_n := flicker01(t, 2.3)
		_shaft.light_energy = _clamp_energy(
				_shaft_base * cloud * (1.0 + _shaft_amp * (shaft_n - 0.5) * 2.0) * fade)
	if _furnace != null:
		_furnace.light_energy = _clamp_energy(
				_flickered(_furnace_base, 3.1, _furnace_amp) * fire_boost * fade)
	if _pit != null:
		var pit_swell := 0.85 + 0.15 * swell01(t, 5.7)
		_pit.light_energy = _clamp_energy(
				_pit_base * pit_swell * (1.0 + _pit_amp * (flicker01(t, 7.9) - 0.5) * 2.0)
				* fire_boost * fade)
	for i in _lantern_lights.size():
		var fixture := int(LANTERN_LIGHT_FIXTURES[i])
		var light := _lantern_lights[i]
		if fixture < _lantern_lit:
			var seed := 10.0 + float(i) * 1.37
			light.light_energy = _clamp_energy(
					_flickered(LANTERN_ENERGY, seed, _lantern_amp) * lamp_boost * fade)
		else:
			light.light_energy = 0.0
	for i in _brazier_lights.size():
		var seed := 20.0 + float(i) * 2.11
		_brazier_lights[i].light_energy = _clamp_energy(
				_flickered(_brazier_base[i], seed, _brazier_amp) * fire_boost * fade)


func _refresh_shader_parameters(apply_grade: bool) -> void:
	if _beam_material != null:
		if apply_grade:
			_beam_material.set_shader_parameter("beam_color", _shaft_color)
			_beam_material.set_shader_parameter("emission_energy",
					clampf(0.35 + _shaft_base * 1.4, 0.02, 16.0))
			_beam_material.set_shader_parameter("opacity", 1.0)
			_beam_material.set_shader_parameter("noise_scale", 1.15)
			_beam_material.set_shader_parameter("scroll_speed", Vector2(0.035, 0.42))
			_beam_material.set_shader_parameter("dust_density", 0.85)
			_beam_material.set_shader_parameter("radial_softness", 1.25)
			_beam_material.set_shader_parameter("end_softness", 1.6)
			_beam_material.set_shader_parameter("core_power", 1.7)
			_beam_material.set_shader_parameter("band_count", 7.0)
		_beam_material.set_shader_parameter("beam_time", _time)
		_beam_material.set_shader_parameter("cloud", 0.70 + 0.30 * swell01(_cloud_time, 1.7))
	if _molten_material != null:
		if apply_grade:
			_molten_material.set_shader_parameter("hot_color", Color(1.0, 0.74, 0.32))
			_molten_material.set_shader_parameter("mid_color", Color(1.0, 0.34, 0.09))
			_molten_material.set_shader_parameter("cool_color", Color(0.26, 0.09, 0.05))
			_molten_material.set_shader_parameter("foam_color", Color(1.0, 0.88, 0.66))
			_molten_material.set_shader_parameter("noise_scale", 0.52)
			_molten_material.set_shader_parameter("layer_ratio", 1.73)
			_molten_material.set_shader_parameter("foam_width", 0.75)
			_molten_material.set_shader_parameter("foam_strength", 1.15)
			_molten_material.set_shader_parameter("band_count", 6.0)
			_molten_material.set_shader_parameter("streak_strength", 0.55)
		var heat := clampf(_pit_base / maxf(PIT_ENERGY_SCALE, 0.0001), 0.0, 2.0)
		_molten_material.set_shader_parameter("heat", heat)
		_molten_material.set_shader_parameter("emission_energy",
				clampf(0.8 + heat * 1.6, 0.25, 16.0))
		_molten_material.set_shader_parameter("flow_speed", 0.15 + 0.35 * minf(heat, 1.5))
		_molten_material.set_shader_parameter("molten_time", _time)


func _fade_factor() -> float:
	if _quit_total <= 0.0:
		return 1.0
	var k := clampf(_quit_t / _quit_total, 0.0, 1.0)
	return lerpf(1.0, 0.04, k)


func _flickered(base: float, seed: float, amp: float) -> float:
	if base <= 0.0:
		return 0.0
	var n := flicker01(_time, seed)
	return base * (1.0 + amp * (n - 0.5) * 2.0)


static func _clamp_energy(value: float) -> float:
	if not is_finite(value):
		return 0.0
	return clampf(value, 0.0, 64.0)


# ---------------------------------------------------------------------------
# Pure noise (deterministic, no accumulated random floats)
# ---------------------------------------------------------------------------

## Fast fire flicker in 0..1; a pure function of (time, seed). Two sines plus a
## whisper of a third give an irregular but perfectly repeatable flame.
static func flicker01(time: float, seed: float) -> float:
	if not is_finite(time) or not is_finite(seed):
		return 0.5
	var t := time + seed * 13.37
	var v := 0.5 \
			+ 0.28 * sin(t * 1.93 + seed * 3.1) \
			+ 0.17 * sin(t * 4.11 + seed * 7.7 + 1.3) \
			+ 0.05 * sin(t * 8.37 + seed * 2.3 + 2.6)
	return clampf(v, 0.0, 1.0)


## Slow 11 s swell in 0..1 used by the light shaft cloud shadow and the river.
static func swell01(time: float, seed: float) -> float:
	if not is_finite(time) or not is_finite(seed):
		return 0.5
	var t := time * (TAU / 11.0) + seed * 4.31
	var v := 0.5 \
			+ 0.32 * sin(t) \
			+ 0.13 * sin(t * 0.53 + 1.7) \
			+ 0.05 * sin(t * 2.11 + seed)
	return clampf(v, 0.0, 1.0)


# ---------------------------------------------------------------------------
# Grade helpers (tolerant readers: a missing/mistyped key never produces NaN)
# ---------------------------------------------------------------------------

func _num(grade: Dictionary, keys: Array, fallback: float) -> float:
	for key in keys:
		var value: Variant = grade.get(key)
		if value is float:
			var number: float = value
			if is_finite(number):
				return number
		elif value is int:
			return float(value)
	return fallback


func _col(grade: Dictionary, keys: Array, fallback: Color) -> Color:
	for key in keys:
		var value: Variant = grade.get(key)
		if value is Color:
			return _safe_color(value, fallback)
		elif value is Vector3:
			return _safe_color(Color(value.x, value.y, value.z, 1.0), fallback)
	return fallback


func _key(grade: Dictionary, keys: Array, fallback: StringName) -> StringName:
	for key in keys:
		var value: Variant = grade.get(key)
		if value is StringName:
			return value
		elif value is String:
			return StringName(value)
	return fallback


static func _safe_color(value: Color, fallback: Color) -> Color:
	if not (is_finite(value.r) and is_finite(value.g) and is_finite(value.b)):
		return fallback
	return Color(clampf(value.r, 0.0, 64.0), clampf(value.g, 0.0, 64.0),
			clampf(value.b, 0.0, 64.0), 1.0)


static func _scale_color(base: Color, tint: Color) -> Color:
	return Color(
			clampf(base.r * tint.r, 0.0, 64.0),
			clampf(base.g * tint.g, 0.0, 64.0),
			clampf(base.b * tint.b, 0.0, 64.0),
			1.0)


static func _normalize_quality(quality: StringName) -> StringName:
	if quality == QUALITY_BALANCED:
		return QUALITY_BALANCED
	if quality == QUALITY_LOW:
		return QUALITY_LOW
	return QUALITY_HIGH


## The safe cold-forge grade, i.e. what `apply({})` behaves like. Tools and tests use
## this to prove that a missing key never changes the outcome.
static func default_grade() -> Dictionary:
	return {
		"variant": DEF_VARIANT,
		"grade_id": DEF_GRADE_ID,
		"exposure": DEF_EXPOSURE,
		"white": DEF_WHITE,
		"sun_color": DEF_SUN_COLOR,
		"sun_energy": DEF_SUN_ENERGY,
		"furnace_color": DEF_FURNACE_COLOR,
		"furnace_energy": DEF_FURNACE_ENERGY,
		"pit_energy": DEF_PIT_ENERGY,
		"fog_density": DEF_FOG_DENSITY,
		"fog_albedo": DEF_FOG_ALBEDO,
		"fog_emission": DEF_FOG_EMISSION,
		"glow_intensity": DEF_GLOW_INTENSITY,
		"grade_tint": DEF_GRADE_TINT,
		"lantern_lit": DEF_LANTERN_LIT,
		"ambient": DEF_AMBIENT,
		"shaft": DEF_SHAFT,
		"shaft_color": DEF_SHAFT_COLOR,
		"forge": DEF_FORGE,
		"lantern": DEF_LANTERN_COLOR,
		"flicker": DEF_FLICKER,
	}


# ---------------------------------------------------------------------------
# Read-only surface for the title world / tests
# ---------------------------------------------------------------------------

func environment() -> Environment:
	return _env


func world_environment() -> WorldEnvironment:
	return _world_env


## Every light of the rig (12 fixtures), in creation order.
func lights() -> Array[Light3D]:
	var out: Array[Light3D] = []
	out.append_array(_lights)
	return out


## The lights that currently cast a shadow (the quality tier decides).
func shadow_casters() -> Array[Light3D]:
	var out: Array[Light3D] = []
	out.append_array(_shadow_lights)
	return out


func light_budget() -> Dictionary:
	return {
		"fixtures": _lights.size(),
		"max_lights": MAX_LIGHTS,
		"planned_fixtures": LIGHT_FIXTURES,
		"shadow_casters": _shadow_lights.size(),
		"max_shadow_casters": MAX_SHADOW_CASTERS,
		"shadow_map_hints": SHADOW_MAP_HINTS,
	}


## The grade's ambient term, for `TitleKit.set_ambient()` (see the member docs).
func ambient_color() -> Color:
	return _ambient_color


func ambient_energy() -> float:
	return _ambient_energy


func sun_light() -> DirectionalLight3D:
	return _sun


func shaft_light() -> SpotLight3D:
	return _shaft


func furnace_light() -> OmniLight3D:
	return _furnace


func pit_light() -> OmniLight3D:
	return _pit


func lantern_lights() -> Array[OmniLight3D]:
	var out: Array[OmniLight3D] = []
	out.append_array(_lantern_lights)
	return out


func brazier_lights() -> Array[OmniLight3D]:
	var out: Array[OmniLight3D] = []
	out.append_array(_brazier_lights)
	return out


func beam_material() -> ShaderMaterial:
	return _beam_material


func molten_material() -> ShaderMaterial:
	return _molten_material


func grade() -> Dictionary:
	return _grade.duplicate(true)


func quality() -> StringName:
	return _quality


func grade_id() -> StringName:
	return _grade_id


func variant() -> StringName:
	return _variant


func lantern_lit() -> int:
	return _lantern_lit


func time() -> float:
	return _time


func built() -> bool:
	return _built


func cloud_scale() -> float:
	return _cloud_scale


func is_dark() -> bool:
	return _quit_total > 0.0 and _quit_t >= _quit_total


## `volumetric_fog_light_energy` control: scales every light's own
## `light_volumetric_fog_energy` (Forward+ drives volumetric lighting per light, the
## Environment itself has no such property). Clamped 0..4.
func set_volumetric_light_energy(value: float) -> void:
	_volumetric_light_energy = clampf(value if is_finite(value) else 1.0, 0.0, 4.0)
	if _built:
		_apply_volumetric_light_energy()


func volumetric_light_energy() -> float:
	return _volumetric_light_energy
