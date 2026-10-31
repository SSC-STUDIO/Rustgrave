extends Node
## P0 render spike of the 3D pixel-art arena: a mid-lane slice, a controllable
## knight and looping lane minions, with a key for every look option and live
## render stats. Open scenes/moba/RenderSpike.tscn and press F6; H shows keys.
##
## User arguments after `--` start it in a given state for unattended captures:
## --autopan --demo --stress --fit --palette --unsnapped --no-shadows --outline=N
## --dither=N --height=ROWS --zoom=METRES --at=LANE_X,LANE_Z --window=WxH
## --shot-after=SECONDS --quit-after-shot

const PIXEL_STAGE := preload("res://scripts/moba/view/pixel_stage.gd")
const PIXEL_CAMERA := preload("res://scripts/moba/view/pixel_camera.gd")
const TOON_PART := preload("res://scripts/moba/view/toon_part.gd")
const KIT := preload("res://scripts/moba/view/toon_kit.gd")
const SPIKE_MAP := preload("res://scripts/moba/spike/spike_map.gd")
const KNIGHT := preload("res://scripts/moba/view/low_poly_knight.gd")
const MINION := preload("res://scripts/moba/view/spike_minion.gd")
## Loaded on first use so a renderer without depth-texture reads fails only
## when the depth outline is switched on.
const DEPTH_EDGE_SHADER := "res://assets/shaders/moba/depth_edge.gdshader"

const HERO_SPEED := 4.5
const SHOT_DIR := "user://moba_spike"
const STRESS_BATCH := 40
const OUTLINE_TEXELS := 1.15
const DITHER_STEPS: Array[float] = [0.0, 0.35, 0.7]
const OUTLINE_MODES: Array[String] = ["外壳", "深度", "外壳+深度", "关"]
const TEXT_COLOR := Color("#f2e8da")
const HELP_TEXT := "WASD/方向键 移动   J/空格/左键 挥剑   滚轮或 +/- 缩放   触屏: 按住移动, 双击挥剑\n1 内部分辨率   2 铺满/16:9   3 纹素吸附   4 亚像素平移   5 描边   6 抖动   7 调色板锁定\n8 12帧动画   9 太阳阴影   0 自动平移   M 压力测试   P 截图   H 隐藏帮助   Esc 退出"

var stage: PIXEL_STAGE
var camera: PIXEL_CAMERA
var map: SPIKE_MAP
var hero: KNIGHT

var _sun: DirectionalLight3D
## Hero and minions; untyped because their script properties are read per unit.
var _units: Array = []
var _stress: Array = []
var _pan_target: Node3D
var _depth_quad: MeshInstance3D
var _info: Label
var _help: Label
var _rng := RandomNumberGenerator.new()

var _snap := true
var _outline_mode := 0
var _dither_index := 0
var _palette := false
var _stepped := true
var _shadows := true
var _autopan := false
var _demo := false
var _clock := 0.0
var _demo_timer := 0.0
var _info_timer := 0.0
var _frame_time_sum := 0.0
var _frame_count := 0
var _toast := ""
var _toast_timer := 0.0
var _touch_index := -1
var _touch_goal := Vector3.ZERO
var _shot_timer := -1.0
var _quit_after_shot := false


