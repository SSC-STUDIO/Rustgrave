class_name ChapterTransition
extends Node
## 章间间幕执行器（contract §1.3）：进下一章时**一次**的承接演出。
##
## 数据全在 StoryFlow（13 条边界）+ ChapterText（exit_captions/objective）；这里只负责
## 「什么时候播、怎么收」。口语约定：
##   · 一次：旗标 `interlude_<from>_seen`（SaveData 剧情旗标），“跳过也算看过”；
##   · 可跳过：Director.play(..., true) —— Enter / 点“跳过”都结束整段；
##   · 暂停冻结：Director.suspend()/tree.paused 时布景 age 停走（process 里 return）；
##   · 死亡读档不重播：旗标在**开演时**点上，死亡打断也算看过（与开场 abort 语义不同，
##     见 docs/story.md / contract §1.3）；abort 掉、从未开演的间幕不算看过；
##   · 切场硬复位：每次 chapter_started 先 reset_view()：布景、队列、遮幅全收；
##   · 不写未完成章节旗标：只写自己的 interlude 旗标。
##
## 播完/跳过后 ChapterLevel 的章节卡与醒来句照常接上（它们排在 Director 队列后面）。
## 在测试跑里默认 inert（Director.is_test_runner()）；story_flow_test 用 test_enabled 打开。

const OVERLAY_LAYER := 9
const SCRIM := Color(0.028, 0.018, 0.035, 0.82)
const PALE := Color("f5dfbd")
const RUST := Color("975336")
const EMBER := Color("ffc174")

var test_enabled := false

var _overlay: CanvasLayer
var _art: StagingArt
var _staging: String = ""
var _playing := false
var _pending_to: String = ""
var _flag: String = ""


func _ready() -> void:
	name = "ChapterTransition"
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameEvents.chapter_started.connect(_on_chapter_started)
	GameEvents.player_died.connect(_on_player_died)
	GameEvents.ending_chosen.connect(_on_ending_chosen)
	if not Director.script_finished.is_connected(_on_script_finished):
		Director.script_finished.connect(_on_script_finished)
	# abort() / reset_view() 只发 finished，不发 script_finished（它清的是整条队列）。
	# 渲染夹具、死亡、切场都会走 abort：不接这个信号，间幕遮罩会永远留在画面上。
	if not Director.finished.is_connected(_on_director_finished):
		Director.finished.connect(_on_director_finished)


func _on_director_finished() -> void:
	if _playing and not Director.playing:
		_playing = false
		_flag = ""
		_staging = ""
		_hide_staging()


func live() -> bool:
	return test_enabled or not Director.is_test_runner()


func is_playing() -> bool:
	return _playing


func staging() -> String:
	return _staging


## 布景动画时钟（测试读它验「暂停冻结」）。
func staging_age() -> float:
	return _art.age if _art != null else 0.0


# --- 章节到达 -------------------------------------------------------------------

func _on_chapter_started(level_id: String) -> void:
	# 切场硬复位：旧间幕、旧队列、旧遮幅都不许跟到新关。
	reset_view()
	if not live():
		return
	var edge := StoryFlow.edge_into(level_id)
	if edge.is_empty():
		return
	if SaveData.has_flag(StoryFlow.interlude_flag(String(edge["from"]))):
		return
	_pending_to = level_id
	call_deferred("_start_arrival")


## 章节卡/醒来句由 ChapterLevel 用 call_deferred("_wake") 排；这里也 defer，
## 并且先入队，所以顺序是：间幕 → 章节卡 → 醒来句 → 目标。
func _start_arrival() -> void:
	if _pending_to == "" or not is_inside_tree():
		return
	var to := _pending_to
	_pending_to = ""
	var edge := StoryFlow.edge_into(to)
	if edge.is_empty():
		return
	var flag := StoryFlow.interlude_flag(String(edge["from"]))
	if SaveData.has_flag(flag):
		return
	_play_edge(edge, to, flag)


