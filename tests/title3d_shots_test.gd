extends TestCase
## Tests for scripts/title3d/title_shots.gd（镜头表纯数据 + 静态采样）与
## scripts/title3d/title_shot_player.gd（纯采样播放器 / 事件 / skip / attract）。

const Shots := preload("res://scripts/title3d/title_shots.gd")
const Player := preload("res://scripts/title3d/title_shot_player.gd")


func _almost_vec(got: Vector3, expected: Vector3, eps: float, label: String) -> void:
	ok(got.distance_to(expected) <= eps, "%s: expected %s got %s (eps %f)" % [label, expected, got, eps])


func _all_ids() -> PackedStringArray:
	return PackedStringArray(["intro", "idle", "attract", "confirm", "quit"])


# ------------------------------------------------------------------ 镜头表 ----

func test_ids_and_unknown_shot() -> void:
	var ids := Shots.ids()
	eq(ids.size(), 5, "five title shots")
	for expected in _all_ids():
		ok(ids.has(expected), "ids() contains %s" % expected)
	eq(Shots.shot(&"nope").size(), 0, "unknown shot id returns an empty dictionary")


func test_shot_required_fields() -> void:
	for id in _all_ids():
		var s: Dictionary = Shots.shot(StringName(id))
		ok(not s.is_empty(), "shot %s exists" % id)
		eq(StringName(s.get("id", &"")), StringName(id), "shot %s keeps its id" % id)
		ok(Shots.duration(s) > 0.0, "shot %s has a positive duration" % id)
		ok(s.get("events", null) is Array, "shot %s has an events array" % id)
		ok(s.get("loop", null) is bool, "shot %s declares loop" % id)
		if String(s.get("path", &"keys")) == "orbit":
			ok(s.get("orbit", null) is Dictionary, "orbit shot %s has orbit data" % id)
		else:
			var keys: Array = s.get("keys", [])
			ok(not keys.is_empty(), "shot %s has keys" % id)
			for key in keys:
				ok(key.get("pos", null) is Vector3, "shot %s key pos is Vector3" % id)
				ok(key.get("target", null) is Vector3, "shot %s key target is Vector3" % id)


func test_shot_data_is_not_shared_between_calls() -> void:
	var first: Dictionary = Shots.shot(&"confirm")
	(first["keys"] as Array).clear()
	var second: Dictionary = Shots.shot(&"confirm")
	eq((second["keys"] as Array).size(), 2, "each shot() call rebuilds its keys")


func test_camera_contract_constants() -> void:
	eq(Shots.OUTPUT_ROWS, 360, "output rows")
	eq(Shots.OUTPUT_COLUMNS, 640, "output columns")
	almost(Shots.VIEW_HEIGHT, 13.5, 1e-9, "focus plane view height")
	almost(Shots.FOV_DEG, 30.0, 1e-9, "camera fov")
	almost(Shots.world_per_texel(), 0.0375, 1e-9, "one texel is 0.0375 m on the focus plane")
	var expected_focus := (13.5 * 0.5) / tan(deg_to_rad(15.0))
	almost(Shots.focus_distance(), expected_focus, 1e-6,
			"hero distance frames view_height with fov 30")
	var layout := Shots.layout_script()
	if layout != null:
		eq(Shots.hero_target(), Shots.layout_value(&"CAMERA_TARGET", Vector3.ZERO),
				"hero target follows TitleLayout.CAMERA_TARGET")
		eq(Shots.hero_feet(), Shots.layout_value(&"KNIGHT_POS", Vector3.ZERO),
				"hero feet follow TitleLayout.KNIGHT_POS")


