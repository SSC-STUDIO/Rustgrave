extends TestCase
## Phase-2 regressions: cores can never be lost to a death between nests (save at
## pickup + repair of older saves), chapter-1 pickups, flash inside the game picture.

const JUICE := preload("res://scripts/autoload/juice.gd")

var _saved_flags: PackedStringArray


func setup() -> void:
	_saved_flags = SaveData.flags.duplicate()
	SaveData.save_path = "user://rustgrave_test_save_p2.cfg"
	SaveData.delete_save()


func teardown() -> void:
	SaveData.delete_save()
	SaveData.save_path = "user://rustgrave_save.cfg"
	SaveData.flags = _saved_flags


func _pickup(host: Node, node_name: String, core: RustCore) -> CorePickup:
	var folder := Node2D.new()
	folder.name = "Pickups"
	host.add_child(folder)
	var pick := (load("res://scenes/interactables/CorePickup.tscn") as PackedScene).instantiate() as CorePickup
	pick.name = node_name
	pick.core = core
	folder.add_child(pick)
	return pick


func test_core_pickup_writes_pouch_and_consumed_together() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	ok(SaveData.save_game("res://scenes/levels/Level01_Static.tscn", player), "nest save")
	var pick := _pickup(arena, "TetherCoreTest", AbilityCatalog.tether_core())
	await flush(1)
	pick.interact(player)
	# Death between nests reloads from disk: the core must be in the saved pouch.
	SaveData.consumed.clear()
	ok(SaveData.load_game())
	eq(SaveData.data["player"]["pouch"], ["tether_core"], "save-at-pickup stores the core")
	ok(SaveData.consumed.size() == 1, "and its consumed record")


func test_hint_story_flush_carries_the_pouch() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	ok(SaveData.save_game("res://scenes/levels/Level01_Static.tscn", player))
	# Old bug: consumed was flushed by a tutorial-hint write while the pouch was not.
	player.inventory.add_to_pouch(AbilityCatalog.tether_core())
	SaveData.mark_consumed("Enemies/TetherDrop_Spitter")
	SaveData.persist_story()
	ok(SaveData.load_game())
	ok(SaveData.save_owns_core(&"tether_core"), "story flush keeps cores and consumed in step")


func test_old_save_with_lost_core_releases_the_pickup() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	ok(SaveData.save_game("res://scenes/levels/Level01_Static.tscn", player))
	SaveData.mark_consumed("Pickups/LostCore")
	SaveData.mark_consumed("Pickups/OwnedCore")
	var not_player := Node.new()
	SaveData.persist_story(not_player)  # not a Player: writes consumed only, like old builds
	not_player.free()
	ok(SaveData.load_game())
	SaveData.data["player"]["sockets"] = ["kiln_core", ""]
	var host := Node2D.new()
	add_child(host)
	var lost := _pickup(host, "LostCore", AbilityCatalog.tether_core())
	var owned := (load("res://scenes/interactables/CorePickup.tscn") as PackedScene).instantiate() as CorePickup
	owned.name = "OwnedCore"
	owned.core = AbilityCatalog.kiln_core()
	host.get_node("Pickups").add_child(owned)
	await flush(1)
	SaveData.apply_consumed(host)
	await flush(1)
	ok(is_instance_valid(lost) and not lost.is_queued_for_deletion(), "unowned required core comes back")
	ok(not SaveData.is_consumed("Pickups/LostCore"), "and is no longer recorded as consumed")
	ok(not is_instance_valid(owned) or owned.is_queued_for_deletion(), "owned core stays picked up")


func test_no_save_means_no_progress_write() -> void:
	ok(not SaveData.persist_progress(), "before the first nest nothing is written")
	ok(not SaveData.has_save())


func test_level01_has_no_duplicate_kiln_pickups() -> void:
	var text := FileAccess.get_file_as_string("res://scenes/levels/Level01_Static.tscn")
	ok(text != "" and not text.contains("Kiln_"), "the scrap pile is the only chapter-1 kiln core")


func test_flash_layer_is_bound_to_the_game_picture() -> void:
	var j: Node = JUICE.new()
	add_child(j)  # headless: _ready skips the layer, build it by hand
	j._build_flash_layer()
	var layer: CanvasLayer = j._flash_layer
	ok(layer.has_meta("presentation_bound"), "flash follows the integer content rect")
	j.queue_free()


