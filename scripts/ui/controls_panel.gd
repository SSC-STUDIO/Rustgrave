class_name ControlsPanel
extends CanvasLayer
## 操作说明：四段键位各印在一张钉住的旧纸上，按 2×2 摊开。
## 右边是一排键帽（KeyCapPanel）。标题屏与暂停菜单共用，也是原先挤在 HUD 右上角那行操作提示的新家。
##
## 键名全部取自 Settings（经 KeyLabels），玩家在设置里改键后这里自动跟随：
## 每次 open() 和每次 Settings 发出 &"keys" 变更时重写键帽。
##
## 之所以是 CanvasLayer 而不是 Control：这个面板生成时就是隐藏的，而隐藏的
## Control 不会被排版（子节点的锚点算在 0x0 的父矩形上，面板会缩在左上角）。
## CanvasLayer 下的 Control 以视口为父矩形，隐藏期间也能正确排版。
## 调用方负责设置 layer（要盖在自己那层之上）。

signal closed

const Ornaments := preload("res://scripts/ui/ui_ornament.gd")
const Modal := preload("res://scripts/ui/ui_modal.gd")
const ObjectKit := preload("res://scripts/ui/ui_object.gd")
const INK := Color("#30251D")
const FADED_INK := Color("#65513E")
## 压暗到 0.76：这一层通常盖在暂停菜单上，底下的卡片要压到看不出字来，玻璃卡才不会透出串行。
const VEIL := 0.76
const CARD_GAP_H := 16
const CARD_GAP_V := 12
## The baked paper has 10–16px of transparent/deckled contour. Forty design
## pixels leave at least 12 physical pixels inside the paper at 960x540.
const PAPER_CONTENT_INSET := 40.0

## 键位表：[键位模板, 说明]。{action} 在显示时换成当前绑定；{attack2} 是挥砍的备用键
## （K，Settings 不改它），移动行的箭头同理由 KeyLabels.extra_keys 补在后面。
## 固定的键（Tab、Esc、鼠标）直接写字。
const ROWS: Array[Array] = [
	["{move_left} / {move_right}", "移动 · 沉重惯性"],
	["{jump}", "跳跃 · 落地可再跳"],
	["{dash}", "冲刺 · 无敌帧"],
	["{hookshot}", "钩锁 · 先镶钩锁核"],
	["{attack} / 鼠标左键", "挥砍 · 判定帧弹反"],
	["{attack2} / 鼠标右键", "同为挥砍 · 末段或收刀再按，接三连"],
	["{skill_1} / {skill_2}", "技能 1 / 2 · 冷却后放"],
	["{interact}", "交互 · 废料/插座/祠"],
	["{socket_1} / {socket_2}", "镶核 · 剑插座 1 / 2"],
	["按住 Tab", "目标 · 天气 · 剑核"],
	["Esc", "暂停 / 返回"],
	["触控板", "触屏：左移右移；右斩跳冲互；上钩/1/2/暂停"],
]
## 分组：{起始行, 组名}。12 行摊成移动 / 战斗 / 交互与剑核 / 系统四张卡（2×2），
## 行序就是这个分组顺序，key_text(index) 仍按行号取。
const GROUPS: Array[Dictionary] = [
	{"start": 0, "count": 4, "title": "移 动"},
	{"start": 4, "count": 3, "title": "战 斗"},
	{"start": 7, "count": 2, "title": "交 互 · 剑 核"},
	{"start": 9, "count": 3, "title": "系 统"},
]

var _root: Control
var _shell: Dictionary = {}
var _closing := false  ## 退场动画进行中：防连按 Esc 起两条 tween
var _scroll: ScrollContainer
## 每行键帽列（HBox）：refresh() 时按当前绑定重排。下标 = ROWS 的行号。
var _chip_boxes: Array[HBoxContainer] = []
var _notes: Array[Control] = []
var _note_tweens: Array[Tween] = []
var _note_open_token := 0


