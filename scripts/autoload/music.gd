extends Node
## Music director autoload. Owns the `Music` bus: which bed plays for the current
## place (theme), how tense it is (state), and one-shot stingers.
## Do not give this script a class_name — the autoload name is the API.
##
## CONTRACT (other scripts call only these; this script implements them):
##   Music.set_theme(&"graveyard")   place identity: title, graveyard, undercroft, town,
##                                   cathedral, workshop, bell_tower, slag, ramparts, core
##   Music.set_state(&"danger")      calm | danger | boss | ending | silent
##   Music.stinger(&"boss_intro")    chapter, boss_intro, boss_down, ability, death, rest,
##                                   ending_give, ending_keep, ending_snuff
##   Music.duck(-9.0, 0.6)           temporary dip (dialogue, pause) in dB, held for `seconds`
##   Music.theme_for_level("level03") static: chapter id -> theme (all ten ids)
## Every method is safe to call at any time, including headless and before assets exist.
##
## Automatic behaviour (no caller needed): GameEvents.chapter_started switches theme (+ chapter
## stinger once per chapter); danger follows aggroed enemies near the player (4 Hz poll with
## hysteresis); boss_appeared -> boss track, boss_phase_changed >= 2 adds the hi layer,
## boss_defeated / player_died -> calm; ability / core / ending / parry cues; tree pause
## low-passes and ducks the Music bus. A level scene (re)loading clears danger / boss so a
## scene swap can never leave them stuck. TitleScreen should call set_theme(&"title") and
## set_state(&"calm") in _ready (a poll also notices the title scene as a fallback).
##
## Tracks are layered loops (assets/audio/music/<track>_<role>.ogg, tools/gen_audio_music.py):
##   theme  : bed + keys (different length, so the pair never repeats as a whole) + pulse (danger)
##   boss_* : bed + hi (second phase)          ending : bed + keys
## Up to three decks (a deck = one track's layer players) crossfade equal-power; asking for a
## track that is already fading out revives that deck, so a track is never doubled or restarted.

signal theme_changed(theme_id: StringName)
signal state_changed(state_id: StringName)

const THEMES: Array[StringName] = [
	&"title", &"graveyard", &"undercroft", &"town", &"cathedral",
	&"workshop", &"bell_tower", &"slag", &"ramparts", &"core",
]
const STATES: Array[StringName] = [&"calm", &"danger", &"boss", &"ending", &"silent"]
const LEVEL_THEMES := {
	"level01": &"graveyard", "level02": &"undercroft", "level03": &"town", "level04": &"cathedral",
	"level05": &"workshop", "level06": &"graveyard", "level07": &"bell_tower", "level08": &"slag",
	"level09": &"ramparts", "level10": &"core",
}
## Boss track per theme (a boss in a theme without an entry uses the executioner loop).
const BOSS_TRACKS := {&"graveyard": &"boss_executioner", &"core": &"boss_nightmare"}
const DEFAULT_BOSS_TRACK: StringName = &"boss_executioner"
const ENDING_TRACK: StringName = &"ending"
const MUSIC_DIR := "res://assets/audio/music/"
const STINGERS := {
	&"chapter": "res://assets/audio/music/stinger_chapter.ogg",
	&"boss_intro": "res://assets/audio/music/stinger_boss_intro.ogg",
	&"boss_down": "res://assets/audio/music/stinger_boss_down.ogg",
	&"ability": "res://assets/audio/music/stinger_ability.ogg",
	&"death": "res://assets/audio/music/stinger_death.ogg",
	&"rest": "res://assets/audio/music/stinger_rest.ogg",
	&"ending_give": "res://assets/audio/music/stinger_ending_give.ogg",
	&"ending_keep": "res://assets/audio/music/stinger_ending_keep.ogg",
	&"ending_snuff": "res://assets/audio/music/stinger_ending_snuff.ogg",
}
## Stinger -> [priority, duck dB, duck seconds]. A lower-priority cue never cuts a higher one.
const STINGER_RULES := {
	&"chapter": [2, -5.0, 4.5], &"boss_intro": [3, -8.0, 4.5], &"boss_down": [4, -9.0, 5.5],
	&"ability": [2, -5.0, 2.5], &"death": [4, -12.0, 4.5], &"rest": [1, -4.0, 3.5],
	&"ending_give": [5, -12.0, 11.0], &"ending_keep": [5, -12.0, 11.0], &"ending_snuff": [5, -12.0, 11.0],
}

