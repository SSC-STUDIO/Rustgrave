class_name NarrativeCatalog
extends RefCounted
## 《锈墓 Rustgrave》实时动态叙事与树状节点注册表（焚名轮回版）。
##
## 纯常量 + 纯静态查询叶子脚本，零 preload、零场景引用，供 NarrativeDirector、
## LiveVoiceBar、MapScreen、JournalScreen、DisobedienceTrigger、TruthFragmentPickup 共用。
##
## 四阶声线（对标《ICEY》实时动态旁白）：
##   · TONE_GUIDE ("伊尔")     暖金余烬框：顺从发光箭头推进或正常战斗时的温柔指引与战况点评。
##   · TONE_DOUBT ("伊尔？")   抖动暗琥珀框：无视箭头逆行、劈砍封印墙、原地挂机时的劝阻与找补。
##   · TONE_GLITCH ("司炉回声") 猩红裂纹框：强闯禁区时的编号串台（第48/49号柴薪）与清道夫围剿。
##   · TONE_TRUE ("真伊尔")    冷白魂光框：斩破禁区终端拾取【真名残片】时浮现的百年前原声残响。
##   · TONE_BOSS               首领 / 灰卫 / 残魂在战斗或谢幕时的实时台词。

const TONE_GUIDE := &"guide"
const TONE_DOUBT := &"doubt"
const TONE_GLITCH := &"glitch"
const TONE_TRUE := &"true_yir"
const TONE_BOSS := &"boss"

const SPEAKER_BY_TONE := {
	&"guide": "伊尔",
	&"doubt": "伊尔？",
	&"glitch": "司炉回声",
	&"true_yir": "真伊尔",
}

## 14 个大地图节点（8 主线节点 + 5 叛逆裂隙支线 + 1 隐藏真结局终章），
## 顺序与 GameContext.LEVEL_ORDER 及标题屏 14 盏灯笼 / 4 段刻度（0, 3, 7, 11）严格一一对应。
const NODE_ORDER: Array[String] = [
	"stage01", "branch01", "stage02",
	"branch02", "stage03", "branch03", "stage04",
	"stage04b", "stage05", "branch04", "stage06",
	"branch05", "stage07", "stage08_true",
]

const MAIN_SPINE: Array[String] = [
	"stage01", "stage02", "stage03", "stage04",
	"stage04b", "stage05", "stage06", "stage07",
]

const BRANCH_IDS: Array[String] = [
	"branch01", "branch02", "branch03", "branch04", "branch05",
]

const FRAGMENT_IDS: Array[String] = [
	"truth_1", "truth_2", "truth_3", "truth_4", "truth_5",
]

