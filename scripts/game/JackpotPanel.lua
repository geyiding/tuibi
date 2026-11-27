-- ============================================================================
-- JackpotPanel.lua  JP 宝藏舱（3D 机台前沿下方的空带）
--   · 左：九宫格老虎机（3 列滚轮 × 3 行，5 条中奖线；听牌时第三列拖长停轮）
--   · 右：JP 奖池（GRAND 大号滚动数字 + MAJOR/MINI 预估 + 7 盏 JP 灯 + 养分飘字）
--   · JP CHANCE：九宫格外圈 8 格变成跑灯抽奖盘（MINI/MAJOR/GRAND/NEXT），中心格显示倍数
--   · 全屏层：JP CHANCE 开场横幅、NEXT 升级、倾泻时屏幕中央的巨额数字滚动
-- ============================================================================

local Config = require("game/Config")
local Skin = require("game/Skin")
local Fx = require("game/Fx")
local Number = require("game/Number")
local Art = require("game/Art")

local C = Skin.C
local Col = Skin.Col
local floor, min, max, sin, abs, pi = math.floor, math.min, math.max, math.sin, math.abs, math.pi
local OutlinedText, SetAdditive, Rainbow, EstTextW, DrawStarPath =
    Fx.OutlinedText, Fx.SetAdditive, Fx.Rainbow, Fx.EstTextW, Fx.DrawStarPath

local JP = Config.JACKPOT
local LINES = Config.SLOT_LINES
local JP_SYM = Config.SLOT_JP_SYMBOL
local INK = { 10, 8, 26 }
local PANEL_TOP = { 30, 16, 60 }
local PANEL_BOT = { 10, 8, 28 }
local CELL_TOP = { 232, 234, 250 }
local CELL_BOT = { 170, 176, 208 }
local WELL = { 8, 10, 26 }
local GOLD_DEEP = { 196, 120, 20 }
local DEFAULT_LOCK_AT = { 0.45, 0.72, 0.95 }
-- 外圈 8 格（顺时针）对应的九宫格编号
local RING = { 1, 2, 3, 6, 9, 8, 7, 4 }

local JackpotPanel = {}

function JackpotPanel.New()
    return {
        shownPool = 0.0,
        poolKey = -1, poolTxt = "",
        tierKey = -1, tierTxt = "",
        lastPool = 0.0, feedAcc = 0.0, feedT = 0,
        feedPops = {},
        lampFlash = { 0, 0, 0, 0, 0, 0, 0 },
        lastLamps = 0,
        reelStop = { 0, 0, 0 },
        lastLock = { true, true, true },
        sideKey = "", sideTxt = "",
        relShown = 0.0, relKey = -1, relTxt = "",
        bannerKey = "", bannerTxt = "",
        hintKey = -2, hintTxt = "",
        rect = { x = 0, y = 0, w = 0, h = 0 },
    }
end

local function Money(v)
    return "¥" .. Number.FormatCompact(max(0, v or 0))
end

local TILE_SPRITE = { mini = "jp_tile_mini", major = "jp_tile_major", grand = "jp_tile_grand", next = "jp_tile_next" }
local function HasSprite(key) return Skin.SPRITES[key] ~= nil end

