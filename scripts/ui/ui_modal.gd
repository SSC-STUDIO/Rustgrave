extends RefCounted
## 弹窗外壳：设置 / 操作说明 / 教程回看 / 地图 / 暂停菜单都用它搭。
##
## object 选项构建铁、纸、皮革实物；未迁移的界面保留旧花边玻璃卡。
## 实物后方使用屏幕副本的轻模糊与可透景纱幕，保留炉厅或战场环境。
## Content/Header、Body、Footer 路径不变，纸面使用墨色主题。
## 进退场使用可取消的整像素位移动画，像素文字全程不缩放。
##
## 本文件不写 class_name：各界面按 preload 取用。

const Ornaments := preload("res://scripts/ui/ui_ornament.gd")
const Transitions := preload("res://scripts/ui/ui_transition.gd")
const ObjectKit := preload("res://scripts/ui/ui_object.gd")
const BLUR_SHADER := preload("res://assets/shaders/ui_object_blur.gdshader")

## 背景纱幕的默认暗度：0.55 左右刚好压住画面又不至于变黑板。
const DEFAULT_VEIL := 0.55
const DEFAULT_BACK := "Esc 返回"
const INTRO_TIME := 0.12


## opts:
##   title   : String  标题（必填）
##   size    : Vector2 卡片最小尺寸（默认 960×600）
##   kicker  : String  标题上方 12px 小字（可选）
##   hint    : String  底部提示带左侧文字
##   back    : String  提示带右侧文字（默认 "Esc 返回"）
##   veil    : float   背景暗度（默认 0.55；想更暗就调高）
##   embers  : bool    卡片后面是否飘余烬（默认 true）
##   object  : ObjectKit.Kind 实物类型（null 则沿用花边板）
## 返回 {root, veil, card, body, footer, hint, back, field, play_intro, ...}
static func build(host: CanvasLayer, opts: Dictionary) -> Dictionary:
	var root := Control.new()
	root.name = "ModalRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var kind = opts.get("object", null)
	if kind != null:
		root.theme = ObjectKit.surface_theme(kind)
	host.add_child(root)
	if kind != null:
		var copy := BackBufferCopy.new()
		copy.name = "SceneCopy"
		copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
		root.add_child(copy)
		var blur := ColorRect.new()
		blur.name = "SceneBlur"
		blur.set_anchors_preset(Control.PRESET_FULL_RECT)
		blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var material := ShaderMaterial.new()
		material.shader = BLUR_SHADER
		blur.material = material
		root.add_child(blur)

	var veil := ColorRect.new()
	veil.name = "Veil"
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	var alpha := float(opts.get("veil", DEFAULT_VEIL))
	veil.color = Color(UiKit.SCRIM.r, UiKit.SCRIM.g, UiKit.SCRIM.b, alpha)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(veil)
	root.add_child(UiKit.scrim(0.62, 0.22, 0.66))

	var field: Node2D = null
	if bool(opts.get("embers", true)):
		field = UiKit.EmberField.build(Rect2(Vector2.ZERO, Vector2(1280, 720)), 10, 5)
		field.name = "ModalEmbers"
		root.add_child(field)

	var size: Vector2 = opts.get("size", Vector2(960.0, 600.0))
	var card: PanelContainer
	var dressing: Node2D = null
	var wash: TextureRect = null

	if kind == null:
		card = UiKit.panel(&"OrnatePanel")
		card.name = "Card"
		card.set_anchors_preset(Control.PRESET_CENTER)
		card.grow_horizontal = Control.GROW_DIRECTION_BOTH
		card.grow_vertical = Control.GROW_DIRECTION_BOTH
		card.custom_minimum_size = size
		root.add_child(card)
		# 卡片默认半透明（GlassKit）：场景的光从后面透出来。opts.glass = false 才回到实心花边板。
		if bool(opts.get("glass", true)):
			GlassKit.glass(card)
	else:
		card = PanelContainer.new()
		card.name = "Card"
		card.set_anchors_preset(Control.PRESET_CENTER)
		card.grow_horizontal = Control.GROW_DIRECTION_BOTH
		card.grow_vertical = Control.GROW_DIRECTION_BOTH
		card.custom_minimum_size = size
		var sb := ObjectKit.style_box(kind, size)
		card.set_meta("object_kind", kind)
		card.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		card.add_theme_stylebox_override(&"panel", sb)
		root.add_child(card)

		dressing = ObjectKit.dressing(kind, card)
		if dressing != null:
			dressing.name = "Dressing"
			root.add_child(dressing)

		wash = ObjectKit.light_wash(kind, size) if kind != ObjectKit.Kind.NOTES else null
		if wash != null:
			wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
			wash.custom_minimum_size = Vector2.ZERO
			card.add_child(wash)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 10)
	card.add_child(content)

	var header := VBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 4)
	content.add_child(header)
	var kicker_text := String(opts.get("kicker", ""))
	if kicker_text != "":
		var kicker := UiKit.label(kicker_text, &"TinyStrongLabel", HORIZONTAL_ALIGNMENT_CENTER)
		if kind != null and kind in [ObjectKit.Kind.LEDGER, ObjectKit.Kind.JOURNAL]:
			kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		kicker.name = "Kicker"
		header.add_child(kicker)
	var title := UiKit.label(String(opts.get("title", "")), &"HeadLabel",
			HORIZONTAL_ALIGNMENT_CENTER)
	title.name = "Title"
	if kind != null and kind in [ObjectKit.Kind.LEDGER, ObjectKit.Kind.JOURNAL]:
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.add_child(title)
	var rule: Control
	if kind != null and (kind == ObjectKit.Kind.LEDGER or kind == ObjectKit.Kind.JOURNAL or kind == ObjectKit.Kind.LETTER):
		rule = ColorRect.new()
		(rule as ColorRect).color = Color(0.23, 0.14, 0.08, 0.28)
		rule.custom_minimum_size = Vector2(0.0, 2.0)
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		rule = Ornaments.rivet_rule(maxf(size.x - 96.0, 320.0))
	rule.name = "Rule"
	header.add_child(rule)

	var body := Control.new()
	body.name = "Body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(body)

	var footer := UiKit.panel(&"BandPanel")
	footer.name = "Footer"
	footer.custom_minimum_size = Vector2(0.0, 34.0)
	if kind != null:
		var foot_style := StyleBoxEmpty.new()
		foot_style.content_margin_top = 6.0
		footer.add_theme_stylebox_override("panel", foot_style)
	content.add_child(footer)
	var footer_row := HBoxContainer.new()
	footer_row.name = "Row"
	footer.add_child(footer_row)
	var hint := UiKit.label(String(opts.get("hint", "")), &"FootnoteLabel")
	hint.name = "Hint"
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer_row.add_child(hint)
	var back := UiKit.label(String(opts.get("back", DEFAULT_BACK)), &"FootnoteLabel",
			HORIZONTAL_ALIGNMENT_RIGHT)
	back.name = "Back"
	back.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer_row.add_child(back)

	return {
		"root": root, "veil": veil, "card": card, "body": body, "footer": footer,
		"hint": hint, "back": back, "field": field,
		"dressing": dressing, "wash": wash, "kind": kind,
		"card_home": card.position,
		"play_intro": func() -> void:
			if kind != null:
				Transitions.object_in(kind, root, card, veil, dressing)
			else:
				play_intro(root, veil, card, card.position),
		"play_outro": func(on_done: Callable = Callable()) -> void:
			if kind != null:
				Transitions.object_out(kind, root, card, veil, dressing, on_done)
			else:
				play_outro(root, veil, card, on_done),
		"finish_instantly": func() -> void:
			finish_instantly(root, veil, card, card.get_meta("_modal_home", card.position))
			if dressing != null:
				dressing.modulate.a = 1.0
			if dressing != null and dressing.has_method("snap"):
				dressing.call("snap"),
	}


