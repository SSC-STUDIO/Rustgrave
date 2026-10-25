class_name CharacterSelectScreen
extends CanvasLayer
## CharacterSelectScreen: Modal interface for choosing character origin and starting loadout.
## Complies strictly with tests/modal_screens_test.gd invariants:
##   - Built on CanvasLayer (layer = 8)
##   - Uses Modal.build(self, ...) shell (ModalRoot/Card, ModalRoot/Veil, ModalRoot/ModalEmbers)
##   - Card width < 1180.0, veil alpha < 0.8
##
## Three-column layout:
##   - Left: 3 Origin Selector Tabs/Buttons (Ember Vanguard, Scrap Scavenger, Rust Automaton),
##     displaying title, lore, combat focus description.
##   - Middle: Dynamic 6-stat preview (Max HP, Attack, Defense, Toxin Resist, Toxin Decay, Speed Multiplier)
##     calculated dynamically via OriginCatalog.calculate_preview_stats.
##   - Right: Starting equipment overview (displaying preset weapon & armor names and descriptions)
##     and Customizable Trinket Picker from [broken_pendant, bone_amulet, toxic_filter_talisman].
##   - Bottom Action: "点燃启程 (Embark)" button and "取消 (Cancel)" button / Esc hint.

signal embark_requested(origin_id: StringName, loadout: Dictionary)
signal cancelled

const NAV_HINT := "方向键/点击 切换流派与信物 · Enter 启程 · Esc 取消"

const Modal := preload("res://scripts/ui/ui_modal.gd")
const Ornaments := preload("res://scripts/ui/ui_ornament.gd")
const Plate := preload("res://scripts/ui/menu_plate.gd")

const COLOR_ATTACK := Color("#FFC14A")   # Warm yellow
const COLOR_DEFENSE := Color("#BAC4CC")  # Iron grey
const COLOR_TOXIN := Color("#5CE1B6")    # Teal/cyan
const COLOR_SPEED := Color("#5CB3FF")    # Agility blue
const COLOR_HP := Color("#76E074")       # Vitality green

## 流派特化行的语义色：与装备面板的 STAT_COLORS 同一套色相语言，
## 玩家在两个屏之间切换时不用重新学"哪个颜色是哪项数值"。
const BONUS_COLORS := {
	&"max_hp": COLOR_HP,
	&"attack": COLOR_ATTACK,
	&"defense": COLOR_DEFENSE,
	&"toxin_resist": COLOR_TOXIN,
	&"toxin_decay": COLOR_TOXIN,
	&"speed_mult": COLOR_SPEED,
}

## 数值切换的脉冲：换流派时六行预览数字不是"跳"到新值，而是从旧值淡到
## 新值并轻微提亮，0.18s 内读完 —— 慢了会拖住连续切换，快了看不出在动。
const PREVIEW_PULSE := 0.18
## 脉冲提亮的幅度：>1 的 modulate 在像素画上是"这一行刚刚变了"的信号，
## 幅度再大会和悬停高亮混在一起。
const PREVIEW_LIT := Color(1.25, 1.18, 1.06)

var _selected_origin_id: StringName = OriginCatalog.ORIGIN_EMBER_VANGUARD
var _selected_trinket_id: StringName = OriginCatalog.ALLOWED_TRINKETS[0]

var _shell: Dictionary = {}
var _root: Control

# Origin UI Elements
var _origin_buttons: Array[Button] = []
var _origin_title_lbl: Label
var _origin_focus_lbl: Label
var _origin_bonuses_lbl: Label
var _origin_lore_lbl: Label

# Stat Preview UI Elements
var _stat_val_labels: Dictionary = {}
var _stat_detail_labels: Dictionary = {}
var _synergy_badge_lbl: Label

# Equipment UI Elements
var _weapon_name_lbl: Label
var _weapon_desc_lbl: Label
var _armor_name_lbl: Label
var _armor_desc_lbl: Label

