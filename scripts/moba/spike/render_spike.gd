extends Node
## Playable 3D arena: a mid-lane slice driven by the deterministic MobaSim.
##
## MobaSim (scripts/moba/sim/moba_sim.gd) runs at a fixed 30 Hz; this scene
## accumulates frame time, steps it, and pulls every position/anim state from
## `entities()`/`structures()` each frame. Nothing here decides damage: hits,
## deaths, waves and the winner are settled by the simulation, the view only
## plays slash / impact / hit-flash / death-fade and shows the HUD.
##
## F3 opts into render statistics and the original look controls; R restarts
## the match, Esc / the native button returns to the title.
##
## User arguments after `--` start it in a given state for unattended captures:
## --autopan --demo --stress --fit --palette --unsnapped --no-shadows --outline=N
## --dither=N --height=ROWS --zoom=METRES --at=LANE_X,LANE_Y --window=WxH
## --debug --shot-after=SECONDS --quit-after-shot
## --auto --speed=N --seed=N --auto-shots=open:1.5,mid:30,end --shot-dir=PATH

const PIXEL_STAGE := preload("res://scripts/moba/view/pixel_stage.gd")
const PIXEL_CAMERA := preload("res://scripts/moba/view/pixel_camera.gd")
const TOON_PART := preload("res://scripts/moba/view/toon_part.gd")
const KIT := preload("res://scripts/moba/view/toon_kit.gd")
const SPIKE_MAP := preload("res://scripts/moba/spike/spike_map.gd")
const KNIGHT := preload("res://scripts/moba/view/low_poly_knight.gd")
const MINION := preload("res://scripts/moba/view/spike_minion.gd")
const RUN := preload("res://scripts/moba/moba_run.gd")
const VIEW_MAP := preload("res://scripts/moba/present/moba_view_map.gd")
const HUD := preload("res://scripts/moba/present/moba_hud.gd")
const UNIT_POOL := preload("res://scripts/moba/present/moba_unit_pool.gd")
const IMPACT_POOL := preload("res://scripts/moba/present/moba_impact_pool.gd")
const STRUCTURE_VIEW := preload("res://scripts/moba/present/moba_structure_view.gd")
const FX := preload("res://scripts/moba/present/moba_unit_fx.gd")
## Loaded on first use so a renderer without depth-texture reads fails only
## when the depth outline is switched on.
const DEPTH_EDGE_SHADER := "res://assets/shaders/moba/depth_edge.gdshader"
const SIM_PATH := "res://scripts/moba/sim/moba_sim.gd"

const HERO_SPEED := 4.5
const SHOT_DIR := "user://moba_spike"
const STRESS_BATCH := 40
const OUTLINE_TEXELS := 1.15
const DITHER_STEPS: Array[float] = [0.0, 0.35, 0.7]
const OUTLINE_MODES: Array[String] = ["外壳", "深度", "外壳+深度", "关"]
const TEXT_COLOR := Color("#f2e8da")
const MODE_NAME := "余烬竞技场 · 3D试演"
const HELP_TEXT := "1 内部分辨率   2 铺满/16:9   3 纹素吸附   4 亚像素平移\n5 描边   6 抖动   7 调色板锁定   8 12帧动画   9 太阳阴影\n0 自动平移   M 压力测试   P 截图   H 隐藏调试帮助   F3 关闭调试"
## MobaSim runs at a fixed 30 Hz; the view accumulates real frame time into
## whole ticks and never feeds variable dt into the simulation.
const STEP_SECONDS := 1.0 / 30.0
const MAX_STEPS_PER_FRAME := 48
const MATCH_SEED := 20261101
const HERO_SMOOTHING := 24.0
const HERO_DEATH_FADE := 0.7
const HERO_ATTACK_RANGE := 2.2

var stage: PIXEL_STAGE
var camera: PIXEL_CAMERA
var map: SPIKE_MAP
var hero: KNIGHT
## MobaSim instance (RefCounted); null until scripts/moba/sim lands, which the
## HUD reports instead of silently running a fake match.
var sim: RefCounted = null

var _sun: DirectionalLight3D
## Hero plus the optional debug stress batch; untyped because their script
## properties are read per unit.
var _units: Array = []
var _stress: Array = []
var _unit_pool: Node3D
var _impact_pool: Node3D
## "team:kind" -> MobaStructureView
var _structures: Dictionary = {}
var _hud: Node
var _pan_target: Node3D
var _depth_quad: MeshInstance3D
var _overlay: CanvasLayer
var _mode_label: Label
var _player_hint: Label
var _return_button: Button
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
var _debug := false
var _leaving := false
var _pad_actions := {&"move_left": {}, &"move_right": {}, &"ui_up": {}, &"ui_down": {}}

## Simulation step accumulator and time scale for unattended captures.
var _step_accum := 0.0
var _speed_scale := 1.0
var _match_seed := MATCH_SEED
var _restart_count := 0
var _args: Dictionary = {}

## Presentation state pulled from the simulation.
var _hero_entity: Dictionary = {}
var _hero_dead := false
var _hero_fade := 1.0
var _hero_parts: Array[MeshInstance3D] = []
var _hero_flash_timer := 0.0
var _hero_anim: StringName = &""
var _hero_controllable := true
var _hero_respawn_ms := 0
var _prev_hp: Dictionary = {}
var _outcome: StringName = &""
## Every non-player hero the sim publishes (currently the red AI knight); the
## player hero keeps its dedicated `hero` view and camera/input ownership.
var _enemy_heroes: Dictionary = {}
var _enemy_display: Dictionary = {}

## Autopilot + tagged captures for the acceptance screenshots.
var _auto := false
var _auto_last_target := -1
var _auto_log_tick := 0
var _quit_after_sim := -1.0
var _auto_shots: Array[Dictionary] = []
var _pending_shot: Dictionary = {}
var _pending_shot_delay := 0
var _shot_peek_dir := ""


