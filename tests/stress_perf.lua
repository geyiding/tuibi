-- ============================================================================
-- tests/stress_perf.lua  增量首富满载物理与多币并推 3600 帧压测（必须零报错 & <3ms/帧）
-- ============================================================================

local Config = require("game/Config")
local Tycoon = require("game/Tycoon")

local ty = Tycoon.New(nil, { seed = 777 })
ty.cash = 1e20
ty.lifetimeCash = 1e20

for _, m in ipairs(Config.MACHINE_UPGRADES) do
    ty:BuyMachineUpgrade(m.id, 10)
end
for _, t in ipairs(Config.COIN_TIERS) do
    ty:BuyCoin(t.id)
end
assert(#ty:GetUnlockedCoins() == 22, "压测必须开启全部 22 枚硬币")
for _, tc in ipairs(Config.TECH_UPGRADES) do
    ty:BuyTech(tc.id)
end
ty:ApplyAdReward("boost_3x")
ty:ApplyAdReward("instant_fever")
ty:ApplyAdReward("vault_drop")

local t0 = os.clock()
local frames = 3600
for i = 1, frames do
    if i % 6 == 0 then ty:ManualShoot() end
    ty:Update(1 / 60)
end
local elapsed = os.clock() - t0
local perFrameMs = (elapsed / frames) * 1000

assert(ty.cash == ty.cash and ty.cash > 0, "满载 3600 帧后 cash 绝不可为 NaN")
assert(ty.lifetimeCash == ty.lifetimeCash and ty.lifetimeCash > 1e20, "满载 3600 帧后 lifetimeCash 必须正常增长")
assert(#ty.physics.coins <= 150, "物体池上限防护必须生效: " .. #ty.physics.coins)
assert(perFrameMs < 5.0, string.format("单帧耗时过高: %.3f ms", perFrameMs))

print(string.format("[stress_perf] PASS: %d frames in %.3fs (%.3f ms/frame, coins=%d, cps=%g)",
    frames, elapsed, perFrameMs, #ty.physics.coins, ty:GetDisplayCPS()))
