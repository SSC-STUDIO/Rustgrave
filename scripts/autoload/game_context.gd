class_name GameContext
extends RefCounted
## The authored level owns physics and save paths; presentation owns screen UI.

const PRESENTATION_PATH := "res://scenes/ui/GamePresentation.tscn"
## First stage of the v4 ICEY-style node-tree campaign; also fallback when a save names an unknown scene.
const WORLD_PATH := "res://scenes/levels/Stage01_Graveyard.tscn"
const LEGACY_WORLD_PATH := "res://scenes/levels/Level01_Static.tscn"
const LEVEL02_PATH := "res://scenes/levels/Level02_Undercroft.tscn"

## Active 14-node campaign (9 main stages + 5 disobedience truth branches + hidden True Core).
const LEVELS := {
	"stage01": WORLD_PATH,
	"branch01": "res://scenes/levels/Branch01_CorpsePit.tscn",
	"stage02": "res://scenes/levels/Stage02_Conduit.tscn",
	"branch02": "res://scenes/levels/Branch02_DiscardPit.tscn",
	"stage03": "res://scenes/levels/Stage03_Cathedral.tscn",
	"branch03": "res://scenes/levels/Branch03_Archive.tscn",
	"stage04": "res://scenes/levels/Stage04_Workshop.tscn",
	"stage04b": "res://scenes/levels/Stage04b_RainGraveyard.tscn",
	"stage05": "res://scenes/levels/Stage05_BellFoundry.tscn",
	"branch04": "res://scenes/levels/Branch04_BellSummit.tscn",
	"stage06": "res://scenes/levels/Stage06_Ramparts.tscn",
	"branch05": "res://scenes/levels/Branch05_CliffStable.tscn",
	"stage07": "res://scenes/levels/Stage07_ForgeGate.tscn",
	"stage08_true": "res://scenes/levels/Stage08_TrueCore.tscn",
}

## 14-node campaign order matching NarrativeCatalog.NODE_ORDER.
const LEVEL_ORDER: Array[String] = [
	"stage01", "branch01", "stage02", "branch02", "stage03", "branch03",
	"stage04", "stage04b", "stage05", "branch04", "stage06", "branch05",
	"stage07", "stage08_true",
]

## StageRoomBuilder scripts driving each StageLevel scene.
const STAGE_SCRIPTS := {
	"stage01": "res://scripts/levels/stages/stage01_graveyard.gd",
	"branch01": "res://scripts/levels/stages/branch01_corpse_pit.gd",
	"stage02": "res://scripts/levels/stages/stage02_conduit.gd",
	"branch02": "res://scripts/levels/stages/branch02_discard_pit.gd",
	"stage03": "res://scripts/levels/stages/stage03_cathedral.gd",
	"branch03": "res://scripts/levels/stages/branch03_archive.gd",
	"stage04": "res://scripts/levels/stages/stage04_workshop.gd",
	"stage04b": "res://scripts/levels/stages/stage04b_rain_graveyard.gd",
	"stage05": "res://scripts/levels/stages/stage05_bellfoundry.gd",
	"branch04": "res://scripts/levels/stages/branch04_bell_summit.gd",
	"stage06": "res://scripts/levels/stages/stage06_ramparts.gd",
	"branch05": "res://scripts/levels/stages/branch05_cliff_stable.gd",
	"stage07": "res://scripts/levels/stages/stage07_forge_gate.gd",
	"stage08_true": "res://scripts/levels/stages/stage08_true_core.gd",
}

## Legacy linear scenes preserved so standalone smoke/combat tests continue loading cleanly.
const LEGACY_LEVELS := {
	"level01": LEGACY_WORLD_PATH,
	"level02": LEVEL02_PATH,
	"level02b": "res://scenes/levels/Level02b_SlagConduit.tscn",
	"level03": "res://scenes/levels/Level03_RustTown.tscn",
	"level04": "res://scenes/levels/Level04_Cathedral.tscn",
	"level04b": "res://scenes/levels/Level04b_Crypt.tscn",
	"level05": "res://scenes/levels/Level05_Workshop.tscn",
	"level06": "res://scenes/levels/Level06_NightGraveyard.tscn",
	"level07": "res://scenes/levels/Level07_BellTower.tscn",
	"level07b": "res://scenes/levels/Level07b_BellFoundry.tscn",
	"level08": "res://scenes/levels/Level08_SlagDepths.tscn",
	"level09": "res://scenes/levels/Level09_Ramparts.tscn",
	"level09b": "res://scenes/levels/Level09b_EmberwindCliffs.tscn",
	"level10": "res://scenes/levels/Level10_ForgeCore.tscn",
}

