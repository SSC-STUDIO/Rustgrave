extends Node
## Rendered fixture for finisher poise in the real first-chapter arena.
## Places the knight and two sword hits; this is not a normal-input playthrough.

const OUT := "res://screenshots/acceptance/overhaul-v3/p1-poise/render"
const ERRORS := preload("res://tests/error_collector.gd")
var report := {"purpose": "rendered poise fixture, not an input playthrough", "passed": false,
		"captures": [], "engine_errors": []}
var errors


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	errors = ERRORS.new()
	OS.add_logger(errors)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	SaveData.save_path = OUT + "/fixture.cfg"
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.mark_flag("wake")
	SaveData.mark_flag("opening_seen")
	GameContext.pending_world_path = GameContext.LEVELS["level01"]
	var window := get_tree().root
	window.size = Vector2i(1280, 720)
	window.position = Vector2i(-12000, -12000)
	Engine.max_fps = 60
	add_child(preload("res://scenes/ui/GamePresentation.tscn").instantiate())
	for i in 10:
		await RenderingServer.frame_post_draw
	Director.abort()
	Director.set_letterbox(false, true)
	var player := get_tree().get_first_node_in_group("player") as Player
	var camera := get_tree().get_first_node_in_group("game_camera") as GameCamera
	var boss: ExecutionerBoss
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
		if enemy is ExecutionerBoss:
			boss = enemy as ExecutionerBoss
	if boss == null or player == null or camera == null:
		report["error"] = "could not bind real chapter arena"
		_finish()
		return
	player.set_physics_process(false)
	player.cutscene_locked = false
	player.health.invincible = true
	player.global_position = boss.global_position + Vector2(75, 0)
	camera.set_physics_process(false)
	camera.global_position = boss.global_position + Vector2(-70, -100)
	camera.force_update_scroll()
	var director := boss.boss_director()
	director.set_physics_process(false)
	boss.announce()
	Director.abort()
	Director.set_letterbox(false, true)
	boss.call("_begin_slash")
	await _capture("01-windup")
	var blade := Hitbox.new()
	blade.riposte_eligible = true
	blade.blow = &"finisher"
	add_child(blade)
	blade.global_position = boss.global_position + Vector2(-boss._shield_facing * 50, -30)
	var hurt := boss.get_node("Hurtbox") as Hurtbox
	var hp_before := boss.health.current
	for i in 2:
		boss.health._hit_iframe = 0.0
		hurt.receive_hit(1, blade)
	report["damage_applied"] = hp_before - boss.health.current
	report["broken"] = director.is_poise_broken()
	report["recovery_seconds"] = boss._hurt_lock
	report["slash_disarmed"] = boss._slash_box == null and boss._final_box == null
	report["opening_visible"] = boss._opening_mark != null
	# Let the white hit flash and announcement settle while physics is parked.
	await get_tree().create_timer(0.2).timeout
	await _capture("02-broken")
	boss.set_physics_process(true)
	var frames := 0
	while boss.is_hurt_locked() and frames < 240:
		await get_tree().physics_frame
		frames += 1
	boss.set_physics_process(false)
	director.tick(CombatRules.BOSS_POISE_RECOVERY + 0.01)
	report["recovered"] = not boss.is_hurt_locked() and not director.is_poise_broken()
	report["phase_unchanged"] = director.phase == 1
	await _capture("03-recovered")
	report["passed"] = report.damage_applied == 2 and report.broken and report.slash_disarmed \
			and report.opening_visible and report.recovered and report.phase_unchanged
	_finish()


func _capture(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var path := OUT + "/" + tag + ".png"
	var code := get_tree().root.get_texture().get_image().save_png(path)
	if code != OK:
		push_error("poise capture failed: " + path)
	report.captures.append(ProjectSettings.globalize_path(path))


func _finish() -> void:
	report.engine_errors = errors.errors()
	report.passed = report.passed and report.engine_errors.is_empty()
	var file := FileAccess.open(OUT + "/report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("POISE ACCEPTANCE: ", JSON.stringify(report))
	OS.remove_logger(errors)
	SaveData.delete_save()
	get_tree().quit(0 if report.passed else 1)
