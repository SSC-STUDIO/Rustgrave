extends TestCase
## 关卡奖励位：roster 缺席时 EquipmentPickup 走"余温"回退（回血 + 消耗 + 自毁），
## roster 存在时解锁引用；两种状态都不能重复刷出（consumed 持久化）。

const PATH := "user://test_equipment_reward.cfg"


func setup() -> void:
	SaveData.save_path = PATH
	SaveData.delete_save()
	SaveData.flags.clear()
	Director.abort()


func teardown() -> void:
	SaveData.delete_save()
	SaveData.save_path = "user://rustgrave_save.cfg"
	SaveData.flags.clear()
	Director.abort()


func _build_arena() -> Node2D:
	var arena := Node2D.new()
	arena.name = "RewardArena"
	add_child(arena)
	build_floor(arena)
	return arena


func test_reward_pickup_without_roster_heals_once_and_is_consumed() -> void:
	if LoadoutBridge.weapon_available():
		ok(true, "roster present; fallback branch is covered by the roster line")
		return
	var arena := _build_arena()
	var player := await spawn_player(arena)
	player.health.take_damage(2)
	await flush(2)
	var before := player.health.current
	ok(before < player.health.max_hp, "fixture: knight is hurt")
	var pickup := EquipmentPickup.new()
	pickup.name = "WeaponReward"
	pickup.reward_kind = "weapon"
	pickup.reward_ref = "iron_blade"
	pickup.position = player.position + Vector2(0, -8)
	arena.add_child(pickup)
	await flush(2)
	ok(pickup.is_inside_tree(), "reward pickup is planted")
	ok(not SaveData.is_consumed(SaveData.persist_path(pickup)), "not consumed before interaction")
	pickup.interact(player)
	await flush(2)
	eq(player.health.current, before + 1, "fallback warms the knight by one HP")
	ok(not is_instance_valid(pickup), "pickup frees itself")
	ok(not SaveData.consumed.is_empty(), "consumed record written")
	# 同路径重载：新节点在 _ready 里自毁，奖励不会二次刷出。
	arena.free()
	await flush(1)
	var arena2 := _build_arena()
	var again := EquipmentPickup.new()
	again.name = "WeaponReward"
	again.reward_kind = "weapon"
	again.reward_ref = "iron_blade"
	again.position = Vector2(320, -8)
	arena2.add_child(again)
	await flush(2)
	ok(not is_instance_valid(again), "a consumed reward does not respawn")
	arena2.free()


func test_reward_pickup_prompt_names_the_reward() -> void:
	var arena := _build_arena()
	var pickup := EquipmentPickup.new()
	pickup.reward_kind = "character"
	pickup.reward_ref = "gothic_hero"
	pickup.reward_name = "哥特骑士"
	pickup.position = Vector2(120, -8)
	arena.add_child(pickup)
	await flush(2)
	ok(String(pickup.prompt).contains("哥特骑士"), "prompt shows the authored reward name")
	arena.free()
