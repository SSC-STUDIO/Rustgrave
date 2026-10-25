extends TestCase
## 可破坏道具：数据驱动外观/耐久、受击掉血、破碎表现与存档状态。

const PROP_SCENE := preload("res://scenes/interactables/DestructibleProp.tscn")
const Catalog := preload("res://scripts/data/destructible_catalog.gd")
const ImpactCatalog := preload("res://scripts/data/impact_catalog.gd")


func _make_prop(prop_id: StringName, persist: bool = false) -> DestructibleProp:
	var prop := PROP_SCENE.instantiate() as DestructibleProp
	prop.prop_id = prop_id
	prop.persist = persist
	add_child(prop)
	return prop


func _make_attacker(blow: StringName = &"light") -> Hitbox:
	var attacker := Hitbox.new()
	attacker.name = "TestHitbox"
	attacker.team = &"player"
	attacker.blow = blow
	add_child(attacker)
	return attacker


func _hit(prop: DestructibleProp, attacker: Hitbox, amount: int = 1) -> void:
	var hurt := prop.get_node_or_null("Hurtbox") as Hurtbox
	ok(hurt != null, "道具带 Hurtbox")
	if hurt != null:
		hurt.receive_hit(amount, attacker)


func test_catalog_props_build_with_their_declared_material_and_durability() -> void:
	for prop_id in Catalog.ids():
		var prop := _make_prop(prop_id)
		var def: Dictionary = Catalog.def(prop_id)
		eq(prop.hit_material, StringName(def["material"]), "%s 材质" % prop_id)
		eq(prop.collision_layer, 1, "%s 在世界静态层（火球射线可命中）" % prop_id)
		ok(prop.is_in_group(&"destructible_body"), "%s 允许火球放行给 Hurtbox" % prop_id)
		var hurt := prop.get_node_or_null("Hurtbox") as Hurtbox
		ok(hurt != null)
		if hurt != null:
			eq(hurt.team, &"prop", "%s 的 Hurtbox 独立队伍" % prop_id)
		var health := prop.get_node_or_null("Health") as Health
		ok(health != null)
		if health != null:
			eq(health.max_hp, int(def["max_hp"]), "%s 耐久" % prop_id)
			eq(health.current, health.max_hp)
		ok(prop.get_node_or_null("Body") is Sprite2D, "%s 有贴图" % prop_id)
		prop.free()


func test_hit_damages_then_break_plays_feedback_and_announcement() -> void:
	var prop := _make_prop(&"rust_urn")
	var def: Dictionary = Catalog.def(&"rust_urn")
	var announcements: Array[String] = []
	var on_line := func(text: String) -> void: announcements.append(text)
	GameEvents.announcement.connect(on_line)
	var attacker := _make_attacker(&"light")
	_hit(prop, attacker)
	await flush(2)
	var gone := not is_instance_valid(prop) or prop.is_queued_for_deletion()
	ok(gone, "一击打碎 1 耐久锈罐并从场景里退场")
	eq(announcements.size(), 1, "破碎只播一次旁白")
	if announcements.size() == 1:
		eq(announcements[0], String(def["announce"]))
	GameEvents.announcement.disconnect(on_line)
	attacker.free()


func test_two_durability_prop_needs_two_windows() -> void:
	var prop := _make_prop(&"scrap_heap")
	var attacker := _make_attacker(&"light")
	var health: Health = prop.get_node("Health") as Health
	_hit(prop, attacker)
	eq(health.current, 1, "第一击只掉 1")
	# 受击 i-frame 内第二击无效（与敌人同一套 Health 规则）。
	_hit(prop, attacker)
	eq(health.current, 1, "i-frame 内不重复扣血")
	ok(not prop.is_destroyed())
	prop.free()
	attacker.free()


func test_persistent_state_roundtrip() -> void:
	var prop := _make_prop(&"scrap_heap", true)
	eq(bool(prop.get_persistent_state().get("destroyed", false)), false)
	prop.apply_persistent_state({"destroyed": true})
	await flush(2)
	ok(not is_instance_valid(prop) or prop.is_queued_for_deletion(), "读档时直接消失")
	SaveData.delete_save()


func test_session_only_prop_is_not_saved() -> void:
	var prop := _make_prop(&"rust_urn", false)
	ok(not prop.is_in_group(&"persistent"), "persist=false 不写世界状态")
	eq(prop.get_persistent_state(), {"destroyed": false})
	prop.free()


func test_catalog_definitions_are_complete_and_valid() -> void:
	for prop_id in Catalog.ids():
		var def: Dictionary = Catalog.def(prop_id)
		ok(ImpactCatalog.has_material(StringName(def["material"])),
				"%s 材质在 ImpactCatalog 内" % prop_id)
		ok(String(def["texture"]) != "", "%s 有贴图" % prop_id)
		ok(int(def["max_hp"]) >= 1, "%s 耐久 >= 1" % prop_id)
		var blast: Variant = def.get("blast", {})
		if blast is Dictionary and not (blast as Dictionary).is_empty():
			ok(float((blast as Dictionary).get("radius", 0.0)) > 0.0,
					"%s 爆破半径 > 0" % prop_id)
			ok(int((blast as Dictionary).get("damage", 0)) >= 1,
					"%s 爆破伤害 >= 1" % prop_id)


func test_damaged_prop_shows_cracks_before_breaking() -> void:
	var prop := _make_prop(&"scrap_heap") # 耐久 2
	ok(not prop.has_cracks(), "完好时无裂纹")
	var attacker := _make_attacker(&"light")
	_hit(prop, attacker)
	await flush(1)
	ok(not prop.is_destroyed(), "第一击不致命")
	ok(prop.has_cracks(), "耐久过半损失后挂裂纹覆盖层")
	prop.free()
	attacker.free()


func test_ember_cache_drops_ember_xp() -> void:
	SaveData.delete_save()
	SaveData.ember_xp = 0
	var prop := _make_prop(&"ember_cache")
	var health := prop.get_node("Health") as Health
	var attacker := _make_attacker(&"heavy")
	# 直接扣到死（绕过 i-frame 等待），掉落仍在 _break 里结算。
	health.take_damage(99, attacker)
	await flush(1)
	ok(not is_instance_valid(prop) or prop.is_queued_for_deletion(), "余烬窖已碎")
	eq(SaveData.ember_xp, 3, "掉落 3 点余烬经验")
	var award := EmberProgress.last_award()
	eq(int(award.get("amount", 0)), 3)
	eq(StringName(award.get("source", &"")), &"destruction")
	SaveData.ember_xp = 0
	SaveData.delete_save()
	attacker.free()
