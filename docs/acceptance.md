# Rustgrave 验收记录

## 2026-10-25：原生2.5K素材升级

在v3整合之后，世界保持640×360逻辑尺寸，以最高2560×1440物理分辨率渲染；UI仍用1280×720逻辑尺寸。新增1,166张密度4素材及统一加载适配，具体源稿、派生方式、复现命令和内存限制见 `docs/qhd-art.md`。

- 最终无过滤全量：**1471/1471、29062条断言、0引擎错误**，运行/素材源码 `7ed677ad`；`screenshots/acceptance/qhd/full-tests-verified/summary.json` 为 `passed=true`、`completed=true`、未超时。保留既有防护/锚点warning和退出时3个ObjectDB实例泄漏warning，不声称零warning。
- 七位独立Boss的459帧从可编辑绘图源码重新栅格化；标题9层建筑/齿轮重新绘制。50张机械道具同时交付1×与QHD原创几何版本，标题字标重新采样字体；其余645张为既有角色、场景、武器和UI素材的细化处理。保留28项低频光照/气氛蒙版或旧Boss兼容素材，不把派生细化说成从零重画。
- 篝火与标题炉口分别重画8帧火舌、燃料亮芯和固定火根，标题炉口开始播放动画；火星保留为独立粒子层。
- 图像审计：Boss459/459源码重现、跨Boss零完全重复帧；场景707/707尺寸、SHA256及环境底边检查通过，均区别于最近邻放大。GPU单物理像素采样五项全部通过。
- 首轮全量发现面板实心四角和机械底部3个空物理像素。绘图源码已修正，原有 `prop_fit` 7/7通过，检查标准未放宽；失败日志保留在 `screenshots/acceptance/qhd/full-tests-final/`。
- 最终显示矩阵9种尺寸×4夹具=36张，加9张标题；`screenshots/acceptance/display/report.json` 为 `passed=true`、无错误。修正后14章29张QHD机位图全部解码为2560×1440并审阅，索引 `screenshots/acceptance/qhd-chapters-verified/render-manifest.json`。固定机位与摆位只证明构图，不证明通关。
- QHD正常输入 `screenshots/acceptance/input-20261025-121524-769/rekindle.json` 通过，截图38张均为2560×1440；标题新游戏、第一章Boss、死亡/重载、Continue、进入第二章和地窟存档恢复均通过，辅助1.0/1.0/1.0，1次死亡、0引擎错误。这是首章到第二章的验收；此前完整14章输入证据仍是下节列出的1080p历史轮次。
- 最终QHD短时性能探针位于 `screenshots/acceptance/qhd/perf-verified/`：标题/第五章活动场景的离屏渲染回调间隔p95分别为2.910/2.801ms，不作为实体屏FPS或最坏战斗性能结论。

4K输出保留QHD世界细节密度上限；离屏截图与固定60Hz加速输入不证明实体显示器FPS或真人手感。源码按完整改动分次提交，证据留在本地ignored目录。

## 2026-10-25：v3最终整合验收

当前权威结果见 `docs/overhaul-v3.md` 最终门禁表与 `screenshots/acceptance/overhaul-v3/final-evidence-index.json`。下文按日期保留历史失败、局部夹具与旧范围；它们不覆盖本节的新结果。

本节证据路径除源码/文档外，均相对 `screenshots/acceptance/overhaul-v3/`。

