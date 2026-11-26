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
local OutlinedText, SetAdditive, DrawMiniCoin = Fx.OutlinedText, Fx.SetAdditive, Fx.DrawMiniCoin

--- 精细位宽估算（逗号/小数点较窄，避免长串个位数字被过度压缩）
local function EstExactW(s, fs)
    local w = 0
    local i, n = 1, #s
    while i <= n do
        local b = s:byte(i)
        if b == 44 or b == 46 then
            w = w + fs * 0.30
            i = i + 1
        elseif b < 128 then
            w = w + fs * 0.56
            i = i + 1
        else
            w = w + fs
            if b >= 240 then i = i + 4 elseif b >= 224 then i = i + 3 else i = i + 2 end
        end
    end
    return w
end

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

function CashCounter:ResetDisplay()
    self.shown_ = -1
    self.txt_ = "¥0"
    self.txtAcc_ = 1
    self.cpsTxt_ = "¥0/秒"
    self.cpsAcc_ = 99
    self.cpsLast_ = 0
    self.cpsUp_ = 0
    self.punch_ = 0
    self.glow_ = 0
    self.lastT_ = nil
end

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

    -- 金币图标 + 现金数字 + 每秒产值（裁剪在控件区域内，长串数字自适应缩字号不溢出）
    nvgSave(nvg)
    nvgIntersectScissor(nvg, l.x, l.y, l.w, l.h)

    -- 金币图标（旋转 + 冲击放大）
    local ps = 1 + self.punch_ * 0.35
    DrawMiniCoin(nvg, ix, iy, iconR * ps, self.spin_, 255)

    -- 现金数字
    local tx = ix + iconR + 6
    local avail = max(40, l.x + l.w - tx - 4)
    local fs = 21 * (1 + self.punch_ * 0.16)
    local tw = EstExactW(self.txt_, fs)
    if tw > avail then fs = fs * avail / tw end
    nvgFontFace(nvg, self.font_)
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFontSize(nvg, fs)
    local col = (self.punch_ > 0.45) and C.white or C.gold
    OutlinedText(nvg, tx, iy, self.txt_, col, 255, 1.6)

    -- 每秒产值（上涨时绿色闪一下 + 上箭头）
    local cpsFs = 12
    local cpsAvail = max(36, avail - 14)
    local cpsW = EstExactW(self.cpsTxt_, cpsFs)
    if cpsW > cpsAvail then cpsFs = cpsFs * cpsAvail / cpsW end
    nvgFontSize(nvg, cpsFs)
    local cc = (self.cpsUp_ > 0.05) and CPS_UP or C.cyan
    nvgFillColor(nvg, Col(cc, 255))
    nvgText(nvg, tx, l.y + h * 0.82, self.cpsTxt_)
    if self.cpsUp_ > 0.05 then
        local ax = tx + min(cpsAvail, cpsW) + 8
        local ay = l.y + h * 0.82 - self.cpsUp_ * 4
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, ax, ay - 5)
        nvgLineTo(nvg, ax + 5, ay + 2)
        nvgLineTo(nvg, ax - 5, ay + 2)
        nvgClosePath(nvg)
        nvgFillColor(nvg, Col(CPS_UP, floor(255 * min(1, self.cpsUp_ * 2))))
        nvgFill(nvg)
    end
    nvgRestore(nvg)
end

-- ----------------------------------------------------------------------------
-- RankTicker：顶栏实时世界排名（里程表式逐位滚动：59亿8326万 → 3826万4512 → 4512 → 1）
--   · 显示值在对数空间追随真实排名，数字持续往下滚；变化的那一位从下方滑入、旧数字向上滑出
--   · 超越演出交错瞬间被“砸”：放大 + 金光 + 绿色上升箭头
-- ----------------------------------------------------------------------------
local RankLadder = require("game/RankLadder")
local Billionaires = require("game/Billionaires")
local log, exp = math.log, math.exp

local RankTicker = UI.Widget:Extend("RankTicker")
JuiceWidgets.RankTicker = RankTicker

