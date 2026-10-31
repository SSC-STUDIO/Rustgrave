extends Node3D
## Sim-driven lane minion for the 3D arena.
##
## Unlike the retired render-spike walker this unit never moves or decides
## anything itself: MobaUnitPool feeds it the lane position, facing and anim
## state that MobaSim publishes every tick. The view only plays the matching
## cartoon pose (idle bob / walk cycle / attack lunge / death fade) and the hit
## flash. Damage itself is settled by the simulation.
##
## Two silhouettes are built from the same pooled node, picked by the pool:
## a melee iron husk and a floating lantern skull caster.

const KIT := preload("res://scripts/moba/view/toon_kit.gd")
const TOON_PART := preload("res://scripts/moba/view/toon_part.gd")
const FX := preload("res://scripts/moba/present/moba_unit_fx.gd")

const POSE_FPS := 12.0
const WALK_PHASE_RATE := 3.2
const DEATH_FADE_TIME := 0.45
const FLASH_TIME := 0.09

var team := 0
var caster := false
## Child that receives the texel-snap offset; the root stays on the sim position.
var visual: Node3D

var _rig: Node3D
var _legs: Array[Node3D] = []
var _parts: Array[MeshInstance3D] = []
var _phase := 0.0
var _clock := 0.0
var _pose_clock := 0.0
var _anim: StringName = &"idle"
var _attack_elapsed := 0.0
var _fade := 1.0
var _flash_timer := 0.0
var _retiring := false
var _pose_dirty := true


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
	_parts = FX.collect_parts(self)
	_apply_pose()


## Called by the pool every frame with the current simulation state.
func apply(move_to: Vector3, yaw: float, anim: StringName, alive: bool) -> void:
	global_position = move_to
	visual.rotation.y = yaw
	set_anim(&"dead" if not alive else anim)


func set_anim(anim: StringName) -> void:
	if anim == _anim:
		return
	var was_dead := _anim == &"dead"
	_anim = anim
	_pose_dirty = true
	if anim == &"attack":
		_attack_elapsed = 0.0
	if anim == &"dead":
		_retiring = true
	elif was_dead:
		reset_visual()


func flash() -> void:
	if _retiring:
		return
	_flash_timer = FLASH_TIME
	FX.set_flash(_parts, true)


func advance(delta: float) -> void:
	_clock += delta
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			FX.set_flash(_parts, false)
	if _anim == &"run":
		_phase = fmod(_phase + delta * WALK_PHASE_RATE, TAU)
	elif _anim == &"attack":
		_attack_elapsed += delta
		_pose_dirty = true
	if _anim == &"dead" and _fade > 0.0:
		var step := delta / DEATH_FADE_TIME
		_fade = maxf(0.0, _fade - step)
		FX.set_fade(_parts, _fade)
		_pose_dirty = true
	# The 12 fps stepped look of the retired spike walkers: poses only refresh
	# on a fixed animation tick, never every rendered frame.
	_pose_clock += delta
	var stepped := _pose_clock >= 1.0 / POSE_FPS
	if stepped:
		_pose_clock = fmod(_pose_clock, 1.0 / POSE_FPS)
	if _pose_dirty or stepped:
		_apply_pose()


func retire() -> void:
	set_anim(&"dead")


func retire_done() -> bool:
	return _anim == &"dead" and _fade <= 0.0


func reset_visual() -> void:
	_fade = 1.0
	_retiring = false
	_anim = &"idle"
	_attack_elapsed = 0.0
	_flash_timer = 0.0
	_pose_clock = 0.0
	_phase = 0.0
	visible = true
	visual.position = Vector3.ZERO
	visual.rotation = Vector3.ZERO
	_rig.position = Vector3.ZERO
	_rig.rotation = Vector3.ZERO
	FX.set_fade(_parts, 1.0)
	FX.set_flash(_parts, false)
	_pose_dirty = true
	_apply_pose()


func _apply_pose() -> void:
	_pose_dirty = false
	if _anim == &"dead":
		_rig.rotation.x = deg_to_rad(78.0) * (1.0 - _fade)
		_rig.position = Vector3(0.0, -0.3 * (1.0 - _fade), 0.0)
		return
	if caster:
		_rig.rotation = Vector3.ZERO
		_rig.position = Vector3(0.0, sin(_clock * 3.0) * 0.08, 0.0)
		if _anim == &"attack":
			_rig.position.z = -0.22 * _attack_pulse()
		return
	var swing := 0.0
	if _anim == &"run":
		swing = sin(_phase)
	elif _anim == &"attack":
		swing = sin(_clock * 10.0) * 0.4
	if not _legs.is_empty():
		_legs[0].rotation.x = deg_to_rad(32.0) * swing
		_legs[1].rotation.x = -deg_to_rad(32.0) * swing
	var bob := absf(swing) * 0.04
	var lunge := -0.3 * _attack_pulse() if _anim == &"attack" else 0.0
	_rig.rotation = Vector3.ZERO
	_rig.position = Vector3(0.0, bob, lunge)


func _attack_pulse() -> float:
	return sin(clampf(_attack_elapsed / 0.28, 0.0, 1.0) * PI)


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