- 无章节/用例过滤全量：**1462/1462、28740条断言、0引擎错误**。`full-final-window-contract/summary.json` 为 `passed=true`、`completed=true`，源码 `f7bcff7`，启动记录包含两份输入驱动SHA256。保留防护/锚点warning，以及退出时3个ObjectDB实例泄漏warning，不声称零warning。
- 同一源码从标题新游戏完成14章渲染输入：`../input-20261025-002258-602/rekindle.json`，校验归档 `input-final/rekindle-window-contract/`。`input_only/basic_abilities/rendered=true`、`resumed=false`；3次真实死亡、0引擎错误、138个里程碑、115张1080p PNG。七Boss实际击杀、梦魇三阶段、熔渣致死/复活/Continue后Boss缺席、最终出口/字幕与完成存档均通过。辅助0.5/1.5/0.5，机关等待645帧；模拟固定60Hz加速，不代表显示器帧率。
- 第一章熄灭分支为 `input-final/snuff/`：新游戏、基本能力、辅助均100%、1次真实死亡、0引擎错误；这是提前结局。
- 14章×5机位×2分辨率共140张构图、标题24+4张、系统UI8张均已审阅。固定/无敌角色与BossFixture只提供构图或战斗状态证据，不混入输入通关结论。
- 七位Boss独立设计并自行绘制459张透明像素帧，可编辑源稿随代码提交，459/459重绘一致、跨Boss零完全相同帧；见 `docs/original-bosses.md` 与原画板。
- 标题与14章入口15次性能探针，p95 3.349–5.001ms，保留钟楼1160.905ms停顿。源码差异审计 `render-runtime-compatibility.json` 证明后续只读查询与不影响当前章节的预警下限可沿用原构图/采样；未声称停顿已修复或Boss最坏场景达标。
- 音频14个机关文件+1条标题循环数值审计通过；不是主观听感验收。实体触屏、手柄实机手感、真人试玩、音频混音及实体显示器呈现/性能仍未验证。

复现：`./tools/run_tests.ps1 -TimeoutSeconds 2400 -ArtifactsDir <新目录>`；`./tools/run_input_acceptance.ps1 -Campaign -BasicAbilities -Fast -Rendered -Ending rekindle`。测试需清除 `RUSTGRAVE_LEVEL_FILTER`，使用隔离APPDATA。PNG/日志/哈希索引留在本地ignored目录，源代码与本节已提交，未推送或发布。历史逐章定向门禁没有满足“每阶段全量先通过”，此流程偏差保留，不追认。

## 2026-10-24：七位Boss独立原创美术

七位Boss现均读取各自的 `assets/characters/original_*` 素材，共459张透明像素PNG；不再以盾卫、幽魂或旧马匹帧充当Boss主体。设计与可编辑绘制源稿索引见 `docs/original-bosses.md`，权属说明见 `assets/external/CREDITS.md`。

- 刽子手：闭面葬甲、碑盾和裂斧；空钟：双链悬挂裂钟及独立钟舌。
- 绞盘守渠人：潜水压力甲、水平双绞筒与链锚；无声唱诗班：管风琴指挥及三种独立面具。
- 铸钟人：四层铸模重甲、背炉和分节锤；炉风先驱：长喙冠、分节钢翼和镜眼尾羽。
- 梦魇：窑骨骸马、外露炉心和名牌鬃，独立四足步态。

`tools/art/review_original_bosses.py --reproduce` 再次完成459/459帧源稿重绘与逐像素比较，二值透明度、跨Boss零完全相同帧。三份源稿以像素簇和关节绘图，无图片输入、描图或下载角色帧；帧数与哈希是交付完整性检查，不单独作为原创性证明。七套轮廓、装备及动作逐个审阅，实际战斗阶段/前摇/判定/收招/倒地选择对应帧，保留原故事与判定契约。

证据为 `screenshots/acceptance/overhaul-v3/original-bosses/{seven-original-bosses.png,original-assets-review.json}` 及该目录各Boss的渲染/战斗报告。画板按卡片独立放大，不表示游戏内体型；摆位和注入伤害的BossFixture只证明视觉与战斗状态，正常输入通关另列。

## 2026-10-24 v3 续作：Boss 连续终结击破势

- 独立 `codex/overhaul-v3-completion`，整合基线 `8b91f22`；原 OneDrive 工作区的未提交内容未混入。
- 全量 `tools/run_tests.ps1`：**1298/1298，0 engine errors**；
  `screenshots/acceptance/overhaul-v3/p1-poise/full-final/summary.json` 为 `passed=true`、`completed=true`。
- 专项 `boss_poise`：**6/6，111 条断言**，覆盖七个 Boss 的前摇/活动判定撤回、
  剑终结击累计、免疫与格挡、过期/冷却、冻结/重置、阶段及碰撞不变。
- `scenes/tools/BossPoiseAcceptance.tscn` 加载真实第一章竞技场，1280×720 渲染三张图，
  `screenshots/acceptance/overhaul-v3/p1-poise/render/report.json` 通过且无引擎错误；图像已查看。
  这是摆位并调用真实伤害路径的战斗夹具，不能证明正常输入通关或真人手感。
