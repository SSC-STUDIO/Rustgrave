class_name HintService
extends Node
## 情境教学提示：新机制第一次用得上时给一行字（3-4 秒），不是文字墙。
##
## 规则：
##   · 队列深度 1：同一时刻只显示一条，等待位只留一条，永不叠放；两条之间至少隔 GAP 秒。
##   · 每个存档每条只出现一次：看过的 id 以 SaveData 剧情旗标 "hint_<id>" 记录，
##     所以随存档保存、新游戏重置。
##   · 只由现有信号 / 状态触发（挥砍、冲刺、毒素、锈核、余烬巢、钩锁、敌弹、死亡）。
##     状态类触发每 POLL 秒检查一次：就算那一刻被占线也会在下次补上。
##   · 过场、字幕、暂停、死亡画面期间不出；Settings 里关掉 "教学提示" 则全部静默。
##   · 文案里的 {action} 在显示时才换成当前键名（改键后自动跟随）。
##
## 由 HUD 创建并 attach 到它的 Root；关卡作者用 HintArea（scripts/ui/hint_area.gd）
## 放置自己的提示，经 offer() 进入同一条队列。

signal hint_shown(id: StringName, text: String)
signal hint_hidden(id: StringName)

const GROUP := &"hint_service"
const FLAG_PREFIX := "hint_"
const SETTING_ENABLED := &"hints_on"
const TEXT_CACHE_KEY := &"hint_texts"

const HOLD := 3.6
const FADE := 0.3
## 两条提示之间的最短间隔，防刷屏。
const GAP := 2.0
## 可重复提示（once = false）同一 id 的最短重现间隔。
const REPEAT_COOLDOWN := 20.0
const POLL := 0.25
## 敌弹进到这个距离（世界像素）才算"飞向骑士"。
const PROJECTILE_RADIUS := 220.0
const MAX_TEXT_WIDTH := 880.0
const TOP := 64.0

## 内置提示表。order 决定"教程回看"里的排序；title 是回看列表里的小标题。
const CATALOG := {
	&"peek": {"order": 0, "title": "目标与天气",
			"text": "按住 Tab 查看目标与天气 · Esc 暂停 / 设置"},
	&"swing": {"order": 10, "title": "挥砍",
			"text": "挥砍中再按 {attack}：判定末段或收刀时衔接，可接三连"},
	&"dash": {"order": 20, "title": "冲刺",
			"text": "{dash} 冲刺：冲刺期间无敌，可以穿过攻击"},
	&"projectile": {"order": 30, "title": "弹反",
			"text": "弹丸飞来时在判定帧挥剑（{attack}）命中它，即可弹反"},
	&"toxin": {"order": 40, "title": "毒素",
			"text": "毒素是燃料：越高越锋利，满溢会伤血"},
	&"core": {"order": 50, "title": "锈核",
			"text": "按 {socket_1} / {socket_2} 把锈核镶入剑的插座"},
	&"nest": {"order": 60, "title": "余烬巢",
			"text": "{interact} 点燃余烬巢：存档、回复，死后在此重燃"},
	&"hookshot": {"order": 70, "title": "钩锁",
			"text": "{hookshot} 钩锁：对准范围内的锚点，把自己拉过去"},
	&"death": {"order": 80, "title": "重燃",
			"text": "余烬熄灭后，会在最近点燃的余烬巢重燃"},
}

## 跨场景重载保留：死亡 → 读档重进关卡会销毁旧 HUD，"重燃"提示要等新 HUD 来放。
static var _death_pending := false

var _current: StringName = &""
var _current_text := ""
var _hold := 0.0
var _gap_left := 0.0
var _queued: StringName = &""
var _queued_text := ""
var _queued_once := true
var _poll_t := 0.0
var _dead := false
var _bolts: Array = []
var _repeat_seen: Dictionary = {}
var _clock := 0.0

var _panel: PanelContainer
var _label: Label
var _connected := false


func _ready() -> void:
	add_to_group(GROUP)
	_connect_sources()
	# 只在还没看过时排队：存档里没有 "hint_peek" 就等过场结束后放一条。
	offer(&"peek")
	if _death_pending:
		_death_pending = false
		offer(&"death")


func _exit_tree() -> void:
	_disconnect_sources()


func _connect_sources() -> void:
	if _connected:
		return
	_connected = true
	GameEvents.swing_started.connect(_on_swing)
	GameEvents.dash_performed.connect(_on_dash)
	GameEvents.player_died.connect(_on_died)
	var tree := get_tree()
	if tree != null:
		tree.node_added.connect(_on_node_added)


func _disconnect_sources() -> void:
	if not _connected:
		return
	_connected = false
	if GameEvents.swing_started.is_connected(_on_swing):
		GameEvents.swing_started.disconnect(_on_swing)
	if GameEvents.dash_performed.is_connected(_on_dash):
		GameEvents.dash_performed.disconnect(_on_dash)
	if GameEvents.player_died.is_connected(_on_died):
		GameEvents.player_died.disconnect(_on_died)
	var tree := get_tree()
	if tree != null and tree.node_added.is_connected(_on_node_added):
		tree.node_added.disconnect(_on_node_added)


