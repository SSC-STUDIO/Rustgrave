class_name BreakableTerrain
extends StaticBody2D
## 可破坏地形：一整块"裂石板"，按 32px 分块独立掉碰撞/贴图。
##
## 设计边界（见 docs/destruction.md）：
##   · 只有重击（blow=heavy/finisher）、爆炸/冲击波、Boss 砸地、或伤害 ≥2 的弹丸能伤到它；
##     轻击只出火星、不掉血（block_check 吃掉伤害）。
##   · 不进 `Interactable`，也不接管移动/路线：主线必经路径不得只靠打碎它通过。
##   · `persist_break=false`（默认）时重载即恢复；true 才把已碎块写进世界状态。
##
## 分块：每个 chunk 一条 CollisionShape2D + 一张 Sprite2D；根节点保留 Hurtbox 统一收伤，
## 按攻击者位置把伤害落到最近的一块上。
##
## M3 升级：
##   · `chunk_size` 允许 16/32 分块粒度（默认 32，不变旧行为）。
##   · `damage_area(center, radius, amount)`：爆炸/冲击波的面杀伤入口（见 Destruction）。
##   · `support_collapse`（默认 true）：一块碎掉后，同列正上方失去支撑的块连锁塌落；
##     塌落只出碎屑不重复播全碎旁白，读档恢复按记录逐块安静还原（记录已含塌落结果）。

const CHUNK := 32
const SKIN_TEX := {
	"stone": "res://assets/env/slab_a.png",
	"moss": "res://assets/env/moss_slab_a.png",
	"brick": "res://assets/env/brick_slab_a.png",
	"iron": "res://assets/env/iron_slab_a.png",
	"metal": "res://assets/env/iron_slab_a.png",
	"rampart": "res://assets/env/rampart_slab_a.png",
	"basalt": "res://assets/env/basalt_slab_a.png",
	"nave": "res://assets/env/nave_slab_a.png",
}

@export var size: Vector2 = Vector2(64, 32)
@export var skin: String = "stone"
## StaticBody2D 自带 `material`（CanvasItem 属性），所以材质声明统一用 `hit_material`。
@export var hit_material: StringName = &"stone"
@export var chunk_hp: int = 2
@export var persist_break: bool = false
## 分块粒度（像素）：16 = 细碎，32 = 默认。钳制在 8..64。
@export var chunk_size: int = CHUNK
## true = 一块碎掉后同列上方失去支撑的块连锁塌落（M3）。
@export var support_collapse: bool = true

var _cols := 0
var _rows := 0
var _cell := float(CHUNK)
var _hp: Array[int] = []
var _broken: Array[bool] = []
var _shapes: Array[CollisionShape2D] = []
var _sprites: Array[Sprite2D] = []
var _hurtbox: Hurtbox
var _last_attacker: Node = null
## 塌落重入防护：_break_chunk → _collapse_unsupported → _break_chunk 的嵌套
## 摊平成最外层一次迭代，避免深列时的调用栈嵌套。
var _collapsing := false
## 全碎通知只发一次（塌落连锁里最后一块和触发块都会走到 _on_fully_broken）。
var _fully_notified := false


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	add_to_group(&"breakable_terrain")
	if persist_break:
		add_to_group(&"persistent")
	_build()