## 树状选关画布坐标归一化在 520×380 画布内，主线居中横向延展，5 条叛逆支线上下分叉，
## 真结局节点位于最右侧顶冠，由 5 枚残片与炉门共同汇聚。
const STAGE_NODES := {
	"stage01": {
		"number": "壹",
		"name": "腐液墓园",
		"kind": &"main",
		"act": &"awake",
		"theme": &"graveyard",
		"pos": Vector2(48.0, 190.0),
		"parents": [],
		"children": ["stage02", "branch01"],
		"main_next": "stage02",
		"unlock_flag": "",
		"done_flag": "stage01_done",
		"legacy_done_flag": "boss_dead",
		"objective": "顺着路标去炉座续火",
		"guide_note": "伊尔：火种快灭了。顺着箭头斩开刽子手，去炉座续火。",
		"truth_note": "西侧封坟裂墙与炉座灭芯背后，埋着前四十八具同款残骸。",
		"fork_hint": "?? 封坟西墙传来空响",
		"rooms": ["S1", "S2", "S3", "S4", "S5", "S6"],
		"boss_room": "S5",
	},
	"branch01": {
		"number": "裂·壹",
		"name": "废冢尸堆",
		"kind": &"branch",
		"act": &"awake",
		"theme": &"graveyard",
		"pos": Vector2(68.0, 316.0),
		"parents": ["stage01"],
		"children": ["stage08_true"],
		"main_next": "",
		"unlock_flag": "branch01_unlocked",
		"done_flag": "branch01_done",
		"fragment_id": "truth_1",
		"objective": "查验封坟墙后的弃骸",
		"guide_note": "伊尔？：那只是报废的旧铁壳，没什么好看的，快回正路。",
		"truth_note": "四十八具与你同模的空壳叠在坑底，胸口都刻着出厂炉号。",
		"fork_hint": "",
		"rooms": ["B1", "B2"],
		"boss_room": "",
	},
	"stage02": {
		"number": "贰",
		"name": "沉钟水渠",
		"kind": &"main",
		"act": &"awake",
		"theme": &"undercroft",
		"pos": Vector2(124.0, 190.0),
		"parents": ["stage01"],
		"children": ["stage03", "branch02"],
		"main_next": "stage03",
		"unlock_flag": "stage02_unlocked",
		"done_flag": "stage02_done",
		"legacy_done_flag": "level02b_done",
		"objective": "斩停回声，开闸放渣",
		"guide_note": "伊尔：借系核跃过水渠，别碰底下的排渣口。",
		"truth_note": "排渣底沟直通未涂装的灰铁试炼废槽。",
		"fork_hint": "?? 排渣底沟未封死",
		"rooms": ["S1", "S2", "S3", "S4", "S5", "S6"],
		"boss_room": "S6",
	},
	"branch02": {
		"number": "裂·贰",
		"name": "灰铁弃槽",
		"kind": &"branch",
		"act": &"doubt",
		"theme": &"industrial",
		"pos": Vector2(144.0, 68.0),
		"parents": ["stage02"],
		"children": ["stage08_true"],
		"main_next": "",
		"unlock_flag": "branch02_unlocked",
		"done_flag": "branch02_done",
		"fragment_id": "truth_2",
		"objective": "闯过清道夫的回收围剿",
		"guide_note": "司炉回声：第四十九号偏离路线，启动回收栅栏。",
		"truth_note": "所有苦难关卡都是批量的淬火流水线，只为逼人偶吞下更多魂火。",
		"fork_hint": "",
		"rooms": ["B1", "B2", "B3"],
		"boss_room": "",
	},
	"stage03": {
		"number": "叁",
		"name": "死城圣殿",
		"kind": &"main",
		"act": &"doubt",
		"theme": &"cathedral",
		"pos": Vector2(200.0, 190.0),
		"parents": ["stage02"],
		"children": ["stage04", "branch03"],
		"main_next": "stage04",
		"unlock_flag": "stage03_unlocked",
		"done_flag": "stage03_done",
		"legacy_done_flag": "level04b_done",
		"objective": "穿过圣殿，解放唱诗班",
		"guide_note": "伊尔：账本末页在地窖里，顺着长明灯往下走。",
		"truth_note": "圣殿穹顶吊灯之上，藏着封存原声母盘的司书暗阁。",
		"fork_hint": "?? 穹顶吊灯可借钩锁攀上",
		"rooms": ["S1", "S2", "S3", "S4", "S5"],
		"boss_room": "S5",
	},
	"branch03": {
		"number": "裂·叁",
		"name": "司书暗阁",
		"kind": &"branch",
		"act": &"doubt",
		"theme": &"cathedral",
		"pos": Vector2(220.0, 316.0),
		"parents": ["stage03"],
		"children": ["stage08_true"],
		"main_next": "",
		"unlock_flag": "branch03_unlocked",
		"done_flag": "branch03_done",
		"fragment_id": "truth_3",
		"objective": "听取暗阁里的原声母盘",
		"guide_note": "伊尔？：别听那些坏掉的旧蜡筒，那不是我的声音！",
		"truth_note": "剑里的温柔女声是剪接合成的牧火录音；真正的伊尔百年前就因砸炉被捕。",
		"fork_hint": "",
		"rooms": ["B1", "B2", "B3"],
		"boss_room": "",
	},
	"stage04": {
		"number": "肆",
		"name": "切槽工坊",
		"kind": &"main",
		"act": &"doubt",
		"theme": &"industrial",
		"pos": Vector2(272.0, 190.0),
		"parents": ["stage03"],
		"children": ["stage04b"],
		"main_next": "stage04b",
		"unlock_flag": "stage04_unlocked",
		"done_flag": "stage04_done",
		"legacy_done_flag": "level05_done",
		"objective": "杀穿淬火线，查验剑槽",
		"guide_note": "伊尔：工坊切开剑槽，只是为了让你借先人的手艺防身。",
		"truth_note": "切槽台铭牌写着：重剑凹槽实为抽干沿途亡魂余温的蓄火导轨。",
		"fork_hint": "",
		"rooms": ["S1", "S2", "S3"],
		"boss_room": "",
	},
	"stage04b": {
		"number": "伍",
		"name": "夜雨锻冢",
		"kind": &"main",
		"act": &"cast",
		"theme": &"graveyard",
		"pos": Vector2(332.0, 190.0),
		"parents": ["stage04"],
		"children": ["stage05"],
		"main_next": "stage05",
		"unlock_flag": "stage04b_unlocked",
		"done_flag": "stage04b_done",
		"legacy_done_flag": "level06_done",
		"objective": "突围冷雨群骸，抵达钟楼",
		"guide_note": "伊尔：哈伦的剑成了钟楼门闩。冲破雨夜尸群就到了。",
		"truth_note": "锻工哈伦与薇尔宁可折剑空葬，也不肯把真名送进死炉当柴烧。",
		"fork_hint": "",
		"rooms": ["S1", "S2", "S3"],
		"boss_room": "",
	},
	"stage05": {
		"number": "陆",
		"name": "无舌钟楼",
		"kind": &"main",
		"act": &"cast",
		"theme": &"belltower",
		"pos": Vector2(392.0, 190.0),
		"parents": ["stage04b"],
		"children": ["stage06", "branch04"],
		"main_next": "stage06",
		"unlock_flag": "stage05_unlocked",
		"done_flag": "stage05_done",
		"legacy_done_flag": "level07b_done",
		"objective": "下铸钟厅，夺取开门火钥",
		"guide_note": "伊尔：路标朝下！去铸钟厅打倒铸钟人，别往钟顶爬。",
		"truth_note": "无舌真钟顶锁着钟舌的真正去向：火种并非钥匙，而是自焚引信。",
		"fork_hint": "?? 钟井上方禁链松动",
		"rooms": ["S1", "S2", "S3", "S4"],
		"boss_room": "S4",
	},
	"branch04": {
		"number": "裂·肆",
		"name": "无舌钟顶",
		"kind": &"branch",
		"act": &"cast",
		"theme": &"belltower",
		"pos": Vector2(392.0, 68.0),
		"parents": ["stage05"],
		"children": ["stage08_true"],
		"main_next": "",
		"unlock_flag": "branch04_unlocked",
		"done_flag": "branch04_done",
		"fragment_id": "truth_4",
		"objective": "逆攀钟顶，查验无舌真钟",
		"guide_note": "司炉回声：警告！禁止接近钟顶引信校准台！",
		"truth_note": "所谓火种是用钟舌熔铸的高温雷管，一进炉门就会把持剑人偶连魂炸成炉灰。",
		"fork_hint": "",
		"rooms": ["B1", "B2", "B3"],
		"boss_room": "",
	},
	"stage06": {
		"number": "柒",
		"name": "熔渣城墙",
		"kind": &"main",
		"act": &"cast",
		"theme": &"ramparts",
		"pos": Vector2(452.0, 190.0),
		"parents": ["stage05"],
		"children": ["stage07", "branch05"],
		"main_next": "stage07",
		"unlock_flag": "stage06_unlocked",
		"done_flag": "stage06_done",
		"legacy_done_flag": "level09b_done",
		"objective": "翻越城墙，击败炉风先驱",
		"guide_note": "伊尔：杀光拦路的灰卫，顺着风口直走就是炉心门。",
		"truth_note": "不拔剑走过静默灰卫，或跃下断崖古厩，都能听见护门者的真心。",
		"fork_hint": "?? 断崖下方有战马旧厩",
		"rooms": ["S1", "S2", "S3", "S4", "S5"],
		"boss_room": "S5",
	},
	"branch05": {
		"number": "裂·伍",
		"name": "绝壁古厩",
		"kind": &"branch",
		"act": &"break",
		"theme": &"ramparts",
		"pos": Vector2(452.0, 316.0),
		"parents": ["stage06"],
		"children": ["stage08_true"],
		"main_next": "",
		"unlock_flag": "branch05_unlocked",
		"done_flag": "branch05_done",
		"fragment_id": "truth_5",
		"objective": "探访崖底古厩的战马鞍具",
		"guide_note": "伊尔？：崖底只有乱石，梦魇是疯掉的凶兽，别信它的旧鞍！",
		"truth_note": "梦魇正是真伊尔的坐骑；它死守炉门不是阻碍解脱，而是拦住被骗来送死的人偶。",
		"fork_hint": "",
		"rooms": ["B1", "B2"],
		"boss_room": "",
	},
	"stage07": {
		"number": "捌",
		"name": "炉心门前",
		"kind": &"main",
		"act": &"break",
		"theme": &"forge_core",
		"pos": Vector2(512.0, 232.0),
		"parents": ["stage06"],
		"children": ["stage08_true"],
		"main_next": "",
		"unlock_flag": "stage07_unlocked",
		"done_flag": "stage07_done",
		"legacy_done_flag": "game_complete",
		"objective": "迎战梦魇，在炉门前抉择",
		"guide_note": "伊尔：斩下梦魇，把剑推进炉心，一切就结束了。",
		"truth_note": "若未集齐五枚真名残片，无论还火或守炉，都只是第四十九次轮回骗局。",
		"fork_hint": "集齐 5 枚真名残片可唤醒归零母模",
		"rooms": ["S1", "S2", "S3"],
		"boss_room": "S2",
	},
	"stage08_true": {
		"number": "终",
		"name": "归零母模",
		"kind": &"true_end",
		"act": &"break",
		"theme": &"forge_core",
		"pos": Vector2(512.0, 108.0),
		"parents": ["branch01", "branch02", "branch03", "branch04", "branch05", "stage07"],
		"children": [],
		"main_next": "",
		"unlock_flag": "true_ending_unlocked",
		"done_flag": "true_ending_done",
		"objective": "越过俯首战马，斩碎炉约母模",
		"guide_note": "真伊尔：别把剑投进炉膛——举起它，连我的囚笼一起劈碎！",
		"truth_note": "五枚残片拼回真名。梦魇俯首让路，你斩断二百年牧火母模，带着自己的名字走出锈墓。",
		"fork_hint": "",
		"rooms": ["T1", "T2", "T3", "T4"],
		"boss_room": "T4",
	},
}

