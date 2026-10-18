class_name ChapterText
extends RefCounted
## Rustgrave 战役的**唯一剧情文本源**（contract §1.2；M1R4 最终可读性修订版）。
##
## 关卡 layout、开场分镜、第一章事件字幕、暂停菜单前情提要都从这里取字；改故事只改
## 这个文件 + docs/story.md（tests/chapter_text_test.gd 会逐字比对 docs 的「文本锚点」）。
##
## Canon（第五次盲测前冻结，不再改口径）：
##   · 时间线只有一条：炉约立约二百年（头一百年烧剑/名字）；一百年前炉心熄灭，最后一口火
##     封进残芯，守炉人把残芯放上炉座当灯芯、又点了一百年（灯一年比一年暗）；如今残芯快灭，
##     伊尔把名字封进核、把核从炉座取下嵌进你背上的剑，交给你带她回炉心问火。
##   · 残芯＝最后一枚核：剑是它的棺材；伊尔的名字封在里面。第一章：把剑里的残芯放回
##     炉座点亮（炉座只认点过的核；点过才能带走），再收回剑里带下去。
##   · 两种核分名：锈核=技能核（死人职称，捡到就嵌进剑槽借手艺）；残芯只指最后一枚核。
##   · 炉约＝誓约/账本；立誓的那批人叫守炉人（组织/人不叫炉约）。当年守炉人熔了钟舌铸残芯、
##     拆了哈伦的剑做门闩、把残芯当灯芯烧。
##   · 伊尔的动作都在「她把自己封进核之前」；玩家听到的是核里的回声。
##   · 「名字」=刻在剑上、被烧进铁里的死人名字；烧进去就回不来。
##   · 钥匙：炉心门认核不认人；残芯就是钥匙。门后先问火一句门才开，进去再选送剑/守火。
##   · 梦魇=不肯进炉的战马，炉心门的守卫；ch8/ch9 碑文先埋，ch12/13/14 各一句。
##   · 称呼只用「你 / 净化偶 / 锈墓（城）」；不出现未定义的旧称呼与设计术语（测试会拦）。
##
## 这个脚本必须是叶子节点：只要常量、没有 preload、不引用场景，避免 HUD 的
## PauseMenu → MapScreen → ChapterTitles → ChapterText 预加载链把关卡场景拖回加载图。
##
## 章号与 id 分离：存档/旗标永远用 id（level03_done），显示章号只在这里（14 章重编）。
## 长度纪律：醒来句 ≤30 字；目标 ≤16 字；碑文 ≤2 行 × 22 字；出口字幕 1–2 句；
## 前情 ≤40 字；开场每句 ≤22 字。

## 四幕。act id 供 StoryFlow / 文档 / 测试分组，name 只显示。
const ACTS: Array[Dictionary] = [
	{"id": &"awake", "name": "醒"},
	{"id": &"debt", "name": "债"},
	{"id": &"cast", "name": "铸"},
	{"id": &"forge", "name": "炉"},
]

