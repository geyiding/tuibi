-- ============================================================================
-- Hud.lua  主界面（标题页 / 局内三段式 HUD / 三选一奖励弹窗 / 结算弹窗）
--   · 所有控件在 Build() 时一次性建树，后续仅增量改属性（值未变不 set）
--   · 严格遵守 minigame-ui-spec：右上角避让 108px 胶囊区、底栏拇指热区、
--     半透明微暗遮罩保留底层舞台可见、所有多子容器显式写 flexDirection
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("game/Config")
local Skin = require("game/Skin")
local Widgets = require("game/Widgets")
local Number = require("game/Number")
local Roster = require("game/Roster")

local C, U = Skin.C, Skin.UI
local NeoFrame, NeoButton, NeoIcon, NeoBar =
    Widgets.NeoFrame, Widgets.NeoButton, Widgets.NeoIcon, Widgets.NeoBar

local Hud = {}
local st = {
    cb = nil,
    pages = {},
    modals = {},
    refs = {},
    shown = {},
}

local function SetLbl(lbl, txt)
    if lbl and lbl.props.text ~= txt then
        lbl:SetText(txt)
    end
end

-- ----------------------------------------------------------------------------
-- 1. 标题首页（开屏极简清晰，2秒看懂）
-- ----------------------------------------------------------------------------
local function BuildMenuPage(cb)
    local refs = st.refs
    local heroRow = UI.Row {
        width = 240, height = 80, gap = 14, justifyContent = "center", alignItems = "center",
        children = {
            NeoIcon { kind = "coin", key = "thunder", size = 56 },
            NeoIcon { kind = "coin", key = "jackpot7", size = 76 },
            NeoIcon { kind = "coin", key = "bomb", size = 56 },
        },
    }
    refs.menuBest = UI.Label {
        text = "最高记录 0", fontSize = 14, fontWeight = "bold", fontColor = U.gold, textAlign = "center",
    }
    refs.menuDiffBtn = NeoButton {
        text = "难度 1 · 标准", variant = "dark", minHeight = 44, width = "86%", maxWidth = 286,
        onClick = function() if cb.OnOpenDifficulty then cb.OnOpenDifficulty() end end,
    }
    refs.menuContinueBtn = NeoButton {
        text = "继续狂欢", variant = "cyan", minHeight = 48, width = "86%", maxWidth = 286,
        visible = false,
        onClick = function() if cb.OnContinueRun then cb.OnContinueRun() end end,
    }
    refs.menuStartBtn = NeoButton {
        text = "开始狂欢", variant = "primary", minHeight = 54, width = "86%", maxWidth = 286, fontSize = 18,
        onClick = function() if cb.OnStartGame then cb.OnStartGame(false) end end,
    }
    local subRow = UI.Row {
        width = "88%", maxWidth = 294, gap = 8,
        children = {
            NeoButton { text = "每日", variant = "magenta", flexGrow = 1, flexBasis = 0, minHeight = 44, fontSize = 14, paddingHorizontal = 6,
                onClick = function() if cb.OnStartGame then cb.OnStartGame(true) end end },
            NeoButton { text = "图鉴", variant = "dark", flexGrow = 1, flexBasis = 0, minHeight = 44, fontSize = 14, paddingHorizontal = 6,
                onClick = function() if cb.OnOpenCodex then cb.OnOpenCodex() end end },
            NeoButton { text = "设置", variant = "dark", flexGrow = 1, flexBasis = 0, minHeight = 44, fontSize = 14, paddingHorizontal = 6,
                onClick = function() if cb.OnOpenSettings then cb.OnOpenSettings() end end },
        },
    }

    local card = NeoFrame {
        style = "panel", width = "88%", maxWidth = 350, padding = 24, gap = 14,
        flexDirection = "column", alignItems = "center",
        children = {
            UI.Label {
                text = "推币机的狂欢", fontSize = 28, fontWeight = "bold", fontColor = U.gold,
                textAlign = "center", textStroke = { width = 3, color = U.strokeDark },
            },
            UI.Label {
                text = "摆动投币 · 推台瀑布 · 满屏暴击", fontSize = 13, fontColor = U.cyan, textAlign = "center",
            },
            heroRow,
            refs.menuBest,
            refs.menuContinueBtn,
            refs.menuStartBtn,
            refs.menuDiffBtn,
            subRow,
        },
    }

    return UI.Panel {
        width = "100%", height = "100%", position = "absolute", top = 0, left = 0,
        flexDirection = "column", justifyContent = "center", alignItems = "center",
        children = { card },
    }
