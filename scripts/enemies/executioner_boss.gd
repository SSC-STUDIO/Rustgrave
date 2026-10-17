class_name ExecutionerBoss
extends GearShieldEnemy
## 锻炉残室的刽子手。保留正面盾规则；半血后射弹加密并挥斧。

signal slain

enum SlashPhase { NONE, ACTIVE, RECOVERY }
const SLASH_WINDUP := 0.52
const SLASH_ACTIVE := 0.16
const SLASH_RECOVERY := 0.65
## 与 boss_appeared / boss_intro_started / boss_phase_changed 共用的显示名。
const BOSS_TITLE := "炉 约 刽 子 手 · 铸 渣 残 躯"
## 斩击落点框：与 _do_slash 里的判定盒同位同尺寸，前摇期间红框越闪越急。
const SLASH_ZONE_OFFSET := Vector2(22.0, -18.0)
const SLASH_ZONE_SIZE := Vector2(36.0, 28.0)
const SLASH_ZONE_COLOR := Color(1.0, 0.42, 0.18, 0.95)
## 二阶段开场的吼叫：这段时间里不开新的斩 / 射，让玩家看清相变。
const PHASE_ROAR_TIME := 0.6

var _enraged := false
var _slash_next := false
var _slash_cd := 0.0
var _intro_announced := false
var _slash_phase: SlashPhase = SlashPhase.NONE
var _slash_timer := 0.0
var _slash_box: Hitbox
var _roar_left := 0.0


func is_enraged() -> bool:
	return _enraged


func _enemy_ready() -> void:
	super._enemy_ready()
	hit_material = &"boss"
	health.max_hp = 13
	health.heal_full()
	health.changed.connect(_on_hp_changed)
	shoot_interval = 2.0
	aggro_range = 360.0
	if _anim != null:
		if CharFrames.available(EXEC_CHAR, "attack"):
			var frames := CharFrames.anim(EXEC_CHAR, "attack")
			_anim.register("slash", frames, float(frames.size()) / (SLASH_WINDUP + SLASH_ACTIVE), false, EXEC_POS)
		if CharFrames.available(EXEC_CHAR, "skill"):
			_anim.register("skill", CharFrames.anim(EXEC_CHAR, "skill"), 10.0, false, EXEC_POS)


## Boss 血条只在骑士跨进拱门（或先手打到他）时出现；以前在第一帧就弹出来，
## 玩家还在余烬高台上就顶着一条 Boss 血条。
func announce() -> void:
	if _intro_announced:
		return
	_intro_announced = true
	# 先发「开场开始」（音乐 / 演出据此起势），紧接着才是 Boss 血条。
	GameEvents.boss_intro_started.emit(BOSS_TITLE)
	GameEvents.boss_appeared.emit(BOSS_TITLE, health.current, health.max_hp)


func is_announced() -> bool:
	return _intro_announced


func _on_hp_changed(current: int, maximum: int) -> void:
	announce()
	GameEvents.boss_hp_changed.emit(current, maximum)
	if _enraged or maximum <= 0 or current <= 0:
		return
	if current <= maximum / 2:
		_enter_phase_two()


## 二阶段：相变演出（短慢动作 + 震屏 + 圆环 + 受 Settings 缩放的闪色 + 吼叫）、
## 余烬从斧上升起（一直挂着，远处也能认出他变了），随后一小段吼叫硬直再开新招。
func _enter_phase_two() -> void:
	_enraged = true
	shoot_interval = 1.15
	_roar_left = PHASE_ROAR_TIME
	Juice.boss_phase_beat(global_position + Vector2(0.0, -30.0), Palette.EMBER)
	Fx.attach_heat_lick(visual)
	GameEvents.announcement.emit("炉渣在他的斧上重新沸腾")
	GameEvents.boss_phase_changed.emit(BOSS_TITLE, 2)


func _tick_block(delta: float) -> void:
	if _roar_left > 0.0:
		# 吼叫中：站定举盾，不开新招。
		_roar_left = maxf(0.0, _roar_left - delta)
		velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)
		_set_blocking(true)
		return
	_slash_cd = maxf(0.0, _slash_cd - delta)
	var player := knight()
	if player != null and _slash_cd <= 0.0 \
			and global_position.distance_to(player.global_position) < 78.0:
		_begin_slash()
		return
	super._tick_block(delta)


func _tick_state(delta: float) -> void:
	if _dead:
		return
	if _slash_phase == SlashPhase.NONE:
		super._tick_state(delta)
		return
	velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
	_slash_timer -= delta
	if _slash_timer > 0.0:
		return
	if _slash_phase == SlashPhase.ACTIVE:
		_clear_slash_box()
		_slash_phase = SlashPhase.RECOVERY
		_slash_timer = SLASH_RECOVERY
		_set_blocking(false)
		_kill_flicker()
		_refresh_indicator()
		# 收斧的 0.65 秒就是破绽：盾放下 + 头顶金箭头亮满整个窗口。
		show_opening(SLASH_RECOVERY)
	else:
		_slash_phase = SlashPhase.NONE
		_state = State.BLOCK
		_slash_cd = 1.6 if _enraged else 2.1
		# 二阶段「斩 → 射」连招：收斧后紧跟一发弹，不再等满一个射击间隔。
		_shoot_timer = CombatRules.EXECUTIONER_P2_FOLLOWUP if _enraged else shoot_interval
		_set_blocking(true)
		hide_opening()


