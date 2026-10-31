extends TestCase
## 竞技场对局状态、记录 v2、暂停、放弃、路由白名单、剧情守卫。

const ArenaCatalog := preload("res://scripts/data/arena_catalog.gd")
const MobaRunScript := preload("res://scripts/moba/moba_run.gd")
const PATH := "user://test_arena_records.cfg"


func setup() -> void:
	_quiet_reset()
	ArenaRun.use_file(PATH)
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func teardown() -> void:
	_quiet_reset()
	ArenaRun.use_default_file()
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_catalog_rules_and_formatting() -> void:
	ok(ResourceLoader.exists(ArenaCatalog.SCENE), "竞技场场景存在")
	ok(ResourceLoader.exists(ArenaCatalog.TITLE_SCENE))
	eq(ArenaCatalog.DURATION, 720.0)
	eq(ArenaCatalog.MATCH_SECONDS, 720.0)
	eq(ArenaCatalog.WAVE_INTERVAL, 30.0)
	eq(ArenaCatalog.format_time(720.0), "12:00")
	eq(ArenaCatalog.format_time(4.2), "00:05")
	eq(ArenaCatalog.format_time(0.0), "00:00")
	var text := ArenaCatalog.strip_text(120, 4, 87.0)
	ok(text.contains("得分 120") and text.contains("击杀 4") and text.contains("01:27"))
	ok(ArenaCatalog.result_summary({"outcome": "win", "win": true, "kills": 3, "elapsed": 12.0}).begins_with("胜"))
	ok(ArenaCatalog.result_summary({"outcome": "loss", "kills": 1, "elapsed": 4.0}).begins_with("负"))
	ok(ArenaCatalog.result_summary({"outcome": "draw", "draw": true, "kills": 0, "elapsed": 720.0}).begins_with("平"))
	var early := ArenaCatalog.wave_kinds(1)
	var third := ArenaCatalog.wave_kinds(3)
	ok(not early.has("siege") and early.size() == 3)
	ok(third.has("siege") and third.size() == 4)
	ok(not ArenaCatalog.wave_kinds(2).has("siege"))
	ok(ArenaCatalog.wave_kinds(6).has("siege"))
	eq(ArenaCatalog.timeout_outcome(2, 1, 0, 9), "win")
	eq(ArenaCatalog.timeout_outcome(0, 0, 1, 4), "loss")
	eq(ArenaCatalog.timeout_outcome(1, 1, 3, 3), "draw")
	ok(ArenaCatalog.exposed(0, true, true, true))
	ok(not ArenaCatalog.exposed(1, true, true, true))
	ok(ArenaCatalog.exposed(1, false, true, true))
	ok(not ArenaCatalog.exposed(2, false, true, true))
	ok(ArenaCatalog.exposed(2, false, false, true))
	ok(not ArenaCatalog.exposed(2, false, false, false))
	ok(ArenaCatalog.respawn_seconds(6, "veteran") > ArenaCatalog.respawn_seconds(1, "veteran"))
	ok(ArenaCatalog.respawn_seconds(1, "apprentice") < ArenaCatalog.respawn_seconds(1, "veteran"))
	ok(ArenaCatalog.respawn_seconds(1, "forge") > ArenaCatalog.respawn_seconds(1, "veteran"))
	ok(ArenaCatalog.hero_hp(6) > ArenaCatalog.hero_hp(1))
	ok(ArenaCatalog.hero_damage(6) > ArenaCatalog.hero_damage(1))


func test_records_migrate_v1_and_keep_title_keys() -> void:
	var fresh := ArenaRun.read_records()
	eq(int(fresh["best_score"]), 0)
	eq(int(fresh["best_kills"]), 0)
	eq(int(fresh["runs"]), 0)
	eq(int(fresh["wins"]), 0)
	eq(int(fresh["losses"]), 0)
	eq(int(fresh["draws"]), 0)
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 1)
	cfg.set_value("meta", "best_score", 80)
	cfg.set_value("meta", "best_kills", 4)
	cfg.set_value("meta", "runs", 2)
	eq(cfg.save(PATH), OK)
	var migrated := ArenaRun.read_records()
	eq(int(migrated["best_score"]), 80, "v1 最高分保留")
	eq(int(migrated["best_kills"]), 4)
	eq(int(migrated["runs"]), 2)
	eq(int(migrated["wins"]), 0)
	eq(int(migrated["version"]), 2)
	ArenaRun.auto_begin = true
	ArenaRun.activate_for_test()
	ArenaRun.finish_match("win", "test")
	var saved := ArenaRun.read_records()
	eq(int(saved["runs"]), 3)
	eq(int(saved["wins"]), 1)
	eq(int(saved["best_kills"]), 4, "没有更高击杀时不覆盖")
	ok(int(saved["best_score"]) >= 80)
	ok(bool(ArenaRun.match_result()["new_record"]))