func _build() -> void:
	_cell = clampf(float(chunk_size), 8.0, 64.0)
	_cols = maxi(1, int(ceil(size.x / _cell)))
	_rows = maxi(1, int(ceil(size.y / _cell)))
	var tex: Texture2D = null
	var tex_path := String(SKIN_TEX.get(skin, SKIN_TEX["stone"]))
	if ResourceLoader.exists(tex_path):
		tex = DensityTextures.load_texture(tex_path)
	for row in _rows:
		for col in _cols:
			var cell_size := Vector2(
				minf(_cell, size.x - col * _cell),
				minf(_cell, size.y - row * _cell))
			var corner := Vector2(col * _cell, row * _cell)
			var spr := Sprite2D.new()
			spr.name = "Chunk_%d_%d" % [col, row]
			spr.centered = false
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			if tex != null:
				spr.texture = tex
				spr.region_enabled = true
				spr.region_rect = Rect2(0, 0, cell_size.x, cell_size.y)
			var tint := 1.0 + float((col + row) % 2) * 0.04
			spr.modulate = Color(tint, tint, tint)
			spr.position = corner
			spr.z_index = 1
			add_child(spr)
			_sprites.append(spr)
			var shape := CollisionShape2D.new()
			var rect := RectangleShape2D.new()
			rect.size = cell_size
			shape.shape = rect
			shape.position = corner + cell_size * 0.5
			add_child(shape)
			_shapes.append(shape)
			_hp.append(chunk_hp)
			_broken.append(false)
	_hurtbox = Hurtbox.new()
	_hurtbox.name = "Hurtbox"
	_hurtbox.team = &"prop"
	_hurtbox.damage_owner_path = NodePath("..")
	_hurtbox.block_check = Callable(self, "_block_check")
	var hurt_shape := CollisionShape2D.new()
	var hurt_rect := RectangleShape2D.new()
	hurt_rect.size = size
	hurt_shape.shape = hurt_rect
	hurt_shape.position = size * 0.5
	_hurtbox.add_child(hurt_shape)
	add_child(_hurtbox)
	_hurtbox.hurt.connect(_on_hurt)


## Hurtbox 的否决口：返回 true = 这刀不扣血（轻击/普通弹丸只出火星）。
func _block_check(attacker: Object, amount: int) -> bool:
	if attacker is Hitbox:
		var blow := (attacker as Hitbox).blow
		if blow == &"heavy" or blow == &"finisher":
			return false
		return true
	if attacker is Projectile:
		return int((attacker as Projectile).damage) < 2
	if amount >= 2:
		return false
	return true


func _on_hurt(amount: int, attacker: Node) -> void:
	var point := global_position + size * 0.5
	var source := attacker as Node2D
	if source != null:
		point = source.global_position
		_last_attacker = attacker
	if not _accepts(attacker):
		# 轻击：只在表面崩一点火星，不记伤害。
		Fx.impact(hit_material, point, Vector2.UP, &"light")
		return
	var index := _nearest_chunk(point)
	if index < 0:
		return
	# 剑：每一下算 1 点（重击两下破一块）；爆炸/高伤弹丸按实际伤害算。
	var damage := 1
	if attacker is Projectile:
		damage = maxi(1, amount)
	var hp_before := _hp[index]
	damage_chunk(index, damage)
	if not _broken[index] and _hp[index] < hp_before:
		# 打实了但没碎：崩一处轻量材质反馈 + 该块变暗（受损读得出来）。
		Fx.impact(hit_material, point, Vector2.UP, &"light")
		_dim_chunk(index)


func _accepts(attacker: Object) -> bool:
	if attacker == null:
		return false
	if attacker is Hitbox:
		var blow := (attacker as Hitbox).blow
		return blow == &"heavy" or blow == &"finisher"
	if attacker is Projectile:
		return int((attacker as Projectile).damage) >= 2
	var amount: Variant = attacker.get(&"damage")
	return amount is int and int(amount) >= 2


func _nearest_chunk(point: Vector2) -> int:
	var best := -1
	var best_d := INF
	for i in _broken.size():
		if _broken[i]:
			continue
		var col := i % _cols
		var row := int(i / _cols)
		var center := global_position + Vector2((col + 0.5) * _cell, (row + 0.5) * _cell)
		var d := center.distance_squared_to(point)
		if d < best_d:
			best_d = d
			best = i
	return best


## 面杀伤（M3）：爆破/冲击波对半径内所有完好块造成伤害，返回碎块数。
## 与 Hurtbox 的"最近一块"规则互补：单点命中走 _on_hurt，范围伤害走这里。
func damage_area(center: Vector2, radius: float, amount: int) -> int:
	var broken := 0
	for i in _broken.size():
		if _broken[i]:
			continue
		var col := i % _cols
		var row := int(i / _cols)
		var chunk_center := global_position + Vector2((col + 0.5) * _cell, (row + 0.5) * _cell)
		if chunk_center.distance_to(center) <= radius and damage_chunk(i, amount):
			broken += 1
	return broken