const KIND_THEME := 0
const KIND_BOSS := 1
const KIND_ENDING := 2
const SLOTS := 3
const DECKS := 3
const ROLES := {
	KIND_THEME: [&"bed", &"keys", &"pulse"],
	KIND_BOSS: [&"bed", &"hi", &""],
	KIND_ENDING: [&"bed", &"keys", &""],
}
## Layer gain per slot (bed, keys / hi, pulse) for theme tracks.
const CALM_MIX: Array[float] = [1.0, 1.0, 0.0]
const DANGER_MIX: Array[float] = [0.8, 0.35, 1.0]

## Crossfade lengths in seconds (the spec floor for theme changes is 1.5).
const THEME_FADE := 2.2
const BOSS_FADE_IN := 1.6
const BOSS_FADE_OUT := 2.6
const SILENT_FADE := 1.8
const MIN_THEME_FADE := 1.5
const PULSE_FADE_IN := 0.9
const PULSE_FADE_OUT := 3.0
const LAYER_FADE := 1.6

## Danger detection.
const POLL_INTERVAL := 0.25
const DANGER_HOLD := 4.0
const ENGAGE_DEFAULT := 200.0
const ENGAGE_MIN := 90.0
const ENGAGE_MAX := 280.0
const ENGAGE_VERTICAL := 160.0
const EXIT_SCALE := 1.35

## Pause: low-pass + dip on the Music bus.
const PAUSE_CUTOFF_HZ := 1100.0
const OPEN_CUTOFF_HZ := 20500.0
const PAUSE_DUCK_DB := -7.0
const PAUSE_FADE := 0.35
const DUCK_ATTACK_DB_PER_S := 90.0
const DUCK_RELEASE_DB_PER_S := 8.0
const DUCK_SLOTS := 4
const STINGER_VOICES := 3
const STINGER_MIN_GAP := 1.0
## Danger stays off this long after a death (the reload clears it sooner).
const DEAD_LATCH := 6.0
const TITLE_SCENE := "res://scenes/ui/TitleScreen.tscn"

var theme_id: StringName = &""
var state_id: StringName = &"calm"
## Test / debug visibility.
var last_stinger: StringName = &""
var front_track: StringName = &""

var _boss_phase := 1
var _danger_hold := 0.0
var _poll_t := 0.0
var _dead_until := 0.0
var _last_chapter := ""
var _world_level := ""
var _world_id := 0
var _scene_seen := 0
var _headless := false
var _decks: Array[Deck] = []
var _sting_players: Array[AudioStreamPlayer] = []
var _stinger_last: Dictionary = {}
var _stinger_until := 0.0
var _stinger_prio := 0
var _streams: Dictionary = {}
var _path_level: Dictionary = {}
var _duck_db := PackedFloat32Array()
var _duck_until := PackedFloat64Array()
var _duck_cur := 0.0
var _duck_lin := 1.0
var _pause_amount := 0.0
var _lp_enabled := false
var _lp: AudioEffectLowPassFilter = null
var _music_bus := -1
var _player: Node2D = null


class Deck extends RefCounted:
	var track: StringName = &""
	var kind := 0
	var gain := 0.0
	var target := 0.0
	var rate := 0.5
	var players: Array[AudioStreamPlayer] = []
	var layer: Array[float] = [0.0, 0.0, 0.0]
	var last_db: Array[float] = [-99.0, -99.0, -99.0]