- 完整 14 章地形重建、输入通关与渲染矩阵继续按 `docs/overhaul-v3.md` 跟踪，未在此宣告完成。

### 战役输入工具：机关等待与辅助选项

- 第一章与后续章节共用只读 `tools/campaign_hazard_policy.gd`：周期机关等待覆盖完整宽度的安全窗口，
  已在判定区内则继续离开；区分楼层与目的地，摆锤预测后续 0.25 秒的锤头位置。
- 专项 `campaign_hazard_policy` **4/4、16 条断言、0 engine errors**，
  证据 `screenshots/acceptance/overhaul-v3/bot-policy/targeted-final/`。
- 战役工具使用公开设置：受伤 0.5、弹反 1.5、毒素 0.5；报告写入实际倍率与机关等待帧数。
  不更改角色位置、HP、敌人伤害结算、进度旗标或门状态。
- 第一轮真实输入冒烟暴露了辅助弹反前摇读取关闭 Area 的引擎错误；已修为仅查询弹丸，
  专项 `comfort_options` **7/7**、`integration_parry` **3/3**，均无引擎错误。
  实体 Hurtbox 验证前摇无提前剑伤，进入正常判定期才造成伤害。
  本节记录工具与缺陷验证，不宣称 14 章输入通关。
- 输入工具原先要求先精确走到活着的刽子手身后，导航与战斗抢夺方向而反复死亡；
  改为在竞技场近侧交接战斗。`input-20261024-170810-489/rekindle-stdout.log` 已记录第一章 Boss 击杀、
  死亡后进度保留、Continue、进入第二章与地窟存档点检查；本轮为仅基础能力、公开辅助选项的正常输入。
- 多层下落导航统一复用第一章驱动；图连边检查整个人体的台缘净空，不再把被低楼板挡住头部的下落算成可走路线。
  走下台缘时身体完全离开支撑面后再刹车。`bot-navigation/targeted-r3/` 的真实玩家物理夹具
  **3/3、15 条断言、0 engine errors**，验证窄柱下落、绕开头顶障碍、改走上层台后落回下层；
  这些是局部输入回归，完整战役仍待跑完。
- 32px 上升、36px 缺口的跳跃改用已开放的基础冲刺，不再套用同高跳跃的冲刺阈值；
  `bot-navigation/high-gap/` 的局部真实输入回归 **4/4、18 条断言、0 engine errors**，未解锁额外跳跃。
- 渲染工具也改为寻找真实固定台面，并检查整个人体净空；不再固定 y320。
  `peek-support/targeted-final/` **3/3、0 engine errors**；真实第四章 x1760 的渲染图
  `peek-support/render/live_1760_level04_lit_active.png` 已查看，骑士脚点为 (1640,288)，站在掩体台顶。
  仍是固定机位夹具，不提供输入可达性证据。PowerShell 包装恢复调用方 APPDATA，并拒绝引擎 ERROR。

## 2026-10-17 全面升级 · 阶段一（样板）验收

环境：Windows 10、Godot 4.7.1 stable、GL Compatibility、NVIDIA RTX 4060 Laptop。
世界视口 640×360，UI 1280×720 设计单位。所有测试与输入验收使用独立 `%TEMP%` 下的
APPDATA 与独立存档；玩家正式存档未参与。

### 基线

- 升级前工作区（含此前未提交的装备/UI/天气改动）先做基线提交并全量回归：
  **670/670 通过、0 engine errors**。
- 阶段一结束时的全量回归：**758/758 通过、0 engine errors**（含新增的
  `greatsword`、`boss_presentation`、`scene_details`、`level01_backdrop`、
  `prop_fit`、`audio_library`、`music` 等回归用例）。

### 阶段一样板：标题 → 开场 → 第一章 → 战斗 → Boss → 第二章

真实输入**渲染**验收（1920×1080 窗口 + `--fixed-fps 60` 加速；只发送移动/跳跃/冲刺/
攻击/交互/菜单输入，不传送、不改数值；独立 APPDATA 与存档），证据目录
`screenshots/acceptance/input-20261017-204413/`：