func _ready() -> void:
	# Units move at priority 0; the hero and unit snapping follow here, and the
	# camera (priority 100) reads the final positions. Snapping earlier would
	# use last frame's positions and jitter.
	process_priority = 50
	_rng.seed = 20261025
	DisplayFit.apply()
	stage = PIXEL_STAGE.new()
	stage.name = "PixelStage"
	add_child(stage)
	_build_environment()
	camera = PIXEL_CAMERA.new()
	camera.name = "Camera"
	camera.stage = stage
	stage.world.add_child(camera)
	TOON_PART.outline_width = camera.texel_world() * OUTLINE_TEXELS
	map = SPIKE_MAP.new()
	map.name = "Map"
	stage.world.add_child(map)
	hero = KNIGHT.new()
	hero.name = "Hero"
	stage.world.add_child(hero)
	hero.global_position = SPIKE_MAP.lane_to_world(-11.0, 0.6)
	hero.facing = -PI * 0.25
	hero.impact.connect(_on_impact)
	_units.append(hero)
	_spawn_lane_minions()
	_pan_target = Node3D.new()
	_pan_target.name = "PanTarget"
	stage.world.add_child(_pan_target)
	camera.target = hero
	camera.focus = Vector3(hero.global_position.x, 0.0, hero.global_position.z)
	stage.layout_changed.connect(_refresh_outline_width)
	_build_overlay()
	var stress_on_start := _read_user_args()
	_apply_all()
	if stress_on_start:
		_toggle_stress()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
		return
	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _touch_index:
			_touch_goal = _ground_point(drag.position)
		return
	# Touches also arrive as emulated mouse clicks; those must not swing.
	if event.device != InputEvent.DEVICE_ID_EMULATION \
			and (event.is_action_pressed("attack") or event.is_action_pressed("jump")):
		hero.attack()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(-1.0)
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.0)
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if _handle_key(key.physical_keycode):
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_clock += delta
	if _demo:
		_demo_timer -= delta
		if _demo_timer <= 0.0:
			_demo_timer = 1.6
			hero.attack()
	_move_hero(delta)
	if _autopan:
		var center := SPIKE_MAP.lane_to_world(-6.0, 0.0)
		_pan_target.global_position = center + Vector3(sin(_clock * TAU / 20.0) * 6.0, 0.0, sin(_clock * TAU / 13.0) * 4.0)
	for gem in map.crystals:
		gem.rotation.y += delta * 0.8
		gem.position.y = float(gem.get_meta("base_y")) + sin(_clock * 2.0) * 0.12
	_snap_units()
	_update_info(delta)
	if _shot_timer >= 0.0:
		_shot_timer -= delta
		if _shot_timer < 0.0:
			_capture()
			if _quit_after_shot:
				get_tree().quit()


func _handle_key(code: Key) -> bool:
	match code:
		KEY_1:
			stage.cycle_base_height()
			_toast_message("内部分辨率: %d 行" % stage.base_height)
		KEY_2:
			stage.set_fill_screen(not stage.fill_screen)
			_toast_message("画面: %s" % ("铺满" if stage.fill_screen else "16:9 黑边"))
		KEY_3:
			_snap = not _snap
			camera.snap_enabled = _snap
			_toast_message("纹素吸附: %s" % _on(_snap))
		KEY_4:
			stage.set_subpixel(not stage.subpixel_enabled)
			_toast_message("亚像素平移: %s" % _on(stage.subpixel_enabled))
		KEY_5:
			_outline_mode = (_outline_mode + 1) % OUTLINE_MODES.size()
			_apply_outline_mode()
			_toast_message("描边: %s" % OUTLINE_MODES[_outline_mode])
		KEY_6:
			_dither_index = (_dither_index + 1) % DITHER_STEPS.size()
			stage.set_dither(DITHER_STEPS[_dither_index])
			_toast_message("抖动: %.2f" % DITHER_STEPS[_dither_index])
		KEY_7:
			_palette = not _palette
			stage.set_palette(_palette)
			_toast_message("调色板锁定: %s" % _on(_palette))
		KEY_8:
			_stepped = not _stepped
			_apply_stepped()
			_toast_message("12 帧动画: %s" % _on(_stepped))
		KEY_9:
			_shadows = not _shadows
			_sun.shadow_enabled = _shadows
			_toast_message("太阳阴影: %s" % _on(_shadows))
		KEY_0:
			_set_autopan(not _autopan)
			_toast_message("自动平移: %s" % _on(_autopan))
		KEY_EQUAL, KEY_KP_ADD:
			_zoom(-1.0)
		KEY_MINUS, KEY_KP_SUBTRACT:
			_zoom(1.0)
		KEY_M:
			_toggle_stress()
		KEY_P:
			_capture()
		KEY_H:
			_help.visible = not _help.visible
		KEY_ESCAPE:
			get_tree().quit()
		_:
			return false
	return true


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Palette.VOID
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	KIT.set_ambient(Palette.TEAL, 1.4)
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	stage.world.add_child(world_env)
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	_sun.light_color = Color("#ffe9cc")
	_sun.light_energy = 1.2
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = 70.0
	stage.world.add_child(_sun)


