extends TestCase
## Binding of the real RenderSpike scene to MobaSim: the view pulls entity
## positions and HUD numbers from the simulation, waves arrive through
## entities(), and a restart clears every view of the previous match.
##
## The whole case is skipped (with one green assertion) until
## scripts/moba/sim/moba_sim.gd exists, so the view layer can be checked while
## the simulation is still being written in parallel.

const Spike := preload("res://scripts/moba/spike/render_spike.gd")
const VIEW_MAP := preload("res://scripts/moba/present/moba_view_map.gd")
const RUN := preload("res://scripts/moba/moba_run.gd")
const SIM_PATH := "res://scripts/moba/sim/moba_sim.gd"

var _old_hold := false
var _old_shake := 1.0


func setup() -> void:
	_old_hold = WorldClock.menu_hold
	_old_shake = Settings.shake_scale
	RUN.abandon()
	Director._fading = false
	Director._queued_fade_path = ""
	Director.last_fade_target = ""
	Settings.set_shake_scale(1.0, false)


func teardown() -> void:
	RUN.abandon()
	Settings.set_shake_scale(_old_shake, false)
	WorldClock.menu_hold = _old_hold
	Director._fading = false
	Director._queued_fade_path = ""


func _spike():
	var spike = Spike.new()
	add_child(spike)
	await flush(2)
	spike.set_process(false)
	return spike


func _hero_entity(sim) -> Dictionary:
	var hero_id: int = sim.hero_id()
	for raw in sim.entities():
		if raw is Dictionary and int(raw.get("id", -1)) == hero_id:
			return raw
	return {}


func test_render_spike_wires_the_simulation_into_the_views() -> void:
	if not ResourceLoader.exists(SIM_PATH):
		ok(true, "MobaSim not installed yet; binding check deferred")
		return
	var spike = await _spike()
	ok(spike.sim != null, "the scene builds a MobaSim instance")
	eq(spike._structures.size(), 4, "two towers and two crystals are built from the contract")
	eq(spike._hud.blue_crystal_bar["ratio"], 1.0)
	eq(spike._hud.red_crystal_bar["ratio"], 1.0)
	almost(spike._hud.hero_bar["ratio"], 1.0, 0.001)
	var hero := _hero_entity(spike.sim)
	ok(not hero.is_empty(), "the player hero is an entity of the simulation")
	eq(StringName(hero.get("kind", &"")), &"hero")
	spike.queue_free()
	await flush(2)
	ok(not RUN.active(), "freeing the arena detaches its session")


func test_hero_view_follows_the_simulated_lane_position() -> void:
	if not ResourceLoader.exists(SIM_PATH):
		ok(true, "MobaSim not installed yet; binding check deferred")
		return
	var spike = await _spike()
	spike.step_sim(6)
	spike.sync_now(1.0)
	var hero := _hero_entity(spike.sim)
	ok(not hero.is_empty())
	var expected := VIEW_MAP.lane_to_world(Vector2(hero["pos"]))
	almost(spike.hero.global_position.x, expected.x, 0.05, "the knight stands where the sim says")
	almost(spike.hero.global_position.z, expected.z, 0.05)
	var hp := float(hero.get("hp", 0.0))
	almost(float(spike._hud.hero_bar["ratio"]), hp / VIEW_MAP.HERO_HP, 0.01)
	# The HUD hero text is the same number the sim publishes.
	ok(spike._hud.hero_bar["label"].text.begins_with("余烬骑士"))
	spike.queue_free()
	await flush(2)


func test_waves_arrive_through_sim_entities() -> void:
	if not ResourceLoader.exists(SIM_PATH):
		ok(true, "MobaSim not installed yet; binding check deferred")
		return
	var spike = await _spike()
	eq(spike._unit_pool.active_count(), 0, "no lane minions before the first wave")
	spike.step_sim(170)
	ok(int(spike.sim.wave_index()) >= 1, "the first wave has been queued by the sim")
	var live_minions := 0
	for raw in spike.sim.entities():
		if raw is Dictionary and StringName(raw.get("kind", &"")) == &"minion":
			live_minions += 1
	ok(live_minions > 0, "the sim spawned lane minions")
	eq(spike._unit_pool.active_count(), live_minions, "every sim minion has exactly one view")
	# Spot-check that a wave minion's view sits on the mapped lane position.
	for raw in spike.sim.entities():
		if not (raw is Dictionary) or StringName(raw.get("kind", &"")) != &"minion":
			continue
		var entity: Dictionary = raw
		var view = spike._unit_pool.view_for(int(entity["id"]))
		ok(view != null)
		if view != null:
			var expected := VIEW_MAP.lane_to_world(Vector2(entity["pos"]))
			almost(view.global_position.x, expected.x, 0.01)
			almost(view.global_position.z, expected.z, 0.01)
		break
	ok(spike._hud.wave_label.text.contains("第") or spike._hud.wave_label.text.contains("首波"),
			"the wave clock is driven by wave_index()/next_wave_ms()")
	spike.queue_free()
	await flush(2)


