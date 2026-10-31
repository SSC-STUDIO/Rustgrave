extends StageRoomBuilder
## 支线裂·叁 · 司书暗阁（3 房：B1 穹顶书廊 -> B2 暗阁禁卫封锁战 -> B3 原声母盘+真名残片·叁）


func _init() -> void:
	configure_stage("branch03", "cathedral", "dust")


func room_ids() -> Array[String]:
	return ["B1", "B2", "B3"]


func default_room() -> String:
	return "B1"


func spawn_for_room(p_room_id: String, spawn_tag: String) -> Vector2:
	match p_room_id:
		"B1":
			return Vector2(656.0, FLOOR_Y) if spawn_tag == "east" else Vector2(88.0, FLOOR_Y)
		"B2":
			return Vector2(780.0, FLOOR_Y) if spawn_tag == "east" else Vector2(84.0, FLOOR_Y)
		"B3":
			return Vector2(88.0, FLOOR_Y)
	return Vector2(88.0, FLOOR_Y)


func on_room_entered(_host: Node2D, p_room_id: String) -> void:
	match p_room_id:
		"B1":
			GameEvents.voice_triggered.emit("b3_r1_enter", false)
		"B3":
			GameEvents.voice_triggered.emit("b3_r3_terminal", false)


func build_room(host: Node2D, p_room_id: String) -> void:
	match p_room_id:
		"B1":
			_build_b1(host)
		"B2":
			_build_b2(host)
		"B3":
			_build_b3(host)


func _build_b1(host: Node2D) -> void:
	room_box(host, 736, true, "stone", -48.0)
	arch_gate(host, "BackToNave", Vector2(64.0, FLOOR_Y), "返回圣殿中庭",
			"S3", "loft", "stage03")
	prop(host, "column", Vector2(256.0, FLOOR_Y))
	prop(host, "window", Vector2(464.0, FLOOR_Y))
	torch(host, 360.0, FLOOR_Y)
	touch_gate_east(host, "B2", "west")


func _build_b2(host: Node2D) -> void:
	room_box(host, 864, true, "stone", -48.0)
	var gw := touch_gate_west(host, "B1", "east")
	var ge := touch_gate_east(host, "B3", "west")
	step(host, "ArchiveShelfW", Vector2(224.0, FLOOR_Y - 28.0), 96.0, "stone")
	step(host, "ArchiveShelfE", Vector2(544.0, FLOOR_Y - 28.0), 96.0, "stone")
	prop(host, "skull_column", Vector2(432.0, FLOOR_Y))
	torch(host, 280.0, FLOOR_Y)
	torch(host, 584.0, FLOOR_Y)

	var waves := [
		[
			{"kind": "gear_shield", "pos": Vector2(360.0, FLOOR_Y)},
			{"kind": "ghost", "pos": Vector2(580.0, FLOOR_Y - 56.0)},
		],
		[
			{"kind": "gear_shield", "pos": Vector2(300.0, FLOOR_Y)},
			{"kind": "spitter", "pos": Vector2(592.0, FLOOR_Y - 28.0)},
			{"kind": "ghost", "pos": Vector2(456.0, FLOOR_Y - 64.0)},
		],
	]
	wave_arena(host, "ArchiveGuardArena", "B2", 64.0, 800.0, waves,
			"b3_r2_wave_start", "b3_r2_clear", {}, [gw, ge], [])


func _build_b3(host: Node2D) -> void:
	room_box(host, 672, true, "stone", -48.0)
	touch_gate_west(host, "B2", "east")
	prop(host, "altar", Vector2(320.0, FLOOR_Y))
	torch(host, 224.0, FLOOR_Y)
	truth_terminal(host, "TruthFragment3", Vector2(448.0, FLOOR_Y), "truth_3", "branch03")
	arch_gate(host, "ExitToCathedral", Vector2(576.0, FLOOR_Y), "返回圣殿地窖",
			"S4", "west", "stage03")