## 5 枚【真名残片】：每一枚对应一条禁区支线，既有真伊尔原声，也翻转人物/术语认知。
const TRUTH_FRAGMENTS := {
	"truth_1": {
		"index": 1,
		"branch_id": "branch01",
		"title": "真名残片·壹｜第四十九号胸牌",
		"summary": "你并非被偶然捡回的唯一遗骸，而是守炉流水线浇铸的第四十九具收火偶。",
		"voice_clip": "frag_1_true_yir",
		"line": "真伊尔：听见了吗？坑底躺着四十八个你。他们不是没撑到炉心——是走到炉心烧成了灰。",
	},
	"truth_2": {
		"index": 2,
		"branch_id": "branch02",
		"title": "真名残片·贰｜淬火试炼工单",
		"summary": "沿途关卡是被刻意排布的淬火槽，目的是逼迫人偶在厮杀中替重剑吞饱魂火。",
		"voice_clip": "frag_2_true_yir",
		"line": "真伊尔：空壳烧不旺死炉。长老们故意留着恶鬼拦路，好叫你的剑一路吃饱死人的火。",
	},
	"truth_3": {
		"index": 3,
		"branch_id": "branch03",
		"title": "真名残片·叁｜剪接牧火母盘",
		"summary": "剑中温柔指路的「伊尔」是守炉长老用百年前叛逃者嗓音剪接的牧火引导回声。",
		"voice_clip": "frag_3_true_yir",
		"line": "真伊尔：剑里那个温柔劝你送死的声音，是他们割下我的声带模子拼出来的假回声！",
	},
	"truth_4": {
		"index": 4,
		"branch_id": "branch04",
		"title": "真名残片·肆｜钟舌起爆图纸",
		"summary": "重剑里的火种根本不是放走亡魂的钥匙，而是引爆整把蓄火重剑的自焚雷管。",
		"voice_clip": "frag_4_true_yir",
		"line": "真伊尔：火种是起爆雷管！只要你把剑插进炉心，整把剑攒下的魂火就会连你一起炸进炉膛！",
	},
	"truth_5": {
		"index": 5,
		"branch_id": "branch05",
		"title": "真名残片·伍｜梦魇旧鞍铁誓",
		"summary": "战马梦魇死守炉门并非阻碍解脱，而是替被囚母模的真伊尔拦住每一个被骗来投炉的人偶。",
		"voice_clip": "frag_5_true_yir",
		"line": "真伊尔：我的老伙计守了两百年炉门，挨了四十八次剑，只是想拦住你们别往火坑里跳啊……",
	},
}

