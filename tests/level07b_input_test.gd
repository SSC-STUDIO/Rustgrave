extends TestCase

const DRIVER := preload("res://tests/fixtures/navigation_driver.gd")
const RAMP := preload("res://scripts/levels/chapters/level07b_mould_ramp.gd")


func setup() -> void:
	Director.abort()
	Director._set_lock(false)


func teardown() -> void:
	for action in [&"move_left", &"move_right", &"jump", &"dash", &"attack", &"interact"]:
		Input.action_release(action)


func test_real_bell_mould_ramp_allows_a_grounded_runup_and_basic_jump() -> void:
	var host := Node2D.new()
	add_child(host)
	var props := Node2D.new()
	props.name = "Props"
	host.add_child(props)
	var layout := ChapterLayout.new()
	add_child(layout)
	layout.step(host, "FloorE", Vector2(3344, 320), 512.0)
	layout.step(host, "BellMould", Vector2(3600, 288), 176.0)
	var ramp := RAMP.new()
	ramp.position = Vector2(3536, 288)
	host.get_node("Platforms").add_child(ramp)
	var player := await spawn_player(host, Vector2(3488, 296))
	var driver := DRIVER.new()
	driver.world = host
	add_child(driver)
	ok(await driver._nv_flat(3564, 320, false), "normal input settles on the actual rising floor")
	ok(absf(player.get_floor_normal().x) > 0.1, "position is supported by the real ramp")
	ok(player.position.y < 316.0)
	driver._nv_goal = Vector2(3618, 288)
	var route := driver._nv_path(driver._nv_segments(), driver._nv_goal)
	ok(not route.is_empty())
	if route.is_empty(): return
	for i in range(1, route.size()):
		ok(await driver._nv_cross(route[i - 1], route[i]), "mould approach edge uses ordinary input")
	almost(player.position.y, 288.0, 1.0)
	ok(player.is_on_floor())
	ok(not driver._nv_grounded_near(player.position.x, 320), "a level floor cannot use the slope tolerance")
	ok(not player.controller.extra_jumps_unlocked)
	driver._release()
