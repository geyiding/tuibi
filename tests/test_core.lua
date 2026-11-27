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
local Leaderboard = require("game/Leaderboard")

local function approxEq(a, b, tol)
    return math.abs(a - b) <= (tol or 1e-6)
end

-- 1. 大数格式化（精确个位千分位 + 紧凑倍率格式化）& 世界排名格式化 & 时钟格式化
assert(Number.FormatNum(0) == "0")
assert(Number.FormatNum(999) == "999")
assert(Number.FormatNum(15000) == "15,000")
assert(Number.FormatNum(3.5e8) == "350,000,000")
assert(Number.FormatNum(8.2e12) == "8,200,000,000,000")
assert(Number.FormatNum(1234567890123456) == "1,234,567,890,123,456")
assert(Number.FormatNum(9999.5) == "10,000", "小数四舍五入应精确到个位")
assert(Number.FormatNum(99999999) == "99,999,999")
assert(Number.FormatNum(0 / 0) == "NaN")
assert(Number.FormatNum(1 / 0) == "∞")
assert(Number.FormatNum(1.23e22):find("e%+?22"), "超过 1e21 应切科学计数")
assert(Number.FormatCompact(15000) == "1.5万")
assert(Number.FormatCompact(3.5e8) == "3.50亿")
assert(Number.FormatCompact(8.2e12) == "8.20万亿")
assert(Number.FormatCompact(4.1e16) == "4.10京")
assert(Number.FormatCompact(6.7e20) == "6.70垓")
assert(Number.FormatCompact(9.3e24) == "9.30秭")
assert(Number.FormatCompact(9999.5) == "1.0万", "万位进位预舍入")
assert(Number.FormatCompact(99999999) == "1.00亿", "亿位进位预舍入")
assert(Number.FormatCompact(1.23e54):find("e%+?54"), "超高量级紧凑格式应切科学计数")
assert(Number.FormatCash(15000) == "¥15,000")
assert(Number.FormatWorldRank(6e9) == "6,000,000,000")
assert(Number.FormatRankBadge(6e9) == "No.6,000,000,000")
assert(Number.FormatRankBadge(5.8e7) == "No.58,000,000")
assert(Number.FormatRankBadge(990) == "No.990")
assert(Number.FormatClock(0) == "00:00")
assert(Number.FormatClock(125.99) == "02:06", "小数秒绝不可触发 %d 运行时错误")
assert(Number.FormatClock(125.4) == "02:05")
assert(Number.FormatClock(28800) == "8:00:00", "超过1小时应展示 H:MM:SS")
assert(Number.FormatMul(100) == "100")
assert(Number.FormatMul(1.5) == "1.5")
assert(Number.ScoreTier(1500, 100) == 4)
assert(Number.ScoreTier(5000, 100) == 5)

