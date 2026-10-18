extends TestCase
## 锈墓・叁 — 运渣水渠（level02b）关卡测试：
## 章节文本只走 ChapterText、主线（无钩锁）从入口到出口无软锁、毒水渠掉得下去也爬得回、
## 运渣桥吊台链可达、钩锁支路带碑文 + 奖励位、三张存档点安全、Boss 位留出 600px 平地。

const LAYOUT := preload("res://scripts/levels/chapters/level02b_layout.gd")
const CHAPTER_ID := "level02b"
const BOSS_SCENE := "res://scenes/enemies/CapstanWarden.tscn"


func setup() -> void:
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.pending_spawn = Vector2.INF
	Director.abort()
	Director.resume()


func teardown() -> void:
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.pending_spawn = Vector2.INF
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	Director.abort()


func _build() -> Node2D:
	var host := Node2D.new()
	host.name = "Level02bLayoutHost"
	host.scene_file_path = GameContext.LEVELS[CHAPTER_ID]
	host.add_to_group("game_world")
	add_child(host)
	var layout := LAYOUT.new()
	add_child(layout)
	layout.build(host)
	return host


## 章节卡/醒来句/出口字幕/碑文全部来自 ChapterText（docs/integration-contracts.md §1.2）。
func test_metadata_and_text_come_from_chapter_text() -> void:
	ok(ChapterText.has(CHAPTER_ID), "chapter is registered in ChapterText")
	var layout: ChapterLayout = LAYOUT.new()
	eq(layout.level_id(), CHAPTER_ID)
	eq(layout.title(), ChapterText.title_of(CHAPTER_ID))
	eq(layout.title(), "锈墓・叁 — 运渣水渠")
	eq(layout.wake_line(), ChapterText.wake_of(CHAPTER_ID))
	eq(layout.theme(), "undercroft")
	ok(layout.indoors(), "运渣水渠是室内关")
	ok(layout.east_limit() >= 3600, "chapter is at least 3600px wide")
	ok(ChapterLayout.FLOOR_Y - LAYOUT.CEILING_Y >= 360.0, "world height at least 360px")
	ok(layout.motes() != "", "chapter has its own motes flavour")
	layout.free()


## 主路线：体检干净，出生 → 出口 / 三个巢 / 压板 全程不借钩锁（allow_hook=false）。
func test_main_route_completes_without_optional_abilities() -> void:
	var host := _build()
	eq(LevelSanity.check(host), [] as Array[String], "LevelSanity clean")
	var spawn: Vector2 = LAYOUT.ENTRY_SPAWN
	var exit_node := host.get_node("Props/Exit") as LevelExit
	ok(exit_node != null, "exit door is planted")
	eq(exit_node.target_scene, GameContext.LEVELS["level03"])
	eq(exit_node.spawn, ChapterLayout.entry_spawn_of("level03"))
	ok(LevelSanity.is_reachable(host, spawn, LevelSanity.feet_of(exit_node), false),
			"exit reachable on foot")
	for nest_name in ["EmberNestSluice", "EmberNestBridge", "EmberNestPump"]:
		var nest := host.get_node_or_null("Props/" + nest_name) as EmberNest
		ok(nest != null, "%s exists" % nest_name)
		if nest != null:
			ok(LevelSanity.is_reachable(host, spawn, LevelSanity.feet_of(nest), false),
					"%s reachable on foot" % nest_name)
	var plate := host.get_node_or_null("Props/SluiceGatePlate") as PressurePlate
	var door := host.get_node_or_null("Props/SluiceGateDoor") as ArenaDoor
	ok(plate != null and door != null, "sluice gate pair is planted")
	if plate != null and door != null:
		ok(plate.activated.is_connected(door.open_door), "the capstan plate opens the sluice gate")
		ok(LevelSanity.is_reachable(host, spawn, LevelSanity.feet_of(plate), false),
				"the capstan plate is reachable on foot (teaching beat)")
	host.free()
	await flush(1)


