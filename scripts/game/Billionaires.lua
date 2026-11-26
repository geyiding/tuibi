-- ============================================================================
-- Billionaires.lua  真实世界财富排名系统（80亿名起步 -> 全球前1000强真名榜）
--   · 全球前1000名之外（80亿 ~ 1001名）：仅显示匿名财富阶层里程碑与剪影徽章，无任何真人名字
--   · 全球前1000强之内（No.990 ~ No.1 马斯克）：严格参考 2026 Forbes 真实净资产（RMB，1 USD ≈ ¥7.2）
--   · CalcWorldRank(wealth) 实时根据全球真实财富分位对数插值计算玩家当前世界排名
-- ============================================================================

local floor, min, max, log = math.floor, math.min, math.max, math.log

local Billionaires = {}

Billionaires.START_RANK = 8000000000   -- 全球约 80 亿人，从最后一名起步
Billionaires.REAL_NAME_CUTOFF = 1000

-- 1. 全球前 1000 名之外的 22 档匿名财富阶层（参考瑞银/福布斯全球成人财富分布，严禁出现任何真名）
-- 字段：{ rank, target(¥), name, title, quote, prop, milestone }
local ANON_MILESTONES = {
    { 5000000000, 500,         "全球前50亿",   "初攒零钱起步",     "第一桶推币启动金到手，你的世界排名开始飙升！",               "bag",    false },
    { 4000000000, 3500,        "全球前40亿",   "小有积蓄新秀",     "推板稳健运作，甩开全球二十亿人！",                           "bag",    false },
    { 3000000000, 35000,       "全球前30亿",   "超越地球半数人口", "资产迈过全球中位数，正式站在地球财富上半区！",               "crown",  true  },
    { 2000000000, 120000,      "全球前20亿",   "都市稳健中产",     "自动化流水线成型，财富开始进入加速通道！",                   "car",    false },
    { 1000000000, 600000,      "全球前10亿",   "十亿俱乐部成员",   "正式跻身全球前十亿，离百万身价近在咫尺！",                   "crown",  true  },
    { 500000000,  1200000,     "全球前5亿",    "百万资产达标",     "身价破百万人民币，全自动推币进入爆金期！",                   "bag",    false },
    { 200000000,  3000000,     "全球前2亿",    "城市高净值精英",   "超越全球 96% 人口，印钞效率节节攀升！",                     "car",    false },
    { 100000000,  5000000,     "全球前1亿",    "亿人精英圈层",     "闯进地球前一亿名，百万美元大门就在眼前！",                   "crown",  false },
    { 58000000,   7200000,     "全球前5800万", "百万美元富翁",     "身价达 100 万美元，跻身全球顶尖 1% 财富梯队！",               "crown",  true  },
    { 20000000,   18000000,    "全球前2000万", "两千万资产新贵",   "多币联动持续爆发，IPO 声望与资产同步起飞！",                 "btc",    false },
    { 8000000,    36000000,    "全球前800万",  "五百万美元高净值", "跨越 500 万美元大关，成为跨城知名资本家！",                   "car",    false },
    { 2500000,    72000000,    "全球前250万",  "千万美元豪门",     "身价达 1000 万美元，全城霓虹皆为你亮灯！",                   "bag",    false },
    { 1000000,    150000000,   "全球前100万",  "亿万富翁俱乐部",   "杀入全球前一百万名！资产正式突破一亿元！",                   "crown",  true  },
    { 500000,     250000000,   "全球前50万",   "区域实业大亨",     "几亿流动资金奔涌，推币机堪比小型印钞厂！",                   "gpu",    false },
    { 250000,     360000000,   "全球前25万",   "超高净值 UHNW",    "达标 5000 万美元超高净值标准，资本巨轮启动！",               "rocket", false },
    { 100000,     620000000,   "全球前10万",   "地球十万强席位",   "超越地球 99.998% 人口，跻身全球十万强！",                     "crown",  false },
    { 50000,      1100000000,  "全球前5万",    "十亿级资本掌门",   "总资产破十亿人民币，金融圈开始流传你的名字！",               "btc",    false },
    { 20000,      2000000000,  "全球前2万",    "行业巨头资本鳄",   "身价二十亿，随时准备冲击全球万强席位！",                     "gpu",    false },
    { 10000,      3200000000,  "全球前1万",    "全球万强精英",     "跻身世界前一万名，福布斯雷达已经锁定你！",                   "crown",  false },
    { 5000,       5000000000,  "全球前5000",   "跨国财团掌舵人",   "五十亿资产在手，向十亿美元大关发起总攻！",                   "rocket", false },
    { 2800,       7200000000,  "全球前2800",   "十亿美元福布斯门槛","突破 10 亿美元大关！全球仅约 2800 人站在这里！",             "crown",  true  },
    { 1400,       16000000000, "全球前1400",   "叩响世界千强大门", "距离世界财富前 1000 强真名榜仅剩最后一步！",                 "rocket", false },
}

