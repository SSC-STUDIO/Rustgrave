extends Node
## 回火试炼运行时（Autoload，契约 §5）。不要给它 class_name —— 注册后
## `TrialRun` 这个名字就是 API；没注册时（测试 / 分支合并途中）脚本里的 static
## 函数同样可用：`const Trial := preload("res://scripts/autoload/trial_run.gd")`。
##
## 职责：
##   · start(track, target) / active() / abandon() / result —— 试炼生命周期
##   · 载入：只走 GameContext.pending_world_path + Director.fade_to(GamePresentation)，
##     不新建场景加载器（契约 §5）
##   · 计时：单调累加（Time 以 delta 累计，短帧不丢、暂停不涨），死亡数，
##     死亡后 0.9s 自动快速重试（含淡变仍 ≤2s）
##   · 规则：Boss 连战逐场推进（每胜一场回复 1 HP）；限时 / 禁核到出口即结算；
##     Boss 名号由现有 CinematicPresentation 保留（本文件不动它）
##   · 试炼绝不写战役 SaveData：blocks_campaign_save() 供 SaveData 的写入锁读取；
##     记录只写 TrialRecords 的独立文件
##   · 屏幕：右上角试炼条（计时 / 死亡 / 重试提示，不遮角色与预警）+ 结算 overlay
##
## 集成挂点（Lead 合并）：project.godot 注册本 Autoload；SaveData 写入锁；
## Director.play* 在试炼中跳过；player._on_died / HUD._on_player_died / level_exit
## 的试炼分支。详见交接报告里的 patch。

signal run_finished(result: Dictionary)

## 死亡后自动重试的等待（秒）。含淡变 → 重开在 2s 内。
const RETRY_DELAY := 0.9
const MENU_SCENE := "res://scenes/ui/TrialMenu.tscn"
const TITLE_SCENE := "res://scenes/ui/TitleScreen.tscn"
## preload 而不是全局类名：新 class_name 要等编辑器写类缓存；测试/合并期间都能用。
const Catalog := preload("res://scripts/data/trial_catalog.gd")
const Records := preload("res://scripts/data/trial_records.gd")
## 结算 overlay 用运行时 load：它反过来要调本文件的静态接口，preload 会形成循环依赖。
const RESULTS_PATH := "res://scripts/ui/trial_results.gd"

## --- 运行时状态（static：autoload 没注册时测试也能直接驱动） -------------------
static var _node: Node = null
static var _active := false
static var _finished := false
static var _track := -1
static var _target_id := ""
static var _stages: Array[Dictionary] = []
static var _stage_index := 0
static var _elapsed_acc := 0.0
static var _deaths := 0
static var _no_hit := true
static var _retry_left := 0.0
static var _carry_hp := -1
static var _stage_entry_hp := -1
static var _last_result: Dictionary = {}
static var _requester: Callable = Callable()
static var _strip: CanvasLayer = null
static var _strip_time: Label = null
static var _strip_info: Label = null
static var _strip_kicker: Label = null
static var _player_seen: Node = null
static var _stage_started := false
static var _apply_retry := false


func _ready() -> void:
	_node = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameEvents.player_died.connect(_on_player_died)
	GameEvents.boss_defeated.connect(_on_boss_defeated)
	GameEvents.player_respawned.connect(_on_player_respawned)


func _exit_tree() -> void:
	if _node == self:
		_node = null
	if GameEvents.player_died.is_connected(_on_player_died):
		GameEvents.player_died.disconnect(_on_player_died)
	if GameEvents.boss_defeated.is_connected(_on_boss_defeated):
		GameEvents.boss_defeated.disconnect(_on_boss_defeated)
	if GameEvents.player_respawned.is_connected(_on_player_respawned):
		GameEvents.player_respawned.disconnect(_on_player_respawned)


func _process(delta: float) -> void:
	tick(delta)


# --- 生命周期（static API） ----------------------------------------------------

