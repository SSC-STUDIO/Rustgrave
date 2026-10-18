# 破坏引擎（Destruction Engine）

> 本文件是 v3 计划里"破坏引擎"的唯一口径。实现按 A（表现层）→ B（可破坏道具）→ C（可破坏地形）三段推进；每一段都必须**不改基础伤害/碰撞规则**，除非该段明确声明。

## 1. 已落地：A 表现层（M1）

### 1.1 数据

`scripts/data/impact_catalog.gd`

- 材质 → 表现配置：`spark` / `debris` / `decal` / `sfx` / `light` / `energy` / `shake`。
- 六种材质：`dirt` / `stone` / `metal` / `wet` / `wood` / `bone`，未知回退 `stone`。
- `material_for_skin(skin)`：`SolidPlatform.skin` 经 `Sfx.SKIN_SURFACE`（dirt/stone/metal/wet/sludge）映射到表现材质。
- `material_for_collider(collider)`：优先级 `impact_material()` → `hit_material` 属性 → `skin` → meta `impact_material` → `stone`。
- `weight_scale(light/heavy/finisher)` = 1.0 / 1.55 / 2.2，乘到粒子量、震动与音量上。

### 1.2 表现

`scripts/autoload/fx.gd` 的 `Fx.impact(material, pos, normal, weight)`：

1. 火花/碎屑：`burst()` 池化粒子（新增 `dirt`/`stone`/`wood`/`wetsplash`/`ember` 种类）。
2. 贴花：`scripts/world/decal_field.gd` + `impact_decal.gd`，每个世界一个容器，环形复用，上限 `CombatRules.BUDGET[&"decals"] = 24`。
3. 短辉光：`ImpactFlash`（加法混合像素圆，0.09s）。
4. 音效：按材质取 `Sfx.play_at`，受现有音量/并发规则约束。
5. 震动：`Juice.shake`，已乘 `Settings.shake_scale`。

全部为表现层：headless 下只计数（`Fx.impact_count()` / `last_impact()`），不建节点、不影响判定。

### 1.2.1 地面弹坑（用户反馈后返工）

- 火球砸地不再留持久黑色几何块。贴花本质是"贴在地形上的一层纸"，几版实心弹坑在游戏里
  都会读成悬空的黑三角/黑梯形；最终改为 **3.5 秒寿命的稀疏焦痕**（只压暗一半像素、无描边、
  无土沿），砸地的可读性交给火花、落地碎屑、坑内余烬与短辉光。
- 冲击辉光不再有近白核心（之前被读成"植物上的白方块"），改为材质色小光晕。
- 火花与碎屑分离：碎屑用 `debris_dirt/stone/metal/wood/wet`，**受重力、向下打短射线，
  碰到地面就停住再淡出**；不会再在半空消失，也不会穿过地板。

### 1.3 触发点

- **火球撞地/墙**：`Projectile._physics_process` 对"本帧位移"做一条 `PhysicsRayQueryParameters2D` 射线（mask `1 | 64` = 世界静态体 + 可交互/可破坏层），拿到精确命中点/法线后结算一次再消失；`_on_body_entered` 保留为兜底（无命中点的物理信号用近似点）。
- **剑刃扫环境**：`Hitbox.begin_world_probe()` 由 `MeleeCombat._begin_active()` 在玩家判定期开启；每 0.05s 向上/中/下三条短射线扫前方环境，同一碰撞体每刀只触发一次；不进入 hurtbox 路径、不造成伤害。
- 敌人命中仍走原有 `CombatRules.HIT_FEEL` 材质矩阵，不重复出环境特效。

### 1.3.1 可破坏道具 / 地形（M2）

- 道具：`scripts/interactables/destructible_prop.gd` + `scenes/interactables/DestructibleProp.tscn`，
  数据在 `scripts/data/destructible_catalog.gd`（碎铁堆 / 锈罐 / 腐藤结：材质、耐久、回血、旁白）。
  StaticBody2D 挡路 + Hurtbox 收伤；火球射线遇到 `destructible_body` 放行给 Hurtbox，不再一炸了之；
  破坏后掉碎屑、回 1 HP、写世界状态（`persist` 控制）。
- 地形：`scripts/world/breakable_terrain.gd` + `scenes/world/BreakableSlab.tscn`，32px 分块；
  只有重击/终结式、爆炸/冲击波、伤害 ≥2 的弹丸能伤到它；默认会话内破坏（重载恢复），
  `persist_break=true` 的秘道墙才写世界状态。
- 放置：`ChapterLayout.destructible()/breakable()`；level03 街边放了碎铁堆/锈罐，
  死城屋脊上放了一块 64×64 裂石板，打碎后才能走到屋脊奖励位。
- 边界：可破坏物/地形不参与 LevelSanity 的可达性判定，因此**主线必经路径不许只靠打碎通过**；
  道具放在支路/角落。

### 1.4 测试

- `tests/impact_catalog_test.gd`：18+ 种 `SolidPlatform.skin` 都有材质归属、优先级/兜底、权重、配置完整性。
- `tests/impact_fx_test.gd`：headless 不建节点；火球落地/撞墙恰好一次并按材质；非地形层穿透；贴花容器上限与复用。
- `tests/hitbox_world_impact_test.gd`：环境扫描每刀每面一次、收刀即停、不会伤害 hurtbox。
- `tests/destructible_prop_test.gd`（5）、`tests/breakable_terrain_test.gd`（6）、
  `tests/destructible_placement_test.gd`（3）：数据/耐久/轻击不出血/重击分块破坏/
  持久化与读档恢复/level03 放置与 LevelSanity。

## 2. 已落地：B 可破坏道具（M2）

- `scripts/data/destructible_catalog.gd`：木箱 / 锈罐 / 藤蔓 / 灰罐（生命、材质、碎块、掉落、叙事标签）。
- `scripts/interactables/destructible_prop.gd` + `scenes/interactables/DestructibleProp.tscn`：
  - `StaticBody2D`（层 1，可被火球射线命中）+ `Hurtbox`（受剑/弹丸伤害）+ `Health`。
  - `hit_material` 声明材质（wood/metal/stone）；死亡播 `Fx.impact` + 碎块/掉落，并 `SaveData.mark_consumed` 写档。
- 只放在支路/秘道，`level_sanity` 断言"可破坏物不在必经路线"。

## 3. 已落地：C 可破坏地形（M2，安全版）

- `scripts/world/breakable_terrain.gd` + `scenes/world/BreakableSlab.tscn`：裂石板按 16/32px 分块，每块独立碰撞 + 生命 2–3。
- 只有重击（`heavy`/`finisher`）、爆炸/冲击波、Boss 砸地、高功率火球能破坏。
- **默认重载恢复**（会话内有效）；只有 `persist_break=true` 的秘道墙写 `consumed` 路径。
- 硬性约束：主线必经路径不放可破坏地形；route audit 必须在"破坏前/后"两种状态下都能走通。

## 4. 预算

| 资源 | 上限 | 位置 |
|---|---|---|
| 贴花 | 24 | `CombatRules.BUDGET[&"decals"]` / `DecalField.MAX_DECALS` |
| 像素粒子 | 48 | `CombatRules.BUDGET[&"motes"]` / `Fx.MOTE_CAP` |
| 辉光 | 与粒子同帧释放 | `ImpactFlash`（0.09s 自毁） |

新增表现一律先走预算池；不允许无上限的 `Node2D` 生成。