| 路线 | 结果 | 死亡 | 关键里程碑 | 引擎错误 |
|---|---|---|---|---|
| 复燃（rekindle） | PASS（`rendered=true`） | 1（主动验证死亡恢复） | new_game → 教学台 → 毒坑 → 喷吐者/钩锁 → 压板 → 窑核 → 融门 → 余烬核 → 东翼存档 → Boss 击杀 → 死亡重载 → 暂停回标题 → 继续 → 复燃 → 第二章落地 → 地下存档点 → 毒池 → 暂停/继续验证 | 0 |
| 熄灭（snuff） | PASS（`rendered=true`） | 1 | 同上直到炉心选择熄灭 → 提前结局 → 标题 | 0 |

- 同一份驱动先前只在 headless 下通过；渲染窗口里暴露出两个**验收脚本**问题并已修：
  标题在**有存档时默认把光标停在「继续」**（`title_screen.gd`），旧脚本固定按 ↓ 会落到
  「设置」；死亡重载后有一小段淡变，`PauseMenu` 在淡变期间只记下暂停请求，而脚本紧接着
  再按 Esc 会把这个请求收回。现在驱动等淡变结束后再发送真实输入，并带状态重试与诊断
  输出（`[PAUSE]` 行）。修复前可稳定复现 `[WALKTHROUGH FAIL] boss_death_reload`。
  **游戏行为未改**，只改验收驱动。

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

`tools/perf_probe.gd` + `scenes/tools/PerfProbe.tscn`：真实画布壳、四个机位、冻结 AI
与玩家物理（只量渲染/场景开销）、2 秒预热后采样 3 秒，记录
`Performance.TIME_PROCESS + TIME_PHYSICS_PROCESS`、绘制调用与节点数，JSON 存
`screenshots/peek/perf/`。同一位置的两次运行帧时间差异很大（8–55 ms），
说明这是隐藏窗口下受系统/GPU 调度影响的测量，**不能当作真机帧率**。可用的稳定结论：

| 关卡 | 窗口 | 节点数 | 绘制调用 | 帧时间（同机多次） |
|---|---|---:|---:|---|
| 第一章 level01 | 1280×720 | 2085–2094 | 213–328 | 8.6–33 ms，波动大 |
| 第一章 level01 | 1920×1080 | 2084–2093 | 212–328 | 9.2–26 ms，波动大 |
| 第八章 level08 | 1920×1080 | 2749–2767 | 184–236 | 26–56 ms，波动大 |

结论：节点数与绘制调用在四机位间稳定、没有随停留时间增长（FX/粒子/音频节点有预算
测试兜底）；离屏帧率不足以判断显示器性能。真机/实显示器性能仍未验证。

### 阶段二 2A 补丁：装饰"方块感"与悬空件（用户复查）

用户复查截图指出「意义不明的方块」与「贴地件悬空」。根因与修复：

1. **地形贴图当了装饰**：第一关 `PLAY_DECOR` 里种的是 `iron_slab_a.png`——它是
   `SolidPlatform` 的 48×48 铺地切块（平顶 + 断裂底边），单独立在墓地行里就是一块
   读不懂的方碑；同一类错误还有东翼的 `slab_a.png`。二者改为 `gh_rock_pile` /
   `rubble_c` 这类有轮廓的碎石；第一章锈块用例与东翼残石都重新落位。
2. **`slab` 装饰键全章切碎**：工坊/熔渣等章把同一张铺石板当装饰种了多份。生成器
   新增 `_fracture_slab()`，把 48×48 铺石板切成 3 块锯齿错位的碎块并压一条碎石带，
   7 个材质族变体全部重生成（幂等：连续两次运行输出一致）。现在它读作塌落的石堆。
3. **暗刻件悬空**：`gh_furnace`（炉膛/落地火盆）原图内容比画布底边高约 7px，且底部
   带着 11 行 tileset 底板；`gh_skull_arch` / `gh_rock_pile` 底边稀疏。生成器补
   像素柱脚/底座并把底板 flood-key 掉，第一关竞技场两座炉膛、东翼锻炉残件与
   工坊/熔渣/炉心的壁炉现在都真的踩在地面上（`prop_fit_test` 的 bottom-3-rows 断言锁住）。