func _init() -> void:
	_duck_db.resize(DUCK_SLOTS)
	_duck_until.resize(DUCK_SLOTS)
	for i in DUCK_SLOTS:
		_duck_db[i] = 0.0
		_duck_until[i] = -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_headless = DisplayServer.get_name() == "headless"
	for id in GameContext.LEVELS:
		_path_level[GameContext.LEVELS[id]] = id
	GameEvents.chapter_started.connect(_on_chapter_started)
	GameEvents.boss_intro_started.connect(_on_boss_intro)
	GameEvents.boss_appeared.connect(_on_boss_appeared)
	GameEvents.boss_phase_changed.connect(_on_boss_phase)
	GameEvents.boss_defeated.connect(_on_boss_defeated)
	GameEvents.player_died.connect(_on_player_died)
	GameEvents.player_respawned.connect(_on_player_respawned)
	GameEvents.ability_unlocked.connect(_on_ability)
	GameEvents.core_acquired.connect(_on_core)
	GameEvents.ending_chosen.connect(_on_ending_chosen)
	GameEvents.parried.connect(_on_parried)
	# Deck bookkeeping always exists (tests drive the crossfade logic headless);
	# the players only when there is an audio device.
	for d in DECKS:
		_decks.append(Deck.new())
	if _headless:
		set_process(false)
		return
	_music_bus = AudioServer.get_bus_index(&"Music")
	if _music_bus >= 0 and AudioServer.get_bus_effect_count(_music_bus) > 0:
		_lp = AudioServer.get_bus_effect(_music_bus, 0) as AudioEffectLowPassFilter
	var bus := _bus_or_master()
	for deck in _decks:
		for s in SLOTS:
			var p := AudioStreamPlayer.new()
			p.bus = bus
			p.volume_db = -80.0
			add_child(p)
			deck.players.append(p)
	for i in STINGER_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = bus
		add_child(p)
		_sting_players.append(p)


func _exit_tree() -> void:
	for deck in _decks:
		for p in deck.players:
			p.stop()
	for p in _sting_players:
		p.stop()


# --- contract ---------------------------------------------------------------

func set_theme(id: StringName) -> void:
	if id == theme_id:
		return
	theme_id = id
	if id == &"title":
		_last_chapter = ""
	Sfx.set_theme_bed(id)
	_apply()
	theme_changed.emit(id)


func set_state(id: StringName) -> void:
	if id == state_id:
		return
	state_id = id
	if id != &"danger":
		_danger_hold = 0.0
	if id != &"boss":
		_boss_phase = 1
	_apply()
	state_changed.emit(id)


func stinger(id: StringName) -> void:
	if not STINGERS.has(id):
		return
	var now := _now()
	if now - float(_stinger_last.get(id, -100.0)) < STINGER_MIN_GAP:
		return
	var rule: Array = STINGER_RULES[id]
	if now < _stinger_until and int(rule[0]) < _stinger_prio:
		return
	var stream := _stream_for(String(STINGERS[id]), false)
	_stinger_last[id] = now
	last_stinger = id
	if stream != null:
		_stinger_until = now + stream.get_length()
		_stinger_prio = int(rule[0])
	duck(float(rule[1]), float(rule[2]))
	if _headless or stream == null:
		return
	var voice: AudioStreamPlayer = _sting_players[0]
	for p in _sting_players:
		if not p.playing:
			voice = p
			break
	voice.stream = stream
	voice.volume_db = 0.0
	voice.play()


## Dip the music by `amount_db` (<= 0) for `seconds`, then recover. Overlapping ducks do not
## add up: the deepest active one wins. Pause ducks on its own (see PAUSE_DUCK_DB).
func duck(amount_db: float, seconds: float) -> void:
	var now := _now()
	var amount := minf(amount_db, 0.0)
	var slot := -1
	var shallowest := INF
	for i in DUCK_SLOTS:
		if _duck_until[i] <= now:
			slot = i
			break
		if absf(_duck_db[i]) < shallowest:
			shallowest = absf(_duck_db[i])
			slot = i
	if _duck_until[slot] > now and absf(amount) < shallowest:
		return
	_duck_db[slot] = amount
	_duck_until[slot] = now + maxf(seconds, 0.05)


static func theme_for_level(level_id: String) -> StringName:
	return LEVEL_THEMES.get(level_id, &"")


static func boss_track_for(theme: StringName) -> StringName:
	return BOSS_TRACKS.get(theme, DEFAULT_BOSS_TRACK)


