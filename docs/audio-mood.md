# Rustgrave — 音频与氛围（第五步）

给作曲 / 音效师，或喂给音乐生成工具。下面英文块为原始 Prompt，请原样复制。

## Audio Mood Prompt（原文，请原样复制）

```
Atmospheric soundtrack for "Rustgrave". Ambient industrial drones mixed with lonely, echoing piano notes. Combat music features heavy, distorted percussion sounds like clashing anvils and broken chainsaws. Sound effects should have heavy low-end thuds for footsteps on metal, and high-frequency sharp clinks for sword parries.
```

## 分层建议

### 探索层（Furnace Hub / Scrapyard）

- 低频工业 drone，缓慢相位，像没熄灭的炉膛。
- 稀疏的回响钢琴，音程偏向小调与空心五度，不要旋律太完整。
- 远景：滴水、断裂齿轮偶发转动、应急灯继电器咔哒。

### 战斗层

- 铁砧对撞、失真链锯、金属废料刮擦作为节奏组。
- Kick 用低端 thud，不要电子舞曲的干净 808。
- 弹反成功时：极短的高频 clink + 一瞬 drone 被“切开”的静音，再回到压迫底噪。

### 生态区音色偏移

| 区域 | 氛围偏移 |
| --- | --- |
| Scrapyard | 风穿过空心梁，钢琴最清晰 |
| Gutterworks | 流水与气泡，drone 变湿、带合唱 |
| Kiln | 高频嘶嘶、低频炉吼，钢琴几乎消失 |
| Hollow Stack | 垂直风切、回声更长，脚步更空 |
| Abyssal Forge | 以上全部叠在一起，加入极低频心跳式脉冲 |

## 关键 SFX（落地实现）

下表里的事件都已落到 `scripts/autoload/sfx.gd` 的 `LIBRARY`（55 个 key + 16 组
surface/变体）和 `assets/audio/sfx/*.wav`，由 `Sfx.play(key)` / `Sfx.play_at(key, pos)`
驱动；`Music`（`scripts/autoload/music.gd`）负责层次化循环与 stinger，`Settings` 调 Master /
Music / Sfx / Ambience 四条总线。脚手架**已含音频资源**（`assets/audio/` 下 120 个
wav/ogg；另 16 个 Kenney CC0 补位副本，其中 8 个未被 LIBRARY 引用）。项目内资源采样峰值
≤ −3.0 dBFS；Kenney 副本源峰值可达 +1.8 dBFS（有损编码过冲），但它们播放时带 −3..−6 dB
voice gain 并被 `Sfx` 总线 Limiter（−2 dBFS）压住，不会削顶。

| 事件 | 落地 key | 质感 |
| --- | --- | --- |
| 金属脚步 | `step_metal`（surface 变体 `step_stone/dirt/metal/wet/sludge`，每面 3 take） | 低端 thud，落地比抬脚更重；按 `surface_for_skin` 选 stone/dirt/metal/wet/sludge |
| 挥砍 wind-up | `swing_a` / `swing_b` / `swing_heavy_a` / `swing_heavy_b` | 布料与锈铁摩擦，略长 |
| 命中 | `hit_flesh` / `hit_armour` | 钝的铁块，不要轻快刀音 |
| **弹反** | `parry` | 高频尖 clink，带极短响度闪避 |
| 冲刺 | `dash` | 短促空气压缩 + 披风 |
| 跳跃 / 落地 | `jump` / `land` | 轻量体感 |
| 毒素积累 | `toxin_warn` / `toxin_full` | 细碎气泡 / 腐蚀嘶声，满槽时心跳 |
| 插入锈核 | `insert` + `gear_*` | 齿轮咬合 + 余烬爆响 |
| 拾取 | `pickup` | 清亮的拾取提示 |
| 机制 / 闸门 | `gate` | 重机械锁扣 |
| UI | `ui_move` / `ui_select` / `ui_tick` / `ui_pause` / `ui_denied` | 菜单与暂停的轻反馈（可选，缺则静音兜底） |

### 覆盖与平衡策略

