extends TestCase


func setup() -> void:
	Director.abort()


func teardown() -> void:
	Director.abort()


func test_scrap_gives_kiln() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	var pile := ScrapPile.new()
	arena.add_child(pile)
	await flush(1)
	pile.interact(player)
	ok(not pile.can_interact(player))
	eq(player.inventory.pouch.size(), 1)
	eq((player.inventory.pouch[0] as RustCore).ability_id, AbilityIds.HEAT_FORGE)


func test_filter_purifies() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	player.toxin.toxin = 80.0
	var gear := FilterGear.new()
	arena.add_child(gear)
	await flush(1)
	gear.interact(player)
	ok(player.toxin.toxin < 50.0, "filter knocks toxin down")


func test_socket_station_inserts() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	player.collect_core(AbilityCatalog.ember_core())
	var bench := SocketStation.new()
	arena.add_child(bench)
	await flush(1)
	bench.interact(player)
	ok(player.inventory.has_ability(AbilityIds.EMBER_STEP))


func test_shrine_full_cleanse() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	player.toxin.toxin = 90.0
	player.health.current = 1
	var shrine := PurificationShrine.new()
	arena.add_child(shrine)
	await flush(1)
	eq(shrine.get_prompt(player), "E 祈请净化祠")
	shrine.interact(player)
	almost(player.toxin.toxin, 0.0, 0.01)
	eq(player.health.current, player.health.max_hp)
	eq(shrine.get_prompt(player), "净化祠已洁净")


func test_shrine_already_clean_announces() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	var shrine := PurificationShrine.new()
	arena.add_child(shrine)
	await flush(1)
	eq(shrine.get_prompt(player), "净化祠已洁净")
	var heard := [""]
	GameEvents.announcement.connect(func(t: String) -> void: heard[0] = t, CONNECT_ONE_SHOT)
	shrine.interact(player)
	eq(heard[0], "祠里已经没有锈可洗")


func test_closed_door_asks_for_the_plate() -> void:
	var door := ArenaDoor.new()
	add_child(door)
	await flush(1)
	ok(door.can_interact(null), "closed gate stays focusable")
	eq(door.get_prompt(null), "闸门锁死 — 需要压下踏板")
	var heard := [""]
	GameEvents.announcement.connect(func(t: String) -> void: heard[0] = t, CONNECT_ONE_SHOT)
	door.interact(null)
	ok(heard[0].contains("石板"), "E on a locked door points at the plate")
	door.open_door()
	ok(not door.can_interact(null), "open door drops the prompt")


func test_small_prop_collision_uses_reach_pad() -> void:
	var gear := FilterGear.new()
	add_child(gear)
	await flush(1)
	var col: CollisionShape2D = null
	for child in gear.get_children():
		if child is CollisionShape2D:
			col = child
			break
	ok(col != null)
	if col != null:
		var shape := col.shape as RectangleShape2D
		ok(shape != null)
		if shape != null:
			eq(shape.size, Vector2(34, 30), "14×14 gear + reach_pad (10, 8)")


func test_toxin_pool_hints_on_repeat_dip() -> void:
	Director.abort()
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	var pool := ToxinPool.new()
	arena.add_child(pool)
	pool._bodies.append(player)
	var heard := [""]
	var on_ann := func(t: String) -> void: heard[0] = t
	GameEvents.announcement.connect(on_ann)
	eq(pool.surface_rect(), Rect2(pool.global_position, Vector2(112, 32)))
	pool._physics_process(0.1)
	eq(heard[0], "腐液咬着靴底")
	heard[0] = ""
	pool._physics_process(0.1)
	eq(heard[0], "", "standing in the pool does not spam")
	pool._on_body_exited(player)
	heard[0] = ""
	pool._on_body_entered(player)
	pool._physics_process(0.1)
	eq(heard[0], "腐液咬着靴底", "leaving and dipping again re-hints")
	GameEvents.announcement.disconnect(on_ann)
	Director.abort()


