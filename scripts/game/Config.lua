-- ============================================================================
-- Config.lua  全局数值、物理、币种、进化、协同、遗物、战役与难度唯一配置源
-- ============================================================================

local Config = {}

Config.GAME_TITLE = "推币机的狂欢"
Config.WORLD_W = 360
Config.WORLD_H = 600
Config.PIXEL = 2

-- 舞台几何常量（WORLD_W=360, WORLD_H=600）
Config.STAGE = {
    -- 上部落币钉阵区
    SLOT_LEFT = 56,
    SLOT_RIGHT = 304,
    SLOT_TOP = 16,
    SLOT_BOTTOM = 238,
    LAUNCHER_X = 180,
    LAUNCHER_Y = 30,
    LAUNCH_SWING_DEG = 40,
    LAUNCH_SPEED = 270,
    GRAVITY = 520,
    PEG_RADIUS = 5.0,
    COIN_RADIUS = 12.0,
    MINI_RADIUS = 8.4,
    GIANT_RADIUS = 17.5,

    -- 中奖门（与发射口同周期锁相）
    GATE_Y = 216,
    GATE_CYCLE = 2.45,
    GATE_TRAVEL = 74,
    GATE_BASE_HALF = 19,
    GATE_DOOR_W = 24,
    GATE_DOOR_H = 10,

    -- 2.5D 梯形推台区
    DECK_TOP_Y = 238,
    DECK_TOP_HALF = 116,
    DECK_BOT_Y = 540,
    DECK_BOT_HALF = 160,
    SIDE_GAP_Y = 462,     -- y in [462, 540] 两侧开放侧漏缝
    PUSHER_Y_MIN = 256,
    PUSHER_Y_MAX = 336,
    PUSHER_CYCLE = 2.8,
    FRONT_DROP_Y = 542,
    DROP_END_Y = 576,

    -- 性能硬上限
    MAX_COINS = 140,
    STUCK_FUSE_SEC = 3.2,
    SEED_COUNT = 96,
}

-- 基础规则常量
Config.RULES = {
    START_HEARTS = 5,
    MAX_HEARTS = 8,
    START_TICKETS = 24,
    BASE_AMMO_PER_LEVEL = 20,
    COMBO_WINDOW = 4.2,
    FEVER_DURATION = 8.0,
    FEVER_RAIN_COUNT = 16,
    FEVER_SPEED_MUL = 1.75,
    FEVER_MULT_BOOST = 2.0,
    BASE_CRIT_CHANCE = 0.12,
    BASE_CRIT_MULT = 2.0,
    INTEREST_STEP = 25,
    INTEREST_BONUS = 5,
    INTEREST_CAP = 15,
}

-- 特殊钉子定义
Config.PEG_TYPES = {
    normal = { id = "normal", name = "霓虹钉", col = { 100, 210, 255 }, chips = 6, mult = 0 },
    mult   = { id = "mult",   name = "倍增钉", col = { 255, 210, 60 },  chips = 12, mult = 0.25 },
    split  = { id = "split",  name = "分流钉", col = { 110, 245, 160 }, chips = 10, mult = 0.1 },
    bolt   = { id = "bolt",   name = "高压钉", col = { 190, 130, 255 }, chips = 15, mult = 0.15 },
    fever  = { id = "fever",  name = "狂欢钉", col = { 255, 90, 175 },  chips = 10, mult = 0.12, fever = 4 },
}

-- 6 大家族定义（2 / 4 / 6 档协同）
Config.FAMILIES = {
    wealth  = { id = "wealth",  name = "财富", icon = "coin",   col = { 255, 210, 64 },
        t2 = "掉落筹码+25%", t4 = "掉落+60% 利息上限+10", t6 = "每跌落必掉1金券" },
    blast   = { id = "blast",   name = "爆破", icon = "bomb",   col = { 255, 110, 64 },
        t2 = "爆炸范围+25%", t4 = "爆炸+0.8倍率", t6 = "爆炸触发二次余震" },
    chain   = { id = "chain",   name = "连锁", icon = "bolt",   col = { 110, 220, 255 },
        t2 = "闪电额外+1跳", t4 = "电弧暴击且+0.4倍率", t6 = "过门触发5道落雷" },
    swarm   = { id = "swarm",   name = "倾泻", icon = "split",  col = { 110, 245, 150 },
        t2 = "分裂生成+1枚", t4 = "子币倍率+25%", t6 = "投币35%双连发" },
    gravity = { id = "gravity", name = "聚能", icon = "magnet", col = { 186, 136, 255 },
        t2 = "侧漏保护+25%", t4 = "吸币附带筹码爆分", t6 = "推板伸出震荡波" },
    fever   = { id = "fever",   name = "狂欢", icon = "star",   col = { 255, 96, 186 },
        t2 = "狂欢充能+25%", t4 = "狂欢延长+3秒", t6 = "狂欢掉落倍率+0.5" },
}
Config.FAMILY_ORDER = { "wealth", "blast", "chain", "swarm", "gravity", "fever" }
Config.SYNERGY_TIERS = { 2, 4, 6 }