## 实时动态语音总表（全程不锁输入、不拉电影黑边，支持高优先级打断）。
## 字段：tone, speaker(可选覆盖), text(<=38字), hold(秒), priority(1常规 2劝阻 3串台/真名), interruptible
const VOICE_CLIPS := {
	# --- Stage 01 · 腐液墓园 ---
	"s1_r1_wake": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.8,
		"text": "醒了？我是伊尔，封在你背上的重剑里。跟着发光箭头往右走。",
	},
	"s1_r1_linger": {
		"tone": TONE_DOUBT, "priority": 2, "hold": 2.6,
		"text": "怎么站在原地发呆？火种快凉了，箭头在右边，别回头看西墙。",
	},
	"s1_r1_seal_hit_1": {
		"tone": TONE_DOUBT, "priority": 2, "hold": 2.3,
		"text": "别砍那面封坟墙！后面只是塌掉的废坑，浪费力气。",
	},
	"s1_r1_seal_hit_2": {
		"tone": TONE_DOUBT, "priority": 2, "hold": 2.3,
		"text": "住手——灰尘振落会呛灭剑芯的！听话，往右走！",
	},
	"s1_r1_seal_break": {
		"tone": TONE_GLITCH, "priority": 3, "hold": 2.8,
		"text": "啧……第四十九号出现逆行偏差。算了，别往坑底乱翻！",
	},
	"s1_r2_parry_hint": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.6,
		"text": "腐液池边的残魂会吐火弹，看准时机挥剑，能把火弹原路劈回去。",
	},
	"s1_r2_core_hint": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.6,
		"text": "那是窑匠留下的熔热核。嵌进剑槽，锈死的铁栅就会向你让路。",
	},
	"s1_r3_wave_start": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.4,
		"text": "墓道铁栅落下了！握紧重剑，清光它们门才会开！",
	},
	"s1_r3_wave_2": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.2,
		"text": "地底还有第二批！跳上高台避开冲撞，劈碎它们的骨盾！",
	},
	"s1_r3_clear": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.4,
		"text": "干得漂亮。看见亮起的路标了吗？炉座就在前面。",
	},
	"s1_r4_fork": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.5,
		"text": "在余烬巢歇口气吧。刽子手就在东门后守着炉座。",
	},
	"s1_r5_boss_intro": {
		"tone": TONE_BOSS, "speaker": "刽子手", "priority": 2, "hold": 2.6,
		"text": "又是提着空槽剑来的哑巴……滚回去，别再去喂那座假炉！",
	},
	"s1_r5_boss_phase": {
		"tone": TONE_GUIDE, "priority": 2, "hold": 2.4,
		"text": "别听他胡言乱语！他早被腐液烧疯了，趁他收斧硬直斩下去！",
	},
	"s1_r5_boss_down": {
		"tone": TONE_BOSS, "speaker": "刽子手", "priority": 2, "hold": 2.7,
		"text": "第四十九个……我还是没拦住……别信剑里的……",
	},
	"s1_r6_heart": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.8,
		"text": "他在说胡话。快走上炉座选「续火」，千万别选掐灭！",
	},

	# --- Branch 01 · 废冢尸堆 ---
	"b1_r1_enter": {
		"tone": TONE_DOUBT, "priority": 2, "hold": 2.8,
		"text": "你真的钻进来了……地上这些铁壳只是工坊的废品，快出去吧。",
	},
	"b1_r1_wave": {
		"tone": TONE_GLITCH, "priority": 3, "hold": 2.6,
		"text": "警报：个体闯入一号弃置坑。唤醒守坑骸骨，驱离第四十八……四十九号！",
	},
	"b1_r1_clear": {
		"tone": TONE_DOUBT, "priority": 2, "hold": 2.5,
		"text": "刚才是杂音串线了！前面没有路，别碰那块发光的碎铁片！",
	},
	"b1_r2_terminal": {
		"tone": TONE_DOUBT, "priority": 2, "hold": 2.6,
		"text": "求你了，别碰它……知道太多，你的魂火会不稳的。",
	},
	"frag_1_true_yir": {
		"tone": TONE_TRUE, "priority": 3, "hold": 3.4,
		"text": "听见了吗？坑底躺着四十八个你。他们不是没撑到炉心——是走到炉心烧成了灰。",
	},

	# --- Stage 02 · 沉钟水渠 ---
	"s2_r1_enter": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.6,
		"text": "炉座地底连着沉钟水渠。顺着水声往右走，钟门就在深处。",
	},
	"s2_r2_wave_start": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.3,
		"text": "苔水里爬出东西了——小心头顶俯冲的飞魔！",
	},
	"s2_r2_clear": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.3,
		"text": "剑槽比刚才更烫了。很好，继续顺箭头推进。",
	},
	"s2_r3_boss_intro": {
		"tone": TONE_BOSS, "speaker": "空钟", "priority": 2, "hold": 2.5,
		"text": "四十七……四十八……又来一口替死的新钟……",
	},
	"s2_r3_boss_down": {
		"tone": TONE_GUIDE, "priority": 2, "hold": 2.6,
		"text": "回声散了。捡起地上的钩锁系核，前面能拉住高处的铁环。",
	},
	"s2_r4_fork_guide": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.6,
		"text": "抬头看箭头！用钩锁拉上高台走上层桥，底下排渣口全是剧毒！",
	},
	"s2_r4_disobey_pit": {
		"tone": TONE_DOUBT, "priority": 3, "hold": 2.6,
		"text": "等等——你往哪跳？！箭头明明指着上面，底下根本没铺完布景！",
	},
	"s2_r5_wave_start": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.4,
		"text": "渠桥被盾卫封死了！绕背或者弹反飞弹破开防线！",
	},
	"s2_r5_clear": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.3,
		"text": "闸门就在眼前了，打倒守渠人就能升回地面。",
	},
	"s2_r6_boss_intro": {
		"tone": TONE_BOSS, "speaker": "守渠人", "priority": 2, "hold": 2.6,
		"text": "捞不完的断剑，擦不干的铭牌……你背上那把，也急着下渠吗！",
	},
	"s2_r6_boss_down": {
		"tone": TONE_BOSS, "speaker": "守渠人", "priority": 2, "hold": 2.6,
		"text": "闸开了……自己看清楚，渠底冲走的都是刻着真名的灰……",
	},

	# --- Branch 02 · 灰铁弃槽 ---
	"b2_r1_enter": {
		"tone": TONE_DOUBT, "priority": 2, "hold": 2.8,
		"text": "这里连壁灯都没装，只是工坊废弃的灰铁槽……快原路爬上去吧。",
	},
	"b2_r2_ambush": {
		"tone": TONE_GLITCH, "priority": 3, "hold": 3.0,
		"text": "警告：第四十九号脱离淬火动线！锁死试炼槽，投放三批清道夫强制销毁！",
	},
	"b2_r2_wave_2": {
		"tone": TONE_GLITCH, "priority": 3, "hold": 2.5,
		"text": "指令修正：留住重剑蓄火槽，只需拆碎持剑人偶的四肢！",
	},
	"b2_r2_clear": {
		"tone": TONE_DOUBT, "priority": 2, "hold": 2.7,
		"text": "咳……刚才信号被地底铁矿干扰了！我怎么可能派怪物杀你呢？",
	},
	"b2_r3_terminal": {
		"tone": TONE_DOUBT, "priority": 2, "hold": 2.5,
		"text": "那台工单机已经锈死了，别按开关，我们回水渠好不好？",
	},
	"frag_2_true_yir": {
		"tone": TONE_TRUE, "priority": 3, "hold": 3.4,
		"text": "空壳烧不旺死炉。长老们故意留着恶鬼拦路，好叫你的剑一路吃饱死人的火。",
	},

	# --- Stage 03 · 死城圣殿 ---
	"s3_r1_enter": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.6,
		"text": "死城里只剩发光的锈苔了。穿过前面广场，圣殿的门为你开着。",
	},
	"s3_r2_wave_start": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.4,
		"text": "街心游荡的残魂围上来了！别恋战，速战速决！",
	},
	"s3_r2_wave_3": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.3,
		"text": "最后一波！你的重剑吸收余温的速度越来越快了！",
	},
	"s3_r2_clear": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.2,
		"text": "广场肃清了，顺着右边的路标进圣殿中庭。",
	},
	"s3_r3_fork_guide": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.6,
		"text": "地窖暗门在右下角。千万别拿钩锁去拽穹顶的破吊灯，会塌的。",
	},
	"s3_r3_disobey_loft": {
		"tone": TONE_DOUBT, "priority": 3, "hold": 2.6,
		"text": "我都说了别往吊灯上爬！上面只有发霉的旧档案，快下来！",
	},
	"s3_r4_wave_start": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.3,
		"text": "地窖走廊有护殿教徒伏击，小心毒雾与幽影夹击！",
	},
	"s3_r5_boss_intro": {
		"tone": TONE_BOSS, "speaker": "无声唱诗班", "priority": 2, "hold": 2.6,
		"text": "（无声的嘴唇齐齐张合：假的声音……偷走了她的喉咙……）",
	},
	"s3_r5_boss_down": {
		"tone": TONE_GUIDE, "priority": 2, "hold": 2.7,
		"text": "她们终于解脱了。收下余烬核吧，在半空也能再踏出一步。",
	},

	# --- Branch 03 · 司书暗阁 ---
	"b3_r1_enter": {
		"tone": TONE_DOUBT, "priority": 2, "hold": 2.7,
		"text": "司书暗阁早就被长老查封了。听话，转身跳回中庭还来得及。",
	},
	"b3_r2_wave_start": {
		"tone": TONE_GLITCH, "priority": 3, "hold": 2.8,
		"text": "机密泄漏风险！唤醒暗阁禁卫——绝不许实验体接触声纹母盘！",
	},
	"b3_r2_clear": {
		"tone": TONE_GLITCH, "priority": 3, "hold": 2.6,
		"text": "杂音……滋……我是伊尔，我一直都在剑里陪着你呀……别推那扇门……",
	},
	"b3_r3_terminal": {
		"tone": TONE_GLITCH, "priority": 3, "hold": 2.7,
		"text": "停下！销毁录音母盘是重罪——我是说，那会伤到我的魂魄！",
	},
	"frag_3_true_yir": {
		"tone": TONE_TRUE, "priority": 3, "hold": 3.5,
		"text": "剑里那个温柔劝你送死的声音，是他们割下我的声带模子拼出来的假回声！",
	},

	# --- Stage 04 · 切槽工坊 ---
	"s4_r1_enter": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.7,
		"text": "这里是切槽工坊。你的重剑就是在这张铁台上切出凹槽的。",
	},
	"s4_r1_linger": {
		"tone": TONE_DOUBT, "priority": 2, "hold": 2.7,
		"text": "别盯着切槽台的铭牌看了……什么『魂火抽吸器』只是工匠的黑话而已。",
	},
	"s4_r2_wave_start": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.4,
		"text": "淬火车间的自动铁闸合上了！迎战失控的工坊守卫！",
	},
	"s4_r2_wave_2": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.3,
		"text": "漂亮！每一次挥砍都在让剑槽里的火种更饱满！",
	},
	"s4_r2_clear": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.4,
		"text": "车间大门开了。穿过前面的运渣出口就是夜雨锻冢。",
	},
	"s4_r3_exit": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.4,
		"text": "外面在下冷雨，抓紧剑柄，别让雨水浇冷了炉火。",
	},

	# --- Stage 04b · 夜雨锻冢 ---
	"s4b_r1_enter": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.7,
		"text": "锻工哈伦和薇尔埋在这里。他们的剑早就献给钟楼与炉心了。",
	},
	"s4b_r2_wave_start": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.5,
		"text": "雨雾里爬起了大批骸骨！守住墓园石阶，三波连战别退缩！",
	},
	"s4b_r2_wave_3": {
		"tone": TONE_BOSS, "speaker": "哈伦残响", "priority": 2, "hold": 2.6,
		"text": "宁拆铁剑作门闩……休教真名入死炉……持剑人，回头啊！",
	},
	"s4b_r2_clear": {
		"tone": TONE_DOUBT, "priority": 2, "hold": 2.5,
		"text": "雨声太大，你听错了。钟楼大门就在前面，快进去避雨吧。",
	},
	"s4b_r3_exit": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.4,
		"text": "拔掉门闩上的断剑，无舌钟楼在等你。",
	},

	# --- Stage 05 · 无舌钟楼 ---
	"s5_r1_enter": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.5,
		"text": "钟楼里的钟没有钟舌，却被地底炉风震得长鸣不止。",
	},
	"s5_r1_clear": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.3,
		"text": "底层净空了。前面的钟井中枢一定要看清路标。",
	},
	"s5_r2_fork_guide": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.7,
		"text": "箭头指着右下方的铸钟厅！钟顶锁链早就断了，绝对不许往上跳！",
	},
	"s5_r2_disobey_up": {
		"tone": TONE_GLITCH, "priority": 3, "hold": 2.7,
		"text": "站住！你用二段跳往钟顶爬干什么？！立刻降落回下层通道！",
	},
	"s5_r3_wave_start": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.4,
		"text": "熔炉长廊的护卫冲出来了，打穿他们就是铸钟厅！",
	},
	"s5_r4_boss_intro": {
		"tone": TONE_BOSS, "speaker": "铸钟人", "priority": 2, "hold": 2.7,
		"text": "我亲手熔了钟舌浇成雷管……你还敢背着炸药往炉门走？！",
	},
	"s5_r4_boss_down": {
		"tone": TONE_GUIDE, "priority": 2, "hold": 2.7,
		"text": "别信疯匠人的胡话！那是开门的钥匙，不是雷管。往熔渣城墙走吧。",
	},

	# --- Branch 04 · 无舌钟顶 ---
	"b4_r1_enter": {
		"tone": TONE_GLITCH, "priority": 3, "hold": 2.8,
		"text": "你为什么总要跟箭头作对？！第十二号和第三十一号也是在这儿摔碎的！",
	},
	"b4_r2_wave_start": {
		"tone": TONE_GLITCH, "priority": 3, "hold": 2.7,
		"text": "封锁钟顶风廊！护钟铁卫，把这具不听话的容器给我砸下去！",
	},
	"b4_r2_clear": {
		"tone": TONE_DOUBT, "priority": 2, "hold": 2.6,
		"text": "等一下……就算你看见了空钟壳，也改变不了炉约的……",
	},
	"b4_r3_terminal": {
		"tone": TONE_DOUBT, "priority": 2, "hold": 2.5,
		"text": "别看那张起爆图纸……求你了，当作什么都不知道不好吗？",
	},
	"frag_4_true_yir": {
		"tone": TONE_TRUE, "priority": 3, "hold": 3.5,
		"text": "火种是起爆雷管！只要你把剑插进炉心，整把剑攒下的魂火就会连你一起炸进炉膛！",
	},

	# --- Stage 06 · 熔渣城墙 ---
	"s6_r1_enter": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.6,
		"text": "走过浇铸池就是城墙。离炉心越近，你剑里的火就越亮。",
	},
	"s6_r2_wave_start": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.4,
		"text": "渣河铁桥封锁了！三波精锐骸骨，尽情挥剑吧！",
	},
	"s6_r2_clear": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.3,
		"text": "剑槽已经烧得发白了！再往前就是灰卫驻守的城墙。",
	},
	"s6_r3_command_kill": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.6,
		"text": "前面站着守墙灰卫。拔剑砍倒他，拿走他身上的余火！",
	},
	"s6_r3_mercy_pass": {
		"tone": TONE_BOSS, "speaker": "灰卫", "priority": 3, "hold": 2.8,
		"text": "……你收住了剑？四十九位行者里，你是第一个不杀守墙人的。",
	},
	"s6_r3_mercy_yir": {
		"tone": TONE_DOUBT, "priority": 2, "hold": 2.4,
		"text": "你干嘛放过他？少收一份魂火，炉温会不够的……啧，快走吧！",
	},
	"s6_r4_fork_guide": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.6,
		"text": "顺着平路往前冲！千万别往断崖缺口下面跳，底下没有路！",
	},
	"s6_r4_disobey_cliff": {
		"tone": TONE_GLITCH, "priority": 3, "hold": 2.6,
		"text": "疯了吗往断崖下跳？！禁止接触古马厩遗迹——给我回来！",
	},
	"s6_r5_boss_intro": {
		"tone": TONE_BOSS, "speaker": "炉风先驱", "priority": 2, "hold": 2.7,
		"text": "替我试一试你的剑吧——看你究竟是提线柴薪，还是破炉之人！",
	},
	"s6_r5_boss_down": {
		"tone": TONE_BOSS, "speaker": "炉风先驱", "priority": 2, "hold": 2.7,
		"text": "好剑……门后那匹老马守得太苦了，若有真相，替它解开缰绳……",
	},

	# --- Branch 05 · 绝壁古厩 ---
	"b5_r1_enter": {
		"tone": TONE_GLITCH, "priority": 3, "hold": 2.8,
		"text": "警告：个体已接近百年前叛逃者遗留物！立即调派悬崖清道夫拦截！",
	},
	"b5_r1_clear": {
		"tone": TONE_DOUBT, "priority": 2, "hold": 2.6,
		"text": "别再往前走了……那副旧马鞍早就烂透了，梦魇只是头疯兽而已……",
	},
	"b5_r2_terminal": {
		"tone": TONE_GLITCH, "priority": 3, "hold": 2.6,
		"text": "不许碰那块铁誓牌！否则牧火协议会彻底崩——滋——",
	},
	"frag_5_true_yir": {
		"tone": TONE_TRUE, "priority": 3, "hold": 3.5,
		"text": "我的老伙计守了两百年炉门，挨了四十八次剑，只是想拦住你们别往火坑里跳啊……",
	},
	"all_fragments_awake": {
		"tone": TONE_TRUE, "priority": 3, "hold": 3.8,
		"text": "五枚真名残片齐了！假回声锁不住我了——打开地图，来【归零母模】斩碎这座骗局！",
	},

	# --- Stage 07 · 炉心门前（表面结局线） ---
	"s7_r1_enter": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.7,
		"text": "终于到炉心门前了。把拦路的梦魇斩杀，把剑推进炉膛就圆满通关了。",
	},
	"s7_r1_enter_truth_ready": {
		"tone": TONE_TRUE, "priority": 3, "hold": 3.0,
		"text": "你已集齐五枚残片！随时可在地图切入【归零母模】，不必再受假结局摆布。",
	},
	"s7_r2_boss_intro": {
		"tone": TONE_BOSS, "speaker": "梦魇", "priority": 2, "hold": 2.6,
		"text": "（遍体鳞伤的铁马横在炉门前，嘶鸣着踏碎满地引路箭头！）",
	},
	"s7_r2_boss_down": {
		"tone": TONE_GUIDE, "priority": 2, "hold": 2.7,
		"text": "碍事的畜生终于倒了。快去推开炉心门，履行你的使命吧。",
	},
	"s7_r3_door": {
		"tone": TONE_GUIDE, "priority": 1, "hold": 2.7,
		"text": "站在门前做选择吧：还火入炉，或者留在门外替我守夜。",
	},

	# --- Stage 08 True · 归零母模（隐藏真结局终章） ---
	"s8_r1_enter": {
		"tone": TONE_GLITCH, "priority": 3, "hold": 2.9,
		"text": "严重违抗！第四十九号容器拒绝投炉！你怎么敢撕毁发光路标？！",
	},
	"s8_r1_true_reply": {
		"tone": TONE_TRUE, "priority": 3, "hold": 3.0,
		"text": "他不是第四十九号柴薪——他是握紧真名来砸碎你们炉膛的骑士！",
	},
	"s8_r2_nightmare_bow": {
		"tone": TONE_TRUE, "priority": 3, "hold": 3.1,
		"text": "看呐，梦魇认出我的声音了。它向你俯首让开了通往母模的禁门。",
	},
	"s8_r3_wave_start": {
		"tone": TONE_GLITCH, "priority": 3, "hold": 2.7,
		"text": "倾巢而出！司炉禁卫全员出击，把这具叛逆人偶熔成铁水！",
	},
	"s8_r3_clear": {
		"tone": TONE_TRUE, "priority": 3, "hold": 2.7,
		"text": "最后一道铁栅碎了！前面就是囚禁我与两百亡魂的司炉母模！",
	},
	"s8_r4_boss_intro": {
		"tone": TONE_GLITCH, "priority": 3, "hold": 3.0,
		"text": "没有炉约，锈墓就会陷入永夜！跪下，把你背上的火交出来！",
	},
	"s8_r4_boss_phase2": {
		"tone": TONE_TRUE, "priority": 3, "hold": 2.8,
		"text": "弹反它的牧火光球！把假回声的炮火劈回母模核心！",
	},
	"s8_r4_boss_phase3": {
		"tone": TONE_GLITCH, "priority": 3, "hold": 2.8,
		"text": "错误……编号溢出……我才是伊尔……不许斩断炉约——！",
	},
	"s8_r4_boss_down": {
		"tone": TONE_TRUE, "priority": 3, "hold": 3.2,
		"text": "母模碎了……两百年的假火终于熄了。走吧，推开那扇通往黎明的门！",
	},
}


