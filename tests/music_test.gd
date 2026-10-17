extends TestCase
## Music director contract tests (headless safe: no audio device needed).
##
## Music owns the Music bus and a three-deck crossfade: these tests drive the
## public contract (set_theme / set_state / stinger / duck / reset_transient /
## enter_title) plus the deck bookkeeping behind it and assert that
##   * every id the code uses exists and every transition lands on the right track,
##   * a track is never doubled or restarted (deck reuse / fade-out revival),
##   * fades and stinger priority rules are sane,
##   * GameEvents is connected exactly once (no duplicated connect).
## No listening judgement is made here; the numeric layer balance lives in
## tools/gen_audio_verify.py.

const LISTENED_EVENTS := [
	"chapter_started", "boss_intro_started", "boss_appeared", "boss_phase_changed",
	"boss_defeated", "player_died", "player_respawned", "ability_unlocked",
	"core_acquired", "ending_chosen", "parried",
]

var _theme: StringName = &""
var _state: StringName = &""


class EnemyProbe extends Node2D:
	var aggro_range: float = 0.0
	var wake_range: float = 0.0


func setup() -> void:
	_theme = Music.theme_id
	_state = Music.state_id
	# Clear latches left over from other tests: they only matter for stinger
	# priority / danger hysteresis, both tested below with explicit values.
	Music._stinger_until = 0.0
	Music._stinger_prio = 0
	Music._stinger_last.clear()
	Music._dead_until = 0.0
	Music._danger_hold = 0.0
	Music._boss_phase = 1
	Music._last_chapter = ""


func teardown() -> void:
	Music.reset_transient(true)
	Music.set_theme(_theme)
	Music.set_state(_state)


func _c() -> Dictionary:
	return (Music.get_script() as Script).get_script_constant_map()


func _deck_tracks() -> Array:
	var out: Array = []
	for deck in Music.snapshot()["decks"]:
		if String(deck["track"]) != "":
			out.append(StringName(deck["track"]))
	return out


# ---------------------------------------------------------------------------
# Ids and constants
# ---------------------------------------------------------------------------

func test_snapshot_shape_and_known_ids() -> void:
	var c := _c()
	var themes: Array = c["THEMES"]
	var states: Array = c["STATES"]
	ok(themes.size() == 10, "expected ten themes")
	ok(states.size() == 5, "expected five states")
	var seen: Dictionary = {}
	for id in themes:
		ok(not seen.has(id), "duplicate theme id %s" % id)
		seen[id] = true
	seen.clear()
	for id in states:
		ok(not seen.has(id), "duplicate state id %s" % id)
		seen[id] = true
	var snap: Dictionary = Music.snapshot()
	for key in ["theme", "state", "front", "decks", "duck_db", "boss_phase"]:
		ok(snap.has(key), "snapshot() is missing %s" % key)
	ok((snap["decks"] as Array).size() == int(c["DECKS"]),
			"snapshot should expose DECKS decks")
	for deck in snap["decks"]:
		ok((deck["layers"] as Array).size() == int(c["SLOTS"]),
				"每个 deck 应有 SLOTS 层 / every deck should have SLOTS layers")


func test_desired_track_matrix() -> void:
	var c := _c()
	var themes: Array = c["THEMES"]
	var ending: StringName = c["ENDING_TRACK"]
	var default_boss: StringName = c["DEFAULT_BOSS_TRACK"]
	for theme in themes:
		Music.set_theme(theme)
		Music.set_state(&"calm")
		eq(Music.desired_track(), theme, "calm should play the theme track %s" % theme)
		Music.set_state(&"danger")
		eq(Music.desired_track(), theme, "danger should keep the theme track %s" % theme)
		Music.set_state(&"boss")
		eq(Music.desired_track(), Music.boss_track_for(theme), "boss track for %s" % theme)
		Music.set_state(&"ending")
		eq(Music.desired_track(), ending, "ending should play the ending track")
		Music.set_state(&"silent")
		eq(Music.desired_track(), &"", "silent should play nothing")
	Music.set_state(&"calm")
	eq(Music.boss_track_for(&"not_a_theme"), default_boss, "unknown theme -> default boss track")


