# 标题活景 / keyart 与渲染性能验收

日期：2026-10-24。标题基线 `fbb3c96`，独立分支 `codex/title-perf-acceptance`。功能 `b3c7b09`、捕获/探针工具 `222a280`、最终灯位 `9fb3067`；章节补测使用整合根树 `ac00a52`。

## 发现与修复

- 原实现 5 盏吊灯的 `ceil(N*5/14)` 已改为 14 个可见灯笼、精确 N/14。5 个吊灯使用点光池，另有 3 个环境光，仍保持 8 盏预算。
- 裸图审阅又发现边缘灯被近景机壳挡住，已把灯排到世界 x=80..483、顶 y=38，并将灯链置于机壳前。最终图中 act2 可数出 4 盏亮灯、act4 为 13 亮/1 暗、守火为 14 全亮；不以节点计数替代可见性。
- 光柱、炉门及 2 个吊灯光池开启真实阴影，桥身、炉柱、骑士有 LightOccluder2D。冻结同一时刻拍摄阴影开/关，骑士及炉边照明确有差异。
- 守火结局使用从原皮肤装甲像素制作的独立 48×48 坐姿（3 个皮肤纹理，AshRunner 复用 fantasy 并沿用染色），坐在炉边铁凳，隐藏站姿背剑。
- TitlePeek 增加 keyart 回退、阴影对照、实际尺寸稳定检查与 JSON；wrapper 启动后恢复 APPDATA。FrameCostProbe 增加标题/静态模式、真实章节入口、原始回调间隔与 p95，不再把两个 CPU monitor 相加或声称逐脚本归因。

## 最终标题截图

证据根：`screenshots/acceptance/overhaul-v3/title-perf/`。最终主矩阵为 `final-live/` 的 12 张与 `keyart/` 的 12 张，4 变体 cold/give/keep/snuff × 960×540、1280×720、1920×1080；24 张均逐张打开审阅，并由 Pillow 验证解码、文件名尺寸、JSON 实际尺寸一致。

| 检查 | 结果 |
|---|---|
| cold | 冷炉、骑士背剑、0/14 灯与禁用继续项 |
| give | 14 灯亮、骑士离场、桥心插剑 |
| keep | 14 灯亮、骑士坐于炉边，余烬巢可辨 |
| snuff | 吊灯全暗、骑士与剑均无，残红照明 |
| keyart | 每种存档使用静态背景，12 份 JSON 均为 `has_live_viewport=false`；UI 保持同一布局 |
| 三档排版 | 未见菜单/旅程列/墓志裁切或相互遮挡；灯位避开 Logo、菜单和右栏 |
| 960×540 | 保留 640×360 居中整数缩放内容与黑边；次要档案/页脚文字较小，未把它视作触屏可读性验收 |

`final-smoke/` 的 act2/act4 idle 及 keep shadows_on/off 四张补充图均已审阅；`capture-manifest.json` 列出最终 24+4 张的实际尺寸、SHA256、状态与审阅标记。早期 `live/`、`smoke/`、`supplement-*` 图保留作历史诊断，其灯位已被最终矩阵取代。

## 自动化与几何

| 套件 | 用例 | 断言 |
|---|---:|---:|
| title_world | 20/20 | 1294 |
| title_screen | 20/20 | 215 |
| title_flow_adversarial | 5/5 | 59 |
| display_resolution | 6/6 | 49 |
| ui_transition | 6/6 | 50 |
| modal_screens | 5/5 | 86 |
| m5_tier5_adversarial_ui | 6/6 | 85 |
| system_budget | 2/2 | 101 |
| 合计 | 70/70 | 1939 |

以上全部 0 engine errors。最终灯位变更后 title_world/title_screen 又复跑 40/40（1509 断言），保存在 `tests-final/`；其他 6 组保存在 `tests/`。TitleMetrics 在 1280×720、1920×1080、2560×1080 打印 `0 problem(s)`，菜单不越中线、离开/墓志中心 y=640；日志在 `metrics/title-metrics.log`。存在既有 Control 锚点 size warning，未将其称为 engine error。本分支没有运行独立全量套件或普通输入战役，整体验收由根任务执行。

## 性能方法与机器

Godot 4.7.1，Compatibility / OpenGL 3.3；渲染日志实际确认 NVIDIA GeForce RTX 4060 Laptop GPU、NVIDIA 560.94。CPU 为 i9-14900HX（24 核/32 逻辑线程），硬件清单在 `hardware.json`；未根据适配器清单推断实际 GPU。

