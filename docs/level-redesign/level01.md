# 第一章 · 腐液回廊（level01）重建蓝图（plan P3）

> 分支 `feature/overhaul-v3-level01`。故事、文本、章节顺序、玩家能力都不变；改的是地形、机关、遭遇、巢与捷径、
> 奖励、Boss 场。这一章是其余 13 章的质量标杆：**一章 3760px、四个乐章、三层楼、三处场景化遭遇、
> 一条单向捷径、一个带奖励的可选挑战、一场有地形与机关的 Boss 战。**

## 0. 架构

level01 仍是手摆场景，**不是** `ChapterLayout`，也**不进** `GameContext.LAYOUTS`（`level_routing_test` 断言）。

| 文件 | 职责 |
| --- | --- |
| `scenes/levels/Level01_Static.tscn` | 前半（x 0–1168）与全部**持久化节点**（压板、闸门、废料堆、嵌核台、锈门、净化祠、两只喷吐者、碎铁犬、齿盾卫、钩点） |
| `scripts/levels/level01_static.gd` | 玩家 / 相机 / HUD、路牌、墓园装饰、碑 |
| `scripts/levels/level01_east_wing.gd` | 毒坑踏步、中殿底面、余烬阁（EmberLedge / Hook_Ember / EmberCore）、东侧余烬巢、Boss、炉心、炉棚、BossGate、竞技场灯光与**炉龛喷火口接线** |
| `scripts/levels/chapters/level01_east_layout.gd` | **新增**。借 `ChapterLayout` 的铺设助手把东半的新地形 / 机关 / 敌人 / 装饰写进已有的 Platforms / Props 文件夹；由 `Level01EastWing.build()` 调用，建完即释放，**不登记**、无 `class_name` |
| `scripts/levels/scene_details.gd` / `level01_parallax.gd` | 西段墓园细节、背景（视差板本来就是重复平铺，加宽不留黑洞） |

持久化路径不变（`tests/level01_route_test.gd` 逐条断言）：`Props/EmberNest`、`Props/EmberNestEast`、`Props/Door`、
`Props/RustyGate`、`Props/ForgeHeart`、`Props/ScrapPile`、`Pickups/EmberCore`，以及 `Props/Spitter*` 下的 `TetherDrop_*`。
**所有敌人（含新增）放在 `Props/` 下**，和 Spitter1 同父，`TetherDrop_*` 的存档路径一致。

## 1. 剖面图

```
y=112                                         ┌ 余烬阁 ───beam──── 奖励台 ┐       ← 钩锁（可选）
y=176                         [perch+S3]                                  │
y=208  ┌ 楼座 W ─beam─ 楼座 E[压板 S2] ┐          ┌──── 炉廊顶板 ─────┐     │
y=224        HR3                                                          │
y=240      HR2                                                            │
y=264    HR1                                                              │
y=288  perch(S1)                                                          │
y=304  step                                                               │
y=320 ═grass═╗N2╔═ 地穴巷 ═Door═ 工坊 ═ N3 shrine ═ 炉口×3 ═ gate ═╗         │
y=336                                                          stair   ╚═ stage(boss, 炉龛×2, 墩×2)
y=352                                                                  nest  gate        ═ 中殿 ═ N4 ═ BossGate ═ 炉厅 ═ heart
x:   0     800  900 1000 1100  1300  1560  1664   1900  2112   2288..2464 2584  2672   3040 3112  3256-3584  3664   3760
```

## 2. 区段表

