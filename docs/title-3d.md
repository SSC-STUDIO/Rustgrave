# 3D 标题屏：锻造大厅（Forward+ / 像素化渲染）

> 取代 [title-live-scene.md](title-live-scene.md) 的 2D 层叠活景。渲染器从 GL Compatibility
> 切到 **Forward+**，标题屏的世界由实时 3D 锻造大厅（`TitleWorld3D`）渲染进 640×360 的
> 输出纹素网格后整数放大；UI 层（字标 / 菜单 / 旅程列 / 墓志 / 页脚）仍是 2D `Control`，
> 版式与时序常量不变。14 章战役、战斗、Boss、游戏内分镜仍是 2D，不在本次改动范围。

## 1. 渲染链路

```
Window (Forward+)
└─ TitleScreen (Control, PresentationMetrics.bind_control)
   ├─ WindowBackdrop  CanvasLayer -10   黑边
   ├─ WorldLayer      CanvasLayer  -1   3D 世界层（不受 UI 的 Control 变换影响）
   │  └─ Keyart (Control, 全屏)          开屏淡入仍推它的 modulate.a（工具/测试沿用的节点名）
   │     └─ WorldStage (pixel_stage.gd)
   │        ├─ SubViewport  own_world_3d = true，尺寸 = (640+4,360+4) × render_scale
   │        └─ WorldImage (Sprite2D)    像素后处理 + 最近邻整数放大
   └─ 其余 UI：Masthead / Menu / JourneyColumn / Epitaph / CreditBand / 覆盖层
```

- **输出像素网格**：固定 640×360 输出纹素（`fill_screen=false`，16:9 内容矩形 + 黑边），
  整数倍最近邻放大。与 2D 版标题的分辨率和版式一致。
- **超采样**：`render_scale`（默认 2，可设 1–3）只放大 3D 渲染目标；`pixel_post.gdshader`
  在输出纹素内做 r×r 盒式降采样，所以光影渐变是连续的，而最终画面仍落在块状像素网格上。
- **后处理**：暗角、颗粒、dither、可选调色盘锁定、炉口热浪扭曲、`tint`；竞技场不设置这些
  参数，默认全中性，2D 玩法像素完全不受影响。
- **cull/可见性**：标题不可见时 `WorldStage` 的 SubViewport 切 `UPDATE_DISABLED`，不烧 GPU。

## 2. 共享坐标契约（`kit/layout.gd`）

`TitleLayout` 是纯常量模块（1 单位 = 1 米，+Y 上，相机朝 -Z），所有模块只读它，不硬编码：

| 项 | 值 |
|---|---|
| 桥面 / 骑士脚底 | `DECK_Y = 0`、`KNIGHT_POS = (0,0,0)`，桥 X 跨熔河 ±8.5，深 z ±3.6 |
| 大厅 | 宽 32（±16）、高 15、z 从 +6 到 -30（深 36） |
| 熔河 | `PIT_Y = -6`、河面 `LAVA_Y = -5.55`、X ±8.5、z +12..-22 |
| 炉膛 / 炉口 / 炉光 | `FORGE_CENTER=(12.2,3.8,-9.6)`、炉口 `(12.2,2.8,-6.35)`、灯光 `(11.2,2.6,-5)` |
| 齿轮 | 大 `(-11,3.7,-3) r=2.6/16 齿`、小 `(-8.9,7.15,-3) r=1.5/12 齿` |
| 吊灯 | 两排各 7 盏，X -7.5..7.5 步长 2.5，前排 z=+2.2 / 后排 z=-2.8，链顶 y=11.2，灯身 y=6.8 |
| 天窗 / 光柱 | `SKYLIGHT_CENTER=(3.5,15,-12)`、`BEAM_FROM=(3.5,14.8,-12)` → `BEAM_TO=(-2.3,0.05,0.6)` |
| 相机契约 | 透视 FOV 30°、焦平面取景高 13.5 m → 1 输出纹素 = 0.0375 m（`WORLD_PER_TEXEL`） |

## 3. 像素相机（`title_camera_rig.gd`）

- **透视 FOV 30°**、near 0.05 / far 150、`KEEP_HEIGHT`；焦平面 z=0。
- **纹素吸附**：`texel_world = 2·tan(fov/2)·d / 360`；相机平移吸附到整输出纹素，旋转用
  `snap_transform` 保持朝向，剩下的亚纹素余量（`subpixel ∈ [-0.5,0.5]`）交给
  `WorldStage.set_camera_offset()` 做**整数物理像素**平移 —— 静态物体不会爬行。
