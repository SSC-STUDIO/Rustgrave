extends TestCase
## 间幕遮罩生命周期：Director.abort() 只发 finished，不发 script_finished。
## 渲染夹具/死亡/切场都走 abort——遮罩必须一起收掉，否则整屏被 scrim 压暗
## （M2a 渲染证据就是被这个 bug 压到 ~18% 亮度）。这里锁定：
##   1) 到达间幕开演 -> 遮罩可见；
##   2) abort() 后 -> is_playing=false、遮罩隐藏、Director 不再 playing；
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


func test_abort_during_arrival_interlude_hides_the_scrim() -> void:
	var transition := await _make_transition()
	# level03 的入边 02b->03 有门布景；确保它还没看过。
	ok(not SaveData.has_flag(StoryFlow.interlude_flag("level02b")), "fixture: interlude not seen")
	GameEvents.chapter_started.emit("level03")
	await flush(6)
	ok(transition.is_playing(), "arrival interlude started")
	ok(transition.staging() != "", "staging motif is set (%s)" % transition.staging())
	var overlay := transition.get_node_or_null("InterludeLayer") as CanvasLayer
	ok(overlay != null and overlay.visible, "interlude layer covers the screen while playing")
	Director.abort()
	await flush(3)
	ok(not transition.is_playing(), "abort stops the interlude")
	ok(overlay == null or not overlay.visible, "abort hides the scrim (no stuck dark screen)")
	ok(not Director.playing, "director queue is clear")


func test_seen_edge_does_not_play_again() -> void:
	var transition := await _make_transition()
	SaveData.mark_flag(StoryFlow.interlude_flag("level02"))  # 02->02b
	GameEvents.chapter_started.emit("level02b")
	await flush(6)
	ok(not transition.is_playing(), "a watched interlude never replays")
	var overlay := transition.get_node_or_null("InterludeLayer") as CanvasLayer
	ok(overlay == null or not overlay.visible, "no scrim remains when nothing plays")
