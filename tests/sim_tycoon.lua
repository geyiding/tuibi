-- ============================================================================
-- tests/sim_tycoon.lua  真实 60Hz 物理诊断 + 10小时宏观数值校准模拟器 + 浮点溢出压测
-- ============================================================================

local Config = require("game/Config")
local Number = require("game/Number")
local Tycoon = require("game/Tycoon")

local floor, min, max = math.floor, math.min, math.max

-- ----------------------------------------------------------------------------
-- Part A: 180 秒 60Hz 真实物理诊断（idle / click2s / hold × 2 种子）
-- ----------------------------------------------------------------------------
local function runPhysicsDiag(mode, seed)
    local ty = Tycoon.New(nil, { seed = seed })
    -- 置入中盘常见构筑（验证高投币量下的掉币效率、撞钉限制、幸运三连限流与狂欢冷却）
    ty.cash = 1e6
    ty.lifetimeCash = 1e6
    ty.skillPoints = 4000
    local function buyN(id, n)
        for _ = 1, n do ty:BuyMachineUpgrade(id, 1) end
    end
    buyN("auto_rate", 6)
    buyN("multi_shot", 6)
    buyN("pusher_turbo", 5)
    buyN("peg_gold", 5)
    buyN("gate_master", 5)
    buyN("fever_drive", 5)
    for i = 2, 10 do
        ty:BuyCoin(Config.COIN_TIERS[i].id)
    end
    for _, tid in ipairs({ "rail_guard", "metronome", "medkit", "mag_lip", "clover" }) do
        ty:BuyTech(tid)
    end
    ty:ResetPhysics(true)

    local bucket = { front = 0.0, peg = 0.0, gate = 0.0, overclock = 0.0, wave = 0.0, other = 0.0, jp = 0.0 }
    local ctx = "other"
    local origAward = ty.AwardCash
    local origFront = ty.HandleFrontDrop
    local origPeg = ty.HandlePegHit
    local origGate = ty.HandleGateWin
    local origOver = ty.HandleOverclockCoin
    local origAdd = ty.AddWealth

    ty.AwardCash = function(self, baseVal, x, y, sourceTag, canCrit, extraMul)
        local dmg, crit = origAward(self, baseVal, x, y, sourceTag, canCrit, extraMul)
        return dmg, crit
    end
    ty.AddWealth = function(self, amount, addToCps, tempMul)
        local added = origAdd(self, amount, addToCps, tempMul)
        bucket[ctx] = (bucket[ctx] or 0.0) + added
        return added
    end
    ty.HandleFrontDrop = function(self, coin)
        local prev = ctx; ctx = "front"
        origFront(self, coin)
        ctx = prev
    end
    ty.HandlePegHit = function(self, coin, peg, hitSpd)
        local prev = ctx; ctx = "peg"
        origPeg(self, coin, peg, hitSpd)
        ctx = prev
    end
    ty.HandleGateWin = function(self, coin)
        local prev = ctx; ctx = "gate"
        origGate(self, coin)
        ctx = prev
    end
    local origJp = ty.JpRelease
    ty.JpRelease = function(self, tierId)
        local prev = ctx; ctx = "jp"
        local amt = origJp(self, tierId)
        ctx = prev
        return amt
    end
    ty.HandleOverclockCoin = function(self, coin)
        local prev = ctx; ctx = "overclock"
        origOver(self, coin)
        ctx = prev
    end

    -- 预热 10 秒 (600 帧)
    for _ = 1, 600 do
        if mode == "hold" then ty:ManualShoot() end
        ty:Update(1 / 60)
    end
    -- 清零正式统计窗（180 秒 = 10800 帧）
    local drops0 = ty.totalDrops
    for k in pairs(bucket) do bucket[k] = 0.0 end

    collectgarbage("collect")
    local memBefore, memAfter
    local gcFrames = 1800 -- 暂停自动 GC 精确测 30 秒原始堆分配速率
    collectgarbage("stop")
    memBefore = collectgarbage("count")

    local totalFrames = 10800
    local feverFrames = 0
    local luckSum = 0.0
    local gateWins = 0
    local origGateCountWrap = ty.HandleGateWin
    ty.HandleGateWin = function(self, coin)
        gateWins = gateWins + 1
        return origGateCountWrap(self, coin)
    end

    for f = 1, totalFrames do
        if mode == "hold" then
            ty:ManualShoot()
        elseif mode == "click2s" and (f % 30 == 0) then
            ty:ManualShoot()
        end
        ty:Update(1 / 60)
        if ty.feverActive then feverFrames = feverFrames + 1 end
        luckSum = luckSum + (ty.luckMult or 1)
        if f == gcFrames then
            memAfter = collectgarbage("count")
            collectgarbage("restart")
        end
    end

    local gcKbPerSec = ((memAfter or collectgarbage("count")) - memBefore) / (gcFrames / 60.0)
    local totalCash = bucket.front + bucket.peg + bucket.gate + bucket.overclock + bucket.wave + bucket.other
    local frontShare = (totalCash > 0) and (bucket.front / totalCash) or 0
    return {
        mode = mode,
        dropsPerSec = (ty.totalDrops - drops0) / 180.0,
        frontShare = frontShare,
        pegShare = (totalCash > 0) and (bucket.peg / totalCash) or 0,
        gateShare = (totalCash > 0) and (bucket.gate / totalCash) or 0,
        overShare = (totalCash > 0) and (bucket.overclock / totalCash) or 0,
        otherShare = (totalCash > 0) and (bucket.other / totalCash) or 0,
        feverUptime = feverFrames / totalFrames,
        avgLuckMult = luckSum / totalFrames,
        gcKbPerSec = gcKbPerSec,
        gatePerSec = gateWins / 180.0,
    }