-- 2. 仅世界财富前 1000 强真名榜（63 位经核验的 2026 Forbes 全球真实富豪，从第 1 名降至第 990 名）
-- 字段：{ rank, target(RMB), name, title, quote, skin, head, hair, hairCol, glasses, beard, outfit, outfitCol, prop }
local REAL_TOP1000_DESCENDING = {
    { 1,   6.041e12, "马斯克",         "火星火箭造车世界首富", "糟糕！这人推币产值比星舰起飞还猛，快发射猎鹰追赶！",   2, "angular", "swept",  {48,34,24},   "shades",  "none",     "leather", {22,24,30},   "rocket" },
    { 2,   1.850e12, "拉里·佩奇",       "谷歌搜索联合创始人",   "搜遍全网亿万网页，也没搜到这么离谱的爆率！",           2, "oval",    "part",   {92,76,64},   "rimless", "stubble",  "hoodie",  {38,52,82},   "steam"  },
    { 3,   1.706e12, "谢尔盖·布林",     "谷歌极客联合创始人",   "这推币机的物理算法比我们的搜索排序还玄学！",           2, "angular", "swept",  {64,52,44},   "vr",      "stubble",  "tee",     {44,48,60},   "vr"     },
    { 4,   1.613e12, "杰夫·贝索斯",     "亚马逊与蓝色起源掌门", "连蓝色起源的推进器都追不上这波金币瀑布！",             2, "oval",    "bald",   {220,190,165},"shades",  "stubble",  "polo",    {30,44,68},   "rocket" },
    { 5,   1.598e12, "扎克伯格",       "Meta社交与AI霸主",     "连我花几百亿造的元宇宙金库都被他推空了？！",           1, "oval",    "curly",  {124,78,42},  "vr",      "none",     "tee",     {34,36,44},   "vr"     },
    { 6,   1.368e12, "拉里·埃里森",     "甲骨文云端夏威夷岛主", "买下一整座海岛也没他一台推币机印钞快！",               2, "square",  "part",   {210,214,220},"shades",  "goatee",   "suit",    {26,34,54},   "crown"  },
    { 7,   1.231e12, "阿尔诺",         "LVMH顶奢商业帝国",     "早知道卖包不如回家开一百台霓虹推币机！",               2, "angular", "silver", {215,218,225},"rimless", "none",     "suit",    {20,22,30},   "bag"    },
    { 8,   1.109e12, "黄仁勋",         "英伟达皮衣显卡AI教父", "就算把算力显卡全焊上去，也算不赢你这台神机！",         3, "oval",    "silver", {216,220,228},"rimless", "none",     "leather", {18,18,22},   "gpu"    },
    { 9,   1.073e12, "巴菲特",         "奥马哈可乐复利股神",   "握了一辈子可乐搞复利，还是输给了你的金币雨！",           2, "round",   "silver", {235,235,238},"round",   "none",     "suit",    {56,64,84},   "cola"   },
    { 10,  1.066e12, "奥特加",         "Zara快时尚商业大亨",   "门店每周上新款，不如你推币每秒掉一回奖！",             2, "square",  "silver", {200,204,210},"none",    "none",     "suit",    {42,46,56},   "bag"    },
    { 11,  1.051e12, "罗伯·沃尔顿",     "沃尔玛零售帝国长子",   "全美超市连夜盘点营业额，还没你推一分钟多！",           2, "round",   "silver", {220,222,228},"rimless", "none",     "suit",    {34,76,138},  "bag"    },
    { 12,  1.030e12, "吉姆·沃尔顿",     "全球超市家族掌门",     "全球上万家超市一起收银，竟没你掉币叮当响得快！",       2, "oval",    "silver", {214,218,224},"rimless", "none",     "polo",    {34,92,158},  "bag"    },
    { 13,  1.015e12, "迈克尔·戴尔",     "戴尔科技与算力巨头",   "当年宿舍装电脑都没你这台机器来钱爽快！",               2, "square",  "part",   {130,118,108},"none",    "none",     "suit",    {36,56,92},   "gpu"    },
    { 14,  9.648e11, "爱丽丝·沃尔顿",   "沃尔玛帝国女首富",     "私人美术馆里最耀眼的藏品，大概就是这堆金币吧！",       1, "oval",    "silver", {218,214,210},"round",   "none",     "glam",    {94,52,126},  "crown"  },
    { 15,  9.072e11, "史蒂夫·鲍尔默",   "微软前CEO·快船老板",   "Developers! 谁来把这台印钞机给我拆开研究研究！",     2, "round",   "bald",   {218,185,158},"none",    "none",     "polo",    {28,74,148},  "window" },
    { 16,  9.000e11, "卡洛斯·斯利姆",   "拉美电信万年首富",     "胡子都被震撼得翘起来了，推币竟能推成首富！",           3, "round",   "silver", {224,226,232},"none",    "mustache", "suit",    {48,44,40},   "phone"  },
    { 17,  8.064e11, "赵长鹏",         "加密资产行业传奇",     "4! 这波真实物理落币比任何虚拟币都硬核！",               3, "oval",    "buzz",   {28,28,32},   "none",    "none",     "hoodie",  {218,162,24},  "btc"    },
    { 18,  7.848e11, "迈克尔·布隆伯格", "彭博金融终端之王",     "终端 K 线全线拉红，唯有你的现金流直冲天际！",         2, "angular", "silver", {206,208,214},"none",    "none",     "suit",    {24,36,68},   "btc"    },
    { 19,  7.776e11, "比尔·盖茨",       "微软视窗与慈善巨匠",   "等等，我的财富系统怎么弹出蓝屏反超提示了？",           1, "round",   "part",   {154,132,102},"round",   "none",     "polo",    {52,78,128},  "window" },
    { 21,  7.178e11, "穆克什·安巴尼",   "印度信实炼油电信首富", "哪怕住在二十七层摩天豪宅里，也听见你掉币声了！",       4, "round",   "part",   {28,28,34},   "none",    "mustache", "royal",   {126,34,62},  "crown"  },
    { 22,  6.336e11, "孙正义",         "软银AI与芯片投资狂人", "看走眼这么多次，这台推币机绝对是百倍独角兽！",         3, "round",   "part",   {150,152,160},"rimless", "none",     "suit",    {32,38,54},   "rocket" },
    { 23,  6.048e11, "张一鸣",         "字节跳动算法首富",     "这台推币机一定是刷中了黄金流量的终极配方！",           3, "round",   "part",   {28,28,34},   "round",   "none",     "tee",     {42,48,64},   "phone"  },
    { 25,  5.184e11, "高塔姆·阿达尼",   "印度基建能源巨鳄",     "连修十座深水港，现金流都没你这前沿斜坡猛！",           4, "square",  "part",   {32,32,36},   "none",    "stubble",  "suit",    {40,50,74},   "bag"    },
    { 27,  4.572e11, "柳井正",         "优衣库全球快时尚教父", "全国男女老少穿我的基础款，全来围观你推金币！",         3, "angular", "silver", {192,196,204},"rimless", "none",     "suit",    {44,44,54},   "bag"    },
    { 29,  4.334e11, "钟睒睒",         "农夫山泉大自然搬运王", "一瓶水才赚几分钱，你这一推下来直接抵我一湖水！",       3, "square",  "buzz",   {44,44,50},   "none",    "none",     "polo",    {146,28,36},  "water"  },
    { 31,  3.888e11, "肯·格里芬",       "城堡投资华尔街做市王", "连拍卖来的真恐龙化石都要为你这金币瀑布让路！",       2, "square",  "silver", {202,206,214},"none",    "none",     "suit",    {24,40,78},   "bag"    },
    { 33,  3.708e11, "马化腾",         "腾讯社交与游戏帝国",   "充了那么多会员豆，居然全让你的推板推出来了！",         3, "oval",    "part",   {32,34,40},   "rimless", "none",     "suit",    {34,62,112},  "penguin"},
    { 35,  3.564e11, "曾毓群",         "宁德时代全球电池霸主", "把电池全充成狂欢能量槽，也没你掉币续航持久！",       3, "square",  "part",   {36,36,42},   "rimless", "none",     "suit",    {24,64,108},  "gpu"    },
    { 38,  3.312e11, "李嘉诚",         "百岁超人港岛商神",     "做生意的稳健哲学，在你这儿改名叫【疯狂连击】！",       3, "oval",    "bald",   {220,200,178},"round",   "none",     "suit",    {30,36,52},   "crown"  },
    { 42,  2.988e11, "埃里克·施密特",   "谷歌前掌门·AI投资巨鳄","看了这么多硬核 AI 论文，最狠的算法竟是前推板！",       2, "oval",    "silver", {216,220,226},"rimless", "none",     "suit",    {36,48,74},   "gpu"    },
    { 44,  2.880e11, "丁磊",           "网易游戏与黑猪掌柜",   "养了十万头精品黑猪，全让你的炸弹币炸懵了！",           3, "round",   "part",   {32,34,40},   "none",    "none",     "tee",     {144,32,32},  "pig"    },
    { 47,  2.772e11, "何享健",         "美的家电制造教父",     "夏天卖爆全城空调，凉风吹不散你台面金色热浪！",         3, "round",   "silver", {210,214,220},"none",    "none",     "polo",    {46,72,118},  "gpu"    },
    { 50,  2.628e11, "爱德华多·萨维林", "Meta联合创始人·狮城首富","早年在宿舍谈股权，真不如直接给你投一台推币机！",     2, "oval",    "part",   {42,34,28},   "none",    "none",     "suit",    {30,44,72},   "btc"    },
    { 54,  2.520e11, "彼得·蒂尔",       "PayPal与Palantir创投教父","《从0到1》应该改写成《从第80亿名推到世界首富》！",  2, "angular", "part",   {84,74,64},   "none",    "none",     "suit",    {26,32,48},   "rocket" },
    { 58,  2.412e11, "麦肯齐·斯科特",   "散财千亿慈善女王",     "刚准备捐掉百亿做慈善，转头榜单被你刷屏啦！",           1, "oval",    "long",   {128,84,48},  "none",    "none",     "glam",    {108,42,118}, "crown"  },
    { 64,  2.174e11, "黄峥",           "拼多多电商奇迹缔造者", "砍了亿万刀都没你按一下狂欢按钮爆出的钱多！",           3, "round",   "part",   {30,32,36},   "none",    "none",     "polo",    {176,34,42},  "bag"    },
    { 68,  2.124e11, "菲尔·奈特",       "耐克飞人球鞋老顽童",   "Just Push It! 连这句口号都被你推火了！",              2, "angular", "silver", {228,228,232},"shades",  "goatee",   "hoodie",  {34,34,38},   "ball"   },
    { 72,  2.052e11, "雷军",           "小米手机造车劳模",     "Are you OK? 刚造出新神车就被你推币直接超车了！",       3, "oval",    "part",   {30,30,36},   "none",    "none",     "tee",     {24,28,38},   "car"    },
    { 76,  2.002e11, "马云",           "阿里巴巴商业传奇",     "我对钱不感兴趣，但这推币掉满屏的样子实在太帅！",       3, "oval",    "swept",  {38,38,44},   "none",    "none",     "polo",    {28,88,66},   "bag"    },
    { 82,  1.922e11, "史蒂夫·科恩",     "华尔街量化对冲巨鲨",   "对冲模型全线爆表，谁把这台机器接进了交易所？",         2, "round",   "bald",   {226,192,166},"none",    "stubble",  "suit",    {28,44,68},   "btc"    },
    { 92,  1.692e11, "鲁珀特·默多克",   "全球传媒报业教父",     "头条新闻赶紧换！今日全球头版全是你的金币海啸！",       2, "angular", "silver", {228,230,234},"round",   "none",     "suit",    {44,44,54},   "mic"    },
    { 102, 1.476e11, "秦英林",         "牧原千亿养猪产业链王", "猪场自动化再高，也不及你全自动 14 连发射币机！",       3, "square",  "buzz",   {36,36,40},   "none",    "none",     "polo",    {52,88,54},   "pig"    },
    { 108, 1.426e11, "王传福",         "比亚迪新能源造车宗师", "我造的车全用上绿牌刀片，还是追不上你的印钞速！",       3, "square",  "part",   {34,34,40},   "none",    "none",     "suit",    {28,44,74},   "car"    },
    { 126, 1.282e11, "李书福",         "吉利沃尔沃汽车狂人",   "把海外超跑全买回来，加起来都不敌你的金库币！",       3, "round",   "part",   {34,34,38},   "none",    "none",     "suit",    {30,48,84},   "car"    },
    { 138, 1.210e11, "瑞·达利欧",       "桥水基金《原则》教父", "《原则》第零条：永远不要跟爆种的推币机做对！",       2, "angular", "silver", {224,226,232},"rimless", "none",     "suit",    {40,56,74},   "crown"  },
    { 150, 1.152e11, "王卫",           "顺丰极速物流巨擘",     "我快递最快半日达，你金币爆落是零点零一秒达！",       3, "square",  "buzz",   {32,32,36},   "none",    "none",     "polo",    {24,26,32},   "car"    },
    { 168, 1.080e11, "詹姆斯·戴森",     "无叶黑科技发明家",     "我吹了半辈子超级气流，也没把币吹进我袋里！",         2, "angular", "silver", {210,214,220},"none",    "none",     "polo",    {62,48,88},   "gpu"    },
    { 195, 9.720e10, "郭台铭",         "鸿海精密制造霸主",     "全自动化流水线再长，也不及你前推板效率高！",         3, "square",  "silver", {176,180,188},"none",    "none",     "suit",    {36,48,76},   "gpu"    },
    { 225, 8.500e10, "布莱恩·切斯基",   "爱彼迎共享住宿创始人", "全世界房源加起来，不如你台面上这几层金币挤！",       2, "oval",    "buzz",   {52,44,38},   "none",    "stubble",  "tee",     {34,42,58},   "bag"    },
    { 240, 8.280e10, "蔡崇信",         "阿里联合创始人·篮网老板","从买下篮球队那天起，都没见过这么顺的分流爆分！",    3, "oval",    "part",   {40,42,48},   "none",    "none",     "suit",    {30,34,46},   "ball"   },
    { 260, 7.920e10, "丹尼尔·埃克",     "Spotify流媒体首富",    "全球听众循环播放神曲，不如看你听币雨叮当响！",       2, "round",   "bald",   {226,192,166},"none",    "stubble",  "hoodie",  {28,112,62},  "mic"    },
    { 310, 7.340e10, "G胖·加布",       "Steam与Valve掌门",     "我依然数不到 3，但你的【3倍印钞】也太香了吧！",       2, "round",   "long",   {214,216,222},"round",   "silver",   "polo",    {24,28,34},   "steam"  },
    { 450, 5.110e10, "斯皮尔伯格",     "好莱坞票房造梦导演",   "下回大片不用做特效了，直接实拍你这金币海啸！",       2, "oval",    "silver", {224,226,232},"round",   "silver",   "polo",    {54,48,44},   "mic"    },
    { 460, 5.040e10, "唐纳德·特朗普",   "地产传媒加密大亨",     "Nobody pushes coins better than you, tremendous!",     1, "square",  "swept",  {232,194,94}, "none",    "none",     "suit",    {24,38,76},   "crown"  },
    { 490, 4.750e10, "帕维尔·杜罗夫",   "纸飞机加密通信创始人", "就算在纸飞机群里加密讨论，也瞒不住你的暴富！",         1, "angular", "swept",  {52,42,36},   "shades",  "stubble",  "tee",     {16,18,24},   "phone"  },
    { 510, 4.680e10, "马克·库班",       "创智赢家风投狂人",     "这台推币机是我见过最离谱的印钞生意，我投了！",       2, "oval",    "part",   {68,54,44},   "none",    "stubble",  "tee",     {28,58,108},  "ball"   },
    { 560, 4.460e10, "刘强东",         "京东自营物流掌柜",     "兄弟们，今晚全场加投的快递全给安排最高阶币！",       3, "square",  "part",   {32,32,36},   "none",    "none",     "suit",    {146,24,32},  "bag"    },
    { 620, 4.180e10, "蒂姆·斯威尼",     "虚幻引擎与Epic创始人", "这满屏 PBR 金属金币反射比光线追踪还耀眼！",         1, "oval",    "part",   {156,144,132},"round",   "none",     "polo",    {36,42,54},   "steam"  },
    { 700, 3.740e10, "乔治·卢卡斯",     "星战电影帝国之父",     "愿原力与金币永动核心同在，绝不断供！",               2, "round",   "silver", {226,228,232},"round",   "silver",   "polo",    {74,88,112},  "rocket" },
    { 780, 3.380e10, "迈克尔·乔丹",     "空中飞人体育首富",     "飞人滞空时间再久，也没你金库币落台惊艳！",           5, "round",   "bald",   {122,78,52},  "none",    "goatee",   "jersey",  {168,26,34},  "ball"   },
    { 850, 3.240e10, "里德·哈斯廷斯",   "网飞流媒体创始人",     "连一口气追十季热剧，都没看你这推币机掉币上头！",     2, "angular", "silver", {218,220,226},"none",    "silver",   "hoodie",  {148,22,28},  "mic"    },
    { 920, 2.950e10, "李彦宏",         "搜索与AI大模型舵手",   "问十遍大模型，答案依然是：继续升级自动射速！",       3, "oval",    "swept",  {30,30,36},   "none",    "none",     "suit",    {34,58,118},  "car"    },
    { 990, 2.450e10, "奥普拉·温弗瑞",   "全美脱口秀传媒女王",   "你也拿金币！他也拿金币！全场每人三枚彩虹币！",       5, "round",   "curly",  {36,28,28},   "round",   "none",     "glam",    {146,42,102}, "mic"    },
}

