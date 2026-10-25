extends "res://scripts/arena/arena_unit.gd"
## 兵线：更近的精英或敌方小兵，其次已暴露的建筑，再次贴身英雄。不进 player/enemies 组。


func _ready() -> void:
	if unit_kind == "" or unit_kind == "hero":
		unit_kind = "minion"
	super()


func combat_tick(delta: float) -> void:
	_cd = maxf(0.0, _cd - delta)
	var foe := _nearest_of_kind("minion", sight_range)
	var elite := _nearest_of_kind("elite", ArenaCatalog.ELITE_AGGRO)
	var struct := _nearest_structure()
	var goal := ArenaRun.objective_x(team)
	var target: Node2D = null
	if role == "siege" and struct != null:
		target = struct
	elif _closer_than(elite, foe):
		target = elite
	elif foe != null:
		target = foe
	elif struct != null:
		target = struct
	else:
		var hero := _nearest_of_kind("hero", attack_range + 14.0)
		if hero != null:
			target = hero
	if target != null and absf(target.global_position.x - global_position.x) <= attack_range + 4.0:
		move_toward_x(global_position.x, 0.0)
		_face_toward(target.global_position.x)
		_steer_depth(target)
		if _cd <= 0.0:
			_swing(target)
		return
	if target != null:
		_steer_depth(target)
		move_toward_x(target.global_position.x, attack_range * 0.85)
		return
	_steer_depth(null)
	move_toward_x(goal, 12.0)


func _steer_depth(target: Node2D) -> void:
	var lane := ArenaCatalog.lane_y(slot)
	var goal := lane
	if target != null and not ArenaCatalog.node_spans_depth(target):
		goal = lerpf(lane, ArenaCatalog.node_depth(target), 0.7)
	move_toward_depth(goal)


func _closer_than(first: Node2D, second: Node2D) -> bool:
	if first == null:
		return false
	if second == null:
		return true
	var here := global_position.x
	return absf(first.global_position.x - here) <= absf(second.global_position.x - here)


func _swing(target: Node2D) -> void:
	if role == "ranged":
		launch_bolt(facing, target)
	else:
		strike_at(target.global_position + Vector2(0, -12), target)
