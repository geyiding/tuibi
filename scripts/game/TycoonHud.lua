-- ============================================================================
-- TycoonHud.lua  增量推币首富全界面（全一次建树 + 增量属性刷新 + 哪里亮了点哪里）
--   · 严格遵守 minigame-ui-spec：B1-B6 零裁剪、右上角避让 108px、固定高度详情三段式
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("game/Config")
local Billionaires = require("game/Billionaires")
local Skin = require("game/Skin")
local Widgets = require("game/Widgets")
local Number = require("game/Number")

local C, U = Skin.C, Skin.UI
local NeoFrame, NeoButton, NeoIcon, NeoBar, AvatarIcon =
    Widgets.NeoFrame, Widgets.NeoButton, Widgets.NeoIcon, Widgets.NeoBar, Widgets.AvatarIcon
local floor, min, max, ceil = math.floor, math.min, math.max, math.ceil

local TycoonHud = {}
local st = {
    cb = nil,
    modals = {},
    refs = {},
    shown = {},
    curModal = nil,
    -- 选择态
    machSel = 1,
    coinPage = 1,
    coinSel = 1,
    techSel = 1,
    talentSel = 1,
    welfareSel = 1,
    rankPage = ceil(#Config.RANKS / 5),
    -- 弹窗瞬态上下文
    offlineAmt = 0,
    offlineSec = 0,
    prestigeDouble = false,
    mockAdDur = 2.0,
    mockAdLeft = 0,
    overtakeOpen = false,
    overtakeLeft = 0,
    overtakeDur = 4.8,
    overtakeSticky = false,
    overtakeBounty = 0,
}

local function SetLbl(lbl, txt)
    if lbl and lbl.props.text ~= txt then lbl:SetText(txt) end
end

local function SetCellVis(w, vis)
    if w and w.props.visible ~= vis then w:SetVisible(vis) end
end

local function SetCellOp(w, op)
    if w and w.props.opacity ~= op then w:SetStyle({ opacity = op }) end
end

local function MakeGrid(cols, gap, nodes)
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

local function MakeCloseBtn(onClose)
    return NeoButton {
        text = "×", style = "slot", width = 38, minWidth = 38, height = 38, minHeight = 38,
        paddingHorizontal = 0, fontSize = 18,
        onClick = onClose,
    }
end

local function MakeModalWrap(inner, closeOnOverlay)
    return UI.Panel {
        width = "100%", height = "100%", position = "absolute", top = 0, left = 0,
        backgroundColor = U.overlay, visible = false, pointerEvents = "auto",
        flexDirection = "column", justifyContent = "center", alignItems = "center",
        onClick = closeOnOverlay and function() TycoonHud.CloseModal() end or nil,
        children = {
            UI.Panel {
                width = "100%", flexDirection = "column", alignItems = "center", pointerEvents = "box-none",
                onClick = function() end, -- 阻断内部点击穿透到遮罩
                children = { inner },
            },
        },
    }
end

-- B1 固定高度三段隔离详情框（顶部标题 + 中间滚动说明 + 右侧买操作钮）
local function MakeDetailBar(iconKind, iconKey, btnText, btnVar, onAction)
    local ic = NeoIcon { kind = iconKind, key = iconKey, size = 50, flexShrink = 0 }
    local title = UI.Label { text = "", fontSize = 15, fontWeight = "bold", fontColor = U.gold, maxLines = 1, flexShrink = 0 }
    local desc = UI.Label { text = "", fontSize = 12, fontColor = U.textDim, whiteSpace = "normal", width = "100%" }
    local scroll = UI.ScrollView {
        width = "100%", height = 52, scrollY = true,
        children = { desc },
    }
    local btn = NeoButton {
        text = btnText, variant = btnVar or "primary", minWidth = 96, minHeight = 46, paddingHorizontal = 8, fontSize = 13,
        flexShrink = 0,
        onClick = onAction,
    }
    local bar = NeoFrame {
        style = "card", width = "100%", height = 108, padding = 8, gap = 8,
        flexDirection = "row", alignItems = "center",
        children = {
            ic,
            UI.Column { flexGrow = 1, flexBasis = 0, flexShrink = 1, height = 78, gap = 2, children = { title, scroll } },
            btn,
        },
    }
    return bar, ic, title, desc, btn
end

-- ----------------------------------------------------------------------------
-- 1. 主界面（顶栏 + 中央舞台 + 右侧广告浮标 + 5大底部亮灯按钮）
-- ----------------------------------------------------------------------------
local function BuildMainPage(stageWidget, cb)
    local r = st.refs
    r.lblRankNo = UI.Label { text = "No.60.00亿", fontSize = 11, fontWeight = "bold", fontColor = U.cyan, maxLines = 1 }
    local rankBadge = NeoFrame(Widgets.PressFx {
        style = "slot", height = 36, minWidth = 74, paddingHorizontal = 5,
        flexDirection = "row", justifyContent = "center", alignItems = "center",
        children = { r.lblRankNo },
        onClick = function() TycoonHud.OpenModal("ranks") end,
    })

    r.lblCash = UI.Label { text = "¥0", fontSize = 17, fontWeight = "bold", fontColor = U.gold, maxLines = 1 }
    r.lblCps = UI.Label { text = "¥3/秒", fontSize = 12, fontColor = U.cyan, maxLines = 1 }
    local cashCol = UI.Column {
        flexGrow = 1, flexBasis = 0, flexShrink = 1, minWidth = 0, gap = 0,
        children = { r.lblCash, r.lblCps },
    }

    local helpBtn = NeoButton {
        text = "?", style = "slot", width = 34, minWidth = 34, height = 34, minHeight = 34, paddingHorizontal = 0, fontSize = 16,
        onClick = function() TycoonHud.OpenModal("formula") end,
    }
    local gearBtn = NeoFrame(Widgets.PressFx {
        style = "slot", width = 34, height = 34,
        flexDirection = "row", justifyContent = "center", alignItems = "center",
        children = { NeoIcon { kind = "icon", key = "gear", size = 17 } },
        onClick = function() if cb.OnOpenSettings then cb.OnOpenSettings() end end,
    })

    local row1 = UI.Row {
        width = "100%", height = 64, alignItems = "center", paddingLeft = 8, paddingRight = 104, gap = 6,
        children = { rankBadge, cashCol, helpBtn, gearBtn },
    }

    r.lblSp = UI.Label { text = "技能点:0", fontSize = 11, fontWeight = "bold", fontColor = U.gold, maxLines = 1, textAlign = "center" }
    local spPill = NeoFrame(Widgets.PressFx {
        style = "slot", height = 28, minWidth = 66, paddingHorizontal = 5,
        flexDirection = "row", justifyContent = "center", alignItems = "center",
        children = { r.lblSp },
        onClick = function() TycoonHud.OpenModal("coins") end,
    })

    r.rankBar = NeoBar { width = "100%", height = 28, value = 0, text = "街边小摊主 · 0 / 2000" }
    local rankBarWrap = UI.Panel(Widgets.PressFx {
        flexGrow = 1, flexBasis = 0, minWidth = 0, height = 28,
        onClick = function() TycoonHud.OpenModal("ranks") end,
        children = { r.rankBar },
    })

    r.lblMult = UI.Label { text = "x1.0", fontSize = 13, fontWeight = "bold", fontColor = U.magenta, maxLines = 1, textAlign = "center" }
    local multPill = NeoFrame(Widgets.PressFx {
        style = "slot", height = 28, minWidth = 54, paddingHorizontal = 6,
        flexDirection = "row", justifyContent = "center", alignItems = "center",
        children = { r.lblMult },
        onClick = function() TycoonHud.OpenModal("formula") end,
    })

    local row2 = UI.Row {
        width = "100%", height = 34, alignItems = "center", paddingHorizontal = 10, gap = 6,
        children = { spPill, rankBarWrap, multPill },
    }

    local topPlate = NeoFrame {
        style = "plate", width = "100%", height = 102, flexDirection = "column", paddingTop = 2, gap = 2,
        children = { row1, row2 },
    }

    -- 右侧浮动看广告快捷按钮（远离顶部右侧 108px 胶囊且严格 left/right >= 8）
    r.adBoostPill = NeoButton {
        text = "×3印钞", variant = "magenta", minHeight = 38, paddingHorizontal = 10, fontSize = 12,
        onClick = function() if cb.OnWatchAd then cb.OnWatchAd("boost_3x") end end,
    }
    r.airdropPill = NeoButton {
        text = "风投空投", variant = "primary", minHeight = 38, paddingHorizontal = 10, fontSize = 12, visible = false,
        onClick = function() TycoonHud.OpenModal("airdrop") end,
    }
    local floatRack = UI.Column {
        position = "absolute", top = 10, right = 10, alignItems = "flex-end", gap = 8, pointerEvents = "box-none",
        children = { r.adBoostPill, r.airdropPill },
    }

    -- 财富榜超越即时炫耀弹窗（显示卡通人物头像 + 财富阈值 + 被超越人物 + 赏金3倍）
    r.ovAvatar = AvatarIcon { size = 82, shocked = true, surpassed = true }
    r.ovBadgeLbl = UI.Label { text = "🏆 财富榜第 100 名！", fontSize = 13, fontWeight = "bold", fontColor = U.gold, maxLines = 1 }
    r.ovWealthLbl = UI.Label { text = "财富达到 ¥1,500！", fontSize = 16, fontWeight = "bold", fontColor = U.text, maxLines = 1 }
    r.ovWhoLbl = UI.Label { text = "正式超越【富豪】", fontSize = 13, fontWeight = "bold", fontColor = U.cyan, maxLines = 1 }
    r.ovQuoteLbl = UI.Label { text = "“吐槽语”", fontSize = 11, fontColor = U.textDim, whiteSpace = "normal", maxLines = 2, width = "100%" }
    r.ovBountyLbl = UI.Label { text = "晋升赠礼 +0 技能点（看广告可×3!）", fontSize = 12, fontWeight = "bold", fontColor = U.green, maxLines = 1 }
    r.ovCloseBtn = NeoButton {
        text = "收下", variant = "dark", flexGrow = 1, flexBasis = 0, minHeight = 36, height = 36, fontSize = 12,
        onClick = function() TycoonHud.DismissOvertake() end,
    }
    r.ovAdBtn = NeoButton {
        text = "×3技能点(广告)", variant = "primary", flexGrow = 1.25, flexBasis = 0, minHeight = 36, height = 36, fontSize = 12,
        onClick = function()
            if cb.OnClaimOvertakeAd then cb.OnClaimOvertakeAd(st.overtakeBounty) end
        end,
    }
    r.ovTimerBar = NeoBar { width = "100%", height = 10, value = 1, text = "", color = C.gold }
    local ovBox = NeoFrame {
        style = "panel", skin = { rarity = "legendary" }, width = "100%", padding = 10, gap = 6,
        flexDirection = "column", pointerEvents = "auto",
        onClick = function() end,
        children = {
            UI.Row {
                width = "100%", gap = 10, alignItems = "center",
                children = {
                    r.ovAvatar,
                    UI.Column {
                        flexGrow = 1, flexBasis = 0, flexShrink = 1, gap = 2,
                        children = { r.ovBadgeLbl, r.ovWealthLbl, r.ovWhoLbl, r.ovQuoteLbl, r.ovBountyLbl },
                    },
                },
            },
            UI.Row { width = "100%", gap = 8, children = { r.ovCloseBtn, r.ovAdBtn } },
            r.ovTimerBar,
        },
    }
    r.overtakeWrap = UI.Panel {
        position = "absolute", top = 10, left = 10, right = 10,
        visible = false, pointerEvents = "box-none",
        children = { ovBox },
    }

    local stageHost = UI.Panel {
        width = "100%", flexGrow = 1, flexBasis = 0,
        children = { stageWidget, floatRack, r.overtakeWrap },
    }

    local navDefs = {
        { id = "machine", text = "机台" },
        { id = "coins",   text = "币种" },
        { id = "tech",    text = "科技" },
        { id = "prestige",text = "上市" },
        { id = "welfare", text = "福利" },
    }
    r.navBtns = {}
    local navRowChildren = {}
    for i, nd in ipairs(navDefs) do
        local btn = NeoButton {
            text = nd.text, variant = "dark", flexGrow = 1, flexBasis = 0, flexShrink = 1, minWidth = 0,
            minHeight = 50, paddingHorizontal = 2, fontSize = 13,
            onClick = function() TycoonHud.OpenModal(nd.id) end,
        }
        r.navBtns[nd.id] = btn
        navRowChildren[i] = btn
    end

    local bottomBar = NeoFrame {
        style = "cloth", width = "100%", height = 72, paddingHorizontal = 8,
        flexDirection = "row", alignItems = "center", gap = 6,
        children = navRowChildren,
    }

    return UI.Panel {
        width = "100%", height = "100%", position = "absolute", top = 0, left = 0,
        flexDirection = "column",
        children = { topPlate, stageHost, bottomBar },
    }
end

-- ----------------------------------------------------------------------------
-- 2. 机台升级弹窗（4×2 网格 + ×1/×10/最大 切换 + B1 固定详情）
-- ----------------------------------------------------------------------------
local function BuildMachineModal(cb)
    local r = st.refs
    local closeBtn = MakeCloseBtn(function() TycoonHud.CloseModal() end)
    r.machSpLbl = UI.Label { text = "技能点:0", fontSize = 11, fontWeight = "bold", fontColor = U.cyan, maxLines = 1, flexShrink = 1 }
    local header = UI.Row {
        width = "100%", height = 40, alignItems = "center", gap = 6,
        children = { UI.Label { text = "机台暴走改装", fontSize = 17, fontWeight = "bold", fontColor = U.gold }, r.machSpLbl, UI.Spacer(), closeBtn },
    }

    r.modeBtns = {}
    local modes = { { m = 1, lbl = "×1" }, { m = 10, lbl = "×10" }, { m = 0, lbl = "最大" } }
    local modeRowChildren = { UI.Label { text = "连升档位：", fontSize = 12, fontColor = U.textDim } }
    for _, md in ipairs(modes) do
        local mb = NeoButton {
            text = md.lbl, variant = "dark", minWidth = 54, minHeight = 32, height = 32, paddingHorizontal = 8, fontSize = 12,
            onClick = function()
                if cb.OnSetBuyMode then cb.OnSetBuyMode(md.m) end
                TycoonHud.RefreshCurrentModal()
            end,
        }
        r.modeBtns[md.m] = mb
        modeRowChildren[#modeRowChildren + 1] = mb
    end
    local modeRow = UI.Row { width = "100%", height = 34, alignItems = "center", gap = 6, children = modeRowChildren }

    r.machCells = {}
    local cNodes = {}
    for i = 1, 8 do
        local def = Config.MACHINE_UPGRADES[i]
        local ic = NeoIcon { kind = "relic", key = def.relic, size = 44 }
        local nm = UI.Label { text = def.short, fontSize = 12, fontWeight = "bold", fontColor = U.text, maxLines = 1, width = "100%", textAlign = "center" }
        local lv = UI.Label { text = "Lv.0", fontSize = 12, fontColor = U.cyan, maxLines = 1 }
        local cell = NeoFrame(Widgets.PressFx {
            style = "slot", skin = { rarity = "common", selected = false, afford = false },
            flexGrow = 1, flexBasis = 0, flexShrink = 1, minWidth = 0, height = 104, padding = 4, gap = 2,
            flexDirection = "column", alignItems = "center", justifyContent = "center",
            children = { ic, nm, lv },
            onClick = function() st.machSel = i; TycoonHud.RefreshMachine() end,
        })
        r.machCells[i] = { cell = cell, ic = ic, nm = nm, lv = lv }
        cNodes[i] = cell
    end
    local grid = MakeGrid(4, 6, cNodes)

    local detBar, detIc, detTitle, detDesc, detBtn = MakeDetailBar("relic", "double_barrel", "升级", "primary", function()
        local def = Config.MACHINE_UPGRADES[st.machSel]
        if def and cb.OnBuyMachine then cb.OnBuyMachine(def.id) end
    end)
    r.machDetIc, r.machDetTitle, r.machDetDesc, r.machDetBtn = detIc, detTitle, detDesc, detBtn

    local panel = NeoFrame {
        style = "panel", width = "92%", maxWidth = 390, height = 528, padding = 12, gap = 8,
        flexDirection = "column", justifyContent = "space-between",
        children = { header, modeRow, grid, UI.Spacer(), detBar },
    }
    return MakeModalWrap(panel, true)
end

-- ----------------------------------------------------------------------------
-- 3. 22 币渐进进化弹窗（4×3 网格 × 2页）
-- ----------------------------------------------------------------------------
local function BuildCoinsModal(cb)
    local r = st.refs
    r.coinCountLbl = UI.Label { text = "1/22", fontSize = 12, fontColor = U.cyan, maxLines = 1 }
    r.coinSpLbl = UI.Label { text = "技能点:0", fontSize = 11, fontWeight = "bold", fontColor = U.gold, maxLines = 1, flexShrink = 1 }
    local header = UI.Row {
        width = "100%", height = 40, alignItems = "center", gap = 6,
        children = {
            UI.Label { text = "币种进化", fontSize = 17, fontWeight = "bold", fontColor = U.gold },
            r.coinCountLbl, r.coinSpLbl, UI.Spacer(), MakeCloseBtn(function() TycoonHud.CloseModal() end),
        },
    }

    r.coinCells = {}
    local cNodes = {}
    for i = 1, 12 do
        local ic = NeoIcon { kind = "coin", key = "gold", size = 44 }
        local nm = UI.Label { text = "金币", fontSize = 12, fontWeight = "bold", fontColor = U.text, maxLines = 1, width = "100%", textAlign = "center" }
        local sub = UI.Label { text = "Lv.1", fontSize = 12, fontColor = U.gold, maxLines = 1 }
        local cell = NeoFrame(Widgets.PressFx {
            style = "slot", skin = { rarity = "common", selected = false, afford = false },
            flexGrow = 1, flexBasis = 0, flexShrink = 1, minWidth = 0, height = 88, padding = 4, gap = 1,
            flexDirection = "column", alignItems = "center", justifyContent = "center",
            children = { ic, nm, sub },
            onClick = function() st.coinSel = i; TycoonHud.RefreshCoins() end,
        })
        r.coinCells[i] = { cell = cell, ic = ic, nm = nm, sub = sub }
        cNodes[i] = cell
    end
    local grid = MakeGrid(4, 5, cNodes)

    r.coinPageLbl = UI.Label { text = "1/2", fontSize = 13, fontColor = U.textDim }
    local pageRow = UI.Row {
        width = "100%", height = 38, alignItems = "center", justifyContent = "center", gap = 12,
        children = {
            NeoButton { text = "上一页", variant = "dark", minHeight = 36, minWidth = 76, fontSize = 13,
                onClick = function() st.coinPage = 1; st.coinSel = 1; TycoonHud.RefreshCoins() end },
            r.coinPageLbl,
            NeoButton { text = "下一页", variant = "dark", minHeight = 36, minWidth = 76, fontSize = 13,
                onClick = function() st.coinPage = 2; st.coinSel = 1; TycoonHud.RefreshCoins() end },
        },
    }

    local detBar, detIc, detTitle, detDesc, detBtn = MakeDetailBar("coin", "gold", "解锁", "primary", function()
        local idx = (st.coinPage - 1) * 12 + st.coinSel
        local tier = Config.COIN_TIERS[idx]
        if tier and cb.OnBuyCoin then cb.OnBuyCoin(tier.id) end
    end)
    r.coinDetIc, r.coinDetTitle, r.coinDetDesc, r.coinDetBtn = detIc, detTitle, detDesc, detBtn

    local panel = NeoFrame {
        style = "panel", width = "92%", maxWidth = 390, height = 528, padding = 12, gap = 8,
        flexDirection = "column", justifyContent = "space-between",
        children = { header, grid, pageRow, detBar },
    }
    return MakeModalWrap(panel, true)
end

-- ----------------------------------------------------------------------------
-- 4. 12 项黑科技里程碑弹窗（4×3 网格）
-- ----------------------------------------------------------------------------
local function BuildTechModal(cb)
    local r = st.refs
    r.techCountLbl = UI.Label { text = "0/12", fontSize = 12, fontColor = U.green, maxLines = 1 }
    r.techSpLbl = UI.Label { text = "技能点:0", fontSize = 11, fontWeight = "bold", fontColor = U.gold, maxLines = 1, flexShrink = 1 }
    local header = UI.Row {
        width = "100%", height = 40, alignItems = "center", gap = 6,
        children = {
            UI.Label { text = "黑科技", fontSize = 17, fontWeight = "bold", fontColor = U.gold },
            r.techCountLbl, r.techSpLbl, UI.Spacer(), MakeCloseBtn(function() TycoonHud.CloseModal() end),
        },
    }

    r.techCells = {}
    local cNodes = {}
    for i = 1, 12 do
        local t = Config.TECH_UPGRADES[i]
        local ic = NeoIcon { kind = "relic", key = t.relic, size = 42 }
        local nm = UI.Label { text = t.name, fontSize = 12, fontWeight = "bold", fontColor = U.text, maxLines = 1, width = "100%", textAlign = "center" }
        local stLbl = UI.Label { text = "未研", fontSize = 12, fontColor = U.gold, maxLines = 1 }
        local cell = NeoFrame(Widgets.PressFx {
            style = "slot", skin = { rarity = "rare", selected = false, afford = false },
            flexGrow = 1, flexBasis = 0, flexShrink = 1, minWidth = 0, height = 94, padding = 4, gap = 2,
            flexDirection = "column", alignItems = "center", justifyContent = "center",
            children = { ic, nm, stLbl },
            onClick = function() st.techSel = i; TycoonHud.RefreshTech() end,
        })
        r.techCells[i] = { cell = cell, ic = ic, nm = nm, stLbl = stLbl }
        cNodes[i] = cell
    end
    local grid = MakeGrid(4, 6, cNodes)

    local detBar, detIc, detTitle, detDesc, detBtn = MakeDetailBar("relic", "rail_guard", "研发", "green", function()
        local t = Config.TECH_UPGRADES[st.techSel]
        if t and cb.OnBuyTech then cb.OnBuyTech(t.id) end
    end)
    r.techDetIc, r.techDetTitle, r.techDetDesc, r.techDetBtn = detIc, detTitle, detDesc, detBtn

    local panel = NeoFrame {
        style = "panel", width = "92%", maxWidth = 390, height = 528, padding = 12, gap = 8,
        flexDirection = "column", justifyContent = "space-between",
        children = { header, grid, UI.Spacer(), detBar },
    }
    return MakeModalWrap(panel, true)
end

-- ----------------------------------------------------------------------------
-- 5. IPO 上市转生 & 永久天赋弹窗
-- ----------------------------------------------------------------------------
local function BuildPrestigeModal(cb)
    local r = st.refs
    local header = UI.Row {
        width = "100%", height = 40, alignItems = "center", gap = 6,
        children = {
            UI.Label { text = "资本上市敲钟", fontSize = 17, fontWeight = "bold", fontColor = U.gold },
            UI.Label { text = "不清空财富", fontSize = 11, fontWeight = "bold", fontColor = U.green, maxLines = 1 },
            UI.Spacer(), MakeCloseBtn(function() TycoonHud.CloseModal() end),
        },
    }

    r.presSharesLbl = UI.Label { text = "传奇股：0", fontSize = 14, fontWeight = "bold", fontColor = U.gold, maxLines = 1 }
    r.presPendLbl = UI.Label { text = "下轮融资：+0 股 · +0 点", fontSize = 12, fontColor = U.cyan, maxLines = 1 }
    r.presNextLbl = UI.Label { text = "★ 绝不清空现金、机台与已解币种", fontSize = 11, fontColor = U.green, maxLines = 1 }
    local topCard = NeoFrame {
        style = "card", width = "100%", height = 86, padding = 10, gap = 10,
        flexDirection = "row", alignItems = "center",
        children = {
            NeoIcon { kind = "boss", key = "vaultbeast", size = 56, flexShrink = 0 },
            UI.Column { flexGrow = 1, flexBasis = 0, gap = 3, children = { r.presSharesLbl, r.presPendLbl, r.presNextLbl } },
        },
    }

    r.talentCells = {}
    local tNodes = {}
    for i = 1, 4 do
        local p = Config.PRESTIGE_TALENTS[i]
        local ic = NeoIcon { kind = "relic", key = p.relic, size = 44, flexShrink = 0 }
        local nm = UI.Label { text = p.name, fontSize = 13, fontWeight = "bold", fontColor = U.text, maxLines = 1 }
        local lv = UI.Label { text = "Lv.0 · 2股", fontSize = 12, fontColor = U.cyan, maxLines = 1 }
        local cell = NeoFrame(Widgets.PressFx {
            style = "slot", skin = { rarity = "epic", selected = false, afford = false },
            flexGrow = 1, flexBasis = 0, minWidth = 0, height = 80, padding = 8, gap = 8,
            flexDirection = "row", alignItems = "center",
            children = { ic, UI.Column { flexGrow = 1, flexBasis = 0, gap = 2, children = { nm, lv } } },
            onClick = function() st.talentSel = i; TycoonHud.RefreshPrestige() end,
        })
        r.talentCells[i] = { cell = cell, ic = ic, nm = nm, lv = lv }
        tNodes[i] = cell
    end
    local tGrid = MakeGrid(2, 6, tNodes)

    local detBar, detIc, detTitle, detDesc, detBtn = MakeDetailBar("relic", "big_pouch", "点亮", "cyan", function()
        local p = Config.PRESTIGE_TALENTS[st.talentSel]
        if p and cb.OnBuyTalent then cb.OnBuyTalent(p.id) end
    end)
    detBar:SetStyle({ height = 96 })
    r.talDetIc, r.talDetTitle, r.talDetDesc, r.talDetBtn = detIc, detTitle, detDesc, detBtn

    r.presNormalBtn = NeoButton {
        text = "敲钟上市", variant = "dark", flexGrow = 1, flexBasis = 0, minHeight = 46, fontSize = 14,
        onClick = function() if cb.OnConfirmPrestige then cb.OnConfirmPrestige(false) end end,
    }
    r.presAdBtn = NeoButton {
        text = "广告×2上市", variant = "primary", flexGrow = 1, flexBasis = 0, minHeight = 46, fontSize = 14,
        onClick = function() if cb.OnConfirmPrestige then cb.OnConfirmPrestige(true) end end,
    }
    local botRow = UI.Row { width = "100%", gap = 10, children = { r.presNormalBtn, r.presAdBtn } }

    local panel = NeoFrame {
        style = "panel", width = "92%", maxWidth = 390, height = 528, padding = 12, gap = 8,
        flexDirection = "column", justifyContent = "space-between",
        children = { header, topCard, tGrid, detBar, botRow },
    }
    return MakeModalWrap(panel, true)
end

-- ----------------------------------------------------------------------------
-- 6. 福利加速站弹窗（4 张模拟激励广告卡片 2×2 + B1 详情）
-- ----------------------------------------------------------------------------
local function BuildWelfareModal(cb)
    local r = st.refs
    r.welfareCountLbl = UI.Label { text = "已看 0 次", fontSize = 12, fontColor = U.textDim }
    local header = UI.Row {
        width = "100%", height = 40, alignItems = "center", gap = 8,
        children = {
            UI.Label { text = "首富福利加速站", fontSize = 18, fontWeight = "bold", fontColor = U.gold },
            r.welfareCountLbl, UI.Spacer(), MakeCloseBtn(function() TycoonHud.CloseModal() end),
        },
    }

    r.adCards = {}
    local cNodes = {}
    for i = 1, 4 do
        local pid = Config.AD_WELFARE_ORDER[i]
        local def = Config.AD_PLACEMENTS[pid]
        local ic = NeoIcon { kind = def.iconKind, key = def.iconKey, size = 56 }
        local nm = UI.Label { text = def.short, fontSize = 14, fontWeight = "bold", fontColor = U.text, maxLines = 1 }
        local cd = UI.Label { text = "可免费看", fontSize = 12, fontColor = U.green, maxLines = 1 }
        local card = NeoFrame(Widgets.PressFx {
            style = "card", skin = { rarity = "rare", selected = false, afford = true },
            flexGrow = 1, flexBasis = 0, height = 132, padding = 8, gap = 4,
            flexDirection = "column", alignItems = "center", justifyContent = "center",
            children = { ic, nm, cd },
            onClick = function() st.welfareSel = i; TycoonHud.RefreshWelfare() end,
        })
        r.adCards[i] = { card = card, ic = ic, nm = nm, cd = cd }
        cNodes[i] = card
    end
    local grid = MakeGrid(2, 8, cNodes)

    local detBar, detIc, detTitle, detDesc, detBtn = MakeDetailBar("relic", "vip_card", "看广告领", "primary", function()
        local pid = Config.AD_WELFARE_ORDER[st.welfareSel]
        if pid and cb.OnWatchAd then cb.OnWatchAd(pid) end
    end)
    r.adDetIc, r.adDetTitle, r.adDetDesc, r.adDetBtn = detIc, detTitle, detDesc, detBtn

    local panel = NeoFrame {
        style = "panel", width = "92%", maxWidth = 390, height = 528, padding = 12, gap = 8,
        flexDirection = "column", justifyContent = "space-between",
        children = {
            header,
            UI.Label { text = "模拟激励广告位：点击亮卡立即体验商业化增益", fontSize = 12, fontColor = U.cyan, textAlign = "center" },
            grid,
            UI.Spacer(),
            detBar,
        },
    }
    return MakeModalWrap(panel, true)
end

-- ----------------------------------------------------------------------------
-- 7. 全球财富排行榜弹窗（60亿名 -> 前1000强真实福布斯富豪榜，前1000才显示真名与真实身价）
-- ----------------------------------------------------------------------------
local function CalcRankLocatePage(ty)
    local totalPages = max(1, ceil(#Config.RANKS / 5))
    local targetIdx = max(1, min(#Config.RANKS, (ty and ty.rankIdx or 0) + 1))
    local displayPos = (#Config.RANKS + 1) - targetIdx
    return max(1, min(totalPages, ceil(displayPos / 5)))
end

local function BuildRanksModal()
    local r = st.refs
    local header = UI.Row {
        width = "100%", height = 38, alignItems = "center", gap = 8,
        children = {
            UI.Label { text = "全球财富榜 · 前1000真名", fontSize = 17, fontWeight = "bold", fontColor = U.gold },
            UI.Spacer(), MakeCloseBtn(function() TycoonHud.CloseModal() end),
        },
    }
    r.rankCells = {}
    local rowNodes = {}
    for i = 1, 5 do
        local av = AvatarIcon { size = 48 }
        local no = UI.Label { text = "前50亿", fontSize = 12, fontWeight = "bold", fontColor = U.cyan, maxLines = 1 }
        local nm = UI.Label { text = "匿名阶层", fontSize = 14, fontWeight = "bold", fontColor = U.text, maxLines = 1 }
        local ttl = UI.Label { text = "称号", fontSize = 11, fontColor = U.textDim, maxLines = 1 }
        local tg = UI.Label { text = "¥0", fontSize = 13, fontWeight = "bold", fontColor = U.gold, maxLines = 1, textAlign = "right" }
        local stLbl = UI.Label { text = "追赶中", fontSize = 11, fontColor = U.muted, maxLines = 1, textAlign = "right" }
        local row = NeoFrame {
            style = "card", skin = { rarity = "common", selected = false },
            width = "100%", height = 64, paddingHorizontal = 8, paddingVertical = 4, gap = 8,
            flexDirection = "row", alignItems = "center",
            children = {
                av,
                UI.Column {
                    flexGrow = 1, flexBasis = 0, flexShrink = 1, minWidth = 0, gap = 2,
                    children = {
                        UI.Row { width = "100%", gap = 6, alignItems = "center", children = { no, nm } },
                        ttl,
                    },
                },
                UI.Column {
                    alignItems = "flex-end", flexShrink = 0, gap = 2,
                    children = { tg, stLbl },
                },
            },
        }
        r.rankCells[i] = { cell = row, av = av, no = no, nm = nm, ttl = ttl, tg = tg, stLbl = stLbl }
        rowNodes[i] = row
    end
    local listCol = UI.Column { width = "100%", gap = 6, children = rowNodes }

    r.rankPageLbl = UI.Label { text = "1/17", fontSize = 12, fontColor = U.textDim }
    local pageRow = UI.Row {
        width = "100%", height = 38, alignItems = "center", justifyContent = "space-between", gap = 6,
        children = {
            NeoButton { text = "上页", variant = "dark", minHeight = 34, flexGrow = 1, flexBasis = 0, fontSize = 12,
                onClick = function() st.rankPage = max(1, st.rankPage - 1); TycoonHud.RefreshRanks() end },
            NeoButton { text = "定位", variant = "cyan", minHeight = 34, flexGrow = 1, flexBasis = 0, fontSize = 12,
                onClick = function()
                    st.rankPage = CalcRankLocatePage(st.lastTycoon)
                    TycoonHud.RefreshRanks()
                end },
            r.rankPageLbl,
            NeoButton { text = "榜首", variant = "primary", minHeight = 34, flexGrow = 1, flexBasis = 0, fontSize = 12,
                onClick = function() st.rankPage = 1; TycoonHud.RefreshRanks() end },
            NeoButton { text = "下页", variant = "dark", minHeight = 34, flexGrow = 1, flexBasis = 0, fontSize = 12,
                onClick = function()
                    local totalPages = max(1, ceil(#Config.RANKS / 5))
                    st.rankPage = min(totalPages, st.rankPage + 1)
                    TycoonHud.RefreshRanks()
                end },
        },
    }
    r.rankGoalDesc = UI.Label { text = "超越 No.1 马斯克称霸世界!", fontSize = 12, fontColor = U.textDim, whiteSpace = "normal", textAlign = "center", width = "100%" }

    local panel = NeoFrame {
        style = "panel", width = "92%", maxWidth = 390, height = 532, padding = 10, gap = 6,
        flexDirection = "column", justifyContent = "space-between",
        children = {
            header, listCol, pageRow,
            NeoFrame { style = "card", width = "100%", padding = 8, flexDirection = "column", children = { r.rankGoalDesc } },
        },
    }
    return MakeModalWrap(panel, true)
end

-- ----------------------------------------------------------------------------
-- 8. 离线收益 / 商业风投空投 / 玩法公式 / 模拟广告播放器 / 转生确认弹窗
-- ----------------------------------------------------------------------------
local function BuildOfflineModal(cb)
    local r = st.refs
    r.offTimeLbl = UI.Label { text = "离开期间推币机持续自动赚钱！", fontSize = 13, fontColor = U.cyan, textAlign = "center" }
    r.offCashLbl = UI.Label { text = "+¥0", fontSize = 28, fontWeight = "bold", fontColor = U.gold, textAlign = "center", textStroke = { width = 2, color = U.strokeDark } }
    local box = NeoFrame {
        style = "panel", width = "88%", maxWidth = 360, padding = 18, gap = 12,
        flexDirection = "column", alignItems = "center",
        children = {
            NeoIcon { kind = "relic", key = "big_pouch", size = 68 },
            UI.Label { text = "离线挂机分红", fontSize = 20, fontWeight = "bold", fontColor = U.gold },
            r.offTimeLbl,
            r.offCashLbl,
            UI.Row {
                width = "100%", gap = 10,
                children = {
                    NeoButton { text = "直接领取", variant = "dark", flexGrow = 1, flexBasis = 0, minHeight = 46,
                        onClick = function() if cb.OnClaimOffline then cb.OnClaimOffline(false) end end },
                    NeoButton { text = "广告×2领", variant = "primary", flexGrow = 1, flexBasis = 0, minHeight = 46,
                        onClick = function() if cb.OnClaimOffline then cb.OnClaimOffline(true) end end },
                },
            },
        },
    }
    return MakeModalWrap(box, false)
end

local function BuildAirdropModal(cb)
    local r = st.refs
    r.airArt = NeoIcon { kind = "event", key = "vault_crack", width = "100%", height = 184 }
    r.airTitle = UI.Label { text = "商业风投空投箱", fontSize = 20, fontWeight = "bold", fontColor = U.gold }
    r.airDesc = UI.Label { text = "", fontSize = 13, fontColor = U.textDim, whiteSpace = "normal", textAlign = "center", width = "100%" }
    local box = NeoFrame {
        style = "panel", width = "90%", maxWidth = 370, padding = 16, gap = 12,
        flexDirection = "column", alignItems = "center",
        children = {
            r.airArt, r.airTitle, r.airDesc,
            UI.Row {
                width = "100%", gap = 10,
                children = {
                    NeoButton { text = "免费领", variant = "dark", flexGrow = 1, flexBasis = 0, minHeight = 46,
                        onClick = function() if cb.OnClaimAirdrop then cb.OnClaimAirdrop(false) end end },
                    NeoButton { text = "广告×5暴富", variant = "primary", flexGrow = 1, flexBasis = 0, minHeight = 46,
                        onClick = function() if cb.OnClaimAirdrop then cb.OnClaimAirdrop(true) end end },
                },
            },
        },
    }
    return MakeModalWrap(box, true)
end

local function BuildFormulaModal()
    local r = st.refs
    r.formMultLbl = UI.Label { text = "", fontSize = 13, fontColor = U.cyan, whiteSpace = "normal", width = "100%" }
    local box = NeoFrame {
        style = "panel", width = "90%", maxWidth = 370, padding = 18, gap = 12,
        flexDirection = "column", alignItems = "center",
        children = {
            UI.Row {
                width = "100%", height = 38, alignItems = "center",
                children = {
                    UI.Label { text = "无脑首富玩法速览", fontSize = 18, fontWeight = "bold", fontColor = U.gold },
                    UI.Spacer(), MakeCloseBtn(function() TycoonHud.CloseModal() end),
                },
            },
            NeoFrame {
                style = "card", width = "100%", padding = 10, flexDirection = "column", gap = 4,
                children = {
                    UI.Label { text = "1. 钱只涨不花直冲世界第1！达标与排名跃升均赠技能点。", fontSize = 13, fontColor = U.text, whiteSpace = "normal", width = "100%" },
                    UI.Label { text = "2. 下方页签亮灯即点：用技能点升机台、解新币、研黑科技。", fontSize = 13, fontColor = U.text, whiteSpace = "normal", width = "100%" },
                    UI.Label { text = "3. 硬币进活动奖门触发3轴抽奖，最高爆100倍倍率与币雨；达标可敲钟上市不清空资产！", fontSize = 13, fontColor = U.text, whiteSpace = "normal", width = "100%" },
                },
            },
            NeoFrame {
                style = "card", width = "100%", padding = 10, flexDirection = "column", gap = 4,
                children = {
                    UI.Label { text = "当前实时收益乘区拆解", fontSize = 14, fontWeight = "bold", fontColor = U.gold },
                    r.formMultLbl,
                },
            },
            NeoButton { text = "知道了", variant = "primary", width = "54%", minWidth = 148, minHeight = 44,
                onClick = function() TycoonHud.CloseModal() end },
        },
    }
    return MakeModalWrap(box, true)
end

local function BuildMockAdModal(cb)
    local r = st.refs
    r.mockIc = NeoIcon { kind = "relic", key = "vip_card", size = 64 }
    r.mockTitle = UI.Label { text = "模拟激励广告播放中", fontSize = 19, fontWeight = "bold", fontColor = U.gold }
    r.mockDesc = UI.Label { text = "", fontSize = 13, fontColor = U.textDim, whiteSpace = "normal", textAlign = "center", width = "100%" }
    r.mockBar = NeoBar { width = "100%", height = 28, value = 0, text = "模拟播放中 2.0s" }
    r.mockClaimBtn = NeoButton {
        text = "请稍候", variant = "green", flexGrow = 1, flexBasis = 0, minHeight = 46,
        onClick = function() if cb.OnMockAdFinish then cb.OnMockAdFinish() end end,
    }
    local box = NeoFrame {
        style = "panel", width = "88%", maxWidth = 360, padding = 18, gap = 12,
        flexDirection = "column", alignItems = "center",
        children = {
            UI.Label { text = "[开发期假广告占位 · 非真实SDK]", fontSize = 12, fontColor = U.magenta },
            r.mockIc, r.mockTitle, r.mockDesc, r.mockBar,
            UI.Row {
                width = "100%", gap = 10,
                children = {
                    NeoButton { text = "放弃关闭", variant = "dark", flexGrow = 1, flexBasis = 0, minHeight = 46,
                        onClick = function() if cb.OnMockAdCancel then cb.OnMockAdCancel() end end },
                    r.mockClaimBtn,
                },
            },
        },
    }
    return MakeModalWrap(box, false)
end

local function BuildConfirmPrestigeModal(cb)
    local r = st.refs
    r.cpDesc = UI.Label { text = "", fontSize = 13, fontColor = U.textDim, whiteSpace = "normal", textAlign = "center", width = "100%" }
    local box = NeoFrame {
        style = "panel", width = "88%", maxWidth = 360, padding = 18, gap = 14,
        flexDirection = "column", alignItems = "center",
        children = {
            NeoIcon { kind = "boss", key = "gatekeeper", size = 60 },
            UI.Label { text = "确认 IPO 上市转生？", fontSize = 19, fontWeight = "bold", fontColor = U.gold },
            r.cpDesc,
            UI.Row {
                width = "100%", gap = 10,
                children = {
                    NeoButton { text = "取消", variant = "dark", flexGrow = 1, flexBasis = 0, minHeight = 46,
                        onClick = function() TycoonHud.OpenModal("prestige") end },
                    NeoButton { text = "确认上市", variant = "primary", flexGrow = 1, flexBasis = 0, minHeight = 46,
                        onClick = function()
                            if cb.OnConfirmPrestige then cb.OnConfirmPrestige(st.prestigeDouble) end
                        end },
                },
            },
        },
    }
    return MakeModalWrap(box, false)
end

-- ----------------------------------------------------------------------------
-- 对外构建与刷新接口
-- ----------------------------------------------------------------------------
function TycoonHud.Build(stageWidget, cb, settingsModal, cloudFailModal)
    st.cb = cb or {}
    st.modals = {}
    st.shown = {}

    local mainPage = BuildMainPage(stageWidget, st.cb)
    st.modals.machine         = BuildMachineModal(st.cb)
    st.modals.coins           = BuildCoinsModal(st.cb)
    st.modals.tech            = BuildTechModal(st.cb)
    st.modals.prestige        = BuildPrestigeModal(st.cb)
    st.modals.welfare         = BuildWelfareModal(st.cb)
    st.modals.ranks           = BuildRanksModal()
    st.modals.offline         = BuildOfflineModal(st.cb)
    st.modals.airdrop         = BuildAirdropModal(st.cb)
    st.modals.formula         = BuildFormulaModal()
    st.modals.mockAd          = BuildMockAdModal(st.cb)
    st.modals.confirmPrestige = BuildConfirmPrestigeModal(st.cb)
    if settingsModal then st.modals.settings = settingsModal end
    if cloudFailModal then st.modals.cloudFail = cloudFailModal end

    local children = { mainPage }
    for _, m in pairs(st.modals) do
        m:SetVisible(false)
        children[#children + 1] = m
    end

    local safe = UI.SafeAreaView {
        width = "100%", height = "100%", nativeMenuInset = true, pointerEvents = "box-none",
        children = children,
    }
    return UI.Panel {
        id = "rootBg", width = "100%", height = "100%",
        pointerEvents = "box-none",
        children = { safe },
    }
end

function TycoonHud.GetCurModal()
    return st.curModal
end

function TycoonHud.OpenModal(name)
    if name == "ranks" and st.lastTycoon then
        st.rankPage = CalcRankLocatePage(st.lastTycoon)
    end
    st.curModal = name
    for k, m in pairs(st.modals) do
        m:SetVisible(k == name)
    end
    TycoonHud.RefreshCurrentModal()
end

function TycoonHud.CloseModal()
    st.curModal = nil
    for _, m in pairs(st.modals) do
        m:SetVisible(false)
    end
end

function TycoonHud.OpenOfflineModal(amt, elapsed)
    st.offlineAmt = amt or 0
    st.offlineSec = elapsed or 0
    local r = st.refs
    SetLbl(r.offTimeLbl, string.format("离线 %s，推币机自动积累了：", Number.FormatClock(elapsed)))
    SetLbl(r.offCashLbl, "+" .. Number.FormatCash(amt))
    TycoonHud.OpenModal("offline")
end

function TycoonHud.GetOfflineAmt() return st.offlineAmt end

function TycoonHud.OpenMockAd(pendingInfo)
    local r = st.refs
    local def = pendingInfo.def
    r.mockIc:SetIcon(def.iconKind, def.iconKey, 1)
    SetLbl(r.mockTitle, def.title)
    SetLbl(r.mockDesc, pendingInfo.extraDesc or def.desc)
    st.mockAdDur = 2.0
    st.mockAdLeft = 2.0
    r.mockBar:SetProgress(0, "模拟广告播放中 2.0s", C.magenta)
    r.mockClaimBtn:SetText("等待中...")
    r.mockClaimBtn:SetDisabled(true)
    TycoonHud.OpenModal("mockAd")
end

function TycoonHud.TickMockAd(dt)
    if st.curModal ~= "mockAd" then return end
    local r = st.refs
    if st.mockAdLeft > 0 then
        st.mockAdLeft = max(0, st.mockAdLeft - dt)
        local p = 1 - (st.mockAdLeft / st.mockAdDur)
        if st.mockAdLeft > 0 then
            r.mockBar:SetProgress(p, string.format("模拟广告 %.1fs", st.mockAdLeft), C.magenta)
        else
            r.mockBar:SetProgress(1, "模拟播放完成! 点击领奖", C.green)
            r.mockClaimBtn:SetText("领取奖励")
            r.mockClaimBtn:SetDisabled(false)
        end
    end
end

function TycoonHud.OpenPrestigeConfirm(isDouble)
    local ty = st.lastTycoon
    if not ty or not ty:CanDoIpo() then return end
    st.prestigeDouble = (isDouble == true)
    local info = ty:GetNextIpoInfo()
    local gain = isDouble and (info.shares * 2) or info.shares
    SetLbl(st.refs.cpDesc, string.format(
        "方案A·不清空任何资产（保留全币种/机台/现金）！\n本次【%s】敲钟可获 +%s 传奇股 与 +%d 技能点！",
        info.name, Number.FormatNum(gain), info.bonusSp or 0
    ))
    TycoonHud.OpenModal("confirmPrestige")
end

function TycoonHud.ShowOvertake(rankDef, info)
    if not rankDef then return end
    local r = st.refs
    if not r.overtakeWrap then return end
    info = info or {}
    local wealthNow = info.wealthNow or rankDef.target or 0
    local spBounty = info.spBounty or info.bounty or rankDef.spBounty or 2
    local jumped = info.jumped or 1

    r.ovAvatar:SetEntry(rankDef, rankDef.isRealName == true, true)
    if rankDef.isRealName then
        local badgeTxt = (jumped > 1)
            and string.format("🏆 晋升世界第 %d 名！（前1000强 · 连超%d档）", rankDef.rank or 1, jumped)
            or string.format("🏆 晋升世界第 %d 名！（前1000强）", rankDef.rank or 1)
        SetLbl(r.ovBadgeLbl, badgeTxt)
        SetLbl(r.ovWealthLbl, "身价突破 " .. Number.FormatCash(wealthNow) .. "！")
        SetLbl(r.ovWhoLbl, "正式超越【" .. (rankDef.name or "富豪") .. "】· " .. (rankDef.title or ""))
    else
        local wrStr = Number.FormatWorldRank(rankDef.rank)
        SetLbl(r.ovBadgeLbl, string.format("🌍 全球排名跃升至前 %s 名！", wrStr))
        SetLbl(r.ovWealthLbl, "个人资产突破 " .. Number.FormatCash(wealthNow) .. "！")
        SetLbl(r.ovWhoLbl, "跻身【" .. (rankDef.name or "新阶层") .. "】· " .. (rankDef.title or ""))
    end
    SetLbl(r.ovQuoteLbl, "“" .. (rankDef.quote or "这推币速度也太离谱了！") .. "”")
    SetLbl(r.ovBountyLbl, string.format("晋升赠礼 +%d 技能点（看广告可×3!）", spBounty))

    st.overtakeBounty = spBounty
    st.overtakeSticky = (rankDef.milestone == true)
    st.overtakeDur = st.overtakeSticky and 999 or 4.8
    st.overtakeLeft = st.overtakeDur
    st.overtakeOpen = true
    r.ovTimerBar:SetProgress(1, st.overtakeSticky and "里程碑盛典（点击收下或×3技能点）" or "", C.gold)
    SetCellVis(r.overtakeWrap, true)
end

function TycoonHud.DismissOvertake()
    st.overtakeOpen = false
    st.overtakeLeft = 0
    SetCellVis(st.refs.overtakeWrap, false)
end

function TycoonHud.TickOvertake(dt)
    if not st.overtakeOpen or st.overtakeSticky then return end
    st.overtakeLeft = max(0, st.overtakeLeft - dt)
    local p = st.overtakeLeft / max(0.1, st.overtakeDur)
    st.refs.ovTimerBar:SetProgress(p, "", C.gold)
    if st.overtakeLeft <= 0 then
        TycoonHud.DismissOvertake()
    end
end

function TycoonHud.RefreshMain(ty)
    if not ty then return end
    st.lastTycoon = ty
    local r, sh = st.refs, st.shown
    local rkTxt = Number.FormatRankBadge(ty:GetWorldRank())
    if sh.rankNo ~= rkTxt then sh.rankNo = rkTxt; SetLbl(r.lblRankNo, rkTxt) end

    local cashTxt = Number.FormatCash(ty.cash)
    if sh.cash ~= cashTxt then sh.cash = cashTxt; SetLbl(r.lblCash, cashTxt) end

    local cpsTxt = Number.FormatCash(ty:GetDisplayCPS()) .. "/秒"
    if sh.cps ~= cpsTxt then sh.cps = cpsTxt; SetLbl(r.lblCps, cpsTxt) end

    local spTxt = "技能点:" .. Number.FormatNum(ty.skillPoints or 0)
    if sh.spTxt ~= spTxt then sh.spTxt = spTxt; SetLbl(r.lblSp, spTxt) end

    local curRk = ty:GetRankDef()
    local nxtRk = Config.RANKS[ty.rankIdx + 1]
    local barRatio, barTxt, barCol
    if nxtRk then
        local span = max(1, nxtRk.target - curRk.target)
        barRatio = floor(max(0, min(1, (ty.lifetimeCash - curRk.target) / span)) * 200 + 0.5) / 200
        barTxt = nxtRk.isRealName
            and ("下位: No." .. tostring(nxtRk.rank) .. " " .. nxtRk.name .. " · " .. Number.FormatCash(nxtRk.target))
            or ("下位: " .. nxtRk.name .. " · " .. Number.FormatCash(nxtRk.target))
        barCol = C.cyan
    else
        barRatio = 1
        barTxt = "★ No.1 超越马斯克 · " .. Number.FormatCash(ty.lifetimeCash)
        barCol = C.gold
    end
    if sh.rankBarTxt ~= barTxt or sh.rankBarRatio ~= barRatio then
        sh.rankBarTxt, sh.rankBarRatio = barTxt, barRatio
        r.rankBar:SetProgress(barRatio, barTxt, barCol)
    end

    local mTxt = "x" .. Number.FormatMul(ty:GetTotalMult())
    if sh.mult ~= mTxt then sh.mult = mTxt; SetLbl(r.lblMult, mTxt) end

    local boostSec = ceil(ty.adBoostLeft or 0)
    local boostTxt = (boostSec > 0) and ("×3 " .. Number.FormatClock(boostSec)) or "×3印钞"
    local boostVar = (boostSec > 0) and "green" or "magenta"
    if sh.boostTxt ~= boostTxt then sh.boostTxt = boostTxt; r.adBoostPill:SetText(boostTxt) end
    if sh.boostVar ~= boostVar then sh.boostVar = boostVar; r.adBoostPill:SetVariant(boostVar) end

    local airVis = (ty.activeAirdrop ~= nil)
    if sh.airVis ~= airVis then sh.airVis = airVis; SetCellVis(r.airdropPill, airVis) end

    -- 哪里亮了点哪里：可买页签立刻点亮对应醒目糖果色
    sh.navVar = sh.navVar or {}
    sh.navTxt = sh.navTxt or {}
    local dots = ty:GetRedDots()
    local navMap = {
        { id = "machine", base = "机台", lit = "primary", n = dots.machine },
        { id = "coins",   base = "币种", lit = "cyan",    n = dots.coins },
        { id = "tech",    base = "科技", lit = "green",   n = dots.tech },
        { id = "prestige",base = "上市", lit = "magenta", n = dots.prestige },
        { id = "welfare", base = "福利", lit = "primary", n = dots.welfare },
    }
    for _, nm in ipairs(navMap) do
        local b = r.navBtns[nm.id]
        local wantVar = (nm.n > 0) and nm.lit or "dark"
        local wantTxt = (nm.n > 0)
            and ((nm.id == "prestige") and "上市!" or (nm.base .. "·" .. tostring(min(99, nm.n))))
            or nm.base
        if sh.navVar[nm.id] ~= wantVar then sh.navVar[nm.id] = wantVar; b:SetVariant(wantVar) end
        if sh.navTxt[nm.id] ~= wantTxt then sh.navTxt[nm.id] = wantTxt; b:SetText(wantTxt) end
    end
end

function TycoonHud.RefreshMachine()
    local ty = st.lastTycoon
    if not ty then return end
    local r = st.refs
    SetLbl(r.machSpLbl, string.format("技能点:%s (¥%s赠)", Number.FormatNum(ty.skillPoints or 0), Number.FormatNum(ty:GetNextSpThreshold())))
    for m, mb in pairs(r.modeBtns) do
        mb:SetVariant((ty.buyMode == m) and "cyan" or "dark")
    end
    for i = 1, 8 do
        local def = Config.MACHINE_UPGRADES[i]
        local slot = r.machCells[i]
        local lv = ty.machineLv[def.id] or 0
        local _, cnt = ty:GetMachineCost(def.id)
        local maxed = (lv >= def.maxLv)
        SetLbl(slot.lv, maxed and "MAX" or ("Lv." .. lv))
        slot.cell.skin_.selected = (i == st.machSel)
        slot.cell.skin_.afford = (not maxed) and (cnt > 0)
        SetCellOp(slot.cell, (maxed or cnt > 0) and 1.0 or 0.72)
    end
    local def = Config.MACHINE_UPGRADES[st.machSel]
    if def then
        local lv = ty.machineLv[def.id] or 0
        local cost, cnt = ty:GetMachineCost(def.id)
        local maxed = (lv >= def.maxLv)
        r.machDetIc:SetIcon("relic", def.relic, 1)
        SetLbl(r.machDetTitle, string.format("%s (Lv.%d/%d)", def.name, lv, def.maxLv))
        SetLbl(r.machDetDesc, def.desc)
        r.machDetBtn:SetText(maxed and "已满级" or (Number.FormatNum(cost) .. "点" .. (cnt > 1 and (" (+" .. cnt .. ")") or "")))
        r.machDetBtn:SetDisabled(maxed or cnt <= 0)
    end
end

function TycoonHud.RefreshCoins()
    local ty = st.lastTycoon
    if not ty then return end
    local r = st.refs
    SetLbl(r.coinCountLbl, string.format("%d/%d", ty:CountUnlockedCoins(), #Config.COIN_TIERS))
    SetLbl(r.coinSpLbl, string.format("技能点:%s (¥%s赠)", Number.FormatNum(ty.skillPoints or 0), Number.FormatNum(ty:GetNextSpThreshold())))
    SetLbl(r.coinPageLbl, st.coinPage .. "/2")
    for i = 1, 12 do
        local slot = r.coinCells[i]
        local idx = (st.coinPage - 1) * 12 + i
        local tier = Config.COIN_TIERS[idx]
        if tier then
            SetCellVis(slot.cell, true)
            local def = Config.COINS[tier.id]
            local lv = ty.coinLv[tier.id] or 0
            local cost, maxed, locked = ty:GetCoinCost(tier.id)
            local canAff = (not maxed) and (not locked) and ((ty.skillPoints or 0) >= cost)
            slot.ic:SetIcon("coin", tier.id, max(1, min(3, floor(lv / 4) + 1)))
            SetLbl(slot.nm, (def and def.short) or tier.id)
            SetLbl(slot.sub, (lv == 0) and (locked and "待前置" or "未解锁") or (maxed and "MAX" or ("Lv." .. lv)))
            slot.sub:SetStyle({ fontColor = (lv == 0) and (canAff and U.gold or U.textDim) or U.cyan })
            slot.cell.skin_.selected = (i == st.coinSel)
            slot.cell.skin_.afford = canAff
            SetCellOp(slot.cell, (lv > 0 or canAff) and 1.0 or (locked and 0.36 or 0.54))
        else
            SetCellVis(slot.cell, false)
        end
    end
    local idx = (st.coinPage - 1) * 12 + st.coinSel
    local tier = Config.COIN_TIERS[idx]
    if tier then
        local def = Config.COINS[tier.id]
        local lv = ty.coinLv[tier.id] or 0
        local cost, maxed, locked = ty:GetCoinCost(tier.id)
        local unitVal = ty:GetCoinUnitValue(tier.id, max(1, lv))
        r.coinDetIc:SetIcon("coin", tier.id, max(1, min(3, floor(lv / 4) + 1)))
        SetLbl(r.coinDetTitle, string.format("%s (%s)", def and def.name or tier.id, lv == 0 and (locked and "需先解前一种币" or "未解锁") or ("Lv." .. lv)))
        SetLbl(r.coinDetDesc, string.format("单枚基值 %s · %s", Number.FormatCash(unitVal), def and def.desc or ""))
        if maxed then
            r.coinDetBtn:SetText("已满级")
        elseif locked then
            r.coinDetBtn:SetText("先解前币")
        else
            r.coinDetBtn:SetText((lv == 0 and "解锁 " or "升级 ") .. Number.FormatNum(cost) .. "点")
        end
        r.coinDetBtn:SetVariant((lv == 0) and "cyan" or "primary")
        r.coinDetBtn:SetDisabled(maxed or locked or ((ty.skillPoints or 0) < cost))
    end
end

function TycoonHud.RefreshTech()
    local ty = st.lastTycoon
    if not ty then return end
    local r = st.refs
    local sp = ty.skillPoints or 0
    SetLbl(r.techSpLbl, string.format("技能点:%s (¥%s赠)", Number.FormatNum(sp), Number.FormatNum(ty:GetNextSpThreshold())))
    local ownedCnt = 0
    for i = 1, 12 do
        local t = Config.TECH_UPGRADES[i]
        local slot = r.techCells[i]
        local owned = ty:HasTech(t.id)
        if owned then ownedCnt = ownedCnt + 1 end
        local canAff = (not owned) and (sp >= t.costSp)
        SetLbl(slot.stLbl, owned and "已研" or (Number.FormatNum(t.costSp) .. "点"))
        slot.stLbl:SetStyle({ fontColor = owned and U.green or (canAff and U.gold or U.textDim) })
        slot.cell.skin_.selected = (i == st.techSel)
        slot.cell.skin_.afford = canAff
        SetCellOp(slot.cell, (owned or canAff) and 1.0 or 0.56)
    end
    SetLbl(r.techCountLbl, ownedCnt .. "/12")
    local t = Config.TECH_UPGRADES[st.techSel]
    if t then
        local owned = ty:HasTech(t.id)
        r.techDetIc:SetIcon("relic", t.relic, 1)
        SetLbl(r.techDetTitle, t.name .. (owned and " (已解锁)" or ""))
        SetLbl(r.techDetDesc, t.desc)
        r.techDetBtn:SetText(owned and "已研发" or ("研发 " .. Number.FormatNum(t.costSp) .. "点"))
        r.techDetBtn:SetDisabled(owned or sp < t.costSp)
    end
end

function TycoonHud.RefreshPrestige()
    local ty = st.lastTycoon
    if not ty then return end
    local r = st.refs
    local info = ty:GetNextIpoInfo()
    local canIpo = ty:CanDoIpo()
    local curMul = ty:GetShareMult()
    SetLbl(r.presSharesLbl, string.format("持有传奇股：%s 股 (全局×%.2f)", Number.FormatNum(ty.prestigeShares), curMul))
    SetLbl(r.presPendLbl, string.format("本轮【%s】：+%s 股 · +%d 技能点", info.name, Number.FormatNum(info.shares), info.bonusSp or 0))
    SetLbl(r.presNextLbl, canIpo and "★ 达标可敲钟！绝不清空财富与已解进度" or ("需总身价 " .. Number.FormatCash(info.targetWealth) .. " · 不清空资产"))
    r.presNormalBtn:SetDisabled(not canIpo)
    r.presAdBtn:SetDisabled(not canIpo)

    for i = 1, 4 do
        local p = Config.PRESTIGE_TALENTS[i]
        local slot = r.talentCells[i]
        local lv = ty.prestigeLv[p.id] or 0
        local cost, maxed = ty:GetTalentCost(p.id)
        local canAff = (not maxed) and (ty.prestigeShares >= cost)
        SetLbl(slot.lv, maxed and "MAX" or string.format("Lv.%d · %s股", lv, Number.FormatNum(cost)))
        slot.cell.skin_.selected = (i == st.talentSel)
        slot.cell.skin_.afford = canAff
    end
    local p = Config.PRESTIGE_TALENTS[st.talentSel]
    if p then
        local lv = ty.prestigeLv[p.id] or 0
        local cost, maxed = ty:GetTalentCost(p.id)
        r.talDetIc:SetIcon("relic", p.relic, 1)
        SetLbl(r.talDetTitle, string.format("%s (Lv.%d/%d)", p.name, lv, p.maxLv))
        SetLbl(r.talDetDesc, p.desc)
        r.talDetBtn:SetText(maxed and "满级" or ("点亮 " .. Number.FormatNum(cost) .. "股"))
        r.talDetBtn:SetDisabled(maxed or ty.prestigeShares < cost)
    end
end

function TycoonHud.RefreshWelfare()
    local ty = st.lastTycoon
    if not ty then return end
    local r = st.refs
    SetLbl(r.welfareCountLbl, string.format("已看 %d 次", ty.adWatchCount or 0))
    for i = 1, 4 do
        local pid = Config.AD_WELFARE_ORDER[i]
        local cd = ty:GetAdCooldown(pid)
        local c = r.adCards[i]
        SetLbl(c.cd, (cd > 0) and ("冷却 " .. Number.FormatClock(cd)) or "点击可领")
        c.cd:SetStyle({ fontColor = (cd > 0) and U.textDim or U.green })
        c.card.skin_.selected = (i == st.welfareSel)
        c.card.skin_.afford = (cd <= 0)
    end
    local pid = Config.AD_WELFARE_ORDER[st.welfareSel]
    local def = pid and Config.AD_PLACEMENTS[pid]
    if def then
        local cd = ty:GetAdCooldown(pid)
        r.adDetIc:SetIcon(def.iconKind, def.iconKey, 1)
        SetLbl(r.adDetTitle, def.title)
        SetLbl(r.adDetDesc, def.desc)
        r.adDetBtn:SetText((cd > 0) and Number.FormatClock(cd) or "看广告领取")
        r.adDetBtn:SetDisabled(cd > 0)
    end
end

function TycoonHud.RefreshRanks()
    local ty = st.lastTycoon
    if not ty then return end
    local r = st.refs
    local totalPages = max(1, ceil(#Config.RANKS / 5))
    st.rankPage = max(1, min(totalPages, st.rankPage or totalPages))
    SetLbl(r.rankPageLbl, st.rankPage .. "/" .. totalPages)
    local myWorldRank = ty:GetWorldRank()
    for i = 1, 5 do
        local displayPos = (st.rankPage - 1) * 5 + i -- 第1页: No.1 马斯克领衔; 末页: 全球匿名起步阶层
        local idx = (#Config.RANKS + 1) - displayPos
        local rk = (idx >= 1 and idx <= #Config.RANKS) and Config.RANKS[idx] or nil
        local slot = r.rankCells[i]
        if rk then
            SetCellVis(slot.cell, true)
            local unlocked = (ty.rankIdx >= idx)
            local isNextTarget = (idx == ty.rankIdx + 1)
            local isCurrent = (idx == ty.rankIdx)
            slot.av:SetEntry(rk, isCurrent and (rk.isRealName == true), unlocked)
            SetLbl(slot.no, rk.isRealName and ("No." .. tostring(rk.rank)) or ("前" .. Number.FormatWorldRank(rk.rank)))
            slot.no:SetStyle({ fontColor = (rk.rank <= 10) and U.gold or (rk.isRealName and U.cyan or U.textDim) })
            SetLbl(slot.nm, rk.name)
            SetLbl(slot.ttl, rk.title or "")
            SetLbl(slot.tg, Number.FormatCash(rk.target))
            local statusStr = isCurrent and "★ 当前" or (unlocked and (rk.isRealName and "已超越" or "已突破") or (isNextTarget and "下一目标!" or "追赶中"))
            local statusCol = isCurrent and U.gold or (unlocked and U.green or (isNextTarget and U.magenta or U.muted))
            SetLbl(slot.stLbl, statusStr)
            slot.stLbl:SetStyle({ fontColor = statusCol })
            slot.cell.skin_.rarity = (rk.rank <= 10) and "legendary" or (rk.isRealName and "epic" or "common")
            slot.cell.skin_.selected = isCurrent or isNextTarget
            SetCellOp(slot.cell, unlocked and 1.0 or (isNextTarget and 0.92 or 0.65))
        else
            SetCellVis(slot.cell, false)
        end
    end
    local top = Config.RANKS[#Config.RANKS]
    local remainTop1 = max(0, top.target - ty.lifetimeCash)
    local top1000Entry = Config.RANKS[Billionaires.TOP1000_START_IDX]
    local remain1000 = top1000Entry and max(0, top1000Entry.target - ty.lifetimeCash) or 0
    if remainTop1 <= 0 then
        SetLbl(r.rankGoalDesc, "恭喜！你已全面超越 No.1 马斯克，登顶全球首富！")
    elseif myWorldRank <= Billionaires.REAL_NAME_CUTOFF then
        SetLbl(r.rankGoalDesc, string.format("当前世界第 %s 名（前1000真名榜）· 距 No.1 马斯克还差 %s",
            Number.FormatWorldRank(myWorldRank), Number.FormatCash(remainTop1)))
    else
        SetLbl(r.rankGoalDesc, string.format("当前世界第 %s 名 · 距进入前1000真名榜还差 %s",
            Number.FormatWorldRank(myWorldRank), Number.FormatCash(remain1000)))
    end
end

function TycoonHud.RefreshAirdrop()
    local ty = st.lastTycoon
    if not ty or not ty.activeAirdrop then return end
    local r = st.refs
    local air = ty.activeAirdrop
    local ev = Config.EVENTS[air.eventId] or Config.EVENTS.vault_crack
    r.airArt:SetIcon("event", ev.id, 1)
    SetLbl(r.airTitle, "风投空投 · " .. ev.name)
    SetLbl(r.airDesc, string.format(
        "免费领 %s，或看广告立即暴富 5 倍（%s + 10 枚高阶币雨）！",
        Number.FormatCash(air.baseCash), Number.FormatCash(max(600, ty:GetDisplayCPS() * 120))
    ))
end

function TycoonHud.RefreshFormula()
    local ty = st.lastTycoon
    if not ty then return end
    local _, d = ty:GetTotalMult()
    SetLbl(st.refs.formMultLbl, string.format(
        "机台全币：×%s   |   黑科技乘区：×%s\n传奇股+基因：×%s   |   连击加成：×%s\n狂欢时刻：×%s   |   幸运老虎机：×%s\n广告×3：×%s   |   合计总倍率：×%s\n下一技能点阈值：%s（可用 %s 点）",
        Number.FormatMul(d.machine), Number.FormatMul(d.tech),
        Number.FormatMul(d.prestige), Number.FormatMul(d.combo),
        Number.FormatMul(d.fever), Number.FormatMul(d.luck or 1),
        Number.FormatMul(d.ad), Number.FormatMul(d.total),
        Number.FormatCash(ty:GetNextSpThreshold()), Number.FormatNum(ty.skillPoints or 0)
    ))
end

function TycoonHud.RefreshCurrentModal()
    local c = st.curModal
    if c == "machine" then TycoonHud.RefreshMachine()
    elseif c == "coins" then TycoonHud.RefreshCoins()
    elseif c == "tech" then TycoonHud.RefreshTech()
    elseif c == "prestige" then TycoonHud.RefreshPrestige()
    elseif c == "welfare" then TycoonHud.RefreshWelfare()
    elseif c == "ranks" then TycoonHud.RefreshRanks()
    elseif c == "airdrop" then TycoonHud.RefreshAirdrop()
    elseif c == "formula" then TycoonHud.RefreshFormula()
    end
end

return TycoonHud