-- 16 种基础/稀有/传说币 + 6 种进化传说币
-- 字段统一：id, name, short, rarity(common|rare|epic|legendary), family, baseChips, multAdd,
-- massMul, radiusMul, restitution, feverGain, desc, color{base,dark,light,rim,glow}, symbol
Config.COINS = {
    gold = {
        id = "gold", name = "标准金币", short = "金币", rarity = "common", family = "wealth",
        baseChips = 45, multAdd = 0.2, massMul = 1.0, radiusMul = 1.0, restitution = 0.56, feverGain = 6,
        ticketBonus = 1, desc = "掉落基础45筹码，必额外产出1金券。",
        color = { base = { 248, 196, 48 }, dark = { 164, 108, 18 }, light = { 255, 242, 168 }, rim = { 255, 226, 100 }, glow = { 255, 210, 70 } },
        symbol = "yen",
    },
    emerald = {
        id = "emerald", name = "幸运翡翠", short = "翡翠", rarity = "common", family = "fever",
        baseChips = 35, multAdd = 0.6, massMul = 1.0, radiusMul = 1.0, restitution = 0.58, feverGain = 10,
        gateRefund = 2, desc = "过中奖门返+2投币，掉落倍率+0.6。",
        color = { base = { 66, 218, 138 }, dark = { 24, 128, 76 }, light = { 172, 255, 208 }, rim = { 110, 245, 175 }, glow = { 80, 240, 160 } },
        symbol = "clover",
    },
    split = {
        id = "split", name = "分裂子母", short = "分裂", rarity = "common", family = "swarm",
        baseChips = 30, multAdd = 0.25, massMul = 0.95, radiusMul = 1.0, restitution = 0.6, feverGain = 6,
        splitCount = 2, desc = "首撞钉阵裂出2枚小银币同时落台。",
        color = { base = { 96, 224, 188 }, dark = { 34, 130, 108 }, light = { 196, 255, 240 }, rim = { 140, 246, 220 }, glow = { 110, 245, 210 } },
        symbol = "split",
    },
    heavy = {
        id = "heavy", name = "重锤铁币", short = "重锤", rarity = "common", family = "gravity",
        baseChips = 70, multAdd = 0.3, massMul = 2.4, radiusMul = 1.18, restitution = 0.36, feverGain = 7,
        pushPower = 1.5, desc = "大号重体强行碾开币堆，掉落70筹码。",
        color = { base = { 136, 152, 186 }, dark = { 66, 76, 104 }, light = { 214, 226, 248 }, rim = { 176, 194, 226 }, glow = { 160, 180, 225 } },
        symbol = "anvil",
    },
    thunder = {
        id = "thunder", name = "霹雳电币", short = "霹雳", rarity = "common", family = "chain",
        baseChips = 40, multAdd = 0.35, massMul = 1.0, radiusMul = 1.0, restitution = 0.6, feverGain = 8,
        chainJumps = 3, desc = "落台或掉落放出3道闪电连锁加分。",
        color = { base = { 76, 198, 255 }, dark = { 26, 104, 172 }, light = { 188, 242, 255 }, rim = { 132, 224, 255 }, glow = { 90, 215, 255 } },
        symbol = "bolt",
    },
    bomb = {
        id = "bomb", name = "定时炸弹", short = "炸弹", rarity = "common", family = "blast",
        baseChips = 65, multAdd = 0.4, massMul = 1.25, radiusMul = 1.06, restitution = 0.45, feverGain = 9,
        explodeRadius = 72, explodeForce = 240, fuseTime = 3.8, desc = "落台倒数引爆，把前方币轰下悬崖。",
        color = { base = { 244, 96, 72 }, dark = { 148, 36, 30 }, light = { 255, 186, 140 }, rim = { 255, 138, 96 }, glow = { 255, 110, 64 } },
        symbol = "bomb",
    },
    spring = {
        id = "spring", name = "高弹霓虹", short = "弹跳", rarity = "rare", family = "swarm",
        baseChips = 42, multAdd = 0.45, massMul = 0.85, radiusMul = 0.96, restitution = 0.86, feverGain = 9,
        bounceSpawn = 1, desc = "超高弹性在钉阵连撞，额外衍生银币。",
        color = { base = { 255, 116, 196 }, dark = { 156, 38, 110 }, light = { 255, 206, 236 }, rim = { 255, 160, 220 }, glow = { 255, 130, 210 } },
        symbol = "spring",
    },
    magnet = {
        id = "magnet", name = "磁石吸金", short = "磁石", rarity = "rare", family = "gravity",
        baseChips = 55, multAdd = 0.4, massMul = 1.35, radiusMul = 1.05, restitution = 0.45, feverGain = 8,
        magnetR = 72, desc = "吸附周边散币向中心靠拢，防侧漏。",
        color = { base = { 166, 116, 255 }, dark = { 84, 48, 166 }, light = { 226, 202, 255 }, rim = { 196, 160, 255 }, glow = { 176, 132, 255 } },
        symbol = "magnet",
    },
    ruby = {
        id = "ruby", name = "红宝石倍率", short = "红宝", rarity = "rare", family = "wealth",
        baseChips = 50, multAdd = 1.1, massMul = 1.1, radiusMul = 1.0, restitution = 0.54, feverGain = 8,
        permMult = 0.8, desc = "掉落直接为本关永久叠加+0.8倍率。",
        color = { base = { 236, 56, 98 }, dark = { 136, 20, 48 }, light = { 255, 166, 188 }, rim = { 255, 108, 146 }, glow = { 255, 76, 120 } },
        symbol = "gem",
    },
    neon = {
        id = "neon", name = "狂热霓虹", short = "霓虹", rarity = "rare", family = "fever",
        baseChips = 52, multAdd = 0.55, massMul = 1.0, radiusMul = 1.0, restitution = 0.62, feverGain = 24,
        critBonus = 0.25, desc = "掉落狂欢槽+24%，自带+25%暴击率。",
        color = { base = { 255, 68, 220 }, dark = { 142, 22, 138 }, light = { 255, 188, 250 }, rim = { 100, 245, 255 }, glow = { 255, 92, 230 } },
        symbol = "star",
    },
    frost = {
        id = "frost", name = "冰晶棱币", short = "冰晶", rarity = "rare", family = "gravity",
        baseChips = 62, multAdd = 0.5, massMul = 1.4, radiusMul = 1.04, restitution = 0.42, feverGain = 8,
        frostR = 64, desc = "给周围5枚硬币镀上双倍碎冰得分。",
        color = { base = { 118, 238, 255 }, dark = { 42, 134, 174 }, light = { 224, 252, 255 }, rim = { 184, 248, 255 }, glow = { 140, 242, 255 } },
        symbol = "snow",
    },
    ghost = {
        id = "ghost", name = "幽灵穿影", short = "幽灵", rarity = "rare", family = "chain",
        baseChips = 68, multAdd = 0.65, massMul = 0.95, radiusMul = 1.0, restitution = 0.55, feverGain = 10,
        phasePegs = true, desc = "穿越钉阵直狙中奖门，落地化为实体。",
        color = { base = { 174, 210, 255 }, dark = { 76, 98, 158 }, light = { 238, 248, 255 }, rim = { 206, 230, 255 }, glow = { 180, 215, 255 } },
        symbol = "ghost",
    },
    jackpot7 = {
        id = "jackpot7", name = "777轮盘币", short = "777", rarity = "legendary", family = "fever",
        baseChips = 110, multAdd = 1.2, massMul = 1.2, radiusMul = 1.1, restitution = 0.52, feverGain = 18,
        roll777 = true, desc = "掉落必转777大奖，高概率喷射金币雨。",
        color = { base = { 255, 215, 46 }, dark = { 172, 92, 16 }, light = { 255, 250, 198 }, rim = { 255, 82, 128 }, glow = { 255, 224, 72 } },
        symbol = "seven",
    },
    blackhole = {
        id = "blackhole", name = "黑洞奇点", short = "黑洞", rarity = "legendary", family = "gravity",
        baseChips = 120, multAdd = 1.1, massMul = 1.8, radiusMul = 1.12, restitution = 0.35, feverGain = 14,
        bhRadius = 92, desc = "驻留吸聚周边6币蓄能后向前脉冲爆发。",
        color = { base = { 78, 42, 146 }, dark = { 24, 12, 48 }, light = { 182, 124, 255 }, rim = { 220, 150, 255 }, glow = { 156, 86, 255 } },
        symbol = "vortex",
    },
    giant = {
        id = "giant", name = "黄金巨人", short = "巨人", rarity = "legendary", family = "wealth",
        baseChips = 220, multAdd = 1.4, massMul = 4.2, radiusMul = 1.5, restitution = 0.32, feverGain = 18,
        pushPower = 2.4, desc = "巨无霸碾压整条赛道，掉落5倍爆发分。",
        color = { base = { 255, 178, 36 }, dark = { 160, 86, 12 }, light = { 255, 240, 156 }, rim = { 255, 226, 98 }, glow = { 255, 198, 56 } },
        symbol = "crown",
    },
    nuke = {
        id = "nuke", name = "核能烈焰", short = "核爆", rarity = "legendary", family = "blast",
        baseChips = 140, multAdd = 1.3, massMul = 1.5, radiusMul = 1.15, restitution = 0.42, feverGain = 16,
        explodeRadius = 104, explodeForce = 340, fuseTime = 3.2, doubleBlast = true,
        desc = "双重超大爆破冲击，轰飞半台并叠火筹码。",
        color = { base = { 255, 76, 42 }, dark = { 140, 22, 14 }, light = { 255, 224, 120 }, rim = { 255, 166, 52 }, glow = { 255, 100, 46 } },
        symbol = "flame",
    },

    -- 内部衍生币与 Boss 废渣/金库币
    mini = {
        id = "mini", name = "银分身", short = "银币", rarity = "common", family = "swarm",
        baseChips = 24, multAdd = 0.12, massMul = 0.6, radiusMul = 0.72, restitution = 0.62, feverGain = 3,
        internal = true, desc = "分裂产生的轻巧银币。",
        color = { base = { 202, 220, 242 }, dark = { 104, 120, 148 }, light = { 246, 252, 255 }, rim = { 226, 238, 255 }, glow = { 196, 224, 255 } },
        symbol = "dot",
    },
    slag = {
        id = "slag", name = "熔渣废币", short = "熔渣", rarity = "common", family = "blast",
        baseChips = 180, multAdd = 0.5, massMul = 2.6, radiusMul = 1.15, restitution = 0.3, feverGain = 10,
        internal = true, desc = "Boss空投占道币，推落爆出8倍反奖。",
        color = { base = { 106, 94, 92 }, dark = { 52, 42, 42 }, light = { 224, 126, 58 }, rim = { 255, 118, 42 }, glow = { 240, 108, 40 } },
        symbol = "cracks",
    },
    vault = {
        id = "vault", name = "装甲金库币", short = "金库", rarity = "legendary", family = "wealth",
        baseChips = 900, multAdd = 2.5, massMul = 3.2, radiusMul = 1.24, restitution = 0.38, feverGain = 22,
        internal = true, desc = "吞金兽金库币，推落触发40倍超分。",
        color = { base = { 240, 206, 98 }, dark = { 84, 70, 52 }, light = { 255, 248, 198 }, rim = { 116, 236, 255 }, glow = { 255, 226, 116 } },
        symbol = "vault",
    },

    -- 6 种融合进化传说币
    midas = {
        id = "midas", name = "点金圣王", short = "点金", rarity = "legendary", family = "wealth", evolved = true,
        baseChips = 190, multAdd = 1.8, massMul = 1.4, radiusMul = 1.16, restitution = 0.52, feverGain = 16,
        midasR = 78, desc = "周边币点化成双倍黄金并直接叠倍率。",
        color = { base = { 255, 224, 62 }, dark = { 176, 108, 10 }, light = { 255, 254, 210 }, rim = { 255, 242, 140 }, glow = { 255, 232, 92 } },
        symbol = "crown",
    },
    thor = {
        id = "thor", name = "雷神之锤", short = "雷神", rarity = "legendary", family = "chain", evolved = true,
        baseChips = 175, multAdd = 1.6, massMul = 2.8, radiusMul = 1.28, restitution = 0.42, feverGain = 18,
        chainJumps = 8, shockwave = 180, desc = "落地劈出8道落雷与震荡波轰落前排。",
        color = { base = { 98, 228, 255 }, dark = { 32, 98, 188 }, light = { 226, 250, 255 }, rim = { 255, 226, 98 }, glow = { 120, 238, 255 } },
        symbol = "bolt",
    },
    supernova = {
        id = "supernova", name = "超新星爆", short = "新星", rarity = "legendary", family = "blast", evolved = true,
        baseChips = 185, multAdd = 1.7, massMul = 1.4, radiusMul = 1.18, restitution = 0.5, feverGain = 42,
        explodeRadius = 115, explodeForce = 360, fuseTime = 2.6, desc = "超级爆推清屏，同时瞬间灌满半槽狂欢。",
        color = { base = { 255, 92, 174 }, dark = { 138, 20, 86 }, light = { 255, 224, 172 }, rim = { 255, 214, 72 }, glow = { 255, 118, 198 } },
        symbol = "flame",
    },
    hydra = {
        id = "hydra", name = "无限分身", short = "无限", rarity = "legendary", family = "swarm", evolved = true,
        baseChips = 120, multAdd = 1.2, massMul = 1.0, radiusMul = 1.06, restitution = 0.88, feverGain = 15,
        splitCount = 4, bounceSpawn = 2, desc = "每撞钉狂飙弹跳并倾泻4枚以上银币。",
        color = { base = { 82, 248, 174 }, dark = { 22, 132, 86 }, light = { 206, 255, 232 }, rim = { 136, 255, 206 }, glow = { 96, 255, 186 } },
        symbol = "split",
    },
    singularity = {
        id = "singularity", name = "奇点涡轮", short = "奇点", rarity = "legendary", family = "gravity", evolved = true,
        baseChips = 210, multAdd = 1.9, massMul = 2.0, radiusMul = 1.2, restitution = 0.4, feverGain = 18,
        magnetR = 110, bhRadius = 110, shockwave = 220, desc = "吸尽侧漏边缘全部币后向前发射脉冲。",
        color = { base = { 150, 74, 255 }, dark = { 38, 14, 98 }, light = { 228, 198, 255 }, rim = { 102, 236, 255 }, glow = { 172, 108, 255 } },
        symbol = "vortex",
    },
    carnival = {
        id = "carnival", name = "狂欢大满贯", short = "大满贯", rarity = "legendary", family = "fever", evolved = true,
        baseChips = 240, multAdd = 2.4, massMul = 1.3, radiusMul = 1.18, restitution = 0.56, feverGain = 35,
        gateRefund = 3, roll777 = true, feverExtend = 3.0, desc = "直接延长狂欢3秒并掉落必出三连大奖。",
        color = { base = { 255, 204, 64 }, dark = { 164, 58, 128 }, light = { 255, 252, 212 }, rim = { 96, 244, 255 }, glow = { 255, 216, 98 } },
        symbol = "star",
    },
}