-- 2. 真实世界排名系统（80亿起点 -> 22匿名档 -> 63位前1000真名榜）& 配置完整性
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
assert(Billionaires.CalcWorldRank(0) == 8000000000)
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
assert(#Config.SLOT_SYMBOLS == 7 and Config.SLOT_SYMBOLS[Config.SLOT_JP_SYMBOL].id == "jp" and Config.SLOT_PRIZES.jackpot_777.mult == 100,
    "九宫格幸运盘 6 个连线符号 + JP 宝箱与100倍头奖配置必须完整")
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
assert(ty.rankIdx == 0 and ty:GetWorldRank() == 8000000000 and not ty:IsInTop1000(), "初始应为全球第80亿名且未入前1000")
local initCoins = ty:GetUnlockedCoins()
assert(#initCoins == 1 and initCoins[1] == "gold", "开局只应解锁标准金币 gold")

-- 纯挂机（零点击）运行 45 秒 (2700 帧)，检验自动发射 + 推移 + 世界排名实时上升 + 连击无4128x暴走
for _ = 1, 2700 do
    ty:Update(1 / 60)
end
assert(ty.shotsFired >= 30, "自动发射器应持续出币")
assert(ty.totalDrops > 0, "自动推移必须形成有效前沿掉落")
assert(ty.cash > 0 and ty.lifetimeCash > 0, "纯挂机必有持续现金入账")
assert(ty:GetWorldRank() < 8000000000, "纯挂机赚钱后世界排名必须实打实上升")
assert(ty.combo < 200, "钉阵碰撞不得造成连击异常暴走: " .. tostring(ty.combo))
assert(ty:GetDisplayCPS() > 0, "每秒产出展示值必须 > 0")

-- 手动点击加投
local prevClicks = ty.totalClicks
assert(ty:ManualShoot(), "冷却就绪时手点应发射额外硬币")
assert(ty.totalClicks == prevClicks + 1)

-- 4. 机台 8 大升级与 ×1 / ×10 / MAX 购买模式（纯技能点 SP 购买，绝不扣现金！）
ty.cash = 1e9
ty.lifetimeCash = math.max(ty.lifetimeCash, 1e9)
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
assert(ty:BuyMachineUpgrade("peg_gold", 1) and ty.machineLv.peg_gold == 11, "黄金碰钉上限应为 11 级")
assert(countMultPegs(ty.physics) == 13, "11级改造应将全部 11 颗普通钉转为金钉(含基础2颗=13)")

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

-- 8.5 过门 3 轴幸运三连机 + 9秒限流 + 保底 + 低奖不续命 + 自然到期归 1
local tSlot = Tycoon.New(listener, { seed = 31415 })
local sawLuckBuff = false
assert(tSlot:QueueSlotSpin() == true and tSlot.slotSpinning == true, "首次过门应成功入队并开转")
assert(tSlot:QueueSlotSpin() == false, "9秒限流期内连发过门应拒绝排队防止队列溢出")
for _ = 1, 90 do tSlot:Update(1 / 60) end
if tSlot.luckMult >= 2 then sawLuckBuff = true end
for _ = 1, 8 do
    tSlot.slotCd = 0
    assert(tSlot:QueueSlotSpin() == true)
    for _ = 1, 90 do tSlot:Update(1 / 60) end
    if tSlot.luckMult >= 2 then sawLuckBuff = true end
end
assert(sawLuckBuff, "连续过门在8次保底机制下应触发 >=2x 幸运倍率")
tSlot.luckMult = 100
tSlot.luckTimer = 4.0
tSlot.luckDur = 6.0
local baseMult = tSlot:GetTotalMult() / 100
assert(tSlot:GetTotalMult() >= baseMult * 100 * 0.99, "幸运三连倍率必须乘入总收益倍率")
tSlot:ResolveSlotSpin({ reels = { 1, 1, 2 }, prize = Config.SLOT_PRIZES.pair })
assert(tSlot.luckMult == 100 and approxEq(tSlot.luckTimer, 4.0, 1e-4), "低档奖绝不可替100倍续命延长")
tSlot.HandleGateWin = function() end
tSlot.slotQueue = 0
tSlot.slotSpinning = false
for _ = 1, 600 do
    tSlot:Update(1 / 60)
end
assert(tSlot.luckTimer == 0 and tSlot.luckMult == 1, "倒计时结束后幸运三连倍率应归回 1x")

-- 8.6 九宫格：中奖线显示 reels、其余线绝不意外三连、JP 宝箱不压中奖线
local tGrid = Tycoon.New(nil, { seed = 2718 })
for _ = 1, 3000 do
    local out = tGrid:RollSlotOutcome()
    local g = out.grid
    assert(type(g) == "table" and #g == 9, "九宫格必须 9 格")
    for li, ln in ipairs(Config.SLOT_LINES) do
        local a, b, c = g[ln[1]], g[ln[2]], g[ln[3]]
        if li == out.winLine then
            assert(a == out.reels[1] and b == out.reels[2] and c == out.reels[3], "中奖线必须正好显示 reels")
        elseif li == out.jpLine then
            assert(a == Config.SLOT_JP_SYMBOL and b == a and c == a, "宝箱连线必须是 3 个 JP 宝箱")
        else
            assert(not (a == b and b == c), "非中奖线绝不可意外连成三连")
        end
    end
    local chests = 0
    for i = 1, 9 do if g[i] == Config.SLOT_JP_SYMBOL then chests = chests + 1 end end
    assert(chests == (out.chests or 0) + (out.jpLine and 3 or 0), "宝箱数量必须与点灯数一致")
    assert((out.prize.mult > 1) == (out.winLine ~= nil), "有奖才有中奖线")
end

-- 8.7 JP 大奖池：抽成养分 -> 点灯 -> JP CHANCE 跑灯 -> 倾泻到账 + 币瀑布 -> 弹窗 -> 广告再领一份 -> 存档往返
local jpEv = { lamps = 0, chance = 0, ticks = 0, results = {}, release = nil }
local jpListener = {
    OnJpLamp = function(_, lamps) jpEv.lamps = lamps end,
    OnJpChance = function() jpEv.chance = jpEv.chance + 1 end,
    OnJpTick = function() jpEv.ticks = jpEv.ticks + 1 end,
    OnJpResult = function(_, id) jpEv.results[#jpEv.results + 1] = id end,
    OnJpRelease = function(_, p) jpEv.release = p end,
}
local tJp = Tycoon.New(jpListener, { seed = 4242 })
local cash0 = tJp.cash
local paid = tJp:AwardCash(10000, 180, 400, "gold", false)
assert(approxEq(tJp.jpPool, 10000 * tJp:GetTotalMult() * Config.JACKPOT.FEED_TAX, 2.0), "每笔收入必须按 FEED_TAX 抽成注入奖池")
assert(approxEq(tJp.cash - cash0, paid, 1e-6) and paid < 10000 * tJp:GetTotalMult(), "玩家到手 = 收入扣除抽成")
-- 宝箱点灯
tJp:ResolveSlotSpin({ reels = { 1, 2, 3 }, prize = Config.SLOT_PRIZES.miss, chests = 2 })
assert(tJp.jpLamps == 2 and jpEv.lamps == 2 and not tJp.jpPhase, "2 个宝箱点亮 2 盏灯")
tJp.jpPool = 5e8
tJp.jpRefCps = 1e5
tJp.jpLamps = Config.JACKPOT.LAMPS - 1
tJp:ResolveSlotSpin({ reels = { 1, 2, 3 }, prize = Config.SLOT_PRIZES.miss, chests = 1 })
assert(tJp.jpPhase == "intro" and jpEv.chance == 1, "7 盏灯集满必须进入 JP CHANCE")
assert(tJp:QueueSlotSpin() == true and not tJp.slotSpinning, "JP CHANCE 期间过门只排队，九宫格不开转")
local wealthBefore = tJp.lifetimeCash
local guard = 0
while tJp.jpPhase ~= nil and guard < 60 * 40 do
    tJp:Update(1 / 60)
    guard = guard + 1
end
assert(tJp.jpPhase == nil and jpEv.release, "JP CHANCE 必须在有限时间内倾泻完毕")
local pay = jpEv.release
local tierDef = Config.JACKPOT.TIERS[pay.tier]
assert(tierDef and tierDef.frac and pay.amount >= 5e8 * tierDef.frac * pay.bonus * 0.999, "派奖 = 奖池 × 档位比例 × NEXT 倍数")
assert(jpEv.ticks > 8 and #jpEv.results >= 1 and jpEv.results[#jpEv.results] == pay.tier, "跑灯必须逐格移动并停在派奖档位")
for i = 1, #jpEv.results - 1 do assert(jpEv.results[i] == "next", "非最后一轮只能是 NEXT") end
assert(pay.bonus == #jpEv.results, "每次 NEXT 倍数 +1")
assert(tJp.lifetimeCash - wealthBefore >= pay.amount * 0.999, "JP 奖金必须到账")
assert(tJp.jpLamps == 0 and tJp.jpSince < 1, "倾泻后灯位与天井计时清零")
assert(tJp.jpPool >= tJp:GetJpBase() * Config.JACKPOT.SEED_SEC * 0.999, "奖池派奖后保底重置为种子值")
local popup = tJp:TakeJpPopup()
assert(popup == pay and tJp.jpPendingPopup == nil, "倾泻结束后弹窗结算只取一次")
local w2 = tJp.lifetimeCash
assert(tJp:ClaimJpAdDouble(popup) == pay.amount and approxEq(tJp.lifetimeCash - w2, pay.amount, 1.0), "广告再领一份 = 翻倍")
assert(tJp:ClaimJpAdDouble(popup) == 0, "广告翻倍只能领一次")
-- GRAND 全部带走奖池 + 保底
local tG = Tycoon.New(nil, { seed = 77 })
tG.jpPool = 1e9; tG.jpRefCps = 1e5; tG.jpBonus = 3
local gAmt = tG:JpRelease("grand")
assert(approxEq(gAmt, 3e9, 1.0) and tG.jpPool < 1e9 * 0.01, "GRAND ×3 必须带走整个奖池并乘倍数")
tG.jpPool = 0; tG.jpBonus = 1
assert(tG:JpRelease("mini") >= tG:GetJpBase() * Config.JACKPOT.TIERS.mini.floorSec * 0.999, "奖池太小时按保底派奖")
-- 存档往返
tJp.jpPool = 7.5e9; tJp.jpLamps = 4; tJp.jpRefCps = 3.3e5
local jsnap = tJp:ExportState(os.time())
local tJp2 = Tycoon.New(nil, { seed = 1 })
assert(tJp2:ImportState(jsnap) and approxEq(tJp2.jpPool, 7.5e9, 1) and tJp2.jpLamps == 4 and approxEq(tJp2.jpRefCps, 3.3e5, 1),
    "JP 奖池 / 灯位 / 计价基准必须随存档往返")

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

-- 9.5 ×3印钞机 (boost_3x) 独立冷却周期与冷却完毕二次激活验证
assert(Config.AD_PLACEMENTS.boost_3x.cooldown == 360, "boost_3x 冷却应调整为 360 秒")
local tB = Tycoon.New(nil, { seed = 2031 })
assert(MockAd.IsReady(tB, "boost_3x"), "初始应可直接激活 ×3 印钞")
assert(tB:ApplyAdReward("boost_3x"))
assert(math.abs(tB.adBoostLeft - 180) < 1e-4 and math.abs(tB:GetAdCooldown("boost_3x") - 360) < 1e-4)
assert(not MockAd.IsReady(tB, "boost_3x"), "激活后应立即进入 360 秒冷却")
for _ = 1, 180 * 25 + 5 do tB:Update(0.04) end -- 180.2 秒后效果结束，仍余 ~179.8 秒冷却
assert(tB.adBoostLeft == 0, "180 秒后增益时长归 0: " .. tostring(tB.adBoostLeft))
assert(tB:GetAdCooldown("boost_3x") > 170 and not MockAd.IsReady(tB, "boost_3x"), "效果结束后冷却未归 0 前不可提前触发")
for _ = 1, 181 * 25 do tB:Update(0.04) end -- 再过 181 秒，360 秒冷却完毕
assert(tB:GetAdCooldown("boost_3x") == 0 and MockAd.IsReady(tB, "boost_3x"), "360 秒总冷却到期后必须恢复就绪")
assert(tB:ApplyAdReward("boost_3x") and math.abs(tB.adBoostLeft - 180) < 1e-4, "二次激活 ×3 印钞必须成功")

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

-- 11. 2026-11 重构防崩溃/防膨胀全机制回归验证
-- 11.1 P0 浮点溢出防线：超越 2^63 (9.22e18) 后继续推币不负、不NaN
local tFloat = Tycoon.New(nil, { seed = 2027 })
tFloat:AddWealth(1e20, true, 1.0)
for _ = 1, 120 do tFloat:Update(1 / 60) end
tFloat:AddWealth(5e19, true, 1.0)
assert(tFloat.cash >= 1.49e20 and tFloat.cash == tFloat.cash and tFloat.cash < math.huge, "超过2^63后财富不得回绕成负数或NaN")
local snapF = tFloat:ExportState(os.time())
local tFloat2 = Tycoon.New(nil, { seed = 2028 })
assert(tFloat2:ImportState(snapF) and tFloat2.cash > 1e20)

-- 11.2 狂欢 25 秒冷却 + 结束重归0
local tFev = Tycoon.New(nil, { seed = 2029 })
tFev:TriggerFever(false)
assert(tFev.feverActive and tFev.feverDur >= 8)
for _ = 1, 600 do
    tFev:Update(1 / 60)
    if not tFev.feverActive then break end
end
assert(not tFev.feverActive and tFev.feverCd > 20, "狂欢结束后必须进入25秒冷静冷却")
assert(tFev:AddFever(80) == 0 and tFev.fever == 0, "冷却期内不可充能狂欢")

-- 11.3 撞钉限速(>=80) 与单币上限(<=3次) + 超频量子核未研发不发钱
local tPeg = Tycoon.New(nil, { seed = 2030 })
local dummyCoin = { id = 1, kind = "gold", level = 1, x = 180, y = 120, vx = 0, vy = 20, pegCashHits = 0, bounceCount = 0 }
local dummyPeg = { x = 180, y = 120, kind = "normal" }
local c0 = tPeg.cash
tPeg:HandlePegHit(dummyCoin, dummyPeg, 40)
assert(tPeg.cash == c0 and dummyCoin.pegCashHits == 0, "低于80px/s的擦碰抖动绝不可发撞钉现金")
for _ = 1, 5 do tPeg:HandlePegHit(dummyCoin, dummyPeg, 140) end
assert(dummyCoin.pegCashHits == 3, "每枚币撞钉发钱最多3次上限")
local cBeforeOver = tPeg.cash
tPeg:HandleOverclockCoin(dummyCoin)
assert(tPeg.cash == cBeforeOver, "未研发超频量子核前满台回收不得发钱")
tPeg.techOwned.overclock = true
tPeg:HandleOverclockCoin(dummyCoin)
assert(tPeg.cash > cBeforeOver, "研发超频量子核后应按0.2倍结算回收奖金")

-- 11.4 常驻发射池 (最多6枚) 与序列化往返
local tPin = Tycoon.New(nil, { seed = 2031 })
tPin.skillPoints = 5000
for i = 2, 8 do tPin:BuyCoin(Config.COIN_TIERS[i].id) end
for i = 1, 6 do
    local ok, on = tPin:TogglePinCoin(Config.COIN_TIERS[i].id)
    assert(ok and on, "前6枚币设常驻必须成功")
end
assert(tPin:CountPinnedCoins() == 6)
assert(not tPin:TogglePinCoin(Config.COIN_TIERS[7].id), "常驻发射组合最多选择6枚")
local pinSnap = tPin:ExportState(os.time())
local tPin2 = Tycoon.New(nil, { seed = 2032 })
assert(tPin2:ImportState(pinSnap) and tPin2:CountPinnedCoins() == 6 and tPin2:IsCoinPinned("gold"))

-- 11.5 二周目星际飞升 + 基准CPS离线/风投校验
local tEra = Tycoon.New(nil, { seed = 2033 })
tEra:AddWealth(6.05e12, false)
assert(tEra:CanAscendEra(), "登顶世界第1后应解锁星际飞升")
local shEra, spEra = tEra:DoGalacticAscend()
assert(shEra == 25 and spEra == 40 and tEra.era == 1)
assert(not tEra:CanAscendEra(), "星际飞升第2重需10倍身价门槛")
assert(tEra:GetEraTitle() == Config.GALACTIC_TITLES[1])

-- 11.6 重置游戏进度：SaveManager.ResetAll（清空数据/兑换码并递增 saveSeq，保留音频偏好）& Fx:Reset
local dReset = SaveManager.GetData()
dReset.saveSeq = 7
dReset.records.bestScore = 999999
dReset.redeemedCodes.RICH2026 = true
local prefsReset = SaveManager.GetPrefs()
prefsReset.music = false
local tReset = Tycoon.New(nil, { seed = 2034 })
local resetLocalOk, resetCloudOk = nil, nil
SaveManager.ResetAll(tReset:ExportState(123456), function(locOk, cldOk)
    resetLocalOk, resetCloudOk = locOk, cldOk
end)
assert(resetLocalOk == true and resetCloudOk == false, "离线环境下 ResetAll 应写本地档并回调")
local dAfterReset = SaveManager.GetData()
assert(dAfterReset.saveSeq == 8, "重置存档必须递增 saveSeq 防止云端旧档覆写")
assert(dAfterReset.records.bestScore == 0 and dAfterReset.redeemedCodes.RICH2026 == nil, "重置必须清空最高分与已兑换码")
assert(dAfterReset.tycoon and dAfterReset.tycoon.lastActiveAt == 123456 and dAfterReset.tycoon.cash == 0)
assert(SaveManager.GetPrefs().music == false, "重置进度绝不可清除音量开关偏好")

local FxMod = require("game/Fx")
local fxR = FxMod.New()
fxR.ancCashX, fxR.ancCashY = 180, 32
fxR.ancRankX, fxR.ancRankY = 110, 96
fxR:OnScore(5000, 180, 400, true, 10, "drop", 100)
fxR.liveRankTxt = "第8,000,000,000名"
fxR.modalOpen = true
fxR:Reset()
assert(fxR.liveRankTxt == "" and fxR.modalOpen == false and fxR.activePopCount == 0, "Fx:Reset 必须清空瞬态文字与弹窗态")
assert(fxR.ancCashX == 180 and fxR.ancCashY == 32 and fxR.ancRankX == 110, "Fx:Reset 必须保留组件注入的屏幕锚点")

-- 11.7 超越技能点 ×5 与 广告 ×3 校验
for idx, rk in ipairs(Billionaires.LIST) do
    local b = rk.spBounty or 0
    assert(b >= 10, string.format("Rank %d spBounty 加强5倍后应 >= 10, 实际 %s", idx, tostring(b)))
    if not rk.anonymous then
        assert(idx <= (#Billionaires.LIST - 10) and b >= 10 or b == 25)
    end
end
local tOvt = Tycoon.New(nil, { seed = 2040 })
local sp0 = tOvt.skillPoints
local adAdded = tOvt:ClaimOvertakeAdBonus(10)
assert(adAdded == 20 and tOvt.skillPoints == sp0 + 20, "超越广告 ×3 额外应精确发放 +20 SP")

-- 11.8 风投空投 Option A（动态大额奖励 + 4高阶币免费领 + 22层螺旋金库巨塔/60秒×5/25~60技能点）
local tAir = Tycoon.New(nil, { seed = 2041 })
tAir.skillPoints = 500
tAir:BuyCoin("emerald")
tAir:AddWealth(1e6, false)
local pv1 = tAir:GetAirdropPreview()
assert(pv1.freeCash >= 300 and pv1.freeCoins == 4)
assert(pv1.adCash >= 5000 and pv1.adCoins == 20 and pv1.adVaults == 4 and pv1.adSp >= 25 and pv1.adSp <= 60 and pv1.adBuffDur == 60)
tAir.activeAirdrop = { eventId = "vault_crack" }
local cPreFree = tAir.cash
local cntPreFree = #tAir.physics.activeIds
tAir:ClaimAirdrop(false)
assert(tAir.activeAirdrop == nil and tAir.cash >= cPreFree + pv1.freeCash)
assert(#tAir.physics.activeIds >= cntPreFree + 4, "风投空投免费领取应掉落 4 枚最高解锁币")
tAir.activeAirdrop = { eventId = "vault_crack" }
local cPreAd = tAir.cash
local spPreAd = tAir.skillPoints
tAir:ClaimAirdrop(true)
assert(tAir.activeAirdrop == nil and tAir.cash >= cPreAd + pv1.adCash)
assert(tAir.skillPoints >= spPreAd + pv1.adSp, "风投空投广告必须同步发放 25~60 点动态技能点")
assert(tAir.surpriseMult == 5 and tAir.surpriseTimer >= 59, "风投空投广告必须同步开启 60 秒 ×5 狂飙倍率")
assert(#tAir.physics.towers == 1 and tAir.physics.towers[1].total == 22, "风投空投广告应在台面立起 22 层螺旋摩天金库巨塔")
for _ = 1, 200 do tAir:Update(1 / 60) end
assert(#tAir.physics.towers == 0, "风投螺旋巨塔应在成塔倾倒并爆发 4 波雪崩后清理完毕")

-- 11.9 独立惊喜倍率 surpriseMult（与三连/狂欢/广告直接相乘，含 10×3=30 验证）
local tSurp = Tycoon.New(nil, { seed = 2042 })
tSurp.adBoostLeft = 60
tSurp.luckMult = 5
tSurp.luckTimer = 8
tSurp:ApplySurpriseMult(10, 12, "测试奇遇")
local totalM, det = tSurp:GetTotalMult(true)
assert(det.ad == 3 and det.luck == 5 and det.surprise == 10, "奇遇倍率必须独立于三连与印钞存在")
local expectProd = det.machine * det.tech * det.prestige * det.combo * det.fever * det.ad * det.luck * det.surprise
assert(math.abs(totalM - expectProd) <= 1e-6 * totalM, "总倍率必须等于各独立乘区相乘（10×3=30）")

-- 11.10 拖金袋小人 + 12面骰子（免费8秒；全点数1..12均可看广告翻倍并延至整整60秒）+ 广告60秒超级狂欢
local tDice = Tycoon.New(nil, { seed = 2043 })
tDice:SpawnRunner()
assert(tDice.runner.active == true)
local d0 = tDice:HitRunner(tDice.runner.x)
assert(tDice.runner.active == false and d0 ~= nil and d0.face >= 1 and d0.face <= 12 and d0.mult == d0.face and d0.dur == 8)
assert(tDice.pendingDice == d0)
tDice.pendingDice = { face = 3, mult = 3, dur = 8, rerolled = false }
local d1 = tDice:RollDiceReroll()
assert(d1 and d1.rerolled == true and d1.face >= 7 and d1.face <= 12 and d1.mult == d1.face * 2 and d1.mult >= 14 and d1.mult <= 24 and d1.dur == 60)
assert(tDice:RollDiceReroll() == nil, "同一次掷骰仅限翻倍一次")
local cntBeforeDice = #tDice.physics.activeIds
local dMult, dDur = tDice:ClaimPendingDice()
assert(tDice.pendingDice == nil and dMult == d1.mult and dDur == 60 and tDice.surpriseMult == d1.mult and tDice.surpriseTimer >= 59)
assert(#tDice.physics.activeIds >= cntBeforeDice + 6, "看广告翻倍领取后应加送 6 枚高阶币雨")

-- 验证高点数（如 10 点）同样可看广告直接翻倍至 ×20 并延至 60 秒
tDice.pendingDice = { face = 10, mult = 10, dur = 8, rerolled = false }
local dHi = tDice:RollDiceReroll()
assert(dHi and dHi.face == 10 and dHi.mult == 20 and dHi.dur == 60 and dHi.rerolled == true)
tDice:ClaimPendingDice()

tDice.pendingDice = { face = 1, mult = 1, dur = 8, rerolled = false }
local cntLow = #tDice.physics.activeIds
tDice:ClaimPendingDice()
assert(#tDice.physics.activeIds >= cntLow + 3, "掷出1点未翻倍应保底赠送 3 枚高阶币")

-- 狂欢：免费短时 vs 广告整整 60 秒
tDice:TriggerFever(false)
assert(tDice.feverDur >= 8 and tDice.feverDur <= 12, "免费狂欢应维持短爆发节奏")
tDice:TriggerFever(true)
assert(tDice.feverDur == 60 and tDice.feverTimer == 60 and tDice.feverRainLeft == 40, "广告超级狂欢必须持续整整 60 秒并送 40 枚币雨")

-- 黄金气球：槽内硬币碰撞引爆 + 3类奖池覆盖
local tBal = Tycoon.New(nil, { seed = 2044 })
tBal.balloon.active = true
tBal.balloon.x = 180
tBal.balloon.baseY = 118
tBal.balloon.y = 118
tBal.balloon.speed = 0
tBal.balloon.dir = 1
tBal.balloon.bobT = 0
tBal.physics:SpawnCoin({ kind = "gold", level = 1, x = 180, y = 118, vx = 0, vy = 0, zone = "slot" })
tBal:Update(1 / 60)
assert(tBal.balloon.active == false, "入槽硬币撞击气球范围必须立即打爆气球")
local seenBal = {}
for s = 1, 80 do
    local tb = Tycoon.New(nil, { seed = 3000 + s })
    tb.balloon.active = true
    local k = tb:PopBalloon("tap")
    if k then seenBal[k] = true end
end
assert(seenBal.mult and seenBal.vault and seenBal.sp, "黄金气球必须能开出高倍/45倍金库币/技能点福袋三种大奖")

-- 突发黄金暴走
local tRush = Tycoon.New(nil, { seed = 2045 })
local cntRush = #tRush.physics.activeIds
local rMult, rDur = tRush:TriggerGoldRush()
assert((rMult == 10 or rMult == 12 or rMult == 15 or rMult == 20) and rDur == 10)
assert(tRush.surpriseMult == rMult and #tRush.physics.activeIds >= cntRush + 12, "突发黄金暴走必须生效高倍并掉落12枚币雨")

-- 11.11 奇遇倍率存档保留 + 瞬态弹幕重置
tRush:SpawnRunner()
tRush.balloon.active = true
tRush.pendingDice = { face = 5, mult = 5, dur = 8, rerolled = false }
local rushSnap = tRush:ExportState(os.time())
local tRush2 = Tycoon.New(nil, { seed = 2046 })
assert(tRush2:ImportState(rushSnap))
assert(tRush2.surpriseMult == rMult and tRush2.surpriseTimer > 0 and tRush2.surpriseName == "黄金暴走")
assert(tRush2.pendingDice == nil and not tRush2.runner.active and not tRush2.balloon.active, "读档后瞬态小人/气球/待确认骰子弹窗应安全复位")

-- 11.12 满台 (MAX_COINS=120) 下 24层/22层螺旋摩天金塔：筑塔围栏锁定 -> 成塔前倾雪崩爆发（零吞币）
local twStats = { layers = 0, completes = 0, topples = 0, avCoins = 0, avVaults = 0 }
local twListener = {
    OnTowerLayer = function(_, _, _, _, _, isCrown)
        twStats.layers = twStats.layers + 1
    end,
    OnTowerComplete = function() twStats.completes = twStats.completes + 1 end,
    OnTowerTopple = function() twStats.topples = twStats.topples + 1 end,
}
local tTw = Tycoon.New(twListener, { seed = 2048 })
local origTwSpawn = tTw.physics.SpawnCoin
tTw.physics.SpawnCoin = function(selfPhys, params)
    local res = origTwSpawn(selfPhys, params)
    if params and params.forceSpawn and #selfPhys.towers > 0 and selfPhys.towers[1].phase == "toppling" then
        if res then
            if params.kind == "vault" then twStats.avVaults = twStats.avVaults + 1
            else twStats.avCoins = twStats.avCoins + 1 end
        end
    end
    return res
end
for k = 1, Config.STAGE.MAX_COINS do
    tTw.physics:SpawnCoin({
        kind = "gold", level = 1,
        x = 70 + ((k - 1) % 10) * 22, y = 260 + math.floor((k - 1) / 10) * 20,
        zone = "deck", gateChecked = true,
    })
end
assert(tTw.physics.activeCount == Config.STAGE.MAX_COINS, "台面应先铺满 120 枚硬币")
tTw:ApplyAdReward("vault_drop")
assert(#tTw.physics.towers == 1 and tTw.physics.towers[1].total == 24, "金库巨塔必须开建 24 层螺旋塔")
for f = 1, 30 do
    if f % 10 == 0 then tTw:ManualShoot() end
    tTw:Update(1 / 60)
end
assert(tTw.physics.towers[1] and tTw.physics.towers[1].phase == "building" and tTw.physics.towers[1].built >= 8)
local intrude = 0
local tw0 = tTw.physics.towers[1]
for i = 1, tTw.physics.activeCount do
    local c = tTw.physics.coins[tTw.physics.activeIds[i]]
    if c and c.active and c.zone == "deck" and not c.onPusher then
        local dx, dy = c.x - tw0.x, c.y - tw0.y
        if dx * dx + dy * dy < (tw0.radius + c.r - 2) ^ 2 then intrude = intrude + 1 end
    end
end
assert(intrude == 0, "螺旋金塔建造锁定围栏内绝不允许平铺币闯入推散: intrude=" .. tostring(intrude))
for _ = 1, 180 do tTw:Update(1 / 60) end
assert(#tTw.physics.towers == 0 and twStats.completes == 1 and twStats.topples == 1, "24层摩天巨塔必须完整落成并完成雪崩倾倒")
assert(twStats.avCoins == 24 and twStats.avVaults == 2,
    string.format("满台 24层金库巨塔需零吞币爆发 24高阶币 + 2金库巨币 (got %d + %d)", twStats.avCoins, twStats.avVaults))

twStats.layers, twStats.completes, twStats.topples, twStats.avCoins, twStats.avVaults = 0, 0, 0, 0, 0
tTw:ApplyAdReward("airdrop_5x")
assert(#tTw.physics.towers == 1 and tTw.physics.towers[1].total == 22, "风投暴富必须开建 22 层螺旋金库巨塔")
for _ = 1, 180 do tTw:Update(1 / 60) end
assert(#tTw.physics.towers == 0 and twStats.avCoins == 20 and twStats.avVaults == 4 and twStats.topples == 1,
    string.format("满台风投巨塔需零吞币爆发 20高阶币 + 4金库巨币 (got %d + %d)", twStats.avCoins, twStats.avVaults))

-- 12. 全服双排行榜：万亿/兆/京大数单位、32位排序编码、累计时长/首次登顶、clientCloud + 昵称全链路与离线降级
assert(Number.FormatRankWealth(0) == "0")
assert(Number.FormatRankWealth(9500) == "9,500")
assert(Number.FormatRankWealth(9999.5) == "1.00万", "万位进位预舍入应为 1.00万, got " .. Number.FormatRankWealth(9999.5))
assert(Number.FormatRankWealth(15000) == "1.50万")
assert(Number.FormatRankWealth(3.5e8) == "3.50亿")
assert(Number.FormatRankWealth(8.2e12) == "8.20万亿")
assert(Number.FormatRankWealth(9.9999e15) == "1.00兆", "万亿进位应转为 1.00兆, got " .. Number.FormatRankWealth(9.9999e15))
assert(Number.FormatRankWealth(4.1e16) == "4.10兆", "万亿后必须接 兆, got " .. Number.FormatRankWealth(4.1e16))
assert(Number.FormatRankWealth(9.9999e19) == "1.00京", "兆进位应转为 1.00京, got " .. Number.FormatRankWealth(9.9999e19))
assert(Number.FormatRankWealth(6.7e20) == "6.70京", "兆后必须接 京, got " .. Number.FormatRankWealth(6.7e20))
assert(Number.FormatRankWealth(9.3e24) == "9.30垓", "京后必须接 垓, got " .. Number.FormatRankWealth(9.3e24))
assert(Number.FormatRankWealth(0 / 0) == "NaN")
assert(Number.FormatRankWealth(1 / 0) == "∞")
assert(Number.FormatRankCash(4.1e16) == "¥4.10兆")
assert(Number.FormatRankCash(6.7e20) == "¥6.70京")

local wealthSamples = { 1, 1e4, 1e8, 1e12, 1e16, 1e20, 1e24, 1e35, 1e50 }
local prevEnc = 0
for _, w in ipairs(wealthSamples) do
    local enc = Leaderboard.EncodeWealthScore(w)
    assert(math.type(enc) == "integer" and enc > 0 and enc <= 2147483647, "财富排序分必须为32位正整数: " .. tostring(enc))
    assert(enc > prevEnc, "财富排序分必须严格单调递增: " .. tostring(w))
    prevEnc = enc
end

local prevSp = 2147483647
for _, sec in ipairs({ 60, 600, 3600, 86400 }) do
    local enc = Leaderboard.EncodeSpeedScore(sec)
    assert(math.type(enc) == "integer" and enc > 0 and enc <= 2147483647)
    assert(enc < prevSp, "耗时越短排序分必须越高: " .. tostring(sec))
    assert(Leaderboard.DecodeSpeedScore(enc) == sec, "登顶秒数编解码必须无损往返")
    prevSp = enc
end

local w1Rec = 0
local tSpeed = Tycoon.New({
    OnWorld1Record = function(_, sec) w1Rec = sec end,
}, { seed = 2050 })
for _ = 1, 125 do tSpeed:Update(0.05) end
assert(tSpeed.playSeconds >= 6.0 and tSpeed.world1TimeSec == 0 and w1Rec == 0)
local topTarget = Config.RANKS[#Config.RANKS].target
tSpeed:AddWealth(topTarget + 1000, false)
assert(tSpeed.rankIdx == #Config.RANKS and tSpeed.world1TimeSec == math.floor(tSpeed.playSeconds + 0.5) and w1Rec == tSpeed.world1TimeSec,
    "首次登顶世界第1必须锁定累计游戏耗时并触发 OnWorld1Record")
local lockedRec = tSpeed.world1TimeSec
for _ = 1, 80 do tSpeed:Update(0.05) end
assert(tSpeed.world1TimeSec == lockedRec, "后续继续游玩绝不可改写已锁定的首次登顶记录")
local snapSpeed = tSpeed:ExportState(os.time())
local tSpeed2 = Tycoon.New(nil, { seed = 2051 })
assert(tSpeed2:ImportState(snapSpeed))
assert(approxEq(tSpeed2.playSeconds, snapSpeed.playSeconds, 0.2) and tSpeed2.world1TimeSec == lockedRec,
    "Export/Import 必须完整恢复累计时长与世界第1耗时")

-- 老存档回归防护：旧版本没有 playSeconds/world1TimeSec 但身价已超越马斯克，读档严禁伪造 1 秒登顶成绩
local legacyEvents = 0
local tLegacy = Tycoon.New({ OnWorld1Record = function() legacyEvents = legacyEvents + 1 end }, { seed = 2052 })
assert(tLegacy:ImportState({ lifetimeCash = topTarget * 2, cash = topTarget * 2 }))
assert(tLegacy.rankIdx == #Config.RANKS and tLegacy.world1TimeSec == 0 and legacyEvents == 0,
    "老存档导入已登顶财富时严禁伪造世界第1用时")

-- Mock clientCloud + GetUserNickname 测试上传、双榜读取（含兆/京附加字段）、个人排名、总人数及离线降级
local prevCC, prevNick = _G.clientCloud, _G.GetUserNickname
Leaderboard.ResetSession()
_G.clientCloud = nil
local offBoard = Leaderboard.Fetch("speed", tSpeed2, true)
assert(offBoard.status == "offline" and #offBoard.items == 0, "未登录云端时必须安全降级为 offline 状态")

local mockCloudStore = {
    [1001] = {
        iscore = {
            [Leaderboard.KEY_SPEED] = Leaderboard.EncodeSpeedScore(725),
            [Leaderboard.KEY_WEALTH_RANK] = Leaderboard.EncodeWealthScore(3.5e20),
        },
        score = {
            [Leaderboard.KEY_SPEED_EXACT] = 725,
            [Leaderboard.KEY_WEALTH_EXACT] = 3.5e20,
        },
    },
    [2002] = {
        iscore = {
            [Leaderboard.KEY_WEALTH_RANK] = Leaderboard.EncodeWealthScore(4.2e16),
        },
        score = {
            [Leaderboard.KEY_WEALTH_EXACT] = 4.2e16,
        },
    },
}
_G.clientCloud = {
    userId = 3003,
    BatchSet = function(_)
        local pending = { iscore = {}, score = {} }
        local b = {}
        function b:SetInt(k, v) pending.iscore[k] = math.floor(v); return self end
        function b:Set(k, v) pending.score[k] = v; return self end
        function b:Save(_, ev)
            mockCloudStore[3003] = mockCloudStore[3003] or { iscore = {}, score = {} }
            for k, v in pairs(pending.iscore) do mockCloudStore[3003].iscore[k] = v end
            for k, v in pairs(pending.score) do mockCloudStore[3003].score[k] = v end
            if ev and ev.ok then ev.ok() end
        end
        return b
    end,
    GetRankList = function(_, key, start, count, ev)
        local rows = {}
        for uid, data in pairs(mockCloudStore) do
            if data.iscore[key] then
                rows[#rows + 1] = { userId = uid, iscore = data.iscore, score = data.score }
            end
        end
        table.sort(rows, function(a, b) return a.iscore[key] > b.iscore[key] end)
        local sliced = {}
        for i = (start or 0) + 1, math.min(#rows, (start or 0) + (count or 20)) do
            sliced[#sliced + 1] = rows[i]
        end
        if ev and ev.ok then ev.ok(sliced) end
    end,
    GetUserRank = function(_, uid, key, ev)
        local rows = {}
        for id, data in pairs(mockCloudStore) do
            if data.iscore[key] then rows[#rows + 1] = { uid = id, val = data.iscore[key] } end
        end
        table.sort(rows, function(a, b) return a.val > b.val end)
        for i, r in ipairs(rows) do
            if r.uid == uid then
                if ev and ev.ok then ev.ok(i, r.val) end
                return
            end
        end
        if ev and ev.ok then ev.ok(nil, 0) end
    end,
    GetRankTotal = function(_, key, ev)
        local n = 0
        for _, data in pairs(mockCloudStore) do if data.iscore[key] then n = n + 1 end end
        if ev and ev.ok then ev.ok(n) end
    end,
}
_G.GetUserNickname = function(req)
    local map = { [1001] = "京级大佬", [2002] = "兆亿新星", [3003] = "我方首富" }
    local out = {}
    for _, uid in ipairs(req.userIds or {}) do
        out[#out + 1] = { userId = uid, nickname = map[uid] or ("玩家" .. tostring(uid)) }
    end
    if req.onSuccess then req.onSuccess(out) end
end

local spUpdates, wlUpdates = 0, 0
local bSpeed = Leaderboard.Fetch("speed", tSpeed2, true, function() spUpdates = spUpdates + 1 end)
assert(bSpeed.status == "ready" and #bSpeed.items == 2 and spUpdates >= 2, "最快登顶榜应回读全服列表与昵称")
assert(bSpeed.items[1].userId == 3003 and bSpeed.items[1].value == lockedRec and bSpeed.items[1].name == "我方首富")
assert(bSpeed.items[2].userId == 1001 and bSpeed.items[2].value == 725 and bSpeed.items[2].name == "京级大佬")
assert(bSpeed.myRank == 1 and bSpeed.total == 2)

local bWealth = Leaderboard.Fetch("wealth", tSpeed2, true, function() wlUpdates = wlUpdates + 1 end)
assert(bWealth.status == "ready" and #bWealth.items == 3 and wlUpdates >= 2, "总财富榜应返回 3 名玩家")
assert(bWealth.items[1].userId == 1001 and Number.FormatRankCash(bWealth.items[1].value) == "¥3.50京")
assert(bWealth.items[2].userId == 2002 and Number.FormatRankCash(bWealth.items[2].value) == "¥4.20兆")
assert(bWealth.items[3].userId == 3003 and bWealth.myRank == 3 and bWealth.total == 3)

Leaderboard.ResetSession()
_G.clientCloud, _G.GetUserNickname = prevCC, prevNick

print(string.format("[test_core] ALL PASS! prestiges=%d ranks=%d unlocks=%d slotWins=%d spGains=%d ads=%d",
    tIpo.totalPrestiges, #events.ranks, #events.unlocks, #events.slotWins, events.spGains, ty.adWatchCount))
