# level09 锈城城墙：塔楼支路与风道

保持 `level09`、`ramparts` 主题、出生点 `(96,300)`、出口 `level09_done → level09b`、城墙铭正文和原持久化节点名。本章没有 Boss，不改下一章的炉风先驱。

```text
                          中塔瞭望台 y192               钩锁鹰巢 y160             箭楼奖励 y224
                       中巢 ← ↓   ↗                        ↑   ↓                    ↗   ↓
入口320—风教学256—西门楼顶256—中巢320—中塔256—东巢320—宽墩风道288/256—东塔256—箭楼前巢320—出口320
                 ↓ 96px ↙                                  下层避风室352
           门楼内室352—东侧敞口回中巢
```

| 区段 | 几何、机关与遭遇 |
| --- | --- |
| x0–704 入口和首风 | 起点巢176/320、原城墙铭；32px台阶升到墙顶256。首风480–592，推力+48、4秒周期、半周期有风，两侧各留48px以上安全读风处；下方352接台，失足能向西爬出。 |
| x704–1152 西门楼 | 顶部48px落口，向下96px进门楼室352；内室装甲犬和幽魂集中，墙顶另有一只独立飞魔。下层向西通入口巢，东侧留敞口和1120/352接台，单跳到Mid巢。 |
| x1152–2016 中巢和中塔 | 原Mid巢移1184/320。主墙顶256；从东侧1840/224踏点升到瞭望台192，保留城墙铭·风。瞭望台向西经ReturnBalcony落128px回中巢，普通单跳不能逆爬。散射喷吐者和疾行犬构成有高差的小遭遇；压板1920/256，原WallGatePlate/Door名字保留。 |
| x2016–2864 东巢和宽墩风口 | 原East巢移2208/320；旧五块小风石改成两个宽墩，台面宽128、间距48、单次上升不超过32。真实ForceZone推力先−64后+64，周期5秒、半周期有风；下面352接台，两端能由32px台阶爬出。第二只飞魔独守此处，和西侧分点。 |
| x2864–3328 东塔 | 墙顶256、下层避风室352；保留HookTower、EmberCore、SteleEyrie和EyrieC，鹰巢160保持钩锁专用，新增骨符奖励。下层可从东侧进入；原Rampart巢移3216/320。 |
| x3328–4200 箭楼外墙 | 短断口宽台过渡；主路320，上层箭楼224为普通跳可达的奖励支路。犬和塔上喷吐者组成最后一处地形遭遇，保留Pickups/RewardEyrie铁剑奖励。出口仍4080/320。 |

## 安全与兼容

- 四个旧巢保持父级和名字：Gate176、Mid1184、East2208、Rampart3216；相邻最大1024px，最后到出口864px。巢以真实AI静置六秒验收。
- 保留WallGatePlate/Door、SteleWall/Wind/Eyrie、HookTower、EmberCore、Pickups/RewardEyrie和Exit。不修改存档格式、章节顺序、Boss逻辑、故事或共享脚本。
- 首风预警取ForceZone的0.6秒，推力48/64低于上限96与跑速108，冲刺行为沿用共享控制器。天气区域只管表现，与真实推力矩形分别记录。
- 门楼/东塔房间使用32px屋面、至少64px内部净空；主路只需基础跳跃，鹰巢才要求钩锁。装备图像底边用节点上移7px贴合台面。
- 地面遭遇集中在门楼、中塔、箭楼，采用装甲犬、疾行犬、散射喷吐者；两只飞魔分开布点，喷吐者不交叉覆盖同一跳跃。

## 验收计划

- 章节专测：基础路线、全部巢/门/出口可达；高低塔楼分支及净空；单向落口；真实风道周期、方向、首遇安全面和低层逃生；三组遭遇与飞魔分点；钩锁奖励；巢六秒安全；旧名与出口兼容。
- 定向门禁：level09、仅level09的level_sanity、route_audit、chapter_progression、level_routing、level_weather、chapter_art_audit、prop_fit、chapter_support、parallax_backdrop、system_budget。不运行集成全量测试。
- 对应机位 x432/864/1696/2496/2992/3776，1280×720与1920×1080两档，各图逐张检查。截图仅为停放机位，不作为正常输入通关或真人手感证据。
- 本文先提交蓝图；实际验收计数和截图路径完成后追加。

## 已完成验收（2026-10-24）

| 定向用例 | 结果 |
| --- | --- |
| `level09_layout` | 13/13，含四个巢和首风两侧各六秒真实AI静置、真实阵风推人、普通跳跃离开门楼、原奖励消耗键、单向回巢及钩锁支路。 |
| `level_sanity`，过滤level09 | 13/13，包含全部基础路线、脚点、净空、天气与机关体检。 |
| `route_audit` / `chapter_progression` / `level_routing` | 2/2、3/3、6/6。 |
| `level_weather` / `chapter_art_audit` / `prop_fit` | 6/6、4/4、7/7。 |
| `chapter_support` / `parallax_backdrop` / `system_budget` | 2/2、8/8、2/2。 |

所有定向门禁均为零引擎错误。最终章节日志为 `screenshots/acceptance/overhaul-v3/level09/tests-chapter-final3/`，最终几何为 `tests-sanity-final/`，其余为同目录的 `tests-<filter>` 或 `tests-<filter>-final/`。命令为 `tools/run_tests.ps1 -CaseFilter <filter> -TimeoutSeconds 240 -ArtifactsDir <绝对路径>`，几何检查设置 `RUSTGRAVE_LEVEL_FILTER=level09`。没有运行全量测试。

六个对应机位432/864/1696/2496/2992/3776，两档共12张PNG，实际读取尺寸确认分别为1280×720和1920×1080；已逐张检查HUD、提示、塔室双层、风墩接台、塔楼奖励、出口与巢。720p目录为 `screenshots/acceptance/overhaul-v3/level09/render-720/`，1080p为 `render-1080/`。两档Windows OpenGL / RTX4060 Laptop日志均无引擎错误。复现：`tools/run_peek_live.ps1 -Level level09 -OutDir screenshots/acceptance/overhaul-v3/level09/render-1080 -Spots '432,864,1696,2496,2992,3776' -Hold 2 -Lit -Active -Win 1920x1080`。这些是运行AI的停放机位，未验证正常输入全章通关或真人手感。

没有修改共享玩法脚本。`tests/level_weather_test.gd`仅把两个Level09测试的硬编码旧风口坐标改成从GaleGap实际矩形取点；节点到时钟再到雨的真实玩家断言保留。塔室的局部AtmosphereZone在本章显式补上世界位置。原铁剑奖励直接加入原Pickups父级，回归测试确认旧消耗路径在_ready就移除奖励；新骨符使用独立名字。门楼东口取消会压头的低台阶并补接台，实际身体以一次普通跳跃爬出。
