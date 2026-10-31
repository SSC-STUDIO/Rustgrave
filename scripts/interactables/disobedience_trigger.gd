class_name DisobedienceTrigger
extends Node2D
## 《ICEY》式叛逆行为检测器。
##
## 支持四种交互模式：
##   1. CROSS_LINE  无视发光箭头踏入反向禁区/深井，立即高优先级打断引导语音并解锁对应支线；
##   2. STRIKE_SEAL 可劈砍的裂纹封印墙（3 刀破封）：每挥砍一刀触发一句递进劝阻，第 3 刀碎墙并解锁隐藏门；
##   3. LINGER_IDLE 在房间内驻足超过 linger_seconds 不按路标推进时，触发伊尔的催促或漏嘴找补；
##   4. MERCY_PASS  不攻击静默灰卫直接收剑走过身边时，触发灰卫敬礼与伊尔不满台词。

signal triggered(step: int)
signal seal_broken

enum Mode { CROSS_LINE, STRIKE_SEAL, LINGER_IDLE, MERCY_PASS }

@export var mode: Mode = Mode.CROSS_LINE
@export var branch_id: String = ""
@export var zone_size: Vector2 = Vector2(48.0, 72.0)
@export var voice_clips: PackedStringArray = PackedStringArray()
@export var linger_seconds: float = 6.5
@export var max_hits: int = 3
@export var linked_gate_path: NodePath

var hits_taken: int = 0
var broken: bool = false
var _fired: bool = false
var _linger_elapsed: float = 0.0
var _player_inside: bool = false
var _hostile_swung: bool = false
var _area: Area2D
var _wall_body: StaticBody2D
var _hurtbox: Hurtbox


func _ready() -> void:
	z_index = 2
	if mode == Mode.STRIKE_SEAL:
		_build_seal_wall()
		# 若该支线此前已被劈开解锁，重进房间直接呈破封态。
		if branch_id != "" and NarrativeCatalog.is_node_unlocked(branch_id, SaveData.flags):
			_finish_seal_break(true)
	else:
		_build_sensor_area()
	if mode == Mode.MERCY_PASS:
		GameEvents.swing_started.connect(_on_player_swung)
	queue_redraw()


func _build_sensor_area() -> void:
	_area = Area2D.new()
	_area.name = "Sensor"
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitoring = true
	_area.monitorable = false
	add_child(_area)

	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = zone_size
	col.shape = shape
	col.position = Vector2(0.0, -zone_size.y * 0.5)
	_area.add_child(col)
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)


func _build_seal_wall() -> void:
	_wall_body = StaticBody2D.new()
	_wall_body.name = "SealBarrier"
	_wall_body.collision_layer = 1
	_wall_body.collision_mask = 0
	add_child(_wall_body)

	var body_col := CollisionShape2D.new()
	var body_shape := RectangleShape2D.new()
	body_shape.size = zone_size
	body_col.shape = body_shape
	body_col.position = Vector2(0.0, -zone_size.y * 0.5)
	_wall_body.add_child(body_col)

	_hurtbox = Hurtbox.new()
	_hurtbox.name = "SealHurtbox"
	_hurtbox.team = &"enemy"
	_hurtbox.damage_owner_path = NodePath("")
	add_child(_hurtbox)

	var hurt_col := CollisionShape2D.new()
	var hurt_shape := RectangleShape2D.new()
	hurt_shape.size = zone_size + Vector2(12.0, 8.0)
	hurt_col.shape = hurt_shape
	hurt_col.position = Vector2(0.0, -zone_size.y * 0.5)
	_hurtbox.add_child(hurt_col)
	_hurtbox.hurt.connect(_on_seal_hurt)


func _on_seal_hurt(_amount: int, _attacker: Node) -> void:
	if broken:
		return
	apply_seal_strike()


