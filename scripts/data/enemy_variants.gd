class_name EnemyVariants
extends RefCounted
## 敌人变体预设：同一套 AI 脚本，换血量 / 速度 / 前摇 / 材质 / 染色，再在头顶挂一枚小标记，
## 让同一种敌人在不同章节读起来不一样，而不新增 AI 状态机。
##
## 用法（章节布局里）：
##   enemy(host, "Crawler1", "scrapper", Vector2(900, 320), {"variant": &"armored_scrapper"})
##
## 规则：
##   · 变体只改 `@export` 数值、血量、受击材质和外观；前摇仍满足 CombatRules.TELEGRAPH_MIN；
##   · 预设里写的 props 在 `_enemy_ready()` 之前套上（计时器 / 子节点读得到新值），
##     血量、染色、标记在它之后套（`_enemy_ready` 里会写默认血量）；
##   · 染色走 FrameAnimSprite 的 self_modulate，不碰受击白闪用的 modulate；
##   · 不用小数缩放（像素素材只允许整数倍）；
##   · 基类脚本不匹配时拒绝套用并 push_warning，不会静默套错。
##
## 现有变体：装甲碎铁犬、疾行碎铁犬、重盾卫、散射喷吐者、爆裂骸骨（死后延迟爆开，读招后才伤人）。

const KIND_BY_SCRIPT := {
	"scrapper_enemy.gd": &"scrapper",
	"gear_shield_enemy.gd": &"gear_shield",
	"spitter_enemy.gd": &"spitter",
	"skeleton_enemy.gd": &"skeleton",
	"ghost_enemy.gd": &"ghost",
	"flying_demon_enemy.gd": &"flying_demon",
	"fire_skull_enemy.gd": &"fire_skull",
}

const TABLE := {
	&"armored_scrapper": {
		"base": &"scrapper", "label": "装甲碎铁犬", "hp": 5,
		"hit_material": &"armour",
		"tint": Color(0.8, 0.9, 1.2), "pip": Color(0.7, 0.86, 1.0),
		"props": {"charge_speed": 205.0, "windup_time": 0.55, "stun_time": 1.1},
	},
	&"swift_scrapper": {
		"base": &"scrapper", "label": "疾行碎铁犬", "hp": 2,
		"tint": Color(1.25, 1.0, 0.78), "pip": Color(1.0, 0.8, 0.3),
		"props": {"charge_speed": 285.0, "windup_time": 0.4, "aggro_range": 240.0,
				"re_aggro_cooldown": 0.9},
	},
	&"heavy_guard": {
		"base": &"gear_shield", "label": "重盾卫", "hp": 6,
		"tint": Color(0.86, 0.9, 1.12), "pip": Color(0.7, 0.86, 1.0),
		"props": {"stagger_time": 1.2, "shoot_interval": 3.0, "charge_time": 0.62},
	},
	&"scatter_spitter": {
		"base": &"spitter", "label": "散射喷吐者", "hp": 2,
		"pip": Color(0.55, 1.0, 0.5),
		"props": {"burst": 3, "spread_deg": 15.0, "shoot_interval": 2.7, "projectile_speed": 128.0},
	},
	&"exploder_skeleton": {
		"base": &"skeleton", "label": "爆裂骸骨", "hp": 2,
		"tint": Color(1.3, 0.86, 0.72), "pip": Color(1.0, 0.36, 0.25), "blast": true,
		"props": {"walk_speed": 44.0},
	},
}


static func has_variant(id: StringName) -> bool:
	return TABLE.has(id)


static func preset(id: StringName) -> Dictionary:
	return (TABLE.get(id, {}) as Dictionary).duplicate(true)


static func label_of(id: StringName) -> String:
	return String((TABLE.get(id, {}) as Dictionary).get("label", ""))


