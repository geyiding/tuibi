-- ============================================================================
-- Stage.lua  推币机舞台控件（3D 机台之上的屏幕空间机台 HUD + 2D 兜底机台）
--   · 倍率霓虹招牌：挂在 3D 机台顶棚位置，大号总倍率 + 实时增益来源芯片（连击/狂欢/三连/印钞）
--   · 幸运三连机滚轮：真实滚动 + 依次落定回弹 + 幸运倍率倒计时光条
--   · 狂欢能量玻璃管 / 连击计时光环 / 传说币闪烁星光 / 点击涟漪
--   · 所有锚点来自 Machine3D 投影（随屏幕比例自适应），2D 兜底模式用逻辑坐标映射
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("game/Config")
local Physics = require("game/Physics")
local Skin = require("game/Skin")
local Art = require("game/Art")
local Machine3D = require("game/Machine3D")
local Fx = require("game/Fx")
local Number = require("game/Number")

local S = Config.STAGE
local W, H = Config.WORLD_W, Config.WORLD_H
local C = Skin.C
local Col = Skin.Col
local floor, min, max, sin, cos, rad, pi, abs, log =
    math.floor, math.min, math.max, math.sin, math.cos, math.rad, math.pi, math.abs, math.log

local OutlinedText, SetAdditive, Rainbow, EstTextW, DrawStarPath =
    Fx.OutlinedText, Fx.SetAdditive, Fx.Rainbow, Fx.EstTextW, Fx.DrawStarPath

local INK = { 10, 8, 26 }
local PLATE_TOP = { 34, 18, 66 }
local PLATE_BOT = { 12, 10, 32 }
local ORANGE = { 255, 132, 44 }
local GLASS = { 140, 200, 255 }
local SLOT_WELL_COL = { 8, 10, 26 }
local SLOT_LOCK_AT = { 0.45, 0.72, 0.95 }
local DEFAULT_REELS = { 1, 1, 1 }

local Stage = UI.Widget:Extend("Stage")

local function PickEvent(a, b)
    if type(a) == "table" and a.GetAbsoluteLayout then return b end
    return a
end

--- 倍率颜色分级：×2 青 / ×10 金 / ×100 橙 / ×1000+ 彩虹
local function MultColor(m, t)
    if m >= 1000 then return Rainbow(t * 8) end
    if m >= 100 then return ORANGE end
    if m >= 10 then return C.gold end
    if m >= 2 then return C.cyan end
    return C.white
end
Stage.MultColor = MultColor

function Stage:Init(props)
    props = props or {}
    self.game = props.game
    props.game = nil
    self.holding_ = false
    self.ox_, self.oy_, self.s_ = 0, 0, 1
    self.uiW_, self.uiH_ = 390, 844
    self.depthOrder_ = {}
    self.lastT_ = 0
    -- 招牌状态（显示值滞后实际值，令牌砸中时加速追平 + 冲击放大）
    self.multShown_ = 1
    self.multKey_ = -1
    self.multTxt_ = "×1.0"
    self.signPunch_ = 0
    self.signFlashCol_ = C.gold
    self.signRect_ = { x = 0, y = 0, w = 0, h = 0 }
    self.chipTxt_ = { "", "", "", "" }
    self.chipKey_ = { -1, -1, -1, -1 }
    self.flameAcc_ = 0
    self.reelStop_ = { 0, 0, 0 }
    self.lastReelLock_ = { true, true, true }
    self.comboTxt_ = ""
    self.comboShown_ = -1
    self.feverTxt_ = ""
    self.feverKey_ = -1
    self.luckTxt_ = ""
    self.luckKey_ = -1
    self.slotSideTxt_ = ""
    self.slotSideKey_ = ""

    local selfRef = self
    -- 世界(360×600 逻辑坐标) -> 屏幕坐标（闭包只建一次，供 Fx 在事件回调里换算）
    self.toScreen_ = function(lx, ly)
        if Machine3D.IsActive() then
            return Machine3D.ProjectFast(lx, ly, selfRef.uiW_, selfRef.uiH_)
        end
        return selfRef.ox_ + lx * selfRef.s_, selfRef.oy_ + ly * selfRef.s_
    end
    if self.game and self.game.fx then
        self.game.fx.toScreen = self.toScreen_
    end

    props.onPointerDown = function(a, b)
        local e = PickEvent(a, b)
        if not e then return end
        local sr = selfRef.signRect_
        if e.x and e.y and sr.w > 0 and e.x >= sr.x and e.x <= sr.x + sr.w and e.y >= sr.y and e.y <= sr.y + sr.h then
            if selfRef.game and selfRef.game.OnTapSign then selfRef.game.OnTapSign() end
            return
        end
        selfRef.holding_ = true
        if selfRef.game and selfRef.game.OnTapStage then
            selfRef.game.OnTapStage()
        end
        local fx = selfRef.game and selfRef.game.fx
        if fx and e.x and e.y then fx:OnTap(e.x, e.y) end
    end
    props.onPointerUp = function() selfRef.holding_ = false end
    props.onPointerLeave = function() selfRef.holding_ = false end
    UI.Widget.Init(self, props)
    if UI.Input and UI.Input.On then
        UI.Input.On("PointerUp", function() selfRef.holding_ = false end)
    end
end

function Stage:IsHolding()
    return self.holding_
end

function Stage:ToScreen(lx, ly)
    return self.toScreen_(lx, ly)
end