## 毒水渠：坑底只比地面低一跳（≤32px），掉下去能沿坑岸爬回；渠上有过渠踩石。
func test_slag_canals_can_be_fallen_into_and_climbed_out() -> void:
	var host := _build()
	var tops := LevelSanity.top_segments(host)
	var spawn: Vector2 = LAYOUT.ENTRY_SPAWN
	for spec in [["SluiceCanal", 560.0, 720.0], ["SlagCanal", 1120.0, 2064.0]]:
		var canal := String(spec[0])
		var bed := host.get_node_or_null("Platforms/%sBed" % canal) as SolidPlatform
		var pool := host.get_node_or_null("Props/%sPool" % canal) as ToxinPool
		ok(bed != null, "%s has a pit bed" % canal)
		ok(pool != null, "%s has toxic water" % canal)
		if bed != null:
			almost(bed.position.y - ChapterLayout.FLOOR_Y, 32.0, 0.01,
					"%s bed is one jump under the bank" % canal)
			ok(bed.position.y - ChapterLayout.FLOOR_Y <= LevelSanity.JUMP_RISE_MAX,
					"%s is climbable out of the sludge" % canal)
		if pool != null:
			var rect := pool.surface_rect()
			almost(rect.position.x, float(spec[1]), 0.01)
			almost(rect.end.x, float(spec[2]), 0.01)
	# 水闸广场的两块过渠踩石是主路线的一部分。
	for stone in [["CanalStoneW", 600.0], ["CanalStoneE", 680.0]]:
		var stone_name := String(stone[0])
		var node := host.get_node_or_null("Platforms/" + stone_name) as SolidPlatform
		ok(node != null, "%s exists" % stone_name)
		if node != null:
			var feet := Vector2(node.position.x + node.size.x * 0.5, node.position.y)
			ok(LevelSanity.standing_on(tops, feet) != null, "%s is a standable top" % stone_name)
			ok(LevelSanity.is_reachable(host, spawn, feet, false),
					"%s reachable on foot" % stone_name)
	host.free()
	await flush(1)


## 运渣桥：两块桥石 + 两座横渡吊台，链上每一站（含吊台两端）都能无钩锁到达。
func test_haul_bridge_and_lifts_are_crossing_on_foot() -> void:
	var host := _build()
	var spawn: Vector2 = LAYOUT.ENTRY_SPAWN
	var west := host.get_node_or_null("Platforms/LiftHaulWest") as MovingPlatform
	var east := host.get_node_or_null("Platforms/LiftHaulEast") as MovingPlatform
	ok(west != null, "west haul lift exists")
	ok(east != null, "east haul lift exists")
	if west != null:
		eq(west.travel, Vector2(264.0, 0.0), "west lift crosses the big canal")
	if east != null:
		eq(east.travel, Vector2(240.0, 0.0), "east lift finishes the crossing")
	# 每个落脚点：桥石中心 / 吊台两端，都按「主路线无钩锁」检查。
	var stations: Array = [
		["HaulStoneW", Vector2(1144, 288)],
		["HaulStoneMid", Vector2(1232, 272)],
		["WestLiftStart", Vector2(1352, 272)],
		["WestLiftEnd", Vector2(1616, 272)],
		["HaulStoneE", Vector2(1672, 272)],
		["EastLiftStart", Vector2(1792, 272)],
		["EastLiftEnd", Vector2(2032, 272)],
		["FloorWellLanding", Vector2(2100, 320)],
	]
	for station in stations:
		ok(LevelSanity.is_reachable(host, spawn, station[1], false),
				"%s reachable on foot" % String(station[0]))
	# 抽水井的竖吊台：可选检修走道，起点在 24px 处（不是主路线的必经）。
	var pump := host.get_node_or_null("Platforms/PumpLift") as MovingPlatform
	ok(pump != null, "pump lift exists")
	if pump != null:
		eq(pump.travel, Vector2(0.0, -144.0), "pump lift rises to the catwalk")
		ok(LevelSanity.is_reachable(host, spawn, Vector2(2524, 296), false),
				"pump lift dock is reachable on foot")
	host.free()
	await flush(1)