-- JP 宝箱符号（九宫格第 7 号符号）
function JackpotPanel.DrawChest(nvg, cx, cy, r, glow)
    local w, h = r * 1.55, r * 1.15
    local x0, y0 = cx - w * 0.5, cy - h * 0.38
    if glow and glow > 0 then
        SetAdditive(nvg, true)
        nvgBeginPath(nvg)
        nvgCircle(nvg, cx, cy, r * 1.6)
        nvgFillPaint(nvg, nvgRadialGradient(nvg, cx, cy, r * 0.3, r * 1.6, Col(C.gold, floor(150 * glow)), Col(C.gold, 0)))
        nvgFill(nvg)
        SetAdditive(nvg, false)
    end
    if HasSprite("slot_sym_7") then
        local s = r * 2.3
        if Art.DrawSprite(nvg, "slot_sym_7", cx - s * 0.5, cy - s * 0.5, s, s, 1.0) then return end
    end
    -- 箱体
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x0, y0, w, h * 0.72, r * 0.16)
    nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, y0, 0, y0 + h * 0.72, Col({ 176, 92, 40 }, 255), Col({ 110, 52, 22 }, 255)))
    nvgFill(nvg)
    -- 箱盖
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x0 - r * 0.06, y0 - h * 0.30, w + r * 0.12, h * 0.36, r * 0.22)
    nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, y0 - h * 0.30, 0, y0 + h * 0.06, Col({ 255, 226, 110 }, 255), Col(GOLD_DEEP, 255)))
    nvgFill(nvg)
    -- 金箍
    nvgBeginPath(nvg)
    nvgRect(nvg, x0 + w * 0.42, y0 - h * 0.30, w * 0.16, h * 1.02)
    nvgFillColor(nvg, Col(C.gold, 255))
    nvgFill(nvg)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x0, y0, w, h * 0.72, r * 0.16)
    nvgStrokeColor(nvg, Col(INK, 220))
    nvgStrokeWidth(nvg, 1.2)
    nvgStroke(nvg)
    -- “JP” 字样
    nvgFontSize(nvg, r * 0.78)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    OutlinedText(nvg, cx, y0 + h * 0.36, "JP", C.white, 255, 1.0)
end

local function CellRect(gx, gy, cell, gap, idx)
    local col = (idx - 1) % 3
    local row = floor((idx - 1) / 3)
    return gx + col * (cell + gap), gy + row * (cell + gap)
end

local function DrawCellBg(nvg, x, y, s, lit, litCol)
    if HasSprite("slot_cell") and Art.DrawSprite(nvg, "slot_cell", x, y, s, s, 1.0) then
        if lit then
            SetAdditive(nvg, true)
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, x, y, s, s, s * 0.16)
            nvgFillColor(nvg, Col(litCol or C.gold, 140))
            nvgFill(nvg)
            SetAdditive(nvg, false)
        end
        return
    end
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x, y, s, s, s * 0.16)
    if lit then
        nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, y, 0, y + s, Col(C.white, 255), Col(litCol or C.gold, 255)))
    else
        nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, y, 0, y + s, Col(CELL_TOP, 255), Col(CELL_BOT, 255)))
    end
    nvgFill(nvg)
end

