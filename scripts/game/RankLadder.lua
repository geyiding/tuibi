-- ============================================================================
-- RankLadder.lua  超越阶梯：把“世界排名一路往上爬”拆成足够密的超越目标
--   · 22 档匿名财富阶层 + 63 位前 1000 真名富豪（来自 Billionaires，发技能点赏金）
--   · 36 位“身边人”路人角色（外卖骑手 → 三线城市打工人 → 二线白领 → 小公司老板 → 县城首富 …）
--     只做表现层超越演出，不改经济、不发技能点；阈值由世界排名反推财富，和实时排名完全一致
--   · 全部按财富阈值升序合并成一条阶梯，供顶栏实时排名 / 下一个目标进度条 / 超越演出使用
-- ============================================================================

local Billionaires = require("game/Billionaires")
local Number = require("game/Number")

local floor, max, min, log = math.floor, math.max, math.min, math.log

local RankLadder = {}

-- { 世界排名, 名称, 一句吐槽, 头像{skin, head, hair, hairCol, glasses, beard, outfit, outfitCol, prop} }
local RIVALS = {
    { 7.80e9, "幼儿园小朋友",       "我存钱罐里的硬币，被你一下推没了！",         { 1, "round",   "bob",   { 50, 36, 28 },  "none",    "none",     "tee",     { 120, 200, 255 }, "cola" } },
    { 6.90e9, "早餐店学徒",         "凌晨四点起来揉面，还没你推一下赚得多！",     { 3, "oval",    "buzz",  { 30, 30, 34 },  "none",    "none",     "polo",    { 240, 240, 236 }, "bag" } },
    { 5.92e9, "零花钱小学生",       "我攒了一学期的零花钱都没你推一下多！",       { 1, "round",   "bob",   { 40, 30, 24 },  "none",    "none",     "tee",     { 255, 120, 90 },  "cola" } },
    { 5.75e9, "街角煎饼摊大叔",     "加俩蛋都追不上你这掉币速度！",               { 3, "round",   "buzz",  { 30, 30, 34 },  "none",    "stubble",  "polo",    { 230, 230, 220 }, "bag" } },
    { 5.45e9, "外卖骑手小王",       "我一天跑 60 单，你点一下就超了？",           { 3, "oval",    "cap",   { 26, 26, 30 },  "none",    "none",     "jersey",  { 255, 200, 40 },  "phone" } },
    { 4.80e9, "工厂流水线普工",     "三班倒攒的工资，被你一台机器超了！",         { 3, "square",  "buzz",  { 34, 34, 38 },  "none",    "none",     "polo",    { 70, 110, 170 },  "gpu" } },
    { 4.30e9, "三线城市普通打工人", "朝九晚六供房贷，你这是在印钞吧？",           { 3, "oval",    "part",  { 30, 30, 34 },  "round",   "none",     "polo",    { 90, 100, 120 },  "phone" } },
    { 3.70e9, "县城奶茶店店员",     "一杯奶茶才赚两块，你一秒赚一杯店！",         { 1, "oval",    "long",  { 50, 34, 26 },  "none",    "none",     "tee",     { 255, 160, 190 }, "cola" } },
    { 3.20e9, "网约车司机",         "开了一整天车，不如你推一板金币！",           { 3, "square",  "buzz",  { 28, 28, 32 },  "shades",  "none",     "polo",    { 40, 40, 48 },    "car" } },
    { 2.65e9, "刚毕业的实习生",     "转正工资还没发，你已经甩我一条街了！",       { 1, "oval",    "swept", { 36, 30, 26 },  "rimless", "none",     "hoodie",  { 80, 140, 220 },  "phone" } },
    { 2.25e9, "二线城市白领",       "KPI 还没完成，排名先被你超了！",             { 3, "oval",    "part",  { 30, 30, 36 },  "rimless", "none",     "suit",    { 50, 64, 96 },    "phone" } },
    { 1.75e9, "小区便利店老板",     "收银机都不如你的推币机响得勤！",             { 3, "round",   "buzz",  { 40, 36, 34 },  "none",    "mustache", "polo",    { 200, 60, 50 },   "bag" } },
    { 1.40e9, "一线城市程序员",     "996 的年终奖，被你一个狂欢时刻追平了！",     { 2, "oval",    "wild",  { 30, 30, 34 },  "round",   "stubble",  "hoodie",  { 40, 44, 56 },    "gpu" } },
    { 1.15e9, "中学教导主任",       "这位同学，上课不许推币！……等等你多少名？",   { 3, "square",  "part",  { 60, 60, 64 },  "round",   "none",     "suit",    { 90, 80, 70 },    "window" } },
    { 7.60e8, "县城小饭馆老板",     "炒了一辈子菜，没见过这么香的金币雨！",       { 4, "round",   "buzz",  { 30, 30, 32 },  "none",    "stubble",  "polo",    { 240, 240, 236 }, "pig" } },
    { 6.20e8, "外企部门经理",       "季度汇报还没写完，你又往上蹿了！",           { 2, "angular", "part",  { 70, 56, 44 },  "rimless", "none",     "suit",    { 34, 42, 66 },    "window" } },
    { 4.10e8, "小公司老板",         "我画的饼还没烙熟，你已经数钱数到手软了！",   { 3, "round",   "swept", { 30, 30, 34 },  "none",    "none",     "suit",    { 70, 30, 40 },    "car" } },
    { 2.80e8, "网红美食博主",       "家人们，这台推币机比我的流量还猛！",         { 1, "oval",    "long",  { 120, 76, 40 }, "none",    "none",     "glam",    { 255, 110, 160 }, "mic" } },
    { 1.50e8, "连锁火锅店加盟商",   "十家店的流水，都没你这掉币声好听！",         { 3, "round",   "buzz",  { 34, 34, 36 },  "none",    "none",     "polo",    { 190, 30, 36 },   "pig" } },
    { 8.00e7, "城中村包租婆",       "收了十栋楼的租，还是被你超了！",             { 6, "round",   "curly", { 60, 40, 30 },  "round",   "none",     "glam",    { 160, 60, 120 },  "bag" } },
    { 4.20e7, "省会房产中介店长",   "这业绩我得管你叫一声老板！",                 { 3, "oval",    "swept", { 28, 28, 32 },  "none",    "none",     "suit",    { 30, 40, 80 },    "phone" } },
    { 2.60e7, "百万粉丝带货主播",   "三二一上链接！……你怎么比我卖得还快？",       { 1, "oval",    "long",  { 220, 180, 110 }, "none",  "none",     "glam",    { 240, 80, 120 },  "mic" } },
    { 1.20e7, "地级市建材老板",     "钢筋水泥堆成山，也没你的金币高！",           { 4, "square",  "buzz",  { 30, 30, 30 },  "shades",  "stubble",  "leather", { 40, 34, 30 },    "car" } },
    { 5.20e6, "上市公司高管",       "董事会还在开，你的排名已经超我了！",         { 2, "angular", "silver", { 200, 204, 210 }, "rimless", "none",   "suit",    { 26, 30, 46 },    "btc" } },
    { 3.40e6, "县城首富",           "全县城的生意加起来，都不如你这台机器！",     { 3, "round",   "part",  { 30, 30, 34 },  "none",    "mustache", "suit",    { 120, 30, 30 },   "car" } },
    { 1.70e6, "地级市首富",         "市里排第一有啥用，世界榜上被你超了！",       { 3, "square",  "swept", { 40, 40, 44 },  "shades",  "none",     "suit",    { 20, 24, 36 },    "car" } },
    { 7.00e5, "连锁超市董事长",     "全省的收银台一起响，也没你响得快！",         { 2, "round",   "silver", { 210, 214, 220 }, "rimless", "none",   "suit",    { 40, 80, 60 },    "bag" } },
    { 3.40e5, "私募基金合伙人",     "我的量化模型算不出你的爆率！",               { 2, "angular", "part",  { 80, 60, 40 },  "shades",  "none",     "suit",    { 24, 28, 40 },    "btc" } },
    { 1.60e5, "省会地产大亨",       "盖了半座城的楼，被你一台推币机超了！",       { 3, "square",  "bald",  { 0, 0, 0 },     "none",    "goatee",   "suit",    { 60, 40, 24 },    "crown" } },
    { 7.20e4, "独角兽创始人",       "估值吹了十轮，现金流还不如你！",             { 2, "oval",    "wild",  { 40, 30, 26 },  "vr",      "stubble",  "hoodie",  { 30, 30, 34 },    "rocket" } },
    { 3.30e4, "游戏公司老板",       "我做了一辈子游戏，没见过这么爽的掉币！",     { 3, "round",   "swept", { 30, 30, 34 },  "headset", "none",     "tee",     { 60, 40, 120 },   "steam" } },
    { 1.60e4, "上市集团董事长",     "敲钟那天都没你现在风光！",                   { 3, "square",  "silver", { 200, 200, 206 }, "none",  "none",     "royal",   { 120, 20, 40 },   "crown" } },
    { 7.50e3, "跨国航运巨头",       "全球的货轮加起来，运不完你的金币！",         { 2, "angular", "silver", { 220, 222, 226 }, "none",  "full",     "suit",    { 20, 34, 60 },    "rocket" } },
    { 3.80e3, "顶级对冲基金经理",   "我对冲了所有风险，唯独没对冲你！",           { 2, "oval",    "bald",  { 0, 0, 0 },     "shades",  "none",     "suit",    { 24, 24, 30 },    "btc" } },
    { 1.90e3, "全国商会会长",       "商会年会请你来当主讲嘉宾吧！",               { 3, "round",   "silver", { 210, 212, 216 }, "round", "none",     "royal",   { 140, 110, 30 },  "crown" } },
    { 1.15e3, "神秘隐形富豪",       "我低调了一辈子，还是被你翻出来了……",         { 5, "square",  "bald",  { 0, 0, 0 },     "shades",  "goatee",   "leather", { 18, 18, 22 },    "crown" } },
}