## 钩锁支路：主线（allow_hook=false）读不到；钩锁（allow_hook=true）能到，
## 台上有碑文「闸」和装备奖励位。
func test_hook_branch_is_optional_and_rewarded() -> void:
	var host := _build()
	var spawn: Vector2 = LAYOUT.ENTRY_SPAWN
	var stele := host.get_node_or_null("Props/SteleCapstan") as LoreStele
	ok(stele != null, "capstan gallery carries a stele")
	if stele == null:
		host.free()
		return
	var entry := ChapterText.stele_of(CHAPTER_ID, "SteleCapstan")
	eq(String(stele.lore_title), String(entry.get("title", "")), "branch stele text from ChapterText")
	eq(String(stele.lore_text), String(entry.get("text", "")))
	var stele_feet := LevelSanity.feet_of(stele)
	ok(not LevelSanity.is_reachable(host, spawn, stele_feet, false),
			"main route cannot reach the capstan gallery")
	ok(LevelSanity.is_reachable(host, spawn, stele_feet, true),
			"hookshot reaches the capstan gallery")
	var reward := host.get_node_or_null("Pickups/RewardCapstan") as EquipmentPickup
	ok(reward != null, "branch has an equipment reward slot")
	if reward != null:
		eq(reward.reward_kind, LAYOUT.REWARD_KIND, "reward kind is wired")
		eq(reward.reward_ref, LAYOUT.REWARD_REF, "reward reference is wired")
		ok(EquipmentCatalog.has_id(StringName(reward.reward_ref)), "reward item exists in the catalog")
		var tops := LevelSanity.top_segments(host)
		ok(LevelSanity.standing_on(tops, LevelSanity.feet_of(reward)) != null,
				"reward rests on the gallery (not floating)")
	ok(LevelSanity.is_reachable(host, spawn, LevelSanity.feet_of(host.get_node("Props/SteleSluice")), false),
			"main-route stele is readable on foot")
	host.free()
	await flush(1)


## 存档点：三个巢都在敌人仇恨/唤醒圈外，Boss 前那个贴着竞技场入口。
func test_checkpoints_are_safe_and_reach_the_boss_gate() -> void:
	var host := _build()
	var sluice := host.get_node("Props/EmberNestSluice") as EmberNest
	var bridge := host.get_node("Props/EmberNestBridge") as EmberNest
	var pump := host.get_node("Props/EmberNestPump") as EmberNest
	ok(sluice.global_position.x < bridge.global_position.x, "checkpoints are ordered")
	ok(bridge.global_position.x < pump.global_position.x, "checkpoints are ordered")
	ok(absf(LAYOUT.ARENA_LEFT - pump.global_position.x) <= 80.0,
			"boss checkpoint within 80px of the arena (contract §4.1)")
	var scrapper := host.get_node("Enemies/Scrapper1") as ScrapperEnemy
	ok(absf(sluice.global_position.x - scrapper.global_position.x) - scrapper.patrol_range
			> scrapper.aggro_range, "the plaza scrapper cannot charge the start nest")
	var spitter := host.get_node("Enemies/Spitter1") as SpitterEnemy
	ok(absf(pump.global_position.x - spitter.global_position.x) > spitter.aggro_range,
			"the pump-well spitter is out of range of the boss checkpoint")
	var ghost := host.get_node("Enemies/Ghost1") as GhostEnemy
	ok(absf(pump.global_position.x - ghost.global_position.x) > ghost.wake_range,
			"the canal ghost sleeps away from the boss checkpoint")
	host.free()
	await flush(1)


