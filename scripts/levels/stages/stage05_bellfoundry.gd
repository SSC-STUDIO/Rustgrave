extends StageRoomBuilder
## 节点陆 · 无舌钟楼（4 房：S1 钟座前厅战 -> S2 钟井叛逆分岔[下铸钟厅 vs 逆攀钟顶] -> S3 熔炉长廊三波 -> S4 铸钟人Boss）


func _init() -> void:
	configure_stage("stage05", "belltower", "ash")


func room_ids() -> Array[String]:
	return ["S1", "S2", "S3", "S4"]


func default_room() -> String:
	return "S1"


func boss_room() -> String:
	return "S4"


func spawn_for_room(p_room_id: String, spawn_tag: String) -> Vector2:
	match p_room_id:
		"S1":
			return Vector2(780.0, FLOOR_Y) if spawn_tag == "east" else Vector2(88.0, FLOOR_Y)
		"S2":
			if spawn_tag == "top":
				return Vector2(464.0, FLOOR_Y - 112.0)
			if spawn_tag == "east":
				return Vector2(812.0, FLOOR_Y)
			return Vector2(88.0, FLOOR_Y)
		"S3":
			return Vector2(812.0, FLOOR_Y) if spawn_tag == "east" else Vector2(84.0, FLOOR_Y)
		"S4":
			return Vector2(92.0, FLOOR_Y)
	return Vector2(88.0, FLOOR_Y)


func on_room_entered(_host: Node2D, p_room_id: String) -> void:
	match p_room_id:
		"S1":
			GameEvents.voice_triggered.emit("s5_r1_enter", false)
		"S2":
			GameEvents.voice_triggered.emit("s5_r2_fork_guide", false)
		"S4":
			if not StageRoomMemory.is_cleared(stage_id_val, "S4"):
				GameEvents.voice_triggered.emit("s5_r4_boss_intro", false)


func build_room(host: Node2D, p_room_id: String) -> void:
	match p_room_id:
		"S1":
			_build_s1(host)
		"S2":
			_build_s2(host)
		"S3":
			_build_s3(host)
		"S4":
			_build_s4(host)


func _build_s1(host: Node2D) -> void:
	room_box(host, 864, true, "stone", -48.0)
	var ge := touch_gate_east(host, "S2", "west")
	nest(host, "BellBaseNest", 160.0, FLOOR_Y)
	step(host, "BellStepW", Vector2(304.0, FLOOR_Y - 28.0), 96.0, "stone")
	step(host, "BellStepE", Vector2(560.0, FLOOR_Y - 28.0), 96.0, "stone")
	hanging(host, "chain", Vector2(448.0, -16.0))
	prop(host, "column", Vector2(240.0, FLOOR_Y))
	prop(host, "column", Vector2(680.0, FLOOR_Y))

	var arr := guide_arrow(host, "ArrowShaft", Vector2(780.0, FLOOR_Y - 56.0), GuideArrow.Dir.RIGHT, "钟井", false)
	var waves := [
		[
			{"kind": "gear_shield", "pos": Vector2(440.0, FLOOR_Y)},
			{"kind": "flying_demon", "pos": Vector2(608.0, FLOOR_Y - 72.0)},
		],
		[
			{"kind": "skeleton", "pos": Vector2(352.0, FLOOR_Y - 28.0)},
			{"kind": "spitter", "pos": Vector2(608.0, FLOOR_Y - 28.0)},
			{"kind": "scrapper", "pos": Vector2(500.0, FLOOR_Y)},
		],
	]
	wave_arena(host, "BellBaseArena", "S1", 224.0, 800.0, waves,
			"", "s5_r1_clear", {}, [ge], [arr])


