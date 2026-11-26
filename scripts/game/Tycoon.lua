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

    -- 核心资产与声望状态（钱只涨不跌专冲世界第一，升级全靠技能点 SP）
    self.cash = 0
    self.runCash = 0
    self.lifetimeCash = 0
    self.skillPoints = 0
    self.totalSkillPoints = 0
    self.spStep = 0
    self.ipoRound = 0
    self.prestigeShares = 0
    self.totalPrestiges = 0
    self.rankIdx = 0      -- 0 = 第60亿名起点，依次冲破 22 档匿名阶层 -> 世界前 1000 真名榜
    self.stageTheme = 1

    -- 街机三连老虎机（过中奖门转奖，限时爆发 2x~100x 全局掉落倍率）
    self.slotQueue = 0
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

    -- 四大养成线
    self.machineLv = {}
    for _, m in ipairs(Config.MACHINE_UPGRADES) do self.machineLv[m.id] = 0 end
    self.coinLv = { gold = 1 } -- 渐进起点：开局仅解锁标准金币
    self.techOwned = {}
    self.prestigeLv = {}
    for _, p in ipairs(Config.PRESTIGE_TALENTS) do self.prestigeLv[p.id] = 0 end

    self.buyMode = 1 -- 1 | 10 | 0(MAX)

    -- 推台实时反馈
    self.combo = 0
    self.comboTimer = 0
    self.fever = 0
    self.feverActive = false
    self.feverTimer = 0
    self.feverRainLeft = 0
    self.feverRainTimer = 0

    -- 自动永动与手点加速
    self.autoTimer = 0
    self.manualCd = 0
    self.shotsFired = 0
    self.totalClicks = 0
    self.totalDrops = 0
    self.bestHit = 0
    self.maxCombo = 0

    -- 模拟广告与风投空投
    self.adBoostLeft = 0
    self.adCooldowns = {}
    self.adWatchCount = 0
    self.airdropTimer = 55
    self.activeAirdrop = nil

    -- 收入统计（10秒滑动窗口 + 理论兜底估值）
    self.cpsBuckets = {}
    for i = 1, 10 do self.cpsBuckets[i] = 0 end
    self.cpsIdx = 1
    self.cpsAcc = 0
    self.cpsTick = 0
    self.cashPerSec = 0
    self.interestTick = 0
    self.clock = 0
    self.lastActiveAt = 0

    self.physics = Physics.New({
        OnPegHit = function(coin, peg) self:HandlePegHit(coin, peg) end,
        OnGateWin = function(coin) self:HandleGateWin(coin) end,
        OnGateBounce = function(coin) Emit(self.fx, "OnGateBounce", coin) end,
        OnEnterDeck = function(coin) self:HandleEnterDeck(coin) end,
        OnFrontDrop = function(coin) self:HandleFrontDrop(coin) end,
        OnSideDrain = function(coin) self:HandleSideDrain(coin) end,
        OnCoinFuseExplode = function(coin) self:HandleBombExplode(coin) end,
        OnBlackholeBurst = function(coin) self:HandleBlackholeBurst(coin) end,
        OnOverclockCoin = function(coin) self:HandleOverclockCoin(coin) end,
    })

    self:ResetPhysics(true)
    return self
end

-- ----------------------------------------------------------------------------
-- 养成查询与数值公式
-- ----------------------------------------------------------------------------
function Tycoon:HasTech(id)
    return self.techOwned[id] == true
end

