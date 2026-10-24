extends TestCase

const DRIVER := preload("res://tests/fixtures/navigation_driver.gd")
const LAYOUT := preload("res://scripts/levels/chapters/level04b_layout.gd")


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


func test_vault_checkpoint_climbs_to_the_choir_without_hitting_the_return_launch() -> void:
	var host := Node2D.new()
	add_child(host)
	var layout := LAYOUT.new()
	add_child(layout)
	layout.build(host)
	for e in host.get_node("Enemies").get_children(): e.queue_free()
	for h in LevelSanity.hazards(host): h.queue_free()
	await flush(2)
	var start := LevelSanity.feet_of(host.get_node("Props/EmberNestVault"))
	var goal := LevelSanity.feet_of(host.get_node("Props/EmberNestChoir"))
	var player := await spawn_player(host, start - Vector2(0, 20))
	var driver := DRIVER.new()
	driver.world = host
	add_child(driver)
	driver._nv_goal = goal
	var route := driver._nv_path(driver._nv_segments(), goal)
	ok(not route.is_empty())
	if route.is_empty(): return
	for i in range(1, route.size()):
		var crossed: bool = await driver._nv_cross(route[i - 1], route[i])
		ok(crossed, "crypt recovery edge %d uses basic inputs; feet=%s" % [i, player.position])
		if not crossed:
			driver._release()
			return
	ok(await driver._nv_flat(goal.x, goal.y, false))
	ok(not player.controller.extra_jumps_unlocked)
	ok(not player.inventory.has_ability(AbilityIds.HOOKSHOT_TETHER))
	driver._release()
