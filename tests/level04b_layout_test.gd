extends TestCase
## 锈墓・陆 — 圣殿地窖（level04b）关卡测试：
## 烛桥暗室、下层回收、固定压板、可选账本支路、四巢安全与唱诗堂侧台/烛火。

const LAYOUT := preload("res://scripts/levels/chapters/level04b_layout.gd")
const CHAPTER_ID := "level04b"
const BOSS_SCENE := "res://scenes/enemies/SilentChoir.tscn"


func setup() -> void:
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.pending_spawn = Vector2.INF
	Director.abort()
	Director.resume()


func teardown() -> void:
	Input.action_release("move_right")
	Input.action_release("jump")
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.pending_spawn = Vector2.INF
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	Director.abort()


func _build() -> Node2D:
	var host := Node2D.new()
	host.name = "Level04bLayoutHost"
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
	eq(layout.title(), "锈墓・陆 — 圣殿地窖")
	eq(layout.wake_line(), ChapterText.wake_of(CHAPTER_ID))
	eq(layout.theme(), "cathedral")
	ok(layout.indoors(), "圣殿地窖是室内关")
	ok(layout.east_limit() >= 3600, "chapter is at least 3600px wide")
	ok(ChapterLayout.FLOOR_Y - LAYOUT.CEILING_Y >= 420.0, "world height at least 420px")
	eq(layout.motes(), "candle", "地窖飘烛尘（唱诗班的烛雨）")
	var recipe := layout.weather_recipe()
	ok(recipe.has("allowed"), "indoor recipe declares allowed weather")
	ok(not (recipe["allowed"] as Array).has(WorldClock.Weather.RAIN), "地窖里不下雨")
	layout.free()


## 主路线：体检干净，出生 → 出口 / 四个巢 / 唱诗台压板 全程不借钩锁（allow_hook=false）。
func test_main_route_completes_without_optional_abilities() -> void:
	var host := _build()
	eq(LevelSanity.check(host), [] as Array[String], "LevelSanity clean")
	var spawn: Vector2 = LAYOUT.ENTRY_SPAWN
	var exit_node := host.get_node("Props/Exit") as LevelExit
	ok(exit_node != null, "exit door is planted")
	eq(exit_node.target_scene, GameContext.LEVELS["level05"])
	eq(exit_node.spawn, ChapterLayout.entry_spawn_of("level05"))
	ok(LevelSanity.is_reachable(host, spawn, LevelSanity.feet_of(exit_node), false),
			"exit reachable on foot")
	for nest_name in ["EmberNestAnte", "EmberNestBone", "EmberNestVault", "EmberNestChoir"]:
		var nest := host.get_node_or_null("Props/" + nest_name) as EmberNest
		ok(nest != null, "%s exists" % nest_name)
		if nest != null:
			ok(LevelSanity.is_reachable(host, spawn, LevelSanity.feet_of(nest), false),
					"%s reachable on foot" % nest_name)
	var plate := host.get_node_or_null("Props/ReliquaryGatePlate") as PressurePlate
	var door := host.get_node_or_null("Props/ReliquaryGateDoor") as ArenaDoor
	ok(plate != null and door != null, "reliquary gate pair is planted")
	if plate != null and door != null:
		ok(plate.activated.is_connected(door.open_door), "the choir plate opens the reliquary gate")
		ok(LevelSanity.is_reachable(host, spawn, LevelSanity.feet_of(plate), false),
				"the choir-loft plate is reachable on foot (mechanism beat)")
	host.free()
	await flush(1)


