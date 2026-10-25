extends TestCase
## 每章（第一章除外，它有自己的东翼布局）在原地形上多一个专属机关，
## 并且仍然通过 LevelSanity。不要求移动被旧测试锁住的地面。

const LAYOUTS := {
	"level02": preload("res://scripts/levels/level02_layout.gd"),
	"level02b": preload("res://scripts/levels/chapters/level02b_layout.gd"),
	"level03": preload("res://scripts/levels/chapters/level03_layout.gd"),
	"level04": preload("res://scripts/levels/chapters/level04_layout.gd"),
	"level04b": preload("res://scripts/levels/chapters/level04b_layout.gd"),
	"level05": preload("res://scripts/levels/chapters/level05_layout.gd"),
	"level06": preload("res://scripts/levels/chapters/level06_layout.gd"),
	"level07": preload("res://scripts/levels/chapters/level07_layout.gd"),
	"level07b": preload("res://scripts/levels/chapters/level07b_layout.gd"),
	"level08": preload("res://scripts/levels/chapters/level08_layout.gd"),
	"level09": preload("res://scripts/levels/chapters/level09_layout.gd"),
	"level09b": preload("res://scripts/levels/chapters/level09b_layout.gd"),
	"level10": preload("res://scripts/levels/chapters/level10_layout.gd"),
}

const VARIANTS := {
	"level02": &"armored_scrapper",
	"level02b": &"swift_scrapper",
	"level03": &"armored_scrapper",
	"level04": &"scatter_spitter",
	"level04b": &"exploder_skeleton",
	"level05": &"armored_scrapper",
	"level06": &"exploder_skeleton",
	"level07": &"heavy_guard",
	"level07b": &"scatter_spitter",
	"level08": &"armored_scrapper",
	"level09": &"swift_scrapper",
	"level09b": &"swift_scrapper",
	"level10": &"scatter_spitter",
}

const SIGNATURE := {
	"level02": "Props/OverhaulBell",
	"level02b": "Props/SluiceSurge",
	"level03": "Props/StreetBell",
	"level04": "Props/NaveShock",
	"level04b": "Props/CandleMouth",
	"level05": "Platforms/BeltDeck",
	"level06": "Props/GraveMud",
	"level07": "Props/Clapper",
	"level07b": "Props/LadleFlame",
	"level08": "Props/SlagMouth",
	"level09": "Props/WallWind",
	"level09b": "Props/CliffEmber",
	"level10": "Props/CorePulse",
}


func setup() -> void:
	Director._set_lock(false)


func teardown() -> void:
	Director._set_lock(false)
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)


func test_each_later_chapter_keeps_a_sane_signature_hazard() -> void:
	for id in SIGNATURE:
		var host := _build(id)
		var problems := LevelSanity.check(host)
		eq(problems, [] as Array[String], "%s sanity: %s" % [id, " | ".join(problems)])
		ok(host.get_node_or_null(SIGNATURE[id]) != null, "%s signature %s" % [id, SIGNATURE[id]])
		var hazards := LevelSanity.hazards(host)
		ok(hazards.size() >= 1 and hazards.size() <= 16, "%s hazard count %d" % [id, hazards.size()])
		var lights := host.find_children("*", "PointLight2D", true, false).size()
		ok(lights <= 48, "%s light count %d" % [id, lights])
		_assert_variant(host, id)


func _build(id: String) -> Node2D:
	var host := Node2D.new()
	host.scene_file_path = String(GameContext.LEVELS[id])
	host.add_to_group("game_world")
	add_child(host)
	var layout = LAYOUTS[id].new()
	add_child(layout)
	layout.build(host)
	return host


func _assert_variant(host: Node2D, id: String) -> void:
	var variant := StringName(VARIANTS.get(id, &""))
	if variant == &"":
		return
	var base: StringName = EnemyVariants.preset(variant).get("base", &"")
	var enemies := host.get_node_or_null("Enemies")
	if enemies == null:
		return
	var present := false
	var applied := false
	for child in enemies.get_children():
		if EnemyVariants.kind_of(child) != base:
			continue
		present = true
		if String(child.get_meta("variant", "")) == String(variant):
			applied = true
	if present:
		ok(applied, "%s applies %s" % [id, variant])
