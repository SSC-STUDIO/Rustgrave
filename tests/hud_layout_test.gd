extends TestCase
## Compact HUD geometry, letterbox safety and safe-area handling.

const HUD_SCENE := preload("res://scenes/ui/HUD.tscn")
const HUD_PROMPT_MAX := 1080.0
const HUD_BANNER_MAX := 1040.0
const HUD_OBJECTIVE_MAX := 860.0
const LONG_ZH := "锈墓的炉火在长廊尽头忽明忽暗，腐液沿着砖缝慢慢爬过来，铁门后面还有没有说完的誓言。"


## HUD 用例直接依赖 Director / 暂停 / 教学提示这些全局状态；全量跑时前面的用例
## 可能把它们留在激活态（黑边、字幕、暂停、提示已看过）。每个用例开始前清一遍，
## 跑完再清一遍 —— 这样 `--case-filter=hud_layout` 和全量套件的结果一致。
func setup() -> void:
	var dirty := _dirty_global_ui_state()
	if dirty != "":
		print("HUD_LAYOUT_SETUP cleaned leaked global state: ", dirty)
	_reset_global_ui_state()
	HintService.forget_all()
	Settings.set_value(&"hints_on", true, false)


func teardown() -> void:
	_reset_global_ui_state()
	HintService.forget_all()


## 全量套件里前面用例留下的激活态（仅用于诊断打印）。
func _dirty_global_ui_state() -> String:
	var parts := PackedStringArray()
	if get_tree().paused:
		parts.append("paused")
	if Director.playing:
		parts.append("director_playing")
	if Director.choice_hold:
		parts.append("choice_hold")
	if Director.is_input_locked():
		parts.append("input_locked")
	if Director.letterbox_amount() > 0.02:
		parts.append("letterbox=%.2f" % Director.letterbox_amount())
	var cap: Caption = Director.caption()
	if cap != null and cap.is_busy():
		parts.append("caption_busy")
	if HintService.has_seen(&"peek"):
		parts.append("peek_seen")
	if not HintService.enabled():
		parts.append("hints_off")
	return ", ".join(parts)


func _reset_global_ui_state() -> void:
	Director.choice_hold = false
	Director.abort()
	Director.resume()
	Director.set_letterbox(false, true)
	if get_tree().paused:
		get_tree().paused = false
	var cap: Caption = Director.caption()
	if cap != null:
		cap.clear()


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


# --- 1F 可读性回归：毒素槽 / 安全区 / 键帽 / Boss 相数 / 顶部提示 ---------------

const TOXIN_CASES := [
	[0.0, &"ToxinBarCold", "冷 0%"],
	[35.0, &"ToxinBarWarm", "温 35%"],
	[68.0, &"ToxinBarHot", "炽 68%"],
	[100.0, &"ToxinBarOverflow", "溢 100%"],
]


## 毒素槽曾经是心下面一道 96×12 的暗缝：撑不满状态带、空槽和墨带同色、
## 温/炽/溢三档共用同一条绿色填充。现在它必须是一条和心行同宽的量槽，
## 高度够读、按档位换填充色，而且 3 位数档位字装得进自己的槽。
func test_toxin_gauge_fills_the_plate_and_recolours_per_band() -> void:
	var hud := HUD_SCENE.instantiate()
	add_child(hud)
	await flush(2)
	GameEvents.player_health_changed.emit(7, 7)
	await flush(2)
	var bar := hud.find_child("ToxinBar", true, false) as ProgressBar
	var label := hud.find_child("ToxinLabel", true, false) as Label
	var slot := hud.find_child("ToxinLabelSlot", true, false) as Control
	var plate := hud.find_child("Plate", true, false) as Control
	ok(bar != null and label != null and slot != null and plate != null,
			"toxin gauge nodes exist")
	if bar == null or label == null or slot == null or plate == null:
		hud.queue_free()
		await flush(1)
		return
	ok(bar.custom_minimum_size.y >= 14.0,
			"toxin gauge is thick enough to read (%.0f design px)" % bar.custom_minimum_size.y)
	ok((bar.size_flags_horizontal & Control.SIZE_EXPAND) != 0,
			"toxin gauge stretches with the hearts row instead of staying 96px wide")
	ok(bar.size.x >= plate.size.x * 0.5,
			"toxin gauge fills most of the status plate (%.1f of %.1f)"
			% [bar.size.x, plate.size.x])
	for entry in TOXIN_CASES:
		GameEvents.toxin_changed.emit(float(entry[0]), 100.0)
		await flush(1)
		eq(bar.theme_type_variation, entry[1], "band %.0f uses %s" % [entry[0], entry[1]])
		eq(label.text, entry[2], "band label at %.0f" % entry[0])
	GameEvents.toxin_changed.emit(100.0, 100.0)
	await flush(1)
	ok(label.get_combined_minimum_size().x <= slot.size.x + 0.5,
			"the 3-digit band word fits its slot (%.1f <= %.1f)"
			% [label.get_combined_minimum_size().x, slot.size.x])
	hud.queue_free()
	await flush(1)


