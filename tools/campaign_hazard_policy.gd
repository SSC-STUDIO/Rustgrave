extends RefCounted
## Read-only timing policy shared by the normal-input acceptance drivers.
## Never pauses hazards or changes their phase; an actor already inside keeps moving out.

const BODY_HALF := 7.0
const BODY_HEIGHT := 26.0
const LOOK_AHEAD := 44.0
const ACCEL_MARGIN := 0.3


static func should_wait(hazards: Array, feet: Vector2, target_x: float,
		speed: float = 108.0, look_ahead: float = LOOK_AHEAD) -> bool:
	var direction := signf(target_x - feet.x)
	if direction == 0.0:
		return false
	speed = maxf(1.0, speed)
	for node in hazards:
		if not is_instance_valid(node):
			continue
		if node is CyclicHazard:
			var zone: Rect2 = node.hit_rect()
			if not _same_height(zone, feet):
				continue
			var entry := zone.position.x - BODY_HALF if direction > 0.0 else zone.end.x + BODY_HALF
			var ahead := (entry - feet.x) * direction
			# Stopping inside a jet traps the actor. Keep moving towards the exit.
			if ahead < 0.0 or ahead > look_ahead or (target_x - entry) * direction <= 0.0:
				continue
			var clearance := minf(zone.size.x + BODY_HALF * 2.0,
					absf(target_x - entry))
			var crossing_time := (ahead + clearance) / speed + ACCEL_MARGIN
			if not node.safe_window(crossing_time):
				return true
		elif node is PendulumHazard:
			var swing := node as PendulumHazard
			if not _same_height(swing.danger_rect(), feet):
				continue
			var body := Rect2(feet - Vector2(BODY_HALF, BODY_HEIGHT),
					Vector2(BODY_HALF * 2.0, BODY_HEIGHT))
			if body.grow(swing.head_radius).has_point(swing.head_global_at(swing.clock())):
				continue
			# Predict the next quarter-second, including the moving head, rather than
			# only checking whether it is over the next footstep at this instant.
			for frame in range(1, 16):
				var seconds := float(frame) / 60.0
				var next_feet := feet + Vector2(direction * minf(speed * seconds,
						absf(target_x - feet.x)), 0.0)
				var next_body := Rect2(next_feet - Vector2(BODY_HALF, BODY_HEIGHT), body.size)
				if next_body.grow(swing.head_radius).has_point(
						swing.head_global_at(swing.clock() + seconds)):
					return true
	return false


static func _same_height(zone: Rect2, feet: Vector2) -> bool:
	return feet.y >= zone.position.y and feet.y - BODY_HEIGHT <= zone.end.y