-- ----------------------------------------------------------------------------
-- 幸运三连符号
-- ----------------------------------------------------------------------------
local function DrawSlotSymbol(nvg, symIdx, cx, cy, r, font)
    local syms = Config.SLOT_SYMBOLS
    local cfg = syms and syms[symIdx]
    local col = (cfg and cfg.col) or C.gold
    if symIdx == 1 then
        Fx.DrawMiniCoin(nvg, cx, cy, r * 0.72, 0, 255)
    elseif symIdx == 2 then
        local d, lr = r * 0.30, r * 0.34
        nvgFillColor(nvg, Col(col, 255))
        nvgBeginPath(nvg); nvgCircle(nvg, cx - d, cy - d * 0.4, lr); nvgFill(nvg)
        nvgBeginPath(nvg); nvgCircle(nvg, cx + d, cy - d * 0.4, lr); nvgFill(nvg)
        nvgBeginPath(nvg); nvgCircle(nvg, cx - d * 0.65, cy + d * 0.75, lr); nvgFill(nvg)
        nvgBeginPath(nvg); nvgCircle(nvg, cx + d * 0.65, cy + d * 0.75, lr); nvgFill(nvg)
    elseif symIdx == 3 then
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, cx + r * 0.15, cy - r * 0.78)
        nvgLineTo(nvg, cx - r * 0.42, cy + r * 0.06)
        nvgLineTo(nvg, cx + r * 0.04, cy + r * 0.06)
        nvgLineTo(nvg, cx - r * 0.18, cy + r * 0.78)
        nvgLineTo(nvg, cx + r * 0.46, cy - r * 0.08)
        nvgLineTo(nvg, cx - r * 0.02, cy - r * 0.08)
        nvgClosePath(nvg)
        nvgFillColor(nvg, Col(col, 255))
        nvgFill(nvg)
    elseif symIdx == 4 then
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, cx, cy - r * 0.78)
        nvgLineTo(nvg, cx + r * 0.68, cy)
        nvgLineTo(nvg, cx, cy + r * 0.78)
        nvgLineTo(nvg, cx - r * 0.68, cy)
        nvgClosePath(nvg)
        nvgFillColor(nvg, Col(col, 255))
        nvgFill(nvg)
        nvgStrokeColor(nvg, Col(C.white, 210))
        nvgStrokeWidth(nvg, 1.0)
        nvgStroke(nvg)
    elseif symIdx == 5 then
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, cx - r * 0.65, cy + r * 0.50)
        nvgLineTo(nvg, cx - r * 0.70, cy - r * 0.42)
        nvgLineTo(nvg, cx - r * 0.25, cy + r * 0.05)
        nvgLineTo(nvg, cx, cy - r * 0.60)
        nvgLineTo(nvg, cx + r * 0.25, cy + r * 0.05)
        nvgLineTo(nvg, cx + r * 0.70, cy - r * 0.42)
        nvgLineTo(nvg, cx + r * 0.65, cy + r * 0.50)
        nvgClosePath(nvg)
        nvgFillColor(nvg, Col(col, 255))
        nvgFill(nvg)
    else
        nvgBeginPath(nvg)
        DrawStarPath(nvg, cx, cy, r * 0.85, 0, 0.34)
        nvgFillColor(nvg, Col(col, 255))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, cx, cy - r * 0.36)
        nvgLineTo(nvg, cx + r * 0.30, cy)
        nvgLineTo(nvg, cx, cy + r * 0.36)
        nvgLineTo(nvg, cx - r * 0.30, cy)
        nvgClosePath(nvg)
        nvgFillColor(nvg, Col(C.white, 240))
        nvgFill(nvg)
    end
end
Stage.DrawSlotSymbol = DrawSlotSymbol

-- ----------------------------------------------------------------------------
-- 2D 兜底机台（无 3D 渲染能力时）
-- ----------------------------------------------------------------------------
local sortCoins = nil
local function DepthLess(ia, ib)
    local a, b = sortCoins[ia], sortCoins[ib]
    if a.onPusher ~= b.onPusher then return not a.onPusher end
    return (a.y + a.z * 0.2) < (b.y + b.z * 0.2)
end