end

-- ----------------------------------------------------------------------------
-- 2. 局内玩法页（顶部状态栏避让右上 108px 胶囊 + 中间舞台 + 底部拇指操作区）
-- ----------------------------------------------------------------------------
local function BuildPlayPage(stageWidget, cb)
    local refs = st.refs
    refs.lblStage = UI.Label { text = "1-1", fontSize = 14, fontWeight = "bold", fontColor = U.cyan, maxLines = 1 }
    refs.lblHeart = UI.Label { text = "5", fontSize = 15, fontWeight = "bold", fontColor = U.red, maxLines = 1 }
    refs.lblTicket = UI.Label { text = "24", fontSize = 15, fontWeight = "bold", fontColor = U.gold, maxLines = 1 }

    local gearBtn = NeoFrame(Widgets.PressFx {
        style = "slot", width = 44, height = 44,
        flexDirection = "row", justifyContent = "center", alignItems = "center",
        children = { NeoIcon { kind = "icon", key = "gear", size = 20 } },
        onClick = function() if cb.OnOpenSettings then cb.OnOpenSettings() end end,
    })

    local row1 = UI.Row {
        width = "100%", height = 44, alignItems = "center", paddingLeft = 10, paddingRight = 108, gap = 8,
        children = {
            NeoFrame {
                style = "slot", height = 32, paddingHorizontal = 8,
                flexDirection = "row", alignItems = "center",
                children = { refs.lblStage },
            },
            UI.Row {
                flexDirection = "row", alignItems = "center", gap = 3,
                children = { NeoIcon { kind = "icon", key = "heart", size = 18 }, refs.lblHeart },
            },
            UI.Row {
                flexDirection = "row", alignItems = "center", gap = 3,
                children = { NeoIcon { kind = "icon", key = "coin", size = 18 }, refs.lblTicket },
            },
            UI.Spacer(),
            gearBtn,
        },
    }

    refs.scoreBar = NeoBar { flexGrow = 1, flexBasis = 0, height = 30, value = 0, text = "0 / 35万" }
    refs.lblMult = UI.Label {
        text = "x1.0", fontSize = 14, fontWeight = "bold", fontColor = U.magenta,
        maxLines = 1, textAlign = "center",
    }
    local multPill = NeoFrame {
        style = "slot", height = 30, minWidth = 72, paddingHorizontal = 8,
        flexDirection = "row", justifyContent = "center", alignItems = "center",
        children = { refs.lblMult },
    }

    local row2 = UI.Row {
        width = "100%", height = 34, alignItems = "center", paddingHorizontal = 10, gap = 8,
        children = { refs.scoreBar, multPill },
    }

    local topPlate = NeoFrame {
        style = "plate", width = "100%", height = 84, flexDirection = "column",
        paddingTop = 2, gap = 2,
        children = { row1, row2 },
    }

    -- 底部拇指热区：Next-3 预览 + 超大投币主按钮 + 自动 + 仓
    refs.nextIcons = {}
    for i = 1, 3 do
        refs.nextIcons[i] = NeoIcon { kind = "coin", key = "gold", size = (i == 1) and 30 or 22 }
    end
    refs.lblAmmo = UI.Label {
        text = "x20", fontSize = 15, fontWeight = "bold", fontColor = U.gold, maxLines = 1,
    }
    local queueBox = NeoFrame {
        style = "slot", height = 52, paddingHorizontal = 8, gap = 4,
        flexDirection = "row", alignItems = "center",
        children = { refs.nextIcons[1], refs.nextIcons[2], refs.nextIcons[3], refs.lblAmmo },
    }

    refs.dropBtn = NeoButton {
        text = "投币", variant = "primary", flexGrow = 1, flexBasis = 0, minHeight = 52, fontSize = 18,
        onClick = function() if cb.OnDropCoin then cb.OnDropCoin() end end,
    }
    refs.autoBtn = NeoButton {
        text = "自动", variant = "dark", minWidth = 60, minHeight = 52, fontSize = 14,
        onClick = function() if cb.OnToggleAuto then cb.OnToggleAuto() end end,
    }
    refs.deckBtn = NeoButton {
        text = "仓", variant = "cyan", minWidth = 48, minHeight = 52, fontSize = 14,
        onClick = function() if cb.OnOpenDeck then cb.OnOpenDeck() end end,
    }

    local bottomBar = NeoFrame {
        style = "cloth", width = "100%", height = 74, paddingHorizontal = 10,
        flexDirection = "row", alignItems = "center", gap = 8,
        children = { queueBox, refs.dropBtn, refs.autoBtn, refs.deckBtn },
    }

    return UI.Panel {
        width = "100%", height = "100%", position = "absolute", top = 0, left = 0,
        flexDirection = "column",
        children = { topPlate, stageWidget, bottomBar },
    }
