class_name StoryStage
extends Node
## Game-wide story staging: the beats that belong to every chapter, not one level.
## Core pickup / socket insert, boss intro / phase change / defeat, chapter start,
## ending music. A child of the Director autoload, so it outlives scene changes.
##
## Music.* and Sfx.* are contract calls (silent until the audio package supplies
## them). Screen shake and flashes go through Juice, which applies the player's
## accessibility scales. Forced beats are remembered per session as well as in the
## save flags: a death reload rewinds the flags to the last save, but a cutscene
## the player has already sat through must not come back.
##
## The session memory is cleared when a new game starts (OpeningCinematic.try_start)
## and whenever the Director fades to the title screen (Director.fade_to), so New Game
## and Continue always start from the save alone.
##
## Inert inside the test runner unless a test sets `test_enabled`.

## Chapter-1 gate staging lives in Level01StoryBeats (the oath, the shield).
const BOSS_SCRIPTED_ELSEWHERE: Array[String] = ["刽子手"]
## What each core says the first time it is seated. One line, never repeated.
## Same text as docs/story.md; the inventory banner must not repeat it.
const CORE_VOICE := {
	&"heat_forge": "窑匠：把火留在刃上。门会自己让开。",
	&"hookshot_tether": "系索匠：你很重。让世界过来。",
	&"ember_step": "余烬核：灰还能再跳一次。别问它从谁身上来。",
}
const FIRST_CORE_LINE := "这不是战利品。是一个还没说完的职称。"

static var _seen: Dictionary = {}

var test_enabled := false


## True the first time `key` is staged. The save flag is the truth; the session memory
## only fills the gap a death reload leaves (load_game() replaces the flags with the
## last save's). It counts only inside a real run — once the opening has set `wake` —
## so a stale entry can never leak into a fresh save or a test that cleared its flags.
static func once(key: String) -> bool:
	if SaveData.has_flag(key):
		return false
	if _seen.has(key) and SaveData.has_flag("wake"):
		SaveData.mark_flag(key)
		return false
	_seen[key] = true
	SaveData.mark_flag(key)
	return true


## A new game starts clean; nothing from the previous run may suppress its beats.
static func forget() -> void:
	_seen.clear()


static func seen_this_session(key: String) -> bool:
	return _seen.has(key)


func _ready() -> void:
	name = "StoryStage"
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameEvents.core_acquired.connect(_on_core_acquired)
	GameEvents.core_inserted.connect(_on_core_inserted)
	GameEvents.boss_intro_started.connect(_on_boss_intro)
	GameEvents.boss_phase_changed.connect(_on_boss_phase)
	GameEvents.boss_defeated.connect(_on_boss_defeated)
	GameEvents.chapter_started.connect(_on_chapter_started)
	GameEvents.player_died.connect(_on_player_died)
	GameEvents.ending_chosen.connect(_on_ending_chosen)


func live() -> bool:
	return test_enabled or not Director.is_test_runner()


# --- scripts (pure builders; tests read them) ----------------------------------

static func pickup_line(core: RustCore, first_ever: bool) -> String:
	var keys := "%s 或 %s" % [Settings.key_label(&"socket_1"), Settings.key_label(&"socket_2")]
	if first_ever:
		return "%s按 %s 嵌进剑里。" % [FIRST_CORE_LINE, keys]
	match String(core.id):
		"kiln_core":
			return "窑核。还烫着。按 %s 嵌进剑里。" % keys
		"tether_core":
			return "系核。缠着旧索。按 %s 嵌进剑里。" % keys
		"ember_core":
			return "余烬核。一撮灰。按 %s 嵌进剑里。" % keys
	return "%s。按 %s 嵌进剑里。" % [core.display_name, keys]


static func insert_line(core: RustCore) -> String:
	return String(CORE_VOICE.get(core.ability_id, ""))


## Push-in, ring, 0.4 s freeze, one caption, hand the lens back. About 3 s.
## With no knight in the scene (unit fixtures) only the caption survives.
static func core_steps(player: Node2D, line: String) -> Array:
	if player == null:
		return [
			{"kind": "lock"},
			{"kind": "caption", "text": line, "hold": 1.3},
			{"kind": "unlock"},
		]
	return [
		{"kind": "lock"},
		{"kind": "sfx", "id": "core_get"},
		{"kind": "cam_focus", "target": player, "zoom": 1.5, "duration": 0.3},
		{"kind": "fx", "id": "core_ring", "target": player, "seconds": 0.05},
		{"kind": "fx", "id": "freeze", "ms": 400, "seconds": 0.0},
		{"kind": "caption", "text": line, "hold": 1.3},
		{"kind": "cam_release", "duration": 0.4},
		{"kind": "unlock"},
	]


static func boss_intro_steps(boss: Node2D) -> Array:
	return [
		{"kind": "lock"},
		{"kind": "sfx", "id": "boss_roar"},
		{"kind": "cam_focus", "target": boss, "zoom": 1.2, "duration": 0.5},
		{"kind": "fx", "id": "boss_roar", "target": boss, "seconds": 0.5},
		{"kind": "wait", "seconds": 0.45},
		{"kind": "cam_release", "duration": 0.4},
		{"kind": "unlock"},
	]


