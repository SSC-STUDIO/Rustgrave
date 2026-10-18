class_name CombatRules
extends RefCounted
## 战斗数值与反馈矩阵的唯一数据源。纯数据 + 几个无状态的小函数，不持有节点。
## docs/combat-rules.md 逐表镜像这里的数字；tests/combat_rules_test.gd 在两边
## 漂移时失败，所以改数值必须连文档一起改。

# ---------------------------------------------------------------------------
# 挥砍帧表（秒）。下标 = 连段步 0..2；第三刀是终结击。
# ---------------------------------------------------------------------------
const SWING_WINDUP: Array = [0.18, 0.14, 0.30]
const SWING_ACTIVE: Array = [0.12, 0.12, 0.17]
const SWING_RECOVERY: Array = [0.26, 0.20, 0.46]
const SWING_DAMAGE: Array = [1, 1, 2]
const SWING_BLOW: Array[StringName] = [&"light", &"light", &"finisher"]
## 空闲时重新起手的冷却，从后摇开始计时（连段按键不受它限制）。
const SWING_COOLDOWN := 0.40
## 空闲冷却期内按下的攻击最多缓冲这么久。
const ATTACK_BUFFER := 0.16
## 前两刀判定期最后这段时间起、以及整个后摇，可预输入下一刀（队列最多一刀）。
const LINK_EARLY := 0.12
## 后摇刚结束后这段时间内按下，仍算接上一刀（而不是等冷却）。
const LATE_LINK_GRACE := 0.10
## 任意挥砍阶段玩家水平速度的倍率（player.gd move_scale）。
const SWING_MOVE_SCALE := 0.42

# ---------------------------------------------------------------------------
# 位移表
# ---------------------------------------------------------------------------
const DASH_DURATION := 0.13
const DASH_IFRAMES := 0.13
const DASH_COOLDOWN := 0.42
## 冲刺预输入：只在取消窗口临近时有用，过期即丢，从不缩短已承诺的阶段。
const DASH_BUFFER := 0.12
const COYOTE_TIME := 0.12
const JUMP_BUFFER := 0.14
## 受击后的无敌（Health.hit_iframe_time）。
const HIT_IFRAMES := 0.45

# ---------------------------------------------------------------------------
# 取消窗口（后摇进度 0 = 后摇开始，1 = 后摇结束）。前摇、判定期任何动作都不能取消。
# ---------------------------------------------------------------------------
## 挥空：后摇过 60% 才能冲刺取消；命中（或弹反）后从后摇开头就能冲刺取消。
const DASH_CANCEL_FROM := 0.60
const DASH_CANCEL_FROM_CONNECTED := 0.0
## 跳跃取消后摇：挥空要从 60% 起；打实（命中或弹反）从后摇开头就能收刀起跳。
const JUMP_CANCEL_FROM := 0.60
const JUMP_CANCEL_FROM_CONNECTED := 0.0

# ---------------------------------------------------------------------------
# 弹反与破绽
# ---------------------------------------------------------------------------
## 弹反成功：从毒素条扣除的比例、共鸣时长、慢动作。
const PARRY_PURIFY := 0.12
const PARRY_RESONANCE := 2.0
const PARRY_SLOWMO_MS := 120
const PARRY_SLOWMO_SCALE := 0.25
## 被弹回的弹丸命中（或被盾挡下）后敌人露出的破绽：窗口内第一击伤害翻倍。
const RIPOSTE_TIME := 1.2
const RIPOSTE_MULT := 2
## 非盾类敌人被弹丸打中后的硬直（盾类走自己的 stagger_time）。
const RIPOSTE_STAGGER := 0.55

