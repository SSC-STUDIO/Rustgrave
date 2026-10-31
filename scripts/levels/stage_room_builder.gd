class_name StageRoomBuilder
extends ChapterLayout
## 多房间节点关卡（StageLevel）的声明式单房铺设器。
##
## 继承 `ChapterLayout` 复用全套地形/机关/敌人/主题装饰/背景生成管线，并新增《ICEY》式组件助手：
##   · `room_box`          一键铺设单屏/双屏紧凑盒体（640~1280px）及深井/竖井开口；
##   · `touch_gate_*`      触碰式极速切房边界口（自动避开地面与墙体碰撞盒，符合 LevelSanity）；
##   · `arch_gate`         按 E 通行的跨节点/隐藏支线拱门；
##   · `wave_arena`        封门多波次高密度战斗场 + 刷怪预警圈 + 清场慢动作与路标联动；
##   · `guide_arrow`       伊尔发光方向路标；
##   · `disobedience_*`    越界/3刀破封/挂机驻足/收剑慈悲四种叛逆检测器；
##   · `truth_terminal`    禁区支线尽头的【真名残片】终端；
##   · `stage_boss`        Boss 战房封装（联动 RoomGate、GuideArrow、Boss 旗标与单次会话记忆）。

var stage_id_val: String = "stage01"
var stage_theme: String = "graveyard"
var stage_motes: String = "ash"
var room_w: int = 800
var room_cam_top: int = -48
var stage_ambient: Dictionary = {}
var stage_weather_recipe: Dictionary = {}


func configure_stage(p_stage_id: String, p_theme: String, p_motes: String = "",
		p_ambient: Dictionary = {}, p_weather: Dictionary = {}) -> void:
	stage_id_val = p_stage_id
	stage_theme = p_theme
	stage_motes = p_motes
	stage_ambient = p_ambient
	stage_weather_recipe = p_weather


func level_id() -> String:
	return stage_id_val


func title() -> String:
	return ChapterText.title_of(stage_id_val)


func east_limit() -> int:
	return room_w


func camera_top() -> int:
	return room_cam_top


func theme() -> String:
	return stage_theme


func motes() -> String:
	return stage_motes


func ambient() -> Dictionary:
	return stage_ambient


func weather_recipe() -> Dictionary:
	return stage_weather_recipe


func room_ids() -> Array[String]:
	return ["S1"]


func default_room() -> String:
	var ids := room_ids()
	return ids[0] if not ids.is_empty() else "S1"


func entry_spawn() -> Vector2:
	return spawn_for_room(default_room(), "west")


func boss_room() -> String:
	return ""


func spawn_for_room(_room_id: String, spawn_tag: String) -> Vector2:
	match spawn_tag:
		"east":
			return Vector2(float(room_w) - 72.0, FLOOR_Y)
		"top":
			return Vector2(float(room_w) * 0.5, 64.0)
		"bottom":
			return Vector2(float(room_w) * 0.5, FLOOR_Y)
		_:
			return Vector2(72.0, FLOOR_Y)


func build_room(_host: Node2D, _room_id: String) -> void:
	pass


func on_room_entered(_host: Node2D, _room_id: String) -> void:
	pass


