extends TestCase
## MeleeCombat state machine driven manually via tick()/start_swing().
## Timings asserted at 60 fps frames from the GDD budget:
## windup ~0.18 s, active ~0.12 s (parry window), recovery ~0.26 s, cooldown gate.


var melee: MeleeCombat


func setup() -> void:
	melee = MeleeCombat.new()
	var hb := Area2D.new()
	hb.name = "Hitbox"
	hb.set_script(load("res://scripts/combat/hitbox.gd"))
	melee.add_child(hb)
	add_child(melee)
	melee.set_physics_process(false)


func _frames_for(seconds: float) -> int:
	return ceili(seconds * 60.0) + (1 if seconds > 0.0 else 0)


func test_idle_by_default_and_not_parrying() -> void:
	eq(melee.phase_name(), "idle")
	ok(not melee.is_busy())
	ok(not melee.is_parry_window())


func test_swing_walks_windup_active_recovery_and_back_to_idle() -> void:
	ok(melee.start_swing(), "swing starts from idle")
	eq(melee.phase_name(), "windup")

	for i in _frames_for(melee.windup_time):
		melee.tick(1.0 / 60.0)
	eq(melee.phase_name(), "active")
	ok(melee.is_parry_window(), "ACTIVE frames are the parry window")
	ok(mele_hitbox_monitoring())

	for i in _frames_for(melee.active_time):
		melee.tick(1.0 / 60.0)
	eq(melee.phase_name(), "recovery")
	ok(not melee.is_parry_window())
	ok(not mele_hitbox_monitoring(), "hitbox closes after active frames")

	for i in _frames_for(melee.recovery_time):
		melee.tick(1.0 / 60.0)
	eq(melee.phase_name(), "idle")
	ok(not melee.is_busy())


func test_cooldown_blocks_immediate_second_swing() -> void:
	ok(melee.start_swing())
	for i in _frames_for(melee.windup_time + melee.active_time + melee.recovery_time):
		melee.tick(1.0 / 60.0)
	eq(melee.phase_name(), "idle", "back to idle inside cooldown")
	ok(not melee.start_swing(), "cooldown still gating")
	for i in _frames_for(melee.cooldown):
		melee.tick(1.0 / 60.0)
	ok(melee.start_swing(), "cooldown expired")


func test_second_swing_while_busy_is_refused() -> void:
	ok(melee.start_swing())
	ok(not melee.start_swing(), "busy refuses re-entry")


func mele_hitbox_monitoring() -> bool:
	return (melee.hitbox as Area2D).monitoring


func _until_phase(phase: String) -> void:
	for i in 120:
		if melee.phase_name() == phase:
			return
		melee.tick(1.0 / 60.0)
	ok(false, "phase reached: " + phase)


func test_idle_cooldown_buffer_fires_once_and_expires() -> void:
	melee._cooldown = 0.10
	ok(melee.request_attack())
	melee.tick(0.11)
	eq(melee.phase_name(), "windup")
	almost(melee._attack_buffer, 0.0)
	_until_phase("idle")
	melee.tick(0.5)
	eq(melee.phase_name(), "idle", "consumed press never repeats")
	melee._cooldown = 0.3
	ok(melee.request_attack())
	melee.tick(0.17)
	melee.tick(0.2)
	eq(melee.phase_name(), "idle", "expired press cannot fire later")


func test_early_link_preserves_active_and_full_recovery() -> void:
	ok(melee.request_attack())
	ok(not melee.request_attack(), "windup cannot queue")
	_until_phase("active")
	var remaining := melee._timer
	ok(melee.request_attack(), "last 120ms accepts one link")
	ok(melee.request_attack(), "repeated presses still queue only one")
	almost(melee._timer, remaining, 0.001, "input does not shorten active")
	_until_phase("recovery")
	ok(not melee.is_parry_window(), "buffer does not extend parry")
	almost(melee._timer, MeleeCombat.COMBO_RECOVERY[0])
	melee.tick(0.1)
	eq(melee.phase_name(), "recovery")
	_until_phase("windup")
	eq(melee._combo_index, 1)
	_until_phase("idle")
	eq(melee._combo_index, 0, "no third swing without another press")


func test_three_hit_chain_caps_at_finisher() -> void:
	melee.request_attack()
	for index in 2:
		_until_phase("recovery")
		ok(melee.request_attack())
		_until_phase("windup")
	eq(melee._combo_index, 2)
	_until_phase("active")
	ok(not melee.request_attack(), "finisher cannot queue a fourth")
	_until_phase("recovery")
	ok(not melee.request_attack())
	_until_phase("idle")
	melee.tick(1.0)
	eq(melee.phase_name(), "idle")