每次验证实际窗口与缓冲尺寸，关闭该进程 VSync 和帧率上限，预热 2 秒。标题默认采样 4 秒；章节使用固定真实入口相机、静止无敌玩家，`-Active` 保留敌人子树运行。采样循环只等待 `RenderingServer.frame_post_draw` 并读单调时钟/monitor，结束后才读回 PNG。报告分别记录回调间隔、process/physics monitor、draw calls、节点类直方图和原始间隔；下表仅展示回调间隔的 p95/max，单位 ms。

初批 29 次在单个自动渲染进程条件下串行完成，但根任务的 headless 测试/输入工作仍在并发。最终标题 12 次也处于并发 headless 条件，不能用两轮波动推断灯位改变带来性能差异。五章根树补测期间，自动 headless 工作已暂停；用户原有编辑器 PID30864 与游戏 PID48392 仍在运行，未停止它们，故也不是完全空闲机器。根树补测窗口为 2026-10-24 11:53:50.945 至 11:55:14.892 UTC（19:53:50 至19:55:14 上海时间），进程清单和时间文件位于 `final-root/`。

## 标题回调间隔

每格为 p95 / max。live 使用最终灯位，keyart 使用相同回退路径；独立进程、不同背景负载的数值不作严格 A/B 加速比。

| 模式/变体 | 960×540 | 1280×720 | 1920×1080 |
|---|---:|---:|---:|
| live cold | 2.928 / 13.453 | 3.807 / 11.392 | 4.615 / 8.903 |
| live give | 3.142 / 23.146 | 5.036 / 14.469 | 4.361 / 8.650 |
| live keep | 4.091 / 12.919 | 4.236 / 9.895 | 4.024 / 10.548 |
| live snuff | 3.451 / 20.810 | 3.974 / 17.998 | 4.719 / 13.600 |
| keyart cold | 3.536 / 11.528 | 3.708 / 18.830 | 3.439 / 15.417 |

## 14 章入口回调间隔（1920×1080）

03/04/04b/09b/10 采用根树 8 秒补测；其余为基线 4 秒。二者的场景代码来源与背景负载不同，表中明确标出批次。

| 章节 | 批次 / 秒 | p95 | max | process monitor 均值 | physics monitor 均值 |
|---|---|---:|---:|---:|---:|
| level01 | 初批 / 4 | 6.679 | 14.410 | 10.118 | 3.216 |
| level02 | 初批 / 4 | 4.991 | 10.355 | 8.315 | 1.870 |
| level02b | 初批 / 4 | 5.337 | 13.656 | 10.790 | 3.478 |
| level03 | root / 8 | 6.700 | 21.325 | 13.066 | 1.571 |
| level04 | root / 8 | 6.265 | 46.734 | 12.175 | 1.424 |
| level04b | root / 8 | 4.126 | 31.970 | 9.695 | 1.013 |
| level05 | 初批 / 4 | 6.148 | 33.310 | 15.393 | 1.995 |
| level06 | 初批 / 4 | 5.845 | 15.939 | 13.198 | 3.522 |
| level07 | 初批 / 4 | 5.327 | 20.112 | 15.346 | 1.701 |
| level07b | 初批 / 4 | 4.992 | 18.231 | 9.295 | 1.341 |
| level08 | 初批 / 4 | 8.123 | 20.944 | 13.714 | 1.848 |
| level09 | 初批 / 4 | 5.949 | 17.530 | 12.862 | 1.275 |
| level09b | root / 8 | 5.434 | 15.043 | 8.609 | 2.209 |
| level10 | root / 8 | 5.217 | 11.487 | 9.214 | 1.286 |

初批 level10 曾有 **1251.407ms** 单次长停顿（p95 9.271ms），level09b 为 65.746ms（p95 8.462ms）；原始记录完整保留。自动 headless 暂停后的 8 秒复测，level10 为 p95 5.217/max11.487ms，level09b 为 p95 5.434/max15.043ms，未再复现秒级停顿。并发条件改变不能证明停顿根因已找到或修复；根树 04/04b 补测仍有 46.734/31.970ms 最大间隔，因此不能宣称全程无卡顿。

`probe-summary.json` 保存 46 次正式原始运行的索引与哈希（29 初批 +5 根树补测 +12 最终标题），明确选择上述 29 个机位数据。所有对应 PNG 均核验尺寸；初批/根树/最终标题的联系表用于检查场景、玩家与 HUD 确实在预期入口，不能代替关卡全机位美术验收。

