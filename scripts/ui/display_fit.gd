class_name DisplayFit
extends Object
## Rustgrave 全分辨率与多比例自适应控制器。
##
## 基础逻辑视口：1280x720 (16:9)
## The root stays in canvas-items mode. GamePresentation owns the 640x360
## world image and PresentationMetrics owns its centered integer-sized rect;
## keeping both layers in viewport mode would scale the world a second time.

const VIEW_W := 1280
const VIEW_H := 720

enum FitMode {
	ADAPTIVE = 0,   ## 自适应铺满 (Keep Aspect + Fractional)
	EXPAND = 1,     ## 视野扩展 (Expand Aspect)
	INTEGER = 2,    ## 点对点整数 (Integer Scale)
}

const PRESET_RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),   ## 720p HD (16:9)
	Vector2i(1920, 1080),  ## 1080p FHD (16:9)
	Vector2i(2560, 1440),  ## 1440p 2K (16:9)
	Vector2i(3840, 2160),  ## 4K UHD (16:9)
	Vector2i(1280, 800),   ## Steam Deck (16:10)
	Vector2i(1920, 1200),  ## WUXGA (16:10)
	Vector2i(2560, 1080),  ## 21:9 WFHD
	Vector2i(3440, 1440),  ## 21:9 UWQHD
	Vector2i(1024, 768),   ## 4:3 XGA
]

static var _current_fit_mode: FitMode = FitMode.INTEGER
static var _saved_mode_applied := false


static func _get_root_window(win: Window = null) -> Window:
	if win != null:
		return win
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root
	return null


static func apply(win: Window = null) -> void:
	_apply_saved_window_mode()
	apply_fit_mode(int(Settings.value(&"display_fit", FitMode.INTEGER)) as FitMode, win)


## 启动后第一次 apply 时恢复玩家在设置里选的全屏（只做一次，之后窗口模式归玩家说了算）。
static func _apply_saved_window_mode() -> void:
	if _saved_mode_applied:
		return
	_saved_mode_applied = true
	apply_vsync(bool(Settings.value(&"vsync", true)), false)
	var saved: Variant = Settings.value(&"resolution", Vector2i.ZERO)
	if saved is Vector2i and saved in PRESET_RESOLUTIONS:
		apply_resolution(saved, null, false)
	if DisplayServer.get_name() == "headless":
		return
	if bool(Settings.value(&"fullscreen", false)) and not is_fullscreen():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)


static func apply_fit_mode(mode: FitMode, win: Window = null, persist: bool = false) -> void:
	_current_fit_mode = clampi(int(mode), 0, 2) as FitMode
	if persist:
		Settings.set_value(&"display_fit", int(_current_fit_mode))
	var root := _get_root_window(win)
	if root == null:
		return
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	# Every presentation and bound UI uses the same metrics and refresh signal.
	root.size_changed.emit()


static func apply_vsync(enabled: bool, persist: bool = true) -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if enabled else DisplayServer.VSYNC_DISABLED)
	if persist:
		Settings.set_value(&"vsync", enabled)


static func get_fit_mode() -> FitMode:
	return _current_fit_mode


static func fit_mode_label(mode: FitMode = _current_fit_mode) -> String:
	match mode:
		FitMode.ADAPTIVE:
			return "画面: 自适应铺满"
		FitMode.EXPAND:
			return "画面: 视野扩展"
		FitMode.INTEGER:
			return "画面: 点对点整数"
	return "画面: 自适应铺满"


static func cycle_fit_mode(win: Window = null) -> String:
	var next_val := (int(_current_fit_mode) + 1) % 3
	apply_fit_mode(next_val as FitMode, win, true)
	return fit_mode_label()


static func toggle_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if is_fullscreen():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)


static func is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
			or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


static func fullscreen_label() -> String:
	return "窗 口" if is_fullscreen() else "全 屏"


static func get_window_size() -> Vector2i:
	if DisplayServer.get_name() == "headless":
		return Vector2i(VIEW_W, VIEW_H)
	return DisplayServer.window_get_size()


static func get_aspect_ratio_name(size: Vector2i = Vector2i.ZERO) -> String:
	if size == Vector2i.ZERO:
		size = get_window_size()
	if size.y <= 0:
		return "16:9"
	var ratio := float(size.x) / float(size.y)
	if absf(ratio - (16.0 / 9.0)) < 0.05:
		return "16:9"
	elif absf(ratio - (16.0 / 10.0)) < 0.05:
		return "16:10 (Deck/掌机)"
	elif absf(ratio - (21.0 / 9.0)) < 0.15 or ratio > 2.2:
		return "21:9 (超宽带鱼屏)"
	elif absf(ratio - (4.0 / 3.0)) < 0.05:
		return "4:3 (复古方屏)"
	return "%.2f:1" % ratio


static func get_resolution_string() -> String:
	var sz := get_window_size()
	return "%d×%d  %s" % [sz.x, sz.y, get_aspect_ratio_name(sz)]


static func apply_resolution(res: Vector2i, win: Window = null, persist: bool = true) -> void:
	if not res in PRESET_RESOLUTIONS:
		return
	if persist:
		Settings.set_value(&"resolution", res)
		Settings.set_value(&"fullscreen", false)
	if DisplayServer.get_name() == "headless":
		return
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(res)
	var screen_idx := DisplayServer.window_get_current_screen()
	var screen_rect := DisplayServer.screen_get_usable_rect(screen_idx)
	var pos := screen_rect.position + (screen_rect.size - res) / 2
	DisplayServer.window_set_position(pos)
	apply_fit_mode(_current_fit_mode, win)