end

-- ----------------------------------------------------------------------------
-- 3. 战后三选一奖励弹窗（一次创建，重复 Open/Refresh）
-- ----------------------------------------------------------------------------
local function BuildRewardModal(cb)
    local refs = st.refs
    refs.rewardCards = {}
    local cardNodes = {}
    for i = 1, 3 do
        local icon = NeoIcon { kind = "coin", key = "gold", size = 56 }
        local name = UI.Label { text = "金币", fontSize = 15, fontWeight = "bold", fontColor = U.text, maxLines = 1, textAlign = "center" }
        local fam = UI.Label { text = "财富", fontSize = 12, fontColor = U.cyan, maxLines = 1, textAlign = "center" }
        local desc = UI.Label {
            text = "", fontSize = 12, fontColor = U.textDim,
            whiteSpace = "normal", textAlign = "center", width = "100%", maxLines = 3,
        }
        local card = NeoFrame(Widgets.PressFx {
            style = "card", skin = { rarity = "common" },
            flexGrow = 1, flexBasis = 0, minHeight = 166, padding = 8, gap = 6,
            flexDirection = "column", alignItems = "center", justifyContent = "flex-start",
            children = { icon, name, fam, desc },
            onClick = function() if cb.OnPickReward then cb.OnPickReward(i) end end,
        })
        refs.rewardCards[i] = { card = card, icon = icon, name = name, fam = fam, desc = desc }
        cardNodes[i] = card
    end

    refs.rewardSub = UI.Label {
        text = "过关! 选择1枚加入投币仓", fontSize = 13, fontColor = U.cyan, textAlign = "center",
    }
    local skipBtn = NeoButton {
        text = "跳过 +10券", variant = "dark", width = "54%", minWidth = 148, minHeight = 44, alignSelf = "center",
        onClick = function() if cb.OnSkipReward then cb.OnSkipReward() end end,
    }

    local box = NeoFrame {
        style = "panel", width = "92%", maxWidth = 390, padding = 16, gap = 12,
        flexDirection = "column", alignItems = "center",
        children = {
            UI.Label { text = "战利品三选一", fontSize = 20, fontWeight = "bold", fontColor = U.gold },
            refs.rewardSub,
            UI.Row { width = "100%", gap = 8, children = cardNodes },
            skipBtn,
        },
    }

    local ov = UI.Panel {
        width = "100%", height = "100%", position = "absolute", top = 0, left = 0,
        backgroundColor = U.overlay, visible = false, pointerEvents = "auto",
        flexDirection = "column", justifyContent = "center", alignItems = "center",
        children = { box },
    }
    return ov
end

