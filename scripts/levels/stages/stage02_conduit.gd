extends StageRoomBuilder
## 节点贰 · 沉钟水渠（6 房：S1 竖井入水 -> S2 苔水双波 -> S3 空钟Boss+系核 -> S4 钩锁上桥/排渣深井分岔 -> S5 盾桥围城 -> S6 守渠人Boss）


func _init() -> void:
	configure_stage("stage02", "undercroft", "spore")


func room_ids() -> Array[String]:
	return ["S1", "S2", "S3", "S4", "S5", "S6"]


func default_room() -> String:
	return "S1"


func boss_room() -> String:
	return "S6"


func spawn_for_room(p_room_id: String, spawn_tag: String) -> Vector2:
	match p_room_id:
		"S1":
			return Vector2(672.0, FLOOR_Y) if spawn_tag == "east" else Vector2(88.0, FLOOR_Y)
		"S2":
			return Vector2(784.0, FLOOR_Y) if spawn_tag == "east" else Vector2(84.0, FLOOR_Y)
		"S3":
			return Vector2(876.0, FLOOR_Y) if spawn_tag == "east" else Vector2(88.0, FLOOR_Y)
		"S4":
			if spawn_tag == "east":
				return Vector2(820.0, FLOOR_Y - 56.0)
			return Vector2(88.0, FLOOR_Y)
		"S5":
			return Vector2(796.0, FLOOR_Y) if spawn_tag == "east" else Vector2(84.0, FLOOR_Y)
		"S6":
			return Vector2(92.0, FLOOR_Y)
	return Vector2(88.0, FLOOR_Y)


func on_room_entered(_host: Node2D, p_room_id: String) -> void:
	match p_room_id:
		"S1":
			GameEvents.voice_triggered.emit("s2_r1_enter", false)
		"S3":
			if not StageRoomMemory.is_cleared(stage_id_val, "S3"):
				GameEvents.voice_triggered.emit("s2_r3_boss_intro", false)
		"S4":
			GameEvents.voice_triggered.emit("s2_r4_fork_guide", false)
		"S6":
			if not StageRoomMemory.is_cleared(stage_id_val, "S6"):
				GameEvents.voice_triggered.emit("s2_r6_boss_intro", false)


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
	room_box(host, 768, true, "moss", -32.0, Vector2(360.0, 488.0), Vector2.ZERO, false)
	nest(host, "ConduitEntryNest", 192.0, FLOOR_Y)
	toxin_pit(host, "DripPit", 360.0, 488.0, 32.0, "moss")
	step(host, "DripStep", Vector2(392.0, FLOOR_Y - 28.0), 64.0, "moss_float")
	prop(host, "arch", Vector2(280.0, FLOOR_Y))
	prop(host, "pipe_valve", Vector2(576.0, FLOOR_Y))
	hanging(host, "vine", Vector2(332.0, 0.0))
	torch(host, 220.0, FLOOR_Y, Color(0.62, 0.88, 0.9))
	guide_arrow(host, "ArrowEast", Vector2(676.0, FLOOR_Y - 56.0), GuideArrow.Dir.RIGHT, "水渠", true)
	touch_gate_east(host, "S2", "west")


func _build_s2(host: Node2D) -> void:
	room_box(host, 880, true, "moss", -32.0)
	var gw := touch_gate_west(host, "S1", "east")
	var ge := touch_gate_east(host, "S3", "west")
	step(host, "MossPlatW", Vector2(224.0, FLOOR_Y - 28.0), 96.0, "moss_float")
	step(host, "MossPlatE", Vector2(560.0, FLOOR_Y - 28.0), 96.0, "moss_float")
	prop(host, "rubble", Vector2(440.0, FLOOR_Y))
	torch(host, 440.0, FLOOR_Y, Color(0.62, 0.88, 0.9))

	var arr := guide_arrow(host, "ArrowBell", Vector2(792.0, FLOOR_Y - 56.0), GuideArrow.Dir.RIGHT, "钟室", false)
	var waves := [
		[
			{"kind": "scrapper", "pos": Vector2(360.0, FLOOR_Y)},
			{"kind": "flying_demon", "pos": Vector2(560.0, FLOOR_Y - 72.0)},
		],
		[
			{"kind": "spitter", "pos": Vector2(268.0, FLOOR_Y - 28.0)},
			{"kind": "scrapper", "pos": Vector2(520.0, FLOOR_Y)},
			{"kind": "flying_demon", "pos": Vector2(640.0, FLOOR_Y - 76.0)},
		],
	]
	wave_arena(host, "MossWaveArena", "S2", 64.0, 816.0, waves,
			"s2_r2_wave_start", "s2_r2_clear", {}, [gw, ge], [arr])


