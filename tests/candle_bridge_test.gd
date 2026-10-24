extends TestCase
## 烛光桥（CandleBridge）单元测试：
##   1. 点燃 / 预警闪烁 / 熄灭 / 再次点燃时间线与碰撞体开关；
##   2. 骑士靠近烛台（~48px）或挥砍烛台触发点燃，桥面实心可站；
##   3. LevelSanity 规则：计入主线可达（allow_hook=false），拒绝作巢/压板/出口支撑，烛台离巢 ≥40px。


func setup() -> void:
	Director.abort()
	Director.resume()


func teardown() -> void:
	Director.abort()
	Director.resume()


func _host() -> Node2D:
	var host := Node2D.new()
	add_child(host)
	return host


func _bridge(host: Node2D, pos: Vector2 = Vector2(200, -48), width: float = 96.0,
		candle_pos: Vector2 = Vector2(160, 0), props: Dictionary = {}) -> CandleBridge:
	var layout := ChapterLayout.new()
	add_child(layout)
	return layout.candle_bridge(host, "CryptCandleBridge", pos, width, candle_pos, props)


func _shapes(bridge: CandleBridge) -> Array[CollisionShape2D]:
	var out: Array[CollisionShape2D] = []
	for child in bridge.get_children():
		if child is CollisionShape2D:
			out.append(child as CollisionShape2D)
	return out


func test_timeline_unlit_ignite_warn_extinguish_and_reignite() -> void:
	var bridge := _bridge(_host(), Vector2(200, -48), 96.0, Vector2(160, 0),
			{"lit_time": 6.0, "warn_time": 1.2})
	bridge.set_physics_process(false)
	await flush(1)
	ok(bridge.is_in_group(CandleBridge.GROUP), "registered in hazards group")
	eq(String(bridge.get_meta("hazard_kind", "")), "candle", "carries candle hazard_kind metadata")
	var hint := bridge.get_node_or_null("HazardHint") as HintArea
	ok(hint != null and hint.hint_id == &"candle", "attaches first-encounter candle hint")
	eq(bridge.state(), CandleBridge.State.UNLIT, "starts unlit by default")
	ok(not bridge.is_lit() and not bridge.is_solid(), "unlit bridge is not solid")
	var shapes := _shapes(bridge)
	ok(not shapes.is_empty(), "bridge has collision shapes")
	for s in shapes:
		ok(s.disabled, "unlit: collision is disabled")
	var skin := bridge.get_node_or_null("Skin") as Node2D
	ok(skin != null and skin.modulate.a < 0.5, "unlit: drawn as a semi-transparent silhouette")

	ok(bridge.ignite(), "first ignite lights the bridge")
	eq(bridge.state(), CandleBridge.State.LIT)
	ok(bridge.is_lit() and bridge.is_solid(), "lit bridge is solid")
	almost(bridge.time_left(), 6.0, 0.01)
	await flush(1)
	for s in shapes:
		ok(not s.disabled, "lit: collision is enabled")
	almost(skin.modulate.a, 1.0, 0.01, "lit: full opacity")

	bridge.tick(4.5)
	ok(bridge.is_lit() and not bridge.is_warning(), "still steady before warn window")
	bridge.tick(0.6)
	ok(bridge.is_lit() and bridge.is_warning(), "last 1.2s enters warning flicker")
	ok(bridge.is_solid(), "still solid during warning window")

	bridge.tick(1.2)
	eq(bridge.state(), CandleBridge.State.UNLIT, "candle and bridge extinguish after lit_time")
	ok(not bridge.is_lit() and not bridge.is_solid())
	await flush(1)
	for s in shapes:
		ok(s.disabled, "extinguished: collision disabled again")

	ok(bridge.ignite(), "approaching again reignites the candle bridge")
	ok(bridge.is_lit() and bridge.is_solid(), "reignited bridge is solid again")


