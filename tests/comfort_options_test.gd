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


func test_assisted_windup_deflects_real_projectile_without_early_sword_damage() -> void:
	Director.abort()
	Director._set_lock(false)
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	player.set_physics_process(false)
	player.melee.set_process(false)
	var target := Node2D.new()
	target.position = player.position + Vector2(18, -14)
	var hp := Health.new()
	hp.name = "Health"
	hp.max_hp = 20
	target.add_child(hp)
	var hurt := Hurtbox.new()
	hurt.team = &"enemy"
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(10, 10)
	shape.shape = rect
	hurt.add_child(shape)
	target.add_child(hurt)
	arena.add_child(target)
	var bolt := preload("res://scenes/combat/Projectile.tscn").instantiate() as Projectile
	bolt.setup(target.position, Vector2.LEFT, 0.0, &"enemy", null)
	arena.add_child(bolt)
	await flush(2)
	ok(player.melee.start_swing())
	player.melee.tick(player.melee.windup_time * 0.6)
	player.melee._process(0.0)
	ok(not bolt.deflected, "default windup does not parry")
	Settings.set_value(&"assist_parry", 1.5, false)
	player.melee._process(0.0)
	ok(bolt.deflected, "production overlap query deflects during assisted windup")
	ok(not player.melee.hitbox.monitoring, "sword damage volume remains disabled")
	eq(hp.current, 20, "adjacent enemy takes no early sword damage")
	ok(player.melee.swing_connected())
	player.melee.tick(player.melee.windup_time)
	eq(player.melee.phase_name(), "active")
	ok(player.melee._parried_swing, "entering active preserves this swing's earlier parry")
	ok(hp.current < 20, "sword damage starts at the normal active boundary")


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
	# Labels created *after* the setting loads must keep the same theme sizes.
	# A blanket `16 * scale` override used to shrink the 24px menu to 20/22px
	# while inflating the 12px labels — the boot path hit exactly this case.
	var scaled := UiKit.label("scaled", &"BodyLabel")
	add_child(scaled)
	eq(scaled.get_theme_font_size("font_size"), roundi(body * 1.25),
			"a label created at 125% inherits the scaled theme, not a 16px override")
	Settings.set_value(&"text_scale", 1.0, false)
	eq(theme.get_font_size("font_size", &"BodyLabel"), body)
	eq(theme.get_font_size("font_size", &"TinyLabel"), tiny)
	label.queue_free()
	scaled.queue_free()


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
