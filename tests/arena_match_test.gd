extends TestCase
## 水晶护盾、胜负、超时、兵线、原地复活、商店、祝福。

const ArenaCatalog := preload("res://scripts/data/arena_catalog.gd")
const PATH := "user://test_arena_match.cfg"

var _respawns := 0


func setup() -> void:
	_respawns = 0
	_quiet_reset()
	ArenaRun.use_file(PATH)
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func teardown() -> void:
	if GameEvents.player_respawned.is_connected(_on_respawned):
		GameEvents.player_respawned.disconnect(_on_respawned)
	_quiet_reset()
	ArenaRun.use_default_file()
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_crystal_shield_and_tower_order() -> void:
	_play()
	eq(ArenaRun.apply_structure_damage("enemy", 2, 40, "player"), 0)
	eq(ArenaRun.apply_structure_damage("enemy", 1, 40, "player"), 0)
	eq(_hp("enemy", 2), _max_hp("enemy", 2))
	ok(not _exposed("enemy", 1))
	ok(not _exposed("enemy", 2))
	ok(ArenaRun.apply_structure_damage("enemy", 0, 999, "player") > 0)
	eq(ArenaRun.phase(), ArenaCatalog.PHASE_PLAYING)
	ok(_exposed("enemy", 1))
	ok(not _exposed("enemy", 2))
	ok(ArenaRun.apply_structure_damage("enemy", 1, 999, "player") > 0)
	ok(_exposed("enemy", 2))
	ok(ArenaRun.apply_structure_damage("enemy", 2, 999, "player") > 0)
	eq(ArenaRun.phase(), ArenaCatalog.PHASE_RESULT)
	var result := ArenaRun.match_result()
	eq(String(result["outcome"]), "win")
	eq(String(result["reason"]), "crystal")
	ok(bool(result["win"]))
	ok(not bool(result["draw"]))
	eq(int(result["blue_towers"]), 2)
	ok(bool(result["new_record"]))
	eq(String(result["mvp"]["id"]), "player")


func test_timeout_uses_towers_then_kills_then_draw() -> void:
	_play()
	ArenaRun.apply_structure_damage("enemy", 0, 999, "player")
	_tick(720.0)
	eq(String(ArenaRun.match_result()["outcome"]), "win")
	eq(String(ArenaRun.match_result()["reason"]), "timeout")
	eq(int(ArenaRun.match_result()["blue_towers"]), 1)

	_quiet_reset()
	ArenaRun.use_file(PATH)
	_play()
	_kill("enemy_0", "red_a")
	_kill("enemy_0", "red_b")
	_kill("player", "blue_a")
	_tick(720.0)
	eq(String(ArenaRun.match_result()["outcome"]), "loss")
	eq(int(ArenaRun.match_result()["red_kills"]), 2)
	eq(int(ArenaRun.match_result()["blue_kills"]), 1)

	_quiet_reset()
	ArenaRun.use_file(PATH)
	_play()
	_tick(720.0)
	eq(String(ArenaRun.match_result()["outcome"]), "draw")
	ok(bool(ArenaRun.match_result()["draw"]))
	eq(int(ArenaRun.read_records()["draws"]), 1)


func test_wave_roster_every_third_has_siege() -> void:
	_play()
	_tick(1.0)
	var first := _kinds(ArenaRun.take_wave())
	eq(first.size(), 3)
	ok(not first.has("siege"))
	_tick(30.0)
	var second := _kinds(ArenaRun.take_wave())
	eq(second.size(), 3)
	ok(not second.has("siege"))
	ok(ArenaRun.take_wave().is_empty(), "波次只能取走一次")
	_tick(30.0)
	var third := _kinds(ArenaRun.take_wave())
	ok(third.has("siege"))
	eq(third.size(), 4)


func test_wave_power_grows_then_caps() -> void:
	almost(ArenaCatalog.wave_power(1), 1.0, 0.001)
	ok(ArenaCatalog.wave_power(2) > ArenaCatalog.wave_power(1), "第二波开始变厚")
	almost(ArenaCatalog.wave_power(13), ArenaCatalog.WAVE_GROWTH_CAP, 0.001)
	almost(ArenaCatalog.wave_power(40), ArenaCatalog.WAVE_GROWTH_CAP, 0.001, "封顶之后不再涨")
	var base := ArenaCatalog.scaled_max_hp(int(ArenaCatalog.unit_stat("melee")["hp"]), "minion", "veteran")
	var late := int(round(float(base) * ArenaCatalog.wave_power(10)))
	ok(late > base, "第 10 波生命高于第 1 波")
	eq(ArenaCatalog.lane_slot(0, 4, 0), 0)
	eq(ArenaCatalog.lane_slot(1, 4, 0), 1, "没设种子时兵线不抖")
	ArenaCatalog.set_match_seed(3)
	ok(ArenaCatalog.lane_slot(1, 4, 0) != 1, "种子把第二只小兵错开")
	eq(ArenaCatalog.lane_slot(0, 4, 0), 0, "种子不动其余槽位")
	ArenaCatalog.set_match_seed(-1)


