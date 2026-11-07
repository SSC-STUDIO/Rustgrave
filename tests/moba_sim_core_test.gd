extends TestCase
## Deterministic core of MobaSim: frozen API, per-tick hashes, command recording and
## replay, wave scheduling, deep-copied snapshots, reset/seed handling. Headless and
## scene-free (the simulation is a plain RefCounted script).

const SIM_SCRIPT := preload("res://scripts/moba/sim/moba_sim.gd")
const KIND_HERO := &"hero"
const KIND_MINION := &"minion"
const KIND_TOWER := &"tower"
const KIND_CRYSTAL := &"crystal"
const TEAM_BLUE := 0
const TEAM_RED := 1


func _new_sim(seed: int):
	return SIM_SCRIPT.new(seed)


func _find_entity(sim, entity_id: int) -> Dictionary:
	for entity in sim.entities():
		if int(entity["id"]) == entity_id:
			return entity
	return {}


func _entities_of_kind(sim, kind: StringName) -> Array:
	var matches := []
	for entity in sim.entities():
		if entity["kind"] == kind:
			matches.append(entity)
	return matches


func _entities_of_team(sim, kind: StringName, team: int) -> Array:
	var matches := []
	for entity in sim.entities():
		if entity["kind"] == kind and int(entity["team"]) == team:
			matches.append(entity)
	return matches


## Test seam: park the red AI hero so a rule can be tested without its pressure.
func _park_enemy_hero(sim) -> void:
	for entity in sim._entities:
		if entity["kind"] == KIND_HERO and int(entity["team"]) == TEAM_RED:
			entity["alive"] = false
			entity["hp"] = 0
			entity["respawn_tick"] = 1 << 30
			return


func _scripted_commands(sim, tick: int) -> void:
	match tick % 120:
		0:
			sim.set_move(Vector2(1, 0))
		40:
			sim.set_move(Vector2(-0.4, 0.8))
		70:
			sim.command_attack(-1)
		100:
			sim.set_move(Vector2(0, -1))


func _recorded_commands(tick: int) -> Array:
	var commands: Array = []
	match tick % 120:
		0:
			commands.append({"kind": 0, "value": Vector2(1, 0)})
		40:
			commands.append({"kind": 0, "value": Vector2(-0.4, 0.8)})
		70:
			commands.append({"kind": 1, "value": -1})
		100:
			commands.append({"kind": 0, "value": Vector2(0, -1)})
	return commands


func test_initial_state_matches_the_frozen_contract() -> void:
	var sim = _new_sim(7)
	eq(sim.tick_count(), 0)
	eq(sim.time_ms(), 0)
	eq(sim.outcome(), &"")
	ok(sim.hero_id() >= 0, "the player hero has an id")
	eq(sim.wave_index(), 0)
	eq(sim.next_wave_ms(), 5000)
	var entities: Array = sim.entities()
	eq(entities.size(), 6, "two towers, two crystals and two heroes")
	var hero: Dictionary = _find_entity(sim, sim.hero_id())
	eq(hero["kind"], KIND_HERO)
	eq(hero["team"], TEAM_BLUE)
	eq(hero["hp"], 600)
	eq(hero["max_hp"], 600)
	eq(hero["alive"], true)
	eq(hero["anim"], &"idle")
	eq(hero["facing"], 1)
	almost(hero["pos"].x, -28.0, 0.001, "blue base at lane x = -28 m")
	almost(hero["pos"].y, 0.0)
	eq(sim.hero_id(), sim.hero_id(TEAM_BLUE))
	eq(sim.enemy_hero_id(), sim.hero_id(TEAM_RED))
	eq(sim.hero_id(9), -1, "unknown teams have no hero")
	ok(sim.hero_id() != sim.hero_id(TEAM_RED), "the two heroes have distinct ids")
	var enemy_hero: Dictionary = _find_entity(sim, sim.hero_id(TEAM_RED))
	eq(enemy_hero["kind"], KIND_HERO)
	eq(enemy_hero["team"], TEAM_RED)
	eq(enemy_hero["hp"], 600)
	eq(enemy_hero["alive"], true)
	eq(enemy_hero["facing"], -1)
	almost(enemy_hero["pos"].x, 28.0, 0.001, "red AI hero starts at the red base")
	almost(enemy_hero["pos"].y, 0.0)
	var blue_structures: Array = sim.structures(TEAM_BLUE)
	eq(blue_structures.size(), 2)
	var blue_tower := _structure_of(blue_structures, KIND_TOWER)
	eq(blue_tower["team"], TEAM_BLUE)
	eq(blue_tower["hp"], 1200)
	almost(blue_tower["pos"].x, -16.0, 0.001)
	var blue_crystal := _structure_of(blue_structures, KIND_CRYSTAL)
	eq(blue_crystal["hp"], 2400)
	almost(blue_crystal["pos"].x, -26.0, 0.001)
	var red_structures: Array = sim.structures(TEAM_RED)
	eq(red_structures.size(), 2)
	almost(_structure_of(red_structures, KIND_TOWER)["pos"].x, 16.0, 0.001)
	almost(_structure_of(red_structures, KIND_CRYSTAL)["pos"].x, 26.0, 0.001)
	var hero_state: Dictionary = sim.hero_state()
	eq(hero_state["hp"], 600)
	eq(hero_state["max_hp"], 600)
	eq(hero_state["alive"], true)
	eq(hero_state["can_act"], true)
	eq(hero_state["respawn_remaining_ms"], 0)
	eq(hero_state["attack_target"], -1)


