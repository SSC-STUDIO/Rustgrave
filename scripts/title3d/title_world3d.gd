class_name TitleWorld3D
extends Node3D
## The title screen's live 3D forge hall (replaces the retired 2D TitleWorld).
##
## Built in code from the 3D pixel kit: hall / bridge / furnace geometry, the
## Forward+ lighting rig, the props (gears, lanterns, banners, hammer, crucible,
## sword chain, ghosts, souls, braziers, knight, particles), and the shot player
## that drives the title camera. The title screen only talks to the public API at
## the bottom (state / play_intro / skip_intro / set_pointer / nudge / react_to /
## enter_push / quit_out / lantern_pulse), so the UI layer stayed untouched.
##
## Everything that can be missing during bring-up is loaded through
## ResourceLoader.exists() so the title still boots while the modules are being
## written: a missing builder falls back to the placeholder masses below, a
## missing prop simply does not appear. Once the modules are all in the repo the
## dynamic loads can be replaced by preloads without touching the call sites.
##
## Determinism: no physics, no random nodes spawned at runtime; every clock is
## advanced by `advance(dt)` and every flicker is a pure function of time+seed,
## so headless tests can feed fixed deltas.

signal event_fired(kind: StringName, payload: Dictionary)
## Emitted when the intro shot has finished (the title screen fades the menu in).
signal intro_finished

const TITLE_STATE_PATH := "res://scripts/title3d/title_state.gd"
const LIGHTING_PATH := "res://scripts/title3d/title_lighting.gd"
const CAMERA_RIG_PATH := "res://scripts/title3d/title_camera_rig.gd"
const SHOT_PLAYER_PATH := "res://scripts/title3d/title_shot_player.gd"
const KIT_DIR := "res://scripts/title3d/kit/"
const PROP_DIR := "res://scripts/title3d/props/"
const PROP_SCRIPTS := [
	"gears", "lanterns", "banners", "hammer", "crucible", "sword_chain",
	"ghosts", "souls", "braziers", "knight_actor", "embers", "steam",
]
const LANTERN_COUNT := 14
const MAX_LIGHTS := 14
const MAX_SHADOW_CASTERS := 6
## Fallback camera framing (also used by the camera rig's idle shot).
const CAMERA_FOV := 30.0
const VIEW_HEIGHT := 13.5
const IDLE_CAMERA := Vector3(0.9, 2.3, 9.2)
const IDLE_TARGET := Vector3(0.0, 1.5, -1.2)

## Set by the title screen before the node enters the tree (old TitleWorld contract).
var state: Dictionary = {}
## Pixel stage (`res://scripts/moba/view/pixel_stage.gd`): camera subpixel offsets
## are handed to it so the upscaled image moves by whole physical pixels.
var stage: Node2D

var _state_script: GDScript
var _camera: Camera3D
var _camera_rig: Camera3D
var _lighting: Node3D
var _shots: Node
var _geometry: Node3D
var _props_host: Node3D
var _fx_host: Node3D
var _props: Dictionary = {}
var _built := false
var _time := 0.0
var _intro_t := -1.0
var _pointer := Vector2.ZERO
var _pointer_seen := false
var _nudge := 0.0
var _quitting := false
var _quit_at := -1.0
var _dark_at := 0.9
var _lit_lanterns := 0
var _react: Dictionary = {}
var _placeholder: Node3D


func _ready() -> void:
	process_priority = 50
	_state_script = _script(TITLE_STATE_PATH)
	if state.is_empty() and _state_script != null:
		if _state_script.has_method("state_from_save"):
			state = _state_script.call("state_from_save")
	if state.is_empty():
		state = build_fallback_state()
	_geometry = Node3D.new()
	_geometry.name = "Geometry"
	add_child(_geometry)
	_props_host = Node3D.new()
	_props_host.name = "Props"
	add_child(_props_host)
	_fx_host = Node3D.new()
	_fx_host.name = "FX"
	add_child(_fx_host)
	_build_lighting()
	_build_geometry()
	_build_camera()
	_build_props()
	_build_hero_fill()
	_build_shots()
	_built = true
	_apply_grade()
	set_process(true)