Config.COIN_POOL = {
    "gold", "emerald", "split", "heavy", "thunder", "bomb",
    "spring", "magnet", "ruby", "neon", "frost", "ghost",
    "jackpot7", "blackhole", "giant", "nuke",
}

Config.EVOLUTIONS = {
    midas       = { id = "midas",       name = "点金圣王",   parts = { "gold", "ruby" },         result = "midas" },
    thor        = { id = "thor",        name = "雷神之锤",   parts = { "heavy", "thunder" },     result = "thor" },
    supernova   = { id = "supernova",   name = "超新星爆",   parts = { "bomb", "neon" },         result = "supernova" },
    hydra       = { id = "hydra",       name = "无限分身",   parts = { "split", "spring" },      result = "hydra" },
    singularity = { id = "singularity", name = "奇点涡轮",   parts = { "blackhole", "magnet" },  result = "singularity" },
    carnival    = { id = "carnival",    name = "狂欢大满贯", parts = { "jackpot7", "emerald" },  result = "carnival" },
}
Config.EVOLUTION_ORDER = { "midas", "thor", "supernova", "hydra", "singularity", "carnival" }

-- 20 件遗物 / 机台改装件
Config.RELICS = {
    rail_guard   = { id = "rail_guard",   name = "合金护栏",   rarity = "common",    price = 28, icon = "shield", desc = "侧漏缝收窄65%，漏币保留50%分" },
    turbo_pusher = { id = "turbo_pusher", name = "涡轮活塞",   rarity = "common",    price = 30, icon = "spring", desc = "推板速度+25%，前推力+20%" },
    golden_pegs  = { id = "golden_pegs",  name = "黄金倍增钉", rarity = "common",    price = 28, icon = "star",   desc = "钉阵新增4颗x2倍增金钉" },
    wide_gate    = { id = "wide_gate",    name = "宽口中奖门", rarity = "common",    price = 26, icon = "gate",   desc = "中奖门净口宽+35%" },
    metronome    = { id = "metronome",    name = "连击节拍器", rarity = "common",    price = 28, icon = "bolt",   desc = "连击时间窗6.5s，每连击+倍率" },
    bankbook     = { id = "bankbook",     name = "复利金库",   rarity = "rare",      price = 36, icon = "coin",   desc = "每20券+5利息，上限25" },
    crit_seal    = { id = "crit_seal",    name = "暴击印章",   rarity = "rare",      price = 38, icon = "crit",   desc = "暴击率+18%，暴击倍率+0.8" },
    fever_amp    = { id = "fever_amp",    name = "狂欢扩音器", rarity = "rare",      price = 36, icon = "flame",  desc = "狂欢时长+3秒，金币雨+6枚" },
    double_barrel= { id = "double_barrel",name = "双发枪管",   rarity = "rare",      price = 42, icon = "split",  desc = "每第4发自动双连射" },
    mag_lip      = { id = "mag_lip",      name = "磁力前沿",   rarity = "rare",      price = 36, icon = "magnet", desc = "前沿掉落前倍率+30%" },
    powder_keg   = { id = "powder_keg",   name = "超级火药",   rarity = "rare",      price = 35, icon = "bomb",   desc = "爆炸范围+40%，伤害x1.5" },
    tesla_coil   = { id = "tesla_coil",   name = "高压线圈",   rarity = "rare",      price = 36, icon = "bolt",   desc = "所有闪电额外+2跳且充能" },
    clover       = { id = "clover",       name = "幸运四叶草", rarity = "rare",      price = 34, icon = "clover", desc = "中奖轮盘出大奖概率翻倍" },
    medkit       = { id = "medkit",       name = "救急芯片",   rarity = "common",    price = 25, icon = "heart",  desc = "过关回1心，满血+30筹码" },
    big_pouch    = { id = "big_pouch",    name = "大额币袋",   rarity = "common",    price = 28, icon = "bag",    desc = "每关基础投币数+4" },
    recycler     = { id = "recycler",     name = "回收磁爪",   rarity = "rare",      price = 34, icon = "magnet", desc = "侧漏币25%概率回队列" },
    overclock    = { id = "overclock",    name = "超频散热",   rarity = "legendary", price = 48, icon = "flame",  desc = "满台溢出超频收益变3倍" },
    first_surge  = { id = "first_surge",  name = "首冲引擎",   rarity = "legendary", price = 48, icon = "power",  desc = "每关前5枚投币倍率翻倍" },
    vip_card     = { id = "vip_card",     name = "黄金会员卡", rarity = "rare",      price = 32, icon = "crown",  desc = "商店8折，删币费用减半" },
    prism        = { id = "prism",        name = "霓虹棱镜",   rarity = "legendary", price = 52, icon = "star",   desc = "全家族协同门槛减1" },
}
Config.RELIC_ORDER = {
    "rail_guard", "turbo_pusher", "golden_pegs", "wide_gate", "metronome",
    "medkit", "big_pouch", "bankbook", "crit_seal", "fever_amp",
    "double_barrel", "mag_lip", "powder_keg", "tesla_coil", "clover",
    "recycler", "vip_card", "overclock", "first_surge", "prism",
}

