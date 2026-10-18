# Rustgrave 二期集成契约（Campaign v2）

本文件是"主线（战役/关卡/故事/模式/接应）"与并行支线（角色系统、武器系统、视觉/音频）之间的唯一接口口径。
**任何一方改动契约，必须先改本文件并由 Lead 批准。** 契约测试不过 = 不允许合并。

分支：`feature/campaign-v2`（从 `merge/upgrade-into-theme-fit` 53c5f19 切出）。
外部角色/武器线：文件所有权在对方；我方只写适配层与关卡/UI 挂点，feature-detect 缺失时回退默认体验。

---

## 1. 章节注册与文本

### 1.1 GameContext（Lead 所有）

```gdscript
# scripts/autoload/game_context.gd
const LEVELS := { "<id>": "<scene path>", ... }      # 只增不改旧 id
const LEVEL_ORDER: Array[String] = [...]              # 14 章顺序；旧 id 不变
const LAYOUTS := { "<id>": "<layout gd path>", ... }  # ChapterLayout 子类
static func next_level_id(id: String) -> String
```

id 与显示章号分离：**存档旗标/节点路径永远用 id**（`level03_done`），显示章号只用 `ChapterText`。
新增 id：`level02b`、`level04b`、`level07b`、`level09b`。旧 id `level01`…`level10` 不动。

### 1.2 ChapterText（story-lead 所有，Lead 锁 API）

```gdscript
# scripts/data/chapter_text.gd
class_name ChapterText
const ACTS := [{"id": &"awake", "name": "..."}, ...]
const CHAPTERS := {
  "level01": {
    "number": "壹",                 # 显示章号（14 章统一重编）
    "name": "腐液回廊",
    "act": &"awake",
    "objective": "……",              # 目标追踪一句话，≤16 字
    "wake": "……",                   # 醒来句，≤30 字
    "exit_captions": ["……", "……"],  # 出口离别字幕，1–2 句
    "steles": [{"node": "SteleX", "title": "……", "text": "……"}],  # 每行≤22 字、≤2 行
    "boss_intro": "……",              # 可选，Boss 名号副标题
    "recap": "……",                   # 暂停"前情提要"用，≤40 字
  },
  ...
}
static func has(id: String) -> bool
static func order() -> Array[String]                  # 与 GameContext.LEVEL_ORDER 一致
static func title_of(id: String) -> String            # "锈墓・<number> — <name>"
static func subtitle_of(id: String) -> String         # "锈墓・<number>"
static func wake_of(id: String) -> String
static func objective_of(id: String) -> String
static func exit_captions_of(id: String) -> PackedStringArray
static func steles_of(id: String) -> Array
static func recap_of(id: String) -> String
static func act_of(id: String) -> Dictionary
```

规则：
- 关卡 layout 不再写剧情字符串：`title()/wake_line()` 调 ChapterText；`stele()`/`exit_door()` 的文本从注册表取。
- `ChapterTitles` 保留旧常量（`LEVEL01`…）但内部改为委托 ChapterText，避免 UI 测试大面积改。
- 文本修改只需改 ChapterText + docs/story.md，两者必须同步（测试比对）。

### 1.3 story_flow（story-lead 所有）

```gdscript
# scripts/data/story_flow.gd
class_name StoryFlow
const BOUNDARIES := [
  {"from": "level01", "to": "level02",
   "epilogue": ["……", "……"],       # 离场承接（1–3 句）
   "teaser": ["……"],               # 下一章钩子（1 句）
   "staging": "door" | "rain" | "fire" | ...},
  ...
]
static func for_edge(from_id: String) -> Dictionary
```

间幕执行器 `scripts/levels/chapter_transition.gd`（Lead/story-lead）：
- 幂等标志 `interlude_<from>_seen`；跳过一次也算看过；死亡读档不重播；暂停冻结；切场硬复位。
- 不写未完成章节旗标；结局前后各一条特殊序列。

---

## 2. 存档 v2（Lead 所有）

`scripts/autoload/save_data.gd`：
- `SAVE_VERSION := 2`；v1 档必须可继续（迁移测试 `tests/save_migration_test.gd`）。
- 新增字段：
  - `character_id: String`（默认空 = 默认角色，由角色系统提供默认 id）
  - `extras: Dictionary`（角色/武器/试炼外的跨系统元数据；未知键原样保留）
