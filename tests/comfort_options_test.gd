extends TestCase


func teardown() -> void:
	for key in Settings.ASSIST_LIMITS:
		Settings._extra.erase(key)
	UiKit.apply_text_scale(1.0)


func test_default_combat_and_clamped_ranges() -> void:
	for key in Settings.ASSIST_LIMITS:
		almost(Settings.assist(key), 1.0)
	eq(CombatRules.incoming_damage(4), 4)
	almost(CombatRules.toxin_exposure(20.0), 20.0)
	Settings.set_value(&"assist_incoming", 0.5, false)
	eq(CombatRules.incoming_damage(4), 2)
	Settings.set_value(&"assist_toxin", 0.5, false)
	almost(CombatRules.toxin_exposure(20.0), 10.0)
	almost(CombatRules.toxin_exposure(-10.0), -10.0, 0.001, "purifying stays unchanged")
	Settings.set_value(&"assist_parry", 20.0, false)
	almost(Settings.assist(&"assist_parry"), 1.5)
	Settings.set_value(&"assist_parry", 0.0, false)
	almost(Settings.assist(&"assist_parry"), 1.0)


func test_parry_assist_opens_only_late_windup() -> void:
	var melee := MeleeCombat.new()
	var hitbox := Hitbox.new()
	hitbox.name = "Hitbox"
	melee.add_child(hitbox)
	add_child(melee)
	ok(not melee.is_parry_window())
	ok(melee.start_swing())
	melee.tick(melee.windup_time * 0.6)
	ok(not melee.is_parry_window(), "default windup is closed")
	Settings.set_value(&"assist_parry", 1.5, false)
	ok(melee.is_parry_window(), "late windup opens with the assist")
	melee.cancel_attack()
	ok(not melee.is_parry_window(), "assist never makes idle parry")


func test_player_damage_and_exposure_use_assists_but_enemies_do_not() -> void:
	var player := preload("res://scenes/player/Player.tscn").instantiate() as Player
	add_child(player)
	player.set_physics_process(false)
	player.health.max_hp = 20
	player.health.current = 20
	Settings.set_value(&"assist_incoming", 0.5, false)
	ok(player.health.take_damage(4))
	eq(player.health.current, 18)
	Settings.set_value(&"assist_toxin", 0.5, false)
	player.toxin.toxin = 0.0
	player.toxin.expose(20.0)
	almost(player.toxin.toxin, 10.0)
	var enemy_hp := Health.new()
	add_child(enemy_hp)
	enemy_hp.current = 20
	ok(enemy_hp.take_damage(4))
	eq(enemy_hp.current, 16)


func test_text_scale_preserves_theme_ratios_and_updates_live() -> void:
	var theme := load(UiKit.THEME_PATH) as Theme
	var body := theme.get_font_size("font_size", &"BodyLabel")
	var tiny := theme.get_font_size("font_size", &"TinyLabel")
	var label := UiKit.label("text", &"BodyLabel")
	add_child(label)
	Settings.set_value(&"text_scale", 1.25, false)
	eq(theme.get_font_size("font_size", &"BodyLabel"), roundi(body * 1.25))
	eq(theme.get_font_size("font_size", &"TinyLabel"), roundi(tiny * 1.25))
	eq(label.get_theme_font_size("font_size"), roundi(body * 1.25))
	Settings.set_value(&"text_scale", 1.0, false)
	eq(theme.get_font_size("font_size", &"BodyLabel"), body)
	eq(theme.get_font_size("font_size", &"TinyLabel"), tiny)


func test_subtitle_speed_changes_reveal_rate() -> void:
	var caption := Caption.new()
	add_child(caption)
	caption.set_process(false)
	caption.enqueue("字幕速度行为测试需要足够长的一句话来观察文字显示速率。", 1.0)
	caption._process(0.1)
	var normal := caption._shown
	caption.clear()
	Settings.set_value(&"subtitle_speed", 1.5, false)
	caption.enqueue("字幕速度行为测试需要足够长的一句话来观察文字显示速率。", 1.0)
	caption._process(0.1)
	ok(caption._shown > normal, "public setting changes live caption reveal")


func test_settings_page_exposes_every_public_assist_range() -> void:
	var screen := SettingsScreen.new()
	add_child(screen)
	screen.open()
	screen._select_tab(SettingsScreen.TAB_ASSIST)
	for key in Settings.ASSIST_LIMITS:
		var slider := screen.slider_for(key)
		ok(slider != null, String(key))
		if slider != null:
			var limits: Vector2 = Settings.ASSIST_LIMITS[key]
			almost(slider.min_value, limits.x * 100.0)
			almost(slider.max_value, limits.y * 100.0)
	screen.flush()