function Stage:DrawMachine2D(nvg, run, phys, t, accent, trim, themeIdx, boostOn, ox, oy, scale)
    nvgSave(nvg)
    nvgTranslate(nvg, ox, oy)
    nvgScale(nvg, scale, scale)

    -- 机台外壳 + 跑马灯
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, 10, 6, W - 20, H - 12, 16)
    nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, 6, 0, H - 6, Col({ 18, 22, 46 }, 250), Col({ 9, 11, 24 }, 255)))
    nvgFill(nvg)
    nvgStrokeColor(nvg, Col((run.feverActive or boostOn) and C.gold or accent, 220))
    nvgStrokeWidth(nvg, 2.5)
    nvgStroke(nvg)

    local slotX, slotW = S.SLOT_LEFT, S.SLOT_RIGHT - S.SLOT_LEFT
    local bgKey = "backdrop_act" .. tostring(themeIdx)
    if not Art.DrawSprite(nvg, bgKey, slotX, S.SLOT_TOP, slotW, S.DECK_TOP_Y - S.SLOT_TOP, 0.85) then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, slotX, S.SLOT_TOP, slotW, S.DECK_TOP_Y - S.SLOT_TOP + 6, 10)
        nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, S.SLOT_TOP, 0, S.DECK_TOP_Y, Col({ 22, 18, 52 }, 255), Col({ 12, 24, 54 }, 255)))
        nvgFill(nvg)
    end

    nvgBeginPath(nvg)
    nvgRect(nvg, slotX - 4, S.SLOT_TOP, 4, S.DECK_TOP_Y - S.SLOT_TOP)
    nvgRect(nvg, S.SLOT_RIGHT, S.SLOT_TOP, 4, S.DECK_TOP_Y - S.SLOT_TOP)
    nvgFillColor(nvg, Col(accent, 190))
    nvgFill(nvg)

    local bulbPhase = floor(t * (run.feverActive and 12 or 5))
    for b = 0, 11 do
        local by = S.SLOT_TOP + 10 + b * 19
        local lit = ((b + bulbPhase) % 3 == 0)
        local bCol = run.feverActive and (((b % 2 == 0) and C.gold) or C.magenta) or accent
        nvgBeginPath(nvg)
        nvgCircle(nvg, slotX - 10, by, lit and 3.2 or 2.2)
        nvgCircle(nvg, S.SLOT_RIGHT + 10, by, lit and 3.2 or 2.2)
        nvgFillColor(nvg, Col(bCol, lit and 255 or 75))
        nvgFill(nvg)
    end

    local topL, topR = 180 - S.DECK_TOP_HALF, 180 + S.DECK_TOP_HALF
    local botL, botR = 180 - S.DECK_BOT_HALF, 180 + S.DECK_BOT_HALF
    local gapL, gapR = 180 - Physics.TrapezoidHalfW(S.SIDE_GAP_Y), 180 + Physics.TrapezoidHalfW(S.SIDE_GAP_Y)

    nvgBeginPath(nvg)
    nvgMoveTo(nvg, botL, S.DECK_BOT_Y)
    nvgLineTo(nvg, botR, S.DECK_BOT_Y)
    nvgLineTo(nvg, botR, S.DECK_BOT_Y + 14)
    nvgLineTo(nvg, botL, S.DECK_BOT_Y + 14)
    nvgClosePath(nvg)
    nvgFillColor(nvg, Col({ 16, 18, 42 }, 255))
    nvgFill(nvg)

    nvgBeginPath(nvg)
    nvgMoveTo(nvg, topL, S.DECK_TOP_Y)
    nvgLineTo(nvg, topR, S.DECK_TOP_Y)
    nvgLineTo(nvg, botR, S.DECK_BOT_Y)
    nvgLineTo(nvg, botL, S.DECK_BOT_Y)
    nvgClosePath(nvg)
    nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, S.DECK_TOP_Y, 0, S.DECK_BOT_Y,
        Col({ 34, 42, 82 }, 255), Col({ 22, 26, 56 }, 255)))
    nvgFill(nvg)

    nvgBeginPath(nvg)
    for k = -2, 2 do
        nvgMoveTo(nvg, 180 + k * 42, S.DECK_TOP_Y + 4)
        nvgLineTo(nvg, 180 + k * 60, S.DECK_BOT_Y - 2)
    end
    for ry = 310, 510, 50 do
        local hw = Physics.TrapezoidHalfW(ry)
        nvgMoveTo(nvg, 180 - hw + 2, ry)
        nvgLineTo(nvg, 180 + hw - 2, ry)
    end
    nvgStrokeColor(nvg, Col(accent, 42))
    nvgStrokeWidth(nvg, 1)
    nvgStroke(nvg)

    nvgBeginPath(nvg)
    nvgMoveTo(nvg, topL, S.DECK_TOP_Y); nvgLineTo(nvg, gapL, S.SIDE_GAP_Y)
    nvgMoveTo(nvg, topR, S.DECK_TOP_Y); nvgLineTo(nvg, gapR, S.SIDE_GAP_Y)
    nvgStrokeColor(nvg, Col(accent, 235))
    nvgStrokeWidth(nvg, 4)
    nvgStroke(nvg)

    local guarded = phys.railGuard > 0.2
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, gapL, S.SIDE_GAP_Y); nvgLineTo(nvg, botL, S.DECK_BOT_Y)
    nvgMoveTo(nvg, gapR, S.SIDE_GAP_Y); nvgLineTo(nvg, botR, S.DECK_BOT_Y)
    nvgStrokeColor(nvg, Col(guarded and C.green or C.red, guarded and 230 or 165))
    nvgStrokeWidth(nvg, guarded and 4 or 2)
    nvgStroke(nvg)

    -- 前沿收集金线（带辉光）
    SetAdditive(nvg, true)
    nvgBeginPath(nvg)
    nvgRect(nvg, botL, S.DECK_BOT_Y - 6, botR - botL, 12)
    nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, S.DECK_BOT_Y - 6, 0, S.DECK_BOT_Y + 6, Col(C.gold, 0), Col(C.gold, 120)))
    nvgFill(nvg)
    SetAdditive(nvg, false)
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, botL, S.DECK_BOT_Y)
    nvgLineTo(nvg, botR, S.DECK_BOT_Y)
    nvgStrokeColor(nvg, Col(C.gold, 240))
    nvgStrokeWidth(nvg, 3)
    nvgStroke(nvg)

    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, botL + 6, S.DECK_BOT_Y + 14, (botR - botL) - 12, 34, 8)
    nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, S.DECK_BOT_Y + 14, 0, S.DECK_BOT_Y + 48,
        Col(C.gold, 55), Col(C.gold, 10)))
    nvgFill(nvg)

    -- 往复推板
    local py = phys.pusherY
    local pBack = S.DECK_TOP_Y
    local pW = S.DECK_TOP_HALF * 2 - 6
    local px = 180 - pW * 0.5
    local drawnPusher = false
    if Skin.SPRITES.pusher_bar then
        local visH = max(0, py - pBack)
        if visH > 2 then
            nvgSave(nvg)
            nvgIntersectScissor(nvg, px - 6, pBack, pW + 12, visH + 6)
            drawnPusher = Art.DrawSprite(nvg, "pusher_bar", px, py - 92 + 3, pW, 92, 1.0)
            nvgRestore(nvg)
        end
    end
    if not drawnPusher then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, px, pBack, pW, py - pBack, 6)
        nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, pBack, 0, py, Col({ 52, 66, 124 }, 255), Col({ 78, 96, 164 }, 255)))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgRect(nvg, px + 2, py - 9, pW - 4, 9)
        nvgFillColor(nvg, Col(run.feverActive and C.magenta or accent, 230))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgRect(nvg, px + 4, py - 7, pW - 8, 2)
        nvgFillColor(nvg, Col(C.white, 190))
        nvgFill(nvg)
    end

    -- 钉阵（撞击时辉光扩散）
    local pegs = phys.pegs
    SetAdditive(nvg, true)
    for i = 1, #pegs do
        local p = pegs[i]
        local pDef = Config.PEG_TYPES[p.kind] or Config.PEG_TYPES.normal
        local glow = (p.kind ~= "normal") and 0.45 or 0.18
        local f = max(glow, p.flash)
        nvgBeginPath(nvg)
        nvgCircle(nvg, p.x, p.y, p.r * (2.2 + f * 1.6))
        nvgFillPaint(nvg, nvgRadialGradient(nvg, p.x, p.y, p.r * 0.5, p.r * (2.2 + f * 1.6), Col(pDef.col, floor(200 * f)), Col(pDef.col, 0)))
        nvgFill(nvg)
    end
    SetAdditive(nvg, false)
    for i = 1, #pegs do
        local p = pegs[i]
        local pDef = Config.PEG_TYPES[p.kind] or Config.PEG_TYPES.normal
        nvgBeginPath(nvg)
        nvgCircle(nvg, p.x, p.y, p.r)
        nvgFillColor(nvg, Col(pDef.col, 255))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgCircle(nvg, p.x - p.r * 0.3, p.y - p.r * 0.3, p.r * 0.35)
        nvgFillColor(nvg, Col(C.white, 220))
        nvgFill(nvg)
    end

    -- 移动幸运门
    local gx = phys.gateX
    local gy = S.GATE_Y
    local gHalf = phys.gateClosed and 2 or (S.GATE_BASE_HALF * phys.gateWidthScale)
    local dW = S.GATE_DOOR_W
    if not phys.gateClosed then
        SetAdditive(nvg, true)
        nvgBeginPath(nvg)
        nvgRect(nvg, gx - gHalf, gy - 4, gHalf * 2, 22)
        nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, gy - 4, 0, gy + 18, Col(C.gold, 200), Col(C.gold, 0)))
        nvgFill(nvg)
        SetAdditive(nvg, false)
    end
    local gateW = (gHalf + dW) * 1.84
    if not Art.DrawSprite(nvg, "gate_badge", gx - gateW * 0.5, gy - 20, gateW, 34, phys.gateClosed and 0.45 or 1.0) then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, gx - gHalf - dW, gy - 4, dW, S.GATE_DOOR_H, 3)
        nvgRoundedRect(nvg, gx + gHalf, gy - 4, dW, S.GATE_DOOR_H, 3)
        nvgFillColor(nvg, Col(phys.gateClosed and C.red or trim, 245))
        nvgFill(nvg)
    end

    -- 摆动发射炮口
    local angRad = rad(phys.launchAngleDeg)
    nvgSave(nvg)
    nvgTranslate(nvg, S.LAUNCHER_X, S.LAUNCHER_Y)
    nvgRotate(nvg, -angRad)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, -9, -4, 18, 22, 5)
    nvgFillColor(nvg, Col(C.gold, 255))
    nvgFill(nvg)
    nvgStrokeColor(nvg, Col(C.white, 230))
    nvgStrokeWidth(nvg, 1.6)
    nvgStroke(nvg)
    nvgBeginPath(nvg)
    nvgCircle(nvg, 0, 2, 4.5)
    nvgFillColor(nvg, Col(C.bgInset, 255))
    nvgFill(nvg)
    nvgRestore(nvg)

    -- 硬币深度排序绘制（比较器为模块级函数，零每帧闭包）
    local ord = self.depthOrder_
    local cnt = phys.activeCount
    local coins = phys.coins
    local ids = phys.activeIds
    for i = 1, cnt do ord[i] = ids[i] end
    for i = cnt + 1, #ord do ord[i] = nil end
    sortCoins = coins
    table.sort(ord, DepthLess)
    sortCoins = nil
    for i = 1, cnt do
        local c = coins[ord[i]]
        if c.active then
            local squash = (c.zone == "slot") and 0.96 or 0.84
            local syDraw = c.y - c.z * 0.65
            if c.fromManual then
                nvgBeginPath(nvg)
                nvgCircle(nvg, c.x, syDraw, c.r * 1.18)
                nvgStrokeColor(nvg, Col(C.gold, 195))
                nvgStrokeWidth(nvg, 1.5)
                nvgStroke(nvg)
            end
            Art.DrawCoin(nvg, c.kind, c.x, syDraw, c.r, c.level, squash, c.rot, c.frostT > 0, c.fuseT, c.isRain)
        end
    end
    nvgRestore(nvg)
