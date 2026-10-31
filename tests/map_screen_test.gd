extends TestCase
## 树状节点选关图（MapScreen）测试：
##   1. 14 节点树状画布（NodeTree）与顶缘冲孔带（Route）同步渲染，整像素对齐；
##   2. 真名残片计数从 0 / 5 实时刷新至 5 / 5；
##   3. 未解锁支线禁止跃迁；已解锁支线与归零母模可通过 teleport_to_selected() 跃迁并设置入口房间。


func setup() -> void:
	SaveData.save_path = "user://rustgrave_test_save.cfg"
	SaveData.delete_save()
	StageRoomMemory.clear_all()


func teardown() -> void:
	if get_tree() != null:
		get_tree().paused = false
	Director.resume()
	SaveData.delete_save()
	SaveData.save_path = "user://rustgrave_save.cfg"
	StageRoomMemory.clear_all()


func test_node_tree_fragments_alignment_and_teleport() -> void:
	var map := MapScreen.new()
	add_child(map)
	await get_tree().process_frame
	map.open()
	await get_tree().process_frame
	await get_tree().process_frame

	ok(map.visible, "MapScreen opens visible")
	ok(map.node_tree() != null, "NodeTreeCanvas is mounted")
	eq(map.truth_count_text(), "✦ 真名残片 0 / 5", "initial truth fragment counter is 0 / 5")

	var card := map.get_node_or_null("ModalRoot/Card") as Control
	ok(card != null, "ModalRoot/Card exists")
	if card != null:
		almost(card.position.x, roundf(card.position.x), 0.01, "Card x is integer-aligned")
		almost(card.position.y, roundf(card.position.y), 0.01, "Card y is integer-aligned")

	# 选中未解锁的 branch01：应拒绝跃迁
	map.select_node_id("branch01")
	eq(map.selected_chapter(), "branch01", "selected branch01")
	ok(not map.is_selected_unlocked(), "branch01 starts locked")
	ok(not map.can_teleport_selected(), "locked branch01 cannot teleport")
	ok(not map.teleport_to_selected(), "teleport_to_selected() returns false on locked node")

	# 解锁 branch01 + 集齐 5 枚残片并解锁归零母模后重新打开
	SaveData.unlock_node("branch01")
	for frag_id in NarrativeCatalog.FRAGMENT_IDS:
		SaveData.mark_flag(frag_id)
	SaveData.mark_flag("true_ending_unlocked")
	SaveData.unlock_node("stage08_true")

	var sink := [""]
	map.teleport_requester = func(path: String) -> void:
		sink[0] = path

	map.open()
	await get_tree().process_frame
	eq(map.truth_count_text(), "✦ 真名残片 5 / 5", "truth fragment counter updates to 5 / 5")

	map.select_node_id("branch01")
	ok(map.is_selected_unlocked(), "branch01 is now unlocked")
	ok(map.can_teleport_selected(), "branch01 can teleport")
	ok(map.teleport_to_selected(), "teleport_to_selected() succeeds for branch01")
	eq(sink[0], String(GameContext.LEVELS["branch01"]), "teleports to Branch01_Scrapyard.tscn")
	ok(StageRoomMemory.has_pending_for("branch01"), "StageRoomMemory has pending room for branch01")
	var pend := StageRoomMemory.consume_pending_for("branch01")
	eq(String(pend.get("room_id", "")), "B1", "branch01 entry room is B1")

	# 跃迁至隐藏真结局节点 stage08_true
	map.open()
	await get_tree().process_frame
	map.select_node_id("stage08_true")
	ok(map.can_teleport_selected(), "stage08_true can teleport at 5/5 fragments")
	ok(map.teleport_to_selected(), "teleport_to_selected() succeeds for stage08_true")
	eq(sink[0], String(GameContext.LEVELS["stage08_true"]), "teleports to Stage08_TrueCore.tscn")

	map.queue_free()
	await get_tree().process_frame
