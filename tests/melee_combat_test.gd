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
