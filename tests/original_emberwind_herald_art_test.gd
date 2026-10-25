extends TestCase

const BOSS := preload("res://scenes/enemies/EmberwindHerald.tscn")


func test_original_mechanical_bird_frames_have_motion_and_transparency() -> void:
	for prefix in ["", "hot_"]:
		for action in ["idle", "dive", "wind_push", "feather_blades", "updraft", "downed"]:
			var key: String = prefix + action
			var frames := CharFrames.anim("original_emberwind_herald", key)
			eq(frames.size(), 4 if action == "downed" else 6, key)
			var poses := {}
			for texture in frames:
				var im := texture.get_image()
				eq(texture.get_size(), Vector2(192, 144))
				eq(im.get_size(), Vector2i(768, 576))
				almost(im.get_pixel(0, 0).a, 0.0, 0.001)
				ok(im.get_used_rect().has_area())
				poses[hash(im.get_data())] = true
			ok(poses.size() >= 2, "articulated motion in " + key)


func test_actual_attack_steps_and_facing_select_the_original_bird_poses() -> void:
	var boss := BOSS.instantiate() as Node2D
	add_child(boss)
	boss.set_physics_process(false)
	(boss.call("boss_director") as BossDirector).set_physics_process(false)
	var frames := boss.get_node("Visual/HeraldShell/OriginalHeraldFrames") as FrameAnimSprite
	var before: Vector2 = boss.get_node("Hurtbox").position
	for action in ["dive", "wind_push", "feather_blades", "updraft"]:
		boss.call("_begin_attack", StringName(action))
		for step in range(3):
			boss.set("_step", step)
			boss.call("_update_visuals", 0.1)
			eq(frames.current(), action)
			var path := frames.texture.resource_path
			ok(path.ends_with("_%d.png" % (step * 2)) or path.ends_with("_%d.png" % (step * 2 + 1)), "actual step pins " + action)
		boss.call("_interrupt_attack")
	boss.set("_facing", -1.0)
	boss.set("_enraged", true)
	boss.call("_update_visuals", 0.1)
	eq(frames.current(), "hot_idle")
	ok(frames.flip_h, "long beak faces the actual attack direction")
	eq(boss.get_node("Hurtbox").position, before, "art leaves combat collision unchanged")
	boss.queue_free()
	await flush(2)


func test_real_yank_folds_wings_above_the_floor() -> void:
	var host := Node2D.new()
	add_child(host)
	build_floor(host)
	var boss := BOSS.instantiate() as Node2D
	host.add_child(boss)
	boss.set_physics_process(false)
	(boss.call("boss_director") as BossDirector).set_physics_process(false)
	ok(boss.call("yank_to", Vector2.ZERO))
	boss.call("_update_visuals", 0.1)
	var frames := boss.get_node("Visual/HeraldShell/OriginalHeraldFrames") as FrameAnimSprite
	eq(frames.current(), "downed", "actual hook window uses folded wings")
	var used := frames.texture.get_image().get_used_rect()
	var lowest := float(used.end.y) / 4.0 - 72.0 + frames.position.y
	ok(lowest <= 1.0, "folded hull stays above actual ground; bottom=%f" % lowest)
	eq(frames.scale, Vector2.ONE, "native authored pixel size")
	host.queue_free()
	await flush(2)
