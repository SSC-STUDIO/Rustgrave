extends TestCase
## 纵深命中、AI 换深度、Y 排序、玩家不越带、跳跃 z 与阴影、战役玩家不受影响。

const ArenaCatalog := preload("res://scripts/data/arena_catalog.gd")
const UnitScript := preload("res://scripts/arena/arena_unit.gd")
const HeroScript := preload("res://scripts/arena/arena_hero.gd")
const TowerScript := preload("res://scripts/arena/arena_tower.gd")
const BoltScript := preload("res://scripts/arena/arena_bolt.gd")
const ArenaScene := preload("res://scenes/levels/Arena_Duel.tscn")


func setup() -> void:
	if get_tree().paused:
		get_tree().paused = false
	ArenaRun.auto_begin = false
	ArenaRun.abandon()


func teardown() -> void:
	ArenaRun.auto_begin = false
	ArenaRun.abandon()


func test_melee_misses_across_depth_and_structures_span_the_band() -> void:
	_play()
	var attacker := _minion("atk", "player", Vector2(120, ArenaCatalog.DEPTH_BACK + 8.0))
	var victim := _minion("vic", "enemy", Vector2(160, ArenaCatalog.DEPTH_FRONT - 6.0))
	add_child(attacker)
	add_child(victim)
	await flush(1)
	attacker.global_position.y = ArenaCatalog.DEPTH_BACK + 8.0
	victim.global_position.y = ArenaCatalog.DEPTH_FRONT - 6.0
	attacker.call("move_toward_depth", attacker.global_position.y)
	victim.call("move_toward_depth", victim.global_position.y)
	await flush(1)
	var hp := victim.get_node("Health") as Health
	var before := hp.current
	attacker.call("strike_at", victim.global_position + Vector2(0, -12), victim)
	await flush(1)
	eq(hp.current, before, "剑击跨深度打不中")
	ok(not ArenaCatalog.depths_touch(attacker, victim, "melee"))
	victim.global_position.y = attacker.global_position.y
	victim.call("move_toward_depth", attacker.global_position.y)
	await flush(1)
	attacker.call("strike_at", victim.global_position + Vector2(0, -12), victim)
	await flush(1)
	ok(hp.current < before, "同一深度剑击打中")
	var tower := _tower("enemy", 0, Vector2(900, ArenaCatalog.GROUND_Y))
	add_child(tower)
	await flush(1)
	attacker.global_position = Vector2(200, ArenaCatalog.DEPTH_BACK + 4.0)
	attacker.call("move_toward_depth", attacker.global_position.y)
	await flush(1)
	var tower_hp := tower.get_node("Health") as Health
	var tower_before := tower_hp.current
	ok(ArenaCatalog.depths_touch(attacker, tower, "melee"), "塔贯穿纵深带")
	attacker.call("strike_at", tower.global_position + Vector2(0, -40), tower)
	await flush(1)
	ok(tower_hp.current < tower_before, "带后缘也能打到塔")
	ok(ArenaCatalog.hit_tolerance("bolt") > ArenaCatalog.hit_tolerance("melee"))


func test_hero_closes_depth_and_sidesteps_bolts() -> void:
	_play()
	var ally := _hero("ally_d", "player", Vector2(800, ArenaCatalog.lane_y(0)), 0)
	var foe := _hero("foe_d", "enemy", Vector2(860, ArenaCatalog.lane_y(2)), 2)
	add_child(ally)
	add_child(foe)
	var gap0 := absf(ally.global_position.y - foe.global_position.y)
	ok(gap0 > 40.0)
	await flush(50)
	var gap1 := absf(ally.global_position.y - foe.global_position.y)
	ok(gap1 < gap0 - 10.0, "英雄会换深度去贴目标")
	ok(ArenaCatalog.in_depth(ally.global_position.y))
	ok(ArenaCatalog.in_depth(foe.global_position.y))
	var bolt: Node = BoltScript.new()
	add_child(bolt)
	bolt.call("setup", foe, 1.0, 1, null)
	bolt.global_position = Vector2(ally.global_position.x - 70.0, ally.global_position.y - 12.0)
	bolt.set("_depth", ally.global_position.y)
	var vel: Vector2 = bolt.get("velocity")
	bolt.set("velocity", Vector2(absf(vel.x), 0.0))
	var y0 := ally.global_position.y
	await flush(25)
	ok(absf(ally.global_position.y - y0) > 8.0, "英雄让开塔弹所在的深度")
	ok(ArenaCatalog.in_depth(ally.global_position.y))


