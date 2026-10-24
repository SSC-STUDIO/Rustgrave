extends "res://tools/input_walkthrough.gd"
## Continues the real new-game walkthrough through all 14 chapters. Geometry is
## read to choose inputs; the driver never moves actors or grants progress.

var _fight_tick := 0
var _final_caption_recorded := false

const GOAL_ORDER := {
	"level07": ["EmberNestEntry", "BellGatePlate", "EmberNestGallery", "EmberNestSummit", "Exit"],
	"level09b": ["EmberNestCliff", "EmberNestWind", "EmberNestFold", "EmberNestBridge",
		"WindGatePlate", "EmberNestOutpost", "EmberNestGate", "Exit"],
}


static func ordered_goals(id: String, goals: Array[Dictionary]) -> Array[Dictionary]:
	if not GOAL_ORDER.has(id):
		goals.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.feet.x < b.feet.x)
		return goals
	var ordered: Array[Dictionary] = []
	for name_ in GOAL_ORDER[id]:
		for goal in goals:
			if goal.name == name_: ordered.append(goal)
	return ordered


static func resume_goal_index(goals: Array[Dictionary], feet: Vector2) -> int:
	var best := -1
	var distance := 32.0
	for i in goals.size():
		if not String(goals[i].name).begins_with("EmberNest"): continue
		var gap: float = feet.distance_to(goals[i].feet)
		if gap < distance:
			distance = gap
			best = i
	return best

func _run() -> void:
	# Public settings only, in the runner's isolated user directory. No HP grants,
	# invulnerability, direct enemy damage, gate opening or progress mutation.
	Settings.set_value(&"assist_incoming", 0.5, false)
	Settings.set_value(&"assist_parry", 1.5, false)
	Settings.set_value(&"assist_toxin", 0.5, false)
	if not "--resume" in OS.get_cmdline_user_args():
		await super._run()
		return
	get_tree().change_scene_to_file(TITLE)
	await _frames(6)
	await _title_continue()
	if not await _wait_world(): return
	_record("resume_input_checkpoint")
	if not await _after_undercroft(): return
	_write_result(true)
	get_tree().quit(0)

func _after_undercroft() -> bool:
	# The full introductory route temporarily sockets ember instead of kiln.
	if not _player().inventory.has_ability(AbilityIds.HEAT_FORGE):
		await _tap(&"socket_2")
	if not _require(_player().inventory.has_ability(AbilityIds.HEAT_FORGE), "campaign has heat forge"): return false
	var start := maxi(1, GameContext.LEVEL_ORDER.find(GameContext.level_id_of(_player())))
	var resume_feet := _player().position
	for idx in range(start, GameContext.LEVEL_ORDER.size()):
		var id := GameContext.LEVEL_ORDER[idx]
		if not await _wait_world(): return false
		if not _require(GameContext.world_scene_path(_player()) == GameContext.LEVELS[id], "arrived in " + id): return false
		if _basic_abilities:
			if not _require(not _player().inventory.has_ability(AbilityIds.HOOKSHOT_TETHER) and not _player().inventory.has_ability(AbilityIds.EMBER_STEP), id + " uses basic abilities only"): return false
		_record(id + "_entry")
		var goals: Array[Dictionary] = []
		for node in _world().get_node("Props").get_children():
			if node is EmberNest or node is PressurePlate or node is RustyGate or node is LevelExit:
				goals.append({"name": str(node.name), "feet": LevelSanity.feet_of(node)})
		goals = ordered_goals(id, goals)
		var resume_at := resume_goal_index(goals, resume_feet)
		for goal_index in goals.size():
			var goal := goals[goal_index]
			if idx == start and "--resume" in OS.get_cmdline_user_args():
				if resume_at >= 0 and goal_index < resume_at: continue
			var node := _world().get_node_or_null("Props/" + goal.name)
			if node == null: continue
			var is_exit := node is LevelExit
			# Interacting may replace the scene and free the exit immediately.
			var has_ending_choice: bool = is_exit and id == "level10" and node.get("ending_choice") == true
			var is_plate := node is PressurePlate
			var is_gate := node is RustyGate
			if is_exit and id == "level10":
				if not await _nightmare(): return false
			var feet: Vector2 = goal.feet
			if is_gate: feet.x -= 28
			if is_exit: feet.x -= 12
			# Fight from the entrance side. Trying to reach the locked exit first
			# routes the knight through a live boss and can strand navigation.
			if is_exit and node is LevelExit:
				if not await _clear_gate_boss(node as LevelExit): return false
				node = _world().get_node_or_null("Props/" + goal.name)
				if node == null: return false
			if not await _navigate(feet): return false
			if is_exit and id == "level10": _skip_captions = false
			if not is_plate:
				await _tap(&"interact")
				await _frames(12)
				if has_ending_choice:
					if not _require(Director.choice_hold, "final ending menu opens through interact"): return false
					_ui(&"ui_accept") # Default final choice: give the sword.
					await _frames(12)
			else:
				await _frames(12)
			_record(id + "_" + goal.name)
			if goal.name == "EmberNestGallery" and id == "level07":
				if not await _continue_round_trip(id): return false
			if is_exit:
				var next := GameContext.LEVELS.get(GameContext.next_level_id(id), TITLE) as String
				if not await _await_scene(next): return false
	if not _require(SaveData.has_flag("game_complete") and SaveData.has_flag("nightmare_dead"), "final completion saved"): return false
	_record("campaign_complete")
	return true

