class_name CharacterSelectScreen
extends CanvasLayer
## CharacterSelectScreen: 身份与启程配装（开局前的角色选择弹窗）。
## Test contracts kept as-is:
##   - CanvasLayer (layer 8), Modal.build(self, ...) shell (ModalRoot/Card, ModalRoot/Veil, ModalRoot/ModalEmbers)
##   - Card 1120x700 (width < 1180), veil alpha < 0.8, Footer/Row/CancelButton + EmbarkButton
##   - Body/MainVBox/Columns/RightColumn/GearPlaque/Content/TrinketTabs (three trinket buttons)
##   - AppearanceStrip / SkinRow / RuneRow / SkinBtn_<id> / RuneBtn_<id> (find_child)
##
## Layout (card body is about 1052 x 482):
##   - Left: three origin portrait cards in a row (glass, chamfered; the selected card lifts 4px with an
##     ember edge), then the origin lore card, then the appearance strip (skin / rune).
##   - Right: identity detail (name, combat focus, six stats drawn as segmented pips; exact numbers live
##     in the hover tooltip) and the starting gear (preset weapon / armour, set resonance, trinkets).
##   - Footer: cancel (secondary plate) and the embark action (ember-framed primary plate).

signal embark_requested(origin_id: StringName, loadout: Dictionary)
signal cancelled

const Modal := preload("res://scripts/ui/ui_modal.gd")
const Ornaments := preload("res://scripts/ui/ui_ornament.gd")
const Plate := preload("res://scripts/ui/menu_plate.gd")
const SkinCatalog := preload("res://scripts/data/skin_catalog.gd")
const RuneCatalog := preload("res://scripts/data/rune_catalog.gd")
const PassiveCatalog := preload("res://scripts/data/passive_catalog.gd")

const CARD_SIZE := Vector2(1120.0, 700.0)
## Right column width: enough for the three trinket tabs and the pip labels.
const RIGHT_W := 408.0
const COLUMN_GAP := 16
## Origin card body height (the card itself is LIFT taller so the selected card can rise).
const CARD_BODY_H := 200.0
const CARD_LIFT := 4.0

const COLOR_ATTACK := Color("#FFC14A")   # Warm yellow
const COLOR_DEFENSE := Color("#BAC4CC")  # Iron grey
const COLOR_TOXIN := Color("#5CE1B6")    # Teal/cyan
const COLOR_SPEED := Color("#5CB3FF")    # Agility blue
const COLOR_HP := Color("#76E074")       # Vitality green

## Semantic stat colours shared with the equipment panel (same hue language across both screens).
const BONUS_COLORS := {
	&"max_hp": COLOR_HP,
	&"attack": COLOR_ATTACK,
	&"defense": COLOR_DEFENSE,
	&"toxin_resist": COLOR_TOXIN,
	&"toxin_decay": COLOR_TOXIN,
	&"speed_mult": COLOR_SPEED,
}

## Pip meters: one pip = PIP_UNITS in-game units, PIP_COUNTS pips across. The count is only the
## drawing scale (a full track is not a game cap); toxin resistance's 80% cap happens to be 8 pips.
const PIP_UNITS := {
	&"max_hp": 1.0,
	&"attack": 1.0,
	&"defense": 1.0,
	&"toxin_resist": 0.10,
	&"toxin_decay": 0.25,
	&"speed_mult": 0.10,
}
const PIP_COUNTS := {
	&"max_hp": 10,
	&"attack": 4,
	&"defense": 5,
	&"toxin_resist": 8,
	&"toxin_decay": 4,
	&"speed_mult": 12,
}
const STAT_ROWS := [
	[&"max_hp", "生命上限", COLOR_HP],
	[&"attack", "近战攻击", COLOR_ATTACK],
	[&"defense", "伤害减免", COLOR_DEFENSE],
	[&"toxin_resist", "毒素抗性", COLOR_TOXIN],
	[&"toxin_decay", "自然排毒", COLOR_TOXIN],
	[&"speed_mult", "移动修正", COLOR_SPEED],
]

## Pulse when a value changes: the pip row lights for 0.18s instead of jumping. Only changed rows pulse.
const PREVIEW_PULSE := 0.18
const PREVIEW_LIT := Color(1.25, 1.18, 1.06)

var _selected_origin_id: StringName = OriginCatalog.ORIGIN_EMBER_VANGUARD
var _selected_trinket_id: StringName = OriginCatalog.ALLOWED_TRINKETS[0]
## Appearance: skin + rune. Both are written into the loadout and persisted after embark.
var _selected_skin_id: StringName = SkinCatalog.default_for_origin(OriginCatalog.ORIGIN_EMBER_VANGUARD)
var _selected_rune_id: StringName = &""
var _skin_picked := false
var _skin_buttons: Array[Button] = []
var _rune_buttons: Array[Button] = []

var _shell: Dictionary = {}
var _root: Control
var _closing := false

# Origin cards
var _origin_buttons: Array[Button] = []
var _origin_cards: Array = []
var _origin_title_lbl: Label
var _origin_focus_lbl: Label
var _origin_bonuses_lbl: Label
var _origin_lore_lbl: Label
var _passive_lbl: Label

# Stat pips (detail card)
var _stat_meters: Dictionary = {}   # key -> PipMeter
var _stat_titles: Dictionary = {}   # key -> String
var _stat_texts: Dictionary = {}    # key -> last value text (pulse only when it changes)

# Gear summary
var _weapon_row: Control
var _weapon_name_lbl: Label
var _armor_row: Control
var _armor_name_lbl: Label
var _synergy_badge_lbl: Label

# Trinket picker
var _trinket_buttons: Array[Button] = []
var _trinket_desc_lbl: Label

# Action buttons
var _embark_btn: Button
var _cancel_btn: Button


func _ready() -> void:
	layer = 8
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()
	PresentationMetrics.bind_layer(self)
	_refresh_ui()