# ---------------------------------------------------------------------------
# 毒素档位：奖励（伤害、位移、钩程、剑光）与风险（满溢掉血）都读这张表。
# ---------------------------------------------------------------------------
const TOXIN_TIERS := {
	&"cold": {"damage": 0, "finisher_knock": 1.0, "dash": 1.0, "hook": 1.0,
		"arc_color": Color(1.0, 0.92, 0.78, 0.5), "arc_scale": 0.6,
		"tint": Color(1.0, 1.0, 1.0), "ember_chance": 0.0,
		"weight_up": false, "flicker": false, "warn": false},
	&"warm": {"damage": 1, "finisher_knock": 1.0, "dash": 1.12, "hook": 1.2,
		"arc_color": Color(1.35, 0.95, 0.55, 0.62), "arc_scale": 0.68,
		"tint": Color(1.12, 0.96, 0.85), "ember_chance": 0.0,
		"weight_up": true, "flicker": false, "warn": false},
	&"hot": {"damage": 1, "finisher_knock": 1.35, "dash": 1.12, "hook": 1.2,
		"arc_color": Color(1.75, 0.78, 0.32, 0.76), "arc_scale": 0.78,
		"tint": Color(1.28, 0.88, 0.62), "ember_chance": 0.12,
		"weight_up": true, "flicker": false, "warn": false},
	&"overflow": {"damage": 1, "finisher_knock": 1.35, "dash": 1.12, "hook": 1.2,
		"arc_color": Color(1.9, 0.38, 0.3, 0.9), "arc_scale": 0.84,
		"tint": Color(1.4, 0.66, 0.56), "ember_chance": 0.2,
		"weight_up": true, "flicker": true, "warn": true},
}
## 满溢：每隔这么久掉 1 点生命（ToxinMeter.overflow_interval 的镜像）。
const OVERFLOW_TICK := 0.55