func test_phase_lobby_countdown_and_strip() -> void:
	ArenaRun.activate_for_test()
	eq(ArenaRun.phase(), ArenaCatalog.PHASE_LOBBY)
	ok(ArenaRun.active())
	ok(not ArenaRun.running())
	eq(ArenaRun.strip_text(), "按 Enter 开战")
	ok(ArenaRun.set_difficulty("forge"))
	ok(not ArenaRun.set_difficulty("nope"))
	eq(ArenaRun.difficulty_id(), "forge")
	ArenaRun.begin_match()
	eq(ArenaRun.phase(), ArenaCatalog.PHASE_COUNTDOWN)
	ok(not ArenaRun.set_difficulty("apprentice"), "开战倒计时里不能改难度")
	_tick(3.1)
	eq(ArenaRun.phase(), ArenaCatalog.PHASE_PLAYING)
	ok(ArenaRun.running())
	ok(ArenaRun.time_left() > 700.0)


func test_pause_and_suspend_do_not_advance_clock() -> void:
	ArenaRun.auto_begin = true
	ArenaRun.activate_for_test()
	var before := ArenaRun.time_left()
	Director.suspend()
	_tick(2.0)
	Director.resume()
	eq(ArenaRun.time_left(), before, "Director 挂起不计时")
	get_tree().paused = true
	_tick(2.0)
	get_tree().paused = false
	eq(ArenaRun.time_left(), before, "暂停不计时")
	_tick(1.0)
	ok(ArenaRun.time_left() < before)


func test_abandon_does_not_write_a_ghost_win() -> void:
	ArenaRun.auto_begin = true
	ArenaRun.activate_for_test()
	ArenaRun.apply_structure_damage("enemy", 0, 30, "player")
	ArenaRun.abandon()
	ok(not ArenaRun.active())
	eq(ArenaRun.phase(), ArenaCatalog.PHASE_IDLE)
	eq(ArenaRun.last_result().size(), 0)
	eq(int(ArenaRun.read_records()["runs"]), 0)
	_tick(1000.0)
	eq(int(ArenaRun.read_records()["runs"]), 0, "放弃之后走到点也不结算")
	ok(not ArenaRun.blocks_campaign_save())


func test_inactive_arena_does_not_block_campaign_save() -> void:
	ok(not ArenaRun.active())
	ok(not ArenaRun.blocks_campaign_save())
	eq(ArenaRun.score(), 0)
	eq(ArenaRun.time_left(), ArenaCatalog.DURATION)


func test_route_scene_whitelist_keeps_world_meaning() -> void:
	var saved := GameContext.pending_world_path
	ok(not GameContext.is_world_scene(ArenaCatalog.SCENE))
	ok(GameContext.is_mode_scene(ArenaCatalog.SCENE))
	eq(GameContext.route_scene(ArenaCatalog.SCENE), GameContext.PRESENTATION_PATH)
	eq(GameContext.pending_world_path, ArenaCatalog.SCENE)
	eq(GameContext.route_scene("res://scenes/ui/TitleScreen.tscn"), "res://scenes/ui/TitleScreen.tscn")
	eq(GameContext.route_scene(GameContext.WORLD_PATH), GameContext.PRESENTATION_PATH)
	ok(GameContext.is_world_scene(GameContext.WORLD_PATH))
	GameContext.pending_world_path = saved


func test_director_does_not_play_story_in_arena() -> void:
	ArenaRun.activate_for_test()
	Director.play([{"kind": "wait", "seconds": 2.0}])
	ok(not Director.playing, "竞技场会话里 play() 直接丢掉")
	ArenaRun.abandon()
	Director.play([{"kind": "wait", "seconds": 2.0}])
	ok(Director.playing, "离开竞技场后剧情还能播")
	Director.abort()
	ok(not Director.playing)