## 七位原创Boss整合后的最终入口采样

在 `83e430c` 的整合树重新串行采集标题守火态及14章入口，各1920×1080、预热2秒、采样至少8秒。后续测试/工具/文档变化之外，`f7bcff7`为四类机关追加只读safe_window并提升最低抖动下限。`render-runtime-compatibility.json`逐字核对全部运行时差异：仅这四个未被既有运行时调用的方法，以及不影响当前章节0.6/0.7/0.8/1.4秒配置的预警下限。场景、画法、素材、布局与既有调用相同，故保留这批构图与停放入口采样；不称源码逐字相同。证据位于 `screenshots/acceptance/overhaul-v3/final-performance/`：`runs.json` 逐次记录时间、提交和其他Godot进程；`summary.json` 索引原始JSON/PNG及SHA256。15张实际PNG均解码并核对1920×1080，联系表已检查真实入口、玩家、HUD和标题坐姿。

本批日志确认实际渲染器为Windows Compatibility / OpenGL 3.3、RTX 4060 Laptop GPU，驱动字符串为 **NVIDIA 621.01**；上文560.94属于早期采样记录。玩家与相机固定，AI/机关运行；同期有headless全量和用户已有编辑器/游戏，具体PID及命令保存在每次记录中。没有停止用户进程，也不把本批与早期批次当作严格A/B。

| 机位 | 回调间隔p95 / ms | 最大间隔 / ms |
| --- | ---: | ---: |
| title keep | 4.040 | 12.987 |
| level01 | 4.872 | 6.821 |
| level02 | 3.764 | 12.796 |
| level02b | 3.915 | 20.543 |
| level03 | 3.642 | 13.704 |
| level04 | 3.349 | 23.336 |
| level04b | 4.136 | 18.862 |
| level05 | 4.061 | 22.928 |
| level06 | 5.001 | 19.437 |
| level07 | 4.375 | **1160.905** |
| level07b | 3.545 | 16.333 |
| level08 | 4.517 | 12.377 |
| level09 | 3.724 | 6.079 |
| level09b | 3.428 | 18.156 |
| level10 | 3.586 | 19.300 |

钟楼出现一次约1.16秒回调停顿，原始样本保留；并发条件下尚未确定来源，不能宣称已解决或全程无卡顿。本批证明当前树可采到真实渲染回调和CPU监视器数据，未测Boss交战最坏组合、GPU timer或实体屏幕呈现。最终报告保留这一限制。

## 复现与界限

```powershell
./tools/run_title_peek.ps1 -Variants 'cold,give,keep,snuff' -Sizes '960x540,1280x720,1920x1080' -Shots idle -OutDir screenshots/acceptance/overhaul-v3/title-perf/final-live
./tools/run_title_peek.ps1 -Variants 'cold,give,keep,snuff' -Sizes '960x540,1280x720,1920x1080' -Shots idle -Keyart -OutDir screenshots/acceptance/overhaul-v3/title-perf/keyart
./tools/run_title_peek.ps1 -Variants 'act2,act4,keep' -Sizes 1280x720 -Shots idle -Bare -ShadowPair -OutDir screenshots/acceptance/overhaul-v3/title-perf/final-smoke
./tools/run_frame_cost_probe.ps1 -Level title -Variant keep -Win 1920x1080
./tools/run_frame_cost_probe.ps1 -Level level10 -Active -Win 1920x1080 -SampleSeconds 8
```

- 离屏渲染回调频率不是实体显示器呈现 FPS；未获取 GPU timer、逐脚本时间、帧呈现或整机功耗。
- 固定入口、短时采样与无敌静止玩家不证明全关移动、Boss 战、最坏粒子/灯光组合、低端 GPU 或长时间稳定性。
- 本轮没有实体触屏/手柄、真人手感、实体显示器性能或现场音频听感验收；不能从单元测试、PNG 或回调频率推出这些结论。
- 标题截图/定向测试与探针证据已完成；最终接口提交后的普通输入14章战役已通过，见 `overhaul-v3/input-final/rekindle-window-contract/`。它采用公开辅助和基本能力、3次真实死亡、115张1080p截图、0引擎错误；与本页停放机位性能样本分别归档。最终全量以 `docs/overhaul-v3.md` 和 `docs/acceptance.md` 的最终记录为准。
