extends TestCase

const L2 := preload("res://scripts/levels/level02_undercroft.gd")
const CH := preload("res://scripts/levels/chapter_level.gd")

func test_hud_probe() -> void:
	print("L2.HUD before=", L2.HUD, " nodes=", L2.HUD.get_state().get_node_count(), " valid=", L2.HUD.can_instantiate())
	print("CH.HUD before=", CH.HUD, " nodes=", CH.HUD.get_state().get_node_count(), " valid=", CH.HUD.can_instantiate())
	var lv := (load(GameContext.LEVELS["level02"]) as PackedScene).instantiate()
	add_child(lv)
	await flush(2)
	Director.abort()
	print("L2.HUD during=", L2.HUD, " nodes=", L2.HUD.get_state().get_node_count(), " valid=", L2.HUD.can_instantiate())
	print("CH.HUD during=", CH.HUD, " nodes=", CH.HUD.get_state().get_node_count(), " valid=", CH.HUD.can_instantiate())
	var fresh := load("res://scenes/ui/HUD.tscn") as PackedScene
	print("fresh HUD same=", fresh == L2.HUD, " nodes=", fresh.get_state().get_node_count())
	var hud := fresh.instantiate()
	ok(hud != null, "fresh HUD instantiate")
	if hud != null:
		hud.free()
	lv.free()
