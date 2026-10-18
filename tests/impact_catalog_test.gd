extends TestCase
## 环境打击表现表：材质解析、权重、兜底，以及每个 SolidPlatform skin 都有归属。

const ImpactCatalog := preload("res://scripts/data/impact_catalog.gd")
const SolidPlatformScript := preload("res://scripts/world/solid_platform.gd")


func test_every_platform_skin_maps_to_a_defined_material() -> void:
	var surfaces: Dictionary = Sfx.SKIN_SURFACE
	ok(surfaces.size() >= 18, "skin 表至少有 18 项")
	for skin in surfaces:
		var material := ImpactCatalog.material_for_skin(String(skin))
		ok(ImpactCatalog.MATERIALS.has(material),
				"skin %s -> 材质 %s 必须在表现表里" % [skin, material])


func test_surface_family_mapping_is_sane() -> void:
	eq(ImpactCatalog.material_for_skin("ground"), &"dirt")
	eq(ImpactCatalog.material_for_skin("moss"), &"wet")
	eq(ImpactCatalog.material_for_skin("iron"), &"metal")
	eq(ImpactCatalog.material_for_skin("castle"), &"stone")
	eq(ImpactCatalog.material_for_skin("definitely_unknown"), &"stone", "未知回退 stone")


func test_collider_material_priority_and_fallbacks() -> void:
	# 1) hit_material 属性优先
	var script := GDScript.new()
	script.source_code = "extends Node2D\nvar hit_material: StringName = &\"wood\"\n"
	script.reload()
	var declared := Node2D.new()
	declared.set_script(script)
	add_child(declared)
	eq(ImpactCatalog.material_for_collider(declared), &"wood")
	declared.queue_free()

	# 2) impact_material() 方法优先于属性
	var method_script := GDScript.new()
	method_script.source_code = "extends Node2D\nfunc impact_material() -> StringName:\n\treturn &\"metal\"\n"
	method_script.reload()
	var by_method := Node2D.new()
	by_method.set_script(method_script)
	add_child(by_method)
	eq(ImpactCatalog.material_for_collider(by_method), &"metal")
	by_method.queue_free()

	# 3) SolidPlatform 的 skin 走 Sfx.surface_for_skin
	var platform = SolidPlatformScript.new()
	platform.skin = "moss"
	eq(ImpactCatalog.material_for_collider(platform), &"wet")
	platform.free()

	# 4) meta 兜底
	var prop := StaticBody2D.new()
	prop.set_meta(&"impact_material", &"wood")
	add_child(prop)
	eq(ImpactCatalog.material_for_collider(prop), &"wood")
	prop.queue_free()

	# 5) 完全未知 -> stone
	var plain := StaticBody2D.new()
	add_child(plain)
	eq(ImpactCatalog.material_for_collider(plain), &"stone")
	eq(ImpactCatalog.material_for_collider(null), &"stone")
	plain.queue_free()


func test_weights_scale_particles_and_unknown_weight_is_light() -> void:
	ok(float(ImpactCatalog.weight_scale(&"heavy")) > float(ImpactCatalog.weight_scale(&"light")))
	ok(float(ImpactCatalog.weight_scale(&"finisher")) > float(ImpactCatalog.weight_scale(&"heavy")))
	almost(ImpactCatalog.weight_scale(&"nonsense"), 1.0, 0.0001)


func test_every_material_has_a_complete_profile() -> void:
	for material in ImpactCatalog.MATERIALS:
		var prof: Dictionary = ImpactCatalog.profile(material)
		for key in ["spark", "debris", "decal", "sfx", "volume_db", "light", "energy", "shake"]:
			ok(prof.has(key), "%s 缺 %s" % [material, key])
		ok(StringName(prof["spark"]) != &"", "%s 有火花种类" % material)
