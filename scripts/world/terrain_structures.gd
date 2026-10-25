extends RefCounted
## Raised walkways are carried the way their chapter would really build them
## (docs/terrain-structures.md). Scale: 16 px ≈ 1 m; the knight stands ≈ 1.7 m.
##
## · Load path: every pier, column and leg stands on the first solid top below
##   it — the floor, a pit bed, or the deck underneath — never on air.
## · Members stay inside what a builder trusts for the material: masonry bays
##   of 4–6 m with piers at least 1/8 of their height, steel bents up to 9 m
##   and braced once a column passes 2.5 m, rock pillars at least 1/5 of
##   their height. Arches rise as their geometry demands; where the headroom
##   cannot take a full arch the bay turns segmental, then to a flat lintel.
## · Rear members stand in the depth plane behind the walkway and never
##   collide; low steps without standing room get a solid, colliding plinth.
## · Hoists hang from the structure right above their highest stop, or from a
##   headframe of their own when another deck or hoist is in the way. Their
##   decks are planks or tread plate, not stone slabs on a rope.

const KIT := preload("res://scripts/world/structure_kit.gd")
const SKETCH := preload("res://scripts/world/structure_sketch.gd")

const QUEUED := &"terrain_structure_queued"
const BUILT := &"terrain_structure_built"
const GENERATED := &"terrain_structure_generated"
const MAX_PLINTH_GAP := 20.0
const FOUNDED_Y := 384.0
## Camera floor: anything reaching it is founded below the visible world.
const BEDROCK_Y := 400.0
## Rear members sit one depth plane behind the deck they carry.
const REAR := Color(0.66, 0.66, 0.72)
## Members are laid out from 3 px above the deck underside so they tuck under
## ragged ledge skins instead of leaving a lit seam.
const TUCK := 3.0
## Arch ring depth and the masonry kept over its crown.
const RING := 3.0
const CROWN := 2.0
## Two-centred pointed arch: radius as a fraction of the span (rise ≈ 0.71 span).
const POINTED := 0.75
## Clear space a rider needs over a hoist's highest stop before the hoist gear.
const HOIST_HEADROOM := 48.0
## Longer falls of rope read as clutter; such hoists get their own headframe.
const MAX_ROPE := 480.0
const LEG := 6.0

const SYSTEMS := {
	"stone": {"name": "masonry_arcade", "arch": "round", "max_span": 96.0, "min_pier": 12.0, "slender": 8.0},
	"moss": {"name": "masonry_arcade", "arch": "round", "max_span": 80.0, "min_pier": 12.0, "slender": 8.0},
	"brick": {"name": "masonry_arcade", "arch": "round", "max_span": 80.0, "min_pier": 12.0, "slender": 8.0},
	"nave": {"name": "gothic_arcade", "arch": "pointed", "max_span": 80.0, "min_pier": 10.0, "slender": 10.0},
	"castle": {"name": "gothic_arcade", "arch": "pointed", "max_span": 80.0, "min_pier": 12.0, "slender": 8.0},
	"rampart": {"name": "buttressed_arcade", "arch": "round", "max_span": 64.0, "min_pier": 16.0, "slender": 6.0},
	"iron": {"name": "steel_frame", "max_span": 144.0, "min_pier": LEG},
	"basalt": {"name": "rock_pillar", "max_span": 96.0, "min_pier": 14.0, "slender": 5.0},
}
## Hoist spans between legs, by material.
const HOIST_SPAN := {KIT.STEEL: 144.0, KIT.TIMBER: 96.0}


static func request(source: Node) -> void:
	if source.has_meta(GENERATED):
		return
	var host := source.get_parent()
	while host != null and not host.is_in_group(&"game_world"):
		host = host.get_parent()
	if host == null or host.has_meta(QUEUED) or host.has_meta(BUILT):
		return
	host.set_meta(QUEUED, true)
	if host.is_node_ready():
		_build_queued.call_deferred(weakref(host))
	else:
		host.ready.connect(build.bind(host), CONNECT_ONE_SHOT)


## A level freed in the frame it was built (tests, scene swaps) is skipped.
static func _build_queued(ref: WeakRef) -> void:
	var host := ref.get_ref() as Node2D
	if host != null:
		build(host)


static func build(host: Node2D) -> void:
	if host.has_meta(BUILT):
		return
	host.set_meta(BUILT, true)
	var bodies: Array[Node] = []
	_collect(host, bodies)
	var bearings := _bearings(bodies)
	var family := _dominant_family(bodies)
	var hoist := KIT.STEEL if family in ["iron", "basalt"] else KIT.TIMBER
	for body in bodies:
		if body is MovingPlatform:
			_hoist(body as MovingPlatform, host, bodies, bearings, hoist, family)
		elif body is SolidPlatform:
			var p := body as SolidPlatform
			if p.size.x <= 20.0 or String(p.name).begins_with("Ceiling"):
				continue
			var bounds := Rect2(p.global_position, p.size)
			if bounds.end.y >= FOUNDED_Y or _rests_on_body(bounds, bodies, p) or _embedded(bounds, bearings):
				p.set_meta(&"structure_kind", "foundation")
				continue
			_support(p, bounds, _family(p.skin), p.tone, bearings, not (p is CollapsingPlatform))
		elif body is GearPlatform:
			var g := body as GearPlatform
			var block := DensityTextures.load_texture(String(g._block_choice()[0]))
			var visible_height := block.get_height() * (g.radius * 2.0 / block.get_width())
			var bounds := Rect2(g.global_position - Vector2(g.radius, 0.92 * g.radius), Vector2(g.radius * 2.0, visible_height))
			_support(g, bounds, _family(g.family), Color.WHITE, bearings, false)


