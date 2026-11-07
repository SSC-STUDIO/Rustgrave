class_name MobaSim
extends RefCounted
## Deterministic single-lane MOBA simulation core (plan P1 + minimal P2 subset).
##
## Pure logic: no Node/SceneTree/rendering and no floating-point randomness.
## Gameplay positions are integer millimetres internally ([Vector2i]); [method step]
## advances one fixed 1/30 s tick. The same seed plus the same command sequence always
## produces the same per-tick [method state_hash].
##
## Lane frame: X runs along the single lane (blue base at -28 m, red base at +28 m);
## Y is the cross-lane offset (0 = lane centre). The public API reports positions in
## metres; the rule constants below use millimetres and ticks.
##
## Teams: [constant TEAM_BLUE] = 0 owns the player hero, [constant TEAM_RED] = 1.
## Commands issued through [method set_move] / [method command_attack] take effect on
## the next [method step]; the newest command wins, and a move command cancels an
## attack command (and vice versa), matching MOBA input conventions.
##
## Rules (minimal playable subset):
## - Structures: one tower per side (x = -16 / +16, HP 1200, 6 m range, 40 damage per
##   second, targets the nearest enemy minion first and only then the enemy hero) and
##   one crystal per side (x = -26 / +26, HP 2400, does not attack).
## - Minions: 3 per side every 20 s starting at 5 s (HP 300, 18 damage per second,
##   1.2 m range, 3 m/s). They march down the lane, stop to fight the nearest enemy in
##   range, and trade damage simultaneously with their opponent.
## - Hero: HP 600, 55 damage every 0.6 s, 2.2 m range, 4.5 m/s; 6 s after dying it
##   respawns at the blue base. Attack range is centre-to-centre distance.
## - Enemy hero: a red (team 1) mirror hero with the same stats, driven by a small
##   deterministic AI: it attacks the nearest blue minion in range, then the blue hero,
##   then the blue tower, then the blue crystal; otherwise it marches down the lane
##   towards the blue base (it waits at its base until the first minion wave has formed).
##   It respawns at the red base 6 s after dying. Only the blue hero is player-controlled
##   ([method set_move]/[method command_attack] ignore it).
## - Destroying either crystal ends the match ([method outcome] returns the winning
##   team) and freezes the simulation; later [method step] calls change nothing.
##
## Determinism notes: entity ids are assigned in creation order and every per-tick loop
## walks the entity list in ascending id order; ties in target selection prefer the lower
## id; damage is collected during the decision pass and applied simultaneously afterwards
## (so mirrored duels kill each other on the same tick). The only use of the seed RNG is
## a small per-column minion spawn offset shared by both teams, so different seeds shift
## positions slightly but never change combat timing, damage or the outcome. The enemy
## hero AI is a pure function of the world state (no RNG), so replays stay bit-exact.

## Winning team ids, also used by [method structures].
const TEAM_BLUE := 0
const TEAM_RED := 1

## Fixed simulation rate: one [method step] is one tick.
const TICK_HZ := 30

## Sentinels for the player hero's current attack command.
const ATTACK_NONE := -2
const ATTACK_AUTO := -1

const KIND_HERO := &"hero"
const KIND_MINION := &"minion"
const KIND_TOWER := &"tower"
const KIND_CRYSTAL := &"crystal"

const ANIM_IDLE := &"idle"
const ANIM_RUN := &"run"
const ANIM_ATTACK := &"attack"
const ANIM_DEAD := &"dead"

## Lane geometry, millimetres.
const LANE_HALF_X_MM := 32000
const LANE_HALF_Y_MM := 2400
const BASE_X_MM := 28000
const TOWER_X_MM := 16000
const CRYSTAL_X_MM := 26000

## Hero rules.
const HERO_HP := 600
const HERO_DAMAGE := 55
const HERO_ATTACK_TICKS := 18
const HERO_RANGE_MM := 2200
const HERO_SPEED_MM_TICK := 150
const RESPAWN_TICKS := 6 * TICK_HZ

## Minion rules.
const MINION_HP := 300
const MINION_DAMAGE := 18
const MINION_ATTACK_TICKS := 30
const MINION_RANGE_MM := 1200
const MINION_SPEED_MM_TICK := 100
const MINIONS_PER_WAVE := 3
const MINION_LANE_OFFSETS_MM := [-600, 0, 600]