## 烛桥上行到固定唱诗台（208），台面压板开地窖闸门。
func test_candle_chain_reaches_the_fixed_loft_and_opens_the_gate() -> void:
	var host := _build()
	var spawn: Vector2 = LAYOUT.ENTRY_SPAWN
	var tops := LevelSanity.top_segments(host)
	for row in LAYOUT.CANDLE_STEPS:
		var bridge := host.get_node("Platforms/" + String(row[0])) as CandleBridge
		ok(not bridge.is_lit() and not bridge.is_solid(), "%s is initially a temporary silhouette" % bridge.name)
		ok(LevelSanity.is_reachable(host, spawn, bridge.position + Vector2(bridge.size.x * 0.5, 0), false),
				"%s is reached by basic jumps" % bridge.name)
		var support := LevelSanity.standing_on(tops, bridge.candle_pos)
		ok(support != null and support.kind == "", "the candle stands on a permanent landing")
	ok(not _fixed_reachable(host, spawn, LAYOUT.PLATE_FEET), "the first candle chain is needed for the loft")
	var plate := host.get_node("Props/ReliquaryGatePlate") as PressurePlate
	var door := host.get_node("Props/ReliquaryGateDoor") as ArenaDoor
	var lintel := host.get_node("Platforms/ReliquaryLintel") as SolidPlatform
	var head_gap := door.position.y - (lintel.position.y + lintel.size.y)
	ok(head_gap >= 0 and head_gap < 26, "the closed door leaves no knight-sized gap under the lintel")
	var player := await spawn_player(host, Vector2(1400, 300))
	Input.action_press("move_right")
	Input.action_press("jump")
	await flush(60)
	Input.action_release("jump")
	Input.action_release("move_right")
	ok(player.position.x < door.position.x, "the closed gate and lintel cannot be skipped by a basic jump")
	player.position = LevelSanity.feet_of(plate) - Vector2(0, 24)
	player.velocity = Vector2.ZERO
	ok(await wait_until(func() -> bool: return door.is_open), "landing on the fixed loft opens the street gate")
	player.position = Vector2(1400, 300)
	player.velocity = Vector2.ZERO
	await flush(24)
	Input.action_press("move_right")
	await flush(60)
	Input.action_release("move_right")
	ok(player.position.x > door.position.x + 16, "opening the plate gate permits actual walking under its lintel (x=%.1f)" % player.position.x)
	host.free()
	await flush(1)


## 钩锁支路：账本末页碑文 + 武器奖励位；主线（allow_hook=false）读不到，钩锁能到。
func test_hook_branch_carries_the_ledgers_last_page() -> void:
	var host := _build()
	var spawn: Vector2 = LAYOUT.ENTRY_SPAWN
	var stele := host.get_node_or_null("Props/SteleLedger") as LoreStele
	ok(stele != null, "choir gallery carries the ledger stele")
	if stele == null:
		host.free()
		return
	var entry := ChapterText.stele_of(CHAPTER_ID, "SteleLedger")
	eq(String(stele.lore_title), String(entry.get("title", "")), "ledger stele text from ChapterText")
	eq(String(stele.lore_text), String(entry.get("text", "")))
	var stele_feet := LevelSanity.feet_of(stele)
	ok(not LevelSanity.is_reachable(host, spawn, stele_feet, false),
			"main route cannot reach the choir gallery")
	ok(LevelSanity.is_reachable(host, spawn, stele_feet, true),
			"hookshot reaches the choir gallery")
	var reward := host.get_node_or_null("Pickups/RewardLedger") as EquipmentPickup
	ok(reward != null, "branch has a weapon reward slot")
	if reward != null:
		eq(reward.reward_kind, LAYOUT.REWARD_KIND, "reward kind is wired")
		eq(reward.reward_ref, LAYOUT.REWARD_REF, "reward reference is wired")
		ok(EquipmentCatalog.has_id(StringName(reward.reward_ref)), "reward item exists in the catalog")
		var tops := LevelSanity.top_segments(host)
		ok(LevelSanity.standing_on(tops, LevelSanity.feet_of(reward)) != null,
				"reward rests on the gallery (not floating)")
	# 主线的两块碑（唱诗 / 伊尔）都在地面上，无钩锁也能读。
	for stele_name in ["SteleChoir", "SteleYir"]:
		var node := host.get_node_or_null("Props/" + stele_name) as LoreStele
		ok(node != null, "%s is planted" % stele_name)
		if node != null:
			var chapter_entry := ChapterText.stele_of(CHAPTER_ID, stele_name)
			eq(String(node.lore_title), String(chapter_entry.get("title", "")))
			ok(LevelSanity.is_reachable(host, spawn, LevelSanity.feet_of(node), false),
					"%s readable on foot" % stele_name)
	host.free()
	await flush(1)


