extends Node
## Player options, persisted to user://settings.cfg. Kept apart from the save
## file so deleting a save never resets volume, key bindings or comfort options.
## Do not give this script a class_name — the autoload name is the API.
##
## Other systems read the plain properties (shake_scale, flash_scale) at the moment
## they apply an effect; they never cache them, so a slider moves live.

signal changed(key: StringName)

const PATH := "user://settings.cfg"
const VERSION := 1
## Buses the options screen exposes, in menu order. Buses missing from the layout
## are skipped, so this stays valid while the layout evolves.
const VOLUME_BUSES: Array[StringName] = [&"Master", &"Music", &"Sfx", &"Ambience"]
const DEFAULT_VOLUME := {&"Master": 100.0, &"Music": 80.0, &"Sfx": 100.0, &"Ambience": 100.0}
## Actions the options screen lets the player rebind. Only the first keyboard key
## of each action is replaced; arrow keys, mouse buttons and touch stay as shipped.
const REBINDABLE: Array[StringName] = [
	&"move_left", &"move_right", &"jump", &"dash", &"attack", &"interact",
	&"socket_1", &"socket_2", &"hookshot", &"skill_1", &"skill_2",
]
## Keys that may never be bound (menu / system).
const RESERVED_KEYS: Array[int] = [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER]
## Slider drags would otherwise rewrite the file dozens of times per second.
const SAVE_DELAY := 0.4

## Redirectable for tests; production keeps PATH.
var save_path: String = PATH
## 0..1 multiplier on camera shake amplitude (0 = off).
var shake_scale: float = 1.0
## 0..1 multiplier on full-screen flashes and lightning (0 = off).
var flash_scale: float = 1.0

var _volume: Dictionary = {}
var _key_overrides: Dictionary = {}
var _default_keys: Dictionary = {}
var _extra: Dictionary = {}
var _loaded := false
var _save_pending := false
## 最近一次输入来自手柄时，提示文案改画按键名而不是键盘键帽。
var using_gamepad := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_capture_default_keys()
	load_settings()
	_install_gamepad()


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		using_gamepad = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) >= 0.55:
		using_gamepad = true
	elif event is InputEventKey and event.pressed and not event.echo:
		using_gamepad = false
	elif event is InputEventMouseButton and event.pressed:
		using_gamepad = false


## Read the file (missing / corrupt / foreign version all fall back to defaults)
## and push everything into the engine. Returns true when a valid file was read.
func load_settings() -> bool:
	_reset_values()
	var ok := false
	var cfg := ConfigFile.new()
	if FileAccess.file_exists(save_path) and cfg.load(save_path) == OK \
			and int(cfg.get_value("meta", "version", 0)) == VERSION:
		ok = true
		for bus in VOLUME_BUSES:
			_volume[bus] = clampf(float(cfg.get_value("audio", String(bus), DEFAULT_VOLUME[bus])), 0.0, 100.0)
		shake_scale = clampf(float(cfg.get_value("comfort", "shake", 1.0)), 0.0, 1.0)
		flash_scale = clampf(float(cfg.get_value("comfort", "flash", 1.0)), 0.0, 1.0)
		if cfg.has_section("keys"):
			for action in REBINDABLE:
				var code := int(cfg.get_value("keys", String(action), 0))
				if code > 0 and not RESERVED_KEYS.has(code):
					_key_overrides[action] = code
		if cfg.has_section("extra"):
			for key in cfg.get_section_keys("extra"):
				_extra[StringName(key)] = cfg.get_value("extra", key)
	_loaded = true
	apply_all()
	return ok


## Coalesced write: many callers (slider drags) can ask; one write lands ~0.4 s after the last.
func save_soon() -> void:
	if _save_pending:
		return
	_save_pending = true
	if not is_inside_tree():
		save_settings()
		return
	get_tree().create_timer(SAVE_DELAY, true, false, true).timeout.connect(_flush_save)


func _flush_save() -> void:
	if _save_pending:
		save_settings()


