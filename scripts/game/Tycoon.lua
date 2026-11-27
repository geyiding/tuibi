-- ============================================================================
-- Tycoon.lua  《推币机的狂欢》增量首富核心逻辑（永动自动推币 + 22币渐进 + 科技 + IPO转生 + 离线）
-- ============================================================================

local Config = require("game/Config")
local Billionaires = require("game/Billionaires")
local Physics = require("game/Physics")
local Number = require("game/Number")
local RedeemCodes = require("game/RedeemCodes")

local floor, min, max, abs = math.floor, math.min, math.max, math.abs
local function pow(a, b) return a ^ b end
local S = Config.STAGE

local Tycoon = {}
Tycoon.__index = Tycoon

local JP = Config.JACKPOT
local JP_SYM = Config.SLOT_JP_SYMBOL
local REACH_LOCK_AT = { 0.22, 0.40, 0.97 }
local JP_TIER_ORDER = { "mini", "major", "grand", "next" }

local function Emit(fx, name, ...)
    local fn = fx and fx[name]
    if type(fn) == "function" then fn(fx, ...) end
end

local function MakeRng(seed)
    local v = floor(seed or os.time()) % 2147483647
    if v <= 0 then v = 1 end
    return function()
        v = v * 48271 % 2147483647
        return (v - 1) / 2147483646
    end
end

function Tycoon.New(fxListener, opts)
    opts = opts or {}
    local self = setmetatable({}, Tycoon)
    self.fx = fxListener
    self.seed = opts.seed or os.time()
    self.rng = MakeRng(self.seed)

    -- 核心资产与声望状态（全部浮点 0.0 杜绝 Lua 5.4 64位整数溢出；升级仅花技能点 SP）
    self.cash = 0.0
    self.runCash = 0.0
    self.lifetimeCash = 0.0
    self.skillPoints = 0
    self.totalSkillPoints = 0
    self.spStep = 0
    self.ipoRound = 0
    self.era = 0
    self.prestigeShares = 0
    self.totalPrestiges = 0
    self.rankIdx = 0      -- 0 = 第80亿名起点，依次冲破 22 档匿名阶层 -> 世界前 1000 真名榜
    self.stageTheme = 1

    -- 街机幸运三连机（过幸运门 9 秒限流转动，稀缺爆发 1.5x~100x）
    self.slotQueue = 0
    self.slotCd = 0
    self.slotSpinning = false
    self.slotSpinT = 0
    self.slotSpinDur = 0.85
    self.slotReels = { 1, 2, 3 }
    self.slotPending = nil
    self.slotPity = 0
    self.luckMult = 1
    self.luckTimer = 0
    self.luckDur = 0
    self.luckName = ""
    self.slotFlashT = 0
    -- 九宫格（行优先 1..9）、本次中奖线、每列停轮时间点（听牌时第三列拖长）
    self.slotGrid = { 2, 4, 1, 1, 2, 3, 5, 3, 6 }
    self.slotWinLine = nil
    self.slotLockAt = nil

    -- JP 大奖池（养分 -> 灯位 -> JP CHANCE 跑灯 -> 一次性倾泻）
    self.jpPool = 0.0
    self.jpRefCps = 0.0     -- 最近 ~2 分钟真实收入速度（EMA），JP 计价基准
    self.jpLamps = 0
    self.jpSince = 0.0
    self.jpPhase = nil      -- nil | "intro" | "spin" | "result" | "release"
    self.jpT = 0
    self.jpRound = 1
    self.jpBonus = 1
    self.jpCell = 1         -- 外圈 8 格中当前亮灯的格（1..8）
    self.jpSpinFrom = 1
    self.jpSpinSteps = 0
    self.jpResult = nil     -- 本轮停下的格子类型（mini/major/grand/next）
    self.jpPayout = nil     -- 本次派奖 { tier, name, amount, bonus }
    self.jpPendingPopup = nil
    self.jpRainLeft = 0
    self.jpRainT = 0
    self.jpWins = 0
    self.jpBest = 0.0

    -- 独立奇遇乘区 & 三重突发惊喜（金袋小人 12 面骰 / 空中黄金气球 / 突发黄金暴走）
    self.surpriseMult = 1
    self.surpriseTimer = 0
    self.surpriseDur = 0
    self.surpriseName = ""
    self.pendingDice = nil
    self.runner = {
        active = false,
        x = 60,
        y = S.DECK_BOT_Y + 14,
        dir = 1,
        speed = 44,
        cooldown = 38,
        hitCount = 0,
    }
    self.balloon = {
        active = false,
        x = 180,
        y = 118,
        baseY = 118,
        dir = 1,
        speed = 28,
        bobT = 0,
        cooldown = 26,
    }
    self.goldRushNext = 120 + floor(self.rng() * 70)

    -- 四大养成线 + 玩家常驻发射池配置
    self.machineLv = {}
    for _, m in ipairs(Config.MACHINE_UPGRADES) do self.machineLv[m.id] = 0 end
    self.coinLv = { gold = 1 } -- 渐进起点：开局仅解锁标准金币
    self.pinnedCoins = {}
    self._pinnedList = {}
    self._unlockedList = { "gold" }
    self.techOwned = {}
    self.prestigeLv = {}
    for _, p in ipairs(Config.PRESTIGE_TALENTS) do self.prestigeLv[p.id] = 0 end
    self._redDots = { machine = 0, coins = 0, tech = 0, prestige = 0, welfare = 0 }

    self.buyMode = 1 -- 1 | 10 | 0(MAX)

    -- 推台实时反馈（波次连击 + 冷却狂欢）
    self.combo = 0
    self.comboTimer = 0
    self.comboWaveT = 0
    self.comboWaveDur = 15.0
    self.fever = 0
    self.feverActive = false
    self.feverTimer = 0
    self.feverDur = 8.0
    self.feverCd = 0
    self.feverExtended = false
    self.feverChargeAcc = 0
    self.feverChargeTick = 0
    self.feverRainLeft = 0
    self.feverRainTimer = 0

    -- 自动永动与手点加速
    self.autoTimer = 0
    self.manualCd = 0
    self.shotsFired = 0
    self.totalClicks = 0
    self.totalDrops = 0
    self.bestHit = 0.0
    self.maxCombo = 0

    -- 模拟广告与风投空投
    self.adBoostLeft = 0
    self.adCooldowns = {}
    self.adWatchCount = 0
    self.airdropTimer = 55
    self.activeAirdrop = nil

    -- 收入统计（10秒滑动窗口 + 5分钟去瞬时倍率长期基准线）
    self.cpsBuckets = {}
    for i = 1, 10 do self.cpsBuckets[i] = 0.0 end
    self.cpsIdx = 1
    self.cpsAcc = 0.0
    self.cpsTick = 0
    self.cashPerSec = 0.0
    self.baseRevBuckets = {}
    for i = 1, 30 do self.baseRevBuckets[i] = 0.0 end
    self.baseRevIdx = 1
    self.baseRevAcc = 0.0
    self.baseRevTick = 0
    self.longTermBaseCps = 0.0
    self.interestTick = 0
    self.clock = 0
    self.lastActiveAt = 0

    self.physics = Physics.New({
        OnPegHit = function(coin, peg, hitSpd) self:HandlePegHit(coin, peg, hitSpd) end,
        OnGateWin = function(coin) self:HandleGateWin(coin) end,
        OnGateBounce = function(coin) Emit(self.fx, "OnGateBounce", coin) end,
        OnEnterDeck = function(coin) self:HandleEnterDeck(coin) end,
        OnFrontDrop = function(coin) self:HandleFrontDrop(coin) end,
        OnSideDrain = function(coin) self:HandleSideDrain(coin) end,
        OnCoinFuseExplode = function(coin) self:HandleBombExplode(coin) end,
        OnBlackholeBurst = function(coin) self:HandleBlackholeBurst(coin) end,
        OnOverclockCoin = function(coin) self:HandleOverclockCoin(coin) end,
        OnTowerLayer = function(x, y, layer, total, isCrown) Emit(self.fx, "OnTowerLayer", x, y, layer, total, isCrown) end,
        OnTowerComplete = function(x, y, label) Emit(self.fx, "OnTowerComplete", x, y, label) end,
        OnTowerTopple = function(x, y, label) Emit(self.fx, "OnTowerTopple", x, y, label) end,
    })

    self:RebuildCoinCache()
    self:ResetPhysics(true)
    return self
end

-- ----------------------------------------------------------------------------
-- 养成查询与数值公式
-- ----------------------------------------------------------------------------
function Tycoon:HasTech(id)
    return self.techOwned[id] == true
end

