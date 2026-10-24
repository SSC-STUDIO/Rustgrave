extends TestCase
## 使用真实 Health/Hurtbox 结算，覆盖两种 BossDirector 模式及七个首领的取消钩子。

const DT := 1.0 / 60.0
const BOSSES := {
	"executioner": "res://scenes/enemies/ExecutionerBoss.tscn",
	"hollow_bell": "res://scenes/enemies/HollowBell.tscn",
	"capstan_warden": "res://scenes/enemies/CapstanWarden.tscn",
	"silent_choir": "res://scenes/enemies/SilentChoir.tscn",
	"bell_founder": "res://scenes/enemies/BellFounder.tscn",
	"emberwind_herald": "res://scenes/enemies/EmberwindHerald.tscn",
	"nightmare": "res://scenes/enemies/NightmareBoss.tscn",
}


func setup() -> void:
	Director._set_lock(false)
	SaveData.flags.clear()
	build_floor(self)


func _spawn(id: String) -> EnemyBase:
	var enemy := (load(BOSSES[id]) as PackedScene).instantiate() as EnemyBase
	enemy.position = Vector2(320, 0)
	add_child(enemy)
	# Keep repeated hit tests in phase one; phase transitions have their own suite.
	enemy.health.max_hp = 1000
	enemy.health.heal_full()
	enemy.set_physics_process(false)
	var director := enemy.get_node("BossDirector") as BossDirector
	director.set_physics_process(false)
	return enemy


func _blade(blow: StringName = &"finisher", eligible: bool = true) -> Hitbox:
	var blade := Hitbox.new()
	blade.blow = blow
	blade.riposte_eligible = eligible
	add_child(blade)
	return blade


func _strike(enemy: EnemyBase, blade: Hitbox) -> void:
	enemy.health._hit_iframe = 0.0
	(enemy.get_node("Hurtbox") as Hurtbox).receive_hit(1, blade)


func test_only_successful_blade_finishers_accumulate_and_ordinary_combos_keep_progress() -> void:
	var enemy := _spawn("nightmare")
	var director := enemy.get_node("BossDirector") as BossDirector
	_strike(enemy, _blade(&"heavy"))
	_strike(enemy, _blade(&"finisher", false))
	eq(director.poise_hits(), 0, "heavy swings and secondary effects do not count")
	var blade := _blade()
	_strike(enemy, blade)
	eq(director.poise_hits(), 1)
	# A second overlap rejected by Health's i-frame never reaches the meter.
	(enemy.get_node("Hurtbox") as Hurtbox).receive_hit(1, blade)
	eq(director.poise_hits(), 1)
	_strike(enemy, _blade(&"light"))
	eq(director.poise_hits(), 1, "light steps between finishers preserve progress")
	_strike(enemy, blade)
	ok(director.is_poise_broken())
	eq(director.poise_hits(), 0)
	ok(enemy.is_hurt_locked())
	ok(not (enemy.get_node("Hitbox") as Hitbox).monitoring)
	ok(enemy._opening_mark != null, "the recovery has a visible gold opening")


func test_poise_window_and_immunity_expire_without_stunlock() -> void:
	var enemy := _spawn("nightmare")
	var director := enemy.get_node("BossDirector") as BossDirector
	var blade := _blade()
	_strike(enemy, blade)
	director.tick(CombatRules.BOSS_POISE_WINDOW + DT)
	eq(director.poise_hits(), 0, "a stale finisher cannot be banked forever")
	_strike(enemy, blade)
	_strike(enemy, blade)
	ok(director.is_poise_broken())
	_strike(enemy, blade)
	eq(director.poise_hits(), 0, "recovery ignores fresh finishers")
	director.tick(CombatRules.BOSS_POISE_RECOVERY + DT)
	ok(not director.is_poise_broken())
	_strike(enemy, blade)
	eq(director.poise_hits(), 0, "short immunity outlasts the recovery")
	director.tick(CombatRules.BOSS_POISE_COOLDOWN)
	_strike(enemy, blade)
	eq(director.poise_hits(), 1, "the meter rearms after immunity")


func test_poise_freezes_with_pause_cinematics_and_director_then_resets_on_restart() -> void:
	var enemy := _spawn("nightmare")
	var director := enemy.get_node("BossDirector") as BossDirector
	_strike(enemy, _blade())
	director.freeze()
	director.tick(10.0)
	eq(director.poise_hits(), 1)
	director.resume()
	director.set_physics_process(false)
	Director._set_lock(true)
	director.tick(10.0)
	eq(director.poise_hits(), 1)
	Director._set_lock(false)
	get_tree().paused = true
	director.tick(10.0)
	get_tree().paused = false
	eq(director.poise_hits(), 1)
	director.reset_fight()
	eq(director.poise_hits(), 0)
	ok(not director.is_poise_broken())