## Atomic-ish write (temp file then rename) so a crash never leaves half a file.
func save_settings() -> bool:
	_save_pending = false
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", VERSION)
	for bus in VOLUME_BUSES:
		cfg.set_value("audio", String(bus), volume_percent(bus))
	cfg.set_value("comfort", "shake", shake_scale)
	cfg.set_value("comfort", "flash", flash_scale)
	for action in _key_overrides:
		cfg.set_value("keys", String(action), int(_key_overrides[action]))
	for key in _extra:
		cfg.set_value("extra", String(key), _extra[key])
	var tmp := save_path + ".tmp"
	if cfg.save(tmp) != OK:
		return false
	var dir := DirAccess.open(save_path.get_base_dir())
	if dir == null:
		return false
	if FileAccess.file_exists(save_path):
		dir.remove(save_path.get_file())
	return dir.rename(tmp.get_file(), save_path.get_file()) == OK


func apply_all() -> void:
	for bus in VOLUME_BUSES:
		_apply_volume(bus)
	for action in REBINDABLE:
		_apply_key(action, key_for(action))
	_apply_display()


func _apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var vsync_on := bool(value(&"vsync", true))
	DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if vsync_on else DisplayServer.VSYNC_DISABLED)
	var index := int(value(&"resolution_index", -1))
	if index >= 0 and index < DisplayFit.PRESET_RESOLUTIONS.size():
		DisplayFit.apply_resolution(DisplayFit.PRESET_RESOLUTIONS[index])


# --- volume -----------------------------------------------------------------

func volume_percent(bus: StringName) -> float:
	return float(_volume.get(bus, DEFAULT_VOLUME.get(bus, 100.0)))


func set_volume_percent(bus: StringName, percent: float, persist: bool = true) -> void:
	_volume[bus] = clampf(percent, 0.0, 100.0)
	_apply_volume(bus)
	if persist:
		save_soon()
	changed.emit(StringName("volume_" + String(bus)))


func _apply_volume(bus: StringName) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	var pct := volume_percent(bus)
	AudioServer.set_bus_mute(idx, pct <= 0.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(pct / 100.0, 0.0001)))


# --- comfort ----------------------------------------------------------------

func set_shake_scale(value: float, persist: bool = true) -> void:
	shake_scale = clampf(value, 0.0, 1.0)
	if persist:
		save_soon()
	changed.emit(&"shake")


func set_flash_scale(value: float, persist: bool = true) -> void:
	flash_scale = clampf(value, 0.0, 1.0)
	if persist:
		save_soon()
	changed.emit(&"flash")


# --- key bindings -----------------------------------------------------------

## Physical keycode currently bound as the first keyboard key of `action`, or 0.
func key_for(action: StringName) -> int:
	if _key_overrides.has(action):
		return int(_key_overrides[action])
	return int(_default_keys.get(action, 0))


func default_key_for(action: StringName) -> int:
	return int(_default_keys.get(action, 0))


## Human label (layout-aware) for the key bound to `action`.
func key_label(action: StringName) -> String:
	var physical := key_for(action)
	if physical <= 0:
		return "—"
	var keycode := physical as Key
	# The headless display server rejects layout queries with an engine error.
	if DisplayServer.get_name() != "headless":
		var translated := DisplayServer.keyboard_get_keycode_from_physical(physical as Key)
		if translated != KEY_NONE:
			keycode = translated
	return OS.get_keycode_string(keycode)


## Action (other than `except`) whose first keyboard key is `physical`, or &"".
func key_owner(physical: int, except: StringName = &"") -> StringName:
	for action in REBINDABLE:
		if action != except and key_for(action) == physical:
			return action
	return &""


## Bind `physical` as the first key of `action`. A key already used by another
## rebindable action is swapped (that action receives this one's old key), so
## the player can never end up with an unbound action.
## Returns &"" on a plain rebind, the swapped action's name on a swap, and
## &"reserved" when the key may not be used (nothing changes).
func rebind_action(action: StringName, physical: int, persist: bool = true) -> StringName:
	if not REBINDABLE.has(action) or physical <= 0 or RESERVED_KEYS.has(physical):
		return &"reserved"
	var old := key_for(action)
	var other := key_owner(physical, action)
	_set_override(action, physical)
	if other != &"":
		_set_override(other, old)
	if persist:
		save_settings()
	changed.emit(&"keys")
	return other


func reset_keys(persist: bool = true) -> void:
	_key_overrides.clear()
	for action in REBINDABLE:
		_apply_key(action, default_key_for(action))
	if persist:
		save_settings()
	changed.emit(&"keys")


func _set_override(action: StringName, physical: int) -> void:
	if physical == default_key_for(action):
		_key_overrides.erase(action)
	else:
		_key_overrides[action] = physical
	_apply_key(action, physical)