## 开屏：纱幕压下、卡片从下方 18px 合到位（带一点回弹）。
## 旧版卡片立刻可见、只有纱幕淡入——双击设置时整张牌"闪"出来；
## 现在卡片跟着纱幕一起进场，开关都走同一条曲线。
static func play_intro(root: CanvasItem, veil: CanvasItem, card: CanvasItem,
		card_home: Vector2) -> void:
	if root == null or not root.is_inside_tree():
		return
	root.visible = true
	Transitions.modal_in(root, card, veil)


## 退场：卡片沉回去 + 纱幕收掉，动画结束后回调 on_done。
## 调用方在 on_done 里才真正 visible = false——"退完才消失"，不是闪断。
static func play_outro(root: CanvasItem, veil: CanvasItem, card: CanvasItem,
		on_done: Callable = Callable()) -> void:
	if root == null or not root.is_inside_tree():
		if on_done.is_valid():
			on_done.call()
		return
	Transitions.modal_out(root, card, veil, on_done)


## 跳过动画直接落位：开屏第一帧、headless 测试、场景切换时的兜底。
static func finish_instantly(root: CanvasItem, veil: CanvasItem, card: CanvasItem,
		card_home: Vector2) -> void:
	Transitions.modal_reset(root, card, veil, card_home, 1.0)
	if card != null:
		card.modulate.a = 1.0
	if veil != null:
		veil.modulate.a = 1.0
