> 历史实现记录：2026-10-31 已撤下 2.5D 竞技场入口。当前采用的 3D 模式见 [竞技场说明](../arena-mode.md)。

# 竞技场：横版 3v3 推线

你和 2 名 AI 队友（蓝方「灰卫」）对 3 名 AI（红方「锈誓」）。摧毁敌方水晶即胜。12 分钟到点时，先比拆塔数，再比击杀数，仍相同则平局。

这条模式不写战役存档。记录在 `user://rustgrave_arena.cfg`。标题仍调用 `ArenaRun.start()`。

正式界面是 `scripts/ui/arena_hud.gd`（`arena_duel.gd` 进场时挂上）。`ArenaRun.set_ui_attached(true)` 之后，右上角临时文字条隐藏，Enter 也不再由 `ArenaRun` 直接开战或离场。没挂界面时文字条仍可用：大厅「按 Enter 开战」，对局中拆塔 / 击杀 / 时间，结算后「Enter 返回标题」。

## 规则

| 项目 | 值 |
| --- | --- |
| 队伍 | `player` 蓝、`enemy` 红、`neutral` 中立。友军免伤；中立与双方敌对 |
| 时长 | 720 秒（12:00）。暂停（`get_tree().paused`）或 `Director.is_suspended()` 不计时 |
| 倒计时 | 开战前 3 秒，单位冻结 |
| 兵线 | 开场 1 秒第一波，之后每 30 秒。每波 2 近战骸骨 + 1 远程火颅；第 3、6、9… 波加 1 只碎铁犬 |
| 塔 | 每方外塔、内塔。外塔没倒，内塔免伤 |
| 水晶 | 两座塔都倒了才受伤。水晶被毁即结束 |
| 超时 | 拆掉的塔数（不含水晶）→ 击杀数 → 平 |
| 击杀 | 英雄、小兵、精英计入该方击杀。拆塔另计，不算击杀 |
| 等级 | 英雄 1–6 级。经验满升一级，加血、加攻 |
| 复活 | 基地泉水。秒数 = (5 + 1.25×(等级-1)) × 难度系数 |
| 余烬 | 英雄补刀小兵、击杀、拆塔获得。基地泉水旁可买强化 |
| 炉火精英 | 站在中路祭台旁的地面上。击杀后击杀方获得 12 秒「炉火祝福」（×1.3，整数没涨则至少 +1；玩家是攻击 +1）。45 秒后在原地重生 |
| 难度 | 见习 / 老练 / 炉火：反应、伤害系数、小兵生命、出手间隔、复活时间 |

难度 id：`apprentice`（见习）、`veteran`（老练，默认）、`forge`（炉火）。

商店（只在 `playing`、人在己方泉水范围内；测试可把 `ArenaRun.shop_ignore_range` 设为 true）：

| id | 名称 | 价格 | 效果 |
| --- | --- | --- | --- |
| `edge` | 锋刃 | 18 | 攻击 +1 |
| `plate` | 炉甲 | 18 | 生命 +3 |
| `haste` | 疾步 | 12 | 移速 +16 |

`buy()` 失败时 `reason` 为 `phase` / `unknown` / `ember` / `range`。

## 地图

单条主路，宽 3840，地面 y = 312，画面高 360。左右墙封死。

地面是一整块碰撞，左右各伸进封墙 8px，避免墙和地面只在端点相切时把人卡住。祭台（x 1760–2080，丘顶 y 268）只是多边形：比地面高 44px，跳跃大约 36px，上不去，也不做坡。精英站在祭台旁的平地 `(1920, 312)`，不挡路。小兵和英雄走到约 110px 内、且精英比别的目标更近时会打它。击杀给击杀方炉火祝福，45 秒后在同一点重生。

| 点 | 蓝（左） | 红（右） |
| --- | --- | --- |
| 泉水 | 150 | 3690 |
| 水晶 | 460 | 3380 |
| 内塔 | 900 | 2940 |
| 外塔 | 1280 | 2560 |
| 玩家出生 | 300, 312 | — |

