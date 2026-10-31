extends TestCase
## 叙事目录与非阻塞实时语音契约测试：
##   1. 14 节点拓扑与 GameContext.LEVEL_ORDER 严格对齐，5 枚真名残片完整；
##   2. 全部实时语音长度控制在短句预算内，零现代出戏词，零黑屏幕间步骤；
##   3. LiveVoiceBar 支持叛逆高优先级实时打断，且全程绝不锁死玩家输入。

const FORBIDDEN_META_WORDS := [
	"程序员", "键盘", "鼠标", "手柄", "客户端", "游戏开发", "帧率", "服务器", "策划",
]


func setup() -> void:
	SaveData.save_path = "user://rustgrave_test_save.cfg"
	SaveData.delete_save()
	StageRoomMemory.clear_all()
	NarrativeDirector.forget_session()
	if Director.live_voice() != null:
		Director.live_voice().clear()


func teardown() -> void:
	if Director.narrative() != null:
		Director.narrative().test_enabled = false
	if Director.live_voice() != null:
		Director.live_voice().clear()
	NarrativeDirector.forget_session()
	SaveData.delete_save()
	SaveData.save_path = "user://rustgrave_save.cfg"
	StageRoomMemory.clear_all()


func test_stage_nodes_and_fragments_schema() -> void:
	eq(NarrativeCatalog.NODE_ORDER.size(), 14, "NODE_ORDER must have 14 nodes")
	eq(NarrativeCatalog.NODE_ORDER, GameContext.LEVEL_ORDER, "NODE_ORDER must match GameContext.LEVEL_ORDER")
	eq(NarrativeCatalog.MAIN_SPINE.size(), 8, "MAIN_SPINE has 8 main stages")
	eq(NarrativeCatalog.BRANCH_IDS.size(), 5, "BRANCH_IDS has 5 rebellion branches")
	eq(NarrativeCatalog.FRAGMENT_IDS.size(), 5, "FRAGMENT_IDS has 5 truth fragments")

	for node_id in NarrativeCatalog.NODE_ORDER:
		ok(NarrativeCatalog.STAGE_NODES.has(node_id), "STAGE_NODES has %s" % node_id)
		var spec := NarrativeCatalog.node_spec(node_id)
		ok(String(spec.get("name", "")) != "", "%s has non-empty name" % node_id)
		ok(String(spec.get("number", "")) != "", "%s has non-empty number" % node_id)
		var rooms: Array = spec.get("rooms", [])
		ok(not rooms.is_empty(), "%s has rooms" % node_id)
		for p in (spec.get("parents", []) as Array):
			ok(NarrativeCatalog.STAGE_NODES.has(String(p)), "%s parent %s exists" % [node_id, p])
		for ch in (spec.get("children", []) as Array):
			ok(NarrativeCatalog.STAGE_NODES.has(String(ch)), "%s child %s exists" % [node_id, ch])
		eq(StoryFlow.arrival_steps(node_id).size(), 0, "%s must have zero black-screen arrival interludes" % node_id)

	for frag_id in NarrativeCatalog.FRAGMENT_IDS:
		var fspec := NarrativeCatalog.fragment_spec(frag_id)
		ok(not fspec.is_empty(), "fragment %s exists" % frag_id)
		ok(String(fspec.get("title", "")) != "", "fragment %s has title" % frag_id)
		var clip_id := String(fspec.get("voice_clip", ""))
		ok(NarrativeCatalog.VOICE_CLIPS.has(clip_id), "fragment %s voice_clip %s exists" % [frag_id, clip_id])


func test_voice_clips_budget_and_dark_setting_tone() -> void:
	var valid_tones := [
		NarrativeCatalog.TONE_GUIDE,
		NarrativeCatalog.TONE_DOUBT,
		NarrativeCatalog.TONE_GLITCH,
		NarrativeCatalog.TONE_TRUE,
		NarrativeCatalog.TONE_BOSS,
	]
	ok(NarrativeCatalog.VOICE_CLIPS.size() >= 60, "catalog has rich voice coverage")
	for clip_id in NarrativeCatalog.VOICE_CLIPS:
		var spec: Dictionary = NarrativeCatalog.VOICE_CLIPS[clip_id]
		var text := String(spec.get("text", "")).strip_edges()
		var tone: StringName = spec.get("tone", &"")
		ok(text.length() >= 1 and text.length() <= 44,
				"clip %s length (%d) stays concise for live subtitle" % [clip_id, text.length()])
		ok(valid_tones.has(tone), "clip %s has valid tone %s" % [clip_id, tone])
		for bad in FORBIDDEN_META_WORDS:
			ok(not text.contains(bad), "clip %s must not contain fourth-wall modern word '%s'" % [clip_id, bad])


func test_live_voice_bar_interrupts_without_locking_input() -> void:
	var nd := Director.narrative()
	var bar := Director.live_voice()
	ok(nd != null and bar != null, "Director hosts NarrativeDirector and LiveVoiceBar")
	nd.test_enabled = true
	bar.interrupt_count = 0

	var played := nd.say("s1_r1_wake", false, true)
	ok(played, "guide clip starts playing")
	ok(bar.is_speaking(), "voice bar is speaking")
	eq(bar.active_clip_id(), "s1_r1_wake", "active clip is s1_r1_wake")
	eq(bar.active_tone(), NarrativeCatalog.TONE_GUIDE, "tone is guide")
	ok(not Director.is_input_locked(), "guide voice never locks player input")
	ok(GameContext.gameplay_input_enabled(), "gameplay input stays enabled during live voice")

	# 触发叛逆敲墙语音：应立即打断正在播放的引导词，切换为 doubt 声线，且依然零锁输入
	GameEvents.voice_triggered.emit("s1_r1_seal_hit_1", true)
	eq(bar.active_clip_id(), "s1_r1_seal_hit_1", "disobedience clip interrupts guide clip immediately")
	eq(bar.active_tone(), NarrativeCatalog.TONE_DOUBT, "tone switches to doubt")
	ok(bar.interrupt_count >= 1, "interrupt counter incremented")
	ok(not Director.is_input_locked(), "disobedience interrupt never locks player input")