## A real brass pin sits through the baked hole, above each independently moving
## sheet. Keep it outside the content container so it never consumes text space.
class PaperPin extends Node2D:
	var paper: PanelContainer
	func bind_sheet(sheet: PanelContainer) -> void:
		paper = sheet
		sheet.item_rect_changed.connect(queue_redraw)
	func pin_center() -> Vector2:
		if not is_instance_valid(paper):
			return Vector2.ZERO
		var style := paper.get_theme_stylebox("panel") as StyleBoxTexture
		if style == null or style.texture == null:
			return Vector2(paper.size.x * 0.5, 20.0).snapped(Vector2(2, 2))
		# Source hole is (204,20) on paper.png. Match its 9-slice transform;
		# the pin stays in the hole when a sheet is laid out wider or narrower.
		var left := style.texture_margin_left
		var right := style.texture_margin_right
		var source_span := style.texture.get_width() - left - right
		var x := left + (204.0 - left) * (paper.size.x - left - right) / maxf(source_span, 1.0)
		return Vector2(x, 20.0).snapped(Vector2(2, 2))
	func _draw() -> void:
		if not is_instance_valid(paper):
			return
		var p := pin_center()
		# Short shaft shadow, stepped forged head, worn highlight and screwdriver
		# slot distinguish an installed pin from the texture's dark empty hole.
		draw_rect(Rect2(p + Vector2(-6, -2), Vector2(16, 12)), Color("#66553F"))
		var head := PackedVector2Array([
			p + Vector2(-6, -8), p + Vector2(4, -8), p + Vector2(8, -4),
			p + Vector2(8, 4), p + Vector2(4, 8), p + Vector2(-6, 8),
			p + Vector2(-10, 4), p + Vector2(-10, -4)])
		draw_colored_polygon(head, Color("#3A2B1B"))
		draw_rect(Rect2(p + Vector2(-6, -6), Vector2(10, 12)), Color("#A67D3D"))
		draw_rect(Rect2(p + Vector2(-8, -4), Vector2(14, 8)), Color("#A67D3D"))
		draw_rect(Rect2(p + Vector2(-6, -6), Vector2(8, 2)), Color("#E2BC72"))
		draw_rect(Rect2(p + Vector2(-8, -4), Vector2(2, 6)), Color("#CDA35B"))
		draw_line(p + Vector2(-4, 2), p + Vector2(4, -2), Color("#382C20"), 2.0)
		draw_rect(Rect2(p + Vector2(-2, 4), Vector2(6, 2)), Color("#72502A"))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()
	PresentationMetrics.bind_layer(self)
	Settings.changed.connect(_on_setting_changed)


func _exit_tree() -> void:
	if Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.disconnect(_on_setting_changed)


func _build() -> void:
	_shell = Modal.build(self, {
		"object": ObjectKit.Kind.NOTES,
		"title": "操 作 说 明",
		"size": Vector2(1176.0, 720.0),
		"hint": "弹反：判定帧命中敌弹 · 改键：设置 → 键位",
		"back": "Esc / 回车 返回",
		"veil": VEIL,
	})
	_root = _shell["root"] as Control
	# 遮罩会吃掉鼠标事件，所以点击关闭必须走 gui_input —— 被 GUI 消化的事件
	# 不会再进 _unhandled_input。
	_root.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			close())

	var body := _shell["body"] as Control
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_scroll)
	_scroll.resized.connect(_layout_notes)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	_scroll.add_child(column)

	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", CARD_GAP_H)
	grid.add_theme_constant_override("v_separation", CARD_GAP_V)
	column.add_child(grid)
	_chip_boxes.resize(ROWS.size())
	for group in GROUPS:
		var note := _group_card(group)
		grid.add_child(note)
		_notes.append(note)

	refresh()
	_layout_notes.call_deferred()


## 等宽纸面为长键帽与说明预留空间，四张纸不受某一行键名宽度挤压。
func _layout_notes() -> void:
	if _scroll == null or _scroll.size.x < 100.0:
		return
	var width := floorf((_scroll.size.x - CARD_GAP_H - 16.0) * 0.5)
	for note in _notes:
		note.custom_minimum_size.x = width


