extends TestCase
## 《ICEY》式封门多波次激战容器（BattleWaveArena）测试：
##   验证入场封门 → 刷怪预警圈倒计时 → 第 1 波生成与歼灭 → 第 2 波衔接生成与歼灭 →
##   清场解锁 RoomGate、点亮 GuideArrow、写入 StageRoomMemory 重进免刷。


func setup() -> void:
	Engine.time_scale = 1.0
	SaveData.save_path = "user://rustgrave_test_save.cfg"
	SaveData.delete_save()
	StageRoomMemory.clear_all()


func teardown() -> void:
	Engine.time_scale = 1.0
	SaveData.delete_save()
	SaveData.save_path = "user://rustgrave_save.cfg"
	StageRoomMemory.clear_all()


func test_two_wave_lockdown_clear_and_room_memory() -> void:
	var world := Node2D.new()
	world.name = "WaveTestWorld"
	world.add_to_group("game_world")
	add_child(world)

	var platforms := Node2D.new()
	platforms.name = "Platforms"
	world.add_child(platforms)
	var floor_plat := SolidPlatform.new()
	floor_plat.name = "FloorA"
	floor_plat.position = Vector2(0.0, 320.0)
	floor_plat.size = Vector2(800.0, 64.0)
	platforms.add_child(floor_plat)

	var enemies := Node2D.new()
	enemies.name = "Enemies"
	world.add_child(enemies)

	var player := await spawn_player(world, Vector2(96.0, 290.0))

	var gate := RoomGate.new()
	gate.name = "EastGate"
	gate.mode = RoomGate.Mode.INTERACT
	gate.target_room = "S3"
	gate.position = Vector2(740.0, 320.0)
	world.add_child(gate)

	var arrow := GuideArrow.new()
	arrow.name = "ClearArrow"
	arrow.active_on_start = false
	arrow.label_text = "前 进"
	arrow.position = Vector2(700.0, 268.0)
	world.add_child(arrow)

	var arena := BattleWaveArena.new()
	arena.name = "WaveArena"
	arena.stage_id = "stage01"
	arena.room_id = "S2"
	arena.arena_left = 48.0
	arena.arena_right = 720.0
	arena.floor_y = 320.0
	arena.telegraph_seconds = 0.08
	arena.configure_waves([
		[{"kind": "skeleton", "pos": Vector2(420.0, 320.0)}],
		[{"kind": "skeleton", "pos": Vector2(460.0, 320.0)}],
	])
	world.add_child(arena)
	arena.register_gate(gate)
	arena.bind_arrow(arrow)
	await flush(2)

	ok(not arena.is_active(), "arena starts inactive before trigger")
	ok(gate.is_gate_open(), "gate open before wave lockdown")
	ok(not arrow.is_lit, "guide arrow stays dim before clear")

	arena.activate()
	ok(arena.is_active(), "arena becomes active")
	ok(not gate.is_gate_open(), "gate locked while arena is active")
	eq(arena.current_wave, 1, "wave 1 started")
	ok(arena.telegraphing, "wave 1 begins with telegraph ring")
	ok(arena.get_node_or_null("WaveWallLeft") != null, "left barrier spawned")
	ok(arena.get_node_or_null("WaveWallRight") != null, "right barrier spawned")

	var w1_spawned := await wait_until(func() -> bool:
		return not arena.telegraphing and arena.live_enemy_count() == 1, 90)
	ok(w1_spawned, "wave 1 enemy spawned after telegraph")

	_slay_all_wave_enemies(enemies, player)
	var w2_spawned := await wait_until(func() -> bool:
		return arena.current_wave == 2 and not arena.telegraphing and arena.live_enemy_count() == 1, 90)
	ok(w2_spawned, "wave 2 automatically telegraphed and spawned after wave 1 died")

	_slay_all_wave_enemies(enemies, player)
	var cleared_ok := await wait_until(func() -> bool:
		return arena.is_cleared(), 60)
	ok(cleared_ok, "arena marks cleared after final wave dies")
	Engine.time_scale = 1.0

	ok(gate.is_gate_open(), "gate unlocked on clear")
	ok(arrow.is_lit, "guide arrow lit on clear")
	ok(StageRoomMemory.is_cleared("stage01", "S2"), "StageRoomMemory recorded cleared room")

	# 模拟同局重进该房：新实例在 _ready 阶段应直接呈已清场状态，不再封门刷怪
	var gate2 := RoomGate.new()
	gate2.mode = RoomGate.Mode.INTERACT
	gate2.set_locked(true)
	world.add_child(gate2)
	var arrow2 := GuideArrow.new()
	arrow2.active_on_start = false
	world.add_child(arrow2)
	var arena2 := BattleWaveArena.new()
	arena2.stage_id = "stage01"
	arena2.room_id = "S2"
	arena2.configure_waves([[{"kind": "skeleton", "pos": Vector2(420.0, 320.0)}]])
	world.add_child(arena2)
	arena2.register_gate(gate2)
	arena2.bind_arrow(arrow2)
	await flush(2)
	ok(arena2.is_cleared(), "re-entered room arena starts already cleared")
	ok(gate2.is_gate_open(), "re-entered room gate immediately unlocked")
	ok(arrow2.is_lit, "re-entered room guide arrow immediately lit")

	world.queue_free()
	await flush(2)


func _slay_all_wave_enemies(enemies_folder: Node, attacker: Node) -> void:
	for child in enemies_folder.get_children():
		var hp := child.get_node_or_null("Health") as Health
		if hp != null and hp.current > 0:
			hp.take_damage(999, attacker)