# Trinket UI Elements
var _trinket_buttons: Array[Button] = []
var _trinket_name_lbl: Label
var _trinket_desc_lbl: Label

# Action Buttons
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
		"kicker": "陵 墓 废 土 · 战 斗 流 派",
		"size": Vector2(1120.0, 646.0),
		"hint": NAV_HINT,
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
	main_vbox.add_theme_constant_override("separation", 10)
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(main_vbox)

	# Columns row
	var columns := HBoxContainer.new()
	columns.name = "Columns"
	columns.add_theme_constant_override("separation", 14)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(columns)

	_build_left_column(columns)
	_build_middle_column(columns)
	_build_right_column(columns)

	_build_footer_actions()


# ===========================================================================
# Left Column: Origin Selection & Lore
# ===========================================================================

func _build_left_column(parent: Control) -> void:
	var col := VBoxContainer.new()
	col.name = "LeftColumn"
	col.custom_minimum_size = Vector2(330.0, 0.0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	parent.add_child(col)

	var header := UiKit.label("【 骑 士 身 份 】", &"TinyStrongLabel", HORIZONTAL_ALIGNMENT_CENTER)
	header.modulate = UiKit.EMBER
	col.add_child(header)

	# 3 Origin Selector Tabs/Buttons
	var tabs_box := HBoxContainer.new()
	tabs_box.name = "OriginTabs"
	tabs_box.add_theme_constant_override("separation", 6)
	tabs_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(tabs_box)

	var origin_specs := [
		[OriginCatalog.ORIGIN_EMBER_VANGUARD, "余烬重骑"],
		[OriginCatalog.ORIGIN_SCRAP_SCAVENGER, "废料剑客"],
		[OriginCatalog.ORIGIN_RUST_AUTOMATON, "锈械学者"],
	]

	var group := ButtonGroup.new()
	for spec in origin_specs:
		var orig_id: StringName = spec[0]
		var title_text: String = spec[1]
		var btn := Button.new()
		btn.name = "OriginBtn_" + String(orig_id)
		btn.text = title_text
		_style_compact_tab(btn, 14)
		btn.toggle_mode = true
		btn.button_group = group
		btn.focus_mode = Control.FOCUS_ALL
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0.0, 34.0)
		btn.pressed.connect(_on_origin_button_pressed.bind(orig_id))
		btn.mouse_entered.connect(btn.grab_focus)
		tabs_box.add_child(btn)
		_origin_buttons.append(btn)

	# Origin Details Plaque
	var plaque := UiKit.panel(&"StonePanel")
	plaque.name = "OriginDetailsPlaque"
	plaque.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plaque.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(plaque)

	var plaque_box := VBoxContainer.new()
	plaque_box.name = "Content"
	plaque_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	plaque_box.add_theme_constant_override("separation", 8)
	plaque.add_child(plaque_box)

	# 身份剑：竖在铭牌顶上，剑格压住下面的流派名 —— 这柄"挂着的剑"就是
	# 选中流派的视觉锚，切流派时它不动，动的是剑下面的文字。
	var title_row := HBoxContainer.new()
	title_row.name = "TitleRow"
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", 8)
	plaque_box.add_child(title_row)
	title_row.add_child(Ornaments.sword())

	_origin_title_lbl = UiKit.label("余烬重骑", &"HeadLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_origin_title_lbl.name = "OriginTitle"
	_origin_title_lbl.modulate = UiKit.EMBER
	_origin_title_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(_origin_title_lbl)

	_origin_focus_lbl = UiKit.label("稳固防御与高生存", &"TinyStrongLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_origin_focus_lbl.name = "OriginFocus"
	_origin_focus_lbl.modulate = COLOR_DEFENSE
	plaque_box.add_child(_origin_focus_lbl)

	# 流派特化：每项加成按它影响的数值染色（生命绿、攻击黄、减免铁灰、
	# 毒素青、速度蓝），整行读下来就是一张小数值条，不用逐项对名字。
	_origin_bonuses_lbl = UiKit.label("流派特化: 生命上限 +1 · 伤害减免 +1", &"FootnoteLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_origin_bonuses_lbl.name = "OriginBonuses"
	_origin_bonuses_lbl.modulate = UiKit.EMBER_ASH
	plaque_box.add_child(_origin_bonuses_lbl)

	var stub := Ornaments.stub_rule(false)
	stub.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	plaque_box.add_child(stub)

	_origin_lore_lbl = UiKit.label("", &"BodyLabel")
	_origin_lore_lbl.name = "OriginLore"
	_origin_lore_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_origin_lore_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_origin_lore_lbl.modulate = Color(UiKit.ASH.r, UiKit.ASH.g, UiKit.ASH.b, 0.95)
	plaque_box.add_child(_origin_lore_lbl)


# ===========================================================================
# Middle Column: Dynamic 6-Stat Preview
# ===========================================================================

func _build_middle_column(parent: Control) -> void:
	var col := VBoxContainer.new()
	col.name = "MiddleColumn"
	col.custom_minimum_size = Vector2(300.0, 0.0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	parent.add_child(col)

	var header := UiKit.label("【 数 值 联 动 预 览 】", &"TinyStrongLabel", HORIZONTAL_ALIGNMENT_CENTER)
	header.modulate = UiKit.EMBER
	col.add_child(header)

	var plaque := UiKit.panel(&"StonePanel")
	plaque.name = "StatsPlaque"
	plaque.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plaque.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(plaque)

	var plaque_box := VBoxContainer.new()
	plaque_box.name = "Content"
	plaque_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	plaque_box.add_theme_constant_override("separation", 4)
	plaque.add_child(plaque_box)

	var stat_keys := [
		[&"max_hp", "生命上限", COLOR_HP],
		[&"attack", "近战攻击", COLOR_ATTACK],
		[&"defense", "伤害减免", COLOR_DEFENSE],
		[&"toxin_resist", "毒素抗性", COLOR_TOXIN],
		[&"toxin_decay", "自然排毒", COLOR_TOXIN],
		[&"speed_mult", "移动修正", COLOR_SPEED],
	]

	for item in stat_keys:
		var key: StringName = item[0]
		var title: String = item[1]
		var color: Color = item[2]

		var row := VBoxContainer.new()
		row.name = "Row_" + String(key)
		row.add_theme_constant_override("separation", 1)
		plaque_box.add_child(row)

		var top_line := HBoxContainer.new()
		top_line.name = "Top"
		row.add_child(top_line)

		var name_lbl := UiKit.label(title, &"TinyStrongLabel")
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.modulate = Color(1.0, 1.0, 1.0, 0.9)
		top_line.add_child(name_lbl)

		var val_lbl := UiKit.label("0", &"SubHeadLabel", HORIZONTAL_ALIGNMENT_RIGHT)
		val_lbl.name = "Val"
		val_lbl.modulate = color
		top_line.add_child(val_lbl)
		_stat_val_labels[key] = val_lbl

		var desc_lbl := UiKit.label("", &"FootnoteLabel")
		desc_lbl.name = "Desc"
		desc_lbl.modulate = Color(UiKit.ASH.r, UiKit.ASH.g, UiKit.ASH.b, 0.8)
		row.add_child(desc_lbl)
		_stat_detail_labels[key] = desc_lbl

	var stub := Ornaments.stub_rule(false)
	stub.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	plaque_box.add_child(stub)

	_synergy_badge_lbl = UiKit.label("套装共鸣: 无", &"FootnoteLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_synergy_badge_lbl.name = "SynergyBadge"
	_synergy_badge_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_synergy_badge_lbl.modulate = UiKit.EMBER
	plaque_box.add_child(_synergy_badge_lbl)


# ===========================================================================
# Right Column: Equipment Overview & Trinket Picker
# ===========================================================================

func _build_right_column(parent: Control) -> void:
	var col := VBoxContainer.new()
	col.name = "RightColumn"
	col.custom_minimum_size = Vector2(390.0, 0.0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	parent.add_child(col)

	var header := UiKit.label("【 启 程 配 装 与 信 物 】", &"TinyStrongLabel", HORIZONTAL_ALIGNMENT_CENTER)
	header.modulate = UiKit.EMBER
	col.add_child(header)

	var plaque := UiKit.panel(&"StonePanel")
	plaque.name = "GearPlaque"
	plaque.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plaque.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(plaque)

	var plaque_box := VBoxContainer.new()
	plaque_box.name = "Content"
	plaque_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	plaque_box.add_theme_constant_override("separation", 6)
	plaque.add_child(plaque_box)

	# Preset Weapon Box
	var w_box := VBoxContainer.new()
	w_box.name = "WeaponBox"
	w_box.add_theme_constant_override("separation", 2)
	plaque_box.add_child(w_box)

	var w_slot_row := HBoxContainer.new()
	w_box.add_child(w_slot_row)
	var w_tag := UiKit.label("[ 预设武器 ]", &"TinyStrongLabel")
	w_tag.modulate = COLOR_ATTACK
	w_slot_row.add_child(w_tag)
	_weapon_name_lbl = UiKit.label("", &"SubHeadLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	_weapon_name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weapon_name_lbl.modulate = UiKit.EMBER
	w_slot_row.add_child(_weapon_name_lbl)

	_weapon_desc_lbl = UiKit.label("", &"FootnoteLabel")
	_weapon_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_weapon_desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weapon_desc_lbl.modulate = UiKit.ASH
	w_box.add_child(_weapon_desc_lbl)

	# Preset Armor Box
	var a_box := VBoxContainer.new()
	a_box.name = "ArmorBox"
	a_box.add_theme_constant_override("separation", 2)
	plaque_box.add_child(a_box)

	var a_slot_row := HBoxContainer.new()
	a_box.add_child(a_slot_row)
	var a_tag := UiKit.label("[ 预设护甲 ]", &"TinyStrongLabel")
	a_tag.modulate = COLOR_DEFENSE
	a_slot_row.add_child(a_tag)
	_armor_name_lbl = UiKit.label("", &"SubHeadLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	_armor_name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_armor_name_lbl.modulate = COLOR_DEFENSE
	a_slot_row.add_child(_armor_name_lbl)

	_armor_desc_lbl = UiKit.label("", &"FootnoteLabel")
	_armor_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_armor_desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_armor_desc_lbl.modulate = UiKit.ASH
	a_box.add_child(_armor_desc_lbl)

	var stub := Ornaments.stub_rule(false)
	stub.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	plaque_box.add_child(stub)

	# Trinket Picker Section
	var t_header := UiKit.label("[ 随身信物 · 自由选取 ]", &"TinyStrongLabel", HORIZONTAL_ALIGNMENT_CENTER)
	t_header.modulate = COLOR_TOXIN
	plaque_box.add_child(t_header)

	var trinket_tabs := HBoxContainer.new()
	trinket_tabs.name = "TrinketTabs"
	trinket_tabs.add_theme_constant_override("separation", 4)
	trinket_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plaque_box.add_child(trinket_tabs)

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
	var t_info_box := VBoxContainer.new()
	t_info_box.name = "TrinketInfoBox"
	t_info_box.add_theme_constant_override("separation", 2)
	t_info_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	plaque_box.add_child(t_info_box)

	_trinket_name_lbl = UiKit.label("", &"SubHeadLabel")
	_trinket_name_lbl.modulate = COLOR_TOXIN
	t_info_box.add_child(_trinket_name_lbl)

	_trinket_desc_lbl = UiKit.label("", &"FootnoteLabel")
	_trinket_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_trinket_desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trinket_desc_lbl.modulate = UiKit.ASH
	_trinket_desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	t_info_box.add_child(_trinket_desc_lbl)


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
# Footer Action Row (Embedded inside Card's BandPanel)
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
	_cancel_btn.theme_type_variation = &"SettingsButton"
	_cancel_btn.custom_minimum_size = Vector2(130.0, 36.0)
	_cancel_btn.focus_mode = Control.FOCUS_ALL
	_cancel_btn.pressed.connect(cancel)
	_cancel_btn.mouse_entered.connect(_cancel_btn.grab_focus)
	footer_row.add_child(_cancel_btn)

	_embark_btn = Button.new()
	_embark_btn.name = "EmbarkButton"
	_embark_btn.text = "点 燃 启 程 (Embark)"
	_embark_btn.theme_type_variation = &"SettingsButton"
	_embark_btn.custom_minimum_size = Vector2(210.0, 36.0)
	_embark_btn.focus_mode = Control.FOCUS_ALL
	_embark_btn.pressed.connect(embark)
	_embark_btn.mouse_entered.connect(_embark_btn.grab_focus)
	footer_row.add_child(_embark_btn)


# ===========================================================================
# UI Refresh & State Synchronization
# ===========================================================================

func _refresh_ui() -> void:
	var origin := OriginCatalog.get_origin(_selected_origin_id)
	if origin == null:
		_selected_origin_id = OriginCatalog.ORIGIN_EMBER_VANGUARD
		origin = OriginCatalog.get_origin(_selected_origin_id)

	# 1. Update origin tabs
	var origin_ids := OriginCatalog.get_all_origin_ids()
	for i in mini(_origin_buttons.size(), origin_ids.size()):
		_origin_buttons[i].button_pressed = (origin_ids[i] == _selected_origin_id)

	# 2. Update origin details
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

	# 3. Update equipment info
	var weapon: EquipmentItem = EquipmentCatalog.for_id(origin.default_weapon)
	var armor: EquipmentItem = EquipmentCatalog.for_id(origin.default_armor)
	var trinket: EquipmentItem = EquipmentCatalog.for_id(_selected_trinket_id)

	if weapon != null:
		_weapon_name_lbl.text = weapon.display_name
		_weapon_desc_lbl.text = weapon.description
	if armor != null:
		_armor_name_lbl.text = armor.display_name
		_armor_desc_lbl.text = armor.description

	# 4. Update trinket buttons & details
	var trinket_pool := OriginCatalog.get_trinket_pool()
	for i in mini(_trinket_buttons.size(), trinket_pool.size()):
		_trinket_buttons[i].button_pressed = (trinket_pool[i] == _selected_trinket_id)

	if trinket != null:
		_trinket_name_lbl.text = trinket.display_name
		_trinket_desc_lbl.text = trinket.description

	# 5. Calculate and update 6 dynamic preview stats
	var w_id: StringName = weapon.id if weapon != null else &""
	var a_id: StringName = armor.id if armor != null else &""
	var t_id: StringName = trinket.id if trinket != null else &""
	var preview := OriginCatalog.calculate_preview_stats(_selected_origin_id, w_id, a_id, t_id)

	# 换流派/换信物时，只有数值变了的行才脉冲 —— 全屏一起闪会像出错，
	# 只闪变了的行才能读出"哦，这一项被这件装备影响了"。
	_set_preview(&"max_hp", "%d 点" % int(preview["max_hp"]), "(基础 5 + 身份/装备加成)")
	_set_preview(&"attack", "+%d" % int(preview["attack"]), "(挥砍与弹反攻击力加成)")
	_set_preview(&"defense", "%d 点" % int(preview["defense"]), "(受击直接伤害减免)")
	_set_preview(&"toxin_resist", "%d%%" % int(round(float(preview["toxin_resist"]) * 100.0)), "(延缓毒槽累积，上限 80%)")
	_set_preview(&"toxin_decay", "+%.2f/s" % float(preview["toxin_decay"]), "(离开毒雾后的排毒加速)")
	_set_preview(&"speed_mult", "%d%%" % int(round(float(preview["speed_mult"]) * 100.0)), "(奔跑与无敌帧冲刺倍率)")

	# 6. Update synergy indicator
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


## 写一行预览值：文本变化时给数字一个 0.18s 的提亮脉冲。
## 明细行只写文本，它比数值长、脉冲会让整行发糊。
func _set_preview(key: StringName, val_text: String, desc_text: String) -> void:
	var val_lbl := _stat_val_labels.get(key) as Label
	var desc_lbl := _stat_detail_labels.get(key) as Label
	if val_lbl == null or desc_lbl == null:
		return
	var changed := val_lbl.text != val_text
	val_lbl.text = val_text
	desc_lbl.text = desc_text
	if not changed or not is_inside_tree():
		return
	# 脉冲用 modulate 叠加：>1 的倍率提亮后回到本色，和悬停高亮同一个语言，
	# 只是这里自动播完，不需要玩家停在上面。
	var base: Color = val_lbl.modulate
	var tween := create_tween()
	tween.tween_property(val_lbl, "modulate", PREVIEW_LIT, PREVIEW_PULSE * 0.45) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(val_lbl, "modulate", base, PREVIEW_PULSE * 0.55) \
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
	if _closing:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
			get_viewport().set_input_as_handled()
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
	_set_buttons_disabled(false)
	var hint := _shell.get("hint") as Label
	if hint != null:
		hint.text = NAV_HINT
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


var _closing := false
var _close_generation := 0


func close() -> void:
	_close_with_result()


## Latch the outcome before the asynchronous animation. Exactly one outcome is
## emitted after the veil is gone; keyboard repeat and double clicks cannot race it.
func _close_with_result(on_done: Callable = Callable()) -> void:
	if not visible or _closing:
		return
	_closing = true
	_close_generation += 1
	var generation := _close_generation
	_set_buttons_disabled(true)
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and _root.is_ancestor_of(focused):
		focused.release_focus()
	GameContext.suppress_gameplay_input()
	Sfx.play(&"ui_back")
	(_shell.get("play_outro") as Callable).call(func() -> void:
		if not is_instance_valid(self) or not _closing or generation != _close_generation:
			return
		_closing = false
		visible = false
		if on_done.is_valid():
			on_done.call()
	)


func _set_buttons_disabled(disabled: bool) -> void:
	for button in _origin_buttons + _trinket_buttons + [_embark_btn, _cancel_btn]:
		if button != null:
			button.disabled = disabled


func show_start_error() -> void:
	var hint := _shell.get("hint") as Label
	if hint != null:
		hint.text = "保存失败，原进度已保留。请重试或取消。"


func cancel() -> void:
	if not visible or _closing:
		return
	_close_with_result(func() -> void: cancelled.emit())


func embark() -> void:
	if not visible or _closing:
		return
	var origin_id := _selected_origin_id
	var loadout := get_selected_loadout().duplicate(true)
	_close_with_result(func() -> void: embark_requested.emit(origin_id, loadout))


func is_open() -> bool:
	return visible


func select_origin(origin_id: Variant) -> void:
	if _closing:
		return
	var sym := StringName(str(origin_id))
	if not OriginCatalog.has_origin(sym):
		return
	_selected_origin_id = sym
	_refresh_ui()


func get_selected_origin_id() -> StringName:
	return _selected_origin_id


func select_trinket(trinket_id: Variant) -> void:
	if _closing:
		return
	var sym := StringName(str(trinket_id))
	var pool := OriginCatalog.get_trinket_pool()
	if not pool.has(sym):
		return
	_selected_trinket_id = sym
	_refresh_ui()


func get_selected_trinket_id() -> StringName:
	return _selected_trinket_id


func cycle_trinket(direction: int) -> void:
	if _closing:
		return
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
		"trinket": _selected_trinket_id
	}


func get_preview_stats() -> Dictionary:
	var loadout := get_selected_loadout()
	return OriginCatalog.calculate_preview_stats(
		_selected_origin_id,
		loadout["weapon"],
		loadout["armor"],
		loadout["trinket"]
	)