- 既有结构保持：`equipment = {weapon, armor, trinket, bag[]}`；`story.flags`；`meta.ending`。
- 角色/武器持久化键（对方写入这里）：`character_id`、`equipment.*`、`extras["unlocked_characters"]`（Array[String]）、`extras["unlocked_weapons"]`（Array[String]）。
- 试炼模式（TrialRun）**禁止**调用 `save_game/persist_story/mark_flag`；只允许读解锁旗标。试炼记录独立文件。

---

## 3. 角色/武器接应契约

### 3.1 对外 API（角色/武器线提供；我方 feature-detect）

```gdscript
# scripts/data/character_roster.gd   （对方所有）
class_name CharacterRoster
static func ids() -> Array[StringName]
static func def(id: StringName) -> Dictionary
# {display_name, char_frames_id, body_size: Vector2, hurt_size: Vector2,
#  speed_mult: float, max_hp_mod: int, intro_line: String, ability_set: Array[StringName]}
static func default_id() -> StringName

# scripts/data/weapon_roster.gd     （对方所有）
class_name WeaponRoster
static func ids() -> Array[StringName]
static func def(id: StringName) -> Dictionary
# {display_name, slot: StringName, moveset_id: StringName, pickup_art: String,
#  desc: String, unlocked_by: String}
static func default_id() -> StringName
```

我方只通过以下适配层访问（不直接引用对方内部）：`scripts/player/loadout_bridge.gd`（Lead 所有）
```gdscript
class_name LoadoutBridge
static func available() -> bool                        # roster 脚本存在且默认 id 有效
static func character_id() -> StringName               # 缺失时返回 &""
static func weapon_id() -> StringName                  # 缺失/空时返回当前装备 weapon 的 id
static func display_character() -> String              # 缺失时 ""
static func display_weapon() -> String                 # 缺失时现有装备名
static func apply_to_player(player: Player) -> void    # 只调对方公开入口；无入口则 no-op
signal loadout_changed                                  # 由 Bridge 节点转发
```

### 3.2 UI / 关卡挂点（Lead + 主线 agent 所有）

- 暂停菜单：「角色与装备」页由角色/武器线提供 scene/script；Lead 只挂入口（存在才显示）。
- HUD：角色/武器小牌（`Hud.show_loadout(name, weapon)`）；无 roster 时隐藏。
- 标题：新游戏「选择角色/武器」页；无 roster 时整页隐藏，流程与现在一致。
- 关卡奖励位（已落地）：`ChapterLayout.reward(host, name, pos, kind, id)`（Lead 所有）→
  `scripts/interactables/equipment_pickup.gd` 的 reward 模式：
  - `kind ∈ {"weapon", "character", "equipment"}`；`item/item_id` 的旧装备路径保持不变。
  - roster 不存在时回退"一点余温"（回 1 HP + 一次性提示 + consumed），**不回退成假物品、不死锁**。
  - 每幕埋 1–2 个奖励位；奖励文案进 ChapterText；位置必须合理（支路尽头/守关者之后）。
- 教学：新武器/角色有 `HintService` 一条提示 + 键位说明（键位表在 `KeyLabels`）。

**实现状态（M0）**：
- `scripts/player/loadout_bridge.gd` 已实现（静态 API，feature-detect；不新增 autoload）。
- `SaveData` v2 已实现：`character_id` / `extras` / `set_character()` / `get_extra()` / `persist_profile()`。
- `EquipmentPickup` 已加 `reward_kind/reward_ref/reward_name`；装备路径不变。
- HUD/暂停/标题挂点在 M5 集成（等 roster 落地后再加，避免空控件）。

### 3.3 契约测试（合并门）

- `tests/loadout_contract_test.gd`：roster 存在 → id/def/字段/默认值合法；不存在 → skip 并打印原因。
- `tests/loadout_route_test.gd`：对每个角色的 `ability_set` 跑 `LevelSanity.is_reachable` 主路线（14 章）；装备武器不影响移动。
- `tests/loadout_save_test.gd`：旧档无 character_id → 默认角色；未知 weapon id → 回退现有装备；extras 保留。
- 合并后必须：全量测试 + 14 章 campaign walkthrough + 两套 loadout 走查 + 试炼 smoke。

---

## 4. Boss 框架契约

### 4.1 接口（boss-framework 所有）

