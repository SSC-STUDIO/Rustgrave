extends TestCase
## HUD numbers, original result wording and node-stability of the arena HUD.
## The HUD is fed plain snapshot dictionaries, so these cases need no match.

const HUD := preload("res://scripts/moba/present/moba_hud.gd")
const VIEW_MAP := preload("res://scripts/moba/present/moba_view_map.gd")
const LAYOUT_WIDTH := 1280.0

var _layer: CanvasLayer


func _hud() -> Node:
	var hud: Node = HUD.new()
	add_child(hud)
	_layer = CanvasLayer.new()
	add_child(_layer)
	hud.build(_layer)
	hud.layout(LAYOUT_WIDTH)
	return hud


func _snapshot(cyan_hp: float = VIEW_MAP.CRYSTAL_HP, red_hp: float = VIEW_MAP.CRYSTAL_HP) -> Dictionary:
	return {
		"outcome": &"",
		"wave_index": 2,
		"next_wave_ms": 12500,
		"blue": {"crystal_hp": cyan_hp, "crystal_max": VIEW_MAP.CRYSTAL_HP},
		"red": {"crystal_hp": red_hp, "crystal_max": VIEW_MAP.CRYSTAL_HP},
		"hero": {"hp": 420.0, "max_hp": VIEW_MAP.HERO_HP, "alive": true, "respawn_ms": 0},
	}


func test_crystal_and_hero_bars_follow_the_snapshot() -> void:
	var hud := _hud()
	hud.apply(_snapshot(1200.0, 600.0))
	almost(float(hud.blue_crystal_bar["ratio"]), 0.5, 0.0001, "blue crystal half health")
	almost(float(hud.red_crystal_bar["ratio"]), 0.25, 0.0001, "red crystal quarter health")
	eq(hud.blue_crystal_bar["label"].text, "灰卫水晶 1200 / 2400")
	eq(hud.red_crystal_bar["label"].text, "锈誓水晶 600 / 2400")
	almost(hud.hero_ratio(), 0.7, 0.0001)
	eq(hud.hero_bar["label"].text, "余烬骑士 420 / 600")
	# The bar rectangle width is what the player reads; it must match the ratio.
	var inner: float = float(hud.blue_crystal_bar["width"]) - 4.0
	almost(float(hud.blue_crystal_bar["fill"].size.x), inner * 0.5, 0.001)
	hud.queue_free()


func test_wave_clock_text_uses_sim_milliseconds() -> void:
	eq(HUD.wave_text(0, 5000), "首波 5.0s")
	eq(HUD.wave_text(2, 12500), "第 2 波 · 下一波 12.5s")
	eq(HUD.wave_text(7, 0), "第 7 波 · 下一波 0.0s")
	eq(HUD.clock_text(59999), "60.0s")
	var hud := _hud()
	hud.apply(_snapshot())
	eq(hud.wave_label.text, "第 2 波 · 下一波 12.5s")
	hud.queue_free()


func test_death_shows_the_respawn_countdown() -> void:
	var hud := _hud()
	var snapshot := _snapshot()
	eq(hud.respawn_label.visible, false, "no death banner while alive")
	snapshot["hero"] = {"hp": 0.0, "max_hp": VIEW_MAP.HERO_HP, "alive": false, "respawn_ms": 5400}
	hud.apply(snapshot)
	ok(hud.respawn_label.visible)
	eq(hud.respawn_label.text, "余烬骑士阵亡 · 5.4s 后复活")
	hud.apply(_snapshot())
	eq(hud.respawn_label.visible, false, "the banner clears on respawn")
	hud.queue_free()


func test_result_banner_uses_original_team_wording() -> void:
	eq(HUD.result_text(&"blue"), "灰卫攻破锈誓水晶")
	eq(HUD.result_text(&"red"), "锈誓攻破灰卫水晶")
	eq(HUD.result_text(&""), "")
	var hud := _hud()
	eq(hud.result_panel.visible, false, "no banner before the outcome")
	var snapshot := _snapshot()
	snapshot["outcome"] = &"blue"
	hud.apply(snapshot)
	ok(hud.result_panel.visible)
	eq(hud.result_label.text, "灰卫攻破锈誓水晶")
	eq(hud.result_hint.text, "R 重开 · Esc 返回")
	snapshot["outcome"] = &"red"
	hud.apply(snapshot)
	eq(hud.result_label.text, "锈誓攻破灰卫水晶")
	snapshot["outcome"] = &""
	hud.apply(snapshot)
	eq(hud.result_panel.visible, false, "a restart snapshot hides the banner")
	hud.queue_free()


func test_layout_keeps_crystals_left_and_right_of_the_centre() -> void:
	var hud := _hud()
	var centre := LAYOUT_WIDTH * 0.5
	ok(hud.blue_crystal_bar["holder"].position.x < centre)
	ok(hud.red_crystal_bar["holder"].position.x > centre)
	ok(hud.blue_crystal_bar["holder"].position.y < 120.0, "crystal bars sit at the top")
	ok(hud.hero_bar["holder"].position.y > 500.0, "hero bar sits at the bottom")
	hud.layout(960.0)
	ok(hud.red_crystal_bar["holder"].position.x + float(hud.red_crystal_bar["width"]) <= 960.0,
			"narrow windows keep the red bar on screen")
	hud.queue_free()


func test_repeated_updates_do_not_create_nodes() -> void:
	var hud := _hud()
	var before := _node_count(_layer)
	for i in 40:
		hud.apply(_snapshot(VIEW_MAP.CRYSTAL_HP - float(i) * 10.0, VIEW_MAP.CRYSTAL_HP))
		hud.layout(LAYOUT_WIDTH)
	eq(_node_count(_layer), before, "apply()/layout() only move existing nodes")
	hud.reset()
	var snapshot := _snapshot()
	snapshot["outcome"] = &"blue"
	hud.apply(snapshot)
	hud.reset()
	eq(hud.result_panel.visible, false)
	eq(hud.result_label.text, "")
	eq(_node_count(_layer), before, "reset() never rebuilds the HUD tree")
	hud.queue_free()


func test_enemy_hero_bar_is_optional_and_follows_the_snapshot() -> void:
	var hud := _hud()
	eq(hud.enemy_bar["holder"].visible, false, "no enemy bar while the sim has one hero")
	var snapshot := _snapshot()
	snapshot["enemy_hero"] = {"visible": true, "hp": 300.0, "max_hp": VIEW_MAP.HERO_HP, "alive": true}
	hud.apply(snapshot)
	eq(hud.enemy_bar["holder"].visible, true)
	almost(float(hud.enemy_bar["ratio"]), 0.5, 0.0001)
	eq(hud.enemy_bar["label"].text, "锈誓骑士 300 / 600")
	snapshot["enemy_hero"] = {"visible": true, "hp": 0.0, "max_hp": VIEW_MAP.HERO_HP, "alive": false}
	hud.apply(snapshot)
	almost(float(hud.enemy_bar["ratio"]), 0.0, 0.0001)
	hud.reset()
	eq(hud.enemy_bar["holder"].visible, false, "a restart hides the enemy bar again")
	hud.queue_free()


func _node_count(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _node_count(child)
	return total