## Tower rules.
const TOWER_HP := 1200
const TOWER_DAMAGE := 40
const TOWER_ATTACK_TICKS := 30
const TOWER_RANGE_MM := 6000

## Crystal rules.
const CRYSTAL_HP := 2400

## Wave schedule, ticks.
const FIRST_WAVE_TICK := 5 * TICK_HZ
const WAVE_INTERVAL_TICK := 20 * TICK_HZ

## How long the attack pose is shown after a hit lands.
const ATTACK_ANIM_TICKS := 4
## Largest per-column spawn offset in millimetres. Both teams' minions in one column
## share the offset, so the seed shifts positions but never combat timing or outcomes.
const SPAWN_JITTER_MM := 50

## 32-bit FNV-1a constants used by [method state_hash].
const FNV_OFFSET_BASIS := 2166136261
const FNV_PRIME := 16777619
const HASH_MASK := 0xFFFFFFFF

var _seed: int = 0
var _tick: int = 0
var _wave_index: int = 0
var _next_wave_tick: int = 0
var _outcome: StringName = &""
var _rng_state: int = 0
var _entities: Array[Dictionary] = []
var _next_id: int = 0
var _hero: Dictionary = {}
var _hero_id: int = -1
var _enemy_hero: Dictionary = {}
var _enemy_hero_id: int = -1
var _blue_crystal: Dictionary = {}
var _red_crystal: Dictionary = {}

## Player intent. Commands are buffered and applied at the start of the next tick.
var _hero_move_delta: Vector2i = Vector2i.ZERO
var _hero_attack_cmd: int = ATTACK_NONE
var _pending_move_delta: Vector2i = Vector2i.ZERO
var _pending_move_set: bool = false
var _pending_attack_cmd: int = ATTACK_NONE
var _pending_attack_set: bool = false


func _init(initial_seed: int = 0) -> void:
	_seed = initial_seed
	reset(initial_seed)


## Restarts the match. A non-zero [param new_seed] reseeds the RNG; the default keeps
## the current seed so [method reset] can restart a deterministic replay.
func reset(new_seed: int = 0) -> void:
	if new_seed != 0:
		_seed = new_seed
	_tick = 0
	_wave_index = 0
	_next_wave_tick = FIRST_WAVE_TICK
	_outcome = &""
	_rng_state = (_seed * 2654435761 + 1) & HASH_MASK
	_entities.clear()
	_next_id = 0
	_hero = {}
	_hero_id = -1
	_enemy_hero = {}
	_enemy_hero_id = -1
	_blue_crystal = {}
	_red_crystal = {}
	_hero_move_delta = Vector2i.ZERO
	_hero_attack_cmd = ATTACK_NONE
	_pending_move_delta = Vector2i.ZERO
	_pending_move_set = false
	_pending_attack_cmd = ATTACK_NONE
	_pending_attack_set = false
	_spawn_structures()
	_spawn_heroes()


## Advances the simulation by exactly one 1/30 s tick. Does nothing once a crystal has
## been destroyed (the match is frozen at that state).
func step() -> void:
	if _outcome != &"":
		return
	_tick += 1
	_apply_commands()
	_tick_events()
	_tick_combat()


func tick_count() -> int:
	return _tick


## Milliseconds elapsed. Integer ticks are converted with truncation (tick 1 -> 33 ms);
## schedule queries such as [method next_wave_ms] are exact.
func time_ms() -> int:
	return _ticks_to_ms(_tick)


## &"" while the match runs, otherwise the winning team: &"blue" or &"red".
func outcome() -> StringName:
	return _outcome


## Player (team 0) hero id; [method hero_id] with team 1 returns the red AI hero id.
func hero_id(team: int = 0) -> int:
	if team == TEAM_RED:
		return _enemy_hero_id
	if team != TEAM_BLUE:
		return -1
	return _hero_id


## Convenience alias for the red AI hero id (same as hero_id(TEAM_RED)).
func enemy_hero_id() -> int:
	return _enemy_hero_id


## Requests a lane-space move direction for the next tick. Length is clamped to 1; a zero
## vector stops the hero. Cancels a pending/current attack command. Ignored while the
## hero is dead or the match is over.
func set_move(dir_lane: Vector2) -> void:
	if _outcome != &"" or not bool(_hero["alive"]):
		return
	var dir := dir_lane
	var length := dir.length()
	if length > 1.0:
		dir /= length
	_pending_move_delta = Vector2i(
			roundi(dir.x * HERO_SPEED_MM_TICK), roundi(dir.y * HERO_SPEED_MM_TICK))
	_pending_move_set = true
	_pending_attack_cmd = ATTACK_NONE
	_pending_attack_set = true