func test_toxin_pool_breathes_vapor_off_the_film() -> void:
	var pool := ToxinPool.new()
	add_child(pool)
	eq(pool.vapor_count(), 0, "cold start: no wisps yet")
	# Headless skips spawning (nothing renders); drive the emitter directly.
	pool._headless = false
	for i in 40:
		pool._tick_vapor(0.1)
	ok(pool.vapor_count() >= 1, "the film exhales wisps over time")
	ok(pool.vapor_count() <= ToxinPool.VAPOR_MAX, "wisp count is capped")
	var vapor := pool.get_node_or_null("Vapor") as Node2D
	ok(vapor != null and vapor.z_index > 0, "vapor draws above the scum")
	var wisp := vapor.get_child(0) as ToxinPool.Wisp
	ok(wisp != null)
	if wisp == null:
		return
	var r := pool.surface_rect()
	ok(wisp.position.x >= 0.0 and wisp.position.x <= r.size.x, "wisps start inside the pool span")
	almost(wisp.position.y, 1.0, 0.01, "wisps start at the film surface")
	var cells := 0
	for c in wisp.get_children():
		if c is Polygon2D:
			cells += 1
			ok((c as Polygon2D).material is CanvasItemMaterial, "cells are additive so night cannot crush them")
			eq((c as Polygon2D).position, (c as Polygon2D).position.round(), "cells sit on the pixel grid")
	ok(cells >= 3 and cells <= 5, "a wisp is a loose 3-5 cell cluster")
	var y0 := wisp.position.y
	wisp._process(0.5)
	ok(wisp.position.y < y0, "vapor rises")
	ok(wisp.modulate.a > 0.0, "wisp fades in")
	eq(wisp.position, wisp.position.round(), "wisp itself is pixel snapped")
	# A gale must not carry the fog onto the bank: x stays inside the film span.
	WorldClock.wind_heading = 1.0
	WorldClock._heading_target = 1.0
	WorldClock._snap_wind_speed()
	wisp._pos.x = r.size.x - 5.0
	for i in 20:
		wisp._process(0.1)
	ok(wisp.position.x <= r.size.x - 4.0 + 0.5, "vapor is clamped to the pool span")
	ok(wisp.position.x >= 4.0 - 0.5)
	wisp._process(10.0)
	ok(wisp.is_queued_for_deletion(), "wisps die after their lifetime")
	Director.abort()


func test_toxin_pool_does_not_zero_velocity_or_cap_the_pit() -> void:
	Director.abort()
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	var pool := ToxinPool.new()
	pool.position = player.global_position + Vector2(-56.0, -8.0)
	arena.add_child(pool)
	pool.configure(Vector2(112, 32))
	ok(pool is Area2D, "film is an Area, not a Static lid")
	eq(pool.collision_layer, 128)
	eq(pool.surface_rect().size, Vector2(112, 32))
	pool._bodies.append(player)
	player.velocity = Vector2(90.0, -40.0)
	pool._physics_process(0.16)
	almost(player.velocity.x, 90.0, 0.01, "pool does not clear vx")
	almost(player.velocity.y, -40.0, 0.01, "pool does not clear vy")
	player.controller.physics_tick(player, 1.0 / 60.0, 1.0)
	ok(absf(player.velocity.x) > 1.0 or player.velocity.y != 0.0,
			"locomotion still writes velocity while overlapping the film")
	Director.abort()