| # | 区段 | x 范围 | 层 | 内容 | 机关 | 遭遇 | 巢 / 捷径 / 奖励 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | 前半（微调） | 0–1168 | 地面 320；浮石 200–290 | 教学链、毒坑、Spitter1 矮台；**新增上层路**：矮台 → HR1 → HR2 → HR3 → 楼座；矮台东侧加 16px 垫阶 | — | Spitter1（仇恨圈 260）、Scrapper1（140，巡逻 16）、飞魔 | N1 `EmberNest`（150） |
| 1 | 压板偏殿 | 1100–1700 | 地穴巷 320、楼座 208（石板 32 厚）、东头高墩 176 | 压板在楼座、闸门在巷里（跨层谜题）；砖屋立面 | **第一根塌陷锈梁**（`iron_float`，抖 0.8s）：前后各一整块楼座（≥128px/240px），横跨 16px，仇恨圈够不到 | **① 伏击巷**：装甲碎铁犬（Scrapper2，头顶蓝菱形）+ 齿盾卫（GearShield1），互相警觉；**② 楼座交叉火力**：Spitter2（楼座面）+ Spitter3（高墩 176），仇恨圈 140 只盖压板 | N2 `EmberNestMid`（1096）；楼座边落下 = 回巷 |
| 2 | 锻核工坊 / 炉廊 | 1688–2600 | 地面 320；顶板 208；余烬阁 112 | 工坊（砖屋立面 + 废料堆 + 嵌核台）、净化祠休息龛、倾塔地标、**炉廊**（三口 `flame` 炉口，错相 0/0.34/0.67，休止 2.4 / 预警 0.9 / 判定 0.6）、**炉廊顶板**（盖住炉口 + 断链）、锈门在廊尽头 | 三口炉口；第 2 根塌陷梁（余烬阁） | Spitter4 守奖励台（仇恨圈 170，盯第 2 根梁） | N3 `EmberNestForge`（2112，炉口前 166px）；**余烬阁**：Hook_Ember + EmberCore（可选，钩锁）；**奖励台**：`RewardEyrie` = 耐酸头罩（`scholar_cowl`）；**单向捷径**：奖励台西头落 → 回 N3 一侧，东头落到顶板 → 再落到锈门前，越过全部炉口 |
| 3 | 中殿长阶 | 2600–3040 | 320 → 336 → 352 | 锈门之后两级 16px 石阶下到中殿；誓言碑（`SteleExecutioner`）、守墓者石像、落地火膛 | — | — | N4 `EmberNestEast`（3040，离 BossGate 72px，在 Boss 360px 仇恨圈外 380px） |
| 4 | 炉厅竞技场 | 3040–3760 | 中殿 352；石台 336 | **石台**（3256–3584，抬高 16px，Boss 站在上面，终局火柱落点 ±140 都在台上）、**两座掩体墩**（32 高、能挡火球）、**两座落地火膛**夹住 Boss、中央暖池、远处加法暖光地标；最东头炉心 + 炉棚 | **两口炉龛喷火口**（`ArenaVentW/E`，只在 Boss 战里转） | **③ 刽子手**（BOSS_SCALE、受击盒、斩区、两阶段、`ground_wave` / `execution_grab` / `furnace_pillar` 全不动） | — |

### 2.1 为什么这样摆（设计理由）

- **单跳的真实够距比 LevelSanity 的 72px 短得多**：空中加速度只有 270px/s²，站着起跳 0.4s 只飘约 22px；助跑起跳升 16 约 50px、
  升 24 约 44px、升 32 约 38px。所以上层路每一跳 ≤36px 横跨、升 ≤24（后两跳升 16），不靠冲刺。体检的 72px 只是底线。
- **矮台垫阶**：Spitter1 的矮台（顶 288）离地面 32px，台下只有 16px 净空。走过头的人从东边落回地面时单跳 32 爬不回去
  （身体要先升过台面才能横移），所以东侧加一个 16px 垫阶（顶 304），两边都是两个 16px 台阶。
- **第一根塌陷梁在安全处教学**：梁两侧的楼座是实心整块；楼座喷吐者的仇恨圈只有 140px，站在梁上时离它们 ≥160px；
  巷里的敌人隔着楼板（|Δy| ≥ 96）够不到楼座。梁抖 0.8s，跑过去就行，"别停"才是教学。落下去只是掉回巷里（无伤），重爬。
- **压板偏殿的跨层谜题**：压板在楼座上（要爬上层路、过梁），闸门在巷里（要穿伏击巷）。顺序不限：先走巷子的人会在闸门前
  看到楼座上的压板与两只喷吐者。楼座边任意位置都能落回巷里（单向落下）。
- **炉廊**：三口炉口错相，周期里没有任何两口同时喷（测试扫描），口与口之间的 68px 净地够站一个骑士；第一口之前 166px、
  最后一口到锈门 110px 无判定；首遇提示 `flame` 在第一口前弹一次。顶板把炉口盖成"廊"，火舌尖离板底 16px。
- **余烬阁与捷径**：EmberLedge / Hook_Ember / EmberCore 沿用旧阁的相对位置（锚点在台左沿外 16px、高 56px），所以旧的
  "钩锁弹到台面上"的几何测试直接适用。阁的东段是第 2 根塌陷梁 + 奖励台（守台喷吐者够得到梁），这是可选挑战。
  奖励台两头都是单向落下：西头落回 N3 一侧，东头落在顶板上、再落到锈门前，越过全部炉口。**主线不依赖它**。
- **Boss 前的巢**：N4 离 BossGate 72px（≤80），离 Boss 380px（Boss 的 `aggro_range` 360 在 `_enemy_ready` 里写死，
  站在巢边不会被点名）。巢间距 946 / 1016 / 928。
- **石台与终局火柱**：`furnace_pillar` 的落点是 Boss 所在位置的 ±140（脚下 y 取 Boss 的 y），所以石台必须盖住 ±140，
  否则火柱会悬在低处地面上方 16px。石台 328 宽（3256–3584，Boss 在 3420）。