func test_fade_and_rule_constants_are_sane() -> void:
	var c := _c()
	var fades: Dictionary = c
	ok(float(fades["MIN_THEME_FADE"]) >= 1.5, "theme crossfade floor should be at least 1.5 s")
	ok(float(fades["THEME_FADE"]) >= float(fades["MIN_THEME_FADE"]),
			"THEME_FADE must meet the spec floor")
	ok(float(fades["BOSS_FADE_IN"]) >= 1.0, "boss fade-in too short")
	ok(float(fades["BOSS_FADE_OUT"]) >= float(fades["BOSS_FADE_IN"]),
			"a boss should not fade out faster than it fades in")
	ok(float(fades["SILENT_FADE"]) >= 1.0, "silent fade too short")
	ok(float(fades["PULSE_FADE_IN"]) > 0.2 and float(fades["PULSE_FADE_IN"]) <= 3.0,
			"pulse fade-in out of range")
	ok(float(fades["LAYER_FADE"]) > 0.0 and float(fades["LAYER_FADE"]) <= 4.0,
			"layer fade out of range")
	ok(int(c["SLOTS"]) == 3 and int(c["DECKS"]) >= 2, "three layers x at least two decks")
	ok(float(c["DUCK_ATTACK_DB_PER_S"]) > float(c["DUCK_RELEASE_DB_PER_S"]),
			"duck should attack faster than it releases")
	ok(float(c["POLL_INTERVAL"]) > 0.0 and float(c["POLL_INTERVAL"]) < 1.0, "poll interval out of range")
	ok(int(c["STINGER_VOICES"]) >= 2, "stinger voice pool too small")
	# Every state maps to a defined layer mix; every stinger has a rule row.
	var calm: Array = c["CALM_MIX"]
	var danger: Array = c["DANGER_MIX"]
	eq(calm.size(), 3, "CALM_MIX should define three layer gains")
	eq(danger.size(), 3, "DANGER_MIX should define three layer gains")
	eq(float(calm[2]), 0.0, "the pulse layer must be silent when calm")
	ok(float(danger[2]) > 0.0, "the pulse layer must be audible in danger")
	for id in c["STINGERS"]:
		ok(c["STINGER_RULES"].has(id), "stinger %s has no STINGER_RULES row" % id)


# ---------------------------------------------------------------------------
# Transitions / decks
# ---------------------------------------------------------------------------

func test_state_machine_transitions_apply_correct_track() -> void:
	Music.set_theme(&"graveyard")
	Music.set_state(&"calm")
	eq(Music.front_track, &"graveyard", "calm front track")
	Music.set_state(&"danger")
	eq(Music.front_track, &"graveyard", "danger front track")
	Music.set_state(&"boss")
	eq(Music.front_track, &"boss_executioner", "boss front track for graveyard")
	Music.set_state(&"ending")
	eq(Music.front_track, &"ending", "ending front track")
	Music.set_state(&"silent")
	eq(Music.front_track, &"", "silent front track")
	Music.set_state(&"calm")
	eq(Music.front_track, &"graveyard", "back to calm restores the theme")
	Music.set_theme(&"core")
	Music.set_state(&"boss")
	eq(Music.front_track, &"boss_nightmare", "core has the nightmare boss track")


func test_theme_switch_reuses_decks_and_never_doubles() -> void:
	Music.set_state(&"calm")
	Music.set_theme(&"graveyard")
	Music.set_theme(&"undercroft")
	Music.set_theme(&"graveyard")     # revive the deck that is still fading out
	var tracks := _deck_tracks()
	var graveyards := 0
	for t in tracks:
		if t == &"graveyard":
			graveyards += 1
	ok(graveyards == 1, "theme never doubled: expected 1 graveyard deck, got %d (%s)"
			% [graveyards, str(tracks)])
	ok(tracks.size() <= int(_c()["DECKS"]), "more live decks than DECKS")
	for deck in Music.snapshot()["decks"]:
		if StringName(deck["track"]) == &"graveyard":
			eq(float(deck["target"]), 1.0, "revived deck should fade back to full")
		elif StringName(deck["track"]) != &"":
			eq(float(deck["target"]), 0.0, "non-front deck should fade out")


