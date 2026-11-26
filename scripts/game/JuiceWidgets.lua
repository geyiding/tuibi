-- ============================================================================
-- JuiceWidgets.lua  爽感 HUD 控件
--   · FxLayer：全屏顶层特效层（pointerEvents = none），绘制 Fx 的全部屏幕空间特效
--   · CashCounter：顶栏滚动现金计数器（数字滚动追平 + 飞币砸中冲击 + 金光 + 每秒产值）
-- ============================================================================

local UI = require("urhox-libs/UI")
local Skin = require("game/Skin")
local Number = require("game/Number")
local Fx = require("game/Fx")

local C = Skin.C
local Col = Skin.Col
local floor, min, max, sin, abs = math.floor, math.min, math.max, math.sin, math.abs
local OutlinedText, SetAdditive, EstTextW, DrawMiniCoin = Fx.OutlinedText, Fx.SetAdditive, Fx.EstTextW, Fx.DrawMiniCoin

local JuiceWidgets = {}

-- ----------------------------------------------------------------------------
-- FxLayer
-- ----------------------------------------------------------------------------
local FxLayer = UI.Widget:Extend("FxLayer")
JuiceWidgets.FxLayer = FxLayer

function FxLayer:Init(props)
    props = props or {}
    self.fx_ = props.fx
    self.font_ = props.font or "sans"
    self.isModalOpen_ = props.isModalOpen
    props.fx, props.font, props.isModalOpen = nil, nil, nil
    props.position = "absolute"
    props.top = 0
    props.left = 0
    props.width = "100%"
    props.height = "100%"
    props.pointerEvents = "none"
    UI.Widget.Init(self, props)
end

function FxLayer:SetFont(f) self.font_ = f end

function FxLayer:Render(nvg)
    local fx = self.fx_
    if not fx then return end
    local w = (UI.GetWidth and UI.GetWidth()) or 390
    local h = (UI.GetHeight and UI.GetHeight()) or 844
    local modal = self.isModalOpen_ and self.isModalOpen_() or false
    fx:Render(nvg, w, h, self.font_, modal)
end

-- ----------------------------------------------------------------------------
-- CashCounter
-- ----------------------------------------------------------------------------
local CashCounter = UI.Widget:Extend("CashCounter")
JuiceWidgets.CashCounter = CashCounter

local GOLD_GLOW = { 255, 196, 48 }
local CPS_UP = { 120, 255, 170 }

function CashCounter:Init(props)
    props = props or {}
    self.getTy_ = props.getTycoon
    self.getTime_ = props.getTime
    self.fx_ = props.fx
    self.font_ = props.font or "sans"
    props.getTycoon, props.getTime, props.fx, props.font = nil, nil, nil, nil
    props.pointerEvents = props.pointerEvents or "none"
    self.shown_ = -1
    self.txt_ = "¥0"
    self.txtAcc_ = 0
    self.cpsTxt_ = "¥0/秒"
    self.cpsAcc_ = 99
    self.cpsLast_ = 0
    self.cpsUp_ = 0
    self.punch_ = 0
    self.glow_ = 0
    self.spin_ = 0
    self.lastT_ = nil
    UI.Widget.Init(self, props)
end

function CashCounter:SetFont(f) self.font_ = f end