func _world() -> Node:
	return GameContext.world_root(_player())

func _await_scene(path: String) -> bool:
	for i in 900:
		await _frames(1)
		if path == TITLE:
			if not _skip_captions and not _final_caption_recorded and Director.caption()._holding:
				await _frames(2)
				_record("final_caption")
				_final_caption_recorded = true
			if get_tree().current_scene != null and get_tree().current_scene.scene_file_path == TITLE: return true
		elif _player() != null and GameContext.world_scene_path(_player()) == path and GameContext.gameplay_input_enabled(): return true
	_fail("exit did not reach " + path)
	return false

func _continue_round_trip(id: String) -> bool:
	var checkpoint: Vector2 = SaveData.data["player"]["pos"]
	if not await _pause_return_to_title(): return false
	if not await _await_scene(TITLE): return false
	await _frames(6)
	await _title_continue()
	if not await _await_scene(GameContext.LEVELS[id]): return false
	if not _require(_player().position.distance_to(checkpoint) < 20, "continue restores saved checkpoint"): return false
	await _settle_fade()
	_record(id + "_continue")
	return true

func _settle_fade() -> void:
	for i in 120:
		if not Director.is_fading():
			await _frames(2)
			return
		await _frames(1)


## 标题菜单有存档时光标默认停在「继续」（scripts/ui/title_screen.gd:216-218）。
## 以前这里固定按一次 ↓，标题改成默认停在继续之后会落到「设置」。
func _title_continue() -> void:
	if not SaveData.has_save():
		_ui(&"ui_down")
		await _frames(3)
	_ui(&"ui_accept")

func _segments() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var solids := _nv_solids()
	for top in LevelSanity.top_segments(_world()):
		var name_ := top.owner_name.get_slice("@", 0)
		var lift := _world().get_node_or_null("Platforms/" + name_) as MovingPlatform
		if lift != null:
			out.append({"r": Rect2(top.x0, top.y, top.x1 - top.x0, 16), "lift": lift, "end": top.owner_name.ends_with("@end")})
			continue
		var spans: Array[Vector2] = [Vector2(top.x0, top.x1)]
		for r in solids:
			if r.position.y >= top.y - 3 or r.end.y < top.y - 26: continue
			var pieces: Array[Vector2] = []
			for span in spans:
				if r.position.x >= span.y or r.end.x <= span.x: pieces.append(span)
				else:
					if r.position.x - span.x >= 16: pieces.append(Vector2(span.x, r.position.x))
					if span.y - r.end.x >= 16: pieces.append(Vector2(r.end.x, span.y))
			spans = pieces
		for span in spans:
			if span.y - span.x >= 24: out.append({"r": Rect2(span.x, top.y, span.y - span.x, 16), "lift": null, "name": top.owner_name})
	for segment in out:
		segment.wet = false
		if GameContext.level_id_of(_player()) == "level02": continue
		for prop in _world().get_node("Props").get_children():
			if prop is ToxinPool:
				var pool: Rect2 = prop.surface_rect()
				var r: Rect2 = segment.r
				if r.position.y > pool.position.y and r.position.x < pool.end.x and r.end.x > pool.position.x: segment.wet = true
	return out