func _build() -> void:
	_shell = Modal.build(self, {
		"title": "身 份 与 启 程 配 装",
		"kicker": "选 择 角 色",
		"size": CARD_SIZE,
		"hint": "方向键/点击 切换流派与信物 · Enter 出发 · Esc 取消",
		"back": "",
		"veil": 0.60,
		"embers": true,
	})
	_root = _shell["root"] as Control
	_root.theme = UiKit.extras_theme()

	# Clicking veil backdrop outside card closes the screen
	_root.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			cancel())

	var body := _shell["body"] as Control

	var main_vbox := VBoxContainer.new()
	main_vbox.name = "MainVBox"
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(main_vbox)

	var columns := HBoxContainer.new()
	columns.name = "Columns"
	columns.add_theme_constant_override("separation", COLUMN_GAP)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(columns)

	_build_left_column(columns)
	_build_right_column(columns)

	_build_footer_actions()


# ===========================================================================
# Shared glass card: TitleCard body (translucent, same alpha as the modal shell) + padded content
# ===========================================================================

## Returns the Content VBox of a glass card. The root is a PanelContainer so it reports the content's
## minimum size to the parent container; the TitleCard is drawn first, the content sits on top.
static func _glass_card(parent: Control, card_name: String, pad: int, gap: int = 4) -> VBoxContainer:
	var root := GlassCardRoot.new()
	root.name = card_name
	# 内边距放在空样式盒的 content margin 里，所以 Content 是卡片的直接子节点（GearPlaque/Content/...）。
	var pad_box := StyleBoxEmpty.new()
	pad_box.content_margin_left = float(pad)
	pad_box.content_margin_right = float(pad)
	pad_box.content_margin_top = float(pad)
	pad_box.content_margin_bottom = float(pad)
	root.add_theme_stylebox_override("panel", pad_box)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# 卡片本身吃掉点击：空白处不能穿透到外壳的"点卡片外关闭"。
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(root)

	# 玻璃框体是卡片的第一个子节点，画在内容后面；位置与尺寸由 GlassCardRoot 每帧对齐到卡片矩形。
	var frame := TitleCard.new()
	frame.name = "Frame"
	frame.body_alpha = GlassKit.CARD_ALPHA / TitleCard.FILL.a
	root.add_child(frame)
	root.frame = frame

	var content := VBoxContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", gap)
	root.add_child(content)
	return content


# ===========================================================================
# Left Column: origin portrait cards, lore, appearance strip
# ===========================================================================

func _build_left_column(parent: Control) -> void:
	var col := VBoxContainer.new()
	col.name = "LeftColumn"
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)
	parent.add_child(col)

	col.add_child(GlassKit.kicker("选 择 流 派"))
	_build_origin_cards(col)
	_build_lore_card(col)
	_build_appearance_strip(col)


func _build_origin_cards(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.name = "OriginCards"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var group := ButtonGroup.new()
	for orig_id in OriginCatalog.get_all_origin_ids():
		var origin := OriginCatalog.get_origin(orig_id)
		var skin_id := SkinCatalog.default_for_origin(orig_id)
		var card := OriginCard.new()
		card.name = "Card_" + String(orig_id)
		card.setup(orig_id, origin.title, origin.combat_focus, _portrait_for(skin_id),
				SkinCatalog.tint_of(skin_id), CARD_BODY_H, CARD_LIFT)
		row.add_child(card)
		var btn := card.button
		btn.name = "OriginBtn_" + String(orig_id)
		btn.toggle_mode = true
		btn.button_group = group
		btn.pressed.connect(_on_origin_button_pressed.bind(orig_id))
		btn.mouse_entered.connect(btn.grab_focus)
		_origin_buttons.append(btn)
		_origin_cards.append(card)


## The card portrait is the skin's idle frame (the same art the player character uses).
static func _portrait_for(skin_id: StringName) -> Texture2D:
	var frames := SkinCatalog.frames_for(skin_id, &"idle")
	return frames[0] if not frames.is_empty() else null


func _build_lore_card(parent: Control) -> void:
	var box := _glass_card(parent, "LorePlaque", 12, 4)

	_origin_lore_lbl = UiKit.label("", &"BodyLabel")
	_origin_lore_lbl.name = "OriginLore"
	_origin_lore_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_origin_lore_lbl.modulate = Color(1.0, 1.0, 1.0, 0.86)
	_origin_lore_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_origin_lore_lbl)

	# 流派特化与被动：两条都是这个流派自带的效果，放在一起读。
	_origin_bonuses_lbl = UiKit.label("", &"FootnoteLabel")
	_origin_bonuses_lbl.name = "OriginBonuses"
	_origin_bonuses_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_origin_bonuses_lbl.modulate = UiKit.EMBER_ASH
	box.add_child(_origin_bonuses_lbl)

	_passive_lbl = UiKit.label("", &"FootnoteLabel")
	_passive_lbl.name = "OriginPassive"
	_passive_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_passive_lbl.modulate = Color(UiKit.ASH.r, UiKit.ASH.g, UiKit.ASH.b, 0.9)
	box.add_child(_passive_lbl)


# ===========================================================================
# Right Column: identity detail (pips) + starting gear & trinkets
# ===========================================================================

func _build_right_column(parent: Control) -> void:
	var col := VBoxContainer.new()
	col.name = "RightColumn"
	col.custom_minimum_size = Vector2(RIGHT_W, 0.0)
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)
	parent.add_child(col)

	col.add_child(GlassKit.kicker("身 份 详 情"))
	_build_detail_card(col)
	_build_gear_card(col)


