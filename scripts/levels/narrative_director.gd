class_name NarrativeDirector
extends Node
## 实时动态旁白调度器（挂载于 Director 常驻层，取代旧版锁屏 ChapterTransition）。
##
## 监听房间进入、多波次激战、叛逆越界与真名残片拾取信号，驱动 LiveVoiceBar 实时播放与打断。
## 严格保证：任何旁白触发时 Director.is_input_locked() 恒保持原状（false），绝不抢夺玩家控制权。

const TrialRunScript := preload("res://scripts/autoload/trial_run.gd")

var voice_bar: LiveVoiceBar
var test_enabled: bool = false

static var _session_seen: Dictionary = {}


static func forget_session() -> void:
	_session_seen.clear()


func _ready() -> void:
	name = "NarrativeDirector"
	process_mode = Node.PROCESS_MODE_ALWAYS
	voice_bar = LiveVoiceBar.new()
	add_child(voice_bar)

	GameEvents.voice_triggered.connect(_on_voice_triggered)
	GameEvents.room_entered.connect(_on_room_entered)
	GameEvents.truth_fragment_acquired.connect(_on_truth_fragment_acquired)
	GameEvents.player_died.connect(_on_player_died)


func is_live() -> bool:
	if TrialRunScript.suppresses_cinematics() or ArenaRun.active():
		return false
	return test_enabled or not Director.is_test_runner()


## 触发一条语音（once_per_session = true 时本局同一房间重进不重复唠叨，但叛逆打断词可设 false）。
func say(clip_id: String, force_interrupt: bool = false, once_per_session: bool = true) -> bool:
	if clip_id == "" or not is_live():
		return false
	if once_per_session:
		var flag_key := "vo_" + clip_id
		if _session_seen.has(flag_key):
			return false
		_session_seen[flag_key] = true
	return voice_bar.play_clip(clip_id, force_interrupt)


func clear_voice() -> void:
	if voice_bar != null:
		voice_bar.clear()


func _on_voice_triggered(clip_id: String, force_interrupt: bool) -> void:
	# 叛逆与强制打断信号允许重复压断引导词；常规引导词同局只念一次。
	say(clip_id, force_interrupt, not force_interrupt)


func _on_room_entered(stage_id: String, room_id: String) -> void:
	if not is_live():
		return
	# 集齐 5 枚残片后进入表面终章炉门前时，真伊尔主动提醒可去归零母模。
	if stage_id == "stage07" and room_id == "S1" and NarrativeCatalog.all_fragments_collected(SaveData.flags):
		say("s7_r1_enter_truth_ready", true, true)


func _on_truth_fragment_acquired(fragment_id: String) -> void:
	if not is_live():
		return
	var spec := NarrativeCatalog.fragment_spec(fragment_id)
	var clip_id := String(spec.get("voice_clip", ""))
	if clip_id != "":
		say(clip_id, true, false)
	if NarrativeCatalog.all_fragments_collected(SaveData.flags):
		# 排在第五枚残片原声之后紧接着播觉醒提示。
		voice_bar.play_clip("all_fragments_awake", false)


func _on_player_died() -> void:
	clear_voice()