## 存档点：四个巢都在敌人仇恨/唤醒圈外，Boss 前那个贴着竞技场入口。
func test_checkpoints_are_safe_and_reach_the_boss_gate() -> void:
	var host := _build()
	var ante := host.get_node("Props/EmberNestAnte") as EmberNest
	var bone := host.get_node("Props/EmberNestBone") as EmberNest
	var choir := host.get_node("Props/EmberNestChoir") as EmberNest
	ok(ante.global_position.x < bone.global_position.x, "checkpoints are ordered")
	ok(bone.global_position.x < choir.global_position.x, "checkpoints are ordered")
	ok(absf(LAYOUT.ARENA_LEFT - choir.global_position.x) <= 80.0,
			"boss checkpoint within 80px of the arena (contract §4.1)")
	var skeleton := host.get_node("Enemies/Skeleton2") as SkeletonEnemy
	ok(absf(bone.global_position.x - skeleton.global_position.x) > skeleton.wake_range,
			"the bone-room skeleton wakes away from the bone nest")
	var ghost := host.get_node("Enemies/Ghost2") as GhostEnemy
	ok(absf(bone.global_position.x - ghost.global_position.x) > ghost.wake_range,
			"the bone-room ghost sleeps away from the bone nest")
	var shield := host.get_node("Enemies/GearShield1") as GearShieldEnemy
	ok(absf(choir.global_position.x - shield.global_position.x) - shield.patrol_range
			> shield.aggro_range, "the gear-shield guard cannot reach the boss checkpoint")
	var spitter := host.get_node("Enemies/Spitter1") as SpitterEnemy
	ok(absf(ante.global_position.x - spitter.global_position.x) > spitter.aggro_range,
			"the front-hall spitter is out of range of the start nest")
	host.free()
	await flush(1)


## Boss 位：连续回收地面、可达侧龛、烛桥熄灭有固定地面可接。
func test_boss_arena_has_reachable_side_shelters_and_safe_candle_falls() -> void:
	ok(LAYOUT.ARENA_RIGHT - LAYOUT.ARENA_LEFT >= 600.0, "arena is at least 600px wide")
	ok(LAYOUT.BOSS_POS.x > LAYOUT.ARENA_LEFT and LAYOUT.BOSS_POS.x < LAYOUT.ARENA_RIGHT,
			"boss spawns inside the arena")
	var host := _build()
	for side in ["ArenaSideWest", "ArenaSideEast"]:
		var ledge := host.get_node("Platforms/" + side) as SolidPlatform
		var feet := ledge.position + Vector2(ledge.size.x * 0.5, 0)
		ok(LevelSanity.is_reachable(host, LAYOUT.BOSS_POS, feet, false), "arena side shelter is one jump away")
		for hz in LevelSanity.hazards(host):
			if hz is CyclicHazard:
				ok(not (hz as CyclicHazard).hit_rect().grow(12).has_point(feet - Vector2(0, 16)),
						"side shelter is outside every flame sweep")
	for x in [LAYOUT.ARENA_LEFT + 8, LAYOUT.BOSS_POS.x, LAYOUT.ARENA_RIGHT - 8]:
		var support := LevelSanity.standing_on(LevelSanity.top_segments(host), Vector2(x, 320))
		ok(support != null and support.kind == "", "the arena has a continuous recovery floor")
	host.free()
	await flush(1)
	if not ResourceLoader.exists(BOSS_SCENE):
		ok(true, "SilentChoir scene not delivered yet — boss slot reserved, chapter stays finishable")
	else:
		var boss_host := _build()
		var probe := LAYOUT.new() as ChapterLayout
		var arena := probe.boss_arena(boss_host, "SilentChoir") as BossArena
		ok(arena != null, "boss arena is attached once the boss scene lands")
		if arena != null:
			almost(arena.arena_left, LAYOUT.ARENA_LEFT, 0.01)
			almost(arena.arena_right, LAYOUT.ARENA_RIGHT, 0.01)
		probe.free()
		boss_host.free()
		await flush(1)


