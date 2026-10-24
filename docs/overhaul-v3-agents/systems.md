# Agent: systems — 系统升级（P7，不含标题屏）

worktree `C:\dev\rg-systems`，分支 `feature/overhaul-v3-systems`。先读 `docs/overhaul-v3-brief.md`。
标题屏与关卡不归你（别的 agent 在改 `scripts/ui/title_screen.gd`、`scripts/levels/**`）；你的改动集中在设置 / 输入 / HUD / 暂停 /
音频 / 性能。优先级从上到下，做不完的在汇报里写清楚。

## 1. 手柄（最高优先）

现状：`project.godot [input]` 只有键盘 / 鼠标事件（move_left/right、jump、dash、attack、interact、hookshot、socket 等，自行核对完整列表）；
手柄按键只在 `settings_screen.gd` / `trial_menu.gd` 里用于 UI 标签页肩键。
- 给全部玩法动作加摇杆 / 十字键 / 按键映射（左摇杆与十字键移动；A 跳、X 斩、B 或 RB 冲刺、Y 交互、LB 钩锁、
  RT / LT 或十字键上下做插座 1/2；Start 暂停）；`Input.get_axis("move_left","move_right")` 要有死区。
- 设置页的改键（`settings_screen.gd` 约 L676+ 的捕获逻辑，目前只认键盘）扩到手柄按键 / 摇杆方向，存进 `Settings`。
- `scripts/ui/key_labels.gd`：按"最近一次输入设备"切换提示图标（键盘键名 ↔ 手柄按键名），教学提示 `{attack}` 等占位随之变化；
  触屏会话行为不变。
- 测试：扩展 `tests/settings_test.gd`、新增 `tests/gamepad_input_test.gd`（InputMap 里每个玩法动作都有手柄事件、改键往返、标签切换）。

## 2. 辅助选项（设置页新增一组）

受伤倍率（×1 / ×0.5 / 免伤）、弹反窗口（×1 / ×1.5）、毒素累积速度（×1 / ×0.5）、字幕速度、UI 文本缩放（至少 100% / 125% / 150%，
不破版：`PresentationMetrics` 内容矩形不变，改主题字号或容器缩放）。接到 `Settings` → `CombatRules` 的**乘数**（默认值 = 现有平衡，
`tests/combat_rules_test.gd` 与文档镜像表不能漂；乘数在使用处读取，不改表里的常量）。战役 bot 将来用"免伤"通过 Boss 门，
所以免伤必须是可靠的公开选项（`Health.take_damage` 前处理），并在设置页注明"辅助"。
- 测试：`tests/assist_options_test.gd`（默认不改变伤害 / 窗口、各档数值、持久化往返）。

## 3. 显示设置

`scripts/ui/display_fit.gd` 的预设已存在但设置页没暴露：加分辨率 / 窗口模式、垂直同步、缩放策略（整数缩放始终保持）。
测试 `tests/display_fit_test.gd` 扩展。

## 4. 地图热键 + 复活 QoL

- 新增 `map` 动作（键盘 M、手柄 Select/Back），HUD 里按下直接开 `MapScreen`（现在只有暂停 → 地图）；关闭后恢复游戏；
  `tests/pause_menu_test.gd`、`modal_screens_test.gd` 同步。
- 死亡后的固定 1.15s 等待（`scripts/player/player.gd` `_on_died`）改为 0.4s 后可按任意玩法键跳过；重生时 HUD 播一行
  "余烬巢已复位 · 毒素清空"。不能破坏 `progression_e2e_test` / `chapter_progression_test` 的死亡重载流程。

## 5. 机关音效与标题环境声（音频资产）

沿用 `tools/gen_audio_sfx.py` / `gen_audio_dsp.py` 管线与 `tools/gen_audio_verify.py` 门禁（0 缺失 / 0 削波 / 接缝指标）：
- 机关音效键（`scripts/hazards/hazard_fx.gd` 的 `SFX` 表已按"新键 → 老键退回"写好，**只要把新键加进 `Sfx.LIBRARY` 就生效**）：
  `hazard_steam_warn/hazard_steam`、`hazard_flame_warn/hazard_flame`、`hazard_slag_warn/hazard_slag`、`hazard_bell_warn/hazard_bell`、
  `hazard_shock_warn/hazard_shock`、`hazard_collapse_warn/hazard_collapse`、`hazard_pendulum`；再加风阵 / 涌流预兆音
  `hazard_wind_warn`（`ForceZone` 之后接）。给 `Sfx` 的 `TRIM_DB` / `VOICE_RULES` / 优先级补条目，音量关系对齐现有 SFX（见 `docs/acceptance.md` 的音量表）。
- 标题炉厅环境床 `bed_title`（齿轮吱嘎、远处蒸汽、链条低语，可循环、接缝过 `gen_audio_verify`），按 `bed_*` 环境床的方式登记；
  标题 agent 只做 `Sfx.LIBRARY.has(&"bed_title")` 特性探测，你负责资产与登记。
- 测试：`tests/audio_library_test.gd`、`asset_integrity_test.gd`、`music_test.gd` 保持绿。

## 6. 回看余烬总结页（独立模态）

新增 `scripts/ui/recap_screen.gd`（风格对齐 `trial_results.gd` / `ui_modal.gd`）：显示结局（`ChapterText.ending_summary_of`）、
已通关章数 / 14、回火试炼记录条数、余烬竞技场最佳分；底部「回火试炼」（若已解锁）与「关闭」。提供
`RecapScreen.open_in(parent)` 之类入口。**不要改标题屏**——标题 agent 在重做它，合并后由主 agent 把"回 看 余 烬"接过来。
测试：`tests/recap_screen_test.gd`。

## 7. 性能预算测试

`CombatRules.BUDGET` 加 `&"hazards"`（每关机关节点上限，比如 24）与"灯光"相关预算（若已有则对齐）；
`tests/hazard_budget_test.gd`：遍历 `GameContext.LEVELS` 逐关搭建（可参考 `tests/level_sanity_test.gd` 的建关方式），
断言机关 / 灯 / 节点数不超预算，并且连续 `tick` 600 帧节点数不增长。把 `tools/frame_cost_probe.gd` 的使用方法写进 `docs/acceptance.md` 之外的
你自己的说明 `docs/systems-v3.md`（别动共享文档）。

## 交付

各项各自提交；`settings`、`gamepad_input`、`assist_options`、`display_fit`、`pause_menu`、`modal_screens`、`hud`、`combat_rules`、
`audio_library`、`asset_integrity`、`music`、`recap_screen`、`hazard_budget`、`player`（死亡流程相关）过滤用例全绿；`docs/systems-v3.md` 记录
各项做法、默认值、手柄映射表、哪些没做。不能验证的（手柄实机手感）如实写。