## 触屏刘海：安全区必须真的把状态带 / 横幅 / 天气行 / Boss 条 / 交互提示推进来，
## 而不是只在 TouchInput 里算出一个没人用的 Vector4。headless 喂一组边距验证排版。
func test_safe_area_insets_push_every_hud_row_inward() -> void:
	var hud := HUD_SCENE.instantiate()
	add_child(hud)
	await flush(2)
	var insets := Vector4(24.0, 16.0, 30.0, 20.0)
	hud.apply_safe_insets(insets)
	await flush(2)
	var stat := hud.find_child("StatPanel", true, false) as Control
	var banner := hud.find_child("Banner", true, false) as Control
	var atmos := hud.find_child("AtmosphereHint", true, false) as Control
	var prompt := hud.find_child("Prompt", true, false) as Control
	var boss_bar := hud.find_child("BossBar", true, false) as Control
	ok(stat != null and banner != null and atmos != null and prompt != null and boss_bar != null,
			"HUD rows exist")
	if stat == null or banner == null or atmos == null or prompt == null or boss_bar == null:
		hud.queue_free()
		await flush(1)
		return
	almost(stat.offset_left, 12.0 + insets.x, 0.01, "status plate clears the left notch")
	almost(stat.offset_top, 8.0 + insets.y, 0.01, "status plate clears the top notch")
	almost(banner.offset_top, 14.0 + insets.y, 0.01, "banner clears the top notch")
	almost(atmos.offset_right, -(18.0 + insets.z), 0.01, "weather line clears the right notch")
	almost(prompt.offset_bottom, -(10.0 + insets.w), 0.01, "prompt clears the bottom notch")
	almost(boss_bar.offset_bottom, -(22.0 + insets.w), 0.01, "boss bar clears the bottom notch")
	almost(boss_bar.offset_top, -(22.0 + insets.w + 50.0), 0.01,
			"boss bar keeps its 50px height above the bottom inset")
	var plate: Rect2 = hud.plate_rect()
	ok(plate.position.x >= insets.x - 0.01 and plate.position.y >= insets.y - 0.01,
			"status plate stays inside the safe area (%s)" % plate)
	ok(plate.end.x <= 1280.0 - insets.z + 0.01, "status plate clears the right notch (%s)" % plate)
	hud.queue_free()
	await flush(1)


