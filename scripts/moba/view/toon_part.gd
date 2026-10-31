extends MeshInstance3D
## A rigid group of primitive shapes merged into one vertex-coloured mesh (one
## draw call), plus an inverted-hull outline child. The hull is rebuilt whenever
## the world size of one render texel changes so outlines stay one texel wide.

const KIT := preload("res://scripts/moba/view/toon_kit.gd")
const GROUP := &"moba_toon_part"

static var hulls_visible := true
static var outline_width := 0.045

var outline_color := KIT.OUTLINE_COLOR
var hull: MeshInstance3D
var _shapes: Array[Dictionary] = []


func _init() -> void:
	add_to_group(GROUP)


func box(size: Vector3, pos: Vector3, color: Color, rot_deg := Vector3.ZERO, flags := 0) -> void:
	_shapes.append({"kind": "box", "size": size, "xf": _xf(pos, rot_deg), "color": color, "flags": flags, "flat": false})


func cylinder(bottom: float, top: float, height: float, pos: Vector3, color: Color, sides := 8, rot_deg := Vector3.ZERO, flags := 0) -> void:
	_shapes.append({
		"kind": "cylinder", "bottom": bottom, "top": top, "height": height, "sides": sides,
		"xf": _xf(pos, rot_deg), "color": color, "flags": flags, "flat": true,
	})


func sphere(radius: float, height: float, pos: Vector3, color: Color, segments := 6, rings := 3, rot_deg := Vector3.ZERO, flags := 0) -> void:
	_shapes.append({
		"kind": "sphere", "radius": radius, "height": height, "segments": segments, "rings": rings,
		"xf": _xf(pos, rot_deg), "color": color, "flags": flags, "flat": true,
	})


## Triangle prism with its apex on +Y; depth runs along local Z.
func prism(size: Vector3, pos: Vector3, color: Color, rot_deg := Vector3.ZERO, flags := 0) -> void:
	_shapes.append({"kind": "prism", "size": size, "xf": _xf(pos, rot_deg), "color": color, "flags": flags, "flat": true})


func build() -> void:
	var body = KIT.MeshBuilder.new()
	for shape in _shapes:
		var color := KIT.vertex_color(shape["color"], int(shape["flags"]))
		body.add(KIT.shape_arrays(shape, 0.0), shape["xf"], color, bool(shape["flat"]))
	mesh = body.commit()
	if material_override == null:
		material_override = KIT.toon_material()
	rebuild_hull(outline_width)


func rebuild_hull(width: float) -> void:
	var shell = KIT.MeshBuilder.new()
	if width > 0.0:
		for shape in _shapes:
			if int(shape["flags"]) & KIT.NO_OUTLINE:
				continue
			shell.add(KIT.shape_arrays(shape, width), shape["xf"], Color.WHITE, false)
	if shell.is_empty():
		if hull != null:
			hull.queue_free()
			hull = null
		return
	if hull == null:
		hull = MeshInstance3D.new()
		hull.name = "Hull"
		hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(hull)
	hull.mesh = shell.commit()
	hull.material_override = KIT.hull_material(outline_color)
	hull.visible = hulls_visible


func set_hull_visible(on: bool) -> void:
	if hull != null:
		hull.visible = on


static func refresh_all(tree: SceneTree, width: float) -> void:
	outline_width = width
	tree.call_group(GROUP, "rebuild_hull", width)


static func show_hulls(tree: SceneTree, on: bool) -> void:
	hulls_visible = on
	tree.call_group(GROUP, "set_hull_visible", on)


static func _xf(pos: Vector3, rot_deg: Vector3) -> Transform3D:
	var rot := Basis.from_euler(Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)))
	return Transform3D(rot, pos)
