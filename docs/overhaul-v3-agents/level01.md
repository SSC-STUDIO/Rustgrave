# Agent: level01 — 第一章「腐液回廊」前半微调 + 后半重建（P3）

worktree `C:\dev\rg-level01`，分支 `feature/overhaul-v3-level01`。先读 `docs/overhaul-v3-brief.md`。

## 现状（已核实，坐标取自源码）

架构：`scenes/levels/Level01_Static.tscn`（手摆，x≈0–1600）+ 运行时 `Level01EastWing.build()`
（`scripts/levels/level01_east_wing.gd`，扩到 `EAST_LIMIT=2240`）+ `level01_static.gd`（教学台、路牌、碑、装饰、视差）+
`level01_story_beats.gd`（开场、Boss 入场、残芯演出）。**不走 ChapterLayout**，`tests/level_routing_test.gd` 断言 level01 不在
`GameContext.LAYOUTS` 里——保持这一点（可以在 Level01 内部实例化一个 ChapterLayout 子类来借助助手，但不要注册进 LAYOUTS）。

- 平台：GroundLeft(0,320,400×80) ToxinPit(400,352,112×48) GroundRight(512,320,1088×80) WallLeft/WallRight(-16 / 2240)
  浮台 Plat_56_200 / Plat_160_200 / Plat_48_144 / Plat_268_256 / Plat_420_236 / Plat_620_248 / Plat_760_288 / Plat_920_248 /
  Plat_980_180 / Plat_1080_220，Gear(600,200)，TeachTerrace(228,288,40×48)，坑内踏石（PIT_* 常量，level01_east_wing.gd L52–75），
  EastFloor(1600,320,640×80,`stone`)，EmberLedge(1528,112,80×16)。
- 交互物 / 敌人：ToxinPool(400,336→PIT_WATER_Y 328)、FilterGear(352,308)、EmberNest(150,306)、Spitter1(812,288)、Spitter2(1018,180)、
  Scrapper1(860,320)、GearShield1(960,320)、FlyingDemon1(460,130)、PressurePlate(1040,314)、Door(1144,256)、ScrapPile(1220,302)、
  SocketStation(1296,296)、RustyGate(1384,256)、PurificationShrine(1464,288)、EmberNestEast(1536,306)、BossGate(1688,280)、
  Executioner(1860,320)、ForgeHeart(2064,292)、ForgeShelter(2112,240,256×160)。
- 碑：SteleForge(88,144)、SteleCoolant(532,304)、SteleExecutioner(1636,320)。钩点：Hook_Pit(460,160)、Hook_Tower(120,84)、
  Hook_Mid(700,96)、Hook_Plate(1150,110)、Hook_Ember(1512,56)。拾取：EmberCore(1568,96)。路牌：余烬(118)/腐液(300)/压板(980)/东翼(1548)。
- 能力流程：窑核只来自废料堆；钩锁核由 Spitter1 死亡掉落；余烬核在 EmberLedge（需钩锁）。
- 后半（x≈1100–2240）弱点：一条平地走廊（碎铁犬+盾卫同一水平线）→ 压板 → 废料堆/插座/锈门 → 神龛 → 平地竞技场；
  缺垂直与场景化遭遇，没有机关。

## 必须遵守

- **持久化的裸路径节点不改名、不改父级**：`Props/EmberNest`、`Props/EmberNestEast`、`Props/Door`、`Props/RustyGate`、
  `Props/ForgeHeart`、`Pickups/EmberCore`、`Props/ScrapPile`，以及动态 `TetherDrop_*`（`SaveData.persist_path`，level01 用裸路径）。
  `GameContext.level_id()` 对 level01 返回 ""。坐标可以挪（`SpawnSafety` 会兜底旧存档位置）。
- 故事旗标：`boss_dead`、`wake`、`toxin`、`core`、`parry`、`boss_intro`、`interlude_level01_seen`；复燃 → 落进 level02，熄灭 → 提前结局。
  读档必须先于东翼铺设（Boss 要看 `boss_dead`）。