func _build_s3(host: Node2D) -> void:
	room_box(host, 960, true, "moss", -48.0)
	var gw := touch_gate_west(host, "S2", "east")
	var ge := touch_gate_east(host, "S4", "west")
	prop(host, "arch", Vector2(260.0, FLOOR_Y))
	prop(host, "chain", Vector2(480.0, FLOOR_Y))
	torch(host, 200.0, FLOOR_Y, Color(0.62, 0.88, 0.9))
	torch(host, 760.0, FLOOR_Y, Color(0.62, 0.88, 0.9))

	# 战后拾取钩锁系核（tether_core）
	pickup(host, "TetherCorePickup", Vector2(792.0, FLOOR_Y - 32.0), &"tether_core")
	var arr := guide_arrow(host, "ArrowSluice", Vector2(876.0, FLOOR_Y - 56.0), GuideArrow.Dir.RIGHT, "排渣桥", false)
	var foe := stage_boss(host, "S3", "HollowBell", "hollow_bell", Vector2(640.0, FLOOR_Y),
			64.0, 896.0, [gw, ge], [arr], "hollow_bell_dead", "s2_r3_boss_down")
	var arena := boss_arena(host, "HollowBell") as BossArena
	if foe != null and arena != null:
		arena.register_hazard(&"bell_fall_west", arena.make_hazard(BossArena.HazardKind.ROCKFALL,
				Vector2(280.0, FLOOR_Y), {"size": Vector2(48, 32), "offset": Vector2(0, -16), "telegraph": 0.45}))
		arena.register_hazard(&"bell_fall_east", arena.make_hazard(BossArena.HazardKind.ROCKFALL,
				Vector2(680.0, FLOOR_Y), {"size": Vector2(48, 32), "offset": Vector2(0, -16), "telegraph": 0.45}))


func _build_s4(host: Node2D) -> void:
	# 关键叛逆分岔房：上方钩锁与发光箭头指向右上高桥（S5），下方排渣深井无视箭头跳入即进 branch02！
	room_box(host, 928, true, "moss", -48.0, Vector2(416.0, 560.0))
	touch_gate_west(host, "S3", "east")

	# 上层正统钩锁路径（同时铺可跳跃的台阶保证无钩锁也可通过 LevelSanity 连通性校验）
	step(host, "StepClimbA", Vector2(280.0, FLOOR_Y - 28.0), 96.0, "moss_float")
	hook(host, "SluiceHook", Vector2(488.0, FLOOR_Y - 120.0))
	step(host, "BridgeMid", Vector2(424.0, FLOOR_Y - 56.0), 128.0, "moss_float")
	step(host, "BridgeEast", Vector2(600.0, FLOOR_Y - 56.0), 328.0, "moss_float")

	guide_arrow(host, "ArrowUpHook", Vector2(336.0, FLOOR_Y - 84.0), GuideArrow.Dir.UP, "钩锁上桥", true)
	guide_arrow(host, "ArrowBridgeEast", Vector2(828.0, FLOOR_Y - 112.0), GuideArrow.Dir.RIGHT, "水闸", true)
	touch_gate_east(host, "S5", "west", "", "", "", FLOOR_Y - 56.0)

	# 下方排渣深井叛逆口 -> branch02
	prop(host, "warning_plate", Vector2(388.0, FLOOR_Y))
	disobedience_line(host, "PitDisobey", Vector2(488.0, FLOOR_Y + 24.0), Vector2(116.0, 36.0),
			"branch02", PackedStringArray(["s2_r4_disobey_pit"]))
	touch_gate_pit(host, 488.0, 128.0, "B1", "top", "branch02", "branch02")


func _build_s5(host: Node2D) -> void:
	room_box(host, 880, true, "moss", -32.0)
	var gw := touch_gate_west(host, "S4", "east")
	var ge := touch_gate_east(host, "S6", "west")
	nest(host, "SluicePreBossNest", 160.0, FLOOR_Y)
	step(host, "ShieldDeck", Vector2(416.0, FLOOR_Y - 28.0), 112.0, "moss_float")
	prop(host, "pipe_valve", Vector2(312.0, FLOOR_Y))
	prop(host, "balustrade", Vector2(688.0, FLOOR_Y))

	var arr := guide_arrow(host, "ArrowWarden", Vector2(796.0, FLOOR_Y - 56.0), GuideArrow.Dir.RIGHT, "绞盘厅", false)
	var waves := [
		[
			{"kind": "gear_shield", "pos": Vector2(460.0, FLOOR_Y)},
			{"kind": "spitter", "pos": Vector2(648.0, FLOOR_Y)},
		],
		[
			{"kind": "gear_shield", "pos": Vector2(380.0, FLOOR_Y)},
			{"kind": "scrapper", "pos": Vector2(560.0, FLOOR_Y)},
			{"kind": "flying_demon", "pos": Vector2(680.0, FLOOR_Y - 72.0)},
		],
	]
	wave_arena(host, "SluiceBridgeArena", "S5", 224.0, 816.0, waves,
			"s2_r5_wave_start", "s2_r5_clear", {}, [gw, ge], [arr])


func _build_s6(host: Node2D) -> void:
	room_box(host, 960, true, "moss", -48.0)
	var gw := touch_gate_west(host, "S5", "east")
	var out_gate := arch_gate(host, "ToStage03Gate", Vector2(864.0, FLOOR_Y), "死城圣殿",
			"S1", "west", "stage03", "stage03", "stage02", "capstan_dead", "绞盘闸门锁死")
	prop(host, "arch", Vector2(280.0, FLOOR_Y))
	prop(host, "pipe_valve", Vector2(720.0, FLOOR_Y))
	torch(host, 220.0, FLOOR_Y, Color(0.62, 0.88, 0.9))
	torch(host, 740.0, FLOOR_Y, Color(0.62, 0.88, 0.9))
	var arr := guide_arrow(host, "ArrowExit", Vector2(800.0, FLOOR_Y - 56.0), GuideArrow.Dir.RIGHT, "升回地面", false)
	stage_boss(host, "S6", "CapstanWarden", "capstan_warden", Vector2(660.0, FLOOR_Y),
			64.0, 896.0, [gw, out_gate], [arr], "capstan_dead", "s2_r6_boss_down")