- **ambience / drone**：每个生态区一组 `THEME_BEDS`（`bed_hall` / `bed_wind` /
  `bed_workshop` / `bed_forge` / `bed_core`）+ 全图底噪 `cemetery_drone`，按
  `THEME_DRONE_SCALE` 调低（graveyard 1.0 → slag/core 0.2）。`THEME_EVENTS` 给出
  稀疏一次性音（drip / gear_creak），按随机间隔与 dB 抖动，让房间"有呼吸"。
- **天气**：`rain` / `rust_rain` 循环 + `splash` 随雨量变大而提升。
- **距离衰减**：`Sfx.play_at` 以相机为听者，近 `POS_NEAR=110`、远 `POS_FAR=720` 世界像素，
  线性掉到 `POS_FLOOR_DB=-30`；横向用 5 条预平移总线（`SfxPanL2/L1/Sfx/R1/R2`）做声像，
  避免每发声音实时调 pan。
- **重复声音分层控制**：`VOICE_RULES` 给每个 key 配（最大并发声 / 最小间隔），`PRIORITY`
  决定后到的低优先是否顶掉先到的；循环 bed 用 `Music` 的三 deck × 三 slot 等功率交叉淡化，
  同一轨绝不会叠加或重启。
- **总线压限**：`Sfx` 走 Compressor（−14 dB / 2.5:1 / +2 dB makeup）→ Limiter（−2 dBFS），
  Master 再挂 HardLimiter（−1 dBFS），叠满同屏声音也不会削顶；`Ambience` 只挂室内 Reverb。
- **跨场景淡入淡出**：换关 / 回标题由 `Music._poll_world` 自动清理 danger / boss 并切主题；
  暂停时 Master→Music 走低通（`PAUSE_CUTOFF_HZ=1100`）+ duck（`PAUSE_DUCK_DB=-7`）；
  循环接缝由 `tools/gen_audio_verify.py` 在**解码后**逐个循环资源实测（判定：接缝跳变 vs
  文件自身相邻采样步长 p99.9；44 条循环 0 click，详见文末"数值验证"）。
- **接线核对**：脚步在 `player.gd::_poll_stride_audio`（按 `SolidPlatform.skin` 选
  stone/dirt/metal/wet/sludge，雨中叠加 splash）；武器/命中/弹反在 `melee_combat.gd`、
  `juice.gd` 与 `CombatRules.HIT_FEEL`；机关/门/压板/拾取在 `interactables/`；UI 音由
  `MenuList`、`UiKit.sfx` 与各面板的 open/close 统一发出。

### 区域音色偏移（已实现）

| 区域 | 氛围偏移 | 落地 bed |
| --- | --- | --- |
| Scrapyard / Graveyard | 风穿空心梁，钢琴最清晰 | `cemetery_drone` 满，stone 脚步 |
| Gutterworks | 流水与气泡，drone 变湿 | `bed_hall` + `rust_rain`，wet 脚步 |
| Kiln | 高频嘶嘶、低频炉吼 | `bed_forge` 偏强 |
| Hollow Stack | 垂直风切、回声更长 | `bed_wind`，drip 稀疏 |
| Abyssal Forge | 以上全部 + 极低频脉冲 | `bed_forge` + `bed_core` 叠层 |

### 作曲 / 音效师仍可用的空间

代码只认 `<track>_<role>.ogg`（role = bed / keys / pulse / hi）与 `THEME_BEDS` /
`THEME_DRONE_SCALE` / `THEME_EVENTS` 查表；要换音色直接替换 `assets/audio/` 下对应文件、
**保持文件名与长度结构**即可，无需改脚本。在 `Sfx.LIBRARY` / `Music.THEMES` 里新增 key 时，
记得同步登记（否则会被 `UiKit.has_sfx` 探针判定为"无音而静音兜底"）。

## 数值验证（本轮：无试听，靠可复跑的数字与契约）

工具：`tools/gen_audio_verify.py`（Python + numpy/scipy + ffmpeg/ffprobe；解析 `sfx.gd` /
`music.gd` / `combat_rules.gd` 的常量表，再解码每个资源）。回归测试为零依赖 headless：

```
& $godot --headless --path <project> res://tests/run_tests.tscn -- --case-filter=audio   # 11 用例 / 873 断言
& $godot --headless --path <project> res://tests/run_tests.tscn -- --case-filter=music   # 16 用例 / 189 断言
& python tools/gen_audio_verify.py --json report.json                                    # 数字审计，PASS 退出码 0
```

