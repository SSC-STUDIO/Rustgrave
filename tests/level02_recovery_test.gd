extends TestCase
## Geometry fixture: real chapter terrain and ordinary movement/jump/dash inputs.
## Actors/hazards are parked so this isolates recovery after a missed gallery jump.

const DRIVER := preload("res://tests/fixtures/navigation_driver.gd")


func setup() -> void:
	Director.abort()
	Director._set_lock(false)


func teardown() -> void:
	for action in [&"move_left", &"move_right", &"jump", &"dash", &"attack", &"interact"]:
		Input.action_release(action)


func test_entry_prefers_the_broad_recoverable_floor_over_narrow_uphill_stones() -> void:
	var host := Node2D.new()
	add_child(host)
	var layout := Level02Layout.new()
	add_child(layout)
	layout.build(host)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	for hazard in LevelSanity.hazards(host):
		hazard.queue_free()
	for prop in host.get_node("Props").get_children():
		if prop is ToxinPool: prop.queue_free()
	await flush(2)
	var player := await spawn_player(host, Vector2(176, 296))
	var driver := DRIVER.new()
	driver.world = host
	add_child(driver)
	driver._nv_goal = Vector2(1020, 264)
	var segments := driver._nv_segments()
	for segment in segments: segment.wet = false # campaign's documented level02 toxin policy
	var route := driver._nv_path(segments, driver._nv_goal)
	ok(not route.is_empty())
	if route.is_empty(): return
	ok(route[1].r.position == Vector2(448, 352), "same hop count favors the broad recoverable floor")
	for i in range(1, route.size()):
		var crossed: bool = await driver._nv_cross(route[i - 1], route[i])
		ok(crossed, "entry floor route edge %d; feet=%s" % [i, player.position])
		if not crossed:
			driver._release()
			return
	ok(await driver._nv_flat(1020, 264, false))
	ok(not player.controller.extra_jumps_unlocked)
	driver._release()


func test_boss_approach_clears_the_belfry_and_intact_cache_with_basic_inputs() -> void:
	var host := Node2D.new()
	add_child(host)
	var layout := Level02Layout.new()
	add_child(layout)
	layout.build(host)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	for hazard in LevelSanity.hazards(host):
		hazard.queue_free()
	await flush(2)
	var player := await spawn_player(host, Vector2(2632, 296))
	var driver := DRIVER.new()
	driver.world = host
	add_child(driver)
	driver._nv_goal = driver._nv_clear_approach(Vector2(3340, 320), 1.0)
	ok(driver._nv_goal.x >= 3376.0, "approach leaves room for the body beside the intact cache")
	var route := driver._nv_path(driver._nv_segments(), driver._nv_goal)
	ok(not route.is_empty(), "real arena terrain has an input route to the boss")
	if route.is_empty(): return
	ok(driver._nv_link({"r": Rect2(3168, 320, 104, 16), "lift": null},
			{"r": Rect2(3272, 288, 64, 16), "lift": null}),
			"the real lip has space for a vertical single jump after the low ceiling")
	# The full navigator replans after a jump catches a different real landing.
	# Exercise that production behavior rather than requiring a perfect hop.
	ok(await driver._nv_navigate(driver._nv_goal, false), "normal input and live replanning reach the boss approach")
	ok(is_instance_valid(host.get_node("Props/ArenaCacheWest")), "route keeps the narrow west urn intact")
	ok(is_instance_valid(host.get_node("Props/ArenaCacheEast")), "route keeps the original cache intact")
	ok(player.is_on_floor() and player.health.current > 0)
	ok(not player.controller.extra_jumps_unlocked)
	driver._release()


func test_sunken_hall_has_a_basic_ability_recovery_route_before_shortcut_is_open() -> void:
	var host := Node2D.new()
	add_child(host)
	var layout := Level02Layout.new()
	add_child(layout)
	layout.build(host)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	for hazard in LevelSanity.hazards(host):
		hazard.queue_free()
	await flush(2)
	var player := await spawn_player(host, Vector2(2050, 328))
	player.health.invincible = true
	var driver := DRIVER.new()
	driver.world = host
	add_child(driver)
	driver._nv_goal = Vector2(2460, 320)
	var route := driver._nv_path(driver._nv_segments(), driver._nv_goal)
	ok(not route.is_empty(), "a missed gallery jump must not strand the knight below the closed shortcut")
	if route.is_empty():
		return
	for i in range(1, route.size()):
		var crossed: bool = await driver._nv_cross(route[i - 1], route[i])
		ok(crossed, "recovery edge %d uses production player physics; feet=%s" % [i, player.position])
		if not crossed:
			driver._release()
			return
	ok(await driver._nv_flat(2460.0, 320.0, false))
	almost(player.position.y, 320.0, 1.0)
	ok(not player.controller.extra_jumps_unlocked)
	driver._release()


func test_west_recovery_stair_descends_under_the_hall_gallery() -> void:
	var host := Node2D.new()
	add_child(host)
	var layout := Level02Layout.new()
	add_child(layout)
	layout.build(host)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	for hazard in LevelSanity.hazards(host):
		hazard.queue_free()
	await flush(2)
	var player := await spawn_player(host, Vector2(1920, 264))
	player.health.invincible = true
	var driver := DRIVER.new()
	driver.world = host
	add_child(driver)
	driver._nv_goal = Vector2(2180, 352)
	ok(not driver._nv_drop_side_clear(Rect2(1976,256,160,16), Rect2(1960,352,472,16), false),
			"west lip clearance includes the real body's braking tolerance")
	var route := driver._nv_path(driver._nv_segments(), driver._nv_goal)
	ok(not route.is_empty(), "floor beneath the launch stair does not remove the real descent")
	if route.is_empty(): return
	for i in range(1, route.size()):
		var crossed: bool = await driver._nv_cross(route[i - 1], route[i])
		ok(crossed, "west descent edge %d uses actual input; feet=%s" % [i, player.position])
		if not crossed:
			driver._release()
			return
	ok(await driver._nv_flat(2180, 352, false))
	almost(player.position.y, 352.0, 1.0)
	ok(not player.controller.extra_jumps_unlocked)
	driver._release()
