class_name HookAnchor
extends Area2D
## 钩锁锚点：悬浮的哥特石十字 + 背后一圈脉动余烬光晕。
## 光晕让"漂在空中的墓碑"读作刻意的魔物锚点，也标记了可交互性。

const TEX_PATH := "res://assets/env/rubble_b.png"
const GLOW_PATH := "res://assets/env/glow_soft.png"
const BASE_SCALE := 0.62


func _ready() -> void:
	add_to_group("hook_anchor")
	monitoring = false
	var ring := get_node_or_null("Ring")
	var core := get_node_or_null("Core")
	if ring:
		ring.visible = false
	if core:
		core.visible = false
	if get_node_or_null("Sprite") == null and ResourceLoader.exists(TEX_PATH):
		if ResourceLoader.exists(GLOW_PATH):
			var glow := Sprite2D.new()
			glow.name = "Glow"
			glow.texture = DensityTextures.load_texture(GLOW_PATH)
			glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			glow.centered = true
			glow.scale = Vector2(1.1, 1.1)
			glow.modulate = Color(1.0, 0.66, 0.34, 0.4)
			add_child(glow)
		var spr := Sprite2D.new()
		spr.name = "Sprite"
		spr.texture = DensityTextures.load_texture(TEX_PATH)
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.centered = true
		spr.scale = Vector2(BASE_SCALE, BASE_SCALE)
		add_child(spr)


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var pulse := sin(t * 2.2)
	var spr := get_node_or_null("Sprite") as Node2D
	if spr:
		var s := BASE_SCALE + 0.035 * pulse
		spr.scale = Vector2(s, s)
		var glow := get_node_or_null("Glow") as CanvasItem
		if glow:
			glow.modulate.a = 0.3 + 0.16 * (pulse * 0.5 + 0.5)
			(glow as Node2D).scale = Vector2(1.05, 1.05) + Vector2(0.1, 0.1) * pulse
		return
	var ring := get_node_or_null("Ring") as Node2D
	if ring:
		ring.scale = Vector2(1.0 + 0.12 * pulse, 1.0 + 0.12 * pulse)