```gdscript
# scripts/enemies/boss_kit.gd
class_name BossKit
func boss_title() -> String                      # 名号卡标题
func boss_subtitle() -> String
func max_phases() -> int                          # 2 或 3
func attack_table() -> Array[Dictionary]          # {id, phase, weight, cooldown, min_range, max_range}
func arena_events() -> Array[Dictionary]          # {id, at_phase, once}
# 攻击表额外可选字段（boss-framework 已实现，缺省安全）：
#   windup（硬下限 0.35s）/ windup_by_phase / cooldown_by_phase /
#   active / recovery / telegraph / hitbox{offset,size} / damaging / enrage_only
func intro_steps() -> Array                       # Director 步骤
func phase_steps(phase: int) -> Array
func death_steps() -> Array

# scripts/enemies/boss_director.gd（挂 Boss 下，BossKit 驱动）
# scripts/world/boss_arena.gd（竞技场：边界/锁门/相机/机关/存档点）
```

- `ChapterLayout.boss(host, name, kind, pos, arena_left, arena_right)`：统一生成 Boss + BossArena + 存档点校验；
  **返回 Boss 节点（场景缺失返回 null 并 push_warning，不阻塞布局）**；Arena 用 `boss_arena(host, name)` 或 Boss meta 反查。
  `ENEMY_SCENES` 注册新 Boss（capstan_warden/silent_choir/hollow_bell/bell_founder/emberwind_herald 已占位）。
- 现有两场 Boss 采用**协助观测模式**接入 Director（行为/时序严格不变）；新 Boss 用**驾驶模式**：
  `BossDirector.attach(self, kit, true)` + `start()`，出招连 `attack_requested(id)`，收招 `notify_attack_finished()`，死亡 `notify_death()`。
- 场地规格：平地竞技场宽 ≥600（竖向高 ≥900），≥2 个可读机关，Boss 活动边界与相机 limit 一致，Boss 前存档点 ≤80px。
- 可读性硬规则：每招 `CombatMarker` 预警 ≥0.35s；同一时刻最多一条预警；攻击 hitbox 不出场地；阶段转换有 1.2s 无敌演出；死亡演出可跳过。
- 验收：`tools/boss_fixture.gd`（通用夹具）逐 Boss 渲染入场→各阶段→死亡；`tests/boss_framework_test.gd` 锁调度/可读性/边界。

### 4.2 新 Boss 场景命名

`scenes/enemies/<Name>.tscn` + `scripts/enemies/<name>_boss.gd`：
`CapstanWarden`、`SilentChoir`、`HollowBell`、`BellFounder`、`EmberwindHerald`；重做：`ExecutionerBoss`、`NightmareBoss`。

---

## 5. 回火试炼（新游戏模式）

```gdscript
# scripts/autoload/trial_run.gd
enum Track { BOSS_RUSH, TIME_ATTACK, BARE_STEEL }
signal run_finished(result: Dictionary)
static func start(track: int, target_id: String) -> void
static func active() -> bool
static func abandon() -> void
# scripts/data/trial_catalog.gd  trials / unlock / rank thresholds / fixed loadouts
# scripts/data/trial_records.gd  独立 user://rustgrave_trials.cfg，version 1
```

规则：
- 战役 `SaveData` 在试炼中只读；解锁旗标 `trial_unlocked` 由战役写（`level07_done` 或任一结局）。
- 不播间幕/章节卡；Boss 名号保留；HUD 试炼条（时间/赛道/重试）。
- 暂停/退出/死亡重试/记录损坏回退全部有测试；三分辨率 + 触控导航。

---

## 6. 视觉/素材放置契约

- 装饰只能来自 `PropCatalog` 对应 theme 白名单；1× 整数缩放、接地、底边有像素。
- 每个新放置物件必须写清"用途 + 叙事锚点"；禁止无来由的孤立贴图/整块地形切图当装饰。
- 新素材：优先仓库已有包；新引入必须 CC0/兼容许可 + `assets/external/CREDITS.md`；派生必须 `tools/gen_*.py` 幂等可复现。
- 每章交付：5 节拍 × 3 分辨率接触表 + 自动审计（`chapter_art_audit_test`）+ Lead 亲查签字。
- 亮度：Play/Backdrop 亮度比 ≥1.15（沿用 `tools/peek_live.gd --layers` 测量口径）。

---

## 7. 分支、提交与合并

- 主线分支：`feature/campaign-v2`。teammate 不直接 commit；Lead 审 diff + 全量测试 + 渲染后提交。
- 外部线合并流程：rebase 到 `feature/campaign-v2` → 冲突逐文件决策 → 全量测试 + 14 章 walkthrough + loadout/trial smoke → 单 commit 合并。
- 禁止 `git add -A`/`git commit -a`；只 stage 明确文件；禁止 force push。
- 每完成一个完整改动 = 一个 commit；commit message 写清"改了什么/为什么/证据"。