## 开始一场试炼。校验赛道 / 解锁门 / 目标；成功返回 true 并立刻请求载入第一场。
static func start(track: int, target_id: String) -> bool:
	if not Catalog.is_valid_track(track):
		return false
	if not Catalog.unlocked():
		return false
	var stages := Catalog.stages_for(track, target_id)
	if stages.is_empty():
		return false
	_clear_screens()
	_active = true
	_finished = false
	_track = track
	_target_id = target_id
	_stages = stages
	_stage_index = 0
	_elapsed_acc = 0.0
	_deaths = 0
	_no_hit = true
	_retry_left = 0.0
	_carry_hp = -1
	_stage_entry_hp = -1
	_apply_retry = false
	_player_seen = null
	_stage_started = false
	_last_result = {}
	_load_stage()
	return true


## 试炼会话进行中（含结算画面）。SaveData 的写入锁看这个。
static func active() -> bool:
	return _active


## 试炼正在跑（未结算）。时机/暂停菜单/HUD 看这个。
static func running() -> bool:
	return _active and not _finished


static func finished() -> bool:
	return _active and _finished


## 中止试炼（回标题 / 换赛道）：清状态，不写任何战役档。
static func abandon() -> void:
	_active = false
	_finished = false
	_track = -1
	_target_id = ""
	_stages = []
	_stage_index = 0
	_elapsed_acc = 0.0
	_deaths = 0
	_retry_left = 0.0
	_player_seen = null
	_stage_started = false
	_clear_screens()


static func result() -> Dictionary:
	return _last_result.duplicate(true)


static func track() -> int:
	return _track


static func target_id() -> String:
	return _target_id


static func stage_index() -> int:
	return _stage_index


static func stage_count() -> int:
	return _stages.size()


static func stage() -> Dictionary:
	if _stage_index < 0 or _stage_index >= _stages.size():
		return {}
	return (_stages[_stage_index] as Dictionary).duplicate(true)


static func elapsed_ms() -> int:
	return int(_elapsed_acc)


static func deaths() -> int:
	return _deaths


static func no_hit() -> bool:
	return _no_hit


## HUD / 菜单 / 暂停菜单共用的一行状态。
static func status_line() -> String:
	if not running():
		return ""
	var parts := [Catalog.track_name(_track), display_time()]
	if _stages.size() > 1 and _track == Catalog.Track.BOSS_RUSH:
		parts.append("第 %d/%d 场" % [_stage_index + 1, _stages.size()])
	parts.append("死亡 %d" % _deaths)
	return " · ".join(parts)


static func display_time() -> String:
	return Records.format_ms(elapsed_ms())


# --- 载入 ---------------------------------------------------------------------

static func _load_stage() -> void:
	if _stage_index < 0 or _stage_index >= _stages.size():
		return
	var stage_row: Dictionary = _stages[_stage_index]
	_retry_left = 0.0
	_apply_retry = false
	_player_seen = null
	_stage_started = false
	GameContext.pending_world_path = String(stage_row.get("scene", ""))
	# 复用现有 pending 机制：route_scene() 只设置 pending_world_path 并返回表现层路径。
	var route := GameContext.route_scene(String(stage_row.get("scene", "")))
	_request_scene(route)


static func _request_scene(path: String) -> void:
	if path == "":
		return
	if _requester.is_valid():
		_requester.call(path)
		return
	if _node != null and _node.is_inside_tree():
		Director.fade_to(path, 0.45)


## 测试 / 工具用：劫持场景请求（不真的切场景）。传空 Callable 恢复默认。
static func set_scene_requester(requester: Callable) -> void:
	_requester = requester


static func clear_scene_requester() -> void:
	_requester = Callable()


## 当前这一场应加载的场景路径（测试用）。
static func stage_scene_path() -> String:
	var row := stage()
	return String(row.get("scene", ""))


# --- 每帧 ---------------------------------------------------------------------

## 计时 / 重试 / HUD 同步。Autoload 的 _process 每帧调它；测试也可以直接调。
static func tick(delta: float) -> void:
	if not _active:
		return
	if _node == null or not _node.is_inside_tree():
		return
	var tree := _node.get_tree()
	if tree == null or tree.paused:
		return
	if running():
		if not _director_fading():
			_elapsed_acc += delta * 1000.0
		if _retry_left > 0.0:
			_retry_left = maxf(0.0, _retry_left - delta)
			if _retry_left <= 0.0:
				_reload_stage()
		_sync_player()
	_update_strip()


