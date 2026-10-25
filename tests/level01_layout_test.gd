extends TestCase
## Level01 split: east wing still places heart/gate/Boss; story beats still fire.


func setup() -> void:
	SaveData.flags.clear()
	SaveData.pending_spawn = Vector2.INF
	Director.abort()
	Director.resume()
	Director.choice_hold = false


func teardown() -> void:
	SaveData.flags.clear()
	SaveData.pending_spawn = Vector2.INF
	Director.abort()
	Director.resume()
	Director.choice_hold = false
	if get_tree().paused:
		get_tree().paused = false


func test_teach_terrace_is_a_single_jump() -> void:
	almost(Level01Static.GROUND_TOP - Level01Static.TEACH_TERRACE_POS.y, Level01Static.STEP_RISE, 0.01)
	ok(Level01Static.STEP_RISE < Level01Static.JUMP_REACH, "32px step stays under the 37px jump")
	almost(Level01Static.TEACH_TERRACE_POS.y - Level01Static.TEACH_MID_Y, Level01Static.STEP_RISE, 0.01)
	var platforms := Node2D.new()
	platforms.name = "Platforms"
	add_child(platforms)
	var level := Level01Static.new()
	level.place_teach_layout(platforms)
	var terrace := platforms.get_node_or_null("TeachTerrace") as SolidPlatform
	ok(terrace != null, "teach terrace is placed")
	if terrace != null:
		eq(terrace.position, Level01Static.TEACH_TERRACE_POS)
		eq(terrace.size, Level01Static.TEACH_TERRACE_SIZE)
		# A turf cube standing on turf shows grass under grass; the mound sinks a
		# whole tile row into the ground so its earth covers the ground's grass.
		ok(terrace.position.y + terrace.size.y >= Level01Static.GROUND_TOP + 16.0,
				"terrace skirt reaches at least one tile below the ground top")
		var rows := int(terrace.size.y / 16.0)
		var skirt := 0
		for child in terrace.get_children():
			if child is Sprite2D and (child as Sprite2D).position.y >= float(rows - 1) * 16.0:
				skirt += 1
		ok(skirt >= 2, "the buried row is drawn (dirt over the ground's grass), not left empty")
	level.free()


func test_east_pit_steps_are_single_jump_readable() -> void:
	almost(320.0 - Level01EastWing.PIT_CROSS_POS.y, 32.0, 0.01, "pit stone is a 32px hop")
	ok(Level01EastWing.PIT_CLIMB_LEFT_POS.y - Level01EastWing.PIT_LIP_LEFT_POS.y <= 32.0,
			"left bank cap must be reachable from the water lip")
	ok(Level01EastWing.PIT_CLIMB_RIGHT_POS.y - Level01EastWing.PIT_STEP_LOW_POS.y <= 32.0,
			"right bank cap must be reachable from the water lip")
	almost(Level01EastWing.PIT_STEP_LOW_POS.y - Level01EastWing.PIT_STEP_HIGH_POS.y, 32.0, 0.01, "high step is +32px")
	ok(Level01EastWing.PIT_CROSS_POS.x >= 400.0 and Level01EastWing.PIT_CROSS_POS.x + Level01EastWing.PIT_CROSS_SIZE.x <= 512.0,
			"crossing stone sits over the pit, not the walkway")
	var host := _make_host()
	var wing := Level01EastWing.new()
	add_child(wing)
	wing.build(host)
	for pair in [
		["PitClimbLeft", Level01EastWing.PIT_CLIMB_LEFT_POS],
		["PitClimbRight", Level01EastWing.PIT_CLIMB_RIGHT_POS],
		["PitLipLeft", Level01EastWing.PIT_LIP_LEFT_POS],
		["PitCross", Level01EastWing.PIT_CROSS_POS],
		["PitStepLow", Level01EastWing.PIT_STEP_LOW_POS],
		["PitStepHigh", Level01EastWing.PIT_STEP_HIGH_POS],
	]:
		var node := host.get_node_or_null("Platforms/%s" % String(pair[0])) as SolidPlatform
		ok(node != null, "%s was placed" % String(pair[0]))
		if node != null:
			eq(node.position, pair[1])


