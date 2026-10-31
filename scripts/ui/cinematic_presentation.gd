extends CanvasLayer
## Director-owned presentation, below captions and above the world/HUD.
## Uses the Director clock: pause/suspend freezes blends, particles and prompts.

const Tableau := preload("res://scripts/ui/cinematic_tableau.gd")

## Rising-edge watch for the one-line control hint: first press after it appears hides it.
const HINT_ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"jump", &"attack", &"dash", &"interact", &"hookshot",
	&"socket_1", &"socket_2",
]
const HINT_FADE := 0.35
const BOSS_CARD_SECONDS := 2.6
const ABILITY_CARD_SECONDS := 2.0
## A phase tick that arrives after the nameplate timed out brings a short reminder
## card back, so the player still sees the count climb while the camera pushes in.
const PHASE_CARD_SECONDS := 1.8

var front
var back
var skip_button: Button
var hint_panel: PanelContainer
var hint_label: Label
var active_shot := ""
var _blend := 1.0
var _leaving := false
var _hint_age := 0.0
var _card_left := 0.0
var _hint_left := 0.0
var _hint_held: Dictionary = {}
## Last announced boss, kept after the nameplate times out: a phase change re-raises
## the same name with the new tick. Cleared by defeat and by a hard dismiss (abort).
var _boss_title := ""
var _boss_subtitle := ""
## 名号卡上沿的白话一行（ChapterText.boss_intro）；随名号一起记着，相变重举卡时再画。
var _boss_kicker := ""


func _ready() -> void:
	name = "CinematicPresentation"
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	WorldClock.isolate_ui_layer(self)
	PresentationMetrics.bind_layer(self)
	back = _make_canvas()
	front = _make_canvas()
	var prompt_layer := CanvasLayer.new()
	prompt_layer.layer = 16
	add_child(prompt_layer)
	WorldClock.isolate_ui_layer(prompt_layer)
	PresentationMetrics.bind_layer(prompt_layer)
	skip_button = Button.new()
	skip_button.name = "SkipCinematic"
	skip_button.text = "Enter · 继续"
	skip_button.position = Vector2(958, 610)
	skip_button.size = Vector2(286, 48)
	skip_button.focus_mode = Control.FOCUS_NONE
	skip_button.visible = false
	skip_button.pressed.connect(Director.skip_step)
	prompt_layer.add_child(skip_button)
	_build_hint(prompt_layer)
	Director.step_started.connect(_on_step)
	Director.finished.connect(_on_finished)
	GameEvents.boss_appeared.connect(_on_boss_appeared)
	GameEvents.boss_defeated.connect(_on_boss_defeated)
	GameEvents.boss_phase_changed.connect(_on_boss_phase)
	GameEvents.player_died.connect(hide_hint)


func _build_hint(layer: CanvasLayer) -> void:
	# A zero-height strip 118px above the bottom edge; the panel grows upward to fit.
	# It sits in the soil band under the knight's feet and clear of the HUD prompt.
	hint_panel = UiKit.panel(&"HudPanel")
	hint_panel.name = "MoveHint"
	hint_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint_panel.offset_top = -118.0
	hint_panel.offset_bottom = -118.0
	hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_panel.visible = false
	hint_label = UiKit.label("", &"PromptLabel", HORIZONTAL_ALIGNMENT_CENTER)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	hint_panel.add_child(hint_label)
	var root := Control.new()
	root.name = "HintRoot"
	root.size = Vector2(PresentationMetrics.UI_SIZE)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	root.add_child(hint_panel)


## One line over the world, up to `seconds` of unpaused play. First gameplay input,
## death, another cinematic, a scene fade or abort() all hide it.
func show_hint(text: String, seconds: float = 14.0) -> void:
	if hint_panel == null or text == "":
		return
	hint_label.text = text
	hint_panel.modulate.a = 0.0
	hint_panel.visible = true
	_hint_left = maxf(seconds, 0.1)
	_hint_held.clear()
	for action in HINT_ACTIONS:
		_hint_held[action] = InputMap.has_action(action) and Input.is_action_pressed(action)


