extends Node
## 竞技场运行时（Autoload）：限时生存切片。绝不写战役 SaveData，只写独立记录文件。
##
## 生命周期：start() → GameContext.pending_world_path = Arena_Duel + 淡入表现层
##          → 场景里 ArenaRun.begin() → _process 计时/HUD
##          → 死亡或时间到 → finish(win) → 写 user://rustgrave_arena.cfg → 2.5s 后回标题。
##
## 3v3 推线是后续目标；这一版先把"模式入口/独立记录/不碰战役档/计时与计分"跑通。

signal match_finished(result: Dictionary)

const ArenaCatalog := preload("res://scripts/data/arena_catalog.gd")

static var _node: Node = null
static var _active := false
static var _finished := false
static var _score := 0
static var _kills := 0
static var _time_left := ArenaCatalog.DURATION
static var _last_result: Dictionary = {}
static var _strip: CanvasLayer = null
static var _strip_label: Label = null
static var _records_path := ArenaCatalog.RECORDS_PATH


func _ready() -> void:
	_node = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameEvents.player_died.connect(_on_player_died)


func _exit_tree() -> void:
	if _node == self:
		_node = null
	if GameEvents.player_died.is_connected(_on_player_died):
		GameEvents.player_died.disconnect(_on_player_died)


func _process(delta: float) -> void:
	if not active() or _finished:
		return
	_time_left = maxf(0.0, _time_left - delta)
	_update_strip()
	if _time_left <= 0.0:
		finish(true)


# --------------------------------------------------------------- lifecycle --

## 从标题/菜单进入竞技场。返回是否成功开始。
static func start() -> bool:
	if _node == null or not is_instance_valid(_node):
		return false
	_clear_screens()
	_active = true
	_finished = false
	_score = 0
	_kills = 0
	_time_left = ArenaCatalog.DURATION
	_last_result = {}
	GameContext.pending_world_path = ArenaCatalog.SCENE
	var route := GameContext.route_scene(ArenaCatalog.SCENE)
	if route == "":
		_active = false
		return false
	_ensure_strip()
	_update_strip()
	Director.fade_to(route, 0.45)
	return true


## 场景搭好后调用：开始跑计时。
## 测试/截图用：不经过标题淡入，直接把会话拉起来（仍不写战役档）。
static func activate_for_test() -> void:
	_active = true
	_finished = false
	_score = 0
	_kills = 0
	_time_left = ArenaCatalog.DURATION
	_last_result = {}
	_ensure_strip()
	_update_strip()


static func begin() -> void:
	if not _active:
		return
	_finished = false
	_ensure_strip()
	_update_strip()


static func active() -> bool:
	return _active


static func running() -> bool:
	return _active and not _finished


static func score() -> int:
	return _score


static func add_kill(points: int = 0) -> void:
	if not running():
		return
	_kills += 1
	_score += maxi(0, points)
	_update_strip()


static func time_left() -> float:
	return _time_left


static func last_result() -> Dictionary:
	return _last_result


## 结算：写独立记录 + 通知信号 + 显示结算条 + 2.5s 回标题。
static func finish(win: bool) -> void:
	if not _active or _finished:
		return
	_finished = true
	_last_result = {
		"win": win,
		"score": _score,
		"kills": _kills,
		"time_left": _time_left,
		"elapsed": ArenaCatalog.DURATION - _time_left,
	}
	_write_records(_last_result)
	_show_result_strip(_last_result)
	_emit_finished(_last_result)
	await _node.get_tree().create_timer(2.5).timeout
	exit_to_title()


static func abandon() -> void:
	_clear_screens()
	_active = false
	_finished = false
	_score = 0
	_kills = 0
	_time_left = ArenaCatalog.DURATION


## SaveData 写锁：竞技场会话中战役档只读。
static func blocks_campaign_save() -> bool:
	return _active


static func exit_to_title() -> void:
	var was_active := _active
	_clear_screens()
	_active = false
	_finished = false
	if was_active:
		Director.fade_to(ArenaCatalog.TITLE_SCENE, 0.5)


