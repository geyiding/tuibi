-- ============================================================================
-- tests/test_core.lua  《推币机的狂欢》增量首富版全系统 Lua 5.4 单元测试
-- ============================================================================

local Number = require("game/Number")
local Billionaires = require("game/Billionaires")
local Config = require("game/Config")
local RedeemCodes = require("game/RedeemCodes")
local MockAd = require("game/MockAd")
local Tycoon = require("game/Tycoon")
local SaveManager = require("game/SaveManager")

local function approxEq(a, b, tol)
    return math.abs(a - b) <= (tol or 1e-6)
end

-- 1. 大数格式化 & 世界排名格式化 & 时钟格式化
assert(Number.FormatNum(0) == "0")
assert(Number.FormatNum(999) == "999")
assert(Number.FormatNum(15000) == "1.5万")
assert(Number.FormatNum(3.5e8) == "3.50亿")
assert(Number.FormatNum(8.2e12) == "8.20万亿")
assert(Number.FormatNum(4.1e16) == "4.10京")
assert(Number.FormatNum(6.7e20) == "6.70垓")
assert(Number.FormatNum(9.3e24) == "9.30秭")
assert(Number.FormatNum(1.23e30):find("e%+?30"), "超高量级应切科学计数")
assert(Number.FormatCash(15000) == "¥1.5万")
assert(Number.FormatWorldRank(6e9) == "60.00亿")
assert(Number.FormatRankBadge(6e9) == "No.60.00亿")
assert(Number.FormatRankBadge(5.8e7) == "No.5800万")
assert(Number.FormatRankBadge(990) == "No.990")
assert(Number.FormatClock(0) == "00:00")
assert(Number.FormatClock(125.99) == "02:06", "小数秒绝不可触发 %d 运行时错误")
assert(Number.FormatClock(125.4) == "02:05")
assert(Number.ScoreTier(1500, 100) == 4)
assert(Number.ScoreTier(5000, 100) == 5)

