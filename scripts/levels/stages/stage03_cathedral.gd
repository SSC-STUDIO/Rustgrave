extends StageRoomBuilder
## 节点叁 · 死城圣殿（5 房：S1 锈苔死街 -> S2 三波街心围猎 -> S3 中庭吊灯叛逆分岔 -> S4 地窖伏击 -> S5 无声唱诗班Boss+余烬核）


func _init() -> void:
	configure_stage("stage03", "cathedral", "dust")


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
			return Vector2(820.0, FLOOR_Y) if spawn_tag == "east" else Vector2(84.0, FLOOR_Y)
		"S3":
			if spawn_tag == "loft":
				return Vector2(480.0, FLOOR_Y - 112.0)
			if spawn_tag == "east":
				return Vector2(832.0, FLOOR_Y)
			return Vector2(88.0, FLOOR_Y)
		"S4":
			return Vector2(748.0, FLOOR_Y) if spawn_tag == "east" else Vector2(84.0, FLOOR_Y)
		"S5":
			return Vector2(92.0, FLOOR_Y)
	return Vector2(88.0, FLOOR_Y)


func on_room_entered(_host: Node2D, p_room_id: String) -> void:
	match p_room_id:
		"S1":
			GameEvents.voice_triggered.emit("s3_r1_enter", false)
		"S3":
			GameEvents.voice_triggered.emit("s3_r3_fork_guide", false)
		"S5":
			if not StageRoomMemory.is_cleared(stage_id_val, "S5"):
				GameEvents.voice_triggered.emit("s3_r5_boss_intro", false)


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
	room_box(host, 768, true, "stone", -48.0)
	nest(host, "CathedralEntryNest", 184.0, FLOOR_Y)
	prop(host, "column", Vector2(320.0, FLOOR_Y))
	prop(host, "window", Vector2(512.0, FLOOR_Y))
	torch(host, 240.0, FLOOR_Y)
	torch(host, 608.0, FLOOR_Y)
	guide_arrow(host, "ArrowPlaza", Vector2(680.0, FLOOR_Y - 56.0), GuideArrow.Dir.RIGHT, "中庭", true)
	touch_gate_east(host, "S2", "west")


func _build_s2(host: Node2D) -> void:
	room_box(host, 912, true, "stone", -48.0)
	var gw := touch_gate_west(host, "S1", "east")
	var ge := touch_gate_east(host, "S3", "west")
	step(host, "NavePewW", Vector2(224.0, FLOOR_Y - 28.0), 96.0, "stone")
	step(host, "NavePewE", Vector2(592.0, FLOOR_Y - 28.0), 96.0, "stone")
	prop(host, "gargoyle", Vector2(456.0, FLOOR_Y))
	torch(host, 336.0, FLOOR_Y)
	torch(host, 576.0, FLOOR_Y)

	var arr := guide_arrow(host, "ArrowNave", Vector2(828.0, FLOOR_Y - 56.0), GuideArrow.Dir.RIGHT, "圣殿", false)
	var waves := [
		[
			{"kind": "skeleton", "pos": Vector2(340.0, FLOOR_Y)},
			{"kind": "ghost", "pos": Vector2(580.0, FLOOR_Y - 56.0)},
		],
		[
			{"kind": "gear_shield", "pos": Vector2(380.0, FLOOR_Y)},
			{"kind": "spitter", "pos": Vector2(640.0, FLOOR_Y - 28.0)},
		],
		[
			{"kind": "skeleton", "pos": Vector2(272.0, FLOOR_Y - 28.0)},
			{"kind": "ghost", "pos": Vector2(460.0, FLOOR_Y - 64.0)},
			{"kind": "scrapper", "pos": Vector2(620.0, FLOOR_Y)},
		],
	]
	wave_arena(host, "CathedralPlazaArena", "S2", 64.0, 848.0, waves,
			"s3_r2_wave_start", "s3_r2_clear", {3: "s3_r2_wave_3"}, [gw, ge], [arr])


