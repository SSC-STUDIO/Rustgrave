class_name Level01StoryBeats
extends Node
## One-shot Level01 Director scripts. Listens to GameEvents + east-wing signals.
## Every beat goes through StoryStage.once(): the flag lives on SaveData, and the
## stage also remembers it for the session, so a death reload (which rewinds the
## flags to the last save) never replays a cutscene the player already watched.
## Core pickup / insert staging is shared with every other chapter (StoryStage).

const Opening := preload("res://scripts/levels/opening_cinematic.gd")
const LEVEL_ID := "level01"

var _host: Node
var _player: Player
var _boss: ExecutionerBoss
var _bound := false


func bind(host: Node, player: Player, boss: ExecutionerBoss) -> void:
	_host = host
	_player = player
	_boss = boss
	if _bound:
		return
	_bound = true
	GameEvents.toxin_changed.connect(_on_toxin_story)
	GameEvents.core_acquired.connect(_on_core_story)
	GameEvents.parried.connect(_on_parry_story)


func set_boss(boss: ExecutionerBoss) -> void:
	_boss = boss


func _exit_tree() -> void:
	if not _bound:
		return
	_bound = false
	if GameEvents.toxin_changed.is_connected(_on_toxin_story):
		GameEvents.toxin_changed.disconnect(_on_toxin_story)
	if GameEvents.core_acquired.is_connected(_on_core_story):
		GameEvents.core_acquired.disconnect(_on_core_story)
	if GameEvents.parried.is_connected(_on_parry_story):
		GameEvents.parried.disconnect(_on_parry_story)


func try_wake() -> void:
	# After the knight exists, once per load: Continue and death reloads included.
	GameEvents.chapter_started.emit(LEVEL_ID)
	if SaveData.entering_from_checkpoint or SaveData.has_pending_spawn() or SaveData.has_flag("wake"):
		if not Director.playing:
			GameEvents.announcement.emit("锈墓・壹 — 腐液回廊")
		return
	# 全新一局只播开场这一条（含章节卡）。旗标由开场在结束或跳过时点上。
	var nest: Node = null
	if _host != null and is_instance_valid(_host):
		nest = _host.get_node_or_null("Props/EmberNest")
	if Opening.try_start(_player, nest):
		return
	# 继续、已有存档、已有结局：不重播开场，也不再接一段醒来。
	SaveData.mark_flag("wake")
	if not Director.playing:
		GameEvents.announcement.emit("锈墓・壹 — 腐液回廊")


## 刽子手：铁门沉下、炉火涌起，镜头先把整座竞技场（门 + 他）交出来，再推近。
## 名号卡由 boss_appeared 另画，不抢操作。约 4.8 秒，按一次确认键整段跳过。
## 画面先讲清楚三件事（门是关的、他有多大、斧上还有火），字幕才落誓词。
## 进场那一下的炉火涌光由 Level01EastWing 在 boss_intro_started 上点火。
func on_boss_gate(body: Node) -> void:
	if SaveData.has_flag("boss_dead") or not body is Player:
		return
	if _boss == null or not is_instance_valid(_boss):
		return
	if not StoryStage.once("boss_intro"):
		return
	var gate: Node2D = _boss
	Director.play([
		{"kind": "lock"},
		{"kind": "sfx", "id": "gate"},
		# 铁门砸下的余响里，炉火在炉口涌起来：先给竞技场，再给对手。
		{"kind": "wait", "seconds": 0.18},
		{"kind": "cam_focus", "target": Vector2(Level01EastWing.ARENA_CENTER_X - 80.0,
				Level01EastWing.ARENA_HEARTH_Y - 24.0), "zoom": 1.0, "duration": 0.45},
		{"kind": "sfx", "id": "boss_roar"},
		{"kind": "fx", "id": "boss_roar", "target": gate, "seconds": 0.3},
		{"kind": "cam_focus", "target": gate, "zoom": 1.2, "duration": 0.4},
		{"kind": "fx", "id": "phase_flash", "target": gate, "seconds": 0.35},
		# 一拍静默：让他先站着，别急着解释。
		{"kind": "wait", "seconds": 0.35},
		{"kind": "caption", "text": "刽子手还守着残芯。他发过誓：谁来点炉，谁就先被斩。", "hold": 1.3},
		{"kind": "cam_release", "duration": 0.4},
		{"kind": "unlock"},
	], true)