func test_hero_pose() -> void:
	var hero: Dictionary = Shots.hero_pose()
	_almost_vec(hero["target"], Shots.hero_target(), 1e-9, "hero looks at the layout camera target")
	almost((hero["pos"] as Vector3).distance_to(hero["target"]), Shots.focus_distance(), 1e-6,
			"hero camera sits at the focus distance")
	almost((hero["target"] as Vector3).z, 0.0, 1e-9, "hero target lies on the focus plane z = 0")
	almost(float(hero["fov"]), 30.0, 1e-9, "hero shot uses fov 30")
	eq(bool(hero["snap"]), true, "hero shot is snapped")
	# 3/4 机位：偏右偏上
	var offset: Vector3 = (hero["pos"] as Vector3) - (hero["target"] as Vector3)
	ok(offset.x > 0.5, "hero camera is right of the bridge centre (3/4 view)")
	ok(offset.y > 0.5, "hero camera looks slightly down")
	ok(offset.z > 0.0, "hero camera is on the +Z side of the focus plane")


# -------------------------------------------------------------- 时长 / 端点 ----

func test_shot_durations() -> void:
	almost(Shots.duration(Shots.shot(&"intro")), 2.8, 1e-9, "intro lasts 2.8 s (TitleScreen constants)")
	almost(Shots.duration(Shots.shot(&"confirm")), 0.55, 1e-9, "confirm lasts 0.55 s")
	almost(Shots.duration(Shots.shot(&"attract")), 20.0, 1e-9, "attract lasts 20 s")
	ok(Shots.duration(Shots.shot(&"idle")) > 0.0, "idle has a loop length")
	ok(Shots.loops(Shots.shot(&"idle")), "idle loops")
	ok(Shots.loops(Shots.shot(&"attract")), "attract loops")
	ok(not Shots.loops(Shots.shot(&"intro")), "intro does not loop")
	ok(not Shots.loops(Shots.shot(&"confirm")), "confirm does not loop")
	ok(not Shots.loops(Shots.shot(&"quit")), "quit does not loop")


func test_quit_duration_scales_with_lit_lanterns() -> void:
	almost(Shots.duration(Shots.shot(&"quit", &"give")), 14.0 * 0.2, 1e-9,
			"quit from all-lanterns-lit gives 14 x 0.2 s")
	almost(Shots.duration(Shots.shot(&"quit", &"keep")), 14.0 * 0.2, 1e-9,
			"keep ending also has every lantern lit")
	almost(Shots.duration(Shots.shot(&"quit", &"cold")), 0.2, 1e-9,
			"cold title has no lantern to douse, one beat remains")
	almost(Shots.duration(Shots.shot(&"quit", &"journey", 5)), 5.0 * 0.2, 1e-9,
			"journey quit scales with the lit count")
	almost(Shots.duration(Shots.shot(&"quit", &"journey")), 14.0 * 0.2, 1e-9,
			"unknown journey progress falls back to the full wave")


func test_intro_endpoints() -> void:
	var intro: Dictionary = Shots.shot(&"intro")
	var aerial: Dictionary = Shots.aerial_pose()
	var hero: Dictionary = Shots.hero_pose()
	var start: Dictionary = Shots.sample(intro, 0.0)
	_almost_vec(start["pos"], aerial["pos"], 1e-6, "intro starts at the skylight aerial pose")
	_almost_vec(start["target"], aerial["target"], 1e-6, "intro start looks down the light shaft")
	almost(float(start["fov"]), Shots.INTRO_AERIAL_FOV, 1e-9, "intro starts wide")
	eq(bool(start["snap"]), false, "the fast dive is not snapped")
	var landed: Dictionary = Shots.sample(intro, Shots.DOLLY_TIME)
	_almost_vec(landed["pos"], hero["pos"], 1e-6, "the dive lands on the hero pose at 1.6 s")
	_almost_vec(landed["target"], hero["target"], 1e-6, "the dive lands on the hero target")
	almost(float(landed["fov"]), 30.0, 1e-9, "the dive ends at fov 30")
	eq(bool(landed["snap"]), true, "the landed shot is snapped")
	var settled: Dictionary = Shots.sample(intro, Shots.INTRO_DURATION)
	_almost_vec(settled["pos"], hero["pos"], 1e-6, "intro ends exactly on the hero pose")
	almost(float(settled["fov"]), 30.0, 1e-9, "intro ends at fov 30")
	eq(bool(settled["snap"]), true, "intro end is snapped")
	var middle: Dictionary = Shots.sample(intro, 0.8)
	var between := (start["pos"] as Vector3).distance_to(hero["pos"])
	var travelled := (start["pos"] as Vector3).distance_to(middle["pos"])
	ok(travelled > 0.0 and travelled < between, "the dive interpolates between the two poses")


