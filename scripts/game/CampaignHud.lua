-- ============================================================================
-- CampaignHud.lua  战役路线图 / 商店 / 整备工坊 / 奇遇事件 / 宝箱
--   · 所有控件一次建树，Open*/Refresh* 只做属性增量更新
--   · 商店采用 3 列大格（只放图标+短名+价格）+ 底部显式固定高度详情区（0 像素抖动）
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("game/Config")
local Skin = require("game/Skin")
local Art = require("game/Art")
local Widgets = require("game/Widgets")
local Route = require("game/Route")
local Roster = require("game/Roster")
local Number = require("game/Number")

local C, U = Skin.C, Skin.UI
local NeoFrame, NeoButton, NeoIcon = Widgets.NeoFrame, Widgets.NeoButton, Widgets.NeoIcon

local CampaignHud = {}
local st = { cb = nil, pages = {}, refs = {}, shopSelected = 1, shopItems = {} }

local function SetLbl(lbl, t)
    if lbl and lbl.props.text ~= t then lbl:SetText(t) end
end

-- ----------------------------------------------------------------------------
-- 1. 路线图页（连线画布 + 11个预创建节点按钮 + 顶/底栏）
-- ----------------------------------------------------------------------------
local MapLines = UI.Widget:Extend("MapLines")
function MapLines:Init(props)
    props = props or {}
    props.pointerEvents = "none"
    self.route_ = nil
    self.nodes_ = nil
    UI.Widget.Init(self, props)
end
function MapLines:SetData(route, nodeBtns)
    self.route_ = route
    self.nodes_ = nodeBtns
end
function MapLines:Render(nvg)
    local rt, btns = self.route_, self.nodes_
    if not rt or not btns then return end
    local l = self:GetAbsoluteLayout()
    for id, node in pairs(rt.byId) do
        local bA = btns[id]
        if bA and bA:IsVisible() then
            local la = bA:GetAbsoluteLayout()
            local ax, ay = la.x + la.w * 0.5, la.y + la.h * 0.5
            for _, nid in ipairs(node.next or {}) do
                local bB = btns[nid]
                if bB and bB:IsVisible() then
                    local lb = bB:GetAbsoluteLayout()
                    local bx, by = lb.x + lb.w * 0.5, lb.y + lb.h * 0.5
                    local active = node.visited
                    nvgBeginPath(nvg)
                    nvgMoveTo(nvg, ax, ay)
                    nvgLineTo(nvg, bx, by)
                    nvgStrokeColor(nvg, Skin.Col(active and C.cyan or C.border, active and 220 or 120))
                    nvgStrokeWidth(nvg, active and 3 or 2)
                    nvgStroke(nvg)
                end
            end
        end
    end
end

local NODE_IDS = { "6_1", "5_1", "5_2", "4_1", "4_2", "3_1", "3_2", "2_1", "2_2", "1_1" }

