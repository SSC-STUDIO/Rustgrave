extends TestCase
## 队伍伤害、quiet、塔仇恨、英雄撤退。

const ArenaCatalog := preload("res://scripts/data/arena_catalog.gd")
const UnitScript := preload("res://scripts/arena/arena_unit.gd")
const HeroScript := preload("res://scripts/arena/arena_hero.gd")
const TowerScript := preload("res://scripts/arena/arena_tower.gd")

var _hits := 0


func setup() -> void:
	_hits = 0
	ArenaRun.auto_begin = false
	ArenaRun.abandon()
	if GameEvents.hit.is_connected(_on_hit):
		GameEvents.hit.disconnect(_on_hit)


func teardown() -> void:
	if GameEvents.hit.is_connected(_on_hit):
		GameEvents.hit.disconnect(_on_hit)
	ArenaRun.auto_begin = false
	ArenaRun.abandon()


func test_friendly_fire_is_ignored_and_ai_hits_stay_quiet() -> void:
	if get_tree().paused:
		get_tree().paused = false
	if Director.is_suspended():
		Director.resume()
	ArenaRun.auto_begin = true
	ArenaRun.activate_for_test()
	build_floor(self, 0.0)
	var ally := _unit("a", "player", Vector2(-8, 0))
	var mate := _unit("b", "player", Vector2(8, 0))
	add_child(ally)
	add_child(mate)
	await flush(2)
	ok(ally.is_in_group("arena_unit"))
	ok(not ally.is_in_group("player"))
	ok(not ally.is_in_group("enemies"))
	ok(not mate.is_in_group("enemies"))
	GameEvents.hit.connect(_on_hit)
	var mate_hp := mate.get_node("Health") as Health
	var before := mate_hp.current
	ally.call("strike_at", mate.global_position + Vector2(0, -12), mate)
	await flush(2)
	eq(mate_hp.current, before, "同队免伤")
	eq(_hits, 0)
	mate.set("team", "enemy")
	var mate_box := mate.get_node("Hurtbox") as Hurtbox
	mate_box.team = &"enemy"
	ally.call("strike_at", mate.global_position + Vector2(0, -12), mate)
	await flush(2)
	ok(mate_hp.current < before, "敌对会扣血")
	eq(_hits, 0, "AI 打 AI 不发 GameEvents.hit")
	var visual := ally.get_node_or_null("Visual") as CanvasItem
	ok(visual != null)
	if visual != null:
		ok(visual.self_modulate == ArenaCatalog.TEAM_TINT["player"])


func test_quiet_health_still_reports_player_hits() -> void:
	var hp := Health.new()
	hp.quiet = true
	hp.max_hp = 8
	add_child(hp)
	GameEvents.hit.connect(_on_hit)
	ok(hp.take_damage(1, null))
	eq(_hits, 0, "没有玩家参与时 quiet 吞掉 hit")
	for _i in 40:
		hp._process(0.05)
	var attacker := Node.new()
	attacker.add_to_group("player")
	add_child(attacker)
	ok(hp.take_damage(1, attacker))
	eq(_hits, 1, "玩家打出的伤害仍然广播")
	var loud := Health.new()
	loud.quiet = false
	add_child(loud)
	ok(loud.take_damage(1, null))
	eq(_hits, 2, "quiet 默认关闭时照常广播")


func test_tower_target_priority() -> void:
	var pressing := {
		"team": "enemy", "kind": "hero", "attacking_hero": true, "dist": 90.0, "x": 90.0,
	}
	var minion := {
		"team": "enemy", "kind": "minion", "attacking_hero": false, "dist": 10.0, "x": 10.0,
	}
	var hero := {
		"team": "enemy", "kind": "hero", "attacking_hero": false, "dist": 4.0, "x": 4.0,
	}
	var picked := TowerScript.pick_target("player", [hero, minion, pressing])
	ok(bool(picked.get("attacking_hero", false)), "正在打己方英雄的敌方英雄优先")
	var next := TowerScript.pick_target("player", [hero, minion])
	eq(String(next.get("kind", "")), "minion", "其次是小兵，哪怕英雄更近")
	var only_hero := TowerScript.pick_target("player", [hero])
	eq(String(only_hero.get("kind", "")), "hero")
	var ignored := TowerScript.pick_target("player", [
		{"team": "player", "kind": "hero", "dist": 1.0},
		{"team": "neutral", "kind": "hero", "attacking_hero": true, "dist": 1.0},
	])
	ok(ignored.is_empty(), "友军和中立不进仇恨")
	eq(TowerScript.rank_target("player", pressing), 0)
	eq(TowerScript.rank_target("player", minion), 1)
	eq(TowerScript.rank_target("player", hero), 2)


func test_hero_retreats_at_low_hp_before_fighting() -> void:
	var hero: Node = HeroScript.new()
	hero.call("configure", {
		"id": "hero_test",
		"team": "player",
		"kind": "hero",
		"role": "hero",
		"pos": Vector2(1000, 0),
	})
	add_child(hero)
	await flush(1)
	eq(hero.call("decide_state"), "push")
	hero.call("set_sense", [{
		"kind": "hero",
		"team": "enemy",
		"dist": 20.0,
	}])
	hero.call("set_skill_ready", false)
	eq(hero.call("decide_state"), "fight")
	hero.call("set_skill_ready", true)
	eq(hero.call("decide_state"), "skill")
	var hp := hero.get_node("Health") as Health
	hp.current = 1
	eq(hero.call("decide_state"), "retreat", "低血优先于交战")
	eq(hero.call("goal_x"), ArenaCatalog.BLUE_FOUNTAIN.x)


func test_blessing_adds_a_point_of_damage() -> void:
	build_floor(self, 0.0)
	var unit := _unit("blessed", "player", Vector2(0, 0))
	add_child(unit)
	await flush(1)
	var before := int(unit.call("outgoing_damage", null))
	ArenaRun.grant_blessing("player")
	var after := int(unit.call("outgoing_damage", null))
	ok(after >= before + 1, "1.3 倍在 1 点伤害上不能被四舍五入掉")
	ArenaRun.abandon()


func _unit(id: String, team: String, pos: Vector2) -> Node2D:
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


func _on_hit(_attacker: Node, _target: Node, _amount: int) -> void:
	_hits += 1
