extends TestCase
## PROBE: debug cancel-link path.

var melee: MeleeCombat


func setup() -> void:
	melee = MeleeCombat.new()
	var hb := Area2D.new()
	hb.name = "Hitbox"
	hb.set_script(load("res://scripts/combat/hitbox.gd"))
	melee.add_child(hb)
	add_child(melee)
	melee.set_physics_process(false)


func test_debug() -> void:
	melee.cancel_attack()
	melee._combo_index = 0
	melee._cooldown = 0.0
	ok(melee.start_swing())
	for i in 600:
		if melee.phase_name() == "recovery":
			break
		melee.tick(0.002)
	# ride to 60% recovery
	var total := float(MeleeCombat.COMBO_RECOVERY[0])
	melee.tick(total * 0.60 + 0.002)
	ok(melee.can_dash_cancel())
	ok(melee.cancel_recovery())
	eq(melee.phase_name(), "idle")
	print("DEBUG after cancel: cooldown=%f cancel_link=%f cancel_next=%d" % [melee._cooldown, melee._cancel_link_left, melee._cancel_next])
	melee.tick(0.00)
	var cd_before := melee._cooldown
	melee.request_attack()
	print("DEBUG after request@0: phase=%s cooldown=%f cancel_link=%f cancel_next=%d buffer=%f" % [melee.phase_name(), melee._cooldown, melee._cancel_link_left, melee._cancel_next, melee._attack_buffer])
	# step frame by frame
	for i in 30:
		melee.tick(1.0/60.0)
		print("  frame %d: phase=%s cd=%f cl=%f cn=%d buf=%f" % [i, melee.phase_name(), melee._cooldown, melee._cancel_link_left, melee._cancel_next, melee._attack_buffer])
		if melee.phase_name() == "windup":
			break
