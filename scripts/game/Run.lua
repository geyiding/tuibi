-- ============================================================================
-- Run.lua  纯 Lua 游戏规则与战役流程控制器（零渲染依赖，事件驱动 Fx）
-- ============================================================================

local Config = require("game/Config")
local Physics = require("game/Physics")
local Roster = require("game/Roster")
local Route = require("game/Route")

local floor, min, max, abs, sqrt = math.floor, math.min, math.max, math.abs, math.sqrt
local S = Config.STAGE
local R = Config.RULES

local Run = {}
Run.__index = Run

--- FNV-1a 32位哈希算每日挑战种子（不干扰 math.randomseed）
function Run.DailySeed()
    local dayStr = os.date("!%Y%m%d", os.time())
    local h = 2166136261
    for i = 1, #dayStr do
        h = (h ~ string.byte(dayStr, i)) & 0x7FFFFFFF
        h = (h * 16777619) & 0x7FFFFFFF
    end
    return math.max(1, h), dayStr
end

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

function Run.New(fxListener, opts)
    opts = opts or {}
    local self = setmetatable({}, Run)
    self.fx = fxListener
    self.seed = opts.seed or os.time()
    self.rng = MakeRng(self.seed)
    self.difficulty = max(1, min(20, opts.difficulty or 1))
    self.daily = opts.daily == true
    self.disabled = opts.disabled or {}
    self.sessionId = tostring(self.seed) .. "-" .. tostring(self.difficulty)
    self.resultRevision = 0

    self.roster = Roster.New()
    local diff = Config.DIFFICULTY[self.difficulty] or Config.DIFFICULTY[1]
    self.hearts = diff.startHearts
    self.maxHearts = R.MAX_HEARTS
    self.tickets = R.START_TICKETS

    self.act = 1
    self.layer = 1
    self.endless = false
    self.endlessWave = 0
    self.nodeType = "battle"
    self.bossId = nil
    self.bossTimer = 0
    self.bossLipRaised = false
    self.bossMultSuppressed = false
    self.prechargedFever = false

    -- 局内实时统计
    self.score = 0
    self.targetScore = 950
    self.levelChips = 0
    self.levelMult = 1.0
    self.combo = 0
    self.comboTimer = 0
    self.fever = 0
    self.feverActive = false
    self.feverTimer = 0
    self.feverRainLeft = 0
    self.feverRainTimer = 0
    self.ammoLeft = R.BASE_AMMO_PER_LEVEL
    self.ammoMax = R.BASE_AMMO_PER_LEVEL
    self.shotsFired = 0
    self.shootCooldown = 0
    self.autoDrop = false
    self.goalMet = false
    self.levelEnded = false
    self.settleWait = 0
    self.levelClock = 0

    -- 战役总统计
    self.totalScore = 0
    self.bestHit = 0
    self.maxCombo = 0
    self.coinsDropped = 0
    self.gateWins = 0
    self.feversTriggered = 0
    self.levelsCleared = 0

    -- 排队与商店/事件/路线缓存
    self.queue = {}
    self.queueIdx = 1
    self.rewards = {}
    self.shopItems = {}
    self.shopRefreshCost = 8
    self.deleteCost = 14
    self.currentEvent = nil
    self.eventOutcome = nil
    self.chestRelic = nil
    self.chestClaimed = false
    self.route = Route.BuildAct(1, self.rng)
    self.activeNodeId = "1_1"
    self.selectedNextIds = { ["1_1"] = true }
    self.lastSummary = nil
    self.discoveredLog = {}

    -- 创建物理引擎并挂载事件
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

    return self
end

function Run:ShuffleQueue()
    local q = {}
    for i = 1, #self.roster.coins do
        q[i] = self.roster.coins[i]
    end
    for i = #q, 2, -1 do
        local j = floor(self.rng() * i) + 1
        q[i], q[j] = q[j], q[i]
    end
    self.queue = q
    self.queueIdx = 1
end