func test_confirm_push() -> void:
	var confirm: Dictionary = Shots.shot(&"confirm")
	var hero: Dictionary = Shots.hero_pose()
	var start: Dictionary = Shots.sample(confirm, 0.0)
	_almost_vec(start["pos"], hero["pos"], 1e-6, "confirm starts from the hero pose")
	var end: Dictionary = Shots.sample(confirm, Shots.duration(confirm))
	var target: Vector3 = hero["target"]
	var hero_pos: Vector3 = hero["pos"]
	var end_pos: Vector3 = end["pos"]
	almost(end_pos.distance_to(hero_pos), Shots.CONFIRM_PUSH_TEXELS * Shots.world_per_texel(), 1e-6,
			"confirm pushes 5 output texels toward the knight")
	almost((end_pos - hero_pos).normalized().dot((target - hero_pos).normalized()), 1.0, 1e-5,
			"confirm pushes along the view axis")
	almost(end_pos.distance_to(target), Shots.focus_distance() - 5.0 * Shots.world_per_texel(), 1e-6,
			"confirm ends 5 texel closer to the target")
	_almost_vec(end["target"], target, 1e-6, "confirm keeps the aim on the knight")
	eq(bool(end["snap"]), true, "confirm is snapped")


func test_quit_pullback() -> void:
	var quit: Dictionary = Shots.shot(&"quit", &"give")
	var hero: Dictionary = Shots.hero_pose()
	var start: Dictionary = Shots.sample(quit, 0.0)
	_almost_vec(start["pos"], hero["pos"], 1e-6, "quit starts from the hero pose")
	var end: Dictionary = Shots.sample(quit, Shots.duration(quit))
	var target: Vector3 = hero["target"]
	almost((end["pos"] as Vector3).distance_to(target),
			Shots.focus_distance() * (1.0 + Shots.QUIT_PULLBACK), 1e-5,
			"quit pulls the camera back 12 percent")
	_almost_vec(end["target"], target, 1e-6, "quit keeps looking at the knight's mark")
	eq(bool(end["snap"]), true, "quit is snapped")


# ------------------------------------------------------------------ 事件表 ----

func test_intro_event_catalog() -> void:
	var intro: Dictionary = Shots.shot(&"intro")
	var events: Array = intro["events"]
	eq(events.size(), 17, "intro fires 14 lanterns + hammer + logo + menu")
	var lantern_order: Array = []
	var hammer_at := -1.0
	var logo_at := -1.0
	var menu_at := -1.0
	var hammer_index := -1
	var logo_index := -1
	for i in events.size():
		var event: Dictionary = events[i]
		var kind := StringName(event["kind"])
		var at := float(event["at"])
		ok(at >= -1e-9 and at <= Shots.duration(intro) + 1e-9, "intro event inside the shot")
		if i > 0:
			ok(at >= float(events[i - 1]["at"]) - 1e-9, "intro events are sorted by time")
		match String(kind):
			"lantern_wave":
				var index := int(event["payload"].get("index", -1))
				lantern_order.append(index)
				almost(at, 0.30 + 0.16 * float(index), 1e-9,
						"lantern %d lights at 0.30 + 0.16 i" % index)
				eq(int(event["payload"].get("lanterns", 0)), Shots.LANTERN_COUNT,
						"lantern payload carries the total")
			"hammer_strike":
				hammer_at = at
				hammer_index = i
			"logo_forge":
				logo_at = at
				logo_index = i
			"menu_reveal":
				menu_at = at
	eq(lantern_order.size(), Shots.LANTERN_COUNT, "fourteen lantern waves")
	for i in Shots.LANTERN_COUNT:
		eq(int(lantern_order[i]), i, "lantern %d keeps its progress id" % i)
	almost(hammer_at, 1.60, 1e-9, "hammer strike at 1.60 s")
	almost(logo_at, 1.60, 1e-9, "logo forges at LOGO_AT 1.60 s")
	almost(menu_at, 1.95, 1e-9, "menu lands at MENU_AT 1.95 s")
	ok(hammer_index >= 0 and logo_index > hammer_index, "hammer strike fires before logo forging")
	almost(float(events[logo_index]["payload"].get("duration", 0.0)), 0.80, 1e-9,
			"logo forge payload carries LOGO_TIME")