func _ready() -> void:
	_parse_args()
	RUN.attach(self)
	Input.joy_connection_changed.connect(_on_pad_connection_changed)
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
	_build_sim()
	_build_actors()
	_build_structures()
	_pan_target = Node3D.new()
	_pan_target.name = "PanTarget"
	stage.world.add_child(_pan_target)
	camera.target = hero
	camera.focus = Vector3(hero.global_position.x, 0.0, hero.global_position.z)
	stage.layout_changed.connect(_refresh_outline_width)
	_build_overlay()
	var stress_on_start := _apply_args()
	_apply_all()
	_set_debug(_debug)
	if stress_on_start:
		_toggle_stress()
	_sync_world(0.0)
	_snap_units()


func _exit_tree() -> void:
	RUN.detach(self)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_inside_tree():
		_return_to_title()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_touch_index = -1
		_clear_pad_input()


func _return_to_title() -> void:
	if _leaving or Director.is_fading():
		return
	_leaving = true
	_touch_index = -1
	_touch_goal = Vector3.ZERO
	_clear_pad_input()
	if hero != null:
		hero.speed = 0.0
	if sim != null and sim.has_method("set_move"):
		sim.set_move(Vector2.ZERO)
	if _return_button != null:
		_return_button.disabled = true
	if not RUN.exit_to_title():
		_leaving = false
		if _return_button != null:
			_return_button.disabled = false


func _input(event: InputEvent) -> void:
	if _leaving:
		return
	# Settings rebuilds pad bindings with device 0. Keep the same buttons/axes
	# for every controller without mutating the shared InputMap on scene entry.
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_track_pad_input(event)


func _track_pad_input(event: InputEvent) -> void:
	for action in _pad_actions:
		var held: Dictionary = _pad_actions[action]
		for binding in InputMap.action_get_events(action):
			var token := ""
			var strength := 0.0
			if event is InputEventJoypadButton and binding is InputEventJoypadButton \
					and event.button_index == binding.button_index:
				token = "%d:button:%d" % [event.device, event.button_index]
				strength = 1.0 if event.pressed else 0.0
			elif event is InputEventJoypadMotion and binding is InputEventJoypadMotion \
					and event.axis == binding.axis:
				token = "%d:axis:%d" % [event.device, event.axis]
				var zone := InputMap.action_get_deadzone(action)
				strength = clampf((event.axis_value * signf(binding.axis_value) - zone)
						/ maxf(1.0 - zone, 0.001), 0.0, 1.0)
			if not token.is_empty():
				if strength > 0.0:
					held[token] = strength
				else:
					held.erase(token)


func _pad_strength(action: StringName) -> float:
	var strength := 0.0
	for value in (_pad_actions[action] as Dictionary).values():
		strength = maxf(strength, float(value))
	return strength


func _clear_pad_input() -> void:
	for held: Dictionary in _pad_actions.values():
		held.clear()


func _on_pad_connection_changed(device: int, connected: bool) -> void:
	if connected:
		return
	for held: Dictionary in _pad_actions.values():
		for token: String in held.keys():
			if token.begins_with("%d:" % device):
				held.erase(token)


func _unhandled_input(event: InputEvent) -> void:
	if _leaving or Director.is_fading():
		return
	var bound_event := event
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		bound_event = event.duplicate() as InputEvent
		bound_event.device = 0
	if bound_event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_return_to_title()
		return
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
			and (bound_event.is_action_pressed("attack") or bound_event.is_action_pressed("jump")):
		_attack_command()
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
	var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	if _handle_key(code):
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _leaving or Director.is_fading():
		return
	_clock += delta
	if _demo and sim == null:
		_demo_timer -= delta
		if _demo_timer <= 0.0:
			_demo_timer = 1.6
			if hero != null:
				hero.attack()
	if _auto:
		_auto_input(delta)
	_move_hero(delta)
	if _autopan:
		var center := SPIKE_MAP.lane_to_world(-6.0, 0.0)
		_pan_target.global_position = center + Vector3(sin(_clock * TAU / 20.0) * 6.0, 0.0, sin(_clock * TAU / 13.0) * 4.0)
	_advance_sim(delta)
	_sync_world(delta)
	_snap_units()
	_refresh_player_hint()
	_update_info(delta)
	if _shot_timer >= 0.0:
		_shot_timer -= delta
		if _shot_timer < 0.0:
			_capture()
			_quit_if_done()
	_handle_auto_shots()


func _handle_key(code: Key) -> bool:
	if _leaving or Director.is_fading():
		return false
	match code:
		KEY_ESCAPE:
			_return_to_title()
			return true
		KEY_F3:
			_set_debug(not _debug)
			return true
		KEY_R:
			restart_match()
			return true
		KEY_EQUAL, KEY_KP_ADD:
			_zoom(-1.0)
			return true
		KEY_MINUS, KEY_KP_SUBTRACT:
			_zoom(1.0)
			return true
	if not _debug:
		return false
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
		KEY_M:
			_toggle_stress()
		KEY_P:
			_capture()
		KEY_H:
			_help.visible = not _help.visible
		_:
			return false
	return true


func _toggle_stress() -> void:
	if not _stress.is_empty():
		for unit in _stress:
			if is_instance_valid(unit):
				unit.queue_free()
		_stress.clear()
		for i in range(_units.size() - 1, -1, -1):
			if not is_instance_valid(_units[i]):
				_units.remove_at(i)
		_toast_message("压力测试: 关")
		return
	for i in STRESS_BATCH:
		var unit := _spawn_minion(i % 2, _rng.randf() < 0.4, _rng.randf_range(0.0, 54.0), _rng.randf_range(-2.0, 2.0))
		_stress.append(unit)
		_units.append(unit)
	_toast_message("压力测试: +%d 小兵" % STRESS_BATCH)


## Render-only looping walker for the F3 stress tool. The playable lane minions
## are pooled sim entities (MobaUnitPool); this batch exists only to push draw
## call numbers around when validating the render pipeline.
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


# ------------------------------------------------------------ simulation --