local function BuildMapPage(cb)
    local r = st.refs
    r.mapTitle = UI.Label { text = "第1幕 · 霓虹游艺厅", fontSize = 16, fontWeight = "bold", fontColor = U.cyan, maxLines = 1 }
    r.mapHeart = UI.Label { text = "5", fontSize = 15, fontWeight = "bold", fontColor = U.red, maxLines = 1 }
    r.mapTicket = UI.Label { text = "24", fontSize = 15, fontWeight = "bold", fontColor = U.gold, maxLines = 1 }

    local topBar = NeoFrame {
        style = "plate", width = "100%", height = 48, paddingLeft = 12, paddingRight = 108,
        flexDirection = "row", alignItems = "center", gap = 10,
        children = {
            r.mapTitle,
            UI.Spacer(),
            UI.Row { flexDirection = "row", alignItems = "center", gap = 3, children = { NeoIcon { kind = "icon", key = "heart", size = 18 }, r.mapHeart } },
            UI.Row { flexDirection = "row", alignItems = "center", gap = 3, children = { NeoIcon { kind = "icon", key = "coin", size = 18 }, r.mapTicket } },
        },
    }

    r.mapNodeBtns = {}
    r.mapNodeMeta = {}
    local mapLines = MapLines { position = "absolute", top = 0, left = 0, width = "100%", height = "100%" }
    r.mapLines = mapLines

    local layerRows = {}
    local rowSpecs = {
        { layer = 6, ids = { "6_1" } },
        { layer = 5, ids = { "5_1", "5_2" } },
        { layer = 4, ids = { "4_1", "4_2" } },
        { layer = 3, ids = { "3_1", "3_2" } },
        { layer = 2, ids = { "2_1", "2_2" } },
        { layer = 1, ids = { "1_1" } },
    }
    for idx, spec in ipairs(rowSpecs) do
        local rowChildren = {}
        for _, nid in ipairs(spec.ids) do
            local isBoss = (nid == "6_1")
            local ic = NeoIcon { kind = "icon", key = "play", size = isBoss and 38 or 26 }
            local lb = UI.Label { text = "战斗", fontSize = 12, fontWeight = "bold", fontColor = U.text, maxLines = 1 }
            local btn = NeoFrame(Widgets.PressFx {
                style = "card", skin = { rarity = "common", radius = 14 },
                width = isBoss and 112 or 96, height = isBoss and 72 or 64, padding = 6, gap = 2,
                flexDirection = "column", alignItems = "center", justifyContent = "center",
                children = { ic, lb },
                onClick = function()
                    if cb.OnEnterMapNode then cb.OnEnterMapNode(nid) end
                end,
            })
            r.mapNodeBtns[nid] = btn
            r.mapNodeMeta[nid] = { ic = ic, lb = lb, btn = btn }
            rowChildren[#rowChildren + 1] = btn
        end
        layerRows[idx] = UI.Row {
            width = "100%", flexGrow = 1, flexBasis = 0,
            justifyContent = "space-evenly", alignItems = "center",
            children = rowChildren,
        }
    end

    local stageArea = UI.Panel {
        width = "100%", flexGrow = 1, flexBasis = 0, paddingVertical = 10, paddingHorizontal = 14,
        flexDirection = "column",
        children = {
            mapLines,
            layerRows[1], layerRows[2], layerRows[3], layerRows[4], layerRows[5], layerRows[6],
        },
    }

    local botBar = NeoFrame {
        style = "cloth", width = "100%", height = 68, paddingHorizontal = 12,
        flexDirection = "row", alignItems = "center", gap = 10,
        children = {
            NeoButton { text = "投币仓", variant = "cyan", flexGrow = 1, flexBasis = 0, minHeight = 46,
                onClick = function() if cb.OnOpenDeck then cb.OnOpenDeck() end end },
            NeoButton { text = "图鉴", variant = "dark", flexGrow = 1, flexBasis = 0, minHeight = 46,
                onClick = function() if cb.OnOpenCodex then cb.OnOpenCodex() end end },
            NeoButton { text = "设置", variant = "dark", flexGrow = 1, flexBasis = 0, minHeight = 46,
                onClick = function() if cb.OnOpenSettings then cb.OnOpenSettings() end end },
        },
    }

    return UI.Panel {
        width = "100%", height = "100%", position = "absolute", top = 0, left = 0,
        flexDirection = "column",
        children = { topBar, stageArea, botBar },
    }
end

-- ----------------------------------------------------------------------------
-- 2. 商店页（3列网格：只放图标+短名+价格；固定高度底部详情区，0 抖动）
-- ----------------------------------------------------------------------------
local function BuildShopPage(cb)
    local r = st.refs
    r.shopTicket = UI.Label { text = "24", fontSize = 16, fontWeight = "bold", fontColor = U.gold, maxLines = 1 }
    local topBar = NeoFrame {
        style = "plate", width = "100%", height = 48, paddingLeft = 12, paddingRight = 108,
        flexDirection = "row", alignItems = "center", gap = 8,
        children = {
            NeoIcon { kind = "icon", key = "bag", size = 22 },
            UI.Label { text = "霓虹商店", fontSize = 18, fontWeight = "bold", fontColor = U.gold },
            UI.Spacer(),
            NeoIcon { kind = "icon", key = "coin", size = 18 },
            r.shopTicket,
        },
    }

    r.shopCells = {}
    local cells = {}
    for i = 1, 6 do
        local ic = NeoIcon { kind = "coin", key = "gold", size = 50 }
        local nm = UI.Label { text = "金币", fontSize = 13, fontWeight = "bold", fontColor = U.text, maxLines = 1, textAlign = "center" }
        local pr = UI.Label { text = "14券", fontSize = 13, fontWeight = "bold", fontColor = U.gold, maxLines = 1, textAlign = "center" }
        local cell = NeoFrame(Widgets.PressFx {
            style = "card", skin = { rarity = "common", selected = false },
            flexGrow = 1, flexBasis = 0, minWidth = 0, height = 114, padding = 6, gap = 4,
            flexDirection = "column", alignItems = "center", justifyContent = "center",
            children = { ic, nm, pr },
            onClick = function()
                st.shopSelected = i
                CampaignHud.RefreshShopDetail()
            end,
        })
        r.shopCells[i] = { cell = cell, ic = ic, nm = nm, pr = pr }
        cells[i] = cell
    end

    local grid = UI.Column {
        width = "100%", gap = 8,
        children = {
            UI.Row { width = "100%", gap = 8, children = { cells[1], cells[2], cells[3] } },
            UI.Row { width = "100%", gap = 8, children = { cells[4], cells[5], cells[6] } },
        },
    }

    -- 底部显式固定高度详情区（0 像素高度跳动）
    r.shopDetIcon = NeoIcon { kind = "coin", key = "gold", size = 56 }
    r.shopDetTitle = UI.Label { text = "标准金币", fontSize = 16, fontWeight = "bold", fontColor = U.gold, maxLines = 1 }
    r.shopDetDesc = UI.Label {
        text = "", fontSize = 13, fontColor = U.textDim, whiteSpace = "normal", width = "100%", maxLines = 3,
    }
    r.shopBuyBtn = NeoButton {
        text = "购买", variant = "primary", minWidth = 96, minHeight = 46,
        onClick = function()
            if cb.OnBuyShop then cb.OnBuyShop(st.shopSelected) end
        end,
    }
    local detailBox = NeoFrame {
        style = "panel", width = "100%", height = 108, padding = 10, gap = 10,
        flexDirection = "row", alignItems = "center",
        children = {
            r.shopDetIcon,
            UI.Column {
                flexGrow = 1, flexBasis = 0, flexShrink = 1, gap = 4,
                children = { r.shopDetTitle, r.shopDetDesc },
            },
            r.shopBuyBtn,
        },
    }

    r.shopRefreshBtn = NeoButton {
        text = "刷新 8券", variant = "cyan", flexGrow = 1, flexBasis = 0, minHeight = 46, fontSize = 14,
        onClick = function() if cb.OnRefreshShop then cb.OnRefreshShop() end end,
    }
    r.shopDelBtn = NeoButton {
        text = "删币 14券", variant = "magenta", flexGrow = 1, flexBasis = 0, minHeight = 46, fontSize = 14,
        onClick = function() if cb.OnShopOpenDelete then cb.OnShopOpenDelete() end end,
    }
    local leaveBtn = NeoButton {
        text = "离开", variant = "dark", flexGrow = 1, flexBasis = 0, minHeight = 46, fontSize = 14,
        onClick = function() if cb.OnLeaveNode then cb.OnLeaveNode() end end,
    }

    local body = UI.Panel {
        width = "100%", flexGrow = 1, flexBasis = 0, padding = 12, gap = 12,
        flexDirection = "column", justifyContent = "space-between",
        children = {
            grid,
            UI.Column {
                width = "100%", gap = 10,
                children = {
                    detailBox,
                    UI.Row { width = "100%", gap = 8, children = { r.shopRefreshBtn, r.shopDelBtn, leaveBtn } },
                },
            },
        },
    }

    return UI.Panel {
        width = "100%", height = "100%", position = "absolute", top = 0, left = 0,
        flexDirection = "column",
        children = { topBar, body },
    }
end

-- ----------------------------------------------------------------------------
-- 3. 整备工坊页（三合一 / 进化 / 休整回心）
-- ----------------------------------------------------------------------------
local function BuildRestPage(cb)
    local r = st.refs
    r.restInfo = UI.Label { text = "", fontSize = 14, fontColor = U.cyan, whiteSpace = "normal", textAlign = "center", width = "100%" }
    r.restMergeBtn = NeoButton {
        text = "三合一升级", variant = "cyan", flexGrow = 1, flexBasis = 0, minHeight = 48,
        onClick = function() if cb.OnRestMerge then cb.OnRestMerge() end end,
    }
    r.restEvoBtn = NeoButton {
        text = "双币进化", variant = "magenta", flexGrow = 1, flexBasis = 0, minHeight = 48,
        onClick = function() if cb.OnRestEvolve then cb.OnRestEvolve() end end,
    }
    r.restHealBtn = NeoButton {
        text = "修整+2心", variant = "green", flexGrow = 1, flexBasis = 0, minHeight = 46,
        onClick = function() if cb.OnRestHeal then cb.OnRestHeal() end end,
    }
    local leaveBtn = NeoButton {
        text = "离开", variant = "primary", flexGrow = 1, flexBasis = 0, minHeight = 46,
        onClick = function() if cb.OnLeaveNode then cb.OnLeaveNode() end end,
    }

    local card = NeoFrame {
        style = "panel", width = "90%", maxWidth = 370, padding = 20, gap = 14,
        flexDirection = "column", alignItems = "center",
        children = {
            NeoIcon { kind = "icon", key = "gear", size = 64, tint = C.green },
            UI.Label { text = "霓虹整备工坊", fontSize = 22, fontWeight = "bold", fontColor = U.green },
            r.restInfo,
            UI.Row { width = "100%", gap = 8, children = { r.restMergeBtn, r.restEvoBtn } },
            UI.Row { width = "100%", gap = 8, children = { r.restHealBtn, leaveBtn } },
        },
    }

    return UI.Panel {
        width = "100%", height = "100%", position = "absolute", top = 0, left = 0,
        flexDirection = "column", justifyContent = "center", alignItems = "center",
        children = { card },
    }
end

-- ----------------------------------------------------------------------------
-- 4. 奇遇事件页 & 5. 宝箱页
-- ----------------------------------------------------------------------------
local EventArt = UI.Widget:Extend("EventArt")
function EventArt:Init(props)
    props = props or {}
    props.pointerEvents = "none"
    self.evId_ = "gold_altar"
    self.evIcon_ = "crown"
    UI.Widget.Init(self, props)
end
function EventArt:SetEvent(id, icon)
    self.evId_ = id or "gold_altar"
    self.evIcon_ = icon or "crown"
end
function EventArt:Render(nvg)
    local l = self:GetAbsoluteLayout()
    if l.w <= 0 or l.h <= 0 then return end
    if Art.DrawSprite(nvg, "event_" .. self.evId_, l.x, l.y, l.w, l.h, 1.0) then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, l.x + 1, l.y + 1, l.w - 2, l.h - 2, 10)
        nvgStrokeColor(nvg, Skin.Col(C.cyan, 190))
        nvgStrokeWidth(nvg, 2)
        nvgStroke(nvg)
        return
    end
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, l.x, l.y, l.w, l.h, 12)
    nvgFillPaint(nvg, nvgLinearGradient(nvg, l.x, l.y, l.x, l.y + l.h,
        Skin.Col({ 42, 30, 84 }, 255), Skin.Col({ 18, 22, 52 }, 255)))
    nvgFill(nvg)
    nvgStrokeColor(nvg, Skin.Col(C.purple, 220))
    nvgStrokeWidth(nvg, 2)
    nvgStroke(nvg)
    local sz = math.min(l.w, l.h) * 0.65
    Art.DrawIcon(nvg, self.evIcon_, l.x + (l.w - sz) * 0.5, l.y + (l.h - sz) * 0.5, sz, C.gold)