func test_player_respawn_does_not_reload_scene() -> void:
	_play()
	var world := Node2D.new()
	add_child(world)
	build_floor(world, 320.0)
	var scene := get_tree().current_scene
	var player := await spawn_player(world, Vector2(320, -24))
	GameEvents.player_respawned.connect(_on_respawned)
	player.health.take_damage(50)
	await flush(2)
	ok(is_instance_valid(player))
	eq(get_tree().current_scene, scene, "死亡不重载场景")
	eq(player.health.current, 0)
	ok(ArenaRun.respawn_time_left(player) > 1.0)
	_tick(30.0)
	eq(_respawns, 1)
	eq(player.health.current, player.health.max_hp)
	ok(player.health.current > 0)
	almost(player.global_position.x, ArenaCatalog.BLUE_FOUNTAIN.x, 1.0)
	almost(player.global_position.y, ArenaCatalog.BLUE_FOUNTAIN.y, 1.0)
	eq(player.collision_layer, 2)
	ok(player.is_physics_processing())
	eq(get_tree().current_scene, scene)
	player.queue_free()


func test_hint_service_resets_after_respawn() -> void:
	var hint := HintService.new()
	add_child(hint)
	await get_tree().process_frame
	hint._dead = true
	GameEvents.player_respawned.emit()
	eq(hint._dead, false)
	hint.queue_free()


func test_xp_ember_shop_and_blessing() -> void:
	_play()
	_kill("player", "m1")
	_kill("player", "m2")
	_kill("player", "m3")
	eq(ArenaRun.player_level(), 2)
	eq(ArenaRun.player_xp(), 0)
	eq(ArenaRun.player_ember(), 15)
	var poor := ArenaRun.buy("edge")
	ok(not bool(poor["ok"]))
	eq(String(poor["reason"]), "ember")
	ArenaRun.grant_ember("player", 20)
	var blocked := ArenaRun.buy("edge")
	ok(not bool(blocked["ok"]))
	eq(String(blocked["reason"]), "range")
	ArenaRun.shop_ignore_range = true
	var bought := ArenaRun.buy("edge")
	ok(bool(bought["ok"]))
	eq(int(bought["ember"]), 17)
	ArenaRun.report_death({
		"killer_id": "player",
		"victim_id": "elite",
		"victim_team": "neutral",
		"victim_kind": "elite",
		"victim_label": "炉火精英",
		"xp": 36,
		"ember": 20,
	})
	ok(ArenaRun.blessing_time_left("player") > 0.0)
	var board := ArenaRun.scoreboard()
	ok(int(board["blue"]["kills"]) >= 3)
	var heroes: Array = board["heroes"]
	ok(heroes.size() >= 6)


func _play() -> void:
	ArenaRun.auto_begin = true
	ArenaRun.activate_for_test()


func _tick(seconds: float) -> void:
	get_tree().root.get_node("ArenaRun")._process(seconds)


func _kill(killer_id: String, victim_id: String) -> void:
	var victim_team := "enemy"
	if killer_id != "player":
		victim_team = "player"
	ArenaRun.report_death({
		"killer_id": killer_id,
		"victim_id": victim_id,
		"victim_team": victim_team,
		"victim_kind": "minion",
		"victim_label": victim_id,
		"xp": 8,
		"ember": 5,
	})


func _kinds(wave: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var raw: Variant = wave.get("kinds", [])
	if raw is Array:
		for item in raw:
			out.append(String(item))
	return out


func _row(team: String, index: int) -> Dictionary:
	for raw in ArenaRun.tower_status():
		if raw is Dictionary:
			var row: Dictionary = raw
			if String(row.get("team", "")) == team and int(row.get("index", -1)) == index:
				return row
	return {}


func _hp(team: String, index: int) -> int:
	return int(_row(team, index).get("hp", -1))


func _max_hp(team: String, index: int) -> int:
	return int(_row(team, index).get("max_hp", -1))


func _exposed(team: String, index: int) -> bool:
	return bool(_row(team, index).get("exposed", false))


func _on_respawned() -> void:
	_respawns += 1


func _quiet_reset() -> void:
	ArenaRun.auto_begin = false
	ArenaRun.shop_ignore_range = false
	if get_tree() != null and get_tree().paused:
		get_tree().paused = false
	if Director.is_suspended():
		Director.resume()
	ArenaRun.abandon()
	ArenaRun.set_difficulty(ArenaCatalog.DEFAULT_DIFFICULTY)