# ---------------------------------------------------------------------------
# 受击反馈矩阵：材质 x 出手分量。所有顿帧 / 震屏 / 火花 / 击退 / 硬直 / 音效都从这里取。
# stop_*：顿帧（毫秒 / 时间缩放）；shake_*：震屏（像素 / 毫秒）；
# spark / debris：Fx 种类（sheet 精灵火花、metal 金属火星、bone 骨渣、ghost 灵雾、rust 锈屑）；
# knock：击退倍率；lock：敌人硬直秒数；recoil：被击像素后仰；sfx：音效键。
# ---------------------------------------------------------------------------
const MATERIALS: Array[StringName] = [&"flesh", &"bone", &"armour", &"shield", &"boss", &"ghost"]
const WEIGHTS: Array[StringName] = [&"light", &"heavy", &"finisher"]
const HIT_FEEL := {
	&"flesh": {
		&"light": {"stop_ms": 40, "stop_scale": 0.12, "shake_px": 2.0, "shake_ms": 90,
			"spark": &"sheet", "debris": &"none", "ring": false,
			"knock": 1.0, "lock": 0.12, "recoil": 2.0, "sfx": &"hit_flesh"},
		&"heavy": {"stop_ms": 55, "stop_scale": 0.08, "shake_px": 3.2, "shake_ms": 120,
			"spark": &"sheet", "debris": &"rust", "ring": false,
			"knock": 1.0, "lock": 0.18, "recoil": 3.0, "sfx": &"hit_heavy"},
		&"finisher": {"stop_ms": 70, "stop_scale": 0.06, "shake_px": 4.5, "shake_ms": 140,
			"spark": &"sheet", "debris": &"rust", "ring": true,
			"knock": 1.0, "lock": 0.26, "recoil": 4.0, "sfx": &"hit_heavy"},
	},
	&"bone": {
		&"light": {"stop_ms": 34, "stop_scale": 0.14, "shake_px": 1.6, "shake_ms": 80,
			"spark": &"bone", "debris": &"none", "ring": false,
			"knock": 1.0, "lock": 0.10, "recoil": 2.0, "sfx": &"hit_bone"},
		&"heavy": {"stop_ms": 48, "stop_scale": 0.10, "shake_px": 2.8, "shake_ms": 110,
			"spark": &"bone", "debris": &"bone", "ring": false,
			"knock": 1.0, "lock": 0.16, "recoil": 3.0, "sfx": &"hit_bone"},
		&"finisher": {"stop_ms": 62, "stop_scale": 0.07, "shake_px": 3.8, "shake_ms": 130,
			"spark": &"bone", "debris": &"bone", "ring": true,
			"knock": 1.0, "lock": 0.22, "recoil": 4.0, "sfx": &"hit_bone"},
	},
	&"armour": {
		&"light": {"stop_ms": 52, "stop_scale": 0.10, "shake_px": 2.4, "shake_ms": 100,
			"spark": &"metal", "debris": &"none", "ring": false,
			"knock": 0.55, "lock": 0.06, "recoil": 1.0, "sfx": &"hit_metal"},
		&"heavy": {"stop_ms": 66, "stop_scale": 0.07, "shake_px": 3.6, "shake_ms": 130,
			"spark": &"metal", "debris": &"rust", "ring": false,
			"knock": 0.55, "lock": 0.10, "recoil": 1.5, "sfx": &"hit_metal"},
		&"finisher": {"stop_ms": 80, "stop_scale": 0.05, "shake_px": 4.8, "shake_ms": 150,
			"spark": &"metal", "debris": &"rust", "ring": true,
			"knock": 0.55, "lock": 0.14, "recoil": 2.0, "sfx": &"hit_metal"},
	},
	&"shield": {
		&"light": {"stop_ms": 56, "stop_scale": 0.09, "shake_px": 2.0, "shake_ms": 90,
			"spark": &"metal", "debris": &"none", "ring": false,
			"knock": 0.0, "lock": 0.0, "recoil": 1.0, "sfx": &"shield_block"},
		&"heavy": {"stop_ms": 70, "stop_scale": 0.06, "shake_px": 3.0, "shake_ms": 120,
			"spark": &"metal", "debris": &"none", "ring": true,
			"knock": 0.0, "lock": 0.0, "recoil": 1.5, "sfx": &"shield_block"},
		&"finisher": {"stop_ms": 84, "stop_scale": 0.05, "shake_px": 4.0, "shake_ms": 140,
			"spark": &"metal", "debris": &"rust", "ring": true,
			"knock": 0.0, "lock": 0.0, "recoil": 2.0, "sfx": &"shield_break"},
	},
	&"boss": {
		&"light": {"stop_ms": 36, "stop_scale": 0.14, "shake_px": 1.8, "shake_ms": 80,
			"spark": &"metal", "debris": &"none", "ring": false,
			"knock": 0.15, "lock": 0.0, "recoil": 1.0, "sfx": &"hit_metal"},
		&"heavy": {"stop_ms": 60, "stop_scale": 0.08, "shake_px": 3.6, "shake_ms": 130,
			"spark": &"sheet", "debris": &"rust", "ring": false,
			"knock": 0.15, "lock": 0.0, "recoil": 1.5, "sfx": &"hit_heavy"},
		&"finisher": {"stop_ms": 84, "stop_scale": 0.05, "shake_px": 5.0, "shake_ms": 180,
			"spark": &"sheet", "debris": &"rust", "ring": true,
			"knock": 0.15, "lock": 0.08, "recoil": 2.0, "sfx": &"hit_heavy"},
	},
	&"ghost": {
		&"light": {"stop_ms": 28, "stop_scale": 0.18, "shake_px": 1.2, "shake_ms": 70,
			"spark": &"ghost", "debris": &"none", "ring": false,
			"knock": 0.6, "lock": 0.08, "recoil": 1.5, "sfx": &"hit_flesh"},
		&"heavy": {"stop_ms": 40, "stop_scale": 0.12, "shake_px": 2.0, "shake_ms": 90,
			"spark": &"ghost", "debris": &"ghost", "ring": false,
			"knock": 0.6, "lock": 0.12, "recoil": 2.0, "sfx": &"hit_flesh"},
		&"finisher": {"stop_ms": 54, "stop_scale": 0.09, "shake_px": 3.0, "shake_ms": 110,
			"spark": &"ghost", "debris": &"ghost", "ring": true,
			"knock": 0.6, "lock": 0.18, "recoil": 3.0, "sfx": &"hit_flesh"},
	},
}
## 骑士自己挨打：独立一行，不进材质矩阵。
const PLAYER_HURT := {"stop_ms": 60, "stop_scale": 0.08, "shake_px": 4.0, "shake_ms": 160,
	"flash": Color(0.72, 0.22, 0.14, 0.34), "flash_ms": 90, "sfx": &"hurt"}
