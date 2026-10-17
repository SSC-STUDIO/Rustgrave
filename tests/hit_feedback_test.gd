extends TestCase
## 命中反馈矩阵（材质 x 出手分量）：数据完整、单调、范围合理；Juice 按 Settings 缩放震屏 / 闪屏；
## 敌人的硬直 / 击退取自同一张表；同屏临时节点的预算。

var _saved_shake := 1.0
var _saved_flash := 1.0


func setup() -> void:
	_saved_shake = Settings.shake_scale
	_saved_flash = Settings.flash_scale


func teardown() -> void:
	Settings.shake_scale = _saved_shake
	Settings.flash_scale = _saved_flash
	Engine.time_scale = 1.0
	Juice._priority = 0
	Juice._restore_at_ms = 0


const ROW_KEYS := ["stop_ms", "stop_scale", "shake_px", "shake_ms", "spark", "debris", "ring",
		"knock", "lock", "recoil", "sfx"]
const SPARKS := [&"sheet", &"metal", &"bone", &"ghost"]
const DEBRIS := [&"none", &"rust", &"bone", &"ghost"]
## 音频包新增的键（入库前走 SFX_FALLBACK 退回老键）。
const NEW_SFX := [&"hit_metal", &"hit_bone", &"hit_heavy", &"shield_block", &"shield_break"]


func test_matrix_is_complete_and_well_formed() -> void:
	for material in CombatRules.MATERIALS:
		for weight in CombatRules.WEIGHTS:
			var row: Dictionary = CombatRules.HIT_FEEL[material][weight]
			for key in ROW_KEYS:
				ok(row.has(key), "%s/%s has %s" % [material, weight, key])
			ok(int(row["stop_ms"]) >= 25 and int(row["stop_ms"]) <= 90, "%s/%s hit-stop in 25-90 ms" % [material, weight])
			ok(float(row["stop_scale"]) > 0.0 and float(row["stop_scale"]) <= 0.2, "%s/%s hit-stop stays a freeze, not a stall" % [material, weight])
			ok(float(row["shake_px"]) > 0.0 and float(row["shake_px"]) <= CombatRules.SHAKE_PX_CAP, "%s/%s shake within the cap" % [material, weight])
			ok(int(row["shake_ms"]) >= 60 and int(row["shake_ms"]) <= 200, "%s/%s shake duration sane" % [material, weight])
			ok(SPARKS.has(row["spark"]), "%s/%s spark kind known" % [material, weight])
			ok(DEBRIS.has(row["debris"]), "%s/%s debris kind known" % [material, weight])
			ok(float(row["knock"]) >= 0.0 and float(row["knock"]) <= 1.0)
			ok(float(row["lock"]) >= 0.0 and float(row["lock"]) <= 0.3, "%s/%s flinch short enough to keep telegraphs fair" % [material, weight])
			var key: StringName = row["sfx"]
			var lib: Dictionary = Sfx.get_script().get_script_constant_map()["LIBRARY"]
			ok(lib.has(key) or NEW_SFX.has(key), "%s/%s sfx key %s is a library key or a declared new one" % [material, weight, key])
			var resolved := CombatRules.sfx_key(key)
			ok(lib.has(resolved) or NEW_SFX.has(resolved) or lib.has(CombatRules.SFX_FALLBACK.get(key, key)),
					"%s resolves to something that can play" % key)


func test_heavier_blows_hit_harder_for_every_material() -> void:
	for material in CombatRules.MATERIALS:
		var l: Dictionary = CombatRules.feel(material, &"light")
		var h: Dictionary = CombatRules.feel(material, &"heavy")
		var f: Dictionary = CombatRules.feel(material, &"finisher")
		ok(int(l["stop_ms"]) < int(h["stop_ms"]) and int(h["stop_ms"]) < int(f["stop_ms"]), "%s hit-stop climbs" % material)
		ok(float(l["shake_px"]) < float(h["shake_px"]) and float(h["shake_px"]) < float(f["shake_px"]), "%s shake climbs" % material)
		ok(float(l["lock"]) <= float(h["lock"]) and float(h["lock"]) <= float(f["lock"]), "%s flinch never shrinks with weight" % material)