## 一张独立旧纸：纸纹与钉孔跟随实际布局，避免把四纸画死在外壳底纹里。
func _group_card(group: Dictionary) -> Control:
	var title := String(group["title"])
	var card := PanelContainer.new()
	card.name = "Card_" + title.replace(" ", "")
	card.theme = ObjectKit.surface_theme(ObjectKit.Kind.JOURNAL)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override(&"panel", _paper_card())
	var inner := VBoxContainer.new()
	inner.name = "Inner"
	inner.add_theme_constant_override("separation", 2)
	card.add_child(inner)
	inner.add_child(_group_header(title))
	var start_index := int(group["start"])
	for i in range(start_index, start_index + int(group["count"])):
		inner.add_child(_key_row(i))
	var pin := PaperPin.new()
	pin.name = "PaperPin"
	pin.bind_sheet(card)
	card.add_child(pin)
	return card


static func _paper_card() -> StyleBoxTexture:
	var box := ObjectKit.journey_tag_style_box().duplicate() as StyleBoxTexture
	# Preserve this paper's dog-ear and torn contour when the short landscape
	# sheets are stretched. These overrides affect the controls sheets only.
	box.texture_margin_left = 24.0
	box.texture_margin_top = 60.0
	box.texture_margin_right = 60.0
	box.texture_margin_bottom = 36.0
	box.content_margin_left = PAPER_CONTENT_INSET
	box.content_margin_top = PAPER_CONTENT_INSET
	box.content_margin_right = PAPER_CONTENT_INSET
	box.content_margin_bottom = PAPER_CONTENT_INSET
	return box


## 卡片题头：GlassKit 的 kicker（12px 余烬小字）+ 一道锈色发丝线，和故事页、暂停页的题头同一语汇。
func _group_header(title: String) -> Control:
	var row := HBoxContainer.new()
	row.name = "Group_" + title.replace(" ", "")
	row.add_theme_constant_override("separation", 10)
	var label := GlassKit.kicker(title)
	label.modulate = Color.WHITE
	label.add_theme_color_override("font_color", INK)
	label.add_theme_font_size_override("font_size", 24)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var rule := Ornaments.stub_rule(false)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(rule)
	# The folded upper-right corner protrudes into the first title line only.
	# Stop its rule before the fold; later action rows use the full paper width.
	var fold_clearance := Control.new()
	fold_clearance.custom_minimum_size.x = 24.0
	row.add_child(fold_clearance)
	return row


## 左边是简短动作说明，右边是铅字键帽；使用 24px 字号，
## 在 960 窗口的整数半倍显示下仍保留 12px 字形，四纸等宽并自动折行。
func _key_row(index: int) -> Control:
	var row := HBoxContainer.new()
	row.name = "Row%d" % index
	row.custom_minimum_size.y = 32.0
	row.add_theme_constant_override("separation", 10)
	var action := UiKit.label(String(ROWS[index][1]), &"BodyLabel")
	action.add_theme_color_override("font_color", FADED_INK)
	action.add_theme_font_size_override("font_size", 24)
	action.add_theme_constant_override("outline_size", 0)
	action.name = "Action"
	action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(action)
	var chips := HBoxContainer.new()
	chips.name = "Keys"
	chips.size_flags_horizontal = Control.SIZE_SHRINK_END
	chips.alignment = BoxContainer.ALIGNMENT_END
	chips.add_theme_constant_override("separation", 4)
	row.add_child(chips)
	_chip_boxes[index] = chips
	return row


func _chip(text: String) -> Control:
	var plate := UiKit.panel(&"KeyCapPanel")
	plate.name = "Chip"
	plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var stamp := StyleBoxFlat.new()
	stamp.bg_color = Color("#B9A785")
	stamp.border_color = Color("#79664A")
	stamp.set_border_width_all(1)
	stamp.content_margin_left = 6.0
	stamp.content_margin_right = 6.0
	stamp.content_margin_top = 2.0
	stamp.content_margin_bottom = 2.0
	plate.add_theme_stylebox_override("panel", stamp)
	var key := UiKit.label(text, &"KeyCapLabel", HORIZONTAL_ALIGNMENT_CENTER)
	key.add_theme_color_override("font_color", INK)
	key.add_theme_font_size_override("font_size", 24)
	key.add_theme_constant_override("outline_size", 0)
	key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plate.add_child(key)
	return plate


## 把键帽列重写成当前绑定（含备用键）。公开：测试与改键后直接调用。
func refresh() -> void:
	for i in _chip_boxes.size():
		var box := _chip_boxes[i]
		if box == null:
			continue
		for old in box.get_children():
			box.remove_child(old)
			old.queue_free()
		for text in key_chips(i):
			box.add_child(_chip(text))