-- ----------------------------------------------------------------------------
-- 九宫格：普通转动模式
-- ----------------------------------------------------------------------------
local function DrawSlotGrid(st, nvg, run, gx, gy, cell, gap, u, t, font, drawSym)
    local spin = run.slotSpinning == true
    local ratio = spin and max(0, min(1, (run.slotSpinT or 0) / max(0.01, run.slotSpinDur or 0.85))) or 1
    local lockAt = run.slotLockAt or DEFAULT_LOCK_AT
    local grid = run.slotGrid
    local symR = cell * 0.36
    local reachCol = spin and run.slotLockAt ~= nil and ratio >= lockAt[2] and ratio < lockAt[3]
    for c = 1, 3 do
        local x = gx + (c - 1) * (cell + gap)
        local locked = (not spin) or (ratio >= lockAt[c])
        if locked and not st.lastLock[c] then st.reelStop[c] = 1 end
        st.lastLock[c] = locked
        local colH = cell * 3 + gap * 2
        -- 听牌：第三列高亮跑马
        if reachCol and c == 3 then
            SetAdditive(nvg, true)
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, x - 4 * u, gy - 4 * u, cell + 8 * u, colH + 8 * u, 8 * u)
            local rc = (floor(t * 10) % 2 == 0) and C.gold or C.magenta
            nvgFillPaint(nvg, nvgBoxGradient(nvg, x, gy, cell, colH, 6 * u, 10 * u, Col(rc, 200), Col(rc, 0)))
            nvgFill(nvg)
            SetAdditive(nvg, false)
        end
        for r = 1, 3 do
            local y = gy + (r - 1) * (cell + gap)
            DrawCellBg(nvg, x, y, cell, false)
        end
        nvgSave(nvg)
        nvgIntersectScissor(nvg, x, gy, cell, colH)
        if locked then
            local b = st.reelStop[c]
            local yOff = -sin(b * pi) * 6 * u * b
            for r = 1, 3 do
                local idx = (r - 1) * 3 + c
                local sym = (grid and grid[idx]) or 1
                local cx, cy = x + cell * 0.5, gy + (r - 1) * (cell + gap) + cell * 0.5 + yOff
                if sym == JP_SYM then
                    JackpotPanel.DrawChest(nvg, cx, cy, symR, (not spin) and (0.5 + 0.5 * sin(t * 6)) or 0)
                else
                    drawSym(nvg, sym, cx, cy, symR, font)
                end
            end
        else
            -- 滚动：整列符号带循环下落 + 速度残影
            local speed = (reachCol and c == 3) and 7 or 16
            local sp = t * speed + c * 0.37
            local frac = sp - floor(sp)
            local base = floor(sp)
            for k = -1, 3 do
                local sym = ((base - k + c * 2) % 6) + 1
                local cy = gy + (k + frac) * (cell + gap) + cell * 0.5
                drawSym(nvg, sym, x + cell * 0.5, cy, symR, font)
            end
            nvgBeginPath(nvg)
            nvgRect(nvg, x, gy, cell, colH)
            nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, gy, 0, gy + colH, Col(C.white, 120), Col(C.white, 20)))
            nvgFill(nvg)
        end
        -- 玻璃上下阴影
        nvgBeginPath(nvg)
        nvgRect(nvg, x, gy, cell, cell * 0.35)
        nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, gy, 0, gy + cell * 0.35, Col(WELL, 150), Col(WELL, 0)))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgRect(nvg, x, gy + colH - cell * 0.35, cell, cell * 0.35)
        nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, gy + colH - cell * 0.35, 0, gy + colH, Col(WELL, 0), Col(WELL, 150)))
        nvgFill(nvg)
        nvgRestore(nvg)
        if st.reelStop[c] > 0 then st.reelStop[c] = max(0, st.reelStop[c] - 0.06) end
    end

    -- 中奖线高亮（停轮后保持到下一次转动）
    local wl = (not spin) and run.slotWinLine
    if wl and LINES[wl] then
        local ln = LINES[wl]
        local reels = run.slotReels or {}
        local prizeCol = C.gold
        local sCfg = Config.SLOT_SYMBOLS[reels[1] or 1]
        if sCfg and sCfg.col then prizeCol = sCfg.col end
        local flash = (run.slotFlashT or 0) > 0 and (0.6 + 0.4 * sin(t * 18)) or 0.75
        local pts = {}
        for k = 1, 3 do
            local x, y = CellRect(gx, gy, cell, gap, ln[k])
            pts[k] = { x + cell * 0.5, y + cell * 0.5 }
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, x - 1.5, y - 1.5, cell + 3, cell + 3, cell * 0.18)
            nvgStrokeColor(nvg, Col(prizeCol, floor(255 * flash)))
            nvgStrokeWidth(nvg, 2.6 * u)
            nvgStroke(nvg)
        end
        SetAdditive(nvg, true)
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, pts[1][1], pts[1][2])
        nvgLineTo(nvg, pts[2][1], pts[2][2])
        nvgLineTo(nvg, pts[3][1], pts[3][2])
        nvgStrokeColor(nvg, Col(prizeCol, floor(200 * flash)))
        nvgStrokeWidth(nvg, 4 * u)
        nvgStroke(nvg)
        SetAdditive(nvg, false)
    end
end