func test_play_layer_grade_spares_actors_hazards_and_interactables() -> void:
	var host := Node2D.new()
	add_child(host)
	var plats := Node2D.new()
	plats.name = "Platforms"
	host.add_child(plats)
	var tile := Sprite2D.new()
	plats.add_child(tile)
	var glow := Sprite2D.new()
	glow.material = CanvasItemMaterial.new()
	plats.add_child(glow)
	var hook := HookAnchor.new()
	var hook_spr := Sprite2D.new()
	hook.add_child(hook_spr)
	plats.add_child(hook)
	var decor := Node2D.new()
	decor.name = "GraveDecor"
	host.add_child(decor)
	var tree := Sprite2D.new()
	decor.add_child(tree)
	var props := Node2D.new()
	props.name = "Props"
	host.add_child(props)
	var prop_spr := Sprite2D.new()
	props.add_child(prop_spr)
	eq(Level01Parallax.grade_play_layer(host), 2, "terrain tile and grave decor only")
	ok(tile.material is ShaderMaterial and tree.material == tile.material, "one shared soot/rust material")
	ok(glow.material is CanvasItemMaterial, "additive glow keeps its own material")
	ok(hook_spr.material == null, "grapple points stay in their readable colour")
	ok(prop_spr.material == null, "props / interactables are not graded")
	eq(Level01Parallax.grade_play_layer(host), 0, "regrading is idempotent")
	var mat := tile.material as ShaderMaterial
	almost(float(mat.get_shader_parameter("amount")), Level01Parallax.PLAY_GRADE_AMOUNT)
	host.queue_free()


func test_chapter_tint_warms_without_blacking_out() -> void:
	var night := Level01Parallax.chapter_tint(Color(0.36, 0.34, 0.48))
	ok(night.r > night.b, "chapter-1 night leans ember, not violet")
	ok(night.b >= Level01Parallax.TINT_FLOOR and night.g >= Level01Parallax.TINT_FLOOR, "never a black frame")
	var day := Level01Parallax.chapter_tint(Color(0.95, 0.95, 0.95))
	ok(day.r <= 1.0 and day.b < day.r, "day stays in range and warm")


func _plate_ramp_top(backdrop: Node, layer_name: String) -> Color:
	var spr := backdrop.get_node(layer_name).get_child(0) as Sprite2D
	return (spr.material as ShaderMaterial).get_shader_parameter("c4") as Color


func test_night_graveyard_is_not_a_copy_of_chapter_one() -> void:
	var host := Node2D.new()
	add_child(host)
	var plats := Node2D.new()
	plats.name = "Platforms"
	host.add_child(plats)
	var tile := Sprite2D.new()
	plats.add_child(tile)
	var bd := ThemeBackdrop.new()
	host.add_child(bd)
	bd.build(host, "graveyard")
	var backdrop := host.get_node("ParallaxBackdrop")
	var top := _plate_ramp_top(backdrop, "Far")
	ok(top.b > top.r, "graveyard sky ramp is moonlit cold, chapter 1's is ember")
	var rust_top: Color = Level01Parallax.RUST_RAMP[4]
	ok(rust_top.r > rust_top.b)
	ok(tile.material is ShaderMaterial, "graveyard terrain is graded too")
	var tint := host.get_node("MoodTint") as CanvasModulate
	ok(tint.color.b >= tint.color.r - 0.02, "night graveyard mood is not warmed like chapter 1")
	host.queue_free()


func test_cathedral_theme_grades_plates_and_terrain_to_cold_slate() -> void:
	var host := Node2D.new()
	add_child(host)
	var plats := Node2D.new()
	plats.name = "Platforms"
	host.add_child(plats)
	var tile := Sprite2D.new()
	plats.add_child(tile)
	var bd := ThemeBackdrop.new()
	host.add_child(bd)
	bd.build(host, "cathedral")
	var backdrop := host.get_node("ParallaxBackdrop")
	ok((backdrop.get_node("Layer0").get_child(0) as Sprite2D).material is ShaderMaterial, "hall plate graded")
	ok(tile.material is ShaderMaterial, "nave paving graded")
	var mood: Color = (ThemeBackdrop.THEMES["cathedral"] as Dictionary)["mood"]
	ok(mood.b > mood.r and mood.g >= mood.r, "cold slate, no magenta/lavender cast")
	host.queue_free()


func test_touch_pad_buttons_say_what_they_do() -> void:
	var prev := TouchInput.force_show
	TouchInput.force_show = 1
	var pad := TouchControls.new()
	add_child(pad)
	var actions: Array = []
	var pause_found := false
	for n in pad.find_children("*", "Panel", true, false):
		if bool(n.get_meta("pause", false)):
			pause_found = true
		elif n.has_meta("action"):
			actions.append(StringName(n.get_meta("action")))
	for a in [&"move_left", &"move_right", &"jump", &"attack", &"dash"]:
		ok(actions.has(a), "pad button tagged %s" % a)
	ok(pause_found, "pause button tagged")
	pad.queue_free()
	TouchInput.force_show = prev


func test_skip_prompt_uses_the_same_touch_rule_as_the_pad() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/ui/cinematic_presentation.gd")
	ok(src.contains("TouchInput.wants_overlay()") and not src.contains("is_touchscreen_available"),
			"forced / mobile touch sessions see 点此 prompts, not Enter")
