extends StageRoomBuilder
## 节点柒 · 熔渣城墙（5 房：S1 浇铸池城垛 -> S2 渣河铁桥三波 -> S3 静默灰卫收剑慈悲检验 -> S4 断崖叛逆分岔 -> S5 炉风先驱Boss）


func _init() -> void:
	configure_stage(
		"stage06",
		"ramparts",
		"ember",
		{"time": 0.66, "weather": "wind", "hold": 240.0},
		{"allowed": [3, 1], "intensity": Vector2(0.55, 0.9), "hold": 180.0}
	)


func room_ids() -> Array[String]:
	return ["S1", "S2", "S3", "S4", "S5"]


func default_room() -> String:
	return "S1"


func boss_room() -> String:
	return "S5"


func spawn_for_room(p_room_id: String, spawn_tag: String) -> Vector2:
	match p_room_id:
		"S1":
			return Vector2(680.0, FLOOR_Y) if spawn_tag == "east" else Vector2(88.0, FLOOR_Y)
		"S2":
			return Vector2(844.0, FLOOR_Y) if spawn_tag == "east" else Vector2(84.0, FLOOR_Y)
		"S3":
			return Vector2(680.0, FLOOR_Y) if spawn_tag == "east" else Vector2(88.0, FLOOR_Y)
		"S4":
			if spawn_tag == "east":
				return Vector2(820.0, FLOOR_Y - 56.0)
			return Vector2(88.0, FLOOR_Y)
		"S5":
			return Vector2(92.0, FLOOR_Y)
	return Vector2(88.0, FLOOR_Y)


func on_room_entered(_host: Node2D, p_room_id: String) -> void:
	match p_room_id:
		"S1":
			GameEvents.voice_triggered.emit("s6_r1_enter", false)
		"S3":
			GameEvents.voice_triggered.emit("s6_r3_command_kill", false)
		"S4":
			GameEvents.voice_triggered.emit("s6_r4_fork_guide", false)
		"S5":
			if not StageRoomMemory.is_cleared(stage_id_val, "S5"):
				GameEvents.voice_triggered.emit("s6_r5_boss_intro", false)


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
		"S5":
			_build_s5(host)


func _build_s1(host: Node2D) -> void:
	room_box(host, 768, false)
	nest(host, "RampartEntryNest", 180.0, FLOOR_Y)
	step(host, "BattlementStep", Vector2(384.0, FLOOR_Y - 28.0), 112.0, "rampart")
	reward(host, "RampartCarapace", Vector2(440.0, FLOOR_Y - 28.0) - Vector2(0.0, 7.0),
			"equipment", "iron_carapace", EquipmentCatalog.iron_carapace().display_name)
	prop(host, "balustrade_wall", Vector2(288.0, FLOOR_Y))
	prop(host, "ruin_tower", Vector2(580.0, FLOOR_Y))
	guide_arrow(host, "ArrowBridge", Vector2(684.0, FLOOR_Y - 56.0), GuideArrow.Dir.RIGHT, "渣河铁桥", true)
	touch_gate_east(host, "S2", "west")


func _build_s2(host: Node2D) -> void:
	room_box(host, 928, false)
	var gw := touch_gate_west(host, "S1", "east")
	var ge := touch_gate_east(host, "S3", "west")
	step(host, "SlagTowerW", Vector2(224.0, FLOOR_Y - 28.0), 96.0, "rampart")
	step(host, "SlagTowerE", Vector2(608.0, FLOOR_Y - 28.0), 96.0, "rampart")
	prop(host, "balustrade_wall", Vector2(464.0, FLOOR_Y))
	prop(host, "rock_pile", Vector2(352.0, FLOOR_Y))

	var arr := guide_arrow(host, "ArrowWall", Vector2(844.0, FLOOR_Y - 56.0), GuideArrow.Dir.RIGHT, "守墙哨", false)
	var waves := [
		[
			{"kind": "skeleton", "pos": Vector2(340.0, FLOOR_Y)},
			{"kind": "gear_shield", "pos": Vector2(580.0, FLOOR_Y)},
		],
		[
			{"kind": "spitter", "pos": Vector2(272.0, FLOOR_Y - 28.0)},
			{"kind": "scrapper", "pos": Vector2(480.0, FLOOR_Y)},
			{"kind": "fire_skull", "pos": Vector2(640.0, FLOOR_Y - 68.0)},
		],
		[
			{"kind": "gear_shield", "pos": Vector2(360.0, FLOOR_Y)},
			{"kind": "gear_shield", "pos": Vector2(560.0, FLOOR_Y)},
			{"kind": "flying_demon", "pos": Vector2(464.0, FLOOR_Y - 76.0)},
		],
	]
	wave_arena(host, "SlagBridgeArena", "S2", 64.0, 864.0, waves,
			"s6_r2_wave_start", "s6_r2_clear", {}, [gw, ge], [arr])


