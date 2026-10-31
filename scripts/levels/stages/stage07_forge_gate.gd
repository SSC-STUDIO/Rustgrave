extends StageRoomBuilder
## 节点捌 · 炉心门前（表面主线终章 3 房：S1 送火长廊 -> S2 战马梦魇Boss -> S3 炉心门[还火/守炉双假结局]）


func _init() -> void:
	configure_stage("stage07", "forge_core", "ember")


func room_ids() -> Array[String]:
	return ["S1", "S2", "S3"]


func default_room() -> String:
	return "S1"


func boss_room() -> String:
	return "S2"


func spawn_for_room(p_room_id: String, spawn_tag: String) -> Vector2:
	match p_room_id:
		"S1":
			return Vector2(680.0, FLOOR_Y) if spawn_tag == "east" else Vector2(88.0, FLOOR_Y)
		"S2":
			return Vector2(880.0, FLOOR_Y) if spawn_tag == "east" else Vector2(96.0, FLOOR_Y)
		"S3":
			return Vector2(96.0, FLOOR_Y)
	return Vector2(88.0, FLOOR_Y)


func on_room_entered(_host: Node2D, p_room_id: String) -> void:
	match p_room_id:
		"S1":
			if NarrativeCatalog.all_fragments_collected(SaveData.flags):
				GameEvents.voice_triggered.emit("s7_r1_enter_truth_ready", false)
			else:
				GameEvents.voice_triggered.emit("s7_r1_enter", false)
		"S2":
			if not StageRoomMemory.is_cleared(stage_id_val, "S2"):
				GameEvents.voice_triggered.emit("s7_r2_boss_intro", false)
		"S3":
			GameEvents.voice_triggered.emit("s7_r3_door", false)


func build_room(host: Node2D, p_room_id: String) -> void:
	match p_room_id:
		"S1":
			_build_s1(host)
		"S2":
			_build_s2(host)
		"S3":
			_build_s3(host)


func _build_s1(host: Node2D) -> void:
	room_box(host, 768, true, "basalt", -48.0)
	nest(host, "ForgeHallNest", 192.0, FLOOR_Y)
	prop(host, "column", Vector2(336.0, FLOOR_Y))
	prop(host, "skull_column", Vector2(528.0, FLOOR_Y))
	torch(host, 256.0, FLOOR_Y)
	torch(host, 608.0, FLOOR_Y)
	if NarrativeCatalog.all_fragments_collected(SaveData.flags) and not TrialRun.active():
		arch_gate(host, "TrueCoreRift", Vector2(432.0, FLOOR_Y), "归零母模", "T1", "west", "stage08_true", "stage08_true")
	guide_arrow(host, "ArrowNightmare", Vector2(684.0, FLOOR_Y - 56.0), GuideArrow.Dir.RIGHT, "斩杀梦魇", true)
	touch_gate_east(host, "S2", "west")


func _build_s2(host: Node2D) -> void:
	room_box(host, 960, true, "basalt", -48.0)
	var gw := touch_gate_west(host, "S1", "east")
	var ge := touch_gate_east(host, "S3", "west")
	prop(host, "column", Vector2(256.0, FLOOR_Y))
	prop(host, "column", Vector2(704.0, FLOOR_Y))
	torch(host, 200.0, FLOOR_Y)
	torch(host, 760.0, FLOOR_Y)
	var arr := guide_arrow(host, "ArrowDoor", Vector2(876.0, FLOOR_Y - 56.0), GuideArrow.Dir.RIGHT, "炉心门", false)
	stage_boss(host, "S2", "Nightmare", "nightmare_boss", Vector2(680.0, FLOOR_Y),
			64.0, 896.0, [gw, ge], [arr], "nightmare_dead", "s7_r2_boss_down")


func _build_s3(host: Node2D) -> void:
	room_box(host, 704, true, "basalt", -48.0)
	touch_gate_west(host, "S2", "east")
	prop(host, "altar", Vector2(320.0, FLOOR_Y))
	prop(host, "skull_arch", Vector2(432.0, FLOOR_Y))
	torch(host, 224.0, FLOOR_Y)
	guide_arrow(host, "ArrowSubmit", Vector2(448.0, FLOOR_Y - 64.0), GuideArrow.Dir.RIGHT, "投入炉心", true)
	ending_door(host, 544.0, "炉心之门", "", true, "", FLOOR_Y, "梦魇仍守在门前")