# --- 查询（静态：教程回看不需要实例） -----------------------------------------

static func enabled() -> bool:
	return bool(Settings.value(SETTING_ENABLED, true))


static func has_seen(id: StringName) -> bool:
	return SaveData.has_flag(FLAG_PREFIX + String(id))


static func mark_seen(id: StringName) -> void:
	SaveData.mark_flag(FLAG_PREFIX + String(id))
	# 读档（死亡重燃）会按存档文件重置旗标：已有存档就立刻写回，免得刚看过的又来一遍。
	if SaveData.has_save():
		SaveData.persist_story()


## 清掉本存档的全部提示记录（测试与"重置教程"用）。
static func forget_all() -> void:
	var keep := PackedStringArray()
	for flag in SaveData.flags:
		if not String(flag).begins_with(FLAG_PREFIX):
			keep.append(String(flag))
	SaveData.flags = keep


## 文案模板（内置表 → 作者给的 → 上次缓存的）。
static func template_for(id: StringName, given: String = "") -> String:
	if given != "":
		return given
	if CATALOG.has(id):
		return String(CATALOG[id]["text"])
	var cache: Variant = Settings.value(TEXT_CACHE_KEY, {})
	if cache is Dictionary:
		return String((cache as Dictionary).get(String(id), ""))
	return ""


## 教程回看用：已经看过的提示，按内置顺序在前、关卡作者的在后；文案已换成当前键名。
static func seen_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ids: Array = CATALOG.keys()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		return int(CATALOG[a]["order"]) < int(CATALOG[b]["order"]))
	for id in ids:
		if has_seen(id):
			out.append({"id": id, "title": String(CATALOG[id]["title"]),
					"text": KeyLabels.format(String(CATALOG[id]["text"]))})
	var cache: Variant = Settings.value(TEXT_CACHE_KEY, {})
	for flag in SaveData.flags:
		var raw := String(flag)
		if not raw.begins_with(FLAG_PREFIX):
			continue
		var id := StringName(raw.trim_prefix(FLAG_PREFIX))
		if CATALOG.has(id) or not (cache is Dictionary):
			continue
		var text := String((cache as Dictionary).get(String(id), ""))
		if text != "":
			out.append({"id": id, "title": "场景提示", "text": KeyLabels.format(text)})
	return out


# --- 队列 ---------------------------------------------------------------------

func current_id() -> StringName:
	return _current


func queued_id() -> StringName:
	return _queued


func is_showing() -> bool:
	return _current != &""


## 请求显示一条提示。返回 true 表示已进入显示 / 等待位。
## text 为空时取内置表；once = false 的提示可重复出现（间隔 REPEAT_COOLDOWN）。
func offer(id: StringName, text: String = "", once: bool = true) -> bool:
	if id == &"" or not enabled():
		return false
	if template_for(id, text) == "":
		return false
	if once and has_seen(id):
		return false
	if not once and _clock - float(_repeat_seen.get(id, -REPEAT_COOLDOWN)) < REPEAT_COOLDOWN:
		return false
	if id == _current or id == _queued:
		return false
	if _queued != &"":
		return false
	_queued = id
	_queued_text = text
	_queued_once = once
	return true


func dismiss() -> void:
	if _current != &"":
		_hide_current()


func _show(id: StringName, text: String, once: bool) -> void:
	var template := template_for(id, text)
	_current = id
	_current_text = KeyLabels.format(template)
	_hold = HOLD
	if once:
		mark_seen(id)
	else:
		_repeat_seen[id] = _clock
	if not CATALOG.has(id):
		_cache_text(id, template)
	if _label != null:
		_label.text = _current_text
		_fit_label()
	if _panel != null:
		_panel.visible = true
	UiKit.sfx(&"hint_show")
	hint_shown.emit(id, _current_text)


func _hide_current() -> void:
	var id := _current
	_current = &""
	_current_text = ""
	_gap_left = GAP
	hint_hidden.emit(id)


static func _cache_text(id: StringName, template: String) -> void:
	var cache: Variant = Settings.value(TEXT_CACHE_KEY, {})
	var dict: Dictionary = (cache as Dictionary).duplicate() if cache is Dictionary else {}
	if String(dict.get(String(id), "")) == template:
		return
	dict[String(id)] = template
	Settings.set_value(TEXT_CACHE_KEY, dict)


# --- 显示条件 -----------------------------------------------------------------

func _can_show_now() -> bool:
	if _dead or not enabled():
		return false
	var tree := get_tree()
	if tree == null or tree.paused:
		return false
	if Director.playing or Director.choice_hold or Director.is_input_locked():
		return false
	if Director.letterbox_amount() > 0.02:
		return false
	var cap := Director.caption()
	if cap != null and cap.is_busy():
		return false
	return true