## Regression: 人物与水体必须有碰撞。ToxinPool 是 Area2D，靠的是双向位匹配
## （池子 collision_mask 有玩家的 collision_layer 位）+ 池子真的长出一个
## CollisionShape2D。这里用 1A 东翼毒坑的真实几何让物理引擎自己判定重叠，
## 绝不注入 _bodies：任何一环坏了，玩家就穿着水体走过去而毫无反应。
func test_pool_detects_the_player_through_real_physics() -> void:
	var arena := Node2D.new()
	add_child(arena)
	# 坑底在 PIT_FLOOR_Y(352)，水面在 PIT_WATER_Y(328)：玩家脚点踩在 352，
	# 身体与池面矩形 328..368 有实打实的重叠（不再踩在水面石阶上却不中毒）。
	var pit_floor := StaticBody2D.new()
	pit_floor.name = "PitFloor"
	pit_floor.collision_layer = 1
	pit_floor.collision_mask = 0
	pit_floor.position = Vector2(Level01EastWing.PIT_X0,
			Level01EastWing.PIT_FLOOR_Y + Level01EastWing.PIT_FLOOR_SIZE.y * 0.5)
	var pit_shape := CollisionShape2D.new()
	var pit_rect := RectangleShape2D.new()
	pit_rect.size = Level01EastWing.PIT_FLOOR_SIZE
	pit_shape.shape = pit_rect
	pit_floor.add_child(pit_shape)
	arena.add_child(pit_floor)
	var pool := ToxinPool.new()
	pool.position = Vector2(Level01EastWing.PIT_X0, Level01EastWing.PIT_WATER_Y)
	arena.add_child(pool)
	const WATER_SIZE := Level01EastWing.PIT_WATER_SIZE
	pool.configure(WATER_SIZE)
	var col := pool.get_node_or_null("CollisionShape2D") as CollisionShape2D
	ok(col != null,
			"the pool grows its own CollisionShape2D (unnamed -> configure() re-mints one each call)")
	if col != null:
		eq((col.shape as RectangleShape2D).size, WATER_SIZE)
	var player := await spawn_player(arena,
			Vector2(Level01EastWing.PIT_X0 + 56.0, Level01EastWing.PIT_FLOOR_Y))
	await flush(10)
	ok(pool._bodies.has(player),
			"the area reports the knight standing in the sludge, not a silent pass-through")
	if not pool._bodies.has(player):
		return
	# 初入池的那句提示在 flush 期间就已经放掉了；这里先摘掉再复踏一次。
	player.toxin.toxin = 0.0
	pool._physics_process(0.5)
	ok(player.toxin.toxin > 0.0,
			"the exposed knight actually accumulates toxin from the water")
	pool._on_body_exited(player)
	var heard := [""]
	var on_ann := func(t: String) -> void: heard[0] = t
	GameEvents.announcement.connect(on_ann)
	pool._on_body_entered(player)
	pool._physics_process(0.1)
	ok(heard[0] == "腐液咬着靴底", "dipping into the water announces itself")
	heard[0] = ""
	pool._physics_process(0.1)
	ok(heard[0] == "", "and it does not spam while still standing there")
	GameEvents.announcement.disconnect(on_ann)
	Director.abort()

## 用户回归：坑内石阶如果和水面同高，人"站在水面上"、不中毒。现在水面比石阶高 8px，
## 站上石阶也必须被判定为泡在腐液里（几何常量 + 真实物理两层断言）。
func test_submerged_climb_stone_wades_in_the_sludge() -> void:
	ok(Level01EastWing.PIT_WATER_Y < Level01EastWing.PIT_CLIMB_LEFT_POS.y,
			"水面（%s）必须高于坑内石阶（%s）" % [Level01EastWing.PIT_WATER_Y,
					Level01EastWing.PIT_CLIMB_LEFT_POS.y])
	ok(Level01EastWing.PIT_WATER_Y + Level01EastWing.PIT_WATER_SIZE.y
			> Level01EastWing.PIT_FLOOR_Y, "水体要盖住坑底")
	var arena := Node2D.new()
	add_child(arena)
	var stone := StaticBody2D.new()
	stone.name = "PitClimbLeft"
	stone.collision_layer = 1
	stone.collision_mask = 0
	stone.position = Level01EastWing.PIT_CLIMB_LEFT_POS + Level01EastWing.PIT_CLIMB_LEFT_SIZE * 0.5
	var stone_shape := CollisionShape2D.new()
	var stone_rect := RectangleShape2D.new()
	stone_rect.size = Level01EastWing.PIT_CLIMB_LEFT_SIZE
	stone_shape.shape = stone_rect
	stone.add_child(stone_shape)
	arena.add_child(stone)
	var pool := ToxinPool.new()
	pool.position = Vector2(Level01EastWing.PIT_X0, Level01EastWing.PIT_WATER_Y)
	arena.add_child(pool)
	pool.configure(Level01EastWing.PIT_WATER_SIZE)
	var player := await spawn_player(arena,
			Vector2(Level01EastWing.PIT_CLIMB_LEFT_POS.x + 16.0,
					Level01EastWing.PIT_CLIMB_LEFT_POS.y - 48.0))
	await flush(20)
	ok(pool._bodies.has(player),
			"站上没入水面的石阶，Area2D 仍要把骑士判定为在水里")
	if not pool._bodies.has(player):
		Director.abort()
		return
	player.toxin.toxin = 0.0
	pool._physics_process(0.5)
	ok(player.toxin.toxin > 0.0, "泡在水里会累积毒素，而不是干着站在水面上")
	Director.abort()