func test_scene_ysort_and_units_stay_in_the_band() -> void:
	var world := ArenaScene.instantiate()
	add_child(world)
	await flush(2)
	ok(bool(world.get("y_sort_enabled")))
	var lights := 0
	var feet: Array[float] = []
	for node in world.get_tree().get_nodes_in_group("arena_unit"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var body := node as Node2D
		eq(body.z_index, 0)
		ok(ArenaCatalog.in_depth(body.global_position.y), String(node.name))
		feet.append(body.global_position.y)
	var knight := world.get_tree().get_first_node_in_group("player") as Node2D
	ok(knight != null and knight.is_in_group("arena_plane"))
	eq(knight.z_index, 0)
	ok(ArenaCatalog.in_depth(knight.global_position.y))
	for node in world.find_children("*", "PointLight2D", true, false):
		lights += 1
	ok(lights > 0 and lights <= 8, "点光源 %d" % lights)
	ok(world.find_child("FrontVeil", true, false) != null)
	ok(world.find_child("DepthGround", true, false) != null)
	ok(world.find_child("AltarPad", true, false) != null)
	if feet.size() >= 2:
		feet.sort()
		ok(ArenaCatalog.ysort_behind(feet[0], feet[feet.size() - 1]))
	world.queue_free()
	await flush(2)


func test_player_depth_bounds_jump_and_campaign_physics() -> void:
	var rig := Node2D.new()
	rig.name = "DepthRig"
	add_child(rig)
	build_floor(rig, 320.0)
	var player := await spawn_player(rig, Vector2(320, -24))
	_play()
	ok(not player.is_in_group("arena_plane"))
	player.velocity = Vector2.ZERO
	player.global_position = Vector2(320, -80)
	await flush(2)
	ok(player.velocity.y > 0.0, "战役重力仍把人往下拉")
	eq(player.arena_z(), 0.0, "不在竞技场平面里没有跳跃高度")
	player.arena_request_jump()
	await flush(2)
	eq(player.arena_z(), 0.0, "请求跳跃也不会抬战役角色")
	ok(player.motion_mode == CharacterBody2D.MOTION_MODE_GROUNDED)
	player.add_to_group("arena_plane")
	player.global_position = Vector2(400, 10)
	await flush(1)
	almost(player.arena_depth(), ArenaCatalog.DEPTH_BACK, 0.2, "后缘夹住")
	player.global_position.y = 2000.0
	await flush(1)
	almost(player.arena_depth(), ArenaCatalog.DEPTH_FRONT, 0.2, "前缘夹住")
	var feet: float = player.arena_depth()
	var low: Dictionary = player.arena_shadow_metrics()
	player.arena_request_jump()
	await flush(4)
	ok(player.arena_z() > 4.0, "跳跃抬高 z")
	almost(player.arena_depth(), feet, 0.5, "跳跃不改脚底深度")
	var high: Dictionary = player.arena_shadow_metrics()
	ok(float(high["rx"]) < float(low["rx"]), "阴影变小")
	ok(float(high["alpha"]) < float(low["alpha"]), "阴影变淡")
	var hurt := player.get_node("Hurtbox") as Node2D
	ok(hurt.position.y < -1.0, "受击盒跟着 z 抬高")
	player.remove_from_group("arena_plane")
	await flush(8)
	ok(player.motion_mode == CharacterBody2D.MOTION_MODE_GROUNDED)
	eq(player.arena_z(), 0.0)
	player.queue_free()


func _play() -> void:
	ArenaRun.auto_begin = true
	ArenaRun.activate_for_test()


func _minion(id: String, team: String, pos: Vector2) -> Node2D:
	var unit := UnitScript.new() as Node2D
	unit.call("configure", {
		"id": id,
		"team": team,
		"kind": "minion",
		"role": "melee",
		"label": id,
		"pos": pos,
	})
	return unit


func _hero(id: String, team: String, pos: Vector2, slot: int) -> Node2D:
	var unit := HeroScript.new() as Node2D
	unit.call("configure", {
		"id": id,
		"team": team,
		"kind": "hero",
		"role": "hero",
		"label": id,
		"slot": slot,
		"pos": pos,
	})
	return unit


func _tower(team: String, index: int, pos: Vector2) -> Node2D:
	var unit := TowerScript.new() as Node2D
	unit.call("configure", {
		"id": "tower_%s_%d" % [team, index],
		"team": team,
		"kind": "tower",
		"role": "tower",
		"index": index,
		"label": "外塔",
		"pos": pos,
	})
	return unit