## Requests an attack for the next tick. [param target_id] = -1 re-acquires the nearest
## enemy in range every tick (towers and crystals included); a valid entity id locks that
## target. Cancels a pending/current move command. Ignored while dead or match over.
func command_attack(target_id: int = -1) -> void:
	if _outcome != &"" or not bool(_hero["alive"]):
		return
	_pending_attack_cmd = target_id if target_id >= 0 else ATTACK_AUTO
	_pending_attack_set = true
	_pending_move_delta = Vector2i.ZERO
	_pending_move_set = true


## Deep-copied snapshots of every entity (hero, minions, towers, crystals) in ascending
## id order. Dead minions are removed from the simulation, so they never appear here;
## dead heroes/structures stay with "alive": false and anim &"dead".
func entities() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entity in _entities:
		out.append(_public_entity(entity))
	return out


## Deep-copied snapshots of the structures of one team (0 blue, 1 red; negative = both).
## Each entry uses the same keys as [method entities].
func structures(team: int = -1) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entity in _entities:
		var kind: StringName = entity["kind"]
		if kind != KIND_TOWER and kind != KIND_CRYSTAL:
			continue
		if team >= 0 and int(entity["team"]) != team:
			continue
		out.append(_public_entity(entity))
	return out


## Player-hero snapshot: hp/max_hp, alive, can_act, respawn timers and current target.
func hero_state() -> Dictionary:
	var respawn_ticks := 0
	if not bool(_hero["alive"]):
		respawn_ticks = maxi(0, int(_hero["respawn_tick"]) - _tick)
	return {
		"id": _hero_id,
		"team": TEAM_BLUE,
		"kind": KIND_HERO,
		"pos": _to_meters(_hero["pos"]),
		"hp": int(_hero["hp"]),
		"max_hp": int(_hero["max_hp"]),
		"alive": bool(_hero["alive"]),
		"can_act": bool(_hero["alive"]) and _outcome == &"",
		"respawn_remaining_ms": _ticks_to_ms(respawn_ticks),
		"respawn_remaining_ticks": respawn_ticks,
		"facing": int(_hero["facing"]),
		"attack_target": int(_hero["target_id"]),
	}


## Number of waves spawned so far (0 before the first wave at 5 s).
func wave_index() -> int:
	return _wave_index


## Absolute simulation time of the next wave in milliseconds.
func next_wave_ms() -> int:
	return _ticks_to_ms(_next_wave_tick)


## 32-bit FNV-1a hash of every mutable simulation field, including entity ids, teams,
## kinds, positions, hp, facing, anim, attack cooldowns, wave/time state and outcome.
func state_hash() -> int:
	var hash_value: int = FNV_OFFSET_BASIS
	hash_value = _mix_i32(hash_value, _seed)
	hash_value = _mix_i32(hash_value, _tick)
	hash_value = _mix_i32(hash_value, time_ms())
	hash_value = _mix_i32(hash_value, _wave_index)
	hash_value = _mix_i32(hash_value, _next_wave_tick)
	hash_value = _mix_i32(hash_value, _rng_state)
	hash_value = _mix_i32(hash_value, _next_id)
	hash_value = _mix_string(hash_value, String(_outcome))
	hash_value = _mix_i32(hash_value, _hero_attack_cmd)
	hash_value = _mix_i32(hash_value, _hero_move_delta.x)
	hash_value = _mix_i32(hash_value, _hero_move_delta.y)
	hash_value = _mix_i32(hash_value, 1 if _pending_move_set else 0)
	hash_value = _mix_i32(hash_value, _pending_move_delta.x)
	hash_value = _mix_i32(hash_value, _pending_move_delta.y)
	hash_value = _mix_i32(hash_value, 1 if _pending_attack_set else 0)
	hash_value = _mix_i32(hash_value, _pending_attack_cmd)
	hash_value = _mix_i32(hash_value, _entities.size())
	for entity in _entities:
		var pos: Vector2i = entity["pos"]
		hash_value = _mix_i32(hash_value, int(entity["id"]))
		hash_value = _mix_i32(hash_value, int(entity["team"]))
		hash_value = _mix_i32(hash_value, _kind_code(entity["kind"]))
		hash_value = _mix_i32(hash_value, pos.x)
		hash_value = _mix_i32(hash_value, pos.y)
		hash_value = _mix_i32(hash_value, int(entity["hp"]))
		hash_value = _mix_i32(hash_value, int(entity["max_hp"]))
		hash_value = _mix_i32(hash_value, int(entity["facing"]))
		hash_value = _mix_i32(hash_value, _anim_code(entity))
		hash_value = _mix_i32(hash_value, int(entity["attack_cd"]))
		hash_value = _mix_i32(hash_value, int(entity["attack_anim"]))
		hash_value = _mix_i32(hash_value, 1 if bool(entity["alive"]) else 0)
		hash_value = _mix_i32(hash_value, int(entity["target_id"]))
		hash_value = _mix_i32(hash_value, int(entity["respawn_tick"]))
	return hash_value