func test_pit_escape_is_a_single_jump() -> void:
	ok(Level01EastWing.pit_floor_to_bank() <= Level01Static.JUMP_REACH,
			"pit floor to bank is within a held single jump")
	ok(Level01EastWing.water_to_bank() <= Level01Static.JUMP_REACH,
			"water film to bank is within a single jump")
	almost(Level01EastWing.PIT_WATER_Y - Level01EastWing.PIT_CLIMB_LEFT_POS.y, -8.0, 0.01,
			"climb lip is at the water film")
	ok(Level01EastWing.PIT_FLOOR_Y - Level01EastWing.PIT_CLIMB_LEFT_POS.y <= Level01Static.JUMP_REACH,
			"pit floor to water lip is a single jump")
	ok(Level01EastWing.PIT_CLIMB_LEFT_POS.y - Level01EastWing.PIT_BANK_Y <= Level01Static.JUMP_REACH,
			"water lip to bank is a single jump")
	almost(Level01EastWing.PIT_CLIMB_LEFT_POS.y + Level01EastWing.PIT_CLIMB_LEFT_SIZE.y,
			Level01EastWing.PIT_FLOOR_Y, 0.01, "left climb sits on the pit floor")
	almost(Level01EastWing.PIT_CLIMB_RIGHT_POS.y + Level01EastWing.PIT_CLIMB_RIGHT_SIZE.y,
			Level01EastWing.PIT_FLOOR_Y, 0.01, "right climb sits on the pit floor")
	ok(Level01EastWing.PIT_CLIMB_LEFT_POS.x >= Level01EastWing.PIT_X0 - 0.01)
	ok(Level01EastWing.PIT_CLIMB_RIGHT_POS.x + Level01EastWing.PIT_CLIMB_RIGHT_SIZE.x
			<= Level01EastWing.PIT_X1 + 0.01)
	var open_w := Level01EastWing.PIT_CLIMB_RIGHT_POS.x \
			- (Level01EastWing.PIT_CLIMB_LEFT_POS.x + Level01EastWing.PIT_CLIMB_LEFT_SIZE.x)
	ok(open_w > 14.0, "open sludge is wider than the knight so they are not crushed")


func test_old_toxin_pit_is_raised_to_jump_reach() -> void:
	var host := _make_host()
	var pit: SolidPlatform = preload("res://scenes/world/Platform.tscn").instantiate()
	pit.name = "ToxinPit"
	pit.skin = "ground"
	pit.position = Vector2(400, 368)
	pit.size = Vector2(112, 32)
	host.get_node("Platforms").add_child(pit)
	var wing := Level01EastWing.new()
	add_child(wing)
	wing.build(host)
	var tuned := host.get_node_or_null("Platforms/ToxinPit") as SolidPlatform
	ok(tuned != null, "pit floor remains")
	if tuned != null:
		almost(tuned.position.y, Level01EastWing.PIT_FLOOR_Y, 0.01)
		eq(tuned.size, Level01EastWing.PIT_FLOOR_SIZE)


func test_knight_can_jump_from_pit_floor_onto_climb_lip() -> void:
	var arena := Node2D.new()
	add_child(arena)
	_plat(arena, Vector2(0, 320), Vector2(400, 80))
	_plat(arena, Vector2(Level01EastWing.PIT_X0, Level01EastWing.PIT_FLOOR_Y),
			Level01EastWing.PIT_FLOOR_SIZE)
	_plat(arena, Level01EastWing.PIT_CLIMB_LEFT_POS, Level01EastWing.PIT_CLIMB_LEFT_SIZE)
	_plat(arena, Level01EastWing.PIT_CLIMB_RIGHT_POS, Level01EastWing.PIT_CLIMB_RIGHT_SIZE)
	# Include the bank caps: omitting them hid a real 48px exit wall.
	_plat(arena, Level01EastWing.PIT_LIP_LEFT_POS, Level01EastWing.PIT_LIP_LEFT_SIZE)
	_plat(arena, Level01EastWing.PIT_STEP_LOW_POS, Level01EastWing.PIT_STEP_LOW_SIZE)
	_plat(arena, Level01EastWing.PIT_STEP_HIGH_POS, Level01EastWing.PIT_STEP_HIGH_SIZE)
	_plat(arena, Vector2(512, 320), Vector2(200, 80))
	var pool := ToxinPool.new()
	pool.position = Vector2(Level01EastWing.PIT_X0, Level01EastWing.PIT_WATER_Y)
	arena.add_child(pool)
	pool.configure(Vector2(112, 32))
	eq(pool.surface_rect().position.y, Level01EastWing.PIT_WATER_Y)
	var player: Player = preload("res://scenes/player/Player.tscn").instantiate()
	player.position = Vector2(448, 348)
	arena.add_child(player)
	await flush(20)
	ok(player.is_on_floor(), "settled on the pit floor")
	ok(player.global_position.y > Level01EastWing.PIT_WATER_Y + 4.0, "started below the water lip")
	player.controller.call("_do_jump", player, false)
	player.controller._cut_armed = false
	var lip_top := Level01EastWing.PIT_CLIMB_LEFT_POS.y
	var landed := false
	for i in 48:
		player.controller._apply_gravity(player, 1.0 / 60.0)
		player.velocity.x = -player.controller.max_speed
		player.move_and_slide()
		player.controller.settle_after_slide(player)
		await get_tree().physics_frame
		if player.is_on_floor() and player.global_position.y <= lip_top + 2.0 \
				and player.global_position.x < 440.0:
			landed = true
			break
	ok(landed, "jump from the sludge lands on the left climb lip")
	if landed:
		player.controller.call("_do_jump", player, false)
		player.controller._cut_armed = false
		var banked := false
		for i in 48:
			player.controller._apply_gravity(player, 1.0 / 60.0)
			player.velocity.x = -player.controller.max_speed
			player.move_and_slide()
			player.controller.settle_after_slide(player)
			await get_tree().physics_frame
			if player.is_on_floor() and player.global_position.y <= Level01EastWing.PIT_BANK_Y + 2.0 \
					and player.global_position.x < Level01EastWing.PIT_X0 + 2.0:
				banked = true
				break
		ok(banked, "second hop from the water lip lands on the bank")


