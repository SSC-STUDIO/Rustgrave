extends TestCase

const BOSS := preload("res://scenes/enemies/ExecutionerBoss.tscn")


func setup() -> void:
	Director.abort()
	Director._set_lock(false)
	SaveData.flags.clear()
	Engine.time_scale = 1.0


func test_original_frames_are_independent_of_the_guard_and_have_binary_alpha() -> void:
	var guard := CharFrames.anim("gear_shield_executioner", "idle")[0].get_image()
	for action in ["idle", "idle2", "summon", "attack", "skill", "death"]:
		var frames := CharFrames.anim(ExecutionerBoss.BOSS_CHAR, action)
		ok(frames.size() >= 4, action + " has authored poses")
		var distinct := {}
		for texture in frames:
			ok(texture.resource_path.contains("/original_executioner/"))
			var img := texture.get_image()
			eq(texture.get_size(), Vector2(100, 100), "logical canvas")
			eq(img.get_size(), Vector2i(400, 400), "physical QHD pixels")
			ok(img.get_data() != guard.get_data(), "independent drawing, not the guard")
			distinct[hash(img.get_data())] = true
			var alpha_ok := true
			var pixels := img.get_data()
			for i in range(3, pixels.size(), 4):
				if pixels[i] != 0 and pixels[i] != 255:
					alpha_ok = false
			ok(alpha_ok, "hard pixel transparency")
		ok(distinct.size() >= 3, action + " contains motion")


func test_actual_slash_visual_matches_windup_contact_and_recovery() -> void:
	var host := Node2D.new()
	add_child(host)
	build_floor(host)
	var boss := BOSS.instantiate() as ExecutionerBoss
	host.add_child(boss)
	await flush(2)
	boss.set_physics_process(false)
	var anim := boss.get_node("Visual/BodySprite") as FrameAnimSprite
	boss._begin_slash()
	boss._update_anim()
	var frames := CharFrames.anim(ExecutionerBoss.BOSS_CHAR, "attack")
	eq(anim.texture, frames[0], "windup starts with raised weapon")
	boss._tick_charge(ExecutionerBoss.SLASH_WINDUP + 0.01)
	boss._update_anim()
	eq(anim.texture, frames[4], "contact pose is held throughout live hitbox")
	await flush(2)
	eq(anim.texture, frames[4], "render clock cannot run ahead of physics")
	boss._slash_phase = ExecutionerBoss.SlashPhase.RECOVERY
	boss._slash_timer = ExecutionerBoss.SLASH_RECOVERY
	boss._update_anim()
	eq(anim.texture, frames[6], "recovery visibly withdraws the blade")
	almost(boss.drawn_feet_offset(), 0.0, 1.0)
	eq((anim.texture as Texture2D).get_width(), 100)
	host.queue_free()
	await flush(2)


func test_corpse_uses_the_original_animation() -> void:
	var host := Node2D.new()
	add_child(host)
	var boss := BOSS.instantiate() as ExecutionerBoss
	host.add_child(boss)
	await flush(2)
	boss.set_physics_process(false)
	var effects := GameContext.world_effects(boss)
	boss._spawn_death_corpse()
	await flush(1)
	var found := false
	for child in effects.get_children():
		if child is Sprite2D and child != boss:
			var sprite := child as Sprite2D
			if sprite.texture != null and sprite.texture.resource_path.contains("/original_executioner/death/"):
				found = true
				eq(sprite.scale, Vector2(2, 2))
				sprite.queue_free()
	ok(found, "death does not revert to a guard")
	host.queue_free()
	await flush(2)
