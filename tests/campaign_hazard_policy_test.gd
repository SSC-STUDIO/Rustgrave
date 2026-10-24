extends TestCase

const POLICY := preload("res://tools/campaign_hazard_policy.gd")


func setup() -> void:
	Director._set_lock(false)


func _jet(phase: float = 0.0, width: float = 24.0) -> CyclicHazard:
	var jet := CyclicHazard.new()
	jet.position = Vector2(100, 320)
	jet.thick = width
	jet.phase = phase
	add_child(jet)
	jet.set_physics_process(false)
	return jet


func test_waits_for_enough_time_to_clear_the_full_jet_in_both_directions() -> void:
	var jet := _jet()
	jet.tick(2.0) # 0.7s left; momentarily safe, too short for the entire crossing.
	ok(jet.safe_window(0.1))
	ok(POLICY.should_wait([jet], Vector2(64, 320), 150.0))
	ok(POLICY.should_wait([jet], Vector2(136, 320), 50.0))
	jet.tick(jet.period() - jet.clock())
	ok(not POLICY.should_wait([jet], Vector2(64, 320), 150.0))
	ok(not POLICY.should_wait([jet], Vector2(136, 320), 50.0))


func test_escapes_active_zone_and_ignores_other_floors_or_goals_before_it() -> void:
	var jet := _jet(0.9)
	ok(not jet.safe_window())
	ok(not POLICY.should_wait([jet], Vector2(100, 320), 150.0), "keep moving out, never wait inside")
	ok(not POLICY.should_wait([jet], Vector2(64, 224), 150.0), "rooftop is above the vent")
	ok(not POLICY.should_wait([jet], Vector2(64, 320), 72.0), "destination is before the vent")
	ok(not POLICY.should_wait([jet], Vector2(16, 320), 150.0), "distant hazard must not pin the actor")
	ok(POLICY.should_wait([jet], Vector2(64, 320), 150.0))


func test_crossing_time_scales_with_width_and_controller_speed() -> void:
	var jet := _jet(0.0, 96.0)
	jet.tick(1.3) # 1.4 seconds remain before damage.
	ok(not POLICY.should_wait([jet], Vector2(40, 320), 170.0, 108.0))
	ok(POLICY.should_wait([jet], Vector2(40, 320), 170.0, 54.0), "a slowed actor needs a longer safe interval")


func test_predicts_a_pendulum_head_moving_into_the_next_steps() -> void:
	var swing := PendulumHazard.new()
	swing.position = Vector2(100, 224)
	add_child(swing)
	swing.set_physics_process(false)
	# At t=0 the head is at x100 and swings right. A knight to its right
	# cannot simply follow it because it catches up during the next steps.
	ok(POLICY.should_wait([swing], Vector2(140, 320), 220.0, 54.0))
	ok(not POLICY.should_wait([swing], Vector2(40, 224), 220.0), "upper ledge is outside the swing")
	ok(not POLICY.should_wait([swing], Vector2(100, 320), 40.0), "leave a current overlap")