- **指针视差**：归一化指针 → 绕焦平面取景点的 ±1.2° 微轨（焦距不变 ⇒ 纹素尺寸不抖）。
- **呼吸**：±1 输出纹素 / 7 s。`Settings.shake_scale == 0` 时指针 / 呼吸 / nudge 全关。
- 快速镜头（intro 俯冲前 1.6 s）允许 `snap=false`，此时不做纹素吸附。
- 已知残差：SubViewport 含 2 纹素 MARGIN，若严格按 360 行算纹素，实际渲染纹素差 1.1%
  （≤0.0055 纹素/帧，不可见）；需要像素级精确可 `set_stage_margin(2)`。

## 4. 运镜与过场（`title_shots.gd` / `title_shot_player.gd`）

镜头一律**纯采样**（无 Tween、确定性、可跳过），时间推进由 `advance(dt)` 驱动：

| 镜头 | 时长 | 内容 / 事件 |
|---|---|---|
| `intro` | 2.8 s | 0 s 从天窗 42° 广角俯视 → 1.6 s 降到桥面英雄机位；`lantern_wave` 0.30 s 起每 0.16 s 一盏、`hammer_strike` 1.60、`logo_forge` 1.60、`menu_reveal` 1.95（与 TitleScreen 既有常量一致） |
| `idle` | 7 s 循环 | 呼吸 / 指针视差由 rig 负责；道具各自循环（锻锤 3.7 s、坩埚 22 s、骑士 19 s 转身等） |
| `attract` | 20 s | 25 s 无输入后自动触发，绕英雄机位 ±6° 正弦环绕（0/20 s 无缝）；任意输入打断回 idle |
| `confirm` | 0.55 s | 向骑士推进 5 纹素 + `flash` / `furnace_surge` |
| `quit` | 灯数 × 0.2 s | 后退 + `grade_to_dark` + 逐盏 `lantern_out`，返回 `dark_at` 给 TitleScreen 排音效/墓志 |

- 玩家输入跳过开屏、开屏结束自动接 idle；`skip()` 补发剩余终态事件并 `finished`。
- 舒适性：全镜头受 `Settings.shake_scale` / `flash_scale` 控制。
- **构图（集成层，`title_look.gd`）**：镜头表的数据是正对大厅的，直接用会读成平面背景板。
  集成层把每个采样改写成「3/4 微俯仰 diorama」：绕视点 yaw **-10°**、距离 ×**0.95**、
  升高 **+1.8 m**、视点上移 **+0.5 m**、FOV ×1.0（常量在 `title_look.gd` 顶部）。
  intro/confirm/quit 走同一变换，整屏保持一套镜头语言。

## 5. 光影（`title_lighting.gd`，Forward+）

- **Environment**：ACES tonemap + 每变体 exposure/white；BG 深色；低能量 ambient（真正的
  环境项由 kit 的 surface shader 持有，见 §6）；**Glow**（threshold 0.9、bloom 0.15、levels 1–5）；
  **SSAO**（0.7 / 1.4 / 1.2）；**SSR 仅 high 档**（max_steps 32）；**体积雾**（density 0.021–0.034、
  anisotropy 0.3、length 48、temporal on）；近距 depth fog；adjustment 微调。
  **SDFGI / SSIL 关闭**（收敛慢、镜头移动拖影）。
- **灯组（12 盏 ≤ 14，投影 4 盏 ≤ 6）**：Directional 天窗冷光（投影）、Spot 光柱（无影、
  体积雾主贡献）、Omni 炉口（投影）、Omni 桥下熔河、6× Omni 吊灯（fixture 4/10 投影）、
  2× Omni 火盆。坐标全部来自 `TitleLayout`；`TitleState.light_plan()` 与灯组 fixture/影数
  双向断言，防止两套灯分叉。
- **闪烁**是纯函数 `flicker01(t, seed)`：同 dt 序列得到同结果，测试可回放。
- **质量档** `Settings.title3d_quality`：high（SSR + 4 阴影）/ balanced（无 SSR、2 阴影）/
  low（无 SSR、1 阴影），SSAO/Glow/体积雾在各档保留；离开树时恢复渲染器默认全局。
- 体积雾网格分辨率与阴影图尺寸是工程设置（`project.godot`）：`directional_shadow/size=2048`、
  `positional_shadow/atlas_size=2048`、`volumetric_fog/volume_size=96 / volume_depth=96`。

## 6. 几何与材质（`kit/`）

- `title_kit.gd`：调色板、共享 `ShaderMaterial`、顶点色网格合并（`ArrayMesh`）、图元部件、
  1 纹素外壳描边、`palette_texture()`；`set_ambient(linear_color, energy)` 由 `TitleWorld3D`
  在每次 grade 后与灯组同步。