func _build_sim() -> void:
	if not ResourceLoader.exists(SIM_PATH):
		sim = null
		print("ArenaSpike: MobaSim missing at ", SIM_PATH, " - view-only preview")
		return
	var script := load(SIM_PATH) as GDScript
	if script == null:
		sim = null
		print("ArenaSpike: MobaSim failed to load")
		return
	sim = script.new(_match_seed)
	print("ArenaSpike: MobaSim seed=", _match_seed)


func _advance_sim(delta: float) -> void:
	if sim == null:
		return
	_step_accum += delta * _speed_scale
	var steps := 0
	while _step_accum >= STEP_SECONDS and steps < MAX_STEPS_PER_FRAME:
		sim.step()
		_step_accum -= STEP_SECONDS
		steps += 1
	if steps >= MAX_STEPS_PER_FRAME:
		# Do not let a huge frame drop queue minutes of catch-up ticks.
		_step_accum = 0.0
	if _auto and steps > 0 and _sim_tick_count() - _auto_log_tick >= 300:
		_auto_log_tick = _sim_tick_count()
		_auto_log()


## Progress line for unattended runs (stdout only; the player never sees it).
func _auto_log() -> void:
	var hero_lane := UNIT_POOL.lane_of(_hero_entity) if not _hero_entity.is_empty() else Vector2.ZERO
	var blue_hp := float(VIEW_MAP.CRYSTAL_HP)
	var red_hp := float(VIEW_MAP.CRYSTAL_HP)
	var blue_tower := float(VIEW_MAP.TOWER_HP)
	var red_tower := float(VIEW_MAP.TOWER_HP)
	for team in [VIEW_MAP.TEAM_BLUE, VIEW_MAP.TEAM_RED]:
		for raw in _sim_structures(team):
			if not (raw is Dictionary):
				continue
			var row: Dictionary = raw
			var kind := StringName(row.get("kind", &""))
			if kind == &"crystal":
				if team == VIEW_MAP.TEAM_BLUE:
					blue_hp = float(row.get("hp", blue_hp))
				else:
					red_hp = float(row.get("hp", red_hp))
			elif kind == &"tower":
				if team == VIEW_MAP.TEAM_BLUE:
					blue_tower = float(row.get("hp", blue_tower))
				else:
					red_tower = float(row.get("hp", red_tower))
	print("ArenaSpike auto: t=%.1fs wave=%d hero=(%.1f,%.1f) hp=%d dead=%s target=%d blue_tower=%.0f red_tower=%.0f blue_crystal=%.0f red_crystal=%.0f enemy_hero=%s minions=%d outcome=%s" % [
		float(_sim_time_ms()) / 1000.0, _sim_wave_index(), hero_lane.x, hero_lane.y,
		int(_hero_entity.get("hp", 0)), _hero_dead, _auto_last_target, blue_tower, red_tower,
		blue_hp, red_hp, str(_enemy_display.get("hp", "-")), _unit_pool.active_count(), String(_outcome),
	])


## Test/autopilot seam: run whole fixed ticks through the same sync path the
## frame loop uses, so a match can be exercised without waiting real time.
func step_sim(ticks: int) -> void:
	if sim == null:
		return
	for i in maxi(ticks, 0):
		sim.step()
		_sync_world(STEP_SECONDS)
	_snap_units()


## Pull the simulation state into every view right now.
func sync_now(delta: float = STEP_SECONDS) -> void:
	_sync_world(delta)
	_snap_units()


func _sync_world(delta: float) -> void:
	if sim == null:
		_sync_hud()
		return
	var entities: Array = _sim_entities()
	var hero_id := _sim_hero_id()
	var hero_entity: Dictionary = {}
	var minions: Array = []
	var enemy_heroes: Array = []
	for raw in entities:
		if raw is not Dictionary:
			continue
		var entity: Dictionary = raw
		var kind := StringName(entity.get("kind", &"minion"))
		var id := int(entity.get("id", 0))
		_note_entity_damage(entity)
		if id == hero_id:
			hero_entity = entity
		elif kind == &"hero":
			enemy_heroes.append(entity)
		elif kind == &"minion":
			minions.append(entity)
	_hero_entity = hero_entity
	_unit_pool.sync(minions, delta)
	_sync_hero(hero_entity, delta)
	_sync_enemy_heroes(enemy_heroes, delta)
	_sync_structures(delta)
	_impact_pool.advance(delta)
	# Note the outcome before the HUD snapshot so the result banner appears on
	# the frame the crystal falls, not one frame later.
	_note_outcome(_sim_outcome())
	_sync_hud()


func _sync_hero(entity: Dictionary, delta: float) -> void:
	if hero == null:
		return
	var state: Dictionary = _sim_hero_state()
	var alive := bool(state.get("alive", not entity.is_empty() and bool(entity.get("alive", true))))
	var can_act := bool(state.get("can_act", alive))
	_hero_controllable = can_act
	_hero_respawn_ms = _respawn_ms(state)
	var anim := UNIT_POOL.anim_of(entity) if not entity.is_empty() else (&"dead" if not alive else &"idle")
	var target := hero.global_position
	if not entity.is_empty():
		target = VIEW_MAP.lane_to_world(UNIT_POOL.lane_of(entity))
	var smoothing := 1.0 if delta <= 0.0 else 1.0 - exp(-HERO_SMOOTHING * delta)
	hero.global_position = hero.global_position.lerp(target, clampf(smoothing, 0.0, 1.0))
	if anim == &"run":
		if hero.speed < 0.5:
			hero.speed = HERO_SPEED
	elif anim != &"attack":
		hero.speed = 0.0
	if not entity.is_empty():
		var facing := int(entity.get("facing", 1))
		if facing != 0:
			hero.face_towards(VIEW_MAP.lane_dir_to_world(Vector2(float(facing), 0.0)), delta)
	if anim == &"attack" and _hero_anim != &"attack" and not _hero_dead:
		hero.attack()
	_hero_anim = anim
	if _hero_flash_timer > 0.0:
		_hero_flash_timer -= delta
		if _hero_flash_timer <= 0.0:
			FX.set_flash(_hero_parts, false)
	if anim == &"dead" or not alive:
		_enter_hero_death(delta)
	elif _hero_dead:
		_leave_hero_death(target)


