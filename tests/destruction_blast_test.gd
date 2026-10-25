extends TestCase
## M3 中性爆破源：spawn_blast 生成合规 Hitbox、面杀伤裂石板、连锁引爆、
## 对玩家的中性伤害、半径豁免、每帧连锁上限。

const PROP_SCENE := preload("res://scenes/interactables/DestructibleProp.tscn")
const SLAB_SCENE := preload("res://scenes/world/BreakableSlab.tscn")


func setup() -> void:
	SaveData.delete_save()
	SaveData.flags.clear()


func teardown() -> void:
	SaveData.delete_save()
	SaveData.flags.clear()


func _make_prop(prop_id: StringName, pos: Vector2) -> DestructibleProp:
	var prop := PROP_SCENE.instantiate() as DestructibleProp
	prop.prop_id = prop_id
	prop.persist = false
	prop.position = pos
	add_child(prop)
	return prop


func _hit(prop: DestructibleProp, amount: int = 1) -> void:
	var box := Hitbox.new()
	box.team = &"player"
	box.blow = &"light"
	add_child(box)
	box.global_position = prop.global_position + Vector2(4, -8)
	var hurt := prop.get_node_or_null("Hurtbox") as Hurtbox
	ok(hurt != null, "道具 Hurtbox 存在")
	if hurt != null:
		hurt.receive_hit(amount, box)
	box.queue_free()


func _blast_nodes() -> Array[Node]:
	return get_tree().root.find_children("DestructionBlast", "Hitbox", true, false)


func test_spawn_blast_creates_a_compliant_hitbox() -> void:
	var box := Destruction.spawn_blast(self, Vector2(200, 200), 40.0, 1)
	ok(box != null, "爆破生成 Hitbox")
	if box == null:
		return
	eq(box.team, &"player", "爆破 Hitbox 走 player 队（能打敌人与 prop，不伤自己）")
	eq(box.blow, &"heavy", "heavy 够到裂石板破坏门槛")
	eq(box.damage, 1)
	eq(box.collision_layer, 8)
	eq(box.collision_mask, 32)
	await flush(8)
	ok(not is_instance_valid(box), "爆破 Hitbox 寿命结束后自毁")


func test_blast_breaks_terrain_chunks_in_radius() -> void:
	var slab := SLAB_SCENE.instantiate() as BreakableTerrain
	slab.size = Vector2(64, 64)
	slab.skin = "stone"
	slab.persist_break = false
	slab.position = Vector2(400, 100)
	add_child(slab)
	var center := slab.global_position + Vector2(32, 32)
	Destruction.spawn_blast(self, center, 60.0, 1)
	eq(slab.broken_chunks(), 4, "半径全覆盖：2x2 全碎")
	ok(slab.is_destroyed())
	slab.queue_free()


func test_blast_radius_spares_outside_chunks() -> void:
	var slab := SLAB_SCENE.instantiate() as BreakableTerrain
	slab.size = Vector2(128, 32)
	slab.skin = "stone"
	slab.persist_break = false
	slab.position = Vector2(400, 300)
	add_child(slab)
	# 只在左端引爆：左边两块（中心 16/48）进半径，右边两块（80/112）安全。
	Destruction.spawn_blast(self, slab.global_position + Vector2(16, 16), 40.0, 1)
	eq(slab.broken_chunks(), 2, "半径内两块碎")
	ok(slab.is_chunk_broken(0))
	ok(slab.is_chunk_broken(1))
	ok(not slab.is_chunk_broken(2), "半径外的块完好")
	ok(not slab.is_chunk_broken(3), "半径外的块完好")
	slab.queue_free()


func test_blast_urn_break_triggers_blast_node() -> void:
	Fx.reset_impact_counters()
	var urn := _make_prop(&"blast_urn", Vector2(600, 320))
	_hit(urn)
	await flush(1)
	ok(not is_instance_valid(urn) or urn.is_queued_for_deletion(), "爆破罐已碎")
	ok(not _blast_nodes().is_empty(), "破碎瞬间生成爆破 Hitbox")
	ok(Fx.impact_count() >= 2, "破碎打击 + 爆破打击都记数")
	await flush(8)


func test_blast_urn_chain_detonation() -> void:
	var first := _make_prop(&"blast_urn", Vector2(700, 320))
	var second := _make_prop(&"blast_urn", Vector2(720, 320))
	_hit(first)
	await flush(6)
	ok(not is_instance_valid(first) or first.is_queued_for_deletion(), "第一只爆破罐碎")
	ok(not is_instance_valid(second) or second.is_queued_for_deletion(),
			"相邻爆破罐被连锁引爆")


func test_blast_hurts_player_inside_radius_only() -> void:
	var host := Node2D.new()
	add_child(host)
	var player := await spawn_player(host, Vector2(320, -24))
	var health := player.get("health") as Health
	ok(health != null, "玩家 Health 存在")
	if health == null:
		return
	var hp_before := health.current
	# 远处爆破不伤玩家。
	Destruction.spawn_blast(self, player.global_position + Vector2(300, 0), 40.0, 1)
	eq(health.current, hp_before, "半径外玩家不掉血")
	# 贴身爆破掉血（中性危害）。
	Destruction.spawn_blast(self, player.global_position, 44.0, 1)
	ok(health.current < hp_before, "半径内玩家被爆破波及")
	player.queue_free()
	host.queue_free()
	await flush(2)


func test_chain_cap_throttles_same_frame_blasts() -> void:
	var spawned := 0
	for i in Destruction.MAX_CHAIN_PER_FRAME + 2:
		if Destruction.spawn_blast(self, Vector2(900 + i * 60, 100), 24.0, 1) != null:
			spawned += 1
	eq(spawned, Destruction.MAX_CHAIN_PER_FRAME, "同帧爆破数被连锁上限截流")
	await flush(8)


func test_spawn_blast_rejects_detached_host() -> void:
	var orphan := Node2D.new()
	eq(Destruction.spawn_blast(orphan, Vector2.ZERO, 24.0), null, "未入树宿主直接拒绝")
	orphan.free()
