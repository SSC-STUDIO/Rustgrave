class_name OpeningCinematic
extends RefCounted
## 新游戏开场。只在第一章醒来之前播一次。
## 继续、读档、死亡重进、已经醒过都不重播。不写结局，不点章节旗。

const FLAG := "opening_seen"

const LINES: Array[String] = [
	"剑先锈了。里面还有人。",
	"刮锈的偶被丢在墓地。自己也锈透了。",
	"炉还在下面。你得把他们带下去。",
]

static var _active := false
static var _on_done: Callable


static func should_play() -> bool:
	if _active or SaveData.has_flag(FLAG):
		return false
	if SaveData.entering_from_checkpoint or SaveData.has_pending_spawn():
		return false
	if SaveData.has_flag("wake"):
		return false
	if SaveData.has_save():
		return false
	if SaveData.ending != "":
		return false
	return true


static func steps() -> Array:
	return [
		{"kind": "lock"},
		{"kind": "letterbox", "on": true, "duration": 0.4},
		{"kind": "tableau", "id": "relic"},
		{"kind": "sfx", "id": "gate"},
		{"kind": "wait", "seconds": 0.8},
		{"kind": "caption", "text": LINES[0], "hold": 1.7},
		{"kind": "tableau", "id": "grave"},
		{"kind": "fx", "id": "ash_fall", "seconds": 0.85},
		{"kind": "caption", "text": LINES[1], "hold": 1.75},
		{"kind": "tableau", "id": "furnace"},
		{"kind": "sfx", "id": "insert"},
		{"kind": "wait", "seconds": 0.65},
		{"kind": "caption", "text": LINES[2], "hold": 1.85},
		{"kind": "tableau", "id": "world"},
		{"kind": "wait", "seconds": 0.7},
		{"kind": "unlock"},
	]


## 播开场。结束或跳过之后点 opening_seen，再调用 on_done（第一章用来接醒来）。
## 中途 abort（死亡、切场）不点旗、不调用 on_done。
static func try_start(on_done: Callable = Callable()) -> bool:
	if not should_play() or Director.playing:
		return false
	_active = true
	_on_done = on_done
	if not Director.finished.is_connected(_on_finished):
		Director.finished.connect(_on_finished)
	# 标题进关时淡入还盖着屏幕。已经在淡就不重开一次黑。
	if not Director.is_fading():
		Director.fade_in(0.6)
	Director.play(steps(), true)
	return true


static func reset() -> void:
	_active = false
	_on_done = Callable()
	if Director.finished.is_connected(_on_finished):
		Director.finished.disconnect(_on_finished)


static func _on_finished() -> void:
	if not _active:
		return
	var aborted := Director.is_aborting()
	_active = false
	var done := _on_done
	_on_done = Callable()
	if not aborted:
		SaveData.mark_flag(FLAG)
		if done.is_valid():
			done.call()
	if Director.finished.is_connected(_on_finished):
		Director.finished.disconnect(_on_finished)