func _closest(segments: Array[Dictionary], feet: Vector2) -> int:
	var best := -1
	var score := INF
	for i in segments.size():
		var r: Rect2 = segments[i].r
		var value := absf(feet.y - r.position.y) * 4 + absf(feet.x - clampf(feet.x, r.position.x, r.end.x))
		if value < score:
			score = value
			best = i
	return best

func _link(a: Dictionary, b: Dictionary, solids: Array[Rect2] = []) -> bool:
	return _nv_link(a, b, solids)

func _path(segments: Array[Dictionary], feet: Vector2) -> Array[Dictionary]:
	var solids := _nv_solids()
	var start := _closest(segments, _player().position)
	var goal := _closest(segments, feet)
	var parents := {start: -1}
	var costs := {start: 0.0}
	var queue: Array[int] = [start]
	while not queue.is_empty():
		queue.sort_custom(func(a: int, b: int) -> bool: return costs[a] < costs[b])
		var at: int = queue.pop_front()
		if at == goal: break
		for i in segments.size():
			var cost: float = costs[at] + 10.0 + (200.0 if segments[i].wet else 0.0)
			if (not costs.has(i) or cost < costs[i]) and _link(segments[at], segments[i], solids):
				parents[i] = at
				costs[i] = cost
				if not i in queue: queue.append(i)
	if not parents.has(goal): return []
	var route: Array[Dictionary] = []
	while goal >= 0:
		route.push_front(segments[goal])
		goal = parents[goal]
	return route

func _plate_open_at(feet: Vector2) -> bool:
	for plate in _world().get_node("Props").get_children():
		if not plate is PressurePlate or LevelSanity.feet_of(plate).distance_to(feet) > 4: continue
		for connection in plate.activated.get_connections():
			var door = connection.callable.get_object()
			if door is ArenaDoor and door.is_open: return true
	return false

func _navigate(feet: Vector2, restore_plates: bool = true) -> bool:
	_step = "campaign_to_" + str(feet)
	for attempt in 30:
		_release()
		for i in 180:
			await _frames(1)
			if _player() != null and _player().health.current > 0 and _player().is_on_floor() and GameContext.gameplay_input_enabled(): break
		if _player() == null or _player().health.current <= 0: continue
		if _plate_open_at(feet): return true
		if restore_plates:
			var missing_plate := Vector2.INF
			for plate in _world().get_node("Props").get_children():
				if not plate is PressurePlate or LevelSanity.feet_of(plate).distance_to(feet) < 4: continue
				var plate_feet := LevelSanity.feet_of(plate)
				for connection in plate.activated.get_connections():
					var door = connection.callable.get_object()
					if door is ArenaDoor and not door.is_open and door.position.x > _player().position.x and door.position.x < feet.x:
						missing_plate = plate_feet
			if missing_plate != Vector2.INF:
				if not await _navigate(missing_plate, false): return false
		_step = "campaign_to_" + str(feet)
		_nv_goal = feet
		var route := _path(_segments(), feet)
		if route.is_empty():
			_fail("no navigation route to " + str(feet))
			return false
		var traversed := true
		for i in range(1, route.size()):
			if not await _cross(route[i - 1], route[i]):
				traversed = false
				break
		if traversed and await _flat(feet.x, feet.y):
			return true
		if _player() != null and _player().health.current > 0 and _plate_open_at(feet): return true
		print("[NAV RETRY] target=%s at=%s attempt=%d" % [feet, _player().position if _player() else Vector2.INF, attempt])
	_fail("navigation exhausted retries to " + str(feet))
	return false