static func system_for(family: String) -> Dictionary:
	return SYSTEMS.get(family, SYSTEMS["stone"])


static func _collect(node: Node, out: Array[Node]) -> void:
	for child in node.get_children():
		if child.has_meta(GENERATED):
			continue
		if child is SolidPlatform or child is MovingPlatform or child is GearPlatform:
			out.append(child)
		_collect(child, out)


## Tops that can take a load: fixed solid terrain, not decks that fall, run or retract.
static func _bearings(bodies: Array[Node]) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for body in bodies:
		if not (body is SolidPlatform) or body is CollapsingPlatform or body is ConveyorBelt:
			continue
		var p := body as SolidPlatform
		if p.size.x > 20.0 and not String(p.name).begins_with("Ceiling"):
			out.append(Rect2(p.global_position, p.size))
	return out


static func _dominant_family(bodies: Array[Node]) -> String:
	var weight := {}
	for body in bodies:
		if body is SolidPlatform:
			var p := body as SolidPlatform
			var f := _family(p.skin)
			weight[f] = float(weight.get(f, 0.0)) + p.size.x
	var best := "stone"
	var most := -1.0
	for f in weight:
		if float(weight[f]) > most:
			most = float(weight[f])
			best = String(f)
	return best


static func _rests_on_body(rect: Rect2, bodies: Array[Node], source: Node) -> bool:
	for body in bodies:
		if body == source or not (body is SolidPlatform) or body is CollapsingPlatform:
			continue
		var p := body as SolidPlatform
		var other := Rect2(p.global_position, p.size)
		if absf(rect.end.y - other.position.y) <= 1.0 and other.position.x <= rect.position.x + 1.0 and other.end.x >= rect.end.x - 1.0:
			return true
	return false


## Bedded into the ground it stands on (a grave mound sunk into the floor).
static func _embedded(rect: Rect2, bearings: Array[Rect2]) -> bool:
	var probe := Vector2(rect.get_center().x, rect.end.y - 0.5)
	for other in bearings:
		if other != rect and other.position.y < rect.end.y - 1.0 and other.has_point(probe):
			return true
	return false


static func _family(skin: String) -> String:
	if skin in ["auto", "floating", "ground", "stone", ""]:
		return "stone"
	return skin.trim_suffix("_float")


## First solid top at or below `below` under x.
static func _bearing_y(x: float, below: float, bearings: Array[Rect2]) -> float:
	var result := BEDROCK_Y
	for rect in bearings:
		if x >= rect.position.x and x <= rect.end.x and rect.position.y >= below - 1.0:
			result = minf(result, rect.position.y)
	return maxf(below, result)


## Shortest and tallest drop from the deck underside to its bearing, sampled across it.
static func _clearances(bounds: Rect2, bearings: Array[Rect2]) -> Vector2:
	var low := INF
	var high := 0.0
	for k in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var x := lerpf(bounds.position.x + 2.0, bounds.end.x - 2.0, k)
		var gap := _bearing_y(x, bounds.end.y, bearings) - bounds.end.y
		low = minf(low, gap)
		high = maxf(high, gap)
	return Vector2(low, high)


## Pier width for a height: no slimmer than the material allows (rounded up to
## even pixels), never wider than `cap` or 2 m.
static func _section(spec: Dictionary, height: float, cap: float) -> float:
	var need := maxf(float(spec["min_pier"]), height / float(spec.get("slender", 1000.0)))
	return minf(ceilf(need * 0.5) * 2.0, minf(cap, 32.0))