工具检查内容：每个 .wav/.ogg 的原生采样率 / 时长 / 采样峰值 / RMS / DC 偏移 / 削顶率
（|x|≥0.99）/ EBU R128 整体响度与真峰；所有循环资源（10 主题 × bed/keys/pulse、2 Boss
bed/hi、ending、9 个 ambience）在**解码后**的循环接缝；`LIBRARY/VARIANTS/AMBIENCE` 路径存在
且已 import（含 OGG loop=true 标志）；代码里出现的所有 SFX/Music 键可解析；Music 主题 /
Boss / ending / stinger 覆盖；按 `BASE_DB + SFX_MAKEUP_DB + TRIM_DB` 换算的一次性有效峰值、
`AMBIENCE_LEVEL` 连续电平、`CALM_MIX/DANGER_MIX` 之后的音乐响度、以及总线限幅器余量。

### 实测数字（本轮全部通过）

- **资产与契约**：120 个项目内 wav/ogg（约 22.5 MB）+ 16 个 Kenney CC0 补位副本；0 缺失、
  0 未 import、0 未解析键；`CombatRules` 的 21 个受击 / 玩家 / 首领 SFX 键全部直连
  `LIBRARY`（0 个走 `SFX_FALLBACK`）；10 主题全部 bed+keys 齐全，9 个带 pulse（title 只有
  bed+keys），双 Boss bed+hi、ending bed+keys、9 个 stinger 全部存在；`LEVEL_THEMES` 10 章
  映射全部有效。未引用：`nest_light` / `plate_click` / `rustgate_melt` 3 个键（已生成未接线）；
  `SKIN_SURFACE` 覆盖 16/18 个 `SolidPlatform.skin`（`nave` / `nave_float` 走 "未知→stone"
  兜底，结果正确但非显式，见下节）。
- **循环接缝**：44 条循环资源 0 click / 0 warn。判据 = 接缝处 |x[0]−x[-1]| 与文件自身相邻
  采样步长的 99.9 分位比较（持续型 bed/keys 阈值 3.0×；打击型 pulse/hi 允许接缝落在正拍上，
  阈值 8×）。修复前后：
  - `cemetery_drone.wav`：**修复前 −16.7 dBFS = 文件 p99.9 的 60.3×**（每 4 秒一次的真
    click，旧实现 69.2 Hz 正弦在 4 s 内非整数周期 → 相位跳变）；重建后 **−54.1 dBFS /
    0.69×**。
  - `rain.wav` / `rust_rain.wav` / `nest_hiss.wav`：旧版"把文件开头副本贴到结尾"的
    `_crossfade` 会引入二次跳变；改为整周期构造后 r_p999 = 0.44 / 0.10 / 0.62，DC 归零。
  - 音乐循环：最大 3.07×（`cathedral_pulse` 的正拍 attack，属设计；`r_near`<1 证明接缝
    不高于接缝附近 16 ms 内的正常步长）；持续型 ≤ 1.29×。OGG 边界测到的是有损编码边界残差
    （≤ −27.6 dBFS），低于文件自身正常步长，被内容掩蔽。
- **电平 / 总线**：项目内资源采样峰值 ≤ −3.0 dBFS（16 bit 量化后实测 −3.4 ~ −3.5 dBFS）；
  Music：主题 calm −20.7 LUFS / danger −19.1 LUFS、Boss bed −19.5 LUFS、stinger −17.0 LUFS；
  Ambience：主题 bed 经 `AMBIENCE_LEVEL` 后 −36.5..−31.0 LUFS（比 calm 音乐低
  10.3..18.6 dB），天气/drone/hiss −39.5..−30.9 LUFS（低 10.2..21.5 dB）；SFX 一次性有效
  峰值中位 −8.0 dBFS（−17.0..−3.4），脚步再按 `STRIDE.dB` 下压。总线：Master（HardLimiter
  −1 dBFS）→ Music（低通，暂停时启用）/ Sfx（Reverb→Compressor −14 dB/2.5:1/+2 dB→Limiter
  −2 dBFS）/ Ambience（室内 Reverb）/ SfxPanL2..R2（panner ±0.85/±0.45），名字与接线未改。
