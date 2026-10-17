extends TestCase
## Phase-1 slice regressions: pause requests during scene fades, cutscene skip prompt
## wording, caption first frame, stale tutorial hints, chapter-1 backdrop grade.

const Presentation := preload("res://scripts/ui/cinematic_presentation.gd")

var _saved_nests: PackedStringArray
var _saved_flags: PackedStringArray


func setup() -> void:
	Director.choice_hold = false
	Director._fading = false
	_saved_nests = SaveData.lit_nests.duplicate()
	_saved_flags = SaveData.flags.duplicate()
	if get_tree().paused:
		get_tree().paused = false


func teardown() -> void:
	Director._fading = false
	Director.choice_hold = false
	Director.resume()
	SaveData.lit_nests = _saved_nests
	SaveData.flags = _saved_flags
	if get_tree().paused:
		get_tree().paused = false


func _menu() -> PauseMenu:
	var menu := PauseMenu.new()
	add_child(menu)
	return menu


func _esc() -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = &"ui_cancel"
	ev.pressed = true
	return ev


func test_pause_pressed_during_fade_opens_when_fade_ends() -> void:
	var menu := _menu()
	await flush(1)
	Director._fading = true
	menu.open()
	ok(not menu.is_open(), "no pause over a running fade")
	ok(menu.open_pending(), "the Esc press is remembered, not dropped")
	ok(not get_tree().paused, "the tree keeps running while the fade finishes")
	await flush(3)
	ok(not menu.is_open(), "still waiting while the fade runs")
	Director._fading = false
	await wait_until(func() -> bool: return menu.is_open(), 10)
	ok(menu.is_open(), "pause opens right after the fade")
	ok(get_tree().paused and Director.is_suspended(), "pause owns the tree and the Director")
	ok(not menu.open_pending(), "request consumed")
	menu.close()
	ok(not get_tree().paused and not Director.is_suspended(), "close restores play")
	menu.queue_free()


func test_second_esc_during_fade_cancels_the_request() -> void:
	var menu := _menu()
	await flush(1)
	Director._fading = true
	menu._unhandled_input(_esc())
	ok(menu.open_pending(), "first Esc queues")
	menu._unhandled_input(_esc())
	ok(not menu.open_pending(), "second Esc withdraws it")
	Director._fading = false
	await flush(3)
	ok(not menu.is_open(), "withdrawn request never opens the menu")
	menu.queue_free()


func test_pending_pause_is_dropped_by_ending_choice() -> void:
	var menu := _menu()
	await flush(1)
	Director._fading = true
	menu.open()
	Director.choice_hold = true
	Director._fading = false
	await flush(3)
	ok(not menu.is_open(), "ending choice wins over a stale pause request")
	ok(not menu.open_pending(), "and clears it")
	menu.queue_free()


func test_skip_prompt_names_the_opening_only_for_the_opening() -> void:
	eq(Presentation.skip_label(false, true), "Enter · 跳过开场")
	eq(Presentation.skip_label(true, true), "点此跳过开场")
	eq(Presentation.skip_label(false, false), "Enter · 跳过", "boss / pickup beats do not claim to be the opening")
	eq(Presentation.skip_label(true, false), "点此跳过")
	ok(not OpeningCinematic.is_active(), "no opening is running in the test tree")


func test_caption_never_shows_an_empty_strip() -> void:
	var cap := Caption.new()
	add_child(cap)
	await flush(1)
	cap.enqueue("钟响了一声。")
	ok(cap._panel.visible, "panel shows")
	ok(cap._label.text != "", "first glyph is on screen in the same frame as the panel")
	cap.clear()
	cap.enqueue("嗯", 0.05)
	eq(cap._label.text, "嗯", "single-glyph line is complete at once")
	ok(cap.is_busy(), "and still holds")
	await wait_until(func() -> bool: return not cap.is_busy(), 30)
	ok(not cap._panel.visible, "panel hides after the hold")
	cap.queue_free()