const PARRY_FEEL := {"flash": Color(0.98, 0.93, 0.82, 0.34), "flash_ms": 140,
	"shake_px": 3.0, "shake_ms": 150}
## 首领相变 / 首领死亡的一次性演出。
const BOSS_PHASE_FEEL := {"slow_ms": 200, "slow_scale": 0.2, "shake_px": 4.0, "shake_ms": 300,
	"flash_alpha": 0.30, "flash_ms": 160, "sfx": &"boss_roar"}
const BOSS_DEATH_FEEL := {"slow_ms": 700, "slow_scale": 0.18, "shake_px": 6.0, "shake_ms": 500,
	"flash_alpha": 0.38, "flash_ms": 260, "sfx": &"enemy_die"}
## 玩法闪屏的透明度上限与震屏幅度上限：特效不许盖住骑士剪影 / 前摇 / 台缘。
const FLASH_ALPHA_CAP := 0.40
const SHAKE_PX_CAP := 6.5
## 新音效键尚未入库时退回的老键（未知键本身静音，退回只是不让命中变哑）。
const SFX_FALLBACK := {
	&"hit_heavy": &"hit_flesh", &"hit_bone": &"hit_flesh", &"hit_metal": &"hit_flesh",
	&"shield_block": &"parry", &"shield_break": &"parry", &"enemy_die": &"hit_flesh",
	&"swing_heavy": &"swing", &"land_heavy": &"land", &"hook_fire": &"gate",
	&"boss_roar": &"gate", &"boss_axe_swing": &"swing", &"boss_axe_slam": &"land",
	&"horse_charge": &"dash", &"hook_hit": &"hit_flesh",
}

# ---------------------------------------------------------------------------
# 预算：所有临时节点的同屏上限。
# ---------------------------------------------------------------------------
const BUDGET := {
	&"afterimages": 6, &"sparks": 6, &"oneshots": 8, &"markers": 8,
	&"projectiles": 8, &"fire_trails": 3, &"blasts": 1, &"motes": 48, &"rings": 4,
	## 环境打击留下的痕迹（焦痕/裂口/水渍）。与 DecalField.MAX_DECALS 对齐。
	&"decals": 24,
}
## 玩家自己生成的临时伤害体（火带 + 冲击波）合计不超过这个数。
const PLAYER_HITBOX_CAP := 4

