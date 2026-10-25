extends Node2D
## 炉城地下角斗熔炉。分层：天空渐变(左冷蓝右炉红) → 远/中/近炉城剪影 → 沉到墙基的
## 熔河 → 屋顶桁架 → 大门 → 纵深地面 → 祭台 → 蒸汽/余烬 → 8 盏点光 → 前景暗角。
## 点光源不超过 8（测试钉住）。FrontVeil / DepthGround / AltarPad 节点名钉住。
## 像素贴图只做 1 倍或 2 倍缩放，过滤保持最近邻。

const ArenaCatalog := preload("res://scripts/data/arena_catalog.gd")
const GroundScript := preload("res://scripts/levels/arena_ground.gd")
const FlameScript := preload("res://scripts/levels/arena_flame.gd")

const GLOW := "res://assets/title/glow.png"
const FORGE_FAR := "res://assets/env/backdrop/forge_far.png"
const FORGE_MID := "res://assets/env/backdrop/forge_mid.png"
const FORGE_NEAR := "res://assets/env/backdrop/forge_near.png"
const MACHINERY := "res://assets/env/backdrop/machinery_forge.png"
const TRUSS := "res://assets/env/backdrop/truss_forge.png"
const RIVER := "res://assets/title/pit_river.png"
const LANTERN := "res://assets/title/lantern.png"
const MOUTH := "res://assets/title/forge_mouth.png"
const STEAM := "res://assets/title/steam.png"
const PROPS := "res://assets/env/props/basalt/"

## 熔河带上沿。后缘矮墙从 DEPTH_BACK - 26 起，河面露出 202–226 这一段。
const RIVER_Y := 198
const WALL_TOP := 226
## 墙顶火盆的位置（躲开塔、门、祭台）。
const BRAZIER_X := [700.0, 1560.0, 2280.0, 3100.0]

var _lights := 0
var _plx: Array[Dictionary] = []


func _process(_delta: float) -> void:
	# 手动视差：层随镜头反向偏移 (1 - rate)，等价于 Parallax2D 的 scroll_scale，
	# 但全程确定，3840 主路右段不会被引擎 repeat 语义吃掉。
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var cx := cam.get_screen_center_position().x
	for entry in _plx:
		var node: Node2D = entry.get("node")
		if is_instance_valid(node):
			node.position.x = cx * (1.0 - float(entry.get("rate", 1.0)))


