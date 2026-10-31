extends StageRoomBuilder
## 节点壹 · 腐液墓园（6 房：S1 拔剑醒坟+西裂墙 -> S2 弹反池+熔热核 -> S3 双波墓道 -> S4 余烬巢岔口 -> S5 刽子手Boss -> S6 炉座抉择）


func _init() -> void:
	configure_stage(
		"stage01",
		"graveyard",
		"ash",
		{"time": 0.74, "weather": "fog", "hold": 240.0},
		{"allowed": [2, 1], "intensity": Vector2(0.45, 0.8), "hold": 180.0}
	)


func room_ids() -> Array[String]:
	return ["S1", "S2", "S3", "S4", "S5", "S6"]


func default_room() -> String:
	return "S1"


func boss_room() -> String:
	return "S5"


func spawn_for_room(p_room_id: String, spawn_tag: String) -> Vector2:
	match p_room_id:
		"S1":
			if spawn_tag == "east":
				return Vector2(792.0, FLOOR_Y)
			return Vector2(96.0, FLOOR_Y)
		"S2":
			return Vector2(792.0, FLOOR_Y) if spawn_tag == "east" else Vector2(84.0, FLOOR_Y)
		"S3":
			return Vector2(812.0, FLOOR_Y) if spawn_tag == "east" else Vector2(84.0, FLOOR_Y)
		"S4":
			return Vector2(616.0, FLOOR_Y) if spawn_tag == "east" else Vector2(84.0, FLOOR_Y)
		"S5":
			return Vector2(876.0, FLOOR_Y) if spawn_tag == "east" else Vector2(92.0, FLOOR_Y)
		"S6":
			return Vector2(88.0, FLOOR_Y)
	return Vector2(96.0, FLOOR_Y)


func on_room_entered(_host: Node2D, p_room_id: String) -> void:
	match p_room_id:
		"S1":
			if SaveData.has_flag("opening_seen"):
				GameEvents.voice_triggered.emit("s1_r1_wake", false)
		"S2":
			GameEvents.voice_triggered.emit("s1_r2_parry_hint", false)
		"S4":
			GameEvents.voice_triggered.emit("s1_r4_fork", false)
		"S5":
			if not StageRoomMemory.is_cleared(stage_id_val, "S5"):
				GameEvents.voice_triggered.emit("s1_r5_boss_intro", false)
		"S6":
			GameEvents.voice_triggered.emit("s1_r6_heart", false)


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
		"S6":
			_build_s6(host)


func _build_s1(host: Node2D) -> void:
	room_box(host, 880, false)
	# 西侧叛逆裂纹墙 + 背后的废冢尸堆隐藏门（3 刀劈碎解锁 branch01）
	var secret_gate := arch_gate(host, "Branch01Gate", Vector2(32.0, FLOOR_Y), "废冢裂隙",
			"B1", "west", "branch01", "branch01", "", "", "裂纹封坟墙挡着")
	disobedience_seal(host, "WestSealWall", Vector2(64.0, FLOOR_Y), Vector2(20.0, 68.0),
			"branch01", PackedStringArray(["s1_r1_seal_hit_1", "s1_r1_seal_hit_2", "s1_r1_seal_break"]),
			secret_gate, 3)
	disobedience_linger(host, "WakeLinger", "", PackedStringArray(["s1_r1_linger"]), 7.0)

	nest(host, "WakeNest", 228.0, FLOOR_Y)
	step(host, "StepRuin", Vector2(460.0, FLOOR_Y - 28.0), 96.0, "ground")
	prop(host, "grave_cross", Vector2(336.0, FLOOR_Y))
	prop(host, "stone_1", Vector2(412.0, FLOOR_Y))
	prop(host, "statue", Vector2(616.0, FLOOR_Y))
	foliage(host, "tree_1_px", Vector2(688.0, FLOOR_Y), 1.0, true, Color(0.75, 0.78, 0.72))

	guide_arrow(host, "ArrowEast", Vector2(760.0, FLOOR_Y - 56.0), GuideArrow.Dir.RIGHT, "前进", true)
	touch_gate_east(host, "S2", "west")


func _build_s2(host: Node2D) -> void:
	room_box(host, 880, false, "ground", -32.0, Vector2(280.0, 424.0), Vector2.ZERO, false)
	touch_gate_west(host, "S1", "east")
	toxin_pit(host, "RotPit", 280.0, 424.0, 32.0, "ground")
	step(host, "PitBridge", Vector2(312.0, FLOOR_Y - 28.0), 80.0, "ground")
	step(host, "CorePedestal", Vector2(544.0, FLOOR_Y - 24.0), 96.0, "ground")

	# 弹反教学残魂 + 熔热核（kiln_core）+ 热锻锈门
	enemy(host, "ParrySpitter", "spitter", Vector2(488.0, FLOOR_Y))
	pickup(host, "KilnCorePickup", Vector2(592.0, FLOOR_Y - 52.0), &"kiln_core")
	rusty_gate(host, "KilnGate", Vector2(716.0, FLOOR_Y - 64.0))

	prop(host, "grave_cross", Vector2(180.0, FLOOR_Y))
	prop(host, "bones", Vector2(664.0, FLOOR_Y))
	guide_arrow(host, "ArrowEast", Vector2(796.0, FLOOR_Y - 56.0), GuideArrow.Dir.RIGHT, "热锻破门", true)
	touch_gate_east(host, "S3", "west")