func _plat(parent: Node2D, pos: Vector2, size: Vector2) -> void:
	var p: SolidPlatform = preload("res://scenes/world/Platform.tscn").instantiate()
	p.skin = "ground"
	p.position = pos
	p.size = size
	parent.add_child(p)


## 玩法层墓园装饰：1 倍最近邻裁切，脚钉地面，不和路牌抢位。
func test_play_decor_is_integer_and_grounded() -> void:
	ok(Level01Static.PLAY_DECOR.size() >= 8, "west-to-east corridor keeps a full prop line")
	var packed := load("res://scenes/levels/Level01_Static.tscn") as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await flush(2)
	for item in Level01Static.PLAY_DECOR:
		var path := String(item[0])
		var feet: Vector2 = item[1]
		var scale_k := float(item[2])
		almost(scale_k, 1.0, 0.001, "%s is drawn at world 1x" % path.get_file())
		almost(feet.y, Level01Static.GROUND_TOP, 0.01, "%s feet sit on the ground top" % path.get_file())
		ok(ResourceLoader.exists(path), "%s exists" % path)
		if path.get_file().begins_with("tree-") or path.get_file().begins_with("bush-large"):
			ok(path.contains("/normalized/props/"),
					"%s uses a pre-cropped 1x prop, not a fractional runtime scale" % path.get_file())
	var layer := level.get_node_or_null("GraveDecor") as Node2D
	ok(layer != null, "GraveDecor layer is planted")
	if layer == null:
		return
	var grounded := 0
	for node in layer.get_children():
		if node.is_in_group("grounded"):
			grounded += 1
			var feet_meta: Vector2 = node.get_meta("feet")
			almost(feet_meta.y, Level01Static.GROUND_TOP, 0.5,
					"%s meta feet stay on the ground line" % node.name)
			if node is Sprite2D:
				eq((node as Sprite2D).scale, Vector2.ONE, "%s sprite stays 1x" % node.name)
				almost(Level01Env.sprite_opaque_bottom_y(node as Sprite2D), feet_meta.y, 1.01,
						"%s opaque pixels sit on its feet, not on transparent padding" % node.name)
			elif node.get_child_count() > 0 and node.get_child(0) is Sprite2D:
				eq((node.get_child(0) as Sprite2D).scale, Vector2.ONE,
						"%s foliage sprite stays 1x" % node.name)
				eq((node as Node2D).position, feet_meta,
						"%s pivot origin is its foot point" % node.name)
	ok(grounded >= Level01Static.PLAY_DECOR.size(), "every play-decor prop is grounded")


## 角色接地（docs/art-spec.md）：玩家节点原点就是脚点（碰撞盒底边），
## 站在整数像素上；重力和相机都以这个脚点为准。
func test_player_origin_is_the_foot_point() -> void:
	var packed := load("res://scenes/levels/Level01_Static.tscn") as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await flush(2)
	var player := get_tree().get_first_node_in_group("player") as CharacterBody2D
	ok(player != null, "level spawns the knight")
	if player == null:
		return
	eq(player.z_index, 0, "the knight lives on the play canvas (z=0)")
	var col := player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	ok(col != null, "player has a body collision shape")
	if col != null:
		var rect := col.shape as RectangleShape2D
		ok(rect != null)
		if rect != null:
			almost(col.position.y + rect.size.y * 0.5, 0.0, 0.01,
					"collision bottom == node origin y (feet at origin)")
			almost(col.position.x, 0.0, 0.01, "collision is centred on the origin")
	eq(player.position, player.position.round(), "the foot point stays on the pixel grid")


func test_waymarks_name_the_route() -> void:
	eq(Level01Static.WAYMARKS.size(), 4)
	var labels: Array[String] = []
	for item in Level01Static.WAYMARKS:
		var feet: Vector2 = item[0]
		almost(feet.y, Level01Static.GROUND_TOP, 0.01, "%s sits on the ground top" % String(item[1]))
		ok(feet.x < 400.0 or feet.x >= 512.0, "%s is not planted in the pit" % String(item[1]))
		ok(feet.x < Level01EastWing.EAST_LIMIT - 80.0, "%s keeps off the east wall" % String(item[1]))
		labels.append(String(item[1]))
	ok(labels.has("腐液"))
	ok(labels.has("东翼"))
	ok(labels.has("压板"))
	ok(labels.has("余烬"))
	# The words are written on the plank, not floating above the post.
	var packed := load("res://scenes/levels/Level01_Static.tscn") as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await flush(1)
	var sign := level.get_node_or_null("Waymarks/Sign_余烬") as Node2D
	ok(sign != null, "waymark node exists")
	if sign == null:
		return
	var board := sign.get_node_or_null("Board") as Sprite2D
	var text := sign.get_node_or_null("Text") as Label
	ok(board != null and text != null)
	if board == null or text == null:
		return
	eq(DensityTextures.source_path(board.texture), Level01Static.SIGN_TEX, "1x waymark plank, not the 70px Kenney sign")
	eq(board.scale, Vector2.ONE, "plank is drawn at world 1x")
	almost(board.position.y + float(board.texture.get_height()), 0.0, 0.01, "post foot on the ground line")
	var plank := Rect2(board.position + Level01Static.SIGN_PLANK.position, Level01Static.SIGN_PLANK.size)
	var text_rect := Rect2(text.position, text.size)
	ok(plank.encloses(text_rect), "label rect sits inside the plank face")
	eq(text.get_theme_font_size("font_size"), Level01Static.SIGN_FONT_SIZE, "pixel font at its native 12px")
	eq(text.horizontal_alignment, HORIZONTAL_ALIGNMENT_CENTER)
	eq(text.position, text.position.round(), "label origin is on the pixel grid")