func _structure_of(structures: Array, kind: StringName) -> Dictionary:
	for structure in structures:
		if structure["kind"] == kind:
			return structure
	return {}


func test_commands_take_effect_on_the_next_step() -> void:
	var sim = _new_sim(3)
	var hero_id: int = sim.hero_id()
	sim.set_move(Vector2(1, 0))
	almost(_find_entity(sim, hero_id)["pos"].x, -28.0, 0.001,
			"a buffered move does not move the hero before the next step")
	sim.step()
	almost(_find_entity(sim, hero_id)["pos"].x, -27.85, 0.001,
			"hero speed 4.5 m/s = 150 mm per 1/30 s tick")
	eq(sim.tick_count(), 1)
	eq(sim.time_ms(), 33)
	sim.set_move(Vector2.ZERO)
	var stopped_x: float = _find_entity(sim, hero_id)["pos"].x
	sim.step()
	almost(_find_entity(sim, hero_id)["pos"].x, stopped_x, 0.001, "a zero vector stops")
	sim.command_attack(-1)
	sim.step()
	eq(sim.hero_state()["attack_target"], -1, "no enemy is in range at the base")


func test_same_seed_and_commands_keep_identical_hash_every_tick() -> void:
	var first = _new_sim(20261031)
	var second = _new_sim(20261031)
	var initial_hash: int = first.state_hash()
	var mismatched := 0
	var tick := 0
	while tick < 600:
		_scripted_commands(first, tick)
		_scripted_commands(second, tick)
		first.step()
		second.step()
		if first.state_hash() != second.state_hash():
			mismatched += 1
		tick += 1
	eq(mismatched, 0, "600 ticks of identical commands must hash identically")
	eq(first.tick_count(), 600)
	eq(second.tick_count(), 600)
	eq(first.state_hash(), second.state_hash())
	eq(first.outcome(), second.outcome())
	ok(first.state_hash() != initial_hash, "the hash covers advancing state")


func test_recorded_commands_replay_to_the_same_state() -> void:
	var live = _new_sim(424242)
	var recording: Array = []
	var tick := 1
	while tick <= 900:
		for command in _recorded_commands(tick):
			recording.append({
				"tick": tick,
				"kind": int(command["kind"]),
				"value": command["value"],
			})
			if int(command["kind"]) == 0:
				live.set_move(command["value"])
			else:
				live.command_attack(int(command["value"]))
		live.step()
		tick += 1
	ok(recording.size() > 10, "the recording captured the scripted commands")
	var replay = _new_sim(424242)
	var index := 0
	tick = 1
	while tick <= 900:
		while index < recording.size() and int(recording[index]["tick"]) == tick:
			var entry: Dictionary = recording[index]
			if int(entry["kind"]) == 0:
				replay.set_move(entry["value"])
			else:
				replay.command_attack(int(entry["value"]))
			index += 1
		replay.step()
		tick += 1
	eq(index, recording.size())
	eq(replay.tick_count(), live.tick_count())
	eq(replay.state_hash(), live.state_hash(), "replay reproduces the exact state")
	eq(replay.outcome(), live.outcome())
	eq(replay.entities().size(), live.entities().size())