func test_confirm_and_quit_events() -> void:
	var confirm: Dictionary = Shots.shot(&"confirm")
	eq((confirm["events"] as Array).size(), 2, "confirm fires flash + furnace surge")
	eq(StringName(confirm["events"][0]["kind"]), &"flash", "flash event")
	eq(StringName(confirm["events"][1]["kind"]), &"furnace_surge", "furnace surge event")
	almost(float(confirm["events"][0]["at"]), 0.0, 1e-9, "flash fires immediately")
	ok(float(confirm["events"][1]["at"]) <= Shots.duration(confirm), "furnace surge inside the shot")
	var quit: Dictionary = Shots.shot(&"quit", &"journey", 5)
	var events: Array = quit["events"]
	eq(events.size(), 6, "quit with 5 lit lanterns fires grade + 5 lantern outs")
	eq(StringName(events[0]["kind"]), &"grade_to_dark", "grade goes dark first")
	almost(float(events[0]["at"]), 0.0, 1e-9, "grade starts at 0 s")
	for i in 5:
		var event: Dictionary = events[i + 1]
		eq(StringName(event["kind"]), &"lantern_out", "lantern out %d" % i)
		almost(float(event["at"]), 0.2 * float(i), 1e-9, "lantern %d douses at i x 0.2 s" % i)
		eq(int(event["payload"].get("index", -1)), i, "lantern out payload index")
	almost(Shots.duration(quit), 1.0, 1e-9, "five lanterns -> 1.0 s quit")


func test_events_monotonic_and_in_range() -> void:
	for id in _all_ids():
		var s: Dictionary = Shots.shot(StringName(id))
		var events: Array = s["events"]
		var previous := -1.0
		for event in events:
			ok(event.get("kind", null) is StringName, "event kind is StringName")
			ok(event.get("payload", null) is Dictionary, "event payload is Dictionary")
			var at := float(event.get("at", -1.0))
			ok(at >= 0.0, "event time is not negative")
			ok(at <= Shots.duration(s) + 1e-9, "event inside the shot duration")
			ok(at >= previous - 1e-9, "events are sorted by time")
			previous = at


# -------------------------------------------------------------------- 采样 ----

func test_sample_clamps_out_of_range() -> void:
	var intro: Dictionary = Shots.shot(&"intro")
	var first: Dictionary = Shots.sample(intro, -10.0)
	_almost_vec(first["pos"], Shots.sample(intro, 0.0)["pos"], 1e-9, "t below zero clamps to the start")
	var last: Dictionary = Shots.sample(intro, 99.0)
	_almost_vec(last["pos"], Shots.sample(intro, 2.8)["pos"], 1e-9, "t above duration clamps to the end")


func test_sample_no_nan() -> void:
	for id in _all_ids():
		var s: Dictionary = Shots.shot(StringName(id), &"journey", 7)
		var dur := Shots.duration(s)
		for i in range(-4, 30):
			var t := dur * (float(i) / 23.0) + 0.13 * float(i)
			var sample: Dictionary = Shots.sample(s, t)
			var pos: Vector3 = sample["pos"]
			var target: Vector3 = sample["target"]
			ok(is_finite(pos.x) and is_finite(pos.y) and is_finite(pos.z),
					"%s sample pos finite at t=%f" % [id, t])
			ok(is_finite(target.x) and is_finite(target.y) and is_finite(target.z),
					"%s sample target finite at t=%f" % [id, t])
			ok(is_finite(float(sample["roll"])), "%s roll finite" % id)
			var fov := float(sample["fov"])
			ok(is_finite(fov) and fov > 1.0 and fov < 180.0, "%s fov sane at t=%f" % [id, t])
			ok(sample.get("snap", null) is bool, "%s snap is bool" % id)
			ok(sample.get("events", null) is Array, "%s sample carries the event table" % id)