复活点是泉水，不是出生点。泉水半径 78，每秒回 4 点。带内的人只要横向走进这个半径就吃到治疗，不看脚在带子的前缘还是后缘。

## 纵深

对局脚底不再钉死在 y = 312。战场是一条连续纵深带，跳跃是另一条轴。

选连续带，而不是三条硬车道：小兵要微调到目标的深度，英雄要躲开塔弹，小地图也要画出深浅。三条车道做得到换线，但容差和「贴着目标的深度走」会变成跳格。战役玩家仍用原来的重力平台跳跃；只有竞技场把角色放进 `arena_plane` 组之后，才改走这条平面。

| 参数 | 值 | 含义 |
| --- | --- | --- |
| 带 | 脚底 y ∈ [252, 328]，宽 76 | 252 远（画面上），328 近（画面下）。`GROUND_Y` 312 仍在带内，玩家出生在这里 |
| 三股兵线 | 262 / 290 / 318 | `lane_y(slot)`，slot 对 3 取余。小兵按波次槽位分开 |
| 纵深速度 | 74 px/秒 | 上 = 更远，下 = 更近。键是 W / S，以及方向键上 / 下，左摇杆纵轴。空格仍是跳 |
| 跳跃 z | 初速 176，重力 460，最高 34 | 只抬精灵、挥砍和受击盒。脚底 y 不变，阴影留在地上，越高越小越淡 |
| 剑击容差 | \|Δdepth\| ≤ 16 | 英雄平砍、小兵近战、玩家的剑和技能 |
| 飞弹容差 | \|Δdepth\| ≤ 30 | 火颅、英雄技能、塔和水晶的子弹。子弹打出时锁在目标当时的深度上 |
| 塔 / 水晶 | 贯穿整条带 | 任何深度都能打到。仇恨仍按原顺序，同级时深度更近的优先 |

玩家在竞技场里是无重力的平面运动：不调用战役那套 `move_and_slide` 重力，左右仍是走和冲刺，上下改深度，跳跃写成 z。离开竞技场或回到过场锁（大厅、结算）时还原重力、碰撞遮罩和脚底贴地。战役里的 `Player._physics_process` 主路径不读这些变量。

AI：小兵平时待在自己那一股，看见目标后向目标深度靠 70%。英雄交战时贴到对手的深度，撤退时回到泉水那一档；身边有朝自己飞来、深度接近的敌方子弹时，向带子另一侧让 32px。塔的射程覆盖整条带，但排序距离会加上深度差。

画面：父节点打开 Y 排序，单位 `z_index` 都是 0，脚底 y 更大的画在前面。场景是炉城地下的角斗熔炉，不是墓园。视差层不用 Parallax2D 的 repeat（3840 主路右段会被引擎 repeat 语义吃掉），而是 `arena_stage.gd` 手动平铺 + 手动镜头偏移。分层：天空手绘双向渐变（左冷蓝、右炉红，向地平线增亮）→ `SideWash` 阵营色罩（垫在剪影下只染天空）→ 战役炉城套图 `forge_far` / `forge_mid` / `forge_near`（2 倍、最近邻）→ `machinery_forge` 机械剪影带 → 熔河 `pit_river` 加色平铺，沉在后缘矮墙基（y 198–226，墙垛遮挡下沿），河面上一道暖光雾 → 顶棚暗带 + `truss_forge` 桁架 + 垂链吊钩 → 墙面器件（阀 / 表盘 / 警示牌 / 断机，带安装杆）+ 呼吸闪烁的信号灯（左蓝右琥珀）→ 墙顶火盆（动画火，蓝侧冷火、红侧热火）→ 大门（石门框 + 旗帜，蓝方挂灯、红方炉口）→ 纵深地面 → 祭台 → 塔 / 水晶 / 泉水背后的 glow 柔光晕（不占点光源名额）→ 蒸汽 / 余烬 → 8 盏点光 → 前景上下渐变压边 + 两侧石柱剪影。地面砖带对齐纵深 252–328：后缘砖行细、暗、冷，前有矮墙和墙沿暖高光；前缘砖行变高、变亮、变暖，底下一道厚边和阴影；砖面整体压暗衬单位，左半偏冷灰蓝、右半偏暖。地面细节：塔基 / 祭台前灼痕、兵线间排水格栅、后缘阵营镶嵌条（左蓝右红）、三股兵线发光引导纹（虚线 + 柔光衬底 + 96px 节奏箭头）、中路中心炉纹徽记。塔是三级基座的双层石塔，腰间队伍色带、正面挂旗、顶部火盆动画火；水晶是三级台阶上的晶簇（锁住时双环护盾加锁，暴露后环消失、晶核更亮、顶部溅火星），泉水是宽沿水盆加阵营色火焰和呼吸治疗圈，祭台是三级台阶、四角短柱、台面火纹加光柱。队伍色：英雄和小兵写在视觉根的 `self_modulate`，塔、水晶、精英把阵营色画进像素里（避免再被纵深色乘灰）。受击闪白在子精灵的 `modulate`，纵深冷暖写在视觉根的 `modulate`（远冷暗、近暖亮）。点光源 8 盏。像素贴图只做 1 倍或 2 倍缩放。