-- 3 幕战役目标曲线 & Boss 定义
Config.ACTS = {
    {
        id = 1, name = "霓虹游艺厅", boss = "gatekeeper",
        accent = { 56, 224, 255 }, trim = { 255, 76, 178 },
        targets = { 350000, 520000, 750000, 950000, 1150000, 1450000 },
    },
    {
        id = 2, name = "黄金熔炉", boss = "furnace",
        accent = { 255, 198, 56 }, trim = { 255, 96, 48 },
        targets = { 12000000, 18000000, 24000000, 32000000, 42000000, 56000000 },
    },
    {
        id = 3, name = "赛博金库", boss = "vaultbeast",
        accent = { 188, 118, 255 }, trim = { 255, 218, 72 },
        targets = { 280000000, 420000000, 600000000, 780000000, 960000000, 1100000000 },
    },
}

Config.BOSSES = {
    gatekeeper = {
        id = "gatekeeper", name = "铁闸庄家", act = 1, icon = "crown",
        desc = "周期开合中奖门，并间歇抬高前沿阻挡唇。",
    },
    furnace = {
        id = "furnace", name = "熔金巨轮", act = 2, icon = "flame",
        desc = "周期空投占道熔渣币，推落可炸出8倍熔金大奖。",
    },
    vaultbeast = {
        id = "vaultbeast", name = "终极吞金兽", act = 3, icon = "skull",
        desc = "间歇压制倍率，周期生成装甲金库币爆40倍超分。",
    },
}

