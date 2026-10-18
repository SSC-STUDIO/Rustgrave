extends TestCase
## Tester smoke probe: instantiate every level scene headlessly and report
## engine errors, missing landmarks, and obviously broken wiring.

const LEVELS := [
	"res://scenes/levels/Level01_Static.tscn",
	"res://scenes/levels/Level02_Undercroft.tscn",
	"res://scenes/levels/Level03_RustTown.tscn",
	"res://scenes/levels/Level04_Cathedral.tscn",
	"res://scenes/levels/Level05_Workshop.tscn",
	"res://scenes/levels/Level06_NightGraveyard.tscn",
	"res://scenes/levels/Level07_BellTower.tscn",
	"res://scenes/levels/Level08_SlagDepths.tscn",
	"res://scenes/levels/Level09_Ramparts.tscn",
	"res://scenes/levels/Level10_ForgeCore.tscn",
]


func test_every_level_loads_without_errors() -> void:
	for path in LEVELS:
		var packed: PackedScene = load(path)
		ok(packed != null, "scene exists: %s" % path.get_file())
		if packed == null:
			continue
		var level: Node = packed.instantiate()
		add_child(level)
		await flush(30)
		# Player must exist and be in the tree.
		var player := level.get_tree().get_first_node_in_group("player")
		ok(player != null, "%s spawns a player" % path.get_file())
		# Camera must exist.
		var cam := level.find_child("GameCamera", true, false)
		ok(cam != null, "%s has a camera" % path.get_file())
		level.queue_free()
		await get_tree().process_frame


func test_every_level_has_a_hud() -> void:
	for path in LEVELS:
		var packed: PackedScene = load(path)
		if packed == null:
			continue
		var level: Node = packed.instantiate()
		add_child(level)
		await flush(30)
		var hud := level.find_child("HUD", true, false)
		ok(hud != null, "%s has a HUD" % path.get_file())
		level.queue_free()
		await get_tree().process_frame


func test_level_backdrops_exist() -> void:
	for path in LEVELS:
		var packed: PackedScene = load(path)
		if packed == null:
			continue
		var level: Node = packed.instantiate()
		add_child(level)
		await flush(30)
		var backdrop := level.find_child("ParallaxBackdrop", true, false)
		var theme_bd := level.find_child("ThemeBackdrop", true, false)
		var front := level.find_child("ParallaxForeground", true, false)
		ok(backdrop != null or theme_bd != null,
				"%s has some parallax backdrop" % path.get_file())
		level.queue_free()
		await get_tree().process_frame