取舍：没有真透视摄像机，纵深就是画面上的上下。单位之间仍然没有身体碰撞，只靠深度错开。大厅里角色还站在 y = 312 的碰撞板上，开战才进入平面，所以出生的一瞬间不会掉出带子。

## 单位

脚本在 `scripts/arena/`，都没有 `class_name`，互相 `preload`。分组只用 `arena_unit`。AI 不进 `player` / `enemies`。队伍色写在视觉根节点的 `self_modulate` 上（`modulate` 留给受击闪白）。

英雄用 `SkinCatalog` 的三套主角帧，背上 `Greatsword.show_carried()`（巨剑 z = -1，父节点 z ≥ 0）。小兵用现成帧：骸骨 `skeleton/walk`、火颅 `fire_skull/fly`、碎铁犬 `scrapper_hell_hound/walk`。远程和塔的飞弹是 `Hitbox`，不是 `Projectile`，不占 8 发预算。

| 角色 | 生命 | 攻击 | 说明 |
| --- | --- | --- | --- |
| 近战小兵 | 6 | 1 / 22px | 速度 46 |
| 火颅 | 4 | 1 / 148px | 飞弹 |
| 碎铁犬 | 12 | 1，对建筑 +8 | 速度 32。看见已暴露的建筑就直走，不跟小兵缠斗 |
| 英雄 1 级 | 10 | 1，6 级到 3 | 玩家用属性修正抬到同一条曲线（基础 5 血 + 修正） |
| 塔 | 64 | 2 / 176px，间隔 1.25 秒 | 见下方仇恨 |
| 水晶 | 84 | 1 / 136px，间隔 1.4 秒 | 护盾期间免伤，仍会射击 |
| 精英 | 18 | 2 / 42px | 站在地面上，优先打英雄 |

见习：AI 伤害 ×0.55、小兵生命 ×0.6、出手间隔 ×1.4、复活 ×0.6。炉火：×1.35、×1.5、×0.7、×1.45。乘完伤害至少为 1，所以 1 点的英雄平砍三档仍是 1，差别在塔的 1/2/3 点、小兵血量和出手快慢。老练是 1 倍。

小兵每波比上一波厚 6%（生命、伤害、碎铁犬的攻城加成一起乘），第 13 波封顶在 1.72 倍。塔打小兵时伤害少 1 点（至少还是 1），让兵线在塔下多站一会儿。6 分钟（`UNREST_AT` 360 秒）后炉火躁动：小兵出手间隔 ×0.78，每座已经暴露的塔每 3.5 秒掉 1 点血（水晶不掉）。英雄血量不低于一半、且己方有碎铁犬或至少两名小兵靠近当前可打的敌方建筑时，不再为了 130px 外的敌方英雄停在中路，改为跟着兵压塔；敌人贴到攻击距离里仍会交手，低血撤退不变。