function Tycoon:GetUnlockedCoins()
    local list = {}
    for _, t in ipairs(Config.COIN_TIERS) do
        if (self.coinLv[t.id] or 0) > 0 then
            list[#list + 1] = t.id
        end
    end
    if #list == 0 then list[1] = "gold" end
    return list
end

function Tycoon:CountUnlockedCoins()
    local n = 0
    for _, t in ipairs(Config.COIN_TIERS) do
        if (self.coinLv[t.id] or 0) > 0 then n = n + 1 end
    end
    return n
end

function Tycoon:GetHighestUnlockedCoin()
    local best = "gold"
    for _, t in ipairs(Config.COIN_TIERS) do
        if (self.coinLv[t.id] or 0) > 0 then best = t.id end
    end
    return best
end

function Tycoon:GetCoinUnitValue(kind, lvOverride)
    local t = Config.COIN_TIER_BY_ID[kind]
    if not t then
        -- 衍生/金库币映射到基准
        if kind == "vault" then return self:GetCoinUnitValue(self:GetHighestUnlockedCoin()) * 45 end
        if kind == "slag" then return self:GetCoinUnitValue(self:GetHighestUnlockedCoin()) * 6 end
        if kind == "mini" then return self:GetCoinUnitValue("split") * 0.45 end
        return 2.5
    end
    local lv = max(1, floor(lvOverride or self.coinLv[kind] or 1))
    local v = t.baseValue * pow(1.20, lv - 1)
    if lv >= 5 then v = v * 1.30 end
    if lv >= 10 then v = v * 1.40 end
    if lv >= 15 then v = v * 1.50 end
    return v
end

function Tycoon:GetAvgUnlockedCoinValue()
    local list = self:GetUnlockedCoins()
    local topN = min(5, #list)
    local sum = 0
    for i = #list - topN + 1, #list do
        local cid = list[i]
        sum = sum + self:GetCoinUnitValue(cid, self.coinLv[cid])
    end
    return max(2.5, sum / max(1, topN))
end

function Tycoon:GetShareMult()
    return 1 + (self.prestigeShares or 0) * 0.09
end

function Tycoon:GetTotalMult()
    local machine = pow(1.24, self.machineLv.global_mult or 0)
    local tech = 1.0
    for _, t in ipairs(Config.TECH_UPGRADES) do
        if self.techOwned[t.id] then tech = tech * t.mult end
    end
    local prestige = self:GetShareMult() * pow(1.28, self.prestigeLv.golden_dna or 0)
    local comboFactor = self:HasTech("metronome") and 0.012 or 0.008
    local comboM = 1 + min(100, self.combo) * comboFactor
    local feverM = self.feverActive and 2.2 or 1.0
    local adM = (self.adBoostLeft > 0) and 3.0 or 1.0
    local luckM = max(1, self.luckMult or 1)
    local total = machine * tech * prestige * comboM * feverM * adM * luckM
    return total, {
        total = total,
        machine = machine,
        tech = tech,
        prestige = prestige,
        combo = comboM,
        fever = feverM,
        ad = adM,
        luck = luckM,
    }
end

function Tycoon:GetAutoRate()
    local base = 0.95 + (self.machineLv.auto_rate or 0) * 0.18
    local perp = 1 + (self.prestigeLv.perpetual or 0) * 0.14
    local fev = self.feverActive and 1.65 or 1.0
    return min(12.0, base * perp * fev)
end

function Tycoon:GetEstimatedCPS()
    local rate = self:GetAutoRate() * (1 + min(0.75, (self.machineLv.multi_shot or 0) * 0.05))
    local mult = self:GetTotalMult()
    return rate * self:GetAvgUnlockedCoinValue() * mult * 0.92
end

function Tycoon:GetDisplayCPS()
    return max(self.cashPerSec, self:GetEstimatedCPS())
end

function Tycoon:SyncPhysicsMods()
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
end

function Tycoon:ResetPhysics(clearCoins)
    local extraPegs = (self.machineLv.peg_gold or 0)
    self.physics:Reset({
        railGuard = self:HasTech("rail_guard") and 0.78 or 0.12,
        frontLipResist = 0.05,
        extraMultPegs = min(14, extraPegs),
    })
    self:SyncPhysicsMods()
    if clearCoins ~= false then
        self.physics:SeedDeck(self.rng, self:GetUnlockedCoins())
    end
end

-- ----------------------------------------------------------------------------
-- 全球真实财富排名 & 技能点双轨成长（第60亿名起点 -> 全球前1000强真名榜）
-- ----------------------------------------------------------------------------
local STARTER_RANK = {
    id = 0, rank = Billionaires.START_RANK, name = "全球起步", title = "第 60 亿名起点",
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
        local cappedSp = min(totalSp, 60)
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

function Tycoon:AddWealth(amount, addToCps)
    local amt = max(0, tonumber(amount) or 0)
    if amt <= 0 then return 0 end
    self.cash = self.cash + amt
    self.runCash = self.runCash + amt
    self.lifetimeCash = self.lifetimeCash + amt
    if addToCps then
        self.cpsAcc = self.cpsAcc + amt
    end
    self:CheckSpMilestones()
    self:CheckRankUp()
    return amt
end

function Tycoon:ClaimOvertakeAdBonus(spBounty)
    local extraSp = max(2, floor((spBounty or 0) * 2))
    self.adWatchCount = self.adWatchCount + 1
    self.skillPoints = self.skillPoints + extraSp
    self.totalSkillPoints = self.totalSkillPoints + extraSp
    Emit(self.fx, "OnAdReward", "超越技能点 ×3 +" .. tostring(extraSp) .. "点")
    return extraSp
end

-- ----------------------------------------------------------------------------
-- 发币队列（权重偏向最新解锁高价币，每unlock立即出币爽感爆棚）
-- ----------------------------------------------------------------------------
function Tycoon:PickLaunchCoin()
    local list = self:GetUnlockedCoins()
    local n = #list
    if n <= 1 then return list[1], self.coinLv[list[1]] or 1 end
    local start = max(1, n - 5)
    local totalW = 0
    for i = start, n do
        totalW = totalW + (i - start + 1) * 2
    end
    local r = self.rng() * totalW
    local acc = 0
    for i = start, n do
        acc = acc + (i - start + 1) * 2
        if r <= acc then
            local cid = list[i]
            return cid, self.coinLv[cid] or 1
        end
    end
    local last = list[n]
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
    local mainCoin = self.physics:LaunchFromTop(cid, lv, 0)
    self.shotsFired = self.shotsFired + 1
    if mainCoin and isManual then mainCoin.fromManual = true end

    local multiLv = self.machineLv.multi_shot or 0
    local dblChance = min(0.85, multiLv * 0.045)
    if multiLv > 0 and self.rng() < dblChance then
        local cid2, lv2 = self:PickLaunchCoin()
        local c2 = self.physics:LaunchFromTop(cid2, lv2, (self.shotsFired % 2 == 0) and 10 or -10)
        if c2 and isManual then c2.fromManual = true end
        if multiLv >= 10 and self.rng() < (dblChance * 0.45) then
            local cid3, lv3 = self:PickLaunchCoin()
            self.physics:LaunchFromTop(cid3, lv3, (self.shotsFired % 2 == 0) and -16 or 16)
        end
    end
    Emit(self.fx, "OnShoot", mainCoin, self)
    return mainCoin
end

function Tycoon:ManualShoot()
    if self.manualCd > 0 then return false end
    self.manualCd = self.feverActive and 0.08 or 0.11
    self.totalClicks = self.totalClicks + 1
    self:FireOneBurst(true)
    self:AddFever(2.2)
    return true
end

-- ----------------------------------------------------------------------------
-- 现金结算与物理联动回调
-- ----------------------------------------------------------------------------
function Tycoon:AwardCash(baseVal, x, y, sourceTag, canCrit, extraMul)
    local mult = self:GetTotalMult() * (extraMul or 1.0)
    local crit = false
    if canCrit ~= false then
        local critChance = min(0.75, 0.10 + (self.machineLv.crit_power or 0) * 0.015 + ((sourceTag == "neon") and 0.25 or 0))
        if self.rng() < critChance then
            crit = true
            local critMul = 2.0 + (self.machineLv.crit_power or 0) * 0.18 + (self.prestigeLv.tycoon_crit or 0) * 0.8
            mult = mult * critMul
        end
    end
    local dmg = max(1, floor(baseVal * mult + 0.5))
    if dmg > self.bestHit then self.bestHit = dmg end
    self:AddWealth(dmg, true)
    Emit(self.fx, "OnScore", dmg, x, y, crit, self.combo, sourceTag, self:GetDisplayCPS())
    return dmg, crit
end

function Tycoon:AddFever(amt)
    if self.feverActive then return end
    local mul = 1 + (self.machineLv.fever_drive or 0) * 0.06
    self.fever = min(100, self.fever + amt * mul)
    if self.fever >= 100 then
        self:TriggerFever(false)
    end
end

function Tycoon:TriggerFever(isAdSuper)
    self.fever = 100
    self.feverActive = true
    local drive = self.machineLv.fever_drive or 0
    local dur = (isAdSuper and 14 or 8) + min(10, drive * 0.25)
    self.feverTimer = dur
    self.feverRainLeft = (isAdSuper and 28 or 14) + floor(drive * 0.5)
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

function Tycoon:HandlePegHit(coin, peg)
    local pDef = Config.PEG_TYPES[peg.kind] or Config.PEG_TYPES.normal
    if pDef.fever then self:AddFever(pDef.fever * 0.5) end
    local pegMul = (1 + (self.machineLv.peg_gold or 0) * 0.35) * ((peg.kind == "mult") and 2.0 or 1.0)
    self:AwardCash(self:GetAvgUnlockedCoinValue() * 0.06 * pegMul, peg.x, peg.y, "peg", false)
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
    elseif cDef and cDef.bounceSpawn and coin.bounceCount <= 2 then
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
    elseif peg.kind == "bolt" then
        self:TriggerLightning(peg.x, peg.y, 2, coin.level)
    end
end

function Tycoon:RollSlotOutcome()
    local gateLv = self.machineLv.gate_master or 0
    local cloverMul = self:HasTech("clover") and 1.85 or 1.0
    local boost = (1 + gateLv * 0.08) * cloverMul

    local prizeId, reels
    if self.slotPity >= 6 then
        self.slotPity = 0
        if self.rng() < 0.35 then
            prizeId = "triple_gem"
            reels = { 4, 4, 4 }
        else
            prizeId = "triple_bolt"
            reels = { 3, 3, 3 }
        end
    else
        local u = self.rng() * 100
        local p100 = min(4.5, 0.8 * boost)
        local p50  = min(7.0, 2.0 * boost)
        local p25  = min(11.0, 4.0 * boost)
        local p10  = min(16.0, 7.5 * boost)
        local p5   = min(20.0, 14.0 * (1 + gateLv * 0.03))
        local p2   = 32.0

        if u < p100 then
            prizeId = "jackpot_777"; reels = { 6, 6, 6 }
        elseif u < p100 + p50 then
            prizeId = "triple_crown"; reels = { 5, 5, 5 }
        elseif u < p100 + p50 + p25 then
            prizeId = "triple_gem"; reels = { 4, 4, 4 }
        elseif u < p100 + p50 + p25 + p10 then
            prizeId = "triple_bolt"; reels = { 3, 3, 3 }
        elseif u < p100 + p50 + p25 + p10 + p5 then
            prizeId = "triple_low"
            local s = (self.rng() < 0.5) and 1 or 2
            reels = { s, s, s }
        elseif u < p100 + p50 + p25 + p10 + p5 + p2 then
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
    return { reels = reels, prize = prizeDef }
end

function Tycoon:StartNextSlotSpin()
    if self.slotQueue <= 0 then return false end
    self.slotQueue = self.slotQueue - 1
    self.slotSpinning = true
    self.slotSpinT = 0
    self.slotPending = self:RollSlotOutcome()
    return true
end

function Tycoon:QueueSlotSpin()
    self.slotQueue = min(5, (self.slotQueue or 0) + 1)
    if not self.slotSpinning then
        self:StartNextSlotSpin()
    end
end

function Tycoon:ResolveSlotSpin(pending)
    if not pending or not pending.prize then return end
    local prize = pending.prize
    self.slotFlashT = (prize.mult >= 10) and 1.2 or ((prize.mult > 1) and 0.7 or 0.35)

    if prize.mult > (self.luckMult or 1) then
        self.luckMult = prize.mult
        self.luckTimer = prize.dur
        self.luckDur = prize.dur
        self.luckName = prize.label
    elseif prize.mult > 1 and prize.mult == (self.luckMult or 1) then
        self.luckTimer = min(25, (self.luckTimer or 0) + prize.dur * 0.65)
        self.luckDur = max(self.luckDur or prize.dur, self.luckTimer)
    elseif prize.mult > 1 and (self.luckMult or 1) > prize.mult then
        -- 高倍已激活时抽中小奖不降级，顺延 2 秒并额外掉币雨
        self.luckTimer = min(25, (self.luckTimer or 0) + 2.0)
        self.luckDur = max(self.luckDur or 15, self.luckTimer)
    end

    -- 老虎机奖励空投金币雨 / 闪电 / 金库巨币
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
end

function Tycoon:HandleGateWin(coin)
    self:AddFever(14)
    self:RegisterCombo()
    local gateLv = self.machineLv.gate_master or 0
    local dropCnt = min(3, 1 + floor(gateLv / 6))
    local spawnKind = self:GetHighestUnlockedCoin()
    local rewardName = string.format("过门 ×%d + 老虎机!", dropCnt)
    for k = 1, dropCnt do
        local useKind = (k == 1) and spawnKind or "gold"
        self.physics:SpawnCoin({
            kind = useKind, level = self.coinLv[useKind] or 1,
            x = 110 + (k % 4) * 38, y = S.DECK_TOP_Y + 28 + k * 4,
            vx = ((k % 3) - 1) * 32, vy = 45, zone = "deck", gateChecked = true, isRain = true,
        })
    end
    self:AwardCash(self:GetCoinUnitValue(coin.kind, coin.level) * (1.8 + gateLv * 0.35), coin.x, coin.y, "gate", true)
    self:QueueSlotSpin()
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
    local val = self:GetCoinUnitValue(coin.kind, coin.level) * (self:HasTech("overclock") and 4.0 or 1.2)
    self:AwardCash(val, coin.x, coin.y, "overclock", false)
end

function Tycoon:HandleFrontDrop(coin)
    self.totalDrops = self.totalDrops + 1
    local val = self:GetCoinUnitValue(coin.kind, coin.level)
    local def = Config.COINS[coin.kind]
    if coin.frostT > 0 then val = val * 2.0 end
    if coin.kind == "giant" then val = val * 2.5 end
    if coin.fromManual then val = val * 1.15 end
    if coin.kind == "vault" then val = self:GetCoinUnitValue(self:GetHighestUnlockedCoin()) * 50 end

    if def and def.feverExtend and self.feverActive then
        self.feverTimer = min(30, self.feverTimer + 2.0)
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
end

function Tycoon:HandleSideDrain(coin)
    if self:HasTech("recycler") then
        local val = self:GetCoinUnitValue(coin.kind, coin.level) * 0.5
        self:AwardCash(val, coin.x, coin.y, "recycler", false)
    end
    Emit(self.fx, "OnSideDrain", coin)
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
    self:SyncPhysicsMods()
    Emit(self.fx, "OnUnlockCoin", { name = t.name })
    return true
end

-- 资本融资 / 敲钟上市公式（方案 A：达标敲钟领传奇股+技能点，绝不清空财富与进度！）
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
    self.skillPoints = self.skillPoints + bonusSp
    self.totalSkillPoints = self.totalSkillPoints + bonusSp
    Emit(self.fx, "OnPrestige", shares, bonusSp, r.name)
    return shares, bonusSp
end

Tycoon.DoPrestige = Tycoon.DoCapitalIPO

-- 模拟广告与风投空投发奖
function Tycoon:GetAdCooldown(id)
    return max(0, self.adCooldowns[id] or 0)
end

function Tycoon:ApplyAdReward(placementId)
    local def = Config.AD_PLACEMENTS[placementId]
    if not def then return false, nil end
    self.adWatchCount = self.adWatchCount + 1
    if (def.cooldown or 0) > 0 then
        self.adCooldowns[placementId] = def.cooldown
    end

    if placementId == "boost_3x" then
        self.adBoostLeft = min(900, self.adBoostLeft + 180)
        Emit(self.fx, "OnAdReward", "超级印钞 ×3 激活!")
        return true, "全场收益 ×3 生效 180 秒"
    elseif placementId == "instant_fever" then
        self:TriggerFever(true)
        Emit(self.fx, "OnAdReward", "满槽超级狂欢!")
        return true, "超级狂欢激活 14 秒!"
    elseif placementId == "vault_drop" then
        for i = 1, 2 do
            self.physics:SpawnCoin({
                kind = "vault", level = 1,
                x = 140 + (i - 1) * 80, y = S.DECK_TOP_Y + 46,
                vx = (i == 1) and -12 or 12, vy = 55,
                zone = "deck", gateChecked = true,
            })
        end
        Emit(self.fx, "OnAdReward", "2枚50倍金库币空投!")
        return true, "2 枚 50 倍金库巨币已落台!"
    elseif placementId == "airdrop_5x" then
        local amt = max(600, floor(self:GetDisplayCPS() * 120))
        self:AddWealth(amt, false)
        local hi = self:GetHighestUnlockedCoin()
        for k = 1, 10 do
            self.physics:SpawnCoin({
                kind = hi, level = self.coinLv[hi] or 1,
                x = 100 + ((k - 1) % 5) * 40, y = S.DECK_TOP_Y + 30 + floor((k - 1) / 5) * 20,
                vx = (self.rng() - 0.5) * 40, vy = 45, zone = "deck", gateChecked = true, isRain = true,
            })
        end
        self.activeAirdrop = nil
        Emit(self.fx, "OnAdReward", "风投暴富 +" .. Number.FormatCash(amt))
        return true, "到账 " .. Number.FormatCash(amt)
    end
    return true, "奖励已发放"
end

function Tycoon:ClaimAirdrop(isAd)
    local air = self.activeAirdrop
    if not air then return 0 end
    if isAd then
        local amt = max(600, floor(self:GetDisplayCPS() * 120))
        self:ApplyAdReward("airdrop_5x")
        return amt
    end
    local amt = air.baseCash or max(120, floor(self:GetDisplayCPS() * 24))
    self:AddWealth(amt, false)
    self.activeAirdrop = nil
    Emit(self.fx, "OnAdReward", "风投补贴 +" .. Number.FormatCash(amt))
    return amt
end

function Tycoon:CalcOfflineEarnings(nowTs)
    if not self.lastActiveAt or self.lastActiveAt <= 0 then return 0, 0 end
    local elapsed = max(0, (nowTs or os.time()) - self.lastActiveAt)
    if elapsed < 30 then return 0, elapsed end
    local capped = min(8 * 3600, elapsed)
    local amt = max(50, floor(capped * self:GetDisplayCPS() * 0.65))
    return amt, elapsed
end

function Tycoon:ClaimOffline(amt, isDouble)
    local gain = floor((amt or 0) * (isDouble and 2 or 1))
    if gain <= 0 then return 0 end
    if isDouble then self.adWatchCount = self.adWatchCount + 1 end
    self:AddWealth(gain, false)
    Emit(self.fx, "OnAdReward", "离线收益 +" .. Number.FormatCash(gain))
    return gain
end

function Tycoon:ClaimRedeemCode(rawCode, redeemedMap)
    local ok, msg, def = RedeemCodes.Claim(rawCode, redeemedMap)
    if not ok then return false, msg end
    if def.cashSeconds then
        local addCash = max(def.minCash or 0, floor(self:GetDisplayCPS() * def.cashSeconds))
        self:AddWealth(addCash, false)
    end
    if def.shares then
        self.prestigeShares = self.prestigeShares + def.shares
    end
    if def.boostSec then
        self.adBoostLeft = min(900, self.adBoostLeft + def.boostSec)
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
-- 「哪里亮点哪里」红点汇总（按可用技能点 SP / 上市条件 / 广告冷却点亮）
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
    if self:CanDoIpo() then prestigeN = prestigeN + 1 end
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

    return {
        machine = machineN,
        coins = coinsN,
        tech = techN,
        prestige = prestigeN,
        welfare = welfareN,
    }
end

-- ----------------------------------------------------------------------------
-- 主每帧推进
-- ----------------------------------------------------------------------------
function Tycoon:Update(dt)
    dt = min(0.05, max(0, dt or 0))
    self.clock = self.clock + dt
    if self.manualCd > 0 then self.manualCd = max(0, self.manualCd - dt) end

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

    -- 街机老虎机旋转与限时倍率倒计时
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
    if self.slotSpinning then
        self.slotSpinT = self.slotSpinT + dt
        if self.slotSpinT >= self.slotSpinDur then
            self.slotSpinning = false
            self.slotSpinT = 0
            local pending = self.slotPending
            self.slotPending = nil
            if pending and pending.reels then
                self.slotReels = pending.reels
                self:ResolveSlotSpin(pending)
            end
            if self.slotQueue > 0 then
                self:StartNextSlotSpin()
            end
        end
    elseif self.slotQueue > 0 then
        self:StartNextSlotSpin()
    end

    -- 滑动 10 秒 CPS 采样
    self.cpsTick = self.cpsTick + dt
    if self.cpsTick >= 1.0 then
        self.cpsTick = self.cpsTick - 1.0
        self.cpsBuckets[self.cpsIdx] = self.cpsAcc
        self.cpsAcc = 0
        self.cpsIdx = (self.cpsIdx % 10) + 1
        local sum = 0
        for i = 1, 10 do sum = sum + self.cpsBuckets[i] end
        self.cashPerSec = sum / 10
    end

    -- 复利金库锁被动吃利息（按产值派发，杜绝现金指数爆炸）
    if self:HasTech("bankbook") then
        self.interestTick = self.interestTick + dt
        if self.interestTick >= 1.0 then
            self.interestTick = self.interestTick - 1.0
            local gain = max(1, floor(self:GetEstimatedCPS() * 0.14))
            self:AddWealth(gain, true)
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
                baseCash = max(150, floor(self:GetDisplayCPS() * 25)),
            }
        end
    end

    -- 连击衰减
    if self.combo > 0 then
        self.comboTimer = self.comboTimer - dt
        if self.comboTimer <= 0 then
            self.combo = 0
            Emit(self.fx, "OnComboBreak")
        end
    end

    -- Fever 狂欢倒计时与金币雨
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
-- 存档序列化 / 反序列化（纯整数+简单字典，兼容 JSON 无精度丢失）
-- ----------------------------------------------------------------------------
function Tycoon:ExportState(nowTs)
    self.lastActiveAt = nowTs or os.time()
    return {
        cash = self.cash,
        runCash = self.runCash,
        lifetimeCash = self.lifetimeCash,
        skillPoints = self.skillPoints,
        totalSkillPoints = self.totalSkillPoints,
        spStep = self.spStep,
        ipoRound = self.ipoRound,
        prestigeShares = self.prestigeShares,
        totalPrestiges = self.totalPrestiges,
        rankIdx = self.rankIdx,
        stageTheme = self.stageTheme,
        buyMode = self.buyMode,
        machineLv = self.machineLv,
        coinLv = self.coinLv,
        techOwned = self.techOwned,
        prestigeLv = self.prestigeLv,
        adBoostLeft = floor(self.adBoostLeft),
        adWatchCount = self.adWatchCount,
        totalClicks = self.totalClicks,
        totalDrops = self.totalDrops,
        bestHit = self.bestHit,
        maxCombo = self.maxCombo,
        lastActiveAt = self.lastActiveAt,
    }
end

function Tycoon:ImportState(s)
    if type(s) ~= "table" then return false end
    local c = max(0, tonumber(s.cash) or 0)
    local rc = max(0, tonumber(s.runCash) or c)
    self.lifetimeCash = max(c, rc, tonumber(s.lifetimeCash) or 0)
    self.cash = self.lifetimeCash
    self.runCash = self.lifetimeCash
    self.prestigeShares = max(0, floor(tonumber(s.prestigeShares) or 0))
    self.totalPrestiges = max(0, floor(tonumber(s.totalPrestiges) or 0))
    self.ipoRound = max(0, floor(tonumber(s.ipoRound) or self.totalPrestiges))
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
            migSp = migSp + (Config.RANKS[rIdx].spBounty or 2)
        end
        self.skillPoints = migSp
        self.totalSkillPoints = migSp
    end

    self.adBoostLeft = max(0, tonumber(s.adBoostLeft) or 0)
    self.adWatchCount = max(0, floor(tonumber(s.adWatchCount) or 0))
    self.totalClicks = max(0, floor(tonumber(s.totalClicks) or 0))
    self.totalDrops = max(0, floor(tonumber(s.totalDrops) or 0))
    self.bestHit = max(0, tonumber(s.bestHit) or 0)
    self.maxCombo = max(0, floor(tonumber(s.maxCombo) or 0))
    self.lastActiveAt = max(0, floor(tonumber(s.lastActiveAt) or 0))

    self:CheckSpMilestones()
    self:CheckRankUp()
    self:SyncPhysicsMods()
    self:ResetPhysics(true)
    return true
end

return Tycoon