static func track_kind(track: StringName) -> int:
	if track == ENDING_TRACK:
		return KIND_ENDING
	if String(track).begins_with("boss_"):
		return KIND_BOSS
	return KIND_THEME


## Track the current (theme, state) asks for; &"" = silence.
func desired_track() -> StringName:
	match state_id:
		&"silent":
			return &""
		&"ending":
			return ENDING_TRACK
		&"boss":
			return boss_track_for(theme_id)
	return theme_id


## Layer gain (0..1) for slot 0 bed / 1 keys|hi / 2 pulse of `track` right now.
func slot_target(track: StringName, slot: int) -> float:
	match track_kind(track):
		KIND_BOSS:
			if slot == 0:
				return 1.0
			return 1.0 if (slot == 1 and _boss_phase >= 2) else 0.0
		KIND_ENDING:
			return 1.0 if slot < 2 else 0.0
	return DANGER_MIX[slot] if state_id == &"danger" else CALM_MIX[slot]


## Drop gameplay-driven states (danger / boss) and the death latch. `full` also clears the
## cinematic states (silent / ending): a freshly loaded world is always normal play.
func reset_transient(full: bool = false) -> void:
	_dead_until = 0.0
	_danger_hold = 0.0
	_boss_phase = 1
	var s := state_id
	if s == &"danger" or s == &"boss" or (full and (s == &"ending" or s == &"silent")):
		set_state(&"calm")


# --- crossfading ------------------------------------------------------------

func _apply() -> void:
	var want := desired_track()
	if want == front_track:
		return
	var prev := front_track
	front_track = want
	var fade := _fade_for(prev, want)
	var found: Deck = null
	for deck in _decks:
		if deck.track == want and want != &"":
			found = deck
		else:
			deck.target = 0.0
			deck.rate = 1.0 / fade
	if want == &"":
		return
	if found == null:
		found = _free_deck()
		_start_deck(found, want)
	found.target = 1.0
	found.rate = 1.0 / fade


func _fade_for(from_track: StringName, to_track: StringName) -> float:
	if to_track == &"":
		return SILENT_FADE
	if track_kind(to_track) == KIND_BOSS:
		return BOSS_FADE_IN
	if from_track != &"" and track_kind(from_track) == KIND_BOSS:
		return BOSS_FADE_OUT
	return maxf(THEME_FADE, MIN_THEME_FADE)


func _free_deck() -> Deck:
	var best: Deck = _decks[0]
	for deck in _decks:
		if deck.track == &"":
			return deck
		if deck.gain < best.gain:
			best = deck
	return best


func _start_deck(deck: Deck, track: StringName) -> void:
	for p in deck.players:
		p.stop()
	deck.track = track
	deck.kind = track_kind(track)
	deck.gain = 0.0
	var roles: Array = ROLES[deck.kind]
	for s in SLOTS:
		deck.last_db[s] = -99.0
		deck.layer[s] = slot_target(track, s)
		if deck.players.is_empty():
			continue
		var p := deck.players[s]
		p.stream = null
		p.volume_db = -80.0
		var role := String(roles[s])
		if role == "":
			continue
		var stream := _stream_for("%s%s_%s.ogg" % [MUSIC_DIR, String(track), role], true)
		p.stream = stream
		if stream != null:
			p.play(0.0)


func _stream_for(path: String, loops: bool) -> AudioStream:
	if _streams.has(path):
		return _streams[path]
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	if stream is AudioStreamOggVorbis:
		stream.loop = loops
	_streams[path] = stream
	return stream


func _process(delta: float) -> void:
	var tree := get_tree()
	var paused := tree != null and tree.paused
	_pause_amount = move_toward(_pause_amount, 1.0 if paused else 0.0, delta / PAUSE_FADE)
	_update_pause_filter()
	_update_duck(delta)
	_update_decks(delta)
	_poll_t += delta
	if _poll_t >= POLL_INTERVAL:
		_poll_t -= POLL_INTERVAL
		_poll_world()
		if not paused:
			_poll_danger()


