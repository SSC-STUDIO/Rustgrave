extends CanvasLayer
## 分镜播放器：把 Storyboards 的一段分镜（序章 / 章间 / 结局 / 滚动字幕）演出来。
##
## 层 13：在 HUD（10）、遮幅（11）、字幕（12）之上，在跳过按钮（16）与暂停菜单（20+）之下。
## 绑定到 PresentationMetrics（1280×720 的设计单位，和字幕/HUD 同一块内容矩形）；
## 画面是 640×360 的 StoryboardStage 放大 2 倍，台词、名牌、标题是原生 UI 字。
##
## 两种跳过口径（见 docs/cinematics.md）：
##   skip_all_on_accept（章间）  一次 Enter / 点击就跳过整段，和旧章间一样；
##   逐句（序章 / 结局 / 滚动字幕） Enter 先写完这句、再推下一句；按住 Enter 或点「跳过」跳整段。
## 输入宽限：开始后 0.35 秒内的 Enter 不算（刚按下的交互键 / 菜单确认键不能一帧把它跳过）。
##
## Director 驱动：Director 的 board 步骤调用 play_board，Enter 由 Director.skip_step 转发
## press_accept；暂停菜单 / suspend 时整个播放器冻住。replay=true 是故事页回放：自己读输入，
## 暂停中也能播（此时 Esc = 跳过整段）。结束时发 board_finished(id, completed)；
## completed=false 表示被 abort（切场 / 死亡），不记「看过」。

signal board_started(id: String)
signal board_finished(id: String, completed: bool)
signal shot_started(index: int, shot: Dictionary)
signal line_started(index: int, text: String)

const Boards := preload("res://scripts/data/storyboards.gd")
const StageScript := preload("res://scripts/ui/storyboard_stage.gd")

const LAYER := 13
## 故事页回放（replay）从暂停菜单里点开，菜单在 20–22 层：回放必须盖在它上面（结局选择在 25）。
const REPLAY_LAYER := 24
const UI_SIZE := Vector2(1280.0, 720.0)
const OPEN_SEC := 0.3
const CLOSE_SEC := 0.45
const FAST_CLOSE_SEC := 0.22
const CUT_SEC := 0.25
const TAIL_SEC := 0.5
const REVEAL_SEC := 0.3
const INPUT_GRACE := 0.35
const HOLD_SKIP_SEC := 0.8
const CREDITS_FONT := 30
## 字幕条贴在屏下沿，约 80px 高，半透明渐变，不再用一块悬空的实心底框。
const BAR_Y := 640.0
const BAR_H := 80.0

enum Phase { IDLE, OPEN, CUT_IN, TYPING, HOLD, TAIL, CUT_OUT, SCROLL, CLOSE }

var playing := false
var current_id := ""
var skip_all_on_accept := false
var replay := false
var phase: Phase = Phase.IDLE

var _root: Control
var _stage: Control
var _dark: ColorRect
var _panel: Control
var _text: Label
var _who_panel: Control
var _who: Label
var _title: Label
var _skip_btn: Button
var _credits: Label

var _shots: Array = []
var _shot: Dictionary = {}
var _shot_index := -1
var _lines: Array = []
var _line_index := -1
var _full := ""
var _shown := 0.0
var _phase_t := 0.0
var _age := 0.0
var _hold := 0.0
var _hold_armed := false
var _closing_fast := false
var _reveal_left := 0.0
## 上一段分镜刚在黑幕上收完、这一段紧接着开（结局 → 滚动字幕）：接着黑幕走，不闪出场景。
var _chained := false
var _credits_h := 0.0


