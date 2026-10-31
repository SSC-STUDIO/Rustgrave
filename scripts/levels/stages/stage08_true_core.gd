extends StageRoomBuilder
## 隐藏真结局终章 · 归零母模（4 房：T1 真假伊尔对峙破标 -> T2 战马梦魇俯首让路 -> T3 三波司炉禁卫死战 -> T4 司炉母模Boss+破炉黎明门）


func _init() -> void:
	configure_stage("stage08_true", "forge_core", "ember")


func room_ids() -> Array[String]:
	return ["T1", "T2", "T3", "T4"]


func default_room() -> String:
	return "T1"


func boss_room() -> String:
	return "T4"


func spawn_for_room(p_room_id: String, spawn_tag: String) -> Vector2:
	match p_room_id:
		"T1":
			return Vector2(680.0, FLOOR_Y) if spawn_tag == "east" else Vector2(88.0, FLOOR_Y)
		"T2":
			return Vector2(680.0, FLOOR_Y) if spawn_tag == "east" else Vector2(88.0, FLOOR_Y)
		"T3":
			return Vector2(844.0, FLOOR_Y) if spawn_tag == "east" else Vector2(84.0, FLOOR_Y)
		"T4":
			return Vector2(96.0, FLOOR_Y)
	return Vector2(88.0, FLOOR_Y)


func on_room_entered(_host: Node2D, p_room_id: String) -> void:
	match p_room_id:
		"T1":
			GameEvents.voice_triggered.emit("s8_r1_enter", false)
			GameEvents.voice_triggered.emit("s8_r1_true_reply", false)
		"T2":
			GameEvents.voice_triggered.emit("s8_r2_nightmare_bow", false)
		"T4":
			if not StageRoomMemory.is_cleared(stage_id_val, "T4"):
				GameEvents.voice_triggered.emit("s8_r4_boss_intro", false)


func build_room(host: Node2D, p_room_id: String) -> void:
	match p_room_id:
		"T1":
			_build_t1(host)
		"T2":
			_build_t2(host)
		"T3":
			_build_t3(host)
		"T4":
			_build_t4(host)


func _build_t1(host: Node2D) -> void:
	room_box(host, 768, true, "basalt", -48.0)
	prop(host, "broken_machine", Vector2(280.0, FLOOR_Y))
	prop(host, "warning_plate", Vector2(384.0, FLOOR_Y))
	prop(host, "column", Vector2(512.0, FLOOR_Y))
	torch(host, 224.0, FLOOR_Y)
	torch(host, 608.0, FLOOR_Y)
	touch_gate_east(host, "T2", "west")


func _build_t2(host: Node2D) -> void:
	# 梦魇认出真伊尔，不再作为 Boss 阻拦，而是在祭坛前静静俯首守护余烬巢。
	room_box(host, 768, true, "basalt", -48.0)
	touch_gate_west(host, "T1", "east")
	nest(host, "TrueCoreNest", 224.0, FLOOR_Y)
	prop(host, "altar", Vector2(432.0, FLOOR_Y))
	if CharFrames.available("original_nightmare", "idle"):
		var horse_frames := CharFrames.anim("original_nightmare", "idle")
		if not horse_frames.is_empty():
			var bow_horse := Sprite2D.new()
			bow_horse.name = "BowingNightmare"
			bow_horse.texture = horse_frames[0]
			bow_horse.position = Vector2(456.0, FLOOR_Y - 44.0)
			bow_horse.modulate = Color(0.82, 0.92, 1.0, 0.95)
			bow_horse.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			decor_layer(host).add_child(bow_horse)
	torch(host, 320.0, FLOOR_Y)
	torch(host, 576.0, FLOOR_Y)
	touch_gate_east(host, "T3", "west")


func _build_t3(host: Node2D) -> void:
	room_box(host, 928, true, "basalt", -48.0)
	var gw := touch_gate_west(host, "T2", "east")
	var ge := touch_gate_east(host, "T4", "west")
	step(host, "CoreStepW", Vector2(224.0, FLOOR_Y - 28.0), 96.0, "basalt_float")
	step(host, "CoreStepE", Vector2(608.0, FLOOR_Y - 28.0), 96.0, "basalt_float")
	prop(host, "skull_column", Vector2(464.0, FLOOR_Y))
	prop(host, "fire_vent", Vector2(352.0, FLOOR_Y))
	prop(host, "fire_vent", Vector2(576.0, FLOOR_Y))

	var waves := [
		[
			{"kind": "gear_shield", "pos": Vector2(340.0, FLOOR_Y)},
			{"kind": "gear_shield", "pos": Vector2(580.0, FLOOR_Y)},
		],
		[
			{"kind": "spitter", "pos": Vector2(272.0, FLOOR_Y - 28.0)},
			{"kind": "fire_skull", "pos": Vector2(464.0, FLOOR_Y - 68.0)},
			{"kind": "spitter", "pos": Vector2(656.0, FLOOR_Y - 28.0)},
		],
		[
			{"kind": "gear_shield", "pos": Vector2(360.0, FLOOR_Y)},
			{"kind": "scrapper", "pos": Vector2(480.0, FLOOR_Y)},
			{"kind": "flying_demon", "pos": Vector2(600.0, FLOOR_Y - 76.0)},
		],
	]
	wave_arena(host, "PraetorianGauntlet", "T3", 64.0, 864.0, waves,
			"s8_r3_wave_start", "s8_r3_clear", {}, [gw, ge], [])


func _build_t4(host: Node2D) -> void:
	room_box(host, 960, true, "basalt", -64.0)
	var gw := touch_gate_west(host, "T3", "east")
	prop(host, "column", Vector2(240.0, FLOOR_Y))
	prop(host, "column", Vector2(720.0, FLOOR_Y))
	torch(host, 192.0, FLOOR_Y)
	torch(host, 768.0, FLOOR_Y)

	var dawn_door := ending_door(host, 840.0, "破炉黎明之门", "furnace_mother_dead",
			false, "true_break", FLOOR_Y, "司炉母模仍在运转")
	stage_boss(host, "T4", "FurnaceMother", "furnace_mother", Vector2(560.0, FLOOR_Y),
			64.0, 896.0, [gw, dawn_door], [], "furnace_mother_dead", "")
