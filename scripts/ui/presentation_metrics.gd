class_name PresentationMetrics
extends RefCounted
## Physical integer world pixels; UI remains vector/font drawing in the root canvas.

const WORLD_SIZE := Vector2i(640, 360)
const UI_SIZE := Vector2i(1280, 720)
## Four physical samples per world unit at QHD; cap at QHD on 4K displays.
## size_2d_override preserves camera framing, input and every gameplay coordinate.
const MAX_WORLD_DENSITY := 4


static func configure_world(viewport: SubViewport, metrics: Dictionary) -> void:
	var density := mini(MAX_WORLD_DENSITY, int(metrics["scale"]))
	var logical_size: Vector2i = metrics["world_size"]
	var target := logical_size * density
	viewport.size_2d_override = logical_size
	viewport.size_2d_override_stretch = true
	if viewport.size != target:
		viewport.size = target

static func world_input_transform(logical_size: Vector2i, image_rect: Rect2) -> Transform2D:
	var scale := Vector2(logical_size) / image_rect.size
	var transform := Transform2D.IDENTITY.scaled(scale)
	transform.origin = -image_rect.position * scale
	return transform




static func calculate(window_size: Vector2i, mode: int = DisplayFit.FitMode.INTEGER) -> Dictionary:
	var physical := Vector2(maxi(window_size.x, 640), maxi(window_size.y, 360))
	var fit_scale := minf(physical.x / 640.0, physical.y / 360.0)
	var integer_scale := maxi(1, int(floor(fit_scale)))
	var pixel_scale := float(integer_scale) if mode == DisplayFit.FitMode.INTEGER else fit_scale
	var ui_size := Vector2(WORLD_SIZE) * pixel_scale
	var ui_origin := ((physical - ui_size) * 0.5).floor()
	var expanded := mode == DisplayFit.FitMode.EXPAND
	var content_size := physical if expanded else ui_size
	var origin := Vector2.ZERO if expanded else ui_origin
	var root_scale := physical / Vector2(UI_SIZE)
	var canvas_origin := ui_origin / root_scale
	return {
		"scale": integer_scale,
		"world_size": Vector2i((physical / pixel_scale).ceil()) if expanded else WORLD_SIZE,
		"physical_rect": Rect2(origin, content_size),
		"canvas_rect": Rect2(origin / root_scale, content_size / root_scale),
		"ui_canvas_rect": Rect2(canvas_origin, ui_size / root_scale),
		"ui_transform": Transform2D(0.0, Vector2.ONE * pixel_scale * 0.5 / root_scale, 0.0, canvas_origin),
	}


static func for_window(win: Window) -> Dictionary:
	return calculate(win.size if win != null else UI_SIZE, DisplayFit.get_fit_mode())


## Safe-area insets measured on the root canvas (left, top, right, bottom in 1280x720
## units, as TouchInput.safe_insets_ui reports them) -> insets inside a layer bound
## by `bind_layer`. Layer space is the centred integer content rectangle, so a notch
## that lies in the black margin costs nothing and a window with no margin keeps the
## full inset. Pure function: unit-testable without a display.
static func layer_insets(root_insets: Vector4, window_size: Vector2i) -> Vector4:
	if root_insets == Vector4.ZERO:
		return Vector4.ZERO
	var metrics := calculate(window_size, DisplayFit.get_fit_mode())
	var canvas: Rect2 = metrics["ui_canvas_rect"]
	var ui := Vector2(UI_SIZE)
	# The content rect spans [canvas.position, canvas.end] on the root canvas and
	# is exactly UI_SIZE wide/high in layer units, so one layer unit is this many
	# root-canvas units:
	var per_unit := Vector2(canvas.size.x / ui.x, canvas.size.y / ui.y)
	var left := maxf(0.0, (root_insets.x - canvas.position.x) / per_unit.x)
	var top := maxf(0.0, (root_insets.y - canvas.position.y) / per_unit.y)
	var right := maxf(0.0, (root_insets.z - (ui.x - canvas.end.x)) / per_unit.x)
	var bottom := maxf(0.0, (root_insets.w - (ui.y - canvas.end.y)) / per_unit.y)
	return Vector4(left, top, right, bottom)


## Insets for the live window (zero headless / on desktop).
static func safe_layer_insets(win: Window) -> Vector4:
	var size := win.size if win != null else UI_SIZE
	return layer_insets(TouchInput.safe_insets_ui(win), size)


static func apply_layer(layer: CanvasLayer) -> void:
	if not is_instance_valid(layer) or not layer.is_inside_tree():
		return
	layer.transform = for_window(layer.get_tree().root)["ui_transform"]


static func bind_layer(layer: CanvasLayer) -> void:
	if layer == null or not layer.is_inside_tree() or layer.has_meta("presentation_bound"):
		return
	layer.set_meta("presentation_bound", true)
	layer.add_child(LayerBinding.new())
	apply_layer(layer)


## Root-window Control UI (the title screen is a plain scene Control, not a
## CanvasLayer) sits inside the same centred integer content rectangle as the
## world image and every bound CanvasLayer. Without this it would stretch over
## the letterbox at non-16:9 windows while the in-game UI stayed inset.
static func apply_control(control: Control, win: Window = null) -> void:
	if not is_instance_valid(control):
		return
	var root := win if is_instance_valid(win) else _root_window()
	var transform: Transform2D = for_window(root)["ui_transform"]
	# Control 没有 CanvasItem.transform：把内容矩形的位移 / 缩放拆到
	# position / scale / rotation（当前变换只有位移与统一缩放）。
	control.position = transform.origin
	control.scale = transform.get_scale()
	control.rotation = transform.get_rotation()


static func bind_control(control: Control) -> void:
	if control == null or not control.is_inside_tree() or control.has_meta("presentation_control_bound"):
		return
	control.set_meta("presentation_control_bound", true)
	control.add_child(ControlBinding.new())
	apply_control(control)


static func _root_window() -> Window:
	var loop := Engine.get_main_loop()
	return (loop as SceneTree).root if loop is SceneTree else null


class LayerBinding extends Node:
	func _ready() -> void:
		get_tree().root.size_changed.connect(_refresh)


	func _refresh() -> void:
		PresentationMetrics.apply_layer(get_parent() as CanvasLayer)


class ControlBinding extends Node:
	func _ready() -> void:
		get_tree().root.size_changed.connect(_refresh)


	func _refresh() -> void:
		PresentationMetrics.apply_control(get_parent() as Control)
