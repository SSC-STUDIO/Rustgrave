extends TestCase
## Dry recovery, a one-way return, three nests, hook vigil and phase-linked pulses.
const LAYOUT := preload("res://scripts/levels/chapters/level10_layout.gd")
const BOSS_TITLE := "锈 墓 梦 魇 · 无 主 之 马"


func setup() -> void:
	SaveData.delete_save()
	SaveData.pending_spawn = Vector2.INF
	Director.abort()
	Director._set_lock(false)
	_release_input()


func teardown() -> void:
	_release_input()
	Director.abort()
	Director._set_lock(false)
	SaveData.delete_save()
	SaveData.pending_spawn = Vector2.INF
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)


func _release_input() -> void:
	for action in ["jump", "move_left", "move_right", "dash"]:
		Input.action_release(action)


func _build() -> Node2D:
	var host := Node2D.new()
	host.name = "Level10_ForgeCore"
	host.scene_file_path = GameContext.LEGACY_LEVELS["level10"]
	host.add_to_group("game_world")
	add_child(host)
	var layout := LAYOUT.new() as ChapterLayout
	add_child(layout)
	layout.build(host)
	return host


func _rects(host: Node2D) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for node in host.get_node("Platforms").get_children():
		if node is SolidPlatform:
			out.append(Rect2(node.position, node.size))
	return out


func _standing_on(rects: Array[Rect2], feet: Vector2, slack: float = 0.5) -> bool:
	for rect in rects:
		if feet.x >= rect.position.x and feet.x <= rect.end.x and absf(feet.y - rect.position.y) <= slack:
			return true
	return false


func _pulses(host: Node2D) -> Array:
	return [host.get_node("Props/CorePulse1"), host.get_node("Props/CorePulse2"), host.get_node("Props/CorePulse3")]


func _isolate(host: Node2D) -> void:
	for enemy in host.get_node("Enemies").get_children():
		enemy.set_physics_process(false)
		if enemy.name != "Nightmare":
			enemy.queue_free()
	for prop in host.get_node("Props").get_children():
		if prop is CyclicHazard:
			prop.set_physics_process(false)
	Director.abort()


func test_metadata_and_original_inscriptions() -> void:
	var layout := LAYOUT.new() as ChapterLayout
	add_child(layout)
	eq(layout.level_id(), "level10")
	eq(layout.title(), ChapterText.title_of("level10"))
	eq(layout.theme(), "forge_core")
	eq(layout.east_limit(), 4160)
	eq(layout.camera_top(), -128)
	eq(layout.entry_spawn(), LAYOUT.ENTRY_SPAWN)
	ok(layout.indoors())
	eq(GameContext.next_level_id("level10"), "")
	var host := _build()
	for id in ["SteleNightmare", "SteleCompact", "SteleVigil"]:
		var stele := host.get_node("Props/" + id) as LoreStele
		var text := ChapterText.stele_of("level10", id)
		eq(stele.lore_title, text.title)
		eq(stele.lore_text, text.text)
		ok(_standing_on(_rects(host), LevelSanity.feet_of(stele)))
	ok(host.get_node("IndoorZone") is AtmosphereZone)
	ok(host.get_node("ParallaxBackdrop") is CanvasLayer)


func test_main_route_has_dry_recovery_and_only_single_hops() -> void:
	var host := _build()
	for row in LAYOUT.FLOORS:
		var platform := host.get_node("Platforms/" + String(row[0])) as SolidPlatform
		eq(platform.position, Vector2(float(row[1]), float(row[3])))
		almost(platform.size.x, float(row[2]) - float(row[1]))
	for index in range(1, LAYOUT.FLOORS.size()):
		var before: Array = LAYOUT.FLOORS[index - 1]
		var after: Array = LAYOUT.FLOORS[index]
		almost(float(before[2]), float(after[1]), 0.01, "continuous dry recovery floor")
		ok(float(before[3]) - float(after[3]) <= 32.0, "no recovery climb exceeds one jump")
	for pos in [Vector2(800, 352), Vector2(960, 320), Vector2(1024, 288), Vector2(1760, 352), Vector2(1936, 320)]:
		ok(_standing_on(_rects(host), pos), "fixed recovery foothold %s" % pos)
	ok(host.get_node_or_null("Props/SlagPool") == null, "timed jets replace permanent liquid damage")
	ok(LevelSanity.is_reachable(host, LAYOUT.ENTRY_SPAWN, Vector2(LAYOUT.EXIT_X, 320), false))
	var gate := host.get_node("Props/ArenaGate") as RustyGate
	ok(gate != null and not gate._melted, "original heat-forge gate remains closed")