func test_material_character() -> void:
	for weight in CombatRules.WEIGHTS:
		ok(float(CombatRules.feel(&"armour", weight)["knock"]) < float(CombatRules.feel(&"flesh", weight)["knock"]), "armour is shoved less than flesh")
		eq(float(CombatRules.feel(&"shield", weight)["knock"]), 0.0, "a raised shield is not shoved at all")
		ok(float(CombatRules.feel(&"boss", weight)["knock"]) <= 0.2, "bosses barely move")
		eq(CombatRules.feel(&"armour", weight)["spark"], &"metal")
		eq(CombatRules.feel(&"bone", weight)["spark"], &"bone")
		eq(CombatRules.feel(&"ghost", weight)["spark"], &"ghost")
	eq(CombatRules.feel(&"boss", &"light")["lock"], 0.0, "a boss never loses its telegraph to a light poke")
	eq(CombatRules.feel(&"boss", &"heavy")["lock"], 0.0)
	ok(int(CombatRules.feel(&"armour", &"heavy")["stop_ms"]) > int(CombatRules.feel(&"flesh", &"heavy")["stop_ms"]), "metal rings longer than flesh")
	ok(int(CombatRules.feel(&"ghost", &"light")["stop_ms"]) < int(CombatRules.feel(&"flesh", &"light")["stop_ms"]), "a ghost barely resists")


func test_flesh_row_keeps_the_original_feel() -> void:
	var l: Dictionary = CombatRules.feel(&"flesh", &"light")
	eq(int(l["stop_ms"]), 40)
	almost(float(l["shake_px"]), 2.0)
	var f: Dictionary = CombatRules.feel(&"flesh", &"finisher")
	eq(int(f["stop_ms"]), 70)
	almost(float(f["shake_px"]), 4.5)


func test_unknown_material_or_weight_falls_back() -> void:
	eq(CombatRules.feel(&"cheese", &"light"), CombatRules.HIT_FEEL[&"flesh"][&"light"])
	eq(CombatRules.feel(&"bone", &"colossal"), CombatRules.HIT_FEEL[&"bone"][&"light"])


func test_weight_for_lifts_by_damage_and_kill() -> void:
	var box := Hitbox.new()
	box.blow = &"light"
	eq(CombatRules.weight_for(box, 1, false), &"light")
	eq(CombatRules.weight_for(box, 2, false), &"heavy", "two damage lifts a light blow")
	eq(CombatRules.weight_for(box, 1, true), &"finisher", "a kill is always the biggest feedback")
	box.blow = &"finisher"
	eq(CombatRules.weight_for(box, 1, false), &"finisher")
	eq(CombatRules.weight_for(null, 1, false), &"light", "unknown attackers read as light")
	box.free()


func test_material_of_reads_declared_material() -> void:
	var skeleton := preload("res://scenes/enemies/SkeletonEnemy.tscn").instantiate()
	add_child(skeleton)
	eq(CombatRules.material_of(skeleton), &"bone")
	var plain := Node2D.new()
	add_child(plain)
	eq(CombatRules.material_of(plain), &"flesh", "undeclared targets are flesh")
	eq(CombatRules.material_of(null), &"flesh")


# ---------------------------------------------------------------------------
# Juice：缩放与上限
# ---------------------------------------------------------------------------
func test_shake_is_scaled_by_settings_at_the_moment_it_fires() -> void:
	Settings.shake_scale = 1.0
	Juice.shake(4.0, 100)
	almost(Juice.last_shake_px, 4.0)
	Settings.shake_scale = 0.5
	Juice.shake(4.0, 100)
	almost(Juice.last_shake_px, 2.0, 0.0001, "half scale halves the jolt")
	Settings.shake_scale = 0.0
	Juice.shake(4.0, 100)
	almost(Juice.last_shake_px, 0.0, 0.0001, "zero scale is a full off switch")
	Settings.shake_scale = 1.0
	Juice.shake(40.0, 100)
	almost(Juice.last_shake_px, CombatRules.SHAKE_PX_CAP, 0.0001, "absurd requests are capped")


func test_flash_is_scaled_by_settings_and_capped() -> void:
	Settings.flash_scale = 1.0
	Juice.flash(Color(1, 1, 1, 0.9), 100)
	almost(Juice.last_flash_alpha, CombatRules.FLASH_ALPHA_CAP, 0.0001, "gameplay flashes never exceed the cap")
	Settings.flash_scale = 0.5
	Juice.flash(Color(1, 1, 1, 0.3), 100)
	almost(Juice.last_flash_alpha, 0.15, 0.0001)
	Settings.flash_scale = 0.0
	Juice.flash(Color(1, 1, 1, 0.3), 100)
	almost(Juice.last_flash_alpha, 0.0, 0.0001, "zero scale is a full off switch")
	Settings.flash_scale = 1.0
	Juice.flash(Color(0, 0, 0, 0.9), 700, true)
	almost(Juice.last_flash_alpha, 0.9, 0.0001, "the death fade is exempt from the cap (the knight is already down)")
	Settings.flash_scale = 0.5
	Juice.flash(Color(0, 0, 0, 0.9), 700, true)
	almost(Juice.last_flash_alpha, 0.45, 0.0001, "...but still honours the comfort option")


