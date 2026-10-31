extends TestCase
## 14 节点 × 全房间多房拓扑与 LevelSanity 几何体检测试：
##   按三组并发友好的独立用例遍历全部 14 个 StageLevel 场景及 54 间紧凑房间，验证：
##   1. 房间列表与 NarrativeCatalog.STAGE_NODES 严丝合缝；
##   2. 每间房切入零报错、出生点在合法走廊内、所有 RoomGate 目标房间/目标节点均真实存在；
##   3. 每间房通过 LevelSanity 几何体检（无悬空道具/敌人、无埋没台面、无越界实体）。


func setup() -> void:
	SaveData.save_path = "user://rustgrave_test_save.cfg"
	SaveData.delete_save()
	StageRoomMemory.clear_all()
	SaveData.mark_flag("opening_done")


func teardown() -> void:
	SaveData.delete_save()
	SaveData.save_path = "user://rustgrave_save.cfg"
	StageRoomMemory.clear_all()


func test_main_spine_first_half_topology_and_sanity() -> void:
	var rooms := await _audit_nodes(["stage01", "stage02", "stage03", "stage04"])
	eq(rooms, 20, "stage01..stage04 total 20 rooms audited cleanly")


func test_main_spine_second_half_topology_and_sanity() -> void:
	var rooms := await _audit_nodes(["stage04b", "stage05", "stage06", "stage07"])
	eq(rooms, 15, "stage04b..stage07 total 15 rooms audited cleanly")


func test_rebellion_branches_and_true_core_sanity() -> void:
	var rooms := await _audit_nodes([
		"branch01", "branch02", "branch03", "branch04", "branch05", "stage08_true",
	])
	eq(rooms, 17, "branch01..branch05 + stage08_true total 17 rooms audited cleanly")


func _audit_nodes(node_ids: Array[String]) -> int:
	var total_rooms := 0
	for node_id in node_ids:
		ok(GameContext.LEVELS.has(node_id), "GameContext.LEVELS has %s" % node_id)
		var scene_path := String(GameContext.LEVELS[node_id])
		ok(ResourceLoader.exists(scene_path), "scene exists: %s" % scene_path)
		var packed := load(scene_path) as PackedScene
		ok(packed != null, "scene loads: %s" % scene_path)
		if packed == null:
			continue

		var stage := packed.instantiate() as StageLevel
		ok(stage != null, "%s instantiates as StageLevel" % node_id)
		if stage == null:
			continue
		stage.instant_room_transitions = true
		add_child(stage)
		await flush(2)

		eq(stage.stage_id, node_id, "stage_id matches %s" % node_id)
		var expected_rooms: Array = NarrativeCatalog.node_spec(node_id).get("rooms", [])
		var actual_rooms := stage.layout.room_ids()
		eq(actual_rooms.size(), expected_rooms.size(), "%s room count matches catalog" % node_id)

		for room_id in actual_rooms:
			total_rooms += 1
			stage.load_room_immediate(room_id, "west")
			await flush(1)
			eq(stage.current_room_id, room_id, "%s switched to room %s" % [node_id, room_id])

			var east := float(stage.layout.east_limit())
			var top_y := float(stage.layout.camera_top())
			var p := stage.get_node_or_null("Player") as Player
			ok(p != null, "%s/%s has Player" % [node_id, room_id])
			if p != null:
				ok(p.global_position.x >= 0.0 and p.global_position.x <= east,
						"%s/%s player x (%.1f) within 0..%.1f" % [node_id, room_id, p.global_position.x, east])

			for gate in _find_room_gates(stage):
				if gate.target_stage != "" and gate.target_stage != node_id:
					ok(NarrativeCatalog.STAGE_NODES.has(gate.target_stage),
							"%s/%s gate %s target_stage '%s' exists" % [node_id, room_id, gate.name, gate.target_stage])
					if gate.target_room != "":
						var target_rooms: Array = NarrativeCatalog.node_spec(gate.target_stage).get("rooms", [])
						ok(target_rooms.has(gate.target_room),
								"%s/%s gate %s target_room '%s' exists in %s" % [
									node_id, room_id, gate.name, gate.target_room, gate.target_stage])
				else:
					ok(actual_rooms.has(gate.target_room),
							"%s/%s gate %s intra-stage target_room '%s' exists" % [
								node_id, room_id, gate.name, gate.target_room])

			var limits := Rect2(0.0, top_y, east, 400.0 - top_y)
			var issues := LevelSanity.check(stage, limits)
			eq(issues.size(), 0, "%s/%s LevelSanity clean (issues: %s)" % [
				node_id, room_id, "; ".join(PackedStringArray(issues))])

		stage.queue_free()
		await flush(2)

	return total_rooms


func _find_room_gates(root: Node) -> Array[RoomGate]:
	var out: Array[RoomGate] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for ch in cur.get_children():
			if ch is RoomGate:
				out.append(ch as RoomGate)
			stack.append(ch)
	return out