## 交互提示拆成键帽 + 文案：键帽跟随 Settings 改键（和设置页同一个来源），
## 触屏上换成触控板那颗"互"；不带键位的提示不画键帽。
func test_prompt_keycap_follows_rebinding_and_hides_without_a_key() -> void:
	var hud := HUD_SCENE.instantiate()
	add_child(hud)
	await flush(2)
	var old_key := Settings.key_for(&"interact")
	var key_panel := hud.find_child("PromptKeyPanel", true, false) as Control
	ok(key_panel != null, "prompt keycap panel exists")
	GameEvents.interact_prompt.emit("E 点燃余烬巢")
	await flush(1)
	eq(hud.prompt_key_text(), KeyLabels.label(&"interact"),
			"keycap mirrors the interact binding (not a hardcoded E)")
	eq(hud.prompt_body_text(), "点燃余烬巢", "the prompt body drops the key prefix")
	ok(key_panel != null and key_panel.visible, "the keycap is drawn for a keyed prompt")
	if key_panel != null:
		ok(key_panel.get_global_rect().size.x >= 16.0, "the keycap is a real plate, not empty space")
	Settings.rebind_action(&"interact", KEY_Q, false)
	await flush(2)
	eq(hud.prompt_key_text(), "Q", "keycap follows a live rebind, like the settings page")
	TouchInput.force_show = 1
	GameEvents.interact_prompt.emit("E 点燃余烬巢")
	await flush(1)
	eq(hud.prompt_key_text(), "互", "touch players see the on-screen pad's interact glyph")
	TouchInput.force_show = 0
	GameEvents.interact_prompt.emit("门已锁住")
	await flush(1)
	eq(hud.prompt_key_text(), "", "a prompt without a key draws no keycap")
	eq(hud.prompt_body_text(), "门已锁住", "keyless prompts keep their full sentence")
	ok(key_panel != null and not key_panel.visible, "no empty keycap plate for keyless prompts")
	Settings.rebind_action(&"interact", old_key, false)
	await flush(1)
	hud.queue_free()
	await flush(1)


## Boss 血条：名字 + 相数刻度 + 余烬色 HP 都要装进底边那条，升相时刻度加一只，
## 击败后清空。之前血条是 toxin 的绿色填充，且升相在常驻血条上没有任何读数。
func test_boss_bar_shows_phase_ticks_and_an_ember_hp_fill() -> void:
	var hud := HUD_SCENE.instantiate()
	add_child(hud)
	await flush(2)
	var bar_panel := hud.find_child("BossBar", true, false) as Control
	var hp: ProgressBar = hud.boss_hp_bar()
	var pips: Control = hud.boss_phase_pips()
	ok(bar_panel != null and hp != null and pips != null, "boss bar nodes exist")
	if bar_panel == null or hp == null or pips == null:
		hud.queue_free()
		await flush(1)
		return
	eq(hp.theme_type_variation, &"BossHpBar",
			"boss HP uses the ember variation, not the toxin green")
	ok(hp.custom_minimum_size.y >= 12.0,
			"boss HP bar is thick enough (%.0f design px)" % hp.custom_minimum_size.y)
	GameEvents.boss_appeared.emit("炉约刽子手 · 铸渣残躯", 13, 13)
	await flush(2)
	eq(hud.boss_phase_count(), 1, "phase one shows one tick")
	ok(hud.boss_bar_rect().size.y <= 52.0,
			"boss bar stays 50px tall (%s)" % hud.boss_bar_rect())
	var title_row: Control = hud.boss_title_row()
	ok(title_row != null, "name and ticks share one row")
	if title_row != null:
		ok(hud.boss_bar_rect().encloses(title_row.get_global_rect()),
				"name + ticks stay inside the bar (%s)" % title_row.get_global_rect())
		ok(title_row.get_combined_minimum_size().x <= 460.0 - 28.0,
				"name and ticks fit the 460px bar width")
	GameEvents.boss_phase_changed.emit("炉约刽子手 · 铸渣残躯", 2)
	await flush(2)
	eq(hud.boss_phase_count(), 2, "second phase adds a tick")
	GameEvents.boss_defeated.emit()
	await flush(2)
	eq(hud.boss_phase_count(), 0, "defeat clears the phase ticks")
	hud.queue_free()
	await flush(1)


## 低血量血雾：最低血时看得见（会呼吸的红边），但透明度压到 0.4 以下，
## 不再把骑手所在的左半屏整片染红；回血后必须收干净。
func test_low_health_vignette_is_visible_but_subtle() -> void:
	var hud := HUD_SCENE.instantiate()
	add_child(hud)
	await flush(2)
	GameEvents.player_health_changed.emit(7, 7)
	await flush(2)
	eq(hud.vignette_alpha(), 0.0, "no blood vignette at full health")
	GameEvents.player_health_changed.emit(1, 7)
	var faded_in: bool = await wait_until(func() -> bool: return hud.vignette_alpha() > 0.3, 120)
	ok(faded_in, "low HP raises the vignette")
	ok(hud.vignette_alpha() <= 0.40,
			"vignette stays subtle (alpha %.2f <= 0.40)" % hud.vignette_alpha())
	# 呼吸期间也不会超过上限：采样半个周期，取最大值。
	var peak := 0.0
	for i in 45:
		await get_tree().physics_frame
		peak = maxf(peak, hud.vignette_alpha())
	ok(peak <= 0.40, "vignette breathing never covers the knight silhouette (peak %.2f)" % peak)
	GameEvents.player_health_changed.emit(7, 7)
	var cleared: bool = await wait_until(func() -> bool: return hud.vignette_alpha() <= 0.0, 180)
	ok(cleared, "healing fades the vignette back out")
	hud.queue_free()
	await flush(1)


