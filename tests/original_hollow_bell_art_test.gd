extends TestCase
## Original art integration: assets, actual attack-step pinning, and weakpoint alignment.

const BOSS := preload("res://scenes/enemies/HollowBell.tscn")


func test_complete_original_transparent_frame_sets() -> void:
	for prefix in ["", "hot_"]:
		for action in ["idle", "pendulum", "chain_pull", "bell_drop", "toll_wave", "stagger", "hammer"]:
			var key: String = prefix + action
			var frames := CharFrames.anim("original_hollow_bell", key)
			eq(frames.size(), 4 if action in ["idle", "stagger", "hammer"] else 6, key + " frame count")
			if not frames.is_empty():
				var image := frames[0].get_image()
				var logical := Vector2i(40, 64) if action == "hammer" else Vector2i(160, 336)
				eq(Vector2i(frames[0].get_size()), logical, key + " logical canvas")
				eq(image.get_size(), logical * 4, key + " physical canvas")
				almost(image.get_pixel(0, 0).a, 0.0, 0.001, key + " transparent corner")
				ok(image.get_used_rect().has_area(), key + " visible pixels")


func test_actual_attack_states_select_original_poses() -> void:
	var boss := BOSS.instantiate() as Node2D
	add_child(boss)
	boss.set_physics_process(false)
	var director := boss.call("boss_director") as BossDirector
	director.set_physics_process(false)
	var frames := boss.get_node("Visual/BellShell/OriginalBellFrames") as FrameAnimSprite
	for action in ["pendulum", "chain_pull", "bell_drop", "toll_wave"]:
		boss.call("_begin_attack", StringName(action))
		for step in range(3):
			boss.set("_step", step)
			boss.call("_update_visuals", 0.1)
			eq(frames.current(), action, action + " connected to real state")
			var path := frames.texture.resource_path
			ok(path.ends_with("_%d.png" % (step * 2)) or path.ends_with("_%d.png" % (step * 2 + 1)), action + " pins actual step")
		boss.call("_interrupt_attack")
	boss.set("_enraged", true)
	boss.call("_update_visuals", 0.1)
	eq(frames.current(), "hot_idle", "actual phase two selects fractured-hot art")
	boss.set("_state", 2)
	boss.call("_update_visuals", 0.1)
	eq(frames.current(), "hot_stagger", "actual weakpoint stagger selects stagger art")
	boss.queue_free()
	await flush(2)


func test_clapper_remains_separate_and_aligned_with_real_weakpoint() -> void:
	var boss := BOSS.instantiate() as Node2D
	add_child(boss)
	boss.set_physics_process(false)
	var weak := boss.get_node("WeakHurtbox") as Hurtbox
	var before := weak.position
	boss.call("_update_visuals", 0.1)
	var hammer := boss.get_node("Visual/Hammer") as Node2D
	ok(hammer.has_method("animate"), "independent clapper retains animation call")
	var frames := hammer.get_node("OriginalClapperFrames") as FrameAnimSprite
	ok(frames.texture != null, "clapper loads original pixels")
	ok(absf(hammer.position.y - weak.position.y) <= 6.0, "clapper root remains at actual weakpoint")
	eq(weak.position, before, "visual update never moves weak collision")
	eq((weak.get_node("CollisionShape2D").shape as RectangleShape2D).size, Vector2(40, 26), "weak collision size preserved")
	boss.queue_free()
	await flush(2)