## 测试 / 渲染夹具用：无视已看过旗标，直接播一次某条边界的间幕（不写旗标）。
func preview(from_id: String, to_id: String = "") -> bool:
	var edge := StoryFlow.for_edge(from_id)
	if edge.is_empty():
		return false
	if to_id != "" and String(edge["to"]) != to_id:
		return false
	_play_edge(edge, String(edge["to"]), "")
	return true


func _play_edge(edge: Dictionary, to_id: String, flag: String) -> void:
	var steps := StoryFlow.arrival_steps(to_id)
	if steps.is_empty():
		return
	_playing = true
	_flag = flag
	_show_staging(StoryFlow.staging_of(edge))
	Director.play_when_clear(steps, true, func() -> void: _mark_seen(flag))


## 开演才点旗：被 abort 掉、从未开演的间幕不算看过；开演后死亡打断也算看过
## （“死亡读档不重播”）。只写自己的间幕旗标，绝不写章节完成旗标。
func _mark_seen(flag: String) -> void:
	if flag != "":
		SaveData.mark_flag(flag)


# --- 收场 -----------------------------------------------------------------------

func _on_script_finished() -> void:
	if not _playing:
		return
	_playing = false
	_flag = ""
	_staging = ""
	_hide_staging()


func _on_player_died() -> void:
	# 死亡优先：先把间幕收干净，死亡 stinger 与重燃画面不许顶着间幕布景。
	reset_view()


func _on_ending_chosen(_kind: StringName) -> void:
	# 结局前后特殊序列：进终章的 pre_ending 走间幕；结局字幕由 LevelExit 从
	# ChapterText 取（StoryFlow.post_ending_steps 与它同源）。这里只做硬复位。
	reset_view()


## 硬复位：布景、队列、挂起全部清掉，幂等（切场、死亡、回标题都调）。
func reset_view() -> void:
	_pending_to = ""
	_playing = false
	_flag = ""
	_staging = ""
	_hide_staging()


# --- 布景 -----------------------------------------------------------------------

func _show_staging(staging_id: String) -> void:
	_staging = staging_id
	if _overlay == null:
		_overlay = CanvasLayer.new()
		_overlay.name = "InterludeLayer"
		_overlay.layer = OVERLAY_LAYER
		_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
		WorldClock.isolate_ui_layer(_overlay)
		PresentationMetrics.bind_layer(_overlay)
		add_child(_overlay)
		_art = StagingArt.new()
		_art.name = "Staging"
		_art.set_anchors_preset(Control.PRESET_FULL_RECT)
		_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_overlay.add_child(_art)
	_overlay.visible = true
	_art.staging = staging_id
	_art.age = 0.0
	_art.queue_redraw()


func _hide_staging() -> void:
	if _overlay != null:
		_overlay.visible = false


