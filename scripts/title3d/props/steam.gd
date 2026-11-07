extends "res://scripts/title3d/props/title_prop3d.gd"
## Chimney steam for the 3D forge hall (2D: the STEAM puffs of
## scripts/ui/title_sparks.gd, docs/title-live-scene.md §6.1).
##
## Two GPUParticles3D columns: the forge stack (TitleLayout FORGE_STACK_BASE ->
## FORGE_STACK_TOP_Y) and a cooler vent on the left machine deck. The 16x16 procedural
## smoke texture is nearest sampled and alpha blended (not additive), depth-tested so
## the roof trusses cut through it. The rate follows the grade's `steam_rate` (0..1,
## `cold`/`snuff` 0) through `amount_ratio`, so a hot act breathes a lot and a dead
## forge none.
##
## Node contract: two emitters, built once; apply_grade only writes emitting/ratio.

const FORGE_STACK_BASE := Vector3(12.6, 7.6, -11.6)
const FORGE_STACK_TOP_Y := 17.2
const LEFT_VENT := Vector3(-12.4, 6.4, -10.0)
const STACK_AMOUNT := 40
const VENT_AMOUNT := 26

var _stack: GPUParticles3D
var _vent: GPUParticles3D
var _rate := 0.0


func _build() -> void:
	var stack_base := LV3("FORGE_STACK_BASE", FORGE_STACK_BASE)
	var stack_top := L("FORGE_STACK_TOP_Y", FORGE_STACK_TOP_Y)
	_stack = _emitter("SteamStack", STACK_AMOUNT, 5.0, 1.1,
			Vector3(stack_base.x, stack_top, stack_base.z))
	var stack_pm := GEO.upward_process_material(14.0)
	stack_pm.emission_box_extents = Vector3(0.9, 0.2, 0.9)
	stack_pm.initial_velocity_min = 0.6
	stack_pm.initial_velocity_max = 1.3
	stack_pm.gravity = Vector3(0.0, 0.10, 0.0)
	stack_pm.scale_min = 1.4
	stack_pm.scale_max = 3.2
	stack_pm.color_ramp = _steam_ramp(0.55)
	_stack.process_material = stack_pm
	_vent = _emitter("SteamVent", VENT_AMOUNT, 4.0, 0.85,
			LV3("LEFT_VENT", LEFT_VENT))
	var vent_pm := GEO.upward_process_material(20.0)
	vent_pm.emission_box_extents = Vector3(0.5, 0.15, 0.5)
	vent_pm.initial_velocity_min = 0.35
	vent_pm.initial_velocity_max = 0.8
	vent_pm.gravity = Vector3(0.15, 0.12, 0.0)
	vent_pm.scale_min = 1.0
	vent_pm.scale_max = 2.2
	vent_pm.color_ramp = _steam_ramp(0.42)
	_vent.process_material = vent_pm
	_apply_grade()
	_sync()


func _emitter(node_name: String, amount: int, lifetime: float, size_m: float,
		at: Vector3) -> GPUParticles3D:
	var particles := GEO.particles_node(node_name, amount, lifetime, GEO.pixel_texture(1),
			size_m, false)
	particles.position = at
	particles.visibility_aabb = AABB(Vector3(-16.0, -6.0, -20.0), Vector3(32.0, 30.0, 32.0))
	add_child(particles)
	return particles


## Cool grey-white smoke that fades out as it rises; `peak` is the maximum alpha.
func _steam_ramp(peak: float) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.25, 0.7, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.86, 0.84, 0.82, 0.0),
		Color(0.82, 0.80, 0.79, peak),
		Color(0.66, 0.65, 0.66, peak * 0.55),
		Color(0.5, 0.5, 0.54, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	return ramp


func _apply_grade() -> void:
	_rate = g_float("steam_rate", g_float("steam", _rate))
	if is_built():
		_sync()


func _sync() -> void:
	if _stack == null:
		return
	var ratio := clampf(_rate, 0.0, 1.0)
	var emit := ratio > 0.015
	_stack.emitting = emit
	_stack.amount_ratio = ratio
	_vent.emitting = emit
	_vent.amount_ratio = clampf(ratio * 0.7, 0.0, 1.0)
	var speed := clampf(0.75 + 0.35 * heat01(), 0.6, 1.2)
	_stack.speed_scale = speed
	_vent.speed_scale = speed * 0.9


# ------------------------------------------------------------ test helpers ----

func rate() -> float:
	return _rate


func emitter_count() -> int:
	return 2


func stack_ratio() -> float:
	return _stack.amount_ratio if _stack != null else 0.0


func vent_ratio() -> float:
	return _vent.amount_ratio if _vent != null else 0.0


func emitting() -> bool:
	return (_stack != null and _stack.emitting) or (_vent != null and _vent.emitting)


func _snapshot_into(out: Dictionary) -> void:
	out["rate"] = snappedf(_rate, 0.000001)
	out["stack"] = snappedf(stack_ratio(), 0.000001)
	out["vent"] = snappedf(vent_ratio(), 0.000001)
