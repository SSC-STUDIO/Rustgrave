class_name LightPool
extends Sprite2D
## Soft additive glow around a fire light (Level01Parallax.add_light_pools): the WorldLight
## lights surfaces, this gives the air around the flame a visible warm pool. Follows the
## source light: hidden when it is off, strength scales with its energy, size with its radius.

## Pool diameter relative to the light's diameter.
const SPREAD := 1.7
## Energy at which the pool reaches full tint alpha.
const FULL_ENERGY := 1.4

var source: WorldLight
var tint: Color = Color(1.0, 0.6, 0.28, 0.3)


func _ready() -> void:
	centered = true
	z_as_relative = false
	z_index = 2
	add_to_group("no_grade")
	_sync()


func _process(_delta: float) -> void:
	_sync()


func _sync() -> void:
	if source == null or not is_instance_valid(source):
		visible = false
		return
	visible = source.enabled and source.energy > 0.001
	if not visible or texture == null:
		return
	var radius := source.texture_scale * WorldLight.TEX_SIZE * 0.5
	var k := (radius * 2.0 * SPREAD) / float(texture.get_width())
	scale = Vector2(k, k)
	modulate = Color(tint.r, tint.g, tint.b, tint.a * clampf(source.energy / FULL_ENERGY, 0.0, 1.0))