# --- Setup ---------------------------------------------------------------

func _spawn_structures() -> void:
	_create_entity(TEAM_BLUE, KIND_TOWER, -TOWER_X_MM, 0)
	_blue_crystal = _create_entity(TEAM_BLUE, KIND_CRYSTAL, -CRYSTAL_X_MM, 0)
	_create_entity(TEAM_RED, KIND_TOWER, TOWER_X_MM, 0)
	_red_crystal = _create_entity(TEAM_RED, KIND_CRYSTAL, CRYSTAL_X_MM, 0)


func _spawn_heroes() -> void:
	_hero = _create_entity(TEAM_BLUE, KIND_HERO, -BASE_X_MM, 0)
	_hero_id = int(_hero["id"])
	_enemy_hero = _create_entity(TEAM_RED, KIND_HERO, BASE_X_MM, 0)
	_enemy_hero_id = int(_enemy_hero["id"])


func _spawn_wave() -> void:
	var index := 0
	while index < MINIONS_PER_WAVE:
		var offset: int = MINION_LANE_OFFSETS_MM[index]
		# One draw per column, applied to both teams: mirrored minions stay exactly the
		# same distance apart, so a different seed only jitters their positions.
		var lane_shift := _rand_jitter(SPAWN_JITTER_MM)
		_create_entity(TEAM_BLUE, KIND_MINION, -BASE_X_MM + lane_shift, offset)
		_create_entity(TEAM_RED, KIND_MINION, BASE_X_MM + lane_shift, offset)
		index += 1


func _create_entity(team: int, kind: StringName, x_mm: int, y_mm: int) -> Dictionary:
	var max_hp := _max_hp_for(kind)
	var entity := {
		"id": _next_id,
		"team": team,
		"kind": kind,
		"pos": Vector2i(x_mm, y_mm),
		"hp": max_hp,
		"max_hp": max_hp,
		"facing": 1 if team == TEAM_BLUE else -1,
		"attack_cd": 0,
		"attack_anim": 0,
		"alive": true,
		"target_id": -1,
		"moved": false,
		"respawn_tick": 0,
	}
	_next_id += 1
	_entities.append(entity)
	return entity


# --- Per-tick pipeline ---------------------------------------------------

func _apply_commands() -> void:
	if _pending_move_set:
		_hero_move_delta = _pending_move_delta
		_pending_move_set = false
	if _pending_attack_set:
		_hero_attack_cmd = _pending_attack_cmd
		_pending_attack_set = false


func _tick_events() -> void:
	if _tick >= _next_wave_tick:
		_spawn_wave()
		_wave_index += 1
		_next_wave_tick += WAVE_INTERVAL_TICK
	for hero in [_hero, _enemy_hero]:
		if not bool(hero["alive"]) and _tick >= int(hero["respawn_tick"]):
			_revive_hero(hero)


func _revive_hero(hero: Dictionary) -> void:
	var team := int(hero["team"])
	hero["alive"] = true
	hero["hp"] = int(hero["max_hp"])
	hero["pos"] = Vector2i(-BASE_X_MM if team == TEAM_BLUE else BASE_X_MM, 0)
	hero["facing"] = 1 if team == TEAM_BLUE else -1
	hero["attack_cd"] = 0
	hero["attack_anim"] = 0
	hero["target_id"] = -1
	hero["moved"] = false
	hero["respawn_tick"] = 0
	if team == TEAM_BLUE:
		_hero_move_delta = Vector2i.ZERO
		_hero_attack_cmd = ATTACK_NONE