func test_every_gameplay_flash_stays_under_the_cap() -> void:
	ok(float(CombatRules.PLAYER_HURT["flash"].a) <= CombatRules.FLASH_ALPHA_CAP)
	ok(float(CombatRules.PARRY_FEEL["flash"].a) <= CombatRules.FLASH_ALPHA_CAP)
	ok(float(CombatRules.BOSS_PHASE_FEEL["flash_alpha"]) <= CombatRules.FLASH_ALPHA_CAP)
	ok(float(CombatRules.BOSS_DEATH_FEEL["flash_alpha"]) <= CombatRules.FLASH_ALPHA_CAP)
	ok(CombatRules.FLASH_ALPHA_CAP <= 0.4, "a flash can never wash out more than 40% of the picture")
	ok(float(CombatRules.PLAYER_HURT["shake_px"]) <= CombatRules.SHAKE_PX_CAP)
	ok(float(CombatRules.BOSS_DEATH_FEEL["shake_px"]) <= CombatRules.SHAKE_PX_CAP)


func test_camera_trauma_and_land_punch_respect_the_shake_option() -> void:
	var cam := GameCamera.new()
	add_child(cam)
	Settings.shake_scale = 0.0
	cam.add_trauma(1.0)
	almost(cam._trauma, 0.0, 0.0001, "no trauma with shake off")
	cam.notify_landed()
	almost(cam.punch_offset().y, 0.0, 0.0001, "no landing punch with shake off")
	Settings.shake_scale = 0.5
	cam.add_trauma(0.8)
	almost(cam._trauma, 0.4, 0.0001, "trauma scales")
	Settings.shake_scale = 1.0
	cam.free()


func test_feel_runs_the_matrix_row() -> void:
	var row := Juice.feel(&"armour", &"heavy", Vector2.ZERO, 0.0)
	eq(row, CombatRules.feel(&"armour", &"heavy"))
	eq(Juice.last_feel, row)
	almost(Engine.time_scale, float(row["stop_scale"]), 0.0001, "hit-stop uses the row's scale")


func test_hit_signal_drives_the_row_for_the_target_material() -> void:
	var arena := Node2D.new()
	add_child(arena)
	var skeleton := preload("res://scenes/enemies/SkeletonEnemy.tscn").instantiate() as Node2D
	arena.add_child(skeleton)
	await flush(1)
	var box := Hitbox.new()
	box.blow = &"light"
	arena.add_child(box)
	Juice.last_feel = {}
	GameEvents.hit.emit(box, skeleton, 1)
	eq(Juice.last_feel, CombatRules.feel(&"bone", &"light"), "a skeleton is a bone target")
	Juice.last_feel = {}
	GameEvents.hit.emit(box, skeleton, 2)
	eq(Juice.last_feel, CombatRules.feel(&"bone", &"heavy"), "two damage reads heavy")


# ---------------------------------------------------------------------------
# 敌人反应取自同一张表
# ---------------------------------------------------------------------------
func test_enemy_flinch_and_knock_follow_the_table() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var scrap := preload("res://scenes/enemies/ScrapperEnemy.tscn").instantiate() as ScrapperEnemy
	scrap.position = Vector2(320, -20)
	arena.add_child(scrap)
	var guard := preload("res://scenes/enemies/GearShieldEnemy.tscn").instantiate() as GearShieldEnemy
	guard.position = Vector2(520, -20)
	arena.add_child(guard)
	var boss := preload("res://scenes/enemies/NightmareBoss.tscn").instantiate() as Node2D
	boss.position = Vector2(720, -20)
	arena.add_child(boss)
	await flush(3)
	var box := Hitbox.new()
	box.blow = &"light"
	arena.add_child(box)
	GameEvents.hit.emit(box, scrap, 1)
	almost(scrap._hurt_lock, float(CombatRules.feel(&"flesh", &"light")["lock"]), 0.0001)
	scrap._hurt_lock = 0.0
	GameEvents.hit.emit(box, scrap, 2)
	almost(scrap._hurt_lock, float(CombatRules.feel(&"flesh", &"heavy")["lock"]), 0.0001, "heavier blow, longer flinch")
	GameEvents.hit.emit(box, guard, 1)
	almost(guard._hurt_lock, float(CombatRules.feel(&"armour", &"light")["lock"]), 0.0001, "armour shrugs it off faster")
	GameEvents.hit.emit(box, boss, 1)
	almost(boss._hurt_lock, 0.0, 0.0001, "a boss does not flinch from a light poke")
	# 击退：同一次击打，装甲 / 首领被推得更少。
	var kb := Hitbox.new()
	kb.knockback = Vector2(100.0, 0.0)
	arena.add_child(kb)
	scrap.velocity = Vector2.ZERO
	guard.velocity = Vector2.ZERO
	boss.velocity = Vector2.ZERO
	scrap.get_node("Hurtbox")._apply_knockback(kb)
	guard.get_node("Hurtbox")._apply_knockback(kb)
	boss.get_node("Hurtbox")._apply_knockback(kb)
	almost(scrap.velocity.x, 100.0, 0.01)
	almost(guard.velocity.x, 55.0, 0.01, "armour: 55% of the push")
	almost(boss.velocity.x, 15.0, 0.01, "boss: 15% of the push")


