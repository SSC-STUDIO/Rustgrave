extends TestCase


func setup() -> void:
	SaveData.pending_spawn = Vector2.INF
	SaveData.entering_from_checkpoint = false
	SaveData.lit_nests.clear()


func teardown() -> void:
	SaveData.pending_spawn = Vector2.INF
	SaveData.entering_from_checkpoint = false
	SaveData.lit_nests.clear()


func test_pending_spawn_is_consumed_once() -> void:
	ok(not SaveData.has_pending_spawn())
	SaveData.pending_spawn = Vector2(150, 290)
	ok(SaveData.has_pending_spawn())
	var pos := SaveData.consume_pending_spawn()
	eq(pos, Vector2(150, 290))
	ok(not SaveData.has_pending_spawn(), "second consume is empty")


func test_unlit_path_has_no_pending_spawn() -> void:
	eq(SaveData.lit_nests.size(), 0)
	ok(not SaveData.has_pending_spawn(), "no nest means no override spawn")


func test_checkpoint_enter_survives_consume() -> void:
	SaveData.pending_spawn = Vector2(150, 306)
	SaveData.entering_from_checkpoint = true
	var pos := SaveData.consume_pending_spawn()
	eq(pos, Vector2(150, 306))
	ok(not SaveData.has_pending_spawn())
	ok(SaveData.entering_from_checkpoint, "wake still sees the death reload after spawn consume")
	SaveData.entering_from_checkpoint = false


func test_confirm_skips_a_pending_death_wait_once() -> void:
	var player := preload("res://scenes/player/Player.tscn").instantiate() as Player
	add_child(player)
	player.set_physics_process(false)
	var wait := Timer.new()
	wait.one_shot = true
	player.add_child(wait)
	var resumed := [0]
	wait.timeout.connect(func() -> void: resumed[0] += 1)
	wait.start(1.15)
	player._respawn_wait = wait
	var event := InputEventAction.new()
	event.action = &"ui_accept"
	event.pressed = true
	player._unhandled_input(event)
	eq(resumed[0], 1, "confirmation resumes the existing wait")
	ok(wait.is_stopped())
	player._unhandled_input(event)
	eq(resumed[0], 1, "repeated confirmation never starts a second respawn")
