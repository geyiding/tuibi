-- ============================================================================
-- Route.lua  三幕分岔战役路线图生成器（每幕 6 层：战斗/精英/商店/事件/工坊/宝箱/Boss）
-- ============================================================================

local Config = require("game/Config")

local Route = {}

local NODE_META = {
    battle = { name = "战斗",   icon = "play",   col = { 56, 224, 255 } },
    elite  = { name = "精英",   icon = "skull",  col = { 255, 82, 96 } },
    shop   = { name = "商店",   icon = "bag",    col = { 255, 210, 64 } },
    event  = { name = "奇遇",   icon = "star",   col = { 166, 114, 255 } },
    rest   = { name = "工坊",   icon = "gear",   col = { 74, 232, 142 } },
    chest  = { name = "宝箱",   icon = "chest",  col = { 255, 198, 56 } },
    boss   = { name = "Boss",   icon = "crown",  col = { 255, 72, 178 } },
}
Route.NODE_META = NODE_META

--- 生成某一幕的 6 层分岔图
function Route.BuildAct(act, rng)
    local actCfg = Config.ACTS[act] or Config.ACTS[1]
    local layers = {}
    -- layer 1: 起点战斗
    layers[1] = {
        { id = "1_1", layer = 1, col = 0.5, type = "battle", next = { "2_1", "2_2" }, visited = false },
    }
    -- layer 2: 普通 vs 精英
    layers[2] = {
        { id = "2_1", layer = 2, col = 0.28, type = "battle", next = { "3_1", "3_2" }, visited = false },
        { id = "2_2", layer = 2, col = 0.72, type = "elite",  next = { "3_1", "3_2" }, visited = false },
    }
    -- layer 3: 商店 vs 奇遇
    local swap3 = rng and (rng() < 0.35)
    layers[3] = {
        { id = "3_1", layer = 3, col = 0.28, type = swap3 and "event" or "shop", next = { "4_1", "4_2" }, visited = false },
        { id = "3_2", layer = 3, col = 0.72, type = swap3 and "shop" or "event", next = { "4_1", "4_2" }, visited = false },
    }
    -- layer 4: 精英 vs 战斗
    layers[4] = {
        { id = "4_1", layer = 4, col = 0.28, type = "elite",  next = { "5_1", "5_2" }, visited = false },
        { id = "4_2", layer = 4, col = 0.72, type = "battle", next = { "5_1", "5_2" }, visited = false },
    }
    -- layer 5: 工坊 vs 宝箱
    local swap5 = rng and (rng() < 0.4)
    layers[5] = {
        { id = "5_1", layer = 5, col = 0.28, type = swap5 and "chest" or "rest", next = { "6_1" }, visited = false },
        { id = "5_2", layer = 5, col = 0.72, type = swap5 and "rest" or "chest", next = { "6_1" }, visited = false },
    }
    -- layer 6: Boss
    local bossDef = Config.BOSSES[actCfg.boss]
    layers[6] = {
        { id = "6_1", layer = 6, col = 0.5, type = "boss", bossId = actCfg.boss,
          title = bossDef and bossDef.name or "Boss", next = {}, visited = false },
    }

    local byId = {}
    for l = 1, 6 do
        for _, n in ipairs(layers[l]) do
            byId[n.id] = n
        end
    end

    return {
        act = act,
        name = actCfg.name,
        layers = layers,
        byId = byId,
        currentId = "1_1",
    }
end

return Route
