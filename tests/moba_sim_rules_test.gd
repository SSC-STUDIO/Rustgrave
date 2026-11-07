extends TestCase
## MobaSim gameplay rules: tower targeting/range/damage cadence, minion duels and
## simultaneous deaths, hero damage/death/respawn, crystal victory and match freeze.
## Headless and scene-free.

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


## Test seam: mutate the live entity dictionary (identity is what the simulation reads).
func _internal_entity(sim, entity_id: int) -> Dictionary:
	for entity in sim._entities:
		if int(entity["id"]) == entity_id:
			return entity
	return {}


func _teleport(sim, entity_id: int, x_mm: int, y_mm: int) -> void:
	_internal_entity(sim, entity_id)["pos"] = Vector2i(x_mm, y_mm)


## Test seam: park the red AI hero so a single rule can be tested without its pressure.
func _park_enemy_hero(sim) -> void:
	for entity in sim._entities:
		if entity["kind"] == KIND_HERO and int(entity["team"]) == TEAM_RED:
			entity["alive"] = false
			entity["hp"] = 0
			entity["respawn_tick"] = 1 << 30
			return


func test_tower_prefers_minions_then_hero_and_respects_its_range() -> void:
	var sim = _new_sim(11)
	_park_enemy_hero(sim)
	_step_many(sim, 150)  # first wave has spawned, nobody is in range yet
	var blue_minion: Dictionary = _entities_of_team(sim, KIND_MINION, TEAM_BLUE)[0]
	var minion_id: int = blue_minion["id"]
	var red_tower: Dictionary = _structure(sim, TEAM_RED, KIND_TOWER)
	var tower_id: int = red_tower["id"]
	_teleport(sim, sim.hero_id(), 15000, 0)
	_teleport(sim, minion_id, 14000, 0)
	sim.step()
	eq(sim.hero_state()["hp"], 600, "the tower shoots the minion, not the hero")
	eq(_find_entity(sim, minion_id)["hp"], 260, "tower damage is 40")
	eq(_find_entity(sim, tower_id)["anim"], &"attack")
	# One shot per second: nothing more lands for the next 29 ticks.
	_step_many(sim, 29)
	eq(_find_entity(sim, minion_id)["hp"], 260)
	sim.step()
	eq(_find_entity(sim, minion_id)["hp"], 220, "a second shot lands 30 ticks later")
	# Minion out of range, hero inside: the tower switches to the hero.
	_teleport(sim, minion_id, -20000, 0)
	_teleport(sim, sim.hero_id(), 15000, 0)
	_step_many(sim, 30)
	eq(sim.hero_state()["hp"], 560, "the hero takes the 40 damage shot")
	eq(_find_entity(sim, minion_id)["hp"], 220,
			"a target out of the 6 m tower range is never shot")


func test_minions_meet_in_the_middle_fight_in_sync_and_die_together() -> void:
	var sim = _new_sim(21)
	_park_enemy_hero(sim)
	_step_many(sim, 600)
	var minions: Array = _entities_of_team(sim, KIND_MINION, TEAM_BLUE)
	minions.append_array(_entities_of_team(sim, KIND_MINION, TEAM_RED))
	eq(minions.size(), 6, "the first wave is still alive at 20 s")
	var duelist_ids: Array = []
	for minion in minions:
		duelist_ids.append(int(minion["id"]))
		eq(minion["hp"], 192, "six 18-damage hits have landed on every duelist")
		eq(minion["alive"], true)
	# Opposing minions walk no further once inside the 1.2 m attack range.
	var positions: Array = []
	for minion in minions:
		positions.append(minion["pos"])
	_step_many(sim, 10)
	minions = _entities_of_team(sim, KIND_MINION, TEAM_BLUE)
	minions.append_array(_entities_of_team(sim, KIND_MINION, TEAM_RED))
	eq(minions.size(), 6)
	for index in duelist_ids.size():
		eq(_find_entity(sim, duelist_ids[index])["pos"], positions[index],
				"fighting minions are stationary")
	# 17th hit kills mirrored duellists on the same tick; the wave is then cleaned up.
	_step_many(sim, 290)  # tick 900
	for entity_id in duelist_ids:
		eq(_find_entity(sim, entity_id)["hp"], 12, "16 hits leave 12 hp on both sides")
		eq(_find_entity(sim, entity_id)["alive"], true)
	_step_many(sim, 5)  # tick 905: both sides land the lethal hit
	for entity_id in duelist_ids:
		ok(_find_entity(sim, entity_id).is_empty(),
				"a dead minion is removed from the simulation")
	var leftover: Array = []
	leftover.append_array(_entities_of_team(sim, KIND_MINION, TEAM_BLUE))
	leftover.append_array(_entities_of_team(sim, KIND_MINION, TEAM_RED))
	eq(leftover.size(), 6, "the second wave is still alive")
	for minion in leftover:
		eq(minion["hp"], 300, "second wave minions are untouched")