function Tycoon:RebuildCoinCache()
    local u = {}
    local p = {}
    for _, t in ipairs(Config.COIN_TIERS) do
        if (self.coinLv[t.id] or 0) > 0 then
            u[#u + 1] = t.id
            if self.pinnedCoins and self.pinnedCoins[t.id] then
                p[#p + 1] = t.id
            end
        elseif self.pinnedCoins then
            self.pinnedCoins[t.id] = nil
        end
    end
    if #u == 0 then u[1] = "gold" end
    self._unlockedList = u
    self._pinnedList = p
    self:InvalidateCaches()
end

function Tycoon:GetUnlockedCoins()
    return self._unlockedList or { "gold" }
end

function Tycoon:IsCoinPinned(id)
    return self.pinnedCoins and self.pinnedCoins[id] == true
end

function Tycoon:CountPinnedCoins()
    return self._pinnedList and #self._pinnedList or 0
end

function Tycoon:TogglePinCoin(id)
    if (self.coinLv[id] or 0) <= 0 then return false end
    self.pinnedCoins = self.pinnedCoins or {}
    if self.pinnedCoins[id] then
        self.pinnedCoins[id] = nil
        self:RebuildCoinCache()
        return true, false
    end
    if self:CountPinnedCoins() >= 6 then
        return false, false
    end
    self.pinnedCoins[id] = true
    self:RebuildCoinCache()
    return true, true
end

function Tycoon:CountUnlockedCoins()
    local u = self:GetUnlockedCoins()
    return #u
end

function Tycoon:GetHighestUnlockedCoin()
    local u = self:GetUnlockedCoins()
    return u[#u] or "gold"
end

function Tycoon:GetCoinUnitValue(kind, lvOverride)
    local t = Config.COIN_TIER_BY_ID[kind]
    if not t then
        -- 衍生/金库币映射到基准（统一 45x）
        if kind == "vault" then return self:GetCoinUnitValue(self:GetHighestUnlockedCoin()) * 45 end
        if kind == "slag" then return self:GetCoinUnitValue(self:GetHighestUnlockedCoin()) * 6 end
        if kind == "mini" then return self:GetCoinUnitValue("split") * 0.45 end
        return 1.0
    end
    local lv = max(1, floor(lvOverride or self.coinLv[kind] or 1))
    local v = t.baseValue * pow(1.20, lv - 1)
    if lv >= 5 then v = v * 1.30 end
    if lv >= 10 then v = v * 1.40 end
    if lv >= 15 then v = v * 1.50 end
    return v
end

function Tycoon:GetAvgUnlockedCoinValue()
    -- 帧内缓存（撞钉 / 闪电每次结算都会调用，避免反复建表）
    local cached = self._avgVal
    if cached then return cached end
    local list = self:GetUnlockedCoins()
    local topN = min(5, #list)
    local sum = 0
    for i = #list - topN + 1, #list do
        local cid = list[i]
        sum = sum + self:GetCoinUnitValue(cid, self.coinLv[cid])
    end
    cached = max(1.0, sum / max(1, topN))
    self._avgVal = cached
    return cached
end

function Tycoon:GetShareMult()
    return 1 + (self.prestigeShares or 0) * 0.09
end

--- 永久乘区（机台印钞 × 黑科技 × 传奇股/黄金基因 × 星际纪元），帧内缓存
function Tycoon:GetPermParts()
    local machine = pow(1.0205, self.machineLv.global_mult or 0)
    local tech = 1.0
    for _, t in ipairs(Config.TECH_UPGRADES) do
        if self.techOwned[t.id] then tech = tech * t.mult end
    end
    local prestige = self:GetShareMult() * pow(1.28, self.prestigeLv.golden_dna or 0) * pow(3.0, self.era or 0)
    return machine, tech, prestige
end

function Tycoon:GetPermMult()
    local cached = self._permMult
    if cached then return cached end
    local m, t, p = self:GetPermParts()
    cached = m * t * p
    self._permMult = cached
    return cached
end

--- 购买 / 读档后立刻作废帧内缓存
function Tycoon:InvalidateCaches()
    self._permMult = nil
    self._avgVal = nil
end

--- 临时爆发倍率（连击 × 狂欢 × 3x印钞 × 幸运三连 × 奇遇倍率），供结算与长期CPS去噪共用
function Tycoon:GetTempMult()
    local comboFactor = self:HasTech("metronome") and 0.012 or 0.008
    local comboM = 1 + min(100, self.combo) * comboFactor
    local feverM = self.feverActive and 2.2 or 1.0
    local adM = (self.adBoostLeft > 0) and 3.0 or 1.0
    local luckM = max(1, self.luckMult or 1)
    local surpM = max(1, self.surpriseMult or 1)
    return comboM * feverM * adM * luckM * surpM, comboM, feverM, adM, luckM, surpM
end

--- 总倍率；wantBreakdown 为 true 时额外返回分项表（仅 UI 公式页使用，避免每次结算建表）
function Tycoon:GetTotalMult(wantBreakdown)
    local tempM, comboM, feverM, adM, luckM, surpM = self:GetTempMult()
    local total = self:GetPermMult() * tempM
    if not wantBreakdown then return total end
    local machine, tech, prestige = self:GetPermParts()
    return total, {
        total = total,
        machine = machine,
        tech = tech,
        prestige = prestige,
        combo = comboM,
        fever = feverM,
        ad = adM,
        luck = luckM,
        surprise = surpM,
    }
end

function Tycoon:ApplySurpriseMult(mult, dur, name, fromAd)
    mult = max(1, mult or 1)
    dur = max(1, dur or 8)
    if mult >= (self.surpriseMult or 1) or (self.surpriseTimer or 0) <= 0 then
        self.surpriseMult = mult
        local t = max(dur, self.surpriseTimer or 0)
        self.surpriseTimer = t
        self.surpriseDur = max(self.surpriseDur or 0, t)
        self.surpriseName = name or "奇遇"
    elseif fromAd == true then
        local t = max(self.surpriseTimer or 0, dur)
        self.surpriseTimer = t
        self.surpriseDur = max(self.surpriseDur or 0, t)
    elseif mult > 1 then
        local cap = max(self.surpriseDur or dur, dur)
        self.surpriseTimer = min(cap, (self.surpriseTimer or 0) + 3.0)
        self.surpriseDur = cap
    end
    Emit(self.fx, "OnSurpriseMult", self.surpriseMult, self.surpriseTimer, self.surpriseName)
    return self.surpriseMult, self.surpriseTimer
end

function Tycoon:GetAutoRate(ignoreFever)
    local base = 0.75 + (self.machineLv.auto_rate or 0) * 0.14
    local perp = 1 + (self.prestigeLv.perpetual or 0) * 0.14
    local fev = (not ignoreFever and self.feverActive) and 1.65 or 1.0
    return min(9.0, base * perp * fev)
end

function Tycoon:GetEstimatedCPS()
    local rate = self:GetAutoRate(false) * (1 + min(0.75, (self.machineLv.multi_shot or 0) * 0.05))
    local mult = self:GetTotalMult()
    return rate * self:GetAvgUnlockedCoinValue() * mult * 0.92
end

--- 不含临时加成（连击/狂欢/幸运三连/印钞）的基准产值：飘字分级参照，倍率越高字越大越炸
function Tycoon:GetBaselineCPS()
    local rate = self:GetAutoRate(true) * (1 + min(0.75, (self.machineLv.multi_shot or 0) * 0.05))
    return rate * self:GetAvgUnlockedCoinValue() * self:GetPermMult() * 0.92
end

function Tycoon:GetDisplayCPS()
    return max(self.cashPerSec, self:GetEstimatedCPS())
end

function Tycoon:SyncPhysicsMods()
    self:InvalidateCaches()
    local phys = self.physics
    if not phys then return end
    local perp = 1 + (self.prestigeLv.perpetual or 0) * 0.14
    local turbo = 1 + (self.machineLv.pusher_turbo or 0) * 0.06
    local fev = self.feverActive and 1.65 or 1.0
    phys.pusherSpeedScale = min(4.2, turbo * perp * fev)
    phys.pusherForceScale = min(3.5, (1 + (self.machineLv.pusher_turbo or 0) * 0.05) * perp)
    phys.gateWidthScale = min(2.2, 1.0 + (self.machineLv.gate_master or 0) * 0.035)
    phys.railGuard = self:HasTech("rail_guard") and 0.78 or 0.12
    phys.frontLipResist = 0.05
    phys.magLip = self:HasTech("mag_lip") and 0.8 or 0
end

function Tycoon:ResetPhysics(clearCoins)
    local extraPegs = (self.machineLv.peg_gold or 0)
    self.physics:Reset({
        railGuard = self:HasTech("rail_guard") and 0.78 or 0.12,
        frontLipResist = 0.05,
        magLip = self:HasTech("mag_lip") and 0.8 or 0,
        extraMultPegs = min(11, extraPegs),
    })
    self:SyncPhysicsMods()
    if clearCoins ~= false then
        local extraSeed = self:HasTech("big_pouch") and 6 or 0
        self.physics:SeedDeck(self.rng, self:GetUnlockedCoins(), extraSeed)
    end
end

-- ----------------------------------------------------------------------------
-- 全球真实财富排名 & 技能点双轨成长（第80亿名起点 -> 全球前1000强真名榜）
-- ----------------------------------------------------------------------------
local STARTER_RANK = {
    id = 0, rank = Billionaires.START_RANK, name = "全球起步", title = "第 80 亿名起点",
    target = 0, theme = 1, spBounty = 0, bounty = 0, bonus = 0, isRealName = false,
}

function Tycoon:GetWorldRank()
    return Billionaires.CalcWorldRank(self.lifetimeCash)
end

function Tycoon:GetRankDisplayNo()
    return self:GetWorldRank()
end

function Tycoon:IsInTop1000()
    return self:GetWorldRank() <= Billionaires.REAL_NAME_CUTOFF
end

function Tycoon:GetRankDef(idx)
    local i = idx or self.rankIdx
    if not i or i <= 0 then return STARTER_RANK end
    return Config.RANKS[max(1, min(#Config.RANKS, i))]
end

function Tycoon:GetPrevSpThreshold()
    return (self.spStep > 0) and Config.GetSpThreshold(self.spStep) or 0
end

function Tycoon:GetNextSpThreshold()
    return Config.GetSpThreshold((self.spStep or 0) + 1)
end

function Tycoon:CheckSpMilestones()
    local gained = 0
    local bonusLv = self.prestigeLv.angel_fund or 0
    local lastStep = self.spStep or 0
    while self.lifetimeCash >= Config.GetSpThreshold(self.spStep + 1) do
        self.spStep = self.spStep + 1
        gained = gained + Config.GetSpReward(self.spStep, bonusLv)
        lastStep = self.spStep
    end
    if gained > 0 then
        self.skillPoints = self.skillPoints + gained
        self.totalSkillPoints = self.totalSkillPoints + gained
        Emit(self.fx, "OnSkillPointsGain", gained, lastStep)
    end
    return gained
end

function Tycoon:CheckRankUp()
    local jumped = 0
    local totalSp = 0
    local latest = nil
    local anyThemeChanged = false

    while self.rankIdx < #Config.RANKS do
        local nxt = Config.RANKS[self.rankIdx + 1]
        if self.lifetimeCash >= nxt.target then
            self.rankIdx = self.rankIdx + 1
            jumped = jumped + 1
            latest = nxt
            local newTheme = nxt.theme or 1
            if newTheme ~= self.stageTheme then
                self.stageTheme = newTheme
                anyThemeChanged = true
            end
            totalSp = totalSp + (nxt.spBounty or 2)
        else
            break
        end
    end

    if jumped > 0 and latest then
        local cappedSp = min(totalSp, 300)
        self.skillPoints = self.skillPoints + cappedSp
        self.totalSkillPoints = self.totalSkillPoints + cappedSp
        Emit(self.fx, "OnRankUp", latest, anyThemeChanged, {
            jumped = jumped,
            spBounty = cappedSp,
            bounty = cappedSp,
            wealthNow = self.lifetimeCash,
            worldRank = self:GetWorldRank(),
        })
    end
end

function Tycoon:AddWealth(amount, addToCps, tempMul)
    local amt = (tonumber(amount) or 0) + 0.0
    if amt ~= amt or amt == math.huge or amt <= 0 then return 0.0 end
    self.cash = self.cash + amt
    self.runCash = self.runCash + amt
    self.lifetimeCash = self.lifetimeCash + amt
    if addToCps then
        self.cpsAcc = self.cpsAcc + amt
        self.baseRevAcc = self.baseRevAcc + amt / max(1.0, (tonumber(tempMul) or 1.0))
    end
    self:CheckSpMilestones()
    self:CheckRankUp()
    return amt
end

function Tycoon:ClaimOvertakeAdBonus(spBounty)
    local extraSp = max(10, floor((spBounty or 0) * 2))
    self.adWatchCount = self.adWatchCount + 1
    self.skillPoints = self.skillPoints + extraSp
    self.totalSkillPoints = self.totalSkillPoints + extraSp
    Emit(self.fx, "OnAdReward", "超越技能点 ×3 +" .. tostring(extraSp) .. "点")
    return extraSp
end

-- ----------------------------------------------------------------------------
-- 发币队列（支持自选常驻组合 + 全解锁池加权抽取，让早期功能币永不过时）
-- ----------------------------------------------------------------------------
function Tycoon:PickLaunchCoin()
    local list = self:GetUnlockedCoins()
    local n = #list
    if n <= 1 then return list[1], self.coinLv[list[1]] or 1 end

    -- 若玩家指定了常驻发射组合，75% 从常驻组合加权抽取，25% 从全池补充变化
    local pinned = self._pinnedList
    if pinned and #pinned > 0 and self.rng() < 0.75 then
        local tw = 0
        for i = 1, #pinned do
            tw = tw + 1 + min(8, self.coinLv[pinned[i]] or 1)
        end
        local r = self.rng() * tw
        local acc = 0
        for i = 1, #pinned do
            local cid = pinned[i]
            acc = acc + 1 + min(8, self.coinLv[cid] or 1)
            if r <= acc then return cid, self.coinLv[cid] or 1 end
        end
        local last = pinned[#pinned]
        return last, self.coinLv[last] or 1
    end

    -- 30% 抽取前期功能币（1..n-6 按等级加权），70% 抽取前 6 高阶币
    local start, stop
    if n > 6 and self.rng() < 0.30 then
        start, stop = 1, n - 6
    else
        start, stop = max(1, n - 5), n
    end
    local totalW = 0
    for i = start, stop do
        totalW = totalW + (i - start + 1) * 2 + min(4, floor((self.coinLv[list[i]] or 1) * 0.4))
    end
    local r = self.rng() * totalW
    local acc = 0
    for i = start, stop do
        local cid = list[i]
        acc = acc + (i - start + 1) * 2 + min(4, floor((self.coinLv[cid] or 1) * 0.4))
        if r <= acc then
            return cid, self.coinLv[cid] or 1
        end
    end
    local last = list[stop]
    return last, self.coinLv[last] or 1
end

function Tycoon:PeekNextCoins(count)
    local list = self:GetUnlockedCoins()
    local out = {}
    local n = #list
    for i = 1, (count or 3) do
        local idx = max(1, n - ((i - 1) % min(3, n)))
        local cid = list[idx]
        out[i] = { kind = cid, level = self.coinLv[cid] or 1 }
    end
    return out
end

function Tycoon:FireOneBurst(isManual)
    local cid, lv = self:PickLaunchCoin()
    local mainCoin = self.physics:LaunchFromTop(cid, lv, 0, isManual)
    self.shotsFired = self.shotsFired + 1

    local multiLv = self.machineLv.multi_shot or 0
    local dblChance = min(0.85, multiLv * 0.045)
    if multiLv > 0 and self.rng() < dblChance then
        local cid2, lv2 = self:PickLaunchCoin()
        self.physics:LaunchFromTop(cid2, lv2, (self.shotsFired % 2 == 0) and 10 or -10, isManual)
        if multiLv >= 10 and self.rng() < (dblChance * 0.45) then
            local cid3, lv3 = self:PickLaunchCoin()
            self.physics:LaunchFromTop(cid3, lv3, (self.shotsFired % 2 == 0) and -16 or 16, isManual)
        end
    end
    Emit(self.fx, "OnShoot", mainCoin, self)
    return mainCoin
end

function Tycoon:ManualShoot()
    if self.manualCd > 0 then return false end
    self.manualCd = self.feverActive and 0.14 or 0.18
    self.totalClicks = self.totalClicks + 1
    self:FireOneBurst(true)
    self:AddFever(2.2)
    self:RegisterCombo()
    return true
end

-- ----------------------------------------------------------------------------
-- 现金结算与物理联动回调
-- ----------------------------------------------------------------------------
function Tycoon:AwardCash(baseVal, x, y, sourceTag, canCrit, extraMul)
    local tempMul = self:GetTempMult()
    local mult = self:GetPermMult() * tempMul * (extraMul or 1.0)
    local crit = false
    if canCrit ~= false then
        local critChance = min(0.75, 0.10 + (self.machineLv.crit_power or 0) * 0.015 + ((sourceTag == "neon") and 0.25 or 0))
        if self.rng() < critChance then
            crit = true
            local critMul = 2.0 + (self.machineLv.crit_power or 0) * 0.18 + (self.prestigeLv.tycoon_crit or 0) * 0.8
            mult = mult * critMul
        end
    end
    local dmg = max(1.0, floor(baseVal * mult + 0.5) + 0.0)
    -- JP 养分：每笔收入抽成注入奖池（JP CHANCE 时一次性倾泻回来）
    local tax = JP.FEED_TAX or 0
    if tax > 0 and dmg >= 10 then
        local cut = floor(dmg * tax) + 0.0
        self:FeedJackpot(cut)
        dmg = dmg - cut
    end
    if dmg > self.bestHit then self.bestHit = dmg end
    self:AddWealth(dmg, true, tempMul)
    Emit(self.fx, "OnScore", dmg, x, y, crit, self.combo, sourceTag, self:GetBaselineCPS(), mult)
    return dmg, crit
end

function Tycoon:AddFever(amt)
    if self.feverActive or (self.feverCd or 0) > 0 then return 0 end
    local drive = self.machineLv.fever_drive or 0
    local mul = 1 + drive * 0.06
    local secCap = 5.0 + min(1.5, drive * 0.075)
    local remain = max(0, secCap - (self.feverChargeAcc or 0))
    if remain <= 0 then return 0 end
    local gain = min(remain, amt * mul)
    self.feverChargeAcc = (self.feverChargeAcc or 0) + gain
    self.fever = min(100, self.fever + gain)
    if self.fever >= 100 then
        self:TriggerFever(false)
    end
    return gain
end

function Tycoon:TriggerFever(isAdSuper)
    self.fever = 100
    self.feverActive = true
    self.feverCd = 0
    self.feverExtended = false
    self.feverChargeAcc = 0
    local drive = self.machineLv.fever_drive or 0
    local dur = isAdSuper and 60 or (8 + min(4, drive * 0.2))
    self.feverDur = dur
    self.feverTimer = dur
    self.feverRainLeft = isAdSuper and 40 or (10 + floor(drive * 0.35))
    self.feverRainTimer = 0.04
    self:SyncPhysicsMods()
    Emit(self.fx, "OnFeverStart", self)
end

function Tycoon:RegisterCombo()
    self.combo = self.combo + 1
    local win = self:HasTech("metronome") and 4.0 or 2.8
    self.comboTimer = win
    if self.combo > self.maxCombo then self.maxCombo = self.combo end
    Emit(self.fx, "OnCombo", self.combo)
end

function Tycoon:HandlePegHit(coin, peg, hitSpd)
    local pDef = Config.PEG_TYPES[peg.kind] or Config.PEG_TYPES.normal
    local spd = hitSpd or 0
    if spd >= 80 then
        if pDef.fever then self:AddFever(pDef.fever * 0.45) end
        if (coin.pegCashHits or 0) < 3 then
            coin.pegCashHits = (coin.pegCashHits or 0) + 1
            local pegMul = (1 + (self.machineLv.peg_gold or 0) * 0.05) * ((peg.kind == "mult") and 2.0 or 1.0)
            self:AwardCash(self:GetAvgUnlockedCoinValue() * 0.015 * pegMul, peg.x, peg.y, "peg", false)
        end
    end
    Emit(self.fx, "OnPegHit", coin, peg)

    local cDef = Config.COINS[coin.kind]
    if cDef and cDef.splitCount and not coin.splitDone then
        coin.splitDone = true
        local cnt = cDef.splitCount + ((coin.kind == "hydra") and 1 or 0)
        for k = 1, cnt do
            local ang = (k - (cnt + 1) * 0.5) * 52
            self.physics:SpawnCoin({
                kind = "mini", level = coin.level,
                x = coin.x + ang * 0.12, y = coin.y + 4,
                vx = coin.vx * 0.5 + ang * 2.1, vy = max(60, coin.vy * 0.8),
                radiusMul = 0.72, isMini = true, splitDone = true,
            })
        end
        Emit(self.fx, "OnSplit", coin.x, coin.y, cnt)
    elseif cDef and cDef.bounceSpawn and spd >= 70 and coin.bounceCount <= 2 then
        self.physics:SpawnCoin({
            kind = "mini", level = coin.level,
            x = coin.x, y = coin.y + 4,
            vx = (coin.id % 2 == 0) and 65 or -65, vy = 90,
            radiusMul = 0.72, isMini = true, splitDone = true,
        })
    end

    if peg.kind == "split" and not coin.isMini and not coin.splitDone then
        coin.splitDone = true
        self.physics:SpawnCoin({
            kind = "mini", level = 1, x = coin.x + 6, y = coin.y + 4,
            vx = -coin.vx * 0.7, vy = max(80, coin.vy),
            radiusMul = 0.72, isMini = true, splitDone = true,
        })
    elseif peg.kind == "bolt" and spd >= 80 and (coin.pegCashHits or 0) <= 3 then
        self:TriggerLightning(peg.x, peg.y, 2, coin.level)
    end
end

function Tycoon:RollSlotOutcome()
    local gateLv = self.machineLv.gate_master or 0
    local cloverMul = self:HasTech("clover") and 1.85 or 1.0
    local boost = (1 + gateLv * 0.08) * cloverMul

    local prizeId, reels
    if self.slotPity >= 8 then
        self.slotPity = 0
        if self.rng() < 0.35 then
            prizeId = "triple_bolt"
            reels = { 3, 3, 3 }
        else
            prizeId = "triple_low"
            local s = (self.rng() < 0.5) and 1 or 2
            reels = { s, s, s }
        end
    else
        local u = self.rng() * 100
        local p100 = min(0.6, 0.2 * boost)
        local p10  = min(3.5, 1.5 * boost)
        local p5   = min(7.0, 3.5 * boost)
        local p3   = min(12.0, 7.0 * boost)
        local p2   = min(18.0, 13.0 * (1 + gateLv * 0.02))
        local p15  = 28.0

        if u < p100 then
            prizeId = "jackpot_777"; reels = { 6, 6, 6 }
        elseif u < p100 + p10 then
            prizeId = "triple_crown"; reels = { 5, 5, 5 }
        elseif u < p100 + p10 + p5 then
            prizeId = "triple_gem"; reels = { 4, 4, 4 }
        elseif u < p100 + p10 + p5 + p3 then
            prizeId = "triple_bolt"; reels = { 3, 3, 3 }
        elseif u < p100 + p10 + p5 + p3 + p2 then
            prizeId = "triple_low"
            local s = (self.rng() < 0.5) and 1 or 2
            reels = { s, s, s }
        elseif u < p100 + p10 + p5 + p3 + p2 + p15 then
            prizeId = "pair"
            local s = floor(self.rng() * 5) + 1
            local o = (s % 6) + 1
            reels = { s, s, o }
        else
            prizeId = "miss"
            local a = floor(self.rng() * 6) + 1
            local b = (a % 6) + 1
            local c = ((a + 2) % 6) + 1
            reels = { a, b, c }
        end

        if prizeId == "miss" or prizeId == "pair" then
            self.slotPity = self.slotPity + 1
        else
            self.slotPity = 0
        end
    end

    local prizeDef = Config.SLOT_PRIZES[prizeId] or Config.SLOT_PRIZES.miss

    -- 九宫格：中奖线放入 reels，其余格随机且不得意外连成三连；JP 宝箱只放在中奖线外
    local winLine = nil
    if prizeId ~= "miss" then
        winLine = self:PickSlotLine()
    end
    local chests, jpLine = self:RollJpChests(winLine)
    if jpLine then
        winLine, prizeDef, reels = nil, Config.SLOT_PRIZES.miss, { JP_SYM, JP_SYM, JP_SYM }
    end
    local grid = self:BuildSlotGrid(reels, winLine, chests, jpLine)
    -- 听牌：本次会凑满 JP 灯 / 宝箱连线 / 10 倍以上大奖 -> 第三列拖长停轮
    local reach = (jpLine ~= nil) or ((self.jpLamps or 0) + chests >= JP.LAMPS) or (prizeDef.mult >= 10)
    return {
        reels = reels, prize = prizeDef, grid = grid, winLine = winLine,
        chests = chests, jpLine = jpLine, reach = reach,
    }
end

function Tycoon:PickSlotLine()
    local w = Config.SLOT_LINE_WEIGHTS
    local total = 0
    for i = 1, #w do total = total + w[i] end
    local u = self.rng() * total
    for i = 1, #w do
        u = u - w[i]
        if u < 0 then return i end
    end
    return 1
end

--- 本次转动出现几个 JP 宝箱（天井：距上次 JP 越久越容易出）；极小概率 3 宝箱直接连线
function Tycoon:RollJpChests(winLine)
    if self.jpPhase then return 0, nil end
    local over = max(0, (self.jpSince or 0) - JP.CHEST_CEIL_START)
    local p = min(0.85, JP.CHEST_BASE + over * JP.CHEST_CEIL_RAMP)
    if self.rng() < JP.LINE_CHANCE then
        local ln = floor(self.rng() * #Config.SLOT_LINES) + 1
        return 0, ln
    end
    local n = 0
    if self.rng() < p then
        n = 1
        if self.rng() < p * 0.30 then n = 2 end
    end
    return n, nil
end

function Tycoon:BuildSlotGrid(reels, winLine, chests, jpLine)
    local lines = Config.SLOT_LINES
    local g = {}
    local fixed = {}
    local fixLine = winLine or jpLine
    if fixLine then
        local ln = lines[fixLine]
        for k = 1, 3 do
            g[ln[k]] = (reels and reels[k]) or 1
            fixed[ln[k]] = true
        end
    end
    local free = {}
    for i = 1, 9 do
        if not fixed[i] then free[#free + 1] = i end
    end
    for _ = 1, (chests or 0) do
        if #free == 0 then break end
        local j = floor(self.rng() * #free) + 1
        g[free[j]] = JP_SYM
        table.remove(free, j)
    end
    for _ = 1, 24 do
        for k = 1, #free do g[free[k]] = floor(self.rng() * 6) + 1 end
        local clean = true
        for li = 1, #lines do
            if li ~= fixLine then
                local ln = lines[li]
                local a, b, c = g[ln[1]], g[ln[2]], g[ln[3]]
                if a == b and b == c then clean = false; break end
            end
        end
        if clean then break end
    end
    return g
end

function Tycoon:StartNextSlotSpin()
    if self.slotQueue <= 0 or self.jpPhase then return false end
    self.slotQueue = self.slotQueue - 1
    self.slotSpinning = true
    self.slotSpinT = 0
    self.slotWinLine = nil
    local pending = self:RollSlotOutcome()
    self.slotPending = pending
    if pending.reach then
        self.slotSpinDur = 2.1
        self.slotLockAt = REACH_LOCK_AT
    else
        self.slotSpinDur = 0.85
        self.slotLockAt = nil
    end
    return true
end

function Tycoon:QueueSlotSpin()
    if (self.slotCd or 0) > 0 or (self.slotQueue or 0) >= 2 then
        return false
    end
    self.slotQueue = min(2, (self.slotQueue or 0) + 1)
    self.slotCd = 9.0
    if not self.slotSpinning and not self.jpPhase then
        self:StartNextSlotSpin()
    end
    return true
end

function Tycoon:ResolveSlotSpin(pending)
    if not pending or not pending.prize then return end
    local prize = pending.prize
    self.slotFlashT = (prize.mult >= 10) and 1.2 or ((prize.mult > 1) and 0.7 or 0.35)

    -- 高倍激活时：低奖不续命、同档仅重置至本档上限，绝不无限叠时常驻
    if prize.mult > (self.luckMult or 1) then
        self.luckMult = prize.mult
        self.luckTimer = prize.dur
        self.luckDur = prize.dur
        self.luckName = prize.label
    elseif prize.mult > 1 and prize.mult == (self.luckMult or 1) then
        self.luckTimer = max(self.luckTimer or 0, prize.dur)
        self.luckDur = max(self.luckDur or prize.dur, prize.dur)
    end

    -- 幸运三连奖励空投金币雨 / 闪电 / 45倍金库巨币
    local rainCnt = prize.rain or 0
    local hi = self:GetHighestUnlockedCoin()
    for k = 1, rainCnt do
        local useKind = (k == 1 and prize.mult >= 5) and hi or "gold"
        self.physics:SpawnCoin({
            kind = useKind, level = self.coinLv[useKind] or 1,
            x = 100 + ((k * 37) % 160), y = S.DECK_TOP_Y + 26 + (k % 3) * 8,
            vx = ((k % 3) - 1) * 30, vy = 50,
            zone = "deck", gateChecked = true, isRain = true,
        })
    end
    if prize.lightning then
        self:TriggerLightning(self.physics.gateX or 180, S.DECK_TOP_Y + 40, 5, 1)
    end
    if prize.vault and prize.vault > 0 then
        for v = 1, prize.vault do
            self.physics:SpawnCoin({
                kind = "vault", level = 1,
                x = 150 + (v - 1) * 60, y = S.DECK_TOP_Y + 42,
                vx = (v == 1) and -10 or 10, vy = 55,
                zone = "deck", gateChecked = true,
            })
        end
    end

    Emit(self.fx, "OnSlotWin", prize)

    -- JP：宝箱点灯 / 没中奖也往奖池里塞一点养分 / 集满或宝箱连线 -> JP CHANCE
    if prize.mult <= 1 then
        self:FeedJackpot(self:GetJpBase() * JP.FEED_SLOT_MISS_SEC)
    end
    local chests = pending.chests or 0
    if chests > 0 and not self.jpPhase then
        self.jpLamps = min(JP.LAMPS, (self.jpLamps or 0) + chests)
        Emit(self.fx, "OnJpLamp", self.jpLamps, chests)
    end
    if pending.jpLine or (self.jpLamps or 0) >= JP.LAMPS then
        self:StartJpChance(pending.jpLine and "line" or "lamps")
    end
end

function Tycoon:HandleGateWin(coin)
    self:AddFever(10)
    self:RegisterCombo()
    local gateLv = self.machineLv.gate_master or 0
    local dropCnt = min(2, 1 + floor(gateLv / 10)) + ((coin.kind == "emerald") and 1 or 0)
    local spawnKind = self:GetHighestUnlockedCoin()
    for k = 1, dropCnt do
        local useKind = (k == 1) and spawnKind or "gold"
        self.physics:SpawnCoin({
            kind = useKind, level = self.coinLv[useKind] or 1,
            x = 110 + (k % 4) * 38, y = S.DECK_TOP_Y + 28 + k * 4,
            vx = ((k % 3) - 1) * 32, vy = 45, zone = "deck", gateChecked = true, isRain = true,
        })
    end
    self:AwardCash(self:GetCoinUnitValue(coin.kind, coin.level) * (0.18 + gateLv * 0.025), coin.x, coin.y, "gate", true)
    local queued = self:QueueSlotSpin()
    local rewardName = queued and string.format("过门 ×%d + 幸运三连!", dropCnt) or string.format("过门落币 ×%d!", dropCnt)
    Emit(self.fx, "OnGateWin", coin, rewardName)
end

function Tycoon:HandleEnterDeck(coin)
    local def = Config.COINS[coin.kind]
    if def and def.shockwave then
        self.physics:ApplyExplosion(coin.x, coin.y, 115, def.shockwave)
        Emit(self.fx, "OnExplosion", coin.x, coin.y, 115)
    end
    if coin.kind == "thor" or coin.kind == "thunder" then
        self:TriggerLightning(coin.x, coin.y, (def and def.chainJumps) or 3, coin.level)
    end
    Emit(self.fx, "OnCoinLandDeck", coin)
end

function Tycoon:TriggerLightning(sx, sy, jumps, level)
    local totalJumps = jumps + (self:HasTech("tesla_coil") and 2 or 0)
    local cx, cy = sx, sy
    local coins = self.physics.coins
    local ids = self.physics.activeIds
    local n = self.physics.activeCount
    local val = self:GetAvgUnlockedCoinValue() * 0.25 * (1 + (level or 1) * 0.2)
    for _ = 1, totalJumps do
        local best, bestD2 = nil, 135 * 135
        for k = 1, n do
            local t = coins[ids[k]]
            if t.active and t.zone == "deck" then
                local dx, dy = t.x - cx, t.y - cy
                local d2 = dx * dx + dy * dy
                if d2 > 36 and d2 < bestD2 then bestD2 = d2; best = t end
            end
        end
        if not best then break end
        Emit(self.fx, "OnLightning", cx, cy, best.x, best.y)
        best.vy = best.vy + 35
        cx, cy = best.x, best.y
        self:AwardCash(val, cx, cy, "thunder", true)
    end
end

function Tycoon:HandleBombExplode(coin)
    local def = Config.COINS[coin.kind] or Config.COINS.bomb
    local rad = (def.explodeRadius or 72) * (self:HasTech("powder_keg") and 1.35 or 1.0)
    local force = (def.explodeForce or 240) * (self:HasTech("powder_keg") and 1.35 or 1.0)
    self.physics:ApplyExplosion(coin.x, coin.y, rad, force)
    self:AddFever(coin.kind == "supernova" and 35 or 12)
    self:RegisterCombo()
    self:AwardCash(self:GetCoinUnitValue(coin.kind, coin.level) * 1.6, coin.x, coin.y, coin.kind, true)
    Emit(self.fx, "OnExplosion", coin.x, coin.y, rad)
    if def.doubleBlast then
        self.physics:ApplyExplosion(coin.x, coin.y + 18, rad * 0.9, force * 0.8)
    end
end

function Tycoon:HandleBlackholeBurst(coin)
    local def = Config.COINS[coin.kind] or Config.COINS.blackhole
    local rad = def.bhRadius or 92
    self.physics:ApplyExplosion(coin.x, coin.y - 14, rad, 210)
    self:RegisterCombo()
    self:AwardCash(self:GetCoinUnitValue(coin.kind, coin.level) * 1.4, coin.x, coin.y, coin.kind, true)
    Emit(self.fx, "OnBlackholeBurst", coin.x, coin.y, rad)
end

function Tycoon:HandleOverclockCoin(coin)
    if not self:HasTech("overclock") then return end
    local val = self:GetCoinUnitValue(coin.kind, coin.level) * 0.20
    self:AwardCash(val, coin.x, coin.y, "overclock", false)
end

function Tycoon:HandleFrontDrop(coin)
    self.totalDrops = self.totalDrops + 1
    local val = self:GetCoinUnitValue(coin.kind, coin.level) * (coin.valueMul or 1.0)
    local def = Config.COINS[coin.kind]
    if coin.frostT > 0 then val = val * 2.0 end
    if coin.kind == "giant" then val = val * 2.5 end
    if coin.fromManual then
        local manMul = min(1.25, 1.10 + 0.008 * self:CountUnlockedCoins())
        val = val * manMul
    end
    if coin.kind == "vault" then val = self:GetCoinUnitValue(self:GetHighestUnlockedCoin()) * 45 end

    if def and def.feverExtend and self.feverActive and not self.feverExtended then
        self.feverExtended = true
        self.feverTimer = min(24, self.feverTimer + 2.0)
        self.feverDur = max(self.feverDur or 8, self.feverTimer)
    end
    self:AddFever((def and def.feverGain or 6) * 0.65)
    self:RegisterCombo()

    if coin.kind == "thunder" or coin.kind == "thor" then
        self:TriggerLightning(coin.x, S.DECK_BOT_Y - 35, (def and def.chainJumps) or 3, coin.level)
    elseif coin.kind == "frost" then
        local cList, ids = self.physics.coins, self.physics.activeIds
        local marked = 0
        for k = 1, self.physics.activeCount do
            local other = cList[ids[k]]
            if other.active and other.zone == "deck" and marked < 5 then
                other.frostT = 8.0
                marked = marked + 1
            end
        end
    elseif coin.kind == "midas" then
        local cList, ids = self.physics.coins, self.physics.activeIds
        local hi = self:GetHighestUnlockedCoin()
        local turned = 0
        for k = 1, self.physics.activeCount do
            local other = cList[ids[k]]
            if other.active and other.zone == "deck" and other.kind == "gold" and turned < 4 then
                other.kind = hi
                turned = turned + 1
            end
        end
    elseif def and def.roll777 then
        local p = self:HasTech("clover") and 0.65 or 0.42
        if self.rng() < p then
            val = val * 2.5
            local rainK = self:GetHighestUnlockedCoin()
            for k = 1, 5 do
                self.physics:SpawnCoin({
                    kind = rainK, level = self.coinLv[rainK] or 1,
                    x = 110 + k * 28, y = S.DECK_TOP_Y + 34,
                    vx = (k - 3) * 28, vy = 55, zone = "deck", gateChecked = true, isRain = true,
                })
            end
            Emit(self.fx, "OnJackpot777", coin.x, coin.y)
        end
    end

    if self:HasTech("medkit") and (self.totalDrops % 10 == 0) then
        val = val * 2.5
    end

    local dmg, crit = self:AwardCash(val, coin.x, coin.y - 12, coin.kind, true)
    Emit(self.fx, "OnFrontDrop", coin, dmg, crit)

    -- 前沿落币砸中拖金袋小人 -> 弹出 12 面骰子奇遇
    local runEnt = self.runner
    if runEnt and runEnt.active and not self.pendingDice and abs((coin.x or 180) - (runEnt.x or 180)) <= 36 then
        self:HitRunner(coin.x)
    end

    -- 突发黄金暴走：每累计一定落币随机无预警触发高倍 + 币雨（仅在不冲突高倍奇遇时触发）
    if self.totalDrops >= (self.goldRushNext or 150) then
        if (self.surpriseMult or 1) >= 15 and (self.surpriseTimer or 0) > 2 then
            self.goldRushNext = self.totalDrops + 15
        else
            self.goldRushNext = self.totalDrops + 150 + floor(self.rng() * 90)
            self:TriggerGoldRush()
        end
    end
end

function Tycoon:HandleSideDrain(coin)
    self:FeedJackpot(self:GetCoinUnitValue(coin.kind, coin.level) * self:GetTotalMult() * JP.FEED_SIDE_DRAIN)
    if self:HasTech("recycler") then
        local val = self:GetCoinUnitValue(coin.kind, coin.level) * 0.5
        self:AwardCash(val, coin.x, coin.y, "recycler", false)
    end
    Emit(self.fx, "OnSideDrain", coin)
end

-- ----------------------------------------------------------------------------
-- JP 大奖池：持续养分 -> 7 盏 JP 灯 -> JP CHANCE 九宫格跑灯 -> 一次性倾泻
-- ----------------------------------------------------------------------------
function Tycoon:FeedJackpot(amount)
    local a = tonumber(amount) or 0
    if a ~= a or a <= 0 or a == math.huge then return 0 end
    self.jpPool = (self.jpPool or 0) + a
    return a
end

--- JP 计价基准：最近约 2 分钟真实收入速度（含临时倍率），冷启动时退回基准产值
function Tycoon:GetJpBase()
    return max(1.0, self.jpRefCps or 0, self:GetBaselineCPS())
end

--- 预估某档 JP 当前能拿多少（不含 NEXT 倍数）
function Tycoon:GetJpTierAmount(tierId)
    local tier = JP.TIERS[tierId]
    if not tier or not tier.frac then return 0.0 end
    return max((self.jpPool or 0) * tier.frac, self:GetJpBase() * (tier.floorSec or 0))
end

function Tycoon:IsJpActive()
    return self.jpPhase ~= nil
end

function Tycoon:StartJpChance(source)
    if self.jpPhase then return false end
    self.jpPhase = "intro"
    self.jpT = 0
    self.jpRound = 1
    self.jpBonus = 1
    self.jpResult = nil
    self.jpPayout = nil
    self.jpLamps = JP.LAMPS
    self.jpCell = self.jpCell or 1
    Emit(self.fx, "OnJpChance", self.jpPool, source)
    return true
end

local function RollJpTier(self)
    local odds = JP.ODDS[min(#JP.ODDS, self.jpRound or 1)]
    if (self.jpRound or 1) > (JP.MAX_NEXT or 2) then odds = JP.ODDS[#JP.ODDS] end
    local total = 0
    for _, id in ipairs(JP_TIER_ORDER) do total = total + (odds[id] or 0) end
    local u = self.rng() * total
    for _, id in ipairs(JP_TIER_ORDER) do
        u = u - (odds[id] or 0)
        if u < 0 then return id end
    end
    return "mini"
end

function Tycoon:BeginJpSpin()
    local tierId = RollJpTier(self)
    local cells = {}
    for i, id in ipairs(JP.BOARD) do
        if id == tierId then cells[#cells + 1] = i end
    end
    local target = cells[floor(self.rng() * #cells) + 1] or 1
    local from = self.jpCell or 1
    local laps = 3 + min(2, (self.jpRound or 1) - 1)
    self.jpSpinFrom = from
    self.jpSpinSteps = laps * #JP.BOARD + ((target - from) % #JP.BOARD)
    self.jpResult = tierId
    self.jpPhase = "spin"
    self.jpT = 0
end

--- 跑灯缓动：前段飞快、末段逐格挪动（ease-out quart）
function Tycoon:GetJpSpinCell(t)
    local x = max(0, min(1, (t or self.jpT) / JP.SPIN_SEC))
    local e = 1 - (1 - x) ^ 4
    local step = floor(e * self.jpSpinSteps + 0.0001)
    return ((self.jpSpinFrom - 1 + step) % #JP.BOARD) + 1
end

function Tycoon:UpdateJackpot(dt)
    self.jpT = (self.jpT or 0) + dt
    local ph = self.jpPhase
    if ph == "intro" then
        if self.jpT >= JP.INTRO_SEC then self:BeginJpSpin() end
    elseif ph == "spin" then
        local cell = self:GetJpSpinCell(self.jpT)
        if cell ~= self.jpCell then
            self.jpCell = cell
            Emit(self.fx, "OnJpTick", cell)
        end
        if self.jpT >= JP.SPIN_SEC then
            self.jpCell = self:GetJpSpinCell(JP.SPIN_SEC)
            self.jpPhase = "result"
            self.jpT = 0
            Emit(self.fx, "OnJpResult", self.jpResult, self.jpRound, self.jpBonus)
        end
    elseif ph == "result" then
        if self.jpT >= JP.RESULT_SEC then
            if self.jpResult == "next" then
                self.jpRound = self.jpRound + 1
                self.jpBonus = self.jpBonus + 1
                self:BeginJpSpin()
            else
                self:JpRelease(self.jpResult)
            end
        end
    elseif ph == "release" then
        -- 奖池倾泻：最高阶币瀑布分批落台
        if (self.jpRainLeft or 0) > 0 then
            self.jpRainT = (self.jpRainT or 0) - dt
            while self.jpRainT <= 0 and self.jpRainLeft > 0 do
                self.jpRainT = self.jpRainT + 0.06
                self.jpRainLeft = self.jpRainLeft - 1
                local hi = self:GetHighestUnlockedCoin()
                local k = self.jpRainLeft
                self.physics:SpawnCoin({
                    kind = (k % 9 == 0) and "vault" or hi, level = self.coinLv[hi] or 1,
                    x = 84 + self.rng() * 192, y = S.DECK_TOP_Y + 22 + self.rng() * 30,
                    vx = (self.rng() - 0.5) * 60, vy = 60 + self.rng() * 30,
                    zone = "deck", gateChecked = true, isRain = true, forceSpawn = true,
                })
            end
        end
        if self.jpT >= JP.RELEASE_SEC then
            self.jpPhase = nil
            self.jpT = 0
            self.jpLamps = 0
            self.jpSince = 0
            self.jpRainLeft = 0
            self.jpPendingPopup = self.jpPayout
        end
    end
end

function Tycoon:JpRelease(tierId)
    local tier = JP.TIERS[tierId] or JP.TIERS.mini
    local base = self:GetJpBase()
    local pool = self.jpPool or 0
    local raw = max(pool * tier.frac, base * (tier.floorSec or 0))
    local bonus = max(1, self.jpBonus or 1)
    local amt = floor(raw * bonus) + 0.0
    self.jpPool = max(base * JP.SEED_SEC, pool * (1 - tier.frac)) + 0.0
    self:AddWealth(amt, false)
    self.jpWins = (self.jpWins or 0) + 1
    if amt > (self.jpBest or 0) then self.jpBest = amt end
    self.jpRainLeft = min(48, floor((tier.coins or 14) * (1 + (bonus - 1) * 0.25)))
    self.jpRainT = 0.25
    if tierId == "grand" and not self.feverActive then
        self:TriggerFever(false)
    end
    self.jpPayout = {
        tier = tier.id, name = tier.name, amount = amt, bonus = bonus,
        col = tier.col, adClaimed = false,
    }
    self.jpPhase = "release"
    self.jpT = 0
    Emit(self.fx, "OnJpRelease", self.jpPayout)
    return amt
end

--- 取走待弹窗的 JP 结算（HUD 打开弹窗时调用）
function Tycoon:TakeJpPopup()
    local p = self.jpPendingPopup
    self.jpPendingPopup = nil
    return p
end

--- 看广告再领一份（JP 翻倍）
function Tycoon:ClaimJpAdDouble(payout)
    payout = payout or self.jpPayout
    if not payout or payout.adClaimed then return 0 end
    payout.adClaimed = true
    local amt = (payout.amount or 0) + 0.0
    self.adWatchCount = (self.adWatchCount or 0) + 1
    self:AddWealth(amt, false)
    Emit(self.fx, "OnAdReward", (payout.name or "JP") .. " 翻倍 +" .. Number.FormatCash(amt))
    return amt
end

-- ----------------------------------------------------------------------------
-- 三重突发奇遇惊喜（拖金袋小人 12 面骰 / 空中黄金气球 / 突发黄金暴走）
-- ----------------------------------------------------------------------------
function Tycoon:SpawnRunner()
    local r = self.runner
    if not r then return end
    local dir = (self.rng() < 0.5) and 1 or -1
    r.active = true
    r.dir = dir
    r.x = (dir > 0) and 48 or 312
    r.y = S.DECK_BOT_Y + 14
    r.speed = 40 + self.rng() * 14
end

function Tycoon:HitRunner(hitX)
    local r = self.runner
    if not r or not r.active or self.pendingDice then return nil end
    r.active = false
    r.hitCount = (r.hitCount or 0) + 1
    r.cooldown = 52 + self.rng() * 24
    local face = floor(self.rng() * 12) + 1
    self.pendingDice = {
        face = face,
        mult = face,
        dur = 8,
        rerolled = false,
    }
    Emit(self.fx, "OnRunnerHit", hitX or r.x, r.y, self.pendingDice)
    return self.pendingDice
end

function Tycoon:RollDiceReroll()
    local d = self.pendingDice
    if not d or d.rerolled then return nil end
    if (d.face or 1) <= 6 then
        local face2 = 7 + floor(self.rng() * 6)
        d.face = face2
        d.mult = face2 * 2 -- 14..24 倍
    else
        d.mult = (d.face or 7) * 2 -- 14..24 倍
    end
    d.dur = 60
    d.rerolled = true
    self.adWatchCount = (self.adWatchCount or 0) + 1
    return d
end

function Tycoon:ClaimPendingDice()
    local d = self.pendingDice
    if not d then return 1, 0 end
    self.pendingDice = nil
    local mult = max(1, d.mult or 1)
    local dur = d.dur or 8
    local fromAd = (d.rerolled == true)
    self:ApplySurpriseMult(mult, dur, "12面骰子", fromAd)
    local rainCnt = fromAd and 6 or ((mult <= 1) and 3 or 0)
    if rainCnt > 0 then
        local hi = self:GetHighestUnlockedCoin()
        for k = 1, rainCnt do
            self.physics:SpawnCoin({
                kind = hi, level = self.coinLv[hi] or 1,
                x = 100 + ((k - 1) % 6) * 32, y = S.DECK_TOP_Y + 32,
                vx = (self.rng() - 0.5) * 44, vy = 52, zone = "deck", gateChecked = true, isRain = true, forceSpawn = true,
            })
        end
    end
    return mult, dur
end

local BALLOON_MULTS = { 8, 15, 25 }
function Tycoon:PopBalloon(source)
    local b = self.balloon
    if not b or not b.active then return nil end
    local bx, by = b.x, b.y
    b.active = false
    b.cooldown = 55 + self.rng() * 30
    local r = self.rng()
    local label, kind
    if r < 0.50 then
        local m = BALLOON_MULTS[floor(self.rng() * #BALLOON_MULTS) + 1]
        self:ApplySurpriseMult(m, 12, "黄金气球")
        label = "黄金气球 ×" .. tostring(m) .. " (12秒)!"
        kind = "mult"
    elseif r < 0.75 then
        for v = 1, 3 do
            self.physics:SpawnCoin({
                kind = "vault", level = 1,
                x = 115 + (v - 1) * 65, y = S.DECK_TOP_Y + 38,
                vx = (v - 2) * 18, vy = 50, zone = "deck", gateChecked = true,
            })
        end
        label = "空降 3 枚 45倍金库巨币!"
        kind = "vault"
    else
        local sp = min(20, max(8, 8 + floor((self.rankIdx or 0) / 4)))
        self.skillPoints = self.skillPoints + sp
        self.totalSkillPoints = self.totalSkillPoints + sp
        Emit(self.fx, "OnSkillPointsGain", sp)
        label = "技能点福袋 +" .. tostring(sp) .. "点!"
        kind = "sp"
    end
    Emit(self.fx, "OnBalloonPop", bx, by, label, kind)
    return kind, label
end

local GOLDRUSH_MULTS = { 10, 12, 15, 20 }
function Tycoon:TriggerGoldRush()
    local m = GOLDRUSH_MULTS[floor(self.rng() * #GOLDRUSH_MULTS) + 1]
    local dur = 10
    self:ApplySurpriseMult(m, dur, "黄金暴走")
    local hi = self:GetHighestUnlockedCoin()
    for k = 1, 12 do
        self.physics:SpawnCoin({
            kind = hi, level = self.coinLv[hi] or 1,
            x = 92 + ((k - 1) % 6) * 35, y = S.DECK_TOP_Y + 26 + floor((k - 1) / 6) * 18,
            vx = (self.rng() - 0.5) * 46, vy = 54, zone = "deck", gateChecked = true, isRain = true,
        })
    end
    Emit(self.fx, "OnGoldRush", m, dur)
    return m, dur
end

-- ----------------------------------------------------------------------------
-- 购买与养成 API（全部消耗技能点 SP，绝不扣除玩家辛辛苦苦攒的财富！+ 资本上市敲钟）
-- ----------------------------------------------------------------------------
function Tycoon:GetMachineCost(id, modeOverride)
    local def = Config.MACHINE_BY_ID[id]
    if not def then return math.huge, 0 end
    local cur = self.machineLv[id] or 0
    if cur >= def.maxLv then return 0, 0 end
    local mode = modeOverride or self.buyMode or 1
    local function lvCost(lv)
        return max(1, floor(def.baseSp + lv * def.spStep + lv * lv * (def.spQuad or 0)))
    end

    if mode == 1 then
        local c1 = lvCost(cur)
        return c1, (self.skillPoints >= c1 and 1 or 0)
    elseif mode == 10 then
        local n = min(10, def.maxLv - cur)
        local sum = 0
        for i = 0, n - 1 do
            sum = sum + lvCost(cur + i)
        end
        return sum, (self.skillPoints >= sum and n or 0)
    else
        local firstCost = lvCost(cur)
        if self.skillPoints < firstCost then return firstCost, 0 end
        local sum, cnt = 0, 0
        for i = 0, (def.maxLv - cur - 1) do
            local c = lvCost(cur + i)
            if sum + c > self.skillPoints then break end
            sum = sum + c
            cnt = cnt + 1
        end
        return sum, cnt
    end
end

function Tycoon:BuyMachineUpgrade(id, modeOverride)
    local def = Config.MACHINE_BY_ID[id]
    if not def then return false end
    local cur = self.machineLv[id] or 0
    if cur >= def.maxLv then return false end
    local cost, cnt = self:GetMachineCost(id, modeOverride)
    if cnt <= 0 or self.skillPoints < cost then return false end
    self.skillPoints = self.skillPoints - cost
    self.machineLv[id] = cur + cnt
    if id == "peg_gold" then
        self.physics:BuildPegs(min(14, self.machineLv.peg_gold))
    end
    self:SyncPhysicsMods()
    return true, cnt
end

function Tycoon:IsCoinPrereqMet(id)
    local t = Config.COIN_TIER_BY_ID[id]
    if not t then return false end
    if t.order <= 1 then return true end
    local prev = Config.COIN_TIERS[t.order - 1]
    return prev ~= nil and (self.coinLv[prev.id] or 0) > 0
end

function Tycoon:GetCoinCost(id)
    local t = Config.COIN_TIER_BY_ID[id]
    if not t then return math.huge, false, true end
    local cur = self.coinLv[id] or 0
    if cur >= t.maxLv then return 0, true, false end
    if cur == 0 then
        local lockedByPrev = not self:IsCoinPrereqMet(id)
        local cost = t.unlockSp
        -- 若父辈进化配方两枚币均已 >= Lv3，解锁技能点享 5 折
        if t.parents and (self.coinLv[t.parents[1]] or 0) >= 3 and (self.coinLv[t.parents[2]] or 0) >= 3 then
            cost = max(1, floor(cost * 0.5 + 0.5))
        end
        return cost, false, lockedByPrev
    end
    local up = max(1, floor(t.upBaseSp + (cur - 1) * t.upStepSp + 0.5))
    return up, false, false
end

function Tycoon:BuyCoin(id)
    local t = Config.COIN_TIER_BY_ID[id]
    if not t then return false end
    local cur = self.coinLv[id] or 0
    if cur >= t.maxLv then return false end
    local cost, maxed, lockedByPrev = self:GetCoinCost(id)
    if maxed or lockedByPrev or self.skillPoints < cost then return false end
    self.skillPoints = self.skillPoints - cost
    local isUnlock = (cur == 0)
    self.coinLv[id] = cur + 1
    self:RebuildCoinCache()

    -- 刚解锁或升星时立刻空投3枚对应炫酷硬币上台！
    for k = 1, 3 do
        self.physics:SpawnCoin({
            kind = id, level = self.coinLv[id],
            x = 135 + (k - 1) * 45, y = S.SLOT_TOP + 34,
            vx = (k - 2) * 28, vy = 120, zone = "slot",
        })
    end
    if isUnlock then
        Emit(self.fx, "OnUnlockCoin", Config.COINS[id])
    end
    return true, isUnlock
end

function Tycoon:BuyTech(id)
    local t = Config.TECH_BY_ID[id]
    if not t or self.techOwned[id] then return false end
    if self.skillPoints < t.costSp then return false end
    self.skillPoints = self.skillPoints - t.costSp
    self.techOwned[id] = true
    if id == "big_pouch" then
        local hi = self:GetHighestUnlockedCoin()
        for k = 1, 4 do
            self.physics:SpawnCoin({
                kind = hi, level = self.coinLv[hi] or 1,
                x = 108 + (k - 1) * 48, y = S.DECK_TOP_Y + 34,
                vx = (k - 2.5) * 18, vy = 45, zone = "deck", gateChecked = true, isRain = true,
            })
        end
    end
    self:SyncPhysicsMods()
    Emit(self.fx, "OnUnlockCoin", { name = t.name })
    return true
end

-- 资本融资 / 敲钟上市公式（方案 A：不清空财富与进度！）
function Tycoon:GetNextIpoInfo()
    return Config.GetIpoRound((self.ipoRound or 0) + 1)
end

function Tycoon:CanDoIpo()
    local r = self:GetNextIpoInfo()
    return self.lifetimeCash >= r.targetWealth
end

function Tycoon:CalcPendingShares()
    local r = self:GetNextIpoInfo()
    return (self.lifetimeCash >= r.targetWealth) and r.shares or 0
end

function Tycoon:GetNextPrestigeRequirement()
    return self:GetNextIpoInfo().targetWealth
end

function Tycoon:CanAscendEra()
    return (self.rankIdx or 0) >= #Config.RANKS and self.lifetimeCash >= 6.041e12 * pow(10, self.era or 0)
end

function Tycoon:GetEraAscendTarget()
    return 6.041e12 * pow(10, self.era or 0)
end

function Tycoon:GetEraTitle()
    local e = self.era or 0
    if e <= 0 then return nil end
    local titles = Config.GALACTIC_TITLES or {}
    return titles[min(e, #titles)] or ("宇宙财阀 Era " .. tostring(e + 1))
end

function Tycoon:DoGalacticAscend()
    if not self:CanAscendEra() then return 0, 0 end
    self.era = (self.era or 0) + 1
    local shares = 25 * self.era
    local bonusSp = 40 * self.era
    self.prestigeShares = self.prestigeShares + shares
    self.skillPoints = self.skillPoints + bonusSp
    self.totalSkillPoints = self.totalSkillPoints + bonusSp
    self:InvalidateCaches()
    self:SyncPhysicsMods()
    Emit(self.fx, "OnPrestige", shares, bonusSp, self:GetEraTitle() or "星际飞升")
    return shares, bonusSp
end

function Tycoon:GetTalentCost(id)
    local def = Config.PRESTIGE_BY_ID[id]
    if not def then return math.huge, true end
    local cur = self.prestigeLv[id] or 0
    if cur >= def.maxLv then return 0, true end
    return floor(def.baseCost * pow(def.growth, cur) + 0.5), false
end

function Tycoon:BuyPrestigeTalent(id)
    local def = Config.PRESTIGE_BY_ID[id]
    if not def then return false end
    local cur = self.prestigeLv[id] or 0
    if cur >= def.maxLv then return false end
    local cost = self:GetTalentCost(id)
    if self.prestigeShares < cost then return false end
    self.prestigeShares = self.prestigeShares - cost
    self.prestigeLv[id] = cur + 1
    self:SyncPhysicsMods()
    return true
end

function Tycoon:DoCapitalIPO(isDoubleAd)
    if not self:CanDoIpo() then return 0, 0 end
    local r = self:GetNextIpoInfo()
    self.ipoRound = (self.ipoRound or 0) + 1
    self.totalPrestiges = (self.totalPrestiges or 0) + 1
    local shares = r.shares
    if isDoubleAd then
        shares = shares * 2
        self.adWatchCount = self.adWatchCount + 1
    end
    local bonusSp = r.bonusSp or 0
    self.prestigeShares = self.prestigeShares + shares
    self:InvalidateCaches()
    self.skillPoints = self.skillPoints + bonusSp
    self.totalSkillPoints = self.totalSkillPoints + bonusSp
    Emit(self.fx, "OnPrestige", shares, bonusSp, r.name)
    return shares, bonusSp
end

Tycoon.DoPrestige = Tycoon.DoCapitalIPO

-- 模拟广告与风投空投发奖（全部按去瞬时倍率的基准产值计算）
function Tycoon:GetAdCooldown(id)
    return max(0, self.adCooldowns[id] or 0)
end

function Tycoon:GetAirdropPreview()
    local effCps = max(self:GetBaselineCPS(), self:GetEstimatedCPS() * 0.55)
    local freeCash = max(300.0, floor(effCps * 12) + 0.0)
    local adCash = max(5000.0, floor(max(effCps * 180, (self.lifetimeCash or 0) * 0.18)) + 0.0)
    local adSp = min(60, max(25, 25 + floor((self.rankIdx or 0) / 2)))
    return {
        freeCash = freeCash,
        freeCoins = 4,
        adCash = adCash,
        adCoins = 20,
        adVaults = 4,
        adSp = adSp,
        adBuffMult = 5,
        adBuffDur = 60,
    }
end

function Tycoon:ApplyAdReward(placementId)
    local def = Config.AD_PLACEMENTS[placementId]
    if not def then return false, nil end
    self.adWatchCount = self.adWatchCount + 1
    if (def.cooldown or 0) > 0 then
        self.adCooldowns[placementId] = def.cooldown
    end

    if placementId == "boost_3x" then
        self.adBoostLeft = min(300, self.adBoostLeft + 180)
        Emit(self.fx, "OnAdReward", "超级印钞 ×3 激活!")
        return true, "全场收益 ×3 生效 180 秒（上限 300 秒）"
    elseif placementId == "instant_fever" then
        self:TriggerFever(true)
        Emit(self.fx, "OnAdReward", "60秒满槽超级狂欢!")
        return true, "60 秒超级狂欢极速 + 40 枚高阶金币雨!"
    elseif placementId == "vault_drop" then
        local hi = self:GetHighestUnlockedCoin()
        local hiLv = self.coinLv[hi] or 1
        self.physics:StartCoinTower({
            x = 180, y = 446, kind = hi, level = hiLv,
            crownKind = "vault", crownLevel = 1,
            layers = 24, radius = 34,
            layerInterval = 0.055, holdDur = 0.55, toppleDur = 0.72,
            avalancheCoins = 24, avalancheVaults = 2,
            label = "摩天金库巨塔落成！", announceComplete = true,
        })
        Emit(self.fx, "OnAdReward", "24层摩天金库巨塔建造中!")
        return true, "台面正中正筑起 24 层六柱螺旋金库塔（含 24 高阶币 + 2 枚 45 倍金库巨币），成塔倾倒!"
    elseif placementId == "airdrop_5x" then
        local pv = self:GetAirdropPreview()
        local amt = pv.adCash
        self:AddWealth(amt, false)
        local hi = self:GetHighestUnlockedCoin()
        local hiLv = self.coinLv[hi] or 1
        self.physics:StartCoinTower({
            x = 180, y = 442, kind = hi, level = hiLv,
            crownKind = "vault", crownLevel = 1,
            layers = 22, radius = 34,
            layerInterval = 0.058, holdDur = 0.55, toppleDur = 0.72,
            avalancheCoins = pv.adCoins, avalancheVaults = pv.adVaults,
            label = "风投摩天巨塔落成！", announceComplete = true,
        })
        self:ApplySurpriseMult(pv.adBuffMult or 5, pv.adBuffDur or 60, "风投狂飙", true)
        self.skillPoints = self.skillPoints + pv.adSp
        self.totalSkillPoints = self.totalSkillPoints + pv.adSp
        Emit(self.fx, "OnSkillPointsGain", pv.adSp)
        self.activeAirdrop = nil
        Emit(self.fx, "OnAdReward", string.format("风投暴富 +%s · +%d技能点 · 60秒×5!", Number.FormatCash(amt), pv.adSp))
        return true, string.format("到账 %s + %d技能点 + 22层金库巨塔(含4巨币) + 60秒全场×5!", Number.FormatCash(amt), pv.adSp)
    end
    return true, "奖励已发放"
end

function Tycoon:ClaimAirdrop(isAd)
    local air = self.activeAirdrop
    if not air then return 0 end
    if isAd then
        local pv = self:GetAirdropPreview()
        self:ApplyAdReward("airdrop_5x")
        return pv.adCash
    end
    local pv = self:GetAirdropPreview()
    local amt = pv.freeCash + 0.0
    self:AddWealth(amt, false)
    local hi = self:GetHighestUnlockedCoin()
    for k = 1, pv.freeCoins do
        self.physics:SpawnCoin({
            kind = hi, level = self.coinLv[hi] or 1,
            x = 120 + (k - 1) * 40, y = 436,
            z = 76, vz = -250,
            vx = (k - 2.5) * 14, vy = 22,
            zone = "deck", onPusher = false, gateChecked = true, forceSpawn = true,
        })
    end
    self.activeAirdrop = nil
    Emit(self.fx, "OnAdReward", "风投空投 +" .. Number.FormatCash(amt))
    return amt
end

function Tycoon:CalcOfflineEarnings(nowTs)
    if not self.lastActiveAt or self.lastActiveAt <= 0 then return 0.0, 0 end
    local elapsed = max(0, (nowTs or os.time()) - self.lastActiveAt)
    if elapsed < 30 then return 0.0, elapsed end
    local capped = min(8 * 3600, elapsed)
    local rate = (self.longTermBaseCps and self.longTermBaseCps > 0) and self.longTermBaseCps or self:GetBaselineCPS()
    local amt = max(50.0, floor(capped * rate * 0.65) + 0.0)
    return amt, elapsed
end

function Tycoon:ClaimOffline(amt, isDouble)
    local gain = floor((amt or 0) * (isDouble and 2 or 1)) + 0.0
    if gain <= 0 then return 0.0 end
    if isDouble then self.adWatchCount = self.adWatchCount + 1 end
    self:AddWealth(gain, false)
    Emit(self.fx, "OnAdReward", "离线收益 +" .. Number.FormatCash(gain))
    return gain
end

function Tycoon:ClaimRedeemCode(rawCode, redeemedMap)
    local ok, msg, def = RedeemCodes.Claim(rawCode, redeemedMap)
    if not ok then return false, msg end
    if def.cashSeconds then
        local addCash = max(def.minCash or 0, floor(self:GetBaselineCPS() * def.cashSeconds) + 0.0)
        self:AddWealth(addCash, false)
    end
    if def.shares then
        self.prestigeShares = self.prestigeShares + def.shares
        self:InvalidateCaches()
    end
    if def.boostSec then
        self.adBoostLeft = min(300, self.adBoostLeft + def.boostSec)
    end
    if def.triggerFever then
        self:TriggerFever(true)
    end
    if def.dropBonusCoins then
        local hi = self:GetHighestUnlockedCoin()
        for k = 1, def.dropBonusCoins do
            self.physics:SpawnCoin({
                kind = hi, level = self.coinLv[hi] or 1,
                x = 110 + (k % 5) * 35, y = S.DECK_TOP_Y + 32,
                vx = (k - 5) * 12, vy = 45, zone = "deck", gateChecked = true, isRain = true,
            })
        end
    end
    self:CheckSpMilestones()
    self:CheckRankUp()
    return true, msg
end

-- ----------------------------------------------------------------------------
-- 「哪里亮点哪里」红点汇总（复用缓冲表，零每帧GC分配）
-- ----------------------------------------------------------------------------
function Tycoon:GetRedDots()
    local machineN, coinsN, techN, prestigeN, welfareN = 0, 0, 0, 0, 0

    for _, m in ipairs(Config.MACHINE_UPGRADES) do
        local _, cnt = self:GetMachineCost(m.id, 1)
        if cnt > 0 then machineN = machineN + 1 end
    end
    for _, t in ipairs(Config.COIN_TIERS) do
        if (self.coinLv[t.id] or 0) < t.maxLv then
            local cost, maxed, locked = self:GetCoinCost(t.id)
            if (not maxed) and (not locked) and self.skillPoints >= cost then
                coinsN = coinsN + 1
            end
        end
    end
    for _, t in ipairs(Config.TECH_UPGRADES) do
        if (not self.techOwned[t.id]) and self.skillPoints >= t.costSp then
            techN = techN + 1
        end
    end
    if self:CanDoIpo() or self:CanAscendEra() then prestigeN = prestigeN + 1 end
    for _, p in ipairs(Config.PRESTIGE_TALENTS) do
        local cost, maxed = self:GetTalentCost(p.id)
        if (not maxed) and self.prestigeShares >= cost then
            prestigeN = prestigeN + 1
        end
    end
    for _, pid in ipairs(Config.AD_WELFARE_ORDER) do
        if self:GetAdCooldown(pid) <= 0 then
            welfareN = welfareN + 1
        end
    end

    local rd = self._redDots
    rd.machine = machineN
    rd.coins = coinsN
    rd.tech = techN
    rd.prestige = prestigeN
    rd.welfare = welfareN
    return rd
end

-- ----------------------------------------------------------------------------
-- 主每帧推进
-- ----------------------------------------------------------------------------
function Tycoon:Update(dt)
    dt = min(0.05, max(0, dt or 0))
    self.clock = self.clock + dt
    self._permMult = nil
    self._avgVal = nil
    if self.manualCd > 0 then self.manualCd = max(0, self.manualCd - dt) end
    if (self.slotCd or 0) > 0 then self.slotCd = max(0, self.slotCd - dt) end
    if not self.feverActive and (self.feverCd or 0) > 0 then
        self.feverCd = max(0, self.feverCd - dt)
    end
    self.feverChargeTick = (self.feverChargeTick or 0) + dt
    if self.feverChargeTick >= 1.0 then
        self.feverChargeTick = self.feverChargeTick - 1.0
        self.feverChargeAcc = 0
    end

    -- 广告冷却与×3倒计时
    if self.adBoostLeft > 0 then
        self.adBoostLeft = max(0, self.adBoostLeft - dt)
    end
    for k, cd in pairs(self.adCooldowns) do
        if cd > 0 then
            local nxt = cd - dt
            self.adCooldowns[k] = (nxt > 0) and nxt or 0
        end
    end

    -- 街机幸运三连旋转与限时倍率倒计时
    if self.slotFlashT > 0 then
        self.slotFlashT = max(0, self.slotFlashT - dt)
    end
    if self.luckTimer > 0 then
        self.luckTimer = max(0, self.luckTimer - dt)
        if self.luckTimer <= 0 then
            self.luckMult = 1
            self.luckDur = 0
            self.luckName = ""
        end
    end
    if (self.surpriseTimer or 0) > 0 then
        self.surpriseTimer = max(0, self.surpriseTimer - dt)
        if self.surpriseTimer <= 0 then
            self.surpriseMult = 1
            self.surpriseDur = 0
            self.surpriseName = ""
        end
    end

    -- 拖金袋小人：周期性沿台前底部横穿，前沿落币砸中触发 12 面骰子
    local runEnt = self.runner
    if runEnt then
        if runEnt.active then
            runEnt.x = runEnt.x + (runEnt.dir or 1) * (runEnt.speed or 44) * dt
            if runEnt.x < 40 or runEnt.x > 320 then
                runEnt.active = false
                runEnt.cooldown = 34 + self.rng() * 18
            end
        elseif not self.pendingDice then
            runEnt.cooldown = (runEnt.cooldown or 30) - dt
            if runEnt.cooldown <= 0 then
                self:SpawnRunner()
            end
        end
    end

    -- 空中黄金气球：在推盘上方通道飘过，点击或刚入槽硬币撞击均可打爆
    local bal = self.balloon
    if bal then
        if bal.active then
            bal.bobT = (bal.bobT or 0) + dt * 2.6
            bal.x = bal.x + (bal.dir or 1) * (bal.speed or 28) * dt
            bal.y = (bal.baseY or 118) + math.sin(bal.bobT) * 14
            if (bal.dir > 0 and bal.x > 304) or (bal.dir < 0 and bal.x < 56) then
                bal.active = false
                bal.cooldown = 40 + self.rng() * 24
            elseif self.physics and self.physics.activeIds and self.physics.coins then
                local ids, coins = self.physics.activeIds, self.physics.coins
                local bx, by = bal.x, bal.y
                for i = 1, #ids do
                    local c = coins[ids[i]]
                    if c and c.active and c.zone == "slot" then
                        local dx = (c.x or 0) - bx
                        local dy = (c.y or 0) - by
                        if dx * dx + dy * dy <= 24 * 24 then
                            self:PopBalloon("coin")
                            break
                        end
                    end
                end
            end
        else
            bal.cooldown = (bal.cooldown or 24) - dt
            if bal.cooldown <= 0 then
                local dir = (self.rng() < 0.5) and 1 or -1
                bal.active = true
                bal.dir = dir
                bal.x = (dir > 0) and 56 or 304
                bal.baseY = 102 + self.rng() * 44
                bal.y = bal.baseY
                bal.speed = 24 + self.rng() * 12
                bal.bobT = 0
            end
        end
    end
    if self.jpPhase then
        self:UpdateJackpot(dt)
    else
        self.jpSince = (self.jpSince or 0) + dt
    end
    if self.slotSpinning then
        self.slotSpinT = self.slotSpinT + dt
        if self.slotSpinT >= self.slotSpinDur then
            self.slotSpinning = false
            self.slotSpinT = 0
            local pending = self.slotPending
            self.slotPending = nil
            if pending and pending.reels then
                self.slotReels = pending.reels
                if pending.grid then self.slotGrid = pending.grid end
                self.slotWinLine = pending.winLine
                self:ResolveSlotSpin(pending)
            end
            if self.slotQueue > 0 then
                self:StartNextSlotSpin()
            end
        end
    elseif self.slotQueue > 0 and not self.jpPhase then
        self:StartNextSlotSpin()
    end

    -- 滑动 10 秒 CPS 采样 & 5 分钟去瞬时倍率长期基准线采样
    self.cpsTick = self.cpsTick + dt
    if self.cpsTick >= 1.0 then
        self.cpsTick = self.cpsTick - 1.0
        self.cpsBuckets[self.cpsIdx] = self.cpsAcc
        -- JP 计价基准（真实收入 EMA）+ 持续养分
        local ref = self.jpRefCps or 0
        if ref <= 0 then
            ref = max(self.cpsAcc, self:GetBaselineCPS())
        else
            ref = ref + (self.cpsAcc - ref) / JP.REF_TAU
        end
        self.jpRefCps = ref
        if not self.jpPhase and (JP.FEED_SEC_PER_SEC or 0) > 0 then
            self:FeedJackpot(self:GetJpBase() * JP.FEED_SEC_PER_SEC)
        end
        self.cpsAcc = 0.0
        self.cpsIdx = (self.cpsIdx % 10) + 1
        local sum = 0.0
        for i = 1, 10 do sum = sum + self.cpsBuckets[i] end
        self.cashPerSec = sum / 10.0
    end
    self.baseRevTick = (self.baseRevTick or 0) + dt
    if self.baseRevTick >= 10.0 then
        self.baseRevTick = self.baseRevTick - 10.0
        self.baseRevBuckets[self.baseRevIdx] = self.baseRevAcc or 0.0
        self.baseRevAcc = 0.0
        self.baseRevIdx = (self.baseRevIdx % 30) + 1
        self._baseRevSamples = min(30, (self._baseRevSamples or 0) + 1)
        local bSum = 0.0
        for i = 1, 30 do bSum = bSum + self.baseRevBuckets[i] end
        self.longTermBaseCps = bSum / max(10.0, self._baseRevSamples * 10.0)
    end

    -- 复利金库锁被动吃利息（按基准产值派发 8%）
    if self:HasTech("bankbook") then
        self.interestTick = self.interestTick + dt
        if self.interestTick >= 1.0 then
            self.interestTick = self.interestTick - 1.0
            local gain = max(1.0, floor(self:GetBaselineCPS() * 0.08 + 0.0))
            self:AddWealth(gain, true, 1.0)
        end
    end

    -- 风投限时礼盒定时出现
    if not self.activeAirdrop then
        self.airdropTimer = self.airdropTimer - dt
        if self.airdropTimer <= 0 then
            self.airdropTimer = 75
            local evList = Config.EVENT_ORDER
            local evId = evList[(floor(self.clock * 13) % #evList) + 1] or "vault_crack"
            self.activeAirdrop = {
                eventId = evId,
            }
        end
    end

    -- 连击波次结算与超时衰减（每15秒波次结算防止连击数字无意义膨胀）
    if self.combo > 0 then
        self.comboWaveT = (self.comboWaveT or 0) + dt
        if self.comboWaveT >= (self.comboWaveDur or 15.0) then
            self.comboWaveT = 0
            if self.combo >= 8 then
                local waveMult = min(1.5, 0.35 + self.combo * 0.015)
                local bonus = max(10.0, floor(self:GetBaselineCPS() * waveMult + 0.0))
                self:AddWealth(bonus, true, 1.0)
                Emit(self.fx, "OnComboWaveEnd", self.combo, waveMult, bonus)
            end
            self.combo = floor(self.combo * 0.35)
        end
        self.comboTimer = self.comboTimer - dt
        if self.comboTimer <= 0 then
            self.combo = 0
            self.comboWaveT = 0
            Emit(self.fx, "OnComboBreak")
        end
    end

    -- Fever 狂欢倒计时与金币雨（结束后 25 秒冷却）
    if self.feverActive then
        self.feverTimer = self.feverTimer - dt
        if self.feverRainLeft > 0 then
            self.feverRainTimer = self.feverRainTimer - dt
            if self.feverRainTimer <= 0 then
                self.feverRainTimer = 0.22
                self.feverRainLeft = self.feverRainLeft - 1
                local cid, lv = self:PickLaunchCoin()
                self.physics:SpawnCoin({
                    kind = cid, level = lv,
                    x = 92 + self.rng() * 176, y = S.DECK_TOP_Y + 24,
                    vx = (self.rng() - 0.5) * 40, vy = 55,
                    zone = "deck", gateChecked = true, isRain = true,
                })
            end
        end
        if self.feverTimer <= 0 then
            self.feverActive = false
            self.fever = 0
            self.feverCd = Config.RULES.FEVER_COOLDOWN or 28.0
            self.feverExtended = false
            self.feverChargeAcc = 0
            self:SyncPhysicsMods()
            Emit(self.fx, "OnFeverEnd", self)
        end
    end

    -- 永动自动发射器（绝不断供）
    self.autoTimer = self.autoTimer + dt
    local interval = 1.0 / max(0.5, self:GetAutoRate())
    if self.autoTimer >= interval then
        self.autoTimer = self.autoTimer - interval
        if self.autoTimer > interval then self.autoTimer = 0 end
        self:FireOneBurst(false)
    end

    self.physics:Step(dt)
end

-- ----------------------------------------------------------------------------
-- 存档序列化 / 反序列化（浮点财富防 2^63 溢出，保留常驻池/纪元/长期基准产值）
-- ----------------------------------------------------------------------------
function Tycoon:ExportState(nowTs)
    self.lastActiveAt = nowTs or os.time()
    local cds = {}
    for k, v in pairs(self.adCooldowns) do
        if (v or 0) > 1 then cds[k] = floor(v) end
    end
    local pinned = {}
    for k, v in pairs(self.pinnedCoins or {}) do
        if v == true then pinned[k] = true end
    end
    local baseRate = (self.longTermBaseCps and self.longTermBaseCps > 0) and self.longTermBaseCps or self:GetBaselineCPS()
    return {
        cash = self.cash + 0.0,
        runCash = self.runCash + 0.0,
        lifetimeCash = self.lifetimeCash + 0.0,
        skillPoints = self.skillPoints,
        totalSkillPoints = self.totalSkillPoints,
        spStep = self.spStep,
        ipoRound = self.ipoRound,
        era = self.era or 0,
        prestigeShares = self.prestigeShares,
        totalPrestiges = self.totalPrestiges,
        rankIdx = self.rankIdx,
        stageTheme = self.stageTheme,
        buyMode = self.buyMode,
        machineLv = self.machineLv,
        coinLv = self.coinLv,
        pinnedCoins = pinned,
        techOwned = self.techOwned,
        prestigeLv = self.prestigeLv,
        adBoostLeft = floor(self.adBoostLeft),
        adCooldowns = cds,
        adWatchCount = self.adWatchCount,
        totalClicks = self.totalClicks,
        totalDrops = self.totalDrops,
        bestHit = (self.bestHit or 0) + 0.0,
        maxCombo = self.maxCombo,
        surpriseMult = self.surpriseMult or 1,
        surpriseTimer = floor((self.surpriseTimer or 0) * 10) / 10,
        surpriseDur = self.surpriseDur or 0,
        surpriseName = self.surpriseName or "",
        lastBaseCps = baseRate + 0.0,
        lastActiveAt = self.lastActiveAt,
        jpPool = (self.jpPool or 0) + 0.0,
        jpRefCps = (self.jpRefCps or 0) + 0.0,
        jpLamps = (self.jpPhase and 0) or (self.jpLamps or 0),
        jpSince = floor(self.jpSince or 0),
        jpWins = self.jpWins or 0,
        jpBest = (self.jpBest or 0) + 0.0,
    }
end

function Tycoon:ImportState(s)
    if type(s) ~= "table" then return false end
    local c = max(0.0, (tonumber(s.cash) or 0) + 0.0)
    local rc = max(0.0, (tonumber(s.runCash) or c) + 0.0)
    self.lifetimeCash = max(c, rc, (tonumber(s.lifetimeCash) or 0) + 0.0) + 0.0
    self.cash = self.lifetimeCash
    self.runCash = self.lifetimeCash
    self.prestigeShares = max(0, floor(tonumber(s.prestigeShares) or 0))
    self.totalPrestiges = max(0, floor(tonumber(s.totalPrestiges) or 0))
    self.ipoRound = max(0, floor(tonumber(s.ipoRound) or self.totalPrestiges))
    self.era = max(0, floor(tonumber(s.era) or 0))
    self.rankIdx = 0
    while self.rankIdx < #Config.RANKS and self.lifetimeCash >= Config.RANKS[self.rankIdx + 1].target do
        self.rankIdx = self.rankIdx + 1
    end
    self.stageTheme = max(1, min(3, self:GetRankDef().theme or 1))
    if s.buyMode == 1 or s.buyMode == 10 or s.buyMode == 0 then self.buyMode = s.buyMode end

    if type(s.machineLv) == "table" then
        for _, m in ipairs(Config.MACHINE_UPGRADES) do
            self.machineLv[m.id] = max(0, min(m.maxLv, floor(tonumber(s.machineLv[m.id]) or 0)))
        end
    end
    self.coinLv = { gold = 1 }
    if type(s.coinLv) == "table" then
        for _, t in ipairs(Config.COIN_TIERS) do
            local v = floor(tonumber(s.coinLv[t.id]) or 0)
            if v > 0 then self.coinLv[t.id] = min(t.maxLv, v) end
        end
    end
    self.pinnedCoins = {}
    if type(s.pinnedCoins) == "table" then
        local cnt = 0
        for _, t in ipairs(Config.COIN_TIERS) do
            if s.pinnedCoins[t.id] == true and (self.coinLv[t.id] or 0) > 0 and cnt < 6 then
                self.pinnedCoins[t.id] = true
                cnt = cnt + 1
            end
        end
    end
    self.techOwned = {}
    if type(s.techOwned) == "table" then
        for _, t in ipairs(Config.TECH_UPGRADES) do
            if s.techOwned[t.id] == true then self.techOwned[t.id] = true end
        end
    end
    if type(s.prestigeLv) == "table" then
        for _, p in ipairs(Config.PRESTIGE_TALENTS) do
            self.prestigeLv[p.id] = max(0, min(p.maxLv, floor(tonumber(s.prestigeLv[p.id]) or 0)))
        end
    end

    -- 技能点恢复或从旧版本花钱档平滑迁移补偿 SP
    if s.spStep ~= nil then
        self.spStep = max(0, floor(tonumber(s.spStep) or 0))
        self.skillPoints = max(0, floor(tonumber(s.skillPoints) or 0))
        self.totalSkillPoints = max(self.skillPoints, floor(tonumber(s.totalSkillPoints) or 0))
    else
        self.spStep = 0
        self.skillPoints = 0
        self.totalSkillPoints = 0
        local migSp = 0
        local bonusLv = self.prestigeLv.angel_fund or 0
        while self.lifetimeCash >= Config.GetSpThreshold(self.spStep + 1) do
            self.spStep = self.spStep + 1
            migSp = migSp + Config.GetSpReward(self.spStep, bonusLv)
        end
        for rIdx = 1, self.rankIdx do
            migSp = migSp + (Config.RANKS[rIdx].spBounty or 10)
        end
        self.skillPoints = migSp
        self.totalSkillPoints = migSp
    end

    self.adBoostLeft = min(300, max(0, tonumber(s.adBoostLeft) or 0))
    self.adCooldowns = {}
    if type(s.adCooldowns) == "table" then
        for pid, def in pairs(Config.AD_PLACEMENTS) do
            local v = floor(tonumber(s.adCooldowns[pid]) or 0)
            if v > 0 then self.adCooldowns[pid] = min(def.cooldown or 1800, v) end
        end
    end
    self.adWatchCount = max(0, floor(tonumber(s.adWatchCount) or 0))
    self.totalClicks = max(0, floor(tonumber(s.totalClicks) or 0))
    self.totalDrops = max(0, floor(tonumber(s.totalDrops) or 0))
    self.bestHit = max(0.0, (tonumber(s.bestHit) or 0) + 0.0)
    self.maxCombo = max(0, floor(tonumber(s.maxCombo) or 0))
    self.longTermBaseCps = max(0.0, (tonumber(s.lastBaseCps) or 0) + 0.0)
    self.lastActiveAt = max(0, floor(tonumber(s.lastActiveAt) or 0))
    self.slotCd = 0
    self.feverCd = 0
    self.feverExtended = false
    self.feverChargeAcc = 0
    self.comboWaveT = 0
    self._baseRevSamples = 0
    self.surpriseTimer = max(0, tonumber(s.surpriseTimer) or 0)
    self.surpriseDur = max(0, tonumber(s.surpriseDur) or 0)
    self.surpriseMult = (self.surpriseTimer > 0) and max(1, tonumber(s.surpriseMult) or 1) or 1
    self.surpriseName = (self.surpriseTimer > 0 and type(s.surpriseName) == "string") and s.surpriseName or ""
    self.pendingDice = nil
    local jpPool = (tonumber(s.jpPool) or 0) + 0.0
    self.jpPool = (jpPool == jpPool and jpPool < math.huge) and max(0.0, jpPool) or 0.0
    local jpRef = (tonumber(s.jpRefCps) or 0) + 0.0
    self.jpRefCps = (jpRef == jpRef and jpRef < math.huge) and max(0.0, jpRef) or 0.0
    self.jpLamps = max(0, min(JP.LAMPS - 1, floor(tonumber(s.jpLamps) or 0)))
    self.jpSince = max(0, tonumber(s.jpSince) or 0)
    self.jpWins = max(0, floor(tonumber(s.jpWins) or 0))
    self.jpBest = max(0.0, (tonumber(s.jpBest) or 0) + 0.0)
    self.jpPhase = nil
    self.jpPendingPopup = nil
    self.jpRainLeft = 0
    if self.runner then self.runner.active = false end
    if self.balloon then self.balloon.active = false end

    self:RebuildCoinCache()
    self:CheckSpMilestones()
    self:CheckRankUp()
    self:SyncPhysicsMods()
    self:ResetPhysics(true)
    return true
end

return Tycoon
