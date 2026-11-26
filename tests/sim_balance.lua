-- ============================================================================
-- tests/sim_balance.lua  300 局全三幕多流派平衡模拟与爽感校验
-- ============================================================================

local Config = require("game/Config")
local Number = require("game/Number")
local Run = require("game/Run")

local NUM_RUNS = 30    -- 6 大家族 × 5 局 = 30 局完整模拟
local ARCHETYPES = Config.FAMILY_ORDER

local stats = {
    earlyTotal = 0, earlyWins = 0,
    totalRuns = 0, fullClears = 0,
    act3PeakScore = 0,
    byArch = {},
}
for _, arch in ipairs(ARCHETYPES) do
    stats.byArch[arch] = { runs = 0, clears = 0, avgBestHit = 0 }
end

local function SimPickReward(run, arch)
    local bestIdx, bestVal = 1, -1
    for i, item in ipairs(run.rewards or {}) do
        local def = Config.COINS[item.kind]
        local val = (def.family == arch) and 10 or ((def.rarity == "legendary") and 8 or ((def.rarity == "rare") and 5 or 2))
        if val > bestVal then bestVal = val; bestIdx = i end
    end
    run:PickReward(bestIdx)
end

local function SimShopAndRest(run, arch)
    -- 模拟商店/工坊/事件策略
    if run.state == "shop" then
        for idx = 1, #run.shopItems do
            local it = run.shopItems[idx]
            if not it.sold and run.tickets >= it.price then
                if it.kind == "relic" then
                    run:BuyShopItem(idx)
                elseif it.kind == "coin" and Config.COINS[it.id].family == arch then
                    run:BuyShopItem(idx)
                end
            end
        end
        run:LeaveToMap()
    elseif run.state == "rest" then
        local merges = run.roster:FindMergeGroups()
        if #merges > 0 then run.roster:MergeThree(merges[1].kind, merges[1].level) end
        local evos = run.roster:FindAvailableEvolutions()
        if #evos > 0 then run.roster:Evolve(evos[1].id) end
        if run.hearts < run.maxHearts then run:RestHealAndAmmo() end
        run:LeaveToMap()
    elseif run.state == "event" then
        run:ChooseEvent(run.hearts > 2 and "a" or "b")
        run:LeaveToMap()
    elseif run.state == "chest" then
        run:ClaimChest()
        run:LeaveToMap()
    end
end

for r = 1, NUM_RUNS do
    local arch = ARCHETYPES[((r - 1) % #ARCHETYPES) + 1]
    local run = Run.New({}, { seed = 10000 + r * 37, difficulty = 1 })
    stats.totalRuns = stats.totalRuns + 1
    local as = stats.byArch[arch]
    as.runs = as.runs + 1

    local stepGuard = 0
    run:EnterNode("1_1")
    while run.state ~= "result" and stepGuard < 80 do
        stepGuard = stepGuard + 1
        if run.state == "play" then
            run.autoDrop = true
            local frames = 0
            while run.state == "play" and frames < 3600 do
                frames = frames + 1
                run:Update(1 / 30)
            end
            if run.state == "play" then run:FinishLevel() end
            if run.act == 1 and run.layer <= 3 then
                stats.earlyTotal = stats.earlyTotal + 1
                if run.lastSummary and run.lastSummary.cleared then
                    stats.earlyWins = stats.earlyWins + 1
                end
            end
            if run.act == 3 and run.score > stats.act3PeakScore then
                stats.act3PeakScore = run.score
            end
        elseif run.state == "reward" then
            SimPickReward(run, arch)
            run:LeaveToMap()
        elseif run.state == "map" then
            -- 优先选商店/工坊/普通战斗以测试标准玩家构筑线
            local picked = nil
            for nid, _ in pairs(run.selectedNextIds) do
                local nd = run.route.byId[nid]
                if nd and (nd.type == "shop" or nd.type == "rest" or nd.type == "chest" or nd.type == "battle" or nd.type == "boss") then
                    picked = nid; break
                end
            end
            if not picked then picked = next(run.selectedNextIds) end
            run:EnterNode(picked)
        else
            SimShopAndRest(run, arch)
        end
    end

    if run.won then
        stats.fullClears = stats.fullClears + 1
        as.clears = as.clears + 1
    end
    as.avgBestHit = as.avgBestHit + run.bestHit
    if r % 6 == 0 then
        print(string.format("[Progress %d/%d] clears=%d", r, NUM_RUNS, stats.fullClears))
        io.stdout:flush()
    end
end

local earlyRate = stats.earlyWins / math.max(1, stats.earlyTotal)
local clearRate = stats.fullClears / math.max(1, stats.totalRuns)
print(string.format("=== Balance Sim (%d runs) ===", stats.totalRuns))
print(string.format("Act1 L1-3 Clear Rate: %.1f%% (%d/%d)", earlyRate * 100, stats.earlyWins, stats.earlyTotal))
print(string.format("Full 3-Act Clear Rate: %.1f%% (%d/%d)", clearRate * 100, stats.fullClears, stats.totalRuns))
print(string.format("Act3 Peak Score: %s", Number.FormatNum(stats.act3PeakScore)))
for _, arch in ipairs(ARCHETYPES) do
    local as = stats.byArch[arch]
    print(string.format("  [%s] clear=%.1f%% avgBestHit=%s", arch, (as.clears / as.runs) * 100, Number.FormatNum(as.avgBestHit / as.runs)))
end
