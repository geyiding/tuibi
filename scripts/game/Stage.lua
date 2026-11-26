-- ============================================================================
-- Stage.lua  2.5D 霓虹推币机舞台自定义控件（支持点击/连发 + 完整机械/币堆渲染）
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("game/Config")
local Physics = require("game/Physics")
local Skin = require("game/Skin")
local Art = require("game/Art")
local Machine3D = require("game/Machine3D")

local S = Config.STAGE
local W, H = Config.WORLD_W, Config.WORLD_H
local C = Skin.C
local Col = Skin.Col
local floor, min, max, sin, cos, rad, pi = math.floor, math.min, math.max, math.sin, math.cos, math.rad, math.pi

local Stage = UI.Widget:Extend("Stage")

local function PickEvent(a, b)
    if type(a) == "table" and a.GetAbsoluteLayout then return b end
    return a
end

function Stage:Init(props)
    props = props or {}
    self.game = props.game
    props.game = nil
    self.holding_ = false
    self.ox_, self.oy_, self.s_ = 0, 0, 1
    self.depthOrder_ = {}

    local selfRef = self
    props.onPointerDown = function(a, b)
        local e = PickEvent(a, b)
        if not e then return end
        selfRef.holding_ = true
        if selfRef.game and selfRef.game.OnTapStage then
            selfRef.game.OnTapStage()
        end
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

local function DrawSlotSymbol(nvg, symIdx, cx, cy, r, font)
    local syms = Config.SLOT_SYMBOLS
    local cfg = syms and syms[symIdx]
    local col = (cfg and cfg.col) or C.gold
    if symIdx == 1 then
        nvgBeginPath(nvg)
        nvgCircle(nvg, cx, cy, r * 0.72)
        nvgFillColor(nvg, Col(col, 255))
        nvgFill(nvg)
        nvgStrokeColor(nvg, Col(C.white, 210))
        nvgStrokeWidth(nvg, 1.1)
        nvgStroke(nvg)
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
        nvgCircle(nvg, cx, cy, r * 0.76)
        nvgFillColor(nvg, Col(col, 255))
        nvgFill(nvg)
        nvgFontFace(nvg, font or "sans")
        nvgFontSize(nvg, r * 1.45)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, Col(C.white, 255))
        nvgText(nvg, cx, cy + 0.5, "7")
    end
end

local SLOT_WELL_COL = { 12, 16, 36 }
local SLOT_LOCK_AT = { 0.45, 0.72, 0.95 }
local DEFAULT_REELS = { 1, 1, 1 }

local function DrawSlotBar(nvg, run, t, font)
    local bx, by, bw, bh = 102, 8, 156, 32
    local spin = run.slotSpinning == true
    local luckMult = run.luckMult or 1
    local hot = spin or (luckMult > 1) or ((run.slotFlashT or 0) > 0)
    local borderCol = (luckMult >= 25) and C.gold or (hot and C.magenta or C.cyan)

    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, bx, by, bw, bh, 9)
    nvgFillColor(nvg, Col(C.bgInset, hot and 235 or 195))
    nvgFill(nvg)
    nvgStrokeColor(nvg, Col(borderCol, hot and 245 or 165))
    nvgStrokeWidth(nvg, hot and 1.8 or 1.2)
    nvgStroke(nvg)

    local reels = run.slotReels or DEFAULT_REELS
    local ratio = spin and max(0, min(1, 1 - (run.slotSpinT or 0) / max(0.01, run.slotSpinDur or 0.85))) or 1
    local rx0 = bx + 16
    local stepX = 32
    for k = 1, 3 do
        local cx = rx0 + (k - 1) * stepX
        local cy = by + 16
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, cx - 12, cy - 11, 24, 22, 5)
        nvgFillColor(nvg, Col(SLOT_WELL_COL, 235))
        nvgFill(nvg)
        local locked = (not spin) or (ratio >= SLOT_LOCK_AT[k])
        local sym = locked and (reels[k] or 1) or (floor(t * 16 + k * 2) % 6 + 1)
        local yOff = locked and 0 or ((floor(t * 48 + k * 7) % 5) - 2)
        DrawSlotSymbol(nvg, sym, cx, cy + yOff, 10, font)
    end

    -- 右侧状态标识：排队数 / 抽奖中 / 待机
    nvgFontFace(nvg, font or "sans")
    nvgFontSize(nvg, 11)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local q = run.slotQueue or 0
    local sideTxt = spin and "抽奖中" or (q > 0 and ("待抽+" .. q) or ((luckMult > 1) and ("×" .. tostring(luckMult)) or "过门奖池"))
    nvgFillColor(nvg, Col(hot and C.gold or C.muted, 255))
    nvgText(nvg, bx + 128, by + 16, sideTxt)

    -- 中奖全局倍率倒计时条（仅当倍率 > 1x 时出现）
    if luckMult > 1 and (run.luckTimer or 0) > 0 then
        local px, py, pw, ph = 98, 43, 164, 19
        local pCol = (luckMult >= 50) and C.gold or ((luckMult >= 10) and C.magenta or C.cyan)
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, px, py, pw, ph, 7)
        nvgFillColor(nvg, Col(C.bgInset, 232))
        nvgFill(nvg)
        local prog = max(0, min(1, run.luckTimer / max(0.1, run.luckDur or 10)))
        if prog > 0.02 then
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, px + 2, py + 2, (pw - 4) * prog, ph - 4, 5)
            nvgFillColor(nvg, Col(pCol, 145))
            nvgFill(nvg)
        end
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, px, py, pw, ph, 7)
        nvgStrokeColor(nvg, Col(pCol, 240))
        nvgStrokeWidth(nvg, 1.3)
        nvgStroke(nvg)
        nvgFontSize(nvg, 11)
        nvgFillColor(nvg, Col(C.white, 255))
        nvgText(nvg, px + pw * 0.5, py + ph * 0.5 + 0.5,
            string.format("%s · %ds", run.luckName or (tostring(luckMult) .. "倍"), max(1, math.ceil(run.luckTimer))))
    end