func test_waves_spawn_at_five_seconds_then_every_twenty() -> void:
	var sim = _new_sim(11)
	_park_enemy_hero(sim)
	eq(sim.wave_index(), 0)
	eq(sim.next_wave_ms(), 5000)
	for i in 149:
		sim.step()
	eq(sim.tick_count(), 149)
	eq(sim.wave_index(), 0)
	eq(_entities_of_kind(sim, KIND_MINION).size(), 0)
	sim.step()
	eq(sim.tick_count(), 150)
	eq(sim.time_ms(), 5000)
	eq(sim.wave_index(), 1)
	eq(sim.next_wave_ms(), 25000)
	var first_wave: Array = _entities_of_kind(sim, KIND_MINION)
	eq(first_wave.size(), 6, "three minions per side")
	var blue_minions := _entities_of_team(sim, KIND_MINION, TEAM_BLUE)
	var red_minions := _entities_of_team(sim, KIND_MINION, TEAM_RED)
	eq(blue_minions.size(), 3)
	eq(red_minions.size(), 3)
	for minion in first_wave:
		eq(minion["hp"], 300)
		eq(minion["max_hp"], 300)
		eq(minion["alive"], true)
		# Spawn at the base, then the same tick already advances one 100 mm minion step.
		if int(minion["team"]) == TEAM_BLUE:
			ok(minion["pos"].x >= -27.96 and minion["pos"].x <= -27.84,
					"blue minions spawn at their base")
		else:
			ok(minion["pos"].x >= 27.84 and minion["pos"].x <= 27.96,
					"red minions spawn at their base")
	for i in 600:
		sim.step()
	eq(sim.tick_count(), 750)
	eq(sim.wave_index(), 2)
	eq(sim.next_wave_ms(), 45000)
	eq(_entities_of_kind(sim, KIND_MINION).size(), 12, "wave 1 is still fighting")
	for i in 600:
		sim.step()
	eq(sim.tick_count(), 1350)
	eq(sim.wave_index(), 3)
	eq(sim.next_wave_ms(), 65000)
	eq(_entities_of_kind(sim, KIND_MINION).size(), 12,
			"wave 1 died, wave 2 fights, wave 3 just spawned")


func test_entities_and_structures_are_deep_copies() -> void:
	var sim = _new_sim(5)
	var before: int = sim.state_hash()
	var snapshot: Array = sim.entities()
	eq(snapshot.size(), 6)
	snapshot[0]["hp"] = 12345
	snapshot[0]["pos"] = Vector2(99.0, 99.0)
	snapshot[0]["anim"] = &"dead"
	snapshot.append({"id": -1})
	var structures: Array = sim.structures(TEAM_BLUE)
	eq(structures.size(), 2)
	structures[0]["hp"] = 1
	eq(sim.state_hash(), before, "mutating returned dictionaries cannot change the simulation")
	var fresh: Array = sim.entities()
	eq(fresh.size(), 6)
	eq(fresh[0]["hp"], 1200)
	ok(fresh[0]["pos"].x != 99.0)
	ok(fresh[0]["anim"] != &"dead")
	eq(sim.structures(TEAM_BLUE)[0]["hp"], 1200)
	eq(sim.structures(TEAM_RED).size(), 2)


func test_reset_restarts_the_current_seed_and_accepts_a_new_one() -> void:
	var sim = _new_sim(98765)
	var initial_hash: int = sim.state_hash()
	for i in 120:
		sim.step()
	ok(sim.state_hash() != initial_hash)
	sim.reset()
	eq(sim.tick_count(), 0)
	eq(sim.time_ms(), 0)
	eq(sim.outcome(), &"")
	eq(sim.wave_index(), 0)
	eq(sim.entities().size(), 6)
	eq(sim.state_hash(), initial_hash, "reset() keeps the current seed for replays")
	var other = _new_sim(111)
	sim.reset(111)
	eq(sim.state_hash(), other.state_hash(), "reset(seed) reseeds deterministically")


func test_different_seeds_only_jitter_spawn_positions() -> void:
	var first = _new_sim(1)
	var second = _new_sim(2)
	_park_enemy_hero(first)
	_park_enemy_hero(second)
	for i in 600:
		first.step()
		second.step()
	eq(first.tick_count(), second.tick_count())
	eq(first.wave_index(), second.wave_index())
	eq(first.outcome(), second.outcome(), "seeds must not change the rules")
	var first_entities: Array = first.entities()
	var second_entities: Array = second.entities()
	eq(first_entities.size(), 12, "six structures/heroes plus the first wave")
	eq(second_entities.size(), first_entities.size())
	for entity_index in first_entities.size():
		var first_entity: Dictionary = first_entities[entity_index]
		var second_entity: Dictionary = second_entities[entity_index]
		eq(first_entity["id"], second_entity["id"], "entity ids stay in sync")
		eq(first_entity["kind"], second_entity["kind"])
		eq(first_entity["hp"], second_entity["hp"],
				"seeded jitter must not change damage or combat timing")
		almost(first_entity["pos"].x, second_entity["pos"].x, 0.15,
				"spawn jitter stays tiny")
		almost(first_entity["pos"].y, second_entity["pos"].y, 0.001)
	eq(first.structures(TEAM_BLUE)[0]["hp"], 1200)
	eq(second.structures(TEAM_RED)[1]["hp"], 2400)
	ok(first.state_hash() != second.state_hash(),
			"the seed still shifts positions, so the hashes differ")