## 章间布景：一张压暗的 640×360 构图，只画几何，不建节点、不 loading。全部
## 布景 id 都是 StoryFlow 里出现过的；未知 id 退化成一块干净的黑幕（不报错）。
class StagingArt extends Control:
	var staging := ""
	var age := 0.0

	func _process(delta: float) -> void:
		# 暂停 / 挂起时冻住：过场中间按 Esc，布景不许在玩家背后继续动。
		if Director.is_suspended() or get_tree().paused:
			return
		age += delta
		queue_redraw()

	func _draw() -> void:
		var full := Rect2(Vector2.ZERO, size)
		draw_rect(full, Color(0.028, 0.018, 0.035, 0.82))
		var k: float = minf(size.x / 1280.0, size.y / 720.0)
		var center := size * 0.5
		_motif(k, center)
		# 顶/底两道锈线：间幕是“一页账”，不是黑屏加载。
		draw_line(Vector2(size.x * 0.16, size.y * 0.2), Vector2(size.x * 0.84, size.y * 0.2),
				Color(0.59, 0.33, 0.21, 0.55), maxf(1.0, 2.0 * k))
		draw_line(Vector2(size.x * 0.16, size.y * 0.8), Vector2(size.x * 0.84, size.y * 0.8),
				Color(0.59, 0.33, 0.21, 0.55), maxf(1.0, 2.0 * k))

	func _motif(k: float, c: Vector2) -> void:
		var pale := Color(0.96, 0.87, 0.74, 0.5)
		var ember := Color(1.0, 0.76, 0.45, 0.5)
		var rust := Color(0.59, 0.33, 0.21, 0.5)
		match staging:
			"door", "crypt":
				# 门框：两根立柱 + 门楣；灰从门缝里往上走。
				draw_rect(Rect2(c + Vector2(-120.0, -150.0) * k, Vector2(240.0, 300.0) * k),
						Color(0.05, 0.03, 0.06, 0.5))
				draw_rect(Rect2(c + Vector2(-120.0, -150.0) * k, Vector2(16.0, 300.0) * k), rust)
				draw_rect(Rect2(c + Vector2(104.0, -150.0) * k, Vector2(16.0, 300.0) * k), rust)
				draw_rect(Rect2(c + Vector2(-120.0, -150.0) * k, Vector2(240.0, 16.0) * k), rust)
				for i in 9:
					var lift := fposmod(age * (14.0 + float(i % 4) * 6.0) + float(i) * 37.0, 260.0)
					var x := c.x + fposmod(float(i) * 53.0, 180.0) - 90.0
					draw_rect(Rect2(Vector2(x, c.y + 130.0 - lift), Vector2(2.0, 2.0) * k),
							Color(ember.r, ember.g, ember.b, 0.5 * (1.0 - lift / 260.0)))
			"water", "canal":
				# 渠水：三道水平的渣波纹，慢慢往上游推。
				for row in 3:
					var y: float = c.y - 60.0 + float(row) * 60.0
					var shift := fposmod(age * (10.0 + float(row) * 4.0), 80.0)
					var points := PackedVector2Array()
					for i in 17:
						var x: float = c.x - 420.0 + float(i) * 52.0 + shift
						points.append(Vector2(x, y + sin(float(i) * 0.7 + age * 1.4) * 6.0 * k))
					draw_polyline(points, Color(pale.r, pale.g, pale.b, 0.22), maxf(1.0, 2.0 * k))
			"town":
				# 死城的窗：一排窗格，只有一扇还亮着。
				for col in 7:
					for row in 2:
						var x: float = c.x - 300.0 + float(col) * 100.0
						var y: float = c.y - 120.0 + float(row) * 130.0
						var lit := col == 4 and row == 0
						var tint := Color(0.85, 0.62, 0.36, 0.28) if lit else Color(0.16, 0.14, 0.16, 0.6)
						draw_rect(Rect2(Vector2(x, y), Vector2(46.0, 62.0) * k), tint)
			"rain":
				# 雨：斜线落下来，快而轻。
				for i in 26:
					var x := fposmod(float(i) * 173.0 + age * 90.0, 900.0) - 450.0
					var y := fposmod(float(i) * 97.0 + age * 520.0, 360.0) - 120.0
					draw_line(c + Vector2(x, y) * k, c + Vector2(x - 9.0, y + 26.0) * k,
							Color(0.7, 0.75, 0.8, 0.22), maxf(1.0, k))
			"workshop":
				# 工坊：一只慢慢转的齿轮。
				var r: float = 96.0 * k
				draw_arc(c, r, 0.0, TAU, 40, Color(rust.r, rust.g, rust.b, 0.5),
						maxf(1.0, 2.0 * k))
				for i in 8:
					var a: float = age * 0.28 + TAU * float(i) / 8.0
					draw_line(c + Vector2(cos(a), sin(a)) * r,
							c + Vector2(cos(a), sin(a)) * (r + 18.0 * k),
							Color(rust.r, rust.g, rust.b, 0.45), maxf(1.0, 3.0 * k))
			"bell":
				# 钟：一口吊着的钟形，摆得很轻。
				var swing: float = sin(age * 0.7) * 6.0 * k
				var top := c + Vector2(swing, -130.0 * k)
				draw_line(top + Vector2(0, -50.0 * k), top, Color(pale.r, pale.g, pale.b, 0.4),
						maxf(1.0, 2.0 * k))
				draw_arc(top + Vector2(0, 90.0 * k), 92.0 * k, PI, TAU, 24,
						Color(pale.r, pale.g, pale.b, 0.36), maxf(1.0, 2.0 * k))
				draw_line(top + Vector2(-92.0, 90.0) * k, top + Vector2(-64.0, 150.0) * k,
						Color(pale.r, pale.g, pale.b, 0.3), maxf(1.0, 2.0 * k))
				draw_line(top + Vector2(92.0, 90.0) * k, top + Vector2(64.0, 150.0) * k,
						Color(pale.r, pale.g, pale.b, 0.3), maxf(1.0, 2.0 * k))
			"foundry":
				# 铸钟厅：炉门拱洞，里的火一呼一吸。
				draw_rect(Rect2(c + Vector2(-180.0, -80.0) * k, Vector2(360.0, 220.0) * k),
						Color(0.06, 0.03, 0.03, 0.6))
				var breath: float = 0.35 + 0.2 * sin(age * 1.6)
				draw_rect(Rect2(c + Vector2(-110.0, -20.0) * k, Vector2(220.0, 150.0) * k),
						Color(1.0, 0.45, 0.18, breath))
				draw_arc(c + Vector2(0, 130.0) * k, 150.0 * k, PI, TAU, 24,
						Color(rust.r, rust.g, rust.b, 0.45), maxf(1.0, 3.0 * k))
			"slag":
				# 渣：底下亮，气泡往上冒。
				draw_rect(Rect2(c + Vector2(-420.0, 120.0) * k, Vector2(840.0, 60.0) * k),
						Color(0.9, 0.42, 0.16, 0.3))
				for i in 14:
					var lift := fposmod(age * (10.0 + float(i % 5) * 5.0) + float(i) * 43.0, 220.0)
					var x := c.x + fposmod(float(i) * 79.0, 820.0) - 410.0
					draw_circle(Vector2(x, c.y + 120.0 - lift), maxf(1.0, 2.0 * k),
							Color(1.0, 0.62, 0.28, 0.35 * (1.0 - lift / 220.0)))
			"rampart":
				# 城墙：一排垛口剪影，风里有灰。
				var base := c.y + 150.0 * k
				for i in 9:
					var x: float = c.x - 420.0 + float(i) * 100.0
					draw_rect(Rect2(Vector2(x, base - 90.0 * k), Vector2(56.0, 90.0) * k),
							Color(0.12, 0.1, 0.12, 0.7))
				draw_rect(Rect2(Vector2(c.x - 420.0, base), Vector2(840.0, 60.0) * k),
						Color(0.12, 0.1, 0.12, 0.7))
				for i in 18:
					var x := fposmod(float(i) * 113.0 + age * 60.0, 900.0) - 450.0
					var y := fposmod(float(i) * 71.0 + age * 40.0, 260.0) - 130.0
					draw_rect(Rect2(c + Vector2(x, y) * k, Vector2(2.0, 2.0) * k),
							Color(0.8, 0.8, 0.84, 0.25))
			"wind":
				# 炉风：横向的灰流，越靠上越快。
				for i in 20:
					var y: float = c.y - 170.0 + float(i) * 18.0
					var speed := 160.0 + float(i % 5) * 60.0
					var x := fposmod(float(i) * 157.0 + age * speed, 940.0) - 470.0
					draw_line(Vector2(c.x + x, y), Vector2(c.x + x + 120.0 * k, y),
							Color(0.78, 0.78, 0.82, 0.16), maxf(1.0, k))
			"heart":
				# 炉心：一枚慢慢跳的芯，外圈的热浪一圈圈推开。
				var beat: float = 0.5 + 0.5 * sin(age * 2.0)
				var r: float = 34.0 * k + beat * 8.0 * k
				draw_circle(c, r, Color(1.0, 0.52, 0.22, 0.5))
				draw_circle(c, r * 0.55, Color(1.0, 0.82, 0.55, 0.8))
				for ring in 3:
					var rad: float = fposmod(age * 40.0 + float(ring) * 60.0, 180.0)
					draw_arc(c, (40.0 + rad) * k, 0.0, TAU, 40,
							Color(1.0, 0.5, 0.22, 0.18 * (1.0 - rad / 180.0)), maxf(1.0, 2.0 * k))
			_:
				pass
