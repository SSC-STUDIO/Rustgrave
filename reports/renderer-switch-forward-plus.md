# 渲染器切换：GL Compatibility → Forward+（P0 门禁报告）

日期：2026-10-31 · 分支 `title-3d-forward-plus` · Godot 4.7.1

## 1. 改了什么

| 文件 | 变更 |
|---|---|
| `project.godot` | `renderer/rendering_method = forward_plus`、`renderer/rendering_method.mobile = forward_plus`、`config/features` 由 `"GL Compatibility"` 改为 `"Forward Plus"`；新增 3D 标题用的工程级渲染参数：`directional_shadow/size=2048`、`positional_shadow/atlas_size=2048`、`volumetric_fog/volume_size=96`、`volume_depth=96` |
| `tools/run_title_peek.ps1`、`run_frame_cost_probe.ps1`、`run_peek_live.ps1`、`run_render_acceptance.ps1`、`run_ui_peek.ps1`、`run_story_shots.ps1` | 去掉硬编码 `--rendering-method gl_compatibility`，新增 `-Renderer <值>` 参数（缺省走工程设置；`gl_compatibility` 用于复现历史基线 / A-B） |
| `tools/compare_shots.py`（新增） | 逐像素 A/B 报告（Pillow/numpy），输出 mean / p99 / %>8 / %>24 / 结构差异判定 + 可选并排 diff 图 |

- 首次切换后 Godot 触发了资产重导入（95 个 `*.import` 的换行/时间戳噪音，内容 diff 为空，已
  `git checkout` 还原，不进入提交）。
- `scripts/moba/spike/render_spike.gd` 的 `reverse_z = method != "gl_compatibility"` 分支在
  Forward+ 下取 `true`（代码本身已按渲染法分支），RTS 竞技场描边/深度的实机复查仍待窗口验收。

## 2. 2D 玩法画面回归（同机、同场景、仅换渲染器）

命令（隔离存档，窗口在屏幕外）：

```
tools/run_peek_live.ps1 -Renderer gl_compatibility -Spots start,mid -OutDir screenshots/acceptance/title3d/p0/compat
tools/run_peek_live.ps1                           -Spots start,mid -OutDir screenshots/acceptance/title3d/p0/forward
python tools/compare_shots.py --a .../compat --b .../forward --out reports/p0-forward-plus/2d-visual-diff.json
```

| 画面 | 平均差（/255） | p99 | 差>24 的像素 | 判定 |
|---|---:|---:|---:|---|
| 关卡起点 | 0.620 | 5 | 0.24% | PASS |
| 关卡中段 | 0.566 | 3 | 0.19% | PASS |

- 阈值：mean ≤ 2.0、差>24 的像素 ≤ 1.0%。两次都远低于阈值，**无结构差异**。
- 残差来自两次运行时刻不同（活景的粒子/雾气在走），不是渲染器造成的色彩/几何变化。
- 结论：**2D 游戏画面在 Forward+ 下可视为与 Compatibility 等价**。

## 3. 性能（同一台机器，离屏渲染回调间隔）

`tools/run_frame_cost_probe.ps1 -Level stage08_true -Win 1920x1080`，各 4 s 采样，1920×1080 窗口：

| 渲染器 | 回调间隔 p95 | 回调/秒 |
|---|---:|---:|
| GL Compatibility | 3.914 ms | 378.4 |
| **Forward+** | **3.792 ms** | **602.7** |

- 同一窗口/同一冻结入口相机。Forward+ 在 Vulkan 上不慢于 Compatibility（本机甚至更快）。
- 注意：本机显示是远程/虚拟显示适配器环境（`GameViewer Virtual Display Adapter` + RTX 4060 Laptop），
  这些是**离屏渲染回调**，不等于实体显示器的呈现 FPS；只用于同机相对比较。
- 2D 世界视口在 QHD 密度（最大 4×）下渲染，Forward+ 未见退化；尚无理由降低
  `PresentationMetrics.MAX_WORLD_DENSITY`。

## 4. 全量测试

- 首次全量 headless 运行暴露的是**资产缓存缺文件**（渲染器切换触发的重导入被
  `run_tests.ps1` 的 early-error 检测提前打断）→ 已用 `godot --headless --import` 完整重导入修复
  （导入后 6074 个 `.import` 的目标文件全部存在，`missing_dest=0`）。
- 迁移期间全量套件暂时会被并行开发中的 3D 标题模块（正在落盘的脚本解析错误）打断；最终全量
  结果见 §5 与 `reports/p0-forward-plus/`。P0 的 2D 部分（本报告 §2/§3）已独立通过。

## 5. 结论与遗留

| 门禁 | 状态 |
|---|---|
| 工程在 Forward+ 下启动、2D 画面无可见变化 | ✅ 通过 |
| 2D 性能不劣于基线 | ✅ 通过 |
| Android 可行性 | ⚠️ 决策已接受：Forward+ 需要 Vulkan；低端无 Vulkan 设备不再支持（用户决定）。导出前需在目标机型实机验证 |
| 移动端渲染器覆盖 | `rendering_method.mobile` 也设为 forward_plus（全平台一致） |

回退方式：`-Renderer gl_compatibility`（工具级诊断）或把 `project.godot` 两项渲染器设置改回
`gl_compatibility`。3D 标题本身不依赖回退路径。