func _flat(x: float, y: float, fight: bool = true) -> bool:
	if not fight: _release()
	for i in 900:
		var p := _player()
		if p == null or p.health.current <= 0: return false
		if _nv_grounded_near(x, y):
			_release()
			return true
		if absf(p.position.y - y) > 40: return false
		if p.is_on_floor() and HAZARD_POLICY.should_wait(LevelSanity.hazards(_world()),
				p.global_position, x, p.controller.max_speed):
			_release()
			_hazard_wait_frames += 1
			await _frames(1)
			continue
		_steer(x)
		var spitter_close := false
		var skeleton_ahead := false
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if enemy is SpitterEnemy and not enemy._dead and absf(enemy.position.y - p.position.y) < 14 and absf(enemy.position.x - p.position.x) < 64: spitter_close = true
			if enemy is EnemyBase and not enemy._dead and enemy.has_method("is_risen") and enemy.is_risen():
				var dx: float = enemy.position.x - p.position.x
				if absf(dx) < 70 and dx * (x - p.position.x) > 0 and absf(enemy.position.y - p.position.y) < 35: skeleton_ahead = true
		if fight or spitter_close or absf(x - p.position.x) > 96:
			_combat(absf(x - p.position.x) > 96)
		else:
			_set_action(&"attack", false)
			_set_action(&"dash", false)
		for gate in _world().get_node("Props").get_children():
			if gate is RustyGate and LevelSanity.feet_of(gate).distance_to(p.position) < 42:
				_set_action(&"interact", i % 30 == 0)
		_set_action(&"jump", (p.is_on_wall() or skeleton_ahead) and i % 36 < 24)
		await _frames(1)
	_release()
	return false

func _steer(x: float) -> void:
	_nv_steer(x)

func _combat(allow_dash: bool = true, hold_ground: bool = false) -> void:
	_fight_tick += 1
	var p := _player()
	var melt := false
	for gate in _world().get_node("Props").get_children():
		if gate is RustyGate and LevelSanity.feet_of(gate).distance_to(p.position) < 42: melt = true
	_set_action(&"interact", melt and _fight_tick % 30 == 0)
	var threat: EnemyBase
	var distance := 64.0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not e is EnemyBase or e._dead or absf(e.position.y - p.position.y) > 40: continue
		if e.has_method("is_risen") and not e.is_risen(): continue
		if e is GhostEnemy and not e.is_tangible(): continue
		var dx: float = absf(e.position.x - p.position.x)
		if dx < distance:
			distance = dx
			threat = e
	var attack := false
	var dash := false
	if _nv_guard_combat(threat, _fight_tick): return
	if threat != null:
		var side := signf(threat.position.x - p.position.x)
		if (threat.has_method("is_airborne") and threat.is_airborne()) or threat.has_method("is_risen") or threat is GhostEnemy:
			if hold_ground:
				_move(side if p.controller.facing != side else 0.0)
			attack = distance < 48 and p.controller.facing == side and _fight_tick % 20 == 0
			# Committing to a swing slows the knight and prevents the dash that
			# clears a skeleton's contact bite. Jump/dash past it while travelling.
			if threat.has_method("is_risen") and not hold_ground: attack = false
			dash = allow_dash and distance < 38 and _fight_tick % 6 == 0
		elif allow_dash and not threat is SpitterEnemy:
			var behind := threat.position.x + 28 - p.position.x
			_move(signf(behind) if absf(behind) > 6 else (-1.0 if p.controller.facing != -1 else 0.0))
			attack = distance < 38 and p.controller.facing == -1 and _fight_tick % 24 == 0
			dash = p.position.x < threat.position.x and distance < 42 and _fight_tick % 6 == 0
		else:
			var hold_distance := 30
			_move(side if distance > hold_distance or p.controller.facing != side else 0.0)
			attack = distance < 48 and p.controller.facing == side and _fight_tick % 20 == 0
	_set_action(&"attack", attack)
	_set_action(&"dash", dash)