func _build_detail_card(parent: Control) -> void:
	var box := _glass_card(parent, "DetailPlaque", 14, 4)

	_origin_title_lbl = UiKit.label("", &"HeadLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_origin_title_lbl.name = "OriginTitle"
	_origin_title_lbl.modulate = UiKit.EMBER
	box.add_child(_origin_title_lbl)

	_origin_focus_lbl = UiKit.label("", &"TinyStrongLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_origin_focus_lbl.name = "OriginFocus"
	_origin_focus_lbl.modulate = COLOR_DEFENSE
	box.add_child(_origin_focus_lbl)

	box.add_child(GlassKit.rule(180.0))

	for spec in STAT_ROWS:
		var key: StringName = spec[0]
		var title: String = spec[1]
		var color: Color = spec[2]

		var row := HBoxContainer.new()
		row.name = "Row_" + String(key)
		row.add_theme_constant_override("separation", 10)
		box.add_child(row)

		var name_lbl := UiKit.label(title, &"TinyStrongLabel")
		name_lbl.name = "Name"
		name_lbl.custom_minimum_size = Vector2(84.0, 0.0)
		name_lbl.modulate = Color(color.r, color.g, color.b, 0.9)
		row.add_child(name_lbl)

		var meter := PipMeter.new()
		meter.name = "Pips"
		meter.set_scale_for(PIP_UNITS[key], PIP_COUNTS[key], color)
		row.add_child(meter)
		_stat_meters[key] = meter
		_stat_titles[key] = title


func _build_gear_card(parent: Control) -> void:
	var box := _glass_card(parent, "GearPlaque", 14, 3)

	# 预设武器 / 护甲：名字上屏，描述与属性放进悬停提示（这里只留能一眼读完的内容）。
	_weapon_row = _equip_row(box, "WeaponRow", "[ 预设武器 ]", COLOR_ATTACK)
	_weapon_name_lbl = _weapon_row.get_meta(&"name_label") as Label
	_armor_row = _equip_row(box, "ArmorRow", "[ 预设护甲 ]", COLOR_DEFENSE)
	_armor_name_lbl = _armor_row.get_meta(&"name_label") as Label

	_synergy_badge_lbl = UiKit.label("套装共鸣: 无", &"FootnoteLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_synergy_badge_lbl.name = "SynergyBadge"
	_synergy_badge_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_synergy_badge_lbl.modulate = UiKit.EMBER
	box.add_child(_synergy_badge_lbl)

	box.add_child(GlassKit.rule(120.0))

	var t_header := UiKit.label("[ 随身信物 · 自由选取 ]", &"TinyStrongLabel", HORIZONTAL_ALIGNMENT_CENTER)
	t_header.name = "TrinketHeader"
	t_header.modulate = COLOR_TOXIN
	box.add_child(t_header)

	var trinket_tabs := HBoxContainer.new()
	trinket_tabs.name = "TrinketTabs"
	trinket_tabs.add_theme_constant_override("separation", 6)
	trinket_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(trinket_tabs)

	var trinket_specs := [
		[&"broken_pendant", "破损挂坠"],
		[&"bone_amulet", "白骨护符"],
		[&"toxic_filter_talisman", "滤毒符印"],
	]

	var t_group := ButtonGroup.new()
	for spec in trinket_specs:
		var t_id: StringName = spec[0]
		var t_title: String = spec[1]
		var btn := Button.new()
		btn.name = "TrinketBtn_" + String(t_id)
		btn.text = t_title
		_style_compact_tab(btn, 13)
		btn.toggle_mode = true
		btn.button_group = t_group
		btn.focus_mode = Control.FOCUS_ALL
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0.0, 32.0)
		btn.pressed.connect(_on_trinket_button_pressed.bind(t_id))
		btn.mouse_entered.connect(btn.grab_focus)
		trinket_tabs.add_child(btn)
		_trinket_buttons.append(btn)

	# 信物的名字已经亮在上面的选中页签里，这里只留描述（高度要让给数值与装备）。
	_trinket_desc_lbl = UiKit.label("", &"FootnoteLabel")
	_trinket_desc_lbl.name = "TrinketDesc"
	_trinket_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_trinket_desc_lbl.modulate = UiKit.ASH
	box.add_child(_trinket_desc_lbl)


## One equipment line: a tag on the left, the item name on the right. The row carries the item's full
## tooltip (description and stat lines) through its meta, so hovering explains without crowding the card.
func _equip_row(parent: Control, row_name: String, tag: String, color: Color) -> Control:
	var row := HBoxContainer.new()
	row.name = row_name
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var tag_lbl := UiKit.label(tag, &"TinyStrongLabel")
	tag_lbl.name = "Tag"
	tag_lbl.custom_minimum_size = Vector2(84.0, 0.0)
	tag_lbl.modulate = color
	row.add_child(tag_lbl)
	var name_lbl := UiKit.label("", &"SubHeadLabel")
	name_lbl.name = "ItemName"
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.modulate = UiKit.EMBER
	row.add_child(name_lbl)
	row.set_meta(&"name_label", name_lbl)
	return row


func _style_compact_tab(btn: Button, font_size: int = 14) -> void:
	btn.theme_type_variation = &"TabButton"
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", Color("#E4DCCC"))
	btn.add_theme_color_override("font_hover_color", UiKit.EMBER)
	btn.add_theme_color_override("font_focus_color", UiKit.EMBER)
	btn.add_theme_color_override("font_pressed_color", UiKit.EMBER)
	btn.add_theme_color_override("font_hover_pressed_color", UiKit.EMBER)
	btn.add_theme_color_override("font_disabled_color", Color("#5E574F"))
	btn.add_theme_constant_override("outline_size", 2)
	btn.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.06, 0.92))

	var states := {
		"normal": Plate.State.NORMAL,
		"hover": Plate.State.SELECTED,
		"pressed": Plate.State.SELECTED,
		"hover_pressed": Plate.State.SELECTED,
		"focus": Plate.State.SELECTED,
		"disabled": Plate.State.DISABLED,
	}
	for s_name in states:
		var sb := Plate.style_box(Plate.Shape.TAG, states[s_name])
		sb.content_margin_left = 6.0
		sb.content_margin_right = 6.0
		sb.content_margin_top = 4.0
		sb.content_margin_bottom = 4.0
		btn.add_theme_stylebox_override(s_name, sb)


# ===========================================================================
# Appearance Strip: skin + rune (v3 loadout decision), at the bottom of the left column
# ===========================================================================

