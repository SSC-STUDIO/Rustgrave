extends StageRoomBuilder
## 支线裂·贰 · 灰铁弃槽（3 房：B1 未涂装灰铁底槽 -> B2 三波清道夫围剿 -> B3 真名残片·贰）


func _init() -> void:
	configure_stage("branch02", "industrial", "spark")


func room_ids() -> Array[String]:
	return ["B1", "B2", "B3"]


func default_room() -> String:
	return "B1"


func spawn_for_room(p_room_id: String, spawn_tag: String) -> Vector2:
	match p_room_id:
		"B1":
			if spawn_tag == "top":
				return Vector2(220.0, FLOOR_Y - 64.0)
			if spawn_tag == "east":
				return Vector2(668.0, FLOOR_Y)
			return Vector2(96.0, FLOOR_Y)
		"B2":
			return Vector2(812.0, FLOOR_Y) if spawn_tag == "east" else Vector2(84.0, FLOOR_Y)
		"B3":
			return Vector2(88.0, FLOOR_Y)
	return Vector2(96.0, FLOOR_Y)


func on_room_entered(_host: Node2D, p_room_id: String) -> void:
	match p_room_id:
		"B1":
			GameEvents.voice_triggered.emit("b2_r1_enter", false)
		"B3":
			GameEvents.voice_triggered.emit("b2_r3_terminal", false)


func build_room(host: Node2D, p_room_id: String) -> void:
	match p_room_id:
		"B1":
			_build_b1(host)
		"B2":
			_build_b2(host)
		"B3":
			_build_b3(host)


func _build_b1(host: Node2D) -> void:
	room_box(host, 768, true, "iron", -48.0)
	arch_gate(host, "BackToConduit", Vector2(72.0, FLOOR_Y), "爬回排渣桥",
			"S4", "west", "stage02")
	prop(host, "girder_l", Vector2(260.0, FLOOR_Y))
	prop(host, "broken_machine", Vector2(440.0, FLOOR_Y))
	prop(host, "warning_plate", Vector2(580.0, FLOOR_Y))
	destructible(host, "ScrapCrateA", &"crate", Vector2(520.0, FLOOR_Y))
	touch_gate_east(host, "B2", "west")


func _build_b2(host: Node2D) -> void:
	room_box(host, 896, true, "iron", -32.0)
	var gw := touch_gate_west(host, "B1", "east")
	var ge := touch_gate_east(host, "B3", "west")
	step(host, "TroughLedgeW", Vector2(224.0, FLOOR_Y - 28.0), 96.0, "iron_float")
	step(host, "TroughLedgeE", Vector2(576.0, FLOOR_Y - 28.0), 96.0, "iron_float")
	prop(host, "beam_bolts", Vector2(448.0, FLOOR_Y))
	prop(host, "fire_vent", Vector2(320.0, FLOOR_Y))
	prop(host, "fire_vent", Vector2(580.0, FLOOR_Y))

	var waves := [
		[
			{"kind": "scrapper", "pos": Vector2(340.0, FLOOR_Y)},
			{"kind": "scrapper", "pos": Vector2(580.0, FLOOR_Y)},
		],
		[
			{"kind": "gear_shield", "pos": Vector2(320.0, FLOOR_Y)},
			{"kind": "spitter", "pos": Vector2(624.0, FLOOR_Y - 28.0)},
		],
		[
			{"kind": "scrapper", "pos": Vector2(260.0, FLOOR_Y - 28.0)},
			{"kind": "gear_shield", "pos": Vector2(480.0, FLOOR_Y)},
			{"kind": "flying_demon", "pos": Vector2(640.0, FLOOR_Y - 72.0)},
		],
	]
	wave_arena(host, "ScavengerLockdown", "B2", 64.0, 832.0, waves,
			"b2_r2_ambush", "b2_r2_clear", {2: "b2_r2_wave_2"}, [gw, ge], [])


func _build_b3(host: Node2D) -> void:
	room_box(host, 672, true, "iron", -32.0)
	touch_gate_west(host, "B2", "east")
	prop(host, "metal_panel", Vector2(240.0, FLOOR_Y))
	prop(host, "broken_machine", Vector2(360.0, FLOOR_Y))
	truth_terminal(host, "TruthFragment2", Vector2(464.0, FLOOR_Y), "truth_2", "branch02")
	arch_gate(host, "ExitToConduit", Vector2(576.0, FLOOR_Y), "返回沉钟水渠",
			"S5", "west", "stage02")