func _enter_hero_death(delta: float) -> void:
	if not _hero_dead:
		_hero_dead = true
		_hero_fade = 1.0
		hero.speed = 0.0
		_toast_message("余烬骑士阵亡")
	_hero_fade = maxf(0.0, _hero_fade - delta / HERO_DEATH_FADE)
	FX.set_fade(_hero_parts, _hero_fade)
	hero.rotation.z = deg_to_rad(74.0) * (1.0 - _hero_fade)
	if _hero_fade <= 0.0:
		hero.visible = false


func _leave_hero_death(target: Vector3) -> void:
	_hero_dead = false
	_hero_fade = 1.0
	_hero_flash_timer = 0.0
	FX.set_fade(_hero_parts, 1.0)
	FX.set_flash(_hero_parts, false)
	hero.visible = true
	hero.rotation = Vector3.ZERO
	hero.global_position = target
	_hero_anim = &""


## Every non-player hero the sim publishes (the red AI knight once it lands)
## gets its own knight view with a permanent red tint so the two teams read
## apart at a glance. The player knight keeps the `hero` view.
func _sync_enemy_heroes(entities: Array, delta: float) -> void:
	var seen: Dictionary = {}
	for raw in entities:
		if raw is not Dictionary:
			continue
		var entity: Dictionary = raw
		var id := int(entity.get("id", 0))
		seen[id] = true
		var state: Dictionary = _enemy_heroes.get(id, {})
		if state.is_empty():
			state = _create_enemy_hero(id)
			_enemy_heroes[id] = state
		var view: KNIGHT = state["view"]
		var parts: Array = state["parts"]
		var anim := UNIT_POOL.anim_of(entity)
		var alive := bool(entity.get("alive", true))
		state["hp"] = float(entity.get("hp", 0.0))
		state["max_hp"] = float(entity.get("max_hp", VIEW_MAP.HERO_HP))
		var target := VIEW_MAP.lane_to_world(UNIT_POOL.lane_of(entity))
		var smoothing := 1.0 if delta <= 0.0 else 1.0 - exp(-HERO_SMOOTHING * delta)
		view.global_position = view.global_position.lerp(target, clampf(smoothing, 0.0, 1.0))
		if bool(state.get("dead", false)) and (alive and anim != &"dead"):
			# Respawned: put the knight back on its feet at the base.
			state["dead"] = false
			state["fade"] = 1.0
			state["anim"] = &""
			state["flash"] = 0.0
			FX.set_fade(parts, 1.0)
			FX.set_overlay(parts, state["tint"])
			view.visible = true
			view.rotation = Vector3.ZERO
			view.global_position = target
		if not alive or anim == &"dead":
			if not bool(state.get("dead", false)):
				state["dead"] = true
				state["fade"] = 1.0
			state["fade"] = maxf(0.0, float(state["fade"]) - delta / HERO_DEATH_FADE)
			FX.set_fade(parts, float(state["fade"]))
			view.rotation.z = deg_to_rad(74.0) * (1.0 - float(state["fade"]))
			if float(state["fade"]) <= 0.0:
				view.visible = false
			continue
		view.speed = HERO_SPEED if anim == &"run" else 0.0
		var facing := int(entity.get("facing", 1))
		if facing != 0:
			view.face_towards(VIEW_MAP.lane_dir_to_world(Vector2(float(facing), 0.0)), delta)
		if anim == &"attack" and StringName(state.get("anim", &"")) != &"attack":
			view.attack()
		state["anim"] = anim
		if float(state.get("flash", 0.0)) > 0.0:
			state["flash"] = maxf(0.0, float(state["flash"]) - delta)
			if float(state["flash"]) <= 0.0:
				FX.set_overlay(parts, state["tint"])
	for id_v in _enemy_heroes.keys():
		var id := int(id_v)
		if seen.has(id):
			continue
		var state: Dictionary = _enemy_heroes[id]
		var view: KNIGHT = state["view"]
		if is_instance_valid(view):
			view.queue_free()
		_enemy_heroes.erase(id)
	_enemy_display = _enemy_hero_display()


func _create_enemy_hero(id: int) -> Dictionary:
	var view: KNIGHT = KNIGHT.new()
	view.name = "EnemyHero%d" % id
	view.team = VIEW_MAP.TEAM_RED
	stage.world.add_child(view)
	view.global_position = VIEW_MAP.lane_to_world(Vector2(VIEW_MAP.BASE_LANE_X, 0.0))
	view.facing = VIEW_MAP.yaw_for_facing(-1)
	var parts := FX.collect_parts(view)
	var tint := FX.tint_material(KIT.team_color(VIEW_MAP.TEAM_RED), 0.28)
	FX.set_overlay(parts, tint)
	return {
		"view": view, "parts": parts, "tint": tint, "anim": &"", "dead": false,
		"fade": 1.0, "flash": 0.0, "hp": VIEW_MAP.HERO_HP, "max_hp": VIEW_MAP.HERO_HP,
	}


func _enemy_hero_display() -> Dictionary:
	for state: Dictionary in _enemy_heroes.values():
		return {
			"visible": true,
			"hp": float(state.get("hp", 0.0)),
			"max_hp": float(state.get("max_hp", VIEW_MAP.HERO_HP)),
			"alive": not bool(state.get("dead", false)),
		}
	return {}


func _flash_enemy_hero(id: int) -> void:
	var state: Dictionary = _enemy_heroes.get(id, {})
	if state.is_empty():
		return
	state["flash"] = 0.1
	FX.set_flash(state["parts"], true)


