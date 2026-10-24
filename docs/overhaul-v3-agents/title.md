# Agent: title — 标题活景 + 版式与动效重做（P2）

worktree `C:\dev\rg-title`，分支 `feature/overhaul-v3-title`。先读 `docs/overhaul-v3-brief.md`（通用规则、命令、汇报格式）。

## 目标

把标题屏的静态 AI keyart（`assets/kenney_clean/backgrounds/title_keyart.png`：锻厅里一座铁桥，骑士扛着巨剑立在桥上，
链条垂下、天井一道光柱、左右是大齿轮与管线）换成**游戏内实时渲染的像素场景**（真实骑士精灵 + 背扛巨剑、PointLight2D、
多层视差、粒子），随存档进度 / 结局变化；并整体重做版式与动效。keyart 文件保留，只作 `USE_LIVE_SCENE=false` 时的回退与美术对照。

## 渲染架构（已调研）

- 标题屏 `scenes/ui/TitleScreen.tscn` / `scripts/ui/title_screen.gd` 是根窗口里的 Control（不在 GamePresentation 下），
  `PresentationMetrics.bind_control(self)` 把它放进 1280×720 设计层的整数内容矩形；世界始终是 640×360 SubViewport，
  经 `assets/shaders/pixel_smooth.gdshader`（`scale_hint` = `PresentationMetrics.for_window(root)["scale"]`）显示，
  做法见 `scripts/ui/game_presentation.gd`（`SubViewport` + `world_2d = World2D.new()` + nearest + `snap_2d_transforms_to_pixel`）。
- 方案：新建 `scenes/ui/TitleWorld.tscn` + `scripts/ui/title_world.gd`，放进 TitleScreen 自己的 640×360 `SubViewport`，
  用一个名为 **`Keyart`** 的 `TextureRect`（`STRETCH_KEEP_ASPECT_COVERED`，texture = 视口纹理，挂 pixel_smooth 材质，
  根窗口 `size_changed` 时更新 `scale_hint`）显示它——`tests/display_resolution_test.gd`（要求 Keyart 是 TextureRect 且
  KEEP_ASPECT_COVERED）与 `tests/ui_transition_test.gd`（开屏首帧 `Keyart.modulate.a < 0.95`）依赖这个节点名与类型。
- 视口内用自己的 `Camera2D`（`Parallax2D` 需要相机）、`CanvasModulate` 环境色、本地 `WorldEffects` 节点（不要用依赖 `game_world`
  组的 `GameContext.world_effects()`）。`WorldClock.hold_for_menu()` 保持（标题时钟冻结）。
- `TitleScreen.USE_LIVE_SCENE := true` 常量：false 时走旧 keyart。用 3 档分辨率（960×540 / 1280×720 / 1920×1080）截图与
  keyart 对照，观感不及才算没过关。

## 场景构成（640×360 世界坐标，可调）

- 多层视差：`assets/env/backdrop/forge_sky|forge_far|forge_mid|forge_near.png`、`machinery_iron.png`、`truss_forge.png`、
  `core_hall.png` 可作远景；大齿轮、吊灯、链环用新脚本 `tools/gen_title_assets.py`（PIL，色板用 `tools/gen_ui_kit.PAL`）生成
  逐帧旋转的齿轮图集 / 吊灯 / 链环到 `assets/title/`（只要像素、1×、NEAREST，不糊）。
- 铁桥（`_draw` 程序化像素即可）上立着骑士：`CharFrames` / `SkinCatalog.frames_for(skin, &"idle")` + `offset_for` + `tint_of`
  （皮肤取 `SaveData.skin_id`，缺省 `SkinCatalog.DEFAULT_SKIN`），巨剑用 `scripts/player/greatsword.gd` 的 `Greatsword`
  节点 `show_carried()`（不调用需要 Player 的 `tick`，自己用 sin 做 ±1.2° 摆动）。
- 灯光：摇摆吊灯上的 PointLight2D（闪烁 + 随链摆动）、桥下炉心辉光（呼吸）、骑士轮廓光；天井光柱用加法渐变多边形 + 尘埃，不用 PointLight；
  PointLight 总数 ≤8，阴影最多 2 盏。吊灯 / 链环用 `Fx.additive_mat()` 做辉光。
- 粒子：上升火星、下落灰烬、蒸汽（可用 `Fx` / CPUParticles2D，整数像素、预算受控）；相机呼吸 + 鼠标视差（整数像素偏移）。
- 进度变体 `TitleWorld.configure(state: Dictionary)`，另给静态 `TitleWorld.state_from_save()` 读 `SaveData.peek_ending()`、
  `saved_scene`、`flags`、`ember_rank`、`skin_id`：无存档（冷炉、锈剑）/ 进行中（按幕换色阶，已通关章数点亮对应吊灯 N/14，
  通关旗标见各章出口的 `flag_id`，如 `level03_done`；第一章用 `boss_dead`）/ 送剑 `give`（炉稳、骑士不在、剑独自立着）/
  守火 `keep`（骑士坐炉边）/ 熄灭 `snuff`（灯全灭、一点残红）。

