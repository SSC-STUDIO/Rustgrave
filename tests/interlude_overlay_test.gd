extends TestCase
## 间幕遮罩生命周期：Director.abort() 只发 finished，不发 script_finished。
## 渲染夹具/死亡/切场都走 abort——遮罩必须一起收掉，否则整屏被 scrim 压暗
## （M2a 渲染证据就是被这个 bug 压到 ~18% 亮度）。这里锁定：
##   1) 到达间幕开演 -> 播的是这条边界的分镜（不叠几何布景）；
##   2) abort() 后 -> is_playing=false、分镜层与兜底遮罩都隐藏、Director 不再 playing；
##   3) 已看过的边界不再开演。

func setup() -> void:
	SaveData.delete_save()
	SaveData.flags.clear()
	Director.abort()


func teardown() -> void:
	SaveData.delete_save()
	SaveData.flags.clear()
	Director.abort()


func _make_transition() -> ChapterTransition:
	var transition := ChapterTransition.new()
	transition.test_enabled = true
	add_child(transition)
	await flush(1)
	return transition


func test_abort_during_arrival_interlude_clears_the_storyboard() -> void:
	var transition := await _make_transition()
	# level03 的入边 02b->03 有一段分镜；确保它还没看过。
	ok(not SaveData.has_flag(StoryFlow.interlude_flag("level02b")), "fixture: interlude not seen")
	GameEvents.chapter_started.emit("level03")
	await flush(6)
	ok(transition.is_playing(), "arrival interlude started")
	eq(transition.board_id(), "interlude_level02b", "the boundary's storyboard is the one playing")
	eq(transition.staging(), "", "a storyboard needs no geometric scrim on top")
	Director.abort()
	await flush(3)
	ok(not transition.is_playing(), "abort stops the interlude")
	ok(not Director.board_active(), "abort stops the storyboard player")
	ok(not Director.board().visible, "abort hides the storyboard layer (no stuck dark screen)")
	ok(not Director.playing, "director queue is clear")


## 第二章自己的场景脚本以前不发 chapter_started，01→02 的章间永远不播；现在发了。
func test_the_first_boundary_plays_when_level02_announces_itself() -> void:
	var transition := await _make_transition()
	ok(not SaveData.has_flag(StoryFlow.interlude_flag("level01")), "fixture: interlude not seen")
	GameEvents.chapter_started.emit("level02")
	await flush(6)
	ok(transition.is_playing(), "the level01→level02 interlude started")
	eq(transition.board_id(), "interlude_level01", "it is the first boundary's storyboard")
	Director.abort()
	await flush(3)
	ok(not transition.is_playing(), "abort stops it")
	ok(not Director.board_active(), "and the storyboard player with it")


## 兜底几何遮罩（没有分镜的边界才用）也要在 abort / 复位时一起收掉。
func test_fallback_scrim_hides_on_abort() -> void:
	var transition := await _make_transition()
	transition._show_staging("door")
	var overlay := transition.get_node_or_null("InterludeLayer") as CanvasLayer
	ok(overlay != null and overlay.visible, "fallback layer covers the screen while shown")
	transition.reset_view()
	ok(not overlay.visible, "reset hides the fallback scrim")


func test_seen_edge_does_not_play_again() -> void:
	var transition := await _make_transition()
	SaveData.mark_flag(StoryFlow.interlude_flag("level02"))  # 02->02b
	GameEvents.chapter_started.emit("level02b")
	await flush(6)
	ok(not transition.is_playing(), "a watched interlude never replays")
	var overlay := transition.get_node_or_null("InterludeLayer") as CanvasLayer
	ok(overlay == null or not overlay.visible, "no scrim remains when nothing plays")
	ok(not Director.board_active(), "no storyboard plays for a watched interlude")
