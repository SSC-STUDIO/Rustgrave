class_name OpeningCinematic
extends RefCounted
## 新游戏开场（约 13 秒，随时可跳过）。只在第一章醒来之前播一次，和醒来是同一条剧本。
## 继续、读档、死亡重进、已经醒过都不重播。不写结局。
## opening_seen 与 wake 在整段结束或跳过时一起点上；abort 两点都不点。
##
## 分镜（秒；Director 步骤 + 一个只管镜头的 dolly，坟的回应挂在 dolly 的时间线上）：
##   0.0  处境  骑士趴在冷余烬巢旁，锈片剥落，死亡动画倒放撑起身体，剑杵进地里
##   2.1  「剑先锈了。里面还有人。」
##   3.7  身份  镜头退后，巢口飘起一缕火星  「你不是被选中的。刮锈的偶，自己先锈透了。」
##   5.8  异象  地下一声钟：每座坟依次冒灰回应，镜头沿走廊往东推
##        「钟响了一声。底下有人在数。」
##   9.2  目标  走廊尽头残芯的光跳两下，刽子手立在门后  「炉还在下面。你得把他们带下去。」
##  10.3  章节卡；镜头在卡下切回骑士
##  13.0  交还操作；底部一行移动提示，第一次输入后消失
## 用到的 Director 步骤：lock unlock wait tableau caption cam_focus cam_release
## letterbox sfx fx。新 fx id：rust_flake plant bell_ring。

const FLAG := "opening_seen"
const WAKE_FLAG := "wake"
const CHAPTER := "锈墓・壹 — 腐液回廊"
const CARD_SECONDS := 2.2
## 整段（不跳过）的预算。测试按步骤估算，不许超。
const MAX_SECONDS := 14.0

## 顺序 = 处境、身份、异象、目标。
const LINES: Array[String] = [
	"剑先锈了。里面还有人。",
	"你不是被选中的。刮锈的偶，自己先锈透了。",
	"钟响了一声。底下有人在数。",
	"炉还在下面。你得把他们带下去。",
]

const KNIGHT_FALLBACK := Vector2(96, 290)
const NEST_FALLBACK := Vector2(150, 306)
## 残芯（Level01EastWing 放它的位置）。刽子手站在它前面 (1860, 320)。
const HEART := Vector2(2064, 292)
const GROUND_Y := 320.0
## 坟与碑的脚点 x。真实关卡从 GraveDecor / 碑取，取不到才用这一份。
const GRAVE_XS: Array[float] = [210.0, 360.0, 548.0, 596.0, 690.0, 1020.0, 1496.0, 1580.0, 1636.0]
const PULLBACK_X := 262.0
const PAN_END_X := 1990.0
const PAN_SECONDS := 3.4
const PULLBACK_SECONDS := 2.1
const ZOOM_CLOSE := 2.0
const ZOOM_WIDE := 1.4
const ZOOM_ARRIVE := 1.25
## 倒放死亡动画：先趴着不动一会儿，再撑起来。
const HOLD_FRAMES := 6
const RISE_FPS := 8.0

static var _active := false
static var _knight: Variant
static var _nest: Variant
static var _dolly: Node2D
static var _pan: Tween
static var _rise: FrameAnimSprite
static var _hidden: FrameAnimSprite


static func should_play() -> bool:
	if _active or SaveData.has_flag(FLAG):
		return false
	if SaveData.entering_from_checkpoint or SaveData.has_pending_spawn():
		return false
	if SaveData.has_flag(WAKE_FLAG):
		return false
	if SaveData.has_save():
		return false
	if SaveData.ending != "":
		return false
	return true


## 一行移动提示：键位取玩家当前绑定，触控设备改说触控板。
static func move_prompt() -> String:
	if TouchInput.wants_overlay():
		return "左侧触控板移动 · 右侧按键跳跃 · 往东走"
	return "%s / %s 移动 · %s 跳跃 · 往东走" % [
		Settings.key_label(&"move_left"), Settings.key_label(&"move_right"),
		Settings.key_label(&"jump"),
	]