func _process(delta: float) -> void:
	if not _built:
		return
	advance(delta)


## ---------------------------------------------------------------- public API --

func variant() -> StringName:
	return StringName(String(state.get("variant", "cold")))


## Re-apply a new save look without rebuilding geometry (hot switch for the peek
## tool and for "back to title" flows).
func configure(next_state: Dictionary) -> void:
	state = next_state
	if not _built:
		return
	_apply_grade()


func play_intro() -> void:
	_intro_t = 0.0
	play_shot(&"intro")


## Capture-tool helper: jump straight to a named shot (idle / attract / confirm / quit).
func play_shot(id: StringName) -> void:
	if _shots != null and _shots.has_method("play"):
		_shots.call("play", id)


func current_shot() -> StringName:
	if _shots != null and _shots.has_method("current_id"):
		return StringName(String(_shots.call("current_id")))
	return &"idle"


func skip_intro() -> void:
	if _intro_t < 0.0:
		return
	_intro_t = -1.0
	if _shots != null and _shots.has_method("skip"):
		_shots.call("skip")
	_restore_lanterns()

## Normalised pointer (-1..1). The rig turns it into a small orbit; whole-texel
## snapping keeps the image stable while it moves.
func set_pointer(n: Vector2) -> void:
	_pointer = n.clamp(Vector2(-1, -1), Vector2(1, 1))
	_pointer_seen = n != Vector2.ZERO
	if _camera_rig != null and _camera_rig.has_method("set_pointer"):
		_camera_rig.call("set_pointer", _pointer)


func nudge(strength: float = 1.0) -> void:
	_nudge = maxf(_nudge, clampf(strength, 0.0, 2.0))
	if _camera_rig != null and _camera_rig.has_method("nudge"):
		_camera_rig.call("nudge", strength)


## Menu focus reactions (same observable state names as the 2D title).
func react_to(menu_id: StringName) -> bool:
	match menu_id:
		&"new":
			_surge()
			return true
		&"continue":
			_gaze()
			return true
		&"trial":
			_prop_call("hammer", "strike_now")
			_react["strike_requests"] = int(_react.get("strike_requests", 0)) + 1
			return true
		&"arena":
			_prop_call("braziers", "boost_braziers")
			_react["brazier_boost"] = 1.0
			return true
		&"settings":
			if _lighting != null and _lighting.has_method("slow_clouds"):
				_lighting.call("slow_clouds", 0.3)
			_react["cloud_target"] = 0.3
			return true
		&"controls":
			_prop_call("banners", "gust")
			_react["gust"] = 1.0
			return true
		&"quit":
			_prop_call("souls", "soul_boost", 6)
			_react["soul_boost"] = 1.0
			return true
	return false


func reaction_state() -> Dictionary:
	return _react.duplicate()


## Confirm / enter: push the camera toward the bridge and flash the forge.
func enter_push(distance_texels: float = 5.0, seconds: float = 0.55) -> void:
	if _shots != null and _shots.has_method("play"):
		_shots.call("play", &"confirm")
	if _lighting != null and _lighting.has_method("surge"):
		_lighting.call("surge")
	event_fired.emit(&"enter_push", {"distance": distance_texels, "seconds": seconds})


## Quit: douse the lanterns one by one while the camera pulls back into the dark.
## Returns the time (seconds) at which the hall is dark; the title screen schedules
## the gate sound and caption off it (old TitleWorld contract).
func quit_out(seconds_per_lantern: float) -> float:
	_quitting = true
	_quit_at = 0.0
	_dark_at = float(maxi(_lit_lanterns, 1)) * maxf(seconds_per_lantern, 0.01) + 0.35
	if _shots != null and _shots.has_method("play"):
		_shots.call("play", &"quit")
	if _lighting != null and _lighting.has_method("quit_out"):
		_lighting.call("quit_out", _dark_at)
	_prop_call("lanterns", "quit_out", seconds_per_lantern)
	return _dark_at