func _cross(a: Dictionary, b: Dictionary) -> bool:
	# Use the same controller-aware crossing as chapter one: a lower overlapping
	# floor is reached by walking off the current ledge, and gaps need a run-up.
	_nv_vents = LevelSanity.hazards(_world())
	return await _nv_cross(a, b)

## 章节出口可能被 Boss 死亡旗标锁着（hollow_bell_dead / capstan_dead / choir_dead /
## founder_dead / herald_dead）。验收驱动必须像玩家一样真打：找到本章 Boss（实现
## boss_kit() 的敌人），回到竞技场把它打倒，再回来推门。
func _clear_gate_boss(exit: LevelExit) -> bool:
	var flag := String(exit.requires_flag)
	if flag == "" or SaveData.has_flag(flag): return true
	var boss := _gate_boss()
	if boss == null:
		# 没有 Boss 可打：门仍锁着就是布局/旗标问题，让后面的 interact 暴露出来。
		return true
	_step = "campaign_boss_" + flag
	print("[BOSS GATE] fighting %s for flag %s" % [boss.name, flag])
	var boss_label := String(boss.name)
	# 只给一次有界尝试：验收驱动不会为一场 Boss 无限重试（Boss 战正确性由
	# tests/<boss>_test.gd 与 tools/boss_fixture.gd 覆盖）。
	for i in 5400:
		if SaveData.has_flag(flag):
			_release()
			await _frames(60)
			await _settle_fade()
			_record(boss_label + "_slain")
			return true
		var p := _player()
		if p == null: return false
		if p.health.current <= 0 or not GameContext.gameplay_input_enabled():
			# 死了：等余烬巢复活再试（正常输入，不跳过战斗）。
			_release()
			for _wait in 600:
				await _frames(1)
				if _player() != null and _player().health.current > 0 and GameContext.gameplay_input_enabled(): break
			continue
		# Death replaces the whole level, including the boss. Read the current
		# actor every iteration instead of retaining a freed pre-death reference.
		boss = _gate_boss()
		if boss == null:
			await _frames(30)
			continue
		var feet: Vector2 = LevelSanity.feet_of(boss)
		var dx: float = boss.position.x - p.position.x
		var gap := absf(dx)
		if gap > 240.0 or absf(p.position.y - feet.y) > 48.0:
			var side := signf(dx) if absf(dx) > 1.0 else 1.0
			if not await _navigate(Vector2(boss.position.x - 120.0 * side, feet.y)): return false
			_step = "campaign_boss_" + flag
			continue
		if flag == "hollow_bell_dead":
			# The suspended hammer is above a ground swing. Jump into it with
			# normal attack inputs; successful weak hits create the real opening.
			_steer(boss.position.x - 28.0 * (1.0 if dx >= 0.0 else -1.0))
			if gap < 60.0:
				_move(signf(dx) if p.controller.facing != signf(dx) else 0.0)
			_set_action(&"jump", gap < 60.0 and i % 42 < 24)
			_set_action(&"attack", gap < 60.0 and i % 18 == 0)
			_set_action(&"dash", false)
			if i % 300 == 0:
				print("[BOSS GATE] %s hp=%d player=%s hp=%d" % [boss.name, boss.health.current, p.position, p.health.current])
			await _frames(1)
			continue
		# 出招中：拉开距离、必要时跳/冲躲判定；收招/空闲才贴身输出。
		var busy := false
		if boss.has_method("attack_name"):
			busy = String(boss.attack_name()) != "" and boss.get("_step") != 2
		if busy:
			var away := signf(-dx) if absf(dx) > 1.0 else 1.0
			if gap < 132.0: _move(away)
			_set_action(&"attack", false)
			_set_action(&"dash", gap < 84.0 and p.controller._dash_cd <= 0)
			_set_action(&"jump", p.is_on_floor() and gap < 110.0 and i % 21 == 0)
			await _frames(1)
			continue
		if gap > 52.0: _steer(boss.position.x - 32.0 * signf(dx))
		else: _combat(false, true)
		if i % 300 == 0:
			print("[BOSS GATE] %s hp=%d player hp=%d" % [boss.name, boss.health.current, p.health.current])
		await _frames(1)
	_fail("boss gate not won by the input robot (combat skill limit): " + flag)
	return false


