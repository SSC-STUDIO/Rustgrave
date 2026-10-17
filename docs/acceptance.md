# Rustgrave 验收记录

## 2026-10-17 全面升级 · 阶段一（样板）验收

环境：Windows 10、Godot 4.7.1 stable、GL Compatibility、NVIDIA RTX 4060 Laptop。
世界视口 640×360，UI 1280×720 设计单位。所有测试与输入验收使用独立 `%TEMP%` 下的
APPDATA 与独立存档；玩家正式存档未参与。

### 基线

- 升级前工作区（含此前未提交的装备/UI/天气改动）先做基线提交并全量回归：
  **670/670 通过、0 engine errors**。
- 阶段一结束时的全量回归：**756/756 通过、0 engine errors**（数字随后续本轮改动增长，
  以最终提交为准；本页记录每一步的实际数字）。

### 阶段一样板：标题 → 开场 → 第一章 → 战斗 → Boss → 第二章

真实输入验收（`InputWalkthrough`，只发送移动/跳跃/冲刺/攻击/交互/菜单输入，不传送、
不改数值；独立存档）：

| 路线 | 结果 | 死亡 | 关键里程碑 | 引擎错误 |
|---|---|---|---|---|
| 复燃（rekindle） | PASS | 1（主动验证死亡恢复） | new_game → 教学台 → 毒坑 → 喷吐者/钩锁 → 压板 → 窑核 → 融门 → 余烬核 → 东翼存档 → Boss 击杀 → 死亡重载 → 暂停回标题 → 继续 → 复燃 → 第二章落地 → 地下存档点 → 毒池 → 继续验证 | 0 |
| 熄灭（snuff） | PASS | 1 | 同上直到炉心选择熄灭 → 提前结局 → 标题 | 0 |

- 本轮修掉验收脚本自身的一个真实缺陷：标题在**有存档时默认把光标停在「继续」**
  （`title_screen.gd`），旧 walkthrough 仍固定按一次 ↓，于是落到「设置」、世界永远不加载。
  `input_walkthrough.gd` / `campaign_walkthrough.gd` 改为读取该状态后直接确认。
  修复前可稳定复现 `[WALKTHROUGH FAIL] boss_death_reload: world did not become playable`。

演出验收（离屏真实渲染，不是桌面截图）：

- `CinematicAcceptance`：开场 14/14 张、`opening_seen=true`、移动提示可见、
  0 engine errors。第一拍推近到 2.35×，趴着的骑士旁边立着插进土里的巨剑；
  起身后剑回到背上，跳过/abort 走同一条还原路径。
- `BossPresentationAcceptance`：拱门入场（名号卡+炉光涌起，只演一次）、竞技场构图、
  原生 640×360 可读性、斧落点预警框、二阶段（炉火转红热/相位刻度）、死亡（竞技场熄灭、
  炉心解锁、E 提示）、真实 ForgeHeart → Level02 章节交接；`engine_errors=[]`。

### 画面（逐张用 read_image 实看，不是只看通过率）

- 第一章：删除全部不透明占位色块，改为真实目录素材的场景细节（骨堆/断碑/倒石/斜梁/
  锈管/垂链），按区域手排；光照锚定地标节点（余烬巢/毒池/门/锈门/余烬高台/Boss 门/
  炉心）。天空/远山/云派生为锈月夜板（原板保留作回退），加地平线暖雾与 3 束夜色月光；
  材质色阶把草地压成枯橄榄、悬空石板从薰衣草紫收暖、腐液调酸黄绿、植被去饱和。
  渲染：`screenshots/peek/lead-1a`、`lead-1b`、`lead-materials3`、`lead-ui/after1080`。
- 主角：背扛锈蚀锯齿巨剑（1x 像素、程序化生成、`tools/gen_greatsword.py`），
  探索/跑/跳/冲刺可见，挥砍/死亡让位给帧动画；开场先插在土里。
  渲染：`screenshots/peek/lead-1c`、`screenshots/acceptance/cinematics/01-prone.png`。
- Boss：整数 2× 绘制（`docs/art-spec.md` 记录的例外）并同步放大判定；身体提亮 +
  有上限背光/暖底光/冷前光/接地影，骑士仍比他亮 1.78×。渲染：`screenshots/peek/lead-1d/`。
- 界面：毒素槽加宽/分档配色/空槽读作空通道；Boss 血条余烬色 + 相位菱形；交互提示
  按键帽；低血量暗角减半（骑士区域红染 +12.8 → +4.8）；顶部提示从 24px 横幅改为
  12px 小牌并会在首次 Tab 后消失；设置页焦点进入当前分页；触控安全区可注入测试。
  1080p/720p 前后对照：`screenshots/peek/lead-ui/{before,after}{720,1080}` 与
  `crops/final_compare_*.png`。

### 音频（数值验收，无听感结论）

- `tools/gen_audio_verify.py`：136 个文件、55 个 LIBRARY 键、39 个变体、9 条环境循环、
  8 个主题床、10 个音乐主题、2 条 Boss 轨、9 个 stinger；0 缺失/0 未导入/0 未解析键/
  0 削波/0 直流偏移。修复 `cemetery_drone` 每 4 秒一次的循环爆音（-16.7 dBFS、
  60.3× 自身步长 → -54.1 dBFS、0.69×），雨/锈雨/巢嘶重做为圆形循环（交叉淡化残留与
  直流偏移清零）。44 条循环全部通过接缝指标。
