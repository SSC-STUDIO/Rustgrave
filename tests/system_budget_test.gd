extends TestCase
const MAX_HAZARDS := 32
const MAX_LIGHTS := 64
const MAX_WORLD_NODES := 6000


func test_dedicated_hazard_cues_and_title_bed_resolve_with_voice_caps() -> void:
	for skin in HazardFx.SFX:
		for moment in HazardFx.SFX[skin]:
			if HazardFx.SFX[skin][moment].is_empty():
				continue
			var key := HazardFx.resolve(skin, moment)
			ok(String(key).begins_with("hazard_"), "%s/%s uses a dedicated cue" % [skin, moment])
			var stream := load(Sfx.LIBRARY[key]) as AudioStream
			ok(stream != null and stream.get_length() > 0.1)
			ok(Sfx.VOICE_RULES.has(key))
			ok(Sfx.VOICE_RULES[key].x <= 2)
	var bed := load(Sfx.AMBIENCE[&"bed_title"]) as AudioStreamOggVorbis
	ok(bed != null)
	if bed != null:
		almost(bed.get_length(), 24.0, 0.1)
	ok(Sfx.THEME_BEDS[&"title"].has(&"bed_title"))


func test_every_chapter_stays_within_hazard_light_and_node_budgets() -> void:
	var before_flags := SaveData.flags.duplicate()
	var before_path := SaveData.save_path
	SaveData.save_path = "user://system_budget_missing.cfg"
	SaveData.flags = PackedStringArray(["wake", "boss_intro"])
	for id in GameContext.LEVEL_ORDER:
		Director.abort()
		var world := load(GameContext.LEVELS[id]).instantiate() as Node
		add_child(world)
		await flush(1)
		Director.abort()
		var hazard_count := 0
		for node in world.find_children("*", "Node", true, false):
			if node.is_in_group("hazards"):
				hazard_count += 1
		var lights := world.find_children("*", "Light2D", true, false).size()
		var nodes := world.find_children("*", "Node", true, false).size()
		ok(hazard_count <= MAX_HAZARDS, "%s hazards %d <= %d" % [id, hazard_count, MAX_HAZARDS])
		ok(lights <= MAX_LIGHTS, "%s lights %d <= %d" % [id, lights, MAX_LIGHTS])
		ok(nodes <= MAX_WORLD_NODES, "%s nodes %d <= %d" % [id, nodes, MAX_WORLD_NODES])
		print("[BUDGET] %s hazards=%d lights=%d nodes=%d" % [id, hazard_count, lights, nodes])
		world.queue_free()
		await flush(2)
	SaveData.flags = before_flags
	SaveData.save_path = before_path
	Director.abort()