## 本章的 Boss：Enemies/ 下实现 boss_kit() 的敌人（每章最多一个正式 Boss）。
func _gate_boss() -> EnemyBase:
	var enemies := _world().get_node_or_null("Enemies")
	if enemies == null: return null
	for e in enemies.get_children():
		if e is EnemyBase and not e._dead and e.has_method("boss_kit"):
			return e
	return null


func _nightmare() -> bool:
	var phases := {}
	var prepared_actor := 0
	for i in 18000:
		if SaveData.has_flag("nightmare_dead"):
			_release()
			await _frames(90)
			await _settle_fade()
			_record("nightmare_slain")
			if not await _nightmare_death_reload(): return false
			if not await _continue_round_trip("level10"): return false
			return _require(_world().get_node_or_null("Enemies/Nightmare") == null and SaveData.has_flag("nightmare_dead"), "Nightmare remains absent after Continue")
		var p := _player()
		if p == null or p.health.current <= 0 or not GameContext.gameplay_input_enabled():
			_release()
			await _frames(1)
			continue
		if p.get_instance_id() != prepared_actor:
			# Read the authored ring, not the previous finale's x1668/x1190.
			# Crossing above the horse uses the same ordinary jumps as the route.
			for name_ in ["RingGalleryWest", "RingGalleryInnerWest", "RingGalleryInnerEast", "RingGalleryEast", "RingStairEastMid", "RingStairEastLow"]:
				var feet := _nightmare_ring_feet(name_)
				if not _require(feet.is_finite(), "authored Nightmare ring span exists: " + name_): return false
				if not await _navigate(feet): return false
			prepared_actor = _player().get_instance_id()
			_record("nightmare_ring_approach")
			p = _player()
		_step = "nightmare_combat"
		var boss = _world().get_node_or_null("Enemies/Nightmare")
		if boss == null: return false
		var phase: int = boss.phase()
		if not phases.has(phase):
			_record({1: "nightmare_phase_one", 2: "nightmare_phase_two", 3: "nightmare_phase_three"}[phase])
			phases[phase] = true
		var perch := _world().get_node("Platforms/RingStairEastLow") as SolidPlatform
		var target := perch.position.x + 20.0
		var dx: float = boss.position.x - p.position.x
		_steer(target)
		if absf(p.position.x - target) < 4.0:
			_move(signf(dx) if p.controller.facing != signf(dx) else 0.0)
		var nearby := absf(dx) < 72.0
		for enemy in _world().get_node("Enemies").get_children():
			if enemy is EnemyBase and not enemy._dead and enemy.position.distance_to(p.position) < 72.0:
				nearby = true
		_set_action(&"attack", nearby and i % 12 == 0)
		_set_action(&"jump", p.position.y > perch.position.y + 6.0 and i % 36 < 24)
		_set_action(&"dash", false)
		if i % 180 == 0:
			print("[NIGHTMARE] player=%s hp=%d boss=%s hp=%d phase=%d state=%d" % [p.position, p.health.current, boss.position, boss.health.current, phase, boss.state()])
		await _frames(1)
	_fail("nightmare fight timed out")
	return false


func _nightmare_ring_feet(platform_name: String, rightmost: bool = true) -> Vector2:
	# Pillar seats and the altar dais sit on the gallery. Select the platform's
	# actual clear span, rather than targeting a buried nominal origin + 20px.
	# Use the far span in the travel direction to keep the route above the horse.
	var target := Vector2.INF
	for segment in _segments():
		if String(segment.get("name", "")) == platform_name:
			var rect: Rect2 = segment.r
			var candidate := Vector2(rect.position.x + minf(20.0, rect.size.x * 0.5), rect.position.y)
			if not target.is_finite() or (candidate.x > target.x if rightmost else candidate.x < target.x):
				target = candidate
	return target