func test_sample_events_are_the_shot_table() -> void:
	var intro: Dictionary = Shots.shot(&"intro")
	var sample: Dictionary = Shots.sample(intro, 1.0)
	eq((sample["events"] as Array).size(), (intro["events"] as Array).size(),
			"sample exposes the whole event table for inspection")


func test_pose_helper() -> void:
	var hero: Dictionary = Shots.sample(Shots.shot(&"idle"), 0.0)
	var transform: Transform3D = Shots.pose(hero)
	_almost_vec(transform.origin, hero["pos"], 1e-9, "pose keeps the sampled position")
	var forward := -transform.basis.z.normalized()
	var wanted: Vector3 = ((hero["target"] as Vector3) - (hero["pos"] as Vector3)).normalized()
	almost(forward.dot(wanted), 1.0, 1e-6, "pose -Z axis points at the target")
	ok(transform.basis.y.dot(Vector3.UP) > 0.99, "pose keeps the camera upright")


func test_attract_orbit() -> void:
	var attract: Dictionary = Shots.shot(&"attract")
	var hero: Dictionary = Shots.hero_pose()
	var duration := Shots.duration(attract)
	var start: Dictionary = Shots.sample(attract, 0.0)
	var end: Dictionary = Shots.sample(attract, duration)
	_almost_vec(start["pos"], hero["pos"], 1e-6, "attract starts on the hero pose")
	_almost_vec(end["pos"], hero["pos"], 1e-5, "attract loops back to the hero pose")
	_almost_vec(start["target"], hero["target"], 1e-6, "attract orbits the hero target")
	var centre: Vector3 = hero["target"]
	var yaw_base := 6.0
	for t in [0.0, 5.0, 10.0, 15.0, 20.0]:
		var sample: Dictionary = Shots.sample(attract, t)
		eq(bool(sample["snap"]), true, "attract is snapped")
		almost((sample["pos"] as Vector3).distance_to(centre), Shots.focus_distance(), 1e-5,
				"attract keeps the focus distance at t=%f" % t)
		var offset: Vector3 = (sample["pos"] as Vector3) - centre
		var azimuth := rad_to_deg(atan2(offset.x, offset.z))
		ok(absf(azimuth - yaw_base) <= Shots.ATTRACT_ORBIT_DEG + 1e-4,
				"attract yaw stays within +-6 deg at t=%f (got %.4f)" % [t, azimuth])
	# 正弦环绕在 1/4 与 3/4 周期取到两端
	var quarter: Dictionary = Shots.sample(attract, duration * 0.25)
	var three_quarter: Dictionary = Shots.sample(attract, duration * 0.75)
	var q_offset: Vector3 = (quarter["pos"] as Vector3) - centre
	var tq_offset: Vector3 = (three_quarter["pos"] as Vector3) - centre
	almost(rad_to_deg(atan2(q_offset.x, q_offset.z)), yaw_base + 6.0, 1e-3,
			"attract reaches +6 deg at a quarter period")
	almost(rad_to_deg(atan2(tq_offset.x, tq_offset.z)), yaw_base - 6.0, 1e-3,
			"attract reaches -6 deg at three quarters")


func test_events_until_and_between() -> void:
	var intro: Dictionary = Shots.shot(&"intro")
	eq(Shots.events_until(intro, 1.0).size(), 5, "five lanterns lit by 1.0 s")
	eq(Shots.events_until(intro, -1.0).size(), 0, "nothing due before the shot")
	eq(Shots.events_until(intro, 1.6).size(), 11, "nine lanterns + hammer + logo due at 1.6 s")
	eq(Shots.events_between(intro, 0.5, 1.0).size(), 3, "three lantern events in (0.5, 1.0]")
	eq(Shots.events_between(intro, 2.0, 2.8).size(), 3, "three lantern events in (2.0, 2.8]")


# -------------------------------------------------------------------- 播放器 ---