func build(host: Node2D) -> void:
	name = "ArenaStage"
	z_index = 0
	host.add_child(self)
	var sky := SkyWash.new()
	sky.name = "SkyWash"
	add_child(sky)
	_parallax("FarForge", FORGE_FAR, Vector2(0, WALL_TOP - 284), Vector2(0.12, 0.0), -30, Color(0.8, 0.78, 0.9), 2)
	_parallax("MidForge", FORGE_MID, Vector2(0, WALL_TOP - 300), Vector2(0.26, 0.0), -25, Color(0.95, 0.85, 0.85), 2)
	_parallax("NearWall", FORGE_NEAR, Vector2(0, WALL_TOP - 208), Vector2(0.42, 0.0), -21, Color(1.1, 0.95, 0.9), 2)
	_parallax("Machinery", MACHINERY, Vector2(0, WALL_TOP - 128), Vector2(0.52, 0.0), -19, Color(1.2, 1.08, 1.0), 1)
	_parallax("LavaRiver", RIVER, Vector2(0, RIVER_Y), Vector2(0.55, 0.0), -17, Color(1.6, 1.25, 0.95), 1, true)
	var glow := LavaGlow.new()
	glow.name = "LavaBand"
	add_child(glow)
	var wash := SideWash.new()
	wash.name = "SideWash"
	add_child(wash)
	var ceiling := CeilingBand.new()
	ceiling.name = "CeilingBand"
	add_child(ceiling)
	_parallax("Roofline", TRUSS, Vector2(0, -2), Vector2(0.92, 0.0), -13, Color(0.72, 0.68, 0.72), 1)
	var chains := HangingChains.new()
	chains.name = "HangingChains"
	add_child(chains)
	var fixtures := WallFixtures.new()
	fixtures.name = "WallFixtures"
	add_child(fixtures)
	var lamps := SignalLamps.new()
	lamps.name = "SignalLamps"
	add_child(lamps)
	_gate(true)
	_gate(false)
	_braziers()
	_halos()
	var ground: Node2D = GroundScript.new()
	add_child(ground)
	_altar()
	_steam(Vector2(560, 186), Color(0.7, 0.8, 1.0, 0.35))
	_steam(Vector2(1560, 182), Color(0.85, 0.78, 0.72, 0.3))
	_steam(Vector2(2320, 184), Color(1.0, 0.72, 0.55, 0.35))
	_steam(Vector2(3260, 186), Color(1.1, 0.6, 0.42, 0.4))
	var embers := Embers.new()
	embers.name = "Embers"
	add_child(embers)
	_light("BlueGate", Vector2(70, 214), Color(0.55, 0.72, 1.2), 0.75, 1.8)
	_light("BlueWell", Vector2(150, 286), Color(0.5, 0.75, 1.25), 0.9, 1.6)
	_light("BlueCrystal", Vector2(460, 250), Color(0.45, 0.7, 1.3), 0.6, 1.7)
	_light("AltarFire", Vector2(1888, 268), Color(1.15, 0.62, 0.28), 0.8, 2.0)
	_light("LavaGlow", Vector2(1920, 218), Color(1.1, 0.45, 0.16), 0.45, 2.4)
	_light("RedCrystal", Vector2(3380, 250), Color(1.2, 0.4, 0.22), 0.65, 1.7)
	_light("RedWell", Vector2(3690, 286), Color(1.25, 0.36, 0.16), 0.95, 1.6)
	_light("RedGate", Vector2(3768, 206), Color(1.3, 0.34, 0.12), 0.8, 1.9)
	var veil := FrontFrame.new()
	veil.name = "FrontVeil"
	add_child(veil)


func light_count() -> int:
	return _lights


func _gate(blue: bool) -> void:
	var gate := Gate.new()
	gate.blue = blue
	gate.name = "BlueGate" if blue else "RedGate"
	gate.position = Vector2(206, ArenaCatalog.DEPTH_BACK) if blue else Vector2(3576, ArenaCatalog.DEPTH_BACK)
	gate.z_index = -12
	add_child(gate)
	if blue:
		_sprite(gate, LANTERN, Vector2(16, -76), 2, Color(0.85, 0.95, 1.25, 1.0), 1)
		_sprite(gate, LANTERN, Vector2(64, -76), 2, Color(0.8, 0.9, 1.2, 1.0), 1)
		_flame(gate, Vector2(48, -18), Color(0.7, 0.85, 1.3, 0.95), 2)
	else:
		_sprite(gate, MOUTH, Vector2(20, -118), 2, Color(1.25, 0.8, 0.5, 1.0), 1)
		_flame(gate, Vector2(50, -26), Color(1.4, 0.7, 0.35, 1.0), 2)


func _altar() -> void:
	var altar := Altar.new()
	altar.name = "AltarPad"
	altar.position = Vector2(1920, ArenaCatalog.DEPTH_BACK)
	altar.z_index = -7
	add_child(altar)
	_flame(altar, Vector2(-28, 8), Color(1.5, 0.85, 0.4, 1.0), 2)
	var shaft := Polygon2D.new()
	shaft.name = "AltarShaft"
	shaft.z_index = -6
	shaft.position = Vector2(-28, -20)
	shaft.polygon = PackedVector2Array([
		Vector2(-14, 0), Vector2(14, 0), Vector2(5, -128), Vector2(-5, -128),
	])
	shaft.color = Color(1.2, 0.55, 0.18, 0.2)
	shaft.material = Fx.additive_mat()
	altar.add_child(shaft)


