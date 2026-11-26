-- ============================================================================
-- Widgets.lua  霓虹街机 UI 控件库（全一次建树 + 属性增量刷新）
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("game/Config")
local Skin = require("game/Skin")
local Art = require("game/Art")
local Number = require("game/Number")

local Widgets = {}
local C, U = Skin.C, Skin.UI
local floor, min, max = math.floor, math.min, math.max

local function PickWidget(a, b)
    if type(a) == "table" and a.GetAbsoluteLayout then return a end
    return b
end
Widgets.PickWidget = PickWidget

function Widgets.PressFx(props)
    props.transition = "scale 0.1s easeOut"
    props.onPointerDown = function(a, b)
        local w = PickWidget(a, b)
        if w and not (w.skin_ and w.skin_.disabled) then w:SetStyle({ scale = 0.94 }) end
    end
    props.onPointerUp = function(a, b)
        local w = PickWidget(a, b)
        if w then w:SetStyle({ scale = 1.0 }) end
    end
    props.onPointerLeave = function(a, b)
        local w = PickWidget(a, b)
        if w then w:SetStyle({ scale = 1.0 }) end
    end
    return props
end

-- ----------------------------------------------------------------------------
-- NeoFrame：支持 Skin.TEXTURES 九宫格切片替换的程序化容器
-- ----------------------------------------------------------------------------
local NeoFrame = UI.Panel:Extend("NeoFrame")
Widgets.NeoFrame = NeoFrame

function NeoFrame:Init(props)
    props = props or {}
    self.skinStyle_ = props.style or "panel"
    self.skin_ = props.skin or {}
    props.style, props.skin = nil, nil
    local tex = Skin.TEXTURES[self.skinStyle_]
    if tex then
        props.backgroundImage = tex.image
        props.backgroundFit = "sliced"
        props.backgroundSlice = tex.slice
        self.useTexture_ = true
    end
    UI.Panel.Init(self, props)
end

function NeoFrame:Render(nvg)
    if self.useTexture_ then
        UI.Panel.Render(self, nvg)
        return
    end
    local l = self:GetAbsoluteLayout()
    Skin.Draw(nvg, self.skinStyle_, l.x, l.y, l.w, l.h, self.skin_)
end

-- ----------------------------------------------------------------------------
-- NeoButton：霓虹立体按钮（单行文字不裁剪，按压 0.94 缩放，支持禁用态）
-- ----------------------------------------------------------------------------
local NeoButton = NeoFrame:Extend("NeoButton")
Widgets.NeoButton = NeoButton

function NeoButton:Init(props)
    props = props or {}
    local variant = props.variant or "primary"
    local darkText = (variant == "primary" or variant == "cyan" or variant == "green")
    self.onPress_ = props.onClick
    self.btnLabel_ = UI.Label {
        text = props.text or "",
        fontSize = props.fontSize or 16,
        fontWeight = "bold",
        fontColor = props.fontColor or (darkText and { 14, 16, 32, 255 } or U.text),
        textAlign = "center",
        maxLines = 1,
        flexShrink = 1,
    }
    local selfRef = self
    local fp = {
        style = "button",
        skin = { variant = variant, pressed = false, disabled = false, radius = props.borderRadius or 12 },
        flexDirection = "row",
        justifyContent = "center",
        alignItems = "center",
        minHeight = props.minHeight or 44,
        paddingHorizontal = props.paddingHorizontal or 12,
        paddingBottom = 2,
        width = props.width,
        height = props.height,
        minWidth = props.minWidth,
        maxWidth = props.maxWidth,
        alignSelf = props.alignSelf,
        flexGrow = props.flexGrow,
        flexBasis = props.flexBasis,
        flexShrink = props.flexShrink,
        visible = props.visible,
        children = { self.btnLabel_ },
        transition = "scale 0.1s easeOut",
        onPointerDown = function()
            if selfRef.skin_.disabled then return end
            selfRef.skin_.pressed = true
            selfRef:SetStyle({ scale = 0.94 })
            selfRef.btnLabel_:SetStyle({ translateY = 1.5 })
        end,
        onPointerUp = function() selfRef:Unpress() end,
        onPointerLeave = function() selfRef:Unpress() end,
        onClick = function()
            if selfRef.skin_.disabled then return end
            if selfRef.onPress_ then selfRef.onPress_(selfRef) end
        end,
    }
    NeoFrame.Init(self, fp)
end

function NeoButton:Unpress()
    if not self.skin_.pressed then return end
    self.skin_.pressed = false
    self:SetStyle({ scale = 1.0 })
    self.btnLabel_:SetStyle({ translateY = 0 })
end

function NeoButton:SetText(t)
    if self.btnLabel_.props.text ~= t then
        self.btnLabel_:SetText(t)
    end
end

function NeoButton:SetVariant(v)
    if self.skin_.variant ~= v then
        self.skin_.variant = v
        local darkText = (v == "primary" or v == "cyan" or v == "green")
        self.btnLabel_:SetStyle({ fontColor = darkText and { 14, 16, 32, 255 } or U.text })
    end