func _build_appearance_strip(parent: Control) -> void:
	# 外观分两行（皮肤 / 刻印）：五个刻印按钮排一行会把字挤没。
	var strip := VBoxContainer.new()
	strip.name = "AppearanceStrip"
	strip.add_theme_constant_override("separation", 4)
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(strip)

	var skin_row := HBoxContainer.new()
	skin_row.name = "SkinRow"
	skin_row.add_theme_constant_override("separation", 6)
	skin_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.add_child(skin_row)
	var tag := UiKit.label("[ 外 观 ]", &"TinyStrongLabel")
	tag.custom_minimum_size = Vector2(72.0, 0.0)
	tag.modulate = UiKit.EMBER
	skin_row.add_child(tag)
	for skin_id in SkinCatalog.ids():
		var btn := Button.new()
		btn.name = "SkinBtn_" + String(skin_id)
		btn.text = SkinCatalog.name_of(skin_id)
		_style_compact_tab(btn, 12)
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(0.0, 26.0)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_skin_button_pressed.bind(skin_id))
		btn.mouse_entered.connect(btn.grab_focus)
		skin_row.add_child(btn)
		_skin_buttons.append(btn)

	var rune_row := HBoxContainer.new()
	rune_row.name = "RuneRow"
	rune_row.add_theme_constant_override("separation", 6)
	rune_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.add_child(rune_row)
	var rune_tag := UiKit.label("[ 刻 印 ]", &"TinyStrongLabel")
	rune_tag.custom_minimum_size = Vector2(72.0, 0.0)
	rune_tag.modulate = Color("#5CE1B6")
	rune_row.add_child(rune_tag)
	var rune_ids: Array[StringName] = [&""]
	for id in RuneCatalog.ids():
		rune_ids.append(id)
	for rune_id in rune_ids:
		var btn := Button.new()
		btn.name = "RuneBtn_" + (String(rune_id) if rune_id != &"" else "none")
		btn.text = "无" if rune_id == &"" else RuneCatalog.name_of(rune_id)
		_style_compact_tab(btn, 12)
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(0.0, 26.0)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_rune_button_pressed.bind(rune_id))
		btn.mouse_entered.connect(btn.grab_focus)
		rune_row.add_child(btn)
		_rune_buttons.append(btn)
	_sync_appearance_buttons()


func _sync_appearance_buttons() -> void:
	for i in _skin_buttons.size():
		var id: StringName = SkinCatalog.ids()[i]
		_skin_buttons[i].set_pressed_no_signal(id == _selected_skin_id)
	var rune_ids: Array[StringName] = [&""]
	for id in RuneCatalog.ids():
		rune_ids.append(id)
	for i in _rune_buttons.size():
		if i < rune_ids.size():
			_rune_buttons[i].set_pressed_no_signal(rune_ids[i] == _selected_rune_id)


func _on_skin_button_pressed(skin_id: StringName) -> void:
	select_skin(skin_id)
	Sfx.play(&"ui_tick", 0.04, -10.0)


func _on_rune_button_pressed(rune_id: StringName) -> void:
	select_rune(rune_id)
	Sfx.play(&"ui_tick", 0.04, -10.0)


func select_skin(skin_id: Variant) -> void:
	var sym := StringName(str(skin_id))
	if not SkinCatalog.has(sym):
		return
	_selected_skin_id = sym
	_skin_picked = true
	_sync_appearance_buttons()


func select_rune(rune_id: Variant) -> void:
	var sym := StringName(str(rune_id))
	if sym != &"" and not RuneCatalog.has(sym):
		return
	_selected_rune_id = sym
	_sync_appearance_buttons()


func get_selected_skin_id() -> StringName:
	return _selected_skin_id


func get_selected_rune_id() -> StringName:
	return _selected_rune_id


# ===========================================================================
# Footer Action Row (embedded inside the modal's footer band)
# ===========================================================================

func _build_footer_actions() -> void:
	var footer := _shell.get("footer") as PanelContainer
	if footer == null:
		return
	footer.custom_minimum_size = Vector2(0.0, 48.0)

	var footer_row := footer.get_node_or_null("Row") as HBoxContainer
	if footer_row == null:
		return
	footer_row.add_theme_constant_override("separation", 14)

	var back_lbl := _shell.get("back") as Control
	if back_lbl != null:
		back_lbl.visible = false

	_cancel_btn = Button.new()
	_cancel_btn.name = "CancelButton"
	_cancel_btn.text = "取 消 (Esc)"
	_cancel_btn.theme_type_variation = &"PlateButton"
	_cancel_btn.custom_minimum_size = Vector2(164.0, 36.0)
	_cancel_btn.focus_mode = Control.FOCUS_ALL
	_footer_plate(_cancel_btn, false)
	_cancel_btn.pressed.connect(cancel)
	_cancel_btn.mouse_entered.connect(_cancel_btn.grab_focus)
	footer_row.add_child(_cancel_btn)

	_embark_btn = Button.new()
	_embark_btn.name = "EmbarkButton"
	_embark_btn.text = "出 发 (Embark)"
	_embark_btn.theme_type_variation = &"PlateButton"
	_embark_btn.custom_minimum_size = Vector2(236.0, 36.0)
	_embark_btn.focus_mode = Control.FOCUS_ALL
	_footer_plate(_embark_btn, true)
	_embark_btn.pressed.connect(embark)
	_embark_btn.mouse_entered.connect(_embark_btn.grab_focus)
	footer_row.add_child(_embark_btn)


## Footer plates: the primary action carries the ember ring at rest (the one "go" signal on the
## screen); the secondary action sits on the dark plate until hovered or focused.
func _footer_plate(btn: Button, primary: bool) -> void:
	var rest := Plate.State.SELECTED if primary else Plate.State.NORMAL
	var states := {
		"normal": rest,
		"hover": Plate.State.SELECTED,
		"pressed": Plate.State.SELECTED,
		"hover_pressed": Plate.State.SELECTED,
		"focus": Plate.State.SELECTED,
		"disabled": Plate.State.DISABLED,
	}
	for s_name in states:
		var sb := Plate.style_box(Plate.Shape.TAG, states[s_name])
		sb.content_margin_left = 16.0
		sb.content_margin_right = 16.0
		btn.add_theme_stylebox_override(s_name, sb)
	btn.add_theme_color_override("font_color", UiKit.EMBER if primary else Color("#E4DCCC"))
	btn.add_theme_color_override("font_hover_color", UiKit.EMBER)
	btn.add_theme_color_override("font_focus_color", UiKit.EMBER)
	btn.add_theme_color_override("font_pressed_color", UiKit.EMBER)