function Run:PeekNextCoins(n)
    local out = {}
    local len = #self.queue
    if len == 0 then return out end
    for i = 0, (n or 3) - 1 do
        local idx = ((self.queueIdx - 1 + i) % len) + 1
        out[#out + 1] = self.queue[idx]
    end
    return out
end

function Run:ComputeTargetScore(act, layer, nodeType)
    local diff = Config.DIFFICULTY[self.difficulty] or Config.DIFFICULTY[1]
    if self.endless then
        local base = 2000000000 * (2.3 ^ math.max(0, self.endlessWave - 1))
        return floor(base * diff.targetMul)
    end
    local actCfg = Config.ACTS[act] or Config.ACTS[3]
    local base = actCfg.targets[layer] or actCfg.targets[#actCfg.targets]
    if nodeType == "elite" then base = floor(base * 1.25) end
    return floor(base * diff.targetMul)
end

function Run:StartLevel(act, layer, nodeType)
    self.act = act or self.act
    self.layer = layer or self.layer
    self.nodeType = nodeType or "battle"
    self.bossId = (self.nodeType == "boss") and ((Config.ACTS[self.act] and Config.ACTS[self.act].boss) or "gatekeeper") or nil

    local diff = Config.DIFFICULTY[self.difficulty] or Config.DIFFICULTY[1]
    local pouchBonus = self.roster:HasRelic("big_pouch") and 4 or 0
    self.ammoMax = max(12, R.BASE_AMMO_PER_LEVEL + diff.ammoDelta + pouchBonus + ((self.nodeType == "boss") and 4 or 0))
    self.ammoLeft = self.ammoMax
    self.shotsFired = 0
    self.shootCooldown = 0
    self.score = 0
    self.targetScore = self:ComputeTargetScore(self.act, self.layer, self.nodeType)
    self.levelChips = 0
    self.levelMult = 1.0 + (self.act - 1) * 0.6
    self.combo = 0
    self.comboTimer = 0
    self.fever = self.prechargedFever and 100 or 0
    self.prechargedFever = false
    self.feverActive = false
    self.feverTimer = 0
    self.feverRainLeft = 0
    self.feverRainTimer = 0
    self.goalMet = false
    self.levelEnded = false
    self.settleWait = 0
    self.levelClock = 0
    self.bossTimer = 0
    self.bossLipRaised = false
    self.bossMultSuppressed = false
    self.state = "play"

    self.roster:RecomputeSynergies()
    self:ShuffleQueue()

    self.physics:Reset({
        pusherSpeedScale = self.roster:HasRelic("turbo_pusher") and 1.25 or 1.0,
        pusherForceScale = self.roster:HasRelic("turbo_pusher") and 1.20 or 1.0,
        gateWidthScale   = self.roster:HasRelic("wide_gate") and 1.35 or 1.0,
        railGuard        = self.roster:HasRelic("rail_guard") and 0.65 or 0,
        extraMultPegs    = self.roster:HasRelic("golden_pegs") and 4 or 0,
    })

    local seedKinds = { "gold", "gold", "gold", "emerald", "split", "thunder" }
    if self.act >= 2 then seedKinds[5] = "ruby"; seedKinds[6] = "neon" end
    self.physics:SeedDeck(self.rng, seedKinds)

    if self.fever >= 100 then
        self:TriggerFever()
    end

    Emit(self.fx, "OnLevelLoaded", self)
end

function Run:GetEffectiveMult()
    local m = self.levelMult
    if self.roster:HasRelic("first_surge") and self.shotsFired <= 5 then
        m = m * 2.0
    end
    if self.feverActive then
        m = m * R.FEVER_MULT_BOOST
    end
    if self.bossMultSuppressed then
        m = m * 0.7
    end
    local metBonus = self.roster:HasRelic("metronome") and (self.combo * 0.04) or 0
    return max(1.0, m + metBonus)
end

function Run:AddFever(amount)
    if self.feverActive then return end
    local mul = (self.roster:GetTier("fever") >= 2) and 1.25 or 1.0
    self.fever = min(100, self.fever + amount * mul)
    if self.fever >= 100 then
        self:TriggerFever()
    end
end

function Run:TriggerFever()
    self.fever = 100
    self.feverActive = true
    local dur = R.FEVER_DURATION
    if self.roster:GetTier("fever") >= 4 then dur = dur + 3.0 end
    if self.roster:HasRelic("fever_amp") then dur = dur + 3.0 end
    self.feverTimer = dur
    local rain = R.FEVER_RAIN_COUNT + (self.roster:HasRelic("fever_amp") and 6 or 0)
    self.feverRainLeft = rain
    self.feverRainTimer = 0.05
    self.feversTriggered = self.feversTriggered + 1
    self.physics.pusherSpeedScale = (self.roster:HasRelic("turbo_pusher") and 1.25 or 1.0) * R.FEVER_SPEED_MUL
    Emit(self.fx, "OnFeverStart", self)
end

function Run:RegisterCombo(x, y)
    self.combo = self.combo + 1
    if self.combo > self.maxCombo then self.maxCombo = self.combo end
    self.comboTimer = self.roster:HasRelic("metronome") and 6.5 or R.COMBO_WINDOW
    Emit(self.fx, "OnCombo", self.combo, x, y)
end

function Run:AwardScore(baseChips, x, y, sourceTag, allowCrit)
    local wealthTier = self.roster:GetTier("wealth")
    if wealthTier >= 4 then baseChips = baseChips * 1.60
    elseif wealthTier >= 2 then baseChips = baseChips * 1.25 end
    -- 按幕数放大基础筹码尺度，让2/3幕打出百万到亿级爽感
    local actScale = (self.act == 1) and 1.0 or ((self.act == 2) and 14.0 or 260.0)
    if self.endless then actScale = actScale * (2.0 ^ max(0, self.endlessWave)) end
    baseChips = baseChips * actScale

    local mult = self:GetEffectiveMult()
    local comboMul = 1 + floor(self.combo / 5) * 0.12

    local crit = false
    local critMul = 1.0
    if allowCrit ~= false then
        local cc = R.BASE_CRIT_CHANCE + (self.roster:HasRelic("crit_seal") and 0.18 or 0)
        if self.feverActive then cc = cc + 0.25 end
        if sourceTag == "neon" or sourceTag == "jackpot7" or sourceTag == "carnival" then cc = cc + 0.25 end
        if self.rng() < cc then
            crit = true
            critMul = R.BASE_CRIT_MULT + (self.roster:HasRelic("crit_seal") and 0.8 or 0)
        end
    end

    local dmg = max(1, floor(baseChips * mult * comboMul * critMul + 0.5))
    self.score = self.score + dmg
    self.totalScore = self.totalScore + dmg
    if dmg > self.bestHit then self.bestHit = dmg end
    self.levelChips = self.levelChips + floor(baseChips + 0.5)

    if not self.goalMet and self.score >= self.targetScore then
        self.goalMet = true
        Emit(self.fx, "OnGoalMet", self)
    end

    Emit(self.fx, "OnScore", dmg, x, y, crit, self.combo, sourceTag)
    return dmg, crit
end

function Run:ShootCoin()
    if self.state ~= "play" or self.levelEnded then return false end
    if self.ammoLeft <= 0 or self.shootCooldown > 0 then return false end

    if self.queueIdx > #self.queue then self:ShuffleQueue() end
    local entry = self.queue[self.queueIdx] or { kind = "gold", level = 1 }
    self.queueIdx = self.queueIdx + 1
    if self.queueIdx > #self.queue then self:ShuffleQueue() end

    self.ammoLeft = self.ammoLeft - 1
    self.shotsFired = self.shotsFired + 1
    self.shootCooldown = self.feverActive and 0.14 or 0.20

    local mainCoin = self.physics:LaunchFromTop(entry.kind, entry.level, 0)
    Emit(self.fx, "OnShoot", mainCoin, self)

    -- 双连发（倾泻6档或双发枪管遗物）
    local swarmDouble = (self.roster:GetTier("swarm") >= 6) and (self.rng() < 0.35)
    local barrelDouble = self.roster:HasRelic("double_barrel") and (self.shotsFired % 4 == 0)
    if swarmDouble or barrelDouble then
        self.physics:LaunchFromTop(entry.kind, entry.level, (self.shotsFired % 2 == 0) and 9 or -9)
    end
    return true
end

function Run:HandlePegHit(coin, peg)
    local pDef = Config.PEG_TYPES[peg.kind] or Config.PEG_TYPES.normal
    if pDef.mult and pDef.mult > 0 then
        self.levelMult = self.levelMult + pDef.mult
    end
    if pDef.fever then
        self:AddFever(pDef.fever)
    end
    self:RegisterCombo(peg.x, peg.y)
    self:AwardScore(pDef.chips or 6, peg.x, peg.y, "peg", false)
    Emit(self.fx, "OnPegHit", coin, peg)

    -- 分裂子母 / 无限分身
    local cDef = Config.COINS[coin.kind]
    if cDef and cDef.splitCount and not coin.splitDone then
        coin.splitDone = true
        local cnt = cDef.splitCount + ((self.roster:GetTier("swarm") >= 2) and 1 or 0)
        for k = 1, cnt do
            local ang = (k - (cnt + 1) * 0.5) * 55
            self.physics:SpawnCoin({
                kind = "mini",
                level = coin.level,
                x = coin.x + ang * 0.12,
                y = coin.y + 4,
                vx = coin.vx * 0.5 + ang * 2.2,
                vy = max(60, coin.vy * 0.8),
                radiusMul = 0.72,
                isMini = true,
                splitDone = true,
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

function Run:HandleGateWin(coin)
    self.gateWins = self.gateWins + 1
    self.levelMult = self.levelMult + 0.45
    self:AddFever(18)
    self:RegisterCombo(coin.x, coin.y)

    local cDef = Config.COINS[coin.kind]
    if cDef and cDef.gateRefund then
        self.ammoLeft = self.ammoLeft + cDef.gateRefund
    end

    -- 迷你幸运轮盘
    local luckyBoost = self.roster:HasRelic("clover") and 0.18 or 0
    local roll = self.rng()
    local rewardName = "+1投币"
    if roll < 0.25 + luckyBoost then
        -- 喷射3枚金币雨到推台
        rewardName = "金币雨!"
        for k = 1, 3 do
            self.physics:SpawnCoin({
                kind = "gold", level = 1,
                x = 120 + k * 30, y = S.DECK_TOP_Y + 26 + k * 6,
                vx = (k - 2) * 35, vy = 45, zone = "deck", gateChecked = true, isRain = true,
            })
        end
    elseif roll < 0.60 then
        self.ammoLeft = self.ammoLeft + 1
        rewardName = "+1 投币!"
    else
        self.levelMult = self.levelMult + 0.6
        rewardName = "+0.6x 倍率!"
    end

    if self.roster:GetTier("chain") >= 6 then
        self:TriggerLightning(coin.x, S.DECK_TOP_Y + 80, 5, coin.level)
    end

    self:AwardScore(55, coin.x, coin.y, "gate", true)
    Emit(self.fx, "OnGateWin", coin, rewardName)
end

function Run:HandleEnterDeck(coin)
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

function Run:TriggerLightning(sx, sy, jumps, level)
    local totalJumps = jumps + ((self.roster:GetTier("chain") >= 2) and 1 or 0) + (self.roster:HasRelic("tesla_coil") and 2 or 0)
    local cx, cy = sx, sy
    local coins = self.physics.coins
    local ids = self.physics.activeIds
    local n = self.physics.activeCount
    local hitCount = 0
    for j = 1, totalJumps do
        local best = nil
        local bestD2 = 135 * 135
        for k = 1, n do
            local t = coins[ids[k]]
            if t.active and t.zone == "deck" then
                local dx, dy = t.x - cx, t.y - cy
                local d2 = dx * dx + dy * dy
                if d2 > 36 and d2 < bestD2 then
                    bestD2 = d2
                    best = t
                end
            end
        end
        if not best then break end
        hitCount = hitCount + 1
        Emit(self.fx, "OnLightning", cx, cy, best.x, best.y)
        best.vy = best.vy + 35
        cx, cy = best.x, best.y
        self:AwardScore(24 * (level or 1), cx, cy, "thunder", self.roster:GetTier("chain") >= 4)
    end
    if self.roster:GetTier("chain") >= 4 and hitCount > 0 then
        self.levelMult = self.levelMult + 0.15
    end
end

function Run:HandleBombExplode(coin)
    local def = Config.COINS[coin.kind] or Config.COINS.bomb
    local rad = def.explodeRadius or 72
    local force = def.explodeForce or 240
    if self.roster:GetTier("blast") >= 2 then rad = rad * 1.25 end
    if self.roster:HasRelic("powder_keg") then rad = rad * 1.4; force = force * 1.35 end
    self.physics:ApplyExplosion(coin.x, coin.y, rad, force)
    if self.roster:GetTier("blast") >= 4 then self.levelMult = self.levelMult + 0.8 end
    self:AddFever(coin.kind == "supernova" and 45 or 14)
    self:RegisterCombo(coin.x, coin.y)
    self:AwardScore(90 * coin.level, coin.x, coin.y, coin.kind, true)
    Emit(self.fx, "OnExplosion", coin.x, coin.y, rad)
    -- 爆破6档或核爆二次余震
    if def.doubleBlast or self.roster:GetTier("blast") >= 6 then
        self.physics:ApplyExplosion(coin.x, coin.y + 18, rad * 0.9, force * 0.8)
    end
end

function Run:HandleBlackholeBurst(coin)
    local def = Config.COINS[coin.kind] or Config.COINS.blackhole
    local rad = def.bhRadius or 92
    self.physics:ApplyExplosion(coin.x, coin.y - 14, rad, 210)
    self:RegisterCombo(coin.x, coin.y)
    self:AwardScore(110 * coin.level, coin.x, coin.y, coin.kind, true)
    Emit(self.fx, "OnBlackholeBurst", coin.x, coin.y, rad)
end

function Run:HandleOverclockCoin(coin)
    local stats = Roster.Resolve(coin.kind, coin.level)
    local mult = self.roster:HasRelic("overclock") and 3 or 1.5
    self:AwardScore(stats.baseChips * mult, coin.x, coin.y, "overclock", false)
end

function Run:HandleFrontDrop(coin)
    self.coinsDropped = self.coinsDropped + 1
    local stats = Roster.Resolve(coin.kind, coin.level)
    local def = stats.def
    local chips = stats.baseChips

    if coin.frostT > 0 then chips = chips * 2 end
    if coin.kind == "giant" then chips = chips * 3.5 end
    if coin.kind == "slag" then chips = chips * 4.5 end
    if coin.kind == "vault" then chips = chips * 18.0 end
    if coin.isMini and self.roster:GetTier("swarm") >= 4 then
        self.levelMult = self.levelMult + 0.2
    end
    if self.roster:HasRelic("mag_lip") then
        self.levelMult = self.levelMult + 0.3
    end

    self.levelMult = self.levelMult + stats.multAdd
    if def.permMult then self.levelMult = self.levelMult + def.permMult end
    if self.feverActive and self.roster:GetTier("fever") >= 6 then
        self.levelMult = self.levelMult + 0.5
    end

    if def.ticketBonus then self.tickets = self.tickets + def.ticketBonus end
    if self.roster:GetTier("wealth") >= 6 then self.tickets = self.tickets + 1 end
    if def.feverExtend and self.feverActive then
        self.feverTimer = self.feverTimer + def.feverExtend
    end

    self:AddFever(stats.feverGain)
    self:RegisterCombo(coin.x, coin.y)

    -- 特殊币掉落连锁效果
    if coin.kind == "thunder" or coin.kind == "thor" then
        self:TriggerLightning(coin.x, S.DECK_BOT_Y - 35, def.chainJumps or 3, coin.level)
    elseif coin.kind == "frost" then
        local cList = self.physics.coins
        local ids = self.physics.activeIds
        local marked = 0
        for k = 1, self.physics.activeCount do
            local other = cList[ids[k]]
            if other.active and other.zone == "deck" and marked < 5 then
                other.frostT = 8.0
                marked = marked + 1
            end
        end
    elseif coin.kind == "midas" then
        local cList = self.physics.coins
        local ids = self.physics.activeIds
        local turned = 0
        for k = 1, self.physics.activeCount do
            local other = cList[ids[k]]
            if other.active and other.zone == "deck" and other.kind ~= "midas" and turned < 4 then
                other.kind = "gold"
                turned = turned + 1
            end
        end
        self.levelMult = self.levelMult + 0.8
    elseif def.roll777 then
        local jackpotProb = self.roster:HasRelic("clover") and 0.65 or 0.40
        if self.rng() < jackpotProb then
            self.tickets = self.tickets + 5
            self.levelMult = self.levelMult + 1.5
            for k = 1, 5 do
                self.physics:SpawnCoin({
                    kind = "gold", level = 1, x = 110 + k * 28, y = S.DECK_TOP_Y + 34,
                    vx = (k - 3) * 28, vy = 55, zone = "deck", gateChecked = true, isRain = true,
                })
            end
            Emit(self.fx, "OnJackpot777", coin.x, coin.y)
        end
    end

    local dmg, crit = self:AwardScore(chips, coin.x, coin.y - 12, coin.kind, true)
    Emit(self.fx, "OnFrontDrop", coin, dmg, crit)
end

function Run:HandleSideDrain(coin)
    if self.roster:HasRelic("rail_guard") then
        local stats = Roster.Resolve(coin.kind, coin.level)
        self:AwardScore(stats.baseChips * 0.5, coin.x, coin.y, "guard", false)
    end
    if self.roster:HasRelic("recycler") and coin.fromShot and self.rng() < 0.25 then
        self.ammoLeft = self.ammoLeft + 1
    end
    Emit(self.fx, "OnSideDrain", coin)
end

function Run:Update(dt)
    if self.state ~= "play" or self.levelEnded then return end
    if dt > 0.05 then dt = 0.05 end
    self.levelClock = self.levelClock + dt
    if self.shootCooldown > 0 then self.shootCooldown = max(0, self.shootCooldown - dt) end

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
                local rx = 96 + self.rng() * 168
                local rKind = (self.feverRainLeft % 5 == 0) and "emerald" or "gold"
                self.physics:SpawnCoin({
                    kind = rKind, level = 1,
                    x = rx, y = S.DECK_TOP_Y + 24,
                    vx = (self.rng() - 0.5) * 40, vy = 55,
                    zone = "deck", gateChecked = true, isRain = true,
                })
            end
        end
        if self.feverTimer <= 0 then
            self.feverActive = false
            self.fever = 0
            self.physics.pusherSpeedScale = self.roster:HasRelic("turbo_pusher") and 1.25 or 1.0
            Emit(self.fx, "OnFeverEnd", self)
        end
    end

    -- Boss 机制驱动
    if self.bossId then
        self:UpdateBoss(dt)
    end

    -- 自动投币
    if self.autoDrop and self.ammoLeft > 0 and self.shootCooldown <= 0 then
        self:ShootCoin()
    end

    -- 推进物理
    self.physics:Step(dt)

    -- 聚能6档：推板伸出波（周期脉冲）
    if self.roster:GetTier("gravity") >= 6 and self.physics.pusherVelY > 36 and floor(self.levelClock * 10) % 15 == 0 then
        self.physics:ApplyExplosion(180, self.physics.pusherY + 12, 95, 45)
    end

    -- 关末结算判定（全部子弹投完 + 槽内硬币全部落地 + 缓冲 0.9s）
    if self.ammoLeft <= 0 and not self.feverActive then
        if not self.physics:HasActiveSlotCoins() then
            self.settleWait = self.settleWait + dt
            if self.settleWait >= 0.9 then
                self:FinishLevel()
            end
        else
            self.settleWait = 0
        end
    end
end

function Run:UpdateBoss(dt)
    self.bossTimer = self.bossTimer + dt
    if self.bossId == "gatekeeper" then
        local cyc = self.bossTimer % 7.5
        self.physics.gateClosed = (cyc >= 5.2)
        self.bossLipRaised = (cyc >= 3.0 and cyc <= 6.2)
        self.physics.frontLipResist = self.bossLipRaised and 0.22 or 0.08
    elseif self.bossId == "furnace" then
        if self.bossTimer >= 4.5 then
            self.bossTimer = 0
            self.physics:SpawnCoin({
                kind = "slag", level = 1,
                x = 120 + self.rng() * 120, y = S.DECK_TOP_Y + 32,
                vx = (self.rng() - 0.5) * 30, vy = 35,
                zone = "deck", gateChecked = true,
            })
            Emit(self.fx, "OnBossAction", "熔金巨轮空投熔渣币!")
        end
    elseif self.bossId == "vaultbeast" then
        local cyc = self.bossTimer % 8.0
        self.bossMultSuppressed = (cyc >= 5.0)
        if floor(self.levelClock * 10) == 20 or (self.bossTimer >= 7.9 and self.bossTimer - dt < 7.9) then
            self.physics:SpawnCoin({
                kind = "vault", level = 1,
                x = 140 + self.rng() * 80, y = S.DECK_TOP_Y + 36,
                vx = 0, vy = 35, zone = "deck", gateChecked = true,
            })
            Emit(self.fx, "OnBossAction", "终极吞金兽投入装甲金库币!")
        end
    end
end

function Run:FinishLevel()
    if self.levelEnded then return end
    self.levelEnded = true
    self.autoDrop = false
    self.physics.gateClosed = false
    self.bossMultSuppressed = false

    local cleared = self.score >= self.targetScore
    local ratio = self.score / max(1, self.targetScore)
    local heartLoss = 0
    if not cleared then
        heartLoss = (ratio >= 0.55) and 1 or 2
        self.hearts = max(0, self.hearts - heartLoss)
    else
        self.levelsCleared = self.levelsCleared + 1
        if self.roster:HasRelic("medkit") and self.layer == 6 then
            if self.hearts < self.maxHearts then self.hearts = self.hearts + 1 end
        end
    end

    -- 过关经济结算
    local baseTicket = 18 + (self.act - 1) * 6 + ((self.nodeType == "boss") and 10 or 0)
    local overkillBonus = cleared and min(12, floor((ratio - 1) * 6)) or 0
    local step = self.roster:HasRelic("bankbook") and 20 or R.INTEREST_STEP
    local cap = R.INTEREST_CAP + (self.roster:HasRelic("bankbook") and 10 or 0) + ((self.roster:GetTier("wealth") >= 4) and 10 or 0)
    local interest = min(cap, floor(self.tickets / step) * R.INTEREST_BONUS)
    local earnedTickets = (cleared and baseTicket or floor(baseTicket * 0.5)) + max(0, overkillBonus) + interest
    if self.hearts > 0 then
        self.tickets = self.tickets + earnedTickets
    end

    self.lastSummary = {
        cleared = cleared,
        score = self.score,
        targetScore = self.targetScore,
        heartLoss = heartLoss,
        baseTicket = baseTicket,
        overkillBonus = max(0, overkillBonus),
        interest = interest,
        earnedTickets = earnedTickets,
    }

    if self.hearts <= 0 then
        self.state = "result"
        self.won = false
        Emit(self.fx, "OnLevelEnd", false, self.lastSummary)
        return
    end

    -- 检查全3幕通关（非无尽）
    if not self.endless and self.act >= 3 and self.layer >= 6 then
        self.state = "result"
        self.won = cleared
        Emit(self.fx, "OnLevelEnd", cleared, self.lastSummary)
        return
    end

    self:BuildRewardChoices()
    self.state = "reward"
    Emit(self.fx, "OnLevelEnd", true, self.lastSummary)
end

function Run:BuildRewardChoices()
    local pool = {}
    for _, id in ipairs(Config.COIN_POOL) do
        if not self.disabled[id] then
            local def = Config.COINS[id]
            local allow = (def.rarity == "common")
                or (def.rarity == "rare" and (self.act >= 2 or self.layer >= 3))
                or (def.rarity == "legendary" and (self.act >= 3 or self.nodeType == "boss" or self.nodeType == "elite"))
            if allow then pool[#pool + 1] = id end
        end
    end
    if #pool < 3 then pool = { "gold", "emerald", "split", "thunder", "bomb" } end

    local picks = {}
    local used = {}
    for i = 1, 3 do
        local chosen = pool[floor(self.rng() * #pool) + 1]
        for _ = 1, 10 do
            if not used[chosen] then break end
            chosen = pool[floor(self.rng() * #pool) + 1]
        end
        used[chosen] = true
        picks[i] = { kind = chosen, level = 1 }
    end
    self.rewards = picks
end

function Run:PickReward(idx)
    if self.state ~= "reward" then return false end
    local r = self.rewards[idx]
    if not r then return false end
    self.roster:AddCoin(r.kind, r.level)
    self.discoveredLog["coin:" .. r.kind] = true
    Emit(self.fx, "OnRewardPicked", r.kind)
    return true
end

function Run:SkipReward()
    if self.state ~= "reward" then return false end
    self.tickets = self.tickets + 10
    return true
end

--- 完成当前节点后回到路线图并解锁后继节点（或进入下一幕）
function Run:LeaveToMap()
    local cur = self.route and self.route.byId[self.activeNodeId]
    if cur then cur.visited = true end

    if self.endless then
        self.endlessWave = self.endlessWave + 1
        self:StartLevel(3, 6, "boss")
        return "play"
    end

    if cur and cur.layer >= 6 then
        if self.act < 3 then
            self.act = self.act + 1
            self.route = Route.BuildAct(self.act, self.rng)
            self.activeNodeId = "1_1"
            self.selectedNextIds = { ["1_1"] = true }
        else
            self.state = "result"
            self.won = true
            return "result"
        end
    elseif cur and #cur.next > 0 then
        self.selectedNextIds = {}
        for _, nid in ipairs(cur.next) do
            self.selectedNextIds[nid] = true
        end
    end
    self.state = "map"
    return "map"
end

function Run:IsNodeSelectable(nodeId)
    return self.selectedNextIds and self.selectedNextIds[nodeId] == true
end

function Run:EnterNode(nodeId)
    if not self.route then return false end
    local node = self.route.byId[nodeId]
    if not node or not self:IsNodeSelectable(nodeId) then return false end
    self.activeNodeId = nodeId
    self.layer = node.layer

    if node.type == "battle" or node.type == "elite" or node.type == "boss" then
        if node.type == "boss" and node.bossId then
            self.discoveredLog["boss:" .. node.bossId] = true
        end
        self:StartLevel(self.act, node.layer, node.type)
        return "play"
    elseif node.type == "shop" then
        self:OpenShop()
        self.state = "shop"
        return "shop"
    elseif node.type == "rest" then
        self.state = "rest"
        return "rest"
    elseif node.type == "event" then
        local eid = Config.EVENT_ORDER[floor(self.rng() * #Config.EVENT_ORDER) + 1]
        self.currentEvent = Config.EVENTS[eid]
        self.eventOutcome = nil
        self.state = "event"
        return "event"
    elseif node.type == "chest" then
        self.chestClaimed = false
        self.chestRelic = self:PickUnownedRelic()
        self.state = "chest"
        return "chest"
    end
    return false
end

function Run:PickUnownedRelic()
    local cand = {}
    for _, rid in ipairs(Config.RELIC_ORDER) do
        if not self.roster:HasRelic(rid) and not self.disabled[rid] then
            cand[#cand + 1] = rid
        end
    end
    if #cand == 0 then return nil end
    return cand[floor(self.rng() * #cand) + 1]
end

function Run:OpenShop()
    self.shopItems = {}
    local disc = self.roster:HasRelic("vip_card") and 0.8 or 1.0
    -- 3 枚币
    local coinPool = {}
    for _, cid in ipairs(Config.COIN_POOL) do
        if not self.disabled[cid] then coinPool[#coinPool + 1] = cid end
    end
    for i = 1, 3 do
        local cid = coinPool[floor(self.rng() * #coinPool) + 1] or "gold"
        local def = Config.COINS[cid]
        local baseP = (def.rarity == "legendary" and 38) or (def.rarity == "rare" and 22) or 14
        self.shopItems[#self.shopItems + 1] = {
            kind = "coin", id = cid, price = max(6, floor(baseP * disc)), sold = false,
        }
    end
    -- 2 件遗物
    local usedRelic = {}
    for i = 1, 2 do
        local rid = self:PickUnownedRelic()
        if rid and not usedRelic[rid] then
            usedRelic[rid] = true
            local rDef = Config.RELICS[rid]
            self.shopItems[#self.shopItems + 1] = {
                kind = "relic", id = rid, price = max(12, floor((rDef.price or 30) * disc)), sold = false,
            }
        end
    end
    -- 1 个心包
    self.shopItems[#self.shopItems + 1] = {
        kind = "heal", id = "bandage", price = max(8, floor(14 * disc)), sold = false,
    }
end

function Run:BuyShopItem(idx)
    local item = self.shopItems[idx]
    if not item or item.sold or self.tickets < item.price then return false end
    if item.kind == "heal" and self.hearts >= self.maxHearts then return false end
    self.tickets = self.tickets - item.price
    item.sold = true
    if item.kind == "coin" then
        self.roster:AddCoin(item.id, 1)
        self.discoveredLog["coin:" .. item.id] = true
    elseif item.kind == "relic" then
        self.roster:AddRelic(item.id)
        self.discoveredLog["relic:" .. item.id] = true
    elseif item.kind == "heal" then
        self.hearts = min(self.maxHearts, self.hearts + 1)
    end
    return true
end

function Run:RefreshShop()
    if self.tickets < self.shopRefreshCost then return false end
    self.tickets = self.tickets - self.shopRefreshCost
    self.shopRefreshCost = self.shopRefreshCost + 4
    self:OpenShop()
    return true
end

function Run:GetDeleteCost()
    local base = self.deleteCost
    if self.roster:HasRelic("vip_card") then base = floor(base * 0.5) end
    return base
end

function Run:DeleteCoinFromShop(uid)
    local cost = self:GetDeleteCost()
    if self.tickets < cost or #self.roster.coins <= 4 then return false end
    if self.roster:RemoveCoinByUid(uid) then
        self.tickets = self.tickets - cost
        self.deleteCost = self.deleteCost + 6
        return true
    end
    return false
end

function Run:RestHealAndAmmo()
    self.hearts = min(self.maxHearts, self.hearts + 2)
    self.roster:AddCoin("gold", 1)
    self.tickets = self.tickets + 8
    return true
end

function Run:ClaimChest()
    if self.chestClaimed then return false end
    self.chestClaimed = true
    if self.chestRelic then
        self.roster:AddRelic(self.chestRelic)
        self.discoveredLog["relic:" .. self.chestRelic] = true
    else
        self.tickets = self.tickets + 35
    end
    self.tickets = self.tickets + 12
    return true
end

function Run:ChooseEvent(choiceKey)
    if not self.currentEvent or self.eventOutcome then return nil end
    local ch = (choiceKey == "a") and self.currentEvent.a or self.currentEvent.b
    local eff = ch and ch.effect
    local msg = "事件完成"
    if eff == "sacrifice_heart" then
        if self.hearts > 1 then
            self.hearts = self.hearts - 1
            self.tickets = self.tickets + 50
            msg = "失去1心，夺得 +50金券！"
        else
            self.tickets = self.tickets + 20
            msg = "仅余1心免于献祭，获赠 +20金券！"
        end
    elseif eff == "free_tickets" then
        self.tickets = self.tickets + 18
        msg = "顺手牵走 +18金券！"
    elseif eff == "upgrade_coin" then
        local up = false
        for i = 1, #self.roster.coins do
            if self.roster.coins[i].level < 3 then
                self.roster:UpgradeCoinByUid(self.roster.coins[i].uid)
                msg = Config.COINS[self.roster.coins[i].kind].name .. " 升至 Lv" .. self.roster.coins[i].level
                up = true
                break
            end
        end
        if not up then self.tickets = self.tickets + 25; msg = "全满星，改赠 +25金券！" end
    elseif eff == "gain_relic" then
        local rid = self:PickUnownedRelic()
        if rid then
            self.roster:AddRelic(rid)
            self.discoveredLog["relic:" .. rid] = true
            msg = "获得遗物：" .. Config.RELICS[rid].name
        else
            self.tickets = self.tickets + 30
            msg = "遗物已满，获得 +30金券！"
        end
    elseif eff == "gamble_tickets" then
        if self.rng() < 0.5 then
            self.tickets = self.tickets + 45
            msg = "手气爆棚！赢取 +45金券！"
        else
            self.tickets = self.tickets + 8
            msg = "差一点点… 拿回 +8安慰金券"
        end
    elseif eff == "safe_tickets" then
        self.tickets = self.tickets + 20
        msg = "稳妥带走 +20金券！"
    elseif eff == "heal_hearts" then
        self.hearts = min(self.maxHearts, self.hearts + 2)
        self.roster:AddCoin("emerald", 1)
        msg = "恢复2心并加入 幸运翡翠！"
    elseif eff == "precharge_fever" then
        self.prechargedFever = true
        msg = "下关满狂欢能量直接爆发！"
    elseif eff == "purge_common" then
        for i = #self.roster.coins, 1, -1 do
            if #self.roster.coins > 4 and self.roster.coins[i].kind == "gold" then
                table.remove(self.roster.coins, i)
                break
            end
        end
        self.roster:RecomputeSynergies()
        self.tickets = self.tickets + 25
        msg = "精简1枚金币并获 +25金券！"
    elseif eff == "add_rare" then
        self.roster:AddCoin("ruby", 1)
        self.discoveredLog["coin:ruby"] = true
        msg = "获得进阶币：红宝石倍率！"
    elseif eff == "buy_relic_cheap" then
        if self.tickets >= 15 then
            self.tickets = self.tickets - 15
            local rid = self:PickUnownedRelic()
            if rid then
                self.roster:AddRelic(rid)
                self.discoveredLog["relic:" .. rid] = true
                msg = "破译成功！获得 " .. Config.RELICS[rid].name
            else
                self.tickets = self.tickets + 30
                msg = "密室余金 +30券！"
            end
        else
            self.tickets = self.tickets + 12
            msg = "金券不足，只取走 +12券"
        end
    else
        self.tickets = self.tickets + 12
        msg = "获得 +12金券"
    end
    self.eventOutcome = msg
    return msg
end

function Run:ExportSnapshot()
    local coins = {}
    for i = 1, #self.roster.coins do
        local c = self.roster.coins[i]
        coins[i] = { kind = c.kind, level = c.level }
    end
    local visited = {}
    if self.route then
        for id, node in pairs(self.route.byId) do
            if node.visited then visited[#visited + 1] = id end
        end
    end
    local nextIds = {}
    for k, v in pairs(self.selectedNextIds or {}) do
        if v then nextIds[#nextIds + 1] = k end
    end
    return {
        seed = self.seed,
        difficulty = self.difficulty,
        daily = self.daily,
        act = self.act,
        layer = self.layer,
        endless = self.endless,
        endlessWave = self.endlessWave,
        hearts = self.hearts,
        tickets = self.tickets,
        totalScore = self.totalScore,
        bestHit = self.bestHit,
        maxCombo = self.maxCombo,
        levelsCleared = self.levelsCleared,
        activeNodeId = self.activeNodeId,
        visited = visited,
        nextIds = nextIds,
        coins = coins,
        relics = self.roster.relicList,
        prechargedFever = self.prechargedFever,
    }
end

function Run:ImportSnapshot(snap)
    if type(snap) ~= "table" or type(snap.coins) ~= "table" then return false end
    self.act = snap.act or 1
    self.layer = snap.layer or 1
    self.endless = snap.endless == true
    self.endlessWave = snap.endlessWave or 0
    self.hearts = max(1, snap.hearts or 5)
    self.tickets = snap.tickets or 24
    self.totalScore = snap.totalScore or 0
    self.bestHit = snap.bestHit or 0
    self.maxCombo = snap.maxCombo or 0
    self.levelsCleared = snap.levelsCleared or 0
    self.prechargedFever = snap.prechargedFever == true

    self.roster.coins = {}
    self.roster.relics = {}
    self.roster.relicList = {}
    self.roster.nextUid = 1
    for _, c in ipairs(snap.coins) do
        self.roster:AddCoin(c.kind, c.level)
    end
    for _, rid in ipairs(snap.relics or {}) do
        self.roster:AddRelic(rid)
    end
    self.roster:RecomputeSynergies()

    self.route = Route.BuildAct(self.act, self.rng)
    for _, vid in ipairs(snap.visited or {}) do
        if self.route.byId[vid] then self.route.byId[vid].visited = true end
    end
    self.activeNodeId = snap.activeNodeId or "1_1"
    self.selectedNextIds = {}
    for _, nid in ipairs(snap.nextIds or {}) do
        self.selectedNextIds[nid] = true
    end
    if not next(self.selectedNextIds) then
        self.selectedNextIds["1_1"] = true
    end
    self.state = "map"
    return true
end

function Run:AdvanceNextBattleSimple()
    -- 兼容 Demo 直进下一关，若调用完整路线流则走 LeaveToMap
    if self.layer < 6 then
        self.layer = self.layer + 1
    else
        self.act = self.act + 1
        self.layer = 1
    end
    local nt = (self.layer == 6) and "boss" or ((self.layer == 4) and "elite" or "battle")
    self:StartLevel(self.act, self.layer, nt)
end

return Run
