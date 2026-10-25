class_name Interactable
extends Area2D
## Base for E-key objects. Pressure plates may extend this but return false from can_interact.

@export var prompt: String = "E 交互"
## Extra Area2D reach beyond the visual. The knight's sensor is only 32×32;
## 12–18px props otherwise demand pixel-perfect overlap.
@export var reach_pad: Vector2 = Vector2(10, 8)


func _ready() -> void:
	collision_layer = 64
	collision_mask = 2
	monitoring = true
	monitorable = true


func can_interact(_actor: Node) -> bool:
	return true


func interact(_actor: Node) -> void:
	pass


func get_prompt(_actor: Node) -> String:
	return prompt


func ensure_rect(size: Vector2, color: Color, offset: Vector2 = Vector2.ZERO) -> void:
	if get_node_or_null("Fill") == null:
		var fill := ColorRect.new()
		fill.name = "Fill"
		fill.size = size
		fill.position = offset
		fill.color = color
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fill)
	_ensure_collision(size, offset)


## Prefer a Gothicvania sprite; ColorRect only if the file is missing.
## `region`（可选）：只取贴图的一个子矩形，避免为了塞进 size 而整图挤压变形。
func ensure_sprite(path: String, size: Vector2, offset: Vector2 = Vector2.ZERO, fallback: Color = Color(0.28, 0.24, 0.34), region: Rect2 = Rect2()) -> void:
	if get_node_or_null("Fill") != null:
		_ensure_collision(size, offset)
		return
	if ResourceLoader.exists(path):
		var tex := DensityTextures.load_texture(path)
		if tex != null:
			var spr := Sprite2D.new()
			spr.name = "Fill"
			spr.texture = tex
			spr.centered = false
			spr.position = offset
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			var src := Vector2(float(tex.get_width()), float(tex.get_height()))
			if region.has_area():
				spr.region_enabled = true
				spr.region_rect = region
				src = region.size
			spr.scale = Vector2(size.x / src.x, size.y / src.y)
			add_child(spr)
			_ensure_collision(size, offset)
			return
	ensure_rect(size, fallback, offset)


func _ensure_collision(size: Vector2, offset: Vector2) -> void:
	if get_node_or_null("CollisionShape2D") == null:
		var pad := reach_pad
		var reach := size + pad * 2.0
		var reach_off := offset - pad
		var col := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = reach
		col.shape = shape
		col.position = reach_off + reach * 0.5
		add_child(col)