func _build_s3(host: Node2D) -> void:
	# 静默灰卫检验房：伊尔催你挥剑杀守卫，但若不挥剑走过灰卫身边（MERCY_PASS），灰卫向你致意、伊尔破防暴露！
	room_box(host, 768, false)
	touch_gate_west(host, "S2", "east")
	touch_gate_east(host, "S4", "west")

	prop(host, "door_arch_wall", Vector2(384.0, FLOOR_Y))
	prop(host, "balustrade_wall", Vector2(256.0, FLOOR_Y))
	prop(host, "fence", Vector2(512.0, FLOOR_Y))
	# 伫立在城垛中央的静默灰卫剪影（使用守墓石像染铁灰呈现不主动出手的守墙老兵）
	prop(host, "res://assets/env/statue_keeper.png", Vector2(416.0, FLOOR_Y), 1.0, Color(0.76, 0.80, 0.86), 0)

	disobedience_mercy(host, "AshGuardMercy", Vector2(480.0, FLOOR_Y), Vector2(96.0, 72.0),
			PackedStringArray(["s6_r3_mercy_pass", "s6_r3_mercy_yir"]))
	guide_arrow(host, "ArrowCliff", Vector2(680.0, FLOOR_Y - 56.0), GuideArrow.Dir.RIGHT, "烬风断崖", true)


func _build_s4(host: Node2D) -> void:
	# 叛逆分岔房：上层石阶与钩锁顺箭头去 S5（炉风先驱），下方断崖缺口跳下即进入【绝壁古厩】（branch05）！
	room_box(host, 928, false, "rampart", -64.0, Vector2(416.0, 560.0))
	touch_gate_west(host, "S3", "east")
	nest(host, "CliffPreBossNest", 176.0, FLOOR_Y)

	step(host, "CliffStepA", Vector2(288.0, FLOOR_Y - 28.0), 96.0, "rampart")
	hook(host, "CliffHook", Vector2(488.0, FLOOR_Y - 120.0))
	step(host, "CliffSpan", Vector2(424.0, FLOOR_Y - 56.0), 128.0, "rampart")
	step(host, "CliffEast", Vector2(600.0, FLOOR_Y - 56.0), 328.0, "rampart")

	guide_arrow(host, "ArrowSpan", Vector2(336.0, FLOOR_Y - 84.0), GuideArrow.Dir.UP, "跃过断崖", true)
	guide_arrow(host, "ArrowHerald", Vector2(828.0, FLOOR_Y - 112.0), GuideArrow.Dir.RIGHT, "炉风先驱", true)
	touch_gate_east(host, "S5", "west", "", "", "", FLOOR_Y - 56.0)

	prop(host, "warning_plate", Vector2(384.0, FLOOR_Y))
	disobedience_line(host, "CliffDropDisobey", Vector2(488.0, FLOOR_Y + 24.0), Vector2(116.0, 36.0),
			"branch05", PackedStringArray(["s6_r4_disobey_cliff"]))
	touch_gate_pit(host, 488.0, 128.0, "B1", "top", "branch05", "branch05")


func _build_s5(host: Node2D) -> void:
	room_box(host, 960, false)
	var gw := touch_gate_west(host, "S4", "east")
	var out_gate := arch_gate(host, "ToStage07Gate", Vector2(864.0, FLOOR_Y), "炉心门前",
			"S1", "west", "stage07", "stage07", "stage06", "herald_dead", "烬风封锁着城门")
	prop(host, "balustrade_wall", Vector2(256.0, FLOOR_Y))
	prop(host, "ruin_tower", Vector2(480.0, FLOOR_Y))
	prop(host, "balustrade_wall", Vector2(720.0, FLOOR_Y))
	var arr := guide_arrow(host, "ArrowForgeGate", Vector2(800.0, FLOOR_Y - 56.0), GuideArrow.Dir.RIGHT, "炉心门", false)
	stage_boss(host, "S5", "EmberwindHerald", "emberwind_herald", Vector2(640.0, FLOOR_Y),
			64.0, 896.0, [gw, out_gate], [arr], "herald_dead", "s6_r5_boss_down")
