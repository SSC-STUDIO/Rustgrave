extends "res://scripts/title3d/props/title_prop3d.gd"
## Far lever trip-hammer on the right machine deck (2D: scripts/ui/title_hammer.gd,
## docs/title-live-scene.md §6.1).
##
## One 3.7 s cycle at heat 1.0, ported from the 2D timing table:
##   0..0.6 raise -> hold -> from 2.4 accelerate down -> 2.52 hit the anvil
##   (`fired("strike")` + spark burst) -> 0.18 s rebound -> rest until 3.7.
## The anvil billet flashes white-hot on the strike and cools to ember orange at
## 0.45/s; at a snuffed forge (heat < 0.06) the hammer freezes raised and the
## billet stays cold. `strike_now()` is the 'trial' menu reaction.
##
## Node contract: rig built once under HAMMER_POS (TitleLayout); advance() only
## writes pivot rotations, spark sprite transforms and glow tints — no new nodes.

const T_RAISE := 0.6
const T_FALL := 2.4
const T_HIT := 2.52
const T_REBOUND := 0.18
const T_END := 3.7
## Start in the falling section: the first strike is visible right after the intro.
const START_AT := 2.40
## The arm hangs from the bearing block; 0 = raised, 1 = head on the billet.
const ARM_RAISED_DEG := 40.0
const SPARK_COUNT := 12
## The forge-hall hammer is far away (z = -15.5), so it is a ~2.4 m machine.
const HAMMER_POS := Vector3(10.6, 1.35, -15.5)

var _rig: Node3D
var _arm: Node3D
var _head: MeshInstance3D
var _billet_cold: MeshInstance3D
var _billet_hot: MeshInstance3D
var _billet_glow: MeshInstance3D
var _flash_glow: MeshInstance3D
var _sparks: Array[MeshInstance3D] = []
var _spark_pos := PackedVector3Array()
var _spark_vel := PackedVector3Array()
var _spark_age := PackedFloat32Array()
var _spark_span := PackedFloat32Array()
var _spark_alive := PackedByteArray()

var _ct := START_AT
var _prev_ct := START_AT
var _head_t := 0.0
var _billet := 0.0
var _flash := 0.0
var _strikes := 0
var _requests := 0
var _force := false