end

function NeoButton:SetDisabled(d)
    local b = d == true
    if self.skin_.disabled ~= b then
        self.skin_.disabled = b
        self:SetStyle({ opacity = b and 0.48 or 1.0 })
    end
end

-- ----------------------------------------------------------------------------
-- NeoIcon：绘制硬币 / 通用程序图标 / 遗物图标（支持 Skin.SPRITES 热替换）
-- ----------------------------------------------------------------------------
local NeoIcon = UI.Widget:Extend("NeoIcon")
Widgets.NeoIcon = NeoIcon

function NeoIcon:Init(props)
    props = props or {}
    local sz = props.size or 28
    props.width = props.width or sz
    props.height = props.height or sz
    props.pointerEvents = props.pointerEvents or "none"
    self.iconKind_ = props.kind or "icon"
    self.iconKey_ = props.key or "coin"
    self.iconLv_ = props.level or 1
    self.iconTint_ = props.tint
    props.kind, props.key, props.level, props.tint, props.size = nil, nil, nil, nil, nil
    UI.Widget.Init(self, props)
end

function NeoIcon:SetIcon(kind, key, level, tint)
    self.iconKind_ = kind or self.iconKind_
    self.iconKey_ = key or self.iconKey_
    self.iconLv_ = level or 1
    self.iconTint_ = tint
end

function NeoIcon:Render(nvg)
    local l = self:GetAbsoluteLayout()
    local s = min(l.w, l.h)
    if s <= 0 then return end
    local x = l.x + (l.w - s) * 0.5
    local y = l.y + (l.h - s) * 0.5
    if self.iconKind_ == "coin" then
        Art.DrawCoin(nvg, self.iconKey_, x + s * 0.5, y + s * 0.5, s * 0.44, self.iconLv_, 0.9, 0, false, -1, false)
    elseif self.iconKind_ == "relic" then
        local sp = "relic_" .. tostring(self.iconKey_)
        if not Art.DrawSprite(nvg, sp, x, y, s, s, 1) then
            local def = Config.RELICS[self.iconKey_]
            Art.DrawIcon(nvg, (def and def.icon) or "star", x, y, s, self.iconTint_)
        end
    else
        Art.DrawIcon(nvg, self.iconKey_, x, y, s, self.iconTint_)
    end
end

-- ----------------------------------------------------------------------------
-- NeoBar：目标分进度条（内置文字居左，百分比居中）
-- ----------------------------------------------------------------------------
local NeoBar = UI.Widget:Extend("NeoBar")
Widgets.NeoBar = NeoBar

function NeoBar:Init(props)
    props = props or {}
    self.barVal_ = props.value or 0
    self.barText_ = props.text or ""
    self.barCol_ = props.color or C.cyan
    props.value, props.text, props.color = nil, nil, nil
    props.pointerEvents = "none"
    UI.Widget.Init(self, props)
end

function NeoBar:SetProgress(val, text, col)
    self.barVal_ = max(0, min(1, val or 0))
    if text ~= nil then self.barText_ = text end
    if col ~= nil then self.barCol_ = col end
end

function NeoBar:Render(nvg)
    local l = self:GetAbsoluteLayout()
    if l.w <= 0 or l.h <= 0 then return end
    local r = min(8, l.h * 0.45)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, l.x, l.y, l.w, l.h, r)
    nvgFillColor(nvg, Skin.Col(C.bgInset, 235))
    nvgFill(nvg)
    local fw = (l.w - 4) * self.barVal_
    if fw > 2 then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, l.x + 2, l.y + 2, fw, l.h - 4, max(2, r - 2))
        nvgFillPaint(nvg, nvgLinearGradient(nvg, l.x, l.y, l.x + fw, l.y,
            Skin.Col(self.barCol_ == C.green and { 24, 146, 86 } or { 24, 118, 196 }, 255),
            Skin.Col(self.barVal_ >= 1 and { 218, 138, 18 } or { 164, 52, 168 }, 255)))
        nvgFill(nvg)
    end
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, l.x, l.y, l.w, l.h, r)
    nvgStrokeColor(nvg, Skin.Col(C.border, 210))
    nvgStrokeWidth(nvg, 1.5)
    nvgStroke(nvg)

    if self.barText_ ~= "" then
        nvgFontFace(nvg, "sans")
        nvgFontSize(nvg, 13)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        local tx, ty = l.x + l.w * 0.5, l.y + l.h * 0.5
        nvgFillColor(nvg, Skin.Col(C.bgInset, 245))
        nvgText(nvg, tx - 1.2, ty, self.barText_)
        nvgText(nvg, tx + 1.2, ty, self.barText_)
        nvgText(nvg, tx, ty - 1.2, self.barText_)
        nvgText(nvg, tx, ty + 1.2, self.barText_)
        nvgFillColor(nvg, Skin.Col(C.white, 255))
        nvgText(nvg, tx, ty, self.barText_)
    end
end

Widgets.FormatNum = Number.FormatNum
Widgets.FormatMul = Number.FormatMul

return Widgets
