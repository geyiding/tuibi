-- ============================================================================
-- Tycoon.lua  《推币机的狂欢》增量首富核心逻辑（永动自动推币 + 22币渐进 + 科技 + IPO转生 + 离线）
-- ============================================================================

local Config = require("game/Config")
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

    -- 核心资产与声望状态
    self.cash = 0
    self.runCash = 0
    self.lifetimeCash = 0
    self.prestigeShares = 0
    self.totalPrestiges = 0
    self.rankIdx = 0      -- 0 = No.101 尚未上榜，依次超越 No.100 -> No.1 马斯克
    self.stageTheme = 1

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
        return 12
    end
    local lv = max(1, floor(lvOverride or self.coinLv[kind] or 1))
    local v = t.baseValue * pow(1.8, lv - 1)
    if lv >= 5 then v = v * 2.5 end
    if lv >= 10 then v = v * 4.0 end
    if lv >= 15 then v = v * 5.0 end
    return v
end

function Tycoon:GetAvgUnlockedCoinValue()
    local list = self:GetUnlockedCoins()
    local topN = min(6, #list)
    local sum = 0
    for i = #list - topN + 1, #list do
        local cid = list[i]
        sum = sum + self:GetCoinUnitValue(cid, self.coinLv[cid])
    end
    return max(12, sum / max(1, topN))
end

function Tycoon:GetTotalMult()
    local machine = pow(1.35, self.machineLv.global_mult or 0)
    local tech = 1.0
    for _, t in ipairs(Config.TECH_UPGRADES) do
        if self.techOwned[t.id] then tech = tech * t.mult end
    end
    local prestige = (1 + self.prestigeShares * 0.15) * pow(1.8, self.prestigeLv.golden_dna or 0)
    local comboFactor = self:HasTech("metronome") and 0.02 or 0.01
    local comboM = 1 + min(200, self.combo) * comboFactor
    local feverM = self.feverActive and 2.5 or 1.0
    local adM = (self.adBoostLeft > 0) and 3.0 or 1.0
    local total = machine * tech * prestige * comboM * feverM * adM
    return total, {
        total = total,
        machine = machine,
        tech = tech,
        prestige = prestige,
        combo = comboM,
        fever = feverM,
        ad = adM,
    }
end

function Tycoon:GetAutoRate()
    local base = 1.25 + (self.machineLv.auto_rate or 0) * 0.22
    local perp = 1 + (self.prestigeLv.perpetual or 0) * 0.20
    local fev = self.feverActive and 1.75 or 1.0
    return min(14.0, base * perp * fev)
end

function Tycoon:GetEstimatedCPS()
    local rate = self:GetAutoRate() * (1 + min(0.75, (self.machineLv.multi_shot or 0) * 0.04))
    local mult = self:GetTotalMult()
    return rate * self:GetAvgUnlockedCoinValue() * mult * 0.92
end

function Tycoon:GetDisplayCPS()
    return max(self.cashPerSec, self:GetEstimatedCPS())
end

function Tycoon:SyncPhysicsMods()
    local phys = self.physics
    if not phys then return end
    local perp = 1 + (self.prestigeLv.perpetual or 0) * 0.20
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
-- 全球 100 富豪阶梯与自动换幕
-- ----------------------------------------------------------------------------
local STARTER_RANK = {
    id = 0, rank = 101, name = "街边起步", title = "霓虹推币新手",
    target = 0, theme = 1, bounty = 0, bonus = 0,
}

function Tycoon:GetRankDisplayNo()
    return (#Config.RANKS + 1) - self.rankIdx
end

function Tycoon:GetRankDef(idx)
    local i = idx or self.rankIdx
    if not i or i <= 0 then return STARTER_RANK end
    return Config.RANKS[max(1, min(#Config.RANKS, i))]
end

function Tycoon:CheckRankUp()
    local jumped = 0
    local totalBounty = 0
    local latest = nil
    local anyThemeChanged = false
    local presMul = (1 + self.prestigeShares * 0.15)

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
            local rawB = nxt.bounty or nxt.bonus or 0
            if rawB > 0 then
                totalBounty = totalBounty + floor(rawB * presMul + 0.5)
            end
        else
            break
        end
    end

    if jumped > 0 and latest then
        if totalBounty > 0 then
            self.cash = self.cash + totalBounty
            self.runCash = self.runCash + totalBounty
            self.lifetimeCash = self.lifetimeCash + totalBounty
        end
        Emit(self.fx, "OnRankUp", latest, anyThemeChanged, {
            jumped = jumped,
            bounty = totalBounty,
            wealthNow = self.lifetimeCash,
        })
    end
end

function Tycoon:ClaimOvertakeAdBonus(bounty)
    local extra = max(150, floor((bounty or 0) * 2))
    self.adWatchCount = self.adWatchCount + 1
    self.cash = self.cash + extra
    self.runCash = self.runCash + extra
    self.lifetimeCash = self.lifetimeCash + extra
    Emit(self.fx, "OnAdReward", "超越赏金 ×3 +" .. Number.FormatCash(extra))
    self:CheckRankUp()
    return extra
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
            local critMul = 2.0 + (self.machineLv.crit_power or 0) * 0.25 + (self.prestigeLv.tycoon_crit or 0) * 1.5
            mult = mult * critMul
        end
    end
    local dmg = max(1, floor(baseVal * mult + 0.5))
    self.cash = self.cash + dmg
    self.runCash = self.runCash + dmg
    self.lifetimeCash = self.lifetimeCash + dmg
    self.cpsAcc = self.cpsAcc + dmg
    if dmg > self.bestHit then self.bestHit = dmg end

    self:CheckRankUp()
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
    local win = self:HasTech("metronome") and 7.0 or 4.5
    self.comboTimer = win
    if self.combo > self.maxCombo then self.maxCombo = self.combo end
    Emit(self.fx, "OnCombo", self.combo)
end

function Tycoon:HandlePegHit(coin, peg)
    local pDef = Config.PEG_TYPES[peg.kind] or Config.PEG_TYPES.normal
    if pDef.fever then self:AddFever(pDef.fever * 0.5) end
    self:RegisterCombo()
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

function Tycoon:HandleGateWin(coin)
    self:AddFever(14)
    self:RegisterCombo()
    local gateLv = self.machineLv.gate_master or 0
    local dropCnt = 2 + floor(gateLv / 5)
    local spawnKind = self:GetHighestUnlockedCoin()
    local rewardName = string.format("过门 ×%d 金币雨!", dropCnt)
    for k = 1, dropCnt do
        local useKind = (k == 1) and spawnKind or "gold"
        self.physics:SpawnCoin({
            kind = useKind, level = self.coinLv[useKind] or 1,
            x = 110 + (k % 4) * 38, y = S.DECK_TOP_Y + 28 + k * 4,
            vx = ((k % 3) - 1) * 32, vy = 45, zone = "deck", gateChecked = true, isRain = true,
        })
    end
    self:AwardCash(self:GetCoinUnitValue(coin.kind, coin.level) * (1.8 + gateLv * 0.35), coin.x, coin.y, "gate", true)
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
-- 购买与养成 API（机台 / 22币 / 黑科技 / IPO转生 / 广告奖励 / 离线收益）
-- ----------------------------------------------------------------------------
function Tycoon:GetMachineCost(id, modeOverride)
    local def = Config.MACHINE_BY_ID[id]
    if not def then return math.huge, 0 end
    local cur = self.machineLv[id] or 0
    if cur >= def.maxLv then return 0, 0 end
    local mode = modeOverride or self.buyMode or 1

    if mode == 1 then
        local c1 = floor(def.baseCost * pow(def.growth, cur) + 0.5)
        return c1, (self.cash >= c1 and 1 or 0)
    elseif mode == 10 then
        local n = min(10, def.maxLv - cur)
        local sum = 0
        for i = 0, n - 1 do
            sum = sum + floor(def.baseCost * pow(def.growth, cur + i) + 0.5)
        end
        return sum, (self.cash >= sum and n or 0)
    else
        local firstCost = floor(def.baseCost * pow(def.growth, cur) + 0.5)
        if self.cash < firstCost then return firstCost, 0 end
        local sum, cnt = 0, 0
        for i = 0, (def.maxLv - cur - 1) do
            local c = floor(def.baseCost * pow(def.growth, cur + i) + 0.5)
            if sum + c > self.cash then break end
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
    if cnt <= 0 or self.cash < cost then return false end
    self.cash = self.cash - cost
    self.machineLv[id] = cur + cnt
    if id == "peg_gold" then
        self.physics:BuildPegs(min(14, self.machineLv.peg_gold))
    end
    self:SyncPhysicsMods()
    return true, cnt
end

function Tycoon:GetCoinCost(id)
    local t = Config.COIN_TIER_BY_ID[id]
    if not t then return math.huge, false end
    local cur = self.coinLv[id] or 0
    if cur >= t.maxLv then return 0, true end
    if cur == 0 then
        local cost = t.unlockCost
        -- 若父辈进化配方两枚币均已 >= Lv3，解锁费用直接享 5 折
        if t.parents and (self.coinLv[t.parents[1]] or 0) >= 3 and (self.coinLv[t.parents[2]] or 0) >= 3 then
            cost = floor(cost * 0.5 + 0.5)
        end
        return cost, false
    end
    local up = floor(t.upBase * pow(t.upGrowth, cur - 1) + 0.5)
    return up, false
end

function Tycoon:BuyCoin(id)
    local t = Config.COIN_TIER_BY_ID[id]
    if not t then return false end
    local cur = self.coinLv[id] or 0
    if cur >= t.maxLv then return false end
    local cost = self:GetCoinCost(id)
    if self.cash < cost then return false end
    self.cash = self.cash - cost
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
    if self.cash < t.cost then return false end
    self.cash = self.cash - t.cost
    self.techOwned[id] = true
    self:SyncPhysicsMods()
    Emit(self.fx, "OnUnlockCoin", { name = t.name })
    return true
end

-- IPO 上市转生公式
function Tycoon:CalcPendingShares()
    if self.runCash < 1e5 then return 0 end
    return max(1, floor(pow(self.runCash / 1e5, 0.5)))
end

function Tycoon:GetNextPrestigeRequirement()
    local curS = self:CalcPendingShares()
    local nextS = curS + 1
    return floor(1e5 * pow(nextS, 2))
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

function Tycoon:DoPrestige(isDoubleAd)
    local shares = self:CalcPendingShares()
    if shares <= 0 then return 0 end
    if isDoubleAd then shares = shares * 2; self.adWatchCount = self.adWatchCount + 1 end

    self.prestigeShares = self.prestigeShares + shares
    self.totalPrestiges = self.totalPrestiges + 1

    -- 保留前 (1 + angel_fund) 枚已解锁过的低序位或高等级币
    local keepSlots = 1 + (self.prestigeLv.angel_fund or 0)
    local newCoins = { gold = 1 }
    local kept = 0
    for _, t in ipairs(Config.COIN_TIERS) do
        if kept >= keepSlots then break end
        if t.id == "gold" or (self.coinLv[t.id] or 0) > 0 then
            newCoins[t.id] = 1
            kept = kept + 1
        end
    end
    self.coinLv = newCoins
    self.machineLv = {}
    for _, m in ipairs(Config.MACHINE_UPGRADES) do self.machineLv[m.id] = 0 end
    self.techOwned = {}

    local angel = self.prestigeLv.angel_fund or 0
    local startCash = (angel > 0) and floor(500 * pow(4, angel - 1)) or 0
    self.cash = startCash
    self.runCash = startCash
    self.combo = 0
    self.fever = 0
    self.feverActive = false
    self:ResetPhysics(true)
    Emit(self.fx, "OnPrestige", shares)
    return shares
end

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
        self.cash = self.cash + amt
        self.runCash = self.runCash + amt
        self.lifetimeCash = self.lifetimeCash + amt
        local hi = self:GetHighestUnlockedCoin()
        for k = 1, 10 do
            self.physics:SpawnCoin({
                kind = hi, level = self.coinLv[hi] or 1,
                x = 100 + ((k - 1) % 5) * 40, y = S.DECK_TOP_Y + 30 + floor((k - 1) / 5) * 20,
                vx = (self.rng() - 0.5) * 40, vy = 45, zone = "deck", gateChecked = true, isRain = true,
            })
        end
        self.activeAirdrop = nil
        self:CheckRankUp()
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
    self.cash = self.cash + amt
    self.runCash = self.runCash + amt
    self.lifetimeCash = self.lifetimeCash + amt
    self.activeAirdrop = nil
    self:CheckRankUp()
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
    self.cash = self.cash + gain
    self.runCash = self.runCash + gain
    self.lifetimeCash = self.lifetimeCash + gain
    self:CheckRankUp()
    Emit(self.fx, "OnAdReward", "离线收益 +" .. Number.FormatCash(gain))
    return gain
end

function Tycoon:ClaimRedeemCode(rawCode, redeemedMap)
    local ok, msg, def = RedeemCodes.Claim(rawCode, redeemedMap)
    if not ok then return false, msg end
    if def.cashSeconds then
        local addCash = max(def.minCash or 0, floor(self:GetDisplayCPS() * def.cashSeconds))
        self.cash = self.cash + addCash
        self.runCash = self.runCash + addCash
        self.lifetimeCash = self.lifetimeCash + addCash
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
    self:CheckRankUp()
    return true, msg
end

-- ----------------------------------------------------------------------------
-- 「哪里亮点哪里」红点汇总（返回 5 大底栏页签当前可操作次数）
-- ----------------------------------------------------------------------------
function Tycoon:GetRedDots()
    local machineN, coinsN, techN, prestigeN, welfareN = 0, 0, 0, 0, 0

    for _, m in ipairs(Config.MACHINE_UPGRADES) do
        local _, cnt = self:GetMachineCost(m.id, 1)
        if cnt > 0 then machineN = machineN + 1 end
    end
    for _, t in ipairs(Config.COIN_TIERS) do
        if (self.coinLv[t.id] or 0) < t.maxLv then
            local cost = self:GetCoinCost(t.id)
            if self.cash >= cost then coinsN = coinsN + 1 end
        end
    end
    for _, t in ipairs(Config.TECH_UPGRADES) do
        if (not self.techOwned[t.id]) and self.cash >= t.cost then
            techN = techN + 1
        end
    end
    if self:CalcPendingShares() >= 1 then prestigeN = prestigeN + 1 end
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

    -- 复利金库锁被动吃利息
    if self:HasTech("bankbook") then
        self.interestTick = self.interestTick + dt
        if self.interestTick >= 1.0 then
            self.interestTick = self.interestTick - 1.0
            local gain = max(1, floor(self.cash * 0.004 + self:GetEstimatedCPS() * 0.12))
            self.cash = self.cash + gain
            self.runCash = self.runCash + gain
            self.lifetimeCash = self.lifetimeCash + gain
            self.cpsAcc = self.cpsAcc + gain
            self:CheckRankUp()
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
    self.cash = max(0, tonumber(s.cash) or 0)
    self.runCash = max(0, tonumber(s.runCash) or self.cash)
    self.lifetimeCash = max(self.runCash, tonumber(s.lifetimeCash) or self.runCash)
    self.prestigeShares = max(0, floor(tonumber(s.prestigeShares) or 0))
    self.totalPrestiges = max(0, floor(tonumber(s.totalPrestiges) or 0))
    self.rankIdx = max(0, min(#Config.RANKS, floor(tonumber(s.rankIdx) or 0)))
    while self.rankIdx > 0 and self.lifetimeCash < Config.RANKS[self.rankIdx].target do
        self.rankIdx = self.rankIdx - 1
    end
    self.stageTheme = max(1, min(3, floor(tonumber(s.stageTheme) or (self:GetRankDef().theme or 1))))
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

    self.adBoostLeft = max(0, tonumber(s.adBoostLeft) or 0)
    self.adWatchCount = max(0, floor(tonumber(s.adWatchCount) or 0))
    self.totalClicks = max(0, floor(tonumber(s.totalClicks) or 0))
    self.totalDrops = max(0, floor(tonumber(s.totalDrops) or 0))
    self.bestHit = max(0, tonumber(s.bestHit) or 0)
    self.maxCombo = max(0, floor(tonumber(s.maxCombo) or 0))
    self.lastActiveAt = max(0, floor(tonumber(s.lastActiveAt) or 0))

    self:CheckRankUp()
    self:ResetPhysics(true)
    return true
end

return Tycoon