static func variants_for(kind: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in TABLE:
		if (TABLE[id] as Dictionary).get("base", &"") == kind:
			out.append(id)
	return out


## 这个敌人是哪一类（按脚本文件名，不引用具体类，避免和 EnemyBase 循环依赖）。
static func kind_of(enemy: Object) -> StringName:
	if enemy == null:
		return &""
	var script := enemy.get_script() as Script
	while script != null:
		var key := script.resource_path.get_file()
		if KIND_BY_SCRIPT.has(key):
			return KIND_BY_SCRIPT[key]
		script = script.get_base_script()
	return &""


## `_enemy_ready()` 之前调用：数值 / 材质。返回是否套上了。
static func apply_pre(enemy: Node, id: StringName) -> bool:
	if id == &"":
		return false
	if not TABLE.has(id):
		push_warning("EnemyVariants: unknown variant '%s' on %s" % [id, enemy.name])
		return false
	var data: Dictionary = TABLE[id]
	if data.get("base", &"") != kind_of(enemy):
		push_warning("EnemyVariants: '%s' is a %s variant, not for %s" % [id, data.get("base", &""), enemy.name])
		return false
	var props: Dictionary = data.get("props", {})
	for key in props:
		if key in enemy:
			enemy.set(key, props[key])
	if data.has("hit_material"):
		enemy.set("hit_material", data["hit_material"])
	return true


## `_enemy_ready()` 之后调用：血量、染色、头顶标记、死亡爆裂标记。
static func apply_post(enemy: EnemyBase, id: StringName) -> void:
	if not TABLE.has(id):
		return
	var data: Dictionary = TABLE[id]
	if data.get("base", &"") != kind_of(enemy):
		return
	if data.has("hp") and enemy.health != null:
		enemy.health.max_hp = int(data["hp"])
		enemy.health.heal_full()
	if data.has("hit_material"):
		enemy.hit_material = data["hit_material"]
	var tint: Color = data.get("tint", Color.WHITE)
	if tint != Color.WHITE:
		var sprite: CanvasItem = enemy._anim if enemy._anim != null else null
		if sprite != null:
			sprite.self_modulate = tint
	if bool(data.get("blast", false)):
		enemy.set_meta("variant_blast", true)
	enemy.set_meta("variant", id)
	if enemy.get_node_or_null("VariantPip") == null:
		var pip := VariantPip.new()
		pip.name = "VariantPip"
		pip.color = data.get("pip", Color.WHITE)
		pip.position = enemy.call("_mark_offset") + Vector2(0.0, -8.0)
		enemy.add_child(pip)


## 爆裂变体死亡：原地留一团读招 0.7s 的警示，之后 0.18s 爆开伤人。
static func death_blast(enemy: EnemyBase) -> void:
	if enemy == null or not enemy.is_inside_tree():
		return
	var host := GameContext.world_effects(enemy)
	if host == null:
		host = enemy.get_parent()
	if host == null:
		return
	var blast := DeathBlast.new()
	blast.name = "DeathBlast_%s" % enemy.name
	host.add_child(blast)
	blast.global_position = enemy.global_position


## 头顶一枚 3×3 的小菱形：玩家一眼分得出「这只和普通的不一样」。
class VariantPip extends Node2D:
	var color: Color = Color.WHITE

	func _ready() -> void:
		z_index = 4

	func _draw() -> void:
		var dark := Color(0.05, 0.04, 0.04, 0.9)
		draw_rect(Rect2(-3, -1, 7, 3), dark)
		draw_rect(Rect2(-1, -3, 3, 7), dark)
		draw_rect(Rect2(-2, 0, 5, 1), color)
		draw_rect(Rect2(0, -2, 1, 5), color)


## 爆裂骸骨的死亡爆炸。内嵌类不引用外层 class_name；读招用 CombatMarker，判定用 Hitbox。
class DeathBlast extends Node2D:
	const WARN := 0.7
	const ACTIVE := 0.18
	const SIZE := Vector2(60.0, 36.0)

	var _t := 0.0
	var _box: Hitbox

	func _ready() -> void:
		z_index = 3
		CombatMarker.spawn(self, CombatMarker.Kind.ZONE, Vector2(0.0, -SIZE.y * 0.5), WARN,
				Color(1.0, 0.42, 0.2, 0.95), {"rect": Rect2(-SIZE * 0.5, SIZE)})
		queue_redraw()

	func _physics_process(delta: float) -> void:
		if Director.is_input_locked():
			return
		_t += delta
		if _box == null and _t >= WARN:
			_fire()
		if _t >= WARN + ACTIVE:
			if _box != null:
				_box.disarm()
			queue_free()
			return
		queue_redraw()

	func _fire() -> void:
		_box = Hitbox.new()
		_box.name = "BlastHitbox"
		_box.damage = 1
		_box.team = &"enemy"
		_box.blow = &"light"
		var shape := CollisionShape2D.new()
		shape.name = "CollisionShape2D"
		var rect := RectangleShape2D.new()
		rect.size = SIZE
		shape.shape = rect
		shape.position = Vector2(0.0, -SIZE.y * 0.5)
		_box.add_child(shape)
		add_child(_box)
		_box.arm(Vector2(0.0, -140.0))
		Fx.burst(&"ember", global_position)
		Fx.burst(&"spark", global_position)
		Sfx.play_at(&"boss_axe_slam", global_position, 0.1, -8.0)
		Juice.shake(2.0, 100)

	func _draw() -> void:
		if _t < WARN:
			var k := clampf(_t / WARN, 0.0, 1.0)
			var blink := 0.5 + 0.5 * sin(_t * lerpf(10.0, 36.0, k))
			draw_rect(Rect2(-4.0, -6.0 - 8.0 * k, 8.0, 6.0 + 8.0 * k),
					Color(1.0, 0.5, 0.2, (0.3 + 0.5 * k) * blink))
		else:
			var a := 1.0 - clampf((_t - WARN) / ACTIVE, 0.0, 1.0)
			draw_rect(Rect2(-SIZE.x * 0.5, -SIZE.y, SIZE.x, SIZE.y), Color(1.0, 0.7, 0.3, 0.55 * a))
			draw_rect(Rect2(-SIZE.x * 0.3, -SIZE.y * 0.8, SIZE.x * 0.6, SIZE.y * 0.6),
					Color(1.0, 0.95, 0.7, 0.9 * a))