func test_stale_nest_hint_is_dropped_once_a_nest_is_lit() -> void:
	var hints := HintService.new()
	add_child(hints)
	SaveData.lit_nests = PackedStringArray()
	ok(hints.still_relevant(&"nest"), "teach the nest before any is lit")
	SaveData.lit_nests = PackedStringArray(["Props/EmberNest"])
	ok(not hints.still_relevant(&"nest"), "lit already: the hint would only repeat what happened")
	ok(hints.still_relevant(&"dash"), "unrelated hints are untouched")
	hints.queue_free()


func test_backdrop_grade_touches_only_listed_plates() -> void:
	var backdrop := CanvasLayer.new()
	add_child(backdrop)
	for layer_name in ["Far", "Mid", "Hills", "FogNear"]:
		var layer := Parallax2D.new()
		layer.name = layer_name
		var spr := Sprite2D.new()
		layer.add_child(spr)
		backdrop.add_child(layer)
	var graded := Level01Parallax.grade_plates(backdrop)
	eq(graded, 3, "sky, mountains and graveyard plates are graded")
	var far := backdrop.get_node("Far").get_child(0) as Sprite2D
	ok(far.material is ShaderMaterial, "far plate carries the grade")
	almost(float((far.material as ShaderMaterial).get_shader_parameter("amount")), float(Level01Parallax.GRADE["Far"]))
	ok((backdrop.get_node("FogNear").get_child(0) as Sprite2D).material == null, "fog is not graded")
	eq(Level01Parallax.grade_plates(backdrop), 3, "regrading reuses the materials")
	ok(far.material is ShaderMaterial)
	backdrop.queue_free()


func test_caption_lifts_over_the_boss_bar_and_drops_back_when_hud_leaves() -> void:
	var cap := Director.caption()
	ok(cap != null, "Director owns the caption")
	if cap == null:
		return
	cap.lift(0.0)
	var hud_scene := load("res://scenes/ui/HUD.tscn") as PackedScene
	var hud := hud_scene.instantiate()
	add_child(hud)
	await flush(2)
	GameEvents.boss_appeared.emit("测 试 · 首 领", 5, 5)
	await flush(1)
	almost(cap.lifted(), 72.0, 0.01, "caption clears the boss bar")
	var bar := hud.find_child("BossBar", true, false) as Control
	var panel := cap.find_child("CaptionPanel", true, false) as Control
	ok(bar != null and panel != null)
	if bar != null and panel != null:
		ok(panel.offset_bottom <= bar.offset_top, "caption strip sits above the bar, not on it")
	hud.queue_free()
	await flush(2)
	almost(cap.lifted(), 0.0, 0.01, "a HUD leaving the tree never strands a lifted caption")


func test_showing_hint_fades_early_when_it_goes_stale() -> void:
	var hints := HintService.new()
	add_child(hints)
	await flush(1)
	SaveData.lit_nests = PackedStringArray()
	SaveData.flags = PackedStringArray()
	hints._show(&"nest", "", true)
	eq(hints.current_id(), &"nest")
	SaveData.lit_nests = PackedStringArray(["Props/EmberNest"])
	await wait_until(func() -> bool: return hints.current_id() == &"", 40)
	eq(hints.current_id(), &"", "nest hint leaves within its fade once the nest is lit")
	hints.queue_free()


func test_director_caption_and_bars_follow_the_game_picture() -> void:
	var cap_layer := Director.get_node_or_null("DirectorCaption") as CanvasLayer
	var bar_layer := Director.get_node_or_null("DirectorLetterbox") as CanvasLayer
	var fade_layer := Director.get_node_or_null("DirectorFade") as CanvasLayer
	ok(cap_layer != null and bar_layer != null and fade_layer != null)
	if cap_layer == null or bar_layer == null:
		return
	ok(cap_layer.has_meta("presentation_bound"), "caption layer is bound to the content rect")
	ok(bar_layer.has_meta("presentation_bound"), "letterbox bars are bound to the content rect")
	ok(not fade_layer.has_meta("presentation_bound"), "the fade still covers the whole window")
	# 960x540 -> 1x content (640x360) centred: the bound transform must shrink and offset.
	var t: Transform2D = PresentationMetrics.calculate(Vector2i(960, 540))["ui_transform"]
	ok(t.get_scale().x < 1.0 and t.origin.y > 0.0, "small windows place captions inside the picture")