func test_proximity_and_slash_ignite_candle_and_support_knight() -> void:
	var host := _host()
	build_floor(host)
	var bridge := _bridge(host, Vector2(260, -32), 96.0, Vector2(216, 0),
			{"lit_time": 4.0, "hint_id": &""})
	var player := await spawn_player(host, Vector2(80, -24))
	await flush(4)
	ok(not bridge.is_lit(), "far from the candle, bridge stays unlit")

	# 靠近烛台（半径 ~48px 内）自动点燃
	player.global_position = Vector2(204, -16)
	await flush(4)
	ok(bridge.is_lit(), "entering ~48px of the candle ignites the bridge")

	# 跳上点燃的桥面可稳稳站住
	player.global_position = Vector2(300, -56)
	player.velocity = Vector2.ZERO
	await flush(18)
	ok(player.is_on_floor() and player.global_position.y < -20.0,
			"the knight stands on the lit candle bridge (y=%.1f)" % player.global_position.y)

	# 熄灭后桥面消失，骑士落回地面（不死、不卡住）
	bridge.extinguish()
	await flush(24)
	ok(player.global_position.y > -12.0, "when the bridge fades, the knight drops safely to the floor below")

	# 剑刃挥砍烛台 Area2D 也能点燃
	player.global_position = Vector2(80, -24)
	await flush(2)
	ok(not bridge.is_lit(), "bridge is unlit before slash")
	var slash := Hitbox.new()
	slash.team = &"player"
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(24, 24)
	shape.shape = rect
	slash.add_child(shape)
	host.add_child(slash)
	slash.global_position = bridge.candle_global_position() + Vector2(0, -10)
	slash.arm()
	await flush(3)
	bridge.tick(0.05)
	ok(bridge.is_lit(), "striking the candle with a player hitbox ignites the bridge")
	slash.queue_free()


func test_sanity_reachability_and_hazard_rules() -> void:
	var host := _host()
	var layout := ChapterLayout.new()
	add_child(layout)
	layout.floor_strip(host, "FloorWest", 0.0, 240.0, "nave")
	layout.floor_strip(host, "FloorSafety", 240.0, 480.0, "nave", false, false, 352.0)
	layout.floor_strip(host, "FloorEast", 480.0, 800.0, "nave")
	layout.nest(host, "NestStart", 96.0, 320.0)
	layout.candle_bridge(host, "Bridge1", Vector2(264, 304), 80.0, Vector2(216, 320))
	layout.candle_bridge(host, "Bridge2", Vector2(376, 288), 80.0, Vector2(320, 304))
	await flush(1)

	eq(LevelSanity.check(host), [] as Array[String], "valid candle bridge layout passes LevelSanity")
	ok(LevelSanity.is_reachable(host, Vector2(96, 300), Vector2(600, 320), false),
			"main route (allow_hook=false) crosses via candle bridges")

	# 规则 1：不得作为余烬巢 / 压板 / 出口的支撑
	var bad_support := _host()
	var l2 := ChapterLayout.new()
	add_child(l2)
	l2.floor_strip(bad_support, "Floor", 0.0, 600.0, "nave")
	l2.candle_bridge(bad_support, "Bridge", Vector2(240, 272), 96.0, Vector2(180, 320))
	l2.nest(bad_support, "NestOnBridge", 280.0, 272.0)
	var support_problems := LevelSanity.check(bad_support)
	var found_support := false
	for p in support_problems:
		if p.contains("NestOnBridge") and p.contains("candle"):
			found_support = true
	ok(found_support, "EmberNest on a CandleBridge is rejected: %s" % [support_problems])

	# 规则 2：烛台离余烬巢 ≥40px
	var bad_candle := _host()
	var l3 := ChapterLayout.new()
	add_child(l3)
	l3.floor_strip(bad_candle, "Floor", 0.0, 600.0, "nave")
	l3.nest(bad_candle, "NestClose", 200.0, 320.0)
	l3.candle_bridge(bad_candle, "BridgeNearNest", Vector2(280, 288), 80.0, Vector2(220, 320))
	var candle_problems := LevelSanity.check(bad_candle)
	var found_candle := false
	for p in candle_problems:
		if p.contains("BridgeNearNest") and p.contains("40"):
			found_candle = true
	ok(found_candle, "Candle within 40px of an EmberNest is rejected: %s" % [candle_problems])
