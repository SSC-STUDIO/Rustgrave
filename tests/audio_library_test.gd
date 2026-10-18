extends TestCase
## Audio-library contract tests (headless, zero dependency, no audio device needed).
##
## These are the executable form of the audio audit: every res:// path named by
## Sfx / Music exists and imports, every key any script asks for resolves, every
## chapter theme has its stem set, and the tables cross-link consistently. The
## measured numbers (peaks / LUFS / loop seams) live in tools/gen_audio_verify.py;
## this file guards the *contract* so a rename, a missing take or a dropped key
## turns the suite red before anyone has to listen.
##
## Files are the source of truth for the key scan: scripts/**/*.gd is walked with
## regexes, so a new Sfx.play(&"nope") anywhere in gameplay code fails here.

const SFX_DIR := "res://scripts"
const MUSIC_STEMS := "res://assets/audio/music/"
const LIBRARY_PATH_RE := "res://"
## Skin values known to rely on the documented "unknown => stone" fallback.
## SolidPlatform exposes them (cathedral nave) but Sfx.SKIN_SURFACE does not list
## them yet; the result is still stone, so the test documents the gap instead of
## pretending it is covered. Expert fix is a 2-line SKIN_SURFACE addition.
const SKIN_FALLBACK_ONLY := {&"nave": &"stone", &"nave_float": &"stone"}

var _script_texts: Dictionary = {}


func _gs() -> Script:
	return Sfx.get_script() as Script


func _consts() -> Dictionary:
	return _gs().get_script_constant_map()


func _music_consts() -> Dictionary:
	return (Music.get_script() as Script).get_script_constant_map()


## All .gd sources under res://scripts, cached per test instance.
func _scripts() -> Dictionary:
	if not _script_texts.is_empty():
		return _script_texts
	_walk(SFX_DIR)
	return _script_texts