end

-- ----------------------------------------------------------------------------
-- 3D 模式：传说币闪烁星光（屏幕空间，最多 14 颗）
-- ----------------------------------------------------------------------------
function Stage:DrawTwinkles(nvg, phys, t)
    local coins, ids = phys.coins, phys.activeIds
    local n = 0
    SetAdditive(nvg, true)
    for k = 1, phys.activeCount do
        local c = coins[ids[k]]
        if c.active and c.zone == "deck" then
            local def = Config.COINS[c.kind]
            if def and def.rarity == "legendary" then
                local ph = sin(t * 2.6 + c.id * 1.7)
                if ph > 0.55 then
                    local sx, sy = self.toScreen_(c.x, c.y)
                    if sx then
                        local f = (ph - 0.55) / 0.45
                        local r = (5 + 5 * f) * self.u_
                        local glow = def.color.glow
                        nvgBeginPath(nvg)
                        DrawStarPath(nvg, sx + 3, sy - 5, r, t * 1.5, 0.18)
                        nvgFillColor(nvg, Col(C.white, floor(240 * f)))
                        nvgFill(nvg)
                        nvgBeginPath(nvg)
                        nvgCircle(nvg, sx, sy - 2, r * 1.8)
                        nvgFillPaint(nvg, nvgRadialGradient(nvg, sx, sy - 2, 1, r * 1.8, Col(glow, floor(120 * f)), Col(glow, 0)))
                        nvgFill(nvg)
                        n = n + 1
                        if n >= 14 then break end
                    end
                end
            end
        end
    end
    SetAdditive(nvg, false)
end

-- ----------------------------------------------------------------------------
-- 倍率霓虹招牌
-- ----------------------------------------------------------------------------
local CHIP_COLS = { C.cyan, C.magenta, C.gold, C.green }
local CHIP_HEAD = { "连击", "狂欢", "三连", "印钞" }

