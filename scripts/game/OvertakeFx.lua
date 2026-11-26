-- ============================================================================
-- OvertakeFx.lua  超越演出（世界排名爽点的核心表现）
--   时间线（约 2.4s）：
--     0.00 面板落下（回弹）：上排 = 对手（头像 / 名字 / 排名），下排 = 你（金币头像 / 实时排名）
--     0.25 交换：你那一排带着金色拖尾往上冲，对手被挤下去
--     0.47 交错瞬间：爆点 + 冲击环 + 屏震 + “超越!”大字砸出 + 顶栏排名计数器被砸
--     0.70 对手变灰，红色“已超越”印章砸上；对手吐槽气泡
--     2.05 面板缩小飞进顶栏排名计数器
--   连续超越：演出中再超越，会合并为“连超 N 人”并在当前演出结束后切到最新的对手
-- ============================================================================

local Skin = require("game/Skin")
local AvatarArt = require("game/AvatarArt")
local RankLadder = require("game/RankLadder")

local floor, min, max, sin, cos, pi, abs = math.floor, math.min, math.max, math.sin, math.cos, math.pi, math.abs
local Col = Skin.Col
local C = Skin.C

local OvertakeFx = {}
OvertakeFx.__index = OvertakeFx

local DUR = 2.4
local INK = { 10, 8, 26 }
local PANEL_TOP = { 40, 30, 70 }
local PANEL_BOT = { 16, 12, 36 }
local ROW_BG = { 28, 24, 56 }
local ME_TOP = { 120, 84, 16 }
local ME_BOT = { 60, 36, 8 }
local GREY = { 120, 124, 140 }
local STAMP_RED = { 214, 40, 56 }
local TRAIL = { 255, 214, 90 }
local GREEN_UP = { 110, 255, 160 }

-- 叠加混合（引擎提供时启用）
local function SetAdditiveSafe(nvg, on)
    if type(nvgGlobalCompositeOperation) == "function" and NVG_LIGHTER ~= nil then
        nvgGlobalCompositeOperation(nvg, on and NVG_LIGHTER or (NVG_SOURCE_OVER or 0))
    end
end

local function EaseOutBack(t)
    local c1 = 1.70158
    local c3 = c1 + 1
    local u = t - 1
    return 1 + c3 * u * u * u + c1 * u * u
end

local function EaseInOutCubic(t)
    if t < 0.5 then return 4 * t * t * t end
    local u = -2 * t + 2
    return 1 - u * u * u * 0.5
end

function OvertakeFx.New(fx)
    local self = setmetatable({}, OvertakeFx)
    self.fx = fx
    self.on = false
    self.age = 0
    self.dur = DUR
    self.entry = nil
    self.kind = "rival"
    self.count = 1
    self.rankTxt = ""
    self.nameTxt = ""
    self.quoteTxt = ""
    self.crossed = false
    self.pending = nil
    self.pendingCount = 0
    return self
end

function OvertakeFx:IsBusy()
    return self.on or self.pending ~= nil
end

local function Start(self, item, count)
    self.on = true
    self.age = 0
    self.dur = DUR
    self.entry = item.entry
    self.kind = item.kind
    self.count = count or 1
    self.crossed = false
    local e = item.entry
    if e and e.isRealName then
        self.rankTxt = "世界第 " .. tostring(e.rank) .. " 名"
    else
        self.rankTxt = "第 " .. RankLadder.FormatRankShort(item.rank) .. " 名"
    end
    self.nameTxt = item.name or ""
    self.quoteTxt = item.quote or ""
end

--- 触发一次超越（item = RankLadder.LIST 元素；count = 本次一口气越过的人数）
function OvertakeFx:Trigger(item, count)
    if not item then return end
    count = count or 1
    if self.on and self.age < self.dur - 0.25 then
        -- 正在演出：合并为“连超 N 人”，当前演出加速收尾后切到最新对手
        self.pending = item
        self.pendingCount = self.pendingCount + count
        if self.age > 0.9 then self.dur = min(self.dur, self.age + 0.35) end
        return
    end
    Start(self, item, count)
