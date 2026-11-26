-- ============================================================================
-- SettingsHud.lua  总设置（声音/双端存档时间与失败提示/兑换码）+ 防覆盖弹窗
--   · 严格遵守 save-architecture.md 与 minigame-ui-spec
-- ============================================================================

local UI = require("urhox-libs/UI")
local Skin = require("game/Skin")
local Widgets = require("game/Widgets")

local C, U = Skin.C, Skin.UI
local NeoFrame, NeoButton, NeoIcon = Widgets.NeoFrame, Widgets.NeoButton, Widgets.NeoIcon

local SettingsHud = {}
local st = { cb = nil, modals = {}, refs = {}, codeText = "" }

local function SetLbl(lbl, t)
    if lbl and lbl.props.text ~= t then lbl:SetText(t) end
end

local function BuildSettingsModal(cb)
    local r = st.refs
    local closeBtn = NeoButton {
        text = "×", style = "slot", width = 38, minWidth = 38, height = 38, minHeight = 38, paddingHorizontal = 0, fontSize = 18,
        onClick = function() if cb.OnCloseSettings then cb.OnCloseSettings() end end,
    }
    local header = UI.Row {
        width = "100%", height = 40, alignItems = "center",
        children = {
            NeoIcon { kind = "icon", key = "gear", size = 22 },
            UI.Label { text = "游戏设置", fontSize = 18, fontWeight = "bold", fontColor = U.gold, marginLeft = 6 },
            UI.Spacer(),
            closeBtn,
        },
    }

    -- 1. 声音与偏好开关
    r.togMusic = UI.Toggle {
        label = "背景音乐", value = true,
        onChange = function(_, v) if cb.OnToggleMusic then cb.OnToggleMusic(v) end end,
    }
    r.togSfx = UI.Toggle {
        label = "游戏音效", value = true,
        onChange = function(_, v) if cb.OnToggleSfx then cb.OnToggleSfx(v) end end,
    }
    r.togHaptic = UI.Toggle {
        label = "震动反馈", value = true,
        onChange = function(_, v) if cb.OnToggleHaptic then cb.OnToggleHaptic(v) end end,
    }
    local audioCard = NeoFrame {
        style = "card", width = "100%", padding = 10, gap = 8,
        flexDirection = "column",
        children = {
            UI.Row { width = "100%", justifyContent = "space-between", alignItems = "center", children = { r.togMusic, r.togSfx } },
            UI.Row { width = "100%", alignItems = "center", children = { r.togHaptic } },
        },
    }

    -- 2. 双端存档（展示自动周期、实际本地/云端时间或红字「保存失败」）
    r.lblLocalTime = UI.Label { text = "未保存", fontSize = 12, fontWeight = "bold", fontColor = U.cyan, maxLines = 1 }
    r.lblCloudTime = UI.Label { text = "离线模式", fontSize = 12, fontWeight = "bold", fontColor = U.cyan, maxLines = 1 }
    r.saveBtn = NeoButton {
        text = "保存游戏", variant = "primary", flexGrow = 1, flexBasis = 0, minHeight = 42, fontSize = 14,
        onClick = function() if cb.OnManualSave then cb.OnManualSave() end end,
    }
    r.loadCloudBtn = NeoButton {
        text = "读取云档", variant = "cyan", flexGrow = 1, flexBasis = 0, minHeight = 42, fontSize = 14,
        onClick = function() if cb.OnManualLoadCloud then cb.OnManualLoadCloud() end end,
    }

    local saveCard = NeoFrame {
        style = "card", width = "100%", padding = 10, gap = 6,
        flexDirection = "column",
        children = {
            UI.Label { text = "自动：本地30秒 · 云120秒", fontSize = 12, fontColor = U.textDim },
            UI.Row {
                width = "100%", alignItems = "center",
                children = { UI.Label { text = "本地存档：", fontSize = 12, fontColor = U.text }, UI.Spacer(), r.lblLocalTime },
            },
            UI.Row {
                width = "100%", alignItems = "center",
                children = { UI.Label { text = "云端存档：", fontSize = 12, fontColor = U.text }, UI.Spacer(), r.lblCloudTime },
            },
            UI.Row { width = "100%", gap = 8, children = { r.saveBtn, r.loadCloudBtn } },
        },
    }

    -- 3. 兑换码区
    r.codeField = UI.TextField {
        placeholder = "输入兑换码 (如 CARNIVAL2026)", flexGrow = 1, flexBasis = 0, height = 40, fontSize = 13,
        onChange = function(_, v) st.codeText = v or "" end,
    }
    r.redeemBtn = NeoButton {
        text = "兑换", variant = "magenta", minWidth = 74, minHeight = 40, fontSize = 14,
        onClick = function()
            if cb.OnRedeemCode then cb.OnRedeemCode(st.codeText) end
        end,
    }
    r.redeemStatus = UI.Label { text = "输入礼包码领取金券与特殊币", fontSize = 12, fontColor = U.textDim, maxLines = 1 }
    local codeCard = NeoFrame {
        style = "card", width = "100%", padding = 10, gap = 6,
        flexDirection = "column",
        children = {
            UI.Row { width = "100%", gap = 8, alignItems = "center", children = { r.codeField, r.redeemBtn } },
            r.redeemStatus,
        },
    }

    -- 4. 旅程控制
    r.quitRunBtn = NeoButton {
        text = "保存回标题", variant = "dark", width = "54%", minWidth = 148, minHeight = 44, alignSelf = "center",
        onClick = function() if cb.OnSaveAndQuitRun then cb.OnSaveAndQuitRun() end end,
    }

    local frame = NeoFrame {
        style = "panel", width = "92%", maxWidth = 385, height = 516, padding = 14, gap = 10,
        flexDirection = "column", justifyContent = "space-between",
        children = { header, audioCard, saveCard, codeCard, r.quitRunBtn },
    }

    return UI.Panel {
        width = "100%", height = "100%", position = "absolute", top = 0, left = 0,
        backgroundColor = U.overlay, visible = false, pointerEvents = "auto",
        flexDirection = "column", justifyContent = "center", alignItems = "center",
        children = { frame },
    }