end

local function BuildEventPage(cb)
    local r = st.refs
    r.evArt = EventArt { width = "100%", height = 190 }
    r.evTitle = UI.Label { text = "黄金祭坛", fontSize = 20, fontWeight = "bold", fontColor = U.gold }
    r.evDesc = UI.Label { text = "", fontSize = 14, fontColor = U.textDim, whiteSpace = "normal", textAlign = "center", width = "100%" }
    r.evBtnA = NeoButton { text = "选项A", variant = "primary", flexGrow = 1, flexBasis = 0, minHeight = 46, fontSize = 13,
        onClick = function() if cb.OnEventChoice then cb.OnEventChoice("a") end end }
    r.evBtnB = NeoButton { text = "选项B", variant = "cyan", flexGrow = 1, flexBasis = 0, minHeight = 46, fontSize = 13,
        onClick = function() if cb.OnEventChoice then cb.OnEventChoice("b") end end }
    r.evNextBtn = NeoButton { text = "继续", variant = "primary", width = "54%", minWidth = 148, minHeight = 46, alignSelf = "center",
        visible = false, onClick = function() if cb.OnLeaveNode then cb.OnLeaveNode() end end }
    r.evChoiceRow = UI.Row { width = "100%", gap = 10, children = { r.evBtnA, r.evBtnB } }

    local card = NeoFrame {
        style = "panel", width = "90%", maxWidth = 370, padding = 18, gap = 14,
        flexDirection = "column", alignItems = "center",
        children = { r.evArt, r.evTitle, r.evDesc, r.evChoiceRow, r.evNextBtn },
    }
    return UI.Panel {
        width = "100%", height = "100%", position = "absolute", top = 0, left = 0,
        flexDirection = "column", justifyContent = "center", alignItems = "center",
        children = { card },
    }