- 音量关系：平静音乐 -20.7 LUFS / 危险 -19.1、Boss 床 -19.5、stinger -17.0；
  环境床低于音乐 10–19 dB；SFX 一次性峰值中位 -8.0 dBFS；Limiter 兜底不削波。
- 新增回归：`tests/audio_library_test.gd`（873 断言）、`tests/music_test.gd`（189 断言）。

### 本轮发现并修复的可靠性问题

- 标题「有存档默认停在继续」与验收脚本假设不符（见上，walkthrough 修复）。
- `hud_layout_test` 曾因前序用例泄漏 `director_playing/input_locked/letterbox/caption`
  而只在全量运行失败：测试在 setup/teardown 归一化并打印泄漏状态，现全量稳定。
- `CinematicAcceptance` 因按字幕文本兜底认 tag 而重复抓 08-forge、门禁假失败：
  改为只认步骤 tag，14/14 稳定。

### 并行上游修复的合并（透明记录）

本轮期间从并行分支 `cursor/upgrade-phase1` 合并了 10 个无冲突、互补的提交
（merge commit `8a28a12`）：淡变期间 Esc 暂停请求不丢失、非整数窗口下命中/相位闪光与
字幕/黑边限制在游戏画面内、移除第一章三处重复的浮空窑核（刮渣堆才是本章窑核）、
第 4 章橙色冷却液、第 6 章陵墓门后新增 crypt 存档点（最大存档间隔 1944→1328px）、
peek `--layers`/`-Win`、walkthrough 拾取重试。合并后全量回归与双路线输入验收均通过。
未合并的并行美术线（rust_grade 着色器/章节 grade）与现有锈月派生板方案冲突，
已弃用，避免两套调色叠加。

### 阶段二 2A：全章节视觉 QA（小贴图适配 / 室内背景）

逐章逐机位实看并修（before = `screenshots/peek/qa-base/`，after = `qa-final/`，
完整清单在 `qa-final/FINDINGS.md`）：

- **室内背景**：05/08/10 画面上 55–65% 是无内容黑区。新增程序化室内套件
  （`wall_{iron,forge,core,slate}` 无缝砖墙、`truss_*` 屋顶桁架、`machinery_*`
  地面机械剪影，工业视差由绿改暖铁），按 `ThemeBackdrop.covers_top` 接入并压暗到
  背景明度阶梯；钟楼贴图偏移 bug（整关约 90% 黑）与圣殿上部 30% 黑区一并修复。
- **"贴纸"道具**：`gh_bones/life_remains/skull_arch/rock_pile/furnace` 的不透明图集底
  被 flood-key 掉；Kenney 70px 历史道具补 1x 硬边半分辨率、按主题材质族重着色
  （iron/basalt/moss/rampart）；这些道具按叙事位置重新落地（工坊"上一班的活"、
  熔渣断机、炉心吊装链）。
- **错误材质族**：共享的教堂紫门/压力板/锈门改为随章节材质族重贴图；工坊/熔渣/
  炉心/街巷/城墙移除十字形"墓地"碎石；街巷与城墙灌木改干枯色。
- **像素密度**：清掉全部分数缩放（0.65/0.7/0.9/1.15 等），改用 1x 裁切图键
  （`tree_1_px/tree_2_px/bush_l_px`）；钟楼栏杆/尖窗、熔渣石板、炉心石柱归 1x 并对齐。
- 新增 `tests/prop_fit_test.gd`（3 用例 / 1048 断言）：道具目录的"贴纸"审计（四角
  不透明检测 + 白名单）、各章所种道具的材质族白名单与接地/整数倍、室内主题背景
  必须覆盖相机顶带。
- 未解决/移交：街巷天空上带的规则点阵来自 `assets/shaders/pixel_smooth.gdshader`
  （像素平滑着色器，属于 UI/渲染层，不在本轮美术范围）；街巷砖台边缘仍带源图集的
  绿色苔簇（需要决定是否重做 brick 族地砖）。

### 性能（离屏窗口测量，不冒充真机）

`tools/perf_probe.gd` + `scenes/tools/PerfProbe.tscn`：在真实画布壳里按四个机位采样
Godot `Performance` 监视器（进程帧时间、绘制调用、节点数）。1280×720 / 1920×1080 各跑
一遍，结果存 `screenshots/peek/perf/*.json`。这是在隐藏窗口 + 同机其他渲染任务可能
并行的情况下测的，只用于发现明显瓶颈与节点/绘制增长，不作为真机帧率。

### 已知未验证

- 真机触屏/刘海安全区：只验证了注入 insets 的数学与桌面强制触控渲染；Android 设备未实测。
- 人工手感与「音量是否好听」：无听感测试，音频结论全部来自数值与契约。
- 实体显示器性能：性能探针是离屏窗口测量（并发渲染时数据有噪声），不冒充真机帧率。
- 剧情分支覆盖：验收只覆盖第一章复燃/熄灭两种结局与第二章开端，其余章节依赖既有
  `chapter_progression_test` 与后续阶段推广。

---

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