## Left edges of the supports: first flush left, last flush right, whole pixels.
static func _stations(width: float, member: float, bays: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var pitch := (width - member) / float(bays)
	for i in bays + 1:
		out.append(roundf(i * pitch))
	return out


static func _support(body: Node2D, bounds: Rect2, family: String, tone: Color,
		bearings: Array[Rect2], can_fill: bool) -> void:
	var foot := _bearing_y(bounds.get_center().x, bounds.end.y, bearings)
	var gap := foot - bounds.end.y
	if gap <= 0.5:
		body.set_meta(&"structure_kind", "foundation")
		return
	# Fill only spaces too short for a standing body, and only above a real floor.
	var whole_floor := false
	for rect in bearings:
		if absf(rect.position.y - foot) < 1.0 and rect.position.x <= bounds.position.x and rect.end.x >= bounds.end.x:
			whole_floor = true
	if can_fill and whole_floor and gap <= MAX_PLINTH_GAP:
		var plinth := SolidPlatform.new()
		plinth.name = "MasonryPlinth"
		plinth.set_meta(GENERATED, true)
		plinth.set_meta("non_walkable", true)
		plinth.position = body.to_local(bounds.position + Vector2(0, bounds.size.y))
		plinth.size = Vector2(bounds.size.x, gap)
		plinth.skin = family
		plinth.cap_surface = false
		plinth.tone = tone
		body.add_child(plinth)
		body.set_meta(&"structure_kind", "solid_plinth")
		return
	var sketch: SKETCH = SKETCH.new()
	sketch.name = "RearSupport"
	sketch.set_meta(GENERATED, true)
	sketch.z_index = -3
	# Fragile decks fall away from their permanent supports.
	if body is CollapsingPlatform:
		body.get_parent().add_child(sketch)
	else:
		body.add_child(sketch)
	sketch.global_position = Vector2(bounds.position.x, bounds.end.y - TUCK)
	var spec := system_for(family)
	var report: Dictionary
	match String(spec["name"]):
		"steel_frame":
			report = _steel_frame(sketch, bounds, spec, family, tone, bearings)
		"rock_pillar":
			report = _rock_pillars(sketch, bounds, spec, family, tone, bearings)
		_:
			report = _arcade(sketch, bounds, spec, family, tone, bearings)
	body.set_meta(&"structure_kind", "rear_support")
	body.set_meta(&"structure_system", report["system"])
	body.set_meta(&"structure_arch", report.get("arch", ""))
	body.set_meta(&"structure_spans", report["spans"])
	body.set_meta(&"structure_piers", report["piers"])
	body.set_meta(&"structure_braced", report.get("braced", false))
	body.set_meta(&"structure_foot_y", foot)


## ------------------------------------------------------------- masonry --

static func _arcade(sk: SKETCH, bounds: Rect2, spec: Dictionary, family: String, tone: Color,
		bearings: Array[Rect2]) -> Dictionary:
	var width := bounds.size.x
	var under := bounds.end.y
	var tex := KIT.masonry(family)
	var shade := tone * REAR
	var dressed := shade * Color(1.2, 1.2, 1.18)
	var joint := shade * Color(0.5, 0.5, 0.56)
	var heights := _clearances(bounds, bearings)
	var pier := _section(spec, heights.y, 32.0)
	if width < pier * 2.0 + 24.0:
		return _corbelled(sk, bounds, spec, tex, shade, dressed, joint, bearings, heights.y)
	var bays := maxi(1, ceili((width - pier) / (float(spec["max_span"]) + pier)))
	var arch := ""
	for n in range(bays, bays + 6):
		var clear := (width - pier) / n - pier
		if clear < 16.0:
			break
		if _rise(String(spec["arch"]), clear) + _crown_y() <= heights.x * 0.6:
			bays = n
			arch = String(spec["arch"])
			break
	if arch == "":
		var clear := (width - pier) / bays - pier
		arch = "segmental" if _rise("segmental", clear) + _crown_y() <= heights.x * 0.8 else "lintel"
	var xs := _stations(width, pier, bays)
	var spans := PackedFloat32Array()
	for i in bays:
		spans.append(xs[i + 1] - xs[i] - pier)
		_bay(sk, arch, xs[i] + pier, xs[i + 1], tex, shade, dressed, joint)
	var spring := _crown_y() + _rise(arch, spans[0]) if arch != "lintel" else TUCK + 10.0
	if arch == "lintel":
		sk.strip(Rect2(0, 0, width, TUCK + 6.0), tex, dressed)
		sk.lines(PackedVector2Array([Vector2(0, TUCK + 6.0), Vector2(width, TUCK + 6.0)]), joint, 0.5)
	var piers: Array[Rect2] = []
	for x in xs:
		var foot := _bearing_y(bounds.position.x + x + pier * 0.5, under, bearings)
		var f := foot - under + TUCK
		piers.append(Rect2(bounds.position.x + x, under, pier, foot - under))
		match String(spec["name"]):
			"gothic_arcade":
				_column(sk, x, pier, f, spring, tex, shade, dressed, joint)
			"buttressed_arcade":
				_buttress(sk, x, pier, f, spring, tex, shade, dressed, arch != "lintel")
			_:
				_pier(sk, x, pier, f, spring, tex, shade, dressed, arch != "lintel")
	return {"system": spec["name"], "arch": arch, "spans": spans, "piers": piers}


## A deck too narrow for an arcade sits on one pier, corbelled out course by
## course; each course oversails the one below by no more than its own height.
static func _corbelled(sk: SKETCH, bounds: Rect2, spec: Dictionary, tex: Texture2D, shade: Color,
		dressed: Color, joint: Color, bearings: Array[Rect2], tallest: float) -> Dictionary:
	var width := bounds.size.x
	var pier := _section(spec, tallest, width)
	var x := roundf((width - pier) * 0.5)
	var foot := _bearing_y(bounds.position.x + width * 0.5, bounds.end.y, bearings)
	var f := foot - bounds.end.y + TUCK
	var courses := clampi(int((width - 2.0 - pier) / 6.0), 0, 4)
	sk.strip(Rect2(x, 0, pier, f), tex, shade)
	sk.strip(Rect2(x - 2.0, f - 4.0, pier + 4.0, 4.0), tex, dressed)
	var seams := PackedVector2Array()
	for k in courses:
		var out := 3.0 * float(courses - k)
		var y := 0.0 if k == 0 else TUCK + 3.0 * k
		var h := TUCK + 3.0 if k == 0 else 3.0
		sk.strip(Rect2(x - out, y, pier + out * 2.0, h), tex, dressed if k == 0 else shade * Color(1.1, 1.1, 1.08))
		seams.append(Vector2(x - out, y + h))
		seams.append(Vector2(x + pier + out, y + h))
	sk.lines(seams, joint, 0.5)
	return {"system": spec["name"], "arch": "corbel", "spans": PackedFloat32Array(),
			"piers": [Rect2(bounds.position.x + x, bounds.end.y, pier, foot - bounds.end.y)],
			"cantilever": (width - pier) * 0.5 - 3.0 * courses}


static func _crown_y() -> float:
	return TUCK + CROWN + RING


static func _rise(kind: String, span: float) -> float:
	match kind:
		"round":
			return span * 0.5
		"pointed":
			var r := span * POINTED
			return sqrt(r * r - pow(r - span * 0.5, 2.0))
		"segmental":
			return maxf(3.0, span / 6.0)
	return 0.0


## Intrados from the left springer to the right one, with outward normals.
static func _intrados(kind: String, xl: float, xr: float, spring: float) -> Array:
	var span := xr - xl
	var points := PackedVector2Array()
	var normals := PackedVector2Array()
	var steps := maxi(8, int(span / 3.0))
	if kind == "pointed":
		var r := span * POINTED
		var crown := acos((span * 0.5 - r) / r)
		var half := maxi(4, int(steps * 0.5))
		for i in half + 1:
			var a := lerpf(PI, crown, float(i) / half)
			var n := Vector2(cos(a), -sin(a))
			points.append(Vector2(xl + r, spring) + n * r)
			normals.append(n)
		for i in range(1, half + 1):
			var a := lerpf(PI - crown, 0.0, float(i) / half)
			var n := Vector2(cos(a), -sin(a))
			points.append(Vector2(xr - r, spring) + n * r)
			normals.append(n)
		return [points, normals]
	var rise := _rise(kind, span)
	var r := (span * span * 0.25 + rise * rise) / (2.0 * rise)
	var centre := Vector2((xl + xr) * 0.5, spring - rise + r)
	var sweep := asin(clampf(span * 0.5 / r, -1.0, 1.0))
	for i in steps + 1:
		var t := lerpf(-sweep, sweep, float(i) / steps)
		var n := Vector2(sin(t), -cos(t))
		points.append(centre + n * r)
		normals.append(n)
	return [points, normals]


## Spandrel, voussoir ring with radiating joints, and a keystone on round work.
static func _bay(sk: SKETCH, kind: String, xl: float, xr: float, tex: Texture2D, shade: Color,
		dressed: Color, joint: Color) -> void:
	if kind == "lintel":
		return
	var curve := _intrados(kind, xl, xr, _crown_y() + _rise(kind, xr - xl))
	var points: PackedVector2Array = curve[0]
	var normals: PackedVector2Array = curve[1]
	var spandrel := PackedVector2Array([Vector2(xl, 0), Vector2(xr, 0)])
	for i in range(points.size() - 1, -1, -1):
		spandrel.append(points[i])
	sk.polygon(spandrel, tex, shade)
	var ring := PackedVector2Array()
	for i in points.size():
		ring.append(points[i] + normals[i] * RING)
	for i in range(points.size() - 1, -1, -1):
		ring.append(points[i])
	sk.polygon(ring, tex, dressed)
	var joints := PackedVector2Array()
	var run := 0.0
	for i in range(1, points.size() - 1):
		run += points[i].distance_to(points[i - 1])
		if run >= 4.5:
			run = 0.0
			joints.append(points[i])
			joints.append(points[i] + normals[i] * RING)
	sk.lines(joints, joint, 0.5)
	if kind != "pointed":
		var mid := int(points.size() * 0.5)
		var c := points[mid]
		var n := normals[mid]
		var t := Vector2(-n.y, n.x)
		sk.polygon(PackedVector2Array([c - t * 2.0, c + t * 2.0, c + t * 2.6 + n * (RING + 1.5),
				c - t * 2.6 + n * (RING + 1.5)]), tex, dressed * Color(1.08, 1.08, 1.06))


## Square pier: footing course, impost at the springing.
static func _pier(sk: SKETCH, x: float, w: float, f: float, spring: float, tex: Texture2D,
		shade: Color, dressed: Color, impost: bool) -> void:
	sk.strip(Rect2(x, 0, w, f), tex, shade)
	sk.strip(Rect2(x - 2.0, f - 4.0, w + 4.0, 4.0), tex, dressed)
	if impost:
		sk.strip(Rect2(x - 1.5, spring - 2.0, w + 3.0, 3.0), tex, dressed)


## Round shaft with a bell capital, abacus, torus and plinth.
static func _column(sk: SKETCH, x: float, w: float, f: float, spring: float, tex: Texture2D,
		shade: Color, dressed: Color, joint: Color) -> void:
	sk.strip(Rect2(x, 0, w, f), tex, shade)
	sk.lines(PackedVector2Array([Vector2(x + w * 0.5, spring + 2.0), Vector2(x + w * 0.5, f - 6.0)]), joint, 0.5)
	sk.polygon(PackedVector2Array([Vector2(x - 3.0, spring - 4.0), Vector2(x + w + 3.0, spring - 4.0),
			Vector2(x + w, spring + 1.0), Vector2(x, spring + 1.0)]), tex, dressed)
	sk.strip(Rect2(x - 3.5, spring - 5.5, w + 7.0, 1.5), tex, dressed * Color(1.06, 1.06, 1.04))
	sk.strip(Rect2(x - 1.5, f - 5.0, w + 3.0, 2.0), tex, dressed)
	sk.strip(Rect2(x - 3.0, f - 3.0, w + 6.0, 3.0), tex, dressed)


## Wall-walk pier: battered faces (1 in 12), a set-off halfway, a spread footing.
static func _buttress(sk: SKETCH, x: float, w: float, f: float, spring: float, tex: Texture2D,
		shade: Color, dressed: Color, impost: bool) -> void:
	var b := clampf(f / 12.0, 1.0, 8.0)
	sk.polygon(PackedVector2Array([Vector2(x, 0), Vector2(x + w, 0), Vector2(x + w + b, f),
			Vector2(x - b, f)]), tex, shade)
	var m := f * 0.55
	var mb := b * 0.55
	sk.strip(Rect2(x - mb - 1.0, m, w + mb * 2.0 + 2.0, 2.5), tex, dressed)
	sk.strip(Rect2(x - b - 2.0, f - 3.0, w + b * 2.0 + 4.0, 3.0), tex, dressed)
	if impost:
		sk.strip(Rect2(x - 1.5, spring - 2.0, w + 3.0, 3.0), tex, dressed)


## --------------------------------------------------------------- steel --

## Bolted bents: plate girder under the deck, I-columns on base plates and
## concrete pads, X-bracing in the end bays once columns pass 40 px (2.5 m),
## knee braces elsewhere.
static func _steel_frame(sk: SKETCH, bounds: Rect2, spec: Dictionary, family: String, tone: Color,
		bearings: Array[Rect2]) -> Dictionary:
	var width := bounds.size.x
	var under := bounds.end.y
	var shade := tone * REAR
	var flat := KIT.flat(family)
	var plate: Color = KIT.steel_colors(family)["dark"]
	var girder_top := TUCK - 1.0
	var girder_bottom := girder_top + 6.0
	sk.strip(Rect2(0, girder_top, width, 6.0), KIT.girder(family), shade)
	var xs: PackedFloat32Array
	if width < 40.0:
		xs = PackedFloat32Array([roundf((width - LEG) * 0.5)])
	else:
		xs = _stations(width, LEG, maxi(1, ceili((width - LEG) / float(spec["max_span"]))))
	var feet := PackedFloat32Array()
	var piers: Array[Rect2] = []
	for x in xs:
		var foot := _bearing_y(bounds.position.x + x + LEG * 0.5, under, bearings)
		var f := foot - under + TUCK
		feet.append(f)
		piers.append(Rect2(bounds.position.x + x, under, LEG, foot - under))
		sk.strip(Rect2(x - 4.0, f - 3.0, LEG + 8.0, 3.0), KIT.concrete(), shade)
		sk.strip(Rect2(x - 2.0, f - 4.5, LEG + 4.0, 1.5), null, plate * shade)
		sk.strip(Rect2(x, girder_bottom, LEG, f - 4.5 - girder_bottom), KIT.column(family), shade)
	var spans := PackedFloat32Array()
	var braced := false
	if xs.size() == 1:
		var h := feet[0] - 4.5 - girder_bottom
		var kb := clampf(minf(width * 0.5 - LEG * 0.5 - 2.0, h * 0.5), 3.0, 12.0)
		if h > 8.0:
			sk.bar(Vector2(xs[0], girder_bottom + kb), Vector2(xs[0] - kb, girder_bottom), 2.0, flat, shade)
			sk.bar(Vector2(xs[0] + LEG, girder_bottom + kb), Vector2(xs[0] + LEG + kb, girder_bottom), 2.0, flat, shade)
			braced = true
	for i in xs.size() - 1:
		var a := xs[i] + LEG
		var b := xs[i + 1]
		spans.append(b - a)
		var h := minf(feet[i], feet[i + 1]) - 4.5 - girder_bottom
		var end_bay := i == 0 or i == xs.size() - 2
		if h >= 40.0 and end_bay:
			var panels := maxi(1, ceili(h / 96.0))
			var ph := h / panels
			for m in panels:
				var y0 := girder_bottom + ph * m
				sk.bar(Vector2(a, y0), Vector2(b, y0 + ph), 2.0, flat, shade)
				sk.bar(Vector2(b, y0), Vector2(a, y0 + ph), 2.0, flat, shade)
				if m > 0:
					sk.strip(Rect2(a, y0 - 1.0, b - a, 2.0), flat, shade)
			braced = true
		elif h >= 8.0:
			var kb := clampf(minf(h * 0.5, (b - a) * 0.3), 3.0, 12.0)
			sk.bar(Vector2(a, girder_bottom + kb), Vector2(a + kb, girder_bottom), 2.0, flat, shade)
			sk.bar(Vector2(b, girder_bottom + kb), Vector2(b - kb, girder_bottom), 2.0, flat, shade)
			braced = true
	return {"system": spec["name"], "spans": spans, "piers": piers, "braced": braced}


## ---------------------------------------------------------------- rock --

## Slag-rock ledges stand on natural pillars: flared under the ledge, waisted,
## spreading into scree at the foot, split by columnar joints.
static func _rock_pillars(sk: SKETCH, bounds: Rect2, spec: Dictionary, family: String, tone: Color,
		bearings: Array[Rect2]) -> Dictionary:
	var width := bounds.size.x
	var under := bounds.end.y
	var tex := KIT.masonry(family)
	var shade := tone * REAR
	var heights := _clearances(bounds, bearings)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector4(bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y))
	var w := _section(spec, heights.y, width)
	var xs: PackedFloat32Array
	if width < w * 2.0 + 32.0:
		xs = PackedFloat32Array([roundf((width - w) * 0.5)])
	else:
		xs = _stations(width, w, maxi(1, ceili((width - w) / (float(spec["max_span"]) + w))))
	var lip := PackedVector2Array([Vector2(0, 0), Vector2(width, 0)])
	var x := width
	while x > 0.5:
		lip.append(Vector2(x, TUCK + rng.randf_range(2.0, 6.0)))
		x -= rng.randf_range(4.0, 8.0)
	lip.append(Vector2(0, TUCK + 2.0))
	sk.polygon(lip, tex, shade)
	var piers: Array[Rect2] = []
	var spans := PackedFloat32Array()
	for i in xs.size():
		var foot := _bearing_y(bounds.position.x + xs[i] + w * 0.5, under, bearings)
		piers.append(Rect2(bounds.position.x + xs[i], under, w, foot - under))
		_pillar(sk, rng, xs[i], w, foot - under + TUCK, tex, shade)
		if i > 0:
			spans.append(xs[i] - xs[i - 1] - w)
	return {"system": spec["name"], "spans": spans, "piers": piers}