function Stage:DrawMultSign(nvg, run, fx, cx, cy, u, t, dt, font)
    -- 1. 显示值追随实际值（增益上涨时快速滚动，过期回落时稍慢）
    local actual = fx.multTotal or (run.GetTotalMult and run:GetTotalMult()) or 1
    local shown = self.multShown_
    local k = (actual > shown) and 7 or 3
    shown = shown + (actual - shown) * min(1, dt * k)
    if abs(actual - shown) < actual * 0.002 then shown = actual end
    self.multShown_ = shown
    local hits = fx.multHits or 0
    if hits > 0 then
        fx.multHits = 0
        self.signPunch_ = 1
        self.signFlashCol_ = fx.multHitCol or C.gold
        self.multShown_ = shown + (actual - shown) * 0.6
    end
    if self.signPunch_ > 0 then self.signPunch_ = max(0, self.signPunch_ - dt * 3.2) end

    local key = (shown < 100) and floor(shown * 10 + 0.5) or floor(log(shown, 10) * 200)
    if key ~= self.multKey_ then
        self.multKey_ = key
        self.multTxt_ = "×" .. Number.FormatMul(shown)
    end

    -- 2. 增益芯片文本（仅数值变化时重建字符串）
    local comboFactor = (run.HasTech and run:HasTech("metronome")) and 0.012 or 0.008
    local cv1 = 1 + min(100, run.combo or 0) * comboFactor
    local cv2 = run.feverActive and 2.2 or 1
    local cv3 = max(1, run.luckMult or 1)
    local cv4 = ((run.adBoostLeft or 0) > 0) and 3 or 1
    local chipVals = self.chipVals_ or { 1, 1, 1, 1 }
    self.chipVals_ = chipVals
    chipVals[1], chipVals[2], chipVals[3], chipVals[4] = cv1, cv2, cv3, cv4

    local pulse = self.signPunch_
    local heat = fx.heat or 0
    local mcol = MultColor(shown, t)
    local w = 196 * u
    local h = 50 * u
    local sc = 1 + pulse * 0.22
    local x0, y0 = cx - w * 0.5, cy - h * 0.5
    self.signRect_.x, self.signRect_.y, self.signRect_.w, self.signRect_.h = x0, y0, w, h + 20 * u

    -- 光晕（热度越高越大越亮）
    SetAdditive(nvg, true)
    local gr = w * (0.5 + heat * 0.2 + pulse * 0.15)
    nvgBeginPath(nvg)
    nvgEllipse(nvg, cx, cy, gr, gr * 0.5)
    nvgFillPaint(nvg, nvgRadialGradient(nvg, cx, cy, h * 0.2, gr, Col(mcol, floor(35 + heat * 55 + pulse * 70)), Col(mcol, 0)))
    nvgFill(nvg)
    SetAdditive(nvg, false)

    nvgSave(nvg)
    nvgTranslate(nvg, cx, cy)
    nvgScale(nvg, sc, sc)
    -- 招牌底板
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, -w * 0.5, -h * 0.5 + 3, w, h, 12 * u)
    nvgFillColor(nvg, Col(INK, 200))
    nvgFill(nvg)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, -w * 0.5, -h * 0.5, w, h, 12 * u)
    nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, -h * 0.5, 0, h * 0.5, Col(PLATE_TOP, 245), Col(PLATE_BOT, 250)))
    nvgFill(nvg)
    nvgStrokeColor(nvg, Col(mcol, 255))
    nvgStrokeWidth(nvg, 2.4)
    nvgStroke(nvg)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, -w * 0.5 + 4, -h * 0.5 + 4, w - 8, h - 8, 9 * u)
    nvgStrokeColor(nvg, Col(C.white, 60))
    nvgStrokeWidth(nvg, 1)
    nvgStroke(nvg)
    -- 招牌灯珠（热度越高跑得越快）
    local nb = 14
    local ph = floor(t * (4 + heat * 16))
    SetAdditive(nvg, true)
    for b = 0, nb - 1 do
        local bx = -w * 0.5 + 10 * u + (w - 20 * u) * b / (nb - 1)
        local lit = ((b + ph) % 3 == 0)
        local bc = (heat > 0.5) and Rainbow(b + ph) or mcol
        nvgBeginPath(nvg)
        nvgCircle(nvg, bx, -h * 0.5, lit and 2.6 * u or 1.6 * u)
        nvgCircle(nvg, bx, h * 0.5, lit and 2.6 * u or 1.6 * u)
        nvgFillColor(nvg, Col(bc, lit and 255 or 90))
        nvgFill(nvg)
    end
    SetAdditive(nvg, false)
    -- 标签 + 大号倍率
    nvgFontFace(nvg, font or "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(nvg, 12 * u)
    nvgFillColor(nvg, Col(C.muted, 255))
    nvgText(nvg, -w * 0.5 + 26 * u, -h * 0.5 + 12 * u, "总倍率")
    local fs = 30 * u
    local tw = EstTextW(self.multTxt_, fs)
    if tw > w - 20 * u then fs = fs * (w - 20 * u) / tw end
    nvgFontSize(nvg, fs)
    local tc = (pulse > 0.4) and C.white or mcol
    OutlinedText(nvg, 6 * u, 3 * u, self.multTxt_, tc, 255, 2.2)
    nvgRestore(nvg)

    -- 3. 增益芯片行（招牌下方，只显示生效中的来源）
    local active = 0
    for i = 1, 4 do if chipVals[i] > 1.001 then active = active + 1 end end
    if active > 0 then
        local chipH = 19 * u
        local fsC = 12 * u
        local totalW = 0
        for i = 1, 4 do
            local v = chipVals[i]
            if v > 1.001 then
                local kk = floor(v * 10 + 0.5)
                if kk ~= self.chipKey_[i] then
                    self.chipKey_[i] = kk
                    self.chipTxt_[i] = CHIP_HEAD[i] .. "×" .. Number.FormatMul(v)
                end
                totalW = totalW + EstTextW(self.chipTxt_[i], fsC) + 12 * u + 4 * u
            end
        end
        local x = cx - totalW * 0.5
        local yy = y0 + h + 4 * u
        nvgFontSize(nvg, fsC)
        for i = 1, 4 do
            if chipVals[i] > 1.001 then
                local cw = EstTextW(self.chipTxt_[i], fsC) + 12 * u
                local cc = CHIP_COLS[i]
                local blink = (i == 2 or i == 3) and (0.75 + 0.25 * sin(t * 10)) or 1
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, x, yy, cw, chipH, chipH * 0.5)
                nvgFillColor(nvg, Col(INK, 225))
                nvgFill(nvg)
                nvgStrokeColor(nvg, Col(cc, floor(255 * blink)))
                nvgStrokeWidth(nvg, 1.5)
                nvgStroke(nvg)
                nvgFillColor(nvg, Col(cc, 255))
                nvgText(nvg, x + cw * 0.5, yy + chipH * 0.5 + 0.5, self.chipTxt_[i])
                x = x + cw + 4 * u
            end
        end
    end

    -- 4. 高热度火苗（从招牌顶部窜起）
    if heat > 0.25 then
        self.flameAcc_ = self.flameAcc_ + dt * (10 + heat * 40)
        while self.flameAcc_ >= 1 do
            self.flameAcc_ = self.flameAcc_ - 1
            local fxk = (math.random() - 0.5) * w * 0.9
            fx:Emit(1, cx + fxk, y0 + 2, (math.random() - 0.5) * 20, -60 - math.random() * 90 * (0.5 + heat),
                0.45 + math.random() * 0.3, (2 + math.random() * 2.5) * u, (math.random() < 0.5) and mcol or ORANGE, -40, 0.5)
        end
    end
