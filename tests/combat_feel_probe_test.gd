extends TestCase
## PROBE: verify attack input no longer lost after dash/jump cancel.

var melee: MeleeCombat


func setup() -> void:
	melee = MeleeCombat.new()
	var hb := Area2D.new()
	hb.name = "Hitbox"
	hb.set_script(load("res://scripts/combat/hitbox.gd"))
	melee.add_child(hb)
	add_child(melee)
	melee.set_physics_process(false)


func _to_phase(phase: String) -> void:
	for i in 600:
		if melee.phase_name() == phase:
			return
		melee.tick(0.002)
	ok(false, "phase reached: " + phase)


func _run(delay: float) -> void:
	melee.cancel_attack()
	melee._combo_index = 0
	melee._cooldown = 0.0
	ok(melee.start_swing())
	_to_phase("recovery")
	var total := float(MeleeCombat.COMBO_RECOVERY[0])
	melee.tick(total * 0.60 + 0.002)
	ok(melee.can_dash_cancel())
	ok(melee.cancel_recovery(), "dash cancels")
	eq(melee.phase_name(), "idle")
	melee.tick(delay)
	melee.request_attack()
	for i in 60:
		melee.tick(1.0 / 60.0)
		if melee.phase_name() == "windup":
			break
	ok(melee.phase_name() == "windup", "dash delay %.2f fires" % delay)


func _run_plain(delay: float) -> void:
	melee.cancel_attack()
	melee._combo_index = 0
	melee._cooldown = 0.0
	ok(melee.start_swing())
	_to_phase("idle")
	melee.tick(delay)
	melee.request_attack()
	for i in 60:
		melee.tick(1.0 / 60.0)
		if melee.phase_name() == "windup":
			break
	ok(melee.phase_name() == "windup", "plain delay %.2f fires" % delay)


func test_probe_dash_cancel() -> void:
	for d in [0.0, 0.02, 0.05, 0.10, 0.16, 0.20, 0.24, 0.30]:
		_run(d)


func test_probe_plain_idle() -> void:
	for d in [0.0, 0.10, 0.20, 0.24, 0.30]:
		_run_plain(d)


## Combo continuity: a cancelled swing still continues the chain.
func test_probe_chain_preserved() -> void:
	# 收刀是 escape，不是接刀：连段归零，补的这一刀是重新起的第一刀（步序 0），
	# 但收刀之后冷却尾巴上的补按不能丢 —— 这正是这场改动要修的输入迟滞。
	melee.cancel_attack()
	melee._combo_index = 0
	melee._cooldown = 0.0
	ok(melee.start_swing())
	_to_phase("recovery")
	melee.tick(float(MeleeCombat.COMBO_RECOVERY[0]) * 0.60 + 0.002)
	ok(melee.cancel_recovery())
	melee.tick(0.30)
	melee.request_attack()
	for i in 30:
		melee.tick(1.0/60.0)
		if melee.phase_name() == "windup":
			break
	ok(melee.phase_name() == "windup", "post-cancel press not dropped")
	eq(melee._combo_index, 0, "cancel breaks chain: refired blow is a fresh 1st")