func test_state_and_theme_signals_fire_once() -> void:
	var hits := {"theme": 0, "state": 0}
	var cb := func(_id: StringName) -> void: hits["theme"] += 1
	var sb := func(_id: StringName) -> void: hits["state"] += 1
	Music.theme_changed.connect(cb)
	Music.state_changed.connect(sb)
	Music.set_theme(&"town")
	Music.set_theme(&"town")          # no-op: same id
	Music.set_state(&"danger")
	Music.set_state(&"danger")        # no-op: same id
	Music.theme_changed.disconnect(cb)
	Music.state_changed.disconnect(sb)
	eq(hits["theme"], 1, "theme_changed should fire once per real change")
	eq(hits["state"], 1, "state_changed should fire once per real change")


func test_unknown_ids_do_not_crash() -> void:
	Music.set_theme(&"definitely_not_a_theme")
	ok(true, "unknown theme accepted without error")
	Music.set_state(&"definitely_not_a_state")
	ok(true, "unknown state accepted without error")
	Music.stinger(&"definitely_not_a_stinger")
	Music.duck(0.0, 0.0)
	Music.reset_transient(true)
	Music.set_state(&"calm")
	Music.set_theme(&"town")
	eq(Music.desired_track(), &"town", "recovered after unknown ids")


func test_danger_hysteresis() -> void:
	Music.set_theme(&"graveyard")
	Music.set_state(&"calm")
	Music._danger_update(1, 0.25)
	eq(Music.state_id, &"danger", "one engaged enemy flips calm -> danger at once")
	Music._danger_update(0, 1.0)
	eq(Music.state_id, &"danger", "danger holds while the hold timer runs")
	Music._danger_update(0, float(_c()["DANGER_HOLD"]) + 0.1)
	eq(Music.state_id, &"calm", "danger -> calm after DANGER_HOLD seconds without enemies")
	# Only calm/danger are managed by the poll; boss must not be downgraded.
	Music.set_state(&"boss")
	Music._danger_update(0, 99.0)
	eq(Music.state_id, &"boss", "danger polling must not touch the boss state")


func test_engage_range_clamps() -> void:
	var probe := EnemyProbe.new()
	add_child(probe)
	eq(int(Music.engage_range(probe)), int(_c()["ENGAGE_MIN"]),
			"tiny aggro_range should clamp up to ENGAGE_MIN")
	probe.aggro_range = 9999.0
	eq(int(Music.engage_range(probe)), int(_c()["ENGAGE_MAX"]),
			"huge aggro_range should clamp down to ENGAGE_MAX")
	probe.aggro_range = 150.0
	eq(int(Music.engage_range(probe)), 150, "in-range aggro_range passes through")
	probe.queue_free()
	var bare := Node.new()
	eq(int(Music.engage_range(bare)), int(_c()["ENGAGE_DEFAULT"]),
			"an object without aggro/wake range uses ENGAGE_DEFAULT")
	bare.free()


# ---------------------------------------------------------------------------
# Stingers / ducking
# ---------------------------------------------------------------------------

func test_every_stinger_fires_and_unknown_is_ignored() -> void:
	var c := _c()
	for id in c["STINGERS"]:
		Music._stinger_until = 0.0
		Music._stinger_prio = 0
		Music.stinger(StringName(id))
		eq(Music.last_stinger, StringName(id), "stinger(%s) should be the last stinger" % id)
	Music._stinger_until = 0.0
	Music.stinger(&"not_a_stinger")
	eq(Music.last_stinger, &"ending_snuff", "unknown stinger must be a silent no-op")


func test_stinger_priority_never_cuts_a_bigger_cue() -> void:
	Music._stinger_until = 0.0
	Music._stinger_prio = 0
	Music.stinger(&"boss_down")                 # priority 4
	eq(Music.last_stinger, &"boss_down", "boss_down should play from a clean slate")
	Music.stinger(&"chapter")                   # priority 2, still inside boss_down
	eq(Music.last_stinger, &"boss_down", "a lower-priority stinger must not cut boss_down")
	Music._stinger_until = 0.0
	Music._stinger_prio = 0
	Music.stinger(&"ending_keep")               # priority 5
	Music.stinger(&"boss_intro")                # priority 3
	eq(Music.last_stinger, &"ending_keep", "a lower-priority stinger must not cut an ending")


