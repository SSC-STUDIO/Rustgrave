extends Node3D
## Box-built greatsword knight (余烬骑士) for the render spike. Rigid parts hang
## off pivot nodes; the walk cycle and the overhead swing are posed in code and
## can run on a 12 fps clock for a hand-animated feel.
##
## Pivot angles are pitch in degrees: positive swings a limb forward. The blade
## angle is absolute: 0 points straight up, 90 straight back, -90 straight ahead.

const KIT := preload("res://scripts/moba/view/toon_kit.gd")
const TOON_PART := preload("res://scripts/moba/view/toon_part.gd")

signal impact(at: Vector3)

const POSE_FPS := 12.0
const SWING_TIME := 0.5
const IMPACT_AT := 0.26
const REACH := 1.9
## t, sword arm, blade, body lean, lunge, ease of the segment ending here
## (0 smooth, 1 ease-out, 2 ease-in). Rest carries the blade on the shoulder.
const SWING_KEYS := [
	[0.0, 50.0, 45.0, 0.0, 0.0, 0],
	[0.16, 190.0, 10.0, 8.0, -0.12, 1],
	[0.26, 60.0, -120.0, -14.0, 0.35, 2],
	[0.5, 50.0, 45.0, 0.0, 0.0, 0],
]

var team := 0
var stepped := true
## Ground speed in m/s, set by the controller; drives the walk cycle.
var speed := 0.0
## Yaw in radians; 0 faces -Z (up the screen).
var facing := 0.0
var visual: Node3D
var body: Node3D
var leg_l: Node3D
var leg_r: Node3D
var arm_l: Node3D
var arm_r: Node3D
var sword: Node3D
var head: Node3D

var _walk_phase := 0.0
var _walk_amount := 0.0
var _swing_t := -1.0
var _impact_sent := false
var _pose_clock := 0.0


func _ready() -> void:
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	visual.add_child(KIT.blob_shadow(0.55))
	body = _pivot(visual, "Body", Vector3.ZERO)
	_build_torso()
	leg_l = _pivot(body, "LegL", Vector3(-0.17, 0.8, 0.0))
	leg_r = _pivot(body, "LegR", Vector3(0.17, 0.8, 0.0))
	_build_leg(leg_l)
	_build_leg(leg_r)
	arm_l = _pivot(body, "ArmL", Vector3(-0.47, 1.36, 0.0))
	arm_r = _pivot(body, "ArmR", Vector3(0.47, 1.36, 0.0))
	_build_arm(arm_l, false)
	_build_arm(arm_r, true)
	sword = _pivot(arm_r, "Sword", Vector3(0.0, -0.62, 0.0))
	_build_sword()
	head = _pivot(body, "Head", Vector3(0.0, 1.43, 0.0))
	_build_head()
	_apply_pose()


func attack() -> void:
	if _swing_t < 0.0:
		_swing_t = 0.0
		_impact_sent = false


func is_attacking() -> bool:
	return _swing_t >= 0.0


func face_towards(dir: Vector3, delta: float) -> void:
	if dir.length_squared() < 0.0001:
		return
	facing = lerp_angle(facing, atan2(-dir.x, -dir.z), 1.0 - exp(-14.0 * delta))


func _process(delta: float) -> void:
	var moving := speed > 0.05
	_walk_amount = move_toward(_walk_amount, 1.0 if moving else 0.0, delta * 6.0)
	if moving:
		_walk_phase = fmod(_walk_phase + delta * (2.0 + speed * 1.6), TAU)
	if _swing_t >= 0.0:
		_swing_t += delta
		if not _impact_sent and _swing_t >= IMPACT_AT:
			_impact_sent = true
			impact.emit(global_position + Vector3(-sin(facing), 0.0, -cos(facing)) * REACH)
		if _swing_t >= SWING_TIME:
			_swing_t = -1.0
	_pose_clock += delta
	if stepped and _pose_clock < 1.0 / POSE_FPS:
		return
	_pose_clock = fmod(_pose_clock, 1.0 / POSE_FPS) if stepped else 0.0
	_apply_pose()


func _apply_pose() -> void:
	var swing := sin(_walk_phase) * _walk_amount
	var bob := absf(sin(_walk_phase)) * 0.05 * _walk_amount
	var arm_deg := 50.0 + 4.0 * swing
	var blade_deg := 45.0 + 3.0 * swing
	var off_arm_deg := 10.0 - 22.0 * swing
	var lean := -5.0 * _walk_amount
	var lunge := 0.0
	if _swing_t >= 0.0:
		var key := _sample_swing(_swing_t)
		arm_deg = key[0]
		blade_deg = key[1]
		lean = key[2]
		lunge = key[3]
		off_arm_deg = lerpf(10.0, arm_deg, 0.75)
		swing *= 0.3
	leg_l.rotation.x = deg_to_rad(28.0) * swing
	leg_r.rotation.x = -deg_to_rad(28.0) * swing
	arm_l.rotation.x = deg_to_rad(off_arm_deg)
	arm_r.rotation.x = deg_to_rad(arm_deg)
	sword.rotation.x = deg_to_rad(blade_deg - arm_deg)
	body.position = Vector3(0.0, bob, -lunge)
	body.rotation.x = deg_to_rad(lean)
	visual.rotation.y = facing


