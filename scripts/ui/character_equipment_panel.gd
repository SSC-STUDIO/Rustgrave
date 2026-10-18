class_name CharacterEquipmentPanel
extends CanvasLayer
## Character Attributes & Equipment Inventory UI Panel (Milestone 4).
## Displays core character attributes, active set synergies, 3 equipped slots,
## 16-slot bag grid, and an interactive item inspection tooltip box.

signal opened()
signal closed()
signal item_equipped(slot: StringName, item: Variant)
signal item_unequipped(slot: StringName, item: Variant)

const Ornaments := preload("res://scripts/ui/ui_ornament.gd")
const Modal := preload("res://scripts/ui/ui_modal.gd")
const Plate := preload("res://scripts/ui/menu_plate.gd")
const OriginCatalogScript := preload("res://scripts/data/origin_catalog.gd")
const CharacterOriginScript := preload("res://scripts/data/character_origin.gd")

const SLOT_WEAPON: StringName = &"weapon"
const SLOT_ARMOR: StringName = &"armor"
const SLOT_TRINKET: StringName = &"trinket"
const SLOTS: Array[StringName] = [SLOT_WEAPON, SLOT_ARMOR, SLOT_TRINKET]

## 属性行的色谱：与身份选择屏共用一套语义色（攻击=暖黄、防御=铁灰、
## 毒素=青绿、速度=蓝、生命=绿）。数值与明细用同一色相的不同明度，
## 扫一眼就知道哪行是哪项，不用逐行读小字。
const STAT_COLORS := {
	&"max_hp": Color("#76E074"),
	&"attack": Color("#FFC14A"),
	&"defense": Color("#BAC4CC"),
	&"toxin_resist": Color("#5CE1B6"),
	&"toxin_decay": Color("#5CE1B6"),
	&"speed_mult": Color("#5CB3FF"),
}
## 空槽 / 空格位的占位色：比 FootnoteLabel 的灰再压暗一档，与"有货"的琥珀
## 形成对比，空状态不抢眼但有存在感。
const SLOT_EMPTY := Color(0.42, 0.40, 0.38, 0.75)

const MAX_BAG_CAPACITY: int = 16
const TAB_HOLD_THRESHOLD: float = 0.22

var is_open: bool = false
var _managed_tree_pause: bool = false
var _closing: bool = false  ## 退场动画进行中：防连按 Tab 起两条 tween
var _tab_press_time: float = -1.0
var _player: Player = null
var _origin_override: StringName = &""
var _shell: Dictionary = {}
var _root: Control = null

# Left Column (Attributes)
var origin_title_label: Label = null
var _attr_rows: Dictionary = {} # stat_name -> { "val": Label, "detail": Label, "row": Control, "name": Label }
var _synergies_container: VBoxContainer = null

# Right Column (Equipment & Bag)
var _slot_buttons: Dictionary = {} # slot -> Button
var _slot_labels: Dictionary = {}  # slot -> { "title": Label, "name": Label, "stat": Label }
var _bag_buttons: Array[Button] = []
var _bag_capacity_label: Label = null

# Tooltip / Inspector
var _tooltip_name: Label = null
var _tooltip_type_set: Label = null
var _tooltip_stats: Label = null
var _tooltip_desc: Label = null
var _tooltip_action_hint: Label = null
var _tooltip_action_btn: Button = null

# Inspected State
var _inspected_item: Variant = null
var _inspected_source: StringName = &"" # &"slot" or &"bag"
var _inspected_slot: StringName = &""
var _inspected_bag_idx: int = -1


func _ready() -> void:
	layer = 21
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	WorldClock.isolate_ui_layer(self)
	PresentationMetrics.bind_layer(self)
	_build()
	GameEvents.player_died.connect(_on_player_died)


func _exit_tree() -> void:
	_unbind_player()


func can_open() -> bool:
	if visible:
		return false
	if Director != null:
		if Director.is_fading() or Director.choice_hold or Director.is_input_locked() or Director.playing:
			return false
	var p := _resolve_player()
	if p != null:
		if "health" in p and p.health != null and p.health.current <= 0:
			return false
		if "cutscene_locked" in p and p.cutscene_locked:
			return false
	return true


func open_panel(from_pause_menu: bool = false) -> void:
	if visible:
		return

	# Determine pause management: if already paused when opened, preserve external pause
	var already_paused := get_tree().paused
	_managed_tree_pause = not from_pause_menu and not already_paused

	is_open = true
	_closing = false
	visible = true

	if _managed_tree_pause:
		get_tree().paused = true
		if Director != null:
			Director.suspend()

	GameContext.suppress_gameplay_input()
	UiKit.sfx(&"ui_pause", &"ui_select")

	if _shell.has("play_intro"):
		var intro_callable: Variant = _shell.get("play_intro")
		if intro_callable is Callable:
			(intro_callable as Callable).call()

	_bind_player()
	_refresh_all()
	_inspect_slot(SLOT_WEAPON)

	if _slot_buttons.has(SLOT_WEAPON):
		var btn: Button = _slot_buttons[SLOT_WEAPON]
		if is_instance_valid(btn):
			btn.grab_focus.call_deferred()

	opened.emit()


func close_panel() -> void:
	if not visible or _closing:
		return

	is_open = false
	_closing = true

	# Release focus if owned by panel
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner != null and is_ancestor_of(focus_owner):
		focus_owner.release_focus()

	# Triple-shield against physics jitter
	GameContext.suppress_gameplay_input()
	var p := _resolve_player()
	if p != null and "controller" in p and p.controller != null:
		if p.controller.has_method("clear_buffers"):
			p.controller.clear_buffers()

	UiKit.sfx(&"ui_back")

	var on_finish := func() -> void:
		if not is_instance_valid(self):
			return
		_closing = false
		visible = false
		if _managed_tree_pause:
			_managed_tree_pause = false
			if Director == null or not Director.choice_hold:
				get_tree().paused = false
				if Director != null:
					Director.resume()
		closed.emit()

	if _shell.has("play_outro") and _shell.get("play_outro") is Callable:
		(_shell.get("play_outro") as Callable).call(on_finish)
	else:
		on_finish.call()


func toggle_panel(from_pause_menu: bool = false) -> void:
	if is_open or visible:
		close_panel()
	else:
		open_panel(from_pause_menu)