Billionaires.ANON_COUNT = #ANON_MILESTONES
Billionaires.TOP1000_COUNT = #REAL_TOP1000_DESCENDING
Billionaires.TOP1000_START_IDX = Billionaires.ANON_COUNT + 1
Billionaires.LIST = {}
local byRankMap = {}

-- 先装配 22 档匿名阶层（idx = 1..22）
for i, src in ipairs(ANON_MILESTONES) do
    local rank, target, name, title, quote, prop, isMile = src[1], src[2], src[3], src[4], src[5], src[6], src[7]
    local idx = #Billionaires.LIST + 1
    local bounty = max(120, floor(target * 0.06))
    local spBounty = isMile and 3 or 2
    local theme = (rank >= 1e6) and 1 or 2
    local entry = {
        id = idx,
        idx = idx,
        rank = rank,
        name = name,
        title = title,
        quote = quote,
        target = target,
        bounty = bounty,
        bonus = bounty,
        spBounty = spBounty,
        theme = theme,
        isRealName = false,
        milestone = (isMile == true),
        desc = string.format("%s（%s）— \"%s\"", name, title, quote),
        avatar = {
            anonymous = true,
            prop = prop,
            bgTier = (rank <= 1e4 and 2) or (rank <= 5.8e7 and 3) or 4,
        },
    }
    Billionaires.LIST[idx] = entry
    byRankMap[rank] = entry