## The ember hook must pull the knight past the ledge's edge and drop them on
## top of it. With the anchor centred over the ledge, the pull line clipped the
## ledge's underside and the tether popped off (input walkthrough failed here).
func test_ember_hook_pull_clears_the_ledge_and_lands_on_it() -> void:
	var tether := HookshotTether.new()
	var ledge := Rect2(Level01EastWing.EMBER_LEDGE_POS, Level01EastWing.EMBER_LEDGE_SIZE)
	var anchor := Level01EastWing.EMBER_HOOK_POS
	const HALF_W := 7.0    # Player body 14x26, feet at origin
	const BODY_H := 26.0
	ok(anchor.x + HALF_W < ledge.position.x, "anchor sits outside the ledge's left edge, so the pull never clips it")
	ok(anchor.y < ledge.position.y - 40.0, "anchor is high enough above the ledge to pop off over it")
	# Launch as the walkthrough does: jump from the approach floor, fire mid-air.
	# 旧阁的发射点 (1447,271) 在锚点左 65px、地面上方 49px：新阁沿用同一相对位置。
	var pos := Vector2(anchor.x - 65.0, 271.0)
	var dir := (anchor - pos).normalized()
	var released := false
	for i in 120:
		var to_anchor := anchor - pos
		if to_anchor.length() <= tether.release_radius:
			released = true
			break
		pos += dir * tether.pull_speed / 60.0
		var body := Rect2(pos.x - HALF_W, pos.y - BODY_H, HALF_W * 2.0, BODY_H)
		ok(not body.intersects(ledge), "pull path clears the ledge at %s" % pos)
	ok(released, "the tether reaches its release radius")
	# Pop-off as HookshotTether._pop_off does, then a plain fall (no air input).
	var vel := dir * tether.pull_speed
	vel.x = vel.x * 0.5 + 130.0
	vel.y = tether.release_pop
	var landed := false
	for i in 120:
		var g := 980.0 if vel.y < 0.0 else 980.0 * 1.85
		vel.y += g / 60.0
		pos += vel / 60.0
		if vel.y > 0.0 and pos.y >= ledge.position.y and pos.x >= ledge.position.x and pos.x <= ledge.end.x:
			landed = true
			break
		if pos.y > ledge.end.y + 8.0:
			break
	ok(landed, "after popping off the knight comes down on the ledge (%s)" % pos)
	tether.free()


func test_east_constants_stay_aligned() -> void:
	eq(Level01Static.EAST_LIMIT, Level01EastWing.EAST_LIMIT)
	almost(Level01Static.EAST_FLOOR_X, Level01EastWing.EAST_FLOOR_X, 0.01)
	var r := Level01EastWing.east_floor_rect()
	almost(r.position.x, Level01EastWing.EAST_FLOOR_X, 0.01)
	almost(r.end.x, float(Level01EastWing.EAST_LIMIT), 0.01, "east floor meets WallRight")
	ok(r.size.x > 608.0, "old 608px floor left a 32px pit")