func _walk(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if dir.current_is_dir():
			if not fname.begins_with("."):
				_walk(dir_path.path_join(fname))
		elif fname.ends_with(".gd"):
			var full := dir_path.path_join(fname)
			var f := FileAccess.open(full, FileAccess.READ)
			if f != null:
				_script_texts[full] = f.get_as_text()
		fname = dir.get_next()
	dir.list_dir_end()


static func _is_comment(text: String, pos: int) -> bool:
	var line_start := text.rfind("\n", pos) + 1
	var head := text.substr(line_start, pos - line_start).strip_edges()
	return head.begins_with("#")


static func _line_of(text: String, pos: int) -> int:
	return text.substr(0, pos).count("\n") + 1


## Collect captures of `pattern` across every script: Array of
## {key, fallback, where}. Group 1 is the key, group 2 (optional) a fallback.
func _scan(pattern: String) -> Array:
	var out: Array = []
	var rx := RegEx.create_from_string(pattern)
	if rx == null:
		return out
	for path in _scripts():
		var text: String = _scripts()[path]
		for m in rx.search_all(text):
			if _is_comment(text, m.get_start(0)):
				continue
			var entry := {"key": StringName(m.get_string(1)), "fallback": &"",
					"where": "%s:%d" % [path.get_file(), _line_of(text, m.get_start(0))]}
			if m.get_group_count() >= 2:
				entry["fallback"] = StringName(m.get_string(2))
			out.append(entry)
	return out


# ---------------------------------------------------------------------------
# 1. Library integrity
# ---------------------------------------------------------------------------

func test_library_paths_exist_load_and_are_imported() -> void:
	var lib: Dictionary = _consts()["LIBRARY"]
	ok(lib.size() >= 50, "LIBRARY should expose the whole pack (got %d keys)" % lib.size())
	for key in lib:
		var path: String = lib[key]
		ok(ResourceLoader.exists(path), "LIBRARY[%s] -> %s does not exist" % [key, path])
		ok(FileAccess.file_exists(path + ".import"),
				"LIBRARY[%s] -> %s was never imported (no .import)" % [key, path])
		var stream := load(path) as AudioStream
		ok(stream != null, "LIBRARY[%s] -> %s is not an AudioStream" % [key, path])
		if stream != null:
			ok(stream.get_length() > 0.02, "LIBRARY[%s] stream is empty (%f s)" % [key, stream.get_length()])


func test_variants_exist_and_match_library() -> void:
	var lib: Dictionary = _consts()["LIBRARY"]
	var variants: Dictionary = _consts()["VARIANTS"]
	ok(not variants.is_empty(), "VARIANTS should not be empty")
	for key in variants:
		ok(lib.has(key), "VARIANTS[%s] has no LIBRARY entry to shadow" % key)
		var takes: Array = variants[key]
		ok(takes.size() >= 2, "VARIANTS[%s] should list at least two takes" % key)
		var seen: Dictionary = {}
		for take in takes:
			var path := String(take)
			ok(ResourceLoader.exists(path), "VARIANTS[%s] take %s does not exist" % [key, path])
			ok(not seen.has(path), "VARIANTS[%s] lists %s twice" % [key, path])
			seen[path] = true
		if lib.has(key) and not takes.is_empty():
			ok(lib[key] == String(takes[0]),
					"VARIANTS[%s] first take should be the LIBRARY entry" % key)


func test_ambience_loops_exist_and_are_looped() -> void:
	var c := _consts()
	var amb: Dictionary = c["AMBIENCE"]
	ok(not amb.is_empty(), "AMBIENCE should not be empty")
	var wav_loops := 0
	for key in amb:
		var path: String = amb[key]
		ok(ResourceLoader.exists(path), "AMBIENCE[%s] -> %s does not exist" % [key, path])
		var stream := load(path) as AudioStream
		ok(stream != null, "AMBIENCE[%s] -> %s is not an AudioStream" % [key, path])
		if stream == null:
			continue
		ok(stream.get_length() > 0.5, "AMBIENCE[%s] loop is shorter than 0.5 s" % key)
		if stream is AudioStreamOggVorbis:
			ok((stream as AudioStreamOggVorbis).loop,
					"AMBIENCE[%s] OGG is imported with loop=false" % key)
		elif stream is AudioStreamWAV:
			# Sfx._ensure_ambience sets LOOP_FORWARD + loop_end at runtime; the
			# import itself is deliberately loop-agnostic on these legacy WAVs.
			wav_loops += 1
			ok((stream as AudioStreamWAV).mix_rate > 0, "AMBIENCE[%s] WAV has no mix rate" % key)
		else:
			ok(false, "AMBIENCE[%s] is neither WAV nor OGG" % key)
		ok(c["AMBIENCE_LEVEL"].has(key), "AMBIENCE_LEVEL is missing %s" % key)
	ok(wav_loops >= 3, "expected the four legacy WAV beds (rain / rust_rain / drone / hiss)")


func test_bed_keys_and_theme_beds_cross_link() -> void:
	var c := _consts()
	var amb: Dictionary = c["AMBIENCE"]
	var bed_keys: Array = c["BED_KEYS"]
	var levels: Dictionary = c["AMBIENCE_LEVEL"]
	ok(not bed_keys.is_empty(), "BED_KEYS should not be empty")
	for key in bed_keys:
		ok(amb.has(key), "BED_KEYS entry %s is not in AMBIENCE" % key)
		ok(levels.has(key), "BED_KEYS entry %s has no AMBIENCE_LEVEL" % key)
	for theme in c["THEME_BEDS"]:
		var beds: Dictionary = c["THEME_BEDS"][theme]
		ok(not beds.is_empty(), "THEME_BEDS[%s] is empty" % theme)
		for bed in beds:
			ok(amb.has(bed), "THEME_BEDS[%s] uses unknown bed %s" % [theme, bed])
			ok(bed_keys.has(bed), "THEME_BEDS[%s] bed %s is not in BED_KEYS" % [theme, bed])
			var gain := float(beds[bed])
			ok(gain > 0.0 and gain <= 1.0, "THEME_BEDS[%s][%s] gain out of 0..1" % [theme, bed])
	# Every theme the Music director knows must have an ambience decision
	# (a themed bed, or the documented graveyard drone-only fallback).
	var music_themes: Array = _music_consts()["THEMES"]
	var gameplay_themes: Dictionary = _music_consts()["LEVEL_THEMES"]
	var gameplay_values: Dictionary = {}
	for level_id in gameplay_themes:
		gameplay_values[gameplay_themes[level_id]] = true
	var drone_scale: Dictionary = c["THEME_DRONE_SCALE"]
	for theme in music_themes:
		ok(drone_scale.has(theme), "THEME_DRONE_SCALE is missing theme %s" % theme)
	# graveyard's bed is the global cemetery drone (THEME_DRONE_SCALE 1.0, no
	# themed bed by design); the title screen only has weather + drone.
	for theme in gameplay_values:
		if theme == &"graveyard":
			continue
		ok(c["THEME_BEDS"].has(theme),
				"playable theme %s has neither THEME_BEDS nor the graveyard drone fallback" % theme)
	for theme in c["THEME_EVENTS"]:
		for event in c["THEME_EVENTS"][theme]:
			ok(c["LIBRARY"].has(StringName(event[0])),
					"THEME_EVENTS[%s] uses unknown key %s" % [theme, event[0]])


func test_surface_and_stride_tables_complete() -> void:
	var c := _consts()
	var surfaces: Array = c["SURFACES"]
	var step_keys: Dictionary = c["STEP_KEYS"]
	var stride: Dictionary = c["STRIDE"]
	var skin_surface: Dictionary = c["SKIN_SURFACE"]
	ok(surfaces.size() == 5, "expected the five footstep surfaces")
	for s in surfaces:
		ok(step_keys.has(s), "STEP_KEYS has no entry for surface %s" % s)
		ok(stride.has(s), "STRIDE has no entry for surface %s" % s)
		ok(c["LIBRARY"].has(step_keys[s]), "STEP_KEYS[%s] -> %s missing from LIBRARY" % [s, step_keys[s]])
	for skin in skin_surface:
		ok(surfaces.has(skin_surface[skin]),
				"SKIN_SURFACE[%s] -> %s is not one of SURFACES" % [skin, skin_surface[skin]])
	ok(Sfx.surface_for_skin(&"definitely_not_a_skin") == &"stone",
			"unknown skin must fall back to stone")
	# Every SolidPlatform.skin value (the enum in solid_platform.gd) must map.
	var skins := _platform_skins()
	ok(skins.size() >= 18, "could not parse the SolidPlatform skin enum (%d values)" % skins.size())
	for skin in skins:
		var got := Sfx.surface_for_skin(skin)
		ok(surfaces.has(got), "skin %s maps to unknown surface %s" % [skin, got])
		var expected := StringName(SKIN_FALLBACK_ONLY.get(skin, skin_surface.get(skin, &"stone")))
		eq(got, expected, "skin %s should map to %s" % [skin, expected])


func _platform_skins() -> Array:
	const PATH := "res://scripts/world/solid_platform.gd"
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return []
	var text := f.get_as_text()
	var start := text.find("@export_enum(")
	var end := text.find(") var skin", start)
	if start < 0 or end < 0:
		return []
	var out: Array = []
	var rx := RegEx.create_from_string("\"([a-z_0-9]+)\"")
	for m in rx.search_all(text.substr(start, end - start)):
		out.append(StringName(m.get_string(1)))
	return out


# ---------------------------------------------------------------------------
# 2. Referenced keys resolve (the "silent fallback" hunt)
# ---------------------------------------------------------------------------

func test_combat_rules_sfx_keys_resolve() -> void:
	var lib: Dictionary = _consts()["LIBRARY"]
	var materials: Array = CombatRules.MATERIALS
	for material in materials:
		for weight in CombatRules.WEIGHTS:
			var row := CombatRules.feel(material, weight)
			var key := StringName(row["sfx"])
			var resolved := CombatRules.sfx_key(key)
			ok(lib.has(resolved),
					"HIT_FEEL[%s/%s] key %s does not resolve (got %s)" % [material, weight, key, resolved])
			eq(resolved, key, "HIT_FEEL[%s/%s] silently falls back from %s" % [material, weight, key])
	var cr_consts: Dictionary = (load("res://scripts/combat/combat_rules.gd") as Script).get_script_constant_map()
	for name in ["PLAYER_HURT", "BOSS_PHASE_FEEL", "BOSS_DEATH_FEEL"]:
		var row: Dictionary = cr_consts[name]
		var key := StringName(row["sfx"])
		eq(CombatRules.sfx_key(key), key, "%s key %s silently falls back" % [name, key])
		ok(lib.has(key), "%s key %s missing from LIBRARY" % [name, key])
	for from_key in CombatRules.SFX_FALLBACK:
		var to_key := StringName(CombatRules.SFX_FALLBACK[from_key])
		ok(lib.has(to_key), "SFX_FALLBACK[%s] target %s missing from LIBRARY" % [from_key, to_key])


func test_code_sfx_keys_resolve() -> void:
	var lib: Dictionary = _consts()["LIBRARY"]
	var fallback := CombatRules.SFX_FALLBACK
	var found := 0
	var patterns := [
		"Sfx\\.play(?:_at)?\\(\\s*&\"([a-z0-9_]+)\"",
		"Sfx\\.play(?:_at)?\\(\\s*CombatRules\\.sfx_key\\(\\s*&\"([a-z0-9_]+)\"",
		"CombatRules\\.sfx_key\\(\\s*&\"([a-z0-9_]+)\"",
		"CombatRules\\.sfx_key\\([^)]*\\belse\\s+&\"([a-z0-9_]+)\"",
		"\"kind\":\\s*\"sfx\",\\s*\"id\":\\s*\"([a-z0-9_]+)\"",
	]
	for pattern in patterns:
		for hit in _scan(pattern):
			found += 1
			var key: StringName = hit["key"]
			ok(lib.has(key), "unresolved Sfx key \"%s\" at %s" % [key, hit["where"]])
			if not lib.has(key):
				ok(fallback.get(key, &"") in lib,
						"%s has neither a LIBRARY entry nor a working SFX_FALLBACK" % key)
	# UiKit.sfx(key, fallback): the fallback must at least be playable.
	for hit in _scan("UiKit\\.sfx\\(\\s*&\"([a-z0-9_]+)\"(?:\\s*,\\s*&\"([a-z0-9_]+)\")?"):
		found += 1
		var key: StringName = hit["key"]
		var fb: StringName = hit["fallback"]
		ok(lib.has(key) or (fb != &"" and lib.has(fb)),
				"UiKit.sfx(%s, %s) at %s resolves to silence" % [key, fb, hit["where"]])
		if fb != &"":
			ok(lib.has(fb), "UiKit.sfx fallback %s at %s is missing from LIBRARY" % [fb, hit["where"]])
	ok(found >= 60, "expected the key scan to find the gameplay call sites (found %d)" % found)


func test_code_music_ids_resolve() -> void:
	var m := _music_consts()
	var valid_states: Array = m["STATES"]
	var valid_themes: Array = m["THEMES"]
	var valid_stingers: Array = []
	for id in m["STINGERS"]:
		valid_stingers.append(id)
	ok(valid_stingers.size() >= 9, "expected the nine stingers (got %d)" % valid_stingers.size())
	var checked := 0
	for hit in _scan("Music\\.stinger\\(\\s*&\"([a-z0-9_]+)\""):
		checked += 1
		ok(valid_stingers.has(hit["key"]),
				"Music.stinger(%s) at %s is not in STINGERS" % [hit["key"], hit["where"]])
	for hit in _scan("Music\\.set_state\\(\\s*&\"([a-z0-9_]+)\""):
		checked += 1
		ok(valid_states.has(hit["key"]),
				"Music.set_state(%s) at %s is not a state" % [hit["key"], hit["where"]])
	for hit in _scan("Music\\.set_theme\\(\\s*&\"([a-z0-9_]+)\""):
		checked += 1
		ok(valid_themes.has(hit["key"]),
				"Music.set_theme(%s) at %s is not a theme" % [hit["key"], hit["where"]])
	# story_stage.ending_stinger() maps ending kinds to ids dynamically.
	for hit in _scan("return\\s+&\"(ending_[a-z]+)\""):
		checked += 1
		ok(valid_stingers.has(hit["key"]),
				"dynamic ending stinger %s at %s is not in STINGERS" % [hit["key"], hit["where"]])
	ok(checked >= 20, "expected music call sites in scripts (found %d)" % checked)
	# Every stinger needs a rule row (Music indexes STINGER_RULES[id] unguarded).
	var rules: Dictionary = m["STINGER_RULES"]
	for id in m["STINGERS"]:
		ok(rules.has(id), "STINGER_RULES has no row for %s (Music would crash)" % id)
		ok(String(m["STINGERS"][id]) != "", "STINGERS[%s] path is empty" % id)


# ---------------------------------------------------------------------------
# 3. Music theme / stem coverage
# ---------------------------------------------------------------------------

func test_every_theme_has_bed_and_keys() -> void:
	var m := _music_consts()
	var themes: Array = m["THEMES"]
	ok(themes.size() == 10, "expected the ten chapter themes (got %d)" % themes.size())
	for theme in themes:
		for role in ["bed", "keys"]:
			var path := "%s%s_%s.ogg" % [MUSIC_STEMS, theme, role]
			ok(ResourceLoader.exists(path), "theme %s is missing %s" % [theme, path])
		if theme != &"title":
			var pulse := "%s%s_pulse.ogg" % [MUSIC_STEMS, theme]
			ok(ResourceLoader.exists(pulse), "percussive theme %s is missing pulse" % theme)
	# Boss tracks and the ending track.
	var boss_set: Dictionary = {}
	for theme in m["BOSS_TRACKS"]:
		boss_set[m["BOSS_TRACKS"][theme]] = true
	for level_id in m["BOSS_TRACKS_BY_LEVEL"]:
		boss_set[m["BOSS_TRACKS_BY_LEVEL"][level_id]] = true
	boss_set[m["DEFAULT_BOSS_TRACK"]] = true
	ok(boss_set.size() == 7,
			"expected seven boss tracks (executioner/nightmare + five campaign bosses), got %s"
			% [boss_set.keys()])
	for track in boss_set:
		for role in ["bed", "hi"]:
			var p := "%s%s_%s.ogg" % [MUSIC_STEMS, track, role]
			ok(ResourceLoader.exists(p), "boss track %s is missing %s" % [track, p])
			var stream := load(p) as AudioStream
			ok(stream != null, "boss track %s does not load as AudioStream" % p)
			if stream != null:
				ok(stream.get_length() >= 20.0, "boss track %s is suspiciously short" % p)
	var ending: StringName = m["ENDING_TRACK"]
	for role in ["bed", "keys"]:
		var p := "%s%s_%s.ogg" % [MUSIC_STEMS, ending, role]
		ok(ResourceLoader.exists(p), "ending track is missing %s" % p)
	# Stingers load and are real one-shots.
	for id in m["STINGERS"]:
		var path: String = m["STINGERS"][id]
		ok(ResourceLoader.exists(path), "stinger %s file missing" % id)
		var stream := load(path) as AudioStream
		ok(stream != null, "stinger %s does not load as AudioStream" % id)
		if stream != null:
			ok(stream.get_length() >= 2.0, "stinger %s is suspiciously short" % id)


func test_level_theme_mapping_covers_every_level() -> void:
	var m := _music_consts()
	var level_themes: Dictionary = m["LEVEL_THEMES"]
	var themes: Array = m["THEMES"]
	ok(level_themes.size() >= 14, "expected a theme for all fourteen campaign chapters")
	for chapter in ["level02b", "level04b", "level07b", "level09b"]:
		ok(level_themes.has(chapter), "campaign chapter %s has no theme" % chapter)
	for level_id in level_themes:
		ok(String(level_themes[level_id]) != "", "%s maps to an empty theme" % level_id)
		ok(themes.has(level_themes[level_id]),
				"%s maps to unknown theme %s" % [level_id, level_themes[level_id]])
		eq(Music.theme_for_level(String(level_id)), level_themes[level_id],
				"theme_for_level(%s) disagrees with LEVEL_THEMES" % level_id)
	eq(Music.theme_for_level("level99"), &"", "unknown level must map to no theme")
	for theme in m["BOSS_TRACKS"]:
		ok(themes.has(theme), "BOSS_TRACKS references unknown theme %s" % theme)
	eq(Music.boss_track_for(&"definitely_not_a_theme"), m["DEFAULT_BOSS_TRACK"],
			"unknown theme must fall back to the default boss track")


## 关卡优先的 Boss 曲映射：同一 theme 下可能有不同 Boss（level02 vs level02b）。
func test_boss_track_for_level_prefers_level_id() -> void:
	var m := _music_consts()
	var by_level: Dictionary = m["BOSS_TRACKS_BY_LEVEL"]
	eq(by_level.size(), 7, "expected seven level-locked boss tracks (campaign bosses)")
	for level_id in by_level:
		var track: StringName = by_level[level_id]
		ok(String(track).begins_with("boss_"),
				"%s boss track %s must start with boss_ (KIND_BOSS detection)" % [level_id, track])
		eq(Music.boss_track_for_level(String(level_id)), track, "level-first lookup %s" % level_id)
		for role in ["bed", "hi"]:
			ok(ResourceLoader.exists("%s%s_%s.ogg" % [MUSIC_STEMS, track, role]),
					"level boss track %s is missing %s stem" % [track, role])
	# 同一 theme 的两个 Boss 必须落到不同曲目。
	eq(Music.boss_track_for_level("level02"), &"boss_hollow_bell", "level02 = 空钟")
	eq(Music.boss_track_for_level("level02b"), &"boss_capstan", "level02b = 绞盘守渠人")
	eq(Music.boss_track_for_level("level07b"), &"boss_bell_founder", "level07b = 铸钟人")
	eq(Music.boss_track_for_level("level09b"), &"boss_emberwind_herald", "level09b = 炉风先驱")
	eq(Music.boss_track_for_level("level10"), &"boss_nightmare", "level10 = 梦魇")
	eq(Music.boss_track_for_level("level01"), &"boss_executioner", "level01 = 刽子手")
	# 未登记的关卡退回 theme 映射 / 默认曲，不会返回空。
	var fallback := Music.boss_track_for_level("level99")
	ok(fallback != &"", "unknown level still gets a boss track")
	eq(fallback, m["DEFAULT_BOSS_TRACK"], "unknown level falls back to the default boss track")
	# play_boss_for_level 记录 level 并在 boss 状态下立刻生效。
	var saved_level := Music.boss_level
	var saved_state := Music.state_id
	var saved_theme := Music.theme_id
	Music.set_state(&"boss")
	eq(Music.play_boss_for_level("level09b"), &"boss_emberwind_herald",
			"play_boss_for_level returns the level track")
	eq(Music.boss_level, "level09b", "play_boss_for_level records the level")
	eq(Music.desired_track(), &"boss_emberwind_herald", "boss state uses the level-first track")
	Music.set_theme(&"title")
	Music.reset_transient(true)
	Music.set_state(saved_state)
	Music.set_theme(saved_theme)
	Music.boss_level = saved_level


func test_music_stinger_rules_are_sane() -> void:
	var rules: Dictionary = _music_consts()["STINGER_RULES"]
	for id in rules:
		var rule: Array = rules[id]
		eq(rule.size(), 3, "STINGER_RULES[%s] should be [priority, duck_db, seconds]" % id)
		ok(float(rule[1]) <= 0.0, "STINGER_RULES[%s] duck must be <= 0 dB" % id)
		ok(float(rule[2]) > 0.0, "STINGER_RULES[%s] duck seconds must be positive" % id)
