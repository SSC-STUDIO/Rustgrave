extends TestCase
## Red AI hero: id queries, target priority, deterministic behaviour, respawn, and the
## "an idle player loses" acceptance check (a match must be losable, not only winnable).
## Headless and scene-free; only public commands are used to drive the player hero.

const SIM_SCRIPT := preload("res://scripts/moba/sim/moba_sim.gd")
const KIND_HERO := &"hero"
const KIND_MINION := &"minion"
const KIND_TOWER := &"tower"
const KIND_CRYSTAL := &"crystal"
const TEAM_BLUE := 0
const TEAM_RED := 1


func _new_sim(seed: int):
	return SIM_SCRIPT.new(seed)


func _step_many(sim, ticks: int) -> void:
	for i in ticks:
		sim.step()


func _find_entity(sim, entity_id: int) -> Dictionary:
	for entity in sim.entities():
		if int(entity["id"]) == entity_id:
			return entity
	return {}


func _entities_of_team(sim, kind: StringName, team: int) -> Array:
	var matches := []
	for entity in sim.entities():
		if entity["kind"] == kind and int(entity["team"]) == team:
			matches.append(entity)
	return matches


func _structure(sim, team: int, kind: StringName) -> Dictionary:
	for structure in sim.structures(team):
		if structure["kind"] == kind:
			return structure
	return {}


func _internal_entity(sim, entity_id: int) -> Dictionary:
	for entity in sim._entities:
		if int(entity["id"]) == entity_id:
			return entity
	return {}


func _teleport(sim, entity_id: int, x_mm: int, y_mm: int) -> void:
	_internal_entity(sim, entity_id)["pos"] = Vector2i(x_mm, y_mm)


func test_hero_id_queries_cover_both_teams() -> void:
	var sim = _new_sim(1)
	eq(sim.hero_id(), sim.hero_id(TEAM_BLUE), "the no-argument query is the blue hero")
	eq(sim.enemy_hero_id(), sim.hero_id(TEAM_RED))
	eq(sim.hero_id(9), -1, "unknown teams have no hero")
	ok(sim.hero_id() != sim.enemy_hero_id())
	var enemy_hero: Dictionary = _find_entity(sim, sim.enemy_hero_id())
	eq(enemy_hero["kind"], KIND_HERO)
	eq(enemy_hero["team"], TEAM_RED)
	eq(enemy_hero["hp"], 600)
	eq(enemy_hero["max_hp"], 600)
	eq(enemy_hero["alive"], true)
	almost(enemy_hero["pos"].x, 28.0, 0.001, "the AI hero starts at the red base")
	almost(enemy_hero["pos"].y, 0.0, 0.001)


func test_red_ai_attacks_minions_before_a_tower_in_range() -> void:
	var sim = _new_sim(4)
	_step_many(sim, 150)  # first wave exists; the AI hero is around the lane centre
	var enemy_id: int = sim.enemy_hero_id()
	var blue_minion: Dictionary = _entities_of_team(sim, KIND_MINION, TEAM_BLUE)[1]
	_teleport(sim, enemy_id, -14000, 0)
	_teleport(sim, blue_minion["id"], -13000, 0)
	sim.step()
	eq(_find_entity(sim, blue_minion["id"])["hp"], 245,
			"the AI hero attacks the blue minion first")
	eq(_structure(sim, TEAM_BLUE, KIND_TOWER)["hp"], 1200,
			"the blue tower is not attacked while a minion is in range")
	# 600 - 40 (tower shot) - 18 (the blue minion retaliates).
	eq(_find_entity(sim, enemy_id)["hp"], 542, "the blue tower and minion shoot back")


func test_red_ai_behaviour_is_deterministic() -> void:
	var first = _new_sim(7)
	var second = _new_sim(7)
	var mismatched := 0
	var tick := 0
	while tick < 3000:
		first.step()
		second.step()
		if first.state_hash() != second.state_hash():
			mismatched += 1
		tick += 1
	eq(mismatched, 0, "the AI must be a pure function of the state: per-tick hashes match")
	eq(first.state_hash(), second.state_hash())
	eq(first.outcome(), second.outcome())
	eq(first.outcome(), &"red", "an idle player loses, so both runs already finished")


func test_red_ai_hero_respawns_at_the_red_base() -> void:
	var sim = _new_sim(2)
	var enemy_id: int = sim.enemy_hero_id()
	_internal_entity(sim, enemy_id)["hp"] = 0
	sim.step()
	var enemy_hero: Dictionary = _find_entity(sim, enemy_id)
	eq(enemy_hero["alive"], false)
	eq(enemy_hero["hp"], 0)
	eq(enemy_hero["anim"], &"dead")
	_step_many(sim, 179)
	eq(_find_entity(sim, enemy_id)["alive"], false, "the 6 s respawn timer has not elapsed")
	sim.step()
	enemy_hero = _find_entity(sim, enemy_id)
	eq(enemy_hero["alive"], true)
	eq(enemy_hero["hp"], 600)
	eq(enemy_hero["max_hp"], 600)
	# The AI walks down the lane again on the revival tick itself.
	almost(enemy_hero["pos"].x, 27.85, 0.001, "the AI hero respawns at the red base")
	almost(enemy_hero["pos"].y, 0.0, 0.001)
	eq(enemy_hero["facing"], -1)


func test_idle_player_loses_to_the_red_ai_and_the_match_freezes() -> void:
	var sim = _new_sim(7)
	var ticks := 0
	while sim.outcome() == &"" and ticks < 20000:
		sim.step()
		ticks += 1
	print("[moba_sim] idle player loss: outcome=", sim.outcome(), " ticks=", ticks,
			" time_ms=", sim.time_ms())
	eq(sim.outcome(), &"red", "an idle player must lose the match")
	ok(ticks < 20000, "the loss happens inside the 20000 tick bound (%d ticks)" % ticks)
	eq(sim.tick_count(), ticks)
	var blue_crystal: Dictionary = _structure(sim, TEAM_BLUE, KIND_CRYSTAL)
	eq(blue_crystal["alive"], false, "the red AI destroys the blue crystal")
	eq(blue_crystal["hp"], 0)
	eq(blue_crystal["anim"], &"dead")
	eq(_structure(sim, TEAM_BLUE, KIND_TOWER)["alive"], false)
	eq(sim.hero_state()["can_act"], false)
	var frozen_hash: int = sim.state_hash()
	var frozen_tick: int = sim.tick_count()
	_step_many(sim, 10)
	eq(sim.tick_count(), frozen_tick, "the defeated match is frozen")
	eq(sim.state_hash(), frozen_hash)