func test_first_jets_have_safe_waiting_and_recovery_space() -> void:
	var host := _build()
	var first := host.get_node("Props/SlagTeachWest") as CyclicHazard
	var second := host.get_node("Props/SlagTeachEast") as CyclicHazard
	for hazard in [first, second]:
		ok(hazard.telegraph_time >= 0.8 and hazard.rest_time + hazard.telegraph_time >= 1.2)
		almost(hazard.hit_rect().size.x, 24.0)
		almost(hazard.hit_rect().size.y, 56.0)
	ok(first.hit_rect().position.x - 416.0 >= 48.0, "fixed landing before first nozzle")
	ok(752.0 - second.hit_rect().end.x >= 48.0, "fixed landing after last nozzle")
	var player := await spawn_player(host, Vector2(400, 268))
	await flush(360)
	eq(player.health.current, player.health.max_hp, "first warning can be read for six seconds")
	player.position = Vector2(720, 328)
	player.velocity = Vector2.ZERO
	await flush(360)
	eq(player.health.current, player.health.max_hp, "post-nozzle recovery is safe for six seconds")


func test_three_grounded_nests_and_boss_gate_distance() -> void:
	var host := _build()
	var positions: Array[Vector2] = []
	for id in ["EmberNestGate", "EmberNestCooling", "EmberNestArena"]:
		var nest := host.get_node("Props/" + id) as EmberNest
		var feet := nest.position + Vector2(6, 14)
		ok(_standing_on(_rects(host), feet))
		positions.append(feet)
	almost(positions[1].x - positions[0].x, 992.0)
	almost(positions[2].x - positions[1].x, 1008.0)
	ok(LAYOUT.ARENA_X0 - positions[2].x <= 80.0)
	var arena := host.get_node("Arenas/NightmareArena") as BossArena
	ok(arena.checkpoint_report().ok)
	var gate := host.get_node("Props/ArenaGate") as RustyGate
	ok(gate.position.x - positions[2].x <= 80.0)
	ok(_standing_on(_rects(host), gate.position + Vector2(8, 64)))


func _rest_at(feet: Vector2) -> void:
	var host := _build()
	var player := await spawn_player(host, feet - Vector2(0, 24))
	await flush(360)
	eq(player.health.current, player.health.max_hp, "six seconds of real enemy AI at nest %s" % feet)
	ok(player.is_on_floor())


func test_entry_checkpoint_is_safe_for_six_seconds() -> void:
	await _rest_at(Vector2(176, 288))


func test_cooling_checkpoint_is_safe_for_six_seconds() -> void:
	await _rest_at(Vector2(1168, 288))


func test_boss_checkpoint_is_safe_for_six_seconds() -> void:
	await _rest_at(Vector2(LAYOUT.NEST_ARENA_X, 320))


func test_encounters_stay_out_of_the_boss_room() -> void:
	var host := _build()
	for row in LAYOUT.ENEMIES:
		var enemy := host.get_node("Enemies/" + String(row[0])) as Node2D
		eq(enemy.position, row[2])
		ok(String(row[1]) in ["ghost", "fire_skull"])
		ok(not LevelSanity.inside_solid(_rects(host), enemy.position), "%s begins in open air" % row[0])
		ok(enemy.position.x < LAYOUT.ARENA_X0)
	var player := await spawn_player(host, Vector2(1760, 328))
	await flush(60)
	player.position = Vector2(2400, 296)
	Director.abort()
	await flush(360)
	for enemy in host.get_node("Enemies").get_children():
		if enemy.name != "Nightmare":
			ok(enemy.position.x <= LAYOUT.CORRIDOR_ENEMY_MAX_X, "pursuer stays outside the arena")