-- 6 个奇遇事件
Config.EVENTS = {
    gold_altar = {
        id = "gold_altar", name = "黄金祭坛", icon = "crown",
        desc = "古老机台浮现双色投币孔，投下献祭或直接索取？",
        a = { text = "献1心夺50券", effect = "sacrifice_heart" },
        b = { text = "免费取18券", effect = "free_tickets" },
    },
    scrap_smith = {
        id = "scrap_smith", name = "机台改造匠", icon = "gear",
        desc = "戴着霓虹护目镜的技师愿免费帮你升级一枚硬币。",
        a = { text = "升级随机币", effect = "upgrade_coin" },
        b = { text = "随机获遗物", effect = "gain_relic" },
    },
    lucky_wheel = {
        id = "lucky_wheel", name = "午夜赌局", icon = "clover",
        desc = "庄家邀你赌一把：50%赚翻倍，50%只拿安慰奖。",
        a = { text = "豪赌45券", effect = "gamble_tickets" },
        b = { text = "稳拿20券", effect = "safe_tickets" },
    },
    neon_spring = {
        id = "neon_spring", name = "狂欢充能站", icon = "star",
        desc = "紫色能量管嗡嗡作响，可修复机台或注入狂欢。",
        a = { text = "回2心+补币", effect = "heal_hearts" },
        b = { text = "下关满狂欢", effect = "precharge_fever" },
    },
    magnet_trap = {
        id = "magnet_trap", name = "废料清道夫", icon = "magnet",
        desc = "清理推台冗余低级币能让高阶币更快触发升级。",
        a = { text = "精简并+25券", effect = "purge_common" },
        b = { text = "加1枚进阶币", effect = "add_rare" },
    },
    vault_crack = {
        id = "vault_crack", name = "加密金库门", icon = "chest",
        desc = "破译霓虹密码锁可打开隐藏货仓。",
        a = { text = "耗15券抽遗物", effect = "buy_relic_cheap" },
        b = { text = "带走12券", effect = "small_tickets" },
    },
}
Config.EVENT_ORDER = { "gold_altar", "scrap_smith", "lucky_wheel", "neon_spring", "magnet_trap", "vault_crack" }