## 版式与动效（1280×720 设计层）

- Logo 居中偏上"锻造入场"（白热 → 锈色扫光 + 火花，shader 或 tween），副题淡入；
- 菜单去掉厚板，改左下"铁条 + 余烬光标"极简列（行动 / 模式 / 系统 / 离开四组），焦点时火星迸发并联动场景灯光与镜头微推；
- 右侧「行程档案」改"旅程刻度"：14 格章节刻度（已通关亮起）+ 当前章前情一句 + 4 枚数据芯片（阶位 / 外观 / 试炼 / 竞技场），Tab 展开完整档案；
- 底部：墓志循环打字机，署名收进"致谢"；
- 动效：开场（灯逐盏亮 → logo 锻造 → 菜单落位）；进关（白热闪 + 镜头推向骑士）；退出（炉厅灯逐盏熄灭，只剩剑影，"余烬熄灭。"）。
- 音频：炉厅环境床键 `&"bed_title"`——由 systems agent 生成资产并加进 `Sfx.LIBRARY`，你这边**只做特性探测**
  （`Sfx.LIBRARY.has(&"bed_title")` 才启动）。
- **顺手修 bug**：`ID_ARENA`（"余烬竞技场"）在 `_on_chosen` 里没有分支，点了没反应——接上 `ArenaRun.start()`（`scripts/autoload/arena_run.gd:51`，
  返回 bool，成功后由它负责切场），并加测试。

## 必须保持的对外表面（改了就在同一提交里更新对应测试）

常量 `ID_NEW/CONTINUE/TRIAL/ARENA/SETTINGS/CONTROLS/QUIT/KEEP/OVERWRITE/UPDATE`、`RAIL_X`、`RAIL_TOP`；
方法 `intro_playing()`、`is_quitting()`、`quit_finished()`、`quit_on_finish`、`open_confirm()/close_confirm()/confirm_open()`、
`character_select_screen()`、`_on_chosen()`、`_on_confirm_chosen()`；节点 `Menu`（7 个 MenuItem，id 同上）、`Keyart`、`Masthead`、
`Inscription/EpitaphRow/Epitaph`、`Dossier` 及 `DossierRank/Skin/Trials/Chapter/Foot`、`TrialLockHint`、`QuitCaption`、`ConfirmMenu`、
`OverwriteConfirm`、`WindowBackdrop/Black`、`CreditBand`、`BootCurtain`。"有存档时光标默认停在「继续」"这一行为不能变
（`tools/input_walkthrough.gd` / `campaign_walkthrough.gd` 依赖）。相关测试：`tests/title_screen_test.gd`、`title_flow_adversarial_test.gd`、
`display_resolution_test.gd`、`ui_transition_test.gd`、`modal_screens_test.gd`、`m5_tier5_adversarial_ui_test.gd`；工具：
`tools/title_metrics.gd`（`scenes/tools/TitleMetrics.tscn`）、`ui_peek.gd`、`transition_probe.gd`、`render_acceptance.gd`。
版式改了就更新这些测试的布局断言（保留"不重叠、触控下限 ≥52px 高、墓志与离开同基线"这类精神，数值可调）。

## 交付

- 新增 `tests/title_world_test.gd`（各变体 headless 构建无错误、灯数与节点数预算、`state_from_save()` 在 5 类存档下的取值）。
- 截图工具：写 `tools/title_peek.gd` + `scenes/tools/TitlePeek.tscn`（窗口模式，抓标题在 960×540 / 1280×720 / 1920×1080 下的开屏后画面；
  各变体各一张），证据放 `screenshots/acceptance/overhaul-v3/title/`；对照图 `assets/kenney_clean/backgrounds/title_keyart.png`。
- `frame_cost_probe` 加标题机位（或在 `title_world_test` 里断言节点 / 灯数预算）。
- 写 `docs/title-live-scene.md`（结构、变体表、版式、可调常量、测试清单），并把旧文档 `docs/title-and-loadout-ui.md` 里被取代的部分标注"已被 v3 取代"。
- 提交前跑过滤用例：`title`、`display_resolution`、`ui_transition`、`modal_screens`、`m5_tier5_adversarial_ui`、`character_select`、`pause`，全绿。
- **不要做**：回看余烬总结页（systems agent 做 `RecapScreen`，合并后由主 agent 接线）、手柄、设置页、音频资产。
