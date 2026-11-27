-- 升级性价比探针：同一存档状态下分别买每个选项（机台 / 币种 / 科技），实机 60Hz 物理跑 N 秒，
-- 比较“收入涨幅 / 花费技能点”。用法：ROI_STAGE=early|mid|late ROI_SEC=300 python3 tests/upgrade_roi.lua
local Config = require("game/Config")
local Tycoon = require("game/Tycoon")
local floor, max = math.floor, math.max

local STAGE = os.getenv("ROI_STAGE") or "mid"
local SEC = tonumber(os.getenv("ROI_SEC") or "") or 300
local SEEDS = { 11, 22, 33, 44, 55, 66 }

-- 三个阶段的典型构筑（技能点按机台/币种/科技大致均衡分配）
local BUILDS = {
    early = { coins = 4, coinLv = 3, mach = { auto_rate = 3, global_mult = 6, multi_shot = 2, crit_power = 2 },
              tech = { "rail_guard", "metronome" } },
    mid   = { coins = 10, coinLv = 6, mach = { auto_rate = 8, global_mult = 30, multi_shot = 6, crit_power = 6, pusher_turbo = 5, gate_master = 5, peg_gold = 4, fever_drive = 5 },
              tech = { "rail_guard", "metronome", "medkit", "big_pouch", "bankbook", "mag_lip" } },
    late  = { coins = 18, coinLv = 10, mach = { auto_rate = 18, global_mult = 90, multi_shot = 12, crit_power = 14, pusher_turbo = 12, gate_master = 12, peg_gold = 9, fever_drive = 12 },
              tech = { "rail_guard", "metronome", "medkit", "big_pouch", "bankbook", "mag_lip", "powder_keg", "tesla_coil", "clover", "recycler" } },
}

local function MakeBase(seed)
    local b = BUILDS[STAGE]
    local ty = Tycoon.New(nil, { seed = seed })
    ty.skillPoints = 1e6
    for i = 2, b.coins do ty:BuyCoin(Config.COIN_TIERS[i].id) end
    for i = 1, b.coins do
        local id = Config.COIN_TIERS[i].id
        while (ty.coinLv[id] or 0) < b.coinLv do ty:BuyCoin(id) end
    end
    for id, lv in pairs(b.mach) do
        while (ty.machineLv[id] or 0) < lv do ty:BuyMachineUpgrade(id, 1) end
    end
    for _, tid in ipairs(b.tech) do ty:BuyTech(tid) end
    ty.skillPoints = 1e6
    return ty
end

-- 候选：返回 { name, cat, apply(ty) -> spentSp }
local function MachineBundle(id, budget)
    return { name = "机台·" .. Config.MACHINE_BY_ID[id].name, cat = "机台", apply = function(ty)
        local spent = 0
        while true do
            local c, cnt = ty:GetMachineCost(id, 1)
            if cnt <= 0 or spent + c > budget then break end
            ty:BuyMachineUpgrade(id, 1); spent = spent + c
        end
        return spent
    end }
end
local function CoinLevelBundle(which, budget)
    return { name = "币种·升级" .. which, cat = "币种", apply = function(ty)
        local list = ty:GetUnlockedCoins()
        local id = (which == "最高币") and list[#list] or list[max(1, #list - 3)]
        local spent = 0
        while true do
            local c, mx = ty:GetCoinCost(id)
            if mx or spent + c > budget then break end
            ty:BuyCoin(id); spent = spent + c
        end
        return spent
    end }
end
local candidates = {}
for _, m in ipairs(Config.MACHINE_UPGRADES) do candidates[#candidates + 1] = MachineBundle(m.id, 12) end
candidates[#candidates + 1] = { name = "币种·解锁下一枚", cat = "币种", apply = function(ty)
    for _, t in ipairs(Config.COIN_TIERS) do
        if (ty.coinLv[t.id] or 0) == 0 then
            local c = ty:GetCoinCost(t.id); ty:BuyCoin(t.id); return c
        end
    end
    return 0
end }
candidates[#candidates + 1] = CoinLevelBundle("最高币", 12)
candidates[#candidates + 1] = CoinLevelBundle("中段币", 12)
for _, t in ipairs(Config.TECH_UPGRADES) do
    candidates[#candidates + 1] = { name = "科技·" .. t.name, cat = "科技", apply = function(ty)
        if ty:HasTech(t.id) then return 0 end
        ty:BuyTech(t.id); return t.costSp
    end }
end

-- 统计口径：剔除幸运三连 / 奇遇（骰子、气球、黄金暴走）这两个纯运气倍率，降低 5 分钟窗口内的随机噪声；
-- 狂欢、连击、暴击等升级会影响的部分照常计入；JP 抽成按到手前金额计（抽成本身最终会返还）
local function Run(ty)
    ty:ResetPhysics(true)
    for _ = 1, 600 do ty:Update(1 / 60) end -- 预热 10 秒
    local sum = 0.0
    local origAdd = ty.AddWealth
    ty.AddWealth = function(self, amt, toCps, tempMul)
        local luck = math.max(1, self.luckMult or 1) * math.max(1, self.surpriseMult or 1)
        if toCps then sum = sum + (tonumber(amt) or 0) / luck end
        return origAdd(self, amt, toCps, tempMul)
    end
    local origFeed = ty.FeedJackpot
    ty.FeedJackpot = function(self, a)
        local luck = math.max(1, self.luckMult or 1) * math.max(1, self.surpriseMult or 1)
        sum = sum + (tonumber(a) or 0) / luck
        return origFeed(self, a)
    end
    for _ = 1, SEC * 60 do ty:Update(1 / 60) end
    return sum
end

local base = 0
for _, sd in ipairs(SEEDS) do base = base + Run(MakeBase(sd)) end
print(string.format("== 阶段 %s  基准收入 %.4g / %ds (×%d 种子)", STAGE, base, SEC, #SEEDS))
local rows = {}
for _, cnd in ipairs(candidates) do
    local tot, spent = 0, 0
    for _, sd in ipairs(SEEDS) do
        local ty = MakeBase(sd)
        spent = cnd.apply(ty)
        tot = tot + Run(ty)
    end
    if spent > 0 then
        local gain = tot / base - 1
        rows[#rows + 1] = { cnd = cnd, spent = spent, gain = gain, eff = math.log(tot / base) / spent }
    end
end
table.sort(rows, function(a, b) return a.eff > b.eff end)
for _, r in ipairs(rows) do
    print(string.format("%-4s %-18s 花%3d点  收入%+7.1f%%  每点%+6.2f%%", r.cnd.cat, r.cnd.name, r.spent, r.gain * 100, (math.exp(r.eff) - 1) * 100))
end
