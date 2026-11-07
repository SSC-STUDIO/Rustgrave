extends TestCase
## Tower / crystal view: health bar, hit flash, destruction animation, restart
## reset, and no node churn while animating.

const STRUCTURE := preload("res://scripts/moba/present/moba_structure_view.gd")
const VIEW_MAP := preload("res://scripts/moba/present/moba_view_map.gd")


func _structure(kind: StringName, team: int):
	var view = STRUCTURE.new()
	view.setup(kind, team)
	add_child(view)
	return view


func test_towers_and_crystals_start_full_and_show_their_health() -> void:
	for kind: StringName in [&"tower", &"crystal"]:
		var view = _structure(kind, 0)
		eq(view.max_hp, VIEW_MAP.structure_hp(kind))
		eq(view.bar_ratio(), 1.0)
		almost(view.bar_fill_width(), 1.0, 0.0001, "full health fills the floating bar")
		ok(view._bar_root.visible)
		view.apply(VIEW_MAP.structure_hp(kind) * 0.5, VIEW_MAP.structure_hp(kind), true)
		almost(view.bar_ratio(), 0.5, 0.0001)
		almost(view.bar_fill_width(), 0.5, 0.0001)
		view.queue_free()


func test_structure_positions_match_the_simulated_lane_x() -> void:
	for team in [VIEW_MAP.TEAM_BLUE, VIEW_MAP.TEAM_RED]:
		for kind: StringName in [&"tower", &"crystal"]:
			var view = _structure(kind, team)
			view.global_position = VIEW_MAP.structure_world(kind, team)
			var lane := VIEW_MAP.world_to_lane(view.global_position)
			almost(absf(lane.x), VIEW_MAP.structure_x(kind), 0.0001)
			view.queue_free()


func test_destruction_collapses_the_tower_and_darkens_it() -> void:
	var view = _structure(&"tower", 1)
	view.apply(300.0, VIEW_MAP.TOWER_HP, true)
	eq(view.destroyed, false)
	view.apply(0.0, VIEW_MAP.TOWER_HP, false)
	ok(view.destroyed, "zero health destroys the structure")
	eq(view._bar_root.visible, false, "the health bar disappears")
	eq(view._flame.visible, false, "the tower fire goes out")
	eq(view._pool.visible, false, "the ground glow goes out")
	view.advance(VIEW_MAP.HERO_RESPAWN_S * 0.5)
	ok(absf(view._root.rotation.z) > 0.01, "the tower topples over")
	view.queue_free()


func test_crystal_destruction_sinks_the_glowing_gem() -> void:
	var view = _structure(&"crystal", 0)
	var gem_y: float = view._gem.position.y
	view.apply(0.0, VIEW_MAP.CRYSTAL_HP, false)
	ok(view.destroyed)
	eq(view._gem.scale.x < 1.0, false, "the shrink happens over the collapse animation")
	view.advance(1.0)
	ok(view._gem.scale.x < 0.5, "the crystal gem shatters down into the plinth")
	ok(view._gem.position.y < gem_y)
	view.queue_free()


func test_reset_state_restores_a_fresh_structure() -> void:
	var view = _structure(&"tower", 0)
	view.apply(0.0, VIEW_MAP.TOWER_HP, false)
	view.advance(1.0)
	view.reset_state()
	eq(view.destroyed, false)
	eq(view.bar_ratio(), 1.0)
	eq(view._bar_root.visible, true)
	eq(view._flame.visible, true)
	eq(view._pool.visible, true)
	almost(view._root.rotation.z, 0.0, 0.0001)
	view.apply(600.0, VIEW_MAP.TOWER_HP, true)
	almost(view.bar_ratio(), 0.5, 0.0001)
	view.queue_free()


func test_animating_never_adds_nodes() -> void:
	var view = _structure(&"crystal", 1)
	var before: int = _node_count(view)
	for i in 120:
		view.advance(1.0 / 30.0)
	eq(_node_count(view), before, "advance() only animates the existing meshes")
	view.apply(0.0, VIEW_MAP.CRYSTAL_HP, false)
	for i in 60:
		view.advance(1.0 / 30.0)
	eq(_node_count(view), before, "the destruction animation adds no nodes either")
	view.queue_free()


func _node_count(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _node_count(child)
	return total