func test_title_menu_still_has_arena_entry() -> void:
	var packed := load("res://scenes/ui/TitleScreen.tscn") as PackedScene
	var title := packed.instantiate() as Node
	add_child(title)
	await get_tree().process_frame
	await get_tree().process_frame
	var menu := title.get_node_or_null("Menu") as MenuList
	ok(menu != null, "标题菜单存在")
	if menu != null:
		ok(menu.item_ids().has(&"arena"), "菜单里有竞技场")
		var idx := menu.item_ids().find(&"arena")
		ok(idx >= 0)
		ok(menu.items()[idx].kind == MenuItem.Kind.SECONDARY)
	title.queue_free()
	await get_tree().process_frame


func test_title_start_uses_3d_without_starting_the_old_lobby() -> void:
	var saved := GameContext.pending_world_path
	ok(ArenaRun.start())
	ok(MobaRunScript.active())
	ok(not ArenaRun.active())
	eq(ArenaRun.phase(), ArenaCatalog.PHASE_IDLE)
	eq(GameContext.pending_world_path, saved)
	MobaRunScript.abandon()
	ok(not MobaRunScript.active())
	GameContext.pending_world_path = saved
	Director._fading = false


## 不开场景。一侧已经赢下兵线：2 名 1 级英雄带着每波小兵打当前建筑，
## 塔优先点小兵，所以英雄在小兵死光前白打。伤害只算在最前面那座上，打不完的留给下一波。
func test_won_lane_resolves_inside_twelve_minutes() -> void:
	eq(ArenaCatalog.timeout_outcome(2, 1, 0, 20), "win", "超时先看拆塔")
	eq(ArenaCatalog.timeout_outcome(1, 1, 3, 4), "loss", "塔数相同再看击杀")
	eq(ArenaCatalog.timeout_outcome(0, 0, 5, 5), "draw")
	var pace := _won_lane_times()
	var outer_t := float(pace["outer"])
	var crystal_t := float(pace["crystal"])
	ok(outer_t > 40.0, "外塔 %.1f 秒，不应开场 40 秒内倒下" % outer_t)
	ok(crystal_t > 45.0, "水晶 %.1f 秒，不应 30 秒速推" % crystal_t)
	ok(crystal_t < ArenaCatalog.MATCH_SECONDS, "水晶 %.1f 秒，赢下兵线应在 12 分钟内结束" % crystal_t)
	ok(crystal_t > outer_t)
	var melee_hp := int(ArenaCatalog.unit_stat("melee")["hp"])
	var app_hp := ArenaCatalog.scaled_max_hp(melee_hp, "minion", "apprentice")
	var vet_hp := ArenaCatalog.scaled_max_hp(melee_hp, "minion", "veteran")
	var forge_hp := ArenaCatalog.scaled_max_hp(melee_hp, "minion", "forge")
	ok(app_hp < vet_hp and vet_hp < forge_hp, "三档小兵生命应拉开")
	var app_cd := ArenaCatalog.cooldown_scale("hero", "apprentice")
	var vet_cd := ArenaCatalog.cooldown_scale("hero", "veteran")
	var forge_cd := ArenaCatalog.cooldown_scale("hero", "forge")
	ok(app_cd > vet_cd and vet_cd > forge_cd, "三档英雄出手间隔应拉开")
	var app_tower := ArenaCatalog.scaled_damage(int(ArenaCatalog.unit_stat("tower")["dmg"]), "tower", "apprentice")
	var vet_tower := ArenaCatalog.scaled_damage(int(ArenaCatalog.unit_stat("tower")["dmg"]), "tower", "veteran")
	var forge_tower := ArenaCatalog.scaled_damage(int(ArenaCatalog.unit_stat("tower")["dmg"]), "tower", "forge")
	ok(app_tower < vet_tower and vet_tower < forge_tower, "三档塔伤害应拉开")