func _spawn_lane_minions() -> void:
	for team in 2:
		for i in 4:
			var caster := i >= 2
			var lateral := (0.9 if i % 2 == 0 else -0.9) * (0.65 if caster else 1.0)
			var progress := (14.0 if team == 0 else 22.0) + float(i) * 1.4
			_units.append(_spawn_minion(team, caster, progress, lateral))


func _spawn_minion(team: int, caster: bool, progress: float, lateral: float) -> Node3D:
	var minion := MINION.new()
	var blue_end := SPIKE_MAP.lane_to_world(-27.0, 0.0)
	var red_end := SPIKE_MAP.lane_to_world(27.0, 0.0)
	minion.team = team
	minion.caster = caster
	minion.path_from = blue_end if team == 0 else red_end
	minion.path_to = red_end if team == 0 else blue_end
	minion.progress = progress
	minion.lateral = lateral
	minion.stepped = _stepped
	stage.world.add_child(minion)
	return minion


func _toggle_stress() -> void:
	if not _stress.is_empty():
		for unit in _stress:
			if is_instance_valid(unit):
				unit.queue_free()
		_stress.clear()
		_toast_message("压力测试: 关")
		return
	for i in STRESS_BATCH:
		var unit := _spawn_minion(i % 2, _rng.randf() < 0.4, _rng.randf_range(0.0, 54.0), _rng.randf_range(-2.0, 2.0))
		_stress.append(unit)
		_units.append(unit)
	_toast_message("压力测试: +%d 小兵" % STRESS_BATCH)


func _move_hero(delta: float) -> void:
	var input := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		input.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		input.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		input.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		input.y += 1.0
	var stick := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if stick.length() > 0.2:
		input += stick
	input = input.limit_length(1.0)
	if input == Vector2.ZERO and _touch_index >= 0:
		var to := _touch_goal - hero.global_position
		if Vector2(to.x, to.z).length() > 0.25:
			input = Vector2(to.x, to.z).normalized()
	if input == Vector2.ZERO and _demo:
		input = Vector2(cos(_clock * 0.6), sin(_clock * 0.6)) * 0.5
	var dir := Vector3(input.x, 0.0, input.y)
	var speed := HERO_SPEED * (0.3 if hero.is_attacking() else 1.0)
	var step := dir * speed * delta
	var from := hero.global_position
	var pos := from
	if step.x != 0.0 and map.is_walkable(pos + Vector3(step.x, 0.0, 0.0)):
		pos.x += step.x
	if step.z != 0.0 and map.is_walkable(pos + Vector3(0.0, 0.0, step.z)):
		pos.z += step.z
	hero.global_position = pos
	hero.speed = from.distance_to(pos) / delta if delta > 0.0 else 0.0
	if not hero.is_attacking():
		hero.face_towards(dir, delta)


## Moves every unit's visual onto the camera's texel grid so a walking unit
## rasterises exactly like its previous frame, only shifted by whole texels.
func _snap_units() -> void:
	for i in range(_units.size() - 1, -1, -1):
		var unit = _units[i]
		if not is_instance_valid(unit):
			_units.remove_at(i)
			continue
		var visual: Node3D = unit.visual
		var unit_pos: Vector3 = unit.global_position
		visual.position = camera.snap_offset(unit_pos) if _snap else Vector3.ZERO