func _ready() -> void:
	name = "StoryboardPlayer"
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()
	WorldClock.isolate_ui_layer(self)
	PresentationMetrics.bind_layer(self)


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "BoardRoot"
	_root.size = UI_SIZE
	_root.custom_minimum_size = UI_SIZE
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_root_input)
	add_child(_root)

	var floor_rect := ColorRect.new()
	floor_rect.name = "Floor"
	floor_rect.color = Color.BLACK
	floor_rect.size = UI_SIZE
	floor_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(floor_rect)

	_stage = StageScript.new()
	_stage.scale = Vector2(2.0, 2.0)
	_root.add_child(_stage)

	_credits = UiKit.label("", &"AnnounceLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_credits.name = "Credits"
	_credits.autowrap_mode = TextServer.AUTOWRAP_OFF
	_credits.size = Vector2(UI_SIZE.x, 100.0)
	_credits.add_theme_font_size_override("font_size", CREDITS_FONT)
	_credits.add_theme_constant_override("line_spacing", 14)
	_credits.add_theme_color_override("font_color", UiKit.EMBER_ASH)
	_credits.visible = false
	_root.add_child(_credits)

	_panel = Control.new()
	_panel.name = "BoardPanel"
	_panel.position = Vector2(0.0, BAR_Y)
	_panel.size = Vector2(UI_SIZE.x, BAR_H)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	_root.add_child(_panel)
	var wash := TextureRect.new()
	wash.name = "Wash"
	wash.texture = _caption_wash()
	wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	_panel.add_child(wash)
	var rule := ColorRect.new()
	rule.name = "Rule"
	rule.position = Vector2(0.0, 0.0)
	rule.size = Vector2(UI_SIZE.x, 1.0)
	rule.color = Color(0.72, 0.42, 0.22, 0.35)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(rule)
	_text = UiKit.label("", &"AnnounceLabel", HORIZONTAL_ALIGNMENT_LEFT)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.position = Vector2(40.0, 6.0)
	_text.size = Vector2(UI_SIZE.x - 80.0, BAR_H - 10.0)
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_text.max_lines_visible = 2
	_text.clip_text = true
	_panel.add_child(_text)
	# 名牌画在渐变之上。实时拼的脚在屏上 y≈572，条顶在 640，脚和火种不会被字压住。
	_who_panel = Control.new()
	_who_panel.name = "BoardWho"
	_who_panel.position = Vector2(36.0, 16.0)
	_who_panel.size = Vector2(140.0, 48.0)
	_who_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_who_panel.visible = false
	_panel.add_child(_who_panel)
	_who = UiKit.label("", &"AnnounceLabel", HORIZONTAL_ALIGNMENT_LEFT)
	_who.position = Vector2.ZERO
	_who.size = Vector2(140.0, 48.0)
	_who.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_who_panel.add_child(_who)

	_title = UiKit.label("", &"AnnounceLabel", HORIZONTAL_ALIGNMENT_LEFT)
	_title.name = "BoardTitle"
	_title.position = Vector2(40.0, 26.0)
	_title.size = Vector2(720.0, 36.0)
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_color", Color(UiKit.ASH.r, UiKit.ASH.g, UiKit.ASH.b, 0.85))
	_root.add_child(_title)

	_skip_btn = Button.new()
	_skip_btn.name = "BoardSkip"
	_skip_btn.text = "跳过 ▸▸"
	_skip_btn.theme = UiKit.extras_theme()
	_skip_btn.theme_type_variation = &"SettingsButton"
	_skip_btn.focus_mode = Control.FOCUS_NONE
	_skip_btn.position = Vector2(1106.0, 20.0)
	_skip_btn.size = Vector2(134.0, 44.0)
	_skip_btn.pressed.connect(skip_all)
	_root.add_child(_skip_btn)

	_dark = ColorRect.new()
	_dark.name = "Dark"
	_dark.color = Color(0.0, 0.0, 0.0, 0.0)
	_dark.size = UI_SIZE
	_dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dark)