end

local function BuildChestPage(cb)
    local r = st.refs
    r.chestIcon = NeoIcon { kind = "icon", key = "chest", size = 76, tint = C.gold }
    r.chestTitle = UI.Label { text = "霓虹秘宝宝箱", fontSize = 22, fontWeight = "bold", fontColor = U.gold }
    r.chestDesc = UI.Label { text = "点击开启获得专属遗物与金券", fontSize = 14, fontColor = U.textDim, whiteSpace = "normal", textAlign = "center", width = "100%" }
    r.chestBtn = NeoButton {
        text = "开启宝箱", variant = "primary", width = "56%", minWidth = 148, minHeight = 50, alignSelf = "center",
        onClick = function() if cb.OnChestAction then cb.OnChestAction() end end,
    }
    local card = NeoFrame {
        style = "panel", width = "88%", maxWidth = 350, padding = 22, gap = 14,
        flexDirection = "column", alignItems = "center",
        children = { r.chestIcon, r.chestTitle, r.chestDesc, r.chestBtn },
    }
    return UI.Panel {
        width = "100%", height = "100%", position = "absolute", top = 0, left = 0,
        flexDirection = "column", justifyContent = "center", alignItems = "center",
        children = { card },
    }
end

-- ----------------------------------------------------------------------------
-- 对外构建与刷新
-- ----------------------------------------------------------------------------
function CampaignHud.BuildPages(cb)
    st.cb = cb
    st.pages.map = BuildMapPage(cb)
    st.pages.shop = BuildShopPage(cb)
    st.pages.rest = BuildRestPage(cb)
    st.pages.event = BuildEventPage(cb)
    st.pages.chest = BuildChestPage(cb)
    return st.pages