func test_east_wing_places_heart_gate_and_boss() -> void:
	var host := _make_host()
	var wing := Level01EastWing.new()
	add_child(wing)
	var boss := wing.build(host)
	ok(boss != null, "fresh run spawns Executioner")
	ok(is_instance_valid(boss))
	var heart := host.get_node_or_null("Props/ForgeHeart") as ForgeHeart
	ok(heart != null, "ForgeHeart lives on Props")
	ok(not heart.unlocked, "heart stays locked while boss lives")
	ok(host.get_node_or_null("BossGate") != null, "BossGate on the level root")
	ok(host.get_node_or_null("Pickups/EmberCore") != null, "east ember pickup has a stable save path")
	var east_nest := host.get_node_or_null("Props/EmberNestEast") as EmberNest
	ok(east_nest != null, "a checkpoint waits before the boss gate")
	if east_nest != null:
		eq(east_nest.position, Level01EastWing.EMBER_NEST_EAST_POS)
		var gate_x: float = host.get_node("BossGate").position.x
		ok(east_nest.position.x < gate_x, "east nest is outside the arena, west of the gate")
		ok(gate_x - east_nest.position.x <= 80.0, "the death run-back to the gate is <= 80px")
		almost(east_nest.position.y, Level01EastWing.NAVE_Y - 14.0, 0.01, "brazier feet sit on the nave floor")
	var shelter := host.get_node_or_null("ForgeShelter") as AtmosphereZone
	ok(shelter != null, "forge remnant is an indoor AtmosphereZone")
	if shelter != null:
		eq(shelter.zone, WorldClock.Zone.INDOORS)
		eq(shelter.position, Level01EastWing.FORGE_SHELTER_POS)
	eq(host.get_node("BossGate").position, Level01EastWing.BOSS_GATE_POS)
	eq(heart.position, Level01EastWing.HEART_POS)
	almost(boss.position.y, Level01EastWing.STAGE_Y, 0.01, "the Executioner stands on the stage top")
	var wall := host.get_node("Platforms/WallRight") as Node2D
	almost(wall.position.x, float(Level01EastWing.EAST_LIMIT), 0.01, "WallRight moved to east limit")
	var placed := false
	for child in host.get_node("Platforms").get_children():
		if child is SolidPlatform and absf(child.position.x - Level01EastWing.EAST_FLOOR_X) < 0.1 \
				and child.size.y >= 48.0:
			almost(child.position.x + child.size.x, float(Level01EastWing.EAST_LIMIT), 0.01,
					"spawned east floor meets the wall")
			ok(child.size.x > 608.0, "spawned floor is not the old 608px span")
			placed = true
	ok(placed, "east floor platform was placed")


func test_east_wing_skips_boss_and_unlocks_heart() -> void:
	SaveData.mark_flag("boss_dead")
	var host := _make_host()
	var wing := Level01EastWing.new()
	add_child(wing)
	var boss := wing.build(host)
	ok(boss == null, "flagged run skips Executioner")
	var heart := host.get_node_or_null("Props/ForgeHeart") as ForgeHeart
	ok(heart != null)
	ok(heart.unlocked, "flagged run lights the heart")


func test_first_toxin_records_story_without_taking_control() -> void:
	var beats := _bind_beats()
	GameEvents.toxin_changed.emit(12.0, 100.0)
	ok(SaveData.has_flag("toxin"))
	ok(not Director.playing, "first toxin leaves the Director free")
	ok(not Director.is_input_locked(), "the player can climb out of the pool")
	GameEvents.toxin_changed.emit(40.0, 100.0)
	eq(SaveData.flags.count("toxin"), 1, "repeat toxin does not re-flag")
	beats.queue_free()


func test_first_core_stages_but_parry_leaves_the_reward_window_playable() -> void:
	var beats := _bind_beats()
	GameEvents.core_acquired.emit(AbilityCatalog.ember_core())
	ok(SaveData.has_flag("core"))
	ok(Director.playing, "first core queues Director")
	Director.abort()
	GameEvents.parried.emit(null, null)
	ok(SaveData.has_flag("parry"))
	ok(not Director.playing, "first parry does not interrupt the fight")
	ok(not Director.is_input_locked(), "the player can use the parry reward")
	beats.queue_free()


func test_wake_cutscene_marks_flag() -> void:
	var saved_path := SaveData.save_path
	SaveData.save_path = "user://rustgrave_level01_wake_test.cfg"
	SaveData.delete_save()
	SaveData.pending_spawn = Vector2.INF
	SaveData.entering_from_checkpoint = false
	OpeningCinematic.reset()
	var beats := _bind_beats()
	beats.try_wake()
	ok(not SaveData.has_flag("wake"), "wake is marked when the opening ends, not when it starts")
	ok(Director.playing, "first wake queues Director")
	var event := InputEventAction.new()
	event.action = "ui_accept"
	event.pressed = true
	Director._unhandled_input(event)
	ok(not Director.playing, "one skip ends the whole opening")
	ok(SaveData.has_flag("wake"))
	ok(SaveData.has_flag(OpeningCinematic.FLAG))
	beats.try_wake()
	ok(not Director.playing, "second wake is an announcement, not a script")
	beats.queue_free()
	Director.abort()
	OpeningCinematic.reset()
	SaveData.delete_save()
	SaveData.save_path = saved_path


func test_boss_slain_unlocks_heart_and_plays() -> void:
	var host := _make_host()
	var wing := Level01EastWing.new()
	add_child(wing)
	wing.build(host)
	var beats := Level01StoryBeats.new()
	add_child(beats)
	beats.bind(host, null, wing.boss)
	beats.on_boss_slain()
	ok(SaveData.has_flag("boss_dead"))
	var heart := host.get_node("Props/ForgeHeart") as ForgeHeart
	ok(heart.unlocked, "slain beat unlocks the heart")
	ok(Director.playing, "slain beat queues Director")


