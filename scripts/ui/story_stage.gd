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
## Text lives in ChapterText (single source); docs/story.md §7.
const CORE_VOICE := ChapterText.CORE_VOICE
const FIRST_CORE_LINE := ChapterText.FIRST_CORE_LINE

static var _seen: Dictionary = {}

var test_enabled := false
## 章间间幕执行器：挂在 StoryStage 下，跟着 Director 常驻、跨场景不销毁。
var transition: ChapterTransition


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
	# 章间间幕执行器挂在这里：Director 的子节点跨场景常驻，间幕不用每关重建。
	# 它自己连 chapter_started；本节点先连，所以硬复位总在间幕之前发生。
	transition = ChapterTransition.new()
	add_child(transition)


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


## 获得一枚核：戒指与冻帧先把「这不是普通战利品」演出来，字幕只念那句职称。
## 嵌进插座时再给一张紧凑的「新动词」卡：能力名由画面报，不再靠一行字幕解释。
## 没有骑士的场景（单元夹具）也能显示这张卡；镜头步骤则省略。
static func core_steps(player: Node2D, line: String, ability_name: String = "") -> Array:
	var card: Array = []
	if ability_name != "":
		card.append({"kind": "tableau", "id": "ability", "title": ability_name,
				"subtitle": "新 的 动 词", "seconds": 2.0})
	if player == null:
		var fixture: Array = [
			{"kind": "lock"},
			{"kind": "caption", "text": line, "hold": 1.3},
		]
		fixture.append_array(card)
		fixture.append({"kind": "unlock"})
		return fixture
	var steps: Array = [
		{"kind": "lock"},
		{"kind": "sfx", "id": "core_get"},
		{"kind": "cam_focus", "target": player, "zoom": 1.5, "duration": 0.3},
		{"kind": "fx", "id": "core_ring", "target": player, "seconds": 0.05},
		{"kind": "fx", "id": "freeze", "ms": 400, "seconds": 0.0},
		# 冻帧解开的瞬间：剑背上的插座亮一下，再开口说话。
		{"kind": "fx", "id": "ember_rise", "target": player, "seconds": 0.6},
		{"kind": "caption", "text": line, "hold": 1.3},
	]
	steps.append_array(card)
	steps.append({"kind": "cam_release", "duration": 0.4})
	steps.append({"kind": "unlock"})
	return steps


## 登场：先把竞技场交出来（1.05x），吼声与冲击环把体量压到画面上，
## 再往身上推近（1.2x）留一拍。名号卡由 boss_appeared 另画，不抢操作。
static func boss_intro_steps(boss: Node2D) -> Array:
	return [
		{"kind": "lock"},
		{"kind": "cam_focus", "target": boss, "zoom": 1.05, "duration": 0.3},
		{"kind": "sfx", "id": "boss_roar"},
		{"kind": "fx", "id": "boss_roar", "target": boss, "seconds": 0.35},
		{"kind": "cam_focus", "target": boss, "zoom": 1.2, "duration": 0.35},
		{"kind": "wait", "seconds": 0.35},
		{"kind": "cam_release", "duration": 0.4},
		{"kind": "unlock"},
	]


static func boss_defeat_steps(boss: Node2D, door: Node2D) -> Array:
	var steps: Array = [
		{"kind": "lock"},
		{"kind": "fx", "id": "slowmo", "ms": 700, "scale": 0.25, "seconds": 0.0},
		{"kind": "fx", "id": "shake", "px": 5.0, "ms": 420, "seconds": 0.0},
		{"kind": "cam_focus", "target": boss, "zoom": 1.3, "duration": 0.45},
		# 跪下的身子留一拍，让「他不会再起来了」先落地。
		{"kind": "wait", "seconds": 0.3},
	]
	if door != null:
		# 再把镜头交给门里的火 —— 下一站不用字幕交代。
		steps.append({"kind": "cam_focus", "target": door, "zoom": 1.0, "duration": 0.8})
		steps.append({"kind": "sfx", "id": "door_open"})
		steps.append({"kind": "fx", "id": "heart_pulse", "target": door, "seconds": 0.45})
		steps.append({"kind": "caption", "text": "门里的火亮了一下。", "hold": 1.2})
	steps.append({"kind": "cam_release", "duration": 0.4})
	steps.append({"kind": "unlock"})
	return steps


## 阶段变化：吼叫、相变光环与镜头推近，但镜头也锁一次 —— 玩家看清「它换了样子」，
## 才谈得上调整打法。约 2.6 秒，可跳过；Juice 的慢放/震屏仍受 Settings 缩放保护。
## 台词不在这里重复：Boss 自己的 announcement / 名号卡相数刻度已经把同一句话说完了。
static func phase_steps(boss: Node2D, line: String) -> Array:
	var steps: Array = [
		{"kind": "lock"},
		{"kind": "sfx", "id": "boss_roar", "db": -6.0},
		{"kind": "fx", "id": "phase_flash", "target": boss, "seconds": 0.35},
		{"kind": "cam_focus", "target": boss, "zoom": 1.25, "duration": 0.35},
		{"kind": "wait", "seconds": 0.25},
	]
	if line != "":
		steps.append({"kind": "caption", "text": line, "hold": 1.5})
	steps.append({"kind": "cam_release", "duration": 0.35})
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
	Director.play(core_steps(player, line, AbilityIds.display_name(rust.ability_id)), true)


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
	var boss := _find_boss()
	if boss == null or not StoryStage.once("boss_phase_%d_%s" % [phase, boss_name.replace(" ", "")]):
		return
	# The boss already announced the change in the HUD banner ("炉渣在……");
	# repeating it as a subtitle under the shot would be the same sentence twice.
	# CinematicPresentation also re-raises the nameplate with the new phase tick.
	Director.play(phase_steps(boss, ""), true)


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
	# A scene (re)load must not inherit a stale lock, hint, caption, letterbox or
	# camera from the one before it. `reset_view` is stronger than abort(): the bars
	# close in the same frame the new level appears, so the chapter card starts from
	# a clean composition and no old script can keep the new knight locked.
	Director.reset_view()


func _on_player_died() -> void:
	# Death wins over any live story beat: release the camera/caption/hint now, then
	# play the death cue over a clean screen. The player already calls abort() before
	# emitting, so this is normally idempotent.
	Director.reset_view()
	Music.stinger(&"death")
	Music.set_state(&"calm")


func _on_ending_chosen(kind: StringName) -> void:
	var stinger := ending_stinger(kind)
	if stinger == &"":
		return
	Director.hide_hint()
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