end

function CampaignHud.RefreshMap(run)
    local r = st.refs
    local rt = run.route
    if not rt then return end
    local actCfg = Config.ACTS[run.act] or Config.ACTS[1]
    SetLbl(r.mapTitle, string.format("第%d幕 · %s", run.act, actCfg.name))
    SetLbl(r.mapHeart, tostring(run.hearts))
    SetLbl(r.mapTicket, tostring(run.tickets))
    r.mapLines:SetData(rt, r.mapNodeBtns)

    for _, nid in ipairs(NODE_IDS) do
        local node = rt.byId[nid]
        local slot = r.mapNodeMeta[nid]
        if node and slot then
            local meta = Route.NODE_META[node.type] or Route.NODE_META.battle
            local canGo = run:IsNodeSelectable(nid)
            if node.type == "boss" and node.bossId then
                slot.ic:SetIcon("boss", node.bossId, 1, C.magenta)
            else
                slot.ic:SetIcon("icon", meta.icon, 1, node.visited and C.muted or meta.col)
            end
            SetLbl(slot.lb, node.title or meta.name)
            slot.btn.skin_.selected = canGo
            slot.btn.skin_.rarity = (node.type == "boss" and "epic") or (canGo and "legendary" or "common")
            slot.btn:SetStyle({ opacity = (canGo or node.visited) and 1.0 or 0.52 })
        end
    end
end

function CampaignHud.RefreshShopDetail()
    local r = st.refs
    local idx = st.shopSelected
    for i = 1, 6 do
        r.shopCells[i].cell.skin_.selected = (i == idx)
    end
    local item = st.shopItems[idx]
    if not item then
        r.shopBuyBtn:SetDisabled(true)
        return
    end
    if item.kind == "coin" then
        local def = Config.COINS[item.id]
        r.shopDetIcon:SetIcon("coin", item.id, 1)
        SetLbl(r.shopDetTitle, def.name)
        SetLbl(r.shopDetDesc, def.desc)
    elseif item.kind == "relic" then
        local def = Config.RELICS[item.id]
        r.shopDetIcon:SetIcon("relic", item.id, 1)
        SetLbl(r.shopDetTitle, def.name)
        SetLbl(r.shopDetDesc, def.desc)
    else
        r.shopDetIcon:SetIcon("icon", "heart", 1, C.red)
        SetLbl(r.shopDetTitle, "生命修补包")
        SetLbl(r.shopDetDesc, "立刻恢复 +1 生命值（不超过上限）。")
    end
    r.shopBuyBtn:SetText(item.sold and "已售罄" or ("买 " .. item.price .. "券"))
    r.shopBuyBtn:SetDisabled(item.sold == true)
