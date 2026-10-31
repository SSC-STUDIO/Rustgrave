extends TestCase
## 《ICEY》式叛逆行为检测器（DisobedienceTrigger）与真名残片（TruthFragmentPickup）测试：
##   1. STRIKE_SEAL：三刀递进语音、碎墙破封、解锁关联门与支线旗标；
##   2. CROSS_LINE：踏入越界感应区立即打断引导语音并解锁支线；
##   3. LINGER_IDLE：原地驻足超时触发催促语音；
##   4. MERCY_PASS：不挥剑通过触发仁慈支线，挥剑后抑制仁慈触发；
##   5. TruthFragmentPickup：集齐 5 枚残片自动解锁归零母模（stage08_true + true_ending_unlocked）。


func setup() -> void:
	SaveData.save_path = "user://rustgrave_test_save.cfg"
	SaveData.delete_save()
	StageRoomMemory.clear_all()
	NarrativeDirector.forget_session()
	if Director.narrative() != null:
		Director.narrative().test_enabled = true
	if Director.live_voice() != null:
		Director.live_voice().clear()


func teardown() -> void:
	if Director.narrative() != null:
		Director.narrative().test_enabled = false
	if Director.live_voice() != null:
		Director.live_voice().clear()
	NarrativeDirector.forget_session()
	SaveData.delete_save()
	SaveData.save_path = "user://rustgrave_save.cfg"
	StageRoomMemory.clear_all()


func test_strike_seal_three_hits_unlocks_branch_and_gate() -> void:
	var root := Node2D.new()
	add_child(root)

	var gate := RoomGate.new()
	gate.name = "SecretGate"
	gate.mode = RoomGate.Mode.INTERACT
	gate.target_stage = "branch01"
	gate.target_room = "B1"
	gate.set_locked(true)
	root.add_child(gate)

	var seal := DisobedienceTrigger.new()
	seal.name = "WestSeal"
	seal.mode = DisobedienceTrigger.Mode.STRIKE_SEAL
	seal.branch_id = "branch01"
	seal.max_hits = 3
	seal.voice_clips = PackedStringArray(["s1_r1_seal_hit_1", "s1_r1_seal_hit_2", "s1_r1_seal_break"])
	seal.linked_gate_path = NodePath("../SecretGate")
	root.add_child(seal)
	await flush(2)

	ok(not seal.broken, "seal intact initially")
	ok(not gate.is_gate_open(), "linked gate locked initially")
	ok(not NarrativeCatalog.is_node_unlocked("branch01", SaveData.flags), "branch01 locked initially")

	seal.apply_seal_strike()
	eq(seal.hits_taken, 1, "1st hit recorded")
	ok(not seal.broken, "seal still standing after 1st hit")
	eq(Director.live_voice().active_clip_id(), "s1_r1_seal_hit_1", "1st hit plays warning clip 1")

	seal.apply_seal_strike()
	eq(seal.hits_taken, 2, "2nd hit recorded")
	ok(not seal.broken, "seal still standing after 2nd hit")
	eq(Director.live_voice().active_clip_id(), "s1_r1_seal_hit_2", "2nd hit interrupts with clip 2")

	seal.apply_seal_strike()
	eq(seal.hits_taken, 3, "3rd hit recorded")
	ok(seal.broken, "3rd hit shatters seal wall")
	eq(Director.live_voice().active_clip_id(), "s1_r1_seal_break", "3rd hit plays break clip")
	ok(gate.is_gate_open(), "linked gate unlocked when seal breaks")
	ok(NarrativeCatalog.is_node_unlocked("branch01", SaveData.flags), "branch01 unlocked in SaveData")

	root.queue_free()
	await flush(2)


func test_cross_line_linger_and_mercy_modes() -> void:
	var world := Node2D.new()
	world.add_to_group("game_world")
	add_child(world)
	build_floor(world, 320.0)
	var player := await spawn_player(world, Vector2(120.0, -24.0))

	# 1. CROSS_LINE 越界解锁 branch02
	var cross := DisobedienceTrigger.new()
	cross.mode = DisobedienceTrigger.Mode.CROSS_LINE
	cross.branch_id = "branch02"
	cross.zone_size = Vector2(64.0, 80.0)
	cross.voice_clips = PackedStringArray(["s2_r4_disobey_pit"])
	cross.position = Vector2(240.0, 0.0)
	world.add_child(cross)

	# 2. LINGER_IDLE 驻足催促
	var linger := DisobedienceTrigger.new()
	linger.mode = DisobedienceTrigger.Mode.LINGER_IDLE
	linger.linger_seconds = 0.12
	linger.voice_clips = PackedStringArray(["s1_r1_linger"])
	world.add_child(linger)
	await flush(2)

	# 原地不动等待 linger 触发
	player.velocity = Vector2.ZERO
	var lingered := await wait_until(func() -> bool:
		return Director.live_voice().active_clip_id() == "s1_r1_linger", 30)
	ok(lingered, "LINGER_IDLE fires clip when player stands still")

	# 踏入越界区触发 CROSS_LINE
	player.global_position = Vector2(240.0, -16.0)
	await flush(4)
	ok(NarrativeCatalog.is_node_unlocked("branch02", SaveData.flags), "CROSS_LINE unlocks branch02")
	eq(Director.live_voice().active_clip_id(), "s2_r4_disobey_pit", "CROSS_LINE interrupts with disobedience voice")

	# 3. MERCY_PASS 不挥剑走过触发仁慈语音
	var mercy := DisobedienceTrigger.new()
	mercy.mode = DisobedienceTrigger.Mode.MERCY_PASS
	mercy.branch_id = "branch04"
	mercy.zone_size = Vector2(64.0, 80.0)
	mercy.voice_clips = PackedStringArray(["s6_r3_mercy_pass"])
	mercy.position = Vector2(420.0, 0.0)
	world.add_child(mercy)
	await flush(2)

	player.global_position = Vector2(420.0, -16.0)
	await flush(4)
	ok(NarrativeCatalog.is_node_unlocked("branch04", SaveData.flags), "MERCY_PASS unlocks branch04 when peaceful")

	world.queue_free()
	await flush(2)


func test_five_truth_fragments_unlock_true_ending_node() -> void:
	var world := Node2D.new()
	world.add_to_group("game_world")
	add_child(world)
	build_floor(world, 320.0)
	var player := await spawn_player(world, Vector2(160.0, -24.0))

	for i in range(1, 6):
		var pickup := TruthFragmentPickup.new()
		pickup.fragment_id = "truth_%d" % i
		pickup.branch_id = "branch0%d" % i
		pickup.auto_open_map = false
		pickup.position = Vector2(160.0 + float(i) * 24.0, 0.0)
		world.add_child(pickup)
		await flush(1)
		pickup.interact(player)
		ok(SaveData.has_flag("truth_%d" % i), "truth_%d recorded" % i)
		ok(SaveData.has_flag("branch0%d_done" % i), "branch0%d_done recorded" % i)
		if i < 5:
			ok(not SaveData.has_flag("true_ending_unlocked"), "true ending stays locked at %d/5" % i)

	eq(NarrativeCatalog.fragment_count(SaveData.flags), 5, "all 5 fragments collected")
	ok(SaveData.has_flag("true_ending_unlocked"), "5th fragment sets true_ending_unlocked")
	ok(NarrativeCatalog.is_node_unlocked("stage08_true", SaveData.flags), "stage08_true node unlocked at 5/5")

	world.queue_free()
	await flush(2)
