class_name BattleWaveArena
extends Node2D
## 《ICEY》式封门多波次高密度战斗容器。
##
## 状态流：
##   Idle → 玩家踏入触发区 → 落下左右实体铁栅 + 夹紧 GameCamera →
##   绘制 0.45s 余烬刷怪预警圈 → 生成第 1 波组合怪 → 清光后自动预警生成第 2..N 波 →
##   最后一波最后一只敌人阵亡瞬间触发慢动作特写 → 降下铁栅、还原镜头、点亮 GuideArrow！

signal arena_started
signal wave_spawned(wave_index: int, total_waves: int)
signal arena_cleared

const TELEGRAPH_DEFAULT := 0.45
const BARRIER_THICKNESS := 16.0
const BARRIER_HEIGHT := 260.0

@export var stage_id: String = ""
@export var room_id: String = ""
@export var arena_left: float = 32.0
@export var arena_right: float = 736.0
@export var floor_y: float = 320.0
@export var trigger_margin: float = 96.0
@export var telegraph_seconds: float = TELEGRAPH_DEFAULT
@export var on_start_clip: String = ""
@export var on_clear_clip: String = ""

## 每波为 Array[Dictionary]：[{"kind": "skeleton", "pos": Vector2(420, 320), "overrides": {}}]
var waves: Array = []
## 波次索引（1-based） -> clip_id
var wave_clips: Dictionary = {}

var active: bool = false
var cleared: bool = false
var current_wave: int = 0
var telegraphing: bool = false

var _telegraph_left: float = 0.0
var _pending_wave_specs: Array = []
var _live_enemies: Array[Node2D] = []
var _gates: Array = []
var _arrows: Array[GuideArrow] = []
var _barriers: Array[StaticBody2D] = []
var _camera: GameCamera
var _saved_cam_limits: Rect2i = Rect2i()
var _has_saved_cam: bool = false
var _pulse: float = 0.0


func _ready() -> void:
	z_index = 3
	if stage_id != "" and room_id != "" and StageRoomMemory.is_cleared(stage_id, room_id):
		cleared = true
		_unlock_all_and_light_arrows(false)


func _exit_tree() -> void:
	_restore_camera()


func configure_waves(wave_list: Array, clips_by_wave: Dictionary = {}) -> void:
	waves = wave_list.duplicate(true)
	wave_clips = clips_by_wave.duplicate()


func register_gate(gate: Node) -> void:
	if gate != null and not _gates.has(gate):
		_gates.append(gate)
		if cleared:
			if gate.has_method("unlock"):
				gate.call("unlock")


func bind_arrow(arrow: GuideArrow) -> void:
	if arrow == null or _arrows.has(arrow):
		return
	_arrows.append(arrow)
	arrow.set_lit(cleared, false)


func is_active() -> bool:
	return active


func is_cleared() -> bool:
	return cleared


func live_enemy_count() -> int:
	_prune_dead_enemies()
	return _live_enemies.size()


func activate() -> void:
	if active or cleared or waves.is_empty():
		return
	active = true
	current_wave = 0
	_lock_gates(true)
	_spawn_barriers()
	_clamp_camera()
	Sfx.play(&"gate")
	Juice.shake(2.5, 140)
	if on_start_clip != "":
		GameEvents.voice_triggered.emit(on_start_clip, false)
	arena_started.emit()
	_begin_next_wave()


func _physics_process(delta: float) -> void:
	if cleared:
		return
	if not active:
		_poll_entry_trigger()
		return

	_pulse += delta * 6.0
	_clamp_player_inside()

	if telegraphing:
		_telegraph_left -= delta
		queue_redraw()
		if _telegraph_left <= 0.0:
			_finish_wave_spawn()
		return

	_prune_dead_enemies()
	if _live_enemies.is_empty():
		if current_wave < waves.size():
			_begin_next_wave()
		else:
			_complete_arena()


func _poll_entry_trigger() -> void:
	if get_tree() == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return
	var px := player.global_position.x
	if px >= arena_left + trigger_margin and px <= arena_right - trigger_margin:
		activate()


func _begin_next_wave() -> void:
	current_wave += 1
	_pending_wave_specs = (waves[current_wave - 1] as Array).duplicate(true)
	telegraphing = true
	_telegraph_left = maxf(0.05, telegraph_seconds)
	if wave_clips.has(current_wave):
		GameEvents.voice_triggered.emit(String(wave_clips[current_wave]), false)
	GameEvents.battle_wave_started.emit(current_wave, waves.size())
	queue_redraw()


func _finish_wave_spawn() -> void:
	telegraphing = false
	var host := GameContext.world_root(self) as Node2D
	if host == null:
		host = get_parent() as Node2D
	var enemies_folder := host.get_node_or_null("Enemies") as Node2D if host != null else null
	if enemies_folder == null and host != null:
		enemies_folder = Node2D.new()
		enemies_folder.name = "Enemies"
		host.add_child(enemies_folder)

	for i in _pending_wave_specs.size():
		var spec: Dictionary = _pending_wave_specs[i]
		var kind := String(spec.get("kind", "skeleton"))
		var pos: Vector2 = spec.get("pos", Vector2((arena_left + arena_right) * 0.5, floor_y))
		var overrides: Dictionary = spec.get("overrides", {})
		var scene_path := String(ChapterLayout.ENEMY_SCENES.get(kind, ""))
		if scene_path == "" or not ResourceLoader.exists(scene_path):
			continue
		var packed := load(scene_path) as PackedScene
		if packed == null:
			continue
		var foe := packed.instantiate() as Node2D
		foe.name = "Wave%d_%s_%d" % [current_wave, kind, i]
		foe.position = pos
		for k in overrides:
			foe.set(k, overrides[k])
		if enemies_folder != null:
			enemies_folder.add_child(foe)
		else:
			add_child(foe)
		Fx.dust_puff(pos)
		_live_enemies.append(foe)
		var hp := foe.get_node_or_null("Health") as Health
		if hp != null and not hp.died.is_connected(_on_wave_enemy_died):
			hp.died.connect(_on_wave_enemy_died.bind(foe), CONNECT_ONE_SHOT)

	_pending_wave_specs.clear()
	queue_redraw()
	wave_spawned.emit(current_wave, waves.size())