function CashCounter:Render(nvg)
    local l = self:GetAbsoluteLayout()
    if l.w <= 0 or l.h <= 0 then return end
    local ty = self.getTy_ and self.getTy_()
    local fx = self.fx_
    local t = (self.getTime_ and self.getTime_()) or 0
    local dt = self.lastT_ and max(0, min(0.1, t - self.lastT_)) or 0
    self.lastT_ = t

    local actual = ty and ty.cash or 0
    if self.shown_ < 0 or actual < self.shown_ then self.shown_ = actual end
    -- 指数追平：大额入账时肉眼可见地“滚”上去
    local diff = actual - self.shown_
    self.shown_ = self.shown_ + diff * min(1, dt * 7)
    if diff < 0.5 then self.shown_ = actual end

    if fx then
        local hits = fx.cashHits or 0
        if hits > 0 then
            fx.cashHits = 0
            self.punch_ = min(1, self.punch_ + 0.22 + hits * 0.06)
            self.glow_ = 1
            self.spin_ = self.spin_ + hits * 1.6
        end
    end
    if self.punch_ > 0 then self.punch_ = max(0, self.punch_ - dt * 4.5) end
    if self.glow_ > 0 then self.glow_ = max(0, self.glow_ - dt * 2.4) end
    self.spin_ = self.spin_ + dt * 2

    self.txtAcc_ = self.txtAcc_ + dt
    if self.txtAcc_ >= 0.033 or self.txt_ == "¥0" then
        self.txtAcc_ = 0
        self.txt_ = Number.FormatCash(self.shown_)
    end
    self.cpsAcc_ = self.cpsAcc_ + dt
    if ty and self.cpsAcc_ >= 0.25 then
        self.cpsAcc_ = 0
        local cps = ty:GetDisplayCPS()
        if cps > self.cpsLast_ * 1.02 and self.cpsLast_ > 0 then self.cpsUp_ = 1 end
        self.cpsLast_ = cps
        self.cpsTxt_ = Number.FormatCash(cps) .. "/秒"
    end
    if self.cpsUp_ > 0 then self.cpsUp_ = max(0, self.cpsUp_ - dt * 1.2) end

    local h = l.h
    local iconR = min(h * 0.3, 16)
    local ix, iy = l.x + iconR + 2, l.y + h * 0.4
    if fx then fx.ancCashX, fx.ancCashY = ix, iy end

    -- 金光（被飞币砸中时）
    if self.glow_ > 0.02 then
        SetAdditive(nvg, true)
        nvgBeginPath(nvg)
        nvgRect(nvg, l.x - 10, l.y - 6, l.w + 20, h + 12)
        nvgFillPaint(nvg, nvgBoxGradient(nvg, l.x, l.y + 4, l.w * 0.8, h * 0.55, h * 0.3, 18, Col(GOLD_GLOW, floor(110 * self.glow_)), Col(GOLD_GLOW, 0)))
        nvgFill(nvg)
        SetAdditive(nvg, false)
    end

    -- 金币图标（旋转 + 冲击放大）
    local ps = 1 + self.punch_ * 0.35
    DrawMiniCoin(nvg, ix, iy, iconR * ps, self.spin_, 255)

    -- 现金数字
    local tx = ix + iconR + 6
    local avail = l.x + l.w - tx
    local fs = 21 * (1 + self.punch_ * 0.16)
    local tw = EstTextW(self.txt_, fs)
    if tw > avail then fs = fs * avail / tw end
    nvgFontFace(nvg, self.font_)
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFontSize(nvg, fs)
    local col = (self.punch_ > 0.45) and C.white or C.gold
    OutlinedText(nvg, tx, iy, self.txt_, col, 255, 1.6)

    -- 每秒产值（上涨时绿色闪一下 + 上箭头）
    nvgFontSize(nvg, 12)
    local cc = (self.cpsUp_ > 0.05) and CPS_UP or C.cyan
    nvgFillColor(nvg, Col(cc, 255))
    nvgText(nvg, tx, l.y + h * 0.82, self.cpsTxt_)
    if self.cpsUp_ > 0.05 then
        local ax = tx + EstTextW(self.cpsTxt_, 12) + 8
        local ay = l.y + h * 0.82 - self.cpsUp_ * 4
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, ax, ay - 5)
        nvgLineTo(nvg, ax + 5, ay + 2)
        nvgLineTo(nvg, ax - 5, ay + 2)
        nvgClosePath(nvg)
        nvgFillColor(nvg, Col(CPS_UP, floor(255 * min(1, self.cpsUp_ * 2))))
        nvgFill(nvg)
    end
end

return JuiceWidgets