func _update_pause_filter() -> void:
	if _lp == null or _music_bus < 0:
		return
	if _pause_amount > 0.001:
		if not _lp_enabled:
			_lp_enabled = true
			AudioServer.set_bus_effect_enabled(_music_bus, 0, true)
		_lp.cutoff_hz = OPEN_CUTOFF_HZ * pow(PAUSE_CUTOFF_HZ / OPEN_CUTOFF_HZ, _pause_amount)
	elif _lp_enabled:
		_lp_enabled = false
		_lp.cutoff_hz = OPEN_CUTOFF_HZ
		AudioServer.set_bus_effect_enabled(_music_bus, 0, false)


func _duck_target() -> float:
	var now := _now()
	var t := PAUSE_DUCK_DB * _pause_amount
	for i in DUCK_SLOTS:
		if _duck_until[i] > now:
			t = minf(t, _duck_db[i])
	return t


func _update_duck(delta: float) -> void:
	var t := _duck_target()
	var rate := DUCK_ATTACK_DB_PER_S if t < _duck_cur else DUCK_RELEASE_DB_PER_S
	_duck_cur = move_toward(_duck_cur, t, rate * delta)
	_duck_lin = db_to_linear(_duck_cur)


func _update_decks(delta: float) -> void:
	for deck in _decks:
		if deck.track == &"":
			continue
		deck.gain = move_toward(deck.gain, deck.target, delta * deck.rate)
		if deck.target <= 0.0 and deck.gain <= 0.0005:
			for p in deck.players:
				p.stop()
			deck.track = &""
			deck.gain = 0.0
			continue
		var xf := sin(deck.gain * PI * 0.5)
		for s in SLOTS:
			var tgt := slot_target(deck.track, s)
			var cur: float = deck.layer[s]
			var seconds := LAYER_FADE
			if s == 2 and deck.kind == KIND_THEME:
				seconds = PULSE_FADE_IN if tgt > cur else PULSE_FADE_OUT
			cur = move_toward(cur, tgt, delta / seconds)
			deck.layer[s] = cur
			if deck.players.is_empty() or deck.players[s].stream == null:
				continue
			var lin := xf * cur * _duck_lin
			var db := -80.0 if lin <= 0.0003 else linear_to_db(lin)
			if absf(db - float(deck.last_db[s])) > 0.05:
				deck.players[s].volume_db = db
				deck.last_db[s] = db


# --- danger / world detection -----------------------------------------------

## Hysteresis: one engaged enemy flips calm -> danger at once; danger -> calm needs
## DANGER_HOLD seconds without any. Only calm / danger are managed here.
func _danger_update(engaged: int, dt: float) -> void:
	if state_id == &"calm":
		if engaged > 0:
			_danger_hold = DANGER_HOLD
			set_state(&"danger")
	elif state_id == &"danger":
		if engaged > 0:
			_danger_hold = DANGER_HOLD
		else:
			_danger_hold -= dt
			if _danger_hold <= 0.0:
				set_state(&"calm")


func _poll_danger() -> void:
	if _now() < _dead_until or (state_id != &"calm" and state_id != &"danger"):
		return
	if Director.is_input_locked():
		return
	var scale := EXIT_SCALE if state_id == &"danger" else 1.0
	_danger_update(_count_engaged(scale), POLL_INTERVAL)


func _count_engaged(scale: float) -> int:
	var player := _player_node()
	if player == null:
		return 0
	var ppos := player.global_position
	var n := 0
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node2D
		if enemy == null or not enemy.is_inside_tree():
			continue
		if enemy.has_method("is_aggroed"):
			if enemy.call("is_aggroed"):
				n += 1
			continue
		if bool(enemy.get("_dead")):
			continue
		var d := enemy.global_position - ppos
		if absf(d.y) <= ENGAGE_VERTICAL and absf(d.x) <= engage_range(enemy) * scale:
			n += 1
	return n


## How close the knight must be before this enemy counts as engaged (its own aggro / wake range,
## clamped; enemies that expose neither use ENGAGE_DEFAULT).
static func engage_range(enemy: Object) -> float:
	var r = enemy.get("aggro_range")
	if r == null:
		r = enemy.get("wake_range")
	if r == null:
		return ENGAGE_DEFAULT
	return clampf(float(r), ENGAGE_MIN, ENGAGE_MAX)