const CHAPTERS := {
	"level01": {
		"number": "壹",
		"name": "腐液回廊",
		"act": &"awake",
		"objective": "把残芯放上炉座点亮",
		"wake": "炉座空着。伊尔把核从座上取下来了。",
		"exit_label": "",
		"exit_captions": ["核在背上剑里。炉座认点过的核：放上点亮，才准带走。", "点亮完收回剑里，炉座又暗了。带剑下去。"],
		"steles": [
			{"node": "SteleForge", "title": "炉约纪事 · 熔熄",
					"text": "残芯是最后一口火封成的核。一百年前炉心熄灭，守炉人放上炉座当灯芯，又点了一百年。"},
			{"node": "SteleCoolant", "title": "工坊遗训 · 腐液",
					"text": "腐液是淬剑用的。吃肺，也把记忆淬进剑里。"},
			{"node": "SteleExecutioner", "title": "刽子手的誓言",
					"text": "炉座是放核的座子：点过的核才能带下城。我守它；谁来点核，谁先被斩。"},
		],
		"boss_intro": "守 座 的 人",
		"recap": "她把快灭的残芯取下；你放回炉座点亮，才带回剑里。",
	},
	"level02": {
		"number": "贰",
		"name": "沉钟地窟",
		"act": &"awake",
		"objective": "停回声，从钟门出去",
		"wake": "钟声在你进门前停了。地窟里的是回声。",
		"exit_label": "钟门",
		"exit_captions": ["钟停了。你停的是回声——钟楼那口真钟还在响。",
				"渠在城上，炉心在城下；渠顶旧街通上城。"],
		"steles": [
			{"node": "SteleShaft", "title": "沉钟纪事 · 回声",
					"text": "地窟里的钟只是回声。真钟在钟楼，还在响。"},
			{"node": "SteleGallery", "title": "沉钟纪事 · 数",
					"text": "回声在数被送进炉的人。听见名字的人，就往下走。"},
		],
		"boss_intro": "钟 的 回 声",
		"recap": "你停住回声，往运渣渠走。",
	},
	"level02b": {
		"number": "叁",
		"name": "运渣水渠",
		"act": &"awake",
		"objective": "开闸，让渣退下去",
		"wake": "渣往低处退。上城的斜坡在闸后。",
		"exit_label": "渠闸门",
		"exit_captions": ["闸开了。渣往低处退，露出上城的斜坡。", "全城会重新想起怎么下来的——上城的窗里，锈苔亮得像人醒了。"],
		"steles": [
			{"node": "SteleSluice", "title": "水渠纪事 · 渠",
					"text": "渣里能捞出剑。每把剑上都刻着一个名字。"},
			{"node": "SteleCapstan", "title": "水渠纪事 · 闸",
					"text": "守渠人：闸不能开。开了，渣退回去，全城会重新想起怎么下来的。"},
		],
		"boss_intro": "守 渠 人",
		"recap": "你开了闸，顺着渣退出的斜坡回城。",
	},
	"level03": {
		"number": "肆",
		"name": "锈城街巷",
		"act": &"debt",
		"objective": "穿过死城，去圣殿",
		"wake": "窗里亮着的不是灯。是锈苔。",
		"exit_label": "圣殿门",
		"exit_captions": ["圣殿还亮着一盏守灯——炉座那盏已经暗了。", "灯下是炉约的账——去圣殿查它。你欠她一次问火。"],
		"steles": [
			{"node": "SteleWindow", "title": "锈城纪事 · 窗",
					"text": "炉灭那夜，人自己关门往下走。窗里亮的是锈苔。"},
			{"node": "SteleStair", "title": "锈城纪事 · 阶",
					"text": "没人赶他们。台阶朝下。灯还亮在圣殿里。"},
			{"node": "SteleTower", "title": "锈城纪事 · 塔",
					"text": "守灯的人先走了。守灯是另点的灯；炉座那盏，靠残芯亮了一百年。"},
		],
		"boss_intro": "",
		"recap": "你穿过死城，找到圣殿的守灯。",
	},
	"level04": {
		"number": "伍",
		"name": "圣殿中庭",
		"act": &"debt",
		"objective": "在灯下查炉约的账",
		"wake": "账还在灯下。你欠她一次问火。",
		"exit_label": "地窖暗门",
		"exit_captions": ["账本末页被撕走了。", "暗门通地窖。"],
		"steles": [
			{"node": "SteleCompact", "title": "圣殿铭 · 炉约",
					"text": "炉约二百年：头一百年烧剑，后一百年守炉人烧残芯撑灯。"},
			{"node": "StelePrice", "title": "炉约 · 灯",
					"text": "灯亮着。签过名的手成了灰。名字还刻在石上。"},
			{"node": "SteleVault", "title": "炉约 · 账",
					"text": "封进核之前，伊尔撕走了末页——她不想让守炉人看见。"},
		],
		"boss_intro": "",
		"recap": "账上写：头一百年烧剑，后一百年烧残芯撑灯。",
	},
	"level04b": {
		"number": "陆",
		"name": "圣殿地窖",
		"act": &"debt",
		"objective": "下地窖，找账本末页",
		"wake": "地窖里有人在唱。没有声音。",
		"exit_label": "工坊暗门",
		"exit_captions": ["末页是伊尔封进核前撕走的：把火还给炉，替名字问一句。",
				"工坊在暗门后。剑槽（接核的槽）在那里切开。"],
		"steles": [
			{"node": "SteleLedger", "title": "地窖纪事 · 末页",
					"text": "末页是伊尔封进核前撕走的：把火还给炉，替名字问一句。"},
			{"node": "SteleChoir", "title": "地窖纪事 · 唱诗",
					"text": "唱诗班的名字还在火里。火一还，她们就散了。"},
			{"node": "SteleYir", "title": "地窖纪事 · 伊尔",
					"text": "封进核之前，她把你从渣里捡回来，把核嵌进你背上的剑，点亮你。"},
		],
		"boss_intro": "无 声 唱 诗 班",
		"recap": "末页写着：替名字问火一句。",
	},
	"level05": {
		"number": "柒",
		"name": "齿轮工坊",
		"act": &"debt",
		"objective": "在工坊接上锈核，从渣道出去",
		"wake": "剑槽是剑上接核的槽。核从这里接上剑。",
		"exit_label": "运渣道",
		"exit_captions": ["运渣道通向雨里的墓园。", "土里埋着两个还叫得出名字的人。"],
		"steles": [
			{"node": "SteleQuench", "title": "工坊遗训 · 切",
					"text": "剑槽不是在剑上长出来的。是工坊切开的——剑在这里接上第一枚锈核。"},
			{"node": "SteleNook", "title": "工坊遗训 · 吊",
					"text": "吊索断过，接上还能用。人不是吊索。"},
			{"node": "SteleChain", "title": "工坊遗训 · 链",
					"text": "吊链每一环都曾有名字。名字离开人，留在铁上。"},
		],
		"boss_intro": "",
		"recap": "剑接上第一枚锈核。你回到地面。",
	},
	"level06": {
		"number": "捌",
		"name": "墓园夜雨",
		"act": &"cast",
		"objective": "查哈伦的剑为何成门闩",
		"wake": "哈伦空手入土。薇尔的剑自己走了。",
		"exit_label": "钟楼门",
		"exit_captions": ["钟楼在雨上面。真钟还在响。", "门闩是哈伦的剑。钟楼里还有守炉人的手笔。"],
		"steles": [
			{"node": "SteleHallen", "title": "墓志 · 哈伦",
					"text": "锻工哈伦，葬时无剑。守炉人拆了他的剑做门闩：钟楼要用喂过名字的铁。"},
			{"node": "SteleVeil", "title": "墓志 · 薇尔",
					"text": "锻工薇尔，剑走了，她留下。三把剑先去炉心问了。"},
			{"node": "SteleTree", "title": "墓志 · 战马",
					"text": "炉心有一匹不肯进炉的战马。守炉人没舍得杀，它就守在门口。"},
		],
		"boss_intro": "",
		"recap": "守炉人拆了哈伦的剑做门闩。你往钟楼去。",
	},
	"level07": {
		"number": "玖",
		"name": "钟楼",
		"act": &"cast",
		"objective": "上钟楼，找熔钟舌的地方",
		"wake": "真钟还在响。钟舌不在了。",
		"exit_label": "渣井门",
		"exit_captions": ["井道通到铸钟厅。", "熔钟舌的地方，在下面。"],
		"steles": [
			{"node": "SteleChain", "title": "守钟人 · 链",
					"text": "真钟没有钟舌，可它自己还在响：炉心的回声顶着它。链是吊钟的。"},
			{"node": "SteleBell", "title": "守钟人 · 舌",
					"text": "钟舌熔成最后一枚核，叫残芯。核里封着伊尔。你背上的回声是她。"},
			{"node": "SteleNook", "title": "守钟人 · 马",
					"text": "守钟人说，夜里有马蹄声往炉心去。那匹马不肯进炉。"},
		],
		"boss_intro": "",
		"recap": "守炉人熔了钟舌铸成残芯。你背上的回声是伊尔。",
	},
	"level07b": {
		"number": "拾",
		"name": "铸钟厅",
		"act": &"cast",
		"objective": "进铸钟厅，查钥匙的用法",
		"wake": "炉温没降过。当年守炉人在铸钥匙。",
		"exit_label": "井道门",
		"exit_captions": ["井道通到渣底。", "城墙在渣的另一头。"],
		"steles": [
			{"node": "SteleMold", "title": "铸钟纪事 · 模",
					"text": "钟模里浇过名字。活人站上模台，钟就有了声音。"},
			{"node": "SteleFounder", "title": "铸钟纪事 · 工",
					"text": "铸钟人把自己浇进钟。他说总得有人替钟说话。"},
			{"node": "SteleKey", "title": "铸钟纪事 · 钥",
					"text": "钥匙的用法：带核到炉心门前，门认核不认人。当年守炉人一直把它当灯芯烧。"},
		],
		"boss_intro": "铸 钟 人",
		"recap": "铸钟人倒下。钥匙就是残芯；门认核不认人。",
	},
	"level08": {
		"number": "拾壹",
		"name": "熔渣深渊",
		"act": &"cast",
		"objective": "从渣渊爬去城墙",
		"wake": "你在这里淬火。铁成了，你先锈了。",
		"exit_label": "城墙梯",
		"exit_captions": ["梯子往上是城墙。", "墙不挡人。它把炉风关在里面。"],
		"steles": [
			{"node": "SteleSlag", "title": "熔渣纪事 · 渣",
					"text": "你在这里淬火失败。铁成了，你先锈了。"},
			{"node": "SteleQuench", "title": "熔渣纪事 · 拼",
					"text": "封进核之前，伊尔从渣面上把你捡回去，把残芯嵌进你背上的剑，点亮你。"},
			{"node": "SteleVent", "title": "熔渣纪事 · 气",
					"text": "渣下还有风，从炉心漏出来。守炉人说：还火的人，自己也要进炉。"},
		],
		"boss_intro": "",
		"recap": "你走过自己锈掉的地方，往城墙去。",
	},
	"level09": {
		"number": "拾贰",
		"name": "锈城城墙",
		"act": &"forge",
		"objective": "翻墙挡炉风，走向风口",
		"wake": "这墙挡的是炉风。灰是守墙的人。",
		"exit_label": "城墙外",
		"exit_captions": ["翻过墙，风小了些。墙外是风口。", "钥匙在你背上。风口后面的崖道通向炉心门。"],
		"steles": [
			{"node": "SteleWall", "title": "城墙铭 · 挡",
					"text": "墙不挡人，挡炉风。灰是守过墙的人。"},
			{"node": "SteleWind", "title": "城墙铭 · 风",
					"text": "风里有铁锈和烧焦的油。墙下的灰，曾经会走路。"},
			{"node": "SteleEyrie", "title": "城墙铭 · 鹰",
					"text": "哨位空着。风替守墙人看路，把眼睛磨成灰。"},
		],
		"boss_intro": "",
		"recap": "你翻过城墙，往风口去。",
	},
	"level09b": {
		"number": "拾叁",
		"name": "炉风崖道",
		"act": &"forge",
		"objective": "穿过风口，到炉心门前",
		"wake": "风口后面是炉心。最后一个灰卫挡着。",
		"exit_label": "炉心门",
		"exit_captions": ["灰卫让开了。他说：替我看看火。", "炉心门就在下面。钥匙在你背上，那匹马在等你。"],
		"steles": [
			{"node": "SteleAsh", "title": "崖道纪事 · 灰",
					"text": "灰卫守的是门，不是城。他们早想让人去问一句。"},
			{"node": "SteleHerald", "title": "崖道纪事 · 先驱",
					"text": "最后那个灰卫把灰披在身上。他说：你过去，替我看看火该不该还。"},
			{"node": "SteleGate", "title": "崖道纪事 · 门",
					"text": "门下没有守卫。守门的是风。"},
		],
		"boss_intro": "最 后 一 个 灰 卫",
		"recap": "灰卫让开路。炉心门在风口下面。",
	},
	"level10": {
		"number": "拾肆",
		"name": "炉心深处",
		"act": &"forge",
		"objective": "到炉心门，问火再选",
		"wake": "梦魇守着炉心门。它守着最后一句回答；先问火，门才开。",
		"exit_label": "炉心门",
		"exit_captions": [],
		"steles": [
			{"node": "SteleNightmare", "title": "炉心铭 · 梦魇",
					"text": "梦魇是那匹不肯进炉的战马。它守着门；先问火一句，它才让开。"},
			{"node": "SteleCompact", "title": "炉心铭 · 炉约",
					"text": "钥匙开的是炉心门。先问火一句，门才开。炉约末条：把火还给炉，把锈还给铁，让城睡下。"},
			{"node": "SteleVigil", "title": "炉心铭 · 守",
					"text": "送剑：剑进炉，名字归火，你散成铁，城睡下。守火：留剑，名字还困着，你永留炉边。"},
		],
		"boss_intro": "梦 魇",
		"recap": "梦魇让开。门开了，里面是炉心和一个选择。",
	},
}