func _process(delta: float) -> void:
	_clock += delta
	_gap_left = maxf(0.0, _gap_left - delta)
	if _current != &"":
		_hold -= delta
		_apply_alpha()
		if _hold <= 0.0:
			_hide_current()
	elif _queued != &"" and _gap_left <= 0.0 and _can_show_now():
		var id := _queued
		var text := _queued_text
		var once := _queued_once
		_queued = &""
		_queued_text = ""
		if still_relevant(id):
			_show(id, text, once)
			_apply_alpha()
		elif once:
			# 玩家在等待期间已经自己做到了（点了巢、镶了核）：不再事后说教，记作看过。
			mark_seen(id)
	if _current == &"" and _panel != null and _panel.visible and _panel.modulate.a <= 0.01:
		_panel.visible = false
	_poll_t -= delta
	if _poll_t <= 0.0:
		_poll_t = POLL
		_scan_state()


## 排队的提示在真正出现前再核对一次：教的事情玩家已经做完了就不出。
func still_relevant(id: StringName) -> bool:
	var player := _player()
	match id:
		&"nest":
			return SaveData.lit_nests.is_empty()
		&"core":
			return player == null or player.inventory == null or not player.inventory.pouch.is_empty()
	return true


func _apply_alpha() -> void:
	if _panel == null:
		return
	var shown_for := HOLD - _hold
	var a := 1.0
	if _current == &"":
		a = 0.0
	else:
		a = minf(clampf(shown_for / FADE, 0.0, 1.0), clampf(_hold / FADE, 0.0, 1.0))
	_panel.modulate.a = a


# --- 触发源 -------------------------------------------------------------------

func _on_swing(_combo: int) -> void:
	offer(&"swing")


func _on_dash() -> void:
	offer(&"dash")


func _on_died() -> void:
	_dead = true
	if not has_seen(&"death") and enabled():
		_death_pending = true
	dismiss()


func _on_node_added(node: Node) -> void:
	if node is Projectile:
		_bolts.append(node)


func _player() -> Player:
	var tree := get_tree()
	return tree.get_first_node_in_group("player") as Player if tree != null else null


## 状态类触发。每个分支先看"还没看过"，看过的零开销。
func _scan_state() -> void:
	if _dead or not enabled():
		return
	var player := _player()
	if player == null or not is_instance_valid(player):
		return
	if not has_seen(&"toxin") and player.toxin != null and player.toxin.toxin > 0.0:
		offer(&"toxin")
	if not has_seen(&"core") and player.inventory != null and not player.inventory.pouch.is_empty():
		offer(&"core")
	if not has_seen(&"nest") and player.sensor != null and player.sensor.get_focus() is EmberNest:
		offer(&"nest")
	if not has_seen(&"hookshot") and _anchor_in_reach(player):
		offer(&"hookshot")
	if not has_seen(&"projectile") and _bolt_near(player):
		offer(&"projectile")


func _anchor_in_reach(player: Player) -> bool:
	if player.inventory == null or not player.inventory.has_ability(AbilityIds.HOOKSHOT_TETHER):
		return false
	var reach := 260.0
	if player.hookshot != null:
		reach = player.hookshot.max_range
	var origin := player.global_position + HookshotTether.ROPE_ORIGIN
	for node in get_tree().get_nodes_in_group("hook_anchor"):
		if node is Node2D and origin.distance_to((node as Node2D).global_position) <= reach:
			return true
	return false


func _bolt_near(player: Player) -> bool:
	var i := _bolts.size() - 1
	var near := false
	while i >= 0:
		var bolt: Variant = _bolts[i]
		if not is_instance_valid(bolt) or not (bolt as Node).is_inside_tree():
			_bolts.remove_at(i)
		elif (bolt as Projectile).can_deflect() \
				and (bolt as Projectile).global_position.distance_to(player.global_position) \
				<= PROJECTILE_RADIUS:
			near = true
		i -= 1
	return near


# --- 视图 ---------------------------------------------------------------------

## 在 parent（HUD 的 Root）下建出提示条。没有 attach 也能工作（测试 / 无界面）。
func attach(parent: Control) -> void:
	if _panel != null:
		return
	_panel = UiKit.panel(&"HintPanel")
	_panel.name = "HintPlate"
	_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.offset_top = TOP
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	_panel.modulate.a = 0.0
	parent.add_child(_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(row)
	var mark := UiKit.sprite_rect(UiKit.TEX_CURSOR)
	mark.name = "Mark"
	mark.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	var art := mark.texture
	if art != null:
		mark.custom_minimum_size = art.get_size()
	row.add_child(mark)
	_label = UiKit.label("", &"HintLabel")
	_label.name = "Text"
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_label)


## 一行放不下（窄屏、长文案）才折行，折行宽度受 MAX_TEXT_WIDTH 限制。
func _fit_label() -> void:
	if _label == null:
		return
	var font := _label.get_theme_font("font")
	var size := _label.get_theme_font_size("font_size")
	var width := font.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	if width > MAX_TEXT_WIDTH:
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_label.custom_minimum_size.x = MAX_TEXT_WIDTH
	else:
		_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		_label.custom_minimum_size.x = 0.0


## HUD 按触屏安全区把提示条往下挪。
func set_top(y: float) -> void:
	if _panel != null:
		_panel.offset_top = y


func view_rect() -> Rect2:
	return _panel.get_global_rect() if _panel != null else Rect2()
