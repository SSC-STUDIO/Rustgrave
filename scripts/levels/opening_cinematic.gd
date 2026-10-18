class_name OpeningCinematic
extends RefCounted
## 新游戏开场（约 44 秒，随时可跳过）。只在第一章醒来之前播一次，和醒来是同一条剧本。
## 继续、读档、死亡重进、已经醒过都不重播。不写结局。
## opening_seen 与 wake 在整段结束或跳过时一起点上；abort 两点都不点。
##
## 前 3 分钟的可读性由这一段铺：每个专名第一次出现就地解释（文本在
## ChapterText.OPENING），其余是画面钉字幕的短句。分镜（秒，按步骤估算 ~44）：
##   0.0  处境  你趴在冷余烬巢旁，锈片剥落，死亡动画倒放撑起身体，剑杵进地里
##   2.8  「剑先锈了。核里还有人。」
##   5.0  专名四拍  镜头退后到巢与坟  「那座誓叫炉约：烧名字换灯，立了二百年。」
##        「立誓的那批人，叫守炉人。」「守炉人造过很多具净化偶——刮锈的人偶。」
##        「你不是被选中的；你是最后一具，自己先锈透了。」（坟群依次冒灰）
##  13.0  伊尔两拍  「伊尔从渣里捡回你，嵌核进剑，点亮你。」
##        「你听见的是回声——她封进核之前的话。」
##  16.5  名字  「名字刻在剑上，烧进铁里，人就回不来。」
##  19.0  时间线四拍  「炉心是城下的大炉膛，一百年前熄了。」→「残芯是炉心最后一口火封成的核。」
##        →「最后一百年，灯靠残芯当灯芯。」→「灯越来越暗。她把核从座上取下。」
##  26.0  异象  地下一声钟，镜头沿走廊往东推  「钟响了一声。底下有人在数。」
##  29.3  目标两拍  走廊尽头空炉座的光跳两下，刽子手立在门后
##        「带剑里的残芯到炉心，替名字问火一句。」「这火该不该还？」
##  33.4  阻碍  「刽子手守着炉座。他发过誓。」
##  35.4  章节卡（2.6 秒）；镜头在卡下切回你
##  38.0  交还操作；脚边火星与巢边余火先响，队列清空后底部一行移动提示，第一次输入后消失
##  45.0  全段预算（按步骤估算 ~44）
##
## 演出原则：同一信息尽量用画面讲，字幕只补画面说不了的。「核里有人」靠火星从剑背
## 应声而起（bell_ring fx），「坟在数人」靠每座坟依次冒灰（grave_answer），「炉座空着」
## 靠镜头推近时空炉座的光（heart_pulse + glow），「目标」则让刽子手真的立在门后 ——
## 玩家先看见他要打谁，字幕才落到「问火一句」。钟声在走廊尽头先应一次
## （_heart_echo），把坟群和炉座说成同一个地方；交接不是又一段字幕，是巢边余火、
## 脚边火星和一次真正的输入解锁。
## 用到的 Director 步骤：lock unlock wait tableau caption cam_focus cam_release
## letterbox sfx fx。新 fx id：rust_flake plant bell_ring。

const FLAG := "opening_seen"
const WAKE_FLAG := "wake"
static var CHAPTER: String = ChapterText.title_of("level01")
const CARD_SECONDS := 2.6
## 整段（不跳过）的预算。测试按步骤估算，不许超。
const MAX_SECONDS := 45.0
## 低于这个时长就说明被删成了幻灯片：前 3 分钟的可读性靠这 45 秒铺。
const MIN_SECONDS := 40.0

## 顺序 = 处境、誓约/守炉人/净化偶（四拍）、伊尔与回声（两拍）、名字、时间线四拍、
## 异象、目标两拍、阻碍。文本单一源在 ChapterText.OPENING。
static var LINES: Array[String] = ChapterText.opening_lines()