func test_hero_hits_for_55_and_minions_hit_for_18() -> void:
	var sim = _new_sim(31)
	_park_enemy_hero(sim)
	_step_many(sim, 150)
	var red_minion: Dictionary = _entities_of_team(sim, KIND_MINION, TEAM_RED)[1]
	var minion_id: int = red_minion["id"]
	_teleport(sim, sim.hero_id(), 0, 0)
	_teleport(sim, minion_id, 1100, 0)
	sim.command_attack(-1)
	sim.step()
	eq(_find_entity(sim, minion_id)["hp"], 245, "hero damage is 55")
	eq(sim.hero_state()["hp"], 582, "the minion retaliates for 18")
	_step_many(sim, 17)
	eq(_find_entity(sim, minion_id)["hp"], 245, "hero attack interval is 0.6 s (18 ticks)")
	sim.step()
	eq(_find_entity(sim, minion_id)["hp"], 190)
	_step_many(sim, 12)  # 30 ticks after the minion's first hit
	eq(sim.hero_state()["hp"], 564, "minion attack interval is 1 s (30 ticks)")


func test_explicit_attack_target_wins_over_auto_acquisition() -> void:
	var sim = _new_sim(41)
	_park_enemy_hero(sim)
	_step_many(sim, 150)
	var red_minions: Array = _entities_of_team(sim, KIND_MINION, TEAM_RED)
	var first_id: int = red_minions[0]["id"]
	var second_id: int = red_minions[1]["id"]
	_teleport(sim, sim.hero_id(), 0, 0)
	_teleport(sim, first_id, 1000, 500)
	_teleport(sim, second_id, -1000, -500)
	sim.command_attack(second_id)
	sim.step()
	eq(_find_entity(sim, first_id)["hp"], 300,
			"an explicit target id overrides the nearer/lower-id auto target")
	eq(_find_entity(sim, second_id)["hp"], 245)


func test_hero_dies_and_respawns_at_the_base_after_six_seconds() -> void:
	var sim = _new_sim(51)
	_park_enemy_hero(sim)
	for i in 300:
		sim.set_move(Vector2(1, 0))
		sim.step()
	sim.set_move(Vector2.ZERO)
	sim.step()  # tick 301: stands at lane x = 17 m, inside the red tower range
	almost(sim.hero_state()["pos"].x, 17.0, 0.001)
	var guard := 0
	while bool(sim.hero_state()["alive"]) and guard < 1200:
		sim.step()
		guard += 1
	eq(sim.hero_state()["alive"], false, "the red tower eventually kills the idle hero")
	var hero: Dictionary = _find_entity(sim, sim.hero_id())
	eq(hero["alive"], false)
	eq(hero["anim"], &"dead")
	eq(hero["hp"], 0)
	eq(sim.hero_state()["can_act"], false)
	eq(sim.hero_state()["respawn_remaining_ms"], 6000)
	var death_x: float = sim.hero_state()["pos"].x
	sim.set_move(Vector2(1, 0))
	sim.command_attack(-1)
	sim.step()
	almost(sim.hero_state()["pos"].x, death_x, 0.001, "dead heroes cannot move")
	eq(sim.hero_state()["respawn_remaining_ms"], 5966)
	_step_many(sim, 178)
	eq(sim.hero_state()["alive"], false, "the respawn timer has not elapsed")
	eq(sim.hero_state()["respawn_remaining_ms"], 33)
	sim.step()
	eq(sim.hero_state()["alive"], true)
	eq(sim.hero_state()["hp"], 600)
	eq(sim.hero_state()["max_hp"], 600)
	eq(sim.hero_state()["can_act"], true)
	eq(sim.hero_state()["respawn_remaining_ms"], 0)
	almost(sim.hero_state()["pos"].x, -28.0, 0.001, "the hero respawns at the blue base")
	almost(sim.hero_state()["pos"].y, 0.0, 0.001)
	eq(_find_entity(sim, sim.hero_id())["anim"], &"idle")