func _player_node() -> Node2D:
	if _player != null and is_instance_valid(_player) and _player.is_inside_tree():
		return _player
	_player = get_tree().get_first_node_in_group("player") as Node2D
	return _player


## Notices a level scene (re)loading or the title scene appearing even when nobody emits
## chapter_started (Level02 does not): sets the theme and clears danger / boss.
func _poll_world() -> void:
	var tree := get_tree()
	var world := tree.get_first_node_in_group("game_world")
	if world != null:
		var wid := world.get_instance_id()
		if wid != _world_id:
			_world_id = wid
			_on_world_loaded(world)
		return
	_world_id = 0
	var scene := tree.current_scene
	if scene != null and scene.get_instance_id() != _scene_seen:
		_scene_seen = scene.get_instance_id()
		if scene.scene_file_path == TITLE_SCENE:
			enter_title()


func _on_world_loaded(world: Node) -> void:
	reset_transient(true)
	_world_level = String(_path_level.get(world.scene_file_path, ""))
	var theme := theme_for_level(_world_level)
	if theme != &"":
		set_theme(theme)


## Title screen: its own theme, a clean slate (no boss / danger / death latch / ending).
func enter_title() -> void:
	reset_transient(true)
	set_theme(&"title")


# --- GameEvents -------------------------------------------------------------

func _on_chapter_started(level_id: String) -> void:
	var theme := theme_for_level(level_id)
	if theme == &"":
		return
	_world_level = level_id
	reset_transient(true)
	var fresh := _last_chapter != level_id
	set_theme(theme)
	_last_chapter = level_id
	if fresh:
		stinger(&"chapter")


func _on_boss_intro(_boss_name: String) -> void:
	stinger(&"boss_intro")


func _on_boss_appeared(_boss_name: String, _hp: int, _max_hp: int) -> void:
	_boss_phase = 1
	set_state(&"boss")


func _on_boss_phase(_boss_name: String, phase: int) -> void:
	_boss_phase = phase


func _on_boss_defeated() -> void:
	if state_id == &"boss":
		set_state(&"calm")
	stinger(&"boss_down")


func _on_player_died() -> void:
	_dead_until = _now() + DEAD_LATCH
	_danger_hold = 0.0
	if state_id == &"boss" or state_id == &"danger":
		set_state(&"calm")
	stinger(&"death")


## The respawn reloads the level (a fresh chapter_started clears the latch); until then a
## short grace keeps enemies near the corpse from restarting the danger layer.
func _on_player_respawned() -> void:
	_dead_until = _now() + 1.5
	_danger_hold = 0.0
	if state_id == &"boss" or state_id == &"danger":
		set_state(&"calm")


func _on_ability(_ability_id: StringName) -> void:
	stinger(&"ability")


func _on_core(_core: Resource) -> void:
	stinger(&"ability")


## give / keep close the story warmly (ending track + stinger); snuff goes cold (silence +
## stinger). The forge heart's &"rekindle" is a choice, not an ending: ignored here.
func _on_ending_chosen(kind: StringName) -> void:
	match kind:
		&"give", &"keep":
			set_state(&"ending")
			stinger(StringName("ending_" + String(kind)))
		&"snuff":
			set_state(&"silent")
			stinger(&"ending_snuff")


func _on_parried(_projectile: Node, _by: Node) -> void:
	duck(-7.0, 0.14)


# --- helpers ----------------------------------------------------------------

func _now() -> float:
	return float(Time.get_ticks_usec()) / 1000000.0


func _bus_or_master() -> StringName:
	return &"Music" if AudioServer.get_bus_index(&"Music") >= 0 else &"Master"


## Test / debug view of the decks (allocates; never call per frame).
func snapshot() -> Dictionary:
	var decks := []
	for deck in _decks:
		decks.append({"track": deck.track, "gain": deck.gain, "target": deck.target,
				"layers": deck.layer.duplicate()})
	return {"theme": theme_id, "state": state_id, "front": front_track, "decks": decks,
			"duck_db": _duck_cur, "boss_phase": _boss_phase}