end

print("=== [Part A] 60Hz Real Physics Diagnostic (180s x 2 seeds) ===")
local diagAgg = {}
for _, mode in ipairs({ "idle", "click2s", "hold" }) do
    local sDrops, sFront, sPeg, sGate, sFev, sLuck, sGc = 0, 0, 0, 0, 0, 0, 0
    local seeds = { 202601, 202602 }
    for _, sd in ipairs(seeds) do
        local r = runPhysicsDiag(mode, sd)
        sDrops = sDrops + r.dropsPerSec
        sFront = sFront + r.frontShare
        sPeg = sPeg + r.pegShare
        sGate = sGate + r.gateShare
        sFev = sFev + r.feverUptime
        sLuck = sLuck + r.avgLuckMult
        sGc = sGc + r.gcKbPerSec
    end
    local n = #seeds
    local avg = {
        dropsPerSec = sDrops / n,
        frontShare = sFront / n,
        pegShare = sPeg / n,
        gateShare = sGate / n,
        feverUptime = sFev / n,
        avgLuckMult = sLuck / n,
        gcKbPerSec = sGc / n,
    }
    diagAgg[mode] = avg
    print(string.format(
        "  mode=%-7s drops/s=%.2f front=%.1f%% peg=%.1f%% gate=%.1f%% fever=%.1f%% avgLuck=x%.2f gc=%.1fKB/s",
        mode, avg.dropsPerSec, avg.frontShare * 100, avg.pegShare * 100,
        avg.gateShare * 100, avg.feverUptime * 100, avg.avgLuckMult, avg.gcKbPerSec
    ))
end

assert(diagAgg.hold.dropsPerSec >= diagAgg.idle.dropsPerSec,
    string.format("长按落币不得少于挂机: hold=%.2f < idle=%.2f", diagAgg.hold.dropsPerSec, diagAgg.idle.dropsPerSec))
assert(diagAgg.click2s.frontShare >= 0.60,
    string.format("正面掉落收入占比必须 >= 60%%, 当前 %.1f%%", diagAgg.click2s.frontShare * 100))
assert(diagAgg.idle.feverUptime >= 0.12 and diagAgg.idle.feverUptime <= 0.28,
    string.format("挂机狂欢在线率目标 15%%~25%% (允许 12%%~28%%), 当前 %.1f%%", diagAgg.idle.feverUptime * 100))
