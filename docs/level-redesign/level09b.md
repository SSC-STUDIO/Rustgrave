# level09b 炉风崖道：三折崖路

保持出生点 `(96,-340)`、宽3400、镜头顶−400、主题ramparts、`level09b_done → level10`、`herald_dead`及全部故事正文。不改基线存档格式与v2兼容路径（当前共享角色档案基线已写v3）。保留先驱的场名、尺寸、攻击和落石/火柱机关。

```text
y−320  入口巢176 → 首风 → 崖卫 → 风巢944 → 东折口1120
                                                 ↓
y−160              折返巢592 ← 落石廊+飞魔 ← 东侧接台
                         ↓          ↑钩锁LeeLedge奖励
y0                 西折口 → 塌桥前巢1088 → 塌桥/固定墩 → 前哨伏击 → 原Outpost巢1848
                                         ↓96px接台/逃生阶                 ↓
y160/192                                               崖壁下降—下层哨位
y320                                                             Gate巢2680—先驱场—炉心门3320
```

| 区段 | 实现计划 |
| --- | --- |
| x0–1120，上层−320 | 保留Cliff巢176和灰碑。首处余烬风推+72、周期4.8s、半周期有风，两边48px以上安全面；中段散射喷吐者和装甲犬集中。新增Wind巢944，入口和巢避开警戒范围。 |
| x480–1184，中层−160 | 东折口降160px接到中层，路线向西。保留BridgeRockfallRig和3.2秒计时器，三个固定落点轮换、预警至少0.55s；一只独立飞魔守落石廊。Fold巢592位于落石西侧安全湾。 |
| x480–1552，下层0 | 西折口下落160px到下层，再向东行。新增Bridge巢1088。两段96px塌桥由固定宽墩隔开，抖动1.4s、恢复4s；首段前后至少48px永久安全台，下面96px接台和32px逃生阶，落石不覆盖塌桥。 |
| x1552–2120，前哨0 | 重盾卫和有界幽魂构成第二处地面遭遇；保留WindGatePlate/Door与Outpost巢1848、先驱碑。避风天气覆盖巢。单向回程从上方折返路的48px缺口x1008..1056落到Bridge巢附近，不能一跳逆爬。 |
| x2120–2740，下降到320 | 分段下落至64/128/192/256/320；一处余烬风与第三处地面遭遇（爆裂骸骨/有界幽魂），警戒范围避开Gate巢2680。保留门碑。主线不要求钩锁、二段跳。 |
| x2740–3400，先驱场 | 保持660px竞技场边界、Boss原点3050/320、原落石2860/168及火柱3220/320；两侧增32px高台x2800..2896、3232..3296，中央保留战斗/落地空间，右台不遮出口。门前旧巢距场门仍≤80px；出口3320要求herald_dead。 |

## 可选路线与兼容

- 保留HookLee、LeeLedge、Pickups/CoreReward；钩锁支路位于落石廊上方，保持普通跳不可达，奖励包含原ember_core和新增装备骨符。原碑文字来自ChapterText，不增加故事文字。
- 原Cliff/Outpost/Gate巢、WindGate门和压板、SteleAsh/Herald/Gate、出口和Boss节点保持名字/父级。新增Wind/Fold/Bridge巢使折返路线的复跑距离接近1000px以内。
- 沿实际折返折线计算的五段巢距分别为768、962.1、881.2、760、916.4px；测试逐个采样点验证实心支撑。不是按排序后的横坐标估算。
- 风采用ForceZone ember皮肤，推力72–80且始终≤96，预警0.6s，冲刺按原控制器不受风。局部天气矩形和实际推力区分开记录。
- 先驱原420px自动警戒会覆盖门前旧巢。本章用HeraldApproach区域在跨入x2740后恢复Boss物理更新，再由原AI启动；Boss脚本、攻击表、命中范围、导演和旗标没有改动。六秒静默检查覆盖所有巢，另用真实玩家跨门验证原AI启动。
- 只修改本章布局、章节测试、本文；必须动共享运行时代码前先报告。每个完整改动提交，不运行全量测试。

## 验收范围

