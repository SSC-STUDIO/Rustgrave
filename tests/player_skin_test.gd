extends TestCase
## 皮肤/刻印在真实 Player 上：换肤重建帧动画、默认回退、刻印常驻属性、落档。

const SkinCatalog := preload("res://scripts/data/skin_catalog.gd")
const RuneCatalog := preload("res://scripts/data/rune_catalog.gd")
const PATH := "user://test_player_skin.cfg"

var _arena: Node2D


func setup() -> void:
	SaveData.save_path = PATH
	SaveData.delete_save()
	SaveData.skin_id = ""
	SaveData.skin_rune = ""
	_arena = Node2D.new()
	add_child(_arena)
	build_floor(_arena)


func teardown() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
	SaveData.delete_save()
	SaveData.save_path = "user://rustgrave_save.cfg"
	SaveData.skin_id = ""
	SaveData.skin_rune = ""
	Director.abort()


func _spawn() -> Player:
	return await spawn_player(_arena, Vector2(320.0, -24.0))


func test_default_look_is_the_fantasy_knight() -> void:
	var player := await _spawn()
	eq(player.skin_id(), SkinCatalog.DEFAULT_SKIN)
	var state := player.skin_state()
	eq(String(state["folder"]), "player_ember_knight")
	eq(state["tint"], Color.WHITE)
	eq(player.rune_id(), &"", "默认无刻印")
	ok(player._anim != null)
	player.free()


func test_apply_skin_rebuilds_the_animation() -> void:
	var player := await _spawn()
	var before := player._anim
	ok(player.apply_skin(&"skin_cemetery_hero"))
	eq(player.skin_id(), &"skin_cemetery_hero")
	eq(String(player.skin_state()["folder"]), "player_cemetery_hero")
	ok(player._anim != null and player._anim != before, "旧的帧动画被替换")
	player.free()


func test_unknown_skin_falls_back_to_default() -> void:
	var player := await _spawn()
	player.apply_skin(&"skin_gothic_hero")
	ok(player.apply_skin(&"skin_does_not_exist"))
	eq(player.skin_id(), SkinCatalog.DEFAULT_SKIN, "非法 id 回落默认皮肤")
	player.free()


func test_skin_persists_to_profile() -> void:
	var player := await _spawn()
	SaveData.init_new_game(OriginCatalog.ORIGIN_EMBER_VANGUARD)
	ok(player.apply_skin(&"skin_gothic_hero", true))
	eq(SaveData.skin_id, "skin_gothic_hero")
	var cfg := ConfigFile.new()
	eq(cfg.load(PATH), OK)
	eq(String(cfg.get_value("profile", "skin_id", "")), "skin_gothic_hero")
	player.free()


func test_rune_modifier_is_applied_and_removed() -> void:
	var player := await _spawn()
	var base_def := player.stats.get_defense_reduction()
	var base_hp := player.stats.get_effective_max_hp()
	ok(player.equip_rune(&"rune_unbroken"))
	eq(player.rune_id(), &"rune_unbroken")
	eq(player.stats.get_defense_reduction(), base_def + 1, "不折之刻防御 +1")
	eq(player.stats.get_effective_max_hp(), base_hp + 1, "生命上限 +1")
	ok(player.stats.has_modifier(RuneCatalog.SLOT_ID))
	ok(player.equip_rune(&""))
	eq(player.stats.get_defense_reduction(), base_def)
	ok(not player.stats.has_modifier(RuneCatalog.SLOT_ID))
	player.free()


func test_rune_rejects_unknown_and_persists() -> void:
	var player := await _spawn()
	ok(not player.equip_rune(&"rune_wrong"))
	SaveData.init_new_game(OriginCatalog.ORIGIN_EMBER_VANGUARD)
	ok(player.equip_rune(&"rune_toxin_filter", true))
	eq(SaveData.skin_rune, "rune_toxin_filter")
	almost(player.stats.get_toxin_resistance(), 0.08, 0.0001, "滤毒刻印抗性 +8%")
	var cfg := ConfigFile.new()
	eq(cfg.load(PATH), OK)
	eq(String(cfg.get_value("profile", "skin_rune", "")), "rune_toxin_filter")
	player.free()


func test_skin_and_rune_switch_does_not_double_stack() -> void:
	var player := await _spawn()
	player.equip_rune(&"rune_unbroken")
	var def_one := player.stats.get_defense_reduction()
	player.equip_rune(&"rune_ember_grip")
	eq(player.stats.get_defense_reduction(), def_one, "换刻印不叠加（仍是 +1）")
	player.equip_rune(&"")
	eq(player.stats.get_defense_reduction(), def_one - 1)
	player.free()
