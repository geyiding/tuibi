-- ============================================================================
-- CodexHud.lua  投币仓 / 协同遗物 / 图鉴禁用 / 20档难度 / 首次轻引导
--   · 全部弹窗一次创建，多页签切换保证外框宽高 0 像素跳动
--   · 同类集合使用 4 列大格 + 显式固定高度底部详情区（0 像素抖动）
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("game/Config")
local Skin = require("game/Skin")
local Widgets = require("game/Widgets")
local Roster = require("game/Roster")

local C, U = Skin.C, Skin.UI
local NeoFrame, NeoButton, NeoIcon = Widgets.NeoFrame, Widgets.NeoButton, Widgets.NeoIcon

local CodexHud = {}
local st = {
    cb = nil,
    modals = {},
    refs = {},
    -- deck state
    deckTab = "coins",
    deckPage = 1,
    deckSelIdx = 1,
    deckDeleteMode = false,
    deckRun = nil,
    deckItems = {},
    synSelFamily = "wealth",
    relicSelId = nil,
    -- codex state
    codexTab = "coins",
    codexPage = 1,
    codexSelIdx = 1,
    codexList = {},
    codexProfile = nil,
    -- diff state
    diffSel = 1,
    diffProfile = nil,
}

local function SetLbl(lbl, t)
    if lbl and lbl.props.text ~= t then lbl:SetText(t) end
end