4. **碑文石浮雕小数缩放**：`LoreStele` 以 28×36 显示 32×40 的裁片 = 0.875/0.9 缩放，
   像素边缘发糊；改为 1:1 32×40、1× 绘制。
5. **Boss 名号卡不居中**：`CinematicTableau._card()` 的 Boss 分支把中心放在 410/640
   （旧设计想给左上血槽让位），读起来像没对齐；改为与章节卡一致的中心 320，卡面
   110..530。战斗仍实时进行，卡片只占顶部 49–128 带，不压脚部/危险/预警。

回归：`prop_fit` 新增 3 条用例（地形贴图不得当装饰、slab 变体必须是碎片、碑石 1×），
全量 **762/762 通过、0 engine errors**。证据：`screenshots/peek/blockfix2/live_560_lit.png`
（第一章原方块处改为碎石堆）、`blockfix/live_1600_level05_lit.png`（切碎 slab）、
`lead-1d/boss_02-gate-intro.png`（居中名号卡 + 炉膛落地）。

### 阶段二 2A 补丁 2：毒池"雨滴感"与土层草影（用户复查）

用户复查又指出两处"特效/布景放错位置"：

1. **没下雨却有水面白点 + 落水效果是扩散的**（毒池截图）：
   - 白点不是雨，而是毒池每 0.4s 冒的"气泡"用了 Kenney `20_magicbubbles` 彩色粒子
     喷溅表，再缩到 0.06–0.1 倍——缩小后是一团乱码白点。改为 `Fx.ToxinBubble`：
     程序化整数像素泡（1–3px，只向上飘，坐标取整），颜色跟池面/雾气一致
     （第 4 章橙色冷却液也成立）；毒雾 `VAPOR_TINT` 也从灰白偏绿压暗，避免再被读成雨滴。
   - 落水反馈原来是 8 点径向扩散环（读作声呐/涟漪向外）。改为**上溅水花**（入水方向
     竖直、横向收束）+ 水面**横向**张开的 1px 亮线，寿命 0.22s；水花透明度随
     `rain_opacity()` 衰减，雨停后不再留下全亮溅落（探针：薄雾下 splash/ripple 计数 0，
     下雨 22/10，转薄雾 9s 后归零）。
   - 证据：`screenshots/peek/pool-fx/pool_haze.png`（隔离池的近景：绿色气泡+绿雾，
     无白点/无扩散环）；`screenshots/peek/weather-probe/`（薄雾/下雨/雨停三态）。
2. **土层下面有移动的植物**：墓园主题的前景草剪影（`Foreground` 贴图 ×1.22 /
   `ForegroundFringe` ×1.38）屏幕 y≈347–352，而横截面镜头的视口底边就是地面平台的
   土壤剖面；深色草影扫过亮土被读成"土里长的植物"。该功能**整段删除**：
   `theme_backdrop.gd` 不再创建墓园近景草板；`Level01_Static.tscn` 删除
   `ParallaxForeground/Foreground` 节点与 `30_fore` 资源；`level01_parallax.gd`
   删除 `FOREGROUND_PLATE`/`FRINGE_*` 常量、`_foreground`/`_fringe` 变量、
   `_add_foreground_fringe()` 与两条 drift（不留"隐藏的死层"）。
   `ParallaxForeground` 只保留贴地雾/雾幕，近景层次交给平台草皮顶与
   `NearSilhouette` 树丛。证据：`screenshots/peek/nograss/`（1440p 底部土壤带
   2.5× 提亮，level01 x≈800 与 level06 x≈960 均无草影），对照 `qa-fig3d/`（前）。

回归：`weather_fx` 新增 2 条（雨停水花不可见、上溅方向/短促水面反馈），
`toxin_bubbles` 新增 2 条（像素绘制不缩放贴图、只上浮且自毁），
全量 **766/766 通过、0 engine errors**。

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


## Campaign v2 验收（2026-10-18，feature/campaign-v2）

本轮把 10 章战役扩为 **14 章 / 四幕 / 7 场 Boss**，并重写故事文本、章间间幕、试炼模式与角色/武器接应层。提交：