## 术语表（17 条）：第一次出现的专名必须在这里有白话解释；docs/story.md 同步。
const TERMS := {
	"炉约": "二百年前全城立的誓：把刻着名字的剑送进炉，换灯不灭。立誓的那批人叫守炉人。",
	"炉心": "城下那座烧铁的大炉膛。一百年前熄了，只剩热和灰。",
	"锈墓": "这座沉进岩层的城。炉灭之后一切慢慢长锈，所以叫锈墓。",
	"锈": "炉灭以后，本该在铁里循环的东西走不动了，结成锈。城和人都慢慢变成锈。",
	"净化偶": "守炉人造来刮锈的人偶，用废铁和死人的骨拼成。守炉人造过很多具；你是最后一具。",
	"锈核": "技能核：从死人剑上取下的职称——死者做过的行当。嵌进剑槽里，就借他一次手艺。",
	"残芯": "最后一枚核：守炉人熔了钟舌铸成它，把炉心最后一口火封进去。伊尔的名字也封在里面，它还是炉心门的钥匙。",
	"名字": "刻在剑上的死人名字。守炉人把名字当燃料烧进铁里，人就回不来。",
	"炉座": "放核的座子。只认点过的核：核在座上点亮，才能带走。",
	"剑槽": "剑上接核的槽。工坊切开它，锈核从这里嵌进剑。",
	"守灯": "守灯人另点的灯。它和炉座那盏不是同一盏；炉座那盏靠残芯亮。",
	"上城": "城的高处。渠顶旧街通上城，圣殿在上城。",
	"送剑": "把背上的剑推进炉心。名字和伊尔归火，你也散成铁，城睡下。",
	"守火": "把剑留下，自己守炉。火不答，名字还困着，你永留炉边。",
	"腐液": "淬剑用的冷却液。吃肺，也会把记忆淬进钢里。",
	"余烬巢": "还剩一口余火的巢。点亮它，你死一次还能在这里醒。",
	"灰卫": "守城墙的人。被炉风烧成灰以后，还在原地站着守。",
}