func test_pause_notification_and_cancel_discard_link() -> void:
	melee.start_swing()
	_until_phase("active")
	melee.request_attack()
	melee.notification(NOTIFICATION_PAUSED)
	ok(not melee._link_buffered)
	_until_phase("idle")
	melee.tick(0.11)  # 补接窗口（0.10s）过期，之后的按键才走冷却缓冲
	melee._cooldown = 0.1
	melee.request_attack()
	melee.clear_attack_buffer()
	melee.tick(0.2)
	eq(melee.phase_name(), "idle")
	melee.start_swing()
	_until_phase("active")
	melee.cancel_attack()
	ok(not melee.is_busy())
	ok(not melee.hitbox.monitoring)


func test_player_cutscene_and_death_cancel_queued_attacks() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	player.set_physics_process(false)
	var combat := player.melee
	combat.set_physics_process(false)
	combat.start_swing()
	for i in 12:
		combat.tick(1.0 / 60.0)
	ok(combat.is_parry_window())
	combat.request_attack()
	player.cutscene_locked = true
	combat.tick(0.01)
	ok(not combat.is_busy())
	ok(not combat._link_buffered)
	ok(not combat.request_attack(), "cutscene rejects input")
	player.cutscene_locked = false
	combat._cooldown = 0.0
	combat.start_swing()
	player.health.take_damage(99, null)
	ok(not combat.is_busy(), "death immediately disarms the sword")
	ok(not combat.hitbox.monitoring)
	ok(not combat.request_attack(), "dead player cannot queue attacks")


func test_holding_attack_does_not_generate_links() -> void:
	Input.action_press("attack")
	await get_tree().process_frame
	melee.start_swing()
	_until_phase("active")
	_until_phase("idle")
	melee.tick(0.5)
	Input.action_release("attack")
	eq(melee.phase_name(), "idle", "held input cannot restart or chain")


# ---------------------------------------------------------------------------
# 判定起点 / 打实后的收刀（真实骑士）
# ---------------------------------------------------------------------------
func _spawn_duel() -> Array:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena, Vector2(320, -24))
	player.set_physics_process(false)
	player.melee.set_physics_process(false)
	return [arena, player]


## 判定开始时已经压在剑里的目标必须在同一帧结算：贴脸挥砍不再白等一个物理帧。
func test_an_overlapping_enemy_is_hit_the_moment_active_begins() -> void:
	var pair := await _spawn_duel()
	var arena: Node2D = pair[0]
	var player: Player = pair[1]
	var skel := preload("res://scenes/enemies/SkeletonEnemy.tscn").instantiate() as SkeletonEnemy
	skel.position = Vector2(336, 0)
	arena.add_child(skel)
	await flush(2)
	skel.set_physics_process(false)
	skel._state = SkeletonEnemy.State.WALK
	skel._set_tangible(true)
	skel.visual.visible = true
	await flush(1)
	var hp := skel.health.current
	ok(player.melee.start_swing())
	for i in 60:
		if player.melee.phase_name() == "active":
			break
		player.melee.tick(1.0 / 60.0)
	eq(player.melee.phase_name(), "active")
	eq(skel.health.current, hp - 1,
			"a bone already inside the blade is cut on the active-entry frame")


## 打实 + 玩家在判定期里已经起跳：后摇第一帧就收刀，不再把骑士锁在空中。
func test_a_jump_inside_a_connected_swing_ends_recovery_at_once() -> void:
	var pair := await _spawn_duel()
	var player: Player = pair[1]
	ok(player.melee.start_swing())
	for i in 60:
		if player.melee.phase_name() == "active":
			break
		player.melee.tick(1.0 / 60.0)
	eq(player.melee.phase_name(), "active")
	player.melee.hitbox.connected = true
	player.controller._do_jump(player, false)
	eq(player.melee.phase_name(), "active", "the jump never shortens the committed active frames")
	ok(player.velocity.y < -100.0, "the jump itself launched")
	for i in 30:
		if player.melee.phase_name() != "active":
			break
		player.melee.tick(1.0 / 60.0)
	eq(player.melee.phase_name(), "idle",
			"a connected swing releases the first recovery frame once the knight is already airborne")


## 同一按键时序打在挥空上：完整后摇照旧，沉重感不被削弱。
func test_a_jump_inside_a_whiffed_swing_keeps_the_full_recovery() -> void:
	var pair := await _spawn_duel()
	var player: Player = pair[1]
	ok(player.melee.start_swing())
	for i in 60:
		if player.melee.phase_name() == "active":
			break
		player.melee.tick(1.0 / 60.0)
	eq(player.melee.phase_name(), "active")
	ok(not player.melee.swing_connected(), "nothing was hit")
	player.controller._do_jump(player, false)
	for i in 30:
		if player.melee.phase_name() != "active":
			break
		player.melee.tick(1.0 / 60.0)
	eq(player.melee.phase_name(), "recovery", "a whiff keeps its committed recovery in the air")
	ok(player.melee.recovery_progress() < 0.6, "the whiff cancel window is still closed")