func hide_hint() -> void:
	_hint_left = 0.0
	_hint_held.clear()
	if hint_panel != null:
		hint_panel.visible = false


func hint_visible() -> bool:
	return hint_panel != null and hint_panel.visible and _hint_left > 0.0


func _tick_hint(delta: float) -> void:
	if _hint_left <= 0.0:
		return
	if Director.playing or Director.is_fading() or Director.choice_hold:
		hide_hint()
		return
	hint_panel.modulate.a = move_toward(hint_panel.modulate.a, 1.0, delta / HINT_FADE)
	if not GameContext.gameplay_input_enabled():
		# Paused or locked: keep the hint, keep the clock, and do not count menu presses.
		for action in HINT_ACTIONS:
			_hint_held[action] = InputMap.has_action(action) and Input.is_action_pressed(action)
		return
	_hint_left -= delta
	for action in HINT_ACTIONS:
		var now := InputMap.has_action(action) and Input.is_action_pressed(action)
		if now and not bool(_hint_held.get(action, false)):
			hide_hint()
			return
		_hint_held[action] = now
	if _hint_left <= 0.0:
		hide_hint()


func _make_canvas() -> Control:
	var canvas := Tableau.new()
	canvas.size = Vector2(1280, 720)
	canvas.visible = false
	add_child(canvas)
	return canvas


func show_shot(id: String, title: String = "", subtitle: String = "") -> void:
	if id != "chapter" and id != "boss" and id != "ability":
		return
	# Swap two bounded canvases, preserving the outgoing frame during a dissolve.
	var previous = back
	back = front
	front = previous
	front.move_to_front()
	front.shot = id
	front.age = 0.0
	front.heading = title
	front.subheading = subtitle
	front.kicker = ""
	# A new encounter starts at phase one; the phase ticks follow from signals.
	front.phase_marks = 1
	front.visible = true
	front.modulate.a = 0.0
	active_shot = id
	_blend = 0.0
	_leaving = false
	if id == "boss":
		_card_left = BOSS_CARD_SECONDS
	elif id == "ability":
		_card_left = ABILITY_CARD_SECONDS
	else:
		_card_left = 0.0
	front.queue_redraw()


func dismiss(immediate: bool = false) -> void:
	active_shot = ""
	_card_left = 0.0
	_leaving = true
	_blend = 0.0
	back.visible = false
	if immediate:
		front.visible = false
		_leaving = false
		skip_button.visible = false
		hide_hint()
		# Abort means death or a scene change: no stale boss should answer a later
		# phase signal from the old level.
		_boss_title = ""
		_boss_subtitle = ""
		_boss_kicker = ""


func _on_step(_index: int, step: Dictionary) -> void:
	var kind := String(step.get("kind", step.get("op", "")))
	if kind == "tableau":
		var id := String(step.get("id", ""))
		if id == "world":
			dismiss()
		else:
			show_shot(id, String(step.get("title", "")), String(step.get("subtitle", "")))
	elif kind == "caption" and active_shot == "chapter":
		dismiss()


func _on_boss_appeared(title: String, current_hp: int, _max_hp: int) -> void:
	# Combat owns the encounter and announces once. This flourish never changes
	# aggro, health, saves, input locks or the boss's punish windows.
	if current_hp <= 0:
		return
	var parts := title.split("·", false, 1)
	var heading := String(parts[0]).replace(" ", "")
	var subtitle := String(parts[1]).strip_edges() if parts.size() > 1 else "守 芯 者"
	_boss_title = heading
	_boss_subtitle = subtitle
	_boss_kicker = _kicker_for_current_level()
	# A chapter card is a bigger arrival than the encounter: never cover it. The
	# next boss signal (or the phase reminder) can still raise the name later.
	if active_shot == "chapter":
		return
	# The encounter may be announced again after a resume/reload; refresh the card
	# instead of dropping the signal or resetting the phase ticks.
	if active_shot == "boss":
		front.heading = heading
		front.subheading = subtitle
		front.kicker = _boss_kicker
		front.queue_redraw()
		return
	show_shot("boss", heading, subtitle)
	front.kicker = _boss_kicker


