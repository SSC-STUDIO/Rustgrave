extends StageRoomBuilder
## 节点伍 · 夜雨锻冢（3 房：S1 哈伦与薇尔空葬墓阶 -> S2 冷雨三波群骸围攻 -> S3 断剑门闩进钟楼）


func _init() -> void:
	configure_stage(
		"stage04b",
		"graveyard",
		"rain",
		{"time": 0.80, "weather": "rain", "hold": 300.0},
		{"allowed": [4, 2], "intensity": Vector2(0.75, 1.0), "hold": 240.0}
	)


func room_ids() -> Array[String]:
	return ["S1", "S2", "S3"]


func default_room() -> String:
	return "S1"


func spawn_for_room(p_room_id: String, spawn_tag: String) -> Vector2:
	match p_room_id:
		"S1":
			return Vector2(680.0, FLOOR_Y) if spawn_tag == "east" else Vector2(88.0, FLOOR_Y)
		"S2":
			return Vector2(844.0, FLOOR_Y) if spawn_tag == "east" else Vector2(84.0, FLOOR_Y)
		"S3":
			return Vector2(88.0, FLOOR_Y)
	return Vector2(88.0, FLOOR_Y)


func on_room_entered(_host: Node2D, p_room_id: String) -> void:
	match p_room_id:
		"S1":
			GameEvents.voice_triggered.emit("s4b_r1_enter", false)
		"S3":
			GameEvents.voice_triggered.emit("s4b_r3_exit", false)


func build_room(host: Node2D, p_room_id: String) -> void:
	match p_room_id:
		"S1":
			_build_s1(host)
		"S2":
			_build_s2(host)
		"S3":
			_build_s3(host)


func _build_s1(host: Node2D) -> void:
	room_box(host, 768, false)
	nest(host, "RainGraveNest", 180.0, FLOOR_Y)
	prop(host, "grave_cross", Vector2(332.0, FLOOR_Y))
	prop(host, "grave_cross", Vector2(396.0, FLOOR_Y))
	prop(host, "statue", Vector2(496.0, FLOOR_Y))
	foliage(host, "tree_2_px", Vector2(600.0, FLOOR_Y), 1.0, true, Color(0.68, 0.75, 0.82))
	guide_arrow(host, "ArrowRainEast", Vector2(684.0, FLOOR_Y - 56.0), GuideArrow.Dir.RIGHT, "墓坡", true)
	touch_gate_east(host, "S2", "west")


func _build_s2(host: Node2D) -> void:
	room_box(host, 928, false)
	var gw := touch_gate_west(host, "S1", "east")
	var ge := touch_gate_east(host, "S3", "west")
	step(host, "RainMoundW", Vector2(240.0, FLOOR_Y - 28.0), 96.0, "ground")
	step(host, "RainMoundE", Vector2(592.0, FLOOR_Y - 28.0), 96.0, "ground")
	prop(host, "stone_2", Vector2(448.0, FLOOR_Y))
	prop(host, "grave_cross", Vector2(512.0, FLOOR_Y))
	prop(host, "balustrade", Vector2(744.0, FLOOR_Y))

	var arr := guide_arrow(host, "ArrowTower", Vector2(844.0, FLOOR_Y - 56.0), GuideArrow.Dir.RIGHT, "钟楼门", false)
	var waves := [
		[
			{"kind": "skeleton", "pos": Vector2(340.0, FLOOR_Y)},
			{"kind": "skeleton", "pos": Vector2(560.0, FLOOR_Y)},
			{"kind": "scrapper", "pos": Vector2(680.0, FLOOR_Y)},
		],
		[
			{"kind": "ghost", "pos": Vector2(320.0, FLOOR_Y - 60.0)},
			{"kind": "gear_shield", "pos": Vector2(500.0, FLOOR_Y)},
			{"kind": "spitter", "pos": Vector2(640.0, FLOOR_Y - 28.0)},
		],
		[
			{"kind": "skeleton", "pos": Vector2(288.0, FLOOR_Y - 28.0)},
			{"kind": "gear_shield", "pos": Vector2(464.0, FLOOR_Y)},
			{"kind": "ghost", "pos": Vector2(620.0, FLOOR_Y - 64.0)},
			{"kind": "scrapper", "pos": Vector2(716.0, FLOOR_Y)},
		],
	]
	wave_arena(host, "RainSiegeArena", "S2", 64.0, 864.0, waves,
			"s4b_r2_wave_start", "s4b_r2_clear", {3: "s4b_r2_wave_3"}, [gw, ge], [arr])


func _build_s3(host: Node2D) -> void:
	room_box(host, 672, false)
	touch_gate_west(host, "S2", "east")
	prop(host, "door_arch", Vector2(320.0, FLOOR_Y))
	prop(host, "broken_machine", Vector2(432.0, FLOOR_Y))
	guide_arrow(host, "ArrowBellTower", Vector2(496.0, FLOOR_Y - 56.0), GuideArrow.Dir.RIGHT, "无舌钟楼", true)
	arch_gate(host, "ToStage05Gate", Vector2(576.0, FLOOR_Y), "无舌钟楼",
			"S1", "west", "stage05", "stage05", "stage04b")