## 人物（8 条，一人一句）：盲测复述人物关系用；docs/story.md §3 同步。
const CAST := {
	"净化偶": "你。守炉人造过很多具刮锈人偶；你是最后一具，自己先锈透了。",
	"伊尔": "炉约最后一个守炉人。封进核之前她把你从渣里捡回来、把残芯嵌进剑、点亮你，只求被带到炉心问一次。",
	"刽子手": "守炉座的人。他发誓谁来点核谁先被斩，于是永远挡在点核的路上。",
	"守炉人": "立誓烧名字换灯的那批人。当年他们熔了钟楼钟舌、拆了哈伦的剑，铸出残芯。",
	"灰卫": "守门的卫队。他们守的不是城；他们早想让人去问火一句。",
	"哈伦": "锻工。剑被拆去做钟楼门闩，所以他空手入土。",
	"薇尔": "锻工。她的剑走了，她留下；三把剑先去炉心问了。",
	"梦魇": "那匹不肯进炉的战马。它守着炉心门的最后一句回答，有人问完才让开。",
}

## 三枚锈核第一次嵌进剑槽时各说一句（之后不再重复）。docs/story.md §8 同步。
const CORE_VOICE := {
	&"heat_forge": "窑匠：把火留在刃上。门会自己让开。",
	&"hookshot_tether": "系索匠：你很重。让世界过来。",
	&"ember_step": "余烬核：灰还能再跳一次。别问它从谁身上来。",
}
## 第一次捡到锈核时把「锈核 / 职称 / 剑槽」就地解释（盲测：第一次捡核就要懂）。
const FIRST_CORE_LINE := "这是锈核——死人的职称，他做过的行当；嵌进剑槽，借他一次手艺。"

