extends Node2D
## Low-resolution 3D render target presented as an integer-scaled
## nearest-neighbour image. The camera moves in whole texels; the leftover
## sub-texel offset is applied here by moving the image in whole physical
## pixels, so scrolling stays smooth while every texel keeps its square shape.
##
## Placement is done with Node2D maths on the root canvas instead of Controls:
## Control positions are rounded in 1280x720 canvas units, which would break
## physical-pixel alignment at fractional window scales.

const POST_SHADER := preload("res://assets/shaders/moba/pixel_post.gdshader")
const KIT := preload("res://scripts/moba/view/toon_kit.gd")
## Extra texels rendered on every side so the sub-texel shift never exposes an edge.
const MARGIN := 2
const HEIGHT_PRESETS: Array[int] = [360, 270, 432]

signal layout_changed

var viewport: SubViewport
var world: Node3D
var image: Sprite2D
## Target texel rows; the real height is ceil(window / scale), so it can be a little taller.
var base_height := 360
## true: cover the whole window (width follows the aspect ratio); false: 16:9 with black bars.
var fill_screen := true
var subpixel_enabled := true
var pixel_scale := 1
var internal_size := Vector2i(640, 360)

var _mask: LetterboxMask
var _post: ShaderMaterial
var _subpixel := Vector2.ZERO
var _origin := Vector2.ZERO
var _root_scale := Vector2.ONE


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.name = "World3DViewport"
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.size = internal_size + Vector2i(MARGIN, MARGIN) * 2
	add_child(viewport)
	world = Node3D.new()
	world.name = "World"
	viewport.add_child(world)
	_post = ShaderMaterial.new()
	_post.shader = POST_SHADER
	var palette := KIT.palette_texture()
	_post.set_shader_parameter("palette_tex", palette)
	_post.set_shader_parameter("palette_size", palette.get_width())
	image = Sprite2D.new()
	image.name = "WorldImage"
	image.centered = false
	image.texture = viewport.get_texture()
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	image.material = _post
	add_child(image)
	_mask = LetterboxMask.new()
	_mask.name = "Letterbox"
	add_child(_mask)
	get_tree().root.size_changed.connect(relayout)
	relayout()


func relayout() -> void:
	var win := get_tree().root
	var phys := Vector2(maxi(win.size.x, 1), maxi(win.size.y, 1))
	_root_scale = _canvas_scale(win, phys)
	var base_width := int(round(base_height * 16.0 / 9.0))
	if fill_screen:
		pixel_scale = maxi(1, floori(phys.y / float(base_height)))
		internal_size = Vector2i(ceili(phys.x / pixel_scale), ceili(phys.y / pixel_scale))
		internal_size += Vector2i(internal_size.x & 1, internal_size.y & 1)
	else:
		pixel_scale = maxi(1, floori(minf(phys.x / float(base_width), phys.y / float(base_height))))
		internal_size = Vector2i(base_width, base_height)
	var shown := Vector2(internal_size * pixel_scale)
	_origin = ((phys - shown) * 0.5).floor()
	var target := internal_size + Vector2i(MARGIN, MARGIN) * 2
	if viewport.size != target:
		viewport.size = target
	image.scale = Vector2(pixel_scale, pixel_scale) / _root_scale
	_post.set_shader_parameter("source_size", Vector2(target))
	_mask.rects = _letterbox_rects(phys, shown)
	_mask.queue_redraw()
	_place_image()
	layout_changed.emit()


func cycle_base_height() -> void:
	var i := HEIGHT_PRESETS.find(base_height)
	base_height = HEIGHT_PRESETS[(i + 1) % HEIGHT_PRESETS.size()]
	relayout()


func set_fill_screen(on: bool) -> void:
	fill_screen = on
	relayout()


## `subpixel`: how far (in texels, x right / y down) the snapped camera image
## must move to show the unsnapped view. `texel`: the camera's whole-texel
## position, used to pin the dither pattern to the world.
func set_camera_offset(subpixel: Vector2, texel: Vector2i) -> void:
	_subpixel = subpixel
	_post.set_shader_parameter("texel_origin", Vector2(posmod(texel.x, 4), posmod(texel.y, 4)))
	_place_image()


func set_subpixel(on: bool) -> void:
	subpixel_enabled = on
	_place_image()


func set_palette(on: bool) -> void:
	_post.set_shader_parameter("palette_on", on)


func set_dither(strength: float) -> void:
	_post.set_shader_parameter("dither_strength", strength)


## Transform for a CanvasLayer drawn over the whole window in uniform units,
## with the window always `rows` units tall. The root canvas stretches each
## axis separately, so layers bound to the 16:9 content rect would sit inset
## from the edges of a full-window image.
func overlay_transform(rows: float = 720.0) -> Transform2D:
	var unit := float(maxi(get_tree().root.size.y, 1)) / rows
	return Transform2D(0.0, Vector2(unit, unit) / _root_scale, 0.0, Vector2.ZERO)


func render_info() -> Dictionary:
	return {
		"draws": viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"shadow_draws": viewport.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"objects": viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_OBJECTS_IN_FRAME),
		"primitives": viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
	}


## Saves the raw low-resolution frame and the final window; returns absolute paths.
func capture(dir: String) -> PackedStringArray:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var low := "%s/%s_lowres.png" % [dir, stamp]
	var full := "%s/%s_window.png" % [dir, stamp]
	viewport.get_texture().get_image().save_png(low)
	get_viewport().get_texture().get_image().save_png(full)
	return PackedStringArray([ProjectSettings.globalize_path(low), ProjectSettings.globalize_path(full)])


func _place_image() -> void:
	var q := _subpixel if subpixel_enabled else Vector2.ZERO
	var shift := Vector2(roundf(q.x * pixel_scale), roundf(q.y * pixel_scale))
	var top_left := _origin - Vector2(MARGIN, MARGIN) * pixel_scale - shift
	image.position = top_left / _root_scale


func _letterbox_rects(phys: Vector2, shown: Vector2) -> Array[Rect2]:
	var left := maxf(_origin.x, 0.0)
	var top := maxf(_origin.y, 0.0)
	var right := minf(_origin.x + shown.x, phys.x)
	var bottom := minf(_origin.y + shown.y, phys.y)
	var physical: Array[Rect2] = []
	if left > 0.0:
		physical.append(Rect2(0.0, 0.0, left, phys.y))
	if right < phys.x:
		physical.append(Rect2(right, 0.0, phys.x - right, phys.y))
	if top > 0.0:
		physical.append(Rect2(left, 0.0, right - left, top))
	if bottom < phys.y:
		physical.append(Rect2(left, bottom, right - left, phys.y - bottom))
	var rects: Array[Rect2] = []
	for rect in physical:
		rects.append(Rect2(rect.position / _root_scale, rect.size / _root_scale))
	return rects


## Root canvas units per physical pixel. DisplayFit keeps the root in
## canvas_items + ignore-aspect mode, so each axis scales independently.
static func _canvas_scale(win: Window, phys: Vector2) -> Vector2:
	if win.content_scale_mode == Window.CONTENT_SCALE_MODE_DISABLED:
		return Vector2.ONE
	var content := Vector2(win.content_scale_size)
	if content.x <= 0.0 or content.y <= 0.0:
		return Vector2.ONE
	return phys / content


class LetterboxMask extends Node2D:
	var rects: Array[Rect2] = []


	func _draw() -> void:
		for rect in rects:
			draw_rect(rect, Color.BLACK)