## 字幕条的竖向渐变：顶上全透，到底部才压暗，字能读、插图底边不被一块实心黑吃掉。
func _caption_wash() -> Texture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.42, 1.0])
	grad.colors = PackedColorArray([
		Color(0.02, 0.01, 0.02, 0.0),
		Color(0.015, 0.008, 0.018, 0.62),
		Color(0.01, 0.006, 0.014, 0.92),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 4
	tex.height = 80
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	return tex


# ------------------------------------------------------------------ public ------

func board_active() -> bool:
	return playing


## Director 的跳过按钮文案。
func skip_label(touch: bool) -> String:
	if skip_all_on_accept:
		return "点此跳过" if touch else "Enter · 跳过"
	return "点此继续" if touch else "Enter · 下一句"


## 开始一段分镜。没有这段分镜返回 false。opts: skip_all / replay。
func play_board(id: String, opts: Dictionary = {}) -> bool:
	var shots := Boards.shots(id)
	if shots.is_empty():
		return false
	if playing:
		_finish(false)
	# 前一段刚在黑幕上收完（_dark 满格、层还显示着）→ 这一段从黑幕接着走。
	_chained = visible and _dark.color.a >= 0.99
	current_id = id
	_shots = shots
	skip_all_on_accept = bool(opts.get("skip_all", id.begins_with("interlude_")))
	replay = bool(opts.get("replay", false))
	layer = REPLAY_LAYER if replay else LAYER
	playing = true
	_age = 0.0
	_hold = 0.0
	_hold_armed = false
	_closing_fast = false
	_shot_index = -1
	_shot = {}
	_lines = []
	_reveal_left = 0.0
	# 从场景淡入到黑（OPEN 阶段里 0→1）；接在上一段后面时直接是黑的。
	_root.modulate.a = 1.0 if _chained else 0.0
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_title.text = Boards.title_of(id)
	_skip_btn.visible = not skip_all_on_accept
	_panel.visible = false
	_who_panel.visible = false
	_credits.visible = false
	_stage.set_black(1.0)
	_dark.color.a = 0.0
	visible = true
	board_started.emit(id)
	_set_phase(Phase.OPEN)
	return true


## Enter / 点击。章间：整段跳过；其余：写完这句 → 推下一句。
func press_accept() -> void:
	if not playing or _age < INPUT_GRACE:
		return
	if skip_all_on_accept:
		skip_all()
		return
	match phase:
		Phase.TYPING:
			_shown = float(_full.length())
			_text.text = _full
			_set_phase(Phase.HOLD)
		Phase.HOLD:
			_next_line()
		Phase.TAIL:
			_after_shot()
		Phase.SCROLL:
			skip_all()


## 跳过整段（算看过）。
func skip_all() -> void:
	if not playing or phase == Phase.CLOSE:
		return
	_closing_fast = true
	_panel.visible = false
	_who_panel.visible = false
	_set_phase(Phase.CLOSE)


## 立刻中断（切场 / 死亡 / 返回标题），不记看过。幂等。
func abort() -> void:
	if playing:
		_finish(false)
	_hide_now()


## 当前镜头的构成（测试读）。
func stage_info() -> Dictionary:
	return (_stage.call("info") as Dictionary) if _stage != null else {}


## 开演后走过的时间（暂停时不走；测试读它验「暂停冻结」）。
func age() -> float:
	return _age


func current_shot_index() -> int:
	return _shot_index


func current_line() -> String:
	return _full


func is_revealing() -> bool:
	return _reveal_left > 0.0


# ------------------------------------------------------------------ driver ------

func _frozen() -> bool:
	if replay:
		return false
	return Director.is_suspended() or get_tree().paused


func _process(delta: float) -> void:
	if not playing:
		if _reveal_left > 0.0:
			_reveal_left -= delta
			_root.modulate.a = clampf(_reveal_left / REVEAL_SEC, 0.0, 1.0)
			if _reveal_left <= 0.0:
				_hide_now()
		return
	if _frozen():
		return
	_age += delta
	_phase_t += delta
	_tick_hold(delta)
	_stage.call("tick", delta)
	match phase:
		Phase.OPEN:
			# 整块画面（黑底）从场景上淡入；接在上一段后面时本来就是黑的，不用淡。
			if not _chained:
				_root.modulate.a = clampf(_phase_t / OPEN_SEC, 0.0, 1.0)
			if _phase_t >= OPEN_SEC:
				_root.modulate.a = 1.0
				_begin_shot(0)
		Phase.CUT_IN:
			_stage.call("set_black", 1.0 - clampf(_phase_t / CUT_SEC, 0.0, 1.0))
			if _phase_t >= CUT_SEC:
				_stage.call("set_black", 0.0)
				_enter_shot_body()
		Phase.TYPING:
			var speed := clampf(float(Settings.value(&"subtitle_speed", 1.0)), 0.6, 1.5)
			_shown += Boards.CHARS_PER_SEC * speed * delta
			var n := mini(_full.length(), int(_shown))
			_text.text = _full.substr(0, n)
			if n >= _full.length():
				_set_phase(Phase.HOLD)
		Phase.HOLD:
			if _phase_t >= Boards.LINE_HOLD:
				_next_line()
		Phase.TAIL:
			if _phase_t >= TAIL_SEC:
				_after_shot()
		Phase.CUT_OUT:
			_stage.call("set_black", clampf(_phase_t / CUT_SEC, 0.0, 1.0))
			if _phase_t >= CUT_SEC:
				_begin_shot(_shot_index + 1)
		Phase.SCROLL:
			var seconds := maxf(float(_shot.get("seconds", Boards.CREDITS_SECONDS)), 1.0)
			var p := clampf(_phase_t / seconds, 0.0, 1.0)
			_credits.position.y = lerpf(UI_SIZE.y, -_credits_h, p)
			if p >= 1.0:
				_after_shot()
		Phase.CLOSE:
			var total := FAST_CLOSE_SEC if _closing_fast else CLOSE_SEC
			_dark.color.a = clampf(_phase_t / total, 0.0, 1.0)
			if _phase_t >= total:
				_finish(true)


func _set_phase(p: Phase) -> void:
	phase = p
	_phase_t = 0.0


## 按住 Enter 跳过整段：开始后必须先松开一次，才开始计时（菜单确认键还按着的情况）。
func _tick_hold(delta: float) -> void:
	if skip_all_on_accept or phase == Phase.CLOSE:
		return
	var down := Input.is_action_pressed("ui_accept")
	if not down:
		_hold_armed = true
		_hold = 0.0
		return
	if not _hold_armed or _age < INPUT_GRACE:
		return
	_hold += delta
	if _hold >= HOLD_SKIP_SEC:
		_hold = 0.0
		skip_all()


func _begin_shot(index: int) -> void:
	if index >= _shots.size():
		_set_phase(Phase.CLOSE)
		return
	_shot_index = index
	_shot = _shots[index] as Dictionary
	_lines = _shot.get("lines", []) as Array
	_line_index = -1
	_full = ""
	_text.text = ""
	_panel.visible = false
	_who_panel.visible = false
	_stage.call("show_shot", _shot, Boards.shot_seconds(_shot))
	_stage.call("set_black", 1.0)
	_credits.visible = false
	shot_started.emit(index, _shot)
	_set_phase(Phase.CUT_IN)


func _enter_shot_body() -> void:
	if _shot.has("scroll"):
		_credits.text = "\n".join(PackedStringArray(_shot["scroll"] as Array))
		_credits.size = Vector2(UI_SIZE.x, 100.0)
		_credits_h = _credits.get_combined_minimum_size().y
		_credits.position = Vector2(0.0, UI_SIZE.y)
		_credits.visible = true
		_set_phase(Phase.SCROLL)
		return
	_next_line()


func _next_line() -> void:
	_line_index += 1
	if _line_index >= _lines.size():
		_panel.visible = false
		_who_panel.visible = false
		_set_phase(Phase.TAIL)
		return
	var parts := ChapterText.split_speaker(String(_lines[_line_index]))
	_full = parts[1]
	_shown = 0.0
	_text.text = ""
	_who.text = parts[0]
	var named := parts[0] != ""
	_who_panel.visible = named
	_who.add_theme_color_override("font_color",
			UiKit.EMBER if parts[0] == "伊尔" else UiKit.EMBER_ASH)
	# 有名牌时台词让到右边，没有就铺满渐变条。
	_text.position.x = 184.0 if named else 40.0
	_text.size.x = UI_SIZE.x - _text.position.x - 40.0
	_panel.visible = true
	line_started.emit(_line_index, String(_lines[_line_index]))
	_set_phase(Phase.TYPING)


## 一个镜头讲完：还有下一个就黑切过去，没有就收尾。
func _after_shot() -> void:
	if _shot_index + 1 < _shots.size():
		_panel.visible = false
		_who_panel.visible = false
		_set_phase(Phase.CUT_OUT)
	else:
		_set_phase(Phase.CLOSE)


func _finish(completed: bool) -> void:
	if not playing:
		return
	playing = false
	phase = Phase.IDLE
	var id := current_id
	if completed and not replay and id != "":
		SaveData.mark_flag(Boards.seen_flag(id))
	_panel.visible = false
	_who_panel.visible = false
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if completed and visible:
		# 给 Director 的下一步让路：黑幕在原地淡出，不再挡输入。
		_reveal_left = REVEAL_SEC
	else:
		_hide_now()
	board_finished.emit(id, completed)


func _hide_now() -> void:
	_reveal_left = 0.0
	visible = false
	if _root != null:
		_root.modulate.a = 1.0
		_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _dark != null:
		_dark.color.a = 0.0


# ------------------------------------------------------------------- input ------

func _on_root_input(event: InputEvent) -> void:
	if not playing:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			press_accept()
			_root.accept_event()


## 故事页回放（replay）没有 Director 转发，自己读键：Enter 推进，Esc 跳过整段。
func _unhandled_input(event: InputEvent) -> void:
	if not playing or not replay:
		return
	if event.is_action_pressed("ui_accept"):
		press_accept()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		skip_all()
		get_viewport().set_input_as_handled()
