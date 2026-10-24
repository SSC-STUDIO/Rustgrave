# v3 改造：并行工作通用说明（给在独立 worktree 里干活的 agent）

> 总清单与验收记录在 `docs/overhaul-v3.md`；这里只写"怎么干活"。本文件随 `feature/overhaul-v3` 分支分发，
> 每个并行 agent 在自己的 worktree + 分支里工作，最后由主 agent 合并。

## 1. 环境与命令（Windows / PowerShell）

- 项目：Godot 4.7.1 + GDScript，世界视口 640×360，UI 设计层 1280×720。Godot 路径
  `C:\Program Files\Godot\Godot_v4.7.1-stable_win64_console.exe`（`Godot_v4.7.1-stable_win64.exe` 为窗口版）。
- **先在你的 worktree 根目录导入一次**（新建 `.godot` 缓存，也会登记新的 `class_name`；新增/改名脚本后要再跑一次）：
  `& "C:\Program Files\Godot\Godot_v4.7.1-stable_win64_console.exe" --headless --path . --import`
- 跑测试（只在你的 worktree 里；用 `-CaseFilter` 做路径子串过滤，**不要频繁跑全量**，全量约 5–6 分钟）：
  `$art = Join-Path (Get-Location).Path 'screenshots/acceptance/overhaul-v3/<你的名字>/tests'; & ./tools/run_tests.ps1 -CaseFilter level05 -TimeoutSeconds 240 -ArtifactsDir $art`
  **`-ArtifactsDir` 必须传绝对路径**（相对路径会按进程启动目录而不是你的 worktree 解析）。
  结果看 `$art/stdout.log` 里的 `[PASS]/[FAIL]` 行与最后的 `OK — N/N passed; 0 engine errors`；
  只想看结论可以：`Get-Content "$art/stdout.log" | Select-String '^\[FAIL\]|^     - |^(OK|FAILED) '`。
  测试会泄漏导演过场锁等全局状态（单跑通过、全量失败的典型原因）：依赖 `Director` 的用例在 `setup()` 里 `Director._set_lock(false)`。
- 单关几何体检：`$env:RUSTGRAVE_LEVEL_FILTER='level05'; & ./tools/run_tests.ps1 -CaseFilter level_sanity -TimeoutSeconds 240 -ArtifactsDir $art`
- 渲染看图（窗口模式，机位停放，不是通关）：
  `& ./tools/run_peek_live.ps1 -Level level05 -OutDir screenshots/acceptance/overhaul-v3/<你的名字>/level05 -Spots 320,960,1600,2240 -Hold 2 -Lit -Active -Win 1280x720`
  （`-Spots` 是镜头中心 x，一屏 640 宽；竖向关加 `-CamY`；用 Read 工具逐张打开 PNG 看：悬空、埋地、遮挡、空荡、颜色打架。）
- 机关外观检查：`scenes/tools/HazardProbe.tscn`（见 `tools/hazard_probe.gd`，窗口模式运行）。
- PowerShell 5.1 对中文很不友好：改含中文的文件请用编辑工具，不要用 `Set-Content`/`Out-File`。`.tscn` 里不能写 `#` 注释。
- git 的 CRLF 警告会走 stderr，PowerShell 会显示成 NativeCommandError，可忽略；命令后面加 `2>$null` 能压掉。

## 2. 必读

1. `docs/level_authoring.md`（硬规则 §3、软规则 §4、贴图规则 §7、**机关工具箱 §8**）。
2. `scripts/levels/chapter_layout.gd`（全部铺设助手，含 `cyclic/collapsing/force_zone/conveyor/pendulum`）与你负责章节的现有
   layout 脚本、`tests/levelNN_layout_test.gd`。
3. `docs/story.md` §5–§6、§11（章节目标、阻碍、Boss、发现、去向；**故事线已冻结，不改文本与章节顺序**）。
4. `scripts/hazards/*.gd`（五个机关基类；参数、`safe_window()`、规则都在文件头注释里）。

## 3. 改造原则（每章都要做到）

- **打破 y=320 单线**：至少两个明显不同的高度层或一段竖向 / 下探；不再用"毒坑 + 3 块踏石"作为默认过渡，
  用本章的专属机关做过渡。
- **三处场景化遭遇**（伏击 / 走廊 / 带地形的小竞技场），不要把敌人均匀撒在长廊上；可用敌人变体
  （`enemy(..., {"variant": &"armored_scrapper"})`，见 `scripts/data/enemy_variants.gd`）、`alert_radius`、`lose_range`。