static func _pillar(sk: SKETCH, rng: RandomNumberGenerator, x: float, w: float, f: float,
		tex: Texture2D, shade: Color) -> void:
	var cx := x + w * 0.5
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var y := 0.0
	while y < f - 2.0:
		var k := y / f
		var spread := lerpf(1.1, 0.88, k / 0.35) if k < 0.35 else lerpf(0.88, 1.4, (k - 0.35) / 0.65)
		left.append(Vector2(cx - w * 0.5 * spread + rng.randf_range(-1.2, 1.2), y))
		right.append(Vector2(cx + w * 0.5 * spread + rng.randf_range(-1.2, 1.2), y))
		y += rng.randf_range(4.0, 7.0)
	left.append(Vector2(cx - w * 0.75, f))
	right.append(Vector2(cx + w * 0.75, f))
	var body := PackedVector2Array(left)
	for i in range(right.size() - 1, -1, -1):
		body.append(right[i])
	sk.polygon(body, tex, shade)
	var joints := PackedVector2Array()
	for j in [-0.22, 0.2]:
		var jx := cx + w * float(j)
		var yy := rng.randf_range(2.0, 8.0)
		while yy < f - 8.0:
			var run := rng.randf_range(5.0, 9.0)
			joints.append(Vector2(jx + rng.randf_range(-0.6, 0.6), yy))
			joints.append(Vector2(jx + rng.randf_range(-0.6, 0.6), minf(f - 6.0, yy + run)))
			yy += run + rng.randf_range(0.5, 2.0)
	sk.lines(joints, shade * Color(0.5, 0.5, 0.55), 0.5)
	var th := clampf(f * 0.2, 3.0, 9.0)
	var tw := w * 0.55 + th * 1.4
	var scree := PackedVector2Array()
	for i in 9:
		var t := float(i) / 8.0
		scree.append(Vector2(cx - tw + tw * 2.0 * t, f - th * sin(t * PI) * rng.randf_range(0.75, 1.0)))
	sk.polygon(scree, tex, shade * Color(1.1, 1.08, 1.05))


