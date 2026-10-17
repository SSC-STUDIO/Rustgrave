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
wav/ogg，22.2 MB；另 16 个 Kenney CC0 兜底副本 0.2 MB。真峰 ≤ −3 dBFS）。

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
  循环接缝靠 `gen_audio_verify.py` 实测真峰与接缝 dB（bed 接缝 0.13–3.85 dB，足够小）。
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

