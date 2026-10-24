extends TestCase
## Regression from the ordinary-input campaign: a missed stepping stone must
## leave a real single-jump exit from the sluice, with the gate still closed.

const DRIVER := preload("res://tests/fixtures/navigation_driver.gd")
const LAYOUT := preload("res://scripts/levels/chapters/level02b_layout.gd")


func setup() -> void:
	Director.abort()
	Director._set_lock(false)


func teardown() -> void:
	for action in [&"move_left", &"move_right", &"jump", &"dash", &"attack", &"interact"]:
		Input.action_release(action)


func test_missed_sluice_stone_can_recover_to_the_east_bank() -> void:
	var host := Node2D.new()
	add_child(host)
	var layout := LAYOUT.new()
	add_child(layout)
	layout.build(host)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	for hazard in LevelSanity.hazards(host):
		hazard.queue_free()
	await flush(2)
	var player := await spawn_player(host, Vector2(712, 328))
	player.health.invincible = true
	var driver := DRIVER.new()
	driver.world = host
	add_child(driver)
	driver._nv_goal = Vector2(756, 320)
	var route := driver._nv_path(driver._nv_segments(), driver._nv_goal)
	ok(not route.is_empty(), "east bank has a basic recovery route")
	if route.is_empty(): return
	for i in range(1, route.size()):
		var crossed: bool = await driver._nv_cross(route[i - 1], route[i])
		ok(crossed, "recovery edge %d uses ordinary physics; feet=%s" % [i, player.position])
		if not crossed:
			driver._release()
			return
	almost(player.position.y, 320.0, 1.0)
	ok(not player.controller.extra_jumps_unlocked)
	driver._release()


func test_pump_lift_hands_off_to_the_upper_shortcut_route_with_basic_inputs() -> void:
	var host := Node2D.new()
	add_child(host)
	var layout := LAYOUT.new()
	add_child(layout)
	layout.build(host)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	for hazard in LevelSanity.hazards(host):
		hazard.queue_free()
	await flush(2)
	var player := await spawn_player(host, Vector2(2518, 272))
	player.health.invincible = true
	var lift := host.get_node("Platforms/PumpLift") as MovingPlatform
	var driver := DRIVER.new()
	driver.world = host
	add_child(driver)
	driver._nv_goal = Vector2(2784, 320)
	var bottom := {"r": Rect2(2500, 296, 48, 16), "lift": lift}
	var top := {"r": Rect2(2500, 152, 48, 16), "lift": lift}
	ok(await driver._nv_cross(bottom, top), "ordinary input rides to the top of the real pump lift")
	var landed: bool = await driver._nv_cross(top, {"r": Rect2(2600, 168, 80, 16), "lift": null})
	ok(landed, "single jump and dash reach the east overlook; feet=%s" % player.position)
	almost(player.position.y, 168.0, 1.0)
	ok(not player.controller.extra_jumps_unlocked)
	driver._release()


func test_east_overlook_descends_past_the_closed_shortcut_gate() -> void:
	var host := Node2D.new()
	add_child(host)
	var layout := LAYOUT.new()
	add_child(layout)
	layout.build(host)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	for hazard in LevelSanity.hazards(host):
		hazard.queue_free()
	await flush(2)
	var player := await spawn_player(host, Vector2(2636, 144))
	player.health.invincible = true
	var driver := DRIVER.new()
	driver.world = host
	add_child(driver)
	driver._nv_goal = Vector2(2796, 320)
	var route := driver._nv_path(driver._nv_segments(), driver._nv_goal)
	ok(not route.is_empty())
	if route.is_empty(): return
	for i in range(1, route.size()):
		var crossed: bool = await driver._nv_cross(route[i - 1], route[i])
		ok(crossed, "east descent edge %d; feet=%s" % [i, player.position])
		if not crossed:
			driver._release()
			return
	ok(await driver._nv_flat(2796, 320, false))
	ok((host.get_node("Props/PumpShortcutDoor") as ArenaDoor).is_open, "normal plate contact opens the shortcut")
	driver._release()
