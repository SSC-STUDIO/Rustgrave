class_name ChapterLook
extends RefCounted
## Phase-3 colour / lighting rules for chapters 2-10, applied on top of each chapter's own
## authored palette (user steer: keep each chapter's original character, a little darker,
## clearer separation). Same rules as chapter 1, different colours per chapter:
##   1. backdrop plates pushed back by depth (farthest darkest), authored hue kept;
##   2. a screen-space haze glow in the chapter's own light colour (horizon / skylight /
##      lava below / hall centre);
##   3. lit platform lips on the play layer (brightest values stay on what you stand on);
##   4. light pools around lit fires (nests, torches, hearths).
## Keys: far / near = value multiplier of the farthest / nearest plate; glow (rgb + a);
## glow_stops (preset name or [[y, k], ...]); top_light (rgb + a); light_pool (rgb + a).

const STOPS := {
	"horizon": [[0.0, 0.0], [0.16, 0.12], [0.44, 0.62], [0.62, 1.0], [0.8, 0.72], [1.0, 0.35]],
	"top": [[0.0, 1.0], [0.3, 0.5], [0.65, 0.12], [1.0, 0.0]],
	"bottom": [[0.0, 0.0], [0.45, 0.1], [0.78, 0.55], [1.0, 1.0]],
	"centre": [[0.0, 0.0], [0.28, 0.35], [0.55, 1.0], [0.82, 0.4], [1.0, 0.0]],
}
const PLAY_FOLDERS := ["Platforms", "Decor"]


static func stops_for(look: Dictionary) -> Array:
	var s: Variant = look.get("glow_stops", "horizon")
	if s is Array:
		return s
	return STOPS.get(String(s), STOPS["horizon"])


## Darken backdrop Parallax2D plates by depth (child order = far to near). Idempotent.
static func push_back_plates(backdrop: Node, far: float, near: float) -> int:
	if backdrop == null or backdrop.has_meta("look_depth"):
		return 0
	var layers: Array[Parallax2D] = []
	for child in backdrop.get_children():
		if child is Parallax2D:
			layers.append(child as Parallax2D)
	var n := layers.size()
	for i in n:
		var k := far if n == 1 else lerpf(far, near, float(i) / float(n - 1))
		for spr in layers[i].get_children():
			if spr is CanvasItem:
				var m := (spr as CanvasItem).modulate
				(spr as CanvasItem).modulate = Color(m.r * k, m.g * k, m.b * k, m.a)
	backdrop.set_meta("look_depth", true)
	return n


static func apply(host: Node2D, backdrop: Node, look: Dictionary, under: String = "Layer1") -> void:
	if host == null or look.is_empty():
		return
	push_back_plates(backdrop, float(look.get("far", 1.0)), float(look.get("near", 1.0)))
	var glow: Color = look.get("glow", Color(0, 0, 0, 0))
	if glow.a > 0.001:
		Level01Parallax.add_glow(backdrop, glow, stops_for(look), under)
	var top: Color = look.get("top_light", Color(0, 0, 0, 0))
	# Deferred: chapter layouts may still be adding terrain when the backdrop is built.
	Level01Parallax.light_tops(host, top, PLAY_FOLDERS)
	Level01Parallax.light_tops.call_deferred(host, top, PLAY_FOLDERS)
	Level01Parallax.add_light_pools.call_deferred(host, look)
