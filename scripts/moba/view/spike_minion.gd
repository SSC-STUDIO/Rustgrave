extends Node3D
## Lane walker for the render spike: an iron husk (melee) or a floating lantern
## skull (caster) in team colours, looping from one end of the lane to the other.

const KIT := preload("res://scripts/moba/view/toon_kit.gd")
const TOON_PART := preload("res://scripts/moba/view/toon_part.gd")

const POSE_FPS := 12.0

var team := 0
var caster := false
var path_from := Vector3.ZERO
var path_to := Vector3.ZERO
## Metres along the path.
var progress := 0.0
## Sideways offset from the lane centre line, in metres.
var lateral := 0.0
var speed := 2.2
var stepped := true
var visual: Node3D

var _rig: Node3D
var _legs: Array[Node3D] = []
var _phase := 0.0
var _clock := 0.0
var _pose_clock := 0.0


func _ready() -> void:
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	visual.add_child(KIT.blob_shadow(0.3 if caster else 0.38))
	_rig = Node3D.new()
	_rig.name = "Rig"
	visual.add_child(_rig)
	if caster:
		_build_caster()
	else:
		_build_husk()
	_phase = fmod(progress * 1.7, TAU)
	_advance(0.0)
	_apply_pose()


func _process(delta: float) -> void:
	_advance(delta)
	_pose_clock += delta
	if stepped and _pose_clock < 1.0 / POSE_FPS:
		return
	_pose_clock = fmod(_pose_clock, 1.0 / POSE_FPS) if stepped else 0.0
	_apply_pose()


func _advance(delta: float) -> void:
	var span := path_to - path_from
	var length := span.length()
	if length < 0.01:
		return
	progress = fmod(progress + speed * delta, length)
	var dir := span / length
	var side := Vector3(-dir.z, 0.0, dir.x)
	position = path_from + dir * progress + side * lateral
	_phase = fmod(_phase + delta * speed * 3.2, TAU)
	_clock += delta
	visual.rotation.y = atan2(-dir.x, -dir.z)


func _apply_pose() -> void:
	if caster:
		_rig.position.y = sin(_clock * 3.0) * 0.08
		return
	var swing := sin(_phase)
	_legs[0].rotation.x = deg_to_rad(32.0) * swing
	_legs[1].rotation.x = -deg_to_rad(32.0) * swing
	_rig.position.y = absf(swing) * 0.04


func _build_husk() -> void:
	var body := TOON_PART.new()
	body.name = "Body"
	_rig.add_child(body)
	body.box(Vector3(0.44, 0.46, 0.3), Vector3(0.0, 0.7, 0.0), Palette.IRON)
	body.box(Vector3(0.3, 0.36, 0.04), Vector3(0.0, 0.7, -0.17), KIT.team_color(team))
	body.box(Vector3(0.3, 0.28, 0.28), Vector3(0.0, 1.08, 0.0), Palette.PALE)
	body.box(Vector3(0.2, 0.05, 0.03), Vector3(0.0, 1.1, -0.15), Palette.EMBER, Vector3.ZERO, KIT.EMISSIVE)
	body.box(Vector3(0.12, 0.4, 0.14), Vector3(-0.3, 0.66, 0.0), Palette.SHADOW, Vector3(-10.0, 0.0, 0.0))
	body.box(Vector3(0.12, 0.4, 0.14), Vector3(0.3, 0.66, 0.0), Palette.SHADOW, Vector3(20.0, 0.0, 0.0))
	body.box(Vector3(0.06, 0.12, 0.42), Vector3(0.32, 0.46, -0.2), Palette.CONCRETE)
	body.build()
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var pivot := Node3D.new()
		pivot.name = "Leg%d" % i
		pivot.position = Vector3(0.11 * side, 0.46, 0.0)
		_rig.add_child(pivot)
		var leg := TOON_PART.new()
		leg.box(Vector3(0.14, 0.4, 0.16), Vector3(0.0, -0.22, 0.0), Palette.SHADOW)
		leg.box(Vector3(0.16, 0.08, 0.22), Vector3(0.0, -0.42, -0.03), Palette.RUST_SHADOW)
		leg.build()
		pivot.add_child(leg)
		_legs.append(pivot)


func _build_caster() -> void:
	var team_col := KIT.team_color(team)
	var part := TOON_PART.new()
	part.name = "Body"
	_rig.add_child(part)
	part.box(Vector3(0.4, 0.34, 0.38), Vector3(0.0, 1.06, 0.0), Palette.PALE)
	part.box(Vector3(0.3, 0.1, 0.3), Vector3(0.0, 0.84, -0.02), Palette.CONCRETE)
	part.box(Vector3(0.1, 0.08, 0.04), Vector3(-0.09, 1.07, -0.2), team_col, Vector3.ZERO, KIT.EMISSIVE)
	part.box(Vector3(0.1, 0.08, 0.04), Vector3(0.09, 1.07, -0.2), team_col, Vector3.ZERO, KIT.EMISSIVE)
	part.prism(Vector3(0.44, 0.5, 0.36), Vector3(0.0, 0.56, 0.02), KIT.team_dark(team), Vector3(180.0, 0.0, 0.0))
	part.cylinder(0.08, 0.1, 0.18, Vector3(0.34, 0.8, -0.1), Palette.EMBER, 6, Vector3.ZERO, KIT.EMISSIVE)
	part.box(Vector3(0.02, 0.2, 0.02), Vector3(0.34, 0.98, -0.1), Palette.VOID)
	part.build()