- 刽子手：不改 `BOSS_SCALE`、受击盒、斩击区数学、`max_phases=2`、终局攻击 id 与前摇（`tests/executioner_*_test.gd`、`boss_framework_test.gd` 锁着）；
  可改：场地几何、两座火膛的位置、竞技场灯、**场地机关与二阶段 / 终局的联动**。`boss_presentation_test` 依赖
  `ARENA_HEARTH_*`、`ARENA_CENTER_X`——同步更新。
- 单跳链 ≤32px 高 / ≤72px 宽；教学顺序不变（跳跃 → 冲刺 → 毒素 → 弹反 → 热锻）；第一章第一处机关必须放在安全处教学。

## 新设计（后半重建；前半 0–1100 微调）

EAST_LIMIT 2240 → 约 3700（`WallRight`、相机右界、`EastFloor` 同步）。后半用 ChapterLayout 助手数据驱动地铺：

1. **压板偏殿（x≈1000–1700）**：下层地穴道（碎铁犬 + 盾卫伏击，窄、有顶沿）+ 上层回廊（喷吐者压制，y≈176–224）。
   压板在回廊、门在地穴，需要跨层配合；回廊里**第一处塌陷锈梁**（`collapsing()`，教"别停"）。可选钩锁捷径上回廊。
2. **锻核工坊（x≈1700–2500）**：废料堆 / 插座台 / 锈门（热锻）移到这里的侧间；锈门后是**炉口喷火廊道**（`cyclic(..., "flame")`，
   前后各 ≥48px 安全落脚，节奏教学：先一口、后两口错相），神龛作喘息，余烬核龛（钩锁，可选）悬在廊道上方。
3. **中殿长阶（x≈2500–3100）**：下沉石阶、誓碑（SteleExecutioner 沿用）、东侧余烬巢 EmberNestEast（距 Boss 门 ≤80px，且在
   伏击圈外）。
4. **炉厅竞技场（x≈3100–3700）**：抬高中台 + 两侧炉口喷火（二阶段 / 终局由 Boss 事件触发"点火"：用 `GameEvents.boss_phase_changed`，
   参见现有 `_on_boss_phase_changed`）；炉心室 ForgeHeart 在最东。
5. 敌人变体可用：`armored_scrapper` 守地穴道、`scatter_spitter` 压回廊（别在同一条跳跃路上放两只喷吐者）。
6. 前半（0–1100）：压平的 512–1000 地段加二层回廊与可选钩锁捷径，Spitter2 位置重排；不要动教学台与毒坑的单跳数学。

## 必须同步更新的测试与工具（硬编码坐标 / 节点名）

`tests/level01_layout_test.gd`（TEACH_*、PIT_*、EMBER_*、BossGate(1688,280)、ForgeHeart、WallRight 2240、钩锁模拟起点 (1447,271)）、
`tests/level01_backdrop_test.gd`、`tests/scene_details_test.gd`（GROUND_DETAILS x<1600、LIGHT_ANCHORS、`EAST_FLOOR_X`）、
`tests/boss_presentation_test.gd`、`tests/interactables_test.gd`、`tests/upgrade_phase2_test.gd`（`.tscn` 里不得出现 `Kiln_`）、
`tests/probes/zz_sanity_probe_test.gd`（相机 Rect2(0,-800,1600,1200)）、`tools/input_walkthrough.gd`（路点 734→812→904→1050→1363→
1430→1536→1885→2052，节点 Props/Door、RustyGate、ForgeHeart、Spitter1、EmberNestEast）、`tools/perf_probe.gd`（采样 x）、
`tools/boss_presentation_acceptance.gd`、`scripts/levels/scene_details.gd`（装饰只铺 x<1600，要扩展到新长度）。
输入机器人（`tools/run_input_acceptance.ps1 -Ending both -Fast`）：更新路点表；如果新机关使机器人无法稳定通过，
写清楚卡在哪（P8 会把机器人升级为机关感知）。

## 交付

蓝图 `docs/level-redesign/level01.md`；`level01_*`、`scene_details`、`boss_presentation`、`executioner`、`interactables`、`level_sanity`
（`RUSTGRAVE_LEVEL_FILTER=level01`）、`route_audit`、`chapter_progression`、`level_routing`、`upgrade_phase2`、`presentation_metrics`、
`grounding_regression` 过滤用例全绿；机位截图（前半 3 张 + 后半每段 2–3 张 + 竞技场全景 + 二阶段炉火联动），1280×720。