## Breathing pulse for the journey column (0.88..1.0, 12 fps stepped). Matches the
## retired 2D TitleWorld formula exactly, so the journey column keeps its old feel.
func lantern_pulse() -> float:
	var step := int(_time * 12.0)
	var n := sin(float(step) * 1.7) * 0.6 + sin(float(step) * 4.3) * 0.4
	return 0.88 + 0.12 * clampf(0.5 + 0.5 * n, 0.0, 1.0)


func advance(dt: float) -> void:
	var step := clampf(dt, 0.0, 0.1)
	_time += step
	_nudge = maxf(0.0, _nudge - step * 0.8)
	if _intro_t >= 0.0:
		_intro_t += step
		if _intro_t > 3.2:
			_intro_t = -1.0
			_restore_lanterns()
			intro_finished.emit()
	# decaying menu reactions
	for key in ["surge", "brazier_boost", "gust", "soul_boost"]:
		if _react.has(key):
			_react[key] = maxf(0.0, float(_react[key]) - step * (0.9 if key == "surge" else 0.55))
	if _react.has("wave_active"):
		_react["wave_active"] = maxf(0.0, float(_react["wave_active"]) - step)
	if _react.has("gazing"):
		_react["gazing"] = maxf(0.0, float(_react["gazing"]) - step)
	if _lighting != null and _lighting.has_method("advance"):
		_lighting.call("advance", step)
	for key in _props.keys():
		var prop: Node = _props[key]
		if is_instance_valid(prop) and prop.has_method("advance"):
			prop.call("advance", step)
	if _camera_rig != null and _camera_rig.has_method("advance"):
		_camera_rig.call("advance", step)
	if _shots != null and _shots.has_method("advance"):
		_shots.call("advance", step)
	if _shots != null and _shots.has_method("configure_state"):
		_shots.call("configure_state", state)
	_drive_camera()
	if _quitting:
		_quit_at += step
		if _quit_at > 0.05 and not _props.has("lanterns"):
			_lit_lanterns = maxi(0, _lit_lanterns - 1)


## ------------------------------------------------------------------ builders --

func build_fallback_state() -> Dictionary:
	return {
		"variant": &"cold",
		"grade_id": &"cold",
		"lit": 0,
		"knight_pose": &"stand",
		"planted_sword": false,
	}


func _build_lighting() -> void:
	var script := _script(LIGHTING_PATH)
	if script == null:
		return
	_lighting = script.new() as Node3D
	if _lighting == null:
		return
	_lighting.name = "Lighting"
	add_child(_lighting)
	if _lighting.has_method("build"):
		_lighting.call("build", self)


func _build_geometry() -> void:
	var built := false
	for entry in [
		["hall_builder", "Hall"],
		["bridge_builder", "Bridge"],
		["furnace_builder", "Furnace"],
	]:
		var script := _script(KIT_DIR + String(entry[0]) + ".gd")
		if script == null:
			continue
		var host := Node3D.new()
		host.name = String(entry[1])
		_geometry.add_child(host)
		if script.has_method("build"):
			script.call("build", host)
			built = true
	if not built:
		_placeholder = _build_placeholder()
		_geometry.add_child(_placeholder)
	# Extra set dressing (foreground shoulders, far arcade, roof bracing, pipes,
	# hanging chains, deck clutter) so the hall is not a bare box from the hero shot.
	var dressing := _script("res://scripts/title3d/title_dressing.gd")
	if dressing != null and dressing.has_method("build"):
		dressing.call("build", _geometry)