func _steam(at: Vector2, tint: Color) -> void:
	_sprite(self, STEAM, at, 2, tint, -13, true)


## 墙顶火盆：矮柱 + 斗，斗里一簇动画火，蓝侧冷火、红侧热火。
func _braziers() -> void:
	var row := BrazierRow.new()
	row.name = "BrazierRow"
	row.z_index = -10
	add_child(row)
	for bx_v in BRAZIER_X:
		var bx := float(bx_v)
		var cool := bx < 1600.0
		var tint := Color(0.7, 0.85, 1.3, 0.95) if cool else Color(1.45, 0.68, 0.3, 1.0)
		_flame(row, Vector2(bx, WALL_TOP - 14), tint, 2)


## 发光晕：塔顶火盆、大门、水晶、祭台背后的柔光，不占点光源名额。
func _halos() -> void:
	var spots := {
		900.0: Color(0.5, 0.72, 1.3, 0.16), 1280.0: Color(0.5, 0.72, 1.3, 0.16),
		2560.0: Color(1.3, 0.5, 0.2, 0.16), 2940.0: Color(1.3, 0.5, 0.2, 0.16),
		460.0: Color(0.5, 0.75, 1.4, 0.18), 3380.0: Color(1.4, 0.45, 0.18, 0.18),
		248.0: Color(0.55, 0.78, 1.3, 0.2), 3620.0: Color(1.35, 0.5, 0.2, 0.2),
		1892.0: Color(1.2, 0.6, 0.25, 0.2),
	}
	for hx in spots:
		var y := 190.0
		if hx == 248.0 or hx == 3620.0:
			y = 170.0
		elif hx == 1892.0:
			y = 236.0
		_sprite(self, GLOW, Vector2(hx - 128.0, y - 128.0), 2, spots[hx], -11, true)


func _flame(parent: Node, at: Vector2, tint: Color, scale_i: int) -> void:
	var flame: Sprite2D = FlameScript.new()
	flame.position = at
	flame.scale = Vector2(scale_i, scale_i)
	flame.modulate = tint
	flame.z_index = 2
	parent.add_child(flame)


func _parallax(layer_name: String, path: String, pos: Vector2, scroll: Vector2, z: int, tint: Color, scale_i: int, additive := false) -> void:
	if not ResourceLoader.exists(path):
		return
	var tex := load(path) as Texture2D
	if tex == null:
		return
	var layer := Node2D.new()
	layer.name = layer_name
	layer.z_index = z
	add_child(layer)
	_plx.append({"node": layer, "rate": scroll.x})
	# 手动平铺：镜头在 320–3520 之间，层空间需要覆盖 [320*rate-320, 3520*rate+320]。
	var step := maxf(1.0, floorf(float(tex.get_width()) * float(scale_i)))
	var rate := maxf(scroll.x, 0.0)
	var first := int(floor((320.0 * rate - 320.0 - pos.x) / step))
	var last := int(ceil((3520.0 * rate + 320.0 - pos.x) / step))
	var i := first
	while i <= last:
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.centered = false
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.position = pos + Vector2(float(i) * step, 0.0)
		spr.scale = Vector2(scale_i, scale_i)
		spr.modulate = tint
		if additive:
			spr.material = Fx.additive_mat()
		layer.add_child(spr)
		i += 1


func _sprite(parent: Node, path: String, pos: Vector2, scale_i: int, tint: Color, z: int, additive := false) -> void:
	if not ResourceLoader.exists(path):
		return
	var tex := load(path) as Texture2D
	if tex == null:
		return
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.position = pos
	spr.scale = Vector2(scale_i, scale_i)
	spr.modulate = tint
	spr.z_index = z
	if additive:
		spr.material = Fx.additive_mat()
	parent.add_child(spr)