end

function OvertakeFx:Update(dt)
    -- 弹窗打开时暂停（演出不在弹窗下面悄悄播完）
    if self.fx.modalOpen then return end
    if not self.on then
        if self.pending then
            local p, c = self.pending, self.pendingCount
            self.pending, self.pendingCount = nil, 0
            Start(self, p, c)
        end
        return
    end
    self.age = self.age + dt
    local fx = self.fx
    if not self.crossed and self.age >= 0.47 then
        self.crossed = true
        local w, h = fx.screenW, fx.screenH
        local cx, cy = w * 0.5, self:PanelY(h)
        local ws0 = fx.ws
        fx.ws = 1
        fx:Burst(cx, cy, 26, Skin.C.gold, 260, 3.4, 8)
        fx:Ring(cx, cy, 20, w * 0.55, Skin.C.gold, 0.5, 5)
        fx:Ring(cx, cy, 4, 70, { 255, 240, 200 }, 0.25, 0, true)
        fx.ws = ws0
        fx:AddTrauma(0.3)
        fx:AddKick(0.4)
        fx:AddFlash(70, Skin.C.gold)
        fx.rankHits = (fx.rankHits or 0) + 1
        if self.entry and (self.entry.milestone or self.entry.isRealName) then
            fx:Confetti(40, 0, w, -10)
        end
    end
    if self.age >= self.dur then
        self.on = false
        if self.pending then
            local p, c = self.pending, self.pendingCount
            self.pending, self.pendingCount = nil, 0
            Start(self, p, c)
        end
    end
end

function OvertakeFx:PanelY(h)
    -- 机台倍率招牌与增益芯片之下，“超越!”大字不压招牌
    return h * 0.40
end

-- 你的头像：金币 + “你”
local function DrawMe(nvg, x, y, r, t)
    nvgBeginPath(nvg)
    nvgCircle(nvg, x, y, r * 1.18)
    nvgFillPaint(nvg, nvgRadialGradient(nvg, x, y, r * 0.8, r * 1.18, Col(C.gold, 140), Col(C.gold, 0)))
    nvgFill(nvg)
    nvgBeginPath(nvg)
    nvgCircle(nvg, x, y, r)
    nvgFillPaint(nvg, nvgLinearGradient(nvg, x - r, y - r, x + r, y + r, Col({ 255, 246, 180 }, 255), Col({ 196, 120, 18 }, 255)))
    nvgFill(nvg)
    nvgBeginPath(nvg)
    nvgCircle(nvg, x, y, r * 0.78)
    nvgStrokeColor(nvg, Col({ 150, 90, 10 }, 200))
    nvgStrokeWidth(nvg, max(1, r * 0.08))
    nvgStroke(nvg)
    nvgFontSize(nvg, r * 1.05)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, Col({ 110, 60, 0 }, 255))
    nvgText(nvg, x, y + 1, "你")
end

local function DrawRowBg(nvg, x, y, w, h, isMe, a, grey)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x, y, w, h, h * 0.3)
    if isMe then
        nvgFillPaint(nvg, nvgLinearGradient(nvg, x, y, x, y + h, Col(ME_TOP, a), Col(ME_BOT, a)))
    else
        nvgFillColor(nvg, Col(grey and INK or ROW_BG, a))
    end
    nvgFill(nvg)
    nvgStrokeColor(nvg, Col(isMe and C.gold or (grey and GREY or C.border), floor(a * (isMe and 1 or 0.7))))
    nvgStrokeWidth(nvg, isMe and 2 or 1.2)
    nvgStroke(nvg)
end