end

-- 换设备无本地档且云读失败/超时防覆盖弹窗（点遮罩不关闭）
local function BuildCloudFailModal(cb)
    local r = st.refs
    r.cloudFailMsg = UI.Label {
        text = "检测到账号可能有云端存档，但本次读取失败或超时。\n直接开始新档将可能覆盖原有进度！",
        fontSize = 13, fontColor = U.textDim, whiteSpace = "normal", textAlign = "center", width = "100%",
    }
    local freshBtn = NeoButton {
        text = "开始新档", variant = "danger", flexGrow = 1, flexBasis = 0, minHeight = 46,
        onClick = function() if cb.OnCloudConfirmFresh then cb.OnCloudConfirmFresh() end end,
    }
    local retryBtn = NeoButton {
        text = "重试读取", variant = "primary", flexGrow = 1, flexBasis = 0, minHeight = 46,
        onClick = function() if cb.OnCloudRetry then cb.OnCloudRetry() end end,
    }
    local frame = NeoFrame {
        style = "panel", width = "88%", maxWidth = 360, padding = 18, gap = 14,
        flexDirection = "column", alignItems = "center",
        children = {
            NeoIcon { kind = "icon", key = "shield", size = 48, tint = C.red },
            UI.Label { text = "云存档读取失败", fontSize = 19, fontWeight = "bold", fontColor = U.red },
            r.cloudFailMsg,
            UI.Row { width = "100%", gap = 10, children = { freshBtn, retryBtn } },
        },
    }
    return UI.Panel {
        width = "100%", height = "100%", position = "absolute", top = 0, left = 0,
        backgroundColor = U.overlay, visible = false, pointerEvents = "auto",
        flexDirection = "column", justifyContent = "center", alignItems = "center",
        children = { frame },
    }
end

function SettingsHud.BuildModals(cb)
    st.cb = cb
    st.modals.settings = BuildSettingsModal(cb)
    st.modals.cloudFail = BuildCloudFailModal(cb)
    return st.modals
end

function SettingsHud.Refresh(prefs, saveStatus, inRun)
    local r = st.refs
    if prefs then
        if r.togMusic.SetValue then r.togMusic:SetValue(prefs.music ~= false) end
        if r.togSfx.SetValue then r.togSfx:SetValue(prefs.sfx ~= false) end
        if r.togHaptic.SetValue then r.togHaptic:SetValue(prefs.haptic ~= false) end
    end
    if saveStatus then
        SetLbl(r.lblLocalTime, saveStatus.localText)
        r.lblLocalTime:SetStyle({ fontColor = saveStatus.localFailed and U.red or U.cyan })
        SetLbl(r.lblCloudTime, saveStatus.saving and "正在保存…" or saveStatus.cloudText)
        r.lblCloudTime:SetStyle({ fontColor = saveStatus.cloudFailed and U.red or U.cyan })
        r.saveBtn:SetDisabled(saveStatus.saving == true)
    end
    r.quitRunBtn:SetVisible(inRun == true)
end

function SettingsHud.SetRedeemFeedback(ok, msg)
    local r = st.refs
    SetLbl(r.redeemStatus, msg or "")
    r.redeemStatus:SetStyle({ fontColor = ok and U.green or U.red })
end

function SettingsHud.SetCloudFailReason(reason)
    SetLbl(st.refs.cloudFailMsg, (reason and (reason .. "\n") or "") .. "直接开始新档可能覆盖云端原有进度，建议重试读取。")
end

return SettingsHud