## -------------------------------------------------------------- hoists --

static func _hoist(lift: MovingPlatform, host: Node2D, bodies: Array[Node], bearings: Array[Rect2],
		material: String, family: String) -> void:
	var origin := lift.get_parent() as Node2D
	var start := origin.to_global(lift.start_position())
	var end := origin.to_global(lift.end_position())
	var high := minf(start.y, end.y)
	var low := maxf(start.y, end.y)
	var vertical := absf(end.x - start.x) < 0.5
	var rope_l := minf(start.x, end.x) + 6.0
	var rope_r := maxf(start.x, end.x) + lift.width - 6.0
	var left := minf(start.x, end.x) - 16.0
	var right := maxf(start.x, end.x) + lift.width + 16.0
	var steel := material == KIT.STEEL
	var beam_h := 6.0 if steel else 7.0
	var mount := _overhead(lift, bodies, rope_l, rope_r, high - HOIST_HEADROOM)
	var hung := mount.size.x > 0.0 and high - mount.end.y <= MAX_ROPE
	var top := mount.end.y + 4.0 if hung else high - HOIST_HEADROOM
	var span := right - left
	var shade := REAR
	var sketch: SKETCH = SKETCH.new()
	sketch.name = String(lift.name) + "Gantry"
	sketch.set_meta(GENERATED, true)
	sketch.z_index = -3
	host.add_child(sketch)
	sketch.global_position = Vector2(left, top)
	var iron: Dictionary = KIT.steel_colors(family)
	sketch.strip(Rect2(0, 0, span, beam_h), KIT.girder(family) if steel else KIT.beam(family), shade)
	if hung:
		# Runway or sheave beam hangs on rods from the slab above.
		var rods := PackedVector2Array()
		var count := maxi(1, ceili(span / 64.0))
		for i in count + 1:
			var x := lerpf(4.0, span - 4.0, float(i) / count)
			if left + x < mount.position.x + 2.0 or left + x > mount.end.x - 2.0:
				continue
			sketch.strip(Rect2(x - 0.75, -4.0, 1.5, 4.0), null, (iron["mid"] as Color) * shade)
			sketch.strip(Rect2(x - 2.5, -4.0, 5.0, 1.0), null, (iron["dark"] as Color) * shade)
			rods.append(Vector2(left + x, mount.end.y))
		lift.set_meta(&"structure_hangers", rods)
	else:
		_hoist_legs(sketch, lift, left, top, span, beam_h, low, bearings, material, family)
	var rope_top: float
	if vertical:
		var sheaves := PackedVector2Array()
		for rx in [start.x + 6.0, start.x + lift.width - 6.0]:
			var c := Vector2(float(rx) - left, beam_h + 4.0)
			_sheave(sketch, c, iron, shade)
			sheaves.append(c + sketch.global_position)
		rope_top = top + beam_h + 4.0
		lift.set_meta(&"structure_sheaves", sheaves)
	else:
		rope_top = top + beam_h + 6.0
		_trolley(lift, top + beam_h - (origin.to_global(lift.position)).y, iron)
	lift.chain_top_y = origin.to_local(Vector2(0, rope_top)).y
	lift._update_chains()
	_deck(lift, material, family)
	lift.set_meta(&"structure_kind", "gantry")
	lift.set_meta(&"structure_hoist", ("hung_" if hung else "frame_") + ("sheaves" if vertical else "runway"))
	lift.set_meta(&"structure_material", material)
	lift.set_meta(&"structure_rope_top", rope_top)