const LEGACY_LEVEL_ORDER: Array[String] = [
	"level01", "level02", "level02b", "level03", "level04", "level04b",
	"level05", "level06", "level07", "level07b", "level08", "level09",
	"level09b", "level10",
]

static func scene_for(id: String) -> String:
	if LEVELS.has(id):
		return String(LEVELS[id])
	if LEGACY_LEVELS.has(id):
		return String(LEGACY_LEVELS[id])
	return ""

## Maps legacy chapter ids to their corresponding v4 stage node id.
const LEGACY_TO_STAGE := {
	"level01": "stage01",
	"level02": "stage02",
	"level02b": "stage02",
	"level03": "stage03",
	"level04": "stage03",
	"level04b": "stage03",
	"level05": "stage04",
	"level06": "stage04b",
	"level07": "stage05",
	"level07b": "stage05",
	"level08": "stage06",
	"level09": "stage06",
	"level09b": "stage06",
	"level10": "stage07",
}

## ChapterLayout scripts for legacy data-driven chapters (level02b+).
const LAYOUTS := {
	"level02b": "res://scripts/levels/chapters/level02b_layout.gd",
	"level03": "res://scripts/levels/chapters/level03_layout.gd",
	"level04": "res://scripts/levels/chapters/level04_layout.gd",
	"level04b": "res://scripts/levels/chapters/level04b_layout.gd",
	"level05": "res://scripts/levels/chapters/level05_layout.gd",
	"level06": "res://scripts/levels/chapters/level06_layout.gd",
	"level07": "res://scripts/levels/chapters/level07_layout.gd",
	"level07b": "res://scripts/levels/chapters/level07b_layout.gd",
	"level08": "res://scripts/levels/chapters/level08_layout.gd",
	"level09": "res://scripts/levels/chapters/level09_layout.gd",
	"level09b": "res://scripts/levels/chapters/level09b_layout.gd",
	"level10": "res://scripts/levels/chapters/level10_layout.gd",
}

## 竞技场等模式场景不是战役关卡（is_world_scene 保持 false，存档不收它们），
## 但仍要走 640×360 表现层，否则会把窗口当成世界视口。
const MODE_SCENES: Array[String] = [
	"res://scenes/levels/Arena_Duel.tscn",
]


## The main-line stage after `id` in campaign progression, or "" for branch / final nodes.
static func next_level_id(id: String) -> String:
	var spec := NarrativeCatalog.node_spec(id)
	if not spec.is_empty() and String(spec.get("kind", "main")) == "main":
		for child_id in spec.get("children", []):
			var c_spec := NarrativeCatalog.node_spec(String(child_id))
			if String(c_spec.get("kind", "")) == "main":
				return String(child_id)
		return ""
	var li := LEGACY_LEVEL_ORDER.find(id)
	if li >= 0:
		return "" if li + 1 >= LEGACY_LEVEL_ORDER.size() else LEGACY_LEVEL_ORDER[li + 1]
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
	return LEVELS.values().has(path) or LEGACY_LEVELS.values().has(path)


static func is_mode_scene(path: String) -> bool:
	return MODE_SCENES.has(path)


## Save-namespace id for a level scene path; "" for legacy Level01 and for unknown
## scenes (unit-test hosts), which keep the legacy bare paths.
static func level_id(path: String) -> String:
	for id in LEVELS:
		if LEVELS[id] == path:
			return id
	for id in LEGACY_LEVELS:
		if LEGACY_LEVELS[id] == path and id != "level01":
			return id
	return ""


static func level_id_of(node: Node) -> String:
	var world := world_root(node)
	if world == null:
		return ""
	if world is StageLevel and (world as StageLevel).stage_id != "":
		return (world as StageLevel).stage_id
	if world.scene_file_path == "":
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
	if is_world_scene(path) or is_mode_scene(path):
		pending_world_path = path
		return PRESENTATION_PATH
	return path
