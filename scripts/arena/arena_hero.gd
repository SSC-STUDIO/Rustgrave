extends "res://scripts/arena/arena_unit.gd"
## 英雄：推进 / 交战 / 低血撤退回泉水 / 技能（一发飞弹）。

var _state := "push"


func _ready() -> void:
	if _cfg.is_empty():
		unit_kind = "hero"
		role = "hero"
	super()
	engage_range = 130.0
	unit_kind = "hero"
	_think = float(slot) * 0.08
	if ArenaCatalog.match_seed >= 0:
		_think += float(posmod(ArenaCatalog.match_seed + slot, 5)) * 0.04


func _state_name() -> String:
	return _state


func decide_state() -> String:
	var ratio := hp_ratio()
	if _retreating:
		if ratio < ArenaCatalog.RETREAT_DONE:
			_state = "retreat"
			return _state
		_retreating = false
	if ratio <= ArenaCatalog.RETREAT_HP:
		_retreating = true
		_state = "retreat"
		return _state
	if _wants_siege() and not _hero_in_reach():
		_state = "push"
		return _state
	if _enemy_hero_near():
		if _skill_cd <= 0.0:
			_state = "skill"
			return _state
		_state = "fight"
		return _state
	_state = "push"
	return _state


func goal_x() -> float:
	if decide_state() == "retreat":
		return ArenaCatalog.fountain_for(team).x
	return ArenaRun.objective_x(team)


func combat_tick(delta: float) -> void:
	_cd = maxf(0.0, _cd - delta)
	_react = maxf(0.0, _react - delta)
	_skill_cd = maxf(0.0, _skill_cd - delta)
	_think -= delta
	if _think <= 0.0:
		_think = _think_gap()
		_state = decide_state()
	_steer_depth()
	if _state == "retreat":
		move_toward_x(ArenaCatalog.fountain_for(team).x, 6.0)
		return
	if _state == "skill":
		var prey := _nearest_where(true, engage_range - sight_range, true)
		if prey != null and _react <= 0.0:
			_face_toward(prey.global_position.x)
			launch_bolt(facing, prey)
			_skill_cd = 6.5
		_state = "fight"
		return
	if _state == "fight":
		var foe := _nearest_where(true, engage_range - sight_range, true)
		if foe == null:
			move_toward_x(ArenaRun.objective_x(team), attack_range)
			return
		var dist := absf(foe.global_position.x - global_position.x)
		_face_toward(foe.global_position.x)
		if dist > attack_range:
			move_toward_x(foe.global_position.x, attack_range)
			return
		move_toward_x(global_position.x, 0.0)
		if _cd <= 0.0 and _react <= 0.0:
			if ranged:
				launch_bolt(facing, foe)
			else:
				strike_at(foe.global_position + Vector2(0, -14), foe)
		return
	var elite := _close_elite()
	if elite != null:
		_face_toward(elite.global_position.x)
		if absf(elite.global_position.x - global_position.x) <= attack_range + 6.0:
			move_toward_x(global_position.x, 0.0)
			if _cd <= 0.0 and _react <= 0.0:
				strike_at(elite.global_position + Vector2(0, -12), elite)
			return
	var struct := _nearest_structure()
	if struct != null:
		move_toward_x(struct.global_position.x, attack_range)
		if absf(struct.global_position.x - global_position.x) <= attack_range + 4.0 and _cd <= 0.0 and _react <= 0.0:
			_face_toward(struct.global_position.x)
			strike_at(struct.global_position + Vector2(0, -16), struct)
		return
	move_toward_x(ArenaRun.objective_x(team), 18.0)


func _steer_depth() -> void:
	var goal := ArenaCatalog.lane_y(slot)
	var dodge := _bolt_dodge()
	if dodge > -900.0:
		move_toward_depth(dodge)
		return
	if _state == "retreat":
		move_toward_depth(ArenaCatalog.clamp_depth(ArenaCatalog.fountain_for(team).y))
		return
	var prey: Node2D = null
	if _state == "fight" or _state == "skill":
		prey = _nearest_where(true, engage_range - sight_range, true)
	if prey == null:
		prey = _close_elite()
	if prey != null and not ArenaCatalog.node_spans_depth(prey):
		goal = ArenaCatalog.node_depth(prey)
	move_toward_depth(goal)


func _bolt_dodge() -> float:
	var tree := get_tree()
	if tree == null:
		return -1000.0
	var best := -1000.0
	for node in tree.get_nodes_in_group("arena_bolt"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var bolt := node as Node2D
		var other := String(node.get("team"))
		if not ArenaCatalog.hostile(team, other):
			continue
		var dx := global_position.x - bolt.global_position.x
		if absf(dx) > 120.0 or absf(dx) < 6.0:
			continue
		var vx := 0.0
		var vel: Variant = node.get("velocity")
		if vel is Vector2:
			vx = (vel as Vector2).x
		if vx * dx <= 0.0:
			continue
		var bolt_depth := ArenaCatalog.node_depth(node)
		if absf(bolt_depth - arena_depth()) > 18.0:
			continue
		var away := arena_depth() + 32.0
		if bolt_depth >= arena_depth():
			away = arena_depth() - 32.0
		best = ArenaCatalog.clamp_depth(away)
	return best


func _wants_siege() -> bool:
	if hp_ratio() < ArenaCatalog.SIEGE_SAFE_HP:
		return false
	var tree := get_tree()
	if tree == null:
		return false
	var goal := ArenaRun.objective_x(team)
	var near := 0
	var dog := false
	for node in tree.get_nodes_in_group("arena_unit"):
		if node == self or not is_instance_valid(node):
			continue
		if String(node.get("team")) != team or String(node.get("unit_kind")) != "minion":
			continue
		if not bool(node.get("alive")):
			continue
		var body := node as Node2D
		if body == null:
			continue
		if absf(body.global_position.x - goal) > ArenaCatalog.SIEGE_PUSH_RANGE:
			continue
		near += 1
		if String(node.get("role")) == "siege":
			dog = true
	return dog or near >= 2


func _hero_in_reach() -> bool:
	if use_sense:
		for raw in sense_override:
			if raw is Dictionary:
				var row: Dictionary = raw
				var kind := String(row.get("kind", ""))
				var other := String(row.get("team", ""))
				var dist := float(row.get("dist", 9999.0))
				if kind == "hero" and ArenaCatalog.hostile(team, other) and dist <= attack_range + 6.0:
					return true
		return false
	var foe := _nearest_where(true, attack_range - sight_range, true)
	return foe != null and absf(foe.global_position.x - global_position.x) <= attack_range + 6.0


func _close_elite() -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("arena_unit"):
		if not is_instance_valid(node):
			continue
		if String(node.get("unit_kind")) != "elite" or not bool(node.get("alive")):
			continue
		var body := node as Node2D
		if body == null:
			continue
		if absf(body.global_position.x - global_position.x) <= ArenaCatalog.ELITE_AGGRO:
			return body
	return null
