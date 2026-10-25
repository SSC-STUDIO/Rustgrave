extends Node
## 无头整局：AI 对推，脚本玩家只往前走并轻微换深度。打印胜负、越带和卡死。

const ArenaCatalog := preload("res://scripts/data/arena_catalog.gd")

var _world: Node = null
var _stuck := 0
var _out := 0
var _last_x: Dictionary = {}
var _still_for: Dictionary = {}
var _next_sample := 15.0
var _next_scan := 1.0
var _saw_tower_damage := false
var _quit := false


func _ready() -> void:
	var seed_text := OS.get_environment("RUSTGRAVE_ARENA_SEED")
	var seed_n := 1
	if seed_text != "":
		seed_n = int(seed_text)
	ArenaCatalog.set_match_seed(seed_n)
	print("ARENA_SIM seed=%d" % seed_n)
	ArenaRun.auto_begin = true
	ArenaRun.activate_for_test()
	var packed := load(ArenaCatalog.SCENE) as PackedScene
	_world = packed.instantiate()
	add_child(_world)
	var stage := _world.find_child("ArenaStage", true, false)
	if stage != null:
		stage.queue_free()


func _process(_delta: float) -> void:
	if _quit or _world == null or not is_instance_valid(_world):
		return
	var steps := 24
	var step := 1.0 / 60.0
	for _i in steps:
		if _quit:
			return
		var board: Dictionary = ArenaRun.scoreboard()
		var elapsed := float(board.get("elapsed", 0.0))
		_drive_player(elapsed)
		_step_match(step)
		elapsed = float(ArenaRun.scoreboard().get("elapsed", elapsed))
		if elapsed >= _next_scan:
			_next_scan += 1.0
			_scan(1.0)
		if elapsed >= _next_sample:
			_next_sample += 60.0
			_print_line("tick", ArenaRun.scoreboard())
		var phase := ArenaRun.phase()
		if phase == ArenaCatalog.PHASE_RESULT or elapsed >= ArenaCatalog.MATCH_SECONDS + 2.0:
			_finish(ArenaRun.scoreboard())
			return


func _step_match(step: float) -> void:
	var run := get_node_or_null("/root/ArenaRun")
	if run != null:
		run._process(step)
	if _world != null and is_instance_valid(_world):
		_world._process(step)
	var units: Array = get_tree().get_nodes_in_group("arena_unit")
	for node in units:
		if is_instance_valid(node) and node.has_method(&"_physics_process"):
			node._physics_process(step)
	var bolts: Array = get_tree().get_nodes_in_group("arena_bolt")
	for node in bolts:
		if is_instance_valid(node) and node.has_method(&"_physics_process"):
			node._physics_process(step)
	var knight := get_tree().get_first_node_in_group("player")
	if knight != null and is_instance_valid(knight) and knight.is_physics_processing():
		knight._physics_process(step)


func _drive_player(elapsed: float) -> void:
	var knight := get_tree().get_first_node_in_group("player")
	if knight == null or not knight.has_method(&"arena_set_drive"):
		return
	var depth := sin(elapsed * 0.7)
	var jump := int(elapsed) % 7 == 0 and int(elapsed * 10.0) % 10 == 0
	knight.call(&"arena_set_drive", 1.0, depth, jump)


func _scan(step: float) -> void:
	for node in get_tree().get_nodes_in_group("arena_unit"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var body := node as Node2D
		if not ArenaCatalog.in_depth(body.global_position.y):
			_out += 1
		if String(node.get("unit_kind")) != "minion" or not bool(node.get("alive")):
			continue
		var id := String(node.get("unit_id"))
		var prev := float(_last_x.get(id, body.global_position.x))
		if absf(body.global_position.x - prev) < 3.0 and not _busy(body):
			_still_for[id] = float(_still_for.get(id, 0.0)) + step
			if float(_still_for[id]) > 20.0:
				_stuck += 1
				_still_for[id] = 0.0
		else:
			_still_for[id] = 0.0
		_last_x[id] = body.global_position.x
	var knight := get_tree().get_first_node_in_group("player") as Node2D
	if knight != null and not ArenaCatalog.in_depth(knight.global_position.y):
		_out += 1
	for raw in ArenaRun.tower_status():
		if raw is Dictionary:
			var row: Dictionary = raw
			if int(row.get("hp", 0)) < int(row.get("max_hp", 0)):
				_saw_tower_damage = true


func _busy(body: Node2D) -> bool:
	for node in get_tree().get_nodes_in_group("arena_unit"):
		if node == body or not is_instance_valid(node) or not (node is Node2D):
			continue
		var other := node as Node2D
		if not bool(node.get("alive")):
			continue
		var kind := String(node.get("unit_kind"))
		if kind != "minion" and kind != "hero" and kind != "tower" and kind != "crystal" and kind != "elite":
			continue
		if absf(other.global_position.x - body.global_position.x) < 48.0:
			return true
	return false


func _finish(board: Dictionary) -> void:
	_quit = true
	var result: Dictionary = ArenaRun.match_result()
	_print_line("end", board)
	print("ARENA_SIM seed=%d outcome=%s elapsed=%.1f blue_towers=%s red_towers=%s blue_kills=%s red_kills=%s out_of_band=%d stuck_flags=%d tower_damaged=%s" % [
		ArenaCatalog.match_seed,
		String(result.get("outcome", ArenaRun.phase())),
		float(board.get("elapsed", 0.0)),
		str((board.get("blue", {}) as Dictionary).get("towers", 0)),
		str((board.get("red", {}) as Dictionary).get("towers", 0)),
		str((board.get("blue", {}) as Dictionary).get("kills", 0)),
		str((board.get("red", {}) as Dictionary).get("kills", 0)),
		_out,
		_stuck,
		str(_saw_tower_damage),
	])
	var code := 0
	if String(result.get("outcome", "")) == "":
		code = 1
	if _out > 0:
		code = 1
	get_tree().quit(code)


func _print_line(tag: String, board: Dictionary) -> void:
	var parts := PackedStringArray()
	for raw in ArenaRun.tower_status():
		if raw is Dictionary:
			var row: Dictionary = raw
			parts.append("%s-%s:%d" % [String(row.get("team", "")), String(row.get("kind", "")), int(row.get("hp", 0))])
	var blue_n := 0
	var red_n := 0
	var blue_x := 0.0
	var red_x := 0.0
	for node in get_tree().get_nodes_in_group("arena_unit"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		if String(node.get("unit_kind")) != "minion" or not bool(node.get("alive")):
			continue
		var body := node as Node2D
		if String(node.get("team")) == ArenaCatalog.TEAM_PLAYER:
			blue_n += 1
			blue_x += body.global_position.x
		elif String(node.get("team")) == ArenaCatalog.TEAM_ENEMY:
			red_n += 1
			red_x += body.global_position.x
	var blue_avg := 0.0
	var red_avg := 0.0
	if blue_n > 0:
		blue_avg = blue_x / float(blue_n)
	if red_n > 0:
		red_avg = red_x / float(red_n)
	print("ARENA_SIM %s t=%.0f minions=%d/%d x=%.0f/%.0f %s" % [tag, float(board.get("elapsed", 0.0)), blue_n, red_n, blue_avg, red_avg, " ".join(parts)])
