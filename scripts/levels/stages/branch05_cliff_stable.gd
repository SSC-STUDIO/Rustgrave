extends StageRoomBuilder
## 支线裂·伍 · 绝壁古厩（2 房：B1 崖底清道夫拦截战 -> B2 梦魇旧鞍+真名残片·伍）


func _init() -> void:
	configure_stage("branch05", "ramparts", "ember")


func room_ids() -> Array[String]:
	return ["B1", "B2"]


func default_room() -> String:
	return "B1"


func spawn_for_room(p_room_id: String, spawn_tag: String) -> Vector2:
	if p_room_id == "B1":
		if spawn_tag == "top":
			return Vector2(200.0, FLOOR_Y - 64.0)
		if spawn_tag == "east":
			return Vector2(780.0, FLOOR_Y)
	return Vector2(88.0, FLOOR_Y)


func on_room_entered(_host: Node2D, p_room_id: String) -> void:
	match p_room_id:
		"B1":
			GameEvents.voice_triggered.emit("b5_r1_enter", false)
		"B2":
			GameEvents.voice_triggered.emit("b5_r2_terminal", false)


func build_room(host: Node2D, p_room_id: String) -> void:
	match p_room_id:
		"B1":
			_build_b1(host)
		"B2":
			_build_b2(host)


func _build_b1(host: Node2D) -> void:
	room_box(host, 864, true, "rampart", -48.0)
	var back_gate := arch_gate(host, "BackToCliff", Vector2(64.0, FLOOR_Y), "攀回断崖",
			"S4", "west", "stage06")
	var ge := touch_gate_east(host, "B2", "west")

	step(host, "UnderpassW", Vector2(256.0, FLOOR_Y - 28.0), 96.0, "rampart")
	step(host, "UnderpassE", Vector2(544.0, FLOOR_Y - 28.0), 96.0, "rampart")
	prop(host, "rock_pile", Vector2(416.0, FLOOR_Y))
	prop(host, "chain", Vector2(672.0, FLOOR_Y))

	var waves := [
		[
			{"kind": "scrapper", "pos": Vector2(360.0, FLOOR_Y)},
			{"kind": "gear_shield", "pos": Vector2(580.0, FLOOR_Y)},
		],
		[
			{"kind": "spitter", "pos": Vector2(300.0, FLOOR_Y - 28.0)},
			{"kind": "gear_shield", "pos": Vector2(500.0, FLOOR_Y)},
			{"kind": "fire_skull", "pos": Vector2(620.0, FLOOR_Y - 68.0)},
		],
	]
	wave_arena(host, "CliffScavengerArena", "B1", 112.0, 800.0, waves,
			"", "b5_r1_clear", {}, [back_gate, ge], [])


func _build_b2(host: Node2D) -> void:
	room_box(host, 672, true, "rampart", -48.0)
	touch_gate_west(host, "B1", "east")
	prop(host, "door_arch_wall", Vector2(280.0, FLOOR_Y))
	prop(host, "life_remains", Vector2(368.0, FLOOR_Y))
	hanging(host, "chain", Vector2(448.0, -16.0))
	truth_terminal(host, "TruthFragment5", Vector2(448.0, FLOOR_Y), "truth_5", "branch05")
	arch_gate(host, "ExitToRamparts", Vector2(576.0, FLOOR_Y), "返回城墙断崖",
			"S4", "west", "stage06")
