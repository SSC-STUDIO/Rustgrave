# 角色系统 v3（进行中）

> 目标：在现有「起源 + 装备 + 属性」之上，把角色做成有成长、有流派差异、有外观决策的系统。
> 本文件记录已完成的第一批（M3-A：存档 v3 / 余烬阶位 / 流派被动），后续批次继续追加。

## 1. 存档 v3（已落地）

`scripts/autoload/save_data.gd`，`SAVE_VERSION := 3`。v1/v2 旧档直接兼容：缺省字段按默认值补齐，不重写版本号。

`profile` 块（唯一结构，读/写都走 `profile_snapshot()`）：

| 字段 | 类型 | 默认 | 含义 |
|---|---|---|---|
| `character_id` | String | "" | 角色/武器线使用 |
| `extras` | Dictionary | {} | 未知键原样保留（解锁表等） |
| `ember_rank` | int | 1 | 余烬阶位 1..10 |
| `ember_xp` | int | 0 | 累计 XP（只增） |
| `attribute_points` | int | 0 | 可分配属性点（每升一阶 +1） |
| `skill_1` / `skill_2` | String | "" | 两个主动技能槽（技能 id） |
| `skin_id` | String | "" | 皮肤 id（"" = 默认外观） |
| `skin_rune` | String | "" | 皮肤刻印 id（"" = 无） |

API：`set_ember_state(rank, xp, points)`、`set_skill_slot(index, id)`、`set_skin(id, rune)`、`persist_profile()`。
`persist_profile()` 只写 profile，不碰战役进度/旗标。

## 2. 余烬阶位（已落地）

`scripts/data/ember_rank.gd`（纯数据/纯函数）+ `scripts/autoload/ember_progress.gd`（Autoload）。

- 10 阶，累计 XP 门槛：0 / 120 / 300 / 560 / 920 / 1400 / 2020 / 2760 / 3660 / 4760。
- 阶名：拾灰者 → 燃薪者 → 余烬侍从 → 灰烬骑士 → 炉心守卫 → 铆钉行者 → 炽骸领队 → 熄灯者 → 墓碑主宰 → 余烬之王。
- 每升 1 阶给 1 点属性点（满阶 9 点）；满阶后 XP 继续累积但不再升阶。
- XP 来源（集中常量）：Boss 击杀 90、章节完成 30、试炼结算 60、竞技胜 120 / 负 30。
- 解锁表（占位给 M4 皮肤/刻印、M3 主动技能）：
  2 阶 `skin_ash_runner`、3 阶 `skill_ember_burst`、4 阶 `rune_ember_grip`、
  5 阶 `skin_cemetery_hero`、6 阶 `skill_hollow_guard`、7 阶 `rune_toxin_filter`、
  8 阶 `skin_gothic_hero`、9 阶 `skill_rust_lance`、10 阶 `rune_unbroken`。
  解锁 id 写进 `profile.extras["unlocked_progression"]`（去重、累计）。
- 信号：`EmberProgress.rank_changed(info: Dictionary)`；升阶时同时播报“余烬升阶 · …”。
- Boss 自动发放：`GameEvents.boss_defeated` → `award_boss()`。
- 试炼中战役档只读：`award_xp()` 返回 `{"blocked": "trial"}`，等结算回标题后再补发。

## 3. 流派被动（已落地）

`CharacterOrigin.passive_id / passive_desc` + `scripts/data/passive_catalog.gd`；触发点在 `scripts/player/player.gd`。

| 起源 | 被动 | 规则 | 触发 |
|---|---|---|---|
| 余烬重骑 | 余烬壁垒 | 完美弹反后 2 秒内防御 +1 | `GameEvents.parried`（只认本人弹反） |
| 废料剑客 | 拾荒本能 | 拾取锈核/装备时回 1 HP，20 秒冷却 | `GameEvents.core_acquired` / `equipment.bag_changed` |
| 锈械学者 | 滤毒转能 | 毒素满溢伤害每两次只结算一次，并排掉 10% 毒素 | `ToxinMeter.overflow_tick` |

Player 侧可读：`player.passive_id()`、`player.passive_state()`（id/name/heal_cd/toxin_skips），
供后续角色面板直接显示。

## 4. 测试

- `tests/save_migration_test.gd`（6）：v1/v2 → v3 默认补齐、v3 字段 round-trip、profile 不碰旗标。
- `tests/ember_progress_test.gd`（8）：门槛/进度/点数/解锁表；升阶/跨阶/满阶；Boss 信号自动发 XP。
- `tests/origin_passive_test.gd`（6）：目录一致性 + 三个被动在真实 Player 上的行为 + 不串用。
- 过滤跑全绿：`save` 29/29、`equipment` 53/53、`toxin` 8/8、`health` 4/4、`character_select` 10/10、`combat_feel` 3/3。

## 5. 主动技能（已落地）

- 目录：`scripts/data/skill_catalog.gd`，4 个技能：
  | id | 名称 | 冷却 | 效果 |
  |---|---|---|---|
  | `ember_burst` | 余烬冲击 | 6s | 前方 56×26 判定，2 伤害、重击退 |
  | `hollow_guard` | 炉心格挡 | 10s | 2 秒防御 +2、毒素抗性 +40% |
  | `rust_lance` | 锈枪突进 | 8s | 向前 430 速度突进 + 路径判定 1 伤害 |
  | `toxin_purge` | 滤毒净化 | 12s | 排掉 50% 毒素并回复 1 HP |
