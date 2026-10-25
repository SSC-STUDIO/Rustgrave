extends TestCase

const TILES := preload("res://scripts/levels/chapters/level03_falling_tiles.gd")

func setup() -> void:
	Director._set_lock(false)

func teardown() -> void:
	Director._set_lock(false)

func _make(phase: float = 0.0) -> CyclicHazard:
	var tile := TILES.new()
	tile.phase = phase
	add_child(tile)
	tile.set_physics_process(false)
	return tile

func test_warning_precedes_fall_and_hitbox_tracks_the_tile() -> void:
	var tile := _make()
	var hit := tile.get_node("HazardHitbox") as Hitbox
	var shape := tile.get_node("HazardHitbox/CollisionShape2D") as CollisionShape2D
	ok(tile.safe_window(1.0), "a deliberate crossing fits the initial safe window")
	tile.tick(tile.rest_time + tile.telegraph_time * 0.5)
	eq(tile.state(), CyclicHazard.State.WARN)
	ok(not hit.monitoring, "warning dust cannot hurt")
	tile.tick(tile.seconds_until_active() + 0.02)
	ok(hit.monitoring, "falling tiles arm after the full warning")
	var early_y := shape.position.y
	ok(early_y < -80.0, "early falling tiles have no ground-level hitbox")
	tile.tick(0.1)
	ok(shape.position.y > early_y, "collision descends with visible tiles")
	almost(shape.position.y + TILES.TILE_HEIGHT * 0.5, tile.fall_bottom(), 0.001)
	tile.tick(TILES.FALL_SECONDS)
	ok(not hit.monitoring, "shattered floor fragments are harmless")
	tile.tick(tile.active_time)
	ok(tile.safe_window(1.0), "the next rest gives another safe crossing")

func test_shattered_phase_starts_harmless_and_rearms_next_fall() -> void:
	var tile := _make(0.99)
	var hit := tile.get_node("HazardHitbox") as Hitbox
	eq(tile.state(), CyclicHazard.State.ACTIVE)
	ok(not hit.monitoring, "loading during the fragment tail never arms it")
	tile.tick(tile.seconds_until_safe() + 0.01)
	tile.tick(tile.seconds_until_active() + 0.02)
	ok(hit.monitoring, "the next real fall still arms normally")

func test_cinematic_lock_freezes_fall_and_disarms_it() -> void:
	var tile := _make()
	var hit := tile.get_node("HazardHitbox") as Hitbox
	tile.tick(tile.seconds_until_active() + 0.02)
	var time := tile.clock()
	var bottom: float = tile.fall_bottom()
	Director._set_lock(true)
	tile.tick(0.8)
	almost(tile.clock(), time)
	almost(tile.fall_bottom(), bottom)
	ok(not hit.monitoring, "cinematics suppress falling collision")
	Director._set_lock(false)
	tile.tick(0.01)
	ok(hit.monitoring, "unfinished fall resumes after the lock")