end

function Stage:Render(nvg)
    local g = self.game
    if not g then return end
    local run = g.tycoon or g.run
    if not run then return end
    local fx = g.fx
    local phys = run.physics
    local l = self:GetAbsoluteLayout()
    if l.w <= 0 or l.h <= 0 then return end

    -- 等比居中映射 360x600 世界到舞台控件内
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
    local boostOn = (run.adBoostLeft or 0) > 0
    local is3D = Machine3D.IsActive()

    if not is3D then
        nvgSave(nvg)
        nvgTranslate(nvg, ox, oy)
        nvgScale(nvg, scale, scale)

        -- 1. 街机机台背景外壳 + 跑马灯（纯 2D 兜底模式）
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, 10, 6, W - 20, H - 12, 16)
        nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, 6, 0, H - 6, Col({ 18, 22, 46 }, 250), Col({ 9, 11, 24 }, 255)))
        nvgFill(nvg)
        nvgStrokeColor(nvg, Col((run.feverActive or boostOn) and C.gold or accent, 220))
        nvgStrokeWidth(nvg, 2.5)
        nvgStroke(nvg)

    -- 上部落币槽背板（随富豪头衔自动晋升 3 幕机台皮肤）
    local slotX, slotW = S.SLOT_LEFT, S.SLOT_RIGHT - S.SLOT_LEFT
    local bgKey = "backdrop_act" .. tostring(themeIdx)
    if not Art.DrawSprite(nvg, bgKey, slotX, S.SLOT_TOP, slotW, S.DECK_TOP_Y - S.SLOT_TOP, 0.85) then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, slotX, S.SLOT_TOP, slotW, S.DECK_TOP_Y - S.SLOT_TOP + 6, 10)
        nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, S.SLOT_TOP, 0, S.DECK_TOP_Y, Col({ 22, 18, 52 }, 255), Col({ 12, 24, 54 }, 255)))
        nvgFill(nvg)
    end

    -- 落币槽左右霓虹灯柱与玻璃高光斜线
    nvgBeginPath(nvg)
    nvgRect(nvg, slotX - 4, S.SLOT_TOP, 4, S.DECK_TOP_Y - S.SLOT_TOP)
    nvgRect(nvg, S.SLOT_RIGHT, S.SLOT_TOP, 4, S.DECK_TOP_Y - S.SLOT_TOP)
    nvgFillColor(nvg, Col(accent, 190))
    nvgFill(nvg)

    -- 跑马灯珠
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

    -- 2. 2.5D 梯形推台与侧漏区（先画下方台面再画上推板）
    local topL, topR = 180 - S.DECK_TOP_HALF, 180 + S.DECK_TOP_HALF
    local botL, botR = 180 - S.DECK_BOT_HALF, 180 + S.DECK_BOT_HALF
    local gapL, gapR = 180 - Physics.TrapezoidHalfW(S.SIDE_GAP_Y), 180 + Physics.TrapezoidHalfW(S.SIDE_GAP_Y)

    -- 梯形台面投影底缘（厚度）
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, botL, S.DECK_BOT_Y)
    nvgLineTo(nvg, botR, S.DECK_BOT_Y)
    nvgLineTo(nvg, botR, S.DECK_BOT_Y + 14)
    nvgLineTo(nvg, botL, S.DECK_BOT_Y + 14)
    nvgClosePath(nvg)
    nvgFillColor(nvg, Col({ 16, 18, 42 }, 255))
    nvgFill(nvg)

    -- 梯形台面表面
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, topL, S.DECK_TOP_Y)
    nvgLineTo(nvg, topR, S.DECK_TOP_Y)
    nvgLineTo(nvg, botR, S.DECK_BOT_Y)
    nvgLineTo(nvg, botL, S.DECK_BOT_Y)
    nvgClosePath(nvg)
    nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, S.DECK_TOP_Y, 0, S.DECK_BOT_Y,
        Col({ 34, 42, 82 }, 255), Col({ 22, 26, 56 }, 255)))
    nvgFill(nvg)

    -- 透视网格装饰线
    nvgBeginPath(nvg)
    for k = -2, 2 do
        local xTop = 180 + k * 42
        local xBot = 180 + k * 60
        nvgMoveTo(nvg, xTop, S.DECK_TOP_Y + 4)
        nvgLineTo(nvg, xBot, S.DECK_BOT_Y - 2)
    end
    for ry = 310, 510, 50 do
        local hw = Physics.TrapezoidHalfW(ry)
        nvgMoveTo(nvg, 180 - hw + 2, ry)
        nvgLineTo(nvg, 180 + hw - 2, ry)
    end
    nvgStrokeColor(nvg, Col(accent, 42))
    nvgStrokeWidth(nvg, 1)
    nvgStroke(nvg)

    -- 侧壁挡板（上段实体墙 + 下段侧漏虚线危险区）
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, topL, S.DECK_TOP_Y); nvgLineTo(nvg, gapL, S.SIDE_GAP_Y)
    nvgMoveTo(nvg, topR, S.DECK_TOP_Y); nvgLineTo(nvg, gapR, S.SIDE_GAP_Y)
    nvgStrokeColor(nvg, Col(accent, 235))
    nvgStrokeWidth(nvg, 4)
    nvgStroke(nvg)

    -- 侧漏缝区域指示（若有护栏遗物则画绿蓝实体护栏）
    local guarded = phys.railGuard > 0.2
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, gapL, S.SIDE_GAP_Y); nvgLineTo(nvg, botL, S.DECK_BOT_Y)
    nvgMoveTo(nvg, gapR, S.SIDE_GAP_Y); nvgLineTo(nvg, botR, S.DECK_BOT_Y)
    nvgStrokeColor(nvg, Col(guarded and C.green or C.red, guarded and 230 or 165))
    nvgStrokeWidth(nvg, guarded and 4 or 2)
    nvgStroke(nvg)

    -- 前沿悬崖收集金线（Boss抬高时高亮警告）
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, botL, S.DECK_BOT_Y)
    nvgLineTo(nvg, botR, S.DECK_BOT_Y)
    nvgStrokeColor(nvg, Col(run.bossLipRaised and C.red or C.gold, 240))
    nvgStrokeWidth(nvg, run.bossLipRaised and 5 or 3)
    nvgStroke(nvg)

    -- 下部回收爆分槽光带
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, botL + 6, S.DECK_BOT_Y + 14, (botR - botL) - 12, 34, 8)
    nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, S.DECK_BOT_Y + 14, 0, S.DECK_BOT_Y + 48,
        Col(C.gold, 55), Col(C.gold, 10)))
    nvgFill(nvg)

    -- 3. 往复机械推板（固定板长向下滑出并用裁剪防拉伸失真）
    local py = phys.pusherY
    local pBack = S.DECK_TOP_Y
    local pW = S.DECK_TOP_HALF * 2 - 6
    local px = 180 - pW * 0.5
    local drawnPusher = false
    if Skin.SPRITES.pusher_bar then
        local visH = max(0, py - pBack)
        if visH > 2 then
            local slabH = 92
            nvgSave(nvg)
            nvgIntersectScissor(nvg, px - 6, pBack, pW + 12, visH + 6)
            drawnPusher = Art.DrawSprite(nvg, "pusher_bar", px, py - slabH + 3, pW, slabH, 1.0)
            nvgRestore(nvg)
        end
    end
    if not drawnPusher then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, px, pBack, pW, py - pBack, 6)
        nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, pBack, 0, py, Col({ 52, 66, 124 }, 255), Col({ 78, 96, 164 }, 255)))
        nvgFill(nvg)
        -- 推板前缘厚度金属条
        nvgBeginPath(nvg)
        nvgRect(nvg, px + 2, py - 9, pW - 4, 9)
        nvgFillColor(nvg, Col(run.feverActive and C.magenta or accent, 230))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgRect(nvg, px + 4, py - 7, pW - 8, 2)
        nvgFillColor(nvg, Col(C.white, 190))
        nvgFill(nvg)
    end

    -- 4. 钉阵（普通/倍增/分流/高压/狂欢钉）
    local pegs = phys.pegs
    for i = 1, #pegs do
        local p = pegs[i]
        local pDef = Config.PEG_TYPES[p.kind] or Config.PEG_TYPES.normal
        if p.flash > 0.05 then
            nvgBeginPath(nvg)
            nvgCircle(nvg, p.x, p.y, p.r + 5 * p.flash)
            nvgFillColor(nvg, Col(pDef.col, floor(150 * p.flash)))
            nvgFill(nvg)
        end
        nvgBeginPath(nvg)
        nvgCircle(nvg, p.x, p.y, p.r)
        nvgFillColor(nvg, Col(pDef.col, 255))
        nvgFill(nvg)
        nvgStrokeColor(nvg, Col(C.white, 210))
        nvgStrokeWidth(nvg, 1.2)
        nvgStroke(nvg)
    end

    -- 5. 移动中奖门
    local gx = phys.gateX
    local gy = S.GATE_Y
    local gHalf = phys.gateClosed and 2 or (S.GATE_BASE_HALF * phys.gateWidthScale)
    local dW = S.GATE_DOOR_W
    -- 中奖口光束
    if not phys.gateClosed then
        nvgBeginPath(nvg)
        nvgRect(nvg, gx - gHalf, gy - 4, gHalf * 2, 16)
        nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, gy - 4, 0, gy + 12, Col(C.gold, 190), Col(C.gold, 0)))
        nvgFill(nvg)
    end
    local gateW = (gHalf + dW) * 1.84
    if not Art.DrawSprite(nvg, "gate_badge", gx - gateW * 0.5, gy - 20, gateW, 34, phys.gateClosed and 0.45 or 1.0) then
        -- 左右斜口门板
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, gx - gHalf - dW, gy - 4, dW, S.GATE_DOOR_H, 3)
        nvgRoundedRect(nvg, gx + gHalf, gy - 4, dW, S.GATE_DOOR_H, 3)
        nvgFillColor(nvg, Col(phys.gateClosed and C.red or trim, 245))
        nvgFill(nvg)
        nvgStrokeColor(nvg, Col(C.white, 210))
        nvgStrokeWidth(nvg, 1.2)
        nvgStroke(nvg)
    elseif phys.gateClosed then
        nvgBeginPath(nvg)
        nvgRect(nvg, gx - gateW * 0.4, gy - 3, gateW * 0.8, 5)
        nvgFillColor(nvg, Col(C.red, 235))
        nvgFill(nvg)
    end

    -- 6. 顶部摆动发射炮口
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

    -- 瞄准方向虚线指示
    nvgBeginPath(nvg)
    for k = 1, 4 do
        local dist = 22 + k * 10
        nvgCircle(nvg, S.LAUNCHER_X + sin(angRad) * dist, S.LAUNCHER_Y + cos(angRad) * dist, 1.8)
    end
    nvgFillColor(nvg, Col(C.gold, 170))
    nvgFill(nvg)

    -- 7. 深度排序并绘制全体硬币（y 从小到大，且上层乘板与高 z 优先后画）
    local ord = self.depthOrder_
    local cnt = phys.activeCount
    local coins = phys.coins
    local ids = phys.activeIds
    for i = 1, cnt do ord[i] = ids[i] end
    for i = cnt + 1, #ord do ord[i] = nil end
    table.sort(ord, function(ia, ib)
        local a, b = coins[ia], coins[ib]
        if a.onPusher ~= b.onPusher then return not a.onPusher end
        return (a.y + a.z * 0.2) < (b.y + b.z * 0.2)
    end)

    for i = 1, cnt do
        local c = coins[ord[i]]
        if c.active then
            local squash = (c.zone == "slot") and 0.96 or 0.84
            local drawY = c.y - c.z * 0.65
            Art.DrawCoin(nvg, c.kind, c.x, drawY, c.r, c.level, squash, c.rot, c.frostT > 0, c.fuseT, c.isRain)
        end
    end

        -- 2D 世界特效
        fx:RenderWorld(nvg, g.font)
    else
        -- 3D 模式下使用预计算角点仿射投影将世界坐标特效/暴击飘字投射至屏幕坐标
        local uiW = UI.GetWidth and UI.GetWidth() or l.w
        local uiH = UI.GetHeight and UI.GetHeight() or (l.y + l.h)
        fx:RenderWorld(nvg, g.font, function(lx, ly)
            return Machine3D.ProjectFast(lx, ly, uiW, uiH)
        end)
        nvgSave(nvg)
        nvgTranslate(nvg, ox, oy)
        nvgScale(nvg, scale, scale)
    end

    -- 8. 狂欢槽进度侧条（舞台左侧内缘）
    local barX, barY, barW, barH = 20, 250, 12, 270
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, barX, barY, barW, barH, 6)
    nvgFillColor(nvg, Col(C.bgInset, 230))
    nvgFill(nvg)
    local fRatio = run.feverActive and min(1, run.feverTimer / Config.RULES.FEVER_DURATION) or min(1, run.fever / 100)
    local fh = (barH - 4) * fRatio
    if fh > 1 then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, barX + 2, barY + barH - 2 - fh, barW - 4, fh, 4)
        nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, barY, 0, barY + barH,
            Col(run.feverActive and C.gold or C.magenta, 255), Col(C.purple, 255)))
        nvgFill(nvg)
    end
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, barX, barY, barW, barH, 6)
    nvgStrokeColor(nvg, Col(run.feverActive and C.gold or C.magenta, 200))
    nvgStrokeWidth(nvg, 1.5)
    nvgStroke(nvg)

    -- 9. 舞台右侧连击计数牌（深色圆角胶囊底板，防止压线）
    if run.combo >= 2 then
        local pop = 1 + (fx.comboPop or 0) * 0.22
        local cx, cy = 304, 266
        nvgSave(nvg)
        nvgTranslate(nvg, cx, cy)
        nvgScale(nvg, pop, pop)
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, -30, -18, 60, 44, 10)
        nvgFillColor(nvg, Col(C.bgInset, 225))
        nvgFill(nvg)
        local cCol = (run.combo >= 30) and C.magenta or ((run.combo >= 15) and C.gold or C.cyan)
        nvgStrokeColor(nvg, Col(cCol, 220))
        nvgStrokeWidth(nvg, 1.6)
        nvgStroke(nvg)
        nvgFontFace(nvg, g.font or "sans")
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFontSize(nvg, 20)
        nvgFillColor(nvg, Col(cCol, 255))
        nvgText(nvg, 0, -4, tostring(run.combo) .. "x")
        nvgFontSize(nvg, 12)
        nvgFillColor(nvg, Col(C.white, 220))
        nvgText(nvg, 0, 14, "连击")
        nvgRestore(nvg)
    end

    -- 10. 首次点按引导（前3次点击内）
    if g.showTapHint and g.showTapHint() then
        local pulse = 0.5 + 0.5 * sin(t * 5.5)
        local hy = 415 + pulse * 10
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, 100, hy - 16, 160, 32, 16)
        nvgFillColor(nvg, Col(C.bgInset, 215))
        nvgFill(nvg)
        nvgStrokeColor(nvg, Col(C.gold, 230))
        nvgStrokeWidth(nvg, 1.8)
        nvgStroke(nvg)
        nvgFontFace(nvg, g.font or "sans")
        nvgFontSize(nvg, 13)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, Col(C.gold, 255))
        nvgText(nvg, 180, hy, "点按推台 狂暴加投!")
    end

    if boostOn then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, 18, 16, 74, 22, 8)
        nvgFillColor(nvg, Col(C.magDark, 230))
        nvgFill(nvg)
        nvgStrokeColor(nvg, Col(C.magenta, 230))
        nvgStrokeWidth(nvg, 1.4)
        nvgStroke(nvg)
        nvgFontFace(nvg, g.font or "sans")
        nvgFontSize(nvg, 11)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, Col(C.gold, 255))
        nvgText(nvg, 55, 27, "×3 印钞中")
    end

    -- 10.5 过门 3 轴抽奖机台与幸运狂潮倍率倒计时条
    DrawSlotBar(nvg, run, t, g.font)

    -- 11. 狂欢边缘流光与横幅叠层（3D 特效已经在上面 RenderWorld 投射）
    if not is3D then
        -- 保持 2D 模式一致调用顺序
    end
    fx:RenderOverlay(nvg, W, H, g.font, run)

    nvgRestore(nvg)
end

return Stage
