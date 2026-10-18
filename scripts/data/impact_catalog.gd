extends Object
## 环境打击表现表：材质 → 火花/碎屑/贴花/音效/照明/震动。
##
## 只服务表现层：不改伤害、不改碰撞、不写存档。火球撞地与剑刃扫到地面/墙体/道具
## 都从这里取一份 profile；世界里的可破坏物只要带 `hit_material`（StringName）或
## `skin`（SolidPlatform 的材质名）就能被识别，无需各自实现特效。
##
## 材质名与 Sfx.SURFACES 同一口径（dirt/stone/metal/wet），另加 wood / bone 给
## 木箱、骨堆这类道具。未知材质一律回退 stone（和脚步声的兜底一致）。

## 每个材质的表现配置：
##   spark/debris : Fx.burst 的种类名（见 fx.gd 的 PooledMote.launch）
##   decal        : 地面/墙面留下的痕迹种类（decal_field.gd 画）
##   sfx/volume_db: 命中音与音量
##   light/energy : 短暂照明颜色与强度（加法混合的像素辉光）
##   shake        : 震动像素数（会再乘 Settings.shake_scale）
const MATERIALS := {
	&"dirt": {
		"spark": &"dirt", "debris": &"dirt", "decal": &"scorch",
		"sfx": &"land", "volume_db": -7.0,
		"light": Color(1.0, 0.62, 0.30), "energy": 0.55, "shake": 0.9,
	},
	&"stone": {
		"spark": &"stone", "debris": &"stone", "decal": &"chip",
		"sfx": &"plate_click", "volume_db": -5.0,
		"light": Color(0.92, 0.86, 0.74), "energy": 0.45, "shake": 1.0,
	},
	&"metal": {
		"spark": &"metal", "debris": &"rust", "decal": &"pit",
		"sfx": &"hit_metal", "volume_db": -6.0,
		"light": Color(1.0, 0.90, 0.58), "energy": 0.80, "shake": 0.8,
	},
	&"wet": {
		"spark": &"wetsplash", "debris": &"wetsplash", "decal": &"puddle",
		"sfx": &"splash", "volume_db": -8.0,
		"light": Color(0.42, 0.82, 0.92), "energy": 0.30, "shake": 0.4,
	},
	&"wood": {
		"spark": &"wood", "debris": &"wood", "decal": &"gash",
		"sfx": &"land", "volume_db": -7.0,
		"light": Color(1.0, 0.70, 0.40), "energy": 0.50, "shake": 0.9,
	},
	&"bone": {
		"spark": &"bone", "debris": &"bone", "decal": &"none",
		"sfx": &"hit_bone", "volume_db": -6.0,
		"light": Color(0.92, 0.90, 0.82), "energy": 0.40, "shake": 0.7,
	},
}

## 出手分量 → 表现倍率（粒子数量、震动、音量都乘它）。
const WEIGHT_SCALE := {
	&"light": 1.0,
	&"heavy": 1.55,
	&"finisher": 2.2,
}

const FALLBACK_MATERIAL := &"stone"
## 这些表面家族在表现层归到哪种材质（Sfx.SURFACES 的口径）。
const SURFACE_MATERIAL := {
	&"dirt": &"dirt",
	&"stone": &"stone",
	&"metal": &"metal",
	&"wet": &"wet",
	&"sludge": &"wet",
	&"wood": &"wood",
}


static func has_material(material: StringName) -> bool:
	return MATERIALS.has(material)


static func profile(material: StringName) -> Dictionary:
	if MATERIALS.has(material):
		return MATERIALS[material]
	return MATERIALS[FALLBACK_MATERIAL]


static func weight_scale(weight: StringName) -> float:
	return float(WEIGHT_SCALE.get(weight, 1.0))


## SolidPlatform.skin → 材质。Sfx.surface_for_skin 已经是唯一权威，这里只做
## surface → 表现材质的映射；未知 skin 回退 stone。
static func material_for_skin(skin: String) -> StringName:
	if skin == "":
		return FALLBACK_MATERIAL
	var surface: StringName = &"stone"
	if Sfx.has_method(&"surface_for_skin"):
		surface = StringName(Sfx.call(&"surface_for_skin", StringName(skin)))
	return StringName(SURFACE_MATERIAL.get(surface, FALLBACK_MATERIAL))


## 从一个碰撞体上读出打击材质，优先级：
##   1. 显式 `hit_material`（StringName，可破坏道具/裂石板直接声明）
##   2. 显式方法 impact_material()（给脚本化物体留的口子）
##   3. `skin`（SolidPlatform，走 Sfx.SURFACES 映射）
##   4. 节点的 meta "impact_material"
##   5. stone
static func material_for_collider(collider: Object) -> StringName:
	if collider == null or not is_instance_valid(collider):
		return FALLBACK_MATERIAL
	if collider.has_method(&"impact_material"):
		var via_method: Variant = collider.call(&"impact_material")
		if via_method is StringName and MATERIALS.has(via_method):
			return via_method
		if via_method is String and MATERIALS.has(StringName(via_method)):
			return StringName(via_method)
	var declared: Variant = collider.get(&"hit_material")
	if declared is StringName and MATERIALS.has(declared):
		return declared
	if declared is String and MATERIALS.has(StringName(declared)):
		return StringName(declared)
	var skin: Variant = collider.get(&"skin")
	if skin is String and skin != "":
		return material_for_skin(String(skin))
	if collider.has_meta(&"impact_material"):
		var meta: Variant = collider.get_meta(&"impact_material")
		if meta is StringName and MATERIALS.has(meta):
			return meta
		if meta is String and MATERIALS.has(StringName(meta)):
			return StringName(meta)
	return FALLBACK_MATERIAL
