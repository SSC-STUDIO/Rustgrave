extends TestCase
## 环境打击：headless 只记账、不建节点；火球撞地/撞墙恰好触发一次并按材质出表现；
## 打击痕迹容器有上限与环形复用。

const PROJ := preload("res://scenes/combat/Projectile.tscn")
const DecalFieldScript := preload("res://scripts/world/decal_field.gd")


func _wall(pos: Vector2, size: Vector2, material: StringName = &"") -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = "Wall"
	body.position = pos
	body.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	if material != &"":
		body.set_meta(&"impact_material", material)
	add_child(body)
	return body


func _bolt(origin: Vector2, direction: Vector2, speed: float = 240.0) -> Projectile:
	var bolt := PROJ.instantiate() as Projectile
	add_child(bolt)
	bolt.setup(origin, direction, speed, &"enemy", null)
	return bolt


func test_headless_impact_only_counts_and_creates_no_nodes() -> void:
	eq(DisplayServer.get_name(), "headless")
	Fx.reset_impact_counters()
	var before := Fx.get_child_count()
	Fx.impact(&"stone", Vector2(12.0, 4.0), Vector2.UP, &"heavy")
	Fx.impact(&"wood", Vector2(-3.0, 8.0), Vector2.LEFT, &"light")
	eq(Fx.impact_count(), 2, "headless 也记录打击次数")
	eq(Fx.get_child_count(), before, "headless 不建任何节点")
	eq(String(Fx.last_impact().get("material", "")), "wood")
	Fx.reset_impact_counters()
	eq(Fx.impact_count(), 0)


func test_decal_field_recycles_at_the_budget_cap() -> void:
	eq(int(CombatRules.BUDGET[&"decals"]), DecalFieldScript.MAX_DECALS,
			"预算表与 DecalField 上限一致")
	var field = DecalFieldScript.new()
	add_child(field)
	var kinds := [&"scorch", &"chip", &"pit", &"puddle", &"gash"]
	for i in DecalFieldScript.MAX_DECALS + 7:
		field.add(kinds[i % kinds.size()], &"stone", Vector2(float(i) * 3.0, -8.0),
				Vector2.UP, 1.0)
	eq(field.count(), DecalFieldScript.MAX_DECALS, "痕迹数量不超过上限")
	eq(field.total_added(), DecalFieldScript.MAX_DECALS + 7)
	eq(field.recycled(), 7, "超出后复用最老的痕迹")
	# 每个痕迹都真的画了格子（none 除外）
	var cells := 0
	for child in field.get_children():
		cells += int(child.call(&"cell_count"))
	ok(cells > 0, "痕迹有可绘制格子")
	field.clear_all()
	eq(field.count(), 0)
	field.queue_free()


func test_fireball_impacts_floor_exactly_once() -> void:
	build_floor(self)
	Fx.reset_impact_counters()
	var bolt := _bolt(Vector2(0.0, -26.0), Vector2.DOWN)
	await flush(24)
	eq(Fx.impact_count(), 1, "落地只结算一次环境打击")
	eq(StringName(Fx.last_impact().get("material", &"")), &"stone",
			"无 skin 的地面回退 stone")
	ok(not is_instance_valid(bolt) or bolt.is_queued_for_deletion(), "弹丸撞地后消失")


func test_fireball_wall_hit_uses_declared_material() -> void:
	_wall(Vector2(0.0, 0.0), Vector2(18.0, 60.0), &"wood")
	Fx.reset_impact_counters()
	var bolt := _bolt(Vector2(-48.0, 0.0), Vector2.RIGHT)
	await flush(24)
	eq(Fx.impact_count(), 1, "撞墙结算一次")
	eq(StringName(Fx.last_impact().get("material", &"")), &"wood", "撞墙读 hit_material")


func test_fireball_ignores_non_terrain_bodies() -> void:
	var actor := CharacterBody2D.new()
	actor.name = "Actor"
	actor.collision_layer = 2  # player body layer，不在 TERRAIN_MASK 里
	add_child(actor)
	Fx.reset_impact_counters()
	var bolt := _bolt(Vector2(-44.0, 0.0), Vector2.RIGHT)
	await flush(16)
	eq(Fx.impact_count(), 0, "火球穿过角色体，不产生环境打击")
	ok(is_instance_valid(bolt) and not bolt.is_queued_for_deletion(), "弹丸仍在飞行")
	bolt.queue_free()
	await flush(2)