- **至少一条单向捷径**回到前一个余烬巢（吊台 / 压板门 / 单向落下），死亡回程不超过约 1000px。
- **一个带奖励的可选挑战**（`reward(host, name, feet, "equipment", ref, label)`；奖励位脚下要有实心台面）。
- **余烬巢间距约 1000px**，Boss 前必有一个且离 Boss 门 ≤80px；巢位要在附近敌人 aggro/wake 范围之外。
- **Boss 竞技场有地形与机关**（抬高台、掩体、侧龛、可破坏物、本章机关），不是 600px 平地；
  不改 Boss 本身的受击盒、尺寸、攻击表与相数（`tests/*_boss_test.gd` 锁着）。
- 每章 1–2 个**专属机关**（见各自简报），首遇有提示（机关助手默认自带 `HintArea`），首个机关放在安全处教学。
- 主线只需单跳 / 冲刺 / 热锻；钩锁与余烬步（二段跳）只能出现在**可选**支路。`LevelSanity.is_reachable(..., allow_hook=false)` 必须走通。
- 保持稳定：`level_id()`、`theme()`、章节出口的 `flag_id` / `requires_flag` / 下一章 id、Boss 的节点名与死亡旗标、
  `entry_spawn()`（改了也行，但要让 `ChapterLayout.entry_spawn_of(id)` 读到新值——上一章出口自动跟随；
  `tests/chapter_progression_test.gd` 校验到达点）。**持久化节点**（余烬巢、压板门、锈门、碑）尽量沿用原名；
  新增节点用新名；旧存档里指向不存在节点的记录会被安全忽略，坐标不安全会由 `SpawnSafety` 退回巢。
- 文本：**不新增故事文本**。复用 `ChapterText` 里已有的碑文与字幕；新增的可选房间只用 2 字路牌（`waymark`）
  和装饰。必须写字时，用关卡里的局部常量、≤2 句、风格对齐 `docs/story.md`，不要改 `scripts/data/chapter_text.gd`
  （它有 canon 回归门）。
- 美术：只用现有素材与 `PropCatalog` 主题白名单（`prop_fit_test` / `chapter_art_audit_test` 会检查）；
  装饰脚点钉台面、整数缩放、不种地形切块。

## 4. 验收门（你的章节必须全部通过再提交）

1. 你的 `tests/levelNN_layout_test.gd`（更新成新几何，保留"巢/压板/出口/奖励可达、脚下有台、敌人落点"这些精神）全绿。
2. `level_sanity`（带你的 `RUSTGRAVE_LEVEL_FILTER`）无问题；`route_audit`、`chapter_progression`、`level_routing`、
   `level_weather`、`chapter_art_audit`、`prop_fit`、`chapter_support`、`parallax_backdrop` 过滤跑一遍全绿。
3. 新机关首遇安全：第一处机关前后各有 ≥48px 的无判定落脚区；预警 ≥0.5s；`LevelSanity` 的机关检查通过。
4. 看图：每章至少 5 个机位 ×（1280×720）逐张看过并修掉明显问题；Boss 场另拍竞技场全景。截图放
   `screenshots/acceptance/overhaul-v3/<你的名字>/`（`screenshots/` 被 gitignore，只在本地）。
5. 写一份 `docs/level-redesign/<levelNN>.md` 蓝图（结构图、区段表 x 范围、机关、遭遇、巢与捷径、奖励、Boss 场、测试清单）。
   不要改共享文档 `docs/overhaul-v3.md` / `docs/level_authoring.md`（主 agent 统一汇总）。

## 5. 提交与汇报

- 在你自己的分支上**小步提交**（`feat(levelNN): ...` / `test(levelNN): ...`），只暂存你负责的文件；不要改别的章节、
  不要改共享脚本（`chapter_layout.gd`、`level_sanity.gd`、`scripts/hazards/*`）——如果确实需要改，只做**向后兼容的最小增补**，
  并在汇报里明确列出。
- 全量测试最多在收尾时跑一次；平时只跑过滤用例。
- 最终汇报（≤800 字）：改了什么（章节形状 / 机关 / 遭遇 / 巢与捷径 / 奖励 / Boss 场）、通过的测试命令与计数、截图目录、
  未解决项与建议、分支名与最后一次提交号、对共享文件的任何改动。