## 处境 → 身份 → 异象 → 目标 → 章节卡。没有第二段醒来，一次跳过结束整条。
## 带 tag 的步骤由 _on_step 挂上镜头 / 动画 / 坟的回应。
static func steps() -> Array:
	var knight: Variant = _knight if _knight != null else KNIGHT_FALLBACK
	var card := ChapterLevel.chapter_card(CHAPTER, CARD_SECONDS)
	card["tag"] = "card"
	return [
		{"kind": "lock"},
		{"kind": "cam_focus", "target": knight, "zoom": ZOOM_CLOSE, "duration": 0.12, "tag": "rouse"},
		{"kind": "fx", "id": "rust_flake", "target": knight, "seconds": 0.5},
		{"kind": "sfx", "id": "land", "db": -14.0},
		{"kind": "wait", "seconds": 0.35},
		{"kind": "sfx", "id": "step", "db": -12.0},
		{"kind": "fx", "id": "rust_flake", "target": knight, "seconds": 0.5},
		{"kind": "wait", "seconds": 0.55},
		{"kind": "fx", "id": "plant", "target": knight, "seconds": 0.1, "tag": "stand"},
		{"kind": "sfx", "id": "land", "db": -8.0},
		{"kind": "caption", "text": LINES[0], "hold": 1.1},
		{"kind": "caption", "text": LINES[1], "hold": 1.2, "tag": "pullback"},
		{"kind": "sfx", "id": "bell_toll", "tag": "toll"},
		{"kind": "fx", "id": "bell_ring", "target": knight, "seconds": 0.0},
		{"kind": "caption", "text": LINES[2], "hold": 1.0},
		{"kind": "wait", "seconds": 1.0},
		{"kind": "caption", "text": LINES[3], "hold": 1.1},
		{"kind": "wait", "seconds": 0.15},
		card,
		{"kind": "tableau", "id": "world"},
		{"kind": "letterbox", "on": false, "duration": 0.4},
		{"kind": "cam_release", "duration": 0.45},
		{"kind": "unlock", "tag": "handoff"},
	]


## 播开场。标题那一次淡入负责揭开墓园，这里不再盖第二张黑。
## 结束或跳过之后点 opening_seen 和 wake。中途 abort 不点旗。
static func try_start(knight: Variant = null, nest: Variant = null) -> bool:
	if not should_play() or Director.playing:
		return false
	_active = true
	_knight = knight
	_nest = nest
	# 新游戏从零开始：上一局留下的「已看过」记忆不能压掉这一局的演出。
	StoryStage.forget()
	if not Director.step_started.is_connected(_on_step):
		Director.step_started.connect(_on_step)
	if not Director.script_finished.is_connected(_on_script_finished):
		Director.script_finished.connect(_on_script_finished)
	if not Director.finished.is_connected(_on_finished):
		Director.finished.connect(_on_finished)
	# The knight lies down and is held before the first frame is drawn, even when the
	# Director has to wait for a scene fade or an open pause menu to clear; the script
	# only starts once nothing is in the way (Director.play_when_clear).
	_begin_rise()
	var player := _knight_node() as Player
	if player != null:
		player.cutscene_locked = true
		var cam := _camera()
		if cam != null:
			# Already pushed in when the title fade lifts, so there is no zoom pop.
			cam.focus(player, ZOOM_CLOSE, 0.12)
	Director.play_when_clear(steps(), true)
	return true


static func reset() -> void:
	_cleanup()
	_active = false
	_knight = null
	_nest = null


## 坟 / 碑的回应时刻（相对 pan 起点，秒）。dolly 走正弦缓动，所以反解
## x(t) = x0 + D·(1 − cos(πt/T))/2，让每缕灰在镜头视野前沿碰到那座坟时冒起；
## 离得近的几座按 min_gap 错开，不挤在同一帧。
static func pan_times(xs: Array[float], x0: float, x1: float, pan_seconds: float,
		lead_px: float = 220.0, min_gap: float = 0.18) -> Array[float]:
	var times: Array[float] = []
	var span := x1 - x0
	if span <= 1.0:
		return times
	var prev := -min_gap
	for x in xs:
		if x > x1 + 40.0:
			continue
		var u := clampf(((x - lead_px) - x0) / span, 0.0, 1.0)
		var t := pan_seconds / PI * acos(1.0 - 2.0 * u)
		t = maxf(t, prev + min_gap)
		times.append(t)
		prev = t
	return times


## 世界里实际种下的坟（石碑、十字冢）和地面碑；取不到时退回常量。
static func grave_xs(world: Node) -> Array[float]:
	var xs: Array[float] = []
	if world != null:
		var layer := world.get_node_or_null("GraveDecor")
		if layer != null:
			for child in layer.get_children():
				var spr := child as Sprite2D
				if spr == null or spr.texture == null:
					continue
				var file := spr.texture.resource_path.get_file().to_lower()
				if file.begins_with("stone-") or file.begins_with("grave_cross"):
					var feet: Variant = spr.get_meta("feet", null)
					xs.append((feet as Vector2).x if feet is Vector2 else spr.position.x)
		for holder in [world.get_node_or_null("Props"), world]:
			if holder == null:
				continue
			for child in holder.get_children():
				if child is LoreStele and (child as Node2D).position.y > 300.0:
					xs.append((child as Node2D).position.x)
	if xs.is_empty():
		return GRAVE_XS.duplicate()
	xs.sort()
	return xs