- **削顶 / DC**：项目内资源 0 削顶（|x|≥0.99 采样占比 0.000%）、0 DC 偏移（修复前
  `rain.wav` +0.0119、`rust_rain.wav` +0.0191）；入库的 Kenney 副本以 −3..−6 dB voice gain
  播放并被 `Sfx` 限幅器压住（未入库的 `hurt.ogg` 解码后 0.121% ≥0.99，不参与播放）。3 个同
  key 声部相干叠加最多 +9.5 dB，会撞 `Sfx` 限幅器（−2 dBFS），Master HardLimiter（−1 dBFS）
  兜底 → 是压限而非采样削顶；Music 三层最坏相干和 ≈ −0.9 dBFS（cathedral danger），stinger
  播放时必定 duck 音乐 4..12 dB。
- **极端 trim**：`TRIM_DB[&"ui_select"] = +19 dB`（Kenney 源峰值 −30.3 dBFS）。归一化后
  ui_select / ui_denied / ui_move 有效峰值 −14.3 / −14.2 / −14.2 dBFS，三件 UI 音是齐的，
  所以保留并在文档记录；若要去掉这个极端值，最小改法是给 `tools/gen_audio_sfx.py` 加一个
  项目原生 ui_select，然后 `sfx.gd` 换路径 + 删 trim（需要 sfx.gd 写权限，本轮未改）。

### 本轮重新生成的资源（生成器同步更新，幂等：重跑字节一致）

- `assets/audio/ambience/rain.wav`、`rust_rain.wav`：3× 平铺循环滤波 + 折返雨滴 + 整周期
  LFO；DC 归零、接缝消除，RMS 保持 −20.8 / −21.4 dBFS（AMBIENCE_LEVEL 0.28 的混音不变）。
- `assets/audio/ambience/cemetery_drone.wav`：4 s → 8 s，三个正弦吸附到每循环整数周期，
  呼吸 LFO 1 周期/8 s（旧 8.98 s）；RMS 保持 −24.3 dBFS。
- `assets/audio/ambience/nest_hiss.wav`：循环滤波 + 折返蒸汽爆，RMS 保持 −19.6 dBFS。
- `assets/audio/sfx/splash.wav`：未变（重跑后 sha256 与旧文件相同）。
- 生成器：`tools/gen_rain_loop.py`、`tools/gen_drone_loop.py`、`tools/gen_wet_sfx.py`
  （numpy，确定性、幂等；删除旧 `_crossfade`）。

### 已知缺口 / 待接线（写权限不在本轮音频包）

- `Sfx.SKIN_SURFACE` 缺 `nave` / `nave_float`（第 4 章大教堂实际使用）：当前靠"未知 → stone"
  兜底，听感正确但不是显式映射，且注释声称覆盖全部 skin。最小修改（`sfx.gd`，
  归音频包所有者）：`&"nave": &"stone", &"nave_float": &"stone",`。
- `LIBRARY` 的 `nest_light` / `plate_click` / `rustgate_melt` 已生成、已 import、无代码触发
  （压力板/铁闸/余烬巢目前分别用 `insert` / `gate` / `insert`），建议在对应
  `interactables/` 里改播专用键。`Music.stinger(&"rest")` 已实现、无调用方（预留）。
- legacy WAV 循环以 QOA（`compress/mode=2`）import：本文件的接缝数字来自源码 WAV 解码，
  Godot 运行时 QOA 解码的接缝无法在 headless 读取，列为未验证项（编解码器帧首状态一致，
  预期无额外接缝；真机若听到接缝可把这 4 个 `.wav.import` 的 `compress/mode` 改为 0=PCM）。

### 未验证项（如实记录）

- **没有任何试听**：以上全是数值与契约证据；响度平衡是否"好听"、音色、接缝是否听得出、
  音乐与 ambience 的情绪匹配均未经人耳判断。
- headless（Dummy 音频驱动）无法验证真实混音总线输出、运行时位置声像、QOA/Vorbis 解码差异；
  只覆盖桌面 Windows + Godot 4.7.1，移动/网页/主机未测。
- 频段/节奏平衡只看了整体 LUFS、真峰与接缝，未做逐段响度曲线（工具输出 LRA 但未设阈值）。

