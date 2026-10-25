extends TestCase
## Real terrain and production inputs: a roof fall / checkpoint reload keeps its way back.

const DRIVER := preload("res://tests/fixtures/navigation_driver.gd")
const LAYOUT := preload("res://scripts/levels/chapters/level03_layout.gd")


func setup() -> void:
	Director.abort()
	Director._set_lock(false)
	SaveData.flags.clear()
	SaveData.consumed.clear()


func teardown() -> void:
	for action in [&"move_left", &"move_right", &"jump", &"dash", &"attack", &"interact"]:
		Input.action_release(action)
	SaveData.flags.clear()
	SaveData.consumed.clear()


func test_plaza_checkpoint_returns_to_roof_plate_before_gate_opens() -> void:
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
	var nest := host.get_node("Props/EmberNestPlaza") as EmberNest
	var plate := host.get_node("Props/GatePlate") as PressurePlate
	var door := host.get_node("Props/GateDoor") as ArenaDoor
	var player := await spawn_player(host, LevelSanity.feet_of(nest) - Vector2(0, 20))
	var driver := DRIVER.new()
	driver.world = host
	add_child(driver)
	driver._nv_goal = LevelSanity.feet_of(plate)
	ok(not door.is_open, "recovery starts on the locked side of the street gate")
	ok(driver._nv_path(driver._nv_segments(), Vector2(1570, 288)).is_empty(),
			"return stairs must not bypass the still-closed street gate")
	var route := driver._nv_path(driver._nv_segments(), driver._nv_goal)
	ok(not route.is_empty(), "Plaza nest must retain a basic-ability route to the rooftop plate")
	if route.is_empty():
		return
	for i in range(1, route.size()):
		var crossed: bool = await driver._nv_cross(route[i - 1], route[i])
		ok(crossed, "return edge %d uses real physics; feet=%s" % [i, player.position])
		if not crossed:
			driver._release()
			return
	ok(await driver._nv_flat(driver._nv_goal.x, driver._nv_goal.y, false))
	ok(await wait_until(func() -> bool: return door.is_open), "ordinary landing activates the existing plate signal")
	ok(not player.controller.extra_jumps_unlocked)
	ok(not player.inventory.has_ability(AbilityIds.HOOKSHOT_TETHER))
	driver._release()


func test_alley_checkpoint_climbs_the_real_stairs_to_the_quarter() -> void:
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
	var nest := host.get_node("Props/EmberNestAlley") as EmberNest
	var goal := LevelSanity.feet_of(host.get_node("Props/EmberNestQuarter"))
	var player := await spawn_player(host, LevelSanity.feet_of(nest) - Vector2(0, 20))
	var driver := DRIVER.new()
	driver.world = host
	add_child(driver)
	driver._nv_goal = goal
	var route := driver._nv_path(driver._nv_segments(), goal)
	ok(not route.is_empty(), "mandatory staircase keeps two clear 32px risers below the return eave")
	if route.is_empty(): return
	for i in range(1, route.size()):
		var crossed: bool = await driver._nv_cross(route[i - 1], route[i])
		ok(crossed, "alley recovery edge %d uses real input; feet=%s" % [i, player.position])
		if not crossed:
			driver._release()
			return
	ok(await driver._nv_flat(goal.x, goal.y, false), "reach the real quarter nest through ordinary inputs")
	eq((host.get_node("Props/RubbleRoofB") as BreakableTerrain).broken_chunks(), 0,
			"mandatory street route never needs to break the optional reward slab")
	ok(not player.controller.extra_jumps_unlocked)
	ok(not player.inventory.has_ability(AbilityIds.HOOKSHOT_TETHER))
	driver._release()