-- 世界排名 -> 达到该排名所需财富（CalcWorldRank 单调递减，二分求逆，结果与实时排名严格一致）
function RankLadder.WealthForRank(rank)
    if rank >= Billionaires.START_RANK then return 0 end
    local lo, hi = 0, 1e13
    for _ = 1, 90 do
        local mid = (lo + hi) * 0.5
        if Billionaires.CalcWorldRank(mid) <= rank then hi = mid else lo = mid end
    end
    return hi
end

-- 合并阶梯
RankLadder.LIST = {}
for i = 1, #Billionaires.LIST do
    local e = Billionaires.LIST[i]
    RankLadder.LIST[#RankLadder.LIST + 1] = {
        kind = "rank", entry = e, rank = e.rank, target = e.target,
        name = e.name, title = e.title, quote = e.quote,
    }
end
for _, src in ipairs(RIVALS) do
    local av = src[4]
    local entry = {
        rank = floor(src[1]), name = src[2], title = "身边的普通人", quote = src[3], isRealName = false,
        avatar = {
            skin = av[1], head = av[2], hair = av[3], hairCol = av[4], glasses = av[5], beard = av[6],
            outfit = av[7], outfitCol = av[8], prop = av[9], bgTier = 4,
        },
    }
    RankLadder.LIST[#RankLadder.LIST + 1] = {
        kind = "rival", entry = entry, rank = entry.rank, target = RankLadder.WealthForRank(entry.rank),
        name = entry.name, title = entry.title, quote = entry.quote,
    }
end
table.sort(RankLadder.LIST, function(a, b)
    if a.target ~= b.target then return a.target < b.target end
    return a.rank > b.rank
end)
RankLadder.COUNT = #RankLadder.LIST
RankLadder.RIVAL_COUNT = #RIVALS

--- 已越过的阶梯数（target <= wealth 的条目数）
function RankLadder.CountPassed(wealth)
    local w = tonumber(wealth) or 0
    local lo, hi = 0, RankLadder.COUNT
    while lo < hi do
        local mid = floor((lo + hi + 1) * 0.5)
        if RankLadder.LIST[mid].target <= w then lo = mid else hi = mid - 1 end
    end
    return lo
end

--- 世界排名精确到个位千分位：5,983,260,000 / 38,264,512 / 4,512
function RankLadder.FormatRank(rank)
    local r = max(1, floor((tonumber(rank) or 1) + 0.5))
    return Number.FormatExactInt(r)
end

--- 静态标签用的世界排名精确格式（同个位千分位，统一全链路视觉风格）
function RankLadder.FormatRankShort(rank)
    local r = max(1, floor((tonumber(rank) or 1) + 0.5))
    return Number.FormatExactInt(r)
end

return RankLadder