local TICK_BG_TOP = { 26, 20, 52 }
local TICK_BG_BOT = { 10, 8, 24 }
local ROLL_DUR = 0.14

function RankTicker:Init(props)
    props = props or {}
    self.getTy_ = props.getTycoon
    self.getTime_ = props.getTime
    self.fx_ = props.fx
    self.font_ = props.font or "sans"
    props.getTycoon, props.getTime, props.fx, props.font = nil, nil, nil, nil
    self.shownLog_ = nil
    self.txt_ = ""
    self.chars_ = {}
    self.prevChars_ = {}
    self.changeT_ = {}
    self.fmtAcc_ = 1
    self.punch_ = 0
    self.up_ = 0
    self.lastT_ = nil
    UI.Widget.Init(self, props)
end

function RankTicker:SetFont(f) self.font_ = f end

function RankTicker:ResetDisplay()
    self.shownLog_ = nil
    self.txt_ = ""
    self.chars_ = {}
    self.prevChars_ = {}
    self.changeT_ = {}
    self.fmtAcc_ = 1
    self.punch_ = 0
    self.up_ = 0
    self.lastT_ = nil
end

local function SplitChars(s, out)
    local n = 0
    for _, c in utf8.codes(s) do
        n = n + 1
        out[n] = utf8.char(c)
    end
    for i = n + 1, #out do out[i] = nil end
    return n
end

