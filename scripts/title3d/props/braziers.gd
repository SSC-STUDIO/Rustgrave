extends "res://scripts/title3d/props/title_prop3d.gd"
## Two bridge-head braziers (2D: scripts/ui/title_braziers.gd,
## docs/title-live-scene.md §6.1).
##
## Each brazier is a forged bowl standing on the deck in front of the knight, with a
## coal bed, a GPUParticles3D flame (8x8 pixel ember texture, nearest sampled, additive
## and depth-tested so the bridge geometry occludes it) and an additive halo. The two
## bowls light up with progress (grade `brazier_left` / `brazier_right`, 0 = cold,
## 1 = lit, >1 = brightest at the 'keep' ending) and `boost_braziers()` is the 'arena'
## menu reaction: cold bowls jump alight for a moment, lit ones flare.
##
## Node contract: both rigs built once; apply_grade/advance only set the particle
## `amount_ratio`/`emitting`, halo tint and coal visibility.

const BRAZIER_LEFT := Vector3(-2.6, 0.0, 1.6)
const BRAZIER_RIGHT := Vector3(-0.9, 0.0, 1.6)
const BOWL_TOP_Y := 0.92
## 2D pool: 26 particles per brazier; the GPUParticles3D draws the same count max.
const FLAME_AMOUNT := 26
const FLAME_LIFETIME := 0.85
const GLOW_SIZE := 2.6
const EMBER_TEX := 0

var _rigs: Array[Node3D] = []
var _flames: Array[GPUParticles3D] = []
var _glows: Array[MeshInstance3D] = []
var _coals: Array[MeshInstance3D] = []
var _cold_glints: Array[MeshInstance3D] = []
var _levels: Array[float] = [0.0, 0.0]
var _boost := 0.0


func _build() -> void:
	_brazier(0, LV3("BRAZIER_LEFT", BRAZIER_LEFT))
	_brazier(1, LV3("BRAZIER_RIGHT", BRAZIER_RIGHT))
	_apply_grade()
	_sync()


func _brazier(index: int, at: Vector3) -> void:
	var rig := Node3D.new()
	rig.name = "Brazier%d" % index
	rig.position = at
	add_child(rig)
	_rigs.append(rig)
	# three legs + bowl + rim + handling ring
	var parts: Array = []
	for k in 3:
		var a := TAU * float(k) / 3.0
		parts.append(GEO.box(Vector3(0.10, 0.72, 0.10),
				Vector3(cos(a) * 0.26, 0.36, sin(a) * 0.26), IRON_DARK,
				Vector3(0.0, rad_to_deg(a), 0.0)))
	parts.append(GEO.box(Vector3(0.72, 0.10, 0.72), Vector3(0.0, 0.16, 0.0), IRON))
	parts.append(GEO.cyl(0.44, 0.26, 10, Vector3(0.0, 0.40, 0.0), IRON))
	parts.append(GEO.cyl(0.50, 0.08, 10, Vector3(0.0, 0.56, 0.0), IRON_LIGHT))
	for k in 4:
		var a := TAU * float(k) / 4.0
		parts.append(GEO.box(Vector3(0.06, 0.34, 0.06),
				Vector3(cos(a) * 0.30, 0.76, sin(a) * 0.30), IRON_DARK))
	var stand := add_mesh(parts, GEO.mat(0), "Stand", Vector3.ZERO, rig)
	GEO.outline(stand, 1.0)
	# glowing coal bed (only visible when the bowl is alive)
	var coals := MeshInstance3D.new()
	coals.name = "Coals"
	coals.mesh = GEO.merge([GEO.cyl(0.36, 0.06, 10, Vector3.ZERO, HOT, Vector3.ZERO, 1.0)])
	coals.material_override = GEO.mat(GEO.EMISSIVE)
	coals.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	coals.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	coals.position = Vector3(0.0, 0.80, 0.0)
	rig.add_child(coals)
	_coals.append(coals)
	var cold_glint := GEO.glow_quad(0.55)
	cold_glint.name = "EmberGlint"
	cold_glint.position = Vector3(0.0, 0.82, 0.22)
	rig.add_child(cold_glint)
	_cold_glints.append(cold_glint)
	# flame particles
	var flame := GEO.particles_node("Flames", FLAME_AMOUNT, FLAME_LIFETIME,
			GEO.pixel_texture(EMBER_TEX), 0.13, true)
	flame.position = Vector3(0.0, BOWL_TOP_Y, 0.0)
	var pm := GEO.upward_process_material(10.0)
	pm.emission_box_extents = Vector3(0.24, 0.03, 0.24)
	pm.initial_velocity_min = 0.35
	pm.initial_velocity_max = 0.85
	pm.gravity = Vector3(0.0, 0.55, 0.0)
	pm.scale_min = 0.7
	pm.scale_max = 1.5
	pm.color_ramp = _flame_ramp()
	flame.process_material = pm
	flame.visibility_aabb = AABB(Vector3(-1.5, -0.5, -1.5), Vector3(3.0, 3.5, 3.0))
	rig.add_child(flame)
	_flames.append(flame)
	var glow := GEO.glow_quad(GLOW_SIZE)
	glow.name = "Halo"
	glow.position = Vector3(0.0, BOWL_TOP_Y + 0.15, 0.35)
	rig.add_child(glow)
	_glows.append(glow)