func test_return_gallery_has_east_stairs_and_one_way_west_drop() -> void:
	var host := _build()
	var sequence := ["ReturnStairLow", "ReturnStairMid", "ReturnStairHigh", "ReturnE", "ReturnD", "ReturnC", "ReturnB", "ReturnEnd"]
	for index in range(1, sequence.size()):
		var from := host.get_node("Platforms/" + sequence[index - 1]) as SolidPlatform
		var to := host.get_node("Platforms/" + sequence[index]) as SolidPlatform
		ok(from.position.y - to.position.y <= 32.0)
		ok(from.position.x - (to.position.x + to.size.x) <= 32.0)
	var end := host.get_node("Platforms/ReturnEnd") as SolidPlatform
	var floor_ := host.get_node("Platforms/FloorHallA") as SolidPlatform
	ok(floor_.position.y - end.position.y > LevelSanity.JUMP_RISE_MAX, "west drop cannot be reversed by a basic jump")
	ok(_standing_on(_rects(host), Vector2(1136, 288)))
	ok(LevelSanity.is_reachable(host, Vector2(1952, 320), Vector2(1136, 224), false))


func test_ring_has_upper_route_four_seats_and_clear_charge_lane() -> void:
	var host := _build()
	var floor_ := host.get_node("Platforms/ArenaFloor") as SolidPlatform
	almost(floor_.position.x, LAYOUT.ARENA_X0)
	almost(floor_.position.y, 320.0)
	for row in LAYOUT.STEPS:
		if String(row[0]).contains("Gallery"):
			var platform := host.get_node("Platforms/" + String(row[0])) as SolidPlatform
			ok(320.0 - (platform.position.y + platform.size.y) >= 80.0, "Nightmare body clears upper route")
	for index in LAYOUT.PILLARS.size():
		var seat := host.get_node("Platforms/PillarSeat%d" % (index + 1)) as SolidPlatform
		almost(seat.position.y, 192.0)
		almost(seat.size.x, 64.0)
		ok(_standing_on(_rects(host), seat.position + Vector2(32, 32)))
		ok(LevelSanity.is_reachable(host, Vector2(2304, 320), seat.position + Vector2(32, 0), false))
	var dais := host.get_node("Platforms/CoreDais") as SolidPlatform
	eq(Rect2(dais.position, dais.size), LAYOUT.CORE_DAIS)
	ok(LevelSanity.is_reachable(host, Vector2(3888, 320), Vector2(2464, 224), false))
	var boss := host.get_node("Enemies/Nightmare") as Node2D
	eq(boss.scale, Vector2.ONE)
	eq(boss.position, LAYOUT.BOSS_POS)
	var body := boss.get_node("CollisionShape2D") as CollisionShape2D
	eq((body.shape as RectangleShape2D).size, Vector2(48, 28))


func test_vigil_branch_is_hook_only_and_grants_real_equipment() -> void:
	var host := _build()
	var deck := host.get_node("Platforms/VigilDeck") as SolidPlatform
	var hook := host.get_node("Hooks/HookVigil") as HookAnchor
	var stele := host.get_node("Props/SteleVigil") as LoreStele
	var reward := host.get_node("Props/RewardVigil") as EquipmentPickup
	ok(hook.position.y < deck.position.y)
	ok(deck.position.y - hook.position.y <= LevelSanity.HOOK_LAND_BELOW)
	ok(stele.lore_text.contains("送剑") and stele.lore_text.contains("守火"))
	ok(not LevelSanity.is_reachable(host, LAYOUT.ENTRY_SPAWN, LAYOUT.VIGIL_REWARD_FEET, false))
	ok(LevelSanity.is_reachable(host, LAYOUT.ENTRY_SPAWN, LAYOUT.VIGIL_REWARD_FEET, true))
	ok(EquipmentCatalog.has_id(reward.reward_ref))
	eq(reward.reward_name, EquipmentCatalog.for_id(reward.reward_ref).display_name)
	_isolate(host)
	var player := await spawn_player(host, Vector2(288, 136))
	reward.interact(player)
	await flush(2)
	ok(not is_instance_valid(reward))
	var received := false
	for item in player.equipment_inventory.bag + player.equipment_inventory.get_equipped_items():
		if item != null and String(item.id) == "iron_carapace":
			received = true
	ok(received, "actual inventory receives the vigil reward")


