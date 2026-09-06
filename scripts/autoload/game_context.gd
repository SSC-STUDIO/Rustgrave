class_name GameContext
extends RefCounted
## The authored level owns physics and save paths; presentation owns screen UI.

const PRESENTATION_PATH := "res://scenes/ui/GamePresentation.tscn"
## First level; also the fallback whenever a save names an unknown scene.
const WORLD_PATH := "res://scenes/levels/Level01_Static.tscn"
const LEVEL02_PATH := "res://scenes/levels/Level02_Undercroft.tscn"
## Every authored level keyed by its save id, in play order. Level01 predates
## ids, so its save paths stay bare ("Props/EmberNest"); later levels prefix
## theirs ("level02:Props/EmberNest") so identical node names never collide.
const LEVELS := {
	"level01": WORLD_PATH,
	"level02": LEVEL02_PATH,
	"level03": "res://scenes/levels/Level03_RustTown.tscn",
	"level04": "res://scenes/levels/Level04_Cathedral.tscn",
	"level05": "res://scenes/levels/Level05_Workshop.tscn",
	"level06": "res://scenes/levels/Level06_NightGraveyard.tscn",
	"level07": "res://scenes/levels/Level07_BellTower.tscn",
	"level08": "res://scenes/levels/Level08_SlagDepths.tscn",
	"level09": "res://scenes/levels/Level09_Ramparts.tscn",
	"level10": "res://scenes/levels/Level10_ForgeCore.tscn",
}
const LEVEL_ORDER: Array[String] = [
	"level01", "level02", "level03", "level04", "level05",
	"level06", "level07", "level08", "level09", "level10",
]
## ChapterLayout scripts for the data-driven chapters (level03+).
const LAYOUTS := {
	"level03": "res://scripts/levels/chapters/level03_layout.gd",
	"level04": "res://scripts/levels/chapters/level04_layout.gd",
	"level05": "res://scripts/levels/chapters/level05_layout.gd",
	"level06": "res://scripts/levels/chapters/level06_layout.gd",
	"level07": "res://scripts/levels/chapters/level07_layout.gd",
	"level08": "res://scripts/levels/chapters/level08_layout.gd",
	"level09": "res://scripts/levels/chapters/level09_layout.gd",
	"level10": "res://scripts/levels/chapters/level10_layout.gd",
}


## The level after `id` in play order, or "" for the last one.
static func next_level_id(id: String) -> String:
	var i := LEVEL_ORDER.find(id)
	if i < 0 or i + 1 >= LEVEL_ORDER.size():
		return ""
	return LEVEL_ORDER[i + 1]
## Level the presentation shell instantiates next. route_scene() sets it.
static var pending_world_path: String = WORLD_PATH
static var _blocked_through_frame: int = -1


static func tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func world_root(node: Node = null) -> Node:
	var cursor := node
	while cursor != null:
		if cursor.is_in_group("game_world"):
			return cursor
		cursor = cursor.get_parent()
	var scene_tree := tree()
	if scene_tree == null:
		return null
	var worlds := scene_tree.get_nodes_in_group("game_world")
	if worlds.size() == 1:
		return worlds[0]
	# Standalone unit fixtures have no presentation wrapper.
	return node.get_parent() if node != null else scene_tree.current_scene


static func world_scene_path(node: Node = null) -> String:
	var world := world_root(node)
	return world.scene_file_path if world != null and world.scene_file_path != "" else WORLD_PATH


static func is_world_scene(path: String) -> bool:
	return LEVELS.values().has(path)


## Save-namespace id for a level scene path; "" for Level01 and for unknown
## scenes (unit-test hosts), which keep the legacy bare paths.
static func level_id(path: String) -> String:
	for id in LEVELS:
		if LEVELS[id] == path and id != "level01":
			return id
	return ""


static func level_id_of(node: Node) -> String:
	var world := world_root(node)
	if world == null or world.scene_file_path == "":
		return ""
	return level_id(world.scene_file_path)


static func world_effects(node: Node = null) -> Node:
	var world := world_root(node)
	if world == null:
		return null
	var effects := world.get_node_or_null("WorldEffects")
	if effects == null:
		effects = Node2D.new()
		effects.name = "WorldEffects"
		world.add_child(effects)
	return effects


static func ui_host(node: Node = null) -> Node:
	var scene_tree := tree()
	if scene_tree != null:
		var presentation := scene_tree.get_first_node_in_group("game_presentation")
		if presentation != null:
			return presentation.get_node("UiHost")
	return world_root(node)


static func suppress_gameplay_input() -> void:
	_blocked_through_frame = Engine.get_physics_frames() + 1


static func gameplay_input_enabled() -> bool:
	var scene_tree := tree()
	return scene_tree != null and not scene_tree.paused \
			and not Director.is_input_locked() and not Director.choice_hold \
			and Engine.get_physics_frames() > _blocked_through_frame


## Authored levels always load inside the presentation shell (640×360 world
## viewport). Remember which level so GamePresentation can instantiate it.
static func route_scene(path: String) -> String:
	if is_world_scene(path):
		pending_world_path = path
		return PRESENTATION_PATH
	return path
