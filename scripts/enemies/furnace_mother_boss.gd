class_name FurnaceMotherBoss
extends EnemyBase
## 真结局最终 Boss：【司炉母模 · 牧火回声】。
##
## 矗立在归零炉核中央的暗金音筒与齿轮母模。
## 三阶段设计：
##   · 一阶段（100%~66%）：牧火弹幕（可弹反回敬母模）+ 炉座震波（地面预警框 -> 近身冲击）；
##   · 二阶段（<=66%）：故障变调，追加三柱炉火矩阵（地面留安全空档，预警 ≥0.55s）；
##   · 三阶段（<=33%）：真伊尔共振破防，双联弹幕 + 全场过载后进入 1.35s 炉核暴露硬直。

signal slain

enum State {
	IDLE,
	ORB_WINDUP,
	ORB_FIRE,
	SLAM_WINDUP,
	SLAM_ACTIVE,
	PILLAR_WINDUP,
	PILLAR_ACTIVE,
	OVERLOAD_WINDUP,
	EXPOSED,
	REST,
}

const BOSS_TITLE := "司 炉 母 模 · 牧 火 回 声"
const DEATH_FLAG := "furnace_mother_dead"
const MAX_HP := 20
const PHASE2_RATIO := 2.0 / 3.0
const PHASE3_RATIO := 1.0 / 3.0
const PROJECTILE_PATH := "res://scenes/combat/Projectile.tscn"

const ORB_WINDUP_SEC := 0.55
const ORB_SPEED := 195.0
const SLAM_WINDUP_SEC := 0.60
const SLAM_ACTIVE_SEC := 0.24
const SLAM_HALF_W := 86.0
const PILLAR_WINDUP_SEC := 0.56
const PILLAR_ACTIVE_SEC := 0.28
const PILLAR_HALF_W := 24.0
const OVERLOAD_WINDUP_SEC := 0.65
const EXPOSED_SEC := 1.35

@export var aggro_range: float = 360.0
@export var arena_left: float = 48.0
@export var arena_right: float = 912.0
@export var contact_damage: int = 1

@onready var visual: Node2D = $Visual
@onready var hitbox: Hitbox = $Hitbox

var _state: State = State.IDLE
var _timer: float = 0.0
var _phase: int = 1
var _announced: bool = false
var _cycle_step: int = 0
var _pulse: float = 0.0
var _pillar_xs: Array[float] = []
var _pillar_hit_done: bool = false
var _monolith_sprite: Sprite2D
var _boss_kit: BossKit
var _boss_director: BossDirector


func _enemy_ready() -> void:
	hit_material = &"boss"
	health.max_hp = MAX_HP
	health.heal_full()
	health.changed.connect(_on_hp_changed)
	hitbox.team = &"enemy"
	hitbox.damage = contact_damage
	hitbox.disarm()
	_build_visual()
	_build_boss_framework()


