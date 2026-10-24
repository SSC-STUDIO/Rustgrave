# 锈墓・贰「沉钟地窟」（`level02`）v3 重设计蓝图

## 1. 架构决策：保持 `Level02Undercroft` 入口 + `Level02Layout extends ChapterLayout`

在 v3 改造中，对于 `level02` 的架构归属采取如下方案：

1. **`Level02Layout` 继承 `ChapterLayout`**（`scripts/levels/level02_layout.gd`）：
   - 直接复用 `ChapterLayout` 的 v3 机关与奖励助手（`cyclic`、`reward`、`destructible`、`enemy` 变体参数、`waymark` 等），无需重复造轮子。
   - 将原成员变量 `var boss: Node2D` 重命名为 `var boss_node: Node2D`，避免与基类方法 `ChapterLayout.boss()` 发生标识符冲突。
2. **保留 `Level02_Undercroft.tscn`、`Level02Undercroft` 与 `Level02Backdrop`，不向 `GameContext.LAYOUTS` 写入 `"level02"`**：
   - `GameContext.LAYOUTS`、`forge_heart.gd`、`pause_menu_test.gd`、`loadout_route_test.gd`、`chapter_art_audit_test.gd` 等共享文件均属于禁改或跨线文件。保留独立场景脚本入口既满足零共享文件冲突，又让 `level_sanity_test`、`route_audit_test`、`level02_layout_test` 与 `level02_scene_test` 全量覆盖本关的几何与无能力主线可达性。

---

## 2. 空间动线与「螺旋下探」多层高度结构（`0..3800`，`y = 136..384`）

原先的 `level02` 除两处小台外几乎贴死在 `y = 320` 的单一直线上，且 E 段（`2480..2600`）重复了 B 段的「毒水坑 + 踏石」模板。v3 重设计将整关拓展为 **五层垂直高度带（`y=136` 梁顶、`y=208/224` 上层桥、`y=256/264` 中层廊、`y=320` 主地面、`y=352/384` 下沉钟堂与深井）**，形成两轮「拾级上探 → 跨井横渡 → 螺旋下沉」的立体节奏：

| 分段 | X 范围 | 高度层级 (Y) | 核心体验与机制 |
| :--- | :--- | :--- | :--- |
| **A 入口竖井** | `0..448` | `40 -> 320` | 从炉心竖井落入 `FloorA (y=320)`；点亮首座余烬巢 `EmberNestShaft (176, 306)`，阅读 `SteleShaft (264, 320)` 与路牌「地窟」。 |
| **B 苔水高廊** | `448..1120` | `352 / 264..320 / 232` | 跨越首处毒水坑（`PitFloorB y=352` + 三踏石 `y=288/264`）；在宽敞平地 `FloorB (720..1120)` 迎来**首口坠钟安全教学点 `BellTeach (832, 320)`**（前后各 `>100px` 安全平地，`0.9s` 预警）；随后沿 `StepB (y=288)` → `LedgeB (y=264)` → `Ring1Balcony (y=232)` 螺旋上探，踩下 `Plate (1008, 258)` 开启闸门 `Door (1120, 256)`（**遭遇战 1**）。 |
| **C 竖井闸厅** | `1120..1600` | `320 -> 256 -> 224 / 296 / 384` | 过门即达第二座余烬巢 `EmberNestVault (1164, 306)`；主路可走下层 `FloorC (y=320)` 迎战装甲碎铁犬，或登 `StepC1 (y=288)` → `VaultCatwalk (y=256)` 穿行于 `BellShaftWest (1296, 256)` 坠钟之下，再跃上 `ShaftOverlook (1448, 224)` 或乘水平吊台 `LiftC (y=296)` 横渡深井 `PitFloorC (y=384)`（**遭遇战 2**）。 |
| **D 沉钟前厅与下沉钟堂** | `1600..2432` | `136 / 208 / 224 / 256 / 320 / 352` | 抵达第三座余烬巢 `EmberNestHall (1664, 306)`。地面东端立有单向捷径门 `ShortcutDoor (1944, 256)`（初始关闭）；首次探索需从 `StepD1 (1908, 288)` 盘旋登上中层 `GalleryD (1976..2136, y=256)` 与上层 `UpperBridgeD (2144..2288, y=224)`，或下探至下沉钟堂底板 `FloorSunken (1960..2432, y=352)`（**遭遇战 3**）。上层桥东端踩下 `ShortcutPlate (2252, 218)` 即可永久打开地面捷径门。 |
| **E 坠钟回廊** | `2432..2700` | `256 -> 288 -> 320` | 去除旧版重复的毒水坑，改由 `StepD2 (y=256)` → `StepD3 (y=288)` 螺旋落回 `FloorE (y=320)`，穿过两口异相交替的周期坠钟 `BellCorridorWest (2480, 320)` 与 `BellCorridorEast (2560, 320)`，抵达 Boss 前存档点 `EmberNestBell (2632, 306)`。 |
| **F 空钟笼厅** | `2700..3620` | `256 / 288 / 320` | `920px` 连续平地之上增设对称笼状高台（`CageAlcoveWest/East y=288`、`CageBelfryWest/East y=256`）与中央击锤高台 `CageDais (3088..3168, y=288)`，配合两处 Boss 落钟机关（`2920 / 3380`）构成空钟 Boss 战舞台；击败后解锁 `BellDoor (3560, 320)` 通往 `level02b`。 |