## Bring-up stand-in until the kit builders exist: just enough masses to prove the
## pixel pipeline, framing and camera snapping (never shipped once builders land).
func _build_placeholder() -> Node3D:
	var root := Node3D.new()
	root.name = "Placeholder"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.14, 0.17)
	mat.roughness = 0.9
	var deck := MeshInstance3D.new()
	var deck_mesh := BoxMesh.new()
	deck_mesh.size = Vector3(22.0, 0.6, 3.2)
	deck.mesh = deck_mesh
	deck.position = Vector3(0, -0.3, 0)
	deck.material_override = mat
	root.add_child(deck)
	var wall := MeshInstance3D.new()
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(32.0, 15.0, 0.8)
	wall.mesh = wall_mesh
	wall.position = Vector3(0, 7.0, -12.0)
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.09, 0.08, 0.11)
	wall_mat.roughness = 1.0
	wall.material_override = wall_mat
	root.add_child(wall)
	var forge := MeshInstance3D.new()
	var forge_mesh := BoxMesh.new()
	forge_mesh.size = Vector3(3.0, 2.4, 2.0)
	forge.mesh = forge_mesh
	forge.position = Vector3(11.0, 1.2, -6.0)
	var forge_mat := StandardMaterial3D.new()
	forge_mat.albedo_color = Color(0.12, 0.09, 0.09)
	forge_mat.emission_enabled = true
	forge_mat.emission = Color(1.0, 0.35, 0.08) * 2.4
	forge.material_override = forge_mat
	root.add_child(forge)
	return root


func _build_camera() -> void:
	var script := _script(CAMERA_RIG_PATH)
	if script != null:
		_camera_rig = script.new() as Camera3D
	if _camera_rig != null:
		_camera_rig.name = "CameraRig"
		add_child(_camera_rig)
		if _camera_rig.has_method("set_stage"):
			_camera_rig.call("set_stage", stage)
		_camera = _camera_rig
	else:
		_camera = Camera3D.new()
		_camera.name = "Camera"
		add_child(_camera)
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = CAMERA_FOV
	_camera.near = 0.05
	_camera.far = 150.0
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.current = true
	_camera.look_at_from_position(IDLE_CAMERA, IDLE_TARGET, Vector3.UP)


func _build_props() -> void:
	var plan: Dictionary = {}
	if _state_script != null and _state_script.has_method("prop_plan"):
		plan = _state_script.call("prop_plan", state)
	var grade := _grade()
	var layout_script := _script(KIT_DIR + "layout.gd")
	for prop_id in PROP_SCRIPTS:
		var script := _script(PROP_DIR + String(prop_id) + ".gd")
		if script == null:
			continue
		var prop: Node3D = script.new() as Node3D
		if prop == null:
			continue
		prop.name = String(prop_id).to_pascal_case()
		_props_host.add_child(prop)
		_props[prop_id] = prop
		if prop.has_method("setup"):
			prop.call("setup", {
				"world": self,
				"layout": layout_script,
				"grade": grade,
				"state": state,
				"seed": 0x51ED2701,
			})
		if prop.has_method("configure"):
			prop.call("configure", plan)
		if prop.has_method("apply_grade"):
			prop.call("apply_grade", grade)
		if prop.has_signal("fired"):
			prop.connect("fired", _on_prop_fired)
	_lit_lanterns = int(grade.get("lantern_lit", state.get("lit", 0)))


func _build_shots() -> void:
	var script := _script(SHOT_PLAYER_PATH)
	if script == null:
		return
	_shots = script.new() as Node
	if _shots == null:
		return
	_shots.name = "ShotPlayer"
	_shots.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_shots)
	if _shots.has_signal("event_fired"):
		_shots.connect("event_fired", _on_shot_event)
	if _shots.has_method("configure_state"):
		_shots.call("configure_state", state)
	if _shots.has_method("play"):
		_shots.call("play", &"idle")


