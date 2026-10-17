extends TestCase
## Compact HUD geometry, letterbox safety and safe-area handling.

const HUD_SCENE := preload("res://scenes/ui/HUD.tscn")
const HUD_PROMPT_MAX := 1080.0
const HUD_BANNER_MAX := 1040.0
const HUD_OBJECTIVE_MAX := 860.0
const LONG_ZH := "锈墓的炉火在长廊尽头忽明忽暗，腐液沿着砖缝慢慢爬过来，铁门后面还有没有说完的誓言。"


func _dump(node: Node, depth: int = 0) -> void:
	if node is Control:
		print("PROBE ", "  ".repeat(depth), node.name, " ", (node as Control).get_global_rect(), " min=", (node as Control).get_combined_minimum_size())
	if depth < 4:
		for c in node.get_children():
			_dump(c, depth + 1)


func test_probe_geometry() -> void:
	var hud := HUD_SCENE.instantiate()
	add_child(hud)
	await flush(4)
	_dump(hud.get_node("Root/StatPanel"))
	ok(true)


## 长交互提示只占一行，超出 1080 设计像素后用省略号收尾，整块仍居中在画布内。
func test_long_prompt_is_bounded_inside_the_hud() -> void:
	var hud := HUD_SCENE.instantiate()
	add_child(hud)
	await flush(3)
	GameEvents.interact_prompt.emit(LONG_ZH.repeat(4))
	await flush(2)
	var label := hud.find_child("PromptLabel", true, false) as Label
	var panel := hud.find_child("Prompt", true, false) as Control
	ok(label != null, "prompt label exists")
	if label != null:
		eq(label.max_lines_visible, 1, "prompt stays one line")
		ok(label.clip_text, "overlong prompt is clipped, not spilled")
		ok(label.get_combined_minimum_size().x <= HUD_PROMPT_MAX + 0.5,
				"prompt min width is capped (%.1f)" % label.get_combined_minimum_size().x)
	if panel != null:
		var rect := panel.get_global_rect()
		ok(rect.position.x >= 0.0 and rect.end.x <= 1280.0,
				"prompt panel stays inside 1280 (%s)" % rect)
	GameEvents.interact_prompt.emit("")
	hud.queue_free()
	await flush(1)


## 播报横幅不能因为碑文/中文长句把铁牌拉出屏幕；换行先被压成空格。
func test_long_announcement_is_bounded_inside_the_hud() -> void:
	var hud := HUD_SCENE.instantiate()
	add_child(hud)
	await flush(3)
	GameEvents.announcement.emit("【炉约碑铭】\n" + LONG_ZH.repeat(4))
	await flush(2)
	var label := hud.find_child("AnnounceLabel", true, false) as Label
	var panel := hud.find_child("Banner", true, false) as Control
	ok(label != null, "announce label exists")
	if label != null:
		eq(label.max_lines_visible, 1, "banner stays one line")
		ok(not label.text.contains("\n"), "author line breaks collapse into spaces")
		ok(label.clip_text, "overlong announcement is clipped")
		ok(label.get_combined_minimum_size().x <= HUD_BANNER_MAX + 0.5,
				"banner min width is capped (%.1f)" % label.get_combined_minimum_size().x)
	if panel != null:
		var rect := panel.get_global_rect()
		ok(rect.position.x >= 0.0 and rect.end.x <= 1280.0,
				"banner panel stays inside 1280 (%s)" % rect)
	hud.queue_free()
	await flush(1)


## Boss 名字走主题里的 BossTitleLabel（不再在 HUD 里 add_theme_color_override），
## 超长名字在 460px 的血条里省略。
func test_boss_title_uses_theme_variation_and_is_bounded() -> void:
	var hud := HUD_SCENE.instantiate()
	add_child(hud)
	await flush(3)
	GameEvents.boss_appeared.emit(LONG_ZH.repeat(3), 10, 10)
	await flush(1)
	var label := hud.find_child("BossTitle", true, false) as Label
	var panel := hud.find_child("BossBar", true, false) as Control
	ok(label != null, "boss title exists")
	if label != null:
		eq(label.theme_type_variation, &"BossTitleLabel", "boss title is a theme variation")
		ok(not label.has_theme_color_override("font_color"),
				"boss title does not bypass the theme with a colour override")
		ok(label.clip_text, "overlong boss name is clipped")
	if panel != null:
		ok(panel.get_global_rect().end.x <= 1280.0, "boss bar stays inside the design width")
	GameEvents.boss_defeated.emit()
	hud.queue_free()
	await flush(1)


## 目标句可以折成两行，但右缘仍停在左列宽度以内。
func test_long_objective_wraps_within_the_left_column() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	await spawn_player(arena)
	arena.set_meta(&"objective", LONG_ZH.repeat(3))
	var hud := HUD_SCENE.instantiate()
	add_child(hud)
	await flush(3)
	var label := hud.find_child("ObjectiveLabel", true, false) as Label
	ok(label != null, "objective label exists")
	hud.peek_for(10.0)
	if label != null:
		await wait_until(func() -> bool: return label.visible and label.text != "", 180)
		ok(label.visible, "objective appears while peeking")
		eq(label.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART,
				"long objective wraps")
		eq(label.max_lines_visible, 2, "objective keeps at most two lines")
		ok(label.get_global_rect().end.x <= 1280.0,
				"objective never leaves the screen (%s)" % label.get_global_rect())
		ok(label.get_combined_minimum_size().x <= HUD_OBJECTIVE_MAX + 0.5,
				"objective width is capped")
	hud.queue_free()
	arena.queue_free()
	await flush(1)