func _on_player_died() -> void:
	if running():
		finish(false)


# ------------------------------------------------------------------ records --

static func use_file(path: String) -> void:
	_records_path = path


static func use_default_file() -> void:
	_records_path = ArenaCatalog.RECORDS_PATH


static func read_records() -> Dictionary:
	if not FileAccess.file_exists(_records_path):
		return {"best_score": 0, "best_kills": 0, "runs": 0}
	var cfg := ConfigFile.new()
	if cfg.load(_records_path) != OK:
		return {"best_score": 0, "best_kills": 0, "runs": 0}
	return {
		"best_score": int(cfg.get_value("meta", "best_score", 0)),
		"best_kills": int(cfg.get_value("meta", "best_kills", 0)),
		"runs": int(cfg.get_value("meta", "runs", 0)),
	}


static func _write_records(result: Dictionary) -> void:
	var records := read_records()
	records["best_score"] = maxi(int(records["best_score"]), int(result.get("score", 0)))
	records["best_kills"] = maxi(int(records["best_kills"]), int(result.get("kills", 0)))
	records["runs"] = int(records.get("runs", 0)) + 1
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", ArenaCatalog.RECORDS_VERSION)
	for key in records:
		cfg.set_value("meta", String(key), records[key])
	cfg.save(_records_path)


# ------------------------------------------------------------------- HUD ----

static func strip() -> CanvasLayer:
	return _strip


static func strip_text() -> String:
	if _strip_label == null or not is_instance_valid(_strip_label):
		return ""
	return _strip_label.text


static func _ensure_strip() -> void:
	if _strip != null and is_instance_valid(_strip):
		return
	if _node == null or not _node.is_inside_tree():
		return
	var host := GameContext.ui_host()
	if host == null:
		host = _node.get_tree().root
	_strip = CanvasLayer.new()
	_strip.name = "ArenaHud"
	_strip.layer = 14
	_strip.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(_strip)
	PresentationMetrics.bind_layer(_strip)
	WorldClock.isolate_ui_layer(_strip)
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiKit.extras_theme()
	_strip.add_child(root)
	var plate := UiKit.panel(&"HudPlate")
	plate.name = "Plate"
	plate.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	plate.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	plate.grow_vertical = Control.GROW_DIRECTION_END
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(plate)
	_strip_label = UiKit.label("", &"TinyStrongLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	_strip_label.name = "Text"
	_strip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_strip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(_strip_label)


static func _update_strip() -> void:
	if _strip_label == null or not is_instance_valid(_strip_label):
		return
	_strip_label.text = ArenaCatalog.strip_text(_score, _kills, _time_left)


static func _show_result_strip(result: Dictionary) -> void:
	if _node == null or not _node.is_inside_tree():
		return
	var host := GameContext.ui_host()
	if host == null:
		host = _node.get_tree().root
	var layer := CanvasLayer.new()
	layer.name = "ArenaResult"
	layer.layer = 30
	host.add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var panel := UiKit.panel(&"OrnatePanel")
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	box.add_child(UiKit.label("竞 技 场 · 结 算", &"TinyStrongLabel", HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UiKit.divider())
	box.add_child(UiKit.label(ArenaCatalog.result_summary(result), &"SubHeadLabel",
			HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UiKit.label("即将返回标题……", &"FootnoteLabel",
			HORIZONTAL_ALIGNMENT_CENTER))
	layer.name = "ArenaResult"


static func _emit_finished(result: Dictionary) -> void:
	if _node == null or not is_instance_valid(_node):
		return
	(_node as Node).emit_signal("match_finished", result)


static func _clear_screens() -> void:
	if _strip != null and is_instance_valid(_strip):
		_strip.queue_free()
	_strip = null
	_strip_label = null
	if _node != null and _node.is_inside_tree():
		var host := GameContext.ui_host()
		if host != null:
			var old := host.get_node_or_null("ArenaResult")
			if old != null:
				old.queue_free()