func _new_player(kinds: Array, payloads: Array, finished: Array) -> Node:
	var player = Player.new()
	player.event_fired.connect(func(kind: StringName, payload: Dictionary) -> void:
		kinds.append(String(kind))
		payloads.append(payload))
	player.finished.connect(func() -> void:
		finished[0] = int(finished[0]) + 1)
	return player


func test_player_fires_each_event_once_in_order() -> void:
	var kinds: Array = []
	var payloads: Array = []
	var finished: Array = [0]
	var player = _new_player(kinds, payloads, finished)
	player.play(&"intro")
	for i in 240:
		player.advance(1.0 / 60.0)
	var expected: Array = Shots.shot(&"intro")["events"]
	eq(kinds.size(), expected.size(), "every intro event fired exactly once")
	for i in expected.size():
		eq(kinds[i], String(expected[i]["kind"]), "event %d order matches the table" % i)
	eq(finished[0], 1, "intro emits finished once")
	player.free()


func test_player_big_step_fires_everything_once() -> void:
	var kinds: Array = []
	var payloads: Array = []
	var finished: Array = [0]
	var player = _new_player(kinds, payloads, finished)
	player.play(&"intro")
	player.advance(10.0)
	var expected: Array = Shots.shot(&"intro")["events"]
	eq(kinds.size(), expected.size(), "a 10 s step still fires every event exactly once")
	for i in expected.size():
		eq(kinds[i], String(expected[i]["kind"]), "big-step event %d order matches" % i)
	eq(finished[0], 1, "big step emits finished once")
	player.free()


func test_player_event_payloads() -> void:
	var kinds: Array = []
	var payloads: Array = []
	var finished: Array = [0]
	var player = _new_player(kinds, payloads, finished)
	player.play(&"confirm")
	player.advance(1.0)
	eq(kinds.size(), 2, "confirm fires two events")
	var flash_index := kinds.find("flash")
	ok(flash_index >= 0, "flash fired")
	eq(StringName(payloads[flash_index].get("source", &"")), &"confirm", "flash payload source")
	player.free()


func test_player_skip_fires_remaining_terminal_events() -> void:
	var kinds: Array = []
	var payloads: Array = []
	var finished: Array = [0]
	var player = _new_player(kinds, payloads, finished)
	player.play(&"intro")
	player.advance(1.0)
	var early := kinds.size()
	ok(early > 0 and early < 17, "some but not all intro events fired before skip")
	player.skip()
	var expected: Array = Shots.shot(&"intro")["events"]
	eq(kinds.size(), expected.size(), "skip补发所有终态事件，一次也不重复")
	for i in expected.size():
		eq(kinds[i], String(expected[i]["kind"]), "skipped event %d keeps table order" % i)
	eq(finished[0], 1, "skip emits finished once")
	var sample: Dictionary = player.sample_now()
	eq(StringName(sample["id"]), &"idle", "skipping the intro lands on idle")
	_almost_vec(sample["pos"], Shots.hero_pose()["pos"], 1e-5, "skip lands on the hero pose")
	almost(float(player.progress()), 0.0, 1e-9, "auto idle restarts its own progress")
	player.free()


func test_player_skip_is_idempotent_for_the_same_shot() -> void:
	var kinds: Array = []
	var payloads: Array = []
	var finished: Array = [0]
	var player = _new_player(kinds, payloads, finished)
	player.play(&"confirm")
	player.advance(0.1)
	player.skip()
	var after_first := kinds.size()
	player.skip()
	eq(kinds.size(), after_first, "skipping a finished shot cannot fire events twice")
	eq(finished[0], 1, "finished is emitted once for the same shot")
	player.free()


