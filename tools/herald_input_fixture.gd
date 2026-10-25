extends "res://tools/campaign_walkthrough.gd"
## LOCAL HERALD CHECKPOINT REPLAY; NOT A FULL CAMPAIGN RUN.
## The runner copies the existing legal campaign save byte-for-byte to isolated
## APPDATA. This fixture uses title Continue and ordinary inputs only; no staging,
## actors, HP, equipment, gates or story flags are modified.

var _fixture_start := {}
var _combat_evidence := {"melee_hits": 0, "reflected_hits": 0, "damage": 0, "yanks": -1}
var _hit_boss_id := 0


func _run() -> void:
	Settings.set_value(&"assist_incoming", 0.5, false)
	Settings.set_value(&"assist_parry", 1.5, false)
	Settings.set_value(&"assist_toxin", 0.5, false)
	get_tree().change_scene_to_file(TITLE)
	await _frames(6)
	if not _require(SaveData.has_save(), "isolated legal campaign checkpoint exists"): return
	await _title_continue()
	if not await _wait_world(): return
	if not _require(GameContext.level_id_of(_player()) == "level09b", "legal checkpoint restores level09b"): return
	if not _require(not SaveData.has_flag("herald_dead"), "Herald starts alive"): return
	var knight := _player()
	_fixture_start = {"position": str(knight.position), "hp": knight.health.current,
		"max_hp": knight.health.max_hp, "attack": knight.melee.damage,
		"heat_forge": knight.inventory.has_ability(AbilityIds.HEAT_FORGE),
		"hook": knight.inventory.has_ability(AbilityIds.HOOKSHOT_TETHER),
		"extra_jump": knight.inventory.has_ability(AbilityIds.EMBER_STEP),
		"last_lit_nest": SaveData.last_lit_nest()}
	if not _require(_fixture_start.heat_forge and not _fixture_start.hook and not _fixture_start.extra_jump, "uses only basic jump/dash and real heat forge"): return
	_record("herald_legal_checkpoint")
	GameEvents.hit.connect(func(attacker: Node, target: Node, amount: int) -> void:
		if is_instance_valid(target) and String(target.name) == "EmberwindHerald":
			if target.get_instance_id() != _hit_boss_id:
				_hit_boss_id = target.get_instance_id()
				_combat_evidence = {"melee_hits": 0, "reflected_hits": 0, "damage": 0, "yanks": -1}
			_combat_evidence.damage += amount
			_combat_evidence.yanks = target.yank_count()
			if attacker is Projectile and attacker.deflected:
				_combat_evidence.reflected_hits += 1
			elif attacker is Hitbox and attacker.team == &"player":
				_combat_evidence.melee_hits += 1)
	var exit := _world().get_node("Props/Exit") as LevelExit
	if not await _clear_gate_boss(exit): return
	if not _require(SaveData.has_flag("herald_dead") and _gate_boss() == null, "real Herald kill clears gate"): return
	if not _require(_combat_evidence.yanks == 0 and _combat_evidence.melee_hits > 0, "real sword hits without hook yanks"): return
	if not await _continue_round_trip("level09b"): return
	if not _require(SaveData.has_flag("herald_dead") and _gate_boss() == null, "Herald remains absent after Continue"): return
	_record("herald_continue_absence_verified")
	exit = _world().get_node("Props/Exit") as LevelExit
	if not await _navigate(LevelSanity.feet_of(exit) - Vector2(12, 0)): return
	await _tap(&"interact")
	if not await _await_scene(GameContext.LEVELS["level10"]): return
	_record("herald_exit_to_level10")
	_write_result(true)
	get_tree().quit(0)


func _record(name_: String) -> void:
	super(name_)
	if _rendered and not name_.begins_with("level"):
		get_tree().root.get_texture().get_image().save_png("user://%s_%s.png" % [_ending, name_])


func _write_result(passed: bool) -> void:
	var report := {"passed": passed, "scope": "LOCAL HERALD CHECKPOINT REPLAY; NOT FULL CAMPAIGN",
		"full_campaign": false, "input_only": true, "fixture_setup": _fixture_start,
		"combat_evidence": _combat_evidence,
		"herald_dead": SaveData.has_flag("herald_dead"), "milestones": _records,
		"deaths": _deaths, "engine_errors": Array(_errors.errors()),
		"failure_step": _step if not passed else "", "rendered": _rendered}
	var file := FileAccess.open("user://herald_input_fixture.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("[LOCAL HERALD FIXTURE] ", JSON.stringify(report))
