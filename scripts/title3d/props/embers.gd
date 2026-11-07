extends "res://scripts/title3d/props/title_prop3d.gd"
## Rising embers for the 3D forge hall (2D: the EMBER/ASH pools of
## scripts/ui/title_sparks.gd, docs/title-live-scene.md §6.1).
##
## Two GPUParticles3D emitters: the forge mouth spits sparks up into the hall, and the
## lava chasm sheds a slower drift of ash. Both use the 8x8 procedural pixel ember
## texture, nearest sampling, additive blending and depth-tested particles (the bridge
## and wall geometry occlude them correctly). The rate is the grade's `ember_rate`
## (0..1.35, `snuff` 0), driven through `amount_ratio` so changing the grade never
## restarts the simulation.
##
## Node contract: the two emitters are built once; apply_grade only writes
## `emitting` / `amount_ratio` / `speed_scale`.

const FORGE_MOUTH := Vector3(12.2, 2.8, -6.35)
const FORGE_LIGHT_POS := Vector3(11.2, 2.6, -5.0)
const PIT_CENTER := Vector3(0.0, -5.55, -7.0)
## 2D pools were rate-driven; these caps cover the 1.35x hottest grade.
const MOUTH_AMOUNT := 72
const PIT_AMOUNT := 48
const MAX_RATE := 1.35

var _mouth: GPUParticles3D
var _pit: GPUParticles3D
var _rate := 0.0


func _build() -> void:
	_mouth = _emitter("EmbersMouth", MOUTH_AMOUNT, 2.4, 0.11,
			LV3("FORGE_LIGHT_POS", FORGE_LIGHT_POS))
	var mouth_pm := GEO.upward_process_material(22.0)
	mouth_pm.emission_box_extents = Vector3(1.2, 0.3, 0.5)
	mouth_pm.direction = Vector3(0.0, 1.0, 0.15)
	mouth_pm.spread = 22.0
	mouth_pm.initial_velocity_min = 0.5
	mouth_pm.initial_velocity_max = 1.4
	mouth_pm.gravity = Vector3(0.0, 0.45, 0.0)
	mouth_pm.scale_min = 0.6
	mouth_pm.scale_max = 1.6
	mouth_pm.color_ramp = _ember_ramp()
	_mouth.process_material = mouth_pm
	_pit = _emitter("EmbersPit", PIT_AMOUNT, 4.5, 0.10,
			LV3("PIT_CENTER", PIT_CENTER) + Vector3(0.0, 0.6, 2.0))
	var pit_pm := GEO.upward_process_material(30.0)
	pit_pm.emission_box_extents = Vector3(6.0, 0.25, 4.0)
	pit_pm.direction = Vector3(0.0, 1.0, 0.0)
	pit_pm.initial_velocity_min = 0.25
	pit_pm.initial_velocity_max = 0.7
	pit_pm.gravity = Vector3(0.0, 0.22, 0.0)
	pit_pm.scale_min = 0.4
	pit_pm.scale_max = 1.1
	pit_pm.color_ramp = _ash_ramp()
	_pit.process_material = pit_pm
	_apply_grade()
	_sync()


func _emitter(node_name: String, amount: int, lifetime: float, size_m: float,
		at: Vector3) -> GPUParticles3D:
	var particles := GEO.particles_node(node_name, amount, lifetime, GEO.pixel_texture(0),
			size_m, true)
	particles.position = at
	particles.visibility_aabb = AABB(Vector3(-14.0, -8.0, -18.0), Vector3(28.0, 28.0, 32.0))
	add_child(particles)
	return particles


## Hot core -> ember -> rust: matches the 2D `_flame_color` ramp.
func _ember_ramp() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.28, 0.58, 0.84, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 0.95, 0.78, 1.0),
		Color(1.0, 0.72, 0.3, 0.95),
		Color(1.0, 0.45, 0.14, 0.7),
		Color(0.8, 0.28, 0.1, 0.35),
		Color(0.4, 0.1, 0.05, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	return ramp


## Ash drifts dimmer and greyer than the forge sparks.
func _ash_ramp() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.4, 0.75, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.8, 0.76, 0.7, 0.55),
		Color(0.62, 0.56, 0.52, 0.4),
		Color(0.42, 0.38, 0.4, 0.22),
		Color(0.3, 0.26, 0.3, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	return ramp


func _apply_grade() -> void:
	_rate = g_float("ember_rate", g_float("embers", _rate))
	if is_built():
		_sync()


func _sync() -> void:
	if _mouth == null:
		return
	var ratio := clampf(_rate / MAX_RATE, 0.0, 1.0)
	var hot := maxf(heat01(), 0.15)
	var emit := ratio > 0.015
	_mouth.emitting = emit
	_mouth.amount_ratio = clampf(ratio * hot, 0.0, 1.0)
	_pit.emitting = emit
	_pit.amount_ratio = clampf(ratio * (0.35 + 0.65 * hot), 0.0, 1.0)
	# a dying fire's sparks slow down; the hottest hall drifts them faster
	var speed := clampf(0.7 + 0.5 * hot, 0.6, 1.25)
	_mouth.speed_scale = speed
	_pit.speed_scale = speed * 0.8


# ------------------------------------------------------------ test helpers ----

func rate() -> float:
	return _rate


func emitter_count() -> int:
	return 2


func mouth_ratio() -> float:
	return _mouth.amount_ratio if _mouth != null else 0.0


func pit_ratio() -> float:
	return _pit.amount_ratio if _pit != null else 0.0


func emitting() -> bool:
	return (_mouth != null and _mouth.emitting) or (_pit != null and _pit.emitting)


func _snapshot_into(out: Dictionary) -> void:
	out["rate"] = snappedf(_rate, 0.000001)
	out["mouth"] = snappedf(mouth_ratio(), 0.000001)
	out["pit"] = snappedf(pit_ratio(), 0.000001)
