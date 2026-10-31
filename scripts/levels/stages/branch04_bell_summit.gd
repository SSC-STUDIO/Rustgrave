extends StageRoomBuilder
## 支线裂·肆 · 无舌钟顶（3 房：B1 风道铁链廊 -> B2 护钟铁卫封锁战 -> B3 无舌真钟+真名残片·肆）


func _init() -> void:
	configure_stage("branch04", "belltower", "ash")


func room_ids() -> Array[String]:
	return ["B1", "B2", "B3"]


func default_room() -> String:
	return "B1"


func spawn_for_room(p_room_id: String, spawn_tag: String) -> Vector2:
	match p_room_id:
		"B1":
			return Vector2(672.0, FLOOR_Y) if spawn_tag == "east" else Vector2(88.0, FLOOR_Y)
		"B2":
			return Vector2(784.0, FLOOR_Y) if spawn_tag == "east" else Vector2(84.0, FLOOR_Y)
		"B3":
			return Vector2(88.0, FLOOR_Y)
	return Vector2(88.0, FLOOR_Y)


func on_room_entered(_host: Node2D, p_room_id: String) -> void:
	match p_room_id:
		"B1":
			GameEvents.voice_triggered.emit("b4_r1_enter", false)
		"B3":
			GameEvents.voice_triggered.emit("b4_r3_terminal", false)


func build_room(host: Node2D, p_room_id: String) -> void:
	match p_room_id:
		"B1":
			_build_b1(host)
		"B2":
			_build_b2(host)
		"B3":
			_build_b3(host)


func _build_b1(host: Node2D) -> void:
	room_box(host, 768, true, "stone", -48.0)
	arch_gate(host, "BackToShaft", Vector2(64.0, FLOOR_Y), "降回钟井",
			"S2", "top", "stage05")
	step(host, "ChainBridge", Vector2(320.0, FLOOR_Y - 28.0), 128.0, "stone")
	hanging(host, "chain", Vector2(280.0, -16.0))
	hanging(host, "chain", Vector2(488.0, -16.0))
	prop(host, "window", Vector2(384.0, FLOOR_Y))
	touch_gate_east(host, "B2", "west")


func _build_b2(host: Node2D) -> void:
	room_box(host, 864, true, "stone", -48.0)
	var gw := touch_gate_west(host, "B1", "east")
	var ge := touch_gate_east(host, "B3", "west")
	step(host, "BelfryLedgeW", Vector2(224.0, FLOOR_Y - 28.0), 96.0, "stone")
	step(host, "BelfryLedgeE", Vector2(544.0, FLOOR_Y - 28.0), 96.0, "stone")
	prop(host, "gargoyle", Vector2(432.0, FLOOR_Y))

	var waves := [
		[
			{"kind": "gear_shield", "pos": Vector2(340.0, FLOOR_Y)},
			{"kind": "flying_demon", "pos": Vector2(560.0, FLOOR_Y - 72.0)},
		],
		[
			{"kind": "gear_shield", "pos": Vector2(300.0, FLOOR_Y)},
			{"kind": "gear_shield", "pos": Vector2(560.0, FLOOR_Y)},
			{"kind": "fire_skull", "pos": Vector2(432.0, FLOOR_Y - 68.0)},
		],
	]
	wave_arena(host, "SummitGuardArena", "B2", 64.0, 800.0, waves,
			"b4_r2_wave_start", "b4_r2_clear", {}, [gw, ge], [])


func _build_b3(host: Node2D) -> void:
	room_box(host, 672, true, "stone", -48.0)
	touch_gate_west(host, "B2", "east")
	hanging(host, "chain", Vector2(352.0, -16.0))
	hanging(host, "chain", Vector2(448.0, -16.0))
	prop(host, "altar", Vector2(352.0, FLOOR_Y))
	truth_terminal(host, "TruthFragment4", Vector2(448.0, FLOOR_Y), "truth_4", "branch04")
	arch_gate(host, "ExitToFoundry", Vector2(576.0, FLOOR_Y), "返回铸钟长廊",
			"S3", "west", "stage05")
