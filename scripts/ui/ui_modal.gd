extends RefCounted
## 弹窗外壳：设置 / 操作说明 / 教程回看 / 地图 / 暂停菜单都用它搭。
##
## 目标是"从底下那层弹出来的一张卡片"，而不是一整页黑板：
##   · 背景只压暗到还看得见后面的程度（纱幕 + 上下渐变），标题屏的 keyart 或暂停
##     菜单会留在卡片四周；四周再飘一点余烬，静止画面不至于一片死色。
##   · 内容卡是主题里的花边面板，尺寸有上限、居中悬浮；卡片内部固定三段：
##     标题带（小字 kicker + 大标题 + 铆钉横线）、内容区、底部锈色提示带。
##   · 开屏只做 0.16s 的透明度淡入，不做缩放 —— 像素字体一旦被非整数倍缩放就糊。
##
## 本文件不写 class_name：各界面按 preload 取用。

const Ornaments := preload("res://scripts/ui/ui_ornament.gd")

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
## 返回 {root, veil, card, body, footer, hint, back, field, play_intro}
static func build(host: CanvasLayer, opts: Dictionary) -> Dictionary:
	var root := Control.new()
	root.name = "ModalRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(root)

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

	var card := UiKit.panel(&"OrnatePanel")
	card.name = "Card"
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	var size: Vector2 = opts.get("size", Vector2(960.0, 600.0))
	card.custom_minimum_size = size
	root.add_child(card)

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
		kicker.name = "Kicker"
		header.add_child(kicker)
	var title := UiKit.label(String(opts.get("title", "")), &"HeadLabel",
			HORIZONTAL_ALIGNMENT_CENTER)
	title.name = "Title"
	header.add_child(title)
	var rule := Ornaments.rivet_rule(maxf(size.x - 96.0, 320.0))
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
		"play_intro": func() -> void: play_intro(veil, card),
	}


## 开屏只让背景纱幕从"亮"淡到"暗"，卡片本身立刻到位。
## 卡片跟着淡入会在开头 0.1s 变成半透明，叠在暂停菜单上就是双重曝光；
## 弹窗要的是"啪一下出现、后面同时压暗"。
static func play_intro(veil: CanvasItem, card: CanvasItem) -> void:
	if veil == null or not veil.is_inside_tree():
		return
	veil.modulate.a = 0.0
	var tween := veil.create_tween()
	tween.tween_property(veil, "modulate:a", 1.0, INTRO_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if card != null:
		card.modulate.a = 1.0