end

-- 再按财富从低（No.990 ¥245亿）到高（No.1 马斯克 ¥6.04万亿）追加真名 1000 强
for j = #REAL_TOP1000_DESCENDING, 1, -1 do
    local src = REAL_TOP1000_DESCENDING[j]
    local rank, target, name, title, quote = src[1], src[2], src[3], src[4], src[5]
    assert(rank <= Billionaires.REAL_NAME_CUTOFF, "真名榜仅限全球前1000名: " .. tostring(name))
    local idx = #Billionaires.LIST + 1
    local bounty = max(1000, floor(target * 0.008))
    local isMilestone = (rank == 990 or rank == 102 or rank == 50 or rank == 23 or rank == 10 or rank == 5 or rank == 3 or rank == 2 or rank == 1)
    local spBounty = (rank <= 10 and 5) or (isMilestone and 4) or 2
    local entry = {
        id = idx,
        idx = idx,
        rank = rank,
        name = name,
        title = title,
        quote = quote,
        target = target,
        bounty = bounty,
        bonus = bounty,
        spBounty = spBounty,
        theme = 3,
        isRealName = true,
        milestone = isMilestone,
        desc = string.format("No.%d %s（%s）— \"%s\"", rank, name, title, quote),
        avatar = {
            anonymous = false,
            skin      = src[6],
            head      = src[7],
            hair      = src[8],
            hairCol   = src[9],
            glasses   = src[10],
            beard     = src[11],
            outfit    = src[12],
            outfitCol = src[13],
            prop      = src[14],
            bgTier    = (rank <= 10 and 1) or (rank <= 50 and 2) or (rank <= 200 and 3) or 4,
        },
    }
    Billionaires.LIST[idx] = entry
    byRankMap[rank] = entry