func _on_wave_enemy_died(foe: Node2D) -> void:
	_live_enemies.erase(foe)


func _prune_dead_enemies() -> void:
	var i := _live_enemies.size() - 1
	while i >= 0:
		var foe := _live_enemies[i]
		if foe == null or not is_instance_valid(foe) or not foe.is_inside_tree():
			_live_enemies.remove_at(i)
		else:
			var hp := foe.get_node_or_null("Health") as Health
			if hp != null and hp.current <= 0:
				_live_enemies.remove_at(i)
		i -= 1


func _complete_arena() -> void:
	if cleared:
		return
	cleared = true
	active = false
	telegraphing = false
	if stage_id != "" and room_id != "":
		StageRoomMemory.mark_cleared(stage_id, room_id)

	Juice.slow_mo(200, 0.32)
	Juice.shake(3.2, 180)
	Sfx.play(&"door_open")
	_free_barriers()
	_restore_camera()
	_unlock_all_and_light_arrows(true)

	if on_clear_clip != "":
		GameEvents.voice_triggered.emit(on_clear_clip, false)
	GameEvents.battle_room_cleared.emit(room_id)
	queue_redraw()
	arena_cleared.emit()


func _unlock_all_and_light_arrows(play_cue: bool) -> void:
	_lock_gates(false)
	for arrow in _arrows:
		if arrow != null and is_instance_valid(arrow):
			arrow.set_lit(true, play_cue)


func _lock_gates(locked_state: bool) -> void:
	for gate in _gates:
		if gate == null or not is_instance_valid(gate):
			continue
		if locked_state and gate.has_method("lock"):
			gate.call("lock")
		elif not locked_state and gate.has_method("unlock"):
			gate.call("unlock")


func _spawn_barriers() -> void:
	if not _barriers.is_empty():
		return
	_barriers.append(_make_barrier("WaveWallLeft", arena_left))
	_barriers.append(_make_barrier("WaveWallRight", arena_right))
	for b in _barriers:
		add_child(b)
	queue_redraw()


func _make_barrier(wall_name: String, x: float) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = wall_name
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = Vector2(x, floor_y - BARRIER_HEIGHT * 0.5)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(BARRIER_THICKNESS, BARRIER_HEIGHT)
	col.shape = shape
	body.add_child(col)
	return body


func _free_barriers() -> void:
	for b in _barriers:
		if b != null and is_instance_valid(b):
			b.queue_free()
	_barriers.clear()


func _clamp_player_inside() -> void:
	if get_tree() == null:
		return
	var player := get_tree().get_first_node_in_group("player") as CharacterBody2D
	if player == null:
		return
	var min_x := arena_left + 14.0
	var max_x := arena_right - 14.0
	if player.global_position.x < min_x:
		player.global_position.x = min_x
	elif player.global_position.x > max_x:
		player.global_position.x = max_x


func _clamp_camera() -> void:
	if get_tree() == null:
		return
	_camera = get_tree().get_first_node_in_group("game_camera") as GameCamera
	if _camera == null:
		return
	if not _has_saved_cam:
		_saved_cam_limits = Rect2i(
			_camera.limit_left,
			_camera.limit_top,
			_camera.limit_right - _camera.limit_left,
			_camera.limit_bottom - _camera.limit_top
		)
		_has_saved_cam = true
	_camera.limit_left = int(roundf(arena_left))
	_camera.limit_right = int(roundf(arena_right))


func _restore_camera() -> void:
	if _camera == null or not is_instance_valid(_camera) or not _has_saved_cam:
		return
	_camera.limit_left = _saved_cam_limits.position.x
	_camera.limit_top = _saved_cam_limits.position.y
	_camera.limit_right = _saved_cam_limits.position.x + _saved_cam_limits.size.x
	_camera.limit_bottom = _saved_cam_limits.position.y + _saved_cam_limits.size.y
	_has_saved_cam = false


func _draw() -> void:
	if active and not _barriers.is_empty():
		var alpha := 0.68 + 0.2 * sin(_pulse)
		var bar_col := Color(0.95, 0.34, 0.22, alpha)
		var core_col := Color(1.0, 0.78, 0.42, alpha)
		for bx: float in [arena_left, arena_right]:
			var lx: float = bx - global_position.x
			draw_rect(Rect2(lx - 3.0, floor_y - 112.0 - global_position.y, 6.0, 112.0), bar_col)
			draw_line(Vector2(lx, floor_y - 112.0 - global_position.y), Vector2(lx, floor_y - global_position.y), core_col, 2.0)

	if telegraphing:
		var ratio := 1.0 - clampf(_telegraph_left / maxf(0.05, telegraph_seconds), 0.0, 1.0)
		var ring_r := lerpf(22.0, 8.0, ratio)
		var col := Color(1.0, 0.45, 0.24, 0.35 + 0.55 * ratio)
		for spec in _pending_wave_specs:
			var pos: Vector2 = (spec as Dictionary).get("pos", Vector2.ZERO) - global_position
			draw_arc(pos + Vector2(0.0, -8.0), ring_r, 0.0, TAU, 20, col, 2.0)
			draw_line(pos + Vector2(0.0, -32.0), pos, Color(1.0, 0.78, 0.42, 0.5 * ratio), 1.5)