## 铺设单房外框与主地面。
##   pit_range:   Vector2(x0, x1) 在主地面挖出深渊落口（x1 > x0 时生效，坑底留净空供 touch_gate_pit 接住）；
##   shaft_range: Vector2(x0, w)  在室内顶板留出向上攀爬的竖井口（w > 0 时生效）。
func room_box(host: Node2D, width_px: int, indoor_box: bool = true, skin: String = "",
		ceiling_y: float = -32.0, pit_range: Vector2 = Vector2.ZERO,
		shaft_range: Vector2 = Vector2.ZERO, add_pit_bed: bool = true) -> void:
	room_w = width_px
	room_cam_top = int(minf(-48.0, ceiling_y - 16.0)) if indoor_box else -96
	var use_skin := skin if skin != "" else skin_family()
	var w := float(width_px)

	if pit_range.y > pit_range.x + 16.0:
		if pit_range.x > 0.0:
			floor_strip(host, "FloorWest", 0.0, pit_range.x, use_skin, true, true)
		if pit_range.y < w:
			floor_strip(host, "FloorEast", pit_range.y, w, use_skin, true, true)
		# 深坑安全兜底台（在 FLOOR_Y + 72 处兜底，高于 VOID_MARGIN 以通过 LevelSanity 接地与防坠检查）
		if add_pit_bed:
			platform(host, "PitSafetyBed", Vector2(pit_range.x, FLOOR_Y + 72.0),
					Vector2(pit_range.y - pit_range.x, 32.0), use_skin, false, false)
	else:
		floor_strip(host, "FloorMain", 0.0, w, use_skin, true, true)

	if indoor_box:
		enclose(host, use_skin, ceiling_y, shaft_range.x, shaft_range.y)
	else:
		walls(host, use_skin, -192.0)


func touch_gate_west(host: Node2D, target_room: String, target_spawn: String = "east",
		target_stage: String = "", feet_y: float = FLOOR_Y) -> RoomGate:
	var g := RoomGate.new()
	g.name = "GateWest_%s" % (target_room if target_room != "" else target_stage)
	g.mode = RoomGate.Mode.TOUCH_EDGE
	g.position = Vector2(20.0, feet_y - 32.0)
	g.touch_size = Vector2(28.0, 64.0)
	g.target_room = target_room
	g.target_spawn = target_spawn
	g.target_stage = target_stage
	group(host, "Props").add_child(g)
	return g


func touch_gate_east(host: Node2D, target_room: String, target_spawn: String = "west",
		target_stage: String = "", unlock_node: String = "", done_node: String = "",
		feet_y: float = FLOOR_Y) -> RoomGate:
	var g := RoomGate.new()
	g.name = "GateEast_%s" % (target_room if target_room != "" else target_stage)
	g.mode = RoomGate.Mode.TOUCH_EDGE
	g.position = Vector2(float(room_w) - 20.0, feet_y - 32.0)
	g.touch_size = Vector2(28.0, 64.0)
	g.target_room = target_room
	g.target_spawn = target_spawn
	g.target_stage = target_stage
	g.unlock_node_id = unlock_node
	g.done_node_id = done_node
	group(host, "Props").add_child(g)
	return g


func touch_gate_pit(host: Node2D, pit_mid_x: float, pit_width: float, target_room: String,
		target_spawn: String = "top", target_stage: String = "", unlock_node: String = "") -> RoomGate:
	var g := RoomGate.new()
	g.name = "GatePit_%s" % (target_room if target_room != "" else target_stage)
	g.mode = RoomGate.Mode.TOUCH_EDGE
	g.position = Vector2(pit_mid_x, FLOOR_Y + 34.0)
	g.touch_size = Vector2(maxf(24.0, pit_width - 16.0), 28.0)
	g.target_room = target_room
	g.target_spawn = target_spawn
	g.target_stage = target_stage
	g.unlock_node_id = unlock_node
	group(host, "Props").add_child(g)
	return g


func touch_gate_shaft(host: Node2D, shaft_mid_x: float, shaft_width: float, ceiling_y: float,
		target_room: String, target_spawn: String = "bottom", target_stage: String = "",
		unlock_node: String = "") -> RoomGate:
	var g := RoomGate.new()
	g.name = "GateShaft_%s" % (target_room if target_room != "" else target_stage)
	g.mode = RoomGate.Mode.TOUCH_EDGE
	g.position = Vector2(shaft_mid_x, ceiling_y + 18.0)
	g.touch_size = Vector2(maxf(24.0, shaft_width - 16.0), 28.0)
	g.target_room = target_room
	g.target_spawn = target_spawn
	g.target_stage = target_stage
	g.unlock_node_id = unlock_node
	group(host, "Props").add_child(g)
	return g


