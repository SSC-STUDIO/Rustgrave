# level03「锈城街巷」v3 重做蓝图

## 1. 章节定位与形状

- **章节 ID / 场景 / 主题**：`level03` / `scenes/levels/Level03_RustTown.tscn` / `town`（室外死城，雾 / 雨 / 放晴）
- **尺寸**：总宽 `4000px`（`east_limit = 4000`），`camera_top = -48`，出生点 `(96, 300)`，出口 `(3840, 320)` → `level04`（旗标 `level03_done`）
- **核心形状**：**街面 / 屋顶双层环线 + 下沉窄巷与上层屋檐单向捷径 + 死城双层屋脊环线**。打破 `y=320` 单线长走，主线在双层街区（`720–1360`）可任选上层塌瓦屋顶线或下层蒸汽街面线抵达屋顶压板与城门。

```
y=160                                     [TowerRoof: 碑文·塔 + 余烬核] (钩锁支路)
y=192                                                                          [TerraceEave]    [RubbleRoofB]
y=224              [RoofEntry]~[塌瓦1]~[RoofA:喷吐]~[塌瓦2]~[RoofC:压板]      [TerraceStep]          [DeadRidge:奖励]~[塌瓦4]~[DeadRoofB:幽魂]~[塌瓦5]
y=256        [桥2]                                          [石阶]  [PlazaEave] [EaveD]<~[塌瓦3]<~[EaveE]<~[Return] [Terrace:蒸汽+盾卫+碑] [DeadRoofA]              [DeadRoofC]
y=288  [桥1]                                                [石阶]  [PlazaStage]                               [StairB:喷吐]             [DeadStepA]                 [DeadStepEast]
y=320 [StreetA:巢1+碑+教学蒸汽] [运河] [StreetB:错相蒸汽x2+犬+可破坏物] [门][Plaza:巢2+高低台双犬+飞魔]           [StairA]                 [DeadStreet:巢4+错相蒸汽x2+疾行犬+喷吐+出口]
y=352                                                                           [Alley:巢3 + 装甲犬群警戒 + 幽魂]
       0                       560  720                                1360    1936                        2368 2528                2880                                    4000
```

## 2. 区段表（x 范围）

| 区段 | x 范围 | 高度层 (y) | 核心玩法与过渡 |
| --- | --- | --- | --- |
| ① 巷口街面 | `0–560` | `320` | 出生点、`EmberNestStreet`、`SteleWindow`、路牌「锈城」；首处安全教学蒸汽喷口 `SteamTeach`（前后 ≥60px 平地、无敌人） |
| ② 运河与双层街区 | `560–1360` | `320` / `288–256` / `224` | 运河毒坑保留一处（`560–720`）；过桥后分流为**上层塌瓦屋顶线**（`y=224`）与**下层错相蒸汽街面线**（`y=320`），东侧石阶汇合回环并开启 `GateDoor` |
| ③ 广场高低台 | `1360–1936` | `320` / `288` / `256` / `160` | `EmberNestPlaza`；高低台小竞技场遭遇；上方 `TowerRoof`（`y=160`）为可选钩锁支路 |
| ④ 窄巷与屋檐捷径 | `1936–2528` | `352`（巷底）/ `256`（屋檐） | 下沉窄巷伏击遭遇（局部浓雾 `AlleyCalm`）；从东侧 `StairB` 可踏上 `y=256` 屋檐向西跨越 `CollapseAlley` 单向落回巷口巢 |
| ⑤ 圣殿前阶 | `2528–2880` | `256` / `224` / `192` | 前阶蒸汽喷口 `SteamTerrace` + 高低掩体台 + 齿盾卫守门 + `SteleStair` |
| ⑥ 死城双层环线 | `2880–4000` | `320` / `288–224` | 局部浓雾 `DeadQuarter`、`EmberNestQuarter`；下层错相蒸汽喷口与疾行犬，上层可破坏裂石板 + 奖励位 + 塌瓦屋脊环线；街尾出口「圣殿门」 |

## 3. 专属机关

1. **下水道蒸汽喷口（`cyclic(..., "steam")`）**：
   - `SteamTeach` `(400, 320)`：`phase=0.0`，预警 `0.8s ≥ 0.5s`，前后各有 `>60px` 无判定安全街面。
   - `SteamStreet1` `(792, 320)`（`phase=0.0`）与 `SteamStreet2` `(968, 320)`（`phase=0.5`）：双层街区下层错相喷发。
   - `SteamTerrace` `(2560, 256)`（`phase=0.25, reach=48`）：前阶入口节奏点，可借 `TerraceStep` 跳过。
   - `SteamDead1` `(3320, 320)`（`phase=0.15`）与 `SteamDead2` `(3528, 320)`（`phase=0.65`）：死城长街错相封路。