## 对某一块造成伤害；hp<=0 时掉该块碰撞/贴图并出碎屑。返回是否打碎。
func damage_chunk(index: int, amount: int) -> bool:
	if index < 0 or index >= _hp.size() or _broken[index]:
		return false
	_hp[index] = maxi(0, _hp[index] - amount)
	if _hp[index] > 0:
		return false
	_break_chunk(index)
	return true


## 受击未碎的块变暗一档：不用新贴图就能读出"这块裂了"。
func _dim_chunk(index: int) -> void:
	if index < _sprites.size() and is_instance_valid(_sprites[index]):
		_sprites[index].modulate *= Color(0.78, 0.78, 0.82)


func _break_chunk(index: int, quiet: bool = false) -> void:
	_broken[index] = true
	var col := index % _cols
	var row := int(index / _cols)
	var cell_size := Vector2(
		minf(_cell, size.x - col * _cell),
		minf(_cell, size.y - row * _cell))
	var center := global_position + Vector2(col * _cell + cell_size.x * 0.5,
			row * _cell + cell_size.y * 0.5)
	if index < _shapes.size() and is_instance_valid(_shapes[index]):
		_shapes[index].disabled = true
		_shapes[index].queue_free()
	if index < _sprites.size() and is_instance_valid(_sprites[index]):
		_sprites[index].visible = false
	if not quiet:
		# 定向碎屑：远离最后攻击者；正上方出手的老路径不受影响（无攻击者时仍向上）。
		var away := Vector2.UP
		if _last_attacker is Node2D and is_instance_valid(_last_attacker):
			var delta: Vector2 = center - (_last_attacker as Node2D).global_position
			if delta.length_squared() > 1.0:
				away = delta.normalized()
		Fx.impact(hit_material, center, away, &"heavy")
		Fx.burst(&"stone" if hit_material == &"stone" else &"rust", center, away.angle())
	if support_collapse:
		_collapse_unsupported(quiet)
	if broken_chunks() >= _broken.size():
		_on_fully_broken(quiet)


## 列式重力（M3）：非底行、正下方块已碎的块失去支撑，连锁塌落。
## 塌落走正常 _break_chunk（出碎屑），但 quiet 恢复路径全程安静；
## 全碎旁白仍只由 _on_fully_broken 播一次。
func _collapse_unsupported(quiet: bool = false) -> void:
	if _collapsing:
		return
	_collapsing = true
	var changed := true
	while changed:
		changed = false
		for col in _cols:
			var row := _rows - 2
			while row >= 0:
				var index := row * _cols + col
				if not _broken[index] and _broken[index + _cols]:
					_break_chunk(index, quiet)
					changed = true
				row -= 1
	_collapsing = false


func _on_fully_broken(quiet: bool = false) -> void:
	if _fully_notified:
		return
	_fully_notified = true
	if _hurtbox != null:
		_hurtbox.set_deferred("monitoring", false)
	if quiet:
		return
	# 整板坍塌是 finisher 级反馈：短慢镜头（低优先级，不压弹反/死亡演出）。
	Juice.slow_mo(110, 0.3, Juice.PRIORITY_HIT)
	Juice.shake(3.2, 160)
	GameEvents.announcement.emit("裂石板碎成了粉尘，后面的路露了出来。")
	if persist_break:
		var player := get_tree().get_first_node_in_group(&"player") as Node
		if player != null:
			SaveData.persist_progress(player)


func broken_chunks() -> int:
	var n := 0
	for b in _broken:
		if b:
			n += 1
	return n


func chunk_count() -> int:
	return _broken.size()


func chunk_hp_left(index: int) -> int:
	if index < 0 or index >= _hp.size():
		return 0
	return _hp[index]


func is_chunk_broken(index: int) -> bool:
	return index >= 0 and index < _broken.size() and _broken[index]


func is_destroyed() -> bool:
	return chunk_count() > 0 and broken_chunks() >= chunk_count()


func get_persistent_state() -> Dictionary:
	var broken: Array[int] = []
	for i in _broken.size():
		if _broken[i]:
			broken.append(i)
	return {"broken": broken}


func apply_persistent_state(state: Dictionary) -> void:
	var raw: Variant = state.get("broken", [])
	if not (raw is Array):
		return
	for value in (raw as Array):
		var index := int(value)
		if index >= 0 and index < _broken.size() and not _broken[index]:
			_break_chunk(index, true)