function OvertakeFx:Render(nvg, w, h, font)
    if not self.on then return end
    local fx = self.fx
    local Out = fx.OutlinedText or require("game/Fx").OutlinedText
    local t = self.age
    local time = fx.time or 0

    -- 进出场
    local inT = min(1, t / 0.22)
    local outStart = self.dur - 0.35
    local alpha, sc, offX, offY = 1, EaseOutBack(inT), 0, 0
    if t < 0.22 then alpha = inT end
    local pw = min(w - 24, 340)
    local ph = 128
    local cx, cy = w * 0.5, self:PanelY(h)
    if t > outStart then
        local u = min(1, (t - outStart) / 0.35)
        local e = u * u
        sc = 1 - 0.75 * e
        alpha = 1 - e
        offX = ((fx.ancRankX or cx) - cx) * e
        offY = ((fx.ancRankY or 60) - cy) * e
    end
    local A = floor(255 * alpha)
    if A <= 2 then return end

    nvgSave(nvg)
    nvgTranslate(nvg, cx + offX, cy + offY)
    nvgScale(nvg, sc, sc)
    local x0, y0 = -pw * 0.5, -ph * 0.5

    -- 面板
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x0, y0 + 5, pw, ph, 16)
    nvgFillColor(nvg, Col(INK, floor(A * 0.6)))
    nvgFill(nvg)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x0, y0, pw, ph, 16)
    nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, y0, 0, y0 + ph, Col(PANEL_TOP, floor(A * 0.97)), Col(PANEL_BOT, floor(A * 0.97))))
    nvgFill(nvg)
    nvgStrokeColor(nvg, Col(C.gold, floor(A * 0.85)))
    nvgStrokeWidth(nvg, 2)
    nvgStroke(nvg)

    -- 两排位置：0.25~0.70 交换
    local rowH, gap = 50, 8
    local topY = y0 + 10
    local botY = topY + rowH + gap
    local s = EaseInOutCubic(max(0, min(1, (t - 0.25) / 0.45)))
    local meY = botY + (topY - botY) * s
    local rivalY = topY + (botY - topY) * s
    local rowX, rowW = x0 + 10, pw - 20
    local crossed = s >= 0.5
    local greyed = t >= 0.7

    -- 对手排
    local ra = floor(A * (greyed and 0.6 or 1))
    DrawRowBg(nvg, rowX, rivalY, rowW, rowH, false, ra, greyed)
    if self.entry then
        AvatarArt.Draw(nvg, self.entry, rowX + 28, rivalY + rowH * 0.5, 20, {
            shocked = crossed, surpassed = false, time = time,
        })
    end
    nvgFontFace(nvg, font or "sans")
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local nameFs = 16
    local nameW = (fx.EstTextW and fx.EstTextW(self.nameTxt, nameFs)) or (#self.nameTxt * 5)
    local maxNameW = rowW - 64 - 96
    if nameW > maxNameW then nameFs = nameFs * maxNameW / nameW end
    nvgFontSize(nvg, nameFs)
    nvgFillColor(nvg, Col(greyed and GREY or C.white, ra))
    nvgText(nvg, rowX + 56, rivalY + rowH * 0.5, self.nameTxt)
    nvgTextAlign(nvg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFontSize(nvg, 13)
    nvgFillColor(nvg, Col(greyed and GREY or C.muted, ra))
    nvgText(nvg, rowX + rowW - 10, rivalY + rowH * 0.5, self.rankTxt)

    -- 已超越印章
    if greyed then
        local u = min(1, (t - 0.7) / 0.16)
        local ssc = 1 + (1 - EaseOutBack(u)) * 1.6
        nvgSave(nvg)
        nvgTranslate(nvg, rowX + rowW * 0.62, rivalY + rowH * 0.5)
        nvgRotate(nvg, -0.2)
        nvgScale(nvg, ssc, ssc)
        local bw, bh = 78, 26
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, -bw * 0.5, -bh * 0.5, bw, bh, 5)
        nvgFillColor(nvg, Col(STAMP_RED, floor(A * 0.92)))
        nvgFill(nvg)
        nvgStrokeColor(nvg, Col(C.white, A))
        nvgStrokeWidth(nvg, 1.6)
        nvgStroke(nvg)
        nvgFontSize(nvg, 15)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, Col(C.white, A))
        nvgText(nvg, 0, 1, "已超越")
        nvgRestore(nvg)
    end

    -- 你：交换途中的金色拖尾
    if s > 0.02 and s < 0.98 then
        SetAdditiveSafe(nvg, true)
        local trailH = (botY - meY) + rowH
        nvgBeginPath(nvg)
        nvgRect(nvg, rowX, meY, rowW, trailH)
        nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, meY + rowH * 0.5, 0, meY + trailH, Col(TRAIL, floor(A * 0.55)), Col(TRAIL, 0)))
        nvgFill(nvg)
        for k = 0, 5 do
            local lx = rowX + 20 + k * (rowW - 40) / 5
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, lx, meY + rowH)
            nvgLineTo(nvg, lx, meY + rowH + 26 + (k % 2) * 14)
            nvgStrokeColor(nvg, Col(C.white, floor(A * 0.6)))
            nvgStrokeWidth(nvg, 1.5)
            nvgStroke(nvg)
        end
        SetAdditiveSafe(nvg, false)
    end
    DrawRowBg(nvg, rowX, meY, rowW, rowH, true, A, false)
    DrawMe(nvg, rowX + 28, meY + rowH * 0.5, 20, time)
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFontSize(nvg, 17)
    nvgFillColor(nvg, Col(C.white, A))
    nvgText(nvg, rowX + 56, meY + rowH * 0.5, "你")
    -- 你的实时排名（交错后显示上升箭头）
    nvgTextAlign(nvg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFontSize(nvg, 14)
    nvgFillColor(nvg, Col(C.gold, A))
    nvgText(nvg, rowX + rowW - 10, meY + rowH * 0.5, fx.liveRankTxt or "")
    if crossed then
        local bob = sin(time * 10) * 2
        local ax = rowX + rowW - 10 - (fx.EstTextW and fx.EstTextW(fx.liveRankTxt or "", 14) or 60) - 12
        local ay = meY + rowH * 0.5 + bob
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, ax, ay - 7)
        nvgLineTo(nvg, ax + 6, ay + 3)
        nvgLineTo(nvg, ax - 6, ay + 3)
        nvgClosePath(nvg)
        nvgFillColor(nvg, Col(GREEN_UP, A))
        nvgFill(nvg)
    end
    nvgRestore(nvg)

    -- “超越!” 大字（交错瞬间砸出，跟随面板但不缩放到计数器）
    if t >= 0.47 and t < outStart + 0.1 then
        local u = min(1, (t - 0.47) / 0.18)
        local bsc = 2.2 - 1.2 * EaseOutBack(u)
        local ba = floor(A * min(1, u * 2))
        local title = (self.count > 1) and ("连超 " .. tostring(self.count) .. " 人!") or "超越!"
        nvgFontFace(nvg, font or "sans")
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFontSize(nvg, 34 * bsc)
        local ty = cy + offY - ph * 0.5 - 26
        Out(nvg, cx + offX, ty + 3, title, INK, ba, 3, INK)
        Out(nvg, cx + offX, ty, title, C.gold, ba, 2.4, { 255, 255, 255 })
        nvgFillColor(nvg, Col(C.gold, ba))
        nvgText(nvg, cx + offX, ty, title)
    end

    -- 对手吐槽气泡
    if t >= 0.75 and t < outStart and self.quoteTxt ~= "" then
        local qa = floor(A * min(1, (t - 0.75) / 0.2))
        local qfs = 13
        local qw = (fx.EstTextW and fx.EstTextW(self.quoteTxt, qfs)) or 200
        local maxW = w - 32
        if qw + 24 > maxW then qfs = qfs * (maxW - 24) / qw; qw = maxW - 24 end
        local bx, by = cx - (qw + 24) * 0.5, cy + ph * 0.5 + 12
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, bx, by, qw + 24, 30, 15)
        nvgFillColor(nvg, Col(C.white, floor(qa * 0.94)))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, cx - 8, by)
        nvgLineTo(nvg, cx, by - 8)
        nvgLineTo(nvg, cx + 8, by)
        nvgClosePath(nvg)
        nvgFill(nvg)
        nvgFontSize(nvg, qfs)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, Col(INK, qa))
        nvgText(nvg, cx, by + 15.5, "“" .. self.quoteTxt .. "”")
    end
end

return OvertakeFx