## Boss 位：600px 连续平地、场地里没有坑/台阶，Boss 在场地中间；场景缺失时框架跳过。
func test_boss_slot_reserves_a_flat_600px_arena() -> void:
	ok(LAYOUT.ARENA_RIGHT - LAYOUT.ARENA_LEFT >= 600.0, "arena is at least 600px wide")
	ok(LAYOUT.BOSS_POS.x > LAYOUT.ARENA_LEFT and LAYOUT.BOSS_POS.x < LAYOUT.ARENA_RIGHT,
			"boss spawns inside the arena")
	var host := _build()
	for seg in LevelSanity.top_segments(host):
		if seg.x1 <= LAYOUT.ARENA_LEFT or seg.x0 >= LAYOUT.ARENA_RIGHT:
			continue
		almost(seg.y, ChapterLayout.FLOOR_Y, 0.01,
				"arena floor is flat (no ledges inside: %s)" % seg.owner_name)
	var props := host.get_node("Props")
	for child in props.get_children():
		if child is ToxinPool:
			var rect := (child as ToxinPool).surface_rect()
			ok(rect.end.x <= LAYOUT.ARENA_LEFT or rect.position.x >= LAYOUT.ARENA_RIGHT,
					"no toxin pit inside the boss arena")
	host.free()
	await flush(1)
	if not ResourceLoader.exists(BOSS_SCENE):
		ok(true, "CapstanWarden scene not delivered yet — boss slot reserved, chapter stays finishable")
	else:
		var boss_host := _build()
		var probe := LAYOUT.new() as ChapterLayout
		var arena := probe.boss_arena(boss_host, "CapstanWarden") as BossArena
		ok(arena != null, "boss arena is attached once the boss scene lands")
		if arena != null:
			almost(arena.arena_left, LAYOUT.ARENA_LEFT, 0.01)
			almost(arena.arena_right, LAYOUT.ARENA_RIGHT, 0.01)
		probe.free()
		boss_host.free()
		await flush(1)


## 视觉 QA Phase A 回归锁：944px 渣渠不能是荧光绿亮带；半空横渡台不能是亮草檐贴片。
##  · 两个毒池都挂 5 段暗绿 sludge_ramp、tint 已压暗（alpha < 1 也让浮沫退下去）；
##  · 浮台/桥石用 brick_float 断砖 skin（有侧面/断口，不是 moss_float 的亮草檐）；
##  · 吊台保留可站立判定，吊索从顶板垂下来（chain_top_y 在顶板底边）。
func test_canal_surface_and_floating_ledges_read_as_stone() -> void:
	var host := _build()
	var props := host.get_node("Props")
	for child in props.get_children():
		if not (child is ToxinPool):
			continue
		var pool := child as ToxinPool
		eq(pool.sludge_ramp.size(), 5, "%s has a 5-stop darkened sludge ramp" % pool.name)
		ok(pool.tint.a < 1.0, "%s scum/sludge tint is held back (alpha %.2f)" % [pool.name, pool.tint.a])
		ok(pool.tint.v < 1.1, "%s is not multiplied into a neon band" % pool.name)
	var tops := LevelSanity.top_segments(host)
	for step_spec in LAYOUT.STEPS:
		var node := host.get_node_or_null("Platforms/" + String(step_spec[0])) as SolidPlatform
		ok(node != null, "%s exists" % String(step_spec[0]))
		if node == null:
			continue
		eq(node.skin, LAYOUT.LEDGE_SKIN, "%s uses the broken-stone ledge skin" % node.name)
		eq(node.tone, LAYOUT.LEDGE_TONE, "%s is toned to mossy stone" % node.name)
		var feet := Vector2(node.position.x + node.size.x * 0.5, node.position.y)
		ok(LevelSanity.standing_on(tops, feet) != null, "%s is still standable" % node.name)
	for lift_spec in LAYOUT.LIFTS:
		var deck := host.get_node_or_null("Platforms/" + String(lift_spec[0])) as MovingPlatform
		ok(deck != null, "%s exists" % String(lift_spec[0]))
		if deck == null:
			continue
		ok(deck.chain_top_y < 0.0, "%s has visible chains to the ceiling" % deck.name)
		# 默认 moss_float 板被关掉，换成 brick_float 断砖碴（每 16px 一块）。
		var visible_planks := 0
		for child in deck.get_children():
			if child is Sprite2D and (child as Sprite2D).visible:
				visible_planks += 1
		ok(visible_planks >= int(deck.width / 16.0), "%s is re-skinned with broken-stone planks" % deck.name)
	# 渠面直边被压边件打断：渠口残阶、半沉断管/落石/断石栏、桥石上的断管落石。
	var keys: Array[String] = []
	for child in (host.get_node("Decor") as Node2D).get_children():
		if child is Sprite2D and child.has_meta("prop_key"):
			keys.append(String(child.get_meta("prop_key")))
	ok(keys.count("pipe_valve") >= 3, "broken pipes press the canal edges")
	ok(keys.count("rubble") >= 4, "rubble presses the canal edges")
	ok(keys.has("stair"), "a ruined stair breaks the east canal mouth")
	host.free()
	await flush(1)


