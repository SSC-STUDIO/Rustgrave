class_name Destruction
extends Object
## 破坏引擎 M3：统一的中性爆破源（爆破罐 / 连锁引爆 / 未来的环境爆炸）。
##
## 伤害路径与仓库既有模式一致（Player._spawn_temp_hitbox / exploder BlastHitbox）：
## 生成一个一帧寿命的圆形 Hitbox（layer 8 / mask 32，team=&"player"，blow=&"heavy"），
## 伤害自动流经 Hurtbox → block_check → Health 标准管线：
##   · 敌人（team=&"enemy"）受伤；
##   · 可破坏道具/裂石板（team=&"prop"）受伤 → 爆破罐因此能连锁引爆；
##   · 玩家（team=&"player"）与 Hitbox 同队被过滤 —— 爆破对玩家的中性伤害
##     由下面的直接 take_damage 负责（仍受 i-frame / assist_incoming 约束）。
## blow=&"heavy" 保证爆炸够到 BreakableTerrain 的破坏门槛；半径内的面杀伤
## 另走 BreakableTerrain.damage_area（单点 Hitbox 经最近块规则只能掉一块）。
##
## 连锁防护：同一进程帧最多 MAX_CHAIN_PER_FRAME 次爆破，超出直接丢弃
## （道具照碎，只是不再产生新的爆炸判定），防止密铺爆破罐同帧递归爆鸣。

const MAX_CHAIN_PER_FRAME := 4
const BLAST_LIFE := 0.1

static var _chain_frame := -1
static var _chain_count := 0


## 在 pos 引爆一次半径 radius 的爆破。返回生成的 Hitbox（被限流/宿主无效时 null）。
static func spawn_blast(host: Node, pos: Vector2, radius: float, damage: int = 1,
		material: StringName = &"metal") -> Hitbox:
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		return null
	var frame := Engine.get_process_frames()
	if frame != _chain_frame:
		_chain_frame = frame
		_chain_count = 0
	if _chain_count >= MAX_CHAIN_PER_FRAME:
		return null
	_chain_count += 1
	var tree := host.get_tree()
	if tree == null:
		return null
	# 表现：finisher 级材质打击 + 冲击环，全部走现有预算池（headless 只计数）。
	Fx.impact(material, pos, Vector2.UP, &"finisher")
	Fx.burst(&"ring", pos)
	var box := Hitbox.new()
	box.name = "DestructionBlast"
	box.damage = maxi(1, damage)
	box.team = &"player"
	box.blow = &"heavy"
	box.knockback = Vector2(0.0, -120.0)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	box.add_child(shape)
	var parent: Node = GameContext.world_effects(host)
	if parent == null:
		parent = host.get_parent()
	if parent == null:
		parent = host
	parent.add_child(box)
	box.global_position = pos
	# Hitbox._ready 会复位 monitoring/layer/mask：必须在入树之后再设
	# （Player._spawn_temp_hitbox 同款顺序，player.gd:677-679）。
	box.collision_layer = 8
	box.collision_mask = 32
	box.monitoring = true
	var tw := box.create_tween()
	tw.tween_interval(BLAST_LIFE)
	tw.tween_callback(box.queue_free)
	# 裂石板面杀伤：半径内所有完好块按爆炸当量掉耐久。
	for node in tree.get_nodes_in_group(&"breakable_terrain"):
		if node is BreakableTerrain:
			(node as BreakableTerrain).damage_area(pos, radius, maxi(2, damage))
	# 爆破不认队伍：玩家在半径内同样受伤（i-frame / 辅助减伤照常生效）。
	var player := tree.get_first_node_in_group(&"player")
	if player is Node2D \
			and (player as Node2D).global_position.distance_to(pos) <= radius + 8.0:
		var hp: Health = player.get(&"health") as Health
		if hp != null:
			hp.take_damage(maxi(1, damage), box)
	return box


## 测试/诊断：当前帧已发生的爆破次数。
static func chain_count_this_frame() -> int:
	return _chain_count if _chain_frame == Engine.get_process_frames() else 0
