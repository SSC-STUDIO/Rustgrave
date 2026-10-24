extends TestCase

const BOSS := preload("res://scenes/enemies/CapstanWarden.tscn")


func setup() -> void:
	Director.abort()
	Director._set_lock(false)
	SaveData.flags.clear()


func test_all_warden_actions_are_original_and_animated() -> void:
	for action in ["idle", "guard", "charge", "sweep", "release", "hurt", "broken", "death"]:
		var frames := CharFrames.anim(CapstanWardenBoss.EXEC_CHAR, action)
		ok(frames.size() >= 3, action)
		var poses := {}
		for texture in frames:
			ok(texture.resource_path.contains("/original_capstan_warden/"))
			eq(texture.get_size(), Vector2(128,112))
			poses[hash(texture.get_image().get_data())] = true
		ok(poses.size() >= 3, "motion in " + action)


func test_warden_actual_sweep_and_break_use_the_new_art() -> void:
	var host := Node2D.new()
	add_child(host)
	build_floor(host)
	var boss := BOSS.instantiate() as CapstanWardenBoss
	host.add_child(boss)
	await flush(2)
	boss.set_physics_process(false)
	var anim := boss.get_node("Visual/BodySprite") as FrameAnimSprite
	eq(anim.scale, Vector2.ONE)
	ok(not anim.flip_h, "drawing is authored facing the chain anchor")
	boss._drive_id = &"chain_sweep"
	boss._drive = CapstanWardenBoss.Drive.ACTIVE
	boss._after_move()
	eq(anim.texture, CharFrames.anim(CapstanWardenBoss.EXEC_CHAR,"sweep")[2])
	boss._break_left = 0.4
	boss._after_move()
	eq(anim.current(), "broken")
	host.queue_free()
	await flush(2)
