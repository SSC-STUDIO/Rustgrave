# level07 钟楼：侧室与钟舌竖井

## 蓝图

```text
-1360                          钩锁顶龛：原守钟人碑
-1280                    G ↑ Crown / 巢 / 渣井门 ──→ 单向坠井
-1120       GalleryE / 巢 / 第三钟舌                   │
 -880   F ↑ GalleryD / 巢 / 旧钟架遭遇                  │
 -640                    E ↑ Summit / 巢 ←─────────────┘
 -400       GalleryC / 巢 / 第二钟舌 ── D ── 东守钟室遭遇
 -160   C ↑ GalleryB / 原中巢 / 压板 / 井中遭遇
   80  西练钟室 ← A ── GalleryA / 新巢 / 首遇钟舌 ── B ↑
  320             入口 / 原入口巢 → A ↑
```

保留 1600px 爬升、七台交替升降的节奏、camera_top=-1472 与顶板 -1440。宽度扩到 1600；楼板依旧是薄台，侧室有独立墙顶、空间与用途，不把一整段楼层填成实心。

## 区段与侧室

| 高度 / 范围 | 路线与玩法 | 遭遇 / 检查点 |
| --- | --- | --- |
| 320→80，x=64–1008 | LiftA 上船后可去西练钟室（64–352），读摆端后穿过钟舌拿 bone_amulet；或单跳去 GalleryA 的安全等候区，过第一主线摆锤再上 LiftB | 入口骸骨仍是单敌教学；原入口巢，新一层巢 |
| -160，x=480–912 | BellGatePlate 与原 GateDoor 接线保持；去西侧 LiftC 继续上行 | 一只喷吐者、幽魂与飞魔构成井中遭遇；原 Gallery 巢 |
| -400，x=480–1536 | GalleryC 主线钟舌；LiftD 底端向东跳进独立守钟室，可原路退回，失足落到下层固定台面 | 东室爆裂骸骨 / 幽魂 / 喷吐者，留退路；新增 C 层巢 |
| -640，x=1024–1536 | 扩宽旧 Summit 为落回平台；LiftE 接下一段 | 原 Summit 巢移到 1280，接住塔顶东侧坠井捷径 |
| -880→-1120，x=480–1008 | 旧钟架和分层敌人；LiftF / G 接力；第三钟舌不盖吊台端点 | 旧钟架骸骨与高层幽魂 / 飞魔构成第三遭遇；D / E 层各补一个巢 |
| -1280 / -1360 | Crown 扩到 x=1360；渣井出口仍去 level07b；HookUpper 支路读原 SteleNook | 原 Crown 巢；从 Crown 东缘落到 Summit 的单向捷径 |

## 硬约束与验收

- 稳定 Props 名：EmberNestEntry / Gallery / Summit / Crown，BellGatePlate / Door，SteleChain / Bell / Nook，Exit。主线只需单跳和吊台；Nook 仍要求钩锁；没有 Boss。故事和出口 flag / 下一章不变。
- 摆锤全部使用 `pendulum(..., {"skin":"clapper"})`。主线首遇与西练钟室各有 ≥48px 的危险区外等候台；首遇不进敌人唤醒 / 射程；摆锤包围区与吊台端点、全身上下船空间及巢分开。摆动本身持续可见，不增加无依据的周期预警参数。
- 巢按实际交替上升路线补齐，相邻路线折线长度目标 ≤1000px；四个旧名及新增巢都各跑六秒真实 AI 静止安全检查。
- 关卡测试验证：基本主线、全行程实体净空与真实骑士上下船、首遇安全等候 / 通过和实伤、侧室回程、坠井真实落地恢复、板门和存档路径、可选奖励及钩锁顶龛。
- 定向门禁：level07_layout、level_sanity（过滤 level07）、route_audit、chapter_progression、level_routing、level_weather、chapter_art_audit、prop_fit、chapter_support、parallax_backdrop；整合阶段统一全量。
- 两档 1280×720 / 1920×1080，覆盖入口、一层主线与西练钟室、中段与东守钟室、旧 Summit / 捷径落点、旧钟架与上层、Crown 与顶龛；逐张看图，固定机位不代替完整正常输入通关。