func _fixed_reachable(host: Node2D, start: Vector2, goal: Vector2) -> bool:
	var fixed: Array[LevelSanity.TopSeg] = []
	for segment in LevelSanity.top_segments(host):
		if segment.kind == "":
			fixed.append(segment)
	var first := LevelSanity._segment_below(fixed, start)
	if first == null:
		return false
	var reached: Array[LevelSanity.TopSeg] = [first]
	var queue: Array[LevelSanity.TopSeg] = [first]
	while not queue.is_empty():
		var current: LevelSanity.TopSeg = queue.pop_front()
		for next in fixed:
			if not reached.has(next) and LevelSanity._can_hop(current, next):
				reached.append(next)
				queue.append(next)
	for segment in reached:
		if goal.x >= segment.x0 and goal.x <= segment.x1 and absf(goal.y - segment.y) < 1.0:
			return true
	return false


func test_candle_extinguishing_drops_to_a_real_recoverable_floor() -> void:
	var host := _build()
	for enemy in host.get_node("Enemies").get_children():
		enemy.set_physics_process(false)
	var player := await spawn_player(host, LAYOUT.ENTRY_SPAWN)
	for row in LAYOUT.CANDLE_STEPS:
		var bridge := host.get_node("Platforms/" + String(row[0])) as CandleBridge
		bridge.set_physics_process(false)
		bridge.ignite()
		await flush(2)
		player.position = bridge.position + Vector2(bridge.size.x * 0.5, -24)
		player.velocity = Vector2.ZERO
		await flush(20)
		ok(player.is_on_floor(), "%s supports the knight when lit" % bridge.name)
		bridge.extinguish()
		await flush(36)
		ok(player.is_on_floor() and player.position.y > bridge.position.y + 24,
				"%s extinguishes into a safe lower floor" % bridge.name)
		var root_candle := bridge.candle_pos
		if String(bridge.name).begins_with("CandleAnte"):
			root_candle = Vector2(384, 320)
		elif String(bridge.name) == "CandleBoneEast":
			root_candle = Vector2(1536, 288)
		ok(_fixed_reachable(host, player.position, root_candle), "the lower route returns to a lighting source")
	host.free()
	await flush(1)


func _quiet_nests(names: Array) -> void:
	for name_ in names:
		var host := _build()
		var calls := {"attacks": 0}
		for enemy in host.get_node("Enemies").get_children():
			(enemy as EnemyBase).telegraph_started.connect(func(_kind, _duration) -> void: calls.attacks += 1)
		var nest := host.get_node("Props/" + String(name_)) as EmberNest
		var player := await spawn_player(host, LevelSanity.feet_of(nest) - Vector2(0, 20))
		var hp := player.health.current
		await flush(360)
		eq(player.health.current, hp, "%s stays safe for six seconds" % name_)
		eq(calls.attacks, 0, "%s leaves encounters asleep" % name_)
		host.free()
		await flush(1)


func test_west_checkpoints_remain_quiet_for_six_seconds() -> void:
	await _quiet_nests(["EmberNestAnte", "EmberNestBone"])


func test_east_checkpoints_remain_quiet_for_six_seconds() -> void:
	await _quiet_nests(["EmberNestVault", "EmberNestChoir"])


func test_first_candle_landings_allow_six_seconds_to_read_the_mechanism() -> void:
	for feet in [Vector2(384, 320), Vector2(600, 304)]:
		var host := _build()
		var calls := {"attacks": 0}
		for enemy in host.get_node("Enemies").get_children():
			(enemy as EnemyBase).telegraph_started.connect(func(_kind, _duration) -> void: calls.attacks += 1)
		var player := await spawn_player(host, feet - Vector2(0, 20))
		var hp := player.health.current
		await flush(360)
		eq(player.health.current, hp, "the fixed candle landing permits safe reading and relighting")
		eq(calls.attacks, 0, "the first candle is taught before the first encounter wakes")
		ok(player.is_on_floor(), "the candle reading landing is permanent")
		var bridge_name := "CandleTeach" if feet.x < 500 else "CandleAnteB"
		ok((host.get_node("Platforms/" + bridge_name) as CandleBridge).is_lit(), "standing by the candle really lights its bridge")
		host.free()
		await flush(1)