func _light(light_name: String, pos: Vector2, color: Color, energy: float, tex_scale: float) -> void:
	if _lights >= 8 or not ResourceLoader.exists(GLOW):
		return
	var light := PointLight2D.new()
	light.name = light_name
	light.texture = load(GLOW) as Texture2D
	light.texture_scale = tex_scale
	light.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	light.position = pos
	light.color = color
	light.energy = energy
	light.shadow_enabled = false
	add_child(light)
	_lights += 1


## 天空：左冷蓝、右炉红的双向渐变，竖向往地平线增亮。
class SkyWash extends Node2D:
	func _ready() -> void:
		z_index = -36

	func _draw() -> void:
		var span := 3840
		var x := 0
		while x < span:
			var t := float(x) / float(span)
			var top := Color(lerpf(0.045, 0.1, t), lerpf(0.065, 0.04, t), lerpf(0.13, 0.05, t))
			var horizon := Color(lerpf(0.2, 0.72, t), lerpf(0.32, 0.24, t), lerpf(0.52, 0.09, t))
			var y := 0
			while y < WALL_TOP:
				var k := pow(float(y) / float(WALL_TOP), 1.7)
				draw_rect(Rect2(x, y, 8, 4), top.lerp(horizon, k))
				y += 4
			x += 8


## 熔河上方的一层暖光雾，把河面和远景粘在一起。
class LavaGlow extends Node2D:
	func _ready() -> void:
		z_index = -16
		material = Fx.additive_mat()

	func _draw() -> void:
		var span := 3840
		var x := 0
		while x < span:
			var warm := clampf(float(x) / float(span), 0.0, 1.0)
			var y := 0
			while y < 34:
				var fade := 1.0 - float(y) / 34.0
				var col := Color(
					lerpf(0.35, 1.5, warm) * fade,
					lerpf(0.3, 0.5, warm) * fade,
					lerpf(0.45, 0.12, warm) * fade,
					0.34 * fade)
				draw_rect(Rect2(x, 172 + y, 8, 1), col)
				y += 2
			x += 8


## 阵营色罩：左冷蓝、右炉红。垫在剪影层底下只染天空，向上渐强，避免把远景楼影洗平。
class SideWash extends Node2D:
	func _ready() -> void:
		z_index = -31

	func _draw() -> void:
		var span := 3840
		var x := 0
		while x < span:
			var t := float(x) / float(span)
			var cool := clampf(1.0 - t / 0.62, 0.0, 1.0)
			var warm := clampf((t - 0.38) / 0.62, 0.0, 1.0)
			var y := 0
			while y < WALL_TOP:
				var fade := 1.0 - float(y) / float(WALL_TOP) * 0.55
				if cool > 0.0:
					draw_rect(Rect2(x, y, 8, 4), Color(0.3, 0.5, 1.05, 0.3 * cool * fade))
				elif warm > 0.0:
					draw_rect(Rect2(x, y, 8, 4), Color(1.1, 0.4, 0.12, 0.22 * warm * fade))
				y += 4
			x += 8


## 顶棚压顶：一道实心暗带盖住桁架顶端，让屋顶读成「盖」而不是漂浮的架子。
class CeilingBand extends Node2D:
	func _ready() -> void:
		z_index = -14

	func _draw() -> void:
		var span := 3840
		draw_rect(Rect2(0, -8, span, 16), Color(0.03, 0.026, 0.03))
		draw_rect(Rect2(0, 8, span, 2), Color(0.09, 0.08, 0.09))


## 顶棚垂链：间距 320，长短交错，末尾带钩。
class HangingChains extends Node2D:
	const CHAIN_TEX := "res://assets/env/props/basalt/chain.png"
	var _hooks: Array[float] = []

	func _ready() -> void:
		z_index = -12
		if not ResourceLoader.exists(CHAIN_TEX):
			return
		var tex := load(CHAIN_TEX) as Texture2D
		var x := 320
		var i := 0
		while x < 3840:
			var links := 1 + (i % 3)
			var j := 0
			while j < links:
				var spr := Sprite2D.new()
				spr.texture = tex
				spr.centered = false
				spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				spr.position = Vector2(float(x), 8.0 + float(j) * 30.0)
				spr.modulate = Color(0.55, 0.5, 0.52)
				add_child(spr)
				j += 1
			_hooks.append(float(x) + 4.0)
			_hooks.append(8.0 + float(links) * 30.0 + 3.0)
			x += 320
			i += 1

	func _draw() -> void:
		var i := 0
		while i + 1 < _hooks.size():
			draw_arc(Vector2(_hooks[i], _hooks[i + 1]), 3.0, -0.4, PI + 0.4, 8, Color(0.16, 0.14, 0.15), 1.5)
			i += 2