-- ----------------------------------------------------------------------------
-- 九宫格：JP CHANCE 跑灯抽奖盘
-- ----------------------------------------------------------------------------
local function DrawLotteryBoard(st, nvg, run, gx, gy, cell, gap, u, t, font)
    local ph = run.jpPhase
    local lit = run.jpCell or 1
    local resultOn = (ph == "result" or ph == "release")
    local blink = (floor(t * 12) % 2 == 0)
    for i, gIdx in ipairs(RING) do
        local tierId = JP.BOARD[i]
        local tier = JP.TIERS[tierId] or JP.TIERS.mini
        local x, y = CellRect(gx, gy, cell, gap, gIdx)
        local isLit
        if ph == "intro" then
            isLit = ((floor(t * 14) + i) % 4 == 0)
        else
            isLit = (i == lit) and (not resultOn or blink or ph == "release")
        end
        local tileKey = TILE_SPRITE[tierId]
        local useTile = tileKey and HasSprite(tileKey) and Art.DrawSprite(nvg, tileKey, x, y, cell, cell, 1.0)
        if not useTile then DrawCellBg(nvg, x, y, cell, isLit, tier.col) end
        if not isLit then
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, x, y, cell, cell, cell * 0.16)
            nvgFillColor(nvg, Col(INK, useTile and 165 or 150))
            nvgFill(nvg)
        elseif useTile then
            SetAdditive(nvg, true)
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, x, y, cell, cell, cell * 0.16)
            nvgFillColor(nvg, Col(C.white, 70))
            nvgFill(nvg)
            SetAdditive(nvg, false)
        end
        if not useTile then
            nvgFontSize(nvg, cell * ((tierId == "next") and 0.30 or 0.27))
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            local label = (tierId == "next") and "NEXT" or string.upper(tierId)
            if isLit then
                OutlinedText(nvg, x + cell * 0.5, y + cell * 0.40, label, INK, 255, 1.2, C.white)
            else
                OutlinedText(nvg, x + cell * 0.5, y + cell * 0.40, label, tier.col, 255, 1.2)
            end
            nvgFontSize(nvg, cell * 0.20)
            local sub = (tierId == "next") and "倍数+1" or "JP"
            nvgFillColor(nvg, Col(isLit and INK or C.white, 230))
            nvgText(nvg, x + cell * 0.5, y + cell * 0.72, sub)
        end
        if isLit and ph ~= "intro" then
            SetAdditive(nvg, true)
            nvgBeginPath(nvg)
            nvgRect(nvg, x - cell * 0.4, y - cell * 0.4, cell * 1.8, cell * 1.8)
            nvgFillPaint(nvg, nvgBoxGradient(nvg, x, y, cell, cell, cell * 0.16, cell * 0.35, Col(tier.col, 190), Col(tier.col, 0)))
            nvgFill(nvg)
            SetAdditive(nvg, false)
        end
    end
    -- 中心格：当前倍数
    local x, y = CellRect(gx, gy, cell, gap, 5)
    if not (HasSprite("slot_center") and Art.DrawSprite(nvg, "slot_center", x, y, cell, cell, 1.0)) then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x, y, cell, cell, cell * 0.16)
        nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, y, 0, y + cell, Col({ 70, 24, 120 }, 255), Col(INK, 255)))
        nvgFill(nvg)
    end
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x, y, cell, cell, cell * 0.16)
    nvgStrokeColor(nvg, Col(Rainbow(t * 4), 255))
    nvgStrokeWidth(nvg, 2 * u)
    nvgStroke(nvg)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(nvg, cell * 0.24)
    nvgFillColor(nvg, Col(C.white, 230))
    nvgText(nvg, x + cell * 0.5, y + cell * 0.28, "JP倍数")
    nvgFontSize(nvg, cell * 0.42)
    OutlinedText(nvg, x + cell * 0.5, y + cell * 0.64, "×" .. tostring(run.jpBonus or 1), C.gold, 255, 1.4)
end

