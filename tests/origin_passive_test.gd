extends TestCase
## 流派被动：目录一致性 + 三个被动在真实 Player 上的行为（可稳定复现）。

const PassiveCatalog := preload("res://scripts/data/passive_catalog.gd")

var _arena: Node2D


func setup() -> void:
	SaveData.delete_save()
	SaveData.flags.clear()
	_arena = Node2D.new()
	add_child(_arena)
	build_floor(_arena)


func teardown() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
	SaveData.delete_save()
	SaveData.flags.clear()
	Director.abort()


func _spawn(origin_id: StringName) -> Player:
	var player := await spawn_player(_arena, Vector2(320.0, -24.0))
	player.set_origin(origin_id)
	await flush(2)
	return player


func test_every_origin_declares_a_catalogued_passive() -> void:
	for origin in OriginCatalog.get_all_origins():
		ok(origin.passive_id != &"", "%s 声明了被动 id" % origin.title)
		ok(PassiveCatalog.has(origin.passive_id),
				"%s 的被动 %s 在目录里" % [origin.title, origin.passive_id])
		eq(PassiveCatalog.for_origin(origin.id), origin.passive_id,
				"起源 <-> 被动 双向一致")
		eq(PassiveCatalog.desc_of(origin.passive_id), origin.passive_desc,
				"说明文案与目录一致")
	eq(PassiveCatalog.for_origin(&"nobody"), &"", "未知起源没有被动")


func test_ember_vanguard_parry_grants_temporary_defense() -> void:
	var player := await _spawn(OriginCatalog.ORIGIN_EMBER_VANGUARD)
	eq(player.passive_state()["id"], &"passive_ember_bulwark")
	var base := player.stats.get_defense_reduction()
	ok(not player.stats.has_modifier(&"passive_ember_bulwark"))
	GameEvents.parried.emit(null, player)
	eq(player.stats.get_defense_reduction(), base + 1, "弹反成功防御 +1")
	ok(player.stats.has_modifier(&"passive_ember_bulwark"))
	player.stats._process(2.1)
	ok(not player.stats.has_modifier(&"passive_ember_bulwark"), "2 秒后失效")
	eq(player.stats.get_defense_reduction(), base)
	player.free()


func test_parry_bonus_only_helps_the_pv_owner() -> void:
	var player := await _spawn(OriginCatalog.ORIGIN_EMBER_VANGUARD)
	GameEvents.parried.emit(null, self)
	ok(not player.stats.has_modifier(&"passive_ember_bulwark"),
			"别人的弹反不会给骑士加防")
	player.free()


func test_scavenger_heals_once_per_cooldown_on_pickup() -> void:
	var player := await _spawn(OriginCatalog.ORIGIN_SCRAP_SCAVENGER)
	eq(player.passive_state()["id"], &"passive_scavenger_instinct")
	player.health.current = 3
	GameEvents.core_acquired.emit(null)
	eq(player.health.current, 4, "拾到核心回 1 点")
	ok(float(player.passive_state()["heal_cd"]) > 0.0, "进入冷却")
	GameEvents.core_acquired.emit(null)
	eq(player.health.current, 4, "冷却内不再回血")
	player.set(&"_passive_heal_cd", 0.0)
	GameEvents.core_acquired.emit(null)
	eq(player.health.current, 5, "冷却结束后可再回一次")
	player.free()


func test_filter_convert_halves_toxin_overflow_damage() -> void:
	var player := await _spawn(OriginCatalog.ORIGIN_RUST_AUTOMATON)
	eq(player.passive_state()["id"], &"passive_filter_convert")
	player.health.current = 5
	player.toxin.toxin = player.toxin.max_toxin
	player._on_toxin_overflow()
	eq(player.health.current, 5, "第一次满溢被滤掉")
	almost(player.toxin.toxin, player.toxin.max_toxin * 0.9, 0.01,
			"顺手排掉 10% 毒素")
	player._on_toxin_overflow()
	eq(player.health.current, 4, "第二次满溢正常掉血")
	player._on_toxin_overflow()
	eq(player.health.current, 4, "第三次又被滤掉")
	player.free()


func test_other_origins_do_not_trigger_foreign_passives() -> void:
	var player := await _spawn(OriginCatalog.ORIGIN_SCRAP_SCAVENGER)
	GameEvents.parried.emit(null, player)
	ok(not player.stats.has_modifier(&"passive_ember_bulwark"),
			"拾荒者没有重骑的弹反防御")
	player.health.current = 5
	player._on_toxin_overflow()
	eq(player.health.current, 4, "拾荒者没有滤毒转能")
	player.free()