## Every grounded enemy stands on a real platform top, and no enemy is drawn
## twice: a turret hovering in the air or a second body sprite reads as a bug.
func test_enemies_stand_on_platforms_and_are_not_duplicated() -> void:
	var packed := load("res://scenes/levels/Level01_Static.tscn") as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await flush(2)
	var platforms: Array[SolidPlatform] = []
	for node in level.find_children("*", "SolidPlatform", true, false):
		platforms.append(node as SolidPlatform)
		# A `#` comment inside a .tscn node block eats the next property; Plat_760_184
		# once lost its position this way and sat at the origin with its spitter in mid-air.
		ok((node as Node2D).position != Vector2.ZERO or node.name == "WallLeft",
				"%s kept its authored position (not the origin)" % node.name)
	ok(platforms.size() > 10, "authored platforms are present")
	var seen: Array[EnemyBase] = []
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as EnemyBase
		if enemy == null or not level.is_ancestor_of(enemy):
			continue
		var bodies := 0
		for child in enemy.find_children("*", "FrameAnimSprite", true, false):
			if (child as CanvasItem).is_visible_in_tree():
				bodies += 1
		ok(bodies <= 1, "%s draws at most one body sprite (found %d)" % [enemy.name, bodies])
		for other in seen:
			if other.get_script() == enemy.get_script():
				ok(other.global_position.distance_to(enemy.global_position) > 24.0,
						"%s and %s are not stacked on the same spot" % [other.name, enemy.name])
		seen.append(enemy)
		if enemy is FlyingDemonEnemy:
			continue
		# Turrets are authored exactly on a top; walkers settle through physics.
		var slack := 0.5 if not enemy._mobile else 4.0
		var footing: SolidPlatform = null
		for plat in platforms:
			var top := plat.global_position.y
			var x0 := plat.global_position.x
			var x1 := x0 + plat.size.x
			if absf(top - enemy.global_position.y) <= slack and enemy.global_position.x >= x0 and enemy.global_position.x <= x1:
				footing = plat
				break
		ok(footing != null, "%s at %s has a platform under its feet, not thin air" % [enemy.name, enemy.global_position])
		if footing != null and enemy is SpitterEnemy:
			var sprites := 0
			for child in footing.get_children():
				if child is Sprite2D and (child as Sprite2D).is_visible_in_tree():
					sprites += 1
			ok(sprites > 0, "%s's ledge %s is actually drawn" % [enemy.name, footing.name])


func test_wall_plates_stand_on_floors() -> void:
	var packed := load("res://scenes/levels/Level01_Static.tscn") as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await flush(2)
	var tops := LevelSanity.top_segments(level)
	var found := 0
	for root_name in ["BastionDecor", "CathedralDecor"]:
		var root := level.get_node_or_null(root_name)
		ok(root != null, "%s exists" % root_name)
		if root == null:
			continue
		for node in root.get_children():
			if not _is_wall_plate(node):
				continue
			found += 1
			var rect := _wall_rect(node as Node2D)
			var foot := Vector2(rect.get_center().x, rect.end.y)
			ok(LevelSanity.standing_on(tops, foot) != null,
					"%s bottom-centre %s stands on a floor" % [node.name, foot])
			var hang := _wall_overhang(rect, tops)
			ok(hang <= 8.0, "%s hangs %.0f px past the floor under %s" % [node.name, hang, foot])
	# West: 2 bastion rails. East: door_arch, 2 nave rails, forge altar, 1 shelter torch.
	# Tall indoor plates (columns / skull / gargoyle / nave torch slabs) stay off the open sky.
	ok(found >= 6, "bastion rails and forge-remnant plates are present (%d)" % found)
	var bastion := level.get_node_or_null("BastionDecor")
	if bastion != null:
		for node in bastion.get_children():
			ok(not (node is TorchLight), "open cemetery keeps the moon; no flat torch wall")
	var cathedral := level.get_node_or_null("CathedralDecor")
	if cathedral != null:
		var nave_torches := 0
		for node in cathedral.get_children():
			if node is TorchLight:
				nave_torches += 1
			var path := _wall_tex_path(node)
			ok(not path.ends_with("column_big.png"), "no cathedral column against outdoor sky")
			ok(not path.ends_with("bg_column_skulls.png"), "no skull column against outdoor sky")
			ok(not path.ends_with("bg_gargoyle.png"), "no gargoyle monolith against outdoor sky")
		eq(nave_torches, 1, "only the forge-shelter torch plate remains")


## EmberLedge is a thin floating skin at y=112 for the hook-shot pickup. Tall
## cathedral wall plates on or beside that ledge read as floating masonry against
## the mountains at the East Wing waymark. Keep the ledge; strip those plates.
func test_ember_ledge_carries_no_tall_wall_plate() -> void:
	var packed := load("res://scenes/levels/Level01_Static.tscn") as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await flush(2)
	var ledge := level.get_node_or_null("Platforms/EmberLedge") as SolidPlatform
	ok(ledge != null, "ember ledge remains for the hook / ember core")
	if ledge == null:
		return
	eq(ledge.skin, "floating")
	eq(ledge.position, Level01EastWing.EMBER_LEDGE_POS)
	var ledge_rect := Rect2(ledge.global_position, ledge.size)
	ok(level.get_node_or_null("CathedralDecor/EmberGargoyle") == null,
			"no gargoyle monolith near the East Wing sky ledge")
	var decor := level.get_node_or_null("CathedralDecor")
	ok(decor != null)
	if decor == null:
		return
	for node in decor.get_children():
		if not _is_wall_plate(node):
			continue
		var rect := _wall_rect(node as Node2D)
		var foot := Vector2(rect.get_center().x, rect.end.y)
		ok(not ledge_rect.has_point(foot),
				"%s must not stand on EmberLedge (foot %s)" % [node.name, foot])
		ok(foot.y >= Level01Static.GROUND_TOP - 8.0,
				"%s bottom is near ground top, not sky (y=%.0f)" % [node.name, foot.y])