func _build_s3(host: Node2D) -> void:
	# 叛逆分岔房：地面箭头引向右侧地窖（S4），但穹顶阶梯与钩锁通向左上【司书暗阁】（branch03）！
	room_box(host, 928, true, "stone", -96.0)
	touch_gate_west(host, "S2", "east")
	touch_gate_east(host, "S4", "west")

	prop(host, "altar", Vector2(464.0, FLOOR_Y))
	prop(host, "column", Vector2(256.0, FLOOR_Y))
	prop(host, "column", Vector2(672.0, FLOOR_Y))
	guide_arrow(host, "ArrowCrypt", Vector2(816.0, FLOOR_Y - 56.0), GuideArrow.Dir.RIGHT, "下地窖", true)

	# 通向穹顶吊灯与暗阁的阶梯 + 钩锁锚点（每阶高度差 <= 28px 满足全连通）
	step(host, "ChoirStep1", Vector2(224.0, FLOOR_Y - 28.0), 80.0, "stone")
	step(host, "ChoirStep2", Vector2(336.0, FLOOR_Y - 56.0), 80.0, "stone")
	step(host, "ChoirStep3", Vector2(448.0, FLOOR_Y - 84.0), 80.0, "stone")
	hook(host, "ChandelierHook", Vector2(512.0, FLOOR_Y - 144.0))
	step(host, "LoftGallery", Vector2(560.0, FLOOR_Y - 112.0), 224.0, "stone")

	disobedience_line(host, "LoftDisobey", Vector2(624.0, FLOOR_Y - 112.0), Vector2(72.0, 56.0),
			"branch03", PackedStringArray(["s3_r3_disobey_loft"]))
	arch_gate(host, "ArchiveGate", Vector2(712.0, FLOOR_Y - 112.0), "司书暗阁",
			"B1", "west", "branch03", "branch03")


func _build_s4(host: Node2D) -> void:
	room_box(host, 832, true, "stone", -32.0)
	var gw := touch_gate_west(host, "S3", "east")
	var ge := touch_gate_east(host, "S5", "west")
	nest(host, "CryptPreBossNest", 160.0, FLOOR_Y)
	step(host, "CryptAltarStep", Vector2(432.0, FLOOR_Y - 28.0), 96.0, "stone")
	prop(host, "skull_column", Vector2(360.0, FLOOR_Y))
	prop(host, "skull_column", Vector2(600.0, FLOOR_Y))

	var arr := guide_arrow(host, "ArrowChoir", Vector2(748.0, FLOOR_Y - 56.0), GuideArrow.Dir.RIGHT, "唱诗厅", false)
	var waves := [
		[
			{"kind": "ghost", "pos": Vector2(420.0, FLOOR_Y - 56.0)},
			{"kind": "spitter", "pos": Vector2(620.0, FLOOR_Y)},
		],
		[
			{"kind": "gear_shield", "pos": Vector2(380.0, FLOOR_Y)},
			{"kind": "ghost", "pos": Vector2(560.0, FLOOR_Y - 64.0)},
			{"kind": "skeleton", "pos": Vector2(660.0, FLOOR_Y)},
		],
	]
	wave_arena(host, "CryptAmbushArena", "S4", 224.0, 768.0, waves,
			"s3_r4_wave_start", "", {}, [gw, ge], [arr])


func _build_s5(host: Node2D) -> void:
	room_box(host, 960, true, "stone", -48.0)
	var gw := touch_gate_west(host, "S4", "east")
	var out_gate := arch_gate(host, "ToStage04Gate", Vector2(864.0, FLOOR_Y), "切槽工坊",
			"S1", "west", "stage04", "stage04", "stage03", "choir_dead", "唱诗坛尚未平息")
	prop(host, "altar", Vector2(480.0, FLOOR_Y))
	prop(host, "window", Vector2(260.0, FLOOR_Y))
	prop(host, "window", Vector2(700.0, FLOOR_Y))
	torch(host, 200.0, FLOOR_Y)
	torch(host, 760.0, FLOOR_Y)

	# 战后拾取余烬核（ember_core：二段跳）
	pickup(host, "EmberCorePickup", Vector2(784.0, FLOOR_Y - 32.0), &"ember_core")
	var arr := guide_arrow(host, "ArrowWorkshop", Vector2(800.0, FLOOR_Y - 56.0), GuideArrow.Dir.RIGHT, "切槽工坊", false)
	stage_boss(host, "S5", "SilentChoir", "silent_choir", Vector2(640.0, FLOOR_Y),
			64.0, 896.0, [gw, out_gate], [arr], "choir_dead", "s3_r5_boss_down")