-- ----------------------------------------------------------------------------
-- 4. 结算弹窗（胜利可进无尽，失败一键再来）
-- ----------------------------------------------------------------------------
local function BuildResultModal(cb)
    local refs = st.refs
    refs.resTitle = UI.Label { text = "狂欢落幕", fontSize = 24, fontWeight = "bold", fontColor = U.gold }
    refs.resScore = UI.Label { text = "总分 0", fontSize = 22, fontWeight = "bold", fontColor = U.cyan }
    refs.resDetail = UI.Label {
        text = "", fontSize = 14, fontColor = U.textDim, whiteSpace = "normal", textAlign = "center", width = "100%",
    }
    refs.resEndlessBtn = NeoButton {
        text = "无尽模式", variant = "magenta", flexGrow = 1, flexBasis = 0, minHeight = 48,
        onClick = function() if cb.OnEndless then cb.OnEndless() end end,
    }
    refs.resRestartBtn = NeoButton {
        text = "再来一局", variant = "primary", flexGrow = 1, flexBasis = 0, minHeight = 48,
        onClick = function() if cb.OnRestart then cb.OnRestart() end end,
    }
    refs.resMenuBtn = NeoButton {
        text = "回主菜单", variant = "dark", width = "52%", minWidth = 148, minHeight = 44, alignSelf = "center",
        onClick = function() if cb.OnBackMenu then cb.OnBackMenu() end end,
    }

    local box = NeoFrame {
        style = "panel", width = "88%", maxWidth = 360, padding = 20, gap = 14,
        flexDirection = "column", alignItems = "center",
        children = {
            refs.resTitle,
            refs.resScore,
            refs.resDetail,
            UI.Row { width = "100%", gap = 10, children = { refs.resEndlessBtn, refs.resRestartBtn } },
            refs.resMenuBtn,
        },
    }

    return UI.Panel {
        width = "100%", height = "100%", position = "absolute", top = 0, left = 0,
        backgroundColor = U.overlay, visible = false, pointerEvents = "auto",
        flexDirection = "column", justifyContent = "center", alignItems = "center",
        children = { box },
    }
end