## 墙面器件：阀、表盘、警示牌、断机，装在熔河前的立面上，下面拖一根安装杆。
class WallFixtures extends Node2D:
	const SPOTS := [
		[340.0, "pipe_valve"], [580.0, "metal_panel"], [780.0, "girder_l"],
		[1050.0, "warning_plate"], [1420.0, "pipe_valve"], [1650.0, "metal_panel"],
		[2150.0, "pipe_valve"], [2400.0, "warning_plate"], [2700.0, "metal_panel"],
		[3050.0, "girder_r"], [3300.0, "broken_machine"], [3450.0, "pipe_valve"],
	]

	func _ready() -> void:
		z_index = -11
		for spot in SPOTS:
			var sx := float(spot[0])
			var path := PROPS + String(spot[1]) + ".png"
			if not ResourceLoader.exists(path):
				continue
			var spr := Sprite2D.new()
			spr.texture = load(path) as Texture2D
			spr.centered = true
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			spr.position = Vector2(sx, 196.0)
			spr.modulate = Color(0.85, 0.8, 0.78)
			add_child(spr)

	func _draw() -> void:
		var mount := Color(0.1, 0.09, 0.1)
		for spot in SPOTS:
			var sx := float(spot[0])
			draw_rect(Rect2(sx - 1, 208, 2, WALL_TOP - 208), mount)


## 墙顶火盆的石座（火由外部 FlameScript 给）。
class BrazierRow extends Node2D:
	func _draw() -> void:
		for bx_v in BRAZIER_X:
			var bx := float(bx_v)
			var warm := clampf(bx / 3840.0, 0.0, 1.0)
			var stone := Color(lerpf(0.3, 0.38, warm), lerpf(0.32, 0.2, warm), lerpf(0.42, 0.14, warm))
			var dark := stone * 0.55
			draw_rect(Rect2(bx - 7, WALL_TOP - 22, 14, 22), stone)
			draw_rect(Rect2(bx + 3, WALL_TOP - 22, 4, 22), dark)
			draw_rect(Rect2(bx - 10, WALL_TOP - 26, 20, 5), dark)
			draw_rect(Rect2(bx - 10, WALL_TOP - 26, 20, 1), stone.lightened(0.4))


## 信号灯：左蓝右琥珀，各自缓慢呼吸闪烁。
class SignalLamps extends Node2D:
	const SPOTS_X := [380.0, 820.0, 1460.0, 2150.0, 2740.0, 3300.0]

	func _ready() -> void:
		z_index = -10
		material = Fx.additive_mat()

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var tick := float(Time.get_ticks_msec()) * 0.001
		var i := 0
		while i < SPOTS_X.size():
			var sx: float = SPOTS_X[i]
			var pulse := 0.55 + 0.45 * sin(tick * 1.7 + float(i) * 1.9)
			var col := Color(0.5, 0.8, 1.5, 0.75 * pulse) if sx < 1920.0 else Color(1.5, 0.75, 0.25, 0.75 * pulse)
			draw_rect(Rect2(sx, 186, 3, 3), col)
			draw_rect(Rect2(sx - 1, 185, 5, 1), Color(col.r, col.g, col.b, 0.3 * pulse))
			i += 1


