class_name DestructibleProp
extends StaticBody2D
## 可砍碎的环境道具（碎铁堆 / 锈罐 / 腐藤结）。
##
## 结构：StaticBody2D（挡路 + 能被火球射线看见）+ Sprite2D + CollisionShape2D
##       + Hurtbox（layer 32，任何非 &"prop" 队伍都能打）+ Health。
## 破坏时：材质打击表现（Fx.impact）+ 碎屑 + 小回血 + 旁白；`persist=true` 时
## 把 destroyed 记进世界状态（SaveData.persist_progress）。从不参与必需路线判定：
## 关卡只把它们放在支路/角落。
##
## M3 升级：
##   · catalog 带 `blast` 的道具破碎时经 Destruction.spawn_blast 引爆（可连锁）；
##   · `drops.ember` 经 EmberProgress.award_xp 掉落余烬经验；
##   · 破坏碎屑沿"远离最后攻击者"方向喷溅；
##   · HP 降至一半以下时挂程序化裂纹覆盖层（无新美术资源）。

const Catalog := preload("res://scripts/data/destructible_catalog.gd")

@export var prop_id: StringName = &"scrap_heap"
## true = 打碎后写进存档；false = 重载恢复（默认用于临时场景/测试）。
@export var persist: bool = true

## ImpactCatalog 读取：火球/剑砍在道具上按这个材质出表现。
var hit_material: StringName = &"metal"

var _def: Dictionary = {}
var _max_hp: int = 2
var _destroyed := false
var _health: Health
var _hurtbox: Hurtbox
var _sprite: Sprite2D
var _flash_tween: Tween
var _last_attacker: Node = null
var _cracks: Node2D = null


func _ready() -> void:
	hit_material = _resolve_material()
	add_to_group(&"destructible_body")
	if persist:
		add_to_group(&"persistent")
	collision_layer = 1
	collision_mask = 0
	_build()


func configure(id: StringName) -> void:
	prop_id = id
	if is_inside_tree():
		# 允许在 add_child 之后再指定：重建一次外观与耐久。
		_def = Catalog.def(prop_id)
		hit_material = _resolve_material()
		_max_hp = int(_def.get("max_hp", 2))
		_rebuild_visuals()
		if _health != null and is_instance_valid(_health):
			_health.max_hp = _max_hp
			_health.current = _max_hp


func _resolve_material() -> StringName:
	_def = Catalog.def(prop_id)
	var material: StringName = StringName(_def.get("material", &"metal"))
	return material


func _build() -> void:
	_def = Catalog.def(prop_id)
	hit_material = _resolve_material()
	_max_hp = int(_def.get("max_hp", 2))
	_rebuild_visuals()
	# 耐久：Hurtbox 负责扣血，Health.died 触发破碎。
	_health = Health.new()
	_health.name = "Health"
	_health.max_hp = _max_hp
	add_child(_health)
	_health.died.connect(_on_died)
	_hurtbox = Hurtbox.new()
	_hurtbox.name = "Hurtbox"
	_hurtbox.team = &"prop"
	_hurtbox.damage_owner_path = NodePath("..")
	var hurt_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = _def.get("size", Vector2(20, 18))
	hurt_shape.shape = rect
	hurt_shape.position = Vector2(0.0, -rect.size.y * 0.5)
	_hurtbox.add_child(hurt_shape)
	add_child(_hurtbox)
	_hurtbox.hurt.connect(_on_hurt)


func _rebuild_visuals() -> void:
	var size: Vector2 = _def.get("size", Vector2(20, 18))
	for old in get_children():
		if old is Sprite2D or old is CollisionShape2D or old == _cracks:
			old.queue_free()
	_cracks = null
	_sprite = Sprite2D.new()
	_sprite.name = "Body"
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var tex_path: String = _def.get("texture", "")
	if ResourceLoader.exists(tex_path):
		var tex := DensityTextures.load_texture(tex_path)
		if tex != null:
			_sprite.texture = tex
			var region: Rect2 = _def.get("region", Rect2())
			if region.has_area():
				_sprite.region_enabled = true
				_sprite.region_rect = region
				_sprite.scale = Vector2(size.x / region.size.x, size.y / region.size.y)
			else:
				_sprite.scale = Vector2(size.x / tex.get_width(), size.y / tex.get_height())
	_sprite.centered = false
	_sprite.position = Vector2(-size.x * 0.5, -size.y)
	add_child(_sprite)
	var body_shape := CollisionShape2D.new()
	var body_rect := RectangleShape2D.new()
	body_rect.size = size
	body_shape.shape = body_rect
	body_shape.position = Vector2(0.0, -size.y * 0.5)
	add_child(body_shape)
	_sprite.z_index = 1


func _on_hurt(_amount: int, attacker: Node) -> void:
	_last_attacker = attacker
	# 命中瞬间只做白闪；hurt 信号先于扣血发出，受损反馈推迟到本帧结算后再评。
	_flash()
	_after_hit.call_deferred()