func arch_gate(host: Node2D, gate_name: String, feet: Vector2, label: String,
		target_room: String, target_spawn: String = "west", target_stage: String = "",
		unlock_node: String = "", done_node: String = "", req_flag: String = "",
		lock_text: String = "铁栅封死") -> RoomGate:
	var g := RoomGate.new()
	g.name = gate_name
	g.mode = RoomGate.Mode.INTERACT
	g.position = feet
	g.gate_label = label
	g.target_room = target_room
	g.target_spawn = target_spawn
	g.target_stage = target_stage
	g.unlock_node_id = unlock_node
	g.done_node_id = done_node
	g.requires_flag = req_flag
	g.locked_prompt = lock_text
	group(host, "Props").add_child(g)
	return g


func guide_arrow(host: Node2D, arrow_name: String, pos: Vector2,
		dir: int = GuideArrow.Dir.RIGHT, tag: String = "",
		lit_on_start: bool = true) -> GuideArrow:
	var a := GuideArrow.new()
	a.name = arrow_name
	a.position = pos
	a.direction = dir as GuideArrow.Dir
	a.label_text = tag
	a.active_on_start = lit_on_start
	group(host, "Decor").add_child(a)
	return a


func wave_arena(host: Node2D, arena_name: String, p_room_id: String,
		left_x: float, right_x: float, wave_list: Array,
		start_clip: String = "", clear_clip: String = "",
		clips_by_wave: Dictionary = {}, gates: Array = [],
		arrows: Array = [], floor_top: float = FLOOR_Y) -> BattleWaveArena:
	var a := BattleWaveArena.new()
	a.name = arena_name
	a.stage_id = stage_id_val
	a.room_id = p_room_id
	a.arena_left = left_x
	a.arena_right = right_x
	a.floor_y = floor_top
	a.on_start_clip = start_clip
	a.on_clear_clip = clear_clip
	a.configure_waves(wave_list, clips_by_wave)
	group(host, "Arenas").add_child(a)
	for g in gates:
		a.register_gate(g)
	for arr in arrows:
		if arr is GuideArrow:
			a.bind_arrow(arr as GuideArrow)
	return a


func disobedience_line(host: Node2D, trig_name: String, feet: Vector2, sz: Vector2,
		p_branch_id: String, clips: PackedStringArray) -> DisobedienceTrigger:
	var t := DisobedienceTrigger.new()
	t.name = trig_name
	t.mode = DisobedienceTrigger.Mode.CROSS_LINE
	t.position = feet
	t.zone_size = sz
	t.branch_id = p_branch_id
	t.voice_clips = clips
	group(host, "Props").add_child(t)
	return t


func disobedience_seal(host: Node2D, trig_name: String, feet: Vector2, sz: Vector2,
		p_branch_id: String, clips: PackedStringArray, gate: RoomGate = null,
		hits: int = 3) -> DisobedienceTrigger:
	var t := DisobedienceTrigger.new()
	t.name = trig_name
	t.mode = DisobedienceTrigger.Mode.STRIKE_SEAL
	t.position = feet
	t.zone_size = sz
	t.branch_id = p_branch_id
	t.voice_clips = clips
	t.max_hits = hits
	group(host, "Props").add_child(t)
	if gate != null:
		if not NarrativeCatalog.is_node_unlocked(p_branch_id, SaveData.flags):
			gate.set_locked(true)
		t.linked_gate_path = t.get_path_to(gate)
	return t


func disobedience_linger(host: Node2D, trig_name: String, p_branch_id: String,
		clips: PackedStringArray, seconds: float = 6.5) -> DisobedienceTrigger:
	var t := DisobedienceTrigger.new()
	t.name = trig_name
	t.mode = DisobedienceTrigger.Mode.LINGER_IDLE
	t.position = Vector2(float(room_w) * 0.5, FLOOR_Y)
	t.branch_id = p_branch_id
	t.voice_clips = clips
	t.linger_seconds = seconds
	group(host, "Props").add_child(t)
	return t


