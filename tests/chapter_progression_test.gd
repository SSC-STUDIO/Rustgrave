extends TestCase
## StageLevel 节点推进、房间存档恢复与双终章（炉心门表面结局 / 归零母模真结局）集成测试。

func setup() -> void:
	SaveData.save_path = "user://rustgrave_progression_test.cfg"
	SaveData.delete_save()
	StageRoomMemory.clear_all()
	Director.abort()


func teardown() -> void:
	SaveData.delete_save()
	SaveData.save_path = "user://rustgrave_save.cfg"
	StageRoomMemory.clear_all()
	Director.abort()
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)


func _load_stage(id: String, room_id: String = "") -> StageLevel:
	if room_id != "":
		StageRoomMemory.set_pending(id, room_id, "west")
	var level := (load(String(GameContext.LEVELS[id])) as PackedScene).instantiate() as StageLevel
	level.instant_room_transitions = true
	add_child(level)
	await flush(2)
	Director.abort()
	var enemies := level.get_node_or_null("Enemies")
	if enemies != null:
		for enemy in enemies.get_children():
			enemy.set_physics_process(false)
	return level


func _player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player


func test_cross_stage_room_gate_saves_next_arrival_and_keeps_abilities() -> void:
	SaveData.mark_flag("capstan_dead")
	var level := await _load_stage("stage02", "S6")
	var p := _player()
	p.inventory.add_to_pouch(AbilityCatalog.kiln_core())
	p.inventory.insert_into_socket(0)
	var out_gate := level.get_node("Props/ToStage03Gate") as RoomGate
	ok(out_gate != null and out_gate.is_gate_open(), "ToStage03Gate opens once Capstan Warden falls")
	out_gate.interact(p)
	await flush(2)
	Director.abort()
	eq(SaveData.saved_scene(), String(GameContext.LEVELS["stage03"]), "cross-stage gate saves stage03")
	ok(SaveData.has_flag("stage02_done"), "marks stage02_done")
	ok(NarrativeCatalog.is_node_unlocked("stage03", SaveData.flags), "unlocks stage03")
	level.free()
	await flush(1)

	var next_stage := await _load_stage("stage03")
	eq(next_stage.current_room_id, "S1")
	ok(_player().inventory.has_ability(AbilityIds.HEAT_FORGE), "heat forge survives stage transition")
	eq(_player().health.current, _player().health.max_hp)
	next_stage.free()
	await flush(1)


func test_stage_room_nest_and_room_persistence_round_trip() -> void:
	for id in ["stage01", "stage03", "stage05"]:
		SaveData.delete_save()
		StageRoomMemory.clear_all()
		var level := await _load_stage(id)
		var player := _player()
		var nest: EmberNest = null
		for node in level.get_node("Props").get_children():
			if node is EmberNest:
				nest = node as EmberNest
				break
		ok(nest != null, "%s entry room has an EmberNest" % id)
		if nest != null:
			player.position = LevelSanity.feet_of(nest) - Vector2(6.0, 2.0)
			var ckpt := player.position
			nest.interact(player)
			var path := SaveData.persist_path(nest)
			ok(path.begins_with("%s_%s:" % [id, level.current_room_id]), "room-scoped persist_path: " + path)
			level.free()
			await flush(1)

			var reloaded := await _load_stage(id)
			ok(_player().position.distance_to(ckpt) < 14.0, "Continue restores saved room position in " + id)
			eq(SaveData.persist_path(_player()._resolve_lit_nest()), path)
			reloaded.free()
			await flush(1)


func test_surface_finale_and_true_core_finale_save_endings() -> void:
	# 1. Surface finale: stage07 S3 ending door -> "give"
	SaveData.mark_flag("nightmare_dead")
	var s7 := await _load_stage("stage07", "S3")
	var door7 := s7.get_node("Props/Exit") as LevelExit
	ok(door7 != null and not door7.is_locked())
	door7.interact(_player())
	door7.confirm_ending(&"give")
	await flush(2)
	Director.abort()
	ok(SaveData.load_game())
	eq(SaveData.ending, "give")
	ok(SaveData.has_flag("game_complete"))
	s7.free()
	await flush(1)

	# 2. Hidden True Core finale: stage08_true T4 FurnaceMotherBoss -> "true_break"
	SaveData.delete_save()
	StageRoomMemory.clear_all()
	for f in NarrativeCatalog.FRAGMENT_IDS:
		SaveData.mark_flag(f)
	SaveData.mark_flag("true_ending_unlocked")
	var s8 := await _load_stage("stage08_true", "T4")
	var mother := s8.get_node("Enemies/FurnaceMother") as FurnaceMotherBoss
	var door8 := s8.get_node("Props/Exit") as LevelExit
	ok(mother != null and door8 != null)
	ok(door8.is_locked(), "dawn door locked while FurnaceMother lives")
	mother.announce()
	mother.health.take_damage(999, _player())
	await flush(3)
	ok(SaveData.has_flag("furnace_mother_dead"), "killing FurnaceMother sets furnace_mother_dead")
	ok(not door8.is_locked(), "dawn door unlocks after FurnaceMother falls")
	door8.interact(_player())
	await flush(2)
	Director.abort()
	ok(SaveData.load_game())
	eq(SaveData.ending, "true_break", "direct true_break ending saved")
	ok(SaveData.has_flag("true_ending_done"), "marks true_ending_done")
	s8.free()
	await flush(1)