func _build_s2(host: Node2D) -> void:
	# 叛逆分岔房：发光箭头强力引导向右下方铸钟厅（S3）；顶板留出竖井开口，逆攀阶梯+钩锁即闯入【无舌钟顶】（branch04）！
	room_box(host, 896, true, "stone", -144.0, Vector2.ZERO, Vector2(384.0, 160.0))
	touch_gate_west(host, "S1", "east")
	touch_gate_east(host, "S3", "west")

	prop(host, "gargoyle", Vector2(256.0, FLOOR_Y))
	prop(host, "gargoyle", Vector2(672.0, FLOOR_Y))
	hanging(host, "chain", Vector2(304.0, -112.0))
	guide_arrow(host, "ArrowDownFoundry", Vector2(760.0, FLOOR_Y - 56.0), GuideArrow.Dir.RIGHT, "去铸钟厅", true)

	# 逆向攀登阶梯（每阶 <= 28px，连往顶板竖井口）
	step(host, "Climb1", Vector2(240.0, FLOOR_Y - 28.0), 80.0, "stone")
	step(host, "Climb2", Vector2(352.0, FLOOR_Y - 56.0), 80.0, "stone")
	step(host, "Climb3", Vector2(464.0, FLOOR_Y - 84.0), 80.0, "stone")
	step(host, "Climb4", Vector2(384.0, FLOOR_Y - 112.0), 160.0, "stone")
	hook(host, "SummitHook", Vector2(464.0, -116.0))

	disobedience_line(host, "SummitDisobey", Vector2(464.0, FLOOR_Y - 112.0), Vector2(112.0, 56.0),
			"branch04", PackedStringArray(["s5_r2_disobey_up"]))
	arch_gate(host, "SummitGate", Vector2(464.0, FLOOR_Y - 112.0), "逆攀无舌钟顶",
			"B1", "west", "branch04", "branch04")


func _build_s3(host: Node2D) -> void:
	room_box(host, 896, true, "stone", -48.0)
	var gw := touch_gate_west(host, "S2", "east")
	var ge := touch_gate_east(host, "S4", "west")
	nest(host, "FoundryPreBossNest", 160.0, FLOOR_Y)
	step(host, "LadlePlatform", Vector2(448.0, FLOOR_Y - 28.0), 112.0, "stone")
	torch(host, 320.0, FLOOR_Y)
	torch(host, 640.0, FLOOR_Y)

	var arr := guide_arrow(host, "ArrowFounder", Vector2(812.0, FLOOR_Y - 56.0), GuideArrow.Dir.RIGHT, "铸钟人", false)
	var waves := [
		[
			{"kind": "scrapper", "pos": Vector2(380.0, FLOOR_Y)},
			{"kind": "fire_skull", "pos": Vector2(580.0, FLOOR_Y - 64.0)},
		],
		[
			{"kind": "gear_shield", "pos": Vector2(360.0, FLOOR_Y)},
			{"kind": "spitter", "pos": Vector2(620.0, FLOOR_Y)},
		],
		[
			{"kind": "gear_shield", "pos": Vector2(420.0, FLOOR_Y)},
			{"kind": "fire_skull", "pos": Vector2(540.0, FLOOR_Y - 68.0)},
			{"kind": "scrapper", "pos": Vector2(680.0, FLOOR_Y)},
		],
	]
	wave_arena(host, "FoundryCorridorArena", "S3", 224.0, 832.0, waves,
			"s5_r3_wave_start", "", {}, [gw, ge], [arr])


func _build_s4(host: Node2D) -> void:
	room_box(host, 960, true, "stone", -48.0)
	var gw := touch_gate_west(host, "S3", "east")
	var out_gate := arch_gate(host, "ToStage06Gate", Vector2(864.0, FLOOR_Y), "熔渣城墙",
			"S1", "west", "stage06", "stage06", "stage05", "founder_dead", "铸钟炉闸锁死")
	prop(host, "altar", Vector2(480.0, FLOOR_Y))
	hanging(host, "chain", Vector2(360.0, -16.0))
	hanging(host, "chain", Vector2(600.0, -16.0))
	torch(host, 224.0, FLOOR_Y)
	torch(host, 736.0, FLOOR_Y)
	var arr := guide_arrow(host, "ArrowRamparts", Vector2(800.0, FLOOR_Y - 56.0), GuideArrow.Dir.RIGHT, "熔渣城墙", false)
	stage_boss(host, "S4", "BellFounder", "bell_founder", Vector2(640.0, FLOOR_Y),
			64.0, 896.0, [gw, out_gate], [arr], "founder_dead", "s5_r4_boss_down")
