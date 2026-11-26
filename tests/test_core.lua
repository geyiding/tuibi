-- ============================================================================
-- tests/test_core.lua  《推币机的狂欢》增量首富版全系统 Lua 5.4 单元测试
-- ============================================================================

local Number = require("game/Number")
local Config = require("game/Config")
local RedeemCodes = require("game/RedeemCodes")
local MockAd = require("game/MockAd")
local Tycoon = require("game/Tycoon")
local SaveManager = require("game/SaveManager")

local function approxEq(a, b, tol)
    return math.abs(a - b) <= (tol or 1e-6)
end

-- 1. 大数格式化 & 时钟格式化
assert(Number.FormatNum(0) == "0")
assert(Number.FormatNum(999) == "999")
assert(Number.FormatNum(15000) == "1.5万")
assert(Number.FormatNum(3.5e8) == "3.50亿")
assert(Number.FormatNum(8.2e12) == "8.20兆")
assert(Number.FormatNum(4.1e16) == "4.10京")
assert(Number.FormatNum(6.7e20) == "6.70垓")
assert(Number.FormatNum(9.3e24) == "9.30秭")
assert(Number.FormatNum(1.23e30):find("e%+?30"), "超高量级应切科学计数")
assert(Number.FormatCash(15000) == "¥1.5万")
assert(Number.FormatClock(0) == "00:00")
assert(Number.FormatClock(125.99) == "02:06", "小数秒绝不可触发 %d 运行时错误")
assert(Number.FormatClock(125.4) == "02:05")
assert(Number.ScoreTier(1500, 100) == 4)
assert(Number.ScoreTier(5000, 100) == 5)