func test_front_shield_and_lethal_damage_never_trigger_poise() -> void:
	var enemy := _spawn("executioner") as ExecutionerBoss
	var director := enemy.get_node("BossDirector") as BossDirector
	var blade := _blade()
	enemy._shield_facing = 1
	enemy._set_blocking(true)
	blade.position = Vector2(400, -30)
	_strike(enemy, blade)
	_strike(enemy, blade)
	eq(director.poise_hits(), 0, "front guard still fully blocks finishers")
	enemy._set_blocking(false)
	enemy.health.current = 2
	_strike(enemy, blade)
	eq(director.poise_hits(), 1)
	_strike(enemy, blade)
	eq(enemy.health.current, 0)
	ok(not director.is_poise_broken(), "death wins over the second finisher")
	eq(director.poise_hits(), 0)


func test_every_boss_cancels_windup_and_recovers_without_changing_phase_or_geometry() -> void:
	for id in BOSSES:
		var enemy := _spawn(id)
		var director := enemy.get_node("BossDirector") as BossDirector
		var shape := (enemy.get_node("CollisionShape2D") as CollisionShape2D).shape
		var shape_before := shape.get_rect()
		var scale_before := enemy.scale
		# Start a real attack before triggering two successful finisher hits.
		enemy.set_physics_process(true)
		if id == "executioner":
			enemy.call("_begin_slash")
			enemy.call("_set_blocking", false)  # rear strikes, independent of the guard
		elif id == "nightmare":
			enemy.call("_enter_windup")
		else:
			director.start()
			director.pick_and_start(100.0)
		enemy.set_physics_process(false)
		_strike(enemy, _blade())
		_strike(enemy, _blade())
		ok(director.is_poise_broken(), "%s enters finisher recovery" % id)
		ok(enemy.is_hurt_locked(), "%s cannot advance its attack" % id)
		ok(not director.is_busy(), "%s releases the scheduled attack" % id)
		for child in enemy.get_children():
			if child is CombatMarker and child.kind in [CombatMarker.Kind.RING,
					CombatMarker.Kind.ZONE, CombatMarker.Kind.LANE]:
				ok(not child.visible or child.is_queued_for_deletion(), "%s clears its warning" % id)
		if enemy.get_node_or_null("Hitbox") is Hitbox:
			ok(not (enemy.get_node("Hitbox") as Hitbox).monitoring, "%s contact is disarmed" % id)
		eq(director.phase, 1, "%s retains its phase" % id)
		eq(shape.get_rect(), shape_before, "%s collision shape is unchanged" % id)
		eq(enemy.scale, scale_before, "%s scale is unchanged" % id)
		# The same director can schedule again after the punish window.
		director.tick(CombatRules.BOSS_POISE_RECOVERY + DT)
		ok(not director.is_poise_broken(), "%s has bounded recovery" % id)
		enemy._hurt_lock = 0.0
		enemy.call("_tick_state", DT)
		if director.auto_drive:
			ok(director.attack_count >= 1, "%s retains its attack scheduler" % id)
		enemy.queue_free()
		await flush(1)


func test_all_seven_active_melee_volumes_disarm_at_the_break() -> void:
	for id in BOSSES:
		var enemy := _spawn(id)
		var director := enemy.get_node("BossDirector") as BossDirector
		var active: Hitbox
		match id:
			"executioner":
				enemy.call("_do_slash")
				active = enemy.get("_slash_box") as Hitbox
			"hollow_bell":
				enemy.call("_begin_pendulum")
				enemy.call("_spawn_pendulum_box")
				active = enemy.get("_fling") as Hitbox
			"capstan_warden":
				enemy.call("_execute_chain")
				active = enemy.get("_active_box") as Hitbox
			"silent_choir":
				enemy.call("_execute_cone")
				active = enemy.get("_active_box") as Hitbox
			"bell_founder":
				enemy.call("_do_hammer")
				for node in enemy.get("_transient"):
					if node is Hitbox:
						active = node as Hitbox
			"emberwind_herald":
				enemy.call("_begin_dive")
				enemy.call("_do_dive")
				active = enemy.get_node("Hitbox") as Hitbox
			"nightmare":
				enemy.call("_begin_charge")
				active = enemy.get_node("Hitbox") as Hitbox
		ok(active != null and active.monitoring, "%s fixture reaches a real active volume" % id)
		_strike(enemy, _blade())
		_strike(enemy, _blade())
		ok(director.is_poise_broken(), "%s active attack can break" % id)
		ok(active != null and not active.monitoring, "%s cancels damage immediately" % id)
		enemy.queue_free()
		await flush(1)
