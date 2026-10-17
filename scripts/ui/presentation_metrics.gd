class_name PresentationMetrics
extends RefCounted
## Physical integer world pixels; UI remains vector/font drawing in the root canvas.

const WORLD_SIZE := Vector2i(640, 360)
const UI_SIZE := Vector2i(1280, 720)


static func calculate(window_size: Vector2i) -> Dictionary:
	var physical := Vector2(maxi(window_size.x, 640), maxi(window_size.y, 360))
	var integer_scale := maxi(1, int(floor(minf(physical.x / 640.0, physical.y / 360.0))))
	var content_size := Vector2(WORLD_SIZE) * integer_scale
	var origin := ((physical - content_size) * 0.5).floor()
	# The native root stretches per axis. Compensate here so Godot never rounds
	# an aspect-preserved render target (1366x768 otherwise becomes 1365x768).
	var root_scale := physical / Vector2(UI_SIZE)
	var canvas_origin := origin / root_scale
	var ui_scale := float(integer_scale) * 0.5
	return {
		"scale": integer_scale,
		"physical_rect": Rect2(origin, content_size),
		"canvas_rect": Rect2(canvas_origin, content_size / root_scale),
		"ui_transform": Transform2D(0.0, Vector2.ONE * ui_scale / root_scale, 0.0, canvas_origin),
	}


static func for_window(win: Window) -> Dictionary:
	return calculate(win.size if win != null else UI_SIZE)


## Safe-area insets measured on the root canvas (left, top, right, bottom in 1280x720
## units, as TouchInput.safe_insets_ui reports them) -> insets inside a layer bound
## by `bind_layer`. Layer space is the centred integer content rectangle, so a notch
## that lies in the black margin costs nothing and a window with no margin keeps the
## full inset. Pure function: unit-testable without a display.
static func layer_insets(root_insets: Vector4, window_size: Vector2i) -> Vector4:
	if root_insets == Vector4.ZERO:
		return Vector4.ZERO
	var metrics := calculate(window_size)
	var canvas: Rect2 = metrics["canvas_rect"]
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


class LayerBinding extends Node:
	func _ready() -> void:
		get_tree().root.size_changed.connect(_refresh)


	func _refresh() -> void:
		PresentationMetrics.apply_layer(get_parent() as CanvasLayer)
