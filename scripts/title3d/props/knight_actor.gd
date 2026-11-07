extends "res://scripts/title3d/props/title_prop3d.gd"
## Low-poly brick knight on the bridge (2D: TitleWorld's knight + Greatsword,
## docs/title-live-scene.md §6.1; assembly idea from
## scripts/moba/view/low_poly_knight.gd, idle pose only).
##
## Four poses driven by `grade.knight_pose` (+ `grade.planted_sword`):
##   stand    back to the hall, greatsword slung on his back (cold / journey / true_break)
##   seated   sitting on the forge bench, looking into the fire (keep)
##   planted  the knight is gone; only the greatsword stands in the bridge (give)
##   absent   empty bridge (snuff)
## When `planted_sword` is true the planted greatsword shows regardless of the pose,
## so the world can stage the moment without rebuilding.
##
## Idle life: a slow breathing bob, a sword micro-sway, and the 2D gaze clock: first
## look at the forge 7 s after start, then every 19 s for 4.6 s (only when
## `prop_plan.knight_turns` is true). `gaze(seconds)` is the 'continue' menu reaction.
##
## Node contract: pivots + merged meshes built once; poses are pivot transforms and
## visibility toggles, so configure()/apply_grade() never rebuild the rig.

const KNIGHT_POS := Vector3(0.0, 0.0, 0.0)
const KEEP_BENCH := Vector3(5.2, 0.0, -1.0)
const GREATSWORD_POS := Vector3(0.6, 0.0, -0.5)
const KNIGHT_HEIGHT := 1.8
## Layout: 0 = facing the camera (+Z); the forge is behind him.
const REST_YAW_DEG := 0.0
const GAZE_YAW_DEG := 180.0
const GAZE_FIRST := 7.0
const GAZE_PERIOD := 19.0
const GAZE_HOLD := 4.6
## Turn ease: 8/s reaches the target in ~0.3 s (readable but not snappy).
const TURN_EASE := 8.0

var _visual: Node3D
var _body: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _back_sword: Node3D
var _planted: Node3D
var _planted_glow: MeshInstance3D
var _visor: MeshInstance3D

var _pose: StringName = &"stand"
var _planted_requested := false
var _yaw := 0.0
var _target_yaw := 0.0
var _gaze_hold := 0.0
var _gaze_wait := GAZE_FIRST
var _gaze_enabled := true
var _breath := 0.0
## Layout-driven anchors (TitleLayout), read once in _build().
var _knight_pos := KNIGHT_POS
var _keep_bench := KEEP_BENCH
var _greatsword_pos := GREATSWORD_POS
var _rest_yaw := 0.0
var _gaze_yaw := PI


func _build() -> void:
	_knight_pos = LV3("KNIGHT_POS", KNIGHT_POS)
	_keep_bench = LV3("KEEP_BENCH", KEEP_BENCH)
	_greatsword_pos = LV3("GREATSWORD_POS", GREATSWORD_POS)
	_rest_yaw = deg_to_rad(L("KNIGHT_YAW_DEG", REST_YAW_DEG))
	_gaze_yaw = deg_to_rad(GAZE_YAW_DEG)
	_yaw = _rest_yaw
	_visual = Node3D.new()
	_visual.name = "Visual"
	_visual.position = _knight_pos
	add_child(_visual)
	_body = Node3D.new()
	_body.name = "Body"
	_body.position = Vector3(0.0, 0.88, 0.0)
	_visual.add_child(_body)
	_torso()
	_leg_l = _pivot(_body, "LegL", Vector3(-0.16, 0.06, 0.0))
	_leg_r = _pivot(_body, "LegR", Vector3(0.16, 0.06, 0.0))
	_build_leg(_leg_l)
	_build_leg(_leg_r)
	_arm_l = _pivot(_body, "ArmL", Vector3(-0.44, 0.52, 0.0))
	_arm_r = _pivot(_body, "ArmR", Vector3(0.44, 0.52, 0.0))
	_build_arm(_arm_l)
	_build_arm(_arm_r)
	_head = _pivot(_body, "Head", Vector3(0.0, 0.80, 0.0))
	_build_head()
	_back_sword = _pivot(_body, "BackSword", Vector3(0.18, 0.48, -0.26))
	_back_sword.rotation.z = deg_to_rad(-22.0)
	_build_back_sword()
	_build_planted()
	_apply_grade()
	_sync()


