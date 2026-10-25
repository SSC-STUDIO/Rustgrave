extends "res://scripts/arena/arena_unit.gd"
## 防御塔。仇恨：正在打己方英雄的敌方英雄 > 小兵 > 英雄。中立不打。
## 外塔倒了内塔才受伤（block_check）。


func _ready() -> void:
	_immobile = true
	if unit_kind != "crystal":
		unit_kind = "tower"
		if role == "" or role == "melee":
			role = "tower"
	super()
	if hurtbox != null:
		hurtbox.block_check = Callable(self, "_blocked")


func _blocked(_attacker: Node, _amount: int) -> bool:
	if not ArenaRun.allows_combat():
		return true
	if structure_index < 0:
		return false
	return not ArenaRun.structure_vulnerable(team, structure_index)


static func rank_target(tower_team: String, row: Dictionary) -> int:
	var other := String(row.get("team", ""))
	if not ArenaCatalog.hostile(tower_team, other):
		return 999
	if other == ArenaCatalog.TEAM_NEUTRAL:
		return 999
	var kind := String(row.get("kind", ""))
	if kind == "hero" and bool(row.get("attacking_hero", false)):
		return 0
	if kind == "minion":
		return 1
	if kind == "hero":
		return 2
	return 50


static func pick_target(tower_team: String, rows: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_rank := 1000
	var best_dist := 100000.0
	for raw in rows:
		if raw is not Dictionary:
			continue
		var row: Dictionary = raw
		var rank := rank_target(tower_team, row)
		if rank >= 100:
			continue
		var dist := float(row.get("dist", 0.0))
		if rank < best_rank or (rank == best_rank and dist < best_dist):
			best_rank = rank
			best_dist = dist
			best = row
	return best


func combat_tick(delta: float) -> void:
	_cd = maxf(0.0, _cd - delta)
	_react = maxf(0.0, _react - delta)
	if _cd > 0.0 or _react > 0.0:
		return
	var picked := pick_target(team, _sense_rows())
	if picked.is_empty():
		return
	var aim := float(picked.get("x", global_position.x))
	_face_toward(aim)
	var node_v: Variant = picked.get("node", null)
	var target: Node = null
	if node_v is Node:
		target = node_v as Node
	launch_bolt(facing, target)


func _sense_rows() -> Array:
	var rows: Array = []
	var tree := get_tree()
	if tree == null:
		return rows
	for node in tree.get_nodes_in_group("arena_unit"):
		_push_row(rows, node)
	for node in tree.get_nodes_in_group("player"):
		_push_row(rows, node)
	return rows


func _push_row(rows: Array, node: Node) -> void:
	if node == self or not is_instance_valid(node) or not (node is Node2D):
		return
	var body := node as Node2D
	var other := ArenaCatalog.TEAM_PLAYER if node.is_in_group("player") else String(node.get("team"))
	if not ArenaCatalog.hostile(team, other) or other == ArenaCatalog.TEAM_NEUTRAL:
		return
	if "alive" in node and not bool(node.get("alive")):
		return
	if node.is_in_group("player"):
		var knight := node as Player
		if knight.health == null or knight.health.current <= 0:
			return
	var dist := absf(body.global_position.x - global_position.x)
	if dist > attack_range:
		return
	var depth_d := absf(ArenaCatalog.node_depth(node) - arena_depth())
	if depth_d > ArenaCatalog.depth_span() + 8.0:
		return
	dist += depth_d * 0.45
	var kind := "hero" if node.is_in_group("player") else String(node.get("unit_kind"))
	if kind == "tower" or kind == "crystal" or kind == "elite":
		return
	var pressing := false
	if node.has_method("is_pressing_hero"):
		pressing = bool(node.call("is_pressing_hero"))
	elif node.is_in_group("player"):
		pressing = ArenaRun.player_pressing_hero()
	rows.append({
		"team": other,
		"kind": "hero" if kind == "hero" else "minion",
		"attacking_hero": pressing,
		"dist": dist,
		"x": body.global_position.x,
		"node": node,
	})
