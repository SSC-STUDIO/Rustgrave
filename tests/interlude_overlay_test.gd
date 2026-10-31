extends TestCase
## ChapterTransition 遮罩安全契约（v4 无黑屏幕间版）：
##   1) 任意章节/节点发出 chapter_started 时，不拉起黑屏间幕、不锁输入；
##   2) 兜底几何遮罩在 reset_view / player_died / abort 时彻底隐藏，绝不残留压暗屏幕的 scrim。

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


func test_chapter_started_never_opens_blocking_interlude() -> void:
	var transition := await _make_transition()
	for id in ["stage01", "stage02", "branch01", "stage08_true"]:
		GameEvents.chapter_started.emit(id)
		await flush(3)
		ok(not transition.is_playing(), "%s arrival never starts a black-screen interlude" % id)
		var overlay := transition.get_node_or_null("InterludeLayer") as CanvasLayer
		ok(overlay == null or not overlay.visible, "%s leaves no dark scrim" % id)
		ok(not Director.board_active(), "%s starts no interlude storyboard" % id)


func test_fallback_scrim_hides_on_reset_and_death() -> void:
	var transition := await _make_transition()
	transition._show_staging("door")
	var overlay := transition.get_node_or_null("InterludeLayer") as CanvasLayer
	ok(overlay != null and overlay.visible, "fallback layer covers screen when explicitly staged")
	transition.reset_view()
	ok(not overlay.visible, "reset_view hides fallback scrim")
	transition._show_staging("heart")
	ok(overlay.visible)
	transition._on_player_died()
	ok(not overlay.visible, "player death hides fallback scrim")