func _tick_combat() -> void:
	var attacks: Array[Dictionary] = []
	var moves: Array[Dictionary] = []
	for entity in _entities:
		entity["moved"] = false
		if int(entity["attack_cd"]) > 0:
			entity["attack_cd"] = int(entity["attack_cd"]) - 1
		if int(entity["attack_anim"]) > 0:
			entity["attack_anim"] = int(entity["attack_anim"]) - 1
	for entity in _entities:
		if not bool(entity["alive"]):
			continue
		var kind: StringName = entity["kind"]
		if kind == KIND_HERO:
			if int(entity["team"]) == TEAM_BLUE:
				_decide_hero(attacks, moves)
			else:
				_decide_enemy_hero(entity, attacks, moves)
		elif kind == KIND_MINION:
			_decide_minion(entity, attacks, moves)
		elif kind == KIND_TOWER:
			_decide_tower(entity, attacks)
	for request in moves:
		_apply_move(request["entity"], request["delta"])
	# Simultaneous damage: every attack is queued from the state at the start of the
	# decision pass, so a mirrored duel kills both sides on the same tick.
	for attack in attacks:
		var target: Dictionary = attack["target"]
		target["hp"] = int(target["hp"]) - int(attack["damage"])
	_mark_deaths()
	_check_outcome()
	_remove_dead_minions()


func _decide_hero(attacks: Array[Dictionary], moves: Array[Dictionary]) -> void:
	var target := _resolve_hero_target()
	if not target.is_empty():
		_hero["target_id"] = int(target["id"])
		_face_towards(_hero, target)
		if _in_range(_hero, target, HERO_RANGE_MM) and int(_hero["attack_cd"]) == 0:
			_queue_attack(_hero, target, HERO_DAMAGE, attacks)
		return
	_hero["target_id"] = -1
	if _hero_attack_cmd != ATTACK_NONE:
		# Attack order without a target in range: hold position instead of chasing.
		return
	if _hero_move_delta != Vector2i.ZERO:
		moves.append({"entity": _hero, "delta": _hero_move_delta})


## Deterministic red-hero AI: fight the highest-priority blue target inside the hero
## range (minion > hero > tower > crystal); otherwise march towards the blue base. It
## waits at its base for the first minion wave, so the push arrives with a wave.
func _decide_enemy_hero(hero: Dictionary, attacks: Array[Dictionary],
		moves: Array[Dictionary]) -> void:
	if _wave_index == 0:
		hero["target_id"] = -1
		return
	var target := _enemy_hero_target(hero)
	if not target.is_empty():
		hero["target_id"] = int(target["id"])
		_face_towards(hero, target)
		if _in_range(hero, target, HERO_RANGE_MM) and int(hero["attack_cd"]) == 0:
			_queue_attack(hero, target, HERO_DAMAGE, attacks)
		return
	hero["target_id"] = -1
	moves.append({"entity": hero, "delta": Vector2i(-HERO_SPEED_MM_TICK, 0)})


func _enemy_hero_target(hero: Dictionary) -> Dictionary:
	var target := _nearest_enemy_of_kind(hero, HERO_RANGE_MM, KIND_MINION)
	if target.is_empty():
		target = _nearest_enemy_of_kind(hero, HERO_RANGE_MM, KIND_HERO)
	if target.is_empty():
		target = _nearest_enemy_of_kind(hero, HERO_RANGE_MM, KIND_TOWER)
	if target.is_empty():
		target = _nearest_enemy_of_kind(hero, HERO_RANGE_MM, KIND_CRYSTAL)
	return target


func _decide_minion(entity: Dictionary, attacks: Array[Dictionary],
		moves: Array[Dictionary]) -> void:
	var target := _current_or_nearest_enemy(entity, MINION_RANGE_MM)
	if not target.is_empty():
		entity["target_id"] = int(target["id"])
		_face_towards(entity, target)
		if int(entity["attack_cd"]) == 0:
			_queue_attack(entity, target, MINION_DAMAGE, attacks)
		return
	entity["target_id"] = -1
	var lane_direction := 1 if int(entity["team"]) == TEAM_BLUE else -1
	moves.append({
		"entity": entity,
		"delta": Vector2i(lane_direction * MINION_SPEED_MM_TICK, 0),
	})