const KNIGHT_FALLBACK := Vector2(96, 320)
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
## 第一拍推得更近：趴着的骑士只有 40px 宽，2.0 倍下在 640 视野里太小，
## 观众第一眼读不出「这里躺着个人」。2.35 倍下骑士与插在地上的巨剑占满画面中部。
const ZOOM_CLOSE := 2.35
const ZOOM_WIDE := 1.4
const ZOOM_ARRIVE := 1.25
## 巨剑插在骑士左侧（世界 x 偏移，朝右）。剑宽 34px，落在 53..87，
## 避开 40..89 的大灌木右缘与 101 起的路牌牌面，也压在趴姿身体的外侧下缘。
const PLANTED_SWORD_OFFSET := Vector2(-24.0, 0.0)
## 倒放死亡动画：先趴着不动一会儿，再撑起来。
const HOLD_FRAMES := 6
const RISE_FPS := 8.0
## 异象拍的坟声顺序：近的坟先应，越远越迟，最后一笔留给牌坊下的新坟。
## 眼前目标拍：残芯跳第二下的间隔，和镜头推近的时长对齐。
const HEART_SECOND_BEAT := 0.55
## 走廊尽头的回应时刻（相对 pan 起点）。镜头走到一半多一点时，残芯的暖光
## 先在远处亮一下、钟再低低地响一次：底下数人的东西就是镜头要去的地方。
## 等到 `_arrive` 再正式跳两下，远处那一下只是先应声。
const ECHO_AT := 0.58

static var _active := false
static var _knight: Variant
static var _nest: Variant
static var _dolly: Node2D
static var _pan: Tween
static var _echo: Tween
static var _rise: FrameAnimSprite
static var _hidden: FrameAnimSprite
## 开场把巨剑从背上摘下来插进土里；起身 / 跳过 / abort 都要把它收回去并还原背剑。
static var _planted: Sprite2D
static var _carrier: Greatsword
## 剧本自然结束或被跳过后，等队列真正清空再交还操作提示：
## 若后面还压着一段过场，提示不能先闪出来又被它盖掉。
static var _pending_handoff := false


## True while the new-game opening owns the Director (the skip prompt says 跳过开场
## only then; every other skippable beat says 跳过).
static func is_active() -> bool:
	return _active


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
## 结尾不写「向东」两个字，交给刚看完的镜头 —— 走廊尽头的光已经指了路。
static func move_prompt() -> String:
	if TouchInput.wants_overlay():
		return "左侧触控板移动 · 右侧按键跳跃"
	return "%s / %s 移动 · %s 跳跃" % [
		Settings.key_label(&"move_left"), Settings.key_label(&"move_right"),
		Settings.key_label(&"jump"),
	]


