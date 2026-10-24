extends TestCase

const POUR := preload("res://scripts/levels/chapters/level07b_pour.gd")
const POLICY := preload("res://tools/campaign_hazard_policy.gd")


func setup() -> void:
	Director.abort()
	Director._set_lock(false)


func test_cleared_boss_pour_reports_safe_after_stopping_during_active_damage() -> void:
	var pour := POUR.new()
	pour.position = Vector2(4016, 160)
	pour.facing = Vector2.DOWN
	pour.reach = 160.0
	pour.ignited = false
	add_child(pour)
	pour.trigger()
	await wait_until(func() -> bool: return pour.is_active(), 120)
	ok(pour.is_active())
	ok(not pour.safe_window(0.8), "live active pour blocks a crossing")
	ok(POLICY.should_wait([pour], Vector2(3966, 320), 4040))
	pour.stop()
	await flush(2)
	ok(not pour.is_active())
	ok(not pour._armed, "arena clearance removes the real damage hitbox")
	ok(pour.safe_window(60.0), "extinguished pour has no upcoming active period")
	ok(is_inf(pour.seconds_until_active()))
	ok(not POLICY.should_wait([pour], Vector2(3966, 320), 4040), "normal-input policy can leave the cleared arena")


func test_reigniting_a_stopped_pour_restores_its_real_warning_deadline() -> void:
	var pour := POUR.new()
	pour.ignited = false
	add_child(pour)
	ok(pour.safe_window(60.0))
	pour.trigger()
	ok(pour.is_warning())
	ok(pour.safe_window(0.2))
	ok(not pour.safe_window(60.0))
	ok(is_finite(pour.seconds_until_active()))
	await wait_until(func() -> bool: return pour.is_active(), 120)
	ok(pour.is_active())