- 输入：`project.godot` 新增 `skill_1`(Q) / `skill_2`(E)；`Settings.REBINDABLE`、`KeyLabels.ACTION_NAMES`、
  `ControlsPanel.ROWS/GROUPS`（战斗组新增"主动技能 1/2 · 冷却好了才能放"）。
- `Player`：两个槽 + 冷却数组；新档槽 1 默认 `ember_burst`、槽 2 空；从 `SaveData.skill_1/2` 读取。
  API：`equip_skill(slot, id, persist)`、`cast_skill(slot)`、`skill_slot_id/skill_cooldown/skill_ready/skill_state`
  （`skill_state()` 给 HUD/竞技面板直接吃）。
- HUD：右下角 `Root/SkillBar` 两个格子，显示 `[Q] 余烬冲击 4.2`，冷却中压暗，空槽显示 `—`。
- 测试：`skill_catalog_test` 4、`player_skills_test` 7（槽位/冷却/四种效果/落档）；UI 回归
  `settings` 16/16、`controls` 8/8、`hud` 16/16、`touch` 8/8。
- 触控板暂未加 Q/E 按钮；等竞技场 HUD 一起做（触控技能键与冷却盘一次设计）。

## 6. 装备词缀 / 稀有度 / 掉落（已落地）

- `scripts/data/affix_catalog.gd`：稀有度 common / rare / epic；词缀条数 0 / 1 / 2；
  6 条词缀（锋锐·攻击、坚壁·防御、余烬生命·HP、滤毒·毒素抗性、余烬护佑·毒素消解、轻步·移速）。
  词缀由 `hash(base_id, rarity)` 确定性生成——同一个 id 永远是同一套，不需要额外存档字段。
- `scripts/data/loot_tables.gd`：生成装备 id `gen:<基座>:<稀有度>`；`EquipmentCatalog.for_id()`
  识别并按 id 重建；`roll_id(slot, level_id, seed)` / `roll_item()` / `roll_for_source()` 确定性掉落
  （Boss / 宝箱 / 可破坏物都能接）；稀有度权重 60 / 30 / 10。
- `EquipmentItem` 新增 `rarity` / `affixes`；`duplicate_item()` / `to_dict()` / `get_stat_lines()`
  都带上词缀（面板会自动显示 "· 锋锐 · 攻击 +1" 这类行）。
- `CharacterStats.recalculate()` 聚合词缀到同一组 bonus（生命/攻击/防御/毒素抗性/消解/移速），
  与套装加成同口径叠加、同样经过钳制。
- 旧装备（broken_sword 等）零改动：稀有度 common、无词缀，旧测试全部保持原值。
- 测试：`equipment_affix_test` 8/8；回归 `equipment` 61/61、`equipment_inventory` 17/17、
  `stats_combat` 16/16、`character_stats` 14/14、`save` 29/29、`loadout` 11/11。

## 7. 外观：皮肤 / 刻印（数据与运行时已落地）

- `scripts/data/skin_catalog.gd`：4 套皮肤（3 套真实素材 + 1 个调色变体）
  | id | 名称 | 素材目录 | 默认起源 | 解锁 |
  |---|---|---|---|---|
  | `skin_fantasy_knight` | 余烬骑士 | `player_fantasy_knight` | 余烬重骑 | 起始 |
  | `skin_ash_runner` | 灰行客 | `player_fantasy_knight`（冷色 tint） | 废料剑客 | 2 阶 |
  | `skin_cemetery_hero` | 墓园行客 | `player_cemetery_hero` | 锈械学者 | 5 阶 |
  | `skin_gothic_hero` | 哥特猎手 | `player_gothic_hero` | — | 8 阶 |
  每套皮肤把 11 个逻辑动作映射到素材动作/帧段（缺动作回退默认骑士），按动作给画布偏移
  （攻击帧单独覆盖），有的还带 tint。默认皮肤由起源决定，无存档时也能一眼看出流派。
- `scripts/data/rune_catalog.gd`：4 个刻印（余烬握柄/滤毒/不折之刻/轻步），通过常驻 modifier
  `skin_rune` 进 `CharacterStats`；切换时先摘后挂，不叠加；解锁 id 对齐 4/7/10 阶奖励。
- `Player`：`apply_skin(id, persist)` / `equip_rune(id, persist)` / `skin_state()`；换肤会重建
  `FrameAnimSprite`（保留当前状态），受击红闪结束后回到皮肤 tint；`SaveData.apply_player`
  在"同场景读档"时也会重挂外观。
- 落档：`SaveData.skin_id / skin_rune`（v3 profile，已有迁移测试）。
- 测试：`skin_catalog_test` 7、`player_skin_test` 7；回归 `player` 27/27、`save` 29/29、
  `origin` 39/39、`equipment` 61/61、`character_select` 10/10、`loadout` 11/11。
- 三套外观实机对比（Level01，同一位置）：`screenshots/peek/skins/skins_compare.png`。

## 8. 待做（后续批次）

1. ~~主动技能~~（已完成）。
2. ~~装备词缀/稀有度~~（已完成，掉落已接生成 id，下一步把 Boss/宝箱/道具真正挂上 `roll_for_source()`）。
2. **装备词缀/稀有度**：`affix_catalog.gd` + 掉落表；`CharacterStats` 聚合词缀；装备面板显示。
3. **外观**：皮肤目录（复用 `player_fantasy_knight` / `player_cemetery_hero` / `player_gothic_hero` 三套帧）
   + 刻印目录 + 角色选择/装备面板的皮肤条与预览。
4. **角色面板**：阶位进度、属性点分配、被动/技能/刻印展示。
