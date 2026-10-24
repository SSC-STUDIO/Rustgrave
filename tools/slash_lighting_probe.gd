extends Node

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	SaveData.save_path = "user://slash-lighting-probe.cfg"
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.mark_flag("wake")
	SaveData.mark_flag("opening_seen")
	GameContext.pending_world_path = GameContext.LEVELS["level01"]
	var win := get_tree().root
	win.mode = Window.MODE_WINDOWED
	win.position = Vector2i(-12000, -12000)
	win.size = Vector2i(1280, 720)
	get_tree().current_scene = null
	call_deferred("_run")

func _run() -> void:
	get_tree().change_scene_to_file(GameContext.PRESENTATION_PATH)
	for i in 60:
		await get_tree().physics_frame
	Director.abort()
	Director.set_letterbox(false, true)
	var player := get_tree().get_first_node_in_group("player") as Player
	var camera := get_tree().get_first_node_in_group("game_camera") as GameCamera
	if player == null or camera == null:
		push_error("could not find player or camera")
		get_tree().quit(1)
		return
	# Set Night time and clear weather for identical sky and atmosphere
	WorldClock.set_time(0.78)
	WorldClock.set_weather(WorldClock.Weather.CLEAR, true)

	var b := get_tree().root.find_child("ExecutionerBoss", true, false) as ExecutionerBoss
	print("FOUND BOSS: ", b)
	if b != null:
		b.announce()
		b.global_position = Vector2(1840, 320)
		b.process_mode = Node.PROCESS_MODE_DISABLED
		for marker in b.get_children():
			if marker is Node2D and marker != b.visual and marker != b._presence and marker.name != "CollisionShape2D" and marker.name != "Hurtbox":
				marker.queue_free()
		var spr := b.visual.get_node_or_null("BodySprite") as Sprite2D
		if spr != null:
			spr.texture = load("res://assets/characters/gear_shield_executioner/idle/idle_0.png")
			spr.modulate = b._body_lift()
		if b.visual != null:
			b.visual.scale.x = 1.0 # Face towards player


	
	player.global_position = Vector2(1880, 320)
	camera.global_position = Vector2(Level01EastWing.ARENA_CENTER_X, 220)
	camera.set_physics_process(false)
	player.cutscene_locked = false
	player.visual.scale.x = -1.0 # Face left
	
	# Simulate J press
	Input.action_press(&"attack")
	for i in 2:
		await get_tree().physics_frame
	Input.action_release(&"attack")
	
	# Wait for active swing frame (frame 1 of attack1)
	for i in 60:
		await get_tree().physics_frame
		if player.melee.phase_name() == "active":
			break
	
	for i in 2:
		await get_tree().physics_frame
	
	for i in 4:
		await RenderingServer.frame_post_draw
	
	for i in 2:
		await RenderingServer.frame_post_draw
	
	_print_tree(get_tree().root)
	
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://screenshots/slash_lighting_preview.png")
	print("SAVED slash_lighting_preview.png")
	get_tree().quit(0)

func _print_tree(n: Node) -> void:
	if n.name == "ExecutionerBoss" or n is ExecutionerBoss:
		_dump_boss(n)
	for c in n.get_children():
		_print_tree(c)

func _dump_boss(b: Node) -> void:
	print("--- BOSS DUMP: ", b.name, " pos=", (b.global_position if "global_position" in b else b.position))
	_dump_rec(b, "  ")

func _dump_rec(n: Node, indent: String) -> void:
	var extra := ""
	if n is Sprite2D:
		extra = " tex=" + (n.texture.resource_path if n.texture else "null") + " mod=" + str(n.modulate) + " self_mod=" + str(n.self_modulate)
	elif n is AnimatedSprite2D:
		extra = " anim=" + str(n.animation) + " frame=" + str(n.frame)
	print(indent, n.name, " (", n.get_class(), ") vis=", (n.visible if "visible" in n else true), " pos=", (n.position if "position" in n else "none"), extra)
	for c in n.get_children():
		_dump_rec(c, indent + "  ")