func _build_visual() -> void:
	# 生成 56x76 像素暗金母模立柱贴图，底边严丝合缝站在 global_position.y (0) 之上
	var img := Image.create(56, 76, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# 底座与炉柱主体
	img.fill_rect(Rect2i(6, 62, 44, 14), Color("#261E28"))
	img.fill_rect(Rect2i(10, 14, 36, 50), Color("#352834"))
	img.fill_rect(Rect2i(14, 6, 28, 10), Color("#4A363E"))
	# 两侧牧火音筒肋条
	for ry in [18, 28, 38, 48]:
		img.fill_rect(Rect2i(8, ry, 40, 4), Color("#6B4C3B"))
	# 中央炉核视窗
	img.fill_rect(Rect2i(20, 24, 16, 20), Color("#160E14"))
	img.fill_rect(Rect2i(22, 26, 12, 16), Color("#FF9B3D"))

	_monolith_sprite = Sprite2D.new()
	_monolith_sprite.name = "MonolithSprite"
	_monolith_sprite.texture = ImageTexture.create_from_image(img)
	_monolith_sprite.centered = false
	_monolith_sprite.position = Vector2(-28.0, -76.0)
	_monolith_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visual.add_child(_monolith_sprite)
	_flash_target = _monolith_sprite
	_hide_placeholder_rects(visual)


func announce() -> void:
	if _announced:
		return
	_announced = true
	GameEvents.boss_intro_started.emit(BOSS_TITLE)
	GameEvents.boss_appeared.emit(BOSS_TITLE, health.current, health.max_hp)
	if _boss_director != null:
		_boss_director.notify_intro()


func is_announced() -> bool:
	return _announced


func phase() -> int:
	return _phase


func state() -> State:
	return _state


func _on_hp_changed(current: int, maximum: int) -> void:
	announce()
	GameEvents.boss_hp_changed.emit(current, maximum)
	if current <= 0 or maximum <= 0:
		if _boss_director != null:
			_boss_director.notify_death()
		return
	if _state == State.IDLE and current < maximum:
		_choose_next_attack()
	var ratio := float(current) / float(maximum)
	if _phase < 2 and ratio <= PHASE2_RATIO:
		_enter_phase(2)
	elif _phase < 3 and ratio <= PHASE3_RATIO:
		_enter_phase(3)
	if _boss_director != null:
		_boss_director.set_hp(current, maximum)


func _enter_phase(next_phase: int) -> void:
	_phase = next_phase
	Juice.boss_phase_beat(global_position + Vector2(0.0, -42.0),
			Color(0.95, 0.35, 0.32) if next_phase == 2 else Color(0.62, 0.92, 1.0))
	GameEvents.boss_phase_changed.emit(BOSS_TITLE, _phase)
	if _phase == 2:
		GameEvents.voice_triggered.emit("s8_r4_boss_phase2", true)
	elif _phase == 3:
		GameEvents.voice_triggered.emit("s8_r4_boss_phase3", true)


func _enemy_process(delta: float) -> void:
	_pulse += delta * (5.0 + float(_phase) * 1.8)
	if not is_on_floor():
		velocity.y = minf(velocity.y + 900.0 * delta, 540.0)
	else:
		velocity.y = 0.0
	velocity.x = 0.0
	move_and_slide()

	var player := _find_player()
	if _state == State.IDLE:
		if player != null and absf(player.global_position.x - global_position.x) <= aggro_range:
			announce()
			_choose_next_attack()
		queue_redraw()
		return

	_timer -= delta
	match _state:
		State.ORB_WINDUP:
			if _timer <= 0.0:
				_fire_orbs(player, 2 if _phase < 3 else 3)
				_enter_state(State.ORB_FIRE, 0.25)
		State.ORB_FIRE:
			if _timer <= 0.0:
				_enter_state(State.REST, 0.72 if _phase < 3 else 0.52)
		State.SLAM_WINDUP:
			if _timer <= 0.0:
				_activate_slam()
		State.SLAM_ACTIVE:
			if _timer <= 0.0:
				hitbox.disarm()
				_enter_state(State.REST, 0.75)
		State.PILLAR_WINDUP:
			if _timer <= 0.0:
				_pillar_hit_done = false
				Sfx.play(&"forge_pulse")
				Juice.shake(3.2, 180)
				_enter_state(State.PILLAR_ACTIVE, PILLAR_ACTIVE_SEC)
		State.PILLAR_ACTIVE:
			if not _pillar_hit_done:
				_pillar_hit_done = true
				_damage_players_in_pillars()
			if _timer <= 0.0:
				_pillar_xs.clear()
				_enter_state(State.REST, 0.68)
		State.OVERLOAD_WINDUP:
			if _timer <= 0.0:
				_fire_orbs(player, 2)
				Sfx.play(&"bell_toll")
				Juice.shake(3.8, 220)
				_enter_state(State.EXPOSED, EXPOSED_SEC)
		State.EXPOSED:
			if _timer <= 0.0:
				_enter_state(State.REST, 0.45)
		State.REST:
			if _timer <= 0.0:
				_choose_next_attack()
	queue_redraw()


func _enter_state(next: State, duration: float) -> void:
	_state = next
	_timer = duration
	if _monolith_sprite != null:
		_monolith_sprite.position.y = -66.0 if next == State.EXPOSED else -76.0


func _choose_next_attack() -> void:
	_cycle_step += 1
	if _phase == 1:
		if _cycle_step % 2 == 1:
			if _boss_director != null:
				_boss_director.notify_attack_started(&"orb_salvo")
			_enter_state(State.ORB_WINDUP, ORB_WINDUP_SEC)
		else:
			if _boss_director != null:
				_boss_director.notify_attack_started(&"sweep_slam")
			_enter_state(State.SLAM_WINDUP, SLAM_WINDUP_SEC)
	elif _phase == 2:
		match _cycle_step % 3:
			1:
				if _boss_director != null:
					_boss_director.notify_attack_started(&"furnace_pillars")
				_prepare_pillars()
				_enter_state(State.PILLAR_WINDUP, PILLAR_WINDUP_SEC)
			2:
				if _boss_director != null:
					_boss_director.notify_attack_started(&"orb_salvo")
				_enter_state(State.ORB_WINDUP, ORB_WINDUP_SEC * 0.9)
			_:
				if _boss_director != null:
					_boss_director.notify_attack_started(&"sweep_slam")
				_enter_state(State.SLAM_WINDUP, SLAM_WINDUP_SEC * 0.9)
	else:
		match _cycle_step % 3:
			1:
				if _boss_director != null:
					_boss_director.notify_attack_started(&"core_overload")
				_enter_state(State.OVERLOAD_WINDUP, OVERLOAD_WINDUP_SEC)
			2:
				if _boss_director != null:
					_boss_director.notify_attack_started(&"furnace_pillars")
				_prepare_pillars()
				_enter_state(State.PILLAR_WINDUP, PILLAR_WINDUP_SEC * 0.88)
			_:
				if _boss_director != null:
					_boss_director.notify_attack_started(&"sweep_slam")
				_enter_state(State.SLAM_WINDUP, SLAM_WINDUP_SEC * 0.85)


func _fire_orbs(player: Player, count: int) -> void:
	if not ResourceLoader.exists(PROJECTILE_PATH):
		return
	var packed := load(PROJECTILE_PATH) as PackedScene
	if packed == null:
		return
	var host := GameContext.world_effects(self)
	if host == null:
		host = get_parent()
	if host == null:
		return

	var origin := global_position + Vector2(0.0, -44.0)
	var base_target := player.global_position + Vector2(0.0, -18.0) if player != null else origin + Vector2(-160.0, 16.0)
	var base_dir := (base_target - origin).normalized()
	if base_dir.length_squared() < 0.01:
		base_dir = Vector2.LEFT

	Sfx.play(&"spit")
	for i in count:
		var spread := (float(i) - float(count - 1) * 0.5) * 0.22
		var bolt := packed.instantiate() as Projectile
		bolt.global_position = origin
		bolt.velocity = base_dir.rotated(spread) * ORB_SPEED
		bolt.source = self
		bolt.damage = contact_damage
		bolt.team = &"enemy"
		host.add_child(bolt)


func _activate_slam() -> void:
	Sfx.play(&"hit_heavy")
	Juice.shake(3.5, 180)
	var col := hitbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col != null and col.shape is RectangleShape2D:
		(col.shape as RectangleShape2D).size = Vector2(SLAM_HALF_W * 2.0, 36.0)
		hitbox.position = Vector2(0.0, -18.0)
	hitbox.arm()
	_enter_state(State.SLAM_ACTIVE, SLAM_ACTIVE_SEC)


func _prepare_pillars() -> void:
	_pillar_xs.clear()
	var left_bound := arena_left + 72.0 if is_finite(arena_left) else global_position.x - 220.0
	var right_bound := arena_right - 72.0 if is_finite(arena_right) else global_position.x + 220.0
	var mid := (left_bound + right_bound) * 0.5
	var offset := 42.0 if (_cycle_step % 2 == 0) else -42.0
	for px in [left_bound + 48.0, mid + offset, right_bound - 48.0]:
		_pillar_xs.append(clampf(px, left_bound, right_bound))


func _damage_players_in_pillars() -> void:
	var player := _find_player()
	if player == null or player.health == null:
		return
	var px := player.global_position.x
	var py := player.global_position.y
	if py < global_position.y - 128.0 or py > global_position.y + 24.0:
		return
	for cx in _pillar_xs:
		if absf(px - cx) <= PILLAR_HALF_W:
			var hurt := player.get_node_or_null("Hurtbox") as Hurtbox
			if hurt != null:
				hurt.receive_hit(contact_damage, self)
			break


func _find_player() -> Player:
	if get_tree() == null:
		return null
	return get_tree().get_first_node_in_group("player") as Player


func _on_died() -> void:
	hitbox.disarm()
	_pillar_xs.clear()
	if _boss_director != null:
		_boss_director.notify_death()
	SaveData.mark_flag(DEATH_FLAG)
	SaveData.persist_story()
	GameEvents.voice_triggered.emit("s8_r4_boss_down", true)
	slain.emit()
	Juice.boss_death_beat(global_position + Vector2(0.0, -44.0))
	GameEvents.boss_defeated.emit()
	var empty_frames: Array[Texture2D] = []
	_death_burst(empty_frames, 12.0, false, -38.0, "司炉母模轰然崩塌")


func boss_kit() -> BossKit:
	if _boss_kit == null:
		_boss_kit = BossKit.new(_boss_kit_config())
	return _boss_kit


func boss_director() -> BossDirector:
	return _boss_director


func boss_arena_bounds() -> Vector2:
	return Vector2(arena_left, arena_right)


func _build_boss_framework() -> void:
	_boss_kit = BossKit.new(_boss_kit_config())
	_boss_director = BossDirector.attach(self, _boss_kit, false)
	if _boss_director != null:
		_boss_director.set_hp(health.current, health.max_hp)


func _boss_kit_config() -> Dictionary:
	return {
		"id": &"furnace_mother",
		"title": BOSS_TITLE,
		"subtitle": "牧 火 回 声",
		"max_phases": 3,
		"phase_thresholds": [1.0, PHASE2_RATIO, PHASE3_RATIO],
		"min_interval": 0.75,
		"attacks": [
			{
				"id": &"orb_salvo", "phase": 1, "weight": 1.6,
				"cooldown": 1.2, "min_range": 0.0, "max_range": aggro_range,
				"windup": ORB_WINDUP_SEC, "active": 0.25, "recovery": 0.72,
				"telegraph": &"furnace_orb", "hitbox": {},
			},
			{
				"id": &"sweep_slam", "phase": 1, "weight": 1.4,
				"cooldown": 1.4, "min_range": 0.0, "max_range": aggro_range,
				"windup": SLAM_WINDUP_SEC, "active": SLAM_ACTIVE_SEC, "recovery": 0.75,
				"telegraph": &"furnace_slam",
				"hitbox": {"offset": Vector2(0.0, -18.0), "size": Vector2(SLAM_HALF_W * 2.0, 36.0)},
			},
			{
				"id": &"furnace_pillars", "phase": 2, "weight": 1.5,
				"cooldown": 2.0, "min_range": 0.0, "max_range": 0.0,
				"windup": PILLAR_WINDUP_SEC, "active": PILLAR_ACTIVE_SEC, "recovery": 0.68,
				"telegraph": &"furnace_pillar", "hitbox": {},
			},
			{
				"id": &"core_overload", "phase": 3, "weight": 1.5,
				"cooldown": 2.4, "min_range": 0.0, "max_range": 0.0,
				"windup": OVERLOAD_WINDUP_SEC, "active": 0.2, "recovery": EXPOSED_SEC,
				"telegraph": &"furnace_overload", "hitbox": {},
			},
		],
		"arena_events": [
			{"id": &"arena_surge", "at_phase": 1, "once": true},
			{"id": &"arena_hot", "at_phase": 2, "once": true},
			{"id": &"arena_dim", "at_phase": 0, "once": true},
		],
	}


func _draw() -> void:
	# 顶部悬浮音环
	var ring_col := Color(1.0, 0.72, 0.32, 0.55)
	if _phase == 2:
		ring_col = Color(0.96, 0.36, 0.34, 0.68)
	elif _phase == 3:
		ring_col = Color(0.62, 0.92, 1.0, 0.75)
	draw_arc(Vector2(0.0, -44.0), 26.0 + sin(_pulse) * 2.5, 0.0, TAU, 24, ring_col, 1.8)

	# 攻击预警可视化（保证 ≥0.45s 清晰读招）
	if _state == State.ORB_WINDUP or _state == State.OVERLOAD_WINDUP:
		draw_circle(Vector2(0.0, -44.0), 11.0 + sin(_pulse * 2.0) * 3.0, Color(1.0, 0.85, 0.42, 0.65))
	elif _state == State.SLAM_WINDUP:
		draw_rect(Rect2(-SLAM_HALF_W, -6.0, SLAM_HALF_W * 2.0, 6.0), Color(1.0, 0.42, 0.24, 0.62))
	elif _state == State.SLAM_ACTIVE:
		draw_rect(Rect2(-SLAM_HALF_W, -28.0, SLAM_HALF_W * 2.0, 28.0), Color(1.0, 0.72, 0.32, 0.52))
	elif _state == State.PILLAR_WINDUP:
		for px in _pillar_xs:
			var lx := px - global_position.x
			draw_rect(Rect2(lx - PILLAR_HALF_W, -132.0, PILLAR_HALF_W * 2.0, 132.0), Color(1.0, 0.38, 0.22, 0.28))
			draw_line(Vector2(lx, -132.0), Vector2(lx, 0.0), Color(1.0, 0.82, 0.42, 0.78), 2.0)
	elif _state == State.PILLAR_ACTIVE:
		for px in _pillar_xs:
			var lx := px - global_position.x
			draw_rect(Rect2(lx - PILLAR_HALF_W, -132.0, PILLAR_HALF_W * 2.0, 132.0), Color(1.0, 0.72, 0.28, 0.72))
	elif _state == State.EXPOSED:
		draw_circle(Vector2(0.0, -34.0), 15.0, Color(0.62, 0.94, 1.0, 0.45))