## 供玩家挥砍或自动化测试直接调用：记一刀，触发对应劝阻语音，满刀破墙。
func apply_seal_strike() -> void:
	if broken:
		return
	hits_taken += 1
	Juice.shake(2.5, 110)
	Sfx.play(&"hit_heavy")
	var clip_idx := mini(hits_taken - 1, voice_clips.size() - 1)
	if clip_idx >= 0 and clip_idx < voice_clips.size():
		GameEvents.voice_triggered.emit(String(voice_clips[clip_idx]), true)
	GameEvents.disobedience_triggered.emit(branch_id, hits_taken)
	triggered.emit(hits_taken)
	queue_redraw()
	if hits_taken >= max_hits:
		_finish_seal_break(false)


func _finish_seal_break(silent: bool) -> void:
	broken = true
	if _wall_body != null and is_instance_valid(_wall_body):
		_wall_body.queue_free()
		_wall_body = null
	if _hurtbox != null and is_instance_valid(_hurtbox):
		_hurtbox.queue_free()
		_hurtbox = null
	if branch_id != "" and not silent:
		SaveData.unlock_node(branch_id)
	var gate := get_node_or_null(linked_gate_path)
	if gate != null and gate.has_method("set_locked"):
		gate.call("set_locked", false)
	if not silent:
		Juice.shake(4.5, 220)
		Sfx.play(&"door_open")
		seal_broken.emit()
	queue_redraw()


func _on_body_entered(body: Node) -> void:
	if not (body is Player):
		return
	_player_inside = true
	if _fired:
		return
	if mode == Mode.CROSS_LINE:
		_fire_once(1)
	elif mode == Mode.MERCY_PASS and not _hostile_swung:
		_fire_once(1)


func _on_body_exited(body: Node) -> void:
	if body is Player:
		_player_inside = false


func _on_player_swung(_combo_index: int) -> void:
	if _player_inside:
		_hostile_swung = true


func _process(delta: float) -> void:
	if mode != Mode.LINGER_IDLE or _fired:
		return
	if not GameContext.gameplay_input_enabled():
		return
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return
	if absf(player.velocity.x) < 8.0 and absf(player.velocity.y) < 8.0:
		_linger_elapsed += delta
		if _linger_elapsed >= linger_seconds:
			_fire_once(1)
	else:
		_linger_elapsed = maxf(0.0, _linger_elapsed - delta * 0.5)


func _fire_once(step: int) -> void:
	_fired = true
	if branch_id != "":
		SaveData.unlock_node(branch_id)
	for i in voice_clips.size():
		GameEvents.voice_triggered.emit(String(voice_clips[i]), i == 0)
	GameEvents.disobedience_triggered.emit(branch_id, step)
	triggered.emit(step)


func _draw() -> void:
	if mode != Mode.STRIKE_SEAL:
		return
	if broken:
		# 破封后在地面留两块碎石痕迹
		draw_rect(Rect2(-10.0, -4.0, 7.0, 4.0), Color("#3A2C2E"))
		draw_rect(Rect2(4.0, -3.0, 6.0, 3.0), Color("#4A3638"))
		return
	var r := Rect2(-zone_size.x * 0.5, -zone_size.y, zone_size.x, zone_size.y)
	draw_rect(r, Color("#241B22"))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 2.0)), Color("#5A4246"))
	# 琥珀红裂纹随受击次数加宽加深，视觉暗示玩家“这堵墙能劈开”
	var crack_col := Color("#D9534F") if hits_taken > 0 else Color("#8C4A32")
	var width := 1.0 + float(hits_taken) * 0.8
	draw_line(Vector2(-3.0, -zone_size.y + 8.0), Vector2(4.0, -zone_size.y * 0.55), crack_col, width)
	draw_line(Vector2(4.0, -zone_size.y * 0.55), Vector2(-4.0, -10.0), crack_col, width)
	if hits_taken >= 1:
		draw_line(Vector2(4.0, -zone_size.y * 0.55), Vector2(8.0, -zone_size.y * 0.3), Color("#FF9E44"), width)
	if hits_taken >= 2:
		draw_line(Vector2(-6.0, -zone_size.y * 0.72), Vector2(5.0, -zone_size.y * 0.2), Color("#FFE082"), width)