赢下兵线的一侧（2 名 1 级英雄带着每波小兵，塔对小兵少 1 点伤害）不会在开场 40 秒内拆掉外塔，也不会 30 秒推完，水晶仍落在 12 分钟里面。两边对耗时，躁动和压塔要在 8–12 分钟里至少拆掉一座塔，而不是 0:0 只比击杀。

`Health.quiet`：竞技场 AI 的血池为 true。AI 打 AI 不发 `GameEvents.hit`（避免顿帧和震屏）。受害者是玩家，或攻击者链上有玩家 / `player` 组，仍然发。

## AI

英雄状态，每拍按难度的 `think` 间隔重算：

1. **撤退**：生命 ≤ 34% 开始，回到己方泉水，回到 85% 才离开。
2. **技能**：交战距离内有敌方英雄且技能好了，打出一发飞弹（约 6.5 秒冷却）。
3. **交战**：敌方英雄进入约 130px。
4. **推进**：否则朝当前可打的建筑走；110px 内有精英就打精英；贴到已暴露的塔/水晶就打。

小兵：110px 内更近的精英，否则最近的敌方小兵 → 攻击距离内已暴露的建筑 → 贴身的英雄。不会从地图另一头追精英，但不会从它身上穿过去。

塔和水晶的仇恨（同级取更近的）：

1. 正在攻击己方英雄的敌方英雄（AI 的交战/技能态，或玩家 1.5 秒内打过敌方英雄）。
2. 小兵。
3. 其他英雄。

中立不打。单位之间没有身体碰撞，只跟地面和墙撞，避免在一条路上卡死。

## 状态机

`ArenaRun.phase()`：

| 阶段 | 含义 |
| --- | --- |
| `idle` | 不在竞技场 |
| `lobby` | 已进场，单位冻结。Enter 开战。镜头可从蓝方飞到红方 |
| `countdown` | 3 秒倒计时，仍然冻结 |
| `playing` | 计时、兵线、战斗 |
| `result` | 已写记录。Enter 回标题。不自动跳走 |

`start()` 进场景后停在 `lobby`。`begin()` 只表示场景准备好了，不开战。`begin_match()` 才进入倒计时。`restart_match()` 清本局再倒计时。`exit_to_title()` 在非结算阶段会先 `abandon()`，所以中途退出不会走出一场胜利。场景 `_exit_tree` 在仍处于大厅/倒计时/对局时也会 `abandon()`。

`running()` 仅表示 `playing` 且未结算。`allows_combat()` 再排除暂停和 Director 挂起。

无头测试：`ArenaRun.auto_begin = true` 再 `activate_for_test()`，跳过大厅和倒计时直接 `playing`。测完把 `auto_begin` 设回 false 并 `abandon()`。

`finish(win)` 仍可用，内部进入结算，**不再** 2.5 秒后自动回标题。

## 记录 v2

文件键（`meta`）：

| 键 | 含义 |
| --- | --- |
| `version` | 2 |
| `best_score` | 最高分。分数 = 个人击杀×10 + 拆掉的敌塔×25 + 获胜 100。记录里仍保留；标题战绩改读 `wins` |
| `best_kills` | 单场个人击杀最高 |
| `runs` | 场次 |
| `wins` / `losses` / `draws` | 胜 / 负 / 平。标题档案写「胜 N 场」，「竞」芯片写「胜N场」；缺 `wins` 按 0 |
| `fastest_win` | 最快胜利用时（秒）。0 表示还没有一场用时 > 0 的胜 |

读取时把 v1（只有 `best_score` / `best_kills` / `runs`）补成上面的形状，不改已有数字，也不在读取时写回磁盘。

## UI 接口

前端只依赖这一节。信号都挂在 Autoload 节点 `ArenaRun` 上。查询函数是脚本上的 static，用 `ArenaRun.foo()` 调用。

### 信号