- `5b5990c` feat(boss): shared boss framework, arena and acceptance fixture
- `57f9a38` feat(campaign-v2): 14-chapter campaign with story, bosses, trials and loadout bridge
- `44947a1` docs: campaign v2 story bible, integration contracts and acceptance plan

### 1. 自动化测试

- 全量：`--headless res://tests/run_tests.tscn` → **OK — 987/987 passed; 0 engine errors**（unique APPDATA，GL Compatibility）。
- 新增/重写过滤：chapter_text 20、story_flow 13、opening_cinematic 19、chapter_transition/interlude_overlay 2、save_migration 4、level_routing 6、chapter_progression 3、level02b 11、level04b 8、level07b 6、level09b 8、boss_framework 14、capstan_warden 9、silent_choir 9、hollow_bell 5、bell_founder 5、emberwind_herald 6、nightmare 10、executioner_finale 1、trial 35（catalog/records/mode/integration）、title/pause/hud/director、loadout_contract 6、loadout_route 2、chapter_art_audit 4。
- 所有过滤均要求 0 engine errors；`tests/chapter_text_test.gd` 内含 canon 回归门（残芯时间线唯一、锈核 vs 残芯、无"幕/债"元语言、伊尔"封核之前"标记、首现术语白话、钥匙落地、结局区分词、配机动因）。

### 2. 渲染证据（`screenshots/`，gitignored；路径为仓库相对）

| 内容 | 路径 |
| --- | --- |
| 视觉审计 Phase A：10 章 × 5 节拍 1280×720 | `screenshots/peek/campaign-v2/<chapter>/` |
| 视觉审计结论：Top 问题 + 逐章 FINDINGS + Phase B 队列 | `screenshots/peek/campaign-v2/TOP_ISSUES.md`、`PHASE_B_QUEUE.md` |
| level02b/04b P0 修前/修后 与对比拼图 | `screenshots/peek/campaign-v2/{level02b,level04b}-fixed/`、`before-after/compare_*.png` |
| 7 场 Boss 入场/各阶段/死亡/清场 + report.json | `screenshots/boss/<level>_<Boss>/` |
| 新章与扩章关键节拍（M2c 22 张） | `screenshots/peek/m2c-evidence/` |
| 14 章干净渲染（重拍用） | `screenshots/peek/qc-07b/`、`qc-09b/`、`level02b_fixed/`、`level04b_fixed/` |
| 试炼菜单/结算/HUD 9 张 | `screenshots/trial/` |
| 故事开场/间幕/章节卡/暂停前情 9 张 | `screenshots/acceptance/story/` |
| Boss 框架首轮 fixture 证据 | `screenshots/peek/m3-boss-framework/` |

Boss fixture 的 report.json 均 `kit_problems=[]`、Boss 前存档点 42–77px（契约 ≤80px）、死亡后 arena cleared；level09b 的 `checkpoint.ok=false` 是飞行 Boss fixture 把悬停 y 当地面造成的取景 artifact，真实布局门前巢距门 61.6px（`level09b_layout_test` 断言）。

### 3. 本轮已修的真实缺陷

- 间幕遮罩在 `Director.abort()/reset_view()` 后不消失（只连 `script_finished`，abort 只发 `finished`）→ 所有渲染被 0.82 scrim 压暗；执行器补连 `Director.finished`，`tests/interlude_overlay_test.gd` 锁定。
- 新 Boss 占位场景缺失/已交付两种状态下的 `ChapterLayout.boss()` 行为由测试双分支锁定；Boss 出口门禁只在场景存在时挂载（不软锁）。
- level02 空钟厅、level10 梦魇竞技场统一 `boss()` 装配；level10 门前存档点 220px→76px。
- level02b 荧光绿带（降饱和 + sludge_ramp + 岸线压边 + brick_float 桥石/吊台链条）；level04b 过暗（暖光池 + 暖雾 veil，0.10→0.16 亮度）；level08 渣河高饱和橙带（降饱和 + 压边）；level07 井底与 level10 竞技场补光。
- 刽子手二阶段"炉膛终局"（≤20% HP，不改变 2 阶段 Kit/HUD 断言）；梦魇三期（余烬雨/地裂/热浪 + 两侧收窄 96px）。
- 音频：新增 5 轨 Boss×2 层，`BOSS_TRACKS_BY_LEVEL` 按关卡优先解析；全部 40s、bed −19.5 LUFS / hi −23.1 LUFS、峰值 ≤−3.3 dBFS、循环接缝 r_p999<1。
- 接应：`LoadoutBridge` 测试注入 + 正向契约、14 章 × 4 能力集可达性矩阵、`tools/loadout_merge_check.gd` 合并门（当前项目 PASS 21 / WARN 5 / FAIL 0）。