func _on_impact(at: Vector3) -> void:
	camera.add_shake(0.12)
	var ring := TOON_PART.new()
	ring.name = "ImpactRing"
	var fx := KIT.EMISSIVE | KIT.NO_OUTLINE
	for i in 8:
		var a := TAU * float(i) / 8.0
		ring.box(Vector3(0.16, 0.06, 0.42), Vector3(cos(a) * 0.5, 0.0, sin(a) * 0.5), Palette.EMBER, Vector3(0.0, -rad_to_deg(a), 0.0), fx)
	stage.world.add_child(ring)
	ring.global_position = at + Vector3(0.0, 0.05, 0.0)
	ring.build()
	ring.scale = Vector3.ONE * 0.6
	var tween := ring.create_tween()
	tween.tween_property(ring, "scale", Vector3.ONE * 1.8, 0.16)
	tween.tween_callback(ring.queue_free)


func _on_touch(touch: InputEventScreenTouch) -> void:
	if touch.pressed:
		if touch.double_tap:
			hero.attack()
		if _touch_index < 0:
			_touch_index = touch.index
			_touch_goal = _ground_point(touch.position)
	elif touch.index == _touch_index:
		_touch_index = -1
	get_viewport().set_input_as_handled()


## Root-canvas position -> point on the ground plane under it.
func _ground_point(canvas_pos: Vector2) -> Vector3:
	var texel := stage.image.to_local(canvas_pos)
	var origin := camera.project_ray_origin(texel)
	var normal := camera.project_ray_normal(texel)
	if absf(normal.y) < 0.0001:
		return hero.global_position
	return origin + normal * (-origin.y / normal.y)


func _zoom(step: float) -> void:
	camera.zoom_by(step)
	_refresh_outline_width()
	_toast_message("视野高度: %.0f m" % camera.view_height)


func _set_autopan(on: bool) -> void:
	_autopan = on
	camera.target = _pan_target if on else hero


func _apply_stepped() -> void:
	for unit in _units:
		if is_instance_valid(unit):
			unit.stepped = _stepped


func _apply_all() -> void:
	camera.snap_enabled = _snap
	stage.set_dither(DITHER_STEPS[_dither_index])
	stage.set_palette(_palette)
	_sun.shadow_enabled = _shadows
	_apply_stepped()
	_apply_outline_mode()
	_set_autopan(_autopan)
	_refresh_outline_width()


func _apply_outline_mode() -> void:
	var hulls := _outline_mode == 0 or _outline_mode == 2
	var depth := _outline_mode == 1 or _outline_mode == 2
	TOON_PART.show_hulls(get_tree(), hulls)
	if depth and _depth_quad == null:
		_depth_quad = _make_depth_quad()
	if _depth_quad != null:
		_depth_quad.visible = depth


func _make_depth_quad() -> MeshInstance3D:
	var material := ShaderMaterial.new()
	material.shader = load(DEPTH_EDGE_SHADER) as Shader
	material.set_shader_parameter("depth_range", camera.far - camera.near)
	material.set_shader_parameter("reverse_z", RenderingServer.get_current_rendering_method() != "gl_compatibility")
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var node := MeshInstance3D.new()
	node.name = "DepthEdge"
	node.mesh = quad
	node.material_override = material
	node.extra_cull_margin = 16384.0
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position = Vector3(0.0, 0.0, -1.0)
	camera.add_child(node)
	return node


## Keeps the inverted hulls one render texel wide after zoom or resolution changes.
func _refresh_outline_width() -> void:
	if camera == null:
		return
	var width := camera.texel_world() * OUTLINE_TEXELS
	if absf(width - TOON_PART.outline_width) > 0.0001:
		TOON_PART.refresh_all(get_tree(), width)


func _capture() -> void:
	var paths := stage.capture(SHOT_DIR)
	_toast_message("截图: %s" % ", ".join(paths))
	print("RenderSpike capture: ", ", ".join(paths))


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Overlay"
	layer.layer = 20
	add_child(layer)
	layer.transform = stage.overlay_transform()
	stage.layout_changed.connect(func() -> void: layer.transform = stage.overlay_transform())
	_info = _make_label(Vector2(14.0, 10.0))
	layer.add_child(_info)
	_help = _make_label(Vector2(14.0, 662.0))
	_help.text = HELP_TEXT
	layer.add_child(_help)