func _build() -> void:
	var at := LV3("HAMMER_POS", HAMMER_POS)
	_rig = Node3D.new()
	_rig.name = "Rig"
	_rig.position = at
	add_child(_rig)
	# anvil + pedestal + column + bearing block (local 0 = anvil top face)
	var parts: Array = []
	parts.append(GEO.box(Vector3(1.6, 0.34, 1.0), Vector3(0.0, -0.17, 0.0), IRON))
	parts.append(GEO.box(Vector3(1.1, 0.20, 0.72), Vector3(0.0, 0.12, 0.0), IRON_LIGHT))
	parts.append(GEO.box(Vector3(0.9, 0.62, 0.54), Vector3(0.0, -0.66, 0.0), IRON_DARK))
	parts.append(GEO.box(Vector3(1.3, 0.22, 0.8), Vector3(0.0, -1.02, 0.0), IRON))
	parts.append(GEO.box(Vector3(0.28, 2.3, 0.28), Vector3(1.05, 0.72, 0.0), IRON_DARK))
	parts.append(GEO.box(Vector3(0.52, 0.20, 0.52), Vector3(1.05, 1.92, 0.0), IRON))
	parts.append(GEO.box(Vector3(1.0, 0.16, 0.26), Vector3(1.05, 2.06, 0.0), IRON_LIGHT))
	parts.append(GEO.box(Vector3(0.22, 0.10, 0.22), Vector3(0.0, 0.25, 0.0), IRON_DARK))
	var stand := add_mesh(parts, GEO.mat(0), "Stand", Vector3.ZERO, _rig)
	GEO.outline(stand, 1.0)
	# lever arm swings around the bearing block
	_arm = Node3D.new()
	_arm.name = "Arm"
	_arm.position = Vector3(1.05, 2.02, 0.0)
	_rig.add_child(_arm)
	var arm_parts: Array = []
	arm_parts.append(GEO.box(Vector3(1.6, 0.16, 0.24), Vector3(-0.8, 0.0, 0.0), IRON_LIGHT))
	arm_parts.append(GEO.box(Vector3(0.26, 0.12, 0.18), Vector3(-1.55, 0.0, 0.0), IRON))
	var arm_mi := add_mesh(arm_parts, GEO.mat(0), "Beam", Vector3.ZERO, _arm)
	GEO.outline(arm_mi, 1.0)
	# head hangs under the arm end and is kept upright in _sync()
	var head_parts: Array = []
	head_parts.append(GEO.box(Vector3(0.52, 0.42, 0.66), Vector3.ZERO, IRON))
	head_parts.append(GEO.box(Vector3(0.56, 0.10, 0.70), Vector3(0.0, 0.22, 0.0), IRON_LIGHT))
	head_parts.append(GEO.box(Vector3(0.12, 0.08, 0.12), Vector3(-0.22, -0.22, 0.0), IRON_DARK))
	_head = add_mesh(head_parts, GEO.mat(0), "HammerHead", Vector3(-1.62, -0.34, 0.0), _arm)
	GEO.outline(_head, 1.0)
	# billet: a cold lit block and a hot emissive block, toggled by temperature
	var cold := add_mesh([GEO.box(Vector3(0.52, 0.18, 0.30), Vector3.ZERO, STEEL_DARK)],
			GEO.mat(0), "BilletCold", Vector3(0.0, 0.09, 0.0), _rig)
	_billet_cold = cold
	var hot := MeshInstance3D.new()
	hot.name = "BilletHot"
	hot.mesh = GEO.merge([GEO.box(Vector3(0.52, 0.18, 0.30), Vector3.ZERO, HOT, Vector3.ZERO, 1.0)])
	hot.material_override = GEO.mat(GEO.EMISSIVE)
	hot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hot.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	hot.position = Vector3(0.0, 0.09, 0.0)
	hot.visible = false
	_rig.add_child(hot)
	_billet_hot = hot
	_billet_glow = GEO.glow_quad(0.9)
	_billet_glow.name = "BilletGlow"
	_billet_glow.position = Vector3(0.0, 0.24, 0.35)
	_rig.add_child(_billet_glow)
	_flash_glow = GEO.glow_quad(2.4)
	_flash_glow.name = "Flash"
	_flash_glow.position = Vector3(0.0, 0.30, 0.4)
	_rig.add_child(_flash_glow)
	# preallocated spark sprites (no nodes created on a strike)
	_spark_pos.resize(SPARK_COUNT)
	_spark_vel.resize(SPARK_COUNT)
	_spark_age.resize(SPARK_COUNT)
	_spark_span.resize(SPARK_COUNT)
	_spark_alive.resize(SPARK_COUNT)
	for i in SPARK_COUNT:
		_spark_alive[i] = 0
		_spark_span[i] = 0.0
		_spark_age[i] = 0.0
		var spark := GEO.sprite_quad(0.16, 0.16, GEO.pixel_texture(2))
		spark.name = "Spark%d" % i
		spark.visible = false
		_rig.add_child(spark)
		_sparks.append(spark)
	_apply_grade()
	_sync()


func _apply_grade() -> void:
	if is_built():
		_sync()


## Cycle time multiplier: 0 at a snuffed forge, clamped to [0.3, 1.3] like the 2D prop.
func speed() -> float:
	return speed_scale(0.3, 1.3)


## The billet's residual heat between strikes; the forge heat decides how warm it sits.
func _billet_floor() -> float:
	var h := heat01()
	if h <= 0.08:
		return 0.0
	return 0.28 + 0.35 * h


func _tick(dt: float) -> void:
	_billet = move_toward(_billet, _billet_floor(), dt * 0.45)
	_flash = move_toward(_flash, 0.0, dt * 2.2)
	_update_sparks(dt)
	var sp := speed()
	if sp <= 0.0:
		_head_t = 0.0
		return
	_prev_ct = _ct
	_ct += dt * sp
	if _force and _ct >= T_RAISE and _ct < T_FALL:
		_ct = T_FALL
	if _ct >= T_FALL:
		_force = false
	if _prev_ct < T_HIT and _ct >= T_HIT:
		_hit()
	if _ct >= T_END:
		_ct -= T_END
		_prev_ct = _ct
	_head_t = head_at(_ct)


