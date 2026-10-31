extends StageRoomBuilder
## 支线裂·壹 · 废冢尸堆（2 房：B1 四十八具空壳伏击 -> B2 真名残片·壹）


func _init() -> void:
	configure_stage(
		"branch01",
		"graveyard",
		"ash",
		{"time": 0.78, "weather": "fog", "hold": 240.0},
		{"allowed": [2], "intensity": Vector2(0.6, 0.9), "hold": 180.0}
	)


func room_ids() -> Array[String]:
	return ["B1", "B2"]


func default_room() -> String:
	return "B1"


func spawn_for_room(p_room_id: String, spawn_tag: String) -> Vector2:
	if p_room_id == "B1" and spawn_tag == "east":
		return Vector2(748.0, FLOOR_Y)
	return Vector2(88.0, FLOOR_Y)


func on_room_entered(_host: Node2D, p_room_id: String) -> void:
	match p_room_id:
		"B1":
			GameEvents.voice_triggered.emit("b1_r1_enter", false)
		"B2":
			GameEvents.voice_triggered.emit("b1_r2_terminal", false)


func build_room(host: Node2D, p_room_id: String) -> void:
	match p_room_id:
		"B1":
			_build_b1(host)
		"B2":
			_build_b2(host)


func _build_b1(host: Node2D) -> void:
	room_box(host, 832, true, "ground", -32.0)
	var back_gate := arch_gate(host, "ReturnStage01", Vector2(56.0, FLOOR_Y), "返回腐液墓园",
			"S1", "branch", "stage01")
	var ge := touch_gate_east(host, "B2", "west")

	step(host, "ShellHeapWest", Vector2(248.0, FLOOR_Y - 28.0), 96.0, "ground")
	step(host, "ShellHeapEast", Vector2(504.0, FLOOR_Y - 28.0), 96.0, "ground")
	for bx in [188.0, 380.0, 444.0, 628.0, 704.0]:
		prop(host, "bones", Vector2(bx, FLOOR_Y))
	prop(host, "broken_machine", Vector2(416.0, FLOOR_Y))

	var waves := [
		[
			{"kind": "skeleton", "pos": Vector2(360.0, FLOOR_Y)},
			{"kind": "skeleton", "pos": Vector2(580.0, FLOOR_Y)},
		],
		[
			{"kind": "scrapper", "pos": Vector2(296.0, FLOOR_Y - 28.0)},
			{"kind": "spitter", "pos": Vector2(552.0, FLOOR_Y - 28.0)},
			{"kind": "skeleton", "pos": Vector2(660.0, FLOOR_Y)},
		],
	]
	wave_arena(host, "CorpsePitArena", "B1", 96.0, 768.0, waves,
			"b1_r1_wave", "b1_r1_clear", {}, [back_gate, ge], [])


func _build_b2(host: Node2D) -> void:
	room_box(host, 672, true, "ground", -32.0)
	touch_gate_west(host, "B1", "east")
	for bx in [196.0, 272.0, 348.0]:
		prop(host, "bones", Vector2(bx, FLOOR_Y))
	prop(host, "skull_arch", Vector2(456.0, FLOOR_Y))
	truth_terminal(host, "TruthFragment1", Vector2(456.0, FLOOR_Y), "truth_1", "branch01")
	arch_gate(host, "ExitToStage01", Vector2(576.0, FLOOR_Y), "返回墓园起点",
			"S1", "branch", "stage01")