# ---------------------------------------------------------------------------
# 预算
# ---------------------------------------------------------------------------
func test_budget_table_matches_the_caps_in_code() -> void:
	eq(int(CombatRules.BUDGET[&"sparks"]), Fx.SPARK_CAP)
	eq(int(CombatRules.BUDGET[&"oneshots"]), Fx.ONESHOT_CAP)
	eq(int(CombatRules.BUDGET[&"motes"]), Fx.MOTE_CAP)
	eq(int(CombatRules.BUDGET[&"rings"]), Fx.RING_CAP)
	eq(int(CombatRules.BUDGET[&"markers"]), 8)
	ok(int(CombatRules.BUDGET[&"projectiles"]) <= 8)
	ok(int(CombatRules.BUDGET[&"afterimages"]) <= 8)
	ok(int(CombatRules.BUDGET[&"fire_trails"]) + int(CombatRules.BUDGET[&"blasts"]) <= CombatRules.PLAYER_HITBOX_CAP)
	ok(Fx.has_room(5, 6))
	ok(not Fx.has_room(6, 6))


func test_pool_rebuilds_when_its_host_changes() -> void:
	var host_a := Node2D.new()
	var host_b := Node2D.new()
	ok(not Fx.pool_needs_rebuild(true, true, host_a, host_a), "same host keeps the pool")
	ok(Fx.pool_needs_rebuild(true, true, host_a, host_b), "a different world gets a fresh pool")
	ok(Fx.pool_needs_rebuild(false, true, null, host_a), "a pool that left the tree is rebuilt")
	ok(Fx.pool_needs_rebuild(true, false, host_a, host_a), "an empty pool is rebuilt")
	host_a.free()
	host_b.free()


func test_enemy_projectiles_are_capped_and_parried_ones_survive() -> void:
	var arena := Node2D.new()
	add_child(arena)
	var shooter := Node2D.new()
	arena.add_child(shooter)
	var cap := int(CombatRules.BUDGET[&"projectiles"])
	var baseline := Projectile.live_count()
	var bolts: Array = []
	for i in cap + 6:
		var b := preload("res://scenes/combat/Projectile.tscn").instantiate() as Projectile
		arena.add_child(b)
		b.setup(Vector2(float(i) * 4.0, -20.0), Vector2.RIGHT, 1.0, &"enemy", shooter)
		bolts.append(b)
	await flush(2)
	ok(Projectile.live_count() - baseline <= cap, "no more than %d live bolts (%d)" % [cap, Projectile.live_count() - baseline])
	var survivors := 0
	for b in bolts:
		if is_instance_valid(b) and not b.is_queued_for_deletion():
			survivors += 1
	ok(survivors <= cap)
	# 弹反过的弹丸不被预算收走。
	var parried := preload("res://scenes/combat/Projectile.tscn").instantiate() as Projectile
	arena.add_child(parried)
	parried.setup(Vector2(0.0, -20.0), Vector2.RIGHT, 1.0, &"enemy", shooter)
	parried.deflect(shooter)
	for i in cap + 3:
		var b := preload("res://scenes/combat/Projectile.tscn").instantiate() as Projectile
		arena.add_child(b)
		b.setup(Vector2(float(i), -40.0), Vector2.RIGHT, 1.0, &"enemy", shooter)
	await flush(2)
	ok(is_instance_valid(parried) and not parried.is_queued_for_deletion(), "a parried bolt is never culled")