-- 2. 配置完整性检查（100 富豪天梯 + 头像特征 + 机台/22币/12科技/4天赋）
assert(#Config.RANKS == 100, "全球富豪榜必须有 100 人")
assert(Config.RANKS[1].rank == 100 and Config.RANKS[1].target == 1500, "第100名起点门槛应为1500")
assert(Config.RANKS[100].rank == 1 and Config.RANKS[100].name == "马斯克", "第1名必须为马斯克")
for idx = 1, #Config.RANKS do
    local rk = Config.RANKS[idx]
    assert(rk.rank == (101 - idx), "rank 编号与 idx 互补")
    assert(type(rk.name) == "string" and rk.name ~= "")
    assert(type(rk.title) == "string" and rk.title ~= "")
    assert(type(rk.quote) == "string" and rk.quote ~= "")
    assert(rk.bounty and rk.bounty > 0)
    assert(rk.avatar and rk.avatar.prop and rk.avatar.head and rk.avatar.outfit)
    if idx > 1 then
        assert(rk.target > Config.RANKS[idx - 1].target, "富豪资产梯度必须严格递增: " .. idx)
    end
end
assert(#Config.MACHINE_UPGRADES == 8, "需有 8 项机台改造")
assert(#Config.COIN_TIERS == 22, "需有 22 枚渐进币种(16+6)")
assert(#Config.TECH_UPGRADES == 12, "需有 12 项里程碑黑科技")
assert(#Config.PRESTIGE_TALENTS == 4, "需有 4 项上市永久天赋")
assert(#Config.AD_WELFARE_ORDER == 4, "福利站应列出 4 项常驻模拟广告")
for _, t in ipairs(Config.COIN_TIERS) do
    assert(Config.COINS[t.id] ~= nil, "币种配置缺失: " .. t.id)
    if t.parents then
        assert(#t.parents == 2 and Config.COINS[t.parents[1]] and Config.COINS[t.parents[2]],
            "进化母体配置无效: " .. t.id)
    end
end

-- 3. 渐进开局 & 无点击自动永动推币产生正现金流 & 无头安全加载 Machine3D / AvatarArt
local Machine3D = require("game/Machine3D")
local AvatarArt = require("game/AvatarArt")
assert(AvatarArt.Draw ~= nil)

local events = { ranks = {}, unlocks = {}, prestiges = 0, ads = {} }
local listener = {
    OnRankUp = function(_, rk, changed, info)
        events.ranks[#events.ranks + 1] = { id = rk.id, rank = rk.rank, changed = changed, info = info }
    end,
    OnUnlockCoin = function(_, c) events.unlocks[#events.unlocks + 1] = c and c.name or "?" end,
    OnPrestige = function(_, s) events.prestiges = events.prestiges + s end,
    OnAdReward = function(_, lbl) events.ads[#events.ads + 1] = lbl end,
}

local ty = Tycoon.New(listener, { seed = 20261126 })
assert(Machine3D.Init(ty) == false and Machine3D.IsActive() == false, "无头单测下 Machine3D.Init 应安全降级")
assert(ty.rankIdx == 0 and ty:GetRankDisplayNo() == 101, "初始尚未上榜应为 No.101")
local initCoins = ty:GetUnlockedCoins()
assert(#initCoins == 1 and initCoins[1] == "gold", "开局只应解锁标准金币 gold")

-- 纯挂机（零点击）运行 45 秒 (2700 帧)，检验自动发射 + 自动推移 + 掉落赚钱
for _ = 1, 2700 do
    ty:Update(1 / 60)
end
assert(ty.shotsFired >= 30, "自动发射器应持续出币")
assert(ty.totalDrops > 0, "自动推移必须形成有效前沿掉落")
assert(ty.cash > 0 and ty.lifetimeCash > 0, "纯挂机必有持续现金入账")
assert(ty:GetDisplayCPS() > 0, "每秒产出展示值必须 > 0")

-- 手动点击加投
local prevClicks = ty.totalClicks
assert(ty:ManualShoot(), "冷却就绪时手点应发射额外硬币")
assert(ty.totalClicks == prevClicks + 1)

-- 4. 机台 8 大升级与 ×1 / ×10 / MAX 购买模式
ty.cash = 1e20
ty.lifetimeCash = math.max(ty.lifetimeCash, 1e20)
local rateCost1, cnt1 = ty:GetMachineCost("auto_rate", 1)
assert(cnt1 == 1 and rateCost1 > 0)
assert(ty:BuyMachineUpgrade("auto_rate", 1) and ty.machineLv.auto_rate == 1)

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

local beforeCashMax = ty.cash
local costMax, cntMax = ty:GetMachineCost("pusher_turbo", 0)
assert(cntMax > 1 and costMax <= beforeCashMax)
assert(ty:BuyMachineUpgrade("pusher_turbo", 0))
assert(ty.cash == beforeCashMax - costMax)

-- 5. 22 币逐级解锁、星级跃迁与母体 Lv>=3 半价进化折扣
local evoId = "midas" -- parents = {"gold", "ruby"}
local evoTier = Config.COIN_TIER_BY_ID[evoId]
local fullEvoCost = ty:GetCoinCost(evoId)
assert(fullEvoCost == evoTier.unlockCost, "母体未达3级前应为原价")
assert(ty:BuyCoin("gold") and ty:BuyCoin("gold"))          -- Lv1 -> Lv3
assert(ty:BuyCoin("ruby") and ty:BuyCoin("ruby") and ty:BuyCoin("ruby")) -- Lv0 -> Lv3
local halfEvoCost = ty:GetCoinCost(evoId)
assert(halfEvoCost == math.floor(evoTier.unlockCost * 0.5 + 0.5), "双母体>=Lv3 应触发进化半价")

-- 解锁全部 22 枚币
for _, t in ipairs(Config.COIN_TIERS) do
    if (ty.coinLv[t.id] or 0) == 0 then
        assert(ty:BuyCoin(t.id), "解锁币种应成功: " .. t.id)
    end
end
assert(#ty:GetUnlockedCoins() == 22, "应成功解锁全部 22 枚硬币")
assert(ty:GetHighestUnlockedCoin() == "carnival")

-- 验证星级跃迁倍率 (Lv1 -> Lv5 -> Lv10)
local v1 = ty:GetCoinUnitValue("gold", 1)
local v5 = ty:GetCoinUnitValue("gold", 5)
assert(v5 > v1 * 10, "Lv5 应叠加 2.5 倍星级质变")

-- 6. 12 项黑科技与被动利息
for _, tech in ipairs(Config.TECH_UPGRADES) do
    assert(ty:BuyTech(tech.id), "购买科技应成功: " .. tech.id)
end
assert(ty:HasTech("bankbook") and ty:HasTech("rail_guard"))
local cashBeforeInterest = ty.cash
for _ = 1, 180 do ty:Update(1 / 60) end
assert(ty.cash > cashBeforeInterest, "复利金库锁被动利息应周期入账")

-- 7. 全球 100 富豪逐级超越弹窗事件、赏金×3广告与 1->2->3 幕自动切换
local tStep = Tycoon.New(listener, { seed = 887 })
tStep.cash = 1600
tStep.lifetimeCash = 1600
tStep:CheckRankUp()
assert(tStep.rankIdx == 1 and tStep:GetRankDisplayNo() == 100, "突破1500应超越第100名")
assert(events.ranks[#events.ranks].info and events.ranks[#events.ranks].info.bounty > 0, "超越富豪应发赏金与通知详情")
local bBeforeAd = tStep.cash
local extraB = tStep:ClaimOvertakeAdBonus(500)
assert(extraB == 1000 and tStep.cash >= bBeforeAd + 1000, "超越赏金看广告应额外发 2 倍（并可连带冲榜）")

local tRank = Tycoon.New(listener, { seed = 888 })
tRank.cash = 2.6e16
tRank.lifetimeCash = 2.6e16
tRank:CheckRankUp()
assert(tRank.rankIdx == 100 and tRank:GetRankDisplayNo() == 1, "累计收益达标应登顶 No.1 马斯克")
assert(tRank.stageTheme == 3, "最高首富阶段应切至第 3 幕")
assert(events.ranks[#events.ranks].info and events.ranks[#events.ranks].info.jumped == 100, "一次性跨越应合并统计连超人数")
local sawThemeSwitch = false
for _, ev in ipairs(events.ranks) do
    if ev.changed then sawThemeSwitch = true end
end
assert(sawThemeSwitch, "晋升跨越幕阶时必须触发场景换幕事件")

-- 8. IPO 上市转生 & 永久天赋
ty.runCash = 2500000
local pending = ty:CalcPendingShares()
assert(pending == 5, "250万本轮营收应获得 5 股传奇股")
local gainedDouble = ty:DoPrestige(true)
assert(gainedDouble == 10 and ty.prestigeShares == 10 and ty.totalPrestiges == 1)
assert(ty.machineLv.auto_rate == 0 and not ty:HasTech("rail_guard"), "转生后机台与科技应重置")
assert(ty:BuyPrestigeTalent("angel_fund"), "应可用传奇股点亮天使启动金")
assert(ty:BuyPrestigeTalent("golden_dna"), "应可用传奇股点亮黄金基因链")
assert(ty:BuyPrestigeTalent("perpetual"), "应可用传奇股点亮永动超马达")
assert(ty:BuyPrestigeTalent("tycoon_crit"), "应可用传奇股点亮首富暴击心")
-- 再次转生检验 angel_fund=1 的开局资金与保留槽位
ty.runCash = 400000
ty.cash = 1000
assert(ty:BuyCoin("emerald"))
ty:DoPrestige(false)
assert(ty.cash == 500, "angel_fund Lv1 第二轮开局应自带 ¥500 启动资金")
assert((ty.coinLv.emerald or 0) >= 1, "angel_fund Lv1 应保留第2种已解锁硬币")

-- 9. 模拟广告系统（UI绑定流 + 无UI单测直发 + 全部 6 广告位 + 空投 + 离线）
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
assert(gOff == math.floor(a1 * 2) and ty.cash == cBeforeOff + gOff)

-- 兑换码系统（新增量版奖励 + 防重领）
local redeemed = {}
local ok1 = ty:ClaimRedeemCode("rich2026", redeemed)
assert(ok1, "RICH2026 应大小写不敏感成功兑换")
assert(not ty:ClaimRedeemCode("RICH2026", redeemed), "已兑换码不可重领")
assert(ty:ClaimRedeemCode("CARNIVAL2026", redeemed))
assert(ty:ClaimRedeemCode("COIN888", redeemed))

-- 10. 红点汇总 + ExportState / ImportState + SaveManager V2
ty.cash = 1e9
local dots = ty:GetRedDots()
assert(dots.machine > 0 and dots.coins > 0 and dots.tech > 0, "资金充裕时底栏红点必须全部点亮")

local snap = ty:ExportState(999999)
local ty2 = Tycoon.New(nil, { seed = 9 })
assert(ty2:ImportState(snap))
assert(approxEq(ty2.cash, ty.cash, 1))
assert(ty2.prestigeShares == ty.prestigeShares)
assert(ty2.rankIdx == ty.rankIdx)
assert(ty2.coinLv.emerald == ty.coinLv.emerald)
assert(ty2.lastActiveAt == 999999)

local saveData = SaveManager.DefaultData and SaveManager.DefaultData() or SaveManager.GetData()
assert(saveData.version == 2, "SaveManager 版本号应升级为 2")

print(string.format("[test_core] ALL PASS! prestiges=%d ranks=%d unlocks=%d ads=%d",
    ty.totalPrestiges, #events.ranks, #events.unlocks, ty.adWatchCount))