### 4. 故事盲测（独立 reviewer，只读玩家可见文本）

同一份 6 题问卷跑了 5 轮（每轮换独立 reviewer，避免前一轮记忆污染），评分变化：
**2/5 → 2/5 → 3/5 → 3/5 → 2/5**（第 5 轮 reviewer 更严格；不同 reviewer 对"术语表是否算首现解释"的判定不同，故 3/5 与 2/5 之间有评分方差）。
- 稳定通过的项：A（身份/目标/动机/代价）、B（剑里是伊尔/问火/残芯在背上剑里）、10 章后的主线复述；
- 未过项：C（专名首现解释不齐：炉约首次无誓的内容、残芯的两个来源没合并、炉座/剑槽等承重词不在术语表）、
  D（第 4/8/10/12/14 章"为什么去下一章"仍靠出口字幕报下个地名；第 8 章目标字面做不到；同一扇"炉心门"连报三章）、
  E（守火"名字还困着"未在选择前说清；"城睡下/半醒"未定义）、F（仍有需长猜的句子）。

M1R5（补丁轮，已落地）：术语表 8→**17**（补炉座/剑槽/守灯/上城/送剑/守火并合并残芯来源）、开场 16→**17 拍**（炉约的誓内容与守炉人拆成两拍、首现即解释）、ch8/ch10/ch12 目标改为可执行的事、ch14 明确"先在门外问火→门开→进去再选"、守火代价补"名字还困着"、城墙出口改"城墙外"（炉心门只留崖道/终章）；canon 测试与 `docs/story.md`（术语表/锚点表/间幕表由 registry 生成）全部同步。
M1R4 已按上一轮 5 条改过：开场补动机/代价、第一章炉座只认点过的核 + 圣殿另点守灯、钟舌线挂回主目标并拆重复目标、
结局补名字下场与守火代价、术语清理（封进核之前/剑槽/炉心门/当年守炉人）。**故事线在此冻结**：剩余 C/D/E/F 是
下一轮文本迭代的明确清单（详见评审原文；不要回退已通过的 canon 门），不在本轮继续循环。

### 5. 未验证 / 已知限制

- 真实输入冒烟（`tools/input_walkthrough`，正常输入驱动）：`--ending=rekindle` → **WALKTHROUGH PASS**（level01 东翼存档点 → 刽子手战 → 故意死亡/读档验证 → Continue → 下到 level02 → 地窖存档点/毒坑 → 暂停/继续；1 deaths，0 engine errors）。这只覆盖第 1–2 章，不等于 14 章通关。
- 输入通关工具的 bug 已修：`tools/campaign_walkthrough.gd` 调用了父类不存在的 `_pause_to_title()`，脚本一直解析失败（此前"跑 >20 分钟无输出"的根因）。改用 `_pause_return_to_title()` 后工具可运行，并补上"Boss 门禁出口要先真打 Boss"的步骤（`_clear_gate_boss`，含出招时拉开/收招贴身、死亡回巢重试的正常输入策略）。
- 工具现在能跑完 level01→level02 全流程（含刽子手战、死亡读档、Continue、下地窟、压板/毒坑），在 level02 空钟门前会**识别门禁并进入 Boss 战**；但输入机器人打不过空钟（玩家 7 血 vs Boss 18 血，无弹反/走位技巧），因此 **14 章全程通关仍未被机器人证明**。该门禁链改由测试覆盖：`hollow_bell_test`（死亡写旗标+清场）、`level02_layout_test`（条件门禁）、`chapter_progression_test`（击杀后推门→进入 level02b 并保存到达点）。
- 真实输入 14 章通关：**未完成**。`scenes/tools/CampaignWalkthrough.tscn` 在本机 headless 跑 >20 分钟无输出（疑似等待游戏输入/标题流程），已中止；真实手柄/键盘人工通关也未做。因此"14 章可从头玩到尾"本轮**没有**正常输入证据，只有逐章 fixture/布局/路由/存储测试与各章渲染证据；这是本轮最大的未验证项。
- 真机触控/刘海、960×540 与 1920×1080 的试炼菜单实拍（只验证布局数学与控件边界）；真机 Boss 战 HUD 未录。
- Boss视觉（历史状态，已于2026-10-24取代）：当时CapstanWarden复用gear_shield、SilentChoir复用ghost，属于占位美术。当前七位均为独立原创像素帧，见本页“七位Boss独立原创美术”及 `docs/original-bosses.md`；不再将该历史描述用于当前版本。
- 视觉审计 Phase B/C（扩章后重拍、Boss 房逐场构图）未全量完成：Phase A 已修 P0；02b/04b 有 before/after；其余扩章段与 7 场 Boss 房列入 `PHASE_B_QUEUE.md` / Phase C，待后续。
- 外部角色/武器线未合并：契约 §3 + `LoadoutBridge`（feature-detect）+ 奖励位 + 可达性矩阵 + `LoadoutMergeCheck` 已就绪；合并时按契约 SMOKE 1–7 跑门禁。
- `docs/` 与源码在同一分支；`screenshots/` 全量 gitignore（证据只在本地，路径如上）。

