# 锈墓・叁 — 运渣水渠（`level02b`）v3 重设计蓝图

## 1. 章节定位与空间动线（`0..3680`，`y = 120..352`）

`level02b`「运渣水渠」承接沉钟地窟出口，是地下墓穴通往地表锈城街巷的排渣动脉。v3 重设计围绕 **「双水位切换改变过渠路线」** 与 **「闸口涌流（`ForceZone` `water`）脉冲推力」** 两大专属机制重构了全章动线：

| 分段 | X 范围 | 高度层级 (Y) | 核心体验与机制 |
| :--- | :--- | :--- | :--- |
| **① 水闸广场** | `0..1120` | `288 / 320 / 352` | 起点点亮首座余烬巢 `EmberNestSluice (176)`、阅读 `SteleSluice (300)`；在平地 `FloorSluice (384..464)` 经历**首处闸口涌流安全教学位 `SurgeTeach`**（前后各 `>64px` 无毒无怪安全平地，观察 `0.6s` 水纹预警与周期推力）；跨过小渠 `SluiceCanal (560..720)` 后，在绞盘石高台 `CapstanStep (800, 288)` 踩下压板开启 `SluiceGateDoor (1008, 256)`（**遭遇战 1**），抵达第二座余烬巢 `EmberNestBridge (1088)`。 |
| **② 双层运渣大渠** | `1120..2064` | `120 / 272 / 288 / 320 / 352` | `944px` 宽的主运渣渠。西桥头石 `HaulStoneW (1120, 288)` 上设有**双水位切换阀板 `DrainValvePlate (1144, 288)`**：<br>· **高水位态（默认）**：走上层悬索吊台桥（`HaulStoneMid` + `LiftHaulWest/East`，`y=272`），迎战高空飞魔、幽魂与双向闸口涌流 `SurgeCanalWest/East`；<br>· **低水位态（踩阀泄水）**：`CanalWaterController` 将 `SlagCanalPool` 液面降至 `y=350` 并削弱涌流推力，露出下层渠床石墩（`CanalPierW/Mid/E`，`y=320`）与渠底通路（`y=352`，**遭遇战 2**）。上下两路均无需钩锁即可通关。 |
| **③ 抽水井与捷径** | `2064..2940` | `136 / 168 / 200 / 296 / 320` | 登岸即达第三座余烬巢 `EmberNestConduit (2084)`。主地面东端立有单向捷径门 `PumpShortcutDoor (2744, 256)`（初始关闭）；首次探索需穿过抽水井底层遭遇战（**遭遇战 3** 与 `SurgePumpWell` 涌流），乘竖吊台 `PumpLift (2500, 296 -> 152)` 登上 `PumpCatwalk (2448, 136)`，再沿 `PumpOverlookE (2600, 168)` → `PumpStepE (2696, 200)` 越过捷径门落回东侧，踩下 `PumpShortcutPlate (2784, 320)` 永久打通地面捷径，直抵第四座余烬巢 `EmberNestPump (2890)`。 |
| **④ 排水闸井竞技场** | `2940..3540` | `288 / 320` | `600px` 宽的绞盘守渠人（`CapstanWarden`）竞技场，两侧设避水石台 `ArenaPerchWest (2984, 288)` 与 `ArenaPerchEast (3440, 288)`，配合 `ArenaDrainage` 二阶段自动泄水机制；击败 Boss 后开启出口 `Exit (3592, 320)` 前往 `level03`。 |

---

## 2. 双水位切换机制（`DrainValvePlate` + `CanalWaterController`）

- **控制器节点**：`Props/CanalWaterController`（连接 `Props/DrainValvePlate.activated` 信号）。
- **状态切换逻辑**：
  1. **`water_state == "high"`（初始态）**：
     - `SlagCanalPool` 液面位于 `y = 336.0`（高度 `32px`），涌流 `SurgeCanalWest/East` 保持 `100%` 推力（`±72 px/s`）。
     - 推荐路线为上层悬索桥（`HaulStoneW -> HaulStoneMid -> LiftHaulWest -> HaulStoneE -> LiftHaulEast -> FloorWell`），风险来自空中敌人与横渡吊台上的脉冲水推。
  2. **`water_state == "low"`（泄水态）**：
     - 踩下 `DrainValvePlate (1144, 288)` 后，`SlagCanalPool` 液面退落至 `y = 350.0`（高度缩至 `16px`、透明度降低），涌流推力衰减至 `65%`，下层石墩 `CanalPierW (1384, 320)`、`CanalPierMid (1552, 320)`、`CanalPierE (1840, 320)` 高亮显露。
     - 玩家可沿下层渠床石墩快速突进，正面对抗渠墩上的散射喷吐者 `SpitterCanal`。

---

## 3. 存档点、单向捷径与可选挑战

### 3.1 四座余烬巢（间距全部 `<= 1000px`，且均在敌人仇恨/唤醒圈外）
- `EmberNestSluice`：`x = 176.0, y = 320.0`
- `EmberNestBridge`：`x = 1088.0, y = 320.0`（距前巢 `912px <= 1000px`）
- `EmberNestConduit`：`x = 2084.0, y = 320.0`（新增大渠东岸存档点，距前巢 `996px <= 1000px`）
- `EmberNestPump`：`x = 2890.0, y = 320.0`（距前巢 `806px <= 1000px`，距 `ARENA_LEFT = 2940` 仅 `50px <= 80px`）