## White-hot core -> ember -> rust-red -> out, like the 2D _flame_color ramp.
func _flame_ramp() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.22, 0.46, 0.72, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 0.97, 0.82, 1.0),
		Color(1.0, 0.76, 0.29, 0.95),
		Color(1.0, 0.52, 0.16, 0.8),
		Color(0.82, 0.32, 0.10, 0.45),
		Color(0.45, 0.16, 0.06, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	return ramp


func _apply_plan() -> void:
	var braziers = _plan.get("braziers", null)
	if braziers is Array and braziers.size() >= 2:
		set_levels(float(braziers[0]), float(braziers[1]))


func _apply_grade() -> void:
	if _grade.has("brazier_left") or _grade.has("brazier_right"):
		set_levels(g_float("brazier_left", _levels[0]), g_float("brazier_right", _levels[1]))
	if is_built():
		_sync()


func set_levels(first: float, second: float) -> void:
	_levels[0] = first
	_levels[1] = second
	if is_built():
		_sync()


## Effective bowl brightness including the menu boost (2D `level_of`).
func level_of(index: int) -> float:
	var base := _levels[clampi(index, 0, 1)]
	return maxf(base * (1.0 + _boost * 0.8), _boost * 0.35)


## 'arena' menu reaction: both bowls flare (even cold ones jump alight for a moment).
func boost_braziers() -> void:
	_boost = 1.0
	if is_built():
		_sync()


func _on_surge(strength: float) -> void:
	_boost = maxf(_boost, strength * 0.5)


func _tick(dt: float) -> void:
	_boost = move_toward(_boost, 0.0, dt * 0.55)


func _sync() -> void:
	if _flames.is_empty():
		return
	var hot := heat01()
	var flicker := g_float("brazier_flicker", 1.0)
	for i in 2:
		var level := clampf(level_of(i), 0.0, 1.4)
		var ratio := clampf(level, 0.0, 1.0) * (0.35 + 0.65 * maxf(hot, 0.25))
		var flame := _flames[i]
		flame.emitting = ratio > 0.02
		flame.amount_ratio = clampf(ratio, 0.0, 1.0)
		flame.speed_scale = clampf(0.8 + 0.4 * ratio, 0.7, 1.6)
		_coals[i].visible = level > 0.05 and hot > 0.08
		var flick := 0.86 + 0.14 * sin(floorf(t * 9.0 * flicker) * 2.1 + float(i) * 1.9)
		var alpha := clampf(0.16 + 0.34 * level, 0.0, 0.85) * flick * maxf(hot, 0.25)
		set_glow(_glows[i], Color(1.0, 0.55, 0.2, alpha))
		# a cold bowl keeps a last red glint in the coals while the hall is warm
		var glint := 0.0
		if level < 0.05 and hot > 0.1:
			glint = (0.45 + 0.35 * sin(t * 1.7 + float(i) * 2.0)) * 0.35 * hot
		set_glow(_cold_glints[i], Color(0.7, 0.18, 0.06, glint))


# ------------------------------------------------------------ test helpers ----

func levels() -> Array[float]:
	return _levels.duplicate()


func lit_count() -> int:
	var n := 0
	for level in _levels:
		if level > 0.05:
			n += 1
	return n


func brightest() -> float:
	return maxf(_levels[0], _levels[1])


func boost() -> float:
	return _boost


func flame_ratio(index: int) -> float:
	if index < 0 or index >= _flames.size():
		return 0.0
	return _flames[index].amount_ratio


func flame_emitting(index: int) -> bool:
	return index >= 0 and index < _flames.size() and _flames[index].emitting


func _snapshot_into(out: Dictionary) -> void:
	out["boost"] = snappedf(_boost, 0.000001)
	out["level0"] = snappedf(level_of(0), 0.000001)
	out["level1"] = snappedf(level_of(1), 0.000001)