end

function CampaignHud.RefreshShop(run)
    local r = st.refs
    st.shopItems = run.shopItems or {}
    if st.shopSelected > #st.shopItems or st.shopSelected < 1 then st.shopSelected = 1 end
    SetLbl(r.shopTicket, tostring(run.tickets))
    r.shopRefreshBtn:SetText("刷新 " .. run.shopRefreshCost .. "券")
    r.shopDelBtn:SetText("删币 " .. run:GetDeleteCost() .. "券")

    for i = 1, 6 do
        local cell = r.shopCells[i]
        local item = st.shopItems[i]
        if item then
            cell.cell:SetVisible(true)
            if item.kind == "coin" then
                local def = Config.COINS[item.id]
                cell.ic:SetIcon("coin", item.id, 1)
                SetLbl(cell.nm, def.short or def.name)
                cell.cell.skin_.rarity = def.rarity
            elseif item.kind == "relic" then
                local def = Config.RELICS[item.id]
                cell.ic:SetIcon("relic", item.id, 1)
                SetLbl(cell.nm, def.name)
                cell.cell.skin_.rarity = def.rarity
            else
                cell.ic:SetIcon("icon", "heart", 1, C.red)
                SetLbl(cell.nm, "回1心")
                cell.cell.skin_.rarity = "common"
            end
            SetLbl(cell.pr, item.sold and "已购" or (item.price .. "券"))
            cell.cell:SetStyle({ opacity = item.sold and 0.48 or 1.0 })
        else
            cell.cell:SetVisible(false)
        end
    end
    CampaignHud.RefreshShopDetail()
end

function CampaignHud.RefreshRest(run)
    local r = st.refs
    local merges = run.roster:FindMergeGroups()
    local evos = run.roster:FindAvailableEvolutions()
    r.restMergeBtn:SetDisabled(#merges == 0)
    r.restEvoBtn:SetDisabled(#evos == 0)
    local mTxt = (#merges > 0) and ("可三合一：" .. Config.COINS[merges[1].kind].name) or "暂无三合一(需3枚同星币)"
    local eTxt = (#evos > 0) and ("可进化：" .. evos[1].name) or "暂无可进化配方"
    SetLbl(r.restInfo, mTxt .. "\n" .. eTxt .. string.format("\n当前生命 %d/%d", run.hearts, run.maxHearts))
end

function CampaignHud.RefreshEvent(run)
    local r = st.refs
    local ev = run.currentEvent
    if not ev then return end
    r.evArt:SetEvent(ev.id, ev.icon)
    SetLbl(r.evTitle, ev.name)
    if run.eventOutcome then
        SetLbl(r.evDesc, run.eventOutcome)
        r.evChoiceRow:SetVisible(false)
        r.evNextBtn:SetVisible(true)
    else
        SetLbl(r.evDesc, ev.desc)
        r.evBtnA:SetText(ev.a.text)
        r.evBtnB:SetText(ev.b.text)
        r.evChoiceRow:SetVisible(true)
        r.evNextBtn:SetVisible(false)
    end
end

function CampaignHud.RefreshChest(run)
    local r = st.refs
    if run.chestClaimed then
        local rid = run.chestRelic
        if rid and Config.RELICS[rid] then
            r.chestIcon:SetIcon("relic", rid, 1)
            SetLbl(r.chestTitle, Config.RELICS[rid].name)
            SetLbl(r.chestDesc, Config.RELICS[rid].desc .. "\n额外获得 +12 金券！")
        else
            r.chestIcon:SetIcon("icon", "coin", 1, C.gold)
            SetLbl(r.chestTitle, "满载金库")
            SetLbl(r.chestDesc, "获得 +47 金券！")
        end
        r.chestBtn:SetText("继续出发")
    else
        r.chestIcon:SetIcon("icon", "chest", 1, C.gold)
        SetLbl(r.chestTitle, "霓虹秘宝宝箱")
        SetLbl(r.chestDesc, "开启必得专属遗物与金券补给")
        r.chestBtn:SetText("开启宝箱")
    end
end

return CampaignHud