# Caller convention aliases
func open() -> void: open_panel()
func close() -> void: close_panel()
func toggle() -> void: toggle_panel()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		if not can_open():
			return
		if event is InputEventKey and not event.echo:
			var key_event := event as InputEventKey
			# Dedicated 'I' key opens immediately
			if key_event.pressed and key_event.keycode == KEY_I:
				open_panel()
				get_viewport().set_input_as_handled()
				return
			# 'Tab' tap-to-toggle (<0.22s) / hold-to-peek (>=0.22s)
			if key_event.keycode == KEY_TAB:
				if key_event.pressed:
					_tab_press_time = Time.get_ticks_msec() / 1000.0
				else:
					if _tab_press_time > 0.0:
						var dur := (Time.get_ticks_msec() / 1000.0) - _tab_press_time
						_tab_press_time = -1.0
						if dur < TAB_HOLD_THRESHOLD:
							open_panel()
							get_viewport().set_input_as_handled()
		return

	# When open:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and not event.echo and event.pressed and (event.keycode == KEY_I or event.keycode == KEY_ESCAPE)):
		close_panel()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and not event.echo and event.keycode == KEY_TAB:
		if event.pressed:
			_tab_press_time = Time.get_ticks_msec() / 1000.0
		else:
			if _tab_press_time > 0.0:
				var dur := (Time.get_ticks_msec() / 1000.0) - _tab_press_time
				_tab_press_time = -1.0
				if dur < TAB_HOLD_THRESHOLD:
					close_panel()
					get_viewport().set_input_as_handled()


func _on_player_died() -> void:
	if visible:
		close_panel()


# ===========================================================================
# UI Construction
# ===========================================================================

func _build() -> void:
	_shell = Modal.build(self, {
		"title": "角 色 · 装 备",
		"kicker": "EMBER KNIGHT ATTRIBUTES & LOADOUT",
		"size": Vector2(1060.0, 646.0),
		"hint": "方向键 移动焦点 · 回车/点击 穿脱/替换 · I/Tab 关闭",
		"back": "Esc 返回",
		"veil": 0.62,
		"embers": true
	})
	_root = _shell["root"] as Control
	_root.theme = UiKit.extras_theme()

	# Clicking veil outside modal card closes the panel
	_root.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			close_panel())

	var body := _shell["body"] as Control
	var main_split := HBoxContainer.new()
	main_split.name = "MainSplit"
	main_split.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_split.add_theme_constant_override("separation", 18)
	main_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(main_split)

	_build_left_attributes(main_split)
	_build_right_inventory(main_split)
	_setup_focus_neighbors()


func _build_left_attributes(parent: Control) -> void:
	var plaque := UiKit.panel()
	plaque.name = "AttributesPlaque"
	plaque.custom_minimum_size = Vector2(400.0, 0.0)
	plaque.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(plaque)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	plaque.add_child(margin)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 2)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(column)

	# 1. Header & Origin Badge
	origin_title_label = UiKit.label(_resolve_origin_title_text(), &"SubHeadLabel", HORIZONTAL_ALIGNMENT_CENTER)
	origin_title_label.name = "OriginTitleLabel"
	origin_title_label.modulate = UiKit.EMBER
	column.add_child(origin_title_label)

	var rule := Ornaments.rivet_rule(360.0)
	column.add_child(rule)

	# 2. Attribute Rows
	var attrs := [
		[&"max_hp", "生命上限"],
		[&"attack", "近战攻击"],
		[&"defense", "伤害减免"],
		[&"toxin_resist", "毒素抗性"],
		[&"toxin_decay", "自然排毒"],
		[&"speed_mult", "移动修正"],
	]

	for attr_spec in attrs:
		var key: StringName = attr_spec[0]
		var title_text: String = attr_spec[1]

		var row_container := VBoxContainer.new()
		row_container.name = "Row_" + String(key)
		row_container.add_theme_constant_override("separation", 1)
		column.add_child(row_container)

		var top_row := HBoxContainer.new()
		top_row.name = "Top"
		row_container.add_child(top_row)

		var name_lbl := UiKit.label(title_text, &"TinyStrongLabel")
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top_row.add_child(name_lbl)

		var val_lbl := UiKit.label("0", &"SubHeadLabel", HORIZONTAL_ALIGNMENT_RIGHT)
		# 数值染色：高对比度色谱阶梯
		var stat_color: Color = STAT_COLORS.get(key, UiKit.EMBER)
		val_lbl.modulate = stat_color
		top_row.add_child(val_lbl)

		var detail_lbl := UiKit.label("", &"FootnoteLabel")
		detail_lbl.modulate = Color(UiKit.ASH.r, UiKit.ASH.g, UiKit.ASH.b, 0.85)
		row_container.add_child(detail_lbl)

		_attr_rows[key] = {
			"val": val_lbl,
			"detail": detail_lbl,
			"row": row_container,
			"name": name_lbl
		}

	# 3. Divider
	var rule2 := Ornaments.rivet_rule(360.0)
	column.add_child(rule2)

	# 4. Set Synergies Container
	var syn_header := UiKit.label("套 装 共 鸣", &"TinyStrongLabel", HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(syn_header)

	_synergies_container = VBoxContainer.new()
	_synergies_container.name = "SynergiesContainer"
	_synergies_container.add_theme_constant_override("separation", 4)
	_synergies_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_synergies_container)