static func has_node_id(node_id: String) -> bool:
	return STAGE_NODES.has(node_id)


static func node_spec(node_id: String) -> Dictionary:
	return (STAGE_NODES.get(node_id, {}) as Dictionary).duplicate(true)


static func clip_spec(clip_id: String) -> Dictionary:
	return (VOICE_CLIPS.get(clip_id, {}) as Dictionary).duplicate(true)


static func speaker_of_clip(clip_id: String) -> String:
	var spec: Dictionary = VOICE_CLIPS.get(clip_id, {})
	if spec.is_empty():
		return ""
	var override_who := String(spec.get("speaker", ""))
	if override_who != "":
		return override_who
	var tone: StringName = spec.get("tone", TONE_GUIDE)
	return String(SPEAKER_BY_TONE.get(tone, "伊尔"))


static func fragment_spec(fragment_id: String) -> Dictionary:
	return (TRUTH_FRAGMENTS.get(fragment_id, {}) as Dictionary).duplicate(true)


static func fragment_count(flags: Variant) -> int:
	if flags == null:
		return 0
	var count := 0
	for fid in FRAGMENT_IDS:
		if flags.has(fid):
			count += 1
	return count


static func all_fragments_collected(flags: Variant) -> bool:
	return fragment_count(flags) >= FRAGMENT_IDS.size()