end

Billionaires.COUNT = #Billionaires.LIST
Billionaires.TOP1000_MIN_WEALTH = Billionaires.LIST[Billionaires.TOP1000_START_IDX].target

-- 严格递增校验
for i = 2, Billionaires.COUNT do
    local prev, cur = Billionaires.LIST[i - 1], Billionaires.LIST[i]
    assert(cur.target > prev.target, "财富阈值必须严格递增 idx=" .. i)
    assert(cur.rank < prev.rank, "世界排名必须严格递减 idx=" .. i)
end

-- 构建实时世界排名插值锚点曲线（0 元 = 第 80 亿名 -> No.1 马斯克 = ¥6.041万亿）
local WORLD_ANCHORS = {
    { w = 0,   r = Billionaires.START_RANK },
    { w = 30,  r = 6600000000 },
    { w = 100, r = 5650000000 },
}
for i = 1, Billionaires.ANON_COUNT do
    local e = Billionaires.LIST[i]
    WORLD_ANCHORS[#WORLD_ANCHORS + 1] = { w = e.target, r = e.rank }
end
WORLD_ANCHORS[#WORLD_ANCHORS + 1] = { w = 2.20e10, r = 1001 }
for i = Billionaires.TOP1000_START_IDX, Billionaires.COUNT do
    local e = Billionaires.LIST[i]
    WORLD_ANCHORS[#WORLD_ANCHORS + 1] = { w = e.target, r = e.rank }
end

function Billionaires.CalcWorldRank(wealth)
    local w = tonumber(wealth) or 0
    if w <= 0 then return Billionaires.START_RANK end
    local topA = WORLD_ANCHORS[#WORLD_ANCHORS]
    if w >= topA.w then return topA.r end

    -- 二分定位 w 所在的锚点区间 [lo, lo+1]
    local lo, hi = 1, #WORLD_ANCHORS - 1
    while lo < hi do
        local mid = floor((lo + hi + 1) * 0.5)
        if WORLD_ANCHORS[mid].w <= w then
            lo = mid
        else
            hi = mid - 1
        end
    end

    local a = WORLD_ANCHORS[lo]
    local b = WORLD_ANCHORS[lo + 1]
    if not b or w >= b.w then return (b and b.r) or a.r end
    if w == a.w then return a.r end

    local r
    if a.w <= 0 then
        local t = w / max(1, b.w)
        r = a.r - t * (a.r - b.r)
    else
        local t = log(w / a.w) / log(b.w / a.w)
        r = a.r * ((b.r / a.r) ^ t)
    end
    return max(b.r + 1, min(a.r, floor(r + 0.5)))
end

function Billionaires.IsInTop1000(wealth)
    return Billionaires.CalcWorldRank(wealth) <= Billionaires.REAL_NAME_CUTOFF
end

function Billionaires.GetByIdx(idx)
    return Billionaires.LIST[idx]
end

function Billionaires.GetByRank(rank)
    return byRankMap[rank]
end

return Billionaires