static func _director_fading() -> bool:
	if _node == null or not _node.is_inside_tree():
		return false
	return Director.is_fading()


## 找到玩家就套固定装载、摆落点、建 HUD 条。每帧调用，直到玩家就位。
static func _sync_player() -> void:
	var player := _live_player()
	if player == null:
		_player_seen = null
		_stage_started = false
		return
	if player == _player_seen and _stage_started:
		return
	_player_seen = player
	var row := stage()
	_apply_loadout(player)
	# Boss 连战：把骑士放到竞技场外的安全落点，让 Boss 自己 announce 入场。
	var spawn: Vector2 = (row.get("spawn", Vector2.INF) as Vector2)
	if spawn != Vector2.INF:
		player.global_position = spawn
	_stage_started = true
	_ensure_strip()
	_update_strip()


static func _live_player() -> Node:
	if _node == null or not _node.is_inside_tree():
		return null
	return _node.get_tree().get_first_node_in_group("player")


## 固定装载（契约 §5）：生命 / 锈核插座 / 口袋都按 TrialCatalog 的快照重置。
static func _apply_loadout(player: Node) -> void:
	var loadout := Catalog.loadout_for(_track)
	var hp := player.get_node_or_null("Health") as Health
	if hp != null:
		hp.max_hp = int(loadout.get("hp", Catalog.BASE_MAX_HP))
		var target_hp := hp.max_hp
		if _track == Catalog.Track.BOSS_RUSH and _carry_hp > 0:
			target_hp = clampi(_carry_hp, 1, hp.max_hp)
			_carry_hp = -1
		hp.current = target_hp
		if _stage_entry_hp < 0:
			_stage_entry_hp = target_hp
		hp.changed.emit(hp.current, hp.max_hp)
		GameEvents.player_health_changed.emit(hp.current, hp.max_hp)
	if player is Player:
		var actor := player as Player
		if actor.inventory != null:
			var inv := actor.inventory
			inv.pouch.clear()
			for slot in inv.socket_count:
				inv.sockets[slot] = null
			var sockets: Array = loadout.get("sockets", [])
			for slot in mini(sockets.size(), inv.socket_count):
				var core := AbilityCatalog.for_id(StringName(sockets[slot]))
				if core != null:
					inv.sockets[slot] = core
			for core_id in loadout.get("pouch", []):
				var pouch_core := AbilityCatalog.for_id(StringName(core_id))
				if pouch_core != null:
					inv.pouch.append(pouch_core)
			inv.sockets_changed.emit()
			inv.pouch_changed.emit()
			GameEvents.sockets_changed.emit()
		if actor.toxin != null:
			actor.toxin.toxin = 0.0
			GameEvents.toxin_changed.emit(0.0, actor.toxin.max_toxin)
		if actor.equipment_inventory != null:
			actor.equipment_inventory.deserialize(Catalog.EQUIPMENT)


# --- 事件 ---------------------------------------------------------------------

## 只有"当前管事"的那个实例处理信号：重复挂载 / 测试 fixture + autoload 并存时，
## 一次死亡或一次 Boss 击杀不能被记两遍。
func _handles_events() -> bool:
	return _node == null or _node == self


func _on_player_died() -> void:
	if not _handles_events():
		return
	on_player_died()


## 死亡：记一次死亡、宣布无伤没了、0.9s 后自动重试本场（不写档、不读档）。
static func on_player_died() -> void:
	if not running() or _retry_left > 0.0:
		return
	_deaths += 1
	_no_hit = false
	_retry_left = RETRY_DELAY


func _on_player_respawned() -> void:
	if not _handles_events():
		return
	# 战役的重燃流程在试炼里不该发生（player._on_died 的补丁会拦住），
	# 万一有别处触发也当一次重试处理。
	on_player_died()


func _on_boss_defeated() -> void:
	if not _handles_events():
		return
	on_boss_defeated()