function RankTicker:Render(nvg)
    local l = self:GetAbsoluteLayout()
    if l.w <= 0 or l.h <= 0 then return end
    local ty = self.getTy_ and self.getTy_()
    local fx = self.fx_
    local t = (self.getTime_ and self.getTime_()) or 0
    local dt = self.lastT_ and max(0, min(0.1, t - self.lastT_)) or 0
    self.lastT_ = t

    local actual = ty and Billionaires.CalcWorldRank(ty.lifetimeCash or 0) or Billionaires.START_RANK
    local la = log(max(1, actual))
    if not self.shownLog_ or la > self.shownLog_ + 0.5 then self.shownLog_ = la end
    local diff = la - self.shownLog_
    self.shownLog_ = self.shownLog_ + diff * min(1, dt * 5)
    if diff < 0 then self.up_ = min(1, self.up_ + dt * 6) else self.up_ = max(0, self.up_ - dt * 1.5) end
    local shown = exp(self.shownLog_)

    -- 每 1/30 秒格式化一次；逐位比较记录变化时间（里程表滚动）
    self.fmtAcc_ = self.fmtAcc_ + dt
    if self.fmtAcc_ >= 0.033 then
        self.fmtAcc_ = 0
        local txt = RankLadder.FormatRank(shown)
        if txt ~= self.txt_ then
            local prev = self.prevChars_
            local cur = self.chars_
            local oldN = #cur
            for i = 1, oldN do prev[i] = cur[i] end
            for i = oldN + 1, #prev do prev[i] = nil end
            local n = SplitChars(txt, cur)
            -- 位数变化（跨单位）时整体重排，不做逐位滑动
            local sameLen = (n == oldN)
            for i = 1, n do
                if sameLen and prev[i] ~= cur[i] then self.changeT_[i] = t
                elseif not sameLen then self.changeT_[i] = -9 end
            end
            self.txt_ = txt
        end
        if fx then fx.liveRankTxt = "第 " .. self.txt_ .. " 名" end
    end

    if fx then
        local hits = fx.rankHits or 0
        if hits > 0 then
            fx.rankHits = 0
            self.punch_ = 1
        end
        fx.ancRankX, fx.ancRankY = l.x + l.w * 0.5, l.y + l.h * 0.5
    end
    if self.punch_ > 0 then self.punch_ = max(0, self.punch_ - dt * 2.5) end

    local h = l.h
    local r = h * 0.5
    -- 底板（被砸时金光外溢）
    if self.punch_ > 0.02 then
        SetAdditive(nvg, true)
        nvgBeginPath(nvg)
        nvgRect(nvg, l.x - 14, l.y - 10, l.w + 28, h + 20)
        nvgFillPaint(nvg, nvgBoxGradient(nvg, l.x, l.y, l.w, h, r, 16, Col(C.gold, floor(150 * self.punch_)), Col(C.gold, 0)))
        nvgFill(nvg)
        SetAdditive(nvg, false)
    end
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, l.x, l.y, l.w, h, r)
    nvgFillPaint(nvg, nvgLinearGradient(nvg, l.x, l.y, l.x, l.y + h, Col(TICK_BG_TOP, 245), Col(TICK_BG_BOT, 250)))
    nvgFill(nvg)
    nvgStrokeColor(nvg, Col(C.gold, floor(150 + 105 * self.punch_)))
    nvgStrokeWidth(nvg, 1.4 + self.punch_ * 1.2)
    nvgStroke(nvg)

    nvgFontFace(nvg, self.font_)
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    -- 左侧小标签
    local lx = l.x + 8
    nvgFontSize(nvg, 11)
    nvgFillColor(nvg, Col(C.muted, 255))
    nvgText(nvg, lx, l.y + h * 0.5, "世界")
    lx = lx + 26

    -- 数字区（按精确字符宽度自适应缩放，8,000,000,000 长串全显示不截断）
    local fs = 16 * (1 + self.punch_ * 0.14)
    local avail = max(40, l.x + l.w - 19 - lx)
    local bodyUnits = 1.72
    for i = 1, #self.chars_ do
        local b = self.chars_[i]:byte(1)
        if b == 44 then bodyUnits = bodyUnits + 0.30
        elseif b < 128 then bodyUnits = bodyUnits + 0.56
        else bodyUnits = bodyUnits + 0.90 end
    end
    local bw = bodyUnits * fs
    if bw > avail then fs = fs * avail / bw end
    local cy = l.y + h * 0.5
    nvgSave(nvg)
    nvgIntersectScissor(nvg, l.x + 2, l.y + 2, l.w - 4, h - 4)
    nvgFontSize(nvg, fs * 0.82)
    nvgFillColor(nvg, Col(C.white, 230))
    nvgText(nvg, lx, cy, "第")
    local x = lx + fs * 0.86
    nvgFontSize(nvg, fs)
    local col = (self.punch_ > 0.4) and C.white or C.gold
    for i = 1, #self.chars_ do
        local ch = self.chars_[i]
        local b = ch:byte(1)
        local isNum = (b >= 48 and b <= 57)
        local isComma = (b == 44)
        local cw = isComma and (fs * 0.30) or ((b < 128) and (fs * 0.56) or fs)
        local age = t - (self.changeT_[i] or -9)
        if age < ROLL_DUR and isNum then
            local e = age / ROLL_DUR
            local slide = fs * 0.75
            nvgFillColor(nvg, Col(col, floor(255 * (1 - e))))
            nvgText(nvg, x, cy - slide * e, self.prevChars_[i] or ch)
            nvgFillColor(nvg, Col(col, floor(255 * e)))
            nvgText(nvg, x, cy + slide * (1 - e), ch)
        else
            local cCol = isNum and col or (isComma and C.muted or C.white)
            nvgFillColor(nvg, Col(cCol, 255))
            nvgText(nvg, x, cy, ch)
        end
        x = x + cw
    end
    nvgFontSize(nvg, fs * 0.82)
    nvgFillColor(nvg, Col(C.white, 230))
    nvgText(nvg, x + 1, cy, "名")
    nvgRestore(nvg)

    -- 右侧上升箭头（排名在往上滚时常亮跳动）
    if self.up_ > 0.05 then
        local ax = l.x + l.w - 12
        local ay = cy + sin(t * 9) * 2
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, ax, ay - 6)
        nvgLineTo(nvg, ax + 5, ay + 3)
        nvgLineTo(nvg, ax - 5, ay + 3)
        nvgClosePath(nvg)
        nvgFillColor(nvg, Col(CPS_UP, floor(255 * self.up_)))
        nvgFill(nvg)
    end
end

return JuiceWidgets