func _wall_tex_path(node: Node) -> String:
	if node is Sprite2D and (node as Sprite2D).texture != null:
		return String((node as Sprite2D).texture.resource_path)
	for child in node.get_children():
		if child is Sprite2D and (child as Sprite2D).texture != null:
			return String((child as Sprite2D).texture.resource_path)
	return ""


func _is_wall_plate(node: Node) -> bool:
	if node is TorchLight:
		return true
	var path := _wall_tex_path(node)
	return path.ends_with("balustrade.png") or path.ends_with("column_big.png") \
			or path.ends_with("bg_column_skulls.png") or path.ends_with("bg_gargoyle.png") \
			or path.ends_with("bg_altar.png") or path.ends_with("door_arch.png")


func _wall_rect(node: Node2D) -> Rect2:
	if node is Sprite2D:
		return node.get_global_transform() * node.get_rect()
	var merged := Rect2()
	var any := false
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		for child in current.get_children():
			stack.append(child)
			if child is Sprite2D:
				var spr := child as Sprite2D
				var r: Rect2 = spr.get_global_transform() * spr.get_rect()
				merged = r if not any else merged.merge(r)
				any = true
	return merged if any else Rect2(node.global_position, Vector2.ZERO)


func _wall_overhang(rect: Rect2, tops: Array) -> float:
	var y := rect.end.y
	var bad := 0.0
	var x := rect.position.x
	while x < rect.end.x - 0.01:
		var step := minf(4.0, rect.end.x - x)
		var mid := x + step * 0.5
		var supported := false
		for t in tops:
			if mid < t.x0 - 1.0 or mid > t.x1 + 1.0:
				continue
			var d := float(y) - float(t.y)
			if d >= -6.0 and d <= 12.0:
				supported = true
				break
		if not supported:
			bad += step
		x += step
	return bad


func test_parallax_adds_mood_tint() -> void:
	var host := Node2D.new()
	add_child(host)
	var backdrop := CanvasLayer.new()
	backdrop.name = "ParallaxBackdrop"
	host.add_child(backdrop)
	var far := Parallax2D.new()
	far.name = "Far"
	backdrop.add_child(far)
	var extras := Level01Parallax.new()
	add_child(extras)
	extras.build(host)
	ok(host.get_node_or_null("MoodTint") != null, "mood tint lands on the host")


## 角色接地 + 特效不遮挡（docs/art-spec.md「角色接地」「特效不遮挡」）：
## 玩家/敌人本体 z=0，剑光弧 z=10 只覆盖判定区，余烬巢 / 壁炬的 WorldLight
## 是局部照明而非遮挡层；地平线剪影永远在 backdrop 一侧。
func test_play_layer_and_fx_depths_stay_split() -> void:
	var packed := load("res://scenes/levels/Level01_Static.tscn") as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await flush(2)
	# 玩家本体：默认 z=0（玩法层）。
	var player := level.get_tree().get_first_node_in_group("player") as Node2D
	ok(player != null, "level spawns a knight")
	if player != null:
		eq(player.z_index, 0, "the knight sits on the play canvas")
	# 前景层（ParallaxForeground）在玩法层之上，但只保留贴地雾/雾幕：
	# 原来的幕前草剪影贴在视口底边、扫过土壤剖面，被读成"土里长的移动植物"，
	# 已整段删除（2026 用户复查）。
	var front := level.get_node_or_null("ParallaxForeground") as CanvasLayer
	ok(front != null and front.layer > 0, "the fog/veil foreground layer draws over the play canvas")
	ok(level.get_node_or_null("ParallaxForeground/Foreground") == null,
			"no grass plate slides under the soil cross-section")
	# backdrop 永远在玩法层后面。
	var backdrop := level.get_node_or_null("ParallaxBackdrop") as CanvasLayer
	ok(backdrop != null and backdrop.layer < 0, "backdrop layer is negative")
	# 剪影带（NearSilhouette）属于 backdrop 侧：脚落在 300..340 地脚带。
	var sil := backdrop.get_node_or_null("NearSilhouette") if backdrop != null else null
	if sil != null:
		ok(sil.get_parent() == backdrop, "near silhouettes stay in the backdrop, never the play layer")