- `phase_changed(phase: String)` — 上表五个字符串之一。
- `kill_feed(entry: Dictionary)` — `killer_id` / `killer_label` / `killer_team` / `victim_id` / `victim_label` / `victim_team` / `kind`（`hero` `minion` `elite`）。
- `tower_destroyed(team: String, index: int)` — `team` 是**被拆的那一方**。`index` 0 外塔、1 内塔、2 水晶。
- `match_finished(result: Dictionary)` — 与 `match_result()` 相同。
- `match_restarted()` — `restart_match()` 已把数据清掉，场景正在重置单位。
- `blessing_granted(team: String)` — `player` 或 `enemy`。

### 流程

- `start() -> bool` — 标题入口。成功则 `active`，阶段 `lobby`，`pending_world_path` 为竞技场，并淡入表现层。
- `set_difficulty(id: String) -> bool` — 仅 `idle` / `lobby`。非法 id 返回 false。
- `difficulty_id() -> String`
- `begin_match()` — `lobby` → `countdown`。
- `restart_match()` — 清空本局，发出 `match_restarted`，再 `begin_match()`。
- `exit_to_title()` — 结算阶段保留 `match_result()`；否则先 `abandon()`。然后淡入标题。
- `abandon()` — 不写记录、清空 `last_result()`、`active` 变 false。
- `activate_for_test()` — 不切场景。`auto_begin` 为 true 时直接 `playing`。
- `begin()` — 场景 `_ready` 调用，表示场馆已生成。

### 查询

- `phase() -> String`
- `active() -> bool` — 含大厅、倒计时、对局、结算。为 true 时战役存档只读（`blocks_campaign_save()`）。
- `running() -> bool` — 仅对局中。
- `allows_combat() -> bool`
- `time_left() -> float` — 剩余秒。不在场时为 720。
- `countdown_left() -> float`
- `score() -> int` — 当前分数（见记录公式，获胜加分要到结算才加上）。
- `add_kill(points := 0)` — 兼容旧调用：给玩家记一次小兵击杀，并把 `points` 加进分数垫。
- `scoreboard() -> Dictionary`

```
{
  phase, difficulty, time_left, elapsed, countdown,
  blue: { kills, towers, crystal_hp, crystal_max, blessing },
  red:  { kills, towers, crystal_hp, crystal_max, blessing },
  heroes: [ { id, team, kind, label, is_player, kills, deaths, assists,
              last_hits, towers, level, xp, ember, alive, respawn } ]
}
```

`heroes` 固定包含玩家和 5 名 AI。`towers` 是该方拆掉的敌塔数（0–2）。`respawn` 是剩余复活秒数。

- `tower_status() -> Array` — 6 项，蓝外/蓝内/蓝水晶、红外/红内/红水晶：

```
{ team, index, kind, label, hp, max_hp, alive, exposed, x, y }
```

`kind` 为 `outer` / `inner` / `crystal`。`exposed` 为 false 时打上去伤害是 0。`label` 为「外塔 / 内塔 / 水晶」。

- `minimap_data() -> Dictionary`

```
{
  lane_left: 0, lane_right: 3840, ground_y: 312,
  depth_back: 252, depth_front: 328, depth_mid: 290,
  altar: { x, y, w, h },
  units: [ { id, team, kind, x, y, alive, depth, spans } ],
  structures: <tower_status>
}
```

`depth` / `spans` / `depth_back` / `depth_front` / `depth_mid` 是后加的。旧字段都还在。`spans` 为真的是塔和水晶，小地图上画成贯穿纵深带的竖标。没有 `depth` 时前端用 `y`。

- `respawn_time_left(unit = null) -> float` — `unit` 可以是节点、`"player"` / 英雄 id，或 null（玩家）。
- `player_level() -> int` / `player_xp() -> int` / `player_ember() -> int`
- `level_of(id: String) -> int`
- `blessing_time_left(team: String) -> float`
- `blessing_multiplier(team: String) -> float` — 无祝福为 1，有则为 1.3。
- `shop_items() -> Array` — 上表的副本。
- `buy(item_id: String) -> Dictionary` — `{ ok, reason, ember, item }`。
- `grant_ember(id, amount)` — 测试和奖励用。
- `match_result() -> Dictionary` / `last_result()` 同一份副本。结算前是 `{}`。

