extends TestCase
## 主动技能：槽位/冷却/效果/落档，都在真实 Player 上跑。

const SkillCatalog := preload("res://scripts/data/skill_catalog.gd")
const PATH := "user://test_player_skills.cfg"

var _arena: Node2D


func setup() -> void:
	Director.abort()
	Director.choice_hold = false
	if get_tree().paused:
		get_tree().paused = false
	SaveData.save_path = PATH
	SaveData.delete_save()
	SaveData.skill_1 = ""
	SaveData.skill_2 = ""
	_arena = Node2D.new()
	add_child(_arena)
	build_floor(_arena)


func teardown() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
	SaveData.delete_save()
	SaveData.save_path = "user://rustgrave_save.cfg"
	SaveData.skill_1 = ""
	SaveData.skill_2 = ""
	Director.abort()
	Director.choice_hold = false
	if get_tree().paused:
		get_tree().paused = false


func _spawn() -> Player:
	var player := await spawn_player(_arena, Vector2(320.0, -24.0))
	return player


func test_slots_load_defaults_and_report_state() -> void:
	var player := await _spawn()
	eq(player.skill_slot_id(0), SkillCatalog.DEFAULT_SLOT_1, "新档槽 1 给默认技能")
	eq(player.skill_slot_id(1), &"", "新档槽 2 空")
	var state := player.skill_state()
	eq(state.size(), 2)
	eq(state[0]["id"], SkillCatalog.DEFAULT_SLOT_1)
	eq(state[0]["action"], &"skill_1")
	ok(bool(state[0]["ready"]))
	ok(not bool(state[1]["ready"]), "空槽永远不 ready")
	player.free()


func test_cast_starts_cooldown_and_blocks_recast() -> void:
	var player := await _spawn()
	ok(player.cast_skill(0), "冷却好时可以放")
	ok(player.skill_cooldown(0) > 0.0, "进入冷却")
	ok(not player.skill_ready(0))
	ok(not player.cast_skill(0), "冷却中不能再放")
	ok(not player.cast_skill(1), "空槽不能放")
	player._tick_skills(99.0)
	ok(player.skill_ready(0), "冷却结束后恢复")
	ok(player.cast_skill(0))
	player.free()


func test_burst_spawns_a_damage_hitbox() -> void:
	var player := await _spawn()
	player.equip_skill(0, &"ember_burst")
	eq(player._skill_boxes.size(), 0)
	ok(player.cast_skill(0))
	eq(player._skill_boxes.size(), 1, "余烬冲击生成一个临时判定")
	if not player._skill_boxes.is_empty():
		var box := player._skill_boxes[0] as Hitbox
		ok(box != null)
		if box != null:
			eq(box.team, &"player")
			eq(box.damage, 2)
			eq(box.blow, &"heavy")
	player.free()


func test_guard_applies_temporary_defense_modifier() -> void:
	var player := await _spawn()
	player.equip_skill(0, &"hollow_guard")
	var base := player.stats.get_defense_reduction()
	ok(player.cast_skill(0))
	eq(player.stats.get_defense_reduction(), base + 2, "炉心格挡防御 +2")
	ok(player.stats.has_modifier(&"skill_hollow_guard"))
	player.free()


func test_lance_launches_the_knight_forward() -> void:
	var player := await _spawn()
	player.equip_skill(0, &"rust_lance")
	var face := float(player.controller.facing)
	ok(player.cast_skill(0))
	ok(player.velocity.x * face > 100.0, "锈枪突进把骑士推向面朝方向")
	eq(player._skill_boxes.size(), 1)
	player.free()


func test_purge_drains_toxin_and_heals_one() -> void:
	var player := await _spawn()
	player.equip_skill(0, &"toxin_purge")
	player.toxin.toxin = player.toxin.max_toxin
	player.health.current = 3
	ok(player.cast_skill(0))
	almost(player.toxin.toxin, player.toxin.max_toxin * 0.5, 0.5, "排掉一半毒素")
	eq(player.health.current, 4, "回复 1 点生命")
	player.free()


func test_equip_persists_a_slot_when_asked() -> void:
	var player := await _spawn()
	SaveData.init_new_game(OriginCatalog.ORIGIN_EMBER_VANGUARD)
	ok(player.equip_skill(0, &"hollow_guard", true))
	eq(SaveData.skill_1, "hollow_guard", "技能槽写进 profile")
	var cfg := ConfigFile.new()
	eq(cfg.load(PATH), OK)
	eq(String(cfg.get_value("profile", "skill_1", "")), "hollow_guard",
			"profile 已落盘")
	player.free()