## 装饰：只用 undercroft 白名单键、接地 1x、有叙事锚点；室内顶板与灯都在。
func test_decor_is_themed_grounded_and_narrative() -> void:
	var host := _build()
	var decor := host.get_node_or_null("Decor") as Node2D
	ok(decor != null, "Decor layer exists")
	if decor == null:
		host.free()
		return
	var tops := LevelSanity.top_segments(host)
	var planted := 0
	var keys: Array[String] = []
	for child in decor.get_children():
		var spr := child as Sprite2D
		if spr == null or not spr.has_meta("prop_key"):
			continue
		var key := String(spr.get_meta("prop_key"))
		planted += 1
		keys.append(key)
		ok(PropCatalog.allowed("undercroft", key), "'%s' is allowed by the undercroft theme" % key)
		eq(spr.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "%s is nearest-filtered" % key)
		if spr.is_in_group("grounded"):
			ok(spr.scale == Vector2.ONE, "%s is drawn at 1x" % key)
			ok(LevelSanity.standing_on(tops, spr.get_meta("feet")) != null,
					"%s stands on a platform" % key)
		elif spr.has_meta("hang_top"):
			ok(String(spr.get_meta("foot_anchor", "")) == "top_center", "%s hangs" % key)
	ok(planted >= 12, "the chapter is dressed (%d catalog props)" % planted)
	for wanted in ["warning_plate", "arch", "life_remains", "pipe_valve", "balustrade"]:
		ok(keys.has(String(wanted)), "narrative anchor '%s' is planted" % wanted)
	var torches := 0
	for child in decor.get_children():
		if child is TorchLight:
			torches += 1
	ok(torches >= 5, "indoor chapter lights its beats (%d wall torches)" % torches)
	ok(LAYOUT.CEILING_Y < 0.0, "indoor chapter is enclosed")
	host.free()
	await flush(1)


## 场景接线：Level02b_SlagConduit.tscn 真的加载这张 layout（不是旧 stub）。
func test_scene_boots_the_real_layout() -> void:
	var packed := load(GameContext.LEVELS[CHAPTER_ID]) as PackedScene
	ok(packed != null, "level scene loads")
	if packed == null:
		return
	var level := packed.instantiate()
	add_child(level)
	await flush(2)
	Director.abort()
	var layout := level.get_node_or_null("Layout") as ChapterLayout
	ok(layout != null, "scene built a ChapterLayout")
	if layout != null:
		eq(layout.level_id(), CHAPTER_ID)
		eq(layout.east_limit(), LAYOUT.EAST_LIMIT, "scene runs the real chapter, not the stub")
		ok(level.get_node_or_null("Platforms/SluiceCanalBed") != null, "canal terrain is built")
		ok(level.get_node_or_null("Props/SteleSluice") != null, "main-route stele is planted")
	level.free()
	await flush(1)