end

-- ----------------------------------------------------------------------------
-- 幸运三连滚轮 + 幸运倍率倒计时
-- ----------------------------------------------------------------------------
function Stage:DrawSlotReels(nvg, run, cx, cy, u, t, font)
    local spin = run.slotSpinning == true
    local luckMult = run.luckMult or 1
    local hot = spin or (luckMult > 1) or ((run.slotFlashT or 0) > 0)
    local zoom = spin and 1.12 or 1.0
    local rw, rh, gap = 30 * u * zoom, 32 * u * zoom, 5 * u
    local boxW = rw * 3 + gap * 2 + 14 * u
    local sideW = 56 * u
    local totalW = boxW + sideW
    local bx = cx - totalW * 0.5
    local by = cy - rh * 0.5 - 6 * u
    local bh = rh + 12 * u
    local border = (luckMult >= 25) and C.gold or (hot and C.magenta or C.cyan)

    if hot then
        SetAdditive(nvg, true)
        nvgBeginPath(nvg)
        nvgRect(nvg, bx - 14, by - 14, totalW + 28, bh + 28)
        nvgFillPaint(nvg, nvgBoxGradient(nvg, bx, by, totalW, bh, 10, 18, Col(border, 110), Col(border, 0)))
        nvgFill(nvg)
        SetAdditive(nvg, false)
    end
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, bx, by, totalW, bh, 10 * u)
    nvgFillColor(nvg, Col(INK, 225))
    nvgFill(nvg)
    nvgStrokeColor(nvg, Col(border, hot and 255 or 170))
    nvgStrokeWidth(nvg, hot and 2 or 1.3)
    nvgStroke(nvg)

    local reels = run.slotReels or DEFAULT_REELS
    local ratio = spin and max(0, min(1, (run.slotSpinT or 0) / max(0.01, run.slotSpinDur or 0.85))) or 1
    local x = bx + 7 * u
    for kIdx = 1, 3 do
        local rcx = x + rw * 0.5
        local rcy = cy
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x, rcy - rh * 0.5, rw, rh, 5 * u)
        nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, rcy - rh * 0.5, 0, rcy + rh * 0.5, Col({ 230, 232, 248 }, 255), Col({ 168, 174, 206 }, 255)))
        nvgFill(nvg)
        local locked = (not spin) or (ratio >= SLOT_LOCK_AT[kIdx])
        if locked and not self.lastReelLock_[kIdx] then
            self.reelStop_[kIdx] = 1
        end
        self.lastReelLock_[kIdx] = locked
        nvgSave(nvg)
        nvgIntersectScissor(nvg, x, rcy - rh * 0.5, rw, rh)
        if locked then
            local bounce = self.reelStop_[kIdx]
            local yOff = -sin(bounce * pi) * 5 * u * bounce
            DrawSlotSymbol(nvg, reels[kIdx] or 1, rcx, rcy + yOff, 11 * u * zoom, font)
        else
            -- 滚动：两枚符号循环下落 + 速度残影
            local sp = t * 14 + kIdx * 0.37
            local frac = sp - floor(sp)
            local s1 = (floor(sp) + kIdx * 2) % 6 + 1
            local s2 = (s1 % 6) + 1
            DrawSlotSymbol(nvg, s1, rcx, rcy + frac * rh, 11 * u * zoom, font)
            DrawSlotSymbol(nvg, s2, rcx, rcy + (frac - 1) * rh, 11 * u * zoom, font)
            nvgBeginPath(nvg)
            nvgRect(nvg, x, rcy - rh * 0.5, rw, rh)
            nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, rcy - rh * 0.5, 0, rcy + rh * 0.5, Col({ 255, 255, 255 }, 150), Col({ 255, 255, 255 }, 0)))
            nvgFill(nvg)
        end
        -- 玻璃上下阴影
        nvgBeginPath(nvg)
        nvgRect(nvg, x, rcy - rh * 0.5, rw, rh * 0.28)
        nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, rcy - rh * 0.5, 0, rcy - rh * 0.22, Col(SLOT_WELL_COL, 160), Col(SLOT_WELL_COL, 0)))
        nvgFill(nvg)
        nvgRestore(nvg)
        if self.reelStop_[kIdx] > 0 then self.reelStop_[kIdx] = max(0, self.reelStop_[kIdx] - 0.06) end
        x = x + rw + gap
    end

    -- 右侧状态
    local q = run.slotQueue or 0
    local sideKey = (spin and "s" or "i") .. tostring(q) .. ":" .. tostring(luckMult)
    if sideKey ~= self.slotSideKey_ then
        self.slotSideKey_ = sideKey
        self.slotSideTxt_ = spin and "转动中" or (q > 0 and ("待转+" .. q) or ((luckMult > 1) and ("×" .. Number.FormatMul(luckMult)) or "过门三连"))
    end
    nvgFontFace(nvg, font or "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local sfs = ((luckMult > 1) and not spin and q == 0) and 16 * u or 12 * u
    nvgFontSize(nvg, sfs)
    local scol = hot and ((luckMult > 1) and Stage.MultColor(luckMult, t) or C.gold) or C.muted
    OutlinedText(nvg, bx + boxW + sideW * 0.5 - 4 * u, cy, self.slotSideTxt_, scol, 255, 1.2)

    -- 幸运倍率倒计时光条
    if luckMult > 1 and (run.luckTimer or 0) > 0 then
        local pw, ph = totalW, 16 * u
        local px, py = bx, by + bh + 4 * u
        local pCol = Stage.MultColor(luckMult, t)
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, px, py, pw, ph, ph * 0.5)
        nvgFillColor(nvg, Col(INK, 230))
        nvgFill(nvg)
        local prog = max(0, min(1, run.luckTimer / max(0.1, run.luckDur or 10)))
        if prog > 0.02 then
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, px + 2, py + 2, (pw - 4) * prog, ph - 4, (ph - 4) * 0.5)
            nvgFillPaint(nvg, nvgLinearGradient(nvg, px, 0, px + pw, 0, Col(pCol, 200), Col(C.white, 230)))
            nvgFill(nvg)
        end
        nvgStrokeColor(nvg, Col(pCol, 255))
        nvgStrokeWidth(nvg, 1.3)
        nvgStroke(nvg)
        local lk = floor(luckMult * 10 + 0.5) * 1000 + math.ceil(run.luckTimer)
        if lk ~= self.luckKey_ then
            self.luckKey_ = lk
            self.luckTxt_ = "幸运 ×" .. Number.FormatMul(luckMult) .. " · " .. tostring(max(1, math.ceil(run.luckTimer))) .. "s"
        end
        nvgFontSize(nvg, 12 * u)
        OutlinedText(nvg, px + pw * 0.5, py + ph * 0.5 + 0.5, self.luckTxt_, C.white, 255, 1.2)
    end
    return cx, cy