# ===========================================================================
# UI Refresh & State Synchronization
# ===========================================================================

func _refresh_ui() -> void:
	var origin := OriginCatalog.get_origin(_selected_origin_id)
	if origin == null:
		_selected_origin_id = OriginCatalog.ORIGIN_EMBER_VANGUARD
		origin = OriginCatalog.get_origin(_selected_origin_id)

	# 1. Origin cards and their toggle buttons
	var origin_ids := OriginCatalog.get_all_origin_ids()
	for i in mini(_origin_buttons.size(), origin_ids.size()):
		var is_on := origin_ids[i] == _selected_origin_id
		_origin_buttons[i].button_pressed = is_on
		(_origin_cards[i] as OriginCard).set_selected(is_on)

	# 2. Origin details: name, combat focus, lore, bonuses, passive
	_origin_title_lbl.text = origin.title
	_origin_focus_lbl.text = "战斗特色: " + origin.combat_focus
	_origin_lore_lbl.text = origin.lore

	var mod_texts: Array[String] = []
	var mod_keys: Array[StringName] = []
	var m_hp := int(origin.stat_modifiers.get("max_hp", 0))
	var m_atk := int(origin.stat_modifiers.get("attack", 0))
	var m_def := int(origin.stat_modifiers.get("defense", 0))
	var m_res := float(origin.stat_modifiers.get("toxin_resist", 0.0))
	var m_dec := float(origin.stat_modifiers.get("toxin_decay", 0.0))
	var m_spd := float(origin.stat_modifiers.get("speed_mult", 0.0))

	if m_hp > 0: mod_texts.append("生命 +%d" % m_hp); mod_keys.append(&"max_hp")
	if m_atk > 0: mod_texts.append("攻击 +%d" % m_atk); mod_keys.append(&"attack")
	if m_def > 0: mod_texts.append("减免 +%d" % m_def); mod_keys.append(&"defense")
	if m_res > 0.0: mod_texts.append("毒抗 +%d%%" % int(round(m_res * 100.0))); mod_keys.append(&"toxin_resist")
	if m_dec > 0.0: mod_texts.append("排毒 +%.2f/s" % m_dec); mod_keys.append(&"toxin_decay")
	if m_spd > 0.0: mod_texts.append("移速 +%d%%" % int(round(m_spd * 100.0))); mod_keys.append(&"speed_mult")
	_origin_bonuses_lbl.text = "流派特化: " + (" · ".join(mod_texts) if not mod_texts.is_empty() else "均衡基础")
	# 整行取第一项加成的色：多个同色系加成合并成一行时没法逐段染色，
	# 用主导项的颜色让"这一系身份"在面板上有色可循。
	if not mod_keys.is_empty():
		_origin_bonuses_lbl.modulate = BONUS_COLORS.get(mod_keys[0], UiKit.EMBER_ASH)
	else:
		_origin_bonuses_lbl.modulate = UiKit.EMBER_ASH

	var passive_id := PassiveCatalog.for_origin(_selected_origin_id)
	if passive_id != &"":
		_passive_lbl.text = "被动 · %s：%s" % [PassiveCatalog.name_of(passive_id), PassiveCatalog.desc_of(passive_id)]
	else:
		_passive_lbl.text = ""

	# 3. Gear: names on the card, full description and stat lines in the hover tooltip
	var weapon: EquipmentItem = EquipmentCatalog.for_id(origin.default_weapon)
	var armor: EquipmentItem = EquipmentCatalog.for_id(origin.default_armor)
	var trinket: EquipmentItem = EquipmentCatalog.for_id(_selected_trinket_id)

	if weapon != null:
		_weapon_name_lbl.text = weapon.display_name
		_weapon_row.tooltip_text = _item_tip(weapon)
	if armor != null:
		_armor_name_lbl.text = armor.display_name
		_armor_row.tooltip_text = _item_tip(armor)

	# 4. Trinket buttons and details
	var trinket_pool := OriginCatalog.get_trinket_pool()
	for i in mini(_trinket_buttons.size(), trinket_pool.size()):
		_trinket_buttons[i].button_pressed = (trinket_pool[i] == _selected_trinket_id)

	if trinket != null:
		_trinket_desc_lbl.text = trinket.description

	# 5. Six stat pips, recomputed from the same preview the rest of the game uses
	var w_id: StringName = weapon.id if weapon != null else &""
	var a_id: StringName = armor.id if armor != null else &""
	var t_id: StringName = trinket.id if trinket != null else &""
	var preview := OriginCatalog.calculate_preview_stats(_selected_origin_id, w_id, a_id, t_id)

	_set_preview(&"max_hp", float(preview["max_hp"]), "%d 点" % int(preview["max_hp"]),
			"(基础 5 + 身份/装备加成)")
	_set_preview(&"attack", float(preview["attack"]), "+%d" % int(preview["attack"]),
			"(挥砍与弹反攻击力加成)")
	_set_preview(&"defense", float(preview["defense"]), "%d 点" % int(preview["defense"]),
			"(受击直接伤害减免)")
	_set_preview(&"toxin_resist", float(preview["toxin_resist"]),
			"%d%%" % int(round(float(preview["toxin_resist"]) * 100.0)),
			"(延缓毒槽累积，上限 80%)")
	_set_preview(&"toxin_decay", float(preview["toxin_decay"]),
			"+%.2f/s" % float(preview["toxin_decay"]), "(离开毒雾后的排毒加速)")
	_set_preview(&"speed_mult", float(preview["speed_mult"]),
			"%d%%" % int(round(float(preview["speed_mult"]) * 100.0)),
			"(奔跑与无敌帧冲刺倍率)")

	# 6. Set resonance line
	var synergies: Array = preview.get("synergies", [])
	if synergies.size() > 0:
		var syn_names: Array[String] = []
		for s in synergies:
			syn_names.append(String(s.get("name", "套装共鸣")))
		_synergy_badge_lbl.text = "★ 套装: %s" % " · ".join(syn_names)
		_synergy_badge_lbl.modulate = UiKit.EMBER
	else:
		_synergy_badge_lbl.text = "套装共鸣: 未激活"
		_synergy_badge_lbl.modulate = Color(UiKit.ASH.r, UiKit.ASH.g, UiKit.ASH.b, 0.7)