# ---------------------------------------------------------------------------
# 敌人读招表：每种敌人一个独有的前摇暗号，伤害绝不早于 time。
# time：从暗号亮起到判定出现的秒数；punish：出招后可见的破绽窗口（0 = 常驻可打）。
# ---------------------------------------------------------------------------
const TELEGRAPH_MIN := 0.25
const TELEGRAPH := {
	&"spitter": {"time": 0.45, "punish": 0.35, "cue": &"pulse",
		"color": Color(1.0, 0.55, 0.0), "signature": &"toxic_swell"},
	&"scrapper": {"time": 0.45, "punish": 0.50, "cue": &"pose",
		"color": Color(1.35, 0.85, 0.45), "signature": &"paw_crouch"},
	&"skeleton": {"time": 0.32, "punish": 0.45, "cue": &"pose",
		"color": Color(1.7, 1.62, 1.4), "signature": &"bone_lean"},
	&"ghost": {"time": 0.28, "punish": 0.35, "cue": &"ring",
		"color": Color(0.6, 1.5, 1.7), "signature": &"wail_ring"},
	&"fire_skull": {"time": 0.30, "punish": 0.30, "cue": &"pulse",
		"color": Color(1.8, 1.5, 0.8), "signature": &"flare_swell"},
	&"flying_demon": {"time": 0.55, "punish": 1.00, "cue": &"pulse",
		"color": Color(1.6, 0.5, 0.55), "signature": &"crimson_flap"},
	&"gear_shield": {"time": 0.50, "punish": 1.50, "cue": &"pulse",
		"color": Color(1.0, 0.76, 0.29), "signature": &"arm_raise"},
	&"executioner": {"time": 0.52, "punish": 0.65, "cue": &"zone",
		"color": Color(1.0, 0.42, 0.18), "signature": &"axe_zone"},
	&"nightmare": {"time": 0.70, "punish": 1.10, "cue": &"lane",
		"color": Color(1.3, 0.78, 0.72), "signature": &"lane_lock"},
}
## 梦魇二阶段：前摇与喘息收紧（前摇仍远大于 TELEGRAPH_MIN，锁向仍留最后 0.2 秒）。
const NIGHTMARE_P2_WINDUP := 0.58
const NIGHTMARE_P2_REST := 0.90
const NIGHTMARE_P2_SPEED_K := 1.12
## 刽子手二阶段：斩后紧接的射弹延迟（原为整个 shoot_interval）。
const EXECUTIONER_P2_FOLLOWUP := 0.55


# ---------------------------------------------------------------------------
# 小函数
# ---------------------------------------------------------------------------
static func swing_total(index: int) -> float:
	var i := clampi(index, 0, SWING_WINDUP.size() - 1)
	return float(SWING_WINDUP[i]) + float(SWING_ACTIVE[i]) + float(SWING_RECOVERY[i])


## 取矩阵一行；未知材质 / 分量退回 flesh / light，不会返回空字典。
static func feel(material: StringName, weight: StringName) -> Dictionary:
	var by_weight: Dictionary = HIT_FEEL.get(material, HIT_FEEL[&"flesh"])
	return by_weight.get(weight, by_weight[&"light"])


## 出手分量：攻击者带的 blow 标签为底，伤害 >= 2 抬到 heavy，致命一击抬到 finisher。
static func weight_for(attacker: Object, amount: int, killed: bool) -> StringName:
	var weight: StringName = &"light"
	if attacker is Hitbox:
		weight = (attacker as Hitbox).blow
	if amount >= 2 and weight == &"light":
		weight = &"heavy"
	if killed:
		weight = &"finisher"
	return weight


## 命中材质：目标身上声明的 hit_material；没有声明的一律按血肉算。
static func material_of(target: Object) -> StringName:
	if target != null:
		var declared: Variant = target.get(&"hit_material")
		if declared is StringName and HIT_FEEL.has(declared):
			return declared
	return &"flesh"


static func toxin_tier(band: StringName) -> Dictionary:
	return TOXIN_TIERS.get(band, TOXIN_TIERS[&"cold"])


## Sfx.LIBRARY 的缓存（const，进程内不变）；取不到时为空字典，全部走退回表。
static var _sfx_library: Dictionary = {}
static var _sfx_library_read := false


## 音效键：库里没有新键时退回老键，库里有则原样。
static func sfx_key(key: StringName) -> StringName:
	if not _sfx_library_read:
		_sfx_library_read = true
		var script: Script = Sfx.get_script() if Sfx != null else null
		if script != null:
			var consts: Dictionary = script.get_script_constant_map()
			if consts.get("LIBRARY") is Dictionary:
				_sfx_library = consts["LIBRARY"]
	if _sfx_library.has(key):
		return key
	return SFX_FALLBACK.get(key, key)


static func flash_alpha(alpha: float, scale: float) -> float:
	return clampf(minf(alpha, FLASH_ALPHA_CAP) * clampf(scale, 0.0, 1.0), 0.0, 1.0)


static func shake_px(px: float, scale: float) -> float:
	return minf(px, SHAKE_PX_CAP) * clampf(scale, 0.0, 1.0)
