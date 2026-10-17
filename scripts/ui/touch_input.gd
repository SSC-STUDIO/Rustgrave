class_name TouchInput
extends Object
## Mobile / touch detection for the on-screen pad.
##
## Headless CI never shows the pad. Pure desktop keyboard sessions stay clean.
## Touchscreen laptops and phones show it. Tests can override with force_show.

## Gameplay InputMap actions the pad drives (must match project.godot).
const GAMEPLAY_ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"jump", &"dash", &"attack",
	&"interact", &"socket_1", &"socket_2", &"hookshot",
]

## -1 force hide · 0 auto · 1 force show (tests / desktop debug).
static var force_show: int = 0


static func is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


static func is_mobile_os() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")


static func has_touchscreen() -> bool:
	if is_headless():
		return false
	return DisplayServer.is_touchscreen_available()


## True when the on-screen pad should be built and considered for visibility.
static func wants_overlay() -> bool:
	if force_show == 1:
		return true
	if force_show == -1:
		return false
	if is_headless():
		return false
	if OS.get_environment("RUSTGRAVE_FORCE_TOUCH") == "1":
		return true
	if OS.get_environment("RUSTGRAVE_FORCE_TOUCH") == "0":
		return false
	return is_mobile_os() or has_touchscreen()


## Safe-area insets in 1280×720 UI design units (left, top, right, bottom).
## Only phones / tablets have notches and rounded corners to avoid. On desktop
## DisplayServer reports the *screen's* usable rect (taskbar, menu bar), which says
## nothing about a window, so desktops always get zero.
static func safe_insets_ui(win: Window = null) -> Vector4:
	if is_headless() or not is_mobile_os():
		return Vector4.ZERO
	var root := win
	if root == null:
		var loop := Engine.get_main_loop()
		if loop is SceneTree:
			root = (loop as SceneTree).root
	if root == null:
		return Vector4.ZERO
	var window_size := root.size
	if window_size.x <= 0 or window_size.y <= 0:
		return Vector4.ZERO
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or safe.size.y <= 0:
		return Vector4.ZERO
	# Map physical safe margins into the stretched UI design space.
	var sx := float(PresentationMetrics.UI_SIZE.x) / float(window_size.x)
	var sy := float(PresentationMetrics.UI_SIZE.y) / float(window_size.y)
	var left := maxf(0.0, float(safe.position.x) * sx)
	var top := maxf(0.0, float(safe.position.y) * sy)
	var right := maxf(0.0, float(window_size.x - safe.end.x) * sx)
	var bottom := maxf(0.0, float(window_size.y - safe.end.y) * sy)
	return Vector4(left, top, right, bottom)