## 开场（新游戏只播一次，可跳过，约 44 秒）。每个专名第一次出现就地解释，
## 并给足动机（她只求你带她问一次）、代价（还火的人要进炉）与另一条路的暗示（守火）。
const OPENING := {
	"situation": "剑先锈了。核里还有人。",
	"oath": "二百年前立誓：烧刻名的剑换灯。此誓叫炉约。",
	"keepers": "立誓的人叫守炉人。",
	"made": "守炉人造过很多具净化偶——刮锈的人偶。",
	"last_one": "你不是被选中的；你是最后一具，自己先锈透了。",
	"saved": "伊尔捡回你、点亮你，只求你带她问一次。",
	"echo": "回声是伊尔封进核之前说的话。",
	"names": "名字刻在剑上，烧进铁里，人就回不来。",
	"furnace": "炉心是城下的大炉膛，一百年前熄了。",
	"remnant": "残芯是熔钟舌铸的核，封着最后一口火。",
	"lamp": "最后一百年，灯靠残芯当灯芯。",
	"dim": "灯越来越暗。她把核从座上取下。",
	"anomaly": "钟响了一声。底下有人在数。",
	"cost": "还火的人要进炉：送剑散成铁，守火留成看守。",
	"goal": "带剑里的残芯到炉心，替名字问火一句。",
	"question": "这火该不该还？",
	"obstacle": "刽子手守着炉座。他发过誓。",
}