func test_first_flame_has_safe_fixed_waiting_landings_on_both_sides() -> void:
	for feet in [Vector2(1272, 320), Vector2(1384, 320)]:
		var host := _build()
		var calls := {"attacks": 0, "flames": 0}
		for enemy in host.get_node("Enemies").get_children():
			(enemy as EnemyBase).telegraph_started.connect(func(_kind, _duration) -> void: calls.attacks += 1)
		var flame := host.get_node("Props/FlameTeach") as CyclicHazard
		flame.fired.connect(func() -> void: calls.flames += 1)
		ok(not flame.hit_rect().grow(12).has_point(feet - Vector2(0, 16)), "the waiting landing clears the full flame sweep")
		var player := await spawn_player(host, feet - Vector2(0, 20))
		var hp := player.health.current
		await flush(360)
		ok(calls.flames > 0, "the actual flame completes a cycle during the wait")
		eq(player.health.current, hp, "the fixed landing stays safe while the flame cycles")
		eq(calls.attacks, 0, "the flame is taught without a live enemy attack")
		ok(player.is_on_floor(), "flame reading does not require a moving or temporary platform")
		host.free()
		await flush(1)


func test_boss_waits_for_entry_and_starts_inside_the_arena() -> void:
	var host := _build()
	var choir := host.get_node("Enemies/SilentChoir") as SilentChoirBoss
	var gate := host.get_node("Props/ChoirWakeGate")
	var player := await spawn_player(host, Vector2(LAYOUT.NEST_CHOIR_X, 300))
	ok(not choir.is_announced() and not choir.is_physics_processing(), "checkpoint does not run the boss AI")
	player.position = Vector2(LAYOUT.ARENA_LEFT + 32, 320)
	await flush(4)
	ok(gate.triggered and choir.is_announced(), "crossing the arena boundary announces the choir")
	ok(choir.is_physics_processing(), "the original boss AI takes over after entry")
	Director.abort()
	host.free()
	await flush(1)


func test_boss_clear_unlocks_the_original_exit_and_arena() -> void:
	var host := _build()
	var choir := host.get_node("Enemies/SilentChoir") as SilentChoirBoss
	var arena := host.get_node("Arenas/SilentChoirArena") as BossArena
	var exit_node := host.get_node("Props/Exit") as LevelExit
	ok(exit_node.is_locked(), "the original choir flag still gates the workshop exit")
	await spawn_player(host, Vector2(LAYOUT.ARENA_LEFT + 32, 300))
	ok(choir.is_announced() and arena.is_active(), "the chapter entry gate activates the original arena")
	choir.health.take_damage(99, null)
	await flush(2)
	ok(SaveData.has_flag("choir_dead"), "the original boss death flag is preserved")
	ok(arena.is_cleared() and not exit_node.is_locked(), "the boss clear releases both arena and exit")
	host.free()
	await flush(1)


func test_checkpoint_spacing_and_one_way_return_gallery() -> void:
	var host := _build()
	var names := ["EmberNestAnte", "EmberNestBone", "EmberNestVault", "EmberNestChoir"]
	for i in range(1, names.size()):
		var left := host.get_node("Props/" + names[i - 1]) as Node2D
		var right := host.get_node("Props/" + names[i]) as Node2D
		ok(right.position.x - left.position.x <= 1000, "checkpoint spacing caps the death run")
	var low := LevelSanity.standing_on(LevelSanity.top_segments(host), Vector2(LAYOUT.NEST_VAULT_X, 320))
	var high := LevelSanity.standing_on(LevelSanity.top_segments(host), Vector2(2240, 224))
	ok(LevelSanity._can_hop(high, low) and not LevelSanity._can_hop(low, high), "return gallery has a one-way drop")
	ok(_fixed_reachable(host, Vector2(2944, 256), Vector2(LAYOUT.NEST_VAULT_X, 320)), "the westbound return needs no temporary steps")
	eq((host.get_node("Enemies/Skeleton2") as EnemyBase).variant, &"exploder_skeleton")
	eq((host.get_node("Enemies/GearShield1") as EnemyBase).variant, &"heavy_guard")
	host.free()
	await flush(1)