- `shapes.gd`：齿形齿轮 / 拱券 / 桁架 / 链环 / 破旗布条的确定性 `ArrayMesh` 生成器。
- `surface.gdshader`（Forward+ spatial）：顶点色为基色 + 世界主轴投影 32×32 亮度纹理
  （逐表面纹素密度一致）+ 顶点 alpha 自发光遮罩 + 三档 toon 光照 + `ambient_light` uniform。
- `hall_builder.gd` / `bridge_builder.gd` / `furnace_builder.gd`：`static func build(host)`
  一次性生成远墙三窗、拱列、侧机壳、屋顶桁架破洞、铁桥与支撑链、炉膛烟道；合并网格，
  合计节点数受控。熔河面与光柱卡归 `title_lighting`，骑士与道具归 `props/`。
- 无外部模型、无 Blender、无 glTF：所有几何在引擎内生成。
- `title_dressing.gd`（集成层）在 kit 几何之上补**布景密度**：左右近景机壳体块、桥后远拱廊、
  屋顶斜撑、侧墙管道、悬挂铁链、侧台杂物（铁砧/桶/货箱）——合并成约 6 个 MeshInstance3D，
  目的是让 3/4 机位下的锻造大厅不像空盒子，而不是增加玩法几何。
- `title_look.gd`（观感层）：逐变体的曝光/环境光/雾/体积光/辉光/后期暗角与色调；同时接管
  构图（§4）与窗玻璃自发光增益（把中间窗从 ACES 白块压回冷钢蓝）。

## 7. 道具与叙事状态（`props/` + `title_state.gd`）

- `title_state.gd` 是**纯函数**存档/变体状态机（从旧 2D `TitleWorld` 移植）：`peek_save()` /
  `build_state()` / `state_from_save()`（含测试接缝 `forced_state`）/ `prop_plan()` /
  `grade()` / `light_plan()`。变体语义不变：cold / act1–4 / give / keep / snuff（+ true_break），
  14 章 → 四幕、吊灯 N/14、未知结局回退 give、损坏存档 → cold。
- `grade()` 返回 3D 光影参数（exposure/white/sun/furnace/pit/fog/glow/grade_tint/
  lantern_lit/gear_speed/ember_rate/steam_rate/souls_*/ghost_count/brazier_*/chain_mode/
  knight_pose/planted_sword），同时保留旧 2D GRADES 12 键作回退。
- 道具：齿轮（真实咬合）、14 盏吊灯 + 6 链、破旗、锻锤、坩埚、送剑链、亡魂、魂光、火盆、
  低多边形骑士（stand / planted / seated / absent，19 s 一次转身望炉）、余烬/蒸汽粒子。
  每个道具 `setup/configure/apply_grade/advance` + `fired` 信号；`configure` 只改参数不重建。
- 菜单 7 行的反应与旧版同名可观察量：`surge`、`wave_active`、`gazing`、`strike_requests`、
  `brazier_boost`、`cloud_target`、`gust`、`soul_boost`（`TitleWorld3D.reaction_state()`）。

## 8. 公开 API 与接线

`TitleScreen` 仍只调用 `TitleWorld3D` 的这些方法（与旧 `TitleWorld` 刻意同名）：
`state`、`configure()`、`play_intro()`、`skip_intro()`、`set_pointer(Vector2)`、`nudge(float)`、
`react_to(StringName)`、`reaction_state()`、`enter_push(dist, sec)`、`quit_out(sec) -> dark_at`、
`lantern_pulse()`；静态状态走 `TitleState`。探针：`lit_lanterns()`、`light_count()`、
`shadow_lights()`、`set_shadows_enabled()`、`knight_pose()`、`current_shot()`、`play_shot()`、
`pixel_stage()`、`variant()`。

## 9. 预算

| 项 | 上限 | 现状 |
|---|---|---|
| 3D 灯 | 14 | 12（4 投影） |
| 标题 SubViewport 尺寸 | — | 1288×728（640+4）×2 超采样；输出 640×360 |
| 道具节点增删 | 构建后 0 | `configure/apply_grade` 只改参数（测试断言 300 帧节点数不变） |
| 标题帧 p95（1920×1080 窗口） | ≤ 8 ms | 见验收报告（本机远程显示环境，仅同机相对比较） |
| 2D 玩法画面 | 与 Compatibility 基线一致 | 平均差 ≤ 0.62/255，无结构差异（`reports/p0-forward-plus/2d-visual-diff.json`） |

## 10. 工具与验收