## 两个正篇结局 + 第一章提前离场。两结局都不背书「正确答案」：give 的回应听不真。
const ENDINGS := {
	"give": {
		"summary": "送剑：门开了，你把剑推进炉。火里的名字应了一声，你听不真是谁——像够了，也像别还。名字和伊尔都归火；核连着你的性命，你也散成铁，城终于睡下。",
		"lines": ["门开了。你把剑推进炉里。火里的名字应了一声——你听不真是谁。",
				"那声音像「够了」，也像「别还」。火稳了，伊尔和铁里的名字都归火。",
				"核连着你的性命。剑一进炉，你也散成铁。城终于睡下。 —— 锈墓・完 ——"],
	},
	"keep": {
		"summary": "守火：门开了，你没有把剑推进去，留下守火。火没有回答，城一直半醒，铁里的名字还困着；你永远走不了。",
		"lines": ["门开了。你没有把剑推进去，留下守火，一年一年地问。",
				"火没有回答。城一直半醒；铁里的名字还困着，伊尔的声音还在。",
				"你走不了。你成了炉边的看守。 —— 锈墓・完 ——"],
	},
	"snuff": {
		"summary": "熄灭残芯：核灭了，你没问到；你散成铁，城还睡着，名字没有答案。",
		"lines": ["你熄灭了残芯。核灭了，你没问到。",
				"你散成铁。城还睡着。",
				"铁里的名字没有答案。 —— 锈墓・完 ——"],
	},
}

## 第一章事件字幕（旧 Level01StoryBeats 里的硬编码文本）。
const EVENTS := {
	"boss_gate": "刽子手守着炉座——放核的座子。谁来点核，谁先被斩。",
	"boss_slain": "残芯还亮着。熄掉它，就再也问不到了。",
	"toxin": "腐液是淬剑用的。吃肺，也把记忆淬进剑里。",
	"parry": "打回去的是他们的火。锈被你炼过一次。",
}


static func has(id: String) -> bool:
	return CHAPTERS.has(id)


## 战役顺序，与 GameContext.LEVEL_ORDER 一致（测试逐项比对）。
static func order() -> Array[String]:
	var ids: Array[String] = []
	for id in GameContext.LEVEL_ORDER:
		if CHAPTERS.has(id):
			ids.append(id)
	return ids


static func index_of(id: String) -> int:
	return order().find(id)


static func acts() -> Array[Dictionary]:
	return ACTS.duplicate(true)


static func act_of(id: String) -> Dictionary:
	var entry: Dictionary = CHAPTERS.get(id, {})
	var act_id: StringName = entry.get("act", &"")
	for act in ACTS:
		if StringName(act["id"]) == act_id:
			return (act as Dictionary).duplicate(true)
	return {}


static func number_of(id: String) -> String:
	return String(CHAPTERS.get(id, {}).get("number", ""))


static func name_of(id: String) -> String:
	return String(CHAPTERS.get(id, {}).get("name", ""))


## "锈墓・<number> — <name>"。ChapterLevel.chapter_card() 依赖这个分隔符。
static func title_of(id: String) -> String:
	if not CHAPTERS.has(id):
		return ""
	return "锈墓・%s — %s" % [number_of(id), name_of(id)]