func _apply_grade() -> void:
	var grade := _grade()
	var quality := StringName(String(Settings.value(&"title3d_quality", "high")))
	if _lighting != null and _lighting.has_method("apply"):
		_lighting.call("apply", grade, quality)
	# The kit's surface shader owns the ambient term (Environment ambient is unused),
	# so it has to receive the same ambient the lighting rig derived from the grade.
	var kit_script := _script(KIT_DIR + "title_kit.gd")
	if kit_script != null and _lighting != null and _lighting.has_method("ambient_color"):
		var ambient: Color = _lighting.call("ambient_color")
		var energy := float(_lighting.call("ambient_energy")) if _lighting.has_method("ambient_energy") else 1.0
		if kit_script.has_method("set_ambient"):
			kit_script.call("set_ambient", ambient, energy)
	for key in _props.keys():
		var prop: Node = _props[key]
		if is_instance_valid(prop) and prop.has_method("apply_grade"):
			prop.call("apply_grade", grade)
	_lit_lanterns = int(grade.get("lantern_lit", state.get("lit", 0)))
	if _lighting != null and _lighting.has_method("set_lantern_lit"):
		_lighting.call("set_lantern_lit", _lit_lanterns)
	_apply_look(grade)
	if _shots != null and _shots.has_method("configure_state"):
		_shots.call("configure_state", state)
	if _shots != null and _shots.has_method("play"):
		_shots.call("play", &"idle")


## Final look pass lives in title_look.gd so the frozen modules stay untouched.
func _apply_look(grade: Dictionary) -> void:
	var look_script := _script("res://scripts/title3d/title_look.gd")
	if look_script != null and look_script.has_method("apply"):
		look_script.call("apply", self, grade)
	if look_script != null and look_script.has_method("apply_windows"):
		look_script.call("apply_windows")


func _grade() -> Dictionary:
	if _state_script != null and _state_script.has_method("grade"):
		return _state_script.call("grade", state)
	return {"variant": variant(), "lantern_lit": int(state.get("lit", 0))}


## ------------------------------------------------------------------ camera ---

func _drive_camera() -> void:
	if _camera == null:
		return
	var desired := Transform3D.IDENTITY
	var snap := true
	var fov := CAMERA_FOV
	if _shots != null and _shots.has_method("sample_now"):
		var sample: Dictionary = _shots.call("sample_now")
		if not sample.is_empty():
			var look_script := _script("res://scripts/title3d/title_look.gd")
			if look_script != null and look_script.has_method("adjust_sample"):
				sample = look_script.call("adjust_sample", sample)
			var pos: Vector3 = sample.get("pos", IDLE_CAMERA)
			var target: Vector3 = sample.get("target", IDLE_TARGET)
			snap = bool(sample.get("snap", true))
			fov = clampf(float(sample.get("fov", CAMERA_FOV)), 1.0, 179.0)
			if not pos.is_equal_approx(target):
				# Transform3D.looking_at points -Z at the target, so pass target - pos.
				desired = Transform3D.IDENTITY.looking_at(target - pos, Vector3.UP)
			desired.origin = pos
	if desired == Transform3D.IDENTITY:
		desired = Transform3D.IDENTITY.looking_at(IDLE_TARGET - IDLE_CAMERA, Vector3.UP)
		desired.origin = IDLE_CAMERA
	# The camera keeps the shot's FOV; the rig must see it before snapping.
	_camera.fov = fov
	if _camera_rig != null and _camera_rig.has_method("apply_pose"):
		var subpixel: Vector2 = _camera_rig.call("apply_pose", desired, snap)
		_set_stage_offset(subpixel, desired)
	elif _camera != null:
		_camera.global_transform = desired


func _set_stage_offset(subpixel: Vector2, pose: Transform3D) -> void:
	if stage == null or not stage.has_method("set_camera_offset"):
		return
	var texel_world := 1.0
	if _camera_rig != null and _camera_rig.has_method("texel_world"):
		texel_world = float(_camera_rig.call("texel_world"))
	var basis := pose.basis
	var texel := Vector2i(
		int(roundf(pose.origin.dot(basis.x) / maxf(texel_world, 0.0001))),
		int(roundf(pose.origin.dot(basis.y) / maxf(texel_world, 0.0001)))
	)
	stage.call("set_camera_offset", subpixel, texel)