## 3. 竞技场炉龛喷火口

`ArenaVentW` / `ArenaVentE`（`CyclicHazard` `flame`，建在 `Props/`，无首遇提示）：

- 平时是熄着的炉口：`Level01EastWing` 关掉它们自己的物理帧，开战（`GameEvents.boss_intro_started`）后才逐帧 `tick`；
- 一阶段 `ARENA_VENT_COOL`（休止 2.6 / 预警 0.9 / 判定 0.6 / 高 64）；二阶段（`boss_phase_changed ≥ 2`）换 `ARENA_VENT_HOT`
  （休止 1.5 / 预警 0.7 / 判定 0.7 / 高 76），换参数后快进到休止期起点，两口再错半拍——不会没有预警就喷；
- Boss 倒地（`slain`）先把它们快进到休止期（判定体收刀）再停 `tick`，这一步发生在过场锁住玩家之前；
- 离 Boss 身体 ≥ 28px、在火膛外侧：不压在近战站位上，但闪避方向上有压力。
- 演出灯（`ArenaHearth*`、`ArenaPool`、新增的 `ArenaGlow` 远景暖光）逻辑不变：进场涌光、二阶段转红、倒地熄灭。

## 4. 测试清单

| 文件 | 内容 |
| --- | --- |
| `tests/level01_route_test.gd`（新增） | 持久化路径、.tscn 与常量一致；主线不靠钩锁的可达性（巢 / 压板 / 闸门 / 废料堆 / 嵌核台 / 锈门 / BossGate / 炉心）；钩锁只通可选支路；压板在楼座、闸门在巷；第一根塌陷梁安全处教学；炉口规则（预警 / 相位 / 净地 / 通过窗口）；遭遇；巢间距与仇恨圈；单向捷径；奖励；竞技场地形；喷火口开战 / 二阶段 / 倒下接线；装饰接地 |
| `tests/level01_layout_test.gd` | 教学台阶、毒坑踏步、钩锁弹到余烬阁、东翼放置、站在台面上的敌人、墙板站地 |
| `tests/boss_presentation_test.gd` | 火膛站在石台上、其余演出逻辑 |
| `tests/scene_details_test.gd` | 西段细节（草地段）、灯光锚点（新增两个巢） |
| `tests/level_sanity_test.gd`（`RUSTGRAVE_LEVEL_FILTER=level01`） | `LevelSanity.check` 无问题 |

## 5. 工具改动

- `tools/input_walkthrough.gd`：新路线（上层路 → 楼座 → 塌陷梁 → 压板 → 地穴巷 → 工坊 → 点 N3 → 炉廊 → 锈门 →
  余烬阁钩锁 → N4 → 竞技场 → 炉心）。新增 **几何导航器** `_nv_*`（读 `LevelSanity` 台面表；机关感知：进炉口判定区之前先看
  `CyclicHazard.safe_window()`；塌陷梁只当踏台；落到更低长地面时选朝向终点且不是墙的那一侧下去；有缺口的跳一律助跑）。
  另修了标题 → 选人界面（新增 `_embark_default_origin`，以前只按一次确认键，选人界面落地后验收就起不来）。
  `campaign_walkthrough.gd` 的 level01 部分继承这条路线（它的 `_navigate` 是另一套，名字不冲突）。
- `tools/boss_fixture.gd`（level01 的竞技场界 / 触发点）、`tools/boss_presentation_acceptance.gd`（骑士站位）、
  `tools/slash_lighting_probe.gd`、`tools/perf_probe.gd`（采样点）。
- `scripts/levels/opening_cinematic.gd`：开场镜头末段扫到炉厅（`PAN_END_X` 3440、`HEART` 新位置、门后剪影位置）。

## 6. 共享文件改动

只有本章自己的文件与测试 / 工具；**没有**改 `chapter_layout.gd`、`level_sanity.gd`、`scripts/hazards/*`、`docs/overhaul-v3.md`、
`docs/level_authoring.md`。

## 7. 已知问题 / 建议

- 前半 Scrapper1 / Spitter1 的仇恨圈被收窄（140 / 260），GearShield1 从前半挪进伏击巷（第一次见盾卫在巷里）。
- 路线 `Level01EastLayout` 的 `theme()` 沿用 "graveyard"，但 `prop_allowed()` 放开了工坊残骸与砖屋立面
  （`SceneDetails.ALLOWED_KEYS` 的同源清单 + `brick_house` / `ruin_tower`）；若以后要把它收进 `PropCatalog` 主题白名单，改 `ALLOWED_DECOR` 即可。
- 以上都是几何 + 输入 bot 的证据；**真人手感**（单跳的 36px 横跨、塌陷梁 0.8s、炉口窗口）仍需真人试玩确认。