func test_markers_are_capped() -> void:
	var arena := Node2D.new()
	add_child(arena)
	var before := CombatMarker.live
	for i in 20:
		CombatMarker.spawn(arena, CombatMarker.Kind.RING, Vector2(float(i), 0.0), 5.0, Color.WHITE)
	var cap := int(CombatRules.BUDGET[&"markers"])
	ok(CombatMarker.live - before <= cap, "markers capped at %d (%d)" % [cap, CombatMarker.live - before])
	arena.queue_free()
	await flush(2)
	ok(CombatMarker.live <= before, "markers leave with their parent")


func test_player_temp_nodes_are_capped() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var p := await spawn_player(arena)
	p.set_physics_process(false)
	for i in 14:
		p._spawn_afterimages(1.0)
	ok(p.tracked_afterimages() <= int(CombatRules.BUDGET[&"afterimages"]), "afterimages capped (%d)" % p.tracked_afterimages())
	for i in 9:
		p._spawn_fire_trail()
		p._spawn_blast()
	ok(p.player_hitbox_count() <= CombatRules.PLAYER_HITBOX_CAP, "fire trail + blast hitboxes capped (%d)" % p.player_hitbox_count())
	var effects := GameContext.world_effects(p)
	var live := 0
	for child in effects.get_children():
		if child is Hitbox and not child.is_queued_for_deletion():
			live += 1
	ok(live <= CombatRules.PLAYER_HITBOX_CAP, "no hitbox leaks past the budget in the world (%d)" % live)
	await flush(2)


func test_temporary_hitboxes_expire_without_timers_on_freed_nodes() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var p := await spawn_player(arena)
	p.set_physics_process(false)
	p._spawn_fire_trail()
	var effects := GameContext.world_effects(p)
	var boxes: Array = []
	for child in effects.get_children():
		if child is Hitbox:
			boxes.append(child)
	ok(boxes.size() >= 1)
	for box in boxes:
		box.queue_free()  # 提前释放：绑在它身上的补间随之消失，不会再碰已释放节点
	await flush(4)
	p._spawn_blast()
	await flush(Player.BLAST_LIFE * 60.0 as int + 8)
	var left := 0
	for child in effects.get_children():
		if child is Hitbox and not child.is_queued_for_deletion():
			left += 1
	eq(left, 0, "short-lived hitboxes clear themselves")


func test_no_duplicate_global_connections_after_respawn_churn() -> void:
	var before_hit := GameEvents.hit.get_connections().size()
	var before_swing := GameEvents.swing_started.get_connections().size()
	var before_dash := GameEvents.dash_performed.get_connections().size()
	var before_parry := GameEvents.parried.get_connections().size()
	for round_i in 3:
		var arena := Node2D.new()
		add_child(arena)
		build_floor(arena)
		var p := await spawn_player(arena)
		var skeleton := preload("res://scenes/enemies/SkeletonEnemy.tscn").instantiate()
		skeleton.position = Vector2(500, 0)
		arena.add_child(skeleton)
		var boss := preload("res://scenes/enemies/ExecutionerBoss.tscn").instantiate()
		boss.position = Vector2(700, 0)
		arena.add_child(boss)
		var cam := GameCamera.new()
		arena.add_child(cam)
		await flush(2)
		arena.queue_free()
		await flush(3)
	eq(GameEvents.hit.get_connections().size(), before_hit, "hit listeners do not pile up")
	eq(GameEvents.swing_started.get_connections().size(), before_swing, "swing listeners do not pile up")
	eq(GameEvents.dash_performed.get_connections().size(), before_dash, "dash listeners do not pile up")
	eq(GameEvents.parried.get_connections().size(), before_parry, "parry listeners do not pile up")


func test_juice_sets_the_window_title_once_not_every_frame() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/autoload/juice.gd")
	var start := src.find("func _process(")
	var stop := src.find("\nfunc ", start + 1)
	var body := src.substr(start, stop - start)
	ok(not body.contains("window_set_title"), "_process no longer writes the window title every frame")
	ok(src.contains("window_set_title"), "the title is still set (in _ready)")


func test_knight_red_flash_matches_the_player_hurt_beat() -> void:
	eq(int(round(Player.HIT_FLASH_SECONDS * 1000.0)), int(CombatRules.PLAYER_HURT["flash_ms"]),
			"the knight's red flash lasts exactly the matrix's 90 ms")