## Boss 连战：胜一场 → 记下携带生命（+1）→ 下一场；最后一场 → 结算。
## 限时 / 禁核选第一章时，"出口"就是刽子手倒下（第一章的完成旗标 boss_dead）。
static func on_boss_defeated() -> void:
	if not running():
		return
	if _track != Catalog.Track.BOSS_RUSH:
		var stage_row := stage()
		var lid := String(stage_row.get("level_id", ""))
		if lid == "level01" or lid == "stage01":
			finish(&"boss_dead")
		return
	var hp := _live_player_health()
	var max_hp := _live_player_max_hp()
	if _stage_index + 1 < _stages.size():
		_carry_hp = mini(max_hp, maxi(1, hp + 1)) if max_hp > 0 else -1
		_stage_index += 1
		_stage_entry_hp = -1
		_load_stage()
	else:
		finish(&"boss_rush_clear")


static func _live_player_health() -> int:
	var player := _live_player()
	if player == null:
		return 0
	var hp := player.get_node_or_null("Health") as Health
	return hp.current if hp != null else 0


static func _live_player_max_hp() -> int:
	var player := _live_player()
	if player == null:
		return 0
	var hp := player.get_node_or_null("Health") as Health
	return hp.max_hp if hp != null else 0


## 限时 / 禁核：到达出口（level_exit 补丁调用）。
static func reach_goal() -> void:
	if not running() or _track == Catalog.Track.BOSS_RUSH:
		return
	finish(&"exit")


## 结算：评级、写独立记录、发信号、显示结算 overlay。只写 TrialRecords。
static func finish(reason: StringName = &"exit") -> void:
	if not _active or _finished:
		return
	_finished = true
	_retry_left = 0.0
	var score := Catalog.score_ms(_track, elapsed_ms(), _deaths)
	var rank := Catalog.rank_for(_track, elapsed_ms(), _deaths, stage_count())
	var result := {
		"track": _track,
		"track_id": String(Catalog.track_id(_track)),
		"track_name": Catalog.track_name(_track),
		"target_id": _target_id,
		"target_title": Catalog.target_title(_track, _target_id),
		"elapsed_ms": elapsed_ms(),
		"deaths": _deaths,
		"no_hit": _no_hit,
		"stage_count": stage_count(),
		"stages_cleared": (stage_count() if reason == &"boss_rush_clear" else 1),
		"score_ms": score,
		"rank": String(rank),
		"reason": String(reason),
	}
	var submission := Records.submit(_track, _target_id, result)
	result["record"] = submission
	result["is_best"] = bool(submission.get("is_best", false))
	result["is_first"] = bool(submission.get("is_first", false))
	result["best_ms"] = int((submission.get("record", {}) as Dictionary).get("ms", elapsed_ms()))
	_last_result = result
	_show_results(result)
	if _node != null and is_instance_valid(_node):
		_node.run_finished.emit(result)


# --- 退出 / 重开 ---------------------------------------------------------------

## 暂停菜单「重开本场」：不记死亡、计时继续，重载当前场。
static func retry_stage() -> void:
	if not running() or _retry_left > 0.0:
		return
	_reload_stage()


static func _reload_stage() -> void:
	if not running():
		return
	_apply_retry = true
	_stage_entry_hp = -1
	_load_stage()


## 退出试炼回标题（不写战役档）。
static func exit_to_title() -> void:
	abandon()
	show_scene(TITLE_SCENE)


## 退出试炼回试炼菜单。
static func exit_to_menu() -> void:
	abandon()
	show_scene(MENU_SCENE)


static func show_scene(path: String) -> void:
	if path == "":
		return
	var tree := _node.get_tree() if _node != null and _node.is_inside_tree() else null
	if tree != null and tree.paused:
		tree.paused = false
	if _requester.is_valid():
		_requester.call(path)
		return
	if _node != null and _node.is_inside_tree():
		Director.fade_to(path, 0.5)


# --- 写入锁 / 集成查询 ---------------------------------------------------------

## SaveData 的写入锁（补丁读取）：试炼会话中返回 true，所有战役写函数直接 no-op。
static func blocks_campaign_save() -> bool:
	return _active


## Director / 间幕补丁读取：试炼进行中不播章节卡与间幕（Boss 名号走 signal，不受影响）。
static func suppresses_cinematics() -> bool:
	return running()


## Boss 击杀补丁：某些关卡会因为战役旗标跳过 Boss，试炼里必须重新生成。
static func forces_boss_spawn() -> bool:
	return running() and _track == Catalog.Track.BOSS_RUSH