## The slab the ropes can hang from: the lowest fixed body above the hoist's
## headroom that spans every rope. Empty when another deck or another hoist's
## path cuts across the ropes first.
static func _overhead(lift: MovingPlatform, bodies: Array[Node], rope_l: float, rope_r: float,
		limit: float) -> Rect2:
	var mount := Rect2()
	var blocked := -INF
	for body in bodies:
		if body == lift:
			continue
		var rect: Rect2
		if body is MovingPlatform:
			var m := body as MovingPlatform
			var o := m.get_parent() as Node2D
			rect = Rect2(o.to_global(m.start_position()), Vector2(m.width, MovingPlatform.WORLD)).merge(
					Rect2(o.to_global(m.end_position()), Vector2(m.width, MovingPlatform.WORLD)))
		elif body is SolidPlatform:
			rect = Rect2((body as SolidPlatform).global_position, (body as SolidPlatform).size)
		else:
			var g := body as GearPlatform
			rect = Rect2(g.global_position - Vector2(g.radius, g.radius), Vector2(g.radius * 2.0, g.radius * 2.0))
		if rect.end.y > limit or rect.end.x <= rope_l - 1.0 or rect.position.x >= rope_r + 1.0:
			continue
		var spans := body is SolidPlatform and not (body is CollapsingPlatform) \
				and rect.position.x <= rope_l - 2.0 and rect.end.x >= rope_r + 2.0
		if spans:
			if mount.size.x <= 0.0 or rect.end.y > mount.end.y:
				mount = rect
		else:
			blocked = maxf(blocked, rect.end.y)
	if mount.size.x <= 0.0 or blocked >= mount.end.y:
		return Rect2()
	return mount


