# 交接说明 · `title-3d-forward-plus` 分支

> 状态：**未完成，可接力**。最后提交 `fccda86c`（本文件单独一个提交）。
> 基线：`master` @ `b376668e`。分支包含 4 个提交（见文末）。
> 作者上下文已丢失，接手前请先读本文件 + `docs/arena-mode.md` + `docs/moba-3d-plan.md` + `docs/title-3d.md`。

## 1. 这个分支做了什么

1. **渲染器全项目切 Forward+**（`gl_compatibility` → `forward_plus`，桌面与 mobile 两处都改）。
   - 2D 画面做过 A/B 对照：平均差约 0.6/255，无可见变化；3D 竞技场在 Forward+ 下渲染正常。
   - 相关：`project.godot`、`reports/renderer-switch-forward-plus.md`。
2. **3D 标题屏实验（已回退，不再接入）**：曾经做过一整座实时 3D 锻造大厅（程序化几何、纹素吸附相机、运镜、体积雾/SSAO/SSR、Blender 导出的 `forge_hall.glb`），后来用户要求改回原版 2D。
   - 现在标题屏 = **原版 2D 像素活景**（`TitleWorld`），只改了右侧信息列的版式平衡。
   - 3D 代码**保留但未实例化**：`scripts/title3d/`、`scenes/title3d/`、`assets/title3d/`、`tools/blender/build_forge_hall.py`、`tools/title3d_probe.gd`、`tests/title3d_*`。想继续 3D 方向可以直接捡起来；不想要可整体删除（不影响运行）。
3. **标题屏版式平衡（在用）**：右列与左下菜单同顶（y=254）、块高 ~396、宽 328、右边距 72；右列 = 旅程短注（计数/章名/14 格横轨）+ 五行档案摘要（阶位/外观/试炼/竞技场/印记）+ 行程注 + 底部「回看余烬」；墓志移到两列之间居中（446..850）。
   - 相关：`scripts/ui/title_screen.gd`、`tests/title_screen_test.gd`。
4. **3D 竞技场可玩化（本分支重点，已能打完整一局）**
   - 入口链不变：标题「余烬竞技场」→ `ArenaRun.start()` → `MobaRun` → `scenes/moba/RenderSpike.tscn`。
   - **确定性模拟核心** `scripts/moba/sim/moba_sim.gd`：30Hz 固定步进、整数毫米、种子 LCG、命令 API（`set_move` / `command_attack`）、逐 tick `state_hash()`（FNV-1a，可回放）。单路 1v1：双方塔（∓16）与水晶（∓26）、每 20s 各 3 兵、玩家英雄（600HP/55 伤/0.6s/2.2m/4.5m/s、死亡 6s 复活）、**红方确定性 AI 英雄**（等首波后带线推进，目标优先：小兵 > 英雄 > 塔 > 水晶）、水晶被拆即定胜负并冻结。
   - **表现层** `scripts/moba/present/`：`moba_view_map`（lane↔world/朝向/结构坐标）、`moba_unit_pool`（小兵对象池，稳态不 new）、`moba_minion_view`、`moba_unit_fx`（受击闪白/死亡淡出/红方 tint）、`moba_impact_pool`、`moba_structure_view`（塔/水晶 3D、悬浮 HP、倒塌/碎落）、`moba_hud`（双方水晶血条、波次倒计时、英雄 HP/复活、敌方英雄条、结果条 + 「R 重开 · Esc 返回」）。
   - `render_spike.gd` 重写为 sim 驱动：固定 30Hz 累积 `sim.step()`、输入→命令、按 hp 差值播特效；保留全部旧调试/渲染选项（0-9 渲染开关、F3、P 截图、M 压测、触屏、手柄返回）。
   - 实测：**约 54.6s 可赢**（纯公开命令推红水晶）；**完全挂机约 62.1s 被 AI 推平**（能输也能赢）。胜负窗口仅约 7.5s，偏窄（见 §3）。
   - 测试：`tests/moba_sim_*_test.gd`（21 例）+ `tests/moba_view_*_test.gd`（32 例）+ 旧 `moba_input/mode`（13 例）= **66/66 绿**（提交时）。

## 2. 怎么跑

```powershell
# 仓库根目录：C:\Users\Administrator\OneDrive\Documents\My-Program\Rustgrave
# Godot console: C:\Program Files\Godot\Godot_v4.7.1-stable_win64_console.exe

# 全量测试（约 10~20 分钟，跑前先拿锁，见 §4）
powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1
# 常用过滤
powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1 -CaseFilter moba
powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1 -CaseFilter title
powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1 -CaseFilter pixel_stage_scale

# 竞技场：自动跑完一局并抓 3 张图（窗口，结束自动退出）
& 'C:\Program Files\Godot\Godot_v4.7.1-stable_win64_console.exe' --path . --windowed --position -12000,-12000 --resolution 1280x720 res://scenes/moba/RenderSpike.tscn -- --auto --speed=2 --auto-shots=open:2,mid:25.7,end --quit-after-shot --shot-dir=<repo>/screenshots/peek/moba3d

# 标题抓图
powershell -ExecutionPolicy Bypass -File tools\run_title_peek.ps1 -Variants act2 -Sizes 1280x720 -Shots idle -OutDir screenshots\peek\title
```