---

## 3. 存档点、单向捷径与可选挑战

### 3.1 四座余烬巢（间距全部 `<= 1000px`）
- `EmberNestShaft`：`x = 176, y = 306`（入口竖井底）
- `EmberNestVault`：`x = 1164, y = 306`（闸门后，距前巢 `988px`）
- `EmberNestHall`：`x = 1664, y = 306`（沉钟前厅，距前巢 `500px`）
- `EmberNestBell`：`x = 2632, y = 306`（空钟厅门前，距前巢 `968px`；距竞技场门 `48px`、距 `ARENA_LEFT` `68px <= 80px`）

### 3.2 单向捷径回环
- **位置**：`ShortcutPlate (2252, 218)`（位于 `UpperBridgeD y=224` 东段）→ 触发开启 `ShortcutDoor (1944, 256)`（位于 `FloorD y=320` 东端）。
- **设计目的**：首次推进必须历经 `StepD1 -> GalleryD -> UpperBridgeD` 或 `FloorSunken` 的立体遭遇战；一旦登顶踩开压板，从 `EmberNestHall (1664)` 复活即可直接沿平地穿过 `ShortcutDoor` 进入下沉钟堂与坠钟回廊，大幅缩短回跑路径。

### 3.3 可选挑战与奖励点
- **路径**：由 `FloorD` 乘竖向吊台 `LiftD (1856, 304 -> 224)` 跳上壁龛 `AlcoveD (1760..1840, y=208)`（阅读第二块碑文 `SteleGallery`），再使用钩锁锚点 `Hook_Gallery (1912, 112)` 荡上悬梁高台 `BellRafter (1864..1960, y=136)`（无钩锁时高差 `72px > 34px` 不可达）。
- **奖励**：`RewardUndercroft`（`pos = Vector2(1912, 129)`，`reward_kind = "equipment"`，`reward_ref = "bone_charm"`「骨符」）与可破坏补给罐 `RafterUrn (1880, 136)`。

---

## 4. 机关与三场分阶段遭遇战