-- ----------------------------------------------------------------------------
-- 对外构建与刷新接口
-- ----------------------------------------------------------------------------
function Hud.Build(stageWidget, cb, extraPages, extraModals)
    st.cb = cb or {}
    st.pages = {}
    st.modals = {}
    st.shown = {}

    st.pages.menu = BuildMenuPage(st.cb)
    st.pages.play = BuildPlayPage(stageWidget, st.cb)
    if extraPages then
        for k, v in pairs(extraPages) do st.pages[k] = v end
    end

    st.modals.reward = BuildRewardModal(st.cb)
    st.modals.result = BuildResultModal(st.cb)
    if extraModals then
        for k, v in pairs(extraModals) do st.modals[k] = v end
    end

    local safeChildren = {}
    for _, p in pairs(st.pages) do
        p:SetVisible(false)
        safeChildren[#safeChildren + 1] = p
    end
    for _, m in pairs(st.modals) do
        m:SetVisible(false)
        safeChildren[#safeChildren + 1] = m
    end

    local safe = UI.SafeAreaView {
        width = "100%", height = "100%", nativeMenuInset = true, pointerEvents = "box-none",
        children = safeChildren,
    }

    -- 最外层全屏暗色底板（确保 SafeAreaView 之外不露白底）
    local root = UI.Panel {
        id = "rootBg",
        width = "100%", height = "100%",
        backgroundColor = U.bgDeep,
        pointerEvents = "box-none",
        children = { safe },
    }
    return root
end

function Hud.ShowPage(name)
    for k, p in pairs(st.pages) do
        p:SetVisible(k == name)
    end
end

function Hud.SetModalVisible(name, vis)
    local m = st.modals[name]
    if m then m:SetVisible(vis == true) end
end

function Hud.CloseAllModals()
    for _, m in pairs(st.modals) do
        m:SetVisible(false)
    end
end

function Hud.RefreshMenu(profile, hasContinue)
    local r = st.refs
    local best = (profile and profile.records and profile.records.bestScore) or 0
    SetLbl(r.menuBest, "最高记录 " .. Number.FormatNum(best))
    local d = (profile and profile.difficulty) or 1
    local diffCfg = Config.DIFFICULTY[d] or Config.DIFFICULTY[1]
    r.menuDiffBtn:SetText("难度 " .. d .. " · " .. diffCfg.name)
    r.menuContinueBtn:SetVisible(hasContinue == true)
end

function Hud.RefreshPlay(run)
    if not run then return end
    local r, sh = st.refs, st.shown
    local stageTxt = run.endless and ("无尽 " .. run.endlessWave) or (run.act .. "-" .. run.layer)
    if sh.stage ~= stageTxt then
        sh.stage = stageTxt
        SetLbl(r.lblStage, stageTxt)
    end
    local hTxt = tostring(run.hearts)
    if sh.hearts ~= hTxt then
        sh.hearts = hTxt
        SetLbl(r.lblHeart, hTxt)
    end
    local tTxt = tostring(run.tickets)
    if sh.tickets ~= tTxt then
        sh.tickets = tTxt
        SetLbl(r.lblTicket, tTxt)
    end
    local sRatio = run.score / math.max(1, run.targetScore)
    local barTxt = Number.FormatNum(run.score) .. " / " .. Number.FormatNum(run.targetScore)
    r.scoreBar:SetProgress(sRatio, barTxt, run.goalMet and C.green or (run.feverActive and C.magenta or C.cyan))

    local mTxt = "x" .. Number.FormatMul(run:GetEffectiveMult())
    if sh.mult ~= mTxt then
        sh.mult = mTxt
        SetLbl(r.lblMult, mTxt)
    end
    local aTxt = "x" .. tostring(run.ammoLeft)
    if sh.ammo ~= aTxt then
        sh.ammo = aTxt
        SetLbl(r.lblAmmo, aTxt)
    end

    local nextList = run:PeekNextCoins(3)
    for i = 1, 3 do
        local e = nextList[i]
        if e then
            r.nextIcons[i]:SetIcon("coin", e.kind, e.level)
        end
    end

    r.autoBtn:SetVariant(run.autoDrop and "green" or "dark")
    r.dropBtn:SetDisabled(run.ammoLeft <= 0)
end

function Hud.OpenReward(run)
    local r = st.refs
    local sum = run.lastSummary
    local txt = sum and (sum.cleared and string.format("过关奖励 +%d券 (含利息+%d)", sum.earnedTickets, sum.interest)
        or string.format("未达标 -%d心，仍获 %d券", sum.heartLoss, sum.earnedTickets))
        or "选择1枚硬币加入投币仓"
    SetLbl(r.rewardSub, txt)

    for i = 1, 3 do
        local item = run.rewards[i]
        local slot = r.rewardCards[i]
        if item then
            local info = Roster.Resolve(item.kind, item.level)
            local fam = Config.FAMILIES[info.family]
            slot.card.skin_.rarity = info.rarity
            slot.icon:SetIcon("coin", item.kind, item.level)
            SetLbl(slot.name, info.def.short or info.name)
            SetLbl(slot.fam, (fam and fam.name or "") .. " · 筹码" .. info.baseChips)
            SetLbl(slot.desc, info.def.desc or "")
            slot.card:SetVisible(true)
        else
            slot.card:SetVisible(false)
        end
    end
    Hud.SetModalVisible("reward", true)
end

function Hud.OpenResult(run, won)
    local r = st.refs
    SetLbl(r.resTitle, won and "全三幕制霸!" or "狂欢落幕")
    SetLbl(r.resScore, "总分 " .. Number.FormatNum(run.totalScore))
    SetLbl(r.resDetail, string.format(
        "通过 %d 关 · 最高单次 %s\n最高连击 %dx · 狂欢 %d 次",
        run.levelsCleared, Number.FormatNum(run.bestHit), run.maxCombo, run.feversTriggered
    ))
    r.resEndlessBtn:SetVisible(won == true and not run.daily)
    Hud.SetModalVisible("result", true)
end

function Hud.GetRefs() return st.refs end
function Hud.GetPages() return st.pages end
function Hud.GetModals() return st.modals end

return Hud
