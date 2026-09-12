# Rustgrave 验收记录

本轮日期：2026-09-12。环境：Windows、Godot 4.7.1 stable，世界视口 640×360，渲染输入验收窗口 1920×1080。所有测试和输入验收使用独立 APPDATA；玩家的正式存档未参与验收。

## 全量测试

`powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_tests.ps1 -TimeoutSeconds 300` 完整运行结果：**363/363 通过，0 engine errors**。

原始日志：`C:/Users/ADMINI~1/AppData/Local/Temp/Rustgrave-tests-8154d31a399745be8972cca9bea75d36/stdout.log`、同目录 `stderr.log`。非错误输出包括已有的 Control 锚点警告，以及 Director 队列溢出测试主动触发的警告；没有隐藏测试失败或脚本错误。

覆盖包括：三种新敌人的行为与受击，梦魇半血阶段和四个召唤物上限，第 3–10 关几何/机关/敌人布置，钟楼四段吊台与入口/中层检查点，以及章节转场和持久化。`chapter_progression_test` 用真实场景检查第二至第十关入口、热锻继承、存档点/压板门/锈门恢复、跨关路径隔离和终局标志。场景测试允许直接设置测试演员位置；它与下述正常输入验收分开记录。

## 正常输入验收

`CampaignWalkthrough` 从标题的新游戏开始，通过移动、单跳、冲刺、攻击、交互和菜单操作推进。脚本只读取几何、敌人状态和存档来选择输入，不设置玩家坐标、不授予能力、不调用伤害或机关/结局接口。`-ResumeSave` 仅复制先前输入生成的隔离存档用于复现，报告标为 `resumed=true`，不计作全程通关。

`-Fast` 使用固定 60 Hz 物理步长加速模拟；日志中的 `elapsed_ms` 是运行墙钟时间，不能当作玩家通关耗时。`-Rendered` 同时经过真实图形后端并输出 PNG，但属于软件动作驱动的离屏窗口验收，不是人工键盘操作或实体显示器性能实测。普通运行可省略 `-Fast`。

已完成的新游戏复核（每份 JSON 都为 `passed=true`、`resumed=false`、`input_only=true`）：

| 路线 | 渲染 | 死亡次数 | 记录目录 |
|---|---|---:|---|
| 复燃 → 第十关终局；基础能力 | 否 | 19 | `screenshots/acceptance/input-20260912-123918-923/rekindle.json` |
| 复燃 → 第十关终局；首关含钩锁/余烬核支线 | 是 | 28 | `screenshots/acceptance/input-20260912-123918-949/rekindle.json` |
| 第一关熄灭 → 标题 | 是 | 1 | 同目录 `snuff.json` |
| 最终复核：基础能力，复燃 → 第十关终局 | 是 | 28 | `screenshots/acceptance/input-20260912-125526-704/rekindle.json` |
| 最终复核：基础能力，第一关熄灭 → 标题 | 是 | 1 | `screenshots/acceptance/input-20260912-125526-724/snuff.json` |

三次十章通关均包含全部余烬巢与压板、热锻熔门、钟楼中层暂停回标题再继续、梦魇击杀后自然死亡再复活、再次退出继续，以及最终字幕后回标题。基础能力模式每次进入第 2–10 关均断言未装备钩锁和余烬步。死亡次数包含主动验证恢复流程的死亡，不是人工难度评测。

所有报告的运行期 `engine_errors` 数组为空。Godot GL 后端在窗口进程退出时仍会输出 Texture/RID 回收提示（默认复燃/熄灭两线分别为 38/6 个纹理 RID，最终基础能力复燃为 21 个）；原始日志保留这些行，包装脚本沿用已有的退出提示过滤规则。全量测试的 0 engine errors 没有使用这一过滤。没有把失败的调试运行计入通过结果。最终基础能力渲染运行包含钟楼入口的最后一次安全修复，以及按已保存位置检查 Continue 的脚本修正。

可复现命令：

```powershell
& ./tools/run_input_acceptance.ps1 -Campaign -Rendered -Fast
& ./tools/run_input_acceptance.ps1 -Campaign -BasicAbilities -Ending rekindle -Rendered -Fast
```

## 本轮修复与视觉检查