### 2026-10-24：熔渣回巢升降台下落

连续新游戏Basic战役 `input-20261024-215829-600` 在level08高台与ReturnLift的交接处失败，保留该轮失败报告。导航原先只对固定台执行“走出整个人体再刹车”的重叠下落规则；升降台被遗漏后，角色会原地跳跃。现将规则用于真实运动升降台，并读取它的当前高度。`overhaul-v3/return-lift-fix/tests/` 17/17、0引擎错误，新增用例使用实际宽度/位置/8秒运动周期，正常方向输入落到低层地面，不冻结平台或改角色坐标。完整战役必须重新运行。

### 2026-10-24：终章Continue与最终出口

渲染连续新游戏 `input-20261024-220815-789` 完成14章到达、梦魇三阶段与击杀、真实熔渣死亡和Continue后，验收脚本误读旧场景的出口引用而失败。现于Continue后重取真实出口；合法已击杀存档恢复不重复执行死亡验证。导航拒绝把会先落到中间楼梯上的下落直接连到远处低层地面。最终东阶中层宽64→32，给从320地面向288台阶起跳留出净空，保留上层回路。

`overhaul-v3/finale-continue-fix/tests-final/` 19/19、0引擎错误；正常移动用例覆盖实际STEPS的东阶净空和中间落脚面。`input-20261024-222018-301/rekindle.json` 为已击杀合法存档恢复的渲染验证，最终出口、结局字幕与campaign_complete均通过，0引擎错误；该轮不是新游戏全程证据。

### 2026-10-24：14章新游戏完整渲染输入通过

`./tools/run_input_acceptance.ps1 -Campaign -BasicAbilities -Fast -Rendered -Ending rekindle` 通过，证据 `screenshots/acceptance/input-20261024-222123-500/rekindle.json`。从标题新游戏开始，`resumed=false`，不拼接恢复局；`input_only=true`、`basic_abilities=true`、`rendered=true`，2次真实死亡、0引擎错误。第一章后依次记录其余13章入口、七Boss真实击杀、梦魇三阶段、熔渣死亡恢复、标题Continue后Boss缺席、最终出口/字幕和持久化game_complete。

主线仅单跳/冲刺/热锻，无钩锁或额外跳跃；公开辅助为受伤0.5、弹反1.5、毒素0.5，按真实机关安全窗口等候665帧。只读路线/敌人状态并发正常输入，不写角色位置、血量、敌人伤害、门或进度旗标。115张PNG全部解码、尺寸确认为1920×1080，哈希和章节入口索引在同目录 `render-manifest.json`。加速固定60Hz模拟和离屏窗口不证明实体性能或真人手感。该历史轮次后的全量曾在 `full-authoritative-final/` 失败；现以本页2026-10-25最终整合节的 `full-final-window-contract/` 为准。