## 大门：石门框 + 门洞辉光 + 队伍旗帜。蓝方挂灯，红方炉口（sprite 由外部加）。
class Gate extends Node2D:
	var blue := true

	func _draw() -> void:
		var stone := Color(0.5, 0.57, 0.7) if blue else Color(0.6, 0.34, 0.24)
		var dark := Color(0.24, 0.29, 0.4) if blue else Color(0.3, 0.13, 0.09)
		var light := Color(0.7, 0.79, 0.95) if blue else Color(0.88, 0.52, 0.33)
		var glow := Color(0.5, 0.78, 1.35, 0.95) if blue else Color(1.35, 0.52, 0.2, 0.95)
		var banner := Color(0.28, 0.55, 1.15) if blue else Color(1.15, 0.32, 0.12)
		# 门柱：左柱背光暗、右柱受光亮，柱脚和柱头加块。
		_p(Rect2(-8, -148, 22, 148), stone)
		_p(Rect2(76, -148, 22, 148), stone)
		_p(Rect2(-8, -148, 4, 148), light)
		_p(Rect2(94, -148, 4, 148), dark)
		_p(Rect2(-12, -12, 30, 12), dark)
		_p(Rect2(72, -12, 30, 12), dark)
		_p(Rect2(-12, -160, 30, 12), light)
		_p(Rect2(72, -160, 30, 12), light)
		# 楣梁与上檐。
		_p(Rect2(-16, -172, 122, 14), stone)
		_p(Rect2(-16, -172, 122, 3), light)
		_p(Rect2(-4, -184, 98, 12), dark)
		_p(Rect2(-4, -184, 98, 2), light)
		# 门洞：近黑，洞口下沿一道队伍色辉光。
		_p(Rect2(14, -158, 62, 158), Color(0.03, 0.03, 0.05, 0.96))
		_p(Rect2(14, -158, 62, 3), dark)
		_p(Rect2(18, -10, 54, 4), glow)
		# 旗帜：楣下两面，底部燕尾。
		_banner(24, -158, banner, light)
		_banner(56, -158, banner, light)
		# 门前台阶。
		_p(Rect2(-4, 0, 98, 3), dark)
		_p(Rect2(0, 3, 90, 3), Color(dark.r * 0.7, dark.g * 0.7, dark.b * 0.7))

	func _banner(x: int, y: int, banner: Color, edge: Color) -> void:
		_p(Rect2(x, y, 12, 30), banner)
		_p(Rect2(x, y, 12, 2), edge)
		_p(Rect2(x + 2, y + 6, 8, 8), edge)
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, y + 30), Vector2(x + 12, y + 30), Vector2(x + 6, y + 24),
		]), banner)

	func _p(rect: Rect2, color: Color) -> void:
		draw_rect(rect, color)


## 祭台：三级台阶 + 中央火纹 + 四角短柱，柱子顶上火盆由外部加 sprite。
class Altar extends Node2D:
	const Catalog := preload("res://scripts/data/arena_catalog.gd")

	func _draw() -> void:
		var back := 0.0
		var front := Catalog.DEPTH_FRONT - Catalog.DEPTH_BACK + 10.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(-160, back + 4), Vector2(160, back + 4),
			Vector2(190, front), Vector2(-190, front),
		]), Color(0.14, 0.1, 0.09))
		draw_colored_polygon(PackedVector2Array([
			Vector2(-120, back + 16), Vector2(120, back + 16),
			Vector2(142, front - 10), Vector2(-142, front - 10),
		]), Color(0.32, 0.2, 0.13))
		draw_colored_polygon(PackedVector2Array([
			Vector2(-78, back + 28), Vector2(78, back + 28),
			Vector2(92, front - 20), Vector2(-92, front - 20),
		]), Color(0.5, 0.3, 0.15))
		# 台面火纹：环 + 四道辐条。
		var ring := Color(1.0, 0.6, 0.22, 0.5)
		var cy := back + 34
		draw_arc(Vector2(0, cy), 30.0, 0.0, TAU, 24, ring, 1.5)
		draw_arc(Vector2(0, cy), 20.0, 0.0, TAU, 18, Color(1.1, 0.7, 0.3, 0.4), 1.0)
		for i in 4:
			var a := TAU * float(i) / 4.0 + PI / 4.0
			draw_line(Vector2(cos(a) * 20.0, cy + sin(a) * 20.0 * 0.35),
				Vector2(cos(a) * 30.0, cy + sin(a) * 30.0 * 0.35), ring, 1.0)
		# 前缘高光与短柱。
		draw_rect(Rect2(-150, front - 4, 300, 3), Color(0.95, 0.58, 0.2, 0.85))
		draw_rect(Rect2(-130, -20, 14, 48), Color(0.3, 0.22, 0.16))
		draw_rect(Rect2(116, -20, 14, 48), Color(0.38, 0.18, 0.12))
		draw_rect(Rect2(-134, -28, 22, 8), Color(0.85, 0.5, 0.22))
		draw_rect(Rect2(112, -28, 22, 8), Color(0.95, 0.4, 0.16))
		draw_rect(Rect2(-134, -28, 22, 2), Color(1.2, 0.8, 0.4))
		draw_rect(Rect2(112, -28, 22, 2), Color(1.3, 0.7, 0.3))


