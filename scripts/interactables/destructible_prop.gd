class_name DestructibleProp
extends StaticBody2D
## 可砍碎的环境道具（碎铁堆 / 锈罐 / 腐藤结）。
##
## 结构：StaticBody2D（挡路 + 能被火球射线看见）+ Sprite2D + CollisionShape2D
##       + Hurtbox（layer 32，任何非 &"prop" 队伍都能打）+ Health。
## 破坏时：材质打击表现（Fx.impact）+ 碎屑 + 小回血 + 旁白；`persist=true` 时
## 把 destroyed 记进世界状态（SaveData.persist_progress）。从不参与必需路线判定：
## 关卡只把它们放在支路/角落。

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
		_rebuild_visuals()


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
		if old is Sprite2D or old is CollisionShape2D:
			old.queue_free()
	_sprite = Sprite2D.new()
	_sprite.name = "Body"
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var tex_path: String = _def.get("texture", "")
	if ResourceLoader.exists(tex_path):
		var tex := ArtTexture.load_texture(tex_path)
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


func _on_hurt(_amount: int, _attacker: Node) -> void:
	# 命中瞬间只做白闪；材质打击/碎屑留到真正破碎那一下，避免同一刀两套特效。
	_flash()


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
	if is_instance_valid(_health):
		_health.queue_free()
	var center := global_position + Vector2(0.0, -8.0)
	Fx.impact(hit_material, center, Vector2.UP, &"heavy")
	Fx.burst(&"rust" if hit_material == &"metal" else &"dirt", center)
	var player := get_tree().get_first_node_in_group(&"player") as Node
	var heal := int(_def.get("heal", 1))
	if player != null and heal > 0 and "health" in player:
		var player_health: Health = player.get(&"health") as Health
		if player_health != null:
			player_health.heal(heal)
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
