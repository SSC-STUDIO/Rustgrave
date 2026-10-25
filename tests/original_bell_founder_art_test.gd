extends TestCase

const BOSS := preload("res://scenes/enemies/BellFounder.tscn")


func test_complete_body_and_segmented_tool_frames() -> void:
	for prefix in ["", "hot_"]:
		for part in ["", "tool_"]:
			for action in ["idle", "hammer_slam", "mold_cast", "molten_pool", "bell_shard", "stagger"]:
				var key: String = prefix + part + action
				var frames := CharFrames.anim("original_bell_founder", key)
				eq(frames.size(), 4 if action in ["idle", "stagger"] else 6, key + " complete")
				if not frames.is_empty():
					var image := frames[0].get_image()
					eq(image.get_size(), Vector2i(128, 112), key + " canvas")
					almost(image.get_pixel(0, 0).a, 0.0, 0.001, key + " transparent background")
					ok(image.get_used_rect().has_area(), key + " original visible pixels")


func test_real_attack_steps_drive_body_and_independent_hammer() -> void:
	var boss := BOSS.instantiate() as Node2D
	add_child(boss)
	boss.set_physics_process(false)
	(boss.call("boss_director") as BossDirector).set_physics_process(false)
	var body := boss.get_node("Visual/FounderShell/OriginalFounderFrames") as FrameAnimSprite
	var tool := boss.get_node("Visual/FounderHammer/OriginalFounderToolFrames") as FrameAnimSprite
	for action in ["hammer_slam", "mold_cast", "molten_pool", "bell_shard"]:
		boss.call("_begin_attack", StringName(action))
		for step in range(3):
			boss.set("_step", step)
			boss.call("_update_visuals", 0.1)
			eq(body.current(), action, "body follows " + action)
			eq(tool.current(), "tool_" + action, "tool follows " + action)
			for sprite in [body, tool]:
				var path: String = sprite.texture.resource_path
				ok(path.ends_with("_%d.png" % (step * 2)) or path.ends_with("_%d.png" % (step * 2 + 1)), "true step pins pose")
		boss.call("_interrupt_attack")
	boss.set("_enraged", true)
	boss.call("_update_visuals", 0.1)
	eq(body.current(), "hot_idle", "phase two exposes furnace seams")
	boss.set("_broken_left", 1.0)
	boss.call("_update_visuals", 0.1)
	eq(body.current(), "hot_stagger", "real broken window selects cracked pose")
	eq(tool.current(), "hot_tool_stagger", "real broken window lowers tool")
	boss.queue_free()
	await flush(2)


func test_visual_calls_preserve_collision_and_swing_contracts() -> void:
	var boss := BOSS.instantiate() as Node2D
	add_child(boss)
	boss.set_physics_process(false)
	var collision := boss.get_node("CollisionShape2D") as CollisionShape2D
	var before := collision.position
	var shell := boss.get_node("Visual/FounderShell")
	var tool := boss.get_node("Visual/FounderHammer") as Node2D
	shell.call("set_hot", true)
	shell.call("crack")
	eq((shell.get_node("OriginalFounderFrames") as FrameAnimSprite).current(), "hot_stagger", "crack API still produces a visible response")
	tool.call("set_swing", 0.5)
	almost(tool.rotation, -0.25, 0.001, "existing real hammer swing remains effective")
	eq(collision.position, before, "visual calls do not move body collision")
	eq((collision.shape as RectangleShape2D).size, Vector2(30, 78), "original body shape unchanged")
	boss.queue_free()
	await flush(2)