func test_duck_deepest_wins_and_never_adds_up() -> void:
	var before := Music._duck_target()
	Music.duck(-3.0, 0.5)
	var once := Music._duck_target()
	ok(once <= minf(before, -3.0) + 0.001, "a -3 dB duck should be the deepest active dip")
	Music.duck(-3.0, 0.5)
	eq(Music._duck_target(), once, "overlapping equal ducks must not add up")
	Music.duck(-9.0, 0.5)
	var deep := Music._duck_target()
	ok(deep <= -9.0 + 0.001, "a -9 dB duck should win over -3 dB")
	Music.duck(6.0, 0.5)                         # positive values clamp to 0
	eq(Music._duck_target(), deep, "duck() must clamp positive input to 0 dB")
	# _update_duck approaches its target smoothly (headless: no audio thread).
	Music._duck_cur = 0.0
	Music._update_duck(10.0)
	ok(Music._duck_cur <= deep + 0.001, "_update_duck should reach the deepest duck")


# ---------------------------------------------------------------------------
# Event handlers (called directly: emitting GameEvents would run other systems)
# ---------------------------------------------------------------------------

func test_event_handlers_drive_theme_and_state() -> void:
	Music.set_state(&"calm")
	Music._on_chapter_started("level08")
	eq(Music.theme_id, &"slag", "chapter_started(level08) should switch to the slag theme")
	eq(Music.state_id, &"calm", "a fresh chapter clears gameplay-driven states")
	Music._on_boss_intro("Executioner")
	Music._on_boss_appeared("Executioner", 100, 100)
	eq(Music.state_id, &"boss", "boss_appeared -> boss state")
	eq(Music.front_track, &"boss_executioner", "graveyard boss uses the executioner track")
	Music._on_boss_phase("Executioner", 2)
	eq(int(Music.snapshot()["boss_phase"]), 2, "boss_phase_changed should store the phase")
	Music._on_boss_defeated()
	eq(Music.state_id, &"calm", "boss_defeated -> calm")
	Music._on_player_died()
	eq(Music.state_id, &"calm", "player_died -> calm")
	Music._on_player_respawned()
	eq(Music.state_id, &"calm", "player_respawned stays calm")
	Music._on_parried(null, null)
	Music._on_core(null)
	Music._on_ability(&"dash")
	ok(true, "parried / core / ability cues run headless")
	Music._on_ending_chosen(&"give")
	eq(Music.state_id, &"ending", "ending give -> ending state")
	eq(Music.front_track, &"ending", "ending state plays the ending track")
	Music._on_ending_chosen(&"snuff")
	eq(Music.state_id, &"silent", "ending snuff -> silent state")
	eq(Music.front_track, &"", "silent state plays nothing")
	Music._on_ending_chosen(&"rekindle")        # a choice, not an ending
	eq(Music.state_id, &"silent", "the forge-heart rekindle choice is not an ending")


func test_reset_transient_semantics() -> void:
	Music.set_theme(&"graveyard")
	Music.set_state(&"boss")
	Music._on_boss_phase("Boss", 2)
	Music.reset_transient()
	eq(Music.state_id, &"calm", "reset_transient drops boss")
	eq(int(Music.snapshot()["boss_phase"]), 1, "reset_transient resets the boss phase")
	Music.set_state(&"ending")
	Music.reset_transient()
	eq(Music.state_id, &"ending", "reset_transient(false) keeps cinematic states")
	Music.reset_transient(true)
	eq(Music.state_id, &"calm", "reset_transient(true) clears ending / silent too")


func test_enter_title() -> void:
	Music._on_chapter_started("level01")
	eq(Music.theme_id, &"graveyard", "level01 starts in the graveyard")
	Music._on_ending_chosen(&"keep")
	Music.enter_title()
	eq(Music.theme_id, &"title", "enter_title switches to the title theme")
	eq(Music.state_id, &"calm", "enter_title leaves a clean calm state")
	eq(Music.front_track, &"title", "enter_title front track")


# ---------------------------------------------------------------------------
# Signal wiring
# ---------------------------------------------------------------------------

func test_game_events_connected_exactly_once() -> void:
	var signal_list: Array = []
	for info in GameEvents.get_signal_list():
		signal_list.append(info["name"])
	for name in LISTENED_EVENTS:
		ok(signal_list.has(name), "GameEvents has no signal %s" % name)
		var count := 0
		for conn in GameEvents.get_signal_connection_list(name):
			var cb: Callable = conn["callable"]
			if cb.get_object() == Music:
				count += 1
		eq(count, 1, "Music should listen to GameEvents.%s exactly once" % name)
