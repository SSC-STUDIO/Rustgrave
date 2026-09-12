extends TestCase
## 梦魇：远处不亮血条 → 靠近只 announce 一次 → 冲锋位移并计数 → 半血嘶鸣召火骷髅 →
## 死亡发 slain 并落 nightmare_dead 旗标。
## 脚本没有 class_name（等导入后类缓存才会更新），所以这里全用动态调用。

const BOSS := preload("res://scenes/enemies/NightmareBoss.tscn")
const FLAG := "nightmare_dead"


func setup() -> void:
	_clear_flag()


func teardown() -> void:
	_clear_flag()


func _clear_flag() -> void:
	var i := SaveData.flags.find(FLAG)
	if i >= 0:
		SaveData.flags.remove_at(i)


func _spawn(arena: Node2D, pos: Vector2) -> Node2D:
	var boss := BOSS.instantiate() as Node2D
	boss.position = pos
	arena.add_child(boss)
	return boss


func _skulls(arena: Node) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for child in arena.get_children():
		if child is Node2D and String(child.name).begins_with("Nightmare_Skull_") \
				and not child.is_queued_for_deletion():
			out.append(child as Node2D)
	return out


func test_far_boss_stays_quiet_and_announces_once_when_the_knight_closes_in() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	var boss = _spawn(arena, player.global_position + Vector2(600, 0))
	var heard: Array = []
	var on_appear := func(name_: String, cur: int, max_: int) -> void: heard.append([name_, cur, max_])
	GameEvents.boss_appeared.connect(on_appear)
	await flush(4)
	ok(not boss.is_announced(), "600px away it has not shown itself")
	eq(heard.size(), 0, "no boss bar yet")
	eq(boss.state(), boss.State.IDLE)
	eq(boss.health.max_hp, 16)
	eq(boss.charge_count(), 0)
	boss.global_position = player.global_position + Vector2(200, 0)
	await flush(2)
	ok(boss.is_announced(), "within 340px it announces")
	eq(heard.size(), 1, "boss_appeared fires exactly once")
	boss.announce()
	eq(heard.size(), 1, "announce() is idempotent")
	if heard.size() == 1:
		eq(heard[0][0], "锈 墓 梦 魇 · 无 主 之 马")
		eq(heard[0][1], 16)
		eq(heard[0][2], 16)
	ok(boss.state() != boss.State.IDLE, "it starts its charge cycle")
	GameEvents.boss_appeared.disconnect(on_appear)


func test_charge_carries_the_boss_past_the_knight_and_counts() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	var boss = _spawn(arena, player.global_position + Vector2(220, 0))
	await flush(2)
	var start_x: float = boss.global_position.x
	eq(boss.charge_count(), 0, "no charge before the windup ends")
	var hp_reports: Array = []
	var on_hp := func(cur: int, _max: int) -> void: hp_reports.append(cur)
	GameEvents.boss_hp_changed.connect(on_hp)
	var charged: bool = await wait_until(
			func() -> bool: return boss.charge_count() >= 1 and boss.state() == boss.State.REST, 360)
	ok(charged, "windup, then a full gallop that ends in a breather")
	eq(boss.charge_count(), 1)
	var moved: float = absf(boss.global_position.x - start_x)
	ok(moved > 150.0, "the gallop carried it far (%.0f px)" % moved)
	ok(boss.global_position.x < player.global_position.x, "it overran the knight and stopped on the far side")
	ok(not boss.hitbox.monitoring, "ram damage is off while it breathes")
	boss.health.take_damage(1, player)
	eq(hp_reports, [15], "every lost point is reported to the boss bar")
	GameEvents.boss_hp_changed.disconnect(on_hp)


func test_enraged_boss_neighs_up_fire_skulls_capped_at_four() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	var boss = _spawn(arena, player.global_position + Vector2(700, 0))
	await flush(2)
	ok(not boss.is_enraged())
	boss.health.take_damage(8, player)
	ok(boss.is_enraged(), "half HP lights the mane")
	eq(boss.health.current, 8)
	ok(boss.is_announced(), "a first strike from afar still raises the bar")
	ok(ResourceLoader.exists("res://scenes/enemies/FireSkullEnemy.tscn"))
	boss._begin_neigh()
	eq(boss.state(), boss.State.NEIGH)
	var skulls := _skulls(arena)
	eq(skulls.size(), 2, "a neigh drops two fire skulls")
	for s in skulls:
		ok(s.global_position.y < boss.global_position.y - 30.0, "skulls appear above the horse")
		ok(absf(s.global_position.x - boss.global_position.x) < 40.0, "skulls appear around the mane")
	boss._begin_neigh()
	eq(_skulls(arena).size(), 4, "a second neigh fills the cap")
	boss._begin_neigh()
	eq(_skulls(arena).size(), 4, "never more than four at once")


func test_killing_blow_emits_slain_and_marks_the_story_flag() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	var boss = _spawn(arena, player.global_position + Vector2(200, 0))
	await flush(2)
	var slain_count := [0]
	boss.slain.connect(func() -> void: slain_count[0] += 1)
	var defeated := [0]
	var on_defeated := func() -> void: defeated[0] += 1
	GameEvents.boss_defeated.connect(on_defeated)
	ok(not SaveData.has_flag(FLAG), "flag is clear before the fight")
	boss.health.take_damage(99, player)
	eq(slain_count[0], 1, "slain fired once")
	eq(defeated[0], 1, "boss_defeated fired once")
	ok(SaveData.has_flag(FLAG), "story flag recorded")
	ok(boss._dead)
	eq(boss.collision_layer, 0)
	ok(not boss.hitbox.monitoring, "a dead horse cannot ram")
	await flush(2)
	ok(not is_instance_valid(boss), "the horse is freed after its death burst")
	GameEvents.boss_defeated.disconnect(on_defeated)


func test_arena_edges_stop_charges_and_bound_summons() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var boss = _spawn(arena, Vector2(320, 0))
	boss.set_physics_process(false)
	boss.arena_left = 280.0
	boss.arena_right = 400.0
	boss._facing = -1.0
	boss._begin_charge()
	boss._tick_charge(null, 0.1)
	eq(boss.state(), boss.State.REST, "brakes before its body crosses the west edge")
	eq(boss.velocity.x, 0.0)
	boss._begin_neigh()
	for skull in _skulls(arena):
		eq(skull.get("arena_left"), 280.0)
		eq(skull.get("arena_right"), 400.0)
		skull.global_position.x = 500.0
		skull.call("_update_facing")
		ok(skull.global_position.x <= 388.0, "summon cannot pursue beyond the arena")
	boss.health.take_damage(99)
	await flush(2)
	eq(_skulls(arena).size(), 0, "killing the boss dismisses its summons")
