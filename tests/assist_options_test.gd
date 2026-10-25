extends TestCase
## 辅助选项测试：默认不改变伤害/窗口、各档数值生效、字号放大不破布局、持久化往返。

const TEST_PATH := "user://rustgrave_test_assist_settings.cfg"

var _old_path := ""


func setup() -> void:
	_old_path = Settings.save_path
	Settings.save_path = TEST_PATH
	_remove(TEST_PATH)
	_remove(TEST_PATH + ".tmp")
	Settings.load_settings()


func teardown() -> void:
	Settings.reset_assist(false)
	Settings.save_path = _old_path
	Settings.load_settings()
	_remove(TEST_PATH)
	_remove(TEST_PATH + ".tmp")


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_defaults_do_not_alter_damage_windows_toxin_subtitle_or_text_scale() -> void:
	almost(Settings.damage_taken_scale, 1.0)
	almost(Settings.parry_window_scale, 1.0)
	almost(Settings.toxin_fill_scale, 1.0)
	almost(Settings.subtitle_speed_scale, 1.0)
	almost(Settings.ui_text_scale, 1.0)
	ok(not CombatRules.is_assist_invincible())

	var hp := Health.new()
	hp.max_hp = 5
	hp.hit_iframe_time = 0.0
	add_child(hp)
	ok(hp.take_damage(2))
	eq(hp.current, 3, "默认 ×1 受伤倍率扣减原额伤害")
	hp.queue_free()

	var melee := MeleeCombat.new()
	add_child(melee)
	almost(melee.active_window_for_step(0), float(CombatRules.SWING_ACTIVE[0]), 0.0001)
	almost(melee.active_window_for_step(2), float(CombatRules.SWING_ACTIVE[2]), 0.0001)
	melee.queue_free()

	var toxin := ToxinMeter.new()
	add_child(toxin)
	toxin.expose(40.0)
	almost(toxin.toxin, 40.0, 0.01, "默认 ×1 毒素累积速度不衰减")
	toxin.queue_free()

	almost(Caption.effective_chars_per_sec(), Caption.CHARS_PER_SEC, 0.01)
	eq(UiKit.scaled_font_size(12), 12)
	await get_tree().process_frame


func test_damage_taken_assist_half_and_invincible() -> void:
	var hp := Health.new()
	hp.max_hp = 6
	hp.hit_iframe_time = 0.0
	add_child(hp)

	Settings.set_damage_taken_scale(0.5, false)
	ok(hp.take_damage(2), "2 点伤害在 ×0.5 下造成 1 点实伤")
	eq(hp.current, 5)

	# 1 点伤害在 ×0.5 下累积两击扣 1 点血
	ok(not hp.take_damage(1), "首击 0.5 点伤害记入半格累积")
	eq(hp.current, 5)
	ok(hp.take_damage(1), "次击凑满 1 点伤害扣血")
	eq(hp.current, 4)

	# 免伤（辅助）：在 Health.take_damage 预处理直接拦截
	Settings.set_damage_taken_scale(0.0, false)
	ok(CombatRules.is_assist_invincible(), "免伤档激活")
	ok(not hp.take_damage(99), "免伤档拦截一切伤害")
	eq(hp.current, 4, "免伤档生命值不变")

	hp.queue_free()
	await get_tree().process_frame


func test_parry_window_and_toxin_fill_assist_multipliers() -> void:
	var melee := MeleeCombat.new()
	add_child(melee)
	Settings.set_parry_window_scale(1.5, false)
	almost(melee.active_window_for_step(0), 0.18, 0.0001, "第一刀弹反窗口放大至 1.5 倍")
	almost(melee.active_window_for_step(2), 0.255, 0.0001, "终结击弹反窗口放大至 1.5 倍")
	almost(float(CombatRules.SWING_ACTIVE[0]), 0.12, 0.0001, "CombatRules 基础常量保持不变")
	melee.queue_free()

	var toxin := ToxinMeter.new()
	add_child(toxin)
	Settings.set_toxin_fill_scale(0.5, false)
	toxin.expose(40.0)
	almost(toxin.toxin, 20.0, 0.01, "×0.5 毒素累积速度减半")
	toxin.queue_free()
	await get_tree().process_frame


func test_subtitle_speed_and_ui_text_scale_preserve_layout() -> void:
	var before_rect: Rect2 = PresentationMetrics.for_viewport(Vector2(1280, 720))["content"]
	Settings.set_subtitle_speed_scale(1.5, false)
	almost(Caption.effective_chars_per_sec(), Caption.CHARS_PER_SEC * 1.5, 0.01)

	Settings.set_ui_text_scale(1.25, false)
	eq(UiKit.scaled_font_size(12), 15)
	Settings.set_ui_text_scale(1.5, false)
	eq(UiKit.scaled_font_size(12), 18)

	var after_rect: Rect2 = PresentationMetrics.for_viewport(Vector2(1280, 720))["content"]
	eq(after_rect, before_rect, "字号放大不改变 PresentationMetrics 内容矩形")

	var screen := SettingsScreen.new()
	add_child(screen)
	await get_tree().process_frame
	screen.show_tab(SettingsScreen.TAB_KEYS)
	await get_tree().process_frame
	var card := screen.get_node_or_null("ModalRoot/Card") as Control
	var grid := screen.find_child("KeyGrid", true, false) as GridContainer
	if card != null and grid != null:
		ok(card.get_global_rect().encloses(grid.get_global_rect()), "150% 字号下键位网格仍不撑破卡片")
	screen.queue_free()
	await get_tree().process_frame


func test_assist_options_persist_and_expose_on_settings_screen() -> void:
	Settings.set_damage_taken_scale(0.0)
	Settings.set_parry_window_scale(1.5)
	Settings.set_toxin_fill_scale(0.5)
	Settings.set_subtitle_speed_scale(0.75)
	Settings.set_ui_text_scale(1.25)

	Settings.reset_assist(false)
	almost(Settings.damage_taken_scale, 1.0)
	ok(Settings.load_settings(), "重读辅助选项配置")
	almost(Settings.damage_taken_scale, 0.0)
	almost(Settings.parry_window_scale, 1.5)
	almost(Settings.toxin_fill_scale, 0.5)
	almost(Settings.subtitle_speed_scale, 0.75)
	almost(Settings.ui_text_scale, 1.25)

	var screen := SettingsScreen.new()
	add_child(screen)
	await get_tree().process_frame
	screen.show_tab(SettingsScreen.TAB_ASSIST)
	await get_tree().process_frame
	for id in SettingsScreen.ASSIST_IDS:
		ok(screen.toggle_for(id) != null, "辅助页暴露 %s 控件" % String(id))
	eq(screen.value_text(SettingsScreen.OPT_DAMAGE_TAKEN), "免伤（辅助）")
	eq(screen.value_text(SettingsScreen.OPT_PARRY_WINDOW), "×1.5（辅助）")
	eq(screen.value_text(SettingsScreen.OPT_TOXIN_FILL), "×0.5（辅助）")
	eq(screen.value_text(SettingsScreen.OPT_SUBTITLE_SPEED), "慢 ×0.75")
	eq(screen.value_text(SettingsScreen.OPT_UI_TEXT_SCALE), "125%")

	screen.queue_free()
	await get_tree().process_frame