## 第 i 行的键位文字（整段，和设置页键帽同一个出口）。
func key_text(index: int) -> String:
	var template := _template(index)
	var text := KeyLabels.format(template)
	var arrows := _arrows_for(template)
	if arrows != "":
		text += "  " + arrows
	return text


## 第 i 行的键帽列：每个键一枚（"A / D" + 备用箭头 → A、D、←、→）。
func key_chips(index: int) -> PackedStringArray:
	var template := _template(index)
	var out := PackedStringArray()
	for part in KeyLabels.format(template).split(" / "):
		var chip := String(part).strip_edges()
		if chip != "":
			out.append(chip)
	var arrows := _arrows_for(template)
	if arrows != "":
		out.append_array(arrows.split("/"))
	return out


## 模板里的 {attack2} 换成挥砍的备用键；没有备用键就把这一段去掉。
func _template(index: int) -> String:
	var template := String(ROWS[index][0])
	if template.begins_with("{attack2}"):
		var alt := KeyLabels.extra_keys(&"attack")
		if alt.is_empty():
			template = template.replace("{attack2} / ", "")
		else:
			template = template.replace("{attack2}", alt[0])
	return template


## 移动行的备用键（←/→，Settings 不改它们）补在后面。
func _arrows_for(template: String) -> String:
	if not template.contains("{move_left}"):
		return ""
	var parts: Array[String] = []
	parts.append_array(KeyLabels.extra_keys(&"move_left"))
	parts.append_array(KeyLabels.extra_keys(&"move_right"))
	return "/".join(parts)


func _on_setting_changed(key: StringName) -> void:
	if key == &"keys":
		refresh()


func open() -> void:
	refresh()
	_closing = false
	visible = true
	(_shell.get("play_intro") as Callable).call()
	_note_open_token += 1
	_play_notes_intro.call_deferred(_note_open_token)
	GameContext.suppress_gameplay_input()
	Sfx.play(&"ui_select")


## 纸张依次落到钉子下。只移动整像素，不旋转或缩放字形。
func _play_notes_intro(token: int) -> void:
	if token != _note_open_token:
		return
	_stop_notes_intro()
	# Binding refresh queues nested container sorts. Capture paper homes only
	# after those sorts finish, otherwise both bottom papers animate to row one.
	_layout_notes()
	await get_tree().process_frame
	await get_tree().process_frame
	if token != _note_open_token:
		return
	if not visible or _closing:
		return
	if DisplayServer.get_name() == "headless":
		return
	for i in _notes.size():
		var note := _notes[i]
		var home := note.position.round()
		note.set_meta("note_home", home)
		note.position = home + Vector2(0.0, 12.0)
		note.modulate.a = 0.0
		var tween := create_tween().set_parallel(true)
		_note_tweens.append(tween)
		tween.tween_method(func(y: float) -> void:
			note.position = Vector2(home.x, roundf(y)), home.y + 12.0, home.y, 0.18) \
				.set_delay(float(i) * 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(note, "modulate:a", 1.0, 0.18).set_delay(float(i) * 0.06)
		tween.finished.connect(func() -> void: note.remove_meta("note_home"))


func _stop_notes_intro() -> void:
	for tween in _note_tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_note_tweens.clear()
	for note in _notes:
		if note.has_meta("note_home"):
			note.position = note.get_meta("note_home") as Vector2
			note.remove_meta("note_home")
		note.modulate.a = 1.0


func close() -> void:
	if not visible or _closing:
		return
	_closing = true
	_note_open_token += 1
	_stop_notes_intro()
	GameContext.suppress_gameplay_input()
	Sfx.play(&"ui_back")
	# 退场动画播完才隐藏：卡片沉回去、纱幕收掉，然后才 emit closed。
	(_shell.get("play_outro") as Callable).call(func() -> void:
		if not is_instance_valid(self):
			return
		_closing = false
		visible = false
		closed.emit()
	)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_scroll.scroll_vertical += 48
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_scroll.scroll_vertical = maxi(0, _scroll.scroll_vertical - 48)
		get_viewport().set_input_as_handled()