```
{
  outcome: "win"|"loss"|"draw",
  win: bool, draw: bool, reason: "crystal"|"timeout"|"finish"|"test",
  duration, elapsed, time_left, score, kills,
  blue_kills, red_kills, blue_towers, red_towers,
  player: <该英雄的记分行>,
  heroes: <scoreboard 的 heroes 快照>,
  mvp: { id, label, team, kills, assists, towers },
  new_record: bool, difficulty
}
```

MVP 分 = 击杀×3 + 助攻 + 拆塔。`kills` 是玩家个人击杀。`new_record` 表示本场刷新了最高分、最高击杀或最快胜利。

- `strip() -> CanvasLayer` / `strip_text() -> String` — 临时文字条。
- `set_ui_attached(on: bool, owner: Node = null)` — 正式界面挂上时 `on = true`。文字条清空并隐藏，`_unhandled_input` 不再吃 Enter。退出时用同一个 `owner` 解开；后挂上的界面不会被先退出的那份误关。`ui_attached` 可读。

### 场景

世界节点在组 `game_world` 上，脚本 `scripts/levels/arena_duel.gd`。

- `set_camera_driver(enabled: bool)` — false 时不再抢镜头。之后用 `camera().focus(...)` 自己飞。
- `camera() -> GameCamera`
- 大厅/倒计时玩家 `cutscene_locked`。进入 `playing` 解开。

镜头限制：左 0、右 3840、上 0、下 360。

## 界面

坐标是 1280×720。局内条在层 10（`MatchChrome`），大厅 / 炉台 / 结算在子层 `ArenaOverlay`（15）。战役 HUD 仍在层 10：竞技场里藏掉目标行、天气条、剑核插座、播报横幅和教学条，血量、毒素、Boss 条保留。死亡不弹战役死亡幕（`DeathOverlay`），改看复活倒计时。

| 阶段 | 界面 |
| --- | --- |
| `lobby` | 左侧面板贴着视口上沿和下沿，阵容、规则、战绩在内部滚动，菜单「难度」「开战」「返回标题」钉在面板底部，1280×720 和 960×540 都能点到。难度 ←→（见习 / 老练 / 炉火，`set_difficulty`）。镜头从蓝方基地飞到红方再回到玩家；Esc 或 Enter 跳过飞行，飞完之前 Enter 不开战。飞完后 Esc 只把焦点移到「返回标题」。 |
| `countdown` | 屏幕中央 3、2、1，归零后短闪「开战」。 |
| `playing` | 顶部记分（蓝/红击杀、存活塔、剩余时间）。两侧外塔 / 内塔 / 水晶血条；没露出的水晶是灰条加「锁」。右上小地图（主路线、队伍色点、塔与水晶、玩家高亮、摄像机视窗）。右侧击杀播报最多 5 条，5 秒淡出；拆塔 / 水晶另用「被摧毁」样式。左下等级、经验、余烬、炉火剩余秒数。死亡时中央「复活倒计时 N 秒」。炉火祝福弹出一条公告。己方泉水旁按交互键打开炉台，`buy(item_id)`；失败原因写在面板上（余烬不足 / 不在泉水旁）。对局外打不开。 |
| `result` | 胜利 / 失败 / 平局、时长、双方击杀与拆塔、个人 K/D/A、补刀、等级、MVP。`new_record` 时显示「新纪录」。「再来一局」调用 `restart_match()`，「返回标题」调用 `exit_to_title()`。Esc 只把焦点移到「返回标题」，不直接退出。 |

键盘和手柄走 `ui_up` / `ui_down` / `ui_left` / `ui_right` / `ui_accept` / `ui_cancel`。阶段切换或场景退出时大厅、结算、炉台一并隐藏，避免纱幕留在画面上。节点离开树时断开对 `ArenaRun` 信号的连接。

## 和其他系统的接缝