- 基础路线及六巢、压板、出口可达；真实三层折返和单向回程；塌桥实际崩塌、接台和逃生；真实余烬风推人；落石轮换与预警；钩锁奖励；三处遭遇及六秒巢安全；先驱契约/旗标/门前80px。
- 章节专测、过滤level09b的Sanity、route_audit、chapter_progression、level_routing、level_weather、chapter_art_audit、prop_fit、chapter_support、parallax_backdrop、system_budget，以及force_zone/collapsing_platform/emberwind_herald相关测试。
- 至少5个对应机位×1280×720/1920×1080，覆盖上/中/下折返、塌桥、前哨和Boss全景，逐张查看。停放截图不代表正常输入全章通关或真人手感。完成后补精确路径与计数。

## 2026-10-24 实际验收

测试命令均从本章独立worktree运行：`./tools/run_tests.ps1 -CaseFilter <case> -TimeoutSeconds 240 -ArtifactsDir <本worktree绝对路径>/screenshots/acceptance/overhaul-v3/level09b/tests-<case>`。章节布局目录名为`tests-chapter`；`level_sanity`额外设置`RUSTGRAVE_LEVEL_FILTER=level09b`并在运行后清除。没有运行全量。

| CaseFilter | 通过数 | 说明 |
| --- | --- | --- |
| level09b_layout | 14/14 | 真实风推力、真实塌桥/接台/普通跳、六巢各6秒静默、折返路程、钩锁可选、先驱跨门后启动、出口净空 |
| level_sanity | 13/13 | 本章过滤几何/可达/像素脚点，加共享机关负例 |
| force_zone | 7/7 | 阵风和冲刺契约 |
| collapsing_platform | 5/5 | 塌落/恢复/安全窗 |
| emberwind_herald | 6/6 | 原先驱套件、落点和两阶段契约 |
| route_audit | 2/2 | 真实关卡重生点到出口/核可达 |
| chapter_progression | 5/5 | 分组后检查章节到达、恢复机关、热锻保留及终章 |
| level_routing | 6/6 | 注册、路由和存档场景 |
| level_weather | 6/6 | 天气矩形与真实玩家切换 |
| chapter_art_audit | 4/4 | 主题、素材和Boss场 |
| prop_fit | 7/7 | 白名单、像素接地、整数缩放 |
| chapter_support | 2/2 | 共享支撑契约 |
| parallax_backdrop | 8/8 | 背景层 |
| system_budget | 2/2 | 本章4机关、8灯、2603节点 |

共87/87，全部0 engine errors。仅出现现有Control锚点警告。锚点下移到`(1384,-376)`后重新跑过章节14/14、过滤Sanity13/13和route_audit2/2。

截图根目录：`screenshots/acceptance/overhaul-v3/level09b/`（本地证据，gitignore）。下列每组同时有`render-720-<组>`与`render-1080-<组>`，全部使用`-Hold 4 -Lit -Active`，18张均逐张打开检查，并以System.Drawing读取实际PNG尺寸。清单为根目录`png-dimensions.json`。

| 组 | 镜头x | CamY | 已核对内容 |
| --- | --- | --- | --- |
| upper | 432、944、1360 | -260 | 首风、上层遭遇与巢、中层折返、完整可见的钩锁和两份奖励 |
| middle | 944 | -90 | 中层落石走廊、48px单向落口、下层桥前巢 |
| lower | 1360、1848 | -20 | 两段塌桥、中央墩、接台/逃生阶、压板门、前哨遭遇/巢 |
| descent | 2448 | 180 | 分层下降、门碑、低层遭遇和门前巢 |
| boss | 2992、3120 | 220 | 对应双图覆盖660px竞技场，两侧32px台、中央空间、原火柱与门道净空 |

未见关键物悬空、角色嵌地、奖励遮蔽或出口被实心侧台堵住。活动敌人、机关和提示可能随时间改变，这些是停放渲染fixture；没有据此宣称普通输入整章通关或主观手感验收。正常输入campaign验证由根工作树统一继续。

共享测试/工具仅本地采用根分支已有`4b3ac07`（PeekLive尺寸门禁）和`163e770`（章节恢复拆组）；不是本章新改动，集成时不要重复挑取。本章实现提交只含布局、章节测试和本文，不修改共享runtime。