-- 2. 真实世界排名系统（60亿起点 -> 22匿名档 -> 63位前1000真名榜）& 配置完整性
assert(#Config.RANKS == Billionaires.ANON_COUNT + Billionaires.TOP1000_COUNT, "排行榜总档位应为 22+63=85")
assert(Config.RANKS[1].rank == 5000000000 and Config.RANKS[1].target == 500 and Config.RANKS[1].isRealName == false)
assert(Config.RANKS[#Config.RANKS].rank == 1 and Config.RANKS[#Config.RANKS].name == "马斯克" and Config.RANKS[#Config.RANKS].target >= 5e12)
for idx = 1, #Config.RANKS do
    local rk = Config.RANKS[idx]
    assert(type(rk.name) == "string" and rk.name ~= "")
    assert(type(rk.title) == "string" and rk.title ~= "")
    assert(type(rk.quote) == "string" and rk.quote ~= "")
    assert(rk.spBounty and rk.spBounty > 0)
    assert(rk.avatar and rk.avatar.prop)
    if rk.rank > 1000 then
        assert(rk.isRealName == false and rk.avatar.anonymous == true, "前1000名之外严禁真名: " .. rk.name)
    else
        assert(rk.isRealName == true and rk.avatar.anonymous == false, "前1000名必须真名漫画头像: " .. rk.name)
        assert(rk.target >= 2e10, "前1000名真实身价必须>=200亿RMB: " .. rk.name)
        assert(rk.avatar.head and rk.avatar.outfit)
    end
    if idx > 1 then
        assert(rk.target > Config.RANKS[idx - 1].target, "富豪资产梯度必须严格递增: " .. idx)
        assert(rk.rank < Config.RANKS[idx - 1].rank, "世界排名必须严格递减: " .. idx)
    end
end
-- 实时排名曲线校验
assert(Billionaires.CalcWorldRank(0) == 6000000000)
assert(Billionaires.CalcWorldRank(7200000) == 58000000)
assert(Billionaires.CalcWorldRank(2.2e10) == 1001 and not Billionaires.IsInTop1000(2.2e10))
assert(Billionaires.CalcWorldRank(2.45e10) == 990 and Billionaires.IsInTop1000(2.45e10))
assert(Billionaires.CalcWorldRank(6.041e12) == 1)
assert(Billionaires.CalcWorldRank(1000) < Billionaires.CalcWorldRank(100))
assert(Billionaires.CalcWorldRank(1e9) < Billionaires.CalcWorldRank(1e6))
assert(#Config.MACHINE_UPGRADES == 8, "需有 8 项机台改造")
assert(#Config.COIN_TIERS == 22, "需有 22 枚渐进币种(16+6)")
assert(#Config.TECH_UPGRADES == 12, "需有 12 项里程碑黑科技")
assert(#Config.PRESTIGE_TALENTS == 4, "需有 4 项上市永久天赋")
assert(#Config.IPO_ROUNDS == 12, "需有 12 轮非重置资本融资上市阶梯")
assert(#Config.SLOT_SYMBOLS == 6 and Config.SLOT_PRIZES.jackpot_777.mult == 100, "老虎机符号与100倍头奖配置必须完整")
assert(#Config.AD_WELFARE_ORDER == 4, "福利站应列出 4 项常驻模拟广告")
for _, t in ipairs(Config.COIN_TIERS) do
    local cdef = Config.COINS[t.id]
    assert(cdef ~= nil, "币种配置缺失: " .. t.id)
    assert(cdef.color and cdef.color.base and type(cdef.color.base[1]) == "number"
        and cdef.color.rim and type(cdef.color.rim[1]) == "number",
        "硬币配色盘格式缺失 base/rim RGB: " .. t.id)
    if t.parents then
        assert(#t.parents == 2 and Config.COINS[t.parents[1]] and Config.COINS[t.parents[2]],
            "进化母体配置无效: " .. t.id)
    end
end
for k, cdef in pairs(Config.COINS) do
    assert(cdef.color and cdef.color.base and type(cdef.color.base[1]) == "number", "COINS." .. k .. " 缺少 base RGB")
end

-- 3. 渐进开局 & 无点击自动永动推币产生正现金流 & 无头安全加载 Machine3D / AvatarArt
local Machine3D = require("game/Machine3D")
local AvatarArt = require("game/AvatarArt")
assert(AvatarArt.Draw ~= nil)

local events = { ranks = {}, unlocks = {}, prestiges = 0, ads = {}, slotWins = {}, spGains = 0 }
local listener = {
    OnRankUp = function(_, rk, changed, info)
        events.ranks[#events.ranks + 1] = { id = rk.id, rank = rk.rank, changed = changed, info = info }
    end,
    OnUnlockCoin = function(_, c) events.unlocks[#events.unlocks + 1] = c and c.name or "?" end,
    OnPrestige = function(_, s) events.prestiges = events.prestiges + s end,
    OnAdReward = function(_, lbl) events.ads[#events.ads + 1] = lbl end,
    OnSlotWin = function(_, prize) events.slotWins[#events.slotWins + 1] = prize end,
    OnSkillPointsGain = function(_, sp) events.spGains = events.spGains + (sp or 0) end,
}

local ty = Tycoon.New(listener, { seed = 20261126 })
assert(Machine3D.Init(ty) == false and Machine3D.IsActive() == false, "无头单测下 Machine3D.Init 应安全降级")
assert(ty.rankIdx == 0 and ty:GetWorldRank() == 6000000000 and not ty:IsInTop1000(), "初始应为全球第60亿名且未入前1000")
local initCoins = ty:GetUnlockedCoins()
assert(#initCoins == 1 and initCoins[1] == "gold", "开局只应解锁标准金币 gold")

-- 纯挂机（零点击）运行 45 秒 (2700 帧)，检验自动发射 + 推移 + 世界排名实时上升 + 连击无4128x暴走
for _ = 1, 2700 do
    ty:Update(1 / 60)
end
assert(ty.shotsFired >= 30, "自动发射器应持续出币")
assert(ty.totalDrops > 0, "自动推移必须形成有效前沿掉落")
assert(ty.cash > 0 and ty.lifetimeCash > 0, "纯挂机必有持续现金入账")
assert(ty:GetWorldRank() < 6000000000, "纯挂机赚钱后世界排名必须实打实上升")
assert(ty.combo < 200, "钉阵碰撞不得造成连击异常暴走: " .. tostring(ty.combo))
assert(ty:GetDisplayCPS() > 0, "每秒产出展示值必须 > 0")

-- 手动点击加投
local prevClicks = ty.totalClicks
assert(ty:ManualShoot(), "冷却就绪时手点应发射额外硬币")
assert(ty.totalClicks == prevClicks + 1)

-- 4. 机台 8 大升级与 ×1 / ×10 / MAX 购买模式（纯技能点 SP 购买，绝不扣现金！）
ty.cash = 1e20
ty.lifetimeCash = math.max(ty.lifetimeCash, 1e20)
ty.skillPoints = 20000
local frozenCash = ty.cash

local rateCost1, cnt1 = ty:GetMachineCost("auto_rate", 1)
assert(cnt1 == 1 and rateCost1 > 0)
assert(ty:BuyMachineUpgrade("auto_rate", 1) and ty.machineLv.auto_rate == 1)
assert(ty.cash == frozenCash, "升级机台只能扣技能点，绝不可扣除现金")

local multCost10, cnt10 = ty:GetMachineCost("global_mult", 10)
assert(cnt10 == 10 and multCost10 > 0)
assert(ty:BuyMachineUpgrade("global_mult", 10) and ty.machineLv.global_mult == 10)

local function countMultPegs(phys)
    local c = 0
    for _, p in ipairs(phys.pegs) do
        if p.kind == "mult" then c = c + 1 end
    end
    return c
end
local multBefore = countMultPegs(ty.physics)
assert(ty:BuyMachineUpgrade("peg_gold", 10))
assert(countMultPegs(ty.physics) > multBefore, "黄金碰钉改造需转化更多金色倍增钉")

local beforeSpMax = ty.skillPoints
local costMax, cntMax = ty:GetMachineCost("pusher_turbo", 0)
assert(cntMax > 1 and costMax <= beforeSpMax)
assert(ty:BuyMachineUpgrade("pusher_turbo", 0))
assert(ty.skillPoints == beforeSpMax - costMax)
assert(ty.cash == frozenCash, "MAX 升机台后现金仍绝对不减")

-- 5. 22 币严格循序解锁、星级跃迁与母体 Lv>=3 半价进化折扣
local _, _, splitLocked = ty:GetCoinCost("split")
assert(splitLocked == true and not ty:BuyCoin("split"), "第2枚翡翠币未解锁前，第3枚必须锁住不可跳级买")
assert(ty:BuyCoin("emerald"), "解锁第2枚翡翠币应成功")

for i = 3, 16 do
    assert(ty:BuyCoin(Config.COIN_TIERS[i].id), "循序解锁币种应成功: " .. Config.COIN_TIERS[i].id)
end

local evoId = "midas" -- parents = {"gold", "ruby"}
local evoTier = Config.COIN_TIER_BY_ID[evoId]
local fullEvoCost = ty:GetCoinCost(evoId)
assert(fullEvoCost == evoTier.unlockSp, "母体未达3级前应为原价技能点")
assert(ty:BuyCoin("gold") and ty:BuyCoin("gold"))          -- Lv1 -> Lv3
assert(ty:BuyCoin("ruby") and ty:BuyCoin("ruby"))          -- Lv1 -> Lv3
local halfEvoCost, _, evoLocked = ty:GetCoinCost(evoId)
assert(not evoLocked and halfEvoCost == math.floor(evoTier.unlockSp * 0.5 + 0.5), "双母体>=Lv3 且前置已解应触发进化半价")

-- 解锁全部 22 枚币
for _, t in ipairs(Config.COIN_TIERS) do
    if (ty.coinLv[t.id] or 0) == 0 then
        assert(ty:BuyCoin(t.id), "解锁进化币种应成功: " .. t.id)
    end
end
assert(#ty:GetUnlockedCoins() == 22, "应成功解锁全部 22 枚硬币")
assert(ty:GetHighestUnlockedCoin() == "carnival")
assert(ty.cash == frozenCash, "全币解锁升级过程现金绝不减少")

-- 验证星级跃迁倍率 (Lv1 -> Lv5，亚临界稳定增长)
local v1 = ty:GetCoinUnitValue("gold", 1)
local v5 = ty:GetCoinUnitValue("gold", 5)
assert(v5 > v1 * 1.6 and v5 < v1 * 3.0, "Lv5 应叠加星级跃迁而非指数爆炸")

-- 6. 12 项黑科技（SP研发）与被动利息
for _, tech in ipairs(Config.TECH_UPGRADES) do
    assert(ty:BuyTech(tech.id), "使用技能点研发科技应成功: " .. tech.id)
end
assert(ty.cash == frozenCash, "研发黑科技也只扣技能点")
assert(ty:HasTech("bankbook") and ty:HasTech("rail_guard"))
local cashBeforeInterest = ty.cash
for _ = 1, 180 do ty:Update(1 / 60) end
assert(ty.cash > cashBeforeInterest, "复利金库锁被动利息应周期入账")

-- 7. 技能点门槛双轨发奖 + 世界排名超越弹窗事件 + 旧档迁移
local tStep = Tycoon.New(listener, { seed = 887 })
tStep:AddWealth(600, false)
assert(tStep.spStep >= 2 and tStep.skillPoints >= 6, "财富达标应自动触发多段技能点里程碑发放")
assert(tStep.rankIdx == 1 and tStep:GetRankDef().isRealName == false, "突破500应迈入第1档匿名全球前50亿")
assert(not tStep:IsInTop1000() and tStep:GetWorldRank() <= 5000000000)
local rankEvInfo = events.ranks[#events.ranks].info
assert(rankEvInfo and (rankEvInfo.spBounty or 0) > 0)
local spBeforeAd = tStep.skillPoints
local cashBeforeAd = tStep.cash
local extraSp = tStep:ClaimOvertakeAdBonus(rankEvInfo.spBounty)
assert(extraSp == rankEvInfo.spBounty * 2 and tStep.skillPoints == spBeforeAd + extraSp, "超越看广告应额外发 2 倍技能点")
assert(tStep.cash == cashBeforeAd, "超越广告改发技能点不改变现有现金")

local tTop = Tycoon.New(listener, { seed = 889 })
tTop:AddWealth(2.5e10, false)
assert(tTop:IsInTop1000() and tTop:GetRankDef().isRealName == true and tTop:GetRankDef().name == "奥普拉·温弗瑞")
assert(tTop.stageTheme == 3, "进入世界前1000名应自动切至第3幕顶级金库机台")

local tRank = Tycoon.New(listener, { seed = 888 })
tRank:AddWealth(6.1e12, false)
assert(tRank.rankIdx == #Config.RANKS and tRank:GetWorldRank() == 1, "累计身价达6.04万亿以上应登顶 No.1 马斯克")
assert(tRank:GetRankDef().name == "马斯克")
assert(tRank.stageTheme == 3, "最高首富阶段应切至第 3 幕")
assert(events.ranks[#events.ranks].info and events.ranks[#events.ranks].info.jumped == #Config.RANKS, "一次性跨越应统计全部档位")
local sawThemeSwitch = false
for _, ev in ipairs(events.ranks) do
    if ev.changed then sawThemeSwitch = true end
end
assert(sawThemeSwitch, "晋升跨越幕阶时必须触发场景换幕事件")

-- 历史旧档迁入应按新真实世界门槛重算 rankIdx，并按身价补偿技能点 SP
local tMig = Tycoon.New(nil, { seed = 77 })
assert(tMig:ImportState({ cash = 500, lifetimeCash = 2.5e10, rankIdx = 99 }))
assert(tMig.rankIdx == Billionaires.TOP1000_START_IDX and tMig:GetRankDef().isRealName == true and tMig.stageTheme == 3)
assert(tMig.spStep > 0 and tMig.skillPoints > 50, "旧档迁入应自动折算并补偿历史技能点")

-- 8. 方案 A：非重置资本上市敲钟 & 永久天赋
local tIpo = Tycoon.New(listener, { seed = 901 })
tIpo.skillPoints = 200
assert(tIpo:BuyMachineUpgrade("auto_rate", 1))
assert(tIpo:BuyCoin("emerald"))
assert(tIpo:BuyTech("rail_guard"))
tIpo:AddWealth(4.0e4, false)
assert(not tIpo:CanDoIpo() and tIpo:CalcPendingShares() == 0, "未满首轮5万身价不可敲钟上市")
tIpo:AddWealth(4.6e5, false) -- total = 50万
assert(tIpo:CanDoIpo() and tIpo:CalcPendingShares() == 2)
local preCash = tIpo.cash
local spBeforeIpo = tIpo.skillPoints
local gainedDouble, gainedSp = tIpo:DoCapitalIPO(true)
assert(gainedDouble == 4 and gainedSp == 4 and tIpo.prestigeShares == 4 and tIpo.ipoRound == 1)
assert(tIpo.skillPoints == spBeforeIpo + 4, "敲钟上市应同步获赠融资技能点")
assert(tIpo.cash == preCash and tIpo.machineLv.auto_rate == 1 and tIpo:HasTech("rail_guard") and (tIpo.coinLv.emerald or 0) >= 1,
    "方案A资本上市绝不可清空财富、机台、科技与已解币种")
assert(tIpo:BuyPrestigeTalent("angel_fund"), "应可用传奇股点亮资本红利")
assert(Config.GetSpReward(1, 1) == Config.GetSpReward(1, 0) + 1, "资本红利每级应让每档里程碑额外+1技能点")
assert(tIpo:BuyPrestigeTalent("golden_dna"), "应可用传奇股点亮黄金基因链")
local s2 = tIpo:DoCapitalIPO(true) -- 达50万满足第2轮(40万) Pre-A 轮，再领6股
assert(s2 == 6 and tIpo.ipoRound == 2 and tIpo.prestigeShares == 6)
assert(tIpo:BuyPrestigeTalent("perpetual"), "应可用传奇股点亮永动超马达")
assert(tIpo:BuyPrestigeTalent("tycoon_crit"), "应可用传奇股点亮首富暴击心")

-- 8.5 过门 3 轴抽奖老虎机 + 保底 + 全局倍率生效与自然倒计时归 1
local tSlot = Tycoon.New(listener, { seed = 31415 })
local sawBigMult = false
local baseMult = tSlot:GetTotalMult()
for spin = 1, 7 do
    tSlot:QueueSlotSpin()
    assert(tSlot.slotSpinning == true, "加入奖池队列应立即开转")
    for _ = 1, 90 do
        tSlot:Update(1 / 60)
    end
    if tSlot.luckMult >= 5 then
        sawBigMult = true
    end
end
assert(sawBigMult, "连续7次过门未中三连保底机制应必爆 >=5x 大奖")
assert(tSlot:GetTotalMult() >= baseMult * tSlot.luckMult * 0.99, "老虎机中奖倍率必须实打实乘入总收益倍率")
tSlot.HandleGateWin = function() end -- 暂停过门续期，单独验证倒计时自然归零
tSlot.slotQueue = 0
tSlot.slotSpinning = false
for _ = 1, 1600 do
    tSlot:Update(1 / 60)
end
assert(tSlot.luckTimer == 0 and tSlot.luckMult == 1, "倒计时结束后老虎机倍率应归回 1x")

-- 9. 模拟广告系统（UI绑定流 + 无UI单测直发 + 全部广告位 + 空投 + 离线）
local uiOpened = 0
MockAd.BindUI(function(p) uiOpened = uiOpened + 1 end)
local rewarded = false
assert(MockAd.Show("boost_3x", nil, function() rewarded = true end))
assert(uiOpened == 1 and MockAd.GetPending() ~= nil)
MockAd.CompletePending()
assert(rewarded == true and MockAd.GetPending() == nil, "模拟播放完成点领奖必须精确发放奖励")
assert(MockAd.Show("instant_fever", nil, function() rewarded = false end))
MockAd.CancelPending()
assert(rewarded == true and MockAd.GetPending() == nil, "取消模拟广告绝不可发放奖励")

-- 解绑 UI 直接测试 Tycoon:ApplyAdReward 全广告位与冷却
MockAd.BindUI(nil)
for _, pid in ipairs({ "boost_3x", "instant_fever", "vault_drop", "airdrop_5x" }) do
    assert(MockAd.IsReady(ty, pid))
    assert(ty:ApplyAdReward(pid))
    if (Config.AD_PLACEMENTS[pid].cooldown or 0) > 0 then
        assert(not MockAd.IsReady(ty, pid), pid .. " 领奖后应进入冷却")
    else
        assert(MockAd.IsReady(ty, pid), pid .. " 无冷却广告位应允许叠加")
    end
end
assert(ty.adBoostLeft >= 170 and ty.feverActive)

-- 离线收益 (<30秒不弹窗，>=30秒封顶8小时 + ×2)
ty.lastActiveAt = 1000
local a0, e0 = ty:CalcOfflineEarnings(1020)
assert(a0 == 0 and e0 == 20)
local a1, e1 = ty:CalcOfflineEarnings(1000 + 36000) -- 10小时应按8小时封顶
assert(a1 > 0 and e1 == 36000)
local cBeforeOff = ty.cash
local gOff = ty:ClaimOffline(a1, true)
assert(gOff == math.floor(a1 * 2) and ty.cash >= cBeforeOff + gOff)

-- 兑换码系统（新增量版奖励 + 防重领）
local redeemed = {}
local ok1 = ty:ClaimRedeemCode("rich2026", redeemed)
assert(ok1, "RICH2026 应大小写不敏感成功兑换")
assert(not ty:ClaimRedeemCode("RICH2026", redeemed), "已兑换码不可重领")
assert(ty:ClaimRedeemCode("CARNIVAL2026", redeemed))
assert(ty:ClaimRedeemCode("COIN888", redeemed))

-- 10. 红点汇总 + ExportState / ImportState + SaveManager V2
local tDot = Tycoon.New(nil, { seed = 55 })
tDot.skillPoints = 500
local dots = tDot:GetRedDots()
assert(dots.machine > 0 and dots.coins > 0 and dots.tech > 0, "技能点充裕时底栏红点必须全部点亮")

tIpo.skillPoints = 123
local snap = tIpo:ExportState(999999)
local ty2 = Tycoon.New(nil, { seed = 9 })
assert(ty2:ImportState(snap))
assert(approxEq(ty2.cash, tIpo.cash, 1))
assert(ty2.skillPoints == 123 and ty2.spStep == tIpo.spStep and ty2.ipoRound == tIpo.ipoRound)
assert(ty2.prestigeShares == tIpo.prestigeShares)
assert(ty2.rankIdx == tIpo.rankIdx)
assert(ty2.coinLv.emerald == tIpo.coinLv.emerald)
assert(ty2.lastActiveAt == 999999)

local saveData = SaveManager.DefaultData and SaveManager.DefaultData() or SaveManager.GetData()
assert(saveData.version == 2, "SaveManager 版本号应升级为 2")

print(string.format("[test_core] ALL PASS! prestiges=%d ranks=%d unlocks=%d slotWins=%d spGains=%d ads=%d",
    tIpo.totalPrestiges, #events.ranks, #events.unlocks, #events.slotWins, events.spGains, ty.adWatchCount))