func _build_s3(host: Node2D) -> void:
	room_box(host, 896, false)
	var gw := touch_gate_west(host, "S2", "east")
	var ge := touch_gate_east(host, "S4", "west")
	step(host, "CryptWestLedge", Vector2(224.0, FLOOR_Y - 28.0), 96.0, "ground")
	step(host, "CryptEastLedge", Vector2(576.0, FLOOR_Y - 28.0), 96.0, "ground")
	prop(host, "skull_arch", Vector2(448.0, FLOOR_Y))
	prop(host, "rubble_dry", Vector2(156.0, FLOOR_Y))
	prop(host, "rock_pile", Vector2(740.0, FLOOR_Y))

	var arr := guide_arrow(host, "ArrowEast", Vector2(812.0, FLOOR_Y - 56.0), GuideArrow.Dir.RIGHT, "肃清", false)
	var waves := [
		[
			{"kind": "skeleton", "pos": Vector2(360.0, FLOOR_Y)},
			{"kind": "scrapper", "pos": Vector2(610.0, FLOOR_Y)},
		],
		[
			{"kind": "skeleton", "pos": Vector2(260.0, FLOOR_Y - 28.0)},
			{"kind": "spitter", "pos": Vector2(624.0, FLOOR_Y - 28.0)},
			{"kind": "scrapper", "pos": Vector2(468.0, FLOOR_Y)},
		],
	]
	wave_arena(host, "CryptWaveArena", "S3", 64.0, 832.0, waves,
			"s1_r3_wave_start", "s1_r3_clear", {2: "s1_r3_wave_2"}, [gw, ge], [arr])


func _build_s4(host: Node2D) -> void:
	room_box(host, 704, false)
	touch_gate_west(host, "S3", "east")
	nest(host, "BossPrepNest", 240.0, FLOOR_Y)
	step(host, "RelicStep", Vector2(384.0, FLOOR_Y - 28.0), 96.0, "ground")
	reward(host, "GraveCharm", Vector2(432.0, FLOOR_Y - 28.0) - Vector2(0.0, 7.0),
			"equipment", "bone_charm", EquipmentCatalog.bone_charm().display_name)
	destructible(host, "AshUrnA", &"urn", Vector2(520.0, FLOOR_Y))
	prop(host, "door_arch", Vector2(588.0, FLOOR_Y))
	guide_arrow(host, "ArrowBoss", Vector2(612.0, FLOOR_Y - 56.0), GuideArrow.Dir.RIGHT, "刽子手", true)
	touch_gate_east(host, "S5", "west")


func _build_s5(host: Node2D) -> void:
	room_box(host, 960, false)
	var gw := touch_gate_west(host, "S4", "east")
	var ge := touch_gate_east(host, "S6", "west")
	prop(host, "balustrade", Vector2(220.0, FLOOR_Y))
	prop(host, "balustrade", Vector2(740.0, FLOOR_Y))
	prop(host, "bones", Vector2(480.0, FLOOR_Y))
	var arr := guide_arrow(host, "ArrowHeart", Vector2(872.0, FLOOR_Y - 56.0), GuideArrow.Dir.RIGHT, "炉座", false)
	var foe := stage_boss(host, "S5", "Executioner", "executioner", Vector2(680.0, FLOOR_Y),
			64.0, 896.0, [gw, ge], [arr], "boss_dead", "s1_r5_boss_down")
	if foe != null:
		var hp := foe.get_node_or_null("Health") as Health
		if hp != null:
			hp.changed.connect(func(cur: int, mx: int) -> void:
				if cur > 0 and cur <= mx / 2:
					GameEvents.voice_triggered.emit("s1_r5_boss_phase", false)
			)


func _build_s6(host: Node2D) -> void:
	room_box(host, 672, false)
	touch_gate_west(host, "S5", "east")
	prop(host, "statue", Vector2(236.0, FLOOR_Y))
	prop(host, "skull_arch", Vector2(420.0, FLOOR_Y))
	guide_arrow(host, "ArrowShrine", Vector2(340.0, FLOOR_Y - 64.0), GuideArrow.Dir.RIGHT, "续火", true)
	var heart := forge_heart(host, 480.0, FLOOR_Y)
	heart.unlock()
