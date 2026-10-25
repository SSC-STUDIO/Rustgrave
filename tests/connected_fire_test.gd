extends TestCase
## Fire remains readable under scene modulation and obeys extinguish/progress states.

const Flame := preload("res://scripts/ui/title_flame.gd")
const Braziers := preload("res://scripts/ui/title_braziers.gd")


func test_flame_keeps_colour_and_extinguishes() -> void:
	var flame := Flame.new()
	add_child(flame)
	flame.set_process(false)
	flame.set_look(1.0, Color(2.0, 2.0, 2.0))
	flame.advance(0.2)
	var strip := flame.get_node("RootedFlame")
	var mat := strip.material as CanvasItemMaterial
	eq(mat.blend_mode, CanvasItemMaterial.BLEND_MODE_MIX, "Orange edges use normal blending")
	eq(mat.light_mode, CanvasItemMaterial.LIGHT_MODE_UNSHADED, "Ambient colour cannot turn fire green")
	eq(flame.glow_node().material, Fx.additive_mat(), "Glow remains a separate additive layer")
	ok(strip.levels[0] > 0.0, "Burning flame has a connected body")
	flame.burning = false
	flame.advance(0.1)
	eq(strip.levels[0], 0.0, "Extinguished nest has no remaining flame body")
	flame.queue_free()
	await get_tree().process_frame


func test_braziers_follow_progress_and_focus_without_growing_nodes() -> void:
	var braziers := Braziers.new()
	add_child(braziers)
	braziers.set_process(false)
	braziers.set_levels(0.0, 0.0)
	braziers.advance(0.2)
	var strip := braziers.get_node("RootedFlames")
	eq(strip.levels[0], 0.0, "Cold first brazier stays dark")
	eq(strip.levels[1], 0.0, "Cold second brazier stays dark")
	braziers.set_levels(0.6, 0.0)
	braziers.advance(0.1)
	ok(strip.levels[0] > 0.0 and strip.levels[1] == 0.0, "Only the unlocked brazier burns")
	braziers.boost = 1.0
	braziers.advance(0.1)
	ok(strip.levels[0] > 0.6 and strip.levels[1] > 0.0, "Menu focus can briefly wake both fires")
	var children := braziers.get_child_count()
	braziers.advance(12.0)
	eq(braziers.get_child_count(), children, "Animation never creates more nodes")
	eq(children, 2, "One shared strip plus one glow for both braziers")
	braziers.set_look(0.0, Color.WHITE)
	braziers.advance(0.1)
	eq(strip.levels[0], 0.0, "Scene fade also extinguishes focused fire")
	braziers.queue_free()
	await get_tree().process_frame


func test_loop_wraps_and_two_fires_do_not_move_in_lockstep() -> void:
	var strip := preload("res://scripts/fx/connected_fire_strip.gd").new()
	eq(strip.frame_at(0.0), strip.frame_at(16.0 / 12.0), "Animation wraps cleanly")
	ok(strip.frame_at(0.0) != strip.frame_at(0.0, 0.43), "Neighbouring fires use different phases")
	strip.free()