func _sample_swing(t: float) -> PackedFloat32Array:
	for i in range(1, SWING_KEYS.size()):
		var b: Array = SWING_KEYS[i]
		if t > float(b[0]) and i < SWING_KEYS.size() - 1:
			continue
		var a: Array = SWING_KEYS[i - 1]
		var u := clampf((t - float(a[0])) / (float(b[0]) - float(a[0])), 0.0, 1.0)
		match int(b[5]):
			1:
				u = 1.0 - (1.0 - u) * (1.0 - u)
			2:
				u = u * u
			_:
				u = u * u * (3.0 - 2.0 * u)
		return PackedFloat32Array([
			lerpf(float(a[1]), float(b[1]), u),
			lerpf(float(a[2]), float(b[2]), u),
			lerpf(float(a[3]), float(b[3]), u),
			lerpf(float(a[4]), float(b[4]), u),
		])
	return PackedFloat32Array([50.0, 45.0, 0.0, 0.0])


func _pivot(parent: Node3D, pivot_name: String, at: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = pivot_name
	node.position = at
	parent.add_child(node)
	return node


func _part(parent: Node3D, part_name: String) -> TOON_PART:
	var part := TOON_PART.new()
	part.name = part_name
	parent.add_child(part)
	return part


func _build_torso() -> void:
	var p := _part(body, "Torso")
	p.box(Vector3(0.7, 0.6, 0.44), Vector3(0.0, 1.12, 0.0), Palette.IRON)
	p.box(Vector3(0.56, 0.3, 0.06), Vector3(0.0, 1.2, -0.24), Palette.SHADOW)
	p.box(Vector3(0.16, 0.16, 0.06), Vector3(0.0, 1.2, -0.28), Palette.EMBER, Vector3.ZERO, KIT.EMISSIVE)
	p.box(Vector3(0.76, 0.12, 0.5), Vector3(0.0, 0.86, 0.0), Palette.RUST_DARK)
	p.box(Vector3(0.62, 0.1, 0.06), Vector3(0.0, 0.86, -0.27), KIT.team_color(team))
	p.box(Vector3(0.3, 0.24, 0.42), Vector3(-0.47, 1.43, 0.0), Palette.RUST_MID)
	p.box(Vector3(0.3, 0.24, 0.42), Vector3(0.47, 1.43, 0.0), Palette.RUST_MID)
	p.box(Vector3(0.24, 0.3, 0.3), Vector3(-0.2, 0.7, -0.1), Palette.SHADOW, Vector3(8.0, 0.0, 0.0))
	p.box(Vector3(0.24, 0.3, 0.3), Vector3(0.2, 0.7, -0.1), Palette.SHADOW, Vector3(8.0, 0.0, 0.0))
	p.build()


func _build_leg(pivot: Node3D) -> void:
	var p := _part(pivot, "Leg")
	p.box(Vector3(0.24, 0.66, 0.28), Vector3(0.0, -0.33, 0.0), Palette.SHADOW)
	p.box(Vector3(0.26, 0.14, 0.3), Vector3(0.0, -0.4, -0.01), Palette.IRON)
	p.box(Vector3(0.28, 0.14, 0.4), Vector3(0.0, -0.73, -0.05), Palette.RUST_SHADOW)
	p.build()


func _build_arm(pivot: Node3D, sword_side: bool) -> void:
	var p := _part(pivot, "Arm")
	p.box(Vector3(0.2, 0.56, 0.22), Vector3(0.0, -0.28, 0.0), Palette.SHADOW)
	p.box(Vector3(0.24, 0.18, 0.26), Vector3(0.0, -0.6, 0.0), Palette.IRON if sword_side else Palette.RUST_DARK)
	p.build()


## The hand grips at the pivot; the blade runs along +Y with its width on Z so
## the edge leads the swing.
func _build_sword() -> void:
	var p := _part(sword, "Greatsword")
	p.box(Vector3(0.07, 0.3, 0.07), Vector3.ZERO, Palette.VOID)
	p.box(Vector3(0.11, 0.1, 0.11), Vector3(0.0, -0.18, 0.0), Palette.EMBER_ASH)
	p.box(Vector3(0.1, 0.08, 0.42), Vector3(0.0, 0.18, 0.0), Palette.RUST_DARK)
	p.box(Vector3(0.06, 1.4, 0.26), Vector3(0.0, 0.92, 0.0), Palette.PALE)
	p.box(Vector3(0.075, 1.1, 0.06), Vector3(0.0, 0.86, 0.0), Palette.EMBER, Vector3.ZERO, KIT.EMISSIVE)
	p.prism(Vector3(0.26, 0.26, 0.06), Vector3(0.0, 1.75, 0.0), Palette.PALE, Vector3(0.0, 90.0, 0.0))
	for i in 4:
		p.box(Vector3(0.05, 0.08, 0.06), Vector3(0.0, 0.45 + i * 0.28, 0.15), Palette.CONCRETE)
	p.build()


func _build_head() -> void:
	var p := _part(head, "Helm")
	p.box(Vector3(0.44, 0.42, 0.46), Vector3(0.0, 0.24, 0.0), Palette.IRON)
	p.box(Vector3(0.48, 0.1, 0.5), Vector3(0.0, 0.08, 0.0), Palette.SHADOW)
	p.box(Vector3(0.34, 0.06, 0.04), Vector3(0.0, 0.26, -0.24), Palette.EMBER, Vector3.ZERO, KIT.EMISSIVE)
	p.box(Vector3(0.06, 0.2, 0.04), Vector3(0.0, 0.17, -0.25), Palette.VOID)
	p.box(Vector3(0.08, 0.16, 0.44), Vector3(0.0, 0.5, 0.04), Palette.RUST_LIGHT)
	p.box(Vector3(0.08, 0.1, 0.2), Vector3(0.0, 0.44, 0.3), Palette.RUST_LIGHT)
	p.build()
