extends RefCounted
## 各章专属机关与一个敌人变体。加在已有布局的末尾，不挪被测试锁死的地面、
## 不增加 Enemies 的子节点。落点都避开余烬巢、压板、门、碑和出口（LevelSanity 净空）。
##
## 不注册 class_name：章节脚本用 preload 调用，避免全局类缓存没刷新时整关解析失败。


static func dress(layout: Object, host: Node2D) -> void:
	if layout == null or host == null or not is_instance_valid(host):
		return
	if host.has_meta(&"chapter_overhaul"):
		return
	host.set_meta(&"chapter_overhaul", true)
	var id := ""
	if layout.has_method(&"level_id"):
		id = String(layout.call(&"level_id"))
	var kit := layout as ChapterLayout
	var borrowed := kit != null
	if not borrowed:
		kit = ChapterLayout.new()
	_place(kit, host, id)
	_variant(host, id)
	if not borrowed and is_instance_valid(kit):
		kit.free()


static func _place(kit: ChapterLayout, host: Node2D, id: String) -> void:
	match id:
		"level02":
			# 沉钟前厅地面（FloorD 1600–2480），落在壁龛与回廊巢之间。
			kit.cyclic(host, "OverhaulBell", Vector2(2320, 320), "bell", {"phase": 0.15})
		"level02b":
			# 水闸广场东段的地面，压板与桥前巢之间。涌流向下游，一阵一阵来。
			kit.force_zone(host, "SluiceSurge", Rect2(880, 292, 100, 40), "water",
					Vector2(52, 0), {"gust_period": 3.0, "gust_duty": 0.45, "phase": 0.0})
		"level03":
			# 死街地面。坠钟不是实体，平时不挡路；判定只在落下的那一下。
			kit.cyclic(host, "StreetBell", Vector2(3320, 320), "bell", {"phase": 0.4})
		"level04":
			# 中殿地面（FloorC）。冲击波带在唱诗巢与讲坛之间，不盖到两边。
			kit.cyclic(host, "NaveShock", Vector2(1600, 320), "shock", {"phase": 0.2})
		"level04b":
			kit.cyclic(host, "BoneFlame", Vector2(1900, 320), "flame", {"phase": 0.25})
			_candle(kit, host)
		"level05":
			# 东车间地面（FloorE），闸门巢与吊机巢之间的空档。
			kit.cyclic(host, "QuenchSteam", Vector2(3100, 320), "steam", {"phase": 0.1})
			# 接在检修走道东头，和地面隔开，不挡主路。
			kit.conveyor(host, "BeltDeck", Vector2(3016, 208), 64.0, 40.0, "iron_float")
		"level06":
			# 东坟坡地面（FloorH），土丘东边、东巢西边。泥拖慢脚步，还带一点毒。
			kit.force_zone(host, "GraveMud", Rect2(3000, 300, 140, 36), "mud",
					Vector2.ZERO, {"drag": 0.55, "toxin_per_second": 16.0})
		"level07":
			# 井底偏左的空档，摆幅落不到入口碑，也碰不到右边的吊台。
			kit.pendulum(host, "Clapper", Vector2(200, 40), 100.0,
					{"swing_deg": 28.0, "period": 3.2, "phase": 0.0})
		"level07b":
			# 浇包廊地面（FloorB），浇包巢与钟模碑之间。
			kit.cyclic(host, "LadleFlame", Vector2(1000, 320), "flame", {"phase": 0.35})
		"level08":
			# 渣堤地面（FloorB），碎铁犬与东侧浮石之间。
			kit.cyclic(host, "SlagMouth", Vector2(1040, 320), "slag", {"phase": 0.2})
		"level09":
			# 第一段城墙地面（FloorB），箭楼东边、中巢西边。阵风往东推。
			kit.force_zone(host, "WallWind", Rect2(1020, 292, 100, 40), "wind",
					Vector2(44, 0), {"gust_period": 2.6, "gust_duty": 0.55, "phase": 0.0})
		"level09b":
			# 崖底灰道。上面的巢都在高台上，这段灰道没有休息点。
			kit.force_zone(host, "CliffEmber", Rect2(860, 292, 140, 40), "ember",
					Vector2(28, -80), {"gust_period": 2.4, "gust_duty": 0.5, "phase": 0.1})
		"level10":
			# 炉心竞技场西侧地面，离门、巢和梦魇落点都有一段。
			kit.cyclic(host, "CorePulse", Vector2(2100, 320), "flame", {"phase": 0.5})


## 烛台喷口旁边一块平时不存在的台阶。走到烛火旁才现形。
static func _candle(kit: ChapterLayout, host: Node2D) -> void:
	kit.cyclic(host, "CandleMouth", Vector2(900, 320), "flame",
			{"phase": 0.0, "reach": 36.0, "hint_id": &"candle"})
	var step := kit.platform(host, "CandleStep", Vector2(1040, 288), Vector2(48, 16), "nave_float")
	var watch := Area2D.new()
	watch.name = "CandleWatch"
	watch.set_script(load("res://scripts/levels/candle_watch.gd"))
	watch.position = Vector2(960, 300)
	watch.set("step", step)
	kit.group(host, "Props").add_child(watch)


## 水闸广场那只碎铁犬的巡逻圈是按基础仇恨留的，起点巢贴着它。
## 疾行变体仇恨更远，改套在下一只上，免得冲进余烬巢。
const SKIP_MATCHES := {"level02b": 1}


## 每个章节给一只对得上的敌人套一个预设。套不上就跳过，不警告、不加节点。
static func _variant(host: Node2D, id: String) -> void:
	var variant := StringName(VARIANTS.get(id, &""))
	if variant == &"" or not EnemyVariants.has_variant(variant):
		return
	var enemies := host.get_node_or_null("Enemies")
	if enemies == null:
		return
	var base: StringName = EnemyVariants.preset(variant).get("base", &"")
	var skip := int(SKIP_MATCHES.get(id, 0))
	for child in enemies.get_children():
		var enemy := child as EnemyBase
		if enemy == null:
			continue
		if EnemyVariants.kind_of(enemy) != base:
			continue
		if String(enemy.get_meta("variant", "")) != "":
			continue
		if skip > 0:
			skip -= 1
			continue
		enemy.variant = variant
		if enemy.is_node_ready():
			EnemyVariants.apply_pre(enemy, variant)
			EnemyVariants.apply_post(enemy, variant)
		return


const VARIANTS := {
	"level02": &"armored_scrapper",
	"level02b": &"swift_scrapper",
	"level03": &"armored_scrapper",
	"level04": &"scatter_spitter",
	"level04b": &"exploder_skeleton",
	"level05": &"armored_scrapper",
	"level06": &"exploder_skeleton",
	"level07": &"heavy_guard",
	"level07b": &"scatter_spitter",
	"level08": &"armored_scrapper",
	"level09": &"swift_scrapper",
	"level09b": &"swift_scrapper",
	"level10": &"scatter_spitter",
}
