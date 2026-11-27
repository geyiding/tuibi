-- JP 数值探针：中盘构筑下实机 60Hz 物理跑 N 分钟，统计 JP CHANCE 频率 / 奖池规模 / JP 占总收入比例
-- 用法：JP_MODE=click2s|idle|hold JP_MIN=45 python3 tests/run_lua.py tests/jp_probe.lua
-- 调 Config.JACKPOT 后用它重测占比，再同步 tests/sim_tycoon.lua 的 JP_INCOME_RATIO
local Config = require("game/Config")
local Tycoon = require("game/Tycoon")
local Number = require("game/Number")
local mode = os.getenv("JP_MODE") or "click2s"
local seed = tonumber(os.getenv("JP_SEED") or "") or 202601
local ty = Tycoon.New(nil, { seed = seed })
ty.cash = 1e6; ty.lifetimeCash = 1e6; ty.skillPoints = 4000
local function buyN(id, n) for _ = 1, n do ty:BuyMachineUpgrade(id, 1) end end
buyN("auto_rate", 6); buyN("multi_shot", 6); buyN("pusher_turbo", 5); buyN("peg_gold", 5); buyN("gate_master", 5); buyN("fever_drive", 5)
for i = 2, 10 do ty:BuyCoin(Config.COIN_TIERS[i].id) end
for _, tid in ipairs({ "rail_guard", "metronome", "medkit", "mag_lip", "clover" }) do ty:BuyTech(tid) end
ty:ResetPhysics(true)
local spins, chances, jpCash, otherCash = 0, 0, 0.0, 0.0
local tiers = {}
local origRes = ty.ResolveSlotSpin
ty.ResolveSlotSpin = function(self, p) spins = spins + 1; return origRes(self, p) end
local origStart = ty.StartJpChance
ty.StartJpChance = function(self, src) if not self.jpPhase then chances = chances + 1 end; return origStart(self, src) end
local inJp = false
local origAdd = ty.AddWealth
ty.AddWealth = function(self, a, c, t)
    local r = origAdd(self, a, c, t)
    if inJp then jpCash = jpCash + r else otherCash = otherCash + r end
    return r
end
local origRel = ty.JpRelease
ty.JpRelease = function(self, id)
    inJp = true
    local poolBefore = self.jpPool
    local amt = origRel(self, id)
    inJp = false
    local base = self:GetJpBase()
    tiers[#tiers + 1] = string.format("%s x%d pool=%.0fs amt=%.0fs t=%.1fm", id, self.jpBonus, poolBefore / base, amt / base, self.clock / 60)
    return amt
end
local minutes = tonumber(os.getenv("JP_MIN") or "") or 30
for f = 1, minutes * 3600 do
    if mode == "hold" then ty:ManualShoot() elseif mode == "click2s" and f % 30 == 0 then ty:ManualShoot() end
    ty:Update(1 / 60)
end
local base = ty:GetJpBase()
print(string.format("mode=%s %dmin spins/min=%.2f chances=%d (every %.1fm) jpShare=%.1f%% pool=%.0fs base=%s",
    mode, minutes, spins / minutes, chances, minutes / math.max(1, chances), 100 * jpCash / math.max(1, jpCash + otherCash), ty.jpPool / base, Number.FormatCash(base)))
for _, l in ipairs(tiers) do print("  " .. l) end
