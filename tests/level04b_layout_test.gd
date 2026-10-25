extends TestCase
## 锈墓・陆 — 圣殿地窖（level04b）v3 关卡测试：
## 章节文本只走 ChapterText、主线（无钩锁）从入口与烛桥坠落底层均可无软锁通关、
## 烛桥（CandleBridge）串联多高度暗室与回环捷径、唱诗壳机关与链吊台可达、
## 钩锁支路带账本末页碑文 + 武器奖励位、四张存档点间距 < 1000px 且安全、
## Boss 竞技场含高低壁龛与中央烛火吊桥。

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


## 主路线：体检干净，出生 → 出口 / 四个巢 / 唱诗台压板 / 烛桥底层坠落点 全程不借钩锁（allow_hook=false）。
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
	# 烛桥熄灭坠落到非致命底层后，必须能无钩锁爬回主线并抵达出口。
	for recovery_pt in [Vector2(512.0, 352.0), Vector2(1424.0, 352.0)]:
		ok(LevelSanity.is_reachable(host, recovery_pt, LevelSanity.feet_of(exit_node), false),
				"falling onto sunken crypt floor %s still reaches exit on foot" % str(recovery_pt))
	host.free()
	await flush(1)


## 烛桥（CandleBridge）机关：串联前厅、藏骨堂、捷径回环与唱诗 Boss 场。
func test_candle_bridges_chain_the_crypt_and_arena() -> void:
	var host := _build()
	for bridge_name in [
		"CandleBridgeAnte",
		"CandleBridgeBone",
		"CandleBridgeShortcut",
		"CandleBridgeCatacomb",
		"CandleBridgeArena",
	]:
		var cb := host.get_node_or_null("Platforms/" + bridge_name) as CandleBridge
		ok(cb != null, "%s is planted as a CandleBridge" % bridge_name)
		if cb != null:
			ok(cb.is_in_group("hazards"), "%s is registered in hazards group" % bridge_name)
			eq(String(cb.get_meta("hazard_kind", "")), "candle", "%s carries candle hazard_kind" % bridge_name)
			ok(not cb.is_lit(), "%s starts unlit in the dark crypt" % bridge_name)
			ok(cb.get_node_or_null("Candle") != null, "%s has its associated candle trigger" % bridge_name)
	var first_landing := host.get_node_or_null("Platforms/AnteBridgeWest") as SolidPlatform
	ok(first_landing != null and first_landing.size.x >= 48.0,
			"first CandleBridge encounter has a >=48px safe observation landing")
	host.free()
	await flush(1)


## 唱诗壳机关与单向捷径：链吊台把骑士送上唱诗台（224），台面压板开地窖闸门，西向阳台借烛桥回巢。
func test_choir_lift_and_loft_are_reachable_on_foot() -> void:
	var host := _build()
	var spawn: Vector2 = LAYOUT.ENTRY_SPAWN
	var lift := host.get_node_or_null("Platforms/ChoirLift") as MovingPlatform
	ok(lift != null, "choir lift exists")
	if lift != null:
		eq(lift.travel, Vector2(0.0, -72.0), "the lift rises from the floor step to the loft")
	for station in [
		["LiftStart", Vector2(1616, 296)],
		["LiftEnd", Vector2(1616, 224)],
		["Loft", Vector2(1744, 224)],
		["Plate", LAYOUT.PLATE_FEET + Vector2(0, 0)],
		["ShortcutBalcony", Vector2(1432, 224)],
		["ShortcutBridge", Vector2(1312, 240)],
	]:
		ok(LevelSanity.is_reachable(host, spawn, station[1], false),
				"%s reachable on foot" % String(station[0]))
	var bone_nest := host.get_node("Props/EmberNestBone") as EmberNest
	ok(LevelSanity.is_reachable(host, Vector2(1432, 224), LevelSanity.feet_of(bone_nest), false),
			"shortcut balcony drops back to EmberNestBone on foot")
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