func _sync_structures(delta: float) -> void:
	if _structures.is_empty():
		return
	for team in [VIEW_MAP.TEAM_BLUE, VIEW_MAP.TEAM_RED]:
		var rows: Array = _sim_structures(team)
		var by_kind: Dictionary = {}
		for raw in rows:
			if raw is Dictionary:
				var row: Dictionary = raw
				by_kind[StringName(row.get("kind", &"tower"))] = row
		for kind: StringName in [&"tower", &"crystal"]:
			var view: Variant = _structures.get(_structure_key(team, kind))
			if view == null:
				continue
			var row: Dictionary = by_kind.get(kind, {})
			var full := VIEW_MAP.structure_hp(kind)
			var hp := float(row.get("hp", full))
			var max_hp := float(row.get("max_hp", full))
			var alive := bool(row.get("alive", hp > 0.0))
			var before: float = view.hp
			view.apply(hp, max_hp, alive)
			if hp < before - 0.01:
				_impact_pool.spawn(view.global_position + Vector3(0.0, 1.2, 0.0), 0.9)
			if view.destroyed and before > 0.0:
				_impact_pool.spawn(view.global_position + Vector3(0.0, 1.6, 0.0), 1.3)
				camera.add_shake(0.25)
			# Drives the hit-flash decay, the crystal bob and the topple / shatter
			# animation; without this call a damage flash would never end.
			view.advance(delta)


func _note_entity_damage(entity: Dictionary) -> void:
	var id := int(entity.get("id", 0))
	var hp := float(entity.get("hp", 0.0))
	var prev: Variant = _prev_hp.get(id)
	_prev_hp[id] = hp
	if prev == null:
		return
	if hp >= float(prev) - 0.01:
		return
	# Structures have a pushed-out 3D plinth; MobaStructureView reports their
	# damage at the visual position, so only lane units spark here.
	var kind := StringName(entity.get("kind", &"minion"))
	if kind == &"tower" or kind == &"crystal":
		return
	var pos := VIEW_MAP.lane_to_world(UNIT_POOL.lane_of(entity), 0.7)
	_impact_pool.spawn(pos, 0.55)
	if id == _sim_hero_id():
		_hero_flash_timer = 0.1
		FX.set_flash(_hero_parts, true)
		camera.add_shake(0.1)
	elif _enemy_heroes.has(id):
		_flash_enemy_hero(id)
	else:
		_unit_pool.flash(id)


func _note_outcome(outcome: StringName) -> void:
	if String(outcome).is_empty() or _outcome == outcome:
		return
	_outcome = outcome
	_toast_message("对局结束: %s" % HUD.result_text(outcome))
	print("ArenaSpike: match over outcome=", outcome, " ticks=", _sim_tick_count(), " seed=", _match_seed)
	if _args.has("--quit-on-outcome") and _auto_shots.is_empty():
		_quit_after_shot = true
		get_tree().quit()


# ------------------------------------------------------------------ views --

func _build_actors() -> void:
	hero = KNIGHT.new()
	hero.name = "Hero"
	stage.world.add_child(hero)
	hero.impact.connect(_on_impact)
	hero.global_position = VIEW_MAP.lane_to_world(Vector2(-VIEW_MAP.BASE_LANE_X, 0.0))
	hero.facing = VIEW_MAP.yaw_for_facing(1)
	_hero_parts = FX.collect_parts(hero)
	_units.append(hero)
	_unit_pool = UNIT_POOL.new()
	_unit_pool.name = "Minions"
	stage.world.add_child(_unit_pool)
	_impact_pool = IMPACT_POOL.new()
	_impact_pool.name = "Impacts"
	stage.world.add_child(_impact_pool)


func _build_structures() -> void:
	for team in [VIEW_MAP.TEAM_BLUE, VIEW_MAP.TEAM_RED]:
		for kind: StringName in [&"tower", &"crystal"]:
			var view: Node3D = STRUCTURE_VIEW.new()
			view.name = "%s_%d" % [kind, team]
			view.setup(kind, team)
			stage.world.add_child(view)
			view.global_position = VIEW_MAP.structure_world(kind, team)
			_structures[_structure_key(team, kind)] = view


static func _structure_key(team: int, kind: StringName) -> String:
	return "%d:%s" % [team, kind]


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
	for view in _unit_pool.active_views():
		if not is_instance_valid(view):
			continue
		var visual: Node3D = view.visual
		visual.position = camera.snap_offset(view.global_position) if _snap else Vector3.ZERO
	for state: Dictionary in _enemy_heroes.values():
		var view: KNIGHT = state["view"]
		if is_instance_valid(view):
			view.visual.position = camera.snap_offset(view.global_position) if _snap else Vector3.ZERO


func _on_impact(at: Vector3) -> void:
	if _leaving or Director.is_fading():
		return
	camera.add_shake(0.12)
	_impact_pool.spawn(at, 1.0)


## Player attack input: the sim settles the hit, the knight plays the swing.
func _attack_command() -> void:
	if _leaving or Director.is_fading() or _hero_dead or not _hero_controllable:
		return
	if sim != null and sim.has_method("command_attack"):
		sim.command_attack()
	if hero != null and not hero.is_attacking():
		hero.attack()


# ------------------------------------------------------------------- input --

func _read_move_input() -> Vector2:
	# Actions include rebound keys, D-pad and sticks from every connected pad.
	# W/S remain convenient vertical shortcuts alongside the standard UI axis.
	var input := Vector2(
		maxf(Input.get_action_strength("move_right"), _pad_strength(&"move_right"))
			- maxf(Input.get_action_strength("move_left"), _pad_strength(&"move_left")),
		maxf(Input.get_action_strength("ui_down"), _pad_strength(&"ui_down"))
			- maxf(Input.get_action_strength("ui_up"), _pad_strength(&"ui_up")))
	input.y = clampf(input.y + float(Input.is_physical_key_pressed(KEY_S))
			- float(Input.is_physical_key_pressed(KEY_W)), -1.0, 1.0)
	return input.limit_length(1.0)


