extends TestCase

const BOSS := preload("res://scenes/enemies/SilentChoir.tscn")


func setup() -> void:
	Director.abort()
	Director._set_lock(false)
	SaveData.flags.clear()


func test_conductor_and_all_three_cantors_have_independent_frames() -> void:
	for action in ["idle","windup","cast","recover","hurt","broken","death"]:
		var frames := CharFrames.anim(SilentChoirBoss.GHOST_CHAR,action)
		ok(frames.size() >= 3,action)
		var poses := {}
		for texture in frames:
			ok(texture.resource_path.contains("/original_silent_choir/"))
			eq(texture.get_size(),Vector2(96,144))
			poses[hash(texture.get_image().get_data())] = true
		ok(poses.size() >= 3,"motion in " + action)
	var silhouettes := {}
	for i in 3:
		var source := "original_silent_choir/cantor_%d" % i
		var frames := CharFrames.anim(source,"idle")
		eq(frames.size(),4)
		eq(CharFrames.anim(source,"sing").size(),4)
		silhouettes[hash(frames[0].get_image().get_data())] = true
	eq(silhouettes.size(),3,"three original mask designs")


func test_live_conductor_and_cantors_use_their_original_pose_sources() -> void:
	var host := Node2D.new()
	add_child(host)
	var boss := BOSS.instantiate() as SilentChoirBoss
	host.add_child(boss)
	await flush(2)
	boss.set_physics_process(false)
	var anim := boss.get_node("Visual/BodySprite") as FrameAnimSprite
	eq(anim.scale,Vector2.ONE)
	boss._drive = SilentChoirBoss.Drive.ACTIVE
	boss._after_move()
	eq(anim.current(),"cast")
	for i in 3:
		var shell: Node = boss._shells[i]
		shell.sing_pulse()
		shell._process(0.01)
		ok(shell._sprite.texture.resource_path.contains("/cantor_%d/sing/" % i))
	host.queue_free()
	await flush(2)