-- 20 档难度递增曲线（兼容历史配置）
Config.DIFFICULTY = {}
for i = 1, 20 do
    Config.DIFFICULTY[i] = {
        level = i,
        name = (i == 1) and "标准街机" or ("超频 " .. i),
        targetMul = 1 + (i - 1) * 0.14,
        ammoDelta = (i >= 10) and -2 or ((i >= 5) and -1 or 0),
        startHearts = (i >= 15) and 4 or 5,
        desc = (i == 1) and "标准数值体验" or string.format("目标分x%.2f%s", 1 + (i - 1) * 0.14, i >= 5 and " 投币减少" or ""),
    }
end

-- ============================================================================
-- 增量推币首富体系配置（100位全球富豪梯度榜 / 机台升级 / 22币 / 黑科技 / IPO天赋 / 广告位）
-- ============================================================================
local Billionaires = require("game/Billionaires")

-- 1. 全球富豪排行榜（共 100 档，No.100 一路冲顶 No.1 马斯克，自动换幕与超豪弹窗）
Config.RANKS = Billionaires.LIST

-- 2. 机台 8 项无限强化（4×2 网格，复用 relic_* 成品贴图）
Config.MACHINE_UPGRADES = {
    { id = "auto_rate",    name = "自动投币",   short = "自动射速", relic = "double_barrel", baseCost = 35,  growth = 1.42, maxLv = 60,
      desc = "每秒自动持续投币，等级越高永动射速越快。" },
    { id = "pusher_turbo", name = "涡轮推板",   short = "推板马力", relic = "turbo_pusher",  baseCost = 60,  growth = 1.48, maxLv = 40,
      desc = "加快推板往复速度并加大前推力，金币瀑布更猛。" },
    { id = "global_mult",  name = "印钞倍率",   short = "全币倍率", relic = "vip_card",      baseCost = 100, growth = 1.55, maxLv = 80,
      desc = "全场所有掉落与特效收益每级永久 ×1.35。" },
    { id = "multi_shot",   name = "多管齐射",   short = "双发齐射", relic = "first_surge",   baseCost = 280, growth = 1.75, maxLv = 30,
      desc = "每次自动或手点投币，高概率一次喷出 2~4 枚币。" },
    { id = "crit_power",   name = "暴击增幅",   short = "暴击爆伤", relic = "crit_seal",     baseCost = 180, growth = 1.52, maxLv = 40,
      desc = "大幅提升暴击触发率与金光暴击伤害倍数。" },
    { id = "gate_master",  name = "黄金中奖门", short = "中奖门",   relic = "wide_gate",     baseCost = 220, growth = 1.55, maxLv = 35,
      desc = "加宽移动中奖门，过门必爆现金雨与额外倍增。" },
    { id = "peg_gold",     name = "黄金钉阵",   short = "黄金钉阵", relic = "golden_pegs",   baseCost = 150, growth = 1.50, maxLv = 40,
      desc = "钉阵转化更多金色倍增钉，撞钉即爆即时现金。" },
    { id = "fever_drive",  name = "狂欢超频",   short = "狂欢超频", relic = "fever_amp",     baseCost = 320, growth = 1.60, maxLv = 35,
      desc = "加快狂欢槽充能，延长狂欢时间并狂撒金币雨。" },
}
Config.MACHINE_BY_ID = {}
for _, m in ipairs(Config.MACHINE_UPGRADES) do Config.MACHINE_BY_ID[m.id] = m end