func _hit() -> void:
	_strikes += 1
	_billet = 1.0
	_flash = 1.0
	_burst_sparks()
	emit_fired(&"strike", {"position": _rig.global_position + Vector3(0.0, 0.2, 0.0),
			"count": 9, "strikes": _strikes})


## Deterministic spark burst from the anvil face (pooled sprites, no allocation).
func _burst_sparks() -> void:
	for i in SPARK_COUNT:
		if _spark_alive[i] == 1:
			continue
		var ang := rng.randf() * TAU
		var up := 1.6 + rng.randf() * 1.8
		var out := 0.6 + rng.randf() * 1.2
		_spark_pos[i] = Vector3(0.0, 0.12, 0.0)
		_spark_vel[i] = Vector3(cos(ang) * out, up, sin(ang) * out * 0.6)
		_spark_age[i] = 0.0
		_spark_span[i] = 0.45 + rng.randf() * 0.35
		_spark_alive[i] = 1
		_sparks[i].visible = true
		if i >= 9:
			break


func _update_sparks(dt: float) -> void:
	for i in SPARK_COUNT:
		if _spark_alive[i] == 0:
			continue
		_spark_age[i] += dt
		if _spark_age[i] >= _spark_span[i] or _spark_pos[i].y < 0.0:
			_spark_alive[i] = 0
			_sparks[i].visible = false
			continue
		_spark_vel[i].y -= 6.5 * dt
		_spark_pos[i] += _spark_vel[i] * dt
		var fade := 1.0 - _spark_age[i] / maxf(_spark_span[i], 0.001)
		set_sprite(_sparks[i], Color(HOT.r, HOT.g, HOT.b, fade))


func _sync() -> void:
	if _arm == null:
		return
	var angle := -deg_to_rad(ARM_RAISED_DEG) * (1.0 - clampf(_head_t, 0.0, 1.0))
	_arm.rotation.z = angle
	# keep the head plumb under the arm end while the beam swings
	_head.rotation.z = -angle
	for i in SPARK_COUNT:
		if _spark_alive[i] == 1:
			_sparks[i].position = _spark_pos[i]
	var warm := heat01()
	var level := clampf(_billet, 0.0, 1.0)
	_billet_cold.visible = level < 0.30
	_billet_hot.visible = level >= 0.30
	_billet_hot.scale = Vector3(1.0, 1.0, 1.0) * (0.86 + 0.18 * level)
	var billet_alpha := clampf(level * 0.75 + _flash, 0.0, 1.0) * maxf(warm, 0.3)
	set_glow(_billet_glow, Color(1.0, 0.55, 0.2, 0.35 * billet_alpha))
	set_glow(_flash_glow, Color(1.0, 0.93, 0.8, 0.85 * _flash))


## Head position: 0 = fully raised, 1 = pressed onto the billet (2D timing table).
static func head_at(ct: float) -> float:
	if ct < T_RAISE:
		var c := clampf(ct / T_RAISE, 0.0, 1.0)
		return 1.0 - c * c * (3.0 - 2.0 * c)
	if ct < T_FALL:
		return 0.0
	if ct < T_HIT:
		return pow((ct - T_FALL) / (T_HIT - T_FALL), 1.6)
	if ct < T_HIT + T_REBOUND:
		return 1.0 - 0.3 * sin(PI * (ct - T_HIT) / T_REBOUND)
	return 1.0


## 'trial' menu reaction: strike now (ignored at a snuffed forge, which still counts
## the request like the 2D prop so tests/tools can observe the input).
func strike_now() -> void:
	_requests += 1
	if speed() <= 0.0:
		return
	if _ct >= T_HIT:
		_ct = 0.0
		_prev_ct = 0.0
	_force = true
	if is_built():
		_sync()


# ------------------------------------------------------------ test helpers ----

func strikes() -> int:
	return _strikes


func strike_requests() -> int:
	return _requests


func head() -> float:
	return _head_t


func billet_level() -> float:
	return _billet


func is_frozen() -> bool:
	return speed() <= 0.0


func spark_count() -> int:
	var n := 0
	for i in SPARK_COUNT:
		n += int(_spark_alive[i])
	return n


func _snapshot_into(out: Dictionary) -> void:
	out["ct"] = snappedf(_ct, 0.000001)
	out["head"] = snappedf(_head_t, 0.000001)
	out["strikes"] = _strikes
	out["billet"] = snappedf(_billet, 0.000001)