func _capture_default_keys() -> void:
	_default_keys.clear()
	for action in REBINDABLE:
		if not InputMap.has_action(action):
			continue
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				_default_keys[action] = int((event as InputEventKey).physical_keycode)
				break


## Replace the first keyboard event of `action` in the live InputMap.
func _apply_key(action: StringName, physical: int) -> void:
	if physical <= 0 or not InputMap.has_action(action):
		return
	var events := InputMap.action_get_events(action)
	var replaced := false
	var rebuilt: Array[InputEvent] = []
	for event in events:
		if not replaced and event is InputEventKey:
			rebuilt.append(_key_event(physical))
			replaced = true
		else:
			rebuilt.append(event)
	if not replaced:
		rebuilt.append(_key_event(physical))
	InputMap.action_erase_events(action)
	for event in rebuilt:
		InputMap.action_add_event(action, event)


## Physical-position event (keycode left unset) so WASD stays WASD on AZERTY etc.
func _key_event(physical: int) -> InputEventKey:
	var key := InputEventKey.new()
	key.physical_keycode = physical as Key
	return key


# --- free-form options owned by other systems --------------------------------

func value(key: StringName, default: Variant = null) -> Variant:
	return _extra.get(key, default)


func set_value(key: StringName, v: Variant, persist: bool = true) -> void:
	_extra[key] = v
	if persist:
		save_settings()
	changed.emit(key)


## 手柄默认键。只在这个动作上还没有对应手柄事件时补一条，不覆盖键盘改键。
func _install_gamepad() -> void:
	if not InputMap.has_action(&"world_map"):
		InputMap.add_action(&"world_map", 0.5)
	_ensure_key(&"world_map", KEY_M)
	_ensure_button(&"world_map", JOY_BUTTON_BACK)
	_ensure_button(&"jump", JOY_BUTTON_A)
	_ensure_button(&"dash", JOY_BUTTON_B)
	_ensure_button(&"attack", JOY_BUTTON_X)
	_ensure_button(&"interact", JOY_BUTTON_Y)
	_ensure_button(&"socket_1", JOY_BUTTON_LEFT_SHOULDER)
	_ensure_button(&"socket_2", JOY_BUTTON_RIGHT_SHOULDER)
	_ensure_button(&"hookshot", JOY_BUTTON_RIGHT_STICK)
	_ensure_axis(&"hookshot", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_ensure_button(&"skill_1", JOY_BUTTON_LEFT_STICK)
	_ensure_axis(&"skill_1", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_ensure_button(&"skill_2", JOY_BUTTON_DPAD_UP)
	_ensure_button(&"move_left", JOY_BUTTON_DPAD_LEFT)
	_ensure_button(&"move_right", JOY_BUTTON_DPAD_RIGHT)
	_ensure_axis(&"move_left", JOY_AXIS_LEFT_X, -1.0)
	_ensure_axis(&"move_right", JOY_AXIS_LEFT_X, 1.0)
	if InputMap.has_action(&"ui_cancel"):
		_ensure_button(&"ui_cancel", JOY_BUTTON_START)


func _ensure_key(action: StringName, physical: Key) -> void:
	if not InputMap.has_action(action):
		return
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == physical:
			return
	var key := InputEventKey.new()
	key.physical_keycode = physical
	InputMap.action_add_event(action, key)


func _ensure_button(action: StringName, button: JoyButton) -> void:
	if not InputMap.has_action(action):
		return
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == button:
			return
	var joy := InputEventJoypadButton.new()
	joy.button_index = button
	InputMap.action_add_event(action, joy)


func _ensure_axis(action: StringName, axis: JoyAxis, axis_value: float) -> void:
	if not InputMap.has_action(action):
		return
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion:
			var motion := event as InputEventJoypadMotion
			if motion.axis == axis and signf(motion.axis_value) == signf(axis_value):
				return
	var joy := InputEventJoypadMotion.new()
	joy.axis = axis
	joy.axis_value = axis_value
	InputMap.action_add_event(action, joy)


func _reset_values() -> void:
	_volume.clear()
	for bus in VOLUME_BUSES:
		_volume[bus] = float(DEFAULT_VOLUME[bus])
	shake_scale = 1.0
	flash_scale = 1.0
	_key_overrides.clear()
	_extra.clear()