## 处境 → 誓约/守炉人/净化偶（四拍）→ 伊尔与回声（两拍）→ 名字（一拍）→ 时间线/残芯/灯（四拍）
## → 异象 → 目标（两拍）→ 阻碍 → 章节卡。每个专名第一次出现就带白话。
## 没有第二段醒来，一次跳过结束整条。带 tag 的步骤由 _on_step 挂上镜头 / 动画 / 坟的回应。
static func steps() -> Array:
	var knight: Variant = _knight if _knight != null else KNIGHT_FALLBACK
	var card := ChapterLevel.chapter_card(CHAPTER, CARD_SECONDS)
	card["tag"] = "card"
	return [
		{"kind": "lock"},
		{"kind": "cam_focus", "target": knight, "zoom": ZOOM_CLOSE, "duration": 0.12, "tag": "rouse"},
		{"kind": "fx", "id": "rust_flake", "target": knight, "seconds": 0.5},
		{"kind": "sfx", "id": "land", "db": -14.0},
		{"kind": "wait", "seconds": 0.6},
		{"kind": "sfx", "id": "step", "db": -12.0},
		{"kind": "fx", "id": "rust_flake", "target": knight, "seconds": 0.5},
		{"kind": "wait", "seconds": 1.0},
		{"kind": "fx", "id": "plant", "target": knight, "seconds": 0.1, "tag": "stand"},
		{"kind": "sfx", "id": "land", "db": -8.0},
		# 处境：剑里的火星替「核里还有人」作证，字幕只是钉一下。
		{"kind": "caption", "text": LINES[0], "hold": 1.6},
		{"kind": "wait", "seconds": 0.3},
		# 专名首现就地解释：炉约=誓约、守炉人=立誓那批人、净化偶=刮锈人偶。
		{"kind": "caption", "text": LINES[1], "hold": 1.4},
		{"kind": "caption", "text": LINES[2], "hold": 1.3, "tag": "pullback"},
		# 镜头退到坟群：你也不过是其中一座。
		{"kind": "caption", "text": LINES[3], "hold": 1.3, "tag": "grave_row"},
		{"kind": "wait", "seconds": 0.5},
		# 动机与回声：她只求你带她问一次；你听见的是她封进核之前的回声。
		{"kind": "caption", "text": LINES[4], "hold": 1.5},
		{"kind": "caption", "text": LINES[5], "hold": 1.4},
		{"kind": "wait", "seconds": 0.3},
		# 名字：刻在剑上、烧进铁里就回不来。
		{"kind": "caption", "text": LINES[6], "hold": 1.4},
		{"kind": "wait", "seconds": 0.5},
		# 时间线四拍：炉心 → 残芯 → 灯靠残芯当灯芯 → 如今灯暗、她把核取下。
		{"kind": "caption", "text": LINES[7], "hold": 1.4, "tag": "world"},
		{"kind": "caption", "text": LINES[8], "hold": 1.3},
		{"kind": "caption", "text": LINES[9], "hold": 1.2},
		{"kind": "caption", "text": LINES[10], "hold": 1.3},
		{"kind": "wait", "seconds": 0.5},
		# 异象：地下一声钟，镜头沿着坟群往东推。
		{"kind": "sfx", "id": "bell_toll", "tag": "toll"},
		{"kind": "fx", "id": "bell_ring", "target": knight, "seconds": 0.0},
		{"kind": "caption", "text": LINES[11], "hold": 1.3, "tag": "anomaly"},
		{"kind": "wait", "seconds": 0.8},
		# 代价：还火的人自己也要进炉（送剑=你散成铁），在目标之前钉住。
		{"kind": "caption", "text": LINES[12], "hold": 1.5},
		{"kind": "wait", "seconds": 0.3},
		# 目标两拍：把残芯带到炉心，替名字问火一句「这火该不该还？」。
		# 这一拍带 line_forge，截图夹具按 tag 认它，不按第几句认。
		{"kind": "caption", "text": LINES[13], "hold": 1.5, "tag": "line_forge"},
		{"kind": "caption", "text": LINES[14], "hold": 1.3},
		{"kind": "wait", "seconds": 0.3},
		# 阻碍：玩家先看见刽子手立在门后，字幕才说他守着什么。
		{"kind": "caption", "text": LINES[15], "hold": 1.4, "tag": "obstacle"},
		{"kind": "wait", "seconds": 0.3},
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
	_pending_handoff = false
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
			# 冷墓里只有他身边这一点暖：趴着的剪影先从背景里"浮"出来，
			# 再让剑把他钉在画面里（剑已种在脚边，这里只补一层地雾光）。
			var world := GameContext.world_root(_knight_node())
			if world != null:
				CineFx.glow_pulse(world, _knight_pos() + Vector2(-10.0, -6.0),
						Color(1.0, 0.55, 0.28, 0.30), 1.5, 0.9)
		"stand":
			_end_rise()
		"pullback":
			_begin_pullback()
		"grave_row":
			# 身份第二拍的字幕和坟群的回应同时起：文字晚半步，画面先说话。
			if is_instance_valid(_dolly):
				_grave_row_answer(_dolly.get_parent())
		"toll":
			_begin_pan()
		"card":
			Music.stinger(&"chapter")
			_begin_return()

## 剑先锈了：骑士趴在地上，死亡动画倒放成「撑起来」。真实精灵先藏起来，结束或中断时必还原。
## 巨剑这时候不在背上：它先他一步插进土里（`PLANTED_SWORD_OFFSET`），是这片墓园里
## 唯一还立着的东西 —— 第一眼就有「人和他的武器」这一对剪影，而不是地上的一堆暗色像素。
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
	_stage_planted_sword(player)


## 把巨剑从背上摘下来、插在骑士左侧脚边。返回的精灵由 `_end_rise` 收走。
static func _stage_planted_sword(player: Player) -> void:
	var carrier := player.visual.get_node_or_null("Greatsword") as Greatsword
	if carrier != null:
		_carrier = carrier
		carrier.hide_carried()
	if _planted != null and is_instance_valid(_planted):
		_planted.queue_free()
	_planted = null
	var world := GameContext.world_root(player)
	var host := world if world != null else player.get_parent() as Node2D
	if host == null:
		return
	_planted = Greatsword.spawn_planted(host,
			player.global_position + PLANTED_SWORD_OFFSET)
	if _planted != null:
		# 剑在骑士身后、地面之上：玩家 z=0，地面贴片多为 -1。
		_planted.z_index = -1


static func _start_rise() -> void:
	if is_instance_valid(_rise):
		_rise.set_process(true)


## 起身：收起插在地上的剑（他把剑从土里拔出来扛回背上），再恢复站立精灵。
static func _end_rise() -> void:
	if is_instance_valid(_planted):
		_planted.queue_free()
	_planted = null
	if is_instance_valid(_carrier):
		_carrier.show_carried()
	_carrier = null
	if is_instance_valid(_rise):
		_rise.queue_free()
	_rise = null
	if is_instance_valid(_hidden):
		_hidden.visible = true
	_hidden = null


## 身份：镜头离开骑士退到巢与坟，巢口冒一缕火星，暖光呼吸一次 —— 「歇脚的地方」。
## 退到位时骑士落在坟群边缘：他自己也是其中一座，字幕的「自己先锈透了」不用解释。
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


## 身份拍的最后一笔：骑士身边的几座坟依次回应，烘出「偶也是坟里的一座」。
## 由第二句字幕的 tag 触发（grave_row），镜头停稳的同时坟开始应。
static func _grave_row_answer(world: Node) -> void:
	if world == null:
		return
	var xs := grave_xs(world)
	var shown := 0
	for x in xs:
		if x > PULLBACK_X + 220.0:
			continue
		if shown >= 3:
			break
		shown += 1
		var beat := world.create_tween()
		beat.tween_interval(0.22 * float(shown - 1))
		beat.tween_callback(Director.play_fx.bind("grave_answer", Vector2(x, GROUND_Y)))


## 异象 + 目标：钟声落下，镜头沿走廊匀速往东，坟一座座冒灰回应；到头时残芯跳两下。
static func _begin_pan() -> void:
	var cam := _camera()
	if cam == null or not is_instance_valid(_dolly):
		return
	if _pan != null and _pan.is_valid():
		_pan.kill()
	if _echo != null and _echo.is_valid():
		_echo.kill()
	var from := _dolly.global_position
	var to := Vector2(PAN_END_X, from.y)
	# 钟响那一下镜头猛地拉开；位置靠 dolly 的缓动走，镜头只需紧跟（τ 小，滞后几十像素）。
	cam.focus(_dolly, 1.0, 0.25)
	var world := _dolly.get_parent()
	_pan = _dolly.create_tween()
	_pan.tween_property(_dolly, "global_position", to, PAN_SECONDS) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# 世界悬念：队伍走到一半，走廊尽头先应一声。不是目标灯在闪，是「数人」的
	# 那口钟在底下应了 —— 同一条钟声把坟群和残芯连成一个地方。
	_echo = _dolly.create_tween()
	_echo.tween_interval(PAN_SECONDS * ECHO_AT)
	_echo.tween_callback(_heart_echo)
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


## 走廊尽头的低回应：一声更远的钟、一团还没被镜头认出的暖光。
## 不给全屏闪白 —— 这里只是「下面有东西醒了」，真正的心跳留给 `_arrive`。
static func _heart_echo() -> void:
	if not is_instance_valid(_dolly):
		return
	var world := _dolly.get_parent()
	Sfx.play(&"bell_toll", 0.04, -17.0)
	if world != null:
		CineFx.glow_pulse(world, HEART + Vector2(0.0, -26.0),
				Color(1.0, 0.5, 0.24, 0.28), 2.2, 1.2)


static func _grave_answers(x: float) -> void:
	Director.play_fx("grave_answer", Vector2(x, GROUND_Y))

## 镜头到头：残芯的光跳两下（还没点燃，只是有东西在下面醒着），镜头缓缓推近。
## 门后立着刽子手的剪影：目标先被看见，字幕「你得把他们带下去」才有落点。
static func _arrive() -> void:
	var cam := _camera()
	if not is_instance_valid(_dolly):
		return
	var world := _dolly.get_parent()
	if cam != null:
		cam.focus(_dolly, ZOOM_ARRIVE, 0.7)
	_pulse_heart(world)
	# 第二下心跳压慢半拍：像隔着门传上来的，而不是同一盏灯在闪。
	var beats := _dolly.create_tween()
	beats.tween_interval(HEART_SECOND_BEAT)
	beats.tween_callback(_pulse_heart.bind(world))
	# 门后的剪影：玩家第一次看清「要去打谁」，比任何字幕都直接。
	var gate := _gate_pos()
	if gate != Vector2.INF:
		# 铁门在骑士靠近前先沉一下：目标不是一团光，是一扇得先过去的门。
		Sfx.play(&"gate", 0.04, -12.0)
		CineFx.glow_pulse(world, gate + Vector2(0.0, -30.0),
				Color(1.0, 0.45, 0.2, 0.34), 1.5, 1.1)
		Director.play_fx("shock_ring", gate + Vector2(0.0, -30.0))


## 刽子手门前的位置（Level01EastWing 把 BossGate 放在 x=1688，刽子手立在 x=1860）。
## 真实场景里问不到就退回常量；这一下只是冷光，不牵动战斗。
static func _gate_pos() -> Vector2:
	if is_instance_valid(_dolly):
		var world := _dolly.get_parent()
		if world != null:
			var props := world.get_node_or_null("Props") as Node2D
			if props != null:
				for child in props.get_children():
					if child is ExecutionerBoss and (child as Node2D).position.y > 300.0:
						return (child as Node2D).global_position
	return Vector2(1860.0, GROUND_Y)


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
	# 交还前的最后一拍：骑士自己抖落斗篷上的锈，脚边火星往上走，镜头跟着他。
	# 巢边的余火声音和 `hint_show` 分开，交接是「可以歇一口气」，不是又一段演出。
	var pos := _knight_pos()
	Director.play_fx("dust_puff", pos + Vector2(0.0, -40.0))
	Director.play_fx("ember_rise", pos + Vector2(0.0, -2.0))
	if is_instance_valid(_dolly):
		var world := _dolly.get_parent()
		if world != null:
			CineFx.glow_pulse(world, pos + Vector2(0.0, -24.0),
					Color(1.0, 0.6, 0.3, 0.32), 1.2, 0.9)
	Sfx.play(&"nest_rest", 0.04, -13.0)


## 镜头直接落回骑士身上，不从走廊尽头飞回来（跳过 / 中断 / 章节卡下的切回都用它）。
static func _snap_camera_to_knight(cam: GameCamera) -> void:
	cam.global_position = _knight_pos() + Vector2(0.0, -9.0)
	# 老镜头内部的平滑起点也要重置，否则它仍会从走廊尽头慢慢飞回来。
	if "_follow_inited" in cam:
		cam.set("_follow_inited", false)


# --- lifecycle ------------------------------------------------------------------

## 整条剧本走完或被跳过（不含 abort）：点旗、还原世界、交还音乐。
## 移动提示不在这里给 —— 等 `finished`，也就是队列真正清空之后再交还操作；
## 如果后面还压着一段过场，提示不能先闪出来又被它盖掉。
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
	_cleanup(true)
	Music.set_state(&"calm")
	_pending_handoff = true
	_knight = null
	_nest = null


## `finished` = 整条队列干完（自然结束 / 跳过），或 abort（死亡、切场）。
## 只有前者才交还移动提示；abort 把世界还原干净就走，不留下一次没看完的交接。
static func _on_finished() -> void:
	if _pending_handoff and not Director.is_aborting():
		_pending_handoff = false
		# 交接的那一下有个轻提示音：不看字幕也知道「现在轮到你了」。
		Sfx.play(&"hint_show", 0.04, -6.0)
		Director.show_hint(move_prompt())
	elif _active:
		_active = false
		if is_instance_valid(_dolly):
			var cam := _camera()
			if cam != null and not cam._focused:
				_snap_camera_to_knight(cam)
		Music.set_state(&"calm")
	_pending_handoff = false
	_cleanup()
	_knight = null
	_nest = null


## keep_finished: 剧本自然结束时留下 `finished` 钩子等队列清空；
## reset() / abort 的清理则把所有钩子都断开。
static func _cleanup(keep_finished: bool = false) -> void:
	if _pan != null and _pan.is_valid():
		_pan.kill()
	_pan = null
	if _echo != null and _echo.is_valid():
		_echo.kill()
	_echo = null
	if is_instance_valid(_dolly):
		_dolly.queue_free()
	_dolly = null
	_end_rise()
	# Hold released unless a Director script still owns the lock (skip → queued script).
	var player := _knight_node() as Player
	if player != null and not Director.is_input_locked():
		player.cutscene_locked = false
	_disconnect_hooks(keep_finished)


static func _disconnect_hooks(keep_finished: bool = false) -> void:
	if Director.step_started.is_connected(_on_step):
		Director.step_started.disconnect(_on_step)
	if Director.script_finished.is_connected(_on_script_finished):
		Director.script_finished.disconnect(_on_script_finished)
	if not keep_finished and Director.finished.is_connected(_on_finished):
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