## 扣血结算后评估：未致命才补材质反馈；HP 过半损失挂裂纹；致命由 _break 统一表现。
func _after_hit() -> void:
	if _destroyed or _health == null or not is_instance_valid(_health):
		return
	if _health.current <= 0:
		return
	var point := global_position + Vector2(0.0, -8.0)
	if _last_attacker is Node2D and is_instance_valid(_last_attacker):
		point = (_last_attacker as Node2D).global_position
	Fx.impact(hit_material, point, Vector2.UP, &"light")
	if _health.current <= ceili(_max_hp * 0.5):
		_show_cracks()


## 受损过半：程序化裂纹覆盖层（1px 深色折线，确定性伪随机，不新增贴图）。
func _show_cracks() -> void:
	if _cracks != null and is_instance_valid(_cracks):
		return
	if _sprite == null or not is_instance_valid(_sprite):
		return
	var size: Vector2 = _def.get("size", Vector2(20, 18))
	_cracks = Node2D.new()
	_cracks.name = "Cracks"
	_cracks.z_index = 2
	var seed_value := int(hash(String(prop_id)))
	for i in 3:
		seed_value = int(seed_value * 1103515245 + 12345) & 0x7fffffff
		var line := Line2D.new()
		line.width = 1.0
		line.default_color = Color(0.12, 0.08, 0.06, 0.85)
		var x := -size.x * 0.5 + float(seed_value % maxi(4, int(size.x)))
		seed_value = int(seed_value * 1103515245 + 12345) & 0x7fffffff
		var y := -size.y + float(seed_value % maxi(4, int(size.y * 0.5)))
		line.points = PackedVector2Array([
			Vector2(x, y),
			Vector2(x + 3.0, y + size.y * 0.25),
			Vector2(x - 1.0, y + size.y * 0.5),
		])
		_cracks.add_child(line)
	add_child(_cracks)


## 测试/诊断：裂纹覆盖层是否已挂上。
func has_cracks() -> bool:
	return _cracks != null and is_instance_valid(_cracks)


func _flash() -> void:
	if _sprite == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_sprite.modulate = Color(1.6, 1.45, 1.35)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_sprite, "modulate", Color.WHITE, 0.12)


func _on_died() -> void:
	_break()


func _break() -> void:
	if _destroyed:
		return
	_destroyed = true
	if _hurtbox != null:
		_hurtbox.set_deferred("monitoring", false)
	if _sprite != null:
		_sprite.visible = false
	if _cracks != null and is_instance_valid(_cracks):
		_cracks.queue_free()
	if is_instance_valid(_health):
		_health.queue_free()
	var center := global_position + Vector2(0.0, -8.0)
	# 定向碎屑：远离最后攻击者；无攻击者（读档/脚本）保持向上。
	var away := Vector2.UP
	if _last_attacker is Node2D and is_instance_valid(_last_attacker):
		var delta: Vector2 = center - (_last_attacker as Node2D).global_position
		if delta.length_squared() > 1.0:
			away = delta.normalized()
	Fx.impact(hit_material, center, away, &"heavy")
	Fx.burst(&"rust" if hit_material == &"metal" else &"dirt", center, away.angle())
	# 爆破罐：破碎即引爆（中性爆破源，可连锁；每帧连锁上限见 Destruction）。
	var blast: Variant = _def.get("blast", {})
	if blast is Dictionary and not (blast as Dictionary).is_empty():
		Destruction.spawn_blast(self, center, float((blast as Dictionary).get("radius", 40.0)),
				maxi(1, int((blast as Dictionary).get("damage", 1))), hit_material)
	var player := get_tree().get_first_node_in_group(&"player") as Node
	var heal := int(_def.get("heal", 1))
	if player != null and heal > 0 and "health" in player:
		var player_health: Health = player.get(&"health") as Health
		if player_health != null:
			player_health.heal(heal)
	# M3 掉落：余烬经验（EmberProgress 是 autoload，award_xp 静态可调）。
	var drops: Variant = _def.get("drops", {})
	if drops is Dictionary:
		var ember := int((drops as Dictionary).get("ember", 0))
		if ember > 0:
			EmberProgress.award_xp(ember, &"destruction")
	var line := String(_def.get("announce", ""))
	if line != "":
		GameEvents.announcement.emit(line)
	if persist and player != null:
		SaveData.persist_progress(player)
	queue_free()


func is_destroyed() -> bool:
	return _destroyed


## 脚点（LevelSanity / 放置测试用）。
func feet_point() -> Vector2:
	return global_position


func get_persistent_state() -> Dictionary:
	return {"destroyed": _destroyed}


func apply_persistent_state(state: Dictionary) -> void:
	if bool(state.get("destroyed", false)) and not _destroyed:
		_destroyed = true
		queue_free()