## 装饰：只用 cathedral 白名单键、接地 1x、墙面浮雕在背景层；烛光层次（壁炬 + 烛尘）在。
func test_decor_is_themed_layered_and_grounded() -> void:
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
		ok(PropCatalog.allowed("cathedral", key), "'%s' is allowed by the cathedral theme" % key)
		eq(spr.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "%s is nearest-filtered" % key)
		if spr.is_in_group("grounded"):
			ok(spr.scale == Vector2.ONE, "%s is drawn at 1x" % key)
			ok(LevelSanity.standing_on(tops, spr.get_meta("feet")) != null,
					"%s stands on a platform" % key)
		elif spr.has_meta("hang_top"):
			ok(String(spr.get_meta("foot_anchor", "")) == "top_center", "%s hangs" % key)
	ok(planted >= 14, "the chapter is dressed (%d catalog props)" % planted)
	for wanted in ["door_arch", "skull_column", "altar", "window", "balustrade", "column", "slab"]:
		ok(keys.has(String(wanted)), "narrative anchor '%s' is planted" % wanted)
	# 视觉 QA Phase A：中景家具带（1700/2050/3100）必须有暖光补，不能只是一排黑剪影。
	var warm := 0
	for child in decor.get_children():
		var light := child as WorldLight
		if light != null and String(light.follow) == "authored" and light.lit:
			warm += 1
	ok(warm >= 6, "warm candle fills light the mid-ground furniture band (%d)" % warm)
	# 背景板照不到世界 2D 灯：中景暖雾层必须存在（只盖背景、在角色/道具下面）。
	var veil := host.get_node_or_null("Props/WarmVeil") as ColorRect
	ok(veil != null, "the warm mid-ground veil exists (cathedral backdrop cannot be lit)")
	if veil != null:
		ok(veil.z_index <= -4, "the veil sits under props and actors (z=%d)" % veil.z_index)
		ok(veil.color.a > 0.08 and veil.color.a < 0.24, "the veil is a haze, not a wash (a=%.2f)" % veil.color.a)
	# Boss 房临时地标：两端的石柱/石栏 + 合唱席残石板（纯装饰、无碰撞）。
	var boss_hall_landmarks := 0
	for child in decor.get_children():
		var spr := child as Sprite2D
		if spr == null or not spr.has_meta("prop_key") or not spr.has_meta("feet"):
			continue
		var feet: Vector2 = spr.get_meta("feet")
		if feet.x >= LAYOUT.ARENA_LEFT - 40.0 and feet.x <= LAYOUT.ARENA_RIGHT + 40.0:
			boss_hall_landmarks += 1
	ok(boss_hall_landmarks >= 4, "the boss hall reads as a choir (landmarks: %d)" % boss_hall_landmarks)
	# 墙板浮雕（尖窗/石像鬼/骷髅柱/立柱/祭坛）画在背景层：不会变成竖在路心的板子。
	for child in decor.get_children():
		var spr := child as Sprite2D
		if spr == null or not spr.has_meta("prop_key"):
			continue
		var key := String(spr.get_meta("prop_key"))
		if key in ["window", "gargoyle", "altar", "skull_column", "column"]:
			eq(spr.z_index, -3, "%s is a background wall relief" % key)
	var torches := 0
	for child in decor.get_children():
		if child is TorchLight:
			torches += 1
	ok(torches >= 8, "indoor chapter lights its beats (%d wall torches)" % torches)
	host.free()
	await flush(1)


## 场景接线：Level04b_Crypt.tscn 真的加载这张 layout（不是旧 stub）。
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
		ok(level.get_node_or_null("Platforms/ChoirLoft") != null, "choir loft is built")
		ok(level.get_node_or_null("Props/SteleLedger") != null, "ledger branch stele is planted")
	level.free()
	await flush(1)