func _clear_slash_box() -> void:
	if is_instance_valid(_slash_box):
		_slash_box.disarm()
		_slash_box.queue_free()
	_slash_box = null


func _enter_stagger() -> void:
	_slash_next = false
	_slash_phase = SlashPhase.NONE
	_clear_slash_box()
	super._enter_stagger()


func _begin_slash() -> void:
	_slash_next = true
	_state = State.CHARGE
	_timer = SLASH_WINDUP
	_set_blocking(true)
	_flicker_slash()
	if _anim != null and _anim.has_anim("slash"):
		_anim.play("slash", true)
	# 读招：余烬脉冲（见 _flicker_slash）+ 地面落点红框，框在前摇期间越闪越急，
	# 判定盒与框同位同尺寸。
	begin_telegraph(&"executioner", SLASH_WINDUP)
	CombatMarker.spawn(self, CombatMarker.Kind.ZONE,
			Vector2(float(_shield_facing) * SLASH_ZONE_OFFSET.x, SLASH_ZONE_OFFSET.y),
			SLASH_WINDUP, SLASH_ZONE_COLOR,
			{"rect": Rect2(-SLASH_ZONE_SIZE * 0.5, SLASH_ZONE_SIZE)})


func _update_anim() -> void:
	if (_slash_next or _slash_phase == SlashPhase.ACTIVE) and _anim != null and _anim.has_anim("slash"):
		_anim.play("slash")
		return
	if _slash_phase == SlashPhase.RECOVERY and _anim != null:
		_anim.set_fps("idle", 3.0)
		_anim.play("idle")
		return
	super._update_anim()


func _tick_charge(delta: float) -> void:
	if _dead:
		return
	if not _slash_next:
		super._tick_charge(delta)
		return
	velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)
	_timer -= delta
	if _timer <= 0.0:
		_do_slash()
		_slash_next = false
		_slash_phase = SlashPhase.ACTIVE
		_slash_timer = SLASH_ACTIVE


## 挥斧前摇：余烬脉冲，和射弹蓄力的毒橙闪区分开，0.52s 窗更可读。
func _flicker_slash() -> void:
	if _indicator == null:
		return
	_kill_flicker()
	_flicker_tween = create_tween()
	_flicker_tween.tween_property(_indicator, "modulate", Palette.EMBER, 0.16)
	_flicker_tween.tween_property(_indicator, "modulate", Color(1.45, 0.72, 0.38), 0.36)


func _do_slash() -> void:
	if _dead:
		return
	var box := Hitbox.new()
	_slash_box = box
	box.damage = 2
	box.team = &"enemy"
	box.knockback = Vector2(float(_shield_facing) * 110.0, -28.0)
	box.monitoring = true
	box.collision_layer = 8
	box.collision_mask = 32
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(36, 28)
	shape.shape = rect
	box.add_child(shape)
	box.blow = &"heavy"
	get_parent().add_child(box)
	box.global_position = global_position + Vector2(float(_shield_facing) * 22.0, -18.0)
	box.arm(Vector2(float(_shield_facing) * 110.0, -28.0))
	# 一阶段是挥砍声，二阶段是砸地声 + 一阵尘与震（只加手感，判定盒不变）。
	if _enraged:
		Sfx.play_at(CombatRules.sfx_key(&"boss_axe_slam"), box.global_position)
		Fx.dust_puff(box.global_position + Vector2(0.0, 14.0), -PI * 0.5)
		Juice.shake(2.5, 140)
	else:
		Sfx.play_at(CombatRules.sfx_key(&"boss_axe_swing"), box.global_position)


func _fire() -> void:
	if _dead or _slash_phase != SlashPhase.NONE:
		return
	super._fire()
	if not _enraged:
		return
	if _anim != null and _anim.has_anim("skill"):
		_anim.play("skill", true)
	var player := knight()
	var proj := PROJECTILE_SCENE.instantiate() as Projectile
	var host := GameContext.world_effects(self)
	if host == null:
		host = get_tree().current_scene
	host.add_child(proj)
	var origin := global_position + Vector2(_shield_facing * 16.0, -38.0)
	var aim := Vector2(_shield_facing * 40.0, -18.0)
	if player:
		aim = player.global_position + Vector2(0, -28) - origin
	proj.setup(origin, aim, projectile_speed * 0.92, &"enemy", self)


func _on_died() -> void:
	_slash_next = false
	_slash_phase = SlashPhase.NONE
	_clear_slash_box()
	slain.emit()
	# 死亡演出钩子：慢动作 + 大震屏 + 双圈 + 碎屑 + 音效；并收掉 Boss 血条
	# （此前刽子手倒下时 HUD 的血条没人通知）。
	Juice.boss_death_beat(global_position + Vector2(0.0, -24.0))
	GameEvents.boss_defeated.emit()
	_death_burst(CharFrames.anim(EXEC_CHAR, "death"), 14.0,
			_shield_facing == 1, EXEC_DEATH_BASELINE, "刽子手跪进炉灰里")