## 渲染夹具（opt-in，只在非 headless 且设了 RUSTGRAVE_RENDER_LEVEL 时执行）。
## 为什么放在测试跑者里：本分支新增的章间间幕（scripts/levels/chapter_transition.gd）
## 在 tools/peek_live.gd 的 Director.abort() 之后不会收幕（abort 不发 script_finished），
## 于是 PeekLive 的每张章节图都被 82% 黑幕 + 布景纹样盖住、量出来只有 ~18% 亮度。
## 测试跑者里 Director.is_test_runner() 为真 → 间幕 inert，正好能拍到干净的实机画面。
## 用法（人工取证，常规 headless 下自动 skip、不写文件）：
##   $env:RUSTGRAVE_RENDER_LEVEL='level02b'; $env:RUSTGRAVE_RENDER_OUT=$env:TEMP+'\rg-render'
##   godot --path <repo> --windowed --position -12000,-12000 --resolution 1280x720 \
##     --rendering-method gl_compatibility res://tests/run_tests.tscn -- --case-filter=level02b_layout
## level04b 用同一个夹具：把 RUSTGRAVE_RENDER_LEVEL 换成 level04b 再跑一次。
func test_render_key_beats_fixture() -> void:
	var render_level := OS.get_environment("RUSTGRAVE_RENDER_LEVEL")
	if render_level == "" or DisplayServer.get_name() == "headless":
		ok(true, "render fixture is opt-in (RUSTGRAVE_RENDER_LEVEL, windowed run)")
		return
	var spots_by_level := {
		"level02b": [["01_plaza", 640.0], ["02_haul_bridge", 1500.0], ["03_pump_well", 2950.0]],
		"level04b": [["01_antechamber", 400.0], ["02_bone_room", 1700.0], ["03_choir_hall", 3050.0]],
	}
	if not spots_by_level.has(render_level):
		ok(false, "no render spots authored for %s" % render_level)
		return
	var out_dir := OS.get_environment("RUSTGRAVE_RENDER_OUT")
	if out_dir == "":
		out_dir = OS.get_environment("TEMP")
	DirAccess.make_dir_recursive_absolute(out_dir)
	SaveData.save_path = out_dir + "/render_save.cfg"
	SaveData.delete_save()
	GameContext.pending_world_path = GameContext.LEVELS[render_level]
	var presentation := (load("res://scenes/ui/GamePresentation.tscn") as PackedScene).instantiate()
	add_child(presentation)
	for i in 8:
		await get_tree().process_frame
	Director.abort()
	Director.set_letterbox(false, true)
	var player := get_tree().get_first_node_in_group("player") as Player
	var camera := get_tree().get_first_node_in_group("game_camera") as GameCamera
	ok(player != null and camera != null, "presentation spawned the knight and camera")
	if player == null or camera == null:
		presentation.queue_free()
		GameContext.pending_world_path = GameContext.LEVELS["level01"]
		return
	player.set_physics_process(false)
	player.cutscene_locked = true
	camera.set_physics_process(false)
	# 固定成 1280×720 的可见内容（DisplayFit 已经跑过，这里不会再被覆盖）。
	var root_window := get_window()
	root_window.size = Vector2i(1280, 720)
	root_window.position = Vector2i(-12000, -12000)
	for i in 3:
		await get_tree().process_frame
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
		enemy.set_process(false)
	WorldClock.set_time(0.35)
	WorldClock.set_weather(WorldClock.Weather.HAZE, true)
	WorldClock.wind_heading = 1.0
	WorldClock._heading_target = 1.0
	WorldClock._snap_wind_speed()
	for nest in get_tree().get_nodes_in_group("ember_nests"):
		nest.apply_persistent_state({"lit": true})
	for spot in spots_by_level[render_level]:
		var spot_name := String(spot[0])
		var x := float(spot[1])
		camera.global_position = Vector2(x, 220.0)
		camera.force_update_scroll()
		player.global_position = Vector2(x - 120.0, 320.0)
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var path := "%s/%s_%s.png" % [out_dir, render_level, spot_name]
		var err := image.save_png(path)
		ok(err == OK, "saved %s" % path)
		print("[RENDER] ", path, " err=", err, " size=", image.get_size())
	presentation.queue_free()
	GameContext.pending_world_path = GameContext.LEVELS["level01"]
	await flush(2)