func _decide_tower(tower: Dictionary, attacks: Array[Dictionary]) -> void:
	var target := _nearest_enemy_of_kind(tower, TOWER_RANGE_MM, KIND_MINION)
	if target.is_empty():
		target = _nearest_enemy_of_kind(tower, TOWER_RANGE_MM, KIND_HERO)
	if target.is_empty():
		tower["target_id"] = -1
		return
	tower["target_id"] = int(target["id"])
	_face_towards(tower, target)
	if int(tower["attack_cd"]) == 0:
		_queue_attack(tower, target, TOWER_DAMAGE, attacks)


func _apply_move(entity: Dictionary, delta: Vector2i) -> void:
	var pos: Vector2i = entity["pos"]
	var next_x := clampi(pos.x + delta.x, -LANE_HALF_X_MM, LANE_HALF_X_MM)
	var next_y := clampi(pos.y + delta.y, -LANE_HALF_Y_MM, LANE_HALF_Y_MM)
	if next_x == pos.x and next_y == pos.y:
		return
	entity["pos"] = Vector2i(next_x, next_y)
	entity["moved"] = true
	if next_x != pos.x:
		entity["facing"] = signi(next_x - pos.x)


func _mark_deaths() -> void:
	for entity in _entities:
		if not bool(entity["alive"]):
			continue
		if int(entity["hp"]) > 0:
			continue
		entity["hp"] = 0
		entity["alive"] = false
		entity["attack_cd"] = 0
		entity["attack_anim"] = 0
		entity["target_id"] = -1
		entity["moved"] = false
		if entity["kind"] == KIND_HERO:
			entity["respawn_tick"] = _tick + RESPAWN_TICKS
			if int(entity["team"]) == TEAM_BLUE:
				_hero_move_delta = Vector2i.ZERO
				_hero_attack_cmd = ATTACK_NONE


func _check_outcome() -> void:
	# Blue wins the (impossible in normal play) double-crystal-destroy tie.
	if not bool(_red_crystal["alive"]):
		_outcome = &"blue"
	elif not bool(_blue_crystal["alive"]):
		_outcome = &"red"


func _remove_dead_minions() -> void:
	var kept: Array[Dictionary] = []
	for entity in _entities:
		if entity["kind"] == KIND_MINION and not bool(entity["alive"]):
			continue
		kept.append(entity)
	_entities = kept


# --- Targeting and combat helpers ---------------------------------------

func _resolve_hero_target() -> Dictionary:
	if _hero_attack_cmd == ATTACK_NONE:
		return {}
	if _hero_attack_cmd >= 0:
		var explicit_target := _find_by_id(_hero_attack_cmd)
		if explicit_target.is_empty() or not bool(explicit_target["alive"]) \
				or int(explicit_target["team"]) == TEAM_BLUE:
			_hero_attack_cmd = ATTACK_NONE
			return {}
		return explicit_target
	return _nearest_enemy(_hero, HERO_RANGE_MM)


func _current_or_nearest_enemy(entity: Dictionary, range_mm: int) -> Dictionary:
	var target_id := int(entity["target_id"])
	if target_id >= 0:
		var current := _find_by_id(target_id)
		if not current.is_empty() and bool(current["alive"]) \
				and int(current["team"]) != int(entity["team"]) \
				and _in_range(entity, current, range_mm):
			return current
	return _nearest_enemy(entity, range_mm)


func _nearest_enemy(entity: Dictionary, range_mm: int) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := 0
	var range_sq := range_mm * range_mm
	for other in _entities:
		if not bool(other["alive"]) or int(other["team"]) == int(entity["team"]):
			continue
		var distance := _distance_sq(entity, other)
		if distance > range_sq:
			continue
		if best.is_empty() or distance < best_distance:
			best = other
			best_distance = distance
	return best


func _nearest_enemy_of_kind(entity: Dictionary, range_mm: int, kind: StringName) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := 0
	var range_sq := range_mm * range_mm
	for other in _entities:
		if not bool(other["alive"]) or int(other["team"]) == int(entity["team"]):
			continue
		if other["kind"] != kind:
			continue
		var distance := _distance_sq(entity, other)
		if distance > range_sq:
			continue
		if best.is_empty() or distance < best_distance:
			best = other
			best_distance = distance
	return best


func _find_by_id(entity_id: int) -> Dictionary:
	for entity in _entities:
		if int(entity["id"]) == entity_id:
			return entity
	return {}


