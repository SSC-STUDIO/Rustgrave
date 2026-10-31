extends "res://scripts/title3d/props/title_prop3d.gd"
## Left-bank gear train for the 3D forge hall (2D: scripts/ui/title_gear.gd,
## docs/title-live-scene.md §6.1).
##
## The big and small wheels are a real meshing pair: the small one is not integrated on
## its own clock; its angle is locked to the big wheel by the tooth ratio (16/12) with
## a half-tooth offset, so a tooth always sits in a gap while the pair turns. Speed comes
## straight from the grade (`gear_speed` 0..1.3: cold 0.12, act4 1.3, snuff 0). A hot
## forge lights an optional emissive rim + halo under each wheel ("heat deformation"
## tell) that breathes with the furnace, so the machinery reads with the hall.
##
## Coordinates come from TitleLayout (GEAR_BIG / GEAR_SMALL / GEAR_*_RADIUS /
## GEAR_*_TEETH / GEAR_DEPTH): XY plane, thickness along Z, facing the camera.
##
## Node contract: two pivots (one per gear), each with body / hot rim / halo children,
## all built in setup. advance() only writes rotation, visibility, scale and halo tint.

const BIG_TEETH := 16
const SMALL_TEETH := 12
const BIG_RADIUS := 2.6
const SMALL_RADIUS := 1.5
const GEAR_DEPTH := 0.7
## Degrees per second at gear_speed = 1.0. Slow: this is machinery, not a clock.
const BIG_DEG_PER_SEC := 8.0

var _big: Node3D
var _small: Node3D
var _big_rim: MeshInstance3D
var _small_rim: MeshInstance3D
var _big_glow: MeshInstance3D
var _small_glow: MeshInstance3D
## Big-gear angle (radians). The small gear is derived from it, never integrated alone.
var _angle := 0.0
var _speed_mult := 0.0


func _build() -> void:
	var big_at := LV3("GEAR_BIG", Vector3(-11.0, 3.7, -3.0))
	var small_at := LV3("GEAR_SMALL", Vector3(-8.9, 7.15, -3.0))
	_speed_mult = g_float("gear_speed", clampf(heat, 0.0, 1.3))
	_big = _gear_rig("BigGear", big_at, L("GEAR_BIG_TEETH", float(BIG_TEETH)),
			L("GEAR_BIG_RADIUS", BIG_RADIUS), true)
	_small = _gear_rig("SmallGear", small_at, L("GEAR_SMALL_TEETH", float(SMALL_TEETH)),
			L("GEAR_SMALL_RADIUS", SMALL_RADIUS), false)
	_apply_grade()
	_sync()


## One gear: pivot at the layout centre, body mesh + emissive hot rim + additive halo.
func _gear_rig(node_name: String, at: Vector3, teeth_value: float, radius: float,
		is_big: bool) -> Node3D:
	var teeth := maxi(int(teeth_value), 6)
	var pivot := Node3D.new()
	pivot.name = node_name
	pivot.position = at
	add_child(pivot)
	var depth := L("GEAR_DEPTH", GEAR_DEPTH)
	var hub_radius := radius * 0.26
	var disc_radius := radius * 0.78
	# title-kit's deterministic spur-gear mesh (XY plane, thickness along Z); it bakes
	# the teeth, rim and raised hub shading, so the wheel reads at title distance.
	var gear_mesh: ArrayMesh = GEO.shape_gear(radius, teeth, depth, hub_radius, IRON)
	var body := add_mesh([GEO.part_mesh(gear_mesh, Transform3D.IDENTITY)], GEO.mat(0),
			"Body", Vector3.ZERO, pivot)
	GEO.outline(body, 1.0)
	# hot rim: ten short bars on the web that only glow while the forge is hot
	var rim_parts: Array = []
	for k in 10:
		var a := TAU * float(k) / 10.0
		rim_parts.append(GEO.box(Vector3(radius * 0.17, radius * 0.05, depth * 0.7),
				Vector3(cos(a) * disc_radius * 0.58, sin(a) * disc_radius * 0.58, 0.0),
				HOT, Vector3(0.0, 0.0, rad_to_deg(a)), 0.9))
	var rim := MeshInstance3D.new()
	rim.name = "HotRim"
	rim.mesh = GEO.merge(rim_parts)
	rim.material_override = GEO.mat(GEO.EMISSIVE)
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rim.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	rim.visible = false
	pivot.add_child(rim)
	var glow := GEO.glow_quad(radius * 2.5)
	glow.name = "Halo"
	pivot.add_child(glow)
	if is_big:
		_big_rim = rim
		_big_glow = glow
	else:
		_small_rim = rim
		_small_glow = glow
	return pivot


func _apply_grade() -> void:
	_speed_mult = g_float("gear_speed", clampf(heat, 0.0, 1.3))
	if is_built():
		_sync()


func _tick(dt: float) -> void:
	if _speed_mult <= 0.0:
		return
	_angle = fposmod(_angle + deg_to_rad(BIG_DEG_PER_SEC) * _speed_mult * dt, TAU)


func _sync() -> void:
	if _big == null:
		return
	var small_angle := small_angle_for(_angle)
	_big.rotation.z = _angle
	_small.rotation.z = small_angle
	# Emissive rim + halo: the 2D gears never emit light; the 3D pair gets a forge read.
	var hot := heat01()
	var lit := hot > 0.12
	_big_rim.visible = lit
	_small_rim.visible = lit
	var flick := 0.86 + 0.14 * sin(floorf(t * 9.0) * 2.1)
	var alpha := clampf(0.22 * hot, 0.0, 0.65) * flick * lift.r
	var warm := g_color("furnace_color", Color(1.0, 0.4, 0.14))
	set_glow(_big_glow, Color(warm.r, warm.g * 0.8, warm.b, alpha))
	set_glow(_small_glow, Color(warm.r, warm.g * 0.85, warm.b, alpha * 0.8))


## Meshing relation: the small gear turns the other way, locked by the tooth ratio,
## with a half-tooth offset so the teeth drop into the gaps.
static func small_angle_for(big_angle: float) -> float:
	return fposmod(-big_angle * float(BIG_TEETH) / float(SMALL_TEETH)
			+ PI - PI / float(SMALL_TEETH), TAU)


# ------------------------------------------------------------ test helpers ----

func big_angle() -> float:
	return _angle


func small_angle() -> float:
	return small_angle_for(_angle)


func speed_mult() -> float:
	return _speed_mult


func teeth_counts() -> Vector2i:
	return Vector2i(BIG_TEETH, SMALL_TEETH)


func _snapshot_into(out: Dictionary) -> void:
	out["angle"] = snappedf(_angle, 0.000001)
	out["speed_mult"] = _speed_mult