static func _item_tip(item: EquipmentItem) -> String:
	var lines := item.get_stat_lines()
	var stat_text := " · ".join(lines) if not lines.is_empty() else "基础装备"
	return "%s · %s\n%s" % [item.display_name, stat_text, item.description]


## Writes one pip row: the pips move to the new value, the tooltip carries the exact number, and the
## row pulses only when its value text changed.
func _set_preview(key: StringName, pip_value: float, val_text: String, desc_text: String) -> void:
	var meter := _stat_meters.get(key) as PipMeter
	if meter == null:
		return
	meter.value = pip_value
	meter.queue_redraw()
	meter.tooltip_text = "%s  %s\n%s" % [String(_stat_titles.get(key, "")), val_text, desc_text]
	var changed := String(_stat_texts.get(key, "")) != val_text
	_stat_texts[key] = val_text
	if not changed or not is_inside_tree():
		return
	var tween := create_tween()
	tween.tween_property(meter, "modulate", PREVIEW_LIT, PREVIEW_PULSE * 0.45) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(meter, "modulate", Color.WHITE, PREVIEW_PULSE * 0.55) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


# ===========================================================================
# Callbacks & Input
# ===========================================================================

func _on_origin_button_pressed(orig_id: StringName) -> void:
	select_origin(orig_id)
	Sfx.play(&"ui_select")


func _on_trinket_button_pressed(trinket_id: StringName) -> void:
	select_trinket(trinket_id)
	Sfx.play(&"ui_select")


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		cancel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		var focused := get_viewport().gui_get_focus_owner()
		if focused == null or focused == _embark_btn:
			embark()
			get_viewport().set_input_as_handled()


# ===========================================================================
# Public API
# ===========================================================================

func open() -> void:
	if visible:
		return
	_closing = false
	_refresh_ui()
	visible = true
	if _shell.has("play_intro"):
		(_shell.get("play_intro") as Callable).call()
	GameContext.suppress_gameplay_input()
	Sfx.play(&"ui_select")
	_setup_focus_chain()
	if _embark_btn != null:
		_embark_btn.grab_focus.call_deferred()


func _setup_focus_chain() -> void:
	for i in range(_origin_buttons.size()):
		var b := _origin_buttons[i]
		if i > 0:
			b.focus_neighbor_left = _origin_buttons[i - 1].get_path()
		if i < _origin_buttons.size() - 1:
			b.focus_neighbor_right = _origin_buttons[i + 1].get_path()
		if _cancel_btn != null:
			b.focus_neighbor_bottom = _cancel_btn.get_path()

	for i in range(_trinket_buttons.size()):
		var b := _trinket_buttons[i]
		if i > 0:
			b.focus_neighbor_left = _trinket_buttons[i - 1].get_path()
		if i < _trinket_buttons.size() - 1:
			b.focus_neighbor_right = _trinket_buttons[i + 1].get_path()
		if _embark_btn != null:
			b.focus_neighbor_bottom = _embark_btn.get_path()

	if not _origin_buttons.is_empty() and not _trinket_buttons.is_empty():
		_origin_buttons[-1].focus_neighbor_right = _trinket_buttons[0].get_path()
		_trinket_buttons[0].focus_neighbor_left = _origin_buttons[-1].get_path()

	if _cancel_btn != null and _embark_btn != null:
		_cancel_btn.focus_neighbor_right = _embark_btn.get_path()
		_embark_btn.focus_neighbor_left = _cancel_btn.get_path()
		if not _origin_buttons.is_empty():
			_cancel_btn.focus_neighbor_top = _origin_buttons[0].get_path()
		if not _trinket_buttons.is_empty():
			_embark_btn.focus_neighbor_top = _trinket_buttons[0].get_path()


func close() -> void:
	if not visible or _closing:
		return
	_closing = true
	GameContext.suppress_gameplay_input()
	Sfx.play(&"ui_back")
	var on_finish := func() -> void:
		if not is_instance_valid(self):
			return
		_closing = false
		visible = false

	if _shell.has("play_outro") and _shell.get("play_outro") is Callable:
		(_shell.get("play_outro") as Callable).call(on_finish)
	else:
		on_finish.call()


func cancel() -> void:
	if not visible:
		return
	close()
	cancelled.emit()


func embark() -> void:
	if not visible:
		return
	var origin_id := _selected_origin_id
	var loadout := get_selected_loadout()
	close()
	embark_requested.emit(origin_id, loadout)


func is_open() -> bool:
	return visible and not _closing


func select_origin(origin_id: Variant) -> void:
	var sym := StringName(str(origin_id))
	if not OriginCatalog.has_origin(sym):
		return
	_selected_origin_id = sym
	if not _skin_picked:
		_selected_skin_id = SkinCatalog.default_for_origin(sym)
		_sync_appearance_buttons()
	_refresh_ui()


func get_selected_origin_id() -> StringName:
	return _selected_origin_id


func select_trinket(trinket_id: Variant) -> void:
	var sym := StringName(str(trinket_id))
	var pool := OriginCatalog.get_trinket_pool()
	if not pool.has(sym):
		return
	_selected_trinket_id = sym
	_refresh_ui()


func get_selected_trinket_id() -> StringName:
	return _selected_trinket_id


func cycle_trinket(direction: int) -> void:
	var pool := OriginCatalog.get_trinket_pool()
	var idx := pool.find(_selected_trinket_id)
	if idx == -1:
		idx = 0
	var next_idx := posmod(idx + direction, pool.size())
	select_trinket(pool[next_idx])