### 4.1 周期性坠钟机关（`cyclic(..., "bell")`）
| 节点名 | 落点坐标 | 尺寸 | 预警 / 判定 / 休止 / 相位 | 职责 |
| :--- | :--- | :--- | :--- | :--- |
| `BellTeach` | `(832, 320)` | `36x40` | `0.90s / 0.45s / 2.80s / 0.25` | 安全教学位：前后各 `>100px` 连续平地，无敌人干扰 |
| `BellShaftWest` | `(1296, 256)` | `36x40` | `0.85s / 0.45s / 2.50s / 0.00` | 封锁 C 段上层走道 `VaultCatwalk` 中心，考验过桥时机 |
| `BellVaultLower` | `(2056, 352)` | `36x40` | `0.80s / 0.45s / 2.40s / 0.20` | 分割 D 段下沉钟堂底板，与重盾卫形成夹击 |
| `BellVaultUpper` | `(2176, 224)` | `36x40` | `0.80s / 0.45s / 2.40s / 0.60` | 镇守 D 段上层钟桥 `UpperBridgeD` 西端（离捷径压板 `58px > 40px`） |
| `BellCorridorWest` | `(2480, 320)` | `36x40` | `0.75s / 0.45s / 2.20s / 0.00` | E 段坠钟走廊西钟，替代旧版重复毒水坑 |
| `BellCorridorEast` | `(2560, 320)` | `36x40` | `0.75s / 0.45s / 2.20s / 0.50` | E 段坠钟走廊东钟（与西钟半周期反相，离 Boss 前巢 `54px > 40px`） |

### 4.2 三场分阶段遭遇战与敌人变体
1. **遭遇战 1（苔廊压板高台，`x = 780..1040`）**：
   - `Ghost1`（`ghost`，`(792, 224)`）在半空逼迫走位；`Spitter1`（`spitter`，`(968, 264)`，变体 `&"scatter_spitter"` 散射喷吐者）据守 `LedgeB` 压板高台，扇形毒弹封锁登台路线。
2. **遭遇战 2（双层竖井闸厅，`x = 1240..1540`）**：
   - 下层 `FloorC` 由 `Scrapper1`（`scrapper`，`(1288, 320)`，变体 `&"armored_scrapper"` 装甲碎铁犬）把守；上层吊桥与井口上空由 `BellShaftWest` 坠钟和 `GhostShaft`（`ghost`，`(1480, 184)`）构成高低立体防线。
3. **遭遇战 3（三层下沉钟堂，`x = 1980..2340`）**：
   - 中层 `GalleryD (y=256)`：`Scrapper2`（`scrapper`，`(2040, 256)`，变体 `&"swift_scrapper"` 疾行碎铁犬）高速突袭；
   - 下层 `FloorSunken (y=352)`：`GearShield1`（`gear_shield`，`(2160, 352)`，变体 `&"heavy_guard"` 重盾卫）配合 `BellVaultLower` 坠钟封锁底层；
   - 上层 `UpperBridgeD (y=224)` 与东侧出口阶梯：`Ghost2 (2120, 184)`、`Ghost3 (2260, 184)` 与 `Spitter2 (2316, 256)` 形成立体交叉火力。

---

## 5. 空钟（`HollowBell`）笼状竞技场设计（`x = 2700..3620`）

- **连续底板**：`FloorE` 覆盖 `2432..3800 (y=320)`，保证 `HollowBell` 的横扫、落锤与钟波全程在平地运行。
- **笼状立体支点**：
  - 两侧避钟笼台：`CageAlcoveWest (2760..2824, y=288)`、`CageBelfryWest (2840..2896, y=256)` 与 `CageBelfryEast (3200..3256, y=256)`、`CageAlcoveEast (3272..3336, y=288)`，供玩家在拉链拖拽（`chain_pull`）或地面钟波（`toll_wave`）时跃起规避。
  - 中央击锤高台：`CageDais (3088..3168, y=288)` 位于两口竞技场落钟（`bell_fall_west = 2920`、`bell_fall_east = 3380`）正中，既标示安全区，又提供起跳反击空钟钟舌弱点的战术支点。
  - 战场边缘补给：`ArenaCacheWest (2732, 320)` 与 `ArenaCacheEast (3356, 320)` 两处可砍碎补给物可在激战中提供额外余烬回血。


## 输入验收修正（2026-10-24）

下沉钟堂底板延至 x=2432，和末级悬台末端之间留出32px净空；失足骑士可在未开捷径时用单跳爬回主路，避免跳起撞头。两口回廊坠钟移至2480/2560，给脱困落点留出安全站位。真实角色物理回归从(2050,352)以普通输入走到(2460,320)，未解锁额外跳跃；该夹具停用敌人与机关，仅证明地形脱困。整章正常输入战役仍待最终验收。
