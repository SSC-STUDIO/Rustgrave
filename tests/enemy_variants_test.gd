extends TestCase
## 敌人变体：预设表自洽、数值/材质/血量/头顶标记按预设套上、基类不匹配时拒绝套用、
## 散射喷吐者一口三发、爆裂骸骨死后读招再爆开伤人。

func _host() -> Node2D:
	var host := Node2D.new()
	add_child(host)
	return host


func _enemy(host: Node2D, kind: String, variant: StringName, pos: Vector2 = Vector2(300, 0)) -> EnemyBase:
	var layout := ChapterLayout.new()
	add_child(layout)
	return layout.enemy(host, "%s_%s" % [kind, variant], kind, pos, {"variant": variant}) as EnemyBase


func test_table_is_consistent() -> void:
	ok(EnemyVariants.TABLE.size() >= 5, "five variants")
	for id in EnemyVariants.TABLE:
		var data: Dictionary = EnemyVariants.TABLE[id]
		var base: StringName = data["base"]
		ok(ChapterLayout.ENEMY_SCENES.has(String(base)), "%s has a spawnable base kind (%s)" % [id, base])
		ok(EnemyVariants.label_of(id) != "", "%s has a Chinese label" % id)
		ok(int(data.get("hp", 1)) >= 1)
		var props: Dictionary = data.get("props", {})
		for key in ["windup_time", "charge_time"]:
			if props.has(key):
				ok(float(props[key]) >= CombatRules.TELEGRAPH_MIN,
						"%s keeps the telegraph above the %.2fs floor" % [id, CombatRules.TELEGRAPH_MIN])
		ok(data.has("pip"), "%s has a head marker colour" % id)
	eq(EnemyVariants.variants_for(&"scrapper").size(), 2, "two scrapper variants")
	ok(not EnemyVariants.has_variant(&"nope"))


func test_armored_scrapper_gets_hp_material_props_and_a_marker() -> void:
	var host := _host()
	var dog := _enemy(host, "scrapper", &"armored_scrapper")
	await flush(1)
	eq(dog.health.max_hp, 5)
	eq(dog.health.current, 5)
	eq(dog.hit_material, &"armour")
	almost(float(dog.get("charge_speed")), 205.0, 0.001)
	almost(float(dog.get("windup_time")), 0.55, 0.001)
	ok(dog.get_node_or_null("VariantPip") != null, "the head marker is there")
	eq(dog.get_meta("variant"), &"armored_scrapper")
	if dog._anim != null:
		ok(dog._anim.self_modulate != Color.WHITE, "tint lives on self_modulate, so the hit flash still works")
	var plain := _enemy(host, "scrapper", &"", Vector2(500, 0))
	await flush(1)
	eq(plain.health.max_hp, 3, "the plain scrapper is untouched")
	ok(plain.get_node_or_null("VariantPip") == null)


func test_swift_scrapper_charges_faster_with_a_shorter_but_legal_windup() -> void:
	var host := _host()
	var dog := _enemy(host, "scrapper", &"swift_scrapper")
	await flush(1)
	almost(float(dog.get("charge_speed")), 285.0, 0.001)
	ok(float(dog.get("windup_time")) >= CombatRules.TELEGRAPH_MIN, "still telegraphed")
	eq(dog.health.max_hp, 2)


func test_heavy_guard_and_wrong_base_rejection() -> void:
	var host := _host()
	var guard := _enemy(host, "gear_shield", &"heavy_guard")
	await flush(1)
	eq(guard.health.max_hp, 6)
	almost(float(guard.get("stagger_time")), 1.2, 0.001)
	# 把装甲碎铁犬的预设套到喷吐者上：拒绝，血量保持原样。
	var spitter := _enemy(host, "spitter", &"armored_scrapper", Vector2(700, 0))
	await flush(1)
	eq(spitter.health.max_hp, 2, "a scrapper preset is refused on a spitter")
	ok(spitter.get_node_or_null("VariantPip") == null)


func test_scatter_spitter_fires_a_fan_of_three() -> void:
	var host := _host()
	build_floor(host)
	var player := await spawn_player(host, Vector2(100, -24))
	var spitter := _enemy(host, "spitter", &"scatter_spitter", Vector2(400, -40))
	spitter.set_physics_process(false)
	await flush(1)
	eq(int(spitter.get("burst")), 3)
	var bolts: Array[Projectile] = []
	var watcher := func(node: Node) -> void:
		if node is Projectile:
			bolts.append(node as Projectile)
	get_tree().node_added.connect(watcher)
	spitter.call("_fire", player)
	get_tree().node_added.disconnect(watcher)
	eq(bolts.size(), 3, "one breath, three bolts")
	if bolts.size() == 3:
		var v0 := bolts[0].velocity
		var v1 := bolts[1].velocity
		var v2 := bolts[2].velocity
		ok(v0.angle_to(v1) != 0.0 and v1.angle_to(v2) != 0.0, "fanned out")
		almost(absf(v0.angle_to(v2)), deg_to_rad(30.0), 0.02, "the fan spans 2 x spread_deg")


func test_exploding_skeleton_blasts_after_a_readable_delay() -> void:
	var host := _host()
	build_floor(host)
	var player := await spawn_player(host, Vector2(320, -24))
	var bones := _enemy(host, "skeleton", &"exploder_skeleton", Vector2(320, 0))
	bones.set_physics_process(false)
	await flush(1)
	ok(bones.has_meta("variant_blast"))
	var before := player.health.current
	bones.health.take_damage(99, player)
	await flush(3)
	var found: Node = null
	for node in get_tree().root.find_children("DeathBlast_*", "Node2D", true, false):
		found = node
	ok(found != null, "a blast marker stays where the bones fell")
	eq(player.health.current, before, "nothing hurts during the warning")
	await flush(55)
	ok(player.health.current < before, "the blast hurts a knight who stayed (%d -> %d)" % [before, player.health.current])
	await flush(20)
	var remaining := get_tree().root.find_children("DeathBlast_*", "Node2D", true, false)
	ok(remaining.is_empty(), "and the blast cleans itself up")