func get_selected_loadout() -> Dictionary:
	var origin := OriginCatalog.get_origin(_selected_origin_id)
	var weapon_id: StringName = origin.default_weapon if origin != null else &"broken_sword"
	var armor_id: StringName = origin.default_armor if origin != null else &"broken_armor"
	return {
		"weapon": weapon_id,
		"armor": armor_id,
		"trinket": _selected_trinket_id,
		"skin": _selected_skin_id,
		"rune": _selected_rune_id,
	}


func get_preview_stats() -> Dictionary:
	var loadout := get_selected_loadout()
	return OriginCatalog.calculate_preview_stats(
		_selected_origin_id,
		loadout["weapon"],
		loadout["armor"],
		loadout["trinket"]
	)


# ===========================================================================
# Inner widgets
# ===========================================================================

## Origin portrait card. Painted here (chamfered glass, 2px steps), with the portrait, name and combat
## focus on top and a transparent button over the whole body. Selecting lifts the body by LIFT pixels.
class OriginCard extends Control:
	const EDGE := Color("#4A2A18")
	const EMBER := Color("#FFC14A")
	const FILL := Color(0.055, 0.04, 0.075, 0.82)

	var origin_id: StringName = &""
	var button: Button
	var _body: Control
	var _portrait: Portrait
	var _name: Label
	var _focus: Label
	var _tint := Color.WHITE
	var _body_h := 224.0
	var _lift := 4.0
	var _selected := false
	var _hot := false
	var _tween: Tween = null

	func setup(id: StringName, title: String, focus_text: String, tex: Texture2D, tint: Color,
			body_h: float, lift: float) -> void:
		origin_id = id
		_tint = tint
		_body_h = body_h
		_lift = lift
		custom_minimum_size = Vector2(0.0, body_h + lift)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

		_body = Control.new()
		_body.name = "Body"
		_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_body.anchor_left = 0.0
		_body.anchor_right = 1.0
		_body.anchor_top = 0.0
		_body.anchor_bottom = 0.0
		add_child(_body)
		_apply_lift(lift)

		var margin := MarginContainer.new()
		margin.name = "Margin"
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.set_anchors_preset(Control.PRESET_FULL_RECT)
		margin.add_theme_constant_override("margin_left", 14)
		margin.add_theme_constant_override("margin_right", 14)
		margin.add_theme_constant_override("margin_top", 14)
		margin.add_theme_constant_override("margin_bottom", 12)
		_body.add_child(margin)

		var col := VBoxContainer.new()
		col.name = "Content"
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_theme_constant_override("separation", 6)
		margin.add_child(col)

		_portrait = Portrait.new()
		_portrait.name = "Portrait"
		_portrait.set_art(tex)
		_portrait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_portrait.custom_minimum_size = Vector2(0.0, 110.0)
		col.add_child(_portrait)

		_name = UiKit.label(title, &"SubHeadLabel", HORIZONTAL_ALIGNMENT_CENTER)
		_name.name = "Name"
		col.add_child(_name)

		_focus = UiKit.label(focus_text, &"TinyLabel", HORIZONTAL_ALIGNMENT_CENTER)
		_focus.name = "Focus"
		col.add_child(_focus)

		button = Button.new()
		button.name = "Hit"
		button.flat = true
		button.focus_mode = Control.FOCUS_ALL
		button.set_anchors_preset(Control.PRESET_FULL_RECT)
		for state in ["normal", "hover", "pressed", "focus", "hover_pressed", "disabled"]:
			button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		_body.add_child(button)
		button.focus_entered.connect(_on_focus_changed.bind(true))
		button.focus_exited.connect(_on_focus_changed.bind(false))
		# 鼠标悬停已经经由 grab_focus 走同一条焦点路径，这里不再单独接 mouse 信号。
		set_selected(false)

	func set_selected(on: bool) -> void:
		_selected = on
		_name.modulate = EMBER if on else Color(EMBER.r, EMBER.g, EMBER.b, 0.72)
		_portrait.tint = _tint if on else Color(_tint.r * 0.6, _tint.g * 0.6, _tint.b * 0.66, 1.0)
		_animate_lift(0.0 if on else _lift)
		queue_redraw()

	func _on_focus_changed(focused: bool) -> void:
		_hot = focused
		queue_redraw()

	func _animate_lift(target: float) -> void:
		if _tween != null and _tween.is_valid():
			_tween.kill()
		if not is_inside_tree():
			_apply_lift(target)
			return
		_tween = create_tween()
		_tween.tween_method(_apply_lift, _current_lift(), target, 0.12) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	func _current_lift() -> float:
		return _body.offset_top if _body != null else _lift

	## Moves the card body vertically (integer pixels, so the pixel art stays on the 2px grid).
	func _apply_lift(y: float) -> void:
		var py := roundf(y)
		if _body == null:
			return
		_body.offset_top = py
		_body.offset_bottom = py + _body_h
		queue_redraw()

	func _draw() -> void:
		if _body == null:
			return
		var w := size.x
		var y0 := _body.offset_top
		var h := _body_h
		var lit := _selected or _hot
		var edge := EMBER if lit else EDGE
		var line := 2.0 if _selected else 1.0
		# 落影
		draw_rect(Rect2(6.0, y0 + 6.0, w - 6.0, h - 2.0), Color(0.0, 0.0, 0.0, 0.30))
		# 本体：四角各切 6px，2px 阶梯
		draw_rect(Rect2(6.0, y0, w - 12.0, h), FILL)
		draw_rect(Rect2(2.0, y0 + 2.0, w - 4.0, h - 4.0), FILL)
		draw_rect(Rect2(0.0, y0 + 6.0, w, h - 12.0), FILL)
		if _selected:
			# 选中：卡顶的余烬底光，三级阶梯向下淡出（不用渐变，保持像素感）
			for step in 3:
				draw_rect(Rect2(6.0, y0 + 2.0 + float(step) * 8.0, w - 12.0, 8.0),
						Color(EMBER.r, EMBER.g, EMBER.b, 0.08 - 0.025 * float(step)))
		# 描边：直边 + 切角的阶梯小段
		draw_rect(Rect2(6.0, y0, w - 12.0, line), edge)
		draw_rect(Rect2(6.0, y0 + h - line, w - 12.0, line), edge)
		draw_rect(Rect2(0.0, y0 + 6.0, line, h - 12.0), edge)
		draw_rect(Rect2(w - line, y0 + 6.0, line, h - 12.0), edge)
		draw_rect(Rect2(2.0, y0 + 2.0, 4.0, line), edge)
		draw_rect(Rect2(2.0, y0 + 2.0, line, 4.0), edge)
		draw_rect(Rect2(w - 6.0, y0 + 2.0, 4.0, line), edge)
		draw_rect(Rect2(w - 2.0 - line, y0 + 2.0, line, 4.0), edge)
		draw_rect(Rect2(2.0, y0 + h - 2.0 - line, 4.0, line), edge)
		draw_rect(Rect2(2.0, y0 + h - 6.0, line, 4.0), edge)
		draw_rect(Rect2(w - 6.0, y0 + h - 2.0 - line, 4.0, line), edge)
		draw_rect(Rect2(w - 2.0 - line, y0 + h - 6.0, line, 4.0), edge)
		if _selected:
			# 顶边一道亮线：选中卡独有的余烬标记
			draw_rect(Rect2(12.0, y0, w - 24.0, 2.0), EMBER)