func test_pulses_wait_for_encounter_and_only_match_its_phase_events() -> void:
	var host := _build()
	_isolate(host)
	var pulses := _pulses(host)
	for pulse in pulses:
		pulse.tick(20.0)
		ok(not pulse.enabled and not pulse._armed)
		ok(is_inf(pulse.seconds_until_active()))
	GameEvents.boss_phase_changed.emit(BOSS_TITLE, 3)
	eq(pulses[1].phase_id, 0)
	var arena := host.get_node("Arenas/NightmareArena") as BossArena
	arena.activate()
	for index in pulses.size():
		eq(pulses[index].enabled, index == 1)
	GameEvents.boss_phase_changed.emit("other boss", 3)
	eq(pulses[1].phase_id, 1)
	GameEvents.boss_phase_changed.emit(BOSS_TITLE, 2)
	for pulse in pulses:
		eq(pulse.phase_id, 2)
		ok(pulse.enabled)
		almost(pulse.rest_time, 3.0)
		ok(pulse.seconds_until_active() >= 3.9)
	ok(pulses[0].seconds_until_active() < pulses[1].seconds_until_active())
	ok(pulses[1].seconds_until_active() < pulses[2].seconds_until_active())


func test_real_boss_damage_drives_faster_phases_and_full_warning() -> void:
	var host := _build()
	_isolate(host)
	var arena := host.get_node("Arenas/NightmareArena") as BossArena
	var boss = host.get_node("Enemies/Nightmare")
	arena.activate()
	var pulses := _pulses(host)
	boss.health.take_damage(6)
	Director.abort()
	for pulse in pulses:
		eq(pulse.phase_id, 2)
		pulse.tick(pulse.seconds_until_active() + 0.2)
		ok(pulse._armed)
	# The fixture freezes Boss AI; advance its real transition timer explicitly.
	boss._tick_phase_transition(1.21)
	ok(await wait_until(func() -> bool: return not boss.health.is_invincible(), 240))
	boss.health.take_damage(5)
	Director.abort()
	for pulse in pulses:
		eq(pulse.phase_id, 3)
		almost(pulse.rest_time, 2.0)
		almost(pulse.telegraph_time, 0.8)
		eq(pulse.state(), CyclicHazard.State.REST)
		ok(not pulse._armed)
		pulse.tick(pulse.start_delay + pulse.rest_time + 0.01)
		ok(pulse.is_warning() and not pulse._armed)
		pulse.tick(0.78)
		ok(pulse.is_warning() and not pulse._armed, "complete telegraph after reconfiguration")
		pulse.tick(0.02)
		ok(pulse.is_active() and pulse._armed)


func test_floor_front_really_hurts() -> void:
	var host := _build()
	_isolate(host)
	var player := await spawn_player(host, Vector2(3128, 296))
	var pulse = _pulses(host)[1]
	pulse.configure_phase(1)
	var hp := player.health.current
	pulse.tick(pulse.seconds_until_active() + pulse.active_time * 0.5)
	await flush(8)
	eq(player.health.current, hp - 1, "real Hitbox/Hurtbox floor damage")


func test_basic_jump_evades_the_same_front() -> void:
	var host := _build()
	_isolate(host)
	var player := await spawn_player(host, Vector2(3128, 296))
	var hp := player.health.current
	Input.action_press("jump")
	await flush(7)
	Input.action_release("jump")
	ok(player.position.y < 304.0)
	var pulse = _pulses(host)[1]
	pulse.configure_phase(1)
	pulse.tick(pulse.seconds_until_active() + pulse.active_time * 0.5)
	await flush(8)
	eq(player.health.current, hp, "same front misses airborne knight")


func test_pillar_top_evades_wave_without_timing() -> void:
	var host := _build()
	_isolate(host)
	var player := await spawn_player(host, Vector2(2880, 168))
	var hp := player.health.current
	var pulse = _pulses(host)[0]
	pulse.configure_phase(2)
	pulse.tick(pulse.seconds_until_active() + pulse.active_time * (112.0 / 144.0))
	await flush(8)
	ok(player.is_on_floor())
	almost(player.position.y, 192.0, 1.0)
	eq(player.health.current, hp)