### 3.2 单向捷径回环
- **路径**：`EmberNestConduit (2084)` 与 `EmberNestPump (2890)` 之间的地面在 `x = 2744` 处被 `PumpShortcutDoor` 封锁。首次推进需乘 `PumpLift (2500)` 登上 `PumpCatwalk (y=136)`，再经 `PumpOverlookE (y=168)` → `PumpStepE (y=200)` 从门顶越过，落地踩响 `PumpShortcutPlate (2784, 320)` 永久开启捷径门，使后续来回无需再绕行上层吊台。

### 3.3 钩锁支路与奖励点
- **路径**：从运渣桥上层吊台借钩锁锚点 `HookCapstan (1548, 48)` 荡上高空绞盘架 `CapstanGallery (1472..1568, y=120)`（主线无钩锁时高差 `152px > 34px` 不可达）。
- **内容**：阅读支路碑文 `SteleCapstan (1500, 120)`「水渠纪事 · 闸」，拾取装备奖励 `RewardCapstan (1540, 113)`（`reward_kind = "equipment"`，`reward_ref = "toxic_ward"`「滤毒符印」），并可击碎 `CanalCacheWest (1480, 120)` 获取余烬回血。

---

## 4. 闸口涌流机关与三场分阶段遭遇战

### 4.1 闸口涌流（`force_zone(..., "water", ...)`）
| 节点名 | 区域 `Rect2` | 推力 `push` | `gust_period / duty / phase` | 职责 |
| :--- | :--- | :--- | :--- | :--- |
| `SurgeTeach` | `(384, 280, 80, 40)` | `(-68, 0)` | `4.6s / 0.42 / 0.00` | 安全教学位：前后各 `>64px` 连续平地，无毒池无敌人，提供无惩罚观察 |
| `SurgeCanalWest` | `(1220, 240, 152, 112)` | `(-72, 0)` | `4.8s / 0.45 / 0.00` | 覆盖大渠西段上下两层，逆向推阻过桥与涉水 |
| `SurgeCanalEast` | `(1640, 240, 168, 112)` | `(72, 0)` | `5.2s / 0.45 / 0.50` | 覆盖大渠东段上下两层，顺向突推考验落点控制 |
| `SurgePumpWell` | `(2360, 264, 120, 56)` | `(-76, 0)` | `4.5s / 0.45 / 0.25` | 位于抽水井主交战区中央，配合敌群制造走位压力 |

### 4.2 三场分阶段遭遇战与敌人变体
1. **遭遇战 1（水闸广场绞盘台，`x = 740..960`）**：
   - `Scrapper1`（`scrapper`，`(748, 320)`，变体 `&"armored_scrapper"` 装甲碎铁犬）守在 `CapstanStep` 西侧；`SkeletonGate`（`skeleton`，`(884, 320)`，变体 `&"exploder_skeleton"` 爆裂骸骨）守在绞盘石东侧，死后延迟自爆逼迫玩家离开压板。
2. **遭遇战 2（双层运渣大渠，`x = 1380..1900`）**：
   - 上层路线：`FlyingDemon1 (1500, 210)` 与 `GhostCanal (1860, 204)` 在悬索吊台上方袭扰；
   - 下层路线：`SpitterCanal`（`spitter`，`(1576, 320)`，变体 `&"scatter_spitter"` 散射喷吐者）盘踞中央石墩 `CanalPierMid`，封锁低水位涉水路线。
3. **遭遇战 3（抽水井双层防线，`x = 2316..2640`）**：
   - 地面由 `Scrapper2`（`(2316, 320)`，`&"armored_scrapper"`）与 `Scrapper3`（`(2560, 320)`，`&"swift_scrapper"` 疾行碎铁犬）前后夹击，中间穿插 `SurgePumpWell` 涌流与 `Spitter1`（`(2470, 320)`，`&"scatter_spitter"`），上方由 `Ghost1 (2640, 268)` 封锁登吊台路线。

---

## 5. 绞盘守渠人（`CapstanWarden`）竞技场排水设计（`x = 2940..3540`）

- **两侧避水石台（`ARENA_PERCHES`）**：
  - `ArenaPerchWest (2984..3040, y=288)` 与 `ArenaPerchEast (3440..3496, y=288)` 在 `_build_boss` 中生成（独立于 `STEPS` 常量以兼容 `chapter_art_audit_test` 的预留场地常量审计），为玩家应对守渠人抛钩拖拽（`hook_cast`）与掀起泥浪（`dredge_wave`）提供高处落脚点。
- **二阶段自动排水（`Props/ArenaDrainage`）**：
  - 一阶段（`water_state == "high"`）：竞技场地面覆有浅层渠水；
  - 当 `CapstanWarden` 血量过半触发 `phase_entered(2)`（或 `slain`）时，`ArenaDrainage.drain(2)` 自动将竞技场水线排干至 `water_state == "drained"`，视觉与状态同步切换。


## 正常输入发现的修正与证据（2026-10-24）

东踏石移至640..688，留出32px坑岸净空；抽水井西检修台缩至2448..2496，避开吊台顶点上方的骑士头部。真实角色物理夹具覆盖失足爬岸、吊台骑乘及单跳/冲刺到东检修道、下降踩开原捷径压板：3/3通过。导航读取关闭门实际状态，先绕上层；守渠人等玩家进入竞技场再开战。

本章布局与脱困回归13/13、全章Sanity13/13、守渠人10/10，0engine errors。输入检查input-20261024-181916-476由前段正常存档恢复，零死亡击败守渠人并通过出口进入03；此为恢复调试，尚不代表14章新游戏通关。

截图：screenshots/acceptance/overhaul-v3/level02b-recovery/720p-final和1080p-final，640/1248/2084/2600/3260两档共10张已逐张检查。渲染夹具停放骑士、免伤并结束入场演出，仅证明画面与地形。最终全量仍待整合。