func disobedience_mercy(host: Node2D, trig_name: String, feet: Vector2, sz: Vector2,
		clips: PackedStringArray) -> DisobedienceTrigger:
	var t := DisobedienceTrigger.new()
	t.name = trig_name
	t.mode = DisobedienceTrigger.Mode.MERCY_PASS
	t.position = feet
	t.zone_size = sz
	t.voice_clips = clips
	group(host, "Props").add_child(t)
	return t


func truth_terminal(host: Node2D, term_name: String, feet: Vector2,
		p_fragment_id: String, p_branch_id: String) -> TruthFragmentPickup:
	var term := TruthFragmentPickup.new()
	term.name = term_name
	term.position = feet
	term.fragment_id = p_fragment_id
	term.branch_id = p_branch_id
	group(host, "Props").add_child(term)
	return term


func forge_heart(host: Node2D, x: float, feet_y: float = FLOOR_Y) -> ForgeHeart:
	var h := ForgeHeart.new()
	h.name = "ForgeHeart"
	# ForgeHeart 的 Fill 贴图偏移为 (-10, -8)、尺寸 (36, 40)，底边在 pos + (8, 32)
	h.position = Vector2(x - 8.0, feet_y - 32.0)
	group(host, "Props").add_child(h)
	return h


func ending_door(host: Node2D, x: float, label: String, req_flag: String = "",
		is_choice: bool = false, fixed_kind: String = "",
		feet_y: float = FLOOR_Y, lock_text: String = "门还锁着") -> LevelExit:
	# 确保距离左右墙 ≥ LevelSanity.EXIT_WALL_CLEAR (80px)
	var safe_x := clampf(x, 96.0, float(room_w) - 96.0)
	var e := LevelExit.new()
	e.name = "Exit"
	e.position = Vector2(safe_x, feet_y)
	e.door_label = label
	e.requires_flag = req_flag
	e.locked_prompt = lock_text
	e.flag_id = "game_complete"
	e.ending_choice = is_choice
	if is_choice:
		e.give_captions = ChapterText.ending_lines_of("give")
		e.keep_captions = ChapterText.ending_lines_of("keep")
	if fixed_kind != "":
		e.set("fixed_ending", fixed_kind)
	group(host, "Props").add_child(e)
	return e


func stage_boss(host: Node2D, p_room_id: String, boss_name: String, kind: String,
		pos: Vector2, arena_left: float, arena_right: float,
		gates: Array = [], arrows: Array = [], clear_flag: String = "",
		clear_clip: String = "") -> Node2D:
	if not TrialRun.active() and StageRoomMemory.is_cleared(stage_id_val, p_room_id):
		if clear_flag != "":
			SaveData.mark_flag(clear_flag)
		for g in gates:
			if g != null and g.has_method("unlock"):
				g.call("unlock")
		for arr in arrows:
			if arr is GuideArrow:
				(arr as GuideArrow).set_lit(true, false)
		return null

	var foe := boss(host, boss_name, kind, pos, arena_left, arena_right)
	var arena := boss_arena(host, boss_name)
	if arena != null:
		for g in gates:
			if g != null and arena.has_method("register_gate"):
				arena.call("register_gate", g)
	for arr in arrows:
		if arr is GuideArrow:
			(arr as GuideArrow).set_lit(false, false)

	if foe != null:
		var on_slain := func() -> void:
			StageRoomMemory.mark_cleared(stage_id_val, p_room_id)
			if clear_flag != "":
				SaveData.mark_flag(clear_flag)
			for arr in arrows:
				if arr is GuideArrow and is_instance_valid(arr):
					(arr as GuideArrow).set_lit(true, true)
			if clear_clip != "":
				GameEvents.voice_triggered.emit(clear_clip, false)
			GameEvents.battle_room_cleared.emit(p_room_id)
		if foe.has_signal("slain"):
			foe.connect("slain", on_slain, CONNECT_ONE_SHOT)
		else:
			var hp := foe.get_node_or_null("Health") as Health
			if hp != null:
				hp.died.connect(on_slain, CONNECT_ONE_SHOT)
	return foe