## 刽子手跪下：慢放 + 一震，镜头先给跪倒的他，再移到残芯的光上。约 4.6 秒，可跳过。
## 倒下不是终点：镜头离开他、停在残芯上，玩家已经知道下一站在哪。
func on_boss_slain() -> void:
	var heart: ForgeHeart = null
	if _host != null:
		heart = _host.get_node_or_null("Props/ForgeHeart") as ForgeHeart
	if heart:
		heart.unlock()
	if SaveData.has_flag("boss_dead"):
		return
	Level01EastWing.mark_executioner_slain()
	Music.set_state(&"calm")
	Music.stinger(&"boss_down")
	Director.play([
		{"kind": "lock"},
		{"kind": "fx", "id": "slowmo", "ms": 700, "scale": 0.25, "seconds": 0.0},
		{"kind": "fx", "id": "shake", "px": 5.0, "ms": 400, "seconds": 0.0},
		{"kind": "cam_focus", "target": _boss, "zoom": 1.3, "duration": 0.4},
		# 跪着的他留一拍，再让镜头自己走到残芯上 —— 目标的交接全在镜头里。
		{"kind": "wait", "seconds": 0.3},
		{"kind": "cam_focus", "target": heart, "zoom": 1.0, "duration": 0.7},
		{"kind": "sfx", "id": "forge_pulse"},
		{"kind": "fx", "id": "heart_pulse", "target": heart, "seconds": 0.4},
		{"kind": "caption", "text": "残芯还在跳。熄掉它，或者答应往下问一次。", "hold": 1.4},
		{"kind": "cam_release", "duration": 0.4},
		{"kind": "unlock"},
	], true)


func _on_toxin_story(current: float, _maximum: float) -> void:
	if current <= 0.0 or not StoryStage.once("toxin"):
		return
	var pool: Node = null
	if _host != null:
		pool = _host.get_node_or_null("Props/ToxinPool")
	Director.play([
		{"kind": "lock"},
		# 先让镜头看见那片橙色，再让字幕说它曾是冷却剂。
		{"kind": "cam_focus", "target": pool, "duration": 0.4},
		{"kind": "fx", "id": "ash_fall", "target": pool, "seconds": 0.5},
		{"kind": "caption", "text": "它曾是冷却剂。吃肺，也把记忆淬进剑里。", "hold": 1.6},
		{"kind": "cam_release"},
		{"kind": "unlock"},
	], true)


## 第一枚核（全游戏第一次拾取）。每一枚核各一次的演出在 StoryStage，这里只是第一章的
## 入口：StoryStage 先收到信号时这里不会重复；没有骑士的场景（测试）退化成只有字幕。
func _on_core_story(core: Resource) -> void:
	var stage := Director.get_node_or_null("StoryStage") as StoryStage
	if stage != null:
		stage.stage_pickup(core, true)


func _on_parry_story(_bolt: Node, _by: Node) -> void:
	if not StoryStage.once("parry"):
		return
	# 弹回去的火替玩家说话：镜头只轻轻推一下，字幕钉一句。
	Director.play([
		{"kind": "lock"},
		{"kind": "cam_focus", "target": _player, "zoom": 1.35, "duration": 0.3},
		{"kind": "fx", "id": "shock_ring", "target": _player, "seconds": 0.1},
		{"kind": "caption", "text": "打回去的是他们的火。锈被你炼过一次。", "hold": 1.6},
		{"kind": "cam_release", "duration": 0.35},
		{"kind": "unlock"},
	], true)