## 顶部那条"Tab 目标 · 天气"曾经是 24px 的大横幅，压在画面上 1/12 屏；
## 现在必须是 12px 的小提示，死亡时立刻消失，而且永远画在死亡幕下面。
func test_peek_hint_is_compact_and_never_covers_the_death_screen() -> void:
	HintService.forget_all()
	Settings.set_value(&"hints_on", true, false)
	# 提示只在"没有过场 / 黑边 / 字幕 / 暂停"时出现；全量跑时这些状态可能是前面
	# 用例留下的，先在 setup() 清过一次，这里再断言一次前置条件，失败时好定位。
	var cap: Caption = Director.caption()
	ok(not get_tree().paused and not Director.playing and not Director.choice_hold
			and not Director.is_input_locked() and Director.letterbox_amount() <= 0.02
			and (cap == null or not cap.is_busy()),
			"hint preconditions are clean before the case runs")
	var hud := HUD_SCENE.instantiate()
	add_child(hud)
	await flush(2)
	var hints: HintService = hud.hint_service()
	var appeared: bool = await wait_until(func() -> bool: return hints.is_showing(), 180)
	if not appeared:
		print("HINT_DEBUG paused=", get_tree().paused, " enabled=", HintService.enabled(),
				" seen=", HintService.has_seen(&"peek"),
				" playing=", Director.playing, " choice_hold=", Director.choice_hold,
				" locked=", Director.is_input_locked(),
				" letterbox=", Director.letterbox_amount(),
				" caption_busy=", cap != null and cap.is_busy(),
				" current=", hints.current_id(), " queued=", hints.queued_id(),
				" tree=", hints.is_inside_tree(), " proc=", hints.is_processing())
	ok(appeared, "the one-time peek hint appears at chapter start")
	var plate := hud.find_child("HintPlate", true, false) as Control
	ok(plate != null, "hint plate exists")
	if plate != null:
		var label := plate.find_child("Text", true, false) as Label
		ok(label != null, "hint label exists")
		if label != null:
			eq(label.theme_type_variation, &"TinyHintLabel", "peek hint uses the compact 12px style")
			eq(label.get_theme_font_size("font_size"), 12, "peek hint is 12px, not 24")
			ok(not label.text.contains("查看目标与天气"),
					"peek hint text is shortened to a single line")
		ok(plate.get_global_rect().size.y <= 26.0,
				"peek hint bar is half-height (%.1f design px)" % plate.get_global_rect().size.y)
		ok(plate.get_global_rect().size.x <= 460.0,
				"peek hint bar no longer spans the play area (%s)" % plate.get_global_rect())
		almost(plate.get_global_rect().get_center().x, 640.0, 1.0,
				"peek hint bar stays centered on the HUD canvas")
	# 死亡幕：提示必须马上让位，并且绘制层级在死亡幕之下。
	GameEvents.player_died.emit()
	await flush(3)
	var death := hud.find_child("DeathOverlay", true, false) as Control
	ok(death != null and death.visible, "death overlay is up")
	if plate != null and death != null:
		ok(not plate.visible, "the teaching hint does not linger over the death screen")
		var root := hud.get_node("Root") as Control
		var children := root.get_children()
		var hint_index := children.find(plate)
		var death_index := children.find(death)
		ok(hint_index >= 0 and death_index >= 0 and hint_index < death_index,
				"hint draws below the death overlay (%d < %d)" % [hint_index, death_index])
	hud.queue_free()
	HintService.forget_all()
	await flush(1)