func _distance_sq(first: Dictionary, second: Dictionary) -> int:
	var first_pos: Vector2i = first["pos"]
	var second_pos: Vector2i = second["pos"]
	var dx := first_pos.x - second_pos.x
	var dy := first_pos.y - second_pos.y
	return dx * dx + dy * dy


func _in_range(attacker: Dictionary, target: Dictionary, range_mm: int) -> bool:
	return _distance_sq(attacker, target) <= range_mm * range_mm


func _queue_attack(attacker: Dictionary, target: Dictionary, damage: int,
		attacks: Array[Dictionary]) -> void:
	attacks.append({"attacker": attacker, "target": target, "damage": damage})
	attacker["attack_cd"] = _attack_interval_ticks(attacker["kind"])
	attacker["attack_anim"] = ATTACK_ANIM_TICKS


func _face_towards(entity: Dictionary, target: Dictionary) -> void:
	var entity_pos: Vector2i = entity["pos"]
	var target_pos: Vector2i = target["pos"]
	if entity_pos.x != target_pos.x:
		entity["facing"] = signi(target_pos.x - entity_pos.x)


# --- Stat tables ---------------------------------------------------------

func _max_hp_for(kind: StringName) -> int:
	if kind == KIND_HERO:
		return HERO_HP
	if kind == KIND_MINION:
		return MINION_HP
	if kind == KIND_TOWER:
		return TOWER_HP
	return CRYSTAL_HP


func _attack_interval_ticks(kind: StringName) -> int:
	if kind == KIND_HERO:
		return HERO_ATTACK_TICKS
	if kind == KIND_MINION:
		return MINION_ATTACK_TICKS
	if kind == KIND_TOWER:
		return TOWER_ATTACK_TICKS
	return HERO_ATTACK_TICKS


# --- Snapshot helpers ----------------------------------------------------

func _public_entity(entity: Dictionary) -> Dictionary:
	return {
		"id": int(entity["id"]),
		"team": int(entity["team"]),
		"kind": entity["kind"],
		"pos": _to_meters(entity["pos"]),
		"hp": int(entity["hp"]),
		"max_hp": int(entity["max_hp"]),
		"facing": int(entity["facing"]),
		"anim": _anim_of(entity),
		"attack_t": int(entity["attack_cd"]) / float(TICK_HZ),
		"alive": bool(entity["alive"]),
	}


func _to_meters(pos: Vector2i) -> Vector2:
	return Vector2(pos.x / 1000.0, pos.y / 1000.0)


func _anim_of(entity: Dictionary) -> StringName:
	if not bool(entity["alive"]):
		return ANIM_DEAD
	if int(entity["attack_anim"]) > 0:
		return ANIM_ATTACK
	if bool(entity["moved"]):
		return ANIM_RUN
	return ANIM_IDLE


func _kind_code(kind: StringName) -> int:
	if kind == KIND_HERO:
		return 0
	if kind == KIND_MINION:
		return 1
	if kind == KIND_TOWER:
		return 2
	return 3


func _anim_code(entity: Dictionary) -> int:
	var anim := _anim_of(entity)
	if anim == ANIM_IDLE:
		return 0
	if anim == ANIM_RUN:
		return 1
	if anim == ANIM_ATTACK:
		return 2
	return 3


# --- Deterministic integer RNG (LCG) ------------------------------------

func _rand_next() -> int:
	_rng_state = (_rng_state * 1664525 + 1013904223) & HASH_MASK
	return _rng_state


## Uniform integer in [-limit, limit].
func _rand_jitter(limit: int) -> int:
	return _rand_next() % (limit * 2 + 1) - limit


# --- FNV-1a hash helpers ------------------------------------------------

func _mix_i32(hash_value: int, value: int) -> int:
	var bits := value & HASH_MASK
	var index := 0
	while index < 4:
		hash_value = ((hash_value ^ (bits & 0xFF)) * FNV_PRIME) & HASH_MASK
		bits = bits >> 8
		index += 1
	return hash_value


func _mix_string(hash_value: int, text: String) -> int:
	var bytes := text.to_utf8_buffer()
	hash_value = _mix_i32(hash_value, bytes.size())
	for byte in bytes:
		hash_value = ((hash_value ^ (byte & 0xFF)) * FNV_PRIME) & HASH_MASK
	return hash_value


func _ticks_to_ms(ticks: int) -> int:
	@warning_ignore("integer_division")
	var milliseconds := ticks * 1000 / TICK_HZ
	return milliseconds