## Portrait: the drawn pixels of the idle frame (transparent margins cropped away), scaled by a whole
## number and centred, so the three characters read at a similar figure height. Missing art falls back
## to a diamond seal.
class Portrait extends Control:
	const MAX_SCALE := 5.0
	var texture: Texture2D = null
	var tint := Color.WHITE
	var _crop := Rect2()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	static var _crops: Dictionary = {}

	func set_art(tex: Texture2D) -> void:
		texture = tex
		_crop = Rect2()
		if tex != null:
			var key := tex.get_instance_id()
			if not _crops.has(key):
				_crops[key] = _opaque_bounds(tex)
			_crop = _crops[key]
		queue_redraw()

	## Bounding box of every pixel with some alpha. Falls back to the whole texture when the art cannot be
	## read or has no alpha, and to the texture size when the box is too small to be the figure.
	static func _opaque_bounds(tex: Texture2D) -> Rect2:
		var logical := tex.get_size()
		var whole := Rect2(Vector2.ZERO, logical)
		var img := tex.get_image()
		if img == null:
			return whole
		if img.is_compressed():
			img.decompress()
		# The loader may hand back a higher-density companion image; scan its pixels, then map the
		# box into the texture's logical size (the space draw_texture_rect_region reads).
		var w := img.get_width()
		var h := img.get_height()
		var x0 := w
		var y0 := h
		var x1 := -1
		var y1 := -1
		for y in h:
			for x in w:
				if img.get_pixel(x, y).a > 0.02:
					x0 = mini(x0, x)
					x1 = maxi(x1, x)
					y0 = mini(y0, y)
					y1 = maxi(y1, y)
		if x1 < 0 or (x1 - x0) < 4 or (y1 - y0) < 4 or w <= 0 or h <= 0:
			return whole
		var sx := logical.x / float(w)
		var sy := logical.y / float(h)
		var lx0 := floorf(float(x0) * sx)
		var ly0 := floorf(float(y0) * sy)
		var lx1 := ceilf(float(x1 + 1) * sx)
		var ly1 := ceilf(float(y1 + 1) * sy)
		return Rect2(lx0, ly0, lx1 - lx0, ly1 - ly0)

	func _draw() -> void:
		if texture == null or _crop.size.x <= 0.0 or _crop.size.y <= 0.0:
			GlassKit.diamond(self, Vector2(floorf(size.x * 0.5), floorf(size.y * 0.5)), 18.0,
					Color(tint.r, tint.g, tint.b, 0.6))
			return
		var k := maxf(1.0, floorf(minf(size.x / _crop.size.x, size.y / _crop.size.y)))
		k = minf(k, MAX_SCALE)
		var dw := _crop.size.x * k
		var dh := _crop.size.y * k
		var x := floorf((size.x - dw) * 0.5)
		var y := floorf((size.y - dh) * 0.5)
		draw_texture_rect_region(texture, Rect2(x, y, dw, dh), _crop, tint)


## Segmented pip meter: COUNT segments, each worth UNIT. A partly filled segment is drawn to the 2px grid.
class PipMeter extends Control:
	const GAP := 3.0
	const TRACK := Color("#241C22")
	var value := 0.0
	var unit := 1.0
	var count := 1
	var color := Color.WHITE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		custom_minimum_size = Vector2(0.0, 8.0)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func set_scale_for(u: float, n: int, c: Color) -> void:
		unit = u
		count = n
		color = c
		queue_redraw()

	func _draw() -> void:
		var h := size.y
		var seg := (size.x - GAP * float(count - 1)) / float(count)
		for i in count:
			var x := floorf(float(i) * (seg + GAP))
			var w := floorf(seg)
			draw_rect(Rect2(x, 0.0, w, h), TRACK)
			var frac := clampf(value / unit - float(i), 0.0, 1.0)
			if frac >= 0.999:
				draw_rect(Rect2(x, 0.0, w, h), color)
			elif frac > 0.0:
				var fw := floorf(w * frac / 2.0) * 2.0
				if fw > 0.0:
					draw_rect(Rect2(x, 0.0, fw, h), color)


## 玻璃卡根节点：面板容器（负责尺寸与内边距），每帧把背后的玻璃框体（置顶、脱离容器排版）
## 对齐到自己的矩形上，框体画在内容后面。
class GlassCardRoot extends PanelContainer:
	var frame: Control = null

	func _process(_delta: float) -> void:
		if frame == null or not is_instance_valid(frame):
			return
		if frame.global_position != global_position:
			frame.global_position = global_position
		if frame.size != size:
			frame.size = size