func _won_lane_times() -> Dictionary:
	var diff := "veteran"
	var melee: Dictionary = ArenaCatalog.unit_stat("melee")
	var ranged: Dictionary = ArenaCatalog.unit_stat("ranged")
	var siege: Dictionary = ArenaCatalog.unit_stat("siege")
	var hero: Dictionary = ArenaCatalog.unit_stat("hero")
	var tower: Dictionary = ArenaCatalog.unit_stat("tower")
	var crystal: Dictionary = ArenaCatalog.unit_stat("crystal")
	var hero_cd := float(hero["cd"]) * ArenaCatalog.cooldown_scale("hero", diff)
	var hero_hit := ArenaCatalog.scaled_damage(ArenaCatalog.hero_damage(1), "hero", diff)
	var escort := float(hero_hit) / hero_cd * 2.0
	var tower_hit := maxi(1, ArenaCatalog.scaled_damage(int(tower["dmg"]), "tower", diff) - 1)
	var tower_dps := float(tower_hit) / float(tower["cd"])
	var crystal_hit := ArenaCatalog.scaled_damage(int(crystal["dmg"]), "crystal", diff)
	var crystal_dps := float(crystal_hit) / float(crystal["cd"])
	var pools: Array = [float(int(tower["hp"])), float(int(tower["hp"])), float(int(crystal["hp"]))]
	var guns: Array = [tower_dps, tower_dps, crystal_dps]
	var travel := (ArenaCatalog.RED_OUTER.x - ArenaCatalog.BLUE_MINION_X) / float(melee["speed"])
	var outer_t := -1.0
	var crystal_t := -1.0
	var idx := 0
	var wave_i := 1
	while idx < 3 and wave_i < 40:
		var arrive := ArenaCatalog.FIRST_WAVE_DELAY + travel + float(wave_i - 1) * ArenaCatalog.WAVE_INTERVAL
		var bodies := _pace_bodies(wave_i, melee, ranged, siege, diff)
		var chip := _pace_chip(bodies, float(pools[idx]), float(guns[idx]), escort)
		pools[idx] = float(chip["left"])
		if float(pools[idx]) <= 0.0:
			var fell := arrive + float(chip["dt"])
			if idx == 0:
				outer_t = fell
			if idx == 2:
				crystal_t = fell
			idx += 1
		wave_i += 1
	return {"outer": outer_t, "crystal": crystal_t}


func _pace_bodies(wave_i: int, melee: Dictionary, ranged: Dictionary, siege: Dictionary, diff: String) -> Array:
	var out: Array = []
	var kinds: PackedStringArray = ArenaCatalog.wave_kinds(wave_i)
	for kind_v in kinds:
		var kind := String(kind_v)
		var stat: Dictionary = melee
		if kind == "ranged":
			stat = ranged
		elif kind == "siege":
			stat = siege
		var hp := ArenaCatalog.scaled_max_hp(int(stat["hp"]), "minion", diff)
		var dmg := ArenaCatalog.scaled_damage(int(stat["dmg"]), "minion", diff)
		var grown := ArenaCatalog.wave_power(wave_i)
		hp = maxi(1, int(round(float(hp) * grown)))
		dmg = maxi(1, int(round(float(dmg) * grown)))
		if kind == "siege":
			dmg += int(round(float(stat["siege"]) * grown))
		var cd := float(stat["cd"]) * ArenaCatalog.cooldown_scale("minion", diff)
		out.append({"hp": hp, "dps": float(dmg) / maxf(0.05, cd)})
	return out


func _pace_chip(bodies: Array, struct_hp: float, tower_dps: float, escort: float) -> Dictionary:
	var alive: Array = bodies.duplicate()
	var left := struct_hp
	var used := 0.0
	if tower_dps <= 0.001:
		return {"left": left, "dt": 99999.0}
	while left > 0.0 and not alive.is_empty():
		var raw_tgt: Variant = alive[0]
		var tgt: Dictionary = raw_tgt
		var mdps := escort
		for row_v in alive:
			var row: Dictionary = row_v
			mdps += float(row["dps"])
		if mdps <= 0.001:
			return {"left": left, "dt": 99999.0}
		var kill_dt := float(tgt["hp"]) / tower_dps
		var kill_dmg := mdps * kill_dt
		if kill_dmg >= left:
			used += left / mdps
			left = 0.0
			break
		used += kill_dt
		left -= kill_dmg
		alive.pop_front()
	return {"left": left, "dt": used}


func _tick(seconds: float) -> void:
	var host := get_tree().root.get_node("ArenaRun")
	host._process(seconds)


func _quiet_reset() -> void:
	MobaRunScript.abandon()
	ArenaRun.auto_begin = false
	ArenaRun.shop_ignore_range = false
	if Director.is_suspended():
		Director.resume()
	if Director.playing:
		Director.abort()
	if get_tree() != null and get_tree().paused:
		get_tree().paused = false
	ArenaRun.abandon()
	ArenaRun.set_difficulty(ArenaCatalog.DEFAULT_DIFFICULTY)
