extends TestCase


func test_hearth_animates_without_tint_clipping_and_stops_when_snuffed() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(640, 360)
	vp.world_2d = World2D.new()
	add_child(vp)
	var world := (load("res://scenes/ui/TitleWorld.tscn") as PackedScene).instantiate() as TitleWorld
	world.state = TitleWorld.build_state({"has_save": true, "ending": "keep", "flags": PackedStringArray()})
	vp.add_child(world)
	world.set_process(false)
	var mouth := world.find_child("ForgeMouth", true, false) as Sprite2D
	ok(mouth != null, "Hearth is present")
	var before := mouth.frame
	world._process(0.25)
	ok(mouth.frame != before, "Fire changes shape while the furnace burns")
	ok(mouth.modulate.r <= 1.0 and mouth.modulate.g <= 1.0 and mouth.modulate.b <= 1.0,
			"Emission preserves colour instead of overdriving a channel")
	eq(mouth.texture.get_width() / mouth.hframes, 60, "Original hearth width and anchor survive the atlas change")
	world.configure(TitleWorld.build_state({"has_save": true, "ending": "snuff", "flags": PackedStringArray()}))
	before = mouth.frame
	world._process(0.25)
	eq(mouth.frame, before, "Snuffed furnace stops flickering")
	vp.queue_free()
	await get_tree().process_frame