2. **塌瓦屋檐（`collapsing(..., "brick_float")`）**：
   - `CollapseRoof1` `(824, 224, w=64)`：首块教学塌瓦，两侧有 `RoofEntry`（`64px`）与 `RoofA`（`112px`）实心台，正下方为实心 `StreetB`（失手不掉坑）。
   - `CollapseRoof2` `(1048, 224, w=56)`：连接 `RoofA` 与压板所在的 `RoofC`。
   - `CollapseAlley` `(2160, 256, w=64)`：连接窄巷上层屋檐 `EaveE → EaveD` 回程捷径。
   - `CollapseDead1` `(3288, 224, w=64)` 与 `CollapseDead2` `(3496, 224, w=64)`：死城屋脊东段环线。

## 4. 三处场景化遭遇

1. **遭遇一：双层街区夹击（`x = 736–1224`）**
   - 上层 `RoofA` 由 `Spitter1` `(984, 224)` 封锁塌瓦落点；下层 `StreetB` 由 `Scrapper1` `(1080, 320)` 在错相蒸汽喷口东侧巡逻。
2. **遭遇二：广场高低台小竞技场（`x = 1584–1824`）**
   - 台上 `Scrapper2` `(1624, 288, alert_radius=160)` 与台下疾行变体 `Scrapper3` `(1712, 320, variant=swift_scrapper)` 上下呼应，空中 `FlyingDemon1` `(1704, 184)` 压制跳跃。
3. **遭遇三：下沉窄巷浓雾伏击 + 死城追击（`x = 2120–2640`、`3200–3680`）**
   - 窄巷东端部署装甲变体 `AlleyHound` `(2264, 352, variant=armored_scrapper, alert_radius=180, lose_range=320)` 与穿墙 `Ghost1` `(2248, 304)`，配合阶口 `Spitter2` `(2488, 288)` 与前台 `GearShield1` `(2616, 256)`；
   - 死城街区由疾行变体 `Scrapper4` `(3224, 320, variant=swift_scrapper, alert_radius=180)`、屋脊 `Ghost2` `(3424, 184)` 与街尾 `Spitter3` `(3640, 320)` 构成双层追击。

## 5. 余烬巢与单向捷径

- **余烬巢（4 处，间距 ≤ 1248px，后半程均 < 950px，全部位于敌人仇恨/唤醒圈外）**：
  1. `EmberNestStreet`：`x = 176, y = 320`
  2. `EmberNestPlaza`：`x = 1424, y = 320`
  3. `EmberNestAlley`：`x = 2000, y = 352`
  4. `EmberNestQuarter`：`x = 2936, y = 320`
- **单向捷径**：
  - 从窄巷东侧高阶 `StairB` `(2448, 288)` 踏上上层屋檐链 `AlleyReturnStep (2368, 256) → EaveE (2248, 256) → CollapseAlley (2160, 256) → EaveD (2048, 256)`，在 `EaveD` 西端单向落下 `96px` 直达 `EmberNestAlley` `(2000, 352)`（从巷底 `y=352` 无法逆向跳上 `y=256`）。

## 6. 可选挑战与奖励

- **死城屋脊支路（主线能力可达）**：从 `DeadStepA (2968, 288) → DeadRoofA (3000, 256)` 击碎 `RubbleRoofB`（`64×64` 可破坏裂石板），登上 `DeadRidge (3120, 224)` 拾取 `RewardDeadQuarter`（`EquipmentPickup`：`iron_blade`），并可沿东段塌瓦屋脊环线回到街尾。
- **塔楼屋顶支路（需钩锁）**：由 `HookTower (1856, 104)` 登上 `TowerRoof (1784, 160)`，阅读 `SteleTower`（「锈城纪事 · 塔」）并拾取 `EmberCoreTower`（`ember_core`）。
- **街面可破坏物**：`ScrapHeapStreet (880, 320)`、`RustUrnStreet (1140, 320)`。

## 7. Boss 场

- 本章无 Boss（故事节奏为穿过死城前往圣殿）。

## 8. 测试清单

- `tests/level03_layout_test.gd`（6 项测试全绿）
- `tests/level_sanity_test.gd`（`RUSTGRAVE_LEVEL_FILTER=level03` 全绿）
- `tests/destructible_placement_test.gd`（3 项测试全绿）
- `tests/level_weather_test.gd`、`tests/route_audit_test.gd`、`tests/chapter_art_audit_test.gd`、`tests/prop_fit_test.gd`