## 飘动的余烬：右侧暖橙，左侧冷蓝，数量克制。
class Embers extends Node2D:
	var _p: PackedVector2Array = PackedVector2Array()
	var _v: PackedFloat32Array = PackedFloat32Array()

	func _ready() -> void:
		z_index = -5
		material = Fx.additive_mat()
		var i := 0
		while i < 14:
			_p.append(Vector2(float((i * 277) % 3840), float(40 + (i * 37) % 160)))
			_v.append(8.0 + float(i % 5) * 3.0)
			i += 1

	func _process(delta: float) -> void:
		var i := 0
		while i < _p.size():
			var p := _p[i]
			p.y -= _v[i] * delta
			p.x += sin(p.y * 0.05 + float(i)) * 6.0 * delta
			if p.y < 24.0:
				p.y = 200.0
			_p[i] = p
			i += 1
		queue_redraw()

	func _draw() -> void:
		var i := 0
		while i < _p.size():
			var p := _p[i]
			var warm := Color(1.4, 0.55, 0.15, 0.85)
			if p.x < 1600.0:
				warm = Color(0.7, 0.85, 1.3, 0.5)
			draw_rect(Rect2(round(p.x), round(p.y), 2, 2), warm)
			i += 1


## 前景暗角：贴镜头的上下压边 + 两侧石柱，不挡中路视野。
class FrontFrame extends Node2D:
	func _ready() -> void:
		z_as_relative = false
		z_index = 48

	func _process(_delta: float) -> void:
		var cam := get_viewport().get_camera_2d()
		if cam == null:
			return
		var center := cam.get_screen_center_position()
		global_position = Vector2(round(center.x), round(center.y))
		queue_redraw()

	func _draw() -> void:
		var ink := Color(0.012, 0.009, 0.012, 0.9)
		var edge := Color(0.05, 0.04, 0.05, 0.8)
		# 上下压边：向画面中心渐隐。
		var i := 0
		while i < 18:
			var fade := 1.0 - float(i) / 18.0
			draw_rect(Rect2(-320, -180 + i, 640, 1), Color(ink.r, ink.g, ink.b, 0.85 * fade))
			draw_rect(Rect2(-320, 179 - i, 640, 1), Color(ink.r, ink.g, ink.b, 0.8 * fade))
			i += 1
		# 两侧近景石柱：内沿一道受光边。
		draw_rect(Rect2(-320, -180, 14, 360), ink)
		draw_rect(Rect2(306, -180, 14, 360), ink)
		draw_rect(Rect2(-306, -180, 2, 360), edge)
		draw_rect(Rect2(304, -180, 2, 360), edge)
		# 柱顶石托。
		draw_rect(Rect2(-320, -180, 22, 10), ink)
		draw_rect(Rect2(298, -180, 22, 10), ink)