# --- hooks ----------------------------------------------------------------------

static func _on_step(_index: int, step: Dictionary) -> void:
	if not _active:
		return
	match String(step.get("tag", "")):
		"rouse":
			Music.set_state(&"silent")
			_start_rise()
		"stand":
			_end_rise()
		"pullback":
			_begin_pullback()
		"toll":
			_begin_pan()
		"card":
			Music.stinger(&"chapter")
			_begin_return()


## 剑先锈了：骑士趴在地上，死亡动画倒放成「撑起来」。真实精灵先藏起来，结束或中断时必还原。
static func _begin_rise() -> void:
	var knight := _knight_node()
	if knight == null or not knight is Player or _rise != null:
		return
	var player := knight as Player
	var real := player.visual.get_node_or_null("KnightSprite") as FrameAnimSprite
	if real == null or not CharFrames.available(Player.KNIGHT_CHAR, "death"):
		return
	var frames: Array[Texture2D] = CharFrames.anim(Player.KNIGHT_CHAR, "death")
	if frames.size() < 4:
		return
	var seq: Array[Texture2D] = []
	for _i in HOLD_FRAMES:
		seq.append(frames[frames.size() - 1])
	for i in range(frames.size() - 1, -1, -1):
		seq.append(frames[i])
	var rise := FrameAnimSprite.new()
	rise.name = "OpeningRise"
	rise.register("rise", seq, RISE_FPS, false, Player.KNIGHT_POS)
	rise.play("rise", true)
	# Held on the prone frame until the script reaches its first step.
	rise.set_process(false)
	player.visual.add_child(rise)
	real.visible = false
	_rise = rise
	_hidden = real


static func _start_rise() -> void:
	if is_instance_valid(_rise):
		_rise.set_process(true)


static func _end_rise() -> void:
	if is_instance_valid(_rise):
		_rise.queue_free()
	_rise = null
	if is_instance_valid(_hidden):
		_hidden.visible = true
	_hidden = null


