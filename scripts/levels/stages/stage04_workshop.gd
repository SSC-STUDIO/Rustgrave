extends StageRoomBuilder
## 节点肆 · 切槽工坊（3 房：S1 切槽铁台+驻足拆穿 -> S2 淬火三波连战 -> S3 运渣雨廊出口）


func _init() -> void:
	configure_stage("stage04", "industrial", "spark")


func room_ids() -> Array[String]:
	return ["S1", "S2", "S3"]


func default_room() -> String:
	return "S1"


func spawn_for_room(p_room_id: String, spawn_tag: String) -> Vector2:
	match p_room_id:
		"S1":
			return Vector2(680.0, FLOOR_Y) if spawn_tag == "east" else Vector2(88.0, FLOOR_Y)
		"S2":
			return Vector2(836.0, FLOOR_Y) if spawn_tag == "east" else Vector2(84.0, FLOOR_Y)
		"S3":
			return Vector2(88.0, FLOOR_Y)
	return Vector2(88.0, FLOOR_Y)


func on_room_entered(_host: Node2D, p_room_id: String) -> void:
	match p_room_id:
		"S1":
			GameEvents.voice_triggered.emit("s4_r1_enter", false)
		"S3":
			GameEvents.voice_triggered.emit("s4_r3_exit", false)


func build_room(host: Node2D, p_room_id: String) -> void:
	match p_room_id:
		"S1":
			_build_s1(host)
		"S2":
			_build_s2(host)
		"S3":
			_build_s3(host)


func _build_s1(host: Node2D) -> void:
	room_box(host, 768, true, "iron", -48.0)
	nest(host, "WorkshopNest", 176.0, FLOOR_Y)
	step(host, "SlottingBench", Vector2(368.0, FLOOR_Y - 24.0), 112.0, "iron_float")
	reward(host, "BenchRelic", Vector2(424.0, FLOOR_Y - 24.0) - Vector2(0.0, 7.0),
			"equipment", "bone_amulet", EquipmentCatalog.bone_amulet().display_name)
	prop(host, "broken_machine", Vector2(304.0, FLOOR_Y))
	prop(host, "pipe_valve", Vector2(544.0, FLOOR_Y))
	torch(host, 240.0, FLOOR_Y)
	torch(host, 608.0, FLOOR_Y)

	disobedience_linger(host, "BenchLinger", "", PackedStringArray(["s4_r1_linger"]), 5.5)
	guide_arrow(host, "ArrowQuench", Vector2(680.0, FLOOR_Y - 56.0), GuideArrow.Dir.RIGHT, "淬火线", true)
	touch_gate_east(host, "S2", "west")


func _build_s2(host: Node2D) -> void:
	room_box(host, 928, true, "iron", -48.0)
	var gw := touch_gate_west(host, "S1", "east")
	var ge := touch_gate_east(host, "S3", "west")
	step(host, "GantryWest", Vector2(224.0, FLOOR_Y - 28.0), 96.0, "iron_float")
	step(host, "GantryEast", Vector2(608.0, FLOOR_Y - 28.0), 96.0, "iron_float")
	prop(host, "beam_bolts", Vector2(464.0, FLOOR_Y))
	prop(host, "fire_vent", Vector2(352.0, FLOOR_Y))
	prop(host, "fire_vent", Vector2(576.0, FLOOR_Y))
	torch(host, 464.0, FLOOR_Y)

	var arr := guide_arrow(host, "ArrowOut", Vector2(840.0, FLOOR_Y - 56.0), GuideArrow.Dir.RIGHT, "出车间", false)
	var waves := [
		[
			{"kind": "scrapper", "pos": Vector2(340.0, FLOOR_Y)},
			{"kind": "gear_shield", "pos": Vector2(580.0, FLOOR_Y)},
		],
		[
			{"kind": "spitter", "pos": Vector2(272.0, FLOOR_Y - 28.0)},
			{"kind": "scrapper", "pos": Vector2(480.0, FLOOR_Y)},
			{"kind": "spitter", "pos": Vector2(656.0, FLOOR_Y - 28.0)},
		],
		[
			{"kind": "gear_shield", "pos": Vector2(360.0, FLOOR_Y)},
			{"kind": "gear_shield", "pos": Vector2(560.0, FLOOR_Y)},
			{"kind": "flying_demon", "pos": Vector2(464.0, FLOOR_Y - 76.0)},
		],
	]
	wave_arena(host, "QuenchLineArena", "S2", 64.0, 864.0, waves,
			"s4_r2_wave_start", "s4_r2_clear", {2: "s4_r2_wave_2"}, [gw, ge], [arr])


func _build_s3(host: Node2D) -> void:
	room_box(host, 672, true, "iron", -48.0)
	touch_gate_west(host, "S2", "east")
	prop(host, "girder_r", Vector2(256.0, FLOOR_Y))
	prop(host, "fence", Vector2(384.0, FLOOR_Y))
	destructible(host, "ExitCrate", &"crate", Vector2(448.0, FLOOR_Y))
	guide_arrow(host, "ArrowRain", Vector2(500.0, FLOOR_Y - 56.0), GuideArrow.Dir.RIGHT, "夜雨锻冢", true)
	arch_gate(host, "ToStage04bGate", Vector2(576.0, FLOOR_Y), "夜雨锻冢",
			"S1", "west", "stage04b", "stage04b", "stage04")