## level_exit 补丁：试炼里推开门 = 到达终点，不执行战役换场。
static func handles_level_exit() -> bool:
	return running()


# --- HUD 试炼条 ----------------------------------------------------------------

static func strip() -> CanvasLayer:
	return _strip


static func strip_visible() -> bool:
	return _strip != null and is_instance_valid(_strip) and _strip.visible


## 试炼条矩形（设计单位，HUD 层坐标）。测试断言它不压角色/预警区。
static func strip_rect() -> Rect2:
	if _strip == null or not is_instance_valid(_strip):
		return Rect2()
	var root := _strip.get_node_or_null("Root") as Control
	var plate := root.get_node_or_null("Plate") as Control if root != null else null
	return plate.get_global_rect() if plate != null else Rect2()


static func strip_text() -> String:
	if _strip_time == null or not is_instance_valid(_strip_time):
		return ""
	return "%s | %s" % [_strip_time.text, _strip_info.text]


static func _ensure_strip() -> void:
	if _strip != null and is_instance_valid(_strip):
		return
	if _node == null or not _node.is_inside_tree():
		return
	var host := GameContext.ui_host()
	if host == null:
		host = _node.get_tree().root
	_strip = CanvasLayer.new()
	_strip.name = "TrialHud"
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
	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(column)
	_strip_kicker = UiKit.label("", &"TinyStrongLabel")
	_strip_kicker.name = "Kicker"
	_strip_kicker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_strip_kicker.max_lines_visible = 1
	_strip_kicker.clip_text = true
	_strip_kicker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_strip_kicker)
	_strip_time = UiKit.label("00:00.0", &"PromptLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	_strip_time.name = "Time"
	_strip_time.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_strip_time.max_lines_visible = 1
	column.add_child(_strip_time)
	_strip_info = UiKit.label("", &"TinyLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	_strip_info.name = "Info"
	_strip_info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_strip_info.max_lines_visible = 1
	_strip_info.clip_text = true
	_strip_info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_strip_info)
	_update_strip()


## 顶部右上角：天气行下面一条矮墨带（不遮骑士 / 预警）。安全区刘海一起让开。
static func _update_strip() -> void:
	if _strip == null or not is_instance_valid(_strip):
		return
	var root := _strip.get_node_or_null("Root") as Control
	if root == null:
		return
	var plate := root.get_node_or_null("Plate") as Control
	if plate == null:
		return
	var insets := Vector4.ZERO
	var tree := _node.get_tree() if _node != null and _node.is_inside_tree() else null
	if tree != null:
		insets = PresentationMetrics.safe_layer_insets(tree.root)
	plate.offset_left = -238.0 - insets.z
	plate.offset_right = -18.0 - insets.z
	plate.offset_top = 36.0 + insets.y
	plate.offset_bottom = 36.0 + insets.y
	if _strip_kicker != null:
		_strip_kicker.text = "回 火 试 炼 · %s" % Catalog.track_name(_track)
	var retrying := _retry_left > 0.0
	if _strip_time != null:
		_strip_time.text = display_time()
		_strip_time.modulate = Color(1.3, 0.7, 0.55) if retrying else Color.WHITE
	if _strip_info != null:
		if retrying:
			_strip_info.text = "余烬熄灭 · 重试中…"
			_strip_info.modulate = Color(1.25, 0.8, 0.6)
		else:
			var bits := PackedStringArray()
			if _stages.size() > 1 and _track == Catalog.Track.BOSS_RUSH:
				bits.append("第 %d/%d 场" % [_stage_index + 1, _stages.size()])
			bits.append("死亡 %d" % _deaths)
			bits.append("Esc 暂停")
			_strip_info.text = " · ".join(bits)
			_strip_info.modulate = Color.WHITE


static func _clear_screens() -> void:
	if _strip != null and is_instance_valid(_strip):
		_strip.queue_free()
	_strip = null
	_strip_time = null
	_strip_info = null
	_strip_kicker = null
	var results: GDScript = load(RESULTS_PATH) as GDScript
	if results != null:
		results.close_all()


# --- 结算 overlay ---------------------------------------------------------------

static func _show_results(result: Dictionary) -> void:
	var results: GDScript = load(RESULTS_PATH) as GDScript
	if results != null:
		results.show_result(result)