assert(diagAgg.click2s.avgLuckMult <= 12.0,
    string.format("幸运三连均值倍率必须 <= 12x, 当前 %.2fx", diagAgg.click2s.avgLuckMult))
assert(diagAgg.hold.gcKbPerSec < 50.0,
    string.format("每帧 GC 分配过高: %.2f KB/s >= 50 KB/s", diagAgg.hold.gcKbPerSec))

-- JP 大奖池在宏观模型里按比例计入：普通收入先被抽走 FEED_TAX 养分，JP 再以“占抽成后收入的比例”返还
-- （tests/jp_probe.lua 45 分钟实机物理实测：JP 约占总收入 17%~20% -> 相对抽成后收入约 +0.22；看广告翻倍再 +0.22）
local JP_INCOME_RATIO = 0.22
local JP_TAX = Config.JACKPOT.FEED_TAX or 0

-- ----------------------------------------------------------------------------
-- Part B: 10 小时宏观经济模拟器（使用真实 Tycoon 数值与策略购买，4 玩法 × 4 种子）
-- ----------------------------------------------------------------------------
local function spendSmartSP(ty, isAds)
    local did, bought = false, true
    while bought do
        bought = false
        if ty:CanDoIpo() then
            ty:DoCapitalIPO(isAds)
            for _, p in ipairs(Config.PRESTIGE_TALENTS) do
                while ty:BuyPrestigeTalent(p.id) do did = true end
            end
        end
        if ty:CanAscendEra() then
            ty:DoGalacticAscend()
        end

        local cands = {}
        local curAvg = max(1.0, ty:GetAvgUnlockedCoinValue())
        for _, tier in ipairs(Config.COIN_TIERS) do
            if (ty.coinLv[tier.id] or 0) == 0 then
                local c, mx, lk = ty:GetCoinCost(tier.id)
                if not mx and not lk then
                    local gain = (tier.baseValue / curAvg) * 0.28 + 0.14
                    cands[#cands + 1] = { tp = "coin", id = tier.id, cost = c, roi = gain / max(1, c) }
                end
                break
            end
        end
        local gmCost, gmCnt = ty:GetMachineCost("global_mult", 1)
        if gmCnt > 0 then
            cands[#cands + 1] = { tp = "mach", id = "global_mult", cost = gmCost, roi = 0.0205 / max(1, gmCost) }
        end
        local arCost, arCnt = ty:GetMachineCost("auto_rate", 1)
        if arCnt > 0 then
            local curR = ty:GetAutoRate(true)
            local g = (curR < 9.0) and (0.14 / max(0.5, curR) * 0.65) or 0.001
            cands[#cands + 1] = { tp = "mach", id = "auto_rate", cost = arCost, roi = g / max(1, arCost) }
        end
        local msCost, msCnt = ty:GetMachineCost("multi_shot", 1)
        if msCnt > 0 then
            cands[#cands + 1] = { tp = "mach", id = "multi_shot", cost = msCost, roi = 0.035 / max(1, msCost) }
        end
        -- 功能型机台：按每级附带的全币倍率估值（自身玩法效果实测很小，忽略）
        for _, m in ipairs(Config.MACHINE_UPGRADES) do
            if m.multPerLv then
                local fc, fcnt = ty:GetMachineCost(m.id, 1)
                if fcnt > 0 then
                    cands[#cands + 1] = { tp = "mach", id = m.id, cost = fc, roi = (m.multPerLv - 1.0) / max(1, fc) }
                end
            end
        end
        local crCost, crCnt = ty:GetMachineCost("crit_power", 1)
        if crCnt > 0 then
            cands[#cands + 1] = { tp = "mach", id = "crit_power", cost = crCost, roi = 0.04 / max(1, crCost) }
        end
        for _, tc in ipairs(Config.TECH_UPGRADES) do
            if not ty:HasTech(tc.id) then
                cands[#cands + 1] = { tp = "tech", id = tc.id, cost = tc.costSp, roi = (tc.mult - 1.0) / max(1, tc.costSp) }
            end
        end
        local unl = ty:GetUnlockedCoins()
        for i = max(1, #unl - 2), #unl do
            local cid = unl[i]
            local c, mx, lk = ty:GetCoinCost(cid)
            if not mx and not lk then
                cands[#cands + 1] = { tp = "coin", id = cid, cost = c, roi = 0.065 / max(1, c) }
            end
        end
        table.sort(cands, function(a, b) return a.roi > b.roi end)
        local top = cands[1]
        if top and ty.skillPoints >= top.cost then
            if top.tp == "coin" then bought = ty:BuyCoin(top.id)
            elseif top.tp == "mach" then bought = ty:BuyMachineUpgrade(top.id, 1)
            elseif top.tp == "tech" then bought = ty:BuyTech(top.id) end
            if bought then did = true end
        end
    end
    return did
end

local function calcExpectedSlotLuck()
    local ty = Tycoon.New(nil, { seed = 42 })
    ty.machineLv.gate_master = 5
    ty.techOwned.clover = true
    local totalTime, weightedLuck, curMult, curLeft = 0.0, 0.0, 1.0, 0.0
    for _ = 1, 10000 do
        local stepDt = 9.5
        local act = min(stepDt, curLeft)
        weightedLuck = weightedLuck + act * curMult + (stepDt - act) * 1.0
        totalTime = totalTime + stepDt
        curLeft = max(0.0, curLeft - stepDt)
        if curLeft <= 0 then curMult = 1.0 end
        local out = ty:RollSlotOutcome()
        local p = out and out.prize
        if p and p.mult and p.mult > 1 then
            if p.mult > curMult or curLeft <= 0 then
                curMult, curLeft = p.mult, p.dur
            elseif p.mult == curMult then
                curLeft = max(curLeft, p.dur)
            end
        end
    end
    return weightedLuck / totalTime
end

local expectedSlotLuck = calcExpectedSlotLuck()

local function simulateMacro10Hours(mode, seed)
    local ty = Tycoon.New(nil, { seed = seed })
    -- 禁用物理实体模拟，在 10 小时宏观模型下使用 Part A 实测物理参数 + 长期期望三连倍率
    local diagRef = (mode == "ads") and diagAgg.click2s or diagAgg[mode]
    local isAds = (mode == "ads")
    local actInterval = (mode == "idle") and 60 or 10
    local fevUptime = diagRef.feverUptime
    local luckAvg = expectedSlotLuck
    local manualFrac = (mode == "hold" and 0.68) or ((mode == "click2s" or mode == "ads") and 0.40) or 0.0

    local top1000Min, world1Min, all22Min
    local lastBuyMin = 0.0
    local maxBuyGapMin = 0.0
    local cpsAtWorld1 = 0.0
    local boostLeft = 0.0
    local adCds = { boost_3x = 0, instant_fever = 0, vault_drop = 0, airdrop_5x = 0 }
    local airdropCd = 55.0

    local dt = 1.0
    local totalSec = 15 * 3600 -- 15 小时宏观检验窗（完整容纳 idle ~11.7h 收尾）
    local unlockedN = 1

    for sec = 1, totalSec do
        local minNow = sec / 60.0

        -- 冷却倒计时与广告策略
        if boostLeft > 0 then boostLeft = max(0, boostLeft - dt) end
        for k, v in pairs(adCds) do if v > 0 then adCds[k] = max(0, v - dt) end end
        if isAds then
            if adCds.boost_3x <= 0 then
                boostLeft = min(300, boostLeft + 180)
                adCds.boost_3x = Config.AD_PLACEMENTS.boost_3x.cooldown
            end
            if adCds.instant_fever <= 0 then
                ty:AddWealth(ty:GetBaselineCPS() * 60 * 2.2, false)
                adCds.instant_fever = Config.AD_PLACEMENTS.instant_fever.cooldown
            end
            if adCds.vault_drop <= 0 then
                ty:AddWealth(ty:GetCoinUnitValue(ty:GetHighestUnlockedCoin()) * 45 * 2 * ty:GetPermMult(), false)
                adCds.vault_drop = Config.AD_PLACEMENTS.vault_drop.cooldown
            end
        end

        airdropCd = airdropCd - dt
        if airdropCd <= 0 then
            airdropCd = 75
            local pv = ty:GetAirdropPreview()
            local hiVal = ty:GetCoinUnitValue(ty:GetHighestUnlockedCoin()) * ty:GetPermMult()
            if isAds and adCds.airdrop_5x <= 0 then
                ty:AddWealth(pv.adCash + hiVal * pv.adCoins + hiVal * 45 * pv.adVaults, false)
                ty.skillPoints = ty.skillPoints + pv.adSp
                ty.totalSkillPoints = ty.totalSkillPoints + pv.adSp
                adCds.airdrop_5x = Config.AD_PLACEMENTS.airdrop_5x.cooldown
            else
                ty:AddWealth(pv.freeCash + hiVal * pv.freeCoins, false)
            end
        end

        -- 按实际台面掉落均值 × 机台相对增速 × 手点叠加加成计算本秒物理收益
        local rawScale = (ty:GetAutoRate(true) / 1.59) * (1 + min(0.75, (ty.machineLv.multi_shot or 0) * 0.05))
        local relRate = min(2.2, 0.35 + 0.65 * (rawScale / 1.30))
        local manGain = 1.0 + manualFrac * (min(1.25, 1.10 + 0.008 * ty:CountUnlockedCoins()) - 1.0)
        local effDropRate = diagRef.dropsPerSec * relRate * manGain
        local avgCoin = ty:GetAvgUnlockedCoinValue()
        local perm = ty:GetPermMult()
        local fevMul = 1.0 + fevUptime * (2.2 * 1.45 - 1.0)
        local adMul = (boostLeft > 0) and 3.0 or 1.0
        local bankMul = ty:HasTech("bankbook") and 1.08 or 1.0
        -- 暴击均值期望
        local critChance = min(0.75, 0.10 + (ty.machineLv.crit_power or 0) * 0.015)
        local critMult = 2.0 + (ty.machineLv.crit_power or 0) * 0.18 + (ty.prestigeLv.tycoon_crit or 0) * 0.8
        local avgCrit = 1.0 + critChance * (critMult - 1.0)
        -- 除正面掉落外来自撞钉/过门/波次的正常比例（按实测 frontShare 缩放）
        local jpMul = (1.0 - JP_TAX) * (1.0 + JP_INCOME_RATIO * (isAds and 2.0 or 1.0))
        local totalSecRev = (effDropRate * avgCoin * perm * luckAvg * fevMul * adMul * avgCrit * bankMul * jpMul) / max(0.60, diagRef.frontShare)
        ty:AddWealth(totalSecRev * dt, false)

        if sec % actInterval == 0 then
            if spendSmartSP(ty, isAds) then
                if not world1Min then
                    local gap = minNow - lastBuyMin
                    if gap > maxBuyGapMin then maxBuyGapMin = gap end
                    lastBuyMin = minNow
                end
            end
        end

        local curUnlocked = ty:CountUnlockedCoins()
        if curUnlocked >= 22 and not all22Min then all22Min = minNow end
        if not top1000Min and ty:IsInTop1000() then top1000Min = minNow end
        if not world1Min and ty.rankIdx >= #Config.RANKS then
            world1Min = minNow
            cpsAtWorld1 = totalSecRev
            local endGap = minNow - lastBuyMin
            if endGap > maxBuyGapMin then maxBuyGapMin = endGap end
        end
        unlockedN = curUnlocked
    end

    return {
        top1000Min = top1000Min or 999,
        world1Min = world1Min or 999,
        all22Min = all22Min or 999,
        maxBuyGapMin = maxBuyGapMin,
        cpsAtWorld1 = cpsAtWorld1,
        finalWealth = ty.lifetimeCash,
        unlockedN = unlockedN,
    }
end

print("\n=== [Part B] 10-Hour Macro Economy Simulation (4 modes x 4 seeds) ===")
local macroSummary = {}
for _, mode in ipairs({ "click2s", "idle", "hold", "ads" }) do
    local sTop, sW1, sAll22, sGap, sCps, sFinal, sUnl = 0, 0, 0, 0, 0, 0, 0
    local seeds = { 101, 202, 303, 404 }
    for _, sd in ipairs(seeds) do
        local r = simulateMacro10Hours(mode, sd)
        sTop = sTop + r.top1000Min
        sW1 = sW1 + r.world1Min
        sAll22 = sAll22 + r.all22Min
        sGap = sGap + r.maxBuyGapMin
        sCps = sCps + r.cpsAtWorld1
        sFinal = sFinal + r.finalWealth
        sUnl = sUnl + r.unlockedN
    end
    local n = #seeds
    local m = {
        top1000Min = sTop / n,
        world1Min = sW1 / n,
        all22Min = sAll22 / n,
        maxBuyGapMin = sGap / n,
        cpsAtWorld1 = sCps / n,
        finalWealth = sFinal / n,
        unlockedN = sUnl / n,
    }
    macroSummary[mode] = m
    print(string.format(
        "  mode=%-7s top1000=%.1fm  world#1=%.1fm (%.2fh)  all22=%.1fm  maxGap=%.1fm  cps@W1=%s  end=%s (coins=%.0f)",
        mode, m.top1000Min, m.world1Min, m.world1Min / 60.0, m.all22Min, m.maxBuyGapMin, Number.FormatCash(m.cpsAtWorld1), Number.FormatCash(m.finalWealth), m.unlockedN
    ))
end

-- ----------------------------------------------------------------------------
-- Part C: P0 浮点溢出抗压极限测试（跨越 ¥922京 达 ¥1000京+ 并往返序列化）
-- ----------------------------------------------------------------------------
print("\n=== [Part C] P0 Float Overflow Stress Test (>1e21) ===")
local tOv = Tycoon.New(nil, { seed = 9999 })
tOv:AddWealth(1.23e19, true, 1.0) -- 超过 2^63 (9.22e18)
tOv:AddWealth(1.00e21, true, 1.0) -- ¥1000京 (10垓)
for _ = 1, 600 do
    tOv:ManualShoot()
    tOv:Update(1 / 60)
end
assert(tOv.cash > 1e21 and tOv.cash == tOv.cash and tOv.cash < math.huge, "超过922京后 cash 绝不可负数、NaN或inf: " .. tostring(tOv.cash))
assert(tOv.lifetimeCash >= tOv.cash and tOv.lifetimeCash == tOv.lifetimeCash, "lifetimeCash 不可溢出")
assert(tOv:GetWorldRank() == 1, "超高财富世界排名必须稳定第1名")
local ovFmt = Number.FormatCash(tOv.lifetimeCash)
assert(ovFmt ~= "NaN" and ovFmt:sub(1, 2) ~= "¥-", "超高财富格式化异常: " .. ovFmt)
local snap = tOv:ExportState(os.time())
local tOv2 = Tycoon.New(nil, { seed = 8888 })
assert(tOv2:ImportState(snap) and tOv2.lifetimeCash > 1e21, "超高财富 ExportState/ImportState 必须保持浮点精度")
print(string.format("  PASS! lifetimeCash=%s  rank=%d  bestHit=%s", ovFmt, tOv2:GetWorldRank(), Number.FormatCash(tOv2.bestHit)))

-- 核心数值达标断言
assert(macroSummary.click2s.world1Min >= 300 and macroSummary.click2s.world1Min <= 480,
    string.format("click2s 登顶世界第1必须在 5~8 小时 (300~480m), 当前 %.1fm", macroSummary.click2s.world1Min))
local idleRatio = macroSummary.idle.world1Min / macroSummary.click2s.world1Min
assert(idleRatio >= 1.35 and idleRatio <= 2.30,
    string.format("挂机与点击比值目标 1.4x~2.2x, 当前 %.2fx (idle=%.1fm, click=%.1fm)", idleRatio, macroSummary.idle.world1Min, macroSummary.click2s.world1Min))
assert(macroSummary.click2s.maxBuyGapMin <= 10.0,
    string.format("升级最大断档需 <= 10 分钟, 当前 %.1fm", macroSummary.click2s.maxBuyGapMin))

print("[sim_tycoon] ALL CALIBRATION BENCHMARKS PASS!")