- `GameContext.route_scene`：竞技场在 `MODE_SCENES` 里，走 `GamePresentation`（640×360）。`is_world_scene` 仍只认 14 章，存档不会把竞技场当成关卡。
- `Player._on_died`：`ArenaRun.active()` 时不重载场景，关掉身体碰撞和受击盒，收掉挥砍，等复活。
- `Player.arena_respawn(at)`：先满血再开物理，碰撞层 2、受击盒恢复、约 1.2 秒无敌，发出 `GameEvents.player_respawned`。复活前会把战役 HUD 的 `DeathOverlay` 藏掉。`hud.gd` 在竞技场里也不再弹出这层死亡幕。在 `arena_plane` 组里时，脚底 y 会被夹回纵深带，跳跃高度 z 清零。
- `Player` 纵深只在 `arena_plane` 组里生效（`arena_depth` / `arena_z` / `arena_request_jump` / `arena_set_drive` / `arena_force_z`）。不在这个组时，即使 `ArenaRun.active()`，仍走战役重力。W / S 和方向键上下在组内移动深度，空格跳跃。
- `Health.quiet` / `Health.grant_iframes(seconds)`。玩家的火带和冲击波挂在世界特效节点上，不在 `Player` 的父链里。剑击仍有顿帧；这两下打在 `quiet` 的 AI 身上会扣血、会计入击杀，但不会发 `GameEvents.hit`，因此没有顿帧和震屏。
- `HintService` 在 `ArenaRun.active()` 时不排队、不显示战役死亡提示（那条会教玩家回余烬巢）。离开竞技场后仍按战役规则。
- `Director.play` / `play_when_clear`：竞技场会话中直接返回，不播章节卡和间幕。

暂停菜单在 `ArenaRun.active()` 且阶段为 `playing` 时只显示「继续 / 重开对局 / 退出竞技场」。重开调用 `restart_match()`，退出调用 `exit_to_title()`，两者都会先把 `get_tree().paused` 设回 false。大厅、倒计时、结算打不开暂停菜单。战役暂停菜单仍是原来的七格。退出必须走 `restart_match()` 或 `exit_to_title()`，不要只 `fade_to` 标题。

## 测试

未在本环境执行（终端钩子拦截）。清单：

- `tests/arena_run_test.gd` — 规则与格式、v1→v2、阶段和文字条、暂停不计时、放弃不写幽灵胜、路由白名单、剧情守卫、标题菜单仍有竞技场、`start()` 设置待加载场景、兵线节奏模拟（12 分钟内能分胜负、不会 30 秒速推、超时顺序）。
- `tests/arena_units_test.gd` — 友军免伤、quiet、塔仇恨、低血撤退。
- `tests/arena_match_test.gd` — 塔顺序和水晶护盾、超时三条、兵线每 3 波带狗、原地复活不重载、提示重置、经验/余烬/商店/祝福。
- `tests/arena_hud_test.gd` — 各阶段面板、难度切换、结算按钮与 Esc、暂停菜单竞技场 3 项 / 战役仍 7 项、击杀播报上限与淡出、竞技场不弹死亡幕、覆盖层退出后不留纱幕、大厅三枚按钮在 1280×720 与 960×540 的视口内。
- `tests/arena_match_test.gd` — 另含波次成长：每波 +6% 直到 1.72 封顶；没设种子时兵线槽位不抖。

跑法：`tools/run_tests.ps1`，或只跑上述脚本。无头整局：`res://scenes/tools/ArenaSim.tscn`，环境变量 `RUSTGRAVE_ARENA_SEED` 选种子（不设时按 1）。老练、只有 AI（脚本玩家只往前走），三局都没有越带，也没有卡死。外塔大约在 9–10 分钟倒下。

| 种子 | 用时 | 拆塔（蓝/红） | 击杀（蓝/红） | 结果 | 越带 | 卡死 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 12:00 | 1 / 1 | 80 / 76 | 胜 | 0 | 0 |
| 7 | 12:00 | 1 / 1 | 70 / 67 | 胜 | 0 | 0 |
| 21 | 12:00 | 1 / 1 | 74 / 74 | 平 | 0 | 0 |
