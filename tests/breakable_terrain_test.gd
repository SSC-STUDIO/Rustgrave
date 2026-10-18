extends TestCase
## 可破坏地形：32px 分块、轻击只出火星、重击/爆炸才掉块、持久化与读档恢复。

const SLAB_SCENE := preload("res://scenes/world/BreakableSlab.tscn")


func _make_slab(size: Vector2 = Vector2(64, 32), persist: bool = false) -> BreakableTerrain:
	var slab := SLAB_SCENE.instantiate() as BreakableTerrain
	slab.size = size
	slab.skin = "stone"
	slab.persist_break = persist
	add_child(slab)
	return slab


func _attacker(pos: Vector2, blow: StringName = &"heavy") -> Hitbox:
	var box := Hitbox.new()
	box.name = "TestHitbox"
	box.team = &"player"
	box.blow = blow
	add_child(box)
	box.global_position = pos
	return box


func _hit(slab: BreakableTerrain, attacker: Node, amount: int = 1) -> void:
	var hurt := slab.get_node_or_null("Hurtbox") as Hurtbox
	ok(hurt != null)
	if hurt != null:
		hurt.receive_hit(amount, attacker)


func test_chunk_grid_follows_size() -> void:
	var slab := _make_slab(Vector2(64, 32))
	eq(slab.chunk_count(), 2, "64x32 -> 2 块")
	eq(slab.broken_chunks(), 0)
	ok(not slab.is_destroyed())
	slab.free()
	var tall := _make_slab(Vector2(64, 64))
	eq(tall.chunk_count(), 4, "64x64 -> 4 块")
	tall.free()


func test_light_hits_only_spark_and_never_damage() -> void:
	var slab := _make_slab()
	var slab_center := slab.global_position + Vector2(16, 16)
	var light := _attacker(slab_center, &"light")
	_hit(slab, light)
	eq(slab.broken_chunks(), 0, "轻击不破块")
	eq(slab.chunk_hp_left(0), 2, "轻击不掉耐久")
	light.free()
	slab.free()


func test_heavy_hits_break_chunks_one_by_one() -> void:
	var slab := _make_slab()
	var announcements: Array[String] = []
	var on_line := func(text: String) -> void: announcements.append(text)
	GameEvents.announcement.connect(on_line)
	var heavy := _attacker(slab.global_position + Vector2(16, 16), &"heavy")
	_hit(slab, heavy)
	eq(slab.chunk_hp_left(0), 1, "第一下重击：耐久 2 -> 1")
	_hit(slab, heavy)
	eq(slab.broken_chunks(), 1, "第二下重击打碎第一块")
	ok(not slab.is_chunk_broken(1), "另一块还在")
	eq(announcements.size(), 0, "只碎一块时还不播整块坍塌")
	heavy.global_position = slab.global_position + Vector2(48, 16)
	_hit(slab, heavy)
	_hit(slab, heavy)
	await flush(2)
	eq(slab.broken_chunks(), 2, "第二块也碎")
	ok(slab.is_destroyed(), "整块裂石板被清空")
	eq(announcements.size(), 1, "全碎时播一次旁白")
	GameEvents.announcement.disconnect(on_line)
	heavy.free()
	slab.free()


func test_two_damage_projectile_counts_as_heavy() -> void:
	var slab := _make_slab()
	var bolt_scene := preload("res://scenes/combat/Projectile.tscn")
	var bolt := bolt_scene.instantiate() as Projectile
	bolt.name = "TestBolt"
	slab.add_child(bolt)
	bolt.global_position = slab.global_position
	bolt.damage = 2
	bolt.team = &"enemy"
	_hit(slab, bolt, 2)
	eq(slab.broken_chunks(), 1, "伤害 >=2 的弹丸能打碎一块")
	bolt.free()
	slab.free()


func test_persist_break_roundtrip_and_quiet_restore() -> void:
	var slab := _make_slab(Vector2(64, 32), true)
	ok(slab.is_in_group(&"persistent"), "persist_break 才进世界状态")
	ok(slab.damage_chunk(0, 2), "第一块碎掉")
	var broken_state: Array = slab.get_persistent_state().get("broken", [])
	eq(broken_state, [0])
	var announcements: Array[String] = []
	var on_line := func(text: String) -> void: announcements.append(text)
	GameEvents.announcement.connect(on_line)
	var restored := _make_slab(Vector2(64, 32), true)
	restored.apply_persistent_state({"broken": [0]})
	await flush(2)
	ok(restored.is_chunk_broken(0), "读档恢复已碎块")
	eq(restored.broken_chunks(), 1)
	eq(announcements.size(), 0, "读档恢复不播特效/旁白")
	GameEvents.announcement.disconnect(on_line)
	restored.free()
	slab.free()


func test_session_only_slab_is_not_persistent() -> void:
	var slab := _make_slab(Vector2(64, 32), false)
	ok(not slab.is_in_group(&"persistent"), "默认会话内破坏、重载恢复")
	slab.free()