local function MakeFixedGrid(cols, gap, nodes)
    local rows = {}
    for i = 1, #nodes, cols do
        local rowCells = {}
        for c = 0, cols - 1 do
            local n = nodes[i + c]
            if n then
                rowCells[#rowCells + 1] = n
            else
                rowCells[#rowCells + 1] = UI.Panel { flexGrow = 1, flexBasis = 0, height = 1 }
            end
        end
        rows[#rows + 1] = UI.Row { width = "100%", gap = gap, children = rowCells }
    end
    return UI.Column { width = "100%", gap = gap, children = rows }
end

-- ----------------------------------------------------------------------------
-- 1. 投币仓 & 协同遗物弹窗（固定外框 height = 516，切页签 0 跳动）
-- ----------------------------------------------------------------------------
local DECK_PAGE_SIZE = 12

local function BuildDeckModal(cb)
    local r = st.refs
    r.deckTitle = UI.Label { text = "投币仓", fontSize = 18, fontWeight = "bold", fontColor = U.gold }
    local closeBtn = NeoButton {
        text = "×", variant = "dark", width = 40, minWidth = 40, minHeight = 36, fontSize = 18,
        onClick = function() if cb.OnCloseDeck then cb.OnCloseDeck() end end,
    }
    local header = UI.Row {
        width = "100%", height = 40, alignItems = "center",
        children = { r.deckTitle, UI.Spacer(), closeBtn },
    }

    r.deckTabCoins = NeoButton {
        text = "硬币仓", variant = "cyan", flexGrow = 1, flexShrink = 1, flexBasis = 0, minHeight = 40, fontSize = 14,
        onClick = function() st.deckTab = "coins"; CodexHud.RefreshDeck() end,
    }
    r.deckTabSyn = NeoButton {
        text = "协同/遗物", variant = "dark", flexGrow = 1, flexShrink = 1, flexBasis = 0, minHeight = 40, fontSize = 14,
        onClick = function() st.deckTab = "syn"; CodexHud.RefreshDeck() end,
    }
    local tabRow = UI.Row { width = "100%", gap = 6, children = { r.deckTabCoins, r.deckTabSyn } }

    -- Tab 1: 4×3 硬币格
    r.deckCells = {}
    local cNodes = {}
    for i = 1, DECK_PAGE_SIZE do
        local ic = NeoIcon { kind = "coin", key = "gold", size = 32 }
        local nm = UI.Label { text = "金币", fontSize = 12, fontWeight = "bold", fontColor = U.text, maxLines = 1 }
        local badge = UI.Label { text = "Lv1", fontSize = 12, fontColor = U.gold, maxLines = 1 }
        local cell = NeoFrame(Widgets.PressFx {
            style = "slot", skin = { rarity = "common", selected = false },
            flexGrow = 1, flexShrink = 1, flexBasis = 0, minWidth = 0, height = 84, padding = 3, gap = 0,
            flexDirection = "column", alignItems = "center", justifyContent = "center",
            children = { ic, nm, badge },
            onClick = function()
                st.deckSelIdx = i
                CodexHud.RefreshDeckDetail()
            end,
        })
        r.deckCells[i] = { cell = cell, ic = ic, nm = nm, badge = badge }
        cNodes[i] = cell
    end
    local coinGrid = MakeFixedGrid(4, 4, cNodes)

    r.deckPageLbl = UI.Label { text = "1/1", fontSize = 13, fontColor = U.textDim }
    local pageRow = UI.Row {
        width = "100%", height = 38, alignItems = "center", justifyContent = "center", gap = 12,
        children = {
            NeoButton { text = "上一页", variant = "dark", minHeight = 36, minWidth = 76, fontSize = 13,
                onClick = function() if st.deckPage > 1 then st.deckPage = st.deckPage - 1; CodexHud.RefreshDeck() end end },
            r.deckPageLbl,
            NeoButton { text = "下一页", variant = "dark", minHeight = 36, minWidth = 76, fontSize = 13,
                onClick = function() st.deckPage = st.deckPage + 1; CodexHud.RefreshDeck() end },
        },
    }

    r.deckDetIcon = NeoIcon { kind = "coin", key = "gold", size = 50 }
    r.deckDetName = UI.Label { text = "标准金币", fontSize = 15, fontWeight = "bold", fontColor = U.gold, maxLines = 1 }
    r.deckDetDesc = UI.Label { text = "", fontSize = 12, fontColor = U.textDim, whiteSpace = "normal", width = "100%", maxLines = 3 }
    r.deckActBtn = NeoButton {
        text = "三合一", variant = "primary", minWidth = 88, minHeight = 44, fontSize = 13,
        onClick = function()
            if cb.OnDeckAction then cb.OnDeckAction(st.deckItems[(st.deckPage - 1) * DECK_PAGE_SIZE + st.deckSelIdx]) end
        end,
    }
    local coinDetail = NeoFrame {
        style = "card", width = "100%", height = 96, padding = 8, gap = 8,
        flexDirection = "row", alignItems = "center",
        children = {
            r.deckDetIcon,
            UI.Column { flexGrow = 1, flexBasis = 0, flexShrink = 1, gap = 3, children = { r.deckDetName, r.deckDetDesc } },
            r.deckActBtn,
        },
    }

    r.deckTab1 = UI.Panel {
        width = "100%", flexGrow = 1, flexBasis = 0,
        flexDirection = "column", justifyContent = "space-between",
        children = { coinGrid, pageRow, coinDetail },
    }

    -- Tab 2: 协同 + 遗物
    r.synCells = {}
    local sNodes = {}
    for idx, famId in ipairs(Config.FAMILY_ORDER) do
        local fam = Config.FAMILIES[famId]
        local ic = NeoIcon { kind = "icon", key = fam.icon, size = 24, tint = fam.col }
        local nm = UI.Label { text = fam.name, fontSize = 12, fontWeight = "bold", fontColor = U.text, maxLines = 1 }
        local stLbl = UI.Label { text = "0/2", fontSize = 12, fontColor = U.cyan, maxLines = 1 }
        local cell = NeoFrame(Widgets.PressFx {
            style = "slot", skin = { rarity = "common" },
            flexGrow = 1, flexShrink = 1, flexBasis = 0, minWidth = 0, height = 76, padding = 4, gap = 1,
            flexDirection = "column", alignItems = "center", justifyContent = "center",
            children = { ic, nm, stLbl },
            onClick = function()
                st.synSelFamily = famId
                st.relicSelId = nil
                CodexHud.RefreshSynDetail()
            end,
        })
        r.synCells[famId] = { cell = cell, stLbl = stLbl }
        sNodes[idx] = cell
    end
    local synGrid = MakeFixedGrid(3, 4, sNodes)

    r.ownedRelicCells = {}
    local rNodes = {}
    for i = 1, 8 do
        local ic = NeoIcon { kind = "relic", key = "rail_guard", size = 32 }
        local cell = NeoFrame(Widgets.PressFx {
            style = "slot", skin = { rarity = "rare" },
            flexGrow = 1, flexShrink = 1, flexBasis = 0, minWidth = 0, height = 48, padding = 4,
            flexDirection = "row", alignItems = "center", justifyContent = "center",
            children = { ic },
            onClick = function()
                local run = st.deckRun
                local rid = run and run.roster.relicList[i]
                if rid then st.relicSelId = rid; CodexHud.RefreshSynDetail() end
            end,
        })
        r.ownedRelicCells[i] = { cell = cell, ic = ic }
        rNodes[i] = cell
    end
    local relicGrid = MakeFixedGrid(4, 4, rNodes)

    r.synDetTitle = UI.Label { text = "财富协同", fontSize = 15, fontWeight = "bold", fontColor = U.gold, maxLines = 1 }
    r.synDetDesc = UI.Label { text = "", fontSize = 12, fontColor = U.textDim, whiteSpace = "normal", width = "100%", maxLines = 3 }
    local synDetail = NeoFrame {
        style = "card", width = "100%", height = 96, padding = 10, gap = 4,
        flexDirection = "column", justifyContent = "center",
        children = { r.synDetTitle, r.synDetDesc },
    }

    r.deckTab2 = UI.Panel {
        width = "100%", flexGrow = 1, flexBasis = 0, visible = false,
        flexDirection = "column", justifyContent = "space-between",
        children = { synGrid, relicGrid, synDetail },
    }

    local frame = NeoFrame {
        style = "panel", width = "92%", maxWidth = 390, height = 556, padding = 12, gap = 8,
        flexDirection = "column",
        children = { header, tabRow, r.deckTab1, r.deckTab2 },
    }

    return UI.Panel {
        width = "100%", height = "100%", position = "absolute", top = 0, left = 0,
        backgroundColor = U.overlay, visible = false, pointerEvents = "auto",
        flexDirection = "column", justifyContent = "center", alignItems = "center",
        children = { frame },
    }
end

-- ----------------------------------------------------------------------------
-- 2. 图鉴 & 禁用池弹窗（4 页签切换 0 像素跳动）
-- ----------------------------------------------------------------------------
local CODEX_PAGE_SIZE = 12

local function BuildCodexModal(cb)
    local r = st.refs
    r.codexDisLbl = UI.Label { text = "禁用 0/3", fontSize = 13, fontColor = U.magenta }
    local closeBtn = NeoButton {
        text = "×", variant = "dark", width = 40, minWidth = 40, minHeight = 36, fontSize = 18,
        onClick = function() if cb.OnCloseCodex then cb.OnCloseCodex() end end,
    }
    local header = UI.Row {
        width = "100%", height = 40, alignItems = "center", gap = 8,
        children = {
            UI.Label { text = "狂欢图鉴", fontSize = 18, fontWeight = "bold", fontColor = U.gold },
            r.codexDisLbl,
            UI.Spacer(),
            closeBtn,
        },
    }

    local tabs = { { id = "coins", label = "币种" }, { id = "recipes", label = "进化" }, { id = "relics", label = "遗物" }, { id = "bosses", label = "Boss" } }
    r.codexTabs = {}
    local tabNodes = {}
    for i, t in ipairs(tabs) do
        local b = NeoButton {
            text = t.label, variant = "dark", flexGrow = 1, flexShrink = 1, flexBasis = 0, minWidth = 0, paddingHorizontal = 6, minHeight = 38, fontSize = 13,
            onClick = function()
                st.codexTab = t.id
                st.codexPage = 1
                st.codexSelIdx = 1
                CodexHud.RefreshCodex()
            end,
        }
        r.codexTabs[t.id] = b
        tabNodes[i] = b
    end
    local tabRow = UI.Row { width = "100%", gap = 4, children = tabNodes }

    r.codexCells = {}
    local cNodes = {}
    for i = 1, CODEX_PAGE_SIZE do
        local ic = NeoIcon { kind = "coin", key = "gold", size = 32 }
        local nm = UI.Label { text = "?", fontSize = 12, fontWeight = "bold", fontColor = U.text, maxLines = 1 }
        local tag = UI.Label { text = "", fontSize = 12, fontColor = U.red, maxLines = 1 }
        local cell = NeoFrame(Widgets.PressFx {
            style = "slot", skin = { rarity = "common", selected = false },
            flexGrow = 1, flexShrink = 1, flexBasis = 0, minWidth = 0, height = 84, padding = 3, gap = 0,
            flexDirection = "column", alignItems = "center", justifyContent = "center",
            children = { ic, nm, tag },
            onClick = function()
                st.codexSelIdx = i
                CodexHud.RefreshCodexDetail()
            end,
        })
        r.codexCells[i] = { cell = cell, ic = ic, nm = nm, tag = tag }
        cNodes[i] = cell
    end
    local grid = MakeFixedGrid(4, 4, cNodes)

    r.codexPageLbl = UI.Label { text = "1/1", fontSize = 13, fontColor = U.textDim }
    local pageRow = UI.Row {
        width = "100%", height = 38, alignItems = "center", justifyContent = "center", gap = 12,
        children = {
            NeoButton { text = "上一页", variant = "dark", minHeight = 36, minWidth = 76, fontSize = 13,
                onClick = function() if st.codexPage > 1 then st.codexPage = st.codexPage - 1; CodexHud.RefreshCodex() end end },
            r.codexPageLbl,
            NeoButton { text = "下一页", variant = "dark", minHeight = 36, minWidth = 76, fontSize = 13,
                onClick = function() st.codexPage = st.codexPage + 1; CodexHud.RefreshCodex() end },
        },
    }

    r.codexDetIcon = NeoIcon { kind = "coin", key = "gold", size = 50 }
    r.codexDetTitle = UI.Label { text = "", fontSize = 15, fontWeight = "bold", fontColor = U.gold, maxLines = 1 }
    r.codexDetDesc = UI.Label { text = "", fontSize = 12, fontColor = U.textDim, whiteSpace = "normal", width = "100%", maxLines = 3 }
    r.codexBanBtn = NeoButton {
        text = "禁用", variant = "magenta", minWidth = 74, minHeight = 44, fontSize = 13,
        onClick = function()
            local item = st.codexList[(st.codexPage - 1) * CODEX_PAGE_SIZE + st.codexSelIdx]
            if item and cb.OnToggleDisable then cb.OnToggleDisable(item) end
        end,
    }
    local detail = NeoFrame {
        style = "card", width = "100%", height = 100, padding = 8, gap = 8,
        flexDirection = "row", alignItems = "center",
        children = {
            r.codexDetIcon,
            UI.Column { flexGrow = 1, flexBasis = 0, flexShrink = 1, gap = 3, children = { r.codexDetTitle, r.codexDetDesc } },
            r.codexBanBtn,
        },
    }

    local frame = NeoFrame {
        style = "panel", width = "92%", maxWidth = 390, height = 556, padding = 12, gap = 8,
        flexDirection = "column", justifyContent = "space-between",
        children = { header, tabRow, grid, pageRow, detail },
    }

    return UI.Panel {
        width = "100%", height = "100%", position = "absolute", top = 0, left = 0,
        backgroundColor = U.overlay, visible = false, pointerEvents = "auto",
        flexDirection = "column", justifyContent = "center", alignItems = "center",
        children = { frame },
    }
end

-- ----------------------------------------------------------------------------
-- 3. 20 档难度选择弹窗
-- ----------------------------------------------------------------------------
local function BuildDiffModal(cb)
    local r = st.refs
    r.diffBtns = {}
    local nodes = {}
    for i = 1, 20 do
        local b = NeoButton {
            text = tostring(i), variant = "dark", flexGrow = 1, flexShrink = 1, flexBasis = 0, minWidth = 0, minHeight = 40, fontSize = 14, paddingHorizontal = 4,
            onClick = function()
                st.diffSel = i
                CodexHud.RefreshDiff()
            end,
        }
        r.diffBtns[i] = b
        nodes[i] = b
    end
    local grid = MakeFixedGrid(5, 4, nodes)
    r.diffDesc = UI.Label { text = "", fontSize = 13, fontColor = U.cyan, whiteSpace = "normal", textAlign = "center", width = "100%" }
    local okBtn = NeoButton {
        text = "确认难度", variant = "primary", flexGrow = 1, flexBasis = 0, minHeight = 44,
        onClick = function() if cb.OnSelectDifficulty then cb.OnSelectDifficulty(st.diffSel) end end,
    }
    local cancelBtn = NeoButton {
        text = "取消", variant = "dark", flexGrow = 1, flexBasis = 0, minHeight = 44,
        onClick = function() if cb.OnCloseDifficulty then cb.OnCloseDifficulty() end end,
    }
    local frame = NeoFrame {
        style = "panel", width = "90%", maxWidth = 370, height = 430, padding = 16, gap = 12,
        flexDirection = "column", justifyContent = "space-between", alignItems = "center",
        children = {
            UI.Label { text = "选择超频难度", fontSize = 19, fontWeight = "bold", fontColor = U.gold },
            grid,
            NeoFrame { style = "card", width = "100%", height = 56, padding = 8, flexDirection = "row", alignItems = "center", justifyContent = "center", children = { r.diffDesc } },
            UI.Row { width = "100%", gap = 10, children = { cancelBtn, okBtn } },
        },
    }
    return UI.Panel {
        width = "100%", height = "100%", position = "absolute", top = 0, left = 0,
        backgroundColor = U.overlay, visible = false, pointerEvents = "auto",
        flexDirection = "column", justifyContent = "center", alignItems = "center",
        children = { frame },
    }
end

-- ----------------------------------------------------------------------------
-- 4. 首次机制轻引导弹窗
-- ----------------------------------------------------------------------------
local function BuildIntroModal(cb)
    local r = st.refs
    r.introIcon = NeoIcon { kind = "icon", key = "crown", size = 56, tint = C.gold }
    r.introTitle = UI.Label { text = "新机制", fontSize = 20, fontWeight = "bold", fontColor = U.gold }
    r.introDesc = UI.Label { text = "", fontSize = 14, fontColor = U.textDim, whiteSpace = "normal", textAlign = "center", width = "100%" }
    local okBtn = NeoButton {
        text = "知道了", variant = "primary", width = "52%", minWidth = 148, minHeight = 44, alignSelf = "center",
        onClick = function() if cb.OnCloseIntro then cb.OnCloseIntro() end end,
    }
    local frame = NeoFrame {
        style = "panel", width = "86%", maxWidth = 340, padding = 20, gap = 12,
        flexDirection = "column", alignItems = "center",
        children = { r.introIcon, r.introTitle, r.introDesc, okBtn },
    }
    return UI.Panel {
        width = "100%", height = "100%", position = "absolute", top = 0, left = 0,
        backgroundColor = U.overlay, visible = false, pointerEvents = "auto",
        flexDirection = "column", justifyContent = "center", alignItems = "center",
        children = { frame },
    }
end

-- ----------------------------------------------------------------------------
-- 对外构建与刷新接口
-- ----------------------------------------------------------------------------
function CodexHud.BuildModals(cb)
    st.cb = cb
    st.modals.deck = BuildDeckModal(cb)
    st.modals.codex = BuildCodexModal(cb)
    st.modals.difficulty = BuildDiffModal(cb)
    st.modals.intro = BuildIntroModal(cb)
    return st.modals
end

function CodexHud.OpenDeck(run, deleteMode)
    st.deckRun = run
    st.deckDeleteMode = (deleteMode == true)
    st.deckTab = "coins"
    st.deckPage = 1
    st.deckSelIdx = 1
    SetLbl(st.refs.deckTitle, st.deckDeleteMode and ("删币 (" .. run:GetDeleteCost() .. "券)") or "投币仓")
    CodexHud.RefreshDeck()
end

function CodexHud.RefreshDeck()
    local r = st.refs
    local run = st.deckRun
    if not run then return end
    local isCoins = (st.deckTab == "coins")
    r.deckTab1:SetVisible(isCoins)
    r.deckTab2:SetVisible(not isCoins)
    r.deckTabCoins:SetVariant(isCoins and "cyan" or "dark")
    r.deckTabSyn:SetVariant((not isCoins) and "cyan" or "dark")

    if isCoins then
        st.deckItems = run.roster.coins or {}
        local pages = math.max(1, math.ceil(#st.deckItems / DECK_PAGE_SIZE))
        if st.deckPage > pages then st.deckPage = pages end
        SetLbl(r.deckPageLbl, st.deckPage .. "/" .. pages)
        for i = 1, DECK_PAGE_SIZE do
            local slot = r.deckCells[i]
            local c = st.deckItems[(st.deckPage - 1) * DECK_PAGE_SIZE + i]
            if c then
                local def = Config.COINS[c.kind] or Config.COINS.gold
                slot.cell:SetVisible(true)
                slot.ic:SetIcon("coin", c.kind, c.level)
                SetLbl(slot.nm, def.short or def.name)
                SetLbl(slot.badge, "Lv" .. c.level)
                slot.cell.skin_.rarity = def.rarity
            else
                slot.cell:SetVisible(false)
            end
        end
        CodexHud.RefreshDeckDetail()
    else
        for _, famId in ipairs(Config.FAMILY_ORDER) do
            local s = run.roster.synergies[famId]
            local slot = r.synCells[famId]
            local nextGoal = (s.tier >= 6 and 6) or (s.tier >= 4 and 6) or (s.tier >= 2 and 4) or 2
            SetLbl(slot.stLbl, s.count .. "/" .. nextGoal .. (s.tier > 0 and (" [" .. s.tier .. "]") or ""))
            slot.cell.skin_.rarity = (s.tier >= 6 and "legendary") or (s.tier >= 4 and "epic") or (s.tier >= 2 and "rare") or "common"
        end
        for i = 1, 8 do
            local rid = run.roster.relicList[i]
            local cell = r.ownedRelicCells[i]
            if rid then
                cell.cell:SetVisible(true)
                cell.ic:SetIcon("relic", rid, 1)
            else
                cell.cell:SetVisible(false)
            end
        end
        CodexHud.RefreshSynDetail()
    end
end

function CodexHud.RefreshDeckDetail()
    local r = st.refs
    local run = st.deckRun
    if not run then return end
    local idx = (st.deckPage - 1) * DECK_PAGE_SIZE + st.deckSelIdx
    for i = 1, DECK_PAGE_SIZE do
        r.deckCells[i].cell.skin_.selected = (i == st.deckSelIdx)
    end
    local c = st.deckItems[idx]
    if not c then
        r.deckActBtn:SetDisabled(true)
        return
    end
    local info = Roster.Resolve(c.kind, c.level)
    r.deckDetIcon:SetIcon("coin", c.kind, c.level)
    SetLbl(r.deckDetName, info.name .. " Lv" .. c.level)
    SetLbl(r.deckDetDesc, info.def.desc .. string.format(" (筹码%d)", info.baseChips))

    if st.deckDeleteMode then
        r.deckActBtn:SetText("删 " .. run:GetDeleteCost() .. "券")
        r.deckActBtn:SetVariant("danger")
        r.deckActBtn:SetDisabled(#run.roster.coins <= 4 or run.tickets < run:GetDeleteCost())
    else
        local merges = run.roster:FindMergeGroups()
        local canMerge = false
        for _, m in ipairs(merges) do
            if m.kind == c.kind and m.level == c.level then canMerge = true; break end
        end
        r.deckActBtn:SetText("三合一")
        r.deckActBtn:SetVariant("primary")
        r.deckActBtn:SetDisabled(not canMerge)
    end
end

function CodexHud.RefreshSynDetail()
    local r = st.refs
    if st.relicSelId and Config.RELICS[st.relicSelId] then
        local rd = Config.RELICS[st.relicSelId]
        SetLbl(r.synDetTitle, "遗物 · " .. rd.name)
        SetLbl(r.synDetDesc, rd.desc)
    else
        local fam = Config.FAMILIES[st.synSelFamily] or Config.FAMILIES.wealth
        SetLbl(r.synDetTitle, fam.name .. "家族协同")
        SetLbl(r.synDetDesc, "2:" .. fam.t2 .. " | 4:" .. fam.t4 .. " | 6:" .. fam.t6)
    end
end

function CodexHud.OpenCodex(profileData)
    st.codexProfile = profileData
    st.codexTab = "coins"
    st.codexPage = 1
    st.codexSelIdx = 1
    CodexHud.RefreshCodex()
end

function CodexHud.RefreshCodex()
    local r = st.refs
    local pd = st.codexProfile or {}
    local disN = 0
    for _, v in pairs(pd.disabled or {}) do if v then disN = disN + 1 end end
    SetLbl(r.codexDisLbl, "禁用 " .. disN .. "/3")

    for id, btn in pairs(r.codexTabs) do
        btn:SetVariant(id == st.codexTab and "cyan" or "dark")
    end

    local list = {}
    if st.codexTab == "coins" then
        for _, k in ipairs(Config.COIN_POOL) do list[#list + 1] = k end
        for _, ek in ipairs(Config.EVOLUTION_ORDER) do list[#list + 1] = Config.EVOLUTIONS[ek].result end
    elseif st.codexTab == "recipes" then
        for _, k in ipairs(Config.EVOLUTION_ORDER) do list[#list + 1] = k end
    elseif st.codexTab == "relics" then
        for _, k in ipairs(Config.RELIC_ORDER) do list[#list + 1] = k end
    else
        for k in pairs(Config.BOSSES) do list[#list + 1] = k end
        table.sort(list)
    end
    st.codexList = list

    local pages = math.max(1, math.ceil(#list / CODEX_PAGE_SIZE))
    if st.codexPage > pages then st.codexPage = pages end
    SetLbl(r.codexPageLbl, st.codexPage .. "/" .. pages)

    for i = 1, CODEX_PAGE_SIZE do
        local slot = r.codexCells[i]
        local key = list[(st.codexPage - 1) * CODEX_PAGE_SIZE + i]
        if key then
            slot.cell:SetVisible(true)
            local isDis = pd.disabled and pd.disabled[key] == true
            if st.codexTab == "coins" then
                local def = Config.COINS[key]
                slot.ic:SetIcon("coin", key, 1)
                SetLbl(slot.nm, def.short or def.name)
                slot.cell.skin_.rarity = def.rarity
            elseif st.codexTab == "recipes" then
                local rec = Config.EVOLUTIONS[key]
                slot.ic:SetIcon("coin", rec.result, 2)
                SetLbl(slot.nm, rec.name)
                slot.cell.skin_.rarity = "legendary"
            elseif st.codexTab == "relics" then
                local def = Config.RELICS[key]
                slot.ic:SetIcon("relic", key, 1)
                SetLbl(slot.nm, def.name)
                slot.cell.skin_.rarity = def.rarity
            else
                local def = Config.BOSSES[key]
                slot.ic:SetIcon("icon", def.icon or "crown", 1, C.magenta)
                SetLbl(slot.nm, def.name)
                slot.cell.skin_.rarity = "epic"
            end
            SetLbl(slot.tag, isDis and "已禁用" or "")
        else
            slot.cell:SetVisible(false)
        end
    end
    CodexHud.RefreshCodexDetail()
end

function CodexHud.RefreshCodexDetail()
    local r = st.refs
    local pd = st.codexProfile or {}
    local idx = (st.codexPage - 1) * CODEX_PAGE_SIZE + st.codexSelIdx
    for i = 1, CODEX_PAGE_SIZE do
        r.codexCells[i].cell.skin_.selected = (i == st.codexSelIdx)
    end
    local key = st.codexList[idx]
    if not key then return end
    local canBan = (st.codexTab == "coins" or st.codexTab == "relics")
    r.codexBanBtn:SetVisible(canBan)
    if st.codexTab == "coins" then
        local def = Config.COINS[key]
        r.codexDetIcon:SetIcon("coin", key, 1)
        SetLbl(r.codexDetTitle, def.name)
        SetLbl(r.codexDetDesc, def.desc)
    elseif st.codexTab == "recipes" then
        local rec = Config.EVOLUTIONS[key]
        local p1, p2 = Config.COINS[rec.parts[1]].short, Config.COINS[rec.parts[2]].short
        r.codexDetIcon:SetIcon("coin", rec.result, 2)
        SetLbl(r.codexDetTitle, rec.name .. " (" .. p1 .. "+" .. p2 .. ")")
        SetLbl(r.codexDetDesc, Config.COINS[rec.result].desc)
    elseif st.codexTab == "relics" then
        local def = Config.RELICS[key]
        r.codexDetIcon:SetIcon("relic", key, 1)
        SetLbl(r.codexDetTitle, def.name)
        SetLbl(r.codexDetDesc, def.desc)
    else
        local def = Config.BOSSES[key]
        r.codexDetIcon:SetIcon("icon", def.icon or "crown", 1, C.magenta)
        SetLbl(r.codexDetTitle, def.name)
        SetLbl(r.codexDetDesc, def.desc)
    end
    local isDis = pd.disabled and pd.disabled[key] == true
    r.codexBanBtn:SetText(isDis and "启用" or "禁用")
    r.codexBanBtn:SetVariant(isDis and "green" or "magenta")
end

function CodexHud.OpenDiff(profileData)
    st.diffProfile = profileData
    st.diffSel = profileData.difficulty or 1
    CodexHud.RefreshDiff()
end

function CodexHud.RefreshDiff()
    local r = st.refs
    local maxUnl = (st.diffProfile and st.diffProfile.unlockedDifficulty) or 1
    if st.diffSel > maxUnl then st.diffSel = maxUnl end
    for i = 1, 20 do
        local b = r.diffBtns[i]
        b:SetDisabled(i > maxUnl)
        b:SetVariant(i == st.diffSel and "primary" or "dark")
    end
    local cfg = Config.DIFFICULTY[st.diffSel] or Config.DIFFICULTY[1]
    SetLbl(r.diffDesc, cfg.name .. "：" .. cfg.desc)
end

function CodexHud.OpenIntro(iconKey, title, desc)
    local r = st.refs
    r.introIcon:SetIcon("icon", iconKey or "crown", 1, C.gold)
    SetLbl(r.introTitle, title or "新机制")
    SetLbl(r.introDesc, desc or "")
end

return CodexHud