## Legs at each end of the beam (and between, within the material's span),
## each on its own footing, with knee braces into the beam at the ends.
static func _hoist_legs(sk: SKETCH, lift: MovingPlatform, left: float, top: float, span: float,
		beam_h: float, low: float, bearings: Array[Rect2], material: String, family: String) -> void:
	var steel := material == KIT.STEEL
	var leg_tex := KIT.column(family) if steel else KIT.post(family)
	var brace_tex := KIT.flat(family) if steel else KIT.beam(family)
	var pad_tex := KIT.concrete() if steel else KIT.masonry(family)
	var xs := _stations(span, LEG, maxi(1, ceili((span - LEG) / float(HOIST_SPAN[material]))))
	var legs: Array[Rect2] = []
	for x in xs:
		var foot := _bearing_y(left + x + LEG * 0.5, low + MovingPlatform.WORLD, bearings) - top
		sk.strip(Rect2(x - 3.0, foot - 3.0, LEG + 6.0, 3.0), pad_tex, REAR)
		sk.strip(Rect2(x, beam_h, LEG, foot - 3.0 - beam_h), leg_tex, REAR)
		legs.append(Rect2(left + x, top + beam_h, LEG, foot - beam_h))
	var kb := 10.0
	sk.bar(Vector2(xs[0] + LEG, beam_h + kb), Vector2(xs[0] + LEG + kb, beam_h), 2.0 if steel else 3.0, brace_tex, REAR)
	var last := xs[xs.size() - 1]
	sk.bar(Vector2(last, beam_h + kb), Vector2(last - kb, beam_h), 2.0 if steel else 3.0, brace_tex, REAR)
	lift.set_meta(&"structure_legs", legs)