func test_destroying_the_red_crystal_wins_and_freezes_the_match() -> void:
	var sim = _new_sim(61)
	_park_enemy_hero(sim)  # isolate the crystal/outcome rule from the AI pressure
	_step_many(sim, 150)
	var red_crystal: Dictionary = _structure(sim, TEAM_RED, KIND_CRYSTAL)
	var crystal_id: int = red_crystal["id"]
	_internal_entity(sim, crystal_id)["hp"] = 60  # a late-game last hit
	_teleport(sim, sim.hero_id(), 23800, 0)
	sim.command_attack(-1)
	sim.step()
	eq(_find_entity(sim, crystal_id)["hp"], 5, "the hero hits the crystal for 55")
	eq(sim.outcome(), &"")
	_step_many(sim, 17)
	eq(sim.outcome(), &"", "the crystal is still standing with 5 hp")
	sim.step()  # second hit at tick 169
	eq(sim.outcome(), &"blue", "destroying the red crystal wins for blue")
	eq(sim.tick_count(), 169)
	var destroyed: Dictionary = _find_entity(sim, crystal_id)
	eq(destroyed["alive"], false)
	eq(destroyed["anim"], &"dead")
	eq(destroyed["hp"], 0)
	eq(sim.hero_state()["can_act"], false, "the match is over, the hero cannot act")
	var frozen_hash: int = sim.state_hash()
	var frozen_tick: int = sim.tick_count()
	var frozen_ms: int = sim.time_ms()
	_step_many(sim, 10)
	eq(sim.tick_count(), frozen_tick, "the simulation freezes after the victory")
	eq(sim.time_ms(), frozen_ms)
	eq(sim.state_hash(), frozen_hash)
	sim.set_move(Vector2(1, 0))
	sim.command_attack(-1)
	sim.step()
	eq(sim.state_hash(), frozen_hash, "commands are ignored once the match is frozen")


func test_destroying_the_blue_crystal_loses_and_freezes_the_match() -> void:
	var sim = _new_sim(62)
	var blue_crystal: Dictionary = _structure(sim, TEAM_BLUE, KIND_CRYSTAL)
	_internal_entity(sim, blue_crystal["id"])["hp"] = 0
	sim.step()
	eq(sim.outcome(), &"red", "destroying the blue crystal wins for red")
	eq(sim.hero_state()["can_act"], false)
	var frozen_hash: int = sim.state_hash()
	_step_many(sim, 10)
	eq(sim.state_hash(), frozen_hash)
	eq(sim.tick_count(), 1)


func _red_structure_id(sim, kind: StringName) -> int:
	for structure in sim.structures(TEAM_RED):
		if structure["kind"] == kind:
			return structure["id"]
	return -1


func _alive_entity(sim, entity_id: int) -> bool:
	var entity := _find_entity(sim, entity_id)
	return not entity.is_empty() and bool(entity["alive"])


## Bot using only the frozen public command API (no test seam): rush the red crystal
## (the red tower cannot reach the crystal's attack spot) and destroy it. The view
## layer sends exactly these commands from the stick and the attack button.
func _drive_hero_at_objective(sim, crystal_id: int) -> void:
	if not bool(sim.hero_state()["alive"]):
		return
	if not _alive_entity(sim, crystal_id):
		return
	var hero_pos: Vector2 = sim.hero_state()["pos"]
	if absf(hero_pos.x - 26.0) <= 2.1:
		sim.command_attack(crystal_id)
	else:
		sim.set_move(Vector2(1.0, 0.0))


func test_a_full_match_can_be_won_with_plain_commands() -> void:
	var sim = _new_sim(99)
	var crystal_id: int = _red_structure_id(sim, KIND_CRYSTAL)
	var ticks := 0
	while sim.outcome() == &"" and ticks < 6000:
		_drive_hero_at_objective(sim, crystal_id)
		sim.step()
		ticks += 1
	print("[moba_sim] player-bot win: outcome=", sim.outcome(), " ticks=", ticks,
			" time_ms=", sim.time_ms(), " blue_crystal_hp=",
			_structure(sim, TEAM_BLUE, KIND_CRYSTAL)["hp"])
	eq(sim.outcome(), &"blue", "a player who pushes the lane can win the match")
	eq(sim.tick_count(), ticks)
	ok(ticks < 6000, "the match finishes in under 200 s of match time (%d ticks)" % ticks)
	var red_crystal: Dictionary = _structure(sim, TEAM_RED, KIND_CRYSTAL)
	eq(red_crystal["alive"], false)
	eq(red_crystal["hp"], 0)
	eq(red_crystal["anim"], &"dead")
	var blue_crystal: Dictionary = _structure(sim, TEAM_BLUE, KIND_CRYSTAL)
	eq(blue_crystal["alive"], true, "the player wins before the AI takes the blue crystal")
	ok(int(blue_crystal["hp"]) > 0)
	eq(sim.hero_state()["can_act"], false)
	var frozen_hash: int = sim.state_hash()
	_step_many(sim, 10)
	eq(sim.state_hash(), frozen_hash, "the finished match stays frozen")