func _nightmare_death_reload() -> bool:
	_step = "nightmare_death_reload"
	var actor_id := _player().get_instance_id()
	var hazard := _world().get_node("Props/SlagHallEast") as CyclicHazard
	var destination := hazard.global_position
	# A real cyclic slag jet remains after the encounter. Walk back through the
	# authored floor, stand in its active hitbox, and let normal damage kill us.
	# Keep the return on the ring until its west stair. The generic shortest
	# route can otherwise select a drop beside the east stair's solid soffit.
	for name_ in ["RingGalleryEast", "RingGalleryInnerEast", "RingGalleryInnerWest", "RingGalleryWest", "RingStairWestMid", "RingStairWestLow"]:
		var feet := _nightmare_ring_feet(name_, false)
		if not _require(feet.is_finite(), "authored Nightmare return span exists: " + name_): return false
		if not await _navigate(feet): return false
	var return_feet := _nightmare_ring_feet("ReturnE")
	if not _require(return_feet.is_finite(), "authored slag return balcony exists"): return false
	if not await _navigate(return_feet): return false
	_step = "nightmare_death_reload"
	if not _require(_player().get_instance_id() == actor_id, "survived return to the slag balcony"): return false
	var return_platform := _world().get_node("Platforms/ReturnE") as SolidPlatform
	var drop_x := return_platform.position.x - 16.0
	var cause := {"hazard_hits": 0, "fatal_hazard": false, "last_source": ""}
	var observe_hit := func(attacker: Node, victim: Node, _amount: int) -> void:
		if not is_instance_valid(victim) or victim.get_instance_id() != actor_id: return
		var source := attacker.get_parent() if is_instance_valid(attacker) else null
		var is_hazard := source is CyclicHazard and String(source.name) == "SlagHallEast"
		cause.last_source = str(source.get_path()) if source != null else "unknown"
		if is_hazard: cause.hazard_hits += 1
		if (victim as Player).health.current <= 0: cause.fatal_hazard = is_hazard
	GameEvents.hit.connect(observe_hit)
	var deaths_before := _deaths
	for i in 7200:
		var p := _player()
		if p != null and p.get_instance_id() != actor_id and p.health.current > 0 and GameContext.gameplay_input_enabled():
			_release()
			GameEvents.hit.disconnect(observe_hit)
			if not _require(_deaths > deaths_before and cause.fatal_hazard, "death was caused by a real cyclic hazard: " + JSON.stringify(cause)): return false
			if not _require(SaveData.has_flag("nightmare_dead") and _world().get_node_or_null("Enemies/Nightmare") == null, "Nightmare remains absent after death"): return false
			await _settle_fade()
			_record("nightmare_death_reload_verified")
			_records.back()["death_cause"] = cause
			return true
		if p != null and p.health.current > 0 and GameContext.gameplay_input_enabled():
			# The return balcony roofs over the slag. Drop through its real gap,
			# then walk beneath it to the jet instead of waiting safely overhead.
			_steer(drop_x if p.position.y < destination.y - 40.0 else destination.x)
			# Nearby corridor enemies still run normally. Clear their real bodies
			# with the sword so the required fatal hit can come from the slag.
			_combat(false, true)
			_set_action(&"jump", p.is_on_wall() and i % 36 < 24)
		else:
			_release()
		if i % 180 == 0 and p != null:
			print("[NIGHTMARE DEATH] player=%s hp=%d hazard=%s" % [p.position, p.health.current, destination])
		await _frames(1)
	GameEvents.hit.disconnect(observe_hit)
	_fail("could not verify normal hazard death after Nightmare")
	return false

func _record(name_: String) -> void:
	super(name_)
	if _rendered and (name_.begins_with("level") or name_.contains("nightmare") or name_ in ["campaign_complete", "final_caption"]):
		get_tree().root.get_texture().get_image().save_png("user://%s_%s.png" % [_ending, name_])