正常输入复核补上了静态可达检查无法充分证明的恢复路径：圣殿唱诗台东侧的回程踏步、工坊齿轮石下的坑底净空、钟楼入口/中层余烬巢的敌人唤醒距离、熔渣出口巢前火骷髅的活动范围，以及终关走廊追兵与 Boss 竞技场之间的边界。每项修复都有针对性验证并单独提交。终局场景测试等待实际淡出完成后再检查标题目标，避免依赖固定三帧造成时序误报。

关卡定点渲染位于 `screenshots/peek/final03`、`final04`、`final05`、`final06`、`final08`、`final09`、`final10`，各五个机位；钟楼为 `final07-bottom`、`final07-mid`、`final07-top`，各两个机位。已逐组查看入口、机关区、连续跳跃/战斗区与出口；钟楼全高背景没有断层，吊链与薄楼板保留竖井，熔渣呈橙红色并与落脚石区分。这些工具机位允许冻结角色/敌人、点亮灯光，单独用于画面检查，不能充当输入通关证据。

正常输入的默认完整路线保存了 64 张复燃截图和 4 张熄灭截图，位于 `screenshots/acceptance/input-20260912-123918-949`；第 3–10 关的入口、机关、存档点、出口画面已按章查看。最终基础能力路线另保存 63 张 PNG，位于 `screenshots/acceptance/input-20260912-125526-704`，HUD 可见仅装备热锻。以下索引已查看：

- [钟楼入口、压板、中层继续、塔顶](../screenshots/acceptance/input-20260912-125526-704/tower-contact.jpg)
- [梦魇两阶段、击杀后恢复与最终字幕](../screenshots/acceptance/input-20260912-125526-704/finale-contact.jpg)
- [最终字幕原图](../screenshots/acceptance/input-20260912-125526-704/rekindle_final_caption.png)

Boss 两阶段截图包含完整马身与血条；恢复截图等待淡入完成。最终回标题的瞬间截图仍处于淡入阶段，标题场景到达另由输入报告断言确认。

## 既有显示与天气验证（2026-09-06）

世界输出固定为 640×360，UI 设计单位为 1280×720。已检查 1280×720、1366×768、1920×1080、2560×1440、3840×2160、1280×800、2560×1600、3440×1440；16:9 使用最大整数倍率，其他比例居中留黑边。视觉矩阵（`-Supplement`，30 张）沿走廊自西向东覆盖起点、毒池、中段（齿轮台/喷吐者/压板）、门区（堡垒残墙/锈门）、东翼、Boss 场、炉心室内外，各配昼、夜雨、雾三种天气，另有暂停、字幕和结局菜单。

渲染矩阵是离屏/窗口输出验证，记录内容矩形和性能；它不冒充物理显示器实测，也不替代真实输入通关。它冻结 `WorldClock`，所以毒雾、落叶、风摆这类环境动态不会出现在图里；要看动态请用 `tools/run_peek_live.ps1`（时钟运行，每个机位停几秒后出图到 `screenshots/peek/`，不是验收门；`-Lit` 先点燃所有余烬巢，`-Night` 换成夜雨，`-Weather fog|clear|rain|ember_wind|rust_rain|haze` 指定天气，`-Active` 让敌人 AI 照常运行，`-Level level02` 看第二关，机位 `shaft,pitb,ledge,hall,lift,nest2,gallery,bell`）。

`.tscn` 不支持 `#` 注释：节点块里的 `##` 行会吃掉紧随其后的属性（`Plat_760_184` 曾因此掉到原点、喷吐者悬空）。`level01_layout_test` 现在断言每个平台不在原点、每个落地敌人脚下有平台、同类敌人不重叠、每个敌人只有一张身体精灵。

第二关的几何由 `level02_layout_test` 守着：每条台阶链单跳 ≤32px、机关/敌人/存档点脚下有台、吊台两端对得上上下船的台面、整关是室内区。`level02_scene_test` 在真实场景里验证落点、命名空间存档、压板开门、热锻熔门、吊台载人和沉钟门收尾。


## 可恢复性

实施前快照位于 `C:/Users/Administrator/.codex/artifacts/rustgrave-before-20260905-112740.zip`。既有存档迁移会保留 `.before_progress_repair.bak`。本轮沿用 save version 1，以既有剧情标志保存 `nightmare_dead` 和 `game_complete`。