-- 3. 22 种代币渐进解锁与升级表（开局只有标准金币，点亮后立即上台）
Config.COIN_TIERS = {
    { id = "gold",        unlockCost = 0,       baseValue = 12,     upBase = 40,     upGrowth = 1.65, maxLv = 20 },
    { id = "emerald",     unlockCost = 120,     baseValue = 32,     upBase = 160,    upGrowth = 1.68, maxLv = 20 },
    { id = "split",       unlockCost = 550,     baseValue = 85,     upBase = 650,    upGrowth = 1.70, maxLv = 20 },
    { id = "heavy",       unlockCost = 2400,    baseValue = 220,    upBase = 2800,   upGrowth = 1.72, maxLv = 20 },
    { id = "thunder",     unlockCost = 1.1e4,   baseValue = 620,    upBase = 1.2e4,  upGrowth = 1.74, maxLv = 20 },
    { id = "bomb",        unlockCost = 5e4,     baseValue = 1800,   upBase = 5.5e4,  upGrowth = 1.75, maxLv = 20 },
    { id = "spring",      unlockCost = 2.4e5,   baseValue = 5500,   upBase = 2.6e5,  upGrowth = 1.76, maxLv = 20 },
    { id = "magnet",      unlockCost = 1.2e6,   baseValue = 1.7e4,  upBase = 1.3e6,  upGrowth = 1.78, maxLv = 20 },
    { id = "ruby",        unlockCost = 6e6,     baseValue = 5.5e4,  upBase = 6.5e6,  upGrowth = 1.78, maxLv = 20 },
    { id = "neon",        unlockCost = 3.2e7,   baseValue = 1.8e5,  upBase = 3.5e7,  upGrowth = 1.80, maxLv = 20 },
    { id = "frost",       unlockCost = 1.8e8,   baseValue = 6.5e5,  upBase = 2e8,    upGrowth = 1.80, maxLv = 20 },
    { id = "ghost",       unlockCost = 1e9,     baseValue = 2.4e6,  upBase = 1.1e9,  upGrowth = 1.82, maxLv = 20 },
    { id = "jackpot7",    unlockCost = 6.5e9,   baseValue = 9.5e6,  upBase = 7e9,    upGrowth = 1.82, maxLv = 20 },
    { id = "blackhole",   unlockCost = 4.5e10,  baseValue = 3.8e7,  upBase = 5e10,   upGrowth = 1.84, maxLv = 20 },
    { id = "giant",       unlockCost = 3.2e11,  baseValue = 1.6e8,  upBase = 3.5e11, upGrowth = 1.85, maxLv = 20 },
    { id = "nuke",        unlockCost = 2.5e12,  baseValue = 7.5e8,  upBase = 2.8e12, upGrowth = 1.86, maxLv = 20 },
    { id = "midas",       unlockCost = 2.2e13,  baseValue = 4e9,    upBase = 2.5e13, upGrowth = 1.88, maxLv = 20, parents = { "gold", "ruby" } },
    { id = "thor",        unlockCost = 1.8e14,  baseValue = 2.2e10, upBase = 2e14,   upGrowth = 1.88, maxLv = 20, parents = { "heavy", "thunder" } },
    { id = "supernova",   unlockCost = 1.6e15,  baseValue = 1.3e11, upBase = 1.8e15, upGrowth = 1.90, maxLv = 20, parents = { "bomb", "neon" } },
    { id = "hydra",       unlockCost = 1.5e16,  baseValue = 8e11,   upBase = 1.7e16, upGrowth = 1.90, maxLv = 20, parents = { "split", "spring" } },
    { id = "singularity", unlockCost = 1.2e17,  baseValue = 5e12,   upBase = 1.4e17, upGrowth = 1.92, maxLv = 20, parents = { "blackhole", "magnet" } },
    { id = "carnival",    unlockCost = 8e17,    baseValue = 3.5e13, upBase = 9e17,   upGrowth = 1.94, maxLv = 20, parents = { "jackpot7", "emerald" } },
}
Config.COIN_TIER_BY_ID = {}
for idx, t in ipairs(Config.COIN_TIERS) do
    t.order = idx
    Config.COIN_TIER_BY_ID[t.id] = t
end