## Head sheave hung under the beam: rim, spokes, hub. The rope leaves its centre line.
static func _sheave(sk: SKETCH, c: Vector2, iron: Dictionary, shade: Color) -> void:
	sk.strip(Rect2(c.x - 1.0, c.y - 4.5, 2.0, 1.5), null, (iron["dark"] as Color) * shade)
	sk.disc(c, 4.0, (iron["dark"] as Color) * shade)
	sk.disc(c, 3.2, (iron["mid"] as Color) * shade)
	var spokes := PackedVector2Array()
	for i in 3:
		var a := PI * float(i) / 3.0 + 0.3
		var d := Vector2(cos(a), sin(a)) * 3.0
		spokes.append(c - d)
		spokes.append(c + d)
	sk.lines(spokes, (iron["dark"] as Color) * shade, 0.75)
	sk.disc(c, 1.1, (iron["light"] as Color) * shade)


## Underhung trolley that runs on the runway's bottom flange above the deck.
static func _trolley(lift: MovingPlatform, y: float, iron: Dictionary) -> void:
	var trolley: SKETCH = SKETCH.new()
	trolley.name = "Trolley"
	trolley.set_meta(GENERATED, true)
	trolley.z_index = -2
	lift.add_child(trolley)
	trolley.position = Vector2(0, y)
	var w := lift.width
	trolley.strip(Rect2(3.0, 1.5, w - 6.0, 3.5), null, iron["mid"])
	trolley.strip(Rect2(3.0, 1.5, w - 6.0, 0.75), null, iron["light"])
	trolley.strip(Rect2(3.0, 4.25, w - 6.0, 0.75), null, iron["dark"])
	for x in [8.0, w - 8.0]:
		trolley.disc(Vector2(x, -0.5), 2.5, iron["dark"])
		trolley.disc(Vector2(x, -0.5), 1.0, iron["light"])
	for x in [6.0, w - 6.0]:
		trolley.strip(Rect2(x - 1.5, 4.5, 3.0, 1.5), null, iron["dark"])


## Planks on a strapped stringer, or tread plate on a channel. A deck an author
## already restyled (hidden default pieces) keeps its authored look.
static func _deck(lift: MovingPlatform, material: String, family: String) -> void:
	var defaults: Array[Sprite2D] = []
	for child in lift.get_children():
		if child is Sprite2D:
			if not (child as Sprite2D).visible:
				return
			defaults.append(child as Sprite2D)
	if defaults.is_empty():
		return
	for piece in defaults:
		piece.visible = false
	var deck: SKETCH = SKETCH.new()
	deck.name = "Deck"
	deck.set_meta(GENERATED, true)
	deck.z_index = -1
	lift.add_child(deck)
	var colors: Dictionary = KIT.steel_colors(family) if material == KIT.STEEL else KIT.wood_colors(family)
	deck.strip(Rect2(0, 0, lift.width, 14.0), KIT.deck(material, family), Color.WHITE)
	deck.strip(Rect2(0, 0, 1.0, 14.0), null, colors["dark"])
	deck.strip(Rect2(lift.width - 1.0, 0, 1.0, 14.0), null, colors["dark"])
	lift.set_meta(&"structure_deck", material)