end

-- ----------------------------------------------------------------------------
-- 狂欢能量玻璃管
-- ----------------------------------------------------------------------------
function Stage:DrawFeverTube(nvg, run, x, y0, y1, u, t, font)
    local tw = 14 * u
    local th = y1 - y0
    if th < 40 then return end
    local active = run.feverActive == true
    local cdLeft = (not active) and max(0, run.feverCd or 0) or 0
    local ratio = active and min(1, (run.feverTimer or 0) / max(1, run.feverDur or Config.RULES.FEVER_DURATION))
        or min(1, (run.fever or 0) / 100)
    local col = active and Rainbow(t * 6) or ((cdLeft > 0) and C.muted or C.magenta)
    -- 玻璃外壳
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x - tw * 0.5, y0, tw, th, tw * 0.5)
    nvgFillColor(nvg, Col(INK, 210))
    nvgFill(nvg)
    local fh = (th - 4) * ratio
    if fh > 2 then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x - tw * 0.5 + 2, y1 - 2 - fh, tw - 4, fh, (tw - 4) * 0.5)
        nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, y1 - fh, 0, y1, Col(active and C.gold or C.magenta, 255), Col(C.purple, 255)))
        nvgFill(nvg)
        -- 上升气泡
        SetAdditive(nvg, true)
        for b = 0, 3 do
            local ph = (t * 0.6 + b * 0.27) % 1
            local by = y1 - 4 - ph * fh
            nvgBeginPath(nvg)
            nvgCircle(nvg, x + sin(t * 3 + b) * tw * 0.18, by, (1.5 + (b % 2)) * u)
            nvgFillColor(nvg, Col(C.white, floor(160 * (1 - ph))))
            nvgFill(nvg)
        end
        SetAdditive(nvg, false)
    end
    -- 玻璃高光 + 外框
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x - tw * 0.5 + 2.5, y0 + 5, 2.5 * u, th - 10, 1.2)
    nvgFillColor(nvg, Col(GLASS, 90))
    nvgFill(nvg)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x - tw * 0.5, y0, tw, th, tw * 0.5)
    nvgStrokeColor(nvg, Col(col, active and 255 or 200))
    nvgStrokeWidth(nvg, active and 2.2 or 1.5)
    nvgStroke(nvg)
    if ratio > 0.85 or active then
        SetAdditive(nvg, true)
        nvgBeginPath(nvg)
        nvgRect(nvg, x - tw * 2, y0 - 10, tw * 4, th + 20)
        nvgFillPaint(nvg, nvgBoxGradient(nvg, x - tw * 0.5, y0, tw, th, tw * 0.5, 14, Col(col, floor(120 * (0.6 + 0.4 * sin(t * 8)))), Col(col, 0)))
        nvgFill(nvg)
        SetAdditive(nvg, false)
    end
    -- 顶部火焰图标 + 数值（冷却中显示倒计时）
    local fk = active and (1000 + math.ceil(run.feverTimer or 0))
        or (cdLeft > 0 and (2000 + math.ceil(cdLeft)) or floor(ratio * 100))
    if fk ~= self.feverKey_ then
        self.feverKey_ = fk
        if active then
            self.feverTxt_ = tostring(math.ceil(run.feverTimer or 0)) .. "s"
        elseif cdLeft > 0 then
            self.feverTxt_ = "冷" .. tostring(math.ceil(cdLeft)) .. "s"
        else
            self.feverTxt_ = tostring(floor(ratio * 100)) .. "%"
        end
    end
    nvgFontFace(nvg, font or "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(nvg, 12 * u)
    OutlinedText(nvg, x, y0 - 9 * u, self.feverTxt_, active and C.gold or (cdLeft > 0 and C.muted or C.magenta), 255, 1.2)
    OutlinedText(nvg, x, y1 + 10 * u, cdLeft > 0 and "冷却" or "狂欢", cdLeft > 0 and C.muted or C.magenta, 255, 1.2)
end

-- ----------------------------------------------------------------------------
-- 连击计时光环
-- ----------------------------------------------------------------------------
function Stage:DrawComboBadge(nvg, run, fx, cx, cy, u, t, font)
    local combo = run.combo or 0
    if combo < 2 then return end
    local win = (run.HasTech and run:HasTech("metronome")) and 4.0 or 2.8
    local frac = max(0, min(1, (run.comboTimer or 0) / win))
    local cCol = (combo >= 60) and Rainbow(t * 6) or ((combo >= 30) and C.magenta or ((combo >= 12) and C.gold or C.cyan))
    local pop = 1 + (fx.comboPop or 0) * 0.25
    local r = 24 * u * pop
    nvgBeginPath(nvg)
    nvgCircle(nvg, cx, cy, r)
    nvgFillColor(nvg, Col(INK, 220))
    nvgFill(nvg)
    nvgBeginPath(nvg)
    nvgArc(nvg, cx, cy, r - 2, -pi * 0.5, -pi * 0.5 + frac * pi * 2, NVG_CW)
    nvgStrokeColor(nvg, Col(cCol, 255))
    nvgStrokeWidth(nvg, 3.5 * u)
    nvgStroke(nvg)
    if combo ~= self.comboShown_ then
        self.comboShown_ = combo
        self.comboTxt_ = tostring(combo)
    end
    nvgFontFace(nvg, font or "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local fs = ((combo >= 100) and 15 or 19) * u * pop
    nvgFontSize(nvg, fs)
    OutlinedText(nvg, cx, cy - 3 * u, self.comboTxt_, cCol, 255, 1.5)
    nvgFontSize(nvg, 11 * u)
    nvgFillColor(nvg, Col(C.white, 220))
    nvgText(nvg, cx, cy + 12 * u, "连击")
end

-- ----------------------------------------------------------------------------
-- 主渲染
-- ----------------------------------------------------------------------------
function Stage:Render(nvg)
    local g = self.game
    if not g then return end
    local run = g.tycoon or g.run
    if not run then return end
    local fx = g.fx
    local phys = run.physics
    local l = self:GetAbsoluteLayout()
    if l.w <= 0 or l.h <= 0 then return end
    if fx and fx.toScreen ~= self.toScreen_ then fx.toScreen = self.toScreen_ end

    self.uiW_ = (UI.GetWidth and UI.GetWidth()) or l.w
    self.uiH_ = (UI.GetHeight and UI.GetHeight()) or (l.y + l.h)

    local scale = min(l.w / W, l.h / H)
    local vw, vh = W * scale, H * scale
    local ox = l.x + (l.w - vw) * 0.5 + (fx.shakeX or 0)
    local oy = l.y + (l.h - vh) * 0.5 + (fx.shakeY or 0)
    self.ox_, self.oy_, self.s_ = ox, oy, scale

    local themeIdx = min(3, max(1, run.stageTheme or run.act or 1))
    local actCfg = Config.ACTS[themeIdx] or Config.ACTS[1]
    local accent = actCfg.accent or C.cyan
    local trim = actCfg.trim or C.magenta
    local t = g.time or 0
    local dt = max(0, min(0.1, t - (self.lastT_ or t)))
    self.lastT_ = t
    local boostOn = (run.adBoostLeft or 0) > 0
    local is3D = Machine3D.IsActive()
    local u = max(0.92, min(1.2, l.w / 390))
    self.u_ = u

    -- 锚点（屏幕坐标）
    local mqX, mqY, slTLx, slTLy, slTRx, slBotY, dkTLy, dkBLy
    if is3D then
        local uw, uh = self.uiW_, self.uiH_
        mqX, mqY = Machine3D.GetAnchor("marquee", uw, uh)
        slTLx, slTLy = Machine3D.GetAnchor("slotTL", uw, uh)
        slTRx = Machine3D.GetAnchor("slotTR", uw, uh)
        local _
        _, slBotY = Machine3D.GetAnchor("slotBot", uw, uh)
        _, dkTLy = Machine3D.GetAnchor("deckTL", uw, uh)
        _, dkBLy = Machine3D.GetAnchor("deckBL", uw, uh)
        local trX = Machine3D.GetAnchor("deckTR", uw, uh)
        local tlX = Machine3D.GetAnchor("deckTL", uw, uh)
        if trX and tlX and fx then fx.ws = max(0.8, min(1.4, (trX - tlX) / (S.DECK_TOP_HALF * 2))) end
        if not (mqX and slTLx and slTRx and slBotY and dkTLy and dkBLy) then mqX = nil end
    end
    if not mqX then
        mqX, mqY = ox + 180 * scale, oy + 10 * scale
        slTLx, slTLy = ox + S.SLOT_LEFT * scale, oy + S.SLOT_TOP * scale
        slTRx = ox + S.SLOT_RIGHT * scale
        slBotY = oy + S.DECK_TOP_Y * scale
        dkTLy, dkBLy = oy + S.DECK_TOP_Y * scale, oy + S.DECK_BOT_Y * scale
        if fx then fx.ws = scale end
    end

    if not is3D then
        self:DrawMachine2D(nvg, run, phys, t, accent, trim, themeIdx, boostOn, ox, oy, scale)
    else
        self:DrawTwinkles(nvg, phys, t)
    end

    -- 机台 HUD 布局（招牌 -> 滚轮 -> 左狂欢管 / 右连击环），全部夹在舞台控件区域内
    local signH = 50 * u
    local signY = max(mqY, l.y + signH * 0.5 + 4)
    local chipsBottom = signY + signH * 0.5 + 24 * u
    local reelY = max(chipsBottom + 18 * u, slTLy + 20 * u)
    reelY = min(reelY, l.y + l.h * 0.45)
    local tubeX = max(l.x + 14 * u, slTLx - 20 * u)
    local tubeY0 = reelY + 34 * u
    local tubeY1 = min(l.y + l.h - 30 * u, dkTLy + (dkBLy - dkTLy) * 0.45)
    local comboX = min(l.x + l.w - 40 * u, slTRx + 2 * u) -- 放大 1.25 倍后仍距右边 ≥ 8
    local comboY = (slTLy + slBotY) * 0.5 + 20 * u

    self:DrawFeverTube(nvg, run, tubeX, tubeY0, tubeY1, u, t, g.font)
    self:DrawComboBadge(nvg, run, fx, comboX, comboY, u, t, g.font)
    self:DrawSlotReels(nvg, run, mqX, reelY, u, t, g.font)
    self:DrawMultSign(nvg, run, fx, mqX, signY, u, t, dt, g.font)

    if fx then
        fx.ancMultX, fx.ancMultY = mqX, signY
        fx.ancSlotX, fx.ancSlotY = mqX, reelY
        fx.ancFeverX, fx.ancFeverY = tubeX, (tubeY0 + tubeY1) * 0.5
        fx.ancComboX, fx.ancComboY = comboX, comboY
        fx.ancAdX, fx.ancAdY = l.x + l.w - 50, l.y + 30
    end

    -- 首次点按引导
    if g.showTapHint and g.showTapHint() then
        local pulse = 0.5 + 0.5 * sin(t * 5.5)
        local hx, hy = l.x + l.w * 0.5, (dkTLy + dkBLy) * 0.5 + pulse * 8
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, hx - 96 * u, hy - 17 * u, 192 * u, 34 * u, 17 * u)
        nvgFillColor(nvg, Col(INK, 220))
        nvgFill(nvg)
        nvgStrokeColor(nvg, Col(C.gold, 240))
        nvgStrokeWidth(nvg, 2)
        nvgStroke(nvg)
        nvgFontFace(nvg, g.font or "sans")
        nvgFontSize(nvg, 14 * u)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, Col(C.gold, 255))
        nvgText(nvg, hx, hy, "点按或长按推台 狂暴连发!")
    end
end

return Stage