static func is_node_unlocked(node_id: String, flags: Variant) -> bool:
	if not STAGE_NODES.has(node_id):
		return false
	if node_id == "stage01":
		return true
	if flags == null:
		return false
	var spec: Dictionary = STAGE_NODES[node_id]
	if node_id == "stage08_true":
		return flags.has("true_ending_unlocked") or all_fragments_collected(flags)
	var uflag := String(spec.get("unlock_flag", ""))
	if uflag != "" and flags.has(uflag):
		return true
	var dflag := String(spec.get("done_flag", ""))
	if dflag != "" and flags.has(dflag):
		return true
	var leg := String(spec.get("legacy_done_flag", ""))
	if leg != "" and flags.has(leg):
		return true
	# 主线节点在其前驱主线节点已通关时也自动视为解锁（兼容旧档与跳关存档）。
	if spec.get("kind", &"") == &"main":
		for parent_id in (spec.get("parents", []) as Array):
			if is_node_cleared(String(parent_id), flags):
				return true
	return false


static func is_node_cleared(node_id: String, flags: Variant) -> bool:
	if not STAGE_NODES.has(node_id) or flags == null:
		return false
	var spec: Dictionary = STAGE_NODES[node_id]
	var dflag := String(spec.get("done_flag", ""))
	if dflag != "" and flags.has(dflag):
		return true
	var leg := String(spec.get("legacy_done_flag", ""))
	if leg != "" and flags.has(leg):
		return true
	var fid := String(spec.get("fragment_id", ""))
	if fid != "" and flags.has(fid):
		return true
	return false