## 1A 场景细节（docs/UPGRADE_PLAN.md P0-1）：SceneDetails 里必须都是真实贴图细节，
## 全部踩在台面顶上，且不再有 ColorRect / Polygon2D 占位方块；光照不超过预算。
func test_scene_details_are_grounded_real_props() -> void:
	var packed := load("res://scenes/levels/Level01_Static.tscn") as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await flush(2)
	var layer := level.get_node_or_null("SceneDetails") as Node2D
	ok(layer != null, "SceneDetails layer is planted")
	if layer == null:
		return
	for node in LevelSanity._descendants(layer):
		ok(not (node is ColorRect), "%s is not a ColorRect placeholder" % node.name)
		ok(not (node is Polygon2D), "%s is not a Polygon2D placeholder" % node.name)
	eq(layer.get_child_count(),
			SceneDetails.GROUND_DETAILS.size() + SceneDetails.HANGING_DETAILS.size(),
			"one real detail node per authored row")
	var tops := LevelSanity.top_segments(level)
	var grounded := 0
	for child in layer.get_children():
		var spr := child as Sprite2D
		ok(spr != null, "%s is a real sprite" % child.name)
		if spr == null:
			continue
		ok(spr.texture != null and DensityTextures.source_path(spr.texture) != "",
				"%s draws an imported texture, not a shape" % spr.name)
		eq(spr.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "%s is nearest-filtered" % spr.name)
		eq(spr.scale, Vector2.ONE, "%s is drawn at world 1x" % spr.name)
		if not spr.is_in_group("grounded"):
			continue
		grounded += 1
		var feet: Vector2 = spr.get_meta("feet")
		ok(LevelSanity.standing_on(tops, feet) != null,
				"%s feet stand on a platform top (%s)" % [spr.name, feet])
	eq(grounded, SceneDetails.GROUND_DETAILS.size(), "every ground detail is foot-pinned")
	# Merge contract: the always-on ambience lights are off in chapter 1 (phase-3 LightPool
	# owns fire light); when planted explicitly they still anchor to every landmark.
	ok(level.get_node_or_null("AmbientLighting") == null, "chapter 1 plants no ambience light set")
	var lighting := AmbientLighting.create_for_level(level)
	SceneDetails.add_level01_lighting(lighting, level)
	if lighting != null:
		ok(lighting.light_count() > 0, "level actually gets ambience lights")
		ok(lighting.light_count() <= AmbientLighting.MAX_LIGHTS,
				"light count stays inside the 12-light budget")
		eq(lighting.light_count(), SceneDetails.LIGHT_ANCHORS.size(),
				"every authored light anchor resolves")
		for light in lighting.get_children():
			var world_light := light as WorldLight
			if world_light != null:
				ok(String(world_light.get_meta(&"anchor_path", "")) != "",
						"%s is anchored to a landmark, not a hardcoded coordinate" % world_light.name)


func _bind_beats() -> Level01StoryBeats:
	var beats := Level01StoryBeats.new()
	add_child(beats)
	beats.bind(self, null, null)
	return beats


func _make_host() -> Node2D:
	var host := Node2D.new()
	add_child(host)
	for folder in ["Platforms", "Hooks", "Pickups", "Props"]:
		var node := Node2D.new()
		node.name = folder
		host.add_child(node)
	var wall := Node2D.new()
	wall.name = "WallRight"
	wall.position = Vector2(1600, 0)
	host.get_node("Platforms").add_child(wall)
	return host


## 第一章材质色阶（UPGRADE_PLAN 第一阶段第 6 项）：墓园不再靠「鲜草绿 + 薰衣草紫 +
## 青苔绿」三套色板打架，草地收暖、浮石收成暖灰、齿轮与石台同阶；毒池保留
## 独立的危险青绿，让危险边界不靠亮度区分。这里锁住这四个色阶本身。
func test_graveyard_materials_share_one_temperature_and_the_pool_stays_dangerous() -> void:
	var packed := load("res://scenes/levels/Level01_Static.tscn") as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await flush(3)
	var platforms := level.get_node_or_null("Platforms") as Node2D
	ok(platforms != null, "the level has a platform layer")
	if platforms == null:
		level.queue_free()
		return
	var graded := 0
	for plat in platforms.get_children():
		if plat is SolidPlatform:
			graded += 1
			# 色阶乘在 tone 上：暖方向（r>=g>=b 或整体偏橙），且不带鲜草绿。
			var tone: Color = (plat as SolidPlatform).tone
			ok(tone.g <= tone.r + 0.35 or tone.b >= tone.r,
					"%s is not left in vivid grass green (%s)" % [plat.name, tone])
	ok(graded > 0, "the graveyard grades its solid platforms")
	var gear := platforms.get_node_or_null("Gear") as CanvasItem
	ok(gear != null and gear.modulate.r >= gear.modulate.g
			and gear.modulate.g >= gear.modulate.b,
			"the gear keeps the warm-stone class with the ledges")
	var toxin := level.get_node_or_null("Props/ToxinPool") as ToxinPool
	ok(toxin != null, "the graveyard has its toxin pool")
	if toxin != null:
		ok(toxin.tint.g > toxin.tint.r and toxin.tint.g > toxin.tint.b,
				"the pool keeps its own dangerous green, distinct from the ember warmth")
	level.queue_free()
	await flush(1)
