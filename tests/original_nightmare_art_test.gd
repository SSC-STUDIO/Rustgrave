extends TestCase

const BOSS := preload("res://scenes/enemies/NightmareBoss.tscn")


func setup() -> void:
	Director.abort()
	Director._set_lock(false)
	SaveData.flags.clear()
	Engine.time_scale = 1.0


func test_original_reliquary_horse_has_independent_art_and_full_moves() -> void:
	var previous := CharFrames.anim("boss_nightmare", "idle")[0].get_image().get_data()
	for action in ["idle", "gallop", "windup", "rest", "neigh", "quake", "heat_wave", "death"]:
		var frames := CharFrames.anim("original_nightmare", action)
		ok(frames.size() >= 5, action)
		var poses := {}
		for tex in frames:
			ok(tex.resource_path.contains("/original_nightmare/"))
			var im := tex.get_image()
			eq(tex.get_size(), Vector2(128,96))
			eq(im.get_size(), Vector2i(512,384))
			ok(im.get_data() != previous, "new drawing has no legacy horse pixels")
			poses[hash(im.get_data())] = true
		ok(poses.size() >= 3, "motion in " + action)


func test_real_ai_states_use_the_matching_new_poses() -> void:
	var host := Node2D.new()
	add_child(host)
	build_floor(host)
	var boss := BOSS.instantiate()
	host.add_child(boss)
	await flush(2)
	boss.set_physics_process(false)
	var anim := boss.get_node("Visual/BodySprite") as FrameAnimSprite
	for state in {0:"idle",1:"windup",2:"gallop",3:"rest",4:"neigh",5:"quake",6:"heat_wave"}:
		boss._state = state
		boss._timer = boss.windup_time
		boss._update_anim()
		var expected: String = {0:"idle",1:"windup",2:"gallop",3:"rest",4:"neigh",5:"quake",6:"heat_wave"}[state]
		eq(anim.current(), expected)
		ok(anim.texture.resource_path.contains("/original_nightmare/" + expected + "/"))
	eq(anim.scale, Vector2.ONE)
	host.queue_free()
	await flush(2)