func _move_hero(delta: float) -> void:
	if _leaving or Director.is_fading():
		hero.speed = 0.0
		return
	if _auto:
		# The autopilot issues its own sim commands from _auto_input(); issuing
		# an empty move here would cancel them every frame.
		return
	if _outcome != &"" or _hero_dead:
		if sim != null and sim.has_method("set_move"):
			sim.set_move(Vector2.ZERO)
		hero.speed = 0.0
		return
	var input := Vector2.ZERO
	input = _read_move_input()
	if input == Vector2.ZERO and _touch_index >= 0:
		# Touch keeps its "walk to the touched ground point" behaviour; the
		# goal is converted back into the lane frame the sim moves on.
		var lane := VIEW_MAP.world_to_lane(hero.global_position)
		var goal := VIEW_MAP.world_to_lane(_touch_goal)
		var delta_lane := goal - lane
		if delta_lane.length() > 0.25:
			input = delta_lane.normalized()
	if input == Vector2.ZERO and _demo:
		input = Vector2(cos(_clock * 0.6), sin(_clock * 0.6)) * 0.5
	if not _hero_controllable:
		input = Vector2.ZERO
	var lane_dir := input.limit_length(1.0)
	if sim != null and sim.has_method("set_move"):
		sim.set_move(lane_dir)
	if lane_dir == Vector2.ZERO:
		hero.speed = 0.0
		return
	var world_dir := VIEW_MAP.lane_dir_to_world(lane_dir)
	world_dir.y = 0.0
	if world_dir.length_squared() < 0.000001:
		hero.speed = 0.0
		return
	world_dir = world_dir.normalized()
	# Local prediction: the sim is authoritative and _sync_hero pulls the view
	# back onto its position every frame, but moving on the input frame keeps
	# the knight responsive between 30 Hz ticks.
	hero.global_position += world_dir * HERO_SPEED * delta
	hero.speed = HERO_SPEED
	if not hero.is_attacking():
		hero.face_towards(world_dir, delta)


func _on_touch(touch: InputEventScreenTouch) -> void:
	if _leaving or Director.is_fading():
		return
	if touch.pressed:
		if touch.double_tap:
			_attack_command()
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


# ---------------------------------------------------------------- restart --

## Restarts the match with the next recorded seed and rebuilds every view from
## the fresh simulation state (nothing from the previous match may linger).
func restart_match() -> void:
	if _leaving and not is_inside_tree():
		return
	_restart_count += 1
	_match_seed += 1
	_outcome = &""
	_hero_entity = {}
	_hero_anim = &""
	_prev_hp.clear()
	_step_accum = 0.0
	_hero_dead = false
	_hero_fade = 1.0
	_hero_flash_timer = 0.0
	_auto_log_tick = 0
	_auto_last_target = -1
	_unit_pool.clear()
	_impact_pool.clear()
	for state: Dictionary in _enemy_heroes.values():
		var enemy_view: KNIGHT = state["view"]
		if is_instance_valid(enemy_view):
			enemy_view.queue_free()
	_enemy_heroes.clear()
	_enemy_display = {}
	for view in _structures.values():
		if is_instance_valid(view):
			view.reset_state()
	if hero != null:
		hero.visible = true
		hero.rotation = Vector3.ZERO
		hero.speed = 0.0
		FX.set_fade(_hero_parts, 1.0)
		FX.set_flash(_hero_parts, false)
		hero.global_position = VIEW_MAP.lane_to_world(Vector2(-VIEW_MAP.BASE_LANE_X, 0.0))
		hero.facing = VIEW_MAP.yaw_for_facing(1)
	if sim != null and sim.has_method("reset"):
		sim.reset(_match_seed)
	_sync_world(1.0)
	_center_camera()
	_toast_message("重开 · 种子 %d（第 %d 局）" % [_match_seed, _restart_count + 1])
	print("ArenaSpike: rematch seed=", _match_seed)


# -------------------------------------------------------------------- hud --

func _sync_hud() -> void:
	if _hud == null:
		return
	_hud.apply(_hud_snapshot())


func _hud_snapshot() -> Dictionary:
	var snapshot := {
		"outcome": _outcome,
		"wave_index": _sim_wave_index(),
		"next_wave_ms": _sim_next_wave_remaining_ms(),
		"wave_active": false,
		"blue": _hud_side(VIEW_MAP.TEAM_BLUE),
		"red": _hud_side(VIEW_MAP.TEAM_RED),
		"hero": _hud_hero(),
		"enemy_hero": _enemy_display,
		"seed": _match_seed,
		"ticks": _sim_tick_count(),
	}
	return snapshot


func _hud_side(team: int) -> Dictionary:
	var crystal_hp := VIEW_MAP.CRYSTAL_HP
	var crystal_max := VIEW_MAP.CRYSTAL_HP
	for raw in _sim_structures(team):
		if raw is not Dictionary:
			continue
		var row: Dictionary = raw
		if StringName(row.get("kind", &"")) != &"crystal":
			continue
		crystal_hp = float(row.get("hp", crystal_hp))
		crystal_max = float(row.get("max_hp", crystal_max))
	return {
		"crystal_hp": crystal_hp,
		"crystal_max": crystal_max,
		"crystal_alive": crystal_hp > 0.0,
	}


func _hud_hero() -> Dictionary:
	var state: Dictionary = _sim_hero_state()
	var hp := float(state.get("hp", VIEW_MAP.HERO_HP))
	var max_hp := float(state.get("max_hp", VIEW_MAP.HERO_HP))
	if not _hero_entity.is_empty():
		hp = float(_hero_entity.get("hp", hp))
		max_hp = float(_hero_entity.get("max_hp", max_hp))
	return {
		"hp": hp,
		"max_hp": max_hp,
		"alive": not _hero_dead,
		"respawn_ms": _hero_respawn_ms,
	}


# ---------------------------------------------------------------- overlay --