## ------------------------------------------------------------------ probing --

## Read-only handles for the capture tools / tests (the old 2D world exposed the
## same kind of probes).
func pixel_stage():
	return stage


func lantern_count() -> int:
	return LANTERN_COUNT


func lit_lanterns() -> int:
	if _props.has("lanterns"):
		var prop: Node = _props["lanterns"]
		if is_instance_valid(prop) and prop.has_method("lit_count"):
			return int(prop.call("lit_count"))
	return _lit_lanterns


func knight_pose() -> StringName:
	if _props.has("knight_actor"):
		var prop: Node = _props["knight_actor"]
		if is_instance_valid(prop) and prop.has_method("pose"):
			return StringName(String(prop.call("pose")))
	return StringName(String(state.get("knight_pose", "stand")))


func lights() -> Array:
	var found: Array = []
	if _lighting != null and _lighting.has_method("lights"):
		return _lighting.call("lights")
	for node in find_children("*", "Light3D", true, false):
		found.append(node)
	return found


func light_count() -> int:
	return lights().size()


func shadow_lights() -> Array:
	var found: Array = []
	for node in lights():
		var light := node as Light3D
		if light != null and light.shadow_enabled:
			found.append(light)
	return found


## Software-rendering / A-B helper: toggle every shadow caster without touching the
## layout, so paired captures only differ in shadows.
func set_shadows_enabled(enabled: bool) -> void:
	for node in lights():
		var light := node as Light3D
		if light != null and light.shadow_enabled != enabled:
			light.shadow_enabled = enabled


## ------------------------------------------------------------------ events ---

func _on_prop_fired(kind: StringName, payload: Dictionary) -> void:
	event_fired.emit(kind, payload)


func _on_shot_event(kind: StringName, payload: Dictionary) -> void:
	match kind:
		&"lantern_wave":
			_restore_lanterns()
		&"hammer_strike":
			_prop_call("hammer", "strike_now")
		&"furnace_surge":
			_surge()
		&"grade_to_dark":
			if _lighting != null and _lighting.has_method("quit_out"):
				_lighting.call("quit_out", _dark_at)
	event_fired.emit(kind, payload)


func _surge() -> void:
	_react["surge"] = 1.0
	if _lighting != null and _lighting.has_method("surge"):
		_lighting.call("surge")
	_prop_call("braziers", "surge")


func _gaze() -> void:
	_react["gazing"] = 4.6
	_react["wave_active"] = 0.9
	_prop_call("knight_actor", "gaze", 4.6)


func _restore_lanterns() -> void:
	_prop_call("lanterns", "set_lit", _lit_lanterns)


func _prop_call(prop_id: String, method: String, arg = null) -> void:
	if not _props.has(prop_id):
		return
	var prop: Node = _props[prop_id]
	if not is_instance_valid(prop) or not prop.has_method(method):
		return
	if arg == null:
		prop.call(method)
	else:
		prop.call(method, arg)


static func _script(path: String) -> GDScript:
	if not ResourceLoader.exists(path):
		return null
	var res := load(path)
	return res as GDScript


## One extra warm fill light on the hero, on top of the 12-light rig (budget is 14).
## The reference frame makes the knight the brightest readable silhouette; the
## module lights alone leave him as a dark cut-out between the braziers.
func _build_hero_fill() -> void:
	var fill := OmniLight3D.new()
	fill.name = "HeroFill"
	fill.light_color = Color(1.0, 0.82, 0.62)
	fill.light_energy = 0.75
	fill.omni_range = 5.0
	fill.shadow_enabled = false
	fill.position = Vector3(0.0, 2.3, 2.6)
	add_child(fill)
	if _props.has("knight_actor"):
		var knight: Node3D = _props["knight_actor"]
		if is_instance_valid(knight):
			knight.scale = Vector3.ONE * 1.15