-- ----------------------------------------------------------------------------
-- 面板主体（返回九宫格中心作为飞行令牌锚点）
-- ----------------------------------------------------------------------------
function JackpotPanel.Draw(st, nvg, run, l, topY, u, t, dt, font, drawSym)
    local avail = (l.y + l.h - 6) - topY
    local ph = max(100 * u, min(150 * u, avail))
    local py = min(topY, l.y + l.h - ph - 6)
    local pw = min(l.w - 12, 376 * u)
    local px = l.x + (l.w - pw) * 0.5
    local k = ph / (150 * u)
    st.rect.x, st.rect.y, st.rect.w, st.rect.h = px, py, pw, ph
    local jpOn = run.jpPhase ~= nil
    local lamps = run.jpLamps or 0
    local nearFull = (not jpOn) and lamps >= JP.LAMPS - 1

    -- 外框：霓虹机台面板
    local border = jpOn and Rainbow(t * 5) or (nearFull and ((floor(t * 6) % 2 == 0) and C.gold or C.magenta) or C.gold)
    SetAdditive(nvg, true)
    nvgBeginPath(nvg)
    nvgRect(nvg, px - 16, py - 16, pw + 32, ph + 32)
    nvgFillPaint(nvg, nvgBoxGradient(nvg, px, py, pw, ph, 14 * u, 22 * u, Col(border, jpOn and 160 or 70), Col(border, 0)))
    nvgFill(nvg)
    SetAdditive(nvg, false)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, px, py, pw, ph, 14 * u)
    nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, py, 0, py + ph, Col(PANEL_TOP, 245), Col(PANEL_BOT, 250)))
    nvgFill(nvg)
    nvgStrokeColor(nvg, Col(border, 255))
    nvgStrokeWidth(nvg, 2.4 * u)
    nvgStroke(nvg)
    -- 顶边灯珠
    local nb = 18
    local phase = floor(t * (jpOn and 20 or 5))
    SetAdditive(nvg, true)
    for b = 0, nb - 1 do
        local bx = px + 14 * u + (pw - 28 * u) * b / (nb - 1)
        local on = ((b + phase) % 3 == 0)
        nvgBeginPath(nvg)
        nvgCircle(nvg, bx, py, on and 2.6 * u or 1.6 * u)
        nvgCircle(nvg, bx, py + ph, on and 2.6 * u or 1.6 * u)
        nvgFillColor(nvg, Col(jpOn and Rainbow(b + phase) or C.gold, on and 255 or 90))
        nvgFill(nvg)
    end
    SetAdditive(nvg, false)

    -- 左：九宫格
    local pad = 9 * u * k
    local gs = ph - pad * 2
    local gap = 3 * u * k
    local cell = (gs - gap * 2) / 3
    local gx, gy = px + pad, py + pad
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, gx - 3, gy - 3, gs + 6, gs + 6, 8 * u)
    nvgFillColor(nvg, Col(WELL, 255))
    nvgFill(nvg)
    if jpOn then
        DrawLotteryBoard(st, nvg, run, gx, gy, cell, gap, u, t, font)
    else
        DrawSlotGrid(st, nvg, run, gx, gy, cell, gap, u, t, font, drawSym)
    end

    -- 右：奖池信息
    local rx = gx + gs + 12 * u
    local rw = px + pw - pad - rx
    nvgFontFace(nvg, font or "sans")

    -- (1) 标题 + 状态
    local spin = run.slotSpinning == true
    local q = run.slotQueue or 0
    local sideKey = (jpOn and ("jp" .. tostring(run.jpPhase)) or ((spin and "s" or "i") .. q)) .. (nearFull and "n" or "")
    if sideKey ~= st.sideKey then
        st.sideKey = sideKey
        if jpOn then
            st.sideTxt = "JP CHANCE!"
        elseif spin then
            st.sideTxt = (run.slotLockAt ~= nil) and "听牌!!" or "转动中"
        elseif q > 0 then
            st.sideTxt = "待转+" .. tostring(q)
        else
            st.sideTxt = "过门转九宫格"
        end
    end
    local innerH = ph - pad * 2
    local ty0 = py + pad + 8 * u * k
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFontSize(nvg, 13 * u * k)
    OutlinedText(nvg, rx, ty0, "JP 奖池 · GRAND", C.gold, 255, 1.2)
    nvgTextAlign(nvg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFontSize(nvg, 11.5 * u * k)
    local sCol = (jpOn or (spin and run.slotLockAt ~= nil)) and ((floor(t * 8) % 2 == 0) and C.gold or C.magenta) or C.muted
    OutlinedText(nvg, rx + rw, ty0, st.sideTxt, sCol, 255, 1.1)

    -- (2) GRAND 奖池大数字（显示值追随实际值；养分时轻微脉冲）
    local pool = run.jpPool or 0
    local shown = st.shownPool
    if pool < shown * 0.5 or shown <= 0 then
        shown = pool
    else
        shown = shown + (pool - shown) * min(1, dt * 4)
    end
    st.shownPool = shown
    local grow = pool - (st.lastPool or pool)
    st.lastPool = pool
    if grow > 0 then st.feedAcc = st.feedAcc + grow end
    local key = floor(shown / max(1, 10 ^ max(0, floor(math.log(max(shown, 1), 10)) - 3)))
    if key ~= st.poolKey then
        st.poolKey = key
        st.poolTxt = Money(shown)
    end
    local amtY = py + pad + innerH * 0.33
    local pulse = min(1, st.feedT > 0 and st.feedT * 3 or 0)
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local fs = 30 * u * k * (1 + pulse * 0.06)
    local tw = EstTextW(st.poolTxt, fs)
    if tw > rw then fs = fs * rw / tw end
    nvgFontSize(nvg, fs)
    OutlinedText(nvg, rx, amtY, st.poolTxt, jpOn and Rainbow(t * 4) or C.gold, 255, 2.2)

    -- 养分飘字：每 0.9 秒汇总一次注入量
    st.feedT = max(0, (st.feedT or 0) - dt)
    st.feedClock = (st.feedClock or 0) + dt
    if st.feedClock >= 0.9 then
        st.feedClock = 0
        if st.feedAcc > 0 and not jpOn then
            local pops = st.feedPops
            if #pops < 4 then
                pops[#pops + 1] = { age = 0, txt = "+" .. Money(st.feedAcc) }
            end
            st.feedT = 0.35
        end
        st.feedAcc = 0
    end
    local pops = st.feedPops
    local i = 1
    while i <= #pops do
        local p = pops[i]
        p.age = p.age + dt
        if p.age >= 1.1 then
            table.remove(pops, i)
        else
            local a = (p.age < 0.8) and 1 or (1 - (p.age - 0.8) / 0.3)
            nvgTextAlign(nvg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            nvgFontSize(nvg, 10.5 * u * k)
            OutlinedText(nvg, rx + rw, amtY - 13 * u * k - p.age * 14 * u, p.txt, C.green, floor(230 * a), 1.0)
            i = i + 1
        end
    end

    -- (3) MAJOR / MINI 预估
    local tierKey = floor(math.log(max(1, run:GetJpTierAmount("major")), 10) * 300) * 1000
        + floor(math.log(max(1, run:GetJpTierAmount("mini")), 10) * 300)
    if tierKey ~= st.tierKey then
        st.tierKey = tierKey
        st.tierTxt = "MAJOR " .. Money(run:GetJpTierAmount("major")) .. "  MINI " .. Money(run:GetJpTierAmount("mini"))
    end
    local tierY = py + pad + innerH * 0.53
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local tfs = 11 * u * k
    local ttw = EstTextW(st.tierTxt, tfs)
    if ttw > rw then tfs = tfs * rw / ttw end
    nvgFontSize(nvg, tfs)
    nvgFillColor(nvg, Col(C.white, 200))
    nvgText(nvg, rx, tierY, st.tierTxt)

    -- (4) 7 盏 JP 灯
    if lamps > (st.lastLamps or 0) then
        for li = (st.lastLamps or 0) + 1, min(JP.LAMPS, lamps) do st.lampFlash[li] = 1 end
    end
    st.lastLamps = lamps
    local lampY = py + ph - pad - 11 * u * k
    local lampR = min(9 * u * k, (rw - 4 * u) / (JP.LAMPS * 2.5))
    local lampGap = (rw - lampR * 2) / (JP.LAMPS - 1)
    for li = 1, JP.LAMPS do
        local lx = rx + lampR + (li - 1) * lampGap
        local on = jpOn or li <= lamps
        local fl = st.lampFlash[li] or 0
        if fl > 0 then st.lampFlash[li] = max(0, fl - dt * 1.6) end
        local lc = jpOn and Rainbow(t * 6 + li) or C.gold
        if on then
            SetAdditive(nvg, true)
            nvgBeginPath(nvg)
            nvgCircle(nvg, lx, lampY, lampR * (2.0 + fl * 1.5))
            nvgFillPaint(nvg, nvgRadialGradient(nvg, lx, lampY, lampR * 0.4, lampR * (2.0 + fl * 1.5), Col(lc, floor(150 + fl * 100)), Col(lc, 0)))
            nvgFill(nvg)
            SetAdditive(nvg, false)
        end
        nvgBeginPath(nvg)
        nvgCircle(nvg, lx, lampY, lampR * (1 + fl * 0.35))
        if on then
            nvgFillPaint(nvg, nvgRadialGradient(nvg, lx - lampR * 0.3, lampY - lampR * 0.3, 0, lampR * 1.3, Col(C.white, 255), Col(lc, 255)))
        else
            local blinkNext = nearFull and li == lamps + 1 and (floor(t * 6) % 2 == 0)
            nvgFillColor(nvg, Col(blinkNext and { 120, 90, 20 } or { 44, 40, 70 }, 255))
        end
        nvgFill(nvg)
        nvgStrokeColor(nvg, Col(on and C.white or { 90, 86, 130 }, 200))
        nvgStrokeWidth(nvg, 1)
        nvgStroke(nvg)
    end
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFontSize(nvg, 10 * u * k)
    local hintKey = jpOn and -1 or lamps
    if hintKey ~= st.hintKey then
        st.hintKey = hintKey
        if jpOn then
            st.hintTxt = "JP 灯全亮 · 抽奖中"
        elseif nearFull then
            st.hintTxt = "差 1 盏灯进 JP CHANCE!!"
        else
            st.hintTxt = string.format("宝箱点灯 %d/%d · 集满进 JP CHANCE", lamps, JP.LAMPS)
        end
    end
    nvgFillColor(nvg, Col(nearFull and C.gold or C.muted, 255))
    nvgText(nvg, rx, py + pad + innerH * 0.72, st.hintTxt)

    return gx + gs * 0.5, gy + gs * 0.5
end

-- ----------------------------------------------------------------------------
-- 全屏层：JP CHANCE 横幅 / NEXT / 倾泻巨额数字
-- ----------------------------------------------------------------------------
function JackpotPanel.DrawOverlay(st, nvg, run, l, u, t, dt, font)
    local ph = run.jpPhase
    if not ph then
        st.relShown = 0
        return
    end
    local cx = l.x + l.w * 0.5
    local cy = l.y + l.h * 0.40
    nvgFontFace(nvg, font or "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    if ph == "intro" or ph == "spin" or ph == "result" then
        -- 全场压暗，聚焦九宫格
        -- 九宫格是聚光灯：只压暗面板以外的区域
        local dim = (ph == "intro") and min(1, (run.jpT or 0) * 3) or 1
        local rc = st.rect
        nvgBeginPath(nvg)
        nvgRect(nvg, l.x, l.y, l.w, max(0, rc.y - 8 - l.y))
        nvgRect(nvg, l.x, rc.y + rc.h + 8, l.w, max(0, l.y + l.h - rc.y - rc.h - 8))
        nvgFillColor(nvg, Col(INK, floor(130 * dim)))
        nvgFill(nvg)
        local bx = cx
        local by = l.y + l.h * ((ph == "intro") and 0.40 or 0.30)
        local pop = (ph == "intro") and (1 + max(0, 0.35 - (run.jpT or 0)) * 2.2) or 1
        local bw, bh = min(l.w - 20, 320 * u) * pop, 70 * u * pop
        SetAdditive(nvg, true)
        nvgBeginPath(nvg)
        nvgEllipse(nvg, bx, by, bw * 0.75, bh * 1.2)
        nvgFillPaint(nvg, nvgRadialGradient(nvg, bx, by, bh * 0.2, bw * 0.75, Col(Rainbow(t * 3), 120), Col(C.gold, 0)))
        nvgFill(nvg)
        SetAdditive(nvg, false)
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, bx - bw * 0.5, by - bh * 0.5, bw, bh, 16 * u)
        nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, by - bh * 0.5, 0, by + bh * 0.5, Col(PANEL_TOP, 240), Col(PANEL_BOT, 245)))
        nvgFill(nvg)
        nvgStrokeColor(nvg, Col(Rainbow(t * 5), 255))
        nvgStrokeWidth(nvg, 3 * u)
        nvgStroke(nvg)
        nvgFontSize(nvg, 34 * u * pop)
        OutlinedText(nvg, bx, by - 8 * u * pop, "JP CHANCE!!", C.gold, 255, 2.4)
        local key = tostring(run.jpRound or 1) .. ":" .. tostring(run.jpBonus or 1) .. ":" .. ph .. ":" .. tostring(run.jpResult)
        if key ~= st.bannerKey then
            st.bannerKey = key
            if ph == "result" and run.jpResult == "next" then
                st.bannerTxt = "NEXT!! JP 倍数升到 ×" .. tostring((run.jpBonus or 1) + 1)
            elseif ph == "result" then
                local tier = JP.TIERS[run.jpResult or "mini"]
                st.bannerTxt = (tier and tier.name or "JP") .. " 命中!!"
            elseif (run.jpRound or 1) > 1 then
                st.bannerTxt = string.format("第 %d 轮 · 倍数 ×%d · 冲 GRAND!", run.jpRound, run.jpBonus or 1)
            else
                st.bannerTxt = "GRAND " .. Money(run.jpPool) .. " 等你来拿"
            end
        end
        nvgFontSize(nvg, 14 * u * pop)
        local subCol = (ph == "result") and (JP.TIERS[run.jpResult or "mini"] or JP.TIERS.mini).col or C.white
        OutlinedText(nvg, bx, by + 20 * u * pop, st.bannerTxt, subCol, 255, 1.4)
        return
    end

    -- 倾泻：屏幕中央巨额数字从 0 滚到派奖额
    local pay = run.jpPayout
    if not pay then return end
    local tt = run.jpT or 0
    local x = min(1, tt / 1.6)
    local e = 1 - (1 - x) ^ 3
    local val = (pay.amount or 0) * e
    local rk = floor(val / max(1, (pay.amount or 1) / 400))
    if rk ~= st.relKey then
        st.relKey = rk
        st.relTxt = "+" .. Money(val)
    end
    local tierCol = pay.col or C.gold
    local fade = (tt > JP.RELEASE_SEC - 0.5) and max(0, (JP.RELEASE_SEC - tt) / 0.5) or 1
    -- 旋转光芒
    SetAdditive(nvg, true)
    local rays = 14
    local rr = min(l.w, l.h) * 0.62
    for i = 0, rays - 1 do
        local a0 = t * 0.8 + i * (2 * pi / rays)
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, cx, cy)
        nvgLineTo(nvg, cx + math.cos(a0) * rr, cy + sin(a0) * rr)
        nvgLineTo(nvg, cx + math.cos(a0 + 0.13) * rr, cy + sin(a0 + 0.13) * rr)
        nvgClosePath(nvg)
        nvgFillPaint(nvg, nvgRadialGradient(nvg, cx, cy, 10, rr, Col(tierCol, floor(110 * fade)), Col(tierCol, 0)))
        nvgFill(nvg)
    end
    SetAdditive(nvg, false)
    local pop = 1 + max(0, 0.3 - tt) * 2.5
    nvgFontSize(nvg, 40 * u * pop)
    OutlinedText(nvg, cx, cy - 34 * u, (pay.name or "JP") .. "!!", tierCol, floor(255 * fade), 2.8)
    if (pay.bonus or 1) > 1 then
        nvgFontSize(nvg, 18 * u)
        OutlinedText(nvg, cx, cy - 2 * u, "NEXT 倍数 ×" .. tostring(pay.bonus), C.green, floor(255 * fade), 1.6)
    end
    local fs = 44 * u
    local tw = EstTextW(st.relTxt, fs)
    if tw > l.w - 24 then fs = fs * (l.w - 24) / tw end
    nvgFontSize(nvg, fs)
    OutlinedText(nvg, cx, cy + 34 * u, st.relTxt, (x >= 1 and floor(t * 10) % 2 == 0) and C.white or C.gold, floor(255 * fade), 3.0)
    nvgFontSize(nvg, 14 * u)
    OutlinedText(nvg, cx, cy + 66 * u, "奖池倾泻！金币瀑布砸向推台", C.white, floor(230 * fade), 1.2)
end

return JackpotPanel