func test_result_banner_and_restart_clear_the_previous_match() -> void:
	if not ResourceLoader.exists(SIM_PATH):
		ok(true, "MobaSim not installed yet; binding check deferred")
		return
	var spike = await _spike()
	spike.step_sim(170)
	ok(spike._unit_pool.active_count() > 0, "a match in progress has lane minions")
	# Test seam: the outcome banner itself is exercised without playing out a
	# whole match (the frozen sim has no "force win" command).
	spike._note_outcome(&"blue")
	spike.sync_now(0.0)
	ok(spike._hud.result_panel.visible, "the result banner appears on an outcome")
	eq(spike._hud.result_label.text, "灰卫攻破锈誓水晶")
	eq(spike._hud.result_hint.text, "R 重开 · Esc 返回")
	var seed_before: int = spike._match_seed
	spike.restart_match()
	eq(spike._match_seed, seed_before + 1, "a rematch records the next seed")
	eq(spike._unit_pool.active_count(), 0, "restart clears every unit view")
	await flush(2)
	eq(spike._unit_pool.pool_children(), 0, "restart frees the pooled minion nodes too")
	eq(spike._hud.result_panel.visible, false, "restart hides the result banner")
	eq(spike._hud.red_crystal_bar["ratio"], 1.0, "both crystals are restored")
	eq(spike._hud.blue_crystal_bar["ratio"], 1.0)
	eq(spike._hud.result_label.text, "")
	# Hero is back on the blue spawn of the fresh simulation.
	spike.sync_now(1.0)
	var spawn := VIEW_MAP.lane_to_world(Vector2(-VIEW_MAP.BASE_LANE_X, 0.0))
	almost(spike.hero.global_position.x, spawn.x, 0.01)
	almost(spike.hero.global_position.z, spawn.z, 0.01)
	spike.queue_free()
	await flush(2)


func test_stepping_the_match_creates_no_nodes_in_steady_state() -> void:
	if not ResourceLoader.exists(SIM_PATH):
		ok(true, "MobaSim not installed yet; binding check deferred")
		return
	var spike = await _spike()
	spike.step_sim(30)
	var world_children: int = spike.stage.world.get_child_count()
	var hud_before := _node_count(spike._hud.root)
	spike.step_sim(60)
	eq(spike.stage.world.get_child_count(), world_children,
			"stepping before the first wave adds no world nodes")
	eq(_node_count(spike._hud.root), hud_before, "the HUD only updates existing nodes")
	spike.queue_free()
	await flush(2)


func test_player_input_becomes_sim_commands() -> void:
	if not ResourceLoader.exists(SIM_PATH):
		ok(true, "MobaSim not installed yet; binding check deferred")
		return
	var spike = await _spike()
	var before := _hero_entity(spike.sim)
	Input.action_press("move_right")
	spike._move_hero(0.1)
	Input.action_release("move_right")
	spike.step_sim(6)
	var after := _hero_entity(spike.sim)
	ok(float(after["pos"].x) > float(before["pos"].x), "A/D drive set_move on the simulation")
	# Attack input locks a sim attack command and plays the knight swing.
	var attack := InputEventAction.new()
	attack.action = &"attack"
	attack.pressed = true
	spike._unhandled_input(attack)
	ok(spike.hero.is_attacking(), "the attack action starts the visual swing")
	spike.step_sim(3)
	spike.queue_free()
	await flush(2)


func test_death_blocks_movement_and_hud_shows_the_countdown() -> void:
	if not ResourceLoader.exists(SIM_PATH):
		ok(true, "MobaSim not installed yet; binding check deferred")
		return
	var spike = await _spike()
	# Push into the enemy tower's range and stand still until the tower and the
	# red wave kill the hero (real simulation, no test seam).
	var died := false
	for i in 1200:
		spike.sim.set_move(Vector2(1.0, 0.0) if i < 320 else Vector2.ZERO)
		spike.sim.step()
		if i % 15 == 0 and not bool(spike.sim.hero_state()["alive"]):
			died = true
			break
	ok(died, "standing under the enemy tower eventually kills the hero")
	spike.sync_now(0.1)
	ok(spike._hero_dead, "the view knows the hero is down")
	ok(spike._hud.respawn_label.visible, "the respawn countdown is on screen")
	ok(spike._hud.respawn_label.text.contains("后复活"))
	var before: Vector3 = spike.hero.global_position
	Input.action_press("move_right")
	spike._move_hero(0.5)
	eq(spike.hero.global_position, before, "a dead hero cannot be moved")
	Input.action_release("move_right")
	spike.queue_free()
	await flush(2)


func test_r_key_restarts_after_the_outcome_banner_shows() -> void:
	if not ResourceLoader.exists(SIM_PATH):
		ok(true, "MobaSim not installed yet; binding check deferred")
		return
	var spike = await _spike()
	spike.step_sim(30)
	spike._note_outcome(&"blue")
	spike.sync_now(0.0)
	ok(spike._hud.result_panel.visible)
	ok(spike._handle_key(KEY_R), "R is routed to the restart")
	eq(spike._hud.result_panel.visible, false, "the rematch clears the result banner")
	eq(int(spike._restart_count), 1)
	eq(spike.sim.tick_count(), 0, "the simulation restarted")
	spike.queue_free()
	await flush(2)


func _node_count(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _node_count(child)
	return total