## "锈墓・<number>"（章节卡的副标题）。
static func subtitle_of(id: String) -> String:
	if not CHAPTERS.has(id):
		return ""
	return "锈墓・%s" % number_of(id)


static func wake_of(id: String) -> String:
	return String(CHAPTERS.get(id, {}).get("wake", ""))


static func objective_of(id: String) -> String:
	return String(CHAPTERS.get(id, {}).get("objective", ""))


static func exit_label_of(id: String) -> String:
	return String(CHAPTERS.get(id, {}).get("exit_label", ""))


static func exit_captions_of(id: String) -> PackedStringArray:
	return PackedStringArray(CHAPTERS.get(id, {}).get("exit_captions", []))


static func steles_of(id: String) -> Array:
	return (CHAPTERS.get(id, {}).get("steles", []) as Array).duplicate(true)


## 按节点名取碑文（layout 的 stele() 位置常量留在 layout 里，文本从注册表取）。
static func stele_of(id: String, node_name: String) -> Dictionary:
	for entry in steles_of(id):
		if String(entry.get("node", "")) == node_name:
			return entry
	return {}


static func recap_of(id: String) -> String:
	return String(CHAPTERS.get(id, {}).get("recap", ""))


static func boss_intro_of(id: String) -> String:
	return String(CHAPTERS.get(id, {}).get("boss_intro", ""))


static func endings() -> Array[String]:
	var ids: Array[String] = []
	for kind in ENDINGS:
		ids.append(String(kind))
	ids.sort()
	return ids


static func ending_lines_of(kind: String) -> PackedStringArray:
	var entry: Dictionary = ENDINGS.get(kind, {})
	return PackedStringArray(entry.get("lines", []))


static func ending_summary_of(kind: String) -> String:
	return String(ENDINGS.get(kind, {}).get("summary", ""))


static func terms() -> Array[String]:
	var names: Array[String] = []
	for term in TERMS:
		names.append(String(term))
	names.sort()
	return names


static func term_of(term: String) -> String:
	return String(TERMS.get(term, ""))


static func cast_names() -> Array[String]:
	var names: Array[String] = []
	for name in CAST:
		names.append(String(name))
	names.sort()
	return names


static func cast_of(name: String) -> String:
	return String(CAST.get(name, ""))


## 开场字幕，按分镜顺序。每个专名第一次出现就地解释；动机、代价与另一条路的暗示都在。
static func opening_lines() -> Array[String]:
	return [
		String(OPENING["situation"]),
		String(OPENING["oath"]),
		String(OPENING["keepers"]),
		String(OPENING["made"]),
		String(OPENING["last_one"]),
		String(OPENING["saved"]),
		String(OPENING["echo"]),
		String(OPENING["names"]),
		String(OPENING["furnace"]),
		String(OPENING["remnant"]),
		String(OPENING["lamp"]),
		String(OPENING["dim"]),
		String(OPENING["anomaly"]),
		String(OPENING["cost"]),
		String(OPENING["goal"]),
		String(OPENING["question"]),
		String(OPENING["obstacle"]),
	]


static func event_line(key: String) -> String:
	return String(EVENTS.get(key, ""))


## 已通关章节的 recap（暂停菜单「前情提要」用最近两条）。done_flags 由
## StoryFlow 给（旗标口径跟着存档走），这里只负责挑文本。
static func recap_lines_for(cleared_ids: Array) -> Array[String]:
	var out: Array[String] = []
	for raw in cleared_ids:
		var line := recap_of(String(raw))
		if line != "" and not out.has(line):
			out.append(line)
	return out


## 给 docs 同步测试用：把所有会被玩家读到的长文本收在一起。
static func all_prose() -> Array[String]:
	var out: Array[String] = []
	for id in order():
		out.append(wake_of(id))
		out.append(objective_of(id))
		out.append(recap_of(id))
		for caption in exit_captions_of(id):
			out.append(String(caption))
		for stele in steles_of(id):
			out.append(String(stele.get("title", "")))
			out.append(String(stele.get("text", "")))
	for term in TERMS:
		out.append(String(TERMS[term]))
	for name in CAST:
		out.append(String(CAST[name]))
	for line in opening_lines():
		out.append(line)
	for kind in ENDINGS:
		for line in ending_lines_of(String(kind)):
			out.append(String(line))
	return out