func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.name = "Overlay"
	_overlay.layer = 20
	add_child(_overlay)
	_mode_label = _make_label(Vector2(18.0, 16.0))
	_mode_label.name = "ModeName"
	_mode_label.text = MODE_NAME
	_mode_label.add_theme_font_size_override("font_size", 20)
	_overlay.add_child(_mode_label)
	_player_hint = _make_label(Vector2(18.0, 640.0))
	_player_hint.name = "PlayerHint"
	_player_hint.add_theme_font_size_override("font_size", 14)
	_player_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overlay.add_child(_player_hint)
	_return_button = Button.new()
	_return_button.name = "ReturnToTitle"
	_return_button.text = "返回标题"
	_return_button.size = Vector2(140.0, 42.0)
	_return_button.add_theme_font_size_override("font_size", 16)
	_return_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_return_button.pressed.connect(_return_to_title)
	_return_button.resized.connect(_layout_overlay)
	_overlay.add_child(_return_button)
	_info = _make_label(Vector2(18.0, 214.0))
	_info.name = "RenderStats"
	_overlay.add_child(_info)
	_help = _make_label(Vector2(18.0, 470.0))
	_help.name = "DebugHelp"
	_help.text = HELP_TEXT
	_overlay.add_child(_help)
	_hud = HUD.new()
	_hud.name = "MobHud"
	add_child(_hud)
	_hud.build(_overlay)
	stage.layout_changed.connect(_layout_overlay)
	_layout_overlay()
	_refresh_player_hint()


func _layout_overlay() -> void:
	_overlay.transform = stage.overlay_transform()
	var win := get_tree().root
	var width := float(maxi(win.size.x, 1)) * 720.0 / float(maxi(win.size.y, 1))
	_return_button.position = Vector2(maxf(18.0, width - _return_button.size.x - 18.0), 14.0)
	_player_hint.size = Vector2(maxf(width - 36.0, 1.0), 70.0)
	if _hud != null:
		_hud.layout(maxf(width, 320.0))


func _refresh_player_hint() -> void:
	var text := "移动：%s / %s（W/S 微调）   攻击：%s / %s    R 重开\n触屏按住移动、双击攻击   滚轮 / ± 缩放   Esc / 手柄返回" % [
		KeyLabels.label(&"move_left"), KeyLabels.label(&"move_right"), KeyLabels.label(&"attack"),
		KeyLabels.label(&"jump")]
	if _player_hint.text != text:
		_player_hint.text = text


func _set_debug(on: bool) -> void:
	_debug = on
	_info.visible = on
	_help.visible = on
	_info_timer = 0.0


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
	if not _debug:
		return
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
		"铺满" if stage.fill_screen else "16:9", camera.view_height, camera.texel_world(),
		1 + _unit_pool.active_count(),
	])
	lines.append("吸附 %s   亚像素 %s   描边 %s   抖动 %.2f   调色板 %s   12帧 %s   阴影 %s   自动平移 %s" % [
		_on(_snap), _on(stage.subpixel_enabled), OUTLINE_MODES[_outline_mode], DITHER_STEPS[_dither_index],
		_on(_palette), _on(_stepped), _on(_shadows), _on(_autopan),
	])
	lines.append("模拟 tick %d  时间 %.1fs  实体 %d  波次 %d  种子 %d  结果 %s" % [
		_sim_tick_count(), float(_sim_time_ms()) / 1000.0, _sim_entities().size(),
		_sim_wave_index(), _match_seed, String(_outcome) if not String(_outcome).is_empty() else "-",
	])
	if _toast_timer > 0.0:
		lines.append(_toast)
	_info.text = "\n".join(lines)


func _toast_message(text: String) -> void:
	_toast = text
	_toast_timer = 3.0
	_info_timer = 0.0


# ---------------------------------------------------------------- capture --

func _capture() -> void:
	var paths := stage.capture(SHOT_DIR)
	_toast_message("截图: %s" % ", ".join(paths))
	print("RenderSpike capture: ", ", ".join(paths))


func _quit_if_done() -> void:
	if _quit_after_shot and _auto_shots.is_empty():
		get_tree().quit()


## Tagged capture used by --auto-shots: the low-res 3D frame and the final
## window frame (HUD included) land in the peek folder with stable names.
func _capture_tagged(tag: String) -> void:
	var target_dir := _shot_peek_dir
	if target_dir.is_empty():
		target_dir = ProjectSettings.globalize_path("res://screenshots/peek/moba3d")
	DirAccess.make_dir_recursive_absolute(target_dir)
	var paths := stage.capture(SHOT_DIR.path_join("tagged"))
	for path in paths:
		var file := path.get_file()
		var suffix := "lowres" if file.contains("_lowres") else "window"
		var destination := target_dir.path_join("moba3d_%s_%s.png" % [tag, suffix])
		var error := DirAccess.copy_absolute(path, destination)
		if error == OK:
			print("MOBA3D_SHOT ", destination)
			DirAccess.remove_absolute(path)
		else:
			printerr("MOBA3D_SHOT_FAILED ", destination, " err=", error)
	_toast_message("截图 %s" % tag)


func _sim_seconds() -> float:
	if sim != null and _sim_time_ms() >= 0:
		return float(_sim_time_ms()) / 1000.0
	return _clock


func _handle_auto_shots() -> void:
	# First tagged capture: let the window upload its shaders before reading the
	# frame back, otherwise the opening screenshot can be an empty frame.
	if _clock < 0.9:
		return
	if _quit_after_sim >= 0.0 and sim != null and _sim_seconds() >= _quit_after_sim:
		_auto_log()
		print("ArenaSpike: quit after ", _quit_after_sim, "s of simulation")
		get_tree().quit()
		return
	if not _pending_shot.is_empty():
		# Let two more frames render after the state change (HUD banner, toppled
		# tower) before reading the frame back, or the shot captures the state
		# from before the change.
		_pending_shot_delay -= 1
		if _pending_shot_delay > 0:
			return
		var pending_tag := String(_pending_shot.get("tag", "shot"))
		_pending_shot = {}
		_capture_tagged(pending_tag)
		if _auto_shots.is_empty():
			_quit_if_done()
		return
	if _auto_shots.is_empty():
		return
	var shot: Dictionary = _auto_shots[0]
	var at := float(shot.get("t", -1.0))
	var reached := (_outcome != &"" and at < 0.0) or (at >= 0.0 and _sim_seconds() >= at)
	if not reached:
		return
	_auto_shots.pop_front()
	_pending_shot = shot
	var shot_at := float(shot.get("t", -1.0))
	if shot_at < 0.0:
		# Final shot: let the crystal shatter animation and its destroy flash
		# finish (~1.2 s of simulation) before reading the frame back.
		_pending_shot_delay = maxi(6, int(ceil(72.0 / maxf(_speed_scale, 1.0))))
	else:
		_pending_shot_delay = 6