func test_player_attract_trigger_and_interrupt() -> void:
	var kinds: Array = []
	var payloads: Array = []
	var finished: Array = [0]
	var player = _new_player(kinds, payloads, finished)
	eq(player.current_id(), &"", "no shot before play")
	player.play(&"idle")
	eq(player.current_id(), &"idle", "idle starts")
	player.advance(24.0)
	eq(player.current_id(), &"idle", "still idle before 25 s")
	player.advance(1.5)
	eq(player.current_id(), &"attract", "25 s of no input starts the attract orbit")
	var sample: Dictionary = player.sample_now()
	eq(bool(sample["loop"]), true, "attract loops")
	eq(bool(sample["snap"]), true, "attract is snapped")
	player.notify_input()
	eq(player.current_id(), &"idle", "any input interrupts attract back to idle")
	almost(player.idle_clock(), 0.0, 1e-9, "input resets the idle clock")
	player.advance(10.0)
	eq(player.current_id(), &"idle", "idle stays after the interruption")
	player.play(&"attract")
	player.advance(20.5)
	eq(player.current_id(), &"attract", "attract keeps looping")
	almost(player.time(), 0.5, 1e-3, "attract wraps its clock")
	player.free()


func test_player_auto_idle_after_intro() -> void:
	var kinds: Array = []
	var payloads: Array = []
	var finished: Array = [0]
	var player = _new_player(kinds, payloads, finished)
	player.play(&"intro")
	player.advance(2.9)
	eq(finished[0], 1, "intro finished")
	eq(player.current_id(), &"idle", "intro hands over to idle automatically")
	almost(player.idle_clock(), 0.0, 1e-9, "the idle clock starts after the intro")
	player.advance(25.5)
	eq(player.current_id(), &"attract", "the idle clock still reaches attract")
	player.free()


func test_player_auto_idle_can_be_disabled() -> void:
	var kinds: Array = []
	var payloads: Array = []
	var finished: Array = [0]
	var player = _new_player(kinds, payloads, finished)
	player.auto_idle_after_intro = false
	player.play(&"intro")
	player.advance(3.0)
	eq(finished[0], 1, "intro finished")
	eq(player.current_id(), &"intro", "no automatic idle when disabled")
	eq(player.playing(), false, "the finished shot stops playing")
	player.free()


func test_player_unknown_shot_is_ignored() -> void:
	var kinds: Array = []
	var payloads: Array = []
	var finished: Array = [0]
	var player = _new_player(kinds, payloads, finished)
	player.play(&"idle")
	player.play(&"nope")
	eq(player.current_id(), &"idle", "an unknown shot does not replace the current one")
	player.free()


func test_player_sample_now_contract() -> void:
	var kinds: Array = []
	var payloads: Array = []
	var finished: Array = [0]
	var player = _new_player(kinds, payloads, finished)
	player.play(&"confirm")
	player.advance(0.11)
	var sample: Dictionary = player.sample_now()
	for key in ["pos", "target", "roll", "fov", "snap", "events", "id", "time", "duration",
			"progress", "finished", "loop"]:
		ok(sample.has(key), "sample_now exposes %s" % key)
	eq(StringName(sample["id"]), &"confirm", "sample_now reports the shot id")
	almost(float(sample["duration"]), 0.55, 1e-9, "sample_now reports the duration")
	almost(float(sample["progress"]), 0.11 / 0.55, 1e-4, "sample_now reports the progress")
	eq(bool(sample["snap"]), true, "confirm is snapped")
	var raw: Dictionary = Shots.sample(player.shot_data(), player.time())
	_almost_vec(sample["pos"], raw["pos"], 1e-9, "sample_now is the pure sample at the clock")
	_almost_vec(sample["target"], raw["target"], 1e-9, "sample_now target matches the pure sample")
	player.free()


func test_player_is_deterministic() -> void:
	var a = Player.new()
	var b = Player.new()
	a.play(&"intro")
	b.play(&"intro")
	for i in 60:
		a.advance(1.0 / 30.0)
		b.advance(1.0 / 30.0)
		if i % 7 == 0:
			var sa: Dictionary = a.sample_now()
			var sb: Dictionary = b.sample_now()
			_almost_vec(sa["pos"], sb["pos"], 1e-12, "deterministic camera position")
			_almost_vec(sa["target"], sb["target"], 1e-12, "deterministic camera target")
			almost(float(sa["fov"]), float(sb["fov"]), 1e-12, "deterministic fov")
			eq(bool(sa["snap"]), bool(sb["snap"]), "deterministic snap flag")
	a.free()
	b.free()
