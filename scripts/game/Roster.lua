-- ============================================================================
-- Roster.lua  投币仓构筑、升级合成、双币进化、家族协同与遗物查询
-- ============================================================================

local Config = require("game/Config")

local Roster = {}
Roster.__index = Roster

local LV_CHIPS_MUL = { 1.0, 1.85, 3.4 }
local LV_MULT_MUL  = { 1.0, 1.55, 2.35 }

function Roster.Resolve(kind, level)
    local base = Config.COINS[kind] or Config.COINS.gold
    local lv = math.max(1, math.min(3, math.floor(level or 1)))
    return {
        id = base.id,
        name = base.name,
        short = base.short,
        rarity = base.rarity,
        family = base.family,
        level = lv,
        baseChips = math.floor((base.baseChips or 40) * LV_CHIPS_MUL[lv]),
        multAdd = (base.multAdd or 0.2) * LV_MULT_MUL[lv],
        feverGain = (base.feverGain or 6) * (1 + (lv - 1) * 0.25),
        def = base,
    }
end

function Roster.New()
    local self = setmetatable({}, Roster)
    self.coins = {}
    self.relics = {}
    self.relicList = {}
    self.nextUid = 1
    self.synergies = {}
    for _, fam in ipairs(Config.FAMILY_ORDER) do
        self.synergies[fam] = { count = 0, tier = 0 }
    end
    self:InitStarter()
    return self
end

function Roster:InitStarter()
    self.coins = {}
    self.relics = {}
    self.relicList = {}
    local starter = {
        "gold", "gold", "gold", "gold",
        "emerald", "emerald",
        "split", "thunder", "bomb", "heavy",
    }
    for i = 1, #starter do
        self:AddCoin(starter[i], 1)
    end
    self:RecomputeSynergies()
end

function Roster:AddCoin(kind, level)
    if not Config.COINS[kind] then kind = "gold" end
    local entry = {
        uid = self.nextUid,
        kind = kind,
        level = level or 1,
    }
    self.nextUid = self.nextUid + 1
    self.coins[#self.coins + 1] = entry
    self:RecomputeSynergies()
    return entry
end

function Roster:RemoveCoinByUid(uid)
    if #self.coins <= 4 then return false end  -- 保底留4枚防空库
    for i = 1, #self.coins do
        if self.coins[i].uid == uid then
            table.remove(self.coins, i)
            self:RecomputeSynergies()
            return true
        end
    end
    return false
end

function Roster:UpgradeCoinByUid(uid)
    for i = 1, #self.coins do
        local c = self.coins[i]
        if c.uid == uid and c.level < 3 then
            c.level = c.level + 1
            return true, c
        end
    end
    return false
end

function Roster:AddRelic(id)
    if not Config.RELICS[id] or self.relics[id] then return false end
    self.relics[id] = true
    self.relicList[#self.relicList + 1] = id
    self:RecomputeSynergies()
    return true
end

function Roster:HasRelic(id)
    return self.relics[id] == true
end

function Roster:RecomputeSynergies()
    local counts = {}
    local seenKinds = {}
    for _, fam in ipairs(Config.FAMILY_ORDER) do
        counts[fam] = 0
    end
    -- 按拥有币种+星级加权计数（同种不同名或升星都能推进家族档位，让单局构筑更容易凑出4/6档）
    for i = 1, #self.coins do
        local c = self.coins[i]
        local def = Config.COINS[c.kind]
        if def and def.family and counts[def.family] ~= nil then
            local weight = c.level >= 2 and 2 or 1
            if not seenKinds[c.kind] then
                seenKinds[c.kind] = true
                counts[def.family] = counts[def.family] + weight
            elseif c.level >= 2 then
                counts[def.family] = counts[def.family] + 1
            end
        end
    end
    local prismBonus = self:HasRelic("prism") and 1 or 0
    for _, fam in ipairs(Config.FAMILY_ORDER) do
        local cnt = counts[fam]
        local eff = cnt + prismBonus
        local tier = 0
        if eff >= 6 then tier = 6
        elseif eff >= 4 then tier = 4
        elseif eff >= 2 then tier = 2 end
        self.synergies[fam].count = cnt
        self.synergies[fam].tier = tier
    end
end

function Roster:GetTier(family)
    local s = self.synergies[family]
    return s and s.tier or 0
end

--- 检查哪些 (kind, level<3) 满3枚可手动三合一
function Roster:FindMergeGroups()
    local groups = {}
    local buckets = {}
    for i = 1, #self.coins do
        local c = self.coins[i]
        if c.level < 3 then
            local key = c.kind .. "#" .. c.level
            local b = buckets[key]
            if not b then
                b = { kind = c.kind, level = c.level, count = 0 }
                buckets[key] = b
            end
            b.count = b.count + 1
        end
    end
    for _, b in pairs(buckets) do
        if b.count >= 3 then
            groups[#groups + 1] = b
        end
    end
    table.sort(groups, function(a, b)
        if a.level ~= b.level then return a.level > b.level end
        return a.kind < b.kind
    end)
    return groups
end

function Roster:MergeThree(kind, level)
    local removed = 0
    for i = #self.coins, 1, -1 do
        local c = self.coins[i]
        if c.kind == kind and c.level == level then
            table.remove(self.coins, i)
            removed = removed + 1
            if removed == 3 then break end
        end
    end
    if removed == 3 then
        local upgraded = self:AddCoin(kind, level + 1)
        return true, upgraded
    end
    return false
end

--- 检查可用进化融合配方（两对应币均拥有至少1枚，且至少一枚 >= Lv2 或 任意两枚）
function Roster:FindAvailableEvolutions()
    local res = {}
    for _, recId in ipairs(Config.EVOLUTION_ORDER) do
        local rec = Config.EVOLUTIONS[recId]
        local hasA, hasB = false, false
        for i = 1, #self.coins do
            if self.coins[i].kind == rec.parts[1] then hasA = true end
            if self.coins[i].kind == rec.parts[2] then hasB = true end
        end
        if hasA and hasB then
            res[#res + 1] = rec
        end
    end
    return res
end

function Roster:Evolve(recipeId)
    local rec = Config.EVOLUTIONS[recipeId]
    if not rec then return false end
    local idxA, idxB = nil, nil
    -- 优先消耗低星材料币
    for i = 1, #self.coins do
        local c = self.coins[i]
        if c.kind == rec.parts[1] and (not idxA or c.level < self.coins[idxA].level) then idxA = i end
    end
    for i = 1, #self.coins do
        local c = self.coins[i]
        if i ~= idxA and c.kind == rec.parts[2] and (not idxB or c.level < self.coins[idxB].level) then idxB = i end
    end
    if not idxA or not idxB then return false end
    if idxA > idxB then
        table.remove(self.coins, idxA)
        table.remove(self.coins, idxB)
    else
        table.remove(self.coins, idxB)
        table.remove(self.coins, idxA)
    end
    local evolved = self:AddCoin(rec.result, 2)
    return true, evolved
end

return Roster