func _pivot(parent: Node3D, node_name: String, at: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.position = at
	parent.add_child(node)
	return node


func _torso() -> void:
	var parts: Array = []
	parts.append(GEO.box(Vector3(0.66, 0.56, 0.42), Vector3(0.0, 0.22, 0.0), IRON))
	parts.append(GEO.box(Vector3(0.70, 0.10, 0.46), Vector3(0.0, 0.02, 0.0), IRON_DARK))
	parts.append(GEO.box(Vector3(0.50, 0.26, 0.06), Vector3(0.0, 0.28, 0.23), IRON_LIGHT))
	parts.append(GEO.box(Vector3(0.18, 0.14, 0.05), Vector3(0.0, 0.30, 0.26), HOT, Vector3.ZERO, 1.0))
	for side in [-1.0, 1.0]:
		parts.append(GEO.box(Vector3(0.26, 0.20, 0.44), Vector3(0.40 * side, 0.44, 0.0),
				IRON_DARK))
		parts.append(GEO.box(Vector3(0.28, 0.08, 0.30), Vector3(0.42 * side, 0.55, 0.0),
				IRON_LIGHT))
	var torso := add_mesh(parts, GEO.mat(0), "Torso", Vector3.ZERO, _body)
	GEO.outline(torso, 1.0)


func _build_leg(pivot: Node3D) -> void:
	var parts: Array = []
	parts.append(GEO.box(Vector3(0.22, 0.44, 0.24), Vector3(0.0, -0.24, 0.0), IRON_DARK))
	parts.append(GEO.box(Vector3(0.24, 0.34, 0.26), Vector3(0.0, -0.60, 0.0), IRON))
	parts.append(GEO.box(Vector3(0.26, 0.12, 0.36), Vector3(0.0, -0.80, -0.05), IRON_DARK))
	var leg := add_mesh(parts, GEO.mat(0), "Leg", Vector3.ZERO, pivot)
	GEO.outline(leg, 1.0)


func _build_arm(pivot: Node3D) -> void:
	var parts: Array = []
	parts.append(GEO.box(Vector3(0.18, 0.40, 0.20), Vector3(0.0, -0.20, 0.0), IRON))
	parts.append(GEO.box(Vector3(0.20, 0.16, 0.22), Vector3(0.0, -0.44, 0.0), IRON_DARK))
	parts.append(GEO.box(Vector3(0.16, 0.14, 0.18), Vector3(0.0, -0.56, 0.02), IRON_LIGHT))
	var arm := add_mesh(parts, GEO.mat(0), "Arm", Vector3.ZERO, pivot)
	GEO.outline(arm, 1.0)


func _build_head() -> void:
	var parts: Array = []
	parts.append(GEO.box(Vector3(0.38, 0.34, 0.38), Vector3(0.0, 0.18, 0.0), IRON))
	parts.append(GEO.box(Vector3(0.42, 0.10, 0.42), Vector3(0.0, 0.02, 0.0), IRON_DARK))
	parts.append(GEO.box(Vector3(0.12, 0.20, 0.10), Vector3(0.0, 0.42, 0.0), IRON_DARK))
	var head := add_mesh(parts, GEO.mat(0), "Helm", Vector3.ZERO, _head)
	GEO.outline(head, 1.0)
	# the two ember eyes under the brow
	_visor = MeshInstance3D.new()
	_visor.name = "Visor"
	_visor.mesh = GEO.merge([
		GEO.box(Vector3(0.24, 0.045, 0.05), Vector3(0.0, 0.19, 0.20), HOT, Vector3.ZERO, 1.0),
		GEO.box(Vector3(0.05, 0.10, 0.05), Vector3(0.0, 0.26, 0.21), HOT_DEEP, Vector3.ZERO, 1.0),
	])
	_visor.material_override = GEO.mat(GEO.EMISSIVE)
	_visor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visor.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_head.add_child(_visor)


## The greatsword slung across his back (visible in the stand / seated poses).
func _build_back_sword() -> void:
	var parts: Array = []
	parts.append(GEO.box(Vector3(0.08, 0.34, 0.08), Vector3(0.0, 0.0, 0.0), IRON_DARK))
	parts.append(GEO.box(Vector3(0.20, 0.08, 0.12), Vector3(0.0, 0.20, 0.0), IRON_LIGHT))
	parts.append(GEO.box(Vector3(0.20, 1.35, 0.06), Vector3(0.0, 0.95, 0.0), STEEL))
	parts.append(GEO.box(Vector3(0.06, 1.20, 0.08), Vector3(0.0, 0.92, 0.0), STEEL_LIGHT))
	var sword := add_mesh(parts, GEO.mat(0), "Sword", Vector3.ZERO, _back_sword)
	GEO.outline(sword, 1.0)


## The planted greatsword prop from the 'give' ending: tip in the planks, hilt up.
func _build_planted() -> void:
	_planted = Node3D.new()
	_planted.name = "PlantedSword"
	_planted.position = _greatsword_pos
	_planted.visible = false
	add_child(_planted)
	var parts: Array = []
	parts.append(GEO.box(Vector3(0.22, 0.14, 0.22), Vector3(0.0, 0.02, 0.0), IRON_DARK))
	parts.append(GEO.box(Vector3(0.24, 1.90, 0.07), Vector3(0.0, 1.05, 0.0), STEEL))
	parts.append(GEO.box(Vector3(0.07, 1.76, 0.09), Vector3(0.0, 1.05, 0.0), STEEL_LIGHT))
	parts.append(GEO.box(Vector3(0.16, 0.26, 0.08), Vector3(0.0, 2.12, 0.0), STEEL_DARK))
	parts.append(GEO.box(Vector3(0.78, 0.12, 0.20), Vector3(0.0, 2.28, 0.0), IRON_LIGHT))
	parts.append(GEO.box(Vector3(0.10, 0.42, 0.10), Vector3(0.0, 2.52, 0.0), IRON_DARK))
	parts.append(GEO.box(Vector3(0.22, 0.10, 0.22), Vector3(0.0, 2.74, 0.0), IRON))
	var sword := add_mesh(parts, GEO.mat(0), "Blade", Vector3.ZERO, _planted)
	GEO.outline(sword, 1.0)
	# four name-runes smouldering down the blade
	var runes := MeshInstance3D.new()
	runes.name = "Runes"
	var rune_parts: Array = []
	for m in 4:
		rune_parts.append(GEO.box(Vector3(0.10, 0.10, 0.03),
				Vector3(0.0, 0.55 + 0.35 * float(m), 0.06), HOT, Vector3.ZERO, 1.0))
	runes.mesh = GEO.merge(rune_parts)
	runes.material_override = GEO.mat(GEO.EMISSIVE)
	runes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	runes.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_planted.add_child(runes)
	_planted_glow = GEO.glow_quad(1.6)
	_planted_glow.name = "Halo"
	_planted_glow.position = Vector3(0.0, 1.3, 0.3)
	_planted.add_child(_planted_glow)


# ------------------------------------------------------------------- plan -----

func _apply_plan() -> void:
	_gaze_enabled = p_bool("knight_turns", true)
	if _gaze_enabled:
		_gaze_wait = GAZE_FIRST
	elif _gaze_hold <= 0.0:
		_target_yaw = _rest_yaw


func _apply_grade() -> void:
	if _grade.has("knight_pose"):
		set_pose(g_name("knight_pose", _pose))
	if _grade.has("planted_sword"):
		_planted_requested = g_bool("planted_sword", _planted_requested)
	if _grade.has("knight_turns"):
		_gaze_enabled = g_bool("knight_turns", _gaze_enabled)
	if is_built():
		_sync()


## Switch pose ('stand' / 'planted' / 'seated' / 'absent').
func set_pose(next_pose: StringName) -> void:
	var normalized := next_pose
	if not [&"stand", &"planted", &"seated", &"absent"].has(normalized):
		normalized = &"stand"
	_pose = normalized
	if not is_built():
		return
	_visual.visible = _pose == &"stand" or _pose == &"seated"
	_visual.position = _keep_bench if _pose == &"seated" else _knight_pos
	_back_sword.visible = _pose == &"stand" or _pose == &"seated"
	_planted.visible = _planted_requested or _pose == &"planted"
	# seated: fold the legs forward onto the bench, lean the torso to the fire
	if _pose == &"seated":
		_leg_l.rotation.x = deg_to_rad(-78.0)
		_leg_r.rotation.x = deg_to_rad(-72.0)
		_leg_l.position = Vector3(-0.18, 0.02, 0.16)
		_leg_r.position = Vector3(0.18, 0.02, 0.16)
		_arm_l.rotation.x = deg_to_rad(-38.0)
		_arm_r.rotation.x = deg_to_rad(-44.0)
		_body.rotation.z = deg_to_rad(-4.0)
		_target_yaw = _gaze_yaw
	else:
		_leg_l.rotation.x = 0.0
		_leg_r.rotation.x = 0.0
		_leg_l.position = Vector3(-0.16, 0.06, 0.0)
		_leg_r.position = Vector3(0.16, 0.06, 0.0)
		_arm_l.rotation.x = deg_to_rad(4.0)
		_arm_r.rotation.x = deg_to_rad(4.0)
		_body.rotation.z = 0.0
		_target_yaw = _rest_yaw
	_sync()


func pose() -> StringName:
	return _pose


## 'continue' menu reaction: turn to the furnace for `seconds`.
func gaze(seconds: float = GAZE_HOLD) -> void:
	if not is_built():
		return
	if _pose != &"stand":
		return
	_gaze_hold = maxf(seconds, 0.1)
	_target_yaw = _gaze_yaw
	_sync()


# ------------------------------------------------------------------- tick -----

func _tick(dt: float) -> void:
	_breath += dt
	if _gaze_hold > 0.0:
		_gaze_hold -= dt
		if _gaze_hold <= 0.0:
			_gaze_hold = 0.0
			_target_yaw = _rest_yaw
	elif _gaze_enabled and _pose == &"stand":
		_gaze_wait -= dt
		if _gaze_wait <= 0.0:
			_gaze_wait = GAZE_PERIOD
			gaze(GAZE_HOLD)
	_yaw = lerp_angle(_yaw, _target_yaw, 1.0 - exp(-TURN_EASE * dt))


func _sync() -> void:
	if _visual == null:
		return
	_visual.rotation.y = _yaw
	# breathing: the chest rises, the shoulders follow a frame behind
	var breath := sin(_breath * 1.35) * 0.012
	_body.position.y = 0.88 + (0.05 if _pose == &"seated" else 0.0) + breath
	_body.rotation.x = deg_to_rad(sin(_breath * 0.7) * 1.2)
	_head.rotation.x = deg_to_rad(-sin(_breath * 0.7) * 1.8)
	if _pose != &"seated":
		_arm_l.rotation.z = deg_to_rad(3.0 + sin(_breath * 0.9) * 1.2)
		_arm_r.rotation.z = deg_to_rad(-3.0 - sin(_breath * 0.9) * 1.2)
	# sword micro-sway on the back (2D Greatsword.IDLE_SWAY)
	if _back_sword.visible:
		_back_sword.rotation.z = deg_to_rad(-22.0 + sin(t * 1.7) * 1.5)
	# the ember eyes and the planted sword glow follow the furnace heat
	var hot := clampf(heat01(), 0.0, 1.0)
	set_glow(_planted_glow, Color(1.0, 0.5, 0.2, 0.30 * hot * (0.8 + 0.2 * sin(t * 2.1))))
	if _visor != null:
		_visor.visible = hot > 0.12


# ------------------------------------------------------------ test helpers ----

func knight_visible() -> bool:
	return _visual.visible


func planted_visible() -> bool:
	return _planted.visible


func back_sword_visible() -> bool:
	return _back_sword.visible


func yaw_deg() -> float:
	return rad_to_deg(_yaw)


func gazing() -> bool:
	# the 'keep' knight sits looking into the fire, so he is always gazing
	return _gaze_hold > 0.0 or _pose == &"seated"


func gaze_enabled() -> bool:
	return _gaze_enabled


func _snapshot_into(out: Dictionary) -> void:
	out["pose"] = _pose
	out["yaw"] = snappedf(_yaw, 0.000001)
	out["gaze"] = snappedf(_gaze_hold, 0.000001)
	out["knight"] = knight_visible()
	out["planted"] = planted_visible()