## 名号卡上的白话一行：按玩家所在章取 ChapterText.boss_intro（只读文本，不碰 Boss 的名号
## 字符串和战斗）。不在战役关卡里 / 这一章没有 Boss 介绍就返回空串。
func _kicker_for_current_level() -> String:
	var tree := get_tree()
	if tree == null:
		return ""
	var player := tree.get_first_node_in_group("player")
	if player == null:
		return ""
	var world := GameContext.world_root(player)
	if world == null or not world.is_in_group("game_world"):
		return ""
	var level := GameContext.level_id_of(player)
	if level == "" and world.scene_file_path == GameContext.LEGACY_WORLD_PATH:
		level = "level01"
	return ChapterText.boss_intro_of(level)


func _on_boss_defeated() -> void:
	_boss_title = ""
	_boss_subtitle = ""
	_boss_kicker = ""
	if active_shot == "boss":
		dismiss()


## 阶段变化更新名号卡上的相数刻度：字没变，玩家抬头就知道对手升了相。
## 名号早已退场时把同一块卡短暂重新举起 —— 否则相变演出时看不到刻度。
func _on_boss_phase(_boss_name: String, phase: int) -> void:
	if _boss_title == "":
		return
	if active_shot == "chapter":
		return
	if active_shot != "boss":
		show_shot("boss", _boss_title, _boss_subtitle)
		front.kicker = _boss_kicker
		_card_left = PHASE_CARD_SECONDS
	front.phase_marks = maxi(phase, 1)
	back.phase_marks = maxi(phase, 1)
	front.queue_redraw()
	back.queue_redraw()


func _on_finished() -> void:
	dismiss(Director.is_aborting())
	skip_button.visible = false
	_hint_age = 0.0


## 跳过提示的文案：只有新游戏开场说「跳过开场」；Boss 登场、拾核、剧情拍都只说「跳过」。
static func skip_label(touch: bool, opening: bool) -> String:
	if opening:
		return "点此跳过开场" if touch else "Enter · 跳过开场"
	return "点此跳过" if touch else "Enter · 跳过"


func _process(delta: float) -> void:
	var frozen := Director.is_suspended() or get_tree().paused
	skip_button.visible = Director.playing and not frozen and _hint_age > 0.65
	if frozen:
		return
	_tick_hint(delta)
	if Director.playing:
		_hint_age += delta
		# Same rule as the on-screen pad: a forced / mobile / touchscreen session says 点此.
		var touch := TouchInput.wants_overlay()
		if Director.board_active():
			# 分镜自己说 Enter 是「跳过」（章间）还是「下一句」（序章 / 结局）。
			skip_button.text = Director.board_skip_label(touch)
		elif Director.skips_whole_script():
			skip_button.text = skip_label(touch, OpeningCinematic.is_active())
		else:
			skip_button.text = "点此继续" if touch else "Enter · 继续"
	else:
		_hint_age = 0.0
	if front.visible:
		front.age += delta
		front.queue_redraw()
	if back.visible:
		back.age += delta
		back.queue_redraw()
	_blend = minf(1.0, _blend + delta / 0.6)
	var amount := smoothstep(0.0, 1.0, _blend)
	front.modulate.a = 1.0 - amount if _leaving else amount
	back.modulate.a = 1.0
	if _blend >= 1.0:
		back.visible = false
		if _leaving:
			front.visible = false
			_leaving = false
	if _card_left > 0.0:
		_card_left -= delta
		if _card_left <= 0.0:
			dismiss()