static func boss_defeat_steps(boss: Node2D, door: Node2D) -> Array:
	var steps: Array = [
		{"kind": "lock"},
		{"kind": "fx", "id": "slowmo", "ms": 700, "scale": 0.25, "seconds": 0.0},
		{"kind": "fx", "id": "shake", "px": 5.0, "ms": 420, "seconds": 0.0},
		{"kind": "cam_focus", "target": boss, "zoom": 1.3, "duration": 0.45},
	]
	if door != null:
		steps.append({"kind": "cam_focus", "target": door, "zoom": 1.0, "duration": 0.8})
		steps.append({"kind": "sfx", "id": "door_open"})
		steps.append({"kind": "fx", "id": "heart_pulse", "target": door, "seconds": 0.45})
		steps.append({"kind": "caption", "text": "门里的火亮了一下。", "hold": 1.2})
	steps.append({"kind": "cam_release", "duration": 0.4})
	steps.append({"kind": "unlock"})
	return steps


static func phase_line(boss_name: String, _phase: int) -> String:
	if boss_name.contains("刽子手"):
		return "炉渣在他的斧上重新沸腾。"
	if boss_name.contains("梦魇") or boss_name.contains("无主"):
		return "梦魇的鬃毛烧成了白焰。"
	return "它换了一副样子。"


static func ending_stinger(kind: StringName) -> StringName:
	match kind:
		&"give":
			return &"ending_give"
		&"keep":
			return &"ending_keep"
		&"snuff":
			return &"ending_snuff"
	return &""


# --- listeners ------------------------------------------------------------------

func _on_core_acquired(core: Resource) -> void:
	stage_pickup(core, false)


## Stage the pickup beat for `core`, once per core. Level01StoryBeats also calls this
## with `force` (its first-core contract holds even where the stage is inert); whoever
## gets there second finds the beat already spent and does nothing.
func stage_pickup(core: Resource, force: bool = false) -> void:
	if not core is RustCore or not (force or live()):
		return
	var rust := core as RustCore
	if not StoryStage.once("stage_get_%s" % String(rust.id)):
		return
	var first_ever := StoryStage.once("core")
	Director.play(core_steps(_player(), pickup_line(rust, first_ever)), true)


func _on_core_inserted(core: Resource, _socket_index: int) -> void:
	if not core is RustCore:
		return
	Music.stinger(&"ability")
	if not live():
		return
	var rust := core as RustCore
	var line := insert_line(rust)
	var player := _player()
	if player == null or line == "" or not StoryStage.once("stage_ins_%s" % String(rust.id)):
		return
	StoryStage.once("insert")
	Director.play(core_steps(player, line), true)


func _on_boss_intro(boss_name: String) -> void:
	Music.set_state(&"boss")
	Music.stinger(&"boss_intro")
	if not live():
		return
	for tag in BOSS_SCRIPTED_ELSEWHERE:
		if boss_name.contains(tag):
			return
	var boss := _find_boss()
	if boss == null or not StoryStage.once("boss_intro_%s" % boss_name.replace(" ", "")):
		return
	Director.play(boss_intro_steps(boss), true)


func _on_boss_phase(boss_name: String, phase: int) -> void:
	# Red flash, slow-mo and shake are Juice calls: they honour the accessibility
	# scales and never lock input, so the fight stays live under them.
	Sfx.play(&"boss_roar", 0.05, -6.0)
	Juice.slow_mo(260, 0.2)
	Juice.shake(5.0, 360)
	Juice.flash(Color(0.9, 0.16, 0.1, 0.42), 240)
	if not live():
		return
	var caption := Director.caption()
	if caption != null:
		caption.enqueue(phase_line(boss_name, phase), 1.5)


func _on_boss_defeated() -> void:
	Music.set_state(&"calm")
	Music.stinger(&"boss_down")
	if not live():
		return
	# Chapter 1 stages its own defeat from the Executioner's slain signal.
	var player := _player()
	if player == null or GameContext.level_id_of(player) == "":
		return
	var boss := _find_boss()
	if not StoryStage.once("boss_down_%s" % GameContext.level_id_of(player)):
		return
	Director.play(boss_defeat_steps(boss, _find_door(player)), true)


func _on_chapter_started(_level_id: String) -> void:
	Music.set_state(&"calm")
	# A scene (re)load must not inherit a stale lock or hint from the one before it.
	Director.hide_hint()
	if not Director.playing and Director.is_input_locked():
		Director.abort()


func _on_player_died() -> void:
	Music.stinger(&"death")
	Music.set_state(&"calm")


func _on_ending_chosen(kind: StringName) -> void:
	var stinger := ending_stinger(kind)
	if stinger == &"":
		return
	Music.set_state(&"ending")
	Music.stinger(stinger)


# --- lookups --------------------------------------------------------------------

func _player() -> Player:
	var tree := get_tree()
	return tree.get_first_node_in_group("player") as Player if tree != null else null


## Bosses announce through announce()/is_announced(); no group of their own.
func _find_boss() -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("enemies"):
		if node is Node2D and node.has_method("announce") and node.has_method("is_announced"):
			return node as Node2D
	return null


func _find_door(from: Node) -> Node2D:
	var world := GameContext.world_root(from)
	if world == null:
		return null
	return _walk_for_door(world)


func _walk_for_door(node: Node) -> Node2D:
	if node is LevelExit and (node as LevelExit).ending_choice:
		return node as Node2D
	for child in node.get_children():
		var hit := _walk_for_door(child)
		if hit != null:
			return hit
	return null
