-- ============================================================================
-- tests/stress_perf.lua  3600 帧满台高压性能压测（60秒狂欢金币雨+爆破+闪电）
-- ============================================================================

local Run = require("game/Run")

local run = Run.New({}, { seed = 88888 })
run:StartLevel(3, 6, "boss")
for _, cid in ipairs({ "bomb", "thunder", "split", "nuke", "giant", "jackpot7" }) do
    run.roster:AddCoin(cid, 3)
end
run.autoDrop = true

local t0 = os.clock()
for f = 1, 3600 do
    if f % 300 == 1 then
        run.ammoLeft = 20
        run:AddFever(100)
    end
    run:Update(1 / 60)
    local phys = run.physics
    for i = 1, phys.activeCount do
        local c = phys.coins[phys.activeIds[i]]
        if c.x ~= c.x or c.y ~= c.y or c.vx ~= c.vx or c.vy ~= c.vy then
            error("NaN detected at frame " .. f)
        end
    end
end
local elapsedMs = (os.clock() - t0) * 1000
local perFrameMs = elapsedMs / 3600
print(string.format("=== 3600-Frame Stress OK: total=%.1fms perFrame=%.3fms score=%g ===",
    elapsedMs, perFrameMs, run.score))
assert(perFrameMs < 3.0, "每帧纯Lua逻辑耗时过高: " .. perFrameMs)
