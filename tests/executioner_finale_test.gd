extends TestCase
## TEMP probe (deleted after verification): exercise the Executioner phase-2 finale
## (20% HP one-shot climax) end-to-end: trigger, wave / grab / pillar, single warning.

const BOSS_SCENE := preload("res://scenes/enemies/ExecutionerBoss.tscn")


func setup() -> void:
	SaveData.flags.clear()
	Director.abort()
	Director.resume()


func teardown() -> void:
	Director.abort()
	Director.resume()
	SaveData.flags.clear()


func _spawn(arena: Node2D) -> ExecutionerBoss:
	var boss := BOSS_SCENE.instantiate() as ExecutionerBoss
	boss.position = Vector2(320, 0)
	arena.add_child(boss)
	await flush(2)
	boss.set_physics_process(false)
	return boss


func _tick(boss: ExecutionerBoss, seconds: float, step: float = 0.05) -> void:
	var left := seconds
	while left > 0.0:
		var dt := minf(step, left)
		boss._tick_state(dt)
		left -= dt


func test_finale_triggers_at_twenty_percent_and_runs_its_three_moves() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena, Vector2(360, -24))
	player.set_physics_process(false)
	var boss := await _spawn(arena)
	var lines: Array = []
	GameEvents.announcement.connect(func(text: String) -> void: lines.append(text))
	player.global_position = Vector2(560, -24)
	boss.health.take_damage(7, null)  # 6/13 -> phase 2
	_tick(boss, 2.4)  # 让可能已经起手的斩收完，回到 BLOCK
	ok(boss.is_enraged(), "phase 2 at half HP")
	ok(not boss._final_stand, "finale not before 20%")
	boss.health._hit_iframe = 0.0
	boss.health.take_damage(4, null)  # 2/13 <= 20%
	ok(boss._final_stand, "<=20% HP starts the furnace finale")
	ok(lines.has("炉膛裂了。他不再收斧。"), "finale announces itself")
	var kit := boss.boss_kit()
	var ids: Array = []
	for entry in kit.attack_pool():
		ids.append(String(entry.id))
		ok(kit.windup_for(entry, 2) >= 0.35, "%s windup >= 0.35s in phase 2" % entry.id)
	for required in ["ground_wave", "execution_grab", "furnace_pillar"]:
		ok(ids.has(required), "finale move %s is documented in the kit" % required)
	# 1st finale move: far away -> ground wave
	player.global_position = Vector2(560, -24)
	boss._final_cd = 0.0
	var before := CombatMarker.live
	boss._tick_state(0.02)  # BLOCK tick -> pick a finale move
	ok(boss._final_phase == 1, "finale move starts in windup")
	eq(String(boss._final_id), "ground_wave", "far knight -> ground wave")
	ok(CombatMarker.live <= before + 1, "exactly one finale warning")
	_tick(boss, 0.7)  # windup -> active spawns the two waves
	var waves := 0
	for child in arena.find_children("*", "", true, false):
		if child is ExecutionerBoss.FurnaceWave:
			waves += 1
	ok(waves >= 2, "ground wave spawns two fire waves (%d)" % waves)
	_tick(boss, 0.8)  # let the move + waves finish
	for i in 60:
		if boss._final_phase == 0:
			break
		boss._tick_state(0.05)
	# 2nd finale move: close -> execution grab with a big readable warning
	player.global_position = Vector2(350, -24)
	boss._final_cd = 0.0
	for i in 40:
		boss._tick_state(0.05)
		if boss._final_phase != 0:
			break
	eq(String(boss._final_id), "execution_grab", "close knight -> execution grab")
	_tick(boss, 1.0)  # windup done -> active
	ok(boss._final_phase == 2, "grab lands")
	_tick(boss, 1.0)  # recovery -> idle
	# 3rd finale move: forced pillar (cursor odd)
	player.global_position = Vector2(560, -24)
	boss._pillar_cursor = 1
	boss._final_cd = 0.0
	for i in 60:
		boss._tick_state(0.05)
		if boss._final_phase != 0:
			break
	eq(String(boss._final_id), "furnace_pillar", "pillar move selected")
	ok(boss._pillar_spots.size() >= 1, "pillar spots are staged in the arena")
	_tick(boss, 0.65)
	var pillars := 0
	for child in arena.find_children("*", "", true, false):
		if child is ExecutionerBoss.FurnacePillar:
			pillars += 1
	ok(pillars >= 1, "a furnace pillar erupts (%d)" % pillars)
	arena.queue_free()
	await flush(2)