func test_cinematic_freezes_delay_and_disarms_active_front() -> void:
	var host := _build()
	_isolate(host)
	var pulse = _pulses(host)[2]
	pulse.configure_phase(3)
	var delay: float = pulse.start_delay
	Director._set_lock(true)
	pulse.tick(1.0)
	almost(pulse.start_delay, delay)
	Director._set_lock(false)
	pulse.tick(pulse.seconds_until_active() + 0.2)
	ok(pulse._armed)
	var clock_: float = pulse.clock()
	Director._set_lock(true)
	pulse.tick(1.0)
	almost(pulse.clock(), clock_)
	ok(not pulse._hitbox.monitoring)
	Director._set_lock(false)
	pulse.tick(0.01)
	ok(pulse._hitbox.monitoring)


func test_death_stops_pulses_and_dead_reload_omits_them() -> void:
	var host := _build()
	_isolate(host)
	var arena := host.get_node("Arenas/NightmareArena") as BossArena
	arena.activate()
	for pulse in _pulses(host):
		pulse.configure_phase(3)
		pulse.tick(pulse.seconds_until_active() + 0.2)
		ok(pulse._armed)
	var boss = host.get_node("Enemies/Nightmare")
	boss.health.take_damage(99)
	for pulse in _pulses(host):
		ok(not pulse.enabled and not pulse._armed)
		pulse.tick(20.0)
		ok(not pulse._armed)
	ok(arena.cleared and SaveData.has_flag("nightmare_dead"))
	await flush(2)
	var reloaded := _build()
	ok(reloaded.get_node_or_null("Enemies/Nightmare") == null)
	ok(reloaded.get_node_or_null("Arenas/NightmareArena") == null)
	ok(reloaded.get_node_or_null("Props/CorePulse1") == null)
	ok(not (reloaded.get_node("Props/Exit") as LevelExit).is_locked())


func test_original_ending_door_and_fractured_altars_have_support() -> void:
	var host := _build()
	var exit := host.get_node("Props/Exit") as LevelExit
	eq(exit.target_scene, "")
	eq(exit.requires_flag, "nightmare_dead")
	eq(exit.flag_id, "game_complete")
	eq(exit.door_label, ChapterText.exit_label_of("level10"))
	ok(exit.ending_choice and exit.is_locked())
	eq(exit.give_captions, ChapterText.ending_lines_of("give"))
	eq(exit.keep_captions, ChapterText.ending_lines_of("keep"))
	ok(_standing_on(_rects(host), exit.position))
	ok(exit.position.x > LAYOUT.ARENA_X1 and exit.position.x <= LAYOUT.EAST_LIMIT - 80)
	for id in ["CoreAltar", "ForgeAltar"]:
		var altar := host.get_node("Decor/" + id) as Node2D
		ok(altar.is_in_group("grounded"))
		ok(_standing_on(_rects(host), altar.get_meta("feet")))
		ok(altar.get_child_count() >= 8)


func test_keep_ending_persists_and_returns_to_title() -> void:
	SaveData.mark_flag("nightmare_dead")
	var level := (load(GameContext.LEGACY_LEVELS["level10"]) as PackedScene).instantiate() as Node2D
	add_child(level)
	await flush(2)
	Director.abort()
	for enemy in level.get_node("Enemies").get_children():
		enemy.set_physics_process(false)
	var player := get_tree().get_first_node_in_group("player") as Player
	var exit := level.get_node("Props/Exit") as LevelExit
	exit.interact(player)
	exit.confirm_ending(&"keep")
	await flush(1)
	Director.abort()
	await flush(3)
	ok(SaveData.load_game())
	ok(SaveData.has_flag("game_complete") and SaveData.has_flag("nightmare_dead"))
	eq(SaveData.ending, "keep")
	ok(await wait_until(func() -> bool:
		return not Director.is_fading() and Director.last_fade_target == "res://scenes/ui/TitleScreen.tscn"
	), "original keeping-fire captions return to title")


func test_room_support_and_sanity_are_clean() -> void:
	var host := _build()
	var ceiling := host.get_node("Platforms/Ceiling") as SolidPlatform
	almost(ceiling.position.y, LAYOUT.CEILING_Y)
	almost(ceiling.size.x, LAYOUT.EAST_LIMIT)
	for node in host.get_node("Decor").get_children():
		if node.is_in_group("grounded") and node.has_meta("feet"):
			ok(_standing_on(_rects(host), node.get_meta("feet"), 4.0), "%s has support" % node.name)
	var problems := LevelSanity.check(host)
	for problem in problems:
		ok(false, problem)
	ok(problems.is_empty())
