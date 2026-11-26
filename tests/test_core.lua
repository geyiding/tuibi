-- ============================================================================
-- tests/test_core.lua  Stage 5 全系统单元测试（物理/币种/进化/遗物/战役/存档/兑换码）
-- ============================================================================

local Number = require("game/Number")
local Config = require("game/Config")
local Physics = require("game/Physics")
local Roster = require("game/Roster")
local Route = require("game/Route")
local Run = require("game/Run")
local RedeemCodes = require("game/RedeemCodes")
local SaveManager = require("game/SaveManager")

local function Check(cond, msg)
    if not cond then error("FAIL: " .. tostring(msg), 2) end
end

-- 1. 大数字格式化
Check(Number.FormatNum(950) == "950", "FormatNum < 1万")
Check(Number.FormatNum(12345) == "1.2万", "FormatNum 万")
Check(Number.FormatNum(123456789) == "1.23亿", "FormatNum 亿")
Check(Number.FormatNum(2.5e12) == "2.50兆", "FormatNum 兆")
Check(Number.FormatMul(2.5) == "2.5", "FormatMul")

-- 2. 物理防穿墙、防 NaN、推台前推与跌落
do
    local frontDrops, gateWins = 0, 0
    local phys = Physics.New({
        OnFrontDrop = function() frontDrops = frontDrops + 1 end,
        OnGateWin = function() gateWins = gateWins + 1 end,
    })
    phys:Reset()
    local seed = 42
    local function rng()
        seed = (seed * 1664525 + 1013904223) % 4294967296
        return seed / 4294967296
    end
    phys:SeedDeck(rng)
    Check(phys:CountDeckCoins() >= 60, "开局铺台币充足")
    for f = 1, 600 do
        if f % 20 == 1 and f <= 400 then phys:LaunchFromTop("gold", 1, 0) end
        phys:Step(1 / 60)
        for i = 1, phys.activeCount do
            local c = phys.coins[phys.activeIds[i]]
            Check(c.x == c.x and c.y == c.y and c.vx == c.vx and c.vy == c.vy, "无 NaN")
        end
    end
    Check(frontDrops >= 10, "推板有效把前沿币推落: drops=" .. frontDrops)
end

-- 3. 140 枚满台超频压测 & 卡死保险丝
do
    local overclockCount = 0
    local phys = Physics.New({ OnOverclockCoin = function() overclockCount = overclockCount + 1 end })
    phys:Reset()
    for i = 1, 175 do
        phys:SpawnCoin({ kind = "gold", x = 100 + (i % 8) * 20, y = 290 + (i % 6) * 30, zone = "deck", gateChecked = true })
    end
    Check(phys.activeCount <= Config.STAGE.MAX_COINS, "活跃硬币不超过上限")
    Check(overclockCount >= 30, "溢出触发超频回收")
    local stuck = phys:SpawnCoin({ kind = "heavy", x = 180, y = 90, vx = 0, vy = 0, zone = "slot" })
    for _ = 1, 350 do
        phys:Step(1 / 60)
        if stuck.zone ~= "slot" then break end
    end
    Check(stuck.zone ~= "slot", "重锤币卡死保险丝必须出槽")
end

-- 4. 全部 16 基础币 + 6 进化币 + 20 遗物 逐一在实战触发零报错
do
    local run = Run.New({}, { seed = 999 })
    for _, rid in ipairs(Config.RELIC_ORDER) do
        Check(run.roster:AddRelic(rid), "遗物可添加: " .. rid)
    end
    for _, cid in ipairs(Config.COIN_POOL) do
        run.roster:AddCoin(cid, 2)
    end
    for _, eid in ipairs(Config.EVOLUTION_ORDER) do
        local rec = Config.EVOLUTIONS[eid]
        run.roster:AddCoin(rec.parts[1], 1)
        run.roster:AddCoin(rec.parts[2], 1)
        Check(run.roster:Evolve(eid), "进化配方可合: " .. eid)
    end
    run:StartLevel(3, 6, "boss")
    for _, cid in ipairs(Config.COIN_POOL) do
        local c = run.physics:SpawnCoin({ kind = cid, level = 2, x = 180, y = 538, zone = "deck", gateChecked = true })
        run:HandleFrontDrop(c)
        if cid == "bomb" or cid == "nuke" then run:HandleBombExplode(c) end
        if cid == "blackhole" then run:HandleBlackholeBurst(c) end
    end
    for _, eid in ipairs(Config.EVOLUTION_ORDER) do
        local res = Config.EVOLUTIONS[eid].result
        local c = run.physics:SpawnCoin({ kind = res, level = 3, x = 180, y = 538, zone = "deck", gateChecked = true })
        run:HandleFrontDrop(c)
    end
    Check(run.score > 100000, "全币种与遗物触发后高额爆分: " .. run.score)
end

-- 5. 战役路线图 / 商店 / 工坊 / 事件 / 宝箱 / 断点快照往返
do
    local run = Run.New({}, { seed = 777 })
    Check(run:EnterNode("1_1") == "play", "进入1_1战斗")
    run.score = run.targetScore + 100
    run:FinishLevel()
    Check(run.state == "reward", "过关进三选一")
    run:PickReward(1)
    Check(run:LeaveToMap() == "map", "回路线图解锁第2层")
    Check(run:IsNodeSelectable("2_1") and run:IsNodeSelectable("2_2"), "第2层双分支解锁")

    -- 测试商店/工坊/事件/宝箱
    run.tickets = 200
    run:OpenShop()
    Check(#run.shopItems >= 5, "商店生成货架")
    Check(run:BuyShopItem(1), "购买商品成功")
    Check(run:RefreshShop(), "刷新商店成功")
    run.currentEvent = Config.EVENTS[Config.EVENT_ORDER[1]]
    run.eventOutcome = nil
    Check(run:ChooseEvent("a") ~= nil, "事件选项A执行成功")
    run.chestClaimed = false
    run.chestRelic = "prism"
    Check(run:ClaimChest() and run.roster:HasRelic("prism"), "宝箱获取遗物")

    local snap = run:ExportSnapshot()
    local run2 = Run.New({}, { seed = 777 })
    Check(run2:ImportSnapshot(snap), "存档快照恢复成功")
    Check(run2.tickets == run.tickets and run2.roster:HasRelic("prism"), "恢复后金券与遗物一致")
end

-- 6. 兑换码防重领 & 双端存档防覆盖状态机
do
    local used = {}
    local ok1, _, r1 = RedeemCodes.Claim(" carnival2026 ", used)
    Check(ok1 and r1.tickets == 50, "兑换码忽略大小写与空格")
    local ok2 = RedeemCodes.Claim("CARNIVAL2026", used)
    Check(not ok2, "重复兑换被拒绝")

    -- 模拟换设备无本地档 + 云端超时的防覆盖保护
    SaveManager.SetMockTestHooks({ reset = true })
    _G.clientCloud = {
        userId = 12345,
        BatchGet = function()
            return {
                Key = function(s) return s end,
                Fetch = function(_, ev) ev.timeout() end,
            }
        end,
    }
    local readyCalled, failCalled = false, false
    SaveManager.StartupSync(function() readyCalled = true end, function() failCalled = true end)
    Check(failCalled and not readyCalled, "换设备云读超时触发防覆盖弹窗，绝不静默建新号")
    SaveManager.ConfirmStartFresh()
    Check(readyCalled, "玩家显式确认开始新档后正常放行")
    _G.clientCloud = nil
end

print("=== ALL STAGE 5 UNIT TESTS PASSED ===")