现有验收截图：`screenshots/peek/moba3d/`（开局/中局/结算）、`screenshots/acceptance/title2d/balanced5/`（标题版式）。

## 3. 未完成清单（建议接手顺序）

1. **P3 技能/大招 + 战斗手感**：目前只有普攻；缺技能栏、冷却、受击硬直、目标锁定指示、伤害数字。
2. **AI 更聪明，拉开胜负窗口**：现在双方镜像，玩家 54.6s 赢 / 挂机 62.1s 输，窗口 ~7.5s。建议给红 AI 加回防/换线/撤退逻辑（不改数值），把窗口拉到 30s+。
3. **P4 经济与商店**：金币（补刀/击杀/推塔）、装备栏、锈核；商店入口与暂停语义。
4. **P5 完整地图与 5v5**：三路 + 野区 + 另一座塔/水晶；`spike_map.gd` 目前是单路；sim 需要多路寻路（当前是单轴推进）。
5. **P6 UI**：小地图、技能盘（触屏）、结算页（KDA/时长/重开）、暂停菜单。
6. **P7 美术/音效**：英雄/小兵/塔的正式模型或更丰富程序化造型、技能特效、打击音、BGM 切换。
7. **标题屏（可选）**：2D 版式已平衡；若想回到 3D，`scripts/title3d/` 与 Blender 管线都在，但需要重新接入 `title_screen.gd` 并把 2D 测试迁移。

## 4. 已知陷阱 / 必读约定

- **Godot 锁**：跑任何 Godot（headless 或窗口）前拿 `%TEMP%\rustgrave_godot.lock`，`finally` 删除；写法见 `tools/run_story_shots.ps1:15–26`。同一时刻只跑一个**窗口** Godot；headless 测试并发风险高（资源缓存/导入竞态），尽量串行。
- **中文编码**：仓库注释大量中文。Windows PowerShell 5.1 的 `Get-Content`/`Set-Content` 默认 ANSI，会把中文写坏；务必 `-Encoding UTF8`，或优先用编辑器的 read/edit 工具。被写坏的文件用 `git checkout -- <file>` 还原。
- **全量测试里存在 pre-existing 失败**（与本分支无关，在 pristine `master` 上同样失败）：主要集中在关卡布局、过场安全、parallax、物理控制、可破坏物摆放等；`docs/title-3d.md §12` 有记录与复现方法（pristine worktree + 共享 `.godot` junction）。判断"是不是本分支弄坏的"请先跑基线。
- **慢机器/并发时** `tests/enemy_variants_test.gd` 的 heavy guard 用例可能触发 180s 超时；单独跑应通过。
- **OneDrive 目录**下窗口截图偶发进程卡住：清空目标目录重跑，或先写 `%TEMP%` 再拷回。
- 换渲染器/新增 `class_name` 后如果报资源缺失，跑一次 `godot --headless --path . --import` 重建 `.godot/`（`.godot` 是 gitignored，不进仓库）。
- `RenderSpike` 在找不到 `MobaSim` 时不会崩（HUD 显示"等待模拟核心"），方便并行改动 sim。
- `spike_map.gd` 已移除内置静态塔/水晶几何（改由 `present/moba_structure_view.gd` 按 sim 坐标生成），若其他分支依赖 `map.crystals` 等成员需同步。

## 5. 关键文件地图

| 区域 | 文件 |
|---|---|
| 模拟核心 | `scripts/moba/sim/moba_sim.gd`、`tests/moba_sim_{core,rules,ai}_test.gd` |
| 竞技场表现层 | `scripts/moba/present/*.gd`（7 个模块）、`scripts/moba/spike/render_spike.gd`、`scripts/moba/spike/spike_map.gd` |
| 竞技场测试 | `tests/moba_view_{map,hud,pool,structure,match}_test.gd` |
| 标题屏（2D，在用） | `scripts/ui/title_screen.gd`、`scripts/ui/title_world.gd`、`tests/title_screen_test.gd` |
| 3D 标题实验（未接入） | `scripts/title3d/**`、`assets/title3d/forge_hall.glb`、`tools/blender/build_forge_hall.py`、`tools/title3d_probe.gd` |
| 像素管线 | `scripts/moba/view/pixel_stage.gd`、`assets/shaders/moba/pixel_post.gdshader`（支持 render_scale 超采样/暗角/颗粒/热浪/tint；arena 走默认 render_scale=1） |
| 文档 | `docs/arena-mode.md`、`docs/moba-3d-plan.md`、`docs/title-3d.md`、`docs/renderer*`/`reports/renderer-switch-forward-plus.md` |
| 工具 | `tools/run_tests.ps1`、`tools/run_title_peek.ps1`、`tools/run_frame_cost_probe.ps1`、`tools/title_peek.gd` |

## 6. 分支提交历史

| 提交 | 说明 |
|---|---|
| `403ba417` | 全项目 Forward+ + 3D 标题屏（后被回退） |
| `f319a766` | 3D 标题对齐 2D 参考构图（后随 3D 一起回退） |
| `fd856dbe` | 标题屏回退到 2D 活景 + 左右列版式平衡 |
| `fccda86c` | 3D 竞技场可玩化：确定性模拟核心 + sim 驱动表现 + HUD/胜负/重开 |
| `<this commit>` | 交接说明（本文件） |

**工作区在交接时是干净的**；除本文件外没有未提交改动。