- `tools/run_title_peek.ps1`：窗口截图（变体 × 尺寸 × 镜头：`boot,idle,focus,attract,confirm,quit,dossier,recap`），
  每张附 JSON（renderer、内部分辨率、超采样、draw calls、shadow draws、灯数/亮灯数/姿态）。
  `-Renderer gl_compatibility` 只用于 A/B 诊断。
- `tools/run_frame_cost_probe.ps1 -Level title -Variant cold|give|keep|snuff`：标题帧成本。
- `tools/compare_shots.py --a <参考帧> --b <新帧>`：逐像素差报告（Pillow），渲染器切换与
  2D/3D 对照都用它。
- 测试：`tests/title3d_state_test.gd`、`title3d_camera_test.gd`、`title3d_shots_test.gd`、
  `title3d_lighting_test.gd`、`title3d_kit_test.gd`、`title3d_props_test.gd`、
  `pixel_stage_scale_test.gd` + 更新后的 `title_screen_test.gd` / `display_resolution_test.gd`。
- 视觉参考：旧的 2D 活景参考帧仍在 `screenshots/acceptance/overhaul-v3/title-perf/final-live/`，
  3D 验收帧写到 `screenshots/acceptance/title3d/`。

## 11. 迁移与清理

- 旧的 2D 活景（`TitleWorld` + `title_*.gd` 世界侧脚本 + `assets/title/` 素材 +
  `tools/gen_title_*.py` 生成器）不再被标题运行时实例化；`USE_LIVE_SCENE=false` 只剩静态
  keyart 诊断回退。按计划在 3D 验收通过后删除这些文件（保留被 `arena_stage.gd` /
  `storyboard_stage.gd` 引用的素材）。
- 旧 2D 标题测试套件已删除（`title_world_test` / `title_elements_test` / `title_dolly_adversarial`
  / `title_vault_adversarial` / `title_elements_adversarial`），语义由 §10 的 3D 套件覆盖；
  UI 版式与流程测试（`title_screen_test` / `title_flow_adversarial_test` / `title_adversarial_stress_test`）
  保留并按新世界接口更新。

## 12. 验收状态（2026-10-31，Forward+ 实跑）

| 项 | 结果 |
|---|---|
| 工程在 Forward+ 启动、2D 玩法画面无变化 | ✅ 同机 A/B（Compatibility vs Forward+）平均差 0.57–0.62/255，无结构差异；`reports/renderer-switch-forward-plus.md` |
| 2D 玩法性能 | ✅ 不劣于 Compatibility（stage08_true 冻结机位 p95 3.79 ms vs 3.91 ms） |
| 3D 标题帧成本（1920×1080 窗口，640×360 输出、2× 超采样） | ✅ cold p95 **4.43 ms**、give p95 **4.15 ms**（目标 ≤ 8 ms）；`reports/title3d-perf/` |
| 5 变体 × 3 档分辨率截图 | ✅ `screenshots/acceptance/title3d/final/`（15 张 idle + boot/focus/confirm 7 张，0 SHADER/SCRIPT ERROR） |
| 标题专用测试 | ✅ `title3d_state/camera/shots/lighting/kit/props`、`title_screen_test` 48/48、`display_resolution` 6/6、`pixel_stage_scale` 7/7 |
| 全量 headless 套件 | ⚠️ 36 个用例失败，**经 pristine HEAD worktree 复现确认为既有失败**（level 布局/Director 过场/parallax 板比例/教学纸页等，与本分支改动无关）；本分支新增/修改的标题与渲染相关套件全绿 |
| 尚未做 | 逐帧爬行残差量化、Android 真机 Vulkan 验证、`act1/act3/act4/true_break` 的逐变体人工审图（构图沿用同一套 look 参数推出） |

已知观感遗留（下一步可继续，不阻塞运行）：
- 骑士仍偏蓝灰剪影（cold/act2），2D 的红披风没有对应光源；可加一盏极低能量冷色补光灯（灯预算还有 2 盏余量）。
- 光柱落点 `BEAM_TO` 在骑士左侧 2.3 m（`TitleLayout` 契约值，kit 的 parity 测试锁定）；要复刻 2D「骑士站在光里」需改 layout 并同步 4 个模块的测试。
- 中央窗在部分变体仍略偏亮（窗材质自发光增益已在 `title_look` 压到 0.85，可继续下调）。
- 旧 2D 活景代码/素材（`TitleWorld` + 20 个 2D 道具脚本 + `assets/title/`）仍在仓库但不再被标题实例化；删除清单已核对（`arena_stage.gd`/`storyboard_stage.gd`/若干 asset 测试仍引用部分素材，需一并迁移后再删）。
