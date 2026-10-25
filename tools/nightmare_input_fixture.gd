extends "res://tools/campaign_walkthrough.gd"
## LOCAL FINALE FIXTURE, NOT A CAMPAIGN RUN.
## Initial staging only: place the default knight at the authored arena nest and
## omit the heat-forge entrance gate (this fixture does not grant a kiln core).
## The complete real level/Boss/hazards are otherwise unchanged. After staging,
## only ordinary inputs drive combat, checkpoint interaction, death and Continue.

var _fixture_start := {}


func _run() -> void:
	Settings.set_value(&"assist_incoming", 0.5, false)
	Settings.set_value(&"assist_parry", 1.5, false)
	Settings.set_value(&"assist_toxin", 0.5, false)
	SaveData.delete_save()
	GameContext.pending_world_path = GameContext.LEVELS["level10"]
	get_tree().change_scene_to_file(GameContext.PRESENTATION_PATH)
	await _frames(2)
	var knight := _player()
	var nest := _world().get_node("Props/EmberNestArena") as EmberNest
	knight.position = LevelSanity.feet_of(nest) - Vector2(6, 2)
	_world().get_node("Props/ArenaGate").free()
	_fixture_start = {"position": str(knight.position), "hp": knight.health.current,
		"max_hp": knight.health.max_hp, "attack": knight.melee.damage,
		"omitted_initial_gate": "ArenaGate", "granted_items": [], "granted_flags": []}
	if not await _wait_world(): return
	await _tap(&"interact")
	await _frames(8)
	if not _require(SaveData.last_lit_nest().ends_with("EmberNestArena"), "fixture checkpoint lit through interact"): return
	_fixture_start["checkpoint_hp"] = _player().health.current
	_fixture_start["started_with_nightmare_dead"] = SaveData.has_flag("nightmare_dead")
	_record("local_fixture_checkpoint")
	if not await _nightmare(): return
	for milestone in ["nightmare_phase_one", "nightmare_phase_two", "nightmare_phase_three", "nightmare_slain", "nightmare_death_reload_verified", "level10_continue"]:
		var found := false
		for record in _records:
			if record.milestone == milestone: found = true
		if not _require(found, "local fixture observed " + milestone): return
	_write_result(true)
	get_tree().quit(0)


func _write_result(passed: bool) -> void:
	var report := {"passed": passed, "scope": "LOCAL FINALE FIXTURE; NOT FULL CAMPAIGN",
		"full_campaign": false, "input_only_after_fixture_setup": true,
		"fixture_setup": _fixture_start, "assists": {"incoming": Settings.assist(&"assist_incoming"),
			"parry": Settings.assist(&"assist_parry"), "toxin": Settings.assist(&"assist_toxin")},
		"milestones": _records, "deaths": _deaths, "engine_errors": Array(_errors.errors()),
		"nightmare_dead": SaveData.has_flag("nightmare_dead"),
		"boss_absent": _world() != null and _world().get_node_or_null("Enemies/Nightmare") == null,
		"failure_step": _step if not passed else "", "rendered": _rendered}
	var file := FileAccess.open("user://nightmare_input_fixture.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("[LOCAL NIGHTMARE FIXTURE] ", JSON.stringify(report))