func _make_label(at: Vector2) -> Label:
	var label := Label.new()
	label.position = at
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.04, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	return label


func _update_info(delta: float) -> void:
	_frame_time_sum += delta
	_frame_count += 1
	_toast_timer = maxf(0.0, _toast_timer - delta)
	_info_timer -= delta
	if _info_timer > 0.0:
		return
	_info_timer = 0.25
	var frame_ms := 1000.0 * _frame_time_sum / float(maxi(_frame_count, 1))
	_frame_time_sum = 0.0
	_frame_count = 0
	var info := stage.render_info()
	var lines := PackedStringArray()
	var draws := "绘制 %d" % info["draws"]
	# GL Compatibility does not count shadow-pass draws; omit the field there.
	if int(info["shadow_draws"]) > 0:
		draws += " (+阴影 %d)" % info["shadow_draws"]
	lines.append("FPS %d   帧 %.1f ms   %s   物体 %d   三角形 %.1fk" % [
		Engine.get_frames_per_second(), frame_ms, draws, info["objects"], float(info["primitives"]) / 1000.0,
	])
	lines.append("内部 %d×%d ×%d   %s   视野 %.0f m   每纹素 %.3f m   单位 %d" % [
		stage.internal_size.x, stage.internal_size.y, stage.pixel_scale,
		"铺满" if stage.fill_screen else "16:9", camera.view_height, camera.texel_world(), _units.size(),
	])
	lines.append("吸附 %s   亚像素 %s   描边 %s   抖动 %.2f   调色板 %s   12帧 %s   阴影 %s   自动平移 %s" % [
		_on(_snap), _on(stage.subpixel_enabled), OUTLINE_MODES[_outline_mode], DITHER_STEPS[_dither_index],
		_on(_palette), _on(_stepped), _on(_shadows), _on(_autopan),
	])
	if _toast_timer > 0.0:
		lines.append(_toast)
	_info.text = "\n".join(lines)


func _toast_message(text: String) -> void:
	_toast = text
	_toast_timer = 3.0
	_info_timer = 0.0


## Applies user arguments; returns whether the stress batch should spawn.
func _read_user_args() -> bool:
	var stress := false
	for arg in OS.get_cmdline_user_args():
		var parts := arg.split("=", true, 1)
		var value := parts[1] if parts.size() > 1 else ""
		match parts[0]:
			"--autopan":
				_autopan = true
			"--demo":
				_demo = true
			"--stress":
				stress = true
			"--fit":
				stage.set_fill_screen(false)
			"--palette":
				_palette = true
			"--unsnapped":
				_snap = false
			"--no-shadows":
				_shadows = false
			"--outline":
				_outline_mode = clampi(value.to_int(), 0, OUTLINE_MODES.size() - 1)
			"--dither":
				_dither_index = clampi(value.to_int(), 0, DITHER_STEPS.size() - 1)
			"--height":
				stage.base_height = clampi(value.to_int(), 180, 1080)
				stage.relayout()
			"--zoom":
				camera.view_height = clampf(value.to_float(), 8.0, 24.0)
			"--window":
				var wh := value.split_floats("x")
				if wh.size() == 2:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
					DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
			"--at":
				var lane := value.split_floats(",")
				if lane.size() == 2:
					hero.global_position = SPIKE_MAP.lane_to_world(lane[0], lane[1])
					camera.focus = Vector3(hero.global_position.x, 0.0, hero.global_position.z)
			"--shot-after":
				_shot_timer = maxf(0.0, value.to_float())
			"--quit-after-shot":
				_quit_after_shot = true
	return stress


static func _on(value: bool) -> String:
	return "开" if value else "关"