func _build_right_inventory(parent: Control) -> void:
	var column := VBoxContainer.new()
	column.name = "RightColumn"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	parent.add_child(column)

	# --- Section 1: Equipped Slots ---
	var slot_header := UiKit.label("已 穿 戴 装 备", &"TinyStrongLabel")
	column.add_child(slot_header)

	var slots_hbox := HBoxContainer.new()
	slots_hbox.name = "SlotsHBox"
	slots_hbox.add_theme_constant_override("separation", 8)
	column.add_child(slots_hbox)

	for slot in SLOTS:
		var btn := Button.new()
		btn.name = "Slot_" + String(slot).capitalize()
		btn.custom_minimum_size = Vector2(178.0, 56.0)
		btn.theme_type_variation = &"SettingsButton"
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slots_hbox.add_child(btn)

		var btn_box := VBoxContainer.new()
		btn_box.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
		btn_box.add_theme_constant_override("separation", 1)
		btn.add_child(btn_box)

		var slot_title := UiKit.label(_slot_display_name(slot), &"FootnoteLabel", HORIZONTAL_ALIGNMENT_CENTER)
		slot_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn_box.add_child(slot_title)

		var item_name_lbl := UiKit.label("【 空 】", &"TinyStrongLabel", HORIZONTAL_ALIGNMENT_CENTER)
		item_name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn_box.add_child(item_name_lbl)

		var stat_lbl := UiKit.label("", &"FootnoteLabel", HORIZONTAL_ALIGNMENT_CENTER)
		stat_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stat_lbl.modulate = UiKit.EMBER
		btn_box.add_child(stat_lbl)

		_slot_buttons[slot] = btn
		_slot_labels[slot] = {
			"title": slot_title,
			"name": item_name_lbl,
			"stat": stat_lbl
		}

		btn.pressed.connect(func(): _on_slot_pressed(slot))
		btn.focus_entered.connect(func(): _on_slot_focused(slot))
		btn.mouse_entered.connect(func(): _on_slot_focused(slot))
		# 悬停 / 聚焦时整格提亮一档：槽位是"当前检视对象"，提亮即选中，
		# 和右侧检视框的内容联动，键鼠与手柄给同一个信号。
		btn.focus_exited.connect(func(): _on_slot_blurred(slot))
		btn.mouse_exited.connect(func(): _on_slot_blurred(slot))

	# --- Section 2: Bag Grid ---
	var bag_header_row := HBoxContainer.new()
	bag_header_row.name = "BagHeaderRow"
	column.add_child(bag_header_row)

	var bag_title := UiKit.label("装 备 背 包", &"TinyStrongLabel")
	bag_header_row.add_child(bag_title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_header_row.add_child(spacer)

	_bag_capacity_label = UiKit.label("容量: 0/16", &"FootnoteLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	bag_header_row.add_child(_bag_capacity_label)

	var bag_grid := GridContainer.new()
	bag_grid.name = "BagGrid"
	bag_grid.columns = 4
	bag_grid.add_theme_constant_override("h_separation", 6)
	bag_grid.add_theme_constant_override("v_separation", 6)
	column.add_child(bag_grid)

	for i in MAX_BAG_CAPACITY:
		var btn := Button.new()
		btn.name = "BagSlot_%d" % i
		btn.custom_minimum_size = Vector2(132.0, 52.0)
		btn.theme_type_variation = &"KeyCapButton"
		btn.clip_text = true
		bag_grid.add_child(btn)

		_bag_buttons.append(btn)
		btn.pressed.connect(func(): _on_bag_pressed(i))
		btn.focus_entered.connect(func(): _on_bag_focused(i))
		btn.mouse_entered.connect(func(): _on_bag_focused(i))
		btn.focus_exited.connect(func(): _on_bag_blurred(i))
		btn.mouse_exited.connect(func(): _on_bag_blurred(i))

	# --- Section 3: Tooltip / Inspector Box ---
	var inspect_panel := UiKit.panel(&"HudPanel")
	inspect_panel.name = "InspectorBox"
	inspect_panel.custom_minimum_size = Vector2(0.0, 112.0)
	column.add_child(inspect_panel)

	var inspect_hbox := HBoxContainer.new()
	inspect_hbox.name = "InspectHBox"
	inspect_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	inspect_hbox.add_theme_constant_override("separation", 12)
	inspect_panel.add_child(inspect_hbox)

	var info_col := VBoxContainer.new()
	info_col.name = "InfoCol"
	info_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_col.add_theme_constant_override("separation", 2)
	inspect_hbox.add_child(info_col)

	var name_row := HBoxContainer.new()
	name_row.name = "NameRow"
	name_row.add_theme_constant_override("separation", 8)
	info_col.add_child(name_row)

	_tooltip_name = UiKit.label("【 装备名称 】", &"SubHeadLabel")
	_tooltip_name.modulate = UiKit.EMBER
	name_row.add_child(_tooltip_name)

	_tooltip_type_set = UiKit.label("部位: —", &"FootnoteLabel")
	_tooltip_type_set.modulate = UiKit.ASH
	name_row.add_child(_tooltip_type_set)

	_tooltip_stats = UiKit.label("无属性加成", &"TinyStrongLabel")
	_tooltip_stats.modulate = Color("#7BE382")
	info_col.add_child(_tooltip_stats)

	_tooltip_desc = UiKit.label("选择一件装备以检视详细说明。", &"FootnoteLabel")
	_tooltip_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tooltip_desc.custom_minimum_size = Vector2(360.0, 0.0)
	info_col.add_child(_tooltip_desc)

	_tooltip_action_hint = UiKit.label("", &"FootnoteLabel")
	_tooltip_action_hint.modulate = UiKit.EMBER_ASH
	info_col.add_child(_tooltip_action_hint)

	# Direct Touch Action Button
	_tooltip_action_btn = Button.new()
	_tooltip_action_btn.name = "ActionButton"
	_tooltip_action_btn.text = "装 备"
	_tooltip_action_btn.theme_type_variation = &"SettingsButton"
	_tooltip_action_btn.custom_minimum_size = Vector2(92.0, 52.0)
	_tooltip_action_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tooltip_action_btn.visible = false
	_tooltip_action_btn.pressed.connect(_on_action_btn_pressed)
	inspect_hbox.add_child(_tooltip_action_btn)


func _setup_focus_neighbors() -> void:
	# Configure complete 2D focus graph for controller / keyboard
	var weapon_btn: Button = _slot_buttons[SLOT_WEAPON]
	var armor_btn: Button = _slot_buttons[SLOT_ARMOR]
	var trinket_btn: Button = _slot_buttons[SLOT_TRINKET]

	weapon_btn.focus_neighbor_right = armor_btn.get_path()
	weapon_btn.focus_neighbor_bottom = _bag_buttons[0].get_path()

	armor_btn.focus_neighbor_left = weapon_btn.get_path()
	armor_btn.focus_neighbor_right = trinket_btn.get_path()
	armor_btn.focus_neighbor_bottom = _bag_buttons[1].get_path()

	trinket_btn.focus_neighbor_left = armor_btn.get_path()
	trinket_btn.focus_neighbor_bottom = _bag_buttons[2].get_path()

	for i in MAX_BAG_CAPACITY:
		var btn: Button = _bag_buttons[i]
		var col := i % 4
		var row := i / 4

		# Horizontal
		if col > 0:
			btn.focus_neighbor_left = _bag_buttons[i - 1].get_path()
		if col < 3:
			btn.focus_neighbor_right = _bag_buttons[i + 1].get_path()

		# Up
		if row > 0:
			btn.focus_neighbor_top = _bag_buttons[i - 4].get_path()
		else:
			if col == 0:
				btn.focus_neighbor_top = weapon_btn.get_path()
			elif col == 1:
				btn.focus_neighbor_top = armor_btn.get_path()
			else:
				btn.focus_neighbor_top = trinket_btn.get_path()

		# Down
		if row < 3:
			btn.focus_neighbor_bottom = _bag_buttons[i + 4].get_path()
		else:
			btn.focus_neighbor_bottom = _tooltip_action_btn.get_path()

	_tooltip_action_btn.focus_neighbor_top = _bag_buttons[14].get_path()


# ===========================================================================
# Refreshing & State Binding
# ===========================================================================

func _resolve_player() -> Player:
	if _player != null and is_instance_valid(_player):
		return _player
	if is_inside_tree():
		_player = get_tree().get_first_node_in_group("player") as Player
	return _player


func _bind_player() -> void:
	var p := _resolve_player()
	if p == null:
		return

	if "equipment" in p and p.equipment != null:
		if not p.equipment.equipment_changed.is_connected(_on_equipment_changed):
			p.equipment.equipment_changed.connect(_on_equipment_changed)
		if not p.equipment.bag_changed.is_connected(_on_bag_changed):
			p.equipment.bag_changed.connect(_on_bag_changed)

	if "stats" in p and p.stats != null:
		if not p.stats.stats_changed.is_connected(_on_stats_changed):
			p.stats.stats_changed.connect(_on_stats_changed)


func _unbind_player() -> void:
	if _player == null or not is_instance_valid(_player):
		return

	if "equipment" in _player and _player.equipment != null:
		if _player.equipment.equipment_changed.is_connected(_on_equipment_changed):
			_player.equipment.equipment_changed.disconnect(_on_equipment_changed)
		if _player.equipment.bag_changed.is_connected(_on_bag_changed):
			_player.equipment.bag_changed.disconnect(_on_bag_changed)

	if "stats" in _player and _player.stats != null:
		if _player.stats.stats_changed.is_connected(_on_stats_changed):
			_player.stats.stats_changed.disconnect(_on_stats_changed)


func _on_equipment_changed() -> void:
	_refresh_all()
	_reinspect_current()


func _on_bag_changed() -> void:
	_refresh_all()
	_reinspect_current()


func _on_stats_changed() -> void:
	_refresh_attributes()


func _refresh_all() -> void:
	_refresh_attributes()
	_refresh_slots()
	_refresh_bag()


func _refresh_attributes() -> void:
	_refresh_origin_badge()

	var p := _resolve_player()
	var stats: CharacterStats = p.stats if (p != null and "stats" in p) else null

	var cur_hp := 5
	var base_hp := 5
	var bonus_hp := 0
	var atk := 0
	var def := 0
	var res := 0.0
	var dec := 0.0
	var spd := 1.0

	var origin_hp := 0
	var origin_atk := 0
	var origin_def := 0
	var origin_res := 0.0
	var origin_dec := 0.0
	var origin_spd := 0.0

	if stats != null:
		cur_hp = stats.get_effective_max_hp()
		base_hp = stats.base_max_hp
		bonus_hp = stats.get_max_hp_bonus()
		atk = stats.get_attack_bonus()
		def = stats.get_defense_reduction()
		res = stats.get_toxin_resistance()
		dec = stats.get_toxin_decay_bonus()
		spd = stats.get_speed_multiplier()

		if "origin_max_hp" in stats:
			origin_hp = stats.origin_max_hp
			origin_atk = stats.origin_attack
			origin_def = stats.origin_defense
			origin_res = stats.origin_toxin_resist
			origin_dec = stats.origin_toxin_decay
			origin_spd = stats.origin_speed_mult

	# 1. Max HP (Vitality green)
	if _attr_rows.has(&"max_hp"):
		_attr_rows[&"max_hp"]["val"].text = str(cur_hp)
		_attr_rows[&"max_hp"]["val"].modulate = STAT_COLORS[&"max_hp"]
		var gear_hp := bonus_hp - origin_hp
		if origin_hp != 0 and gear_hp != 0:
			_attr_rows[&"max_hp"]["detail"].text = "(基础 %d + 身份 %+d + 装备 %+d)" % [base_hp, origin_hp, gear_hp]
		elif origin_hp != 0 and gear_hp == 0:
			_attr_rows[&"max_hp"]["detail"].text = "(基础 %d + 身份 %+d)" % [base_hp, origin_hp]
		elif origin_hp == 0 and gear_hp != 0:
			_attr_rows[&"max_hp"]["detail"].text = "(基础 %d + 装备 %+d)" % [base_hp, gear_hp]
		else:
			_attr_rows[&"max_hp"]["detail"].text = "(基础 %d)" % base_hp

	# 2. Attack (Warm yellow)
	if _attr_rows.has(&"attack"):
		_attr_rows[&"attack"]["val"].text = "%+d" % atk
		_attr_rows[&"attack"]["val"].modulate = STAT_COLORS[&"attack"]
		var gear_atk := atk - origin_atk
		if origin_atk != 0 and gear_atk != 0:
			_attr_rows[&"attack"]["detail"].text = "(基础 1 + 身份 %+d + 装备 %+d = %d 点挥砍伤害)" % [origin_atk, gear_atk, 1 + atk]
		elif origin_atk != 0 and gear_atk == 0:
			_attr_rows[&"attack"]["detail"].text = "(基础 1 + 身份 %+d = %d 点挥砍伤害)" % [origin_atk, 1 + atk]
		elif atk != 0:
			_attr_rows[&"attack"]["detail"].text = "(基础 1 + 装备 %+d = %d 点挥砍伤害)" % [atk, 1 + atk]
		else:
			_attr_rows[&"attack"]["detail"].text = "(基础 1 点挥砍伤害，加成 +0)"

	# 3. Defense (Metallic iron grey)
	if _attr_rows.has(&"defense"):
		_attr_rows[&"defense"]["val"].text = "%+d" % def
		_attr_rows[&"defense"]["val"].modulate = STAT_COLORS[&"defense"]
		var gear_def := def - origin_def
		if origin_def != 0 and gear_def != 0:
			_attr_rows[&"defense"]["detail"].text = "(受击减免 %+d 点 [身份 %+d, 装备 %+d]，底线 1 点)" % [def, origin_def, gear_def]
		elif origin_def != 0 and gear_def == 0:
			_attr_rows[&"defense"]["detail"].text = "(受击减免 %+d 点 [身份 %+d]，底线 1 点)" % [def, origin_def]
		else:
			_attr_rows[&"defense"]["detail"].text = "(减免受击伤害 %+d 点，底线 1 点)" % def

	# 4. Toxin Resist (Teal/cyan)
	if _attr_rows.has(&"toxin_resist"):
		_attr_rows[&"toxin_resist"]["val"].text = "%.0f%%" % (res * 100.0)
		_attr_rows[&"toxin_resist"]["val"].modulate = STAT_COLORS[&"toxin_resist"]
		var gear_res := res - origin_res
		if origin_res > 0.001 and gear_res > 0.001:
			_attr_rows[&"toxin_resist"]["detail"].text = "(毒素减缓 %.0f%% [身份 +%.0f%%, 装备 +%.0f%%]，上限 80%%)" % [res * 100.0, origin_res * 100.0, gear_res * 100.0]
		elif origin_res > 0.001:
			_attr_rows[&"toxin_resist"]["detail"].text = "(毒素减缓 %.0f%% [身份 +%.0f%%]，上限 80%%)" % [res * 100.0, origin_res * 100.0]
		else:
			_attr_rows[&"toxin_resist"]["detail"].text = "(减缓毒液累积 %.0f%%，上限 80%%)" % (res * 100.0)

	# 5. Toxin Decay (Teal/cyan)
	if _attr_rows.has(&"toxin_decay"):
		_attr_rows[&"toxin_decay"]["val"].text = "+%.1f/s" % dec
		_attr_rows[&"toxin_decay"]["val"].modulate = STAT_COLORS[&"toxin_decay"]
		var gear_dec := dec - origin_dec
		if origin_dec > 0.001 and gear_dec > 0.001:
			_attr_rows[&"toxin_decay"]["detail"].text = "(自然消散加快 %+.1f/s [身份 +%.0f%%, 装备 +%.1f/s])" % [dec, origin_dec * 100.0, gear_dec]
		elif origin_dec > 0.001:
			_attr_rows[&"toxin_decay"]["detail"].text = "(自然消散加快 %+.1f/s [身份 +%.0f%%])" % [dec, origin_dec * 100.0]
		else:
			_attr_rows[&"toxin_decay"]["detail"].text = "(加快自然消散排毒 %+.1f/s)" % dec

	# 6. Speed Mult (Agility blue)
	if _attr_rows.has(&"speed_mult"):
		_attr_rows[&"speed_mult"]["val"].text = "%.0f%%" % (spd * 100.0)
		_attr_rows[&"speed_mult"]["val"].modulate = STAT_COLORS[&"speed_mult"]
		if origin_spd > 0.001:
			_attr_rows[&"speed_mult"]["detail"].text = "(跑速倍率 %.0f%% [身份 +%.0f%%])" % [spd * 100.0, origin_spd * 100.0]
		else:
			_attr_rows[&"speed_mult"]["detail"].text = "(跑速与冲刺速度倍率 %.0f%%)" % (spd * 100.0)

	# Apply rich formula tooltips to all rows
	for key in _attr_rows.keys():
		var tip := _get_stat_tooltip_text(key, stats)
		var row_dict: Dictionary = _attr_rows[key]
		if row_dict.has("row") and row_dict["row"] != null:
			(row_dict["row"] as Control).tooltip_text = tip
		if row_dict.has("val") and row_dict["val"] != null:
			(row_dict["val"] as Control).tooltip_text = tip
		if row_dict.has("detail") and row_dict["detail"] != null:
			(row_dict["detail"] as Control).tooltip_text = tip

	# Set Synergies
	if _synergies_container != null:
		for child in _synergies_container.get_children():
			child.queue_free()

		var synergies: Array[Dictionary] = []
		if p != null and "equipment" in p and p.equipment != null:
			synergies = p.equipment.get_set_synergies()

		if synergies.is_empty():
			var empty_lbl := UiKit.label("当前未激活套装效果 (穿戴同名套装激活)", &"FootnoteLabel", HORIZONTAL_ALIGNMENT_CENTER)
			empty_lbl.modulate = Color(UiKit.ASH.r, UiKit.ASH.g, UiKit.ASH.b, 0.75)
			_synergies_container.add_child(empty_lbl)
		else:
			for syn in synergies:
				var syn_box := VBoxContainer.new()
				syn_box.add_theme_constant_override("separation", 1)
				_synergies_container.add_child(syn_box)

				var s_name: String = syn.get("name", "套装共鸣")
				var s_pieces: int = int(syn.get("pieces", 2))
				var s_desc: String = syn.get("description", "")

				var head_lbl := UiKit.label("★ %s (%d件套)" % [s_name, s_pieces], &"TinyStrongLabel")
				head_lbl.modulate = UiKit.EMBER
				syn_box.add_child(head_lbl)

				var desc_lbl := UiKit.label(s_desc, &"FootnoteLabel")
				desc_lbl.modulate = Color("#7BE382")
				syn_box.add_child(desc_lbl)


func _refresh_slots() -> void:
	var p := _resolve_player()
	var equip_inv: EquipmentInventory = p.equipment if (p != null and "equipment" in p) else null

	for slot in SLOTS:
		var item: Variant = equip_inv.get_equipped(slot) if equip_inv != null else null
		var lbls: Dictionary = _slot_labels.get(slot, {})
		var name_lbl: Label = lbls.get("name")
		var stat_lbl: Label = lbls.get("stat")

		if name_lbl != null:
			if item != null:
				name_lbl.text = _get_item_display_name(item)
				name_lbl.modulate = UiKit.EMBER
			else:
				name_lbl.text = "【 空 】"
				name_lbl.modulate = SLOT_EMPTY

		if stat_lbl != null:
			if item != null:
				var lines := _get_item_stat_lines(item)
				stat_lbl.text = lines[0] if not lines.is_empty() else ""
			else:
				stat_lbl.text = ""


func _refresh_bag() -> void:
	var p := _resolve_player()
	var equip_inv: EquipmentInventory = p.equipment if (p != null and "equipment" in p) else null
	var bag: Array = equip_inv.bag if equip_inv != null else []

	if _bag_capacity_label != null:
		_bag_capacity_label.text = "容量: %d/%d" % [bag.size(), MAX_BAG_CAPACITY]

	for i in MAX_BAG_CAPACITY:
		var btn: Button = _bag_buttons[i]
		if i < bag.size():
			var item: Variant = bag[i]
			var dname := _get_item_display_name(item)
			var badge := _slot_badge(_get_item_slot(item))
			btn.text = "%s%s" % [badge, dname]
			btn.modulate = _bag_tint(i)
		else:
			btn.text = "—"
			btn.modulate = _bag_tint(i)


## 背包格的基础调制色：有货是本色，空格子压暗 —— 高亮补间回到这个值，
## 不能让"取消高亮"把空格子又点亮成满格的样子。
func _bag_tint(index: int) -> Color:
	var p := _resolve_player()
	var equip_inv: EquipmentInventory = p.equipment if (p != null and "equipment" in p) else null
	var bag: Array = equip_inv.bag if equip_inv != null else []
	return Color.WHITE if index < bag.size() else Color(0.65, 0.65, 0.65, 0.60)


# ===========================================================================
# Tooltip & Inspection Logic
# ===========================================================================

func _on_slot_focused(slot: StringName) -> void:
	_set_slot_lit(slot, true)
	_inspect_slot(slot)


## 槽位的"当前检视对象"高亮：提亮一档而不是换贴图 —— 贴图切换是"按下"的
## 语言，这里要的是"这一格正在被检视"的常亮信号。
func _set_slot_lit(slot: StringName, lit: bool) -> void:
	var btn := _slot_buttons.get(slot) as Button
	if btn == null:
		return
	var tween := create_tween()
	if lit:
		tween.tween_property(btn, "modulate", Color(1.08, 1.04, 0.96), 0.1)
	else:
		tween.tween_property(btn, "modulate", Color.WHITE, 0.16)


func _on_slot_blurred(slot: StringName) -> void:
	_set_slot_lit(slot, false)


func _on_bag_focused(bag_idx: int) -> void:
	_set_bag_lit(bag_idx, true)
	_inspect_bag(bag_idx)


func _on_bag_blurred(bag_idx: int) -> void:
	_set_bag_lit(bag_idx, false)


## 背包格的高亮与槽位同源（提亮一档）；空格子也亮 —— 检视框会告诉玩家
## 这一格是空的、怎么填上它，空格子同样值得"正在看"。
func _set_bag_lit(bag_idx: int, lit: bool) -> void:
	if bag_idx < 0 or bag_idx >= _bag_buttons.size():
		return
	var btn := _bag_buttons[bag_idx]
	var tween := create_tween()
	if lit:
		tween.tween_property(btn, "modulate", Color(1.08, 1.04, 0.96), 0.1)
	else:
		tween.tween_property(btn, "modulate", _bag_tint(bag_idx), 0.16)


func _inspect_slot(slot: StringName) -> void:
	_inspected_source = &"slot"
	_inspected_slot = slot
	_inspected_bag_idx = -1

	var p := _resolve_player()
	var item: Variant = p.equipment.get_equipped(slot) if (p != null and "equipment" in p and p.equipment != null) else null
	_inspected_item = item

	if item == null:
		_tooltip_name.text = "【 未穿戴装备 】"
		_tooltip_name.modulate = UiKit.ASH
		_tooltip_type_set.text = "部位: %s" % _slot_display_name(slot)
		_tooltip_stats.text = "此槽位当前为空"
		_tooltip_stats.modulate = UiKit.ASH
		_tooltip_desc.text = "可从装备背包中选择同部位装备进行穿戴。"
		_tooltip_action_hint.text = ""
		_tooltip_action_btn.visible = false
	else:
		_tooltip_name.text = _get_item_display_name(item)
		_tooltip_name.modulate = UiKit.EMBER
		_tooltip_type_set.text = "部位: %s · 套装: %s" % [_slot_display_name(slot), _get_item_set_name(item)]
		var lines := _get_item_stat_lines(item)
		_tooltip_stats.text = " · ".join(lines) if not lines.is_empty() else "基础装备"
		_tooltip_stats.modulate = STAT_COLORS.get(&"attack", Color("#7BE382"))
		_tooltip_desc.text = _get_item_description(item)
		_tooltip_action_hint.text = "点击 / Enter: 卸下至背包"
		_tooltip_action_btn.visible = true
		_tooltip_action_btn.text = "卸 下"


func _inspect_bag(bag_idx: int) -> void:
	_inspected_source = &"bag"
	_inspected_slot = &""
	_inspected_bag_idx = bag_idx

	var p := _resolve_player()
	var bag: Array = p.equipment.bag if (p != null and "equipment" in p and p.equipment != null) else []
	var item: Variant = bag[bag_idx] if (bag_idx >= 0 and bag_idx < bag.size()) else null
	_inspected_item = item

	if item == null:
		_tooltip_name.text = "【 空格位 】"
		_tooltip_name.modulate = UiKit.ASH
		_tooltip_type_set.text = "背包格子 #%d" % (bag_idx + 1)
		_tooltip_stats.text = "闲置格子"
		_tooltip_stats.modulate = UiKit.ASH
		_tooltip_desc.text = "在锈墓世界中探索遗迹、翻找废料堆或战胜守卫可获取新装备。"
		_tooltip_action_hint.text = ""
		_tooltip_action_btn.visible = false
	else:
		var item_slot := _get_item_slot(item)
		var equipped_in_slot: Variant = p.equipment.get_equipped(item_slot) if (p != null and "equipment" in p and p.equipment != null) else null
		var action_text := "替 换" if equipped_in_slot != null else "装 备"

		_tooltip_name.text = _get_item_display_name(item)
		_tooltip_name.modulate = UiKit.EMBER
		_tooltip_type_set.text = "部位: %s · 套装: %s" % [_slot_display_name(item_slot), _get_item_set_name(item)]
		var lines := _get_item_stat_lines(item)
		_tooltip_stats.text = " · ".join(lines) if not lines.is_empty() else "基础装备"
		_tooltip_stats.modulate = STAT_COLORS.get(&"attack", Color("#7BE382"))
		_tooltip_desc.text = _get_item_description(item)
		_tooltip_action_hint.text = "点击 / Enter: %s至%s槽位" % [action_text, _slot_display_name(item_slot)]
		_tooltip_action_btn.visible = true
		_tooltip_action_btn.text = action_text


func _reinspect_current() -> void:
	if _inspected_source == &"slot" and _inspected_slot != &"":
		_inspect_slot(_inspected_slot)
	elif _inspected_source == &"bag" and _inspected_bag_idx >= 0:
		_inspect_bag(_inspected_bag_idx)
	else:
		_inspect_slot(SLOT_WEAPON)


# ===========================================================================
# User Interaction Handlers (Click, Touch, Keyboard)
# ===========================================================================

func _on_slot_pressed(slot: StringName) -> void:
	var p := _resolve_player()
	if p == null or not ("equipment" in p) or p.equipment == null:
		return

	var current_item: Variant = p.equipment.get_equipped(slot)
	if current_item == null:
		UiKit.sfx(&"ui_tick")
		return

	if p.equipment.bag.size() >= MAX_BAG_CAPACITY:
		UiKit.sfx(&"ui_denied")
		_tooltip_action_hint.text = "背包已满，无法卸下！"
		_tooltip_action_hint.modulate = Color("#FF5555")
		return

	var ok: bool = p.equipment.unequip_slot(slot)
	if ok:
		UiKit.sfx(&"ui_select")
		item_unequipped.emit(slot, current_item)
		_refresh_all()
		_inspect_slot(slot)
	else:
		UiKit.sfx(&"ui_denied")


func _on_bag_pressed(bag_idx: int) -> void:
	var p := _resolve_player()
	if p == null or not ("equipment" in p) or p.equipment == null:
		return

	var bag: Array = p.equipment.bag
	if bag_idx < 0 or bag_idx >= bag.size():
		UiKit.sfx(&"ui_tick")
		return

	var item: Variant = bag[bag_idx]
	var slot := _get_item_slot(item)
	if slot == &"":
		UiKit.sfx(&"ui_denied")
		return

	var ok: bool = p.equipment.swap_item(slot, bag_idx)
	if ok:
		UiKit.sfx(&"ui_select")
		item_equipped.emit(slot, item)
		_refresh_all()
		_inspect_slot(slot)
	else:
		UiKit.sfx(&"ui_denied")


func _on_action_btn_pressed() -> void:
	if _inspected_source == &"bag":
		_on_bag_pressed(_inspected_bag_idx)
	elif _inspected_source == &"slot":
		_on_slot_pressed(_inspected_slot)


# ===========================================================================
# Data & Presentation Helpers
# ===========================================================================

func _slot_display_name(slot: StringName) -> String:
	match slot:
		SLOT_WEAPON: return "武器"
		SLOT_ARMOR: return "护甲"
		SLOT_TRINKET: return "饰品"
		_: return String(slot)


func _slot_badge(slot: StringName) -> String:
	match slot:
		SLOT_WEAPON: return "[剑] "
		SLOT_ARMOR: return "[甲] "
		SLOT_TRINKET: return "[饰] "
		_: return ""


func _get_item_slot(item: Variant) -> StringName:
	if item == null:
		return &""
	if item is EquipmentItem:
		return item.slot_type
	if item is Dictionary:
		return StringName(item.get("slot_type", item.get("slot", "")))
	if item is Object and "slot_type" in item:
		return StringName(item.get("slot_type"))
	if item is String or item is StringName:
		var resolved: EquipmentItem = EquipmentCatalog.for_id(item)
		if resolved != null:
			return resolved.slot_type
	return &""


func _get_item_display_name(item: Variant) -> String:
	if item == null:
		return ""
	if item is EquipmentItem:
		return item.display_name
	if item is Dictionary:
		return String(item.get("display_name", item.get("name", item.get("id", "装备"))))
	if item is Object and "display_name" in item:
		return String(item.get("display_name"))
	if item is String or item is StringName:
		var resolved: EquipmentItem = EquipmentCatalog.for_id(item)
		if resolved != null:
			return resolved.display_name
		return String(item)
	return "装备"


func _get_item_description(item: Variant) -> String:
	if item == null:
		return ""
	if item is EquipmentItem:
		return item.description
	if item is Dictionary:
		return String(item.get("description", item.get("desc", "")))
	if item is Object and "description" in item:
		return String(item.get("description"))
	if item is String or item is StringName:
		var resolved: EquipmentItem = EquipmentCatalog.for_id(item)
		if resolved != null:
			return resolved.description
	return ""


func _get_item_set_name(item: Variant) -> String:
	if item == null:
		return "无"
	var s_id: Variant = null
	if item is EquipmentItem:
		s_id = item.set_id
	elif item is Dictionary:
		s_id = item.get("set_id", item.get("set", null))
	elif item is Object and "set_id" in item:
		s_id = item.get("set_id")

	if s_id == null or str(s_id) == "" or str(s_id) == "none":
		return "无"
	if str(s_id) == "broken_knight":
		return "破损骑士"
	return str(s_id)


func _get_item_stat_lines(item: Variant) -> Array[String]:
	if item == null:
		return []
	if item is EquipmentItem or (item is Object and item.has_method("get_stat_lines")):
		return item.get_stat_lines()
	if item is Dictionary:
		var lines: Array[String] = []
		var atk: int = int(item.get("attack", 0))
		var def: int = int(item.get("defense", 0))
		var hp: int = int(item.get("max_hp", 0))
		var res: float = float(item.get("toxin_resist", 0.0))
		var dec: float = float(item.get("toxin_decay", 0.0))
		var spd: float = float(item.get("speed_mult", 0.0))
		if atk != 0: lines.append("攻击力 %+d" % atk)
		if def != 0: lines.append("防御力 %+d" % def)
		if hp != 0: lines.append("生命上限 %+d" % hp)
		if not is_zero_approx(res): lines.append("毒素抗性 %+.0f%%" % (res * 100.0))
		if not is_zero_approx(dec): lines.append("毒素消散 %+.1f/s" % dec)
		if not is_zero_approx(spd): lines.append("移动速度 %+.0f%%" % (spd * 100.0))
		return lines
	if item is String or item is StringName:
		var resolved: EquipmentItem = EquipmentCatalog.for_id(item)
		if resolved != null:
			return resolved.get_stat_lines()
	return []


# ===========================================================================
# Origin Badge, Stat Inspection & Customization Public APIs
# ===========================================================================

func get_origin_title_text() -> String:
	if origin_title_label != null:
		return origin_title_label.text
	return _resolve_origin_title_text()


func get_stat_color(key: StringName) -> Color:
	return STAT_COLORS.get(key, UiKit.EMBER)


func get_stat_value_label(key: StringName) -> Label:
	if _attr_rows.has(key):
		return _attr_rows[key].get("val")
	return null


func get_stat_detail_label(key: StringName) -> Label:
	if _attr_rows.has(key):
		return _attr_rows[key].get("detail")
	return null


func get_stat_tooltip_text(key: StringName) -> String:
	var p := _resolve_player()
	var stats: CharacterStats = p.stats if (p != null and "stats" in p) else null
	return _get_stat_tooltip_text(key, stats)


func set_player(player: Player) -> void:
	if _player != null and is_instance_valid(_player):
		_unbind_player()
	_player = player
	_bind_player()
	_refresh_all()


func set_origin_override(origin_id: Variant) -> void:
	_origin_override = StringName(str(origin_id)) if origin_id != null else &""
	_refresh_attributes()


func refresh() -> void:
	_refresh_all()


func _refresh_origin_badge() -> void:
	if origin_title_label != null:
		origin_title_label.text = _resolve_origin_title_text()


func _resolve_origin_title_text() -> String:
	var o_id := _resolve_current_origin_id()
	if o_id != &"" and OriginCatalogScript.has_origin(o_id):
		var origin := OriginCatalogScript.get_origin(o_id)
		if origin != null and origin.title != "":
			return "身份 · %s" % origin.title
	return "身份 · 余烬骑士"


func _resolve_current_origin_id() -> StringName:
	if _origin_override != &"":
		return _origin_override

	var p := _resolve_player()
	if p != null:
		if "stats" in p and p.stats != null:
			if p.stats.has_method("get_origin_id"):
				var stats_o: Variant = p.stats.get_origin_id()
				if stats_o != null and str(stats_o) != "":
					return StringName(str(stats_o))
		if "origin" in p:
			var po: Variant = p.origin
			if po != null and str(po) != "":
				return StringName(str(po))

	# Fallback to SaveData
	if Engine.has_singleton(&"SaveData"):
		var sd := Engine.get_singleton(&"SaveData")
		if sd != null:
			if sd.has_method("get_current_origin"):
				var cur: Variant = sd.get_current_origin()
				if cur != null and str(cur) != "":
					return StringName(str(cur))
			if "data" in sd and sd.data is Dictionary:
				var p_dict: Variant = sd.data.get("player", null)
				if p_dict is Dictionary and p_dict.has("origin") and str(p_dict.get("origin")) != "":
					return StringName(str(p_dict.get("origin")))

	if is_inside_tree() and get_tree().root.has_node("SaveData"):
		var sd_node := get_tree().root.get_node("SaveData")
		if sd_node != null:
			if sd_node.has_method("get_current_origin"):
				var cur: Variant = sd_node.get_current_origin()
				if cur != null and str(cur) != "":
					return StringName(str(cur))
			if "data" in sd_node and sd_node.data is Dictionary:
				var p_dict: Variant = sd_node.data.get("player", null)
				if p_dict is Dictionary and p_dict.has("origin") and str(p_dict.get("origin")) != "":
					return StringName(str(p_dict.get("origin")))

	if SaveData != null:
		if SaveData.has_method("get_current_origin"):
			var cur: Variant = SaveData.get_current_origin()
			if cur != null and str(cur) != "":
				return StringName(str(cur))
		if "data" in SaveData and SaveData.data is Dictionary:
			var p_dict: Variant = SaveData.data.get("player", null)
			if p_dict is Dictionary and p_dict.has("origin") and str(p_dict.get("origin")) != "":
				return StringName(str(p_dict.get("origin")))

	return &""


func _get_stat_tooltip_text(key: StringName, stats: CharacterStats) -> String:
	var cur_hp := 5
	var base_hp := 5
	var atk := 0
	var def := 0
	var res := 0.0
	var dec := 0.0
	var spd := 1.0
	var o_hp := 0
	var o_atk := 0
	var o_def := 0
	var o_res := 0.0
	var o_dec := 0.0
	var o_spd := 0.0

	if stats != null:
		cur_hp = stats.get_effective_max_hp()
		base_hp = stats.base_max_hp
		atk = stats.get_attack_bonus()
		def = stats.get_defense_reduction()
		res = stats.get_toxin_resistance()
		dec = stats.get_toxin_decay_bonus()
		spd = stats.get_speed_multiplier()
		if "origin_max_hp" in stats:
			o_hp = stats.origin_max_hp
			o_atk = stats.origin_attack
			o_def = stats.origin_defense
			o_res = stats.origin_toxin_resist
			o_dec = stats.origin_toxin_decay
			o_spd = stats.origin_speed_mult

	match key:
		&"max_hp":
			var gear_hp := cur_hp - base_hp - o_hp
			return "生命上限 (Max HP)\n公式: 基础 %d + 身份 %+d + 装备/共鸣 %+d = %d\n角色生存体魄上限，降至 0 时死亡重生。" % [base_hp, o_hp, gear_hp, cur_hp]
		&"attack":
			var gear_atk := atk - o_atk
			return "近战攻击 (Attack Bonus)\n公式: 基础挥砍 1 + 身份 %+d + 装备 %+d = %d 点伤害\n增加近战斩击与终结招式对敌人造成的实际伤害输出。" % [o_atk, gear_atk, 1 + atk]
		&"defense":
			var gear_def := def - o_def
			return "伤害减免 (Defense Reduction)\n公式: 基础 0 + 身份 %+d + 装备 %+d = %+d 点减免\n减免敌人攻击与环境伤害；单次受击伤害保底 1 点。" % [o_def, gear_def, def]
		&"toxin_resist":
			var gear_res := res - o_res
			return "毒素抗性 (Toxin Resistance)\n公式: 基础 0%% + 身份 %+.0f%% + 装备 %+.0f%% = %.0f%%\n减缓在酸池与毒液环境中的累积；硬性上限 80%%。" % [o_res * 100.0, gear_res * 100.0, res * 100.0]
		&"toxin_decay":
			var gear_dec := dec - o_dec
			return "自然排毒 (Toxin Decay)\n公式: 基础 0.0/s + 身份 %+.1f/s + 装备 %+.1f/s = +%.1f/s\n脱离毒池后毒素自然消散排出的额外速率。" % [o_dec, gear_dec, dec]
		&"speed_mult":
			var gear_spd := spd - 1.0 - o_spd
			return "移动修正 (Speed Multiplier)\n公式: 基础 100%% + 身份 %+.0f%% + 装备 %+.0f%% = %.0f%%\n跑速与冲刺速度倍率；允许范围 10%% ~ 300%%。" % [o_spd * 100.0, gear_spd * 100.0, spd * 100.0]
		_:
			return ""