# ---------------------------------------------------------------- autopilot -

## Very small autopilot for unattended acceptance runs. It follows the exact
## line the sim's own rules test uses to win: push straight at the enemy crystal
## and only send command_attack(id) once inside the 2.2 m attack range (locking
## a target earlier would stop the knight out of reach), otherwise move.
func _auto_input(_delta: float) -> void:
	if sim == null or _outcome != &"" or _hero_dead or not _hero_controllable:
		return
	if _hero_entity.is_empty():
		return
	var team := int(_hero_entity.get("team", VIEW_MAP.TEAM_BLUE))
	var hero_lane := UNIT_POOL.lane_of(_hero_entity)
	var objective := _auto_objective(team)
	if objective.is_empty():
		return
	var objective_id := int(objective.get("id", -1))
	var objective_lane := UNIT_POOL.lane_of(objective)
	_auto_last_target = objective_id
	var gap := objective_lane.x - hero_lane.x
	if absf(gap) <= HERO_ATTACK_RANGE - 0.1:
		sim.command_attack(objective_id)
	else:
		sim.set_move(Vector2(signf(gap), clampf(-hero_lane.y, -1.0, 1.0)))


## Enemy crystal first: standing at its 2.2 m range keeps the hero outside the
## enemy tower's 6 m range (tower lane x is 16, crystal lane x is 26).
func _auto_objective(team: int) -> Dictionary:
	var enemy := VIEW_MAP.enemy_team(team)
	var tower: Dictionary = {}
	for raw in _sim_entities():
		if raw is not Dictionary:
			continue
		var entity: Dictionary = raw
		if int(entity.get("team", -1)) != enemy or not bool(entity.get("alive", false)):
			continue
		var kind := StringName(entity.get("kind", &""))
		if kind == &"crystal":
			return entity
		if kind == &"tower" and tower.is_empty():
			tower = entity
	return tower


# -------------------------------------------------------------------- args --

func _parse_args() -> void:
	_args.clear()
	for arg in OS.get_cmdline_user_args():
		var parts := arg.split("=", true, 1)
		_args[parts[0]] = parts[1] if parts.size() > 1 else ""
	_match_seed = int(_args.get("--seed", MATCH_SEED))
	_speed_scale = clampf(float(_args.get("--speed", "1")), 0.25, 64.0)
	_auto = _args.has("--auto")
	_quit_after_sim = float(_args.get("--quit-after-sim", "-1"))
	_shot_peek_dir = String(_args.get("--shot-dir", ""))
	_auto_shots.clear()
	if _args.has("--auto-shots"):
		for token in String(_args["--auto-shots"]).split(",", false):
			var parts := token.strip_edges().split(":", true, 1)
			var tag := parts[0].strip_edges()
			if tag.is_empty():
				continue
			var at := -1.0
			if parts.size() > 1:
				at = parts[1].to_float()
			_auto_shots.append({"tag": tag, "t": at})


## Applies the render/look arguments after the scene is built; returns whether
## the debug stress batch should spawn.
func _apply_args() -> bool:
	var stress := false
	for key: String in _args.keys():
		var value := String(_args[key])
		match key:
			"--debug":
				_debug = true
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


func _center_camera() -> void:
	if hero == null:
		return
	camera.focus = Vector3(hero.global_position.x, 0.0, hero.global_position.z)
	camera.apply_view()


# ------------------------------------------------------- sim access guards --

func _sim_call(method: StringName) -> Variant:
	if sim == null or not sim.has_method(method):
		return null
	return sim.call(method)


func _sim_entities() -> Array:
	var value: Variant = _sim_call(&"entities")
	return value if value is Array else []


func _sim_structures(team: int) -> Array:
	if sim == null or not sim.has_method("structures"):
		return []
	var value: Variant = sim.call("structures", team)
	return value if value is Array else []


func _sim_hero_id() -> int:
	var value: Variant = _sim_call(&"hero_id")
	return int(value) if value != null else -1


func _sim_hero_state() -> Dictionary:
	var value: Variant = _sim_call(&"hero_state")
	return value if value is Dictionary else {}


func _sim_outcome() -> StringName:
	var value: Variant = _sim_call(&"outcome")
	if value == null:
		return &""
	if value is StringName:
		return value
	return StringName(String(value))


func _sim_wave_index() -> int:
	var value: Variant = _sim_call(&"wave_index")
	return int(value) if value != null else 0


func _sim_next_wave_ms() -> int:
	var value: Variant = _sim_call(&"next_wave_ms")
	return int(value) if value != null else 0


## MobaSim publishes the absolute match time of the next wave; the HUD shows a
## countdown, so convert to time remaining here (one place only).
func _sim_next_wave_remaining_ms() -> int:
	if sim == null or not sim.has_method("next_wave_ms"):
		return 0
	return maxi(0, _sim_next_wave_ms() - _sim_time_ms())


func _sim_tick_count() -> int:
	var value: Variant = _sim_call(&"tick_count")
	return int(value) if value != null else 0


func _sim_time_ms() -> int:
	var value: Variant = _sim_call(&"time_ms")
	return int(value) if value != null else 0


func _respawn_ms(state: Dictionary) -> int:
	if state.has("respawn_remaining_ms"):
		return int(state["respawn_remaining_ms"])
	if state.has("respawn_ms"):
		return int(state["respawn_ms"])
	if state.has("respawn"):
		var value := float(state["respawn"])
		# Tolerate a seconds-based fallback: a respawn counter above 10 is ms.
		return int(round(value * 1000.0)) if value <= 10.0 else int(value)
	return 0


static func _on(value: bool) -> String:
	return "开" if value else "关"