## 存档点与精英变体：四个巢间距 <= 1000px、都在敌人仇恨/唤醒圈外，Boss 前存档点贴着竞技场入口。
func test_checkpoints_are_safe_and_reach_the_boss_gate() -> void:
	var host := _build()
	var ante := host.get_node("Props/EmberNestAnte") as EmberNest
	var bone := host.get_node("Props/EmberNestBone") as EmberNest
	var vault := host.get_node("Props/EmberNestVault") as EmberNest
	var choir := host.get_node("Props/EmberNestChoir") as EmberNest
	ok(ante.global_position.x < bone.global_position.x, "checkpoints are ordered (ante < bone)")
	ok(bone.global_position.x < vault.global_position.x, "checkpoints are ordered (bone < vault)")
	ok(vault.global_position.x < choir.global_position.x, "checkpoints are ordered (vault < choir)")
	ok(bone.global_position.x - ante.global_position.x <= 1000.0, "ante->bone spacing <= 1000px")
	ok(vault.global_position.x - bone.global_position.x <= 1000.0, "bone->vault spacing <= 1000px")
	ok(choir.global_position.x - vault.global_position.x <= 1000.0, "vault->choir spacing <= 1000px")
	ok(absf(LAYOUT.ARENA_LEFT - choir.global_position.x) <= 80.0,
			"boss checkpoint within 80px of the arena (contract §4.1)")
	var skeleton := host.get_node("Enemies/Skeleton2") as SkeletonEnemy
	eq(skeleton.variant_id, &"exploder_skeleton", "bone-room skeleton uses exploder_skeleton variant")
	ok(absf(bone.global_position.x - skeleton.global_position.x) > skeleton.wake_range,
			"the bone-room skeleton wakes away from the bone nest")
	var ghost := host.get_node("Enemies/Ghost2") as GhostEnemy
	ok(absf(vault.global_position.x - ghost.global_position.x) > ghost.wake_range,
			"the reliquary ghost sleeps away from the vault nest")
	var shield := host.get_node("Enemies/GearShield1") as GearShieldEnemy
	eq(shield.variant_id, &"heavy_guard", "catacomb guard uses heavy_guard variant")
	ok(absf(choir.global_position.x - shield.global_position.x) - shield.patrol_range
			> shield.aggro_range, "the heavy guard cannot reach the boss checkpoint")
	var spitter := host.get_node("Enemies/Spitter1") as SpitterEnemy
	ok(absf(ante.global_position.x - spitter.global_position.x) > spitter.aggro_range,
			"the front-hall spitter is out of range of the start nest")
	var scatter := host.get_node("Enemies/Spitter2") as SpitterEnemy
	eq(scatter.variant_id, &"scatter_spitter", "choir loft spitter uses scatter_spitter variant")
	host.free()
	await flush(1)


## Boss 位：600px 连续底层平地 + 两侧高低避难台 + 中央烛桥 + 可破坏掩体骨瓮。
func test_boss_slot_reserves_a_flat_600px_arena() -> void:
	ok(LAYOUT.ARENA_RIGHT - LAYOUT.ARENA_LEFT >= 600.0, "arena is at least 600px wide")
	ok(LAYOUT.BOSS_POS.x > LAYOUT.ARENA_LEFT and LAYOUT.BOSS_POS.x < LAYOUT.ARENA_RIGHT,
			"boss spawns inside the arena")
	var host := _build()
	var floor_choir := host.get_node_or_null("Platforms/FloorChoir") as SolidPlatform
	ok(floor_choir != null, "FloorChoir spans the boss arena")
	for node_name in ["ArenaStepWest", "ArenaStepEast", "ArenaAlcoveWest", "ArenaAlcoveEast", "CandleBridgeArena"]:
		ok(host.get_node_or_null("Platforms/" + node_name) != null,
				"boss arena terrain '%s' is planted" % node_name)
	for urn_name in ["ArenaCoverUrnWest", "ArenaCoverUrnEast"]:
		ok(host.get_node_or_null("Props/" + urn_name) is DestructibleProp,
				"boss arena cover prop '%s' is planted" % urn_name)
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
	# 视觉 QA Phase A：中景家具带必须有暖光补，不能只是一排黑剪影。
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
	# Boss 房地标：两端的石柱/石栏 + 合唱席残石板（纯装饰、无碰撞）。
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