-- 4. 黑科技 12 项一次性里程碑（使用其余 12 张 relic_* 贴图，买到立即质感跃升）
Config.TECH_UPGRADES = {
    { id = "rail_guard",  name = "激光护栏",   relic = "rail_guard",  cost = 600,     mult = 1.4, desc = "永久开启合金侧壁护栏防侧漏，全币收益 ×1.4。" },
    { id = "metronome",   name = "连击共振仪", relic = "metronome",   cost = 3500,    mult = 1.5, desc = "连击窗延长至7秒且每次连击加速叠加倍率，总收益 ×1.5。" },
    { id = "medkit",      name = "智能回收器", relic = "medkit",      cost = 1.8e4,   mult = 1.6, desc = "每落10枚币直接额外返现金红包，总收益 ×1.6。" },
    { id = "big_pouch",   name = "高频供币仓", relic = "big_pouch",   cost = 9e4,     mult = 1.8, desc = "推台初始铺币加密且全币产值 ×1.8。" },
    { id = "bankbook",    name = "复利金库锁", relic = "bankbook",    cost = 5e5,     mult = 2.0, desc = "每秒被动吃利息复利，全币产值翻倍 ×2.0。" },
    { id = "mag_lip",     name = "磁力集束唇", relic = "mag_lip",     cost = 3e6,     mult = 2.2, desc = "前沿吸金加速跌落，爆分倍率 ×2.2。" },
    { id = "powder_keg",  name = "工业炸药库", relic = "powder_keg",  cost = 2e7,     mult = 2.4, desc = "所有炸弹/核爆/脉冲范围与收益 ×2.4。" },
    { id = "tesla_coil",  name = "超导特斯拉", relic = "tesla_coil",  cost = 1.5e8,   mult = 2.6, desc = "闪电链额外 +2 跳且每次跳电增幅 ×2.6。" },
    { id = "clover",      name = "四叶草财神", relic = "clover",      cost = 1.2e9,   mult = 2.8, desc = "中奖门金币雨概率暴涨，全场产值 ×2.8。" },
    { id = "recycler",    name = "重力回流爪", relic = "recycler",    cost = 1e10,    mult = 3.0, desc = "侧漏全部转化为回收奖金，总收益 ×3.0。" },
    { id = "overclock",   name = "超频量子核", relic = "overclock",   cost = 1.2e11,  mult = 3.5, desc = "满台溢出超频回收变成 4 倍暴利，总收益 ×3.5。" },
    { id = "prism",       name = "彩虹棱镜矩阵",relic = "prism",      cost = 2e12,    mult = 4.5, desc = "解锁终极棱镜增幅，全印钞机器效率 ×4.5！" },
}
Config.TECH_BY_ID = {}
for _, t in ipairs(Config.TECH_UPGRADES) do Config.TECH_BY_ID[t.id] = t end

-- 5. IPO 上市转生 4 大永久天赋（消耗传奇声望股，跨转生永久保留）
Config.PRESTIGE_TALENTS = {
    { id = "angel_fund",  name = "天使启动金", relic = "big_pouch",    baseCost = 2, growth = 1.8, maxLv = 20,
      desc = "每次上市转生保留前 Lv 种已解锁高阶币并自带启动资金。" },
    { id = "golden_dna",  name = "黄金基因链", relic = "bankbook",     baseCost = 2, growth = 2.0, maxLv = 25,
      desc = "所有硬币基础售价每级永久 ×1.8。" },
    { id = "perpetual",   name = "永动超马达", relic = "turbo_pusher", baseCost = 3, growth = 2.0, maxLv = 15,
      desc = "自动投币与推板物理速率每级永久 +20%。" },
    { id = "tycoon_crit", name = "首富暴击心", relic = "crit_seal",    baseCost = 3, growth = 2.0, maxLv = 20,
      desc = "全局暴击倍率每级永久 +1.5 倍，满屏紫金跳字。" },
}
Config.PRESTIGE_BY_ID = {}
for _, p in ipairs(Config.PRESTIGE_TALENTS) do Config.PRESTIGE_BY_ID[p.id] = p end

-- 6. 6 个商业级激励模拟广告位（完整 UI + 冷却 + 3秒试看弹窗，先接入 MockAd 不碰真实 SDK）
Config.AD_PLACEMENTS = {
    boost_3x = {
        id = "boost_3x", title = "超级印钞 ×3", short = "×3印钞", cooldown = 0,
        iconKind = "relic", iconKey = "vip_card", inWelfare = true,
        desc = "全场收益立刻翻 3 倍并持续 180 秒（可叠加至 900 秒）！",
    },
    instant_fever = {
        id = "instant_fever", title = "满槽超级狂欢", short = "超级狂欢", cooldown = 60,
        iconKind = "relic", iconKey = "fever_amp", inWelfare = true,
        desc = "瞬间灌满狂欢槽，触发 15 秒极限射速 + 30 枚高阶金币雨！",
    },
    vault_drop = {
        id = "vault_drop", title = "空投50倍金库币", short = "金库巨币", cooldown = 90,
        iconKind = "boss", iconKey = "vaultbeast", inWelfare = true,
        desc = "直接向推台正中空投 2 枚 50 倍【装甲金库巨币】，推落秒赚百倍！",
    },
    airdrop_5x = {
        id = "airdrop_5x", title = "风投空投 ×5 暴富", short = "风投暴富", cooldown = 75,
        iconKind = "event", iconKey = "vault_crack", inWelfare = true,
        desc = "立刻发放 120 秒产值巨额现金 + 10 枚当前最高阶硬币落台！",
    },
    offline_2x = {
        id = "offline_2x", title = "离线收益双倍领", short = "离线双倍", cooldown = 0,
        iconKind = "relic", iconKey = "big_pouch", inWelfare = false,
        desc = "看广告把本次离线挂机赚到的推币现金直接翻 2 倍落袋！",
    },
    prestige_2x = {
        id = "prestige_2x", title = "IPO 双倍传奇股", short = "双倍上市", cooldown = 0,
        iconKind = "boss", iconKey = "gatekeeper", inWelfare = false,
        desc = "本次上市转生获得的永久传奇股数量直接 ×2，起步起飞！",
    },
    overtake_3x = {
        id = "overtake_3x", title = "超越赏金 ×3 暴富", short = "超越×3", cooldown = 0,
        iconKind = "coin", iconKey = "midas", inWelfare = false,
        desc = "看模拟广告立刻把刚刚超越世界富豪的祝贺赏金直接翻 3 倍！",
    },
}
Config.AD_WELFARE_ORDER = { "boost_3x", "instant_fever", "vault_drop", "airdrop_5x" }

return Config