## 身份：镜头离开骑士退到巢与坟，巢口冒一缕火星，暖光呼吸一次 —— 「歇脚的地方」。
static func _begin_pullback() -> void:
	var cam := _camera()
	var knight := _knight_node()
	if cam == null or knight == null:
		return
	var world := GameContext.world_root(knight)
	if world == null:
		return
	_dolly = Node2D.new()
	_dolly.name = "OpeningDolly"
	world.add_child(_dolly)
	_dolly.global_position = knight.global_position
	cam.focus(_dolly, ZOOM_WIDE, 0.9)
	_pan = _dolly.create_tween()
	_pan.tween_property(_dolly, "global_position", Vector2(PULLBACK_X, knight.global_position.y),
			PULLBACK_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var nest := _nest_pos()
	Director.play_fx("ember_rise", nest)
	CineFx.glow_pulse(world, nest + Vector2(6.0, -24.0), Color(1.0, 0.62, 0.28, 0.5), 1.8, 1.3)


## 异象 + 目标：钟声落下，镜头沿走廊匀速往东，坟一座座冒灰回应；到头时残芯跳两下。
static func _begin_pan() -> void:
	var cam := _camera()
	if cam == null or not is_instance_valid(_dolly):
		return
	if _pan != null and _pan.is_valid():
		_pan.kill()
	var from := _dolly.global_position
	var to := Vector2(PAN_END_X, from.y)
	# 钟响那一下镜头猛地拉开；位置靠 dolly 的缓动走，镜头只需紧跟（τ 小，滞后几十像素）。
	cam.focus(_dolly, 1.0, 0.25)
	var world := _dolly.get_parent()
	_pan = _dolly.create_tween()
	_pan.tween_property(_dolly, "global_position", to, PAN_SECONDS) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# 并行的第二条时间线：坟的回应按 dolly 的位置排。
	var answers := _dolly.create_tween()
	var xs := grave_xs(world)
	var times := pan_times(xs, from.x, to.x, PAN_SECONDS)
	var clock := 0.0
	var slot := 0
	for x in xs:
		if x > to.x + 40.0 or slot >= times.size():
			continue
		var at: float = times[slot]
		slot += 1
		answers.tween_interval(maxf(at - clock, 0.0))
		clock = maxf(at, clock)
		answers.tween_callback(_grave_answers.bind(x))
	answers.tween_interval(maxf(PAN_SECONDS - clock, 0.0))
	answers.tween_callback(_arrive)


static func _grave_answers(x: float) -> void:
	Director.play_fx("grave_answer", Vector2(x, GROUND_Y))


## 镜头到头：残芯的光跳两下（还没点燃，只是有东西在下面醒着），镜头缓缓推近。
static func _arrive() -> void:
	var cam := _camera()
	if not is_instance_valid(_dolly):
		return
	var world := _dolly.get_parent()
	if cam != null:
		cam.focus(_dolly, ZOOM_ARRIVE, 0.7)
	_pulse_heart(world)
	var beats := _dolly.create_tween()
	beats.tween_interval(0.75)
	beats.tween_callback(_pulse_heart.bind(world))


static func _pulse_heart(world: Node) -> void:
	Sfx.play(&"forge_pulse")
	Director.play_fx("heart_pulse", HEART)
	CineFx.glow_pulse(world, HEART + Vector2(0.0, -26.0), Color(1.0, 0.5, 0.22, 1.0), 1.6, 3.0)
	CineFx.glow_pulse(world, HEART + Vector2(0.0, -30.0), Color(1.0, 0.78, 0.45, 0.8), 1.2, 1.5)


## 章节卡压暗世界之后，镜头不飞回去，直接切到骑士。
static func _begin_return() -> void:
	if not is_instance_valid(_dolly):
		return
	if _pan != null and _pan.is_valid():
		_pan.kill()
	_pan = _dolly.create_tween()
	_pan.tween_interval(0.5)
	_pan.tween_callback(_cut_to_knight)


static func _cut_to_knight() -> void:
	var cam := _camera()
	if cam == null:
		return
	_snap_camera_to_knight(cam)
	cam.focus(_knight_node() if _knight_node() != null else _knight_pos(), 1.0, 0.25)


## 镜头直接落回骑士身上，不从走廊尽头飞回来（跳过 / 中断 / 章节卡下的切回都用它）。
static func _snap_camera_to_knight(cam: GameCamera) -> void:
	cam.global_position = _knight_pos() + Vector2(0.0, -9.0)
	# 老镜头内部的平滑起点也要重置，否则它仍会从走廊尽头慢慢飞回来。
	if "_follow_inited" in cam:
		cam.set("_follow_inited", false)


# --- lifecycle ------------------------------------------------------------------

## 整条剧本走完或被跳过（不含 abort）：点旗、还原世界、交还音乐、给出移动提示。
static func _on_script_finished() -> void:
	if not _active:
		return
	_active = false
	SaveData.mark_flag(FLAG)
	SaveData.mark_flag(WAKE_FLAG)
	if is_instance_valid(_dolly):
		# Skipped while the camera was out on the corridor: put it back on the knight now.
		var cam := _camera()
		if cam != null and not cam._focused:
			_snap_camera_to_knight(cam)
	_cleanup()
	Music.set_state(&"calm")
	_knight = null
	_nest = null
	Director.show_hint(move_prompt())


## abort（死亡、切场）只会走到这里：不点旗，同样把世界还原干净。
static func _on_finished() -> void:
	if not _active:
		_disconnect_hooks()
		return
	_active = false
	if is_instance_valid(_dolly):
		var cam := _camera()
		if cam != null and not cam._focused:
			_snap_camera_to_knight(cam)
	_cleanup()
	Music.set_state(&"calm")
	_knight = null
	_nest = null


static func _cleanup() -> void:
	if _pan != null and _pan.is_valid():
		_pan.kill()
	_pan = null
	if is_instance_valid(_dolly):
		_dolly.queue_free()
	_dolly = null
	_end_rise()
	# Hold released unless a Director script still owns the lock (skip → queued script).
	var player := _knight_node() as Player
	if player != null and not Director.is_input_locked():
		player.cutscene_locked = false
	_disconnect_hooks()


static func _disconnect_hooks() -> void:
	if Director.step_started.is_connected(_on_step):
		Director.step_started.disconnect(_on_step)
	if Director.script_finished.is_connected(_on_script_finished):
		Director.script_finished.disconnect(_on_script_finished)
	if Director.finished.is_connected(_on_finished):
		Director.finished.disconnect(_on_finished)


# --- lookups --------------------------------------------------------------------

static func _knight_node() -> Node2D:
	# 先 is_instance_valid：对已释放对象做 `is Node2D` 会 SCRIPT ERROR。
	if typeof(_knight) != TYPE_OBJECT or not is_instance_valid(_knight):
		return null
	return _knight as Node2D if _knight is Node2D else null


static func _knight_pos() -> Vector2:
	var node := _knight_node()
	if node != null:
		return node.global_position
	return _knight as Vector2 if typeof(_knight) == TYPE_VECTOR2 else KNIGHT_FALLBACK


static func _nest_pos() -> Vector2:
	if typeof(_nest) == TYPE_OBJECT and is_instance_valid(_nest) and _nest is Node2D:
		return (_nest as Node2D).global_position
	return _nest as Vector2 if typeof(_nest) == TYPE_VECTOR2 else NEST_FALLBACK


static func _camera() -> GameCamera:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.get_first_node_in_group("game_camera") as GameCamera
