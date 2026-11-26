-- ============================================================================
-- Fx.lua  满屏暴击特效系统（预分配对象池，零每帧表创建）
--   · SoA 粒子池 320 / 冲击环 32 / 闪电链 24 / 分级描边暴击飘字 96 / 飞币 48
--   · 顿帧 / 屏幕震动 / 狂欢彩虹屏边光环 / 连击牌弹跳
-- ============================================================================

local Config = require("game/Config")
local Skin = require("game/Skin")
local Number = require("game/Number")

local floor, min, max, sqrt, sin, cos, random, pi =
    math.floor, math.min, math.max, math.sqrt, math.sin, math.cos, math.random, math.pi
local Col = Skin.Col
local C = Skin.C

local Fx = {}
Fx.__index = Fx

local MAX_PARTICLES = 320
local MAX_RINGS = 32
local MAX_BOLTS = 24
local MAX_POPS = 96
local MAX_BANNERS = 1

-- 飘字颜色分级（白 → 霓虹青 → 黄金 → 烈焰橙红 → 霓虹紫）
local TIER_COLORS = {
    { 245, 250, 255 },
    { 72, 234, 255 },
    { 255, 218, 70 },
    { 255, 118, 56 },
    { 238, 108, 255 },
}
local TIER_SIZES = { 16, 20, 25, 30, 36 }
local OUTLINE_COL = { 8, 10, 24 }

function Fx.New()
    local self = setmetatable({}, Fx)
    self.time = 0
    self.trauma = 0
    self.shakeX = 0
    self.shakeY = 0
    self.hitstop = 0
    self.flashA = 0
    self.flashCol = C.gold
    self.feverGlow = 0
    self.comboPop = 0
    self.banner = { t = 0, dur = 0, text = "", col = C.gold }

    -- 粒子池 (SoA)
    self.pX, self.pY, self.pVX, self.pVY = {}, {}, {}, {}
    self.pLife, self.pMax, self.pSize, self.pCol = {}, {}, {}, {}
    for i = 1, MAX_PARTICLES do
        self.pX[i], self.pY[i], self.pVX[i], self.pVY[i] = 0, 0, 0, 0
        self.pLife[i], self.pMax[i], self.pSize[i], self.pCol[i] = 0, 1, 2, C.gold
    end
    self.pCursor = 0

    -- 冲击环池
    self.rings = {}
    for i = 1, MAX_RINGS do
        self.rings[i] = { life = 0, max = 1, x = 0, y = 0, r0 = 4, r1 = 40, col = C.cyan, w = 2.5 }
    end
    self.ringCursor = 0

    -- 闪电池
    self.bolts = {}
    for i = 1, MAX_BOLTS do
        self.bolts[i] = { life = 0, max = 0.25, x1 = 0, y1 = 0, x2 = 0, y2 = 0, mx = 0, my = 0, col = C.cyan }
    end
    self.boltCursor = 0

    -- 分级暴击飘字池
    self.pops = {}
    for i = 1, MAX_POPS do
        self.pops[i] = {
            life = 0, max = 1, x = 0, y = 0, vx = 0, vy = 0,
            text = "", size = 16, col = TIER_COLORS[1], scale = 1,
        }
    end
    self.popCursor = 0

    return self
end

function Fx:Clear()
    self.trauma = 0
    self.shakeX, self.shakeY = 0, 0
    self.hitstop = 0
    self.flashA = 0
    self.banner.t = 0
    for i = 1, MAX_PARTICLES do self.pLife[i] = 0 end
    for i = 1, MAX_RINGS do self.rings[i].life = 0 end
    for i = 1, MAX_BOLTS do self.bolts[i].life = 0 end
    for i = 1, MAX_POPS do self.pops[i].life = 0 end
end

function Fx:SpawnBurst(x, y, count, col, speed, size)
    speed = speed or 130
    size = size or 3.2
    col = col or C.gold
    for _ = 1, count do
        self.pCursor = (self.pCursor % MAX_PARTICLES) + 1
        local i = self.pCursor
        local ang = random() * pi * 2
        local spd = speed * (0.35 + random() * 0.85)
        self.pX[i], self.pY[i] = x, y
        self.pVX[i], self.pVY[i] = cos(ang) * spd, sin(ang) * spd - 25
        self.pLife[i] = 0.35 + random() * 0.35
        self.pMax[i] = self.pLife[i]
        self.pSize[i] = size * (0.7 + random() * 0.7)
        self.pCol[i] = col
    end
end

function Fx:SpawnRing(x, y, r0, r1, col, dur, w)
    self.ringCursor = (self.ringCursor % MAX_RINGS) + 1
    local r = self.rings[self.ringCursor]
    r.life = dur or 0.32
    r.max = r.life
    r.x, r.y = x, y
    r.r0, r.r1 = r0 or 6, r1 or 52
    r.col = col or C.cyan
    r.w = w or 2.5
end

function Fx:SpawnBolt(x1, y1, x2, y2, col)
    self.boltCursor = (self.boltCursor % MAX_BOLTS) + 1
    local b = self.bolts[self.boltCursor]
    b.life = 0.24
    b.max = 0.24
    b.x1, b.y1, b.x2, b.y2 = x1, y1, x2, y2
    b.mx = (x1 + x2) * 0.5 + (random() - 0.5) * 26
    b.my = (y1 + y2) * 0.5 + (random() - 0.5) * 20
    b.col = col or C.cyan
end

function Fx:SpawnPopup(x, y, text, tier, isCrit)
    self.popCursor = (self.popCursor % MAX_POPS) + 1
    local p = self.pops[self.popCursor]
    local tIdx = max(1, min(5, tier or 1))
    p.life = isCrit and 0.95 or 0.78
    p.max = p.life
    p.x = max(36, min(Config.WORLD_W - 36, x + (random() - 0.5) * 22))
    p.y = max(38, min(Config.WORLD_H - 32, y - random() * 10))
    p.vx = (random() - 0.5) * 28
    p.vy = -(48 + tIdx * 8 + (isCrit and 18 or 0))
    p.text = text
    p.size = TIER_SIZES[tIdx] + (isCrit and 5 or 0)
    p.col = isCrit and C.gold or TIER_COLORS[tIdx]
    p.scale = isCrit and 1.35 or 1.1
end

function Fx:ShowBanner(text, col, dur)
    self.banner.text = text or ""
    self.banner.col = col or C.gold
    self.banner.dur = dur or 1.4
    self.banner.t = self.banner.dur
end

-- ----------------------------------------------------------------------------
-- Run 事件接收口
-- ----------------------------------------------------------------------------
function Fx:OnLevelLoaded(run)
    self:Clear()
    self.feverGlow = run.feverActive and 1 or 0
    local actCfg = Config.ACTS[run.act]
    self:ShowBanner((actCfg and actCfg.name or "第" .. run.act .. "幕") .. " · 关" .. run.layer, C.cyan, 1.5)
end

function Fx:OnShoot(coin, run)
    self:SpawnBurst(coin.x, coin.y, 5, C.cyan, 80, 2.4)
end

function Fx:OnPegHit(coin, peg)
    local pDef = Config.PEG_TYPES[peg.kind] or Config.PEG_TYPES.normal
    self:SpawnBurst(peg.x, peg.y, 4, pDef.col, 90, 2.5)
    if peg.kind ~= "normal" then
        self:SpawnRing(peg.x, peg.y, 4, 24, pDef.col, 0.24, 2)
    end
end

function Fx:OnSplit(x, y, cnt)
    self:SpawnRing(x, y, 6, 30, C.green, 0.28, 2.2)
    self:SpawnBurst(x, y, 10, C.green, 120, 2.8)
end

function Fx:OnGateWin(coin, rewardName)
    self:SpawnRing(coin.x, coin.y, 8, 56, C.gold, 0.42, 3.5)
    self:SpawnBurst(coin.x, coin.y, 18, C.gold, 175, 3.6)
    self:SpawnPopup(coin.x, coin.y - 16, rewardName or "中奖!", 3, true)
    self.trauma = min(1, self.trauma + 0.25)
    self.flashA = max(self.flashA, 70)
    self.flashCol = C.gold
end

function Fx:OnGateBounce(coin)
    self:SpawnBurst(coin.x, coin.y, 4, C.magenta, 80, 2.2)
end

function Fx:OnCoinLandDeck(coin)
    self:SpawnBurst(coin.x, coin.y, 5, C.white, 65, 2.0)
end

function Fx:OnScore(dmg, x, y, crit, combo, tag)
    if tag == "peg" and dmg < 50 then
        if random() < 0.28 then
            self:SpawnPopup(x, y, "+" .. Number.FormatNum(dmg), 1, false)
        end
        return
    end
    local tier = Number.ScoreTier(dmg)
    local prefix = crit and "暴击! +" or "+"
    self:SpawnPopup(x, y, prefix .. Number.FormatNum(dmg), tier, crit)
    if crit then
        self.trauma = min(1, self.trauma + 0.16)
        self:SpawnRing(x, y, 5, 36, C.gold, 0.26, 2.2)
    end
end

function Fx:OnFrontDrop(coin, dmg, crit)
    local def = Config.COINS[coin.kind] or Config.COINS.gold
    self:SpawnBurst(coin.x, Config.STAGE.DECK_BOT_Y, crit and 16 or 9, def.color.glow, 150, 3.2)
    if crit or dmg >= 5000 then
        self:SpawnRing(coin.x, Config.STAGE.DECK_BOT_Y, 6, 44, C.gold, 0.3, 2.6)
    end
end

function Fx:OnSideDrain(coin)
    self:SpawnBurst(coin.x, coin.y, 6, C.red, 85, 2.2)
end

function Fx:OnLightning(x1, y1, x2, y2)
    self:SpawnBolt(x1, y1, x2, y2, C.cyan)
    self:SpawnBurst(x2, y2, 6, C.cyan, 110, 2.5)
end

function Fx:OnExplosion(x, y, rad)
    self:SpawnRing(x, y, 10, rad, C.magenta, 0.36, 4.0)
    self:SpawnRing(x, y, 6, rad * 0.72, C.gold, 0.28, 2.5)
    self:SpawnBurst(x, y, 24, C.magenta, 210, 4.0)
    self.trauma = min(1, self.trauma + 0.48)
    self.hitstop = max(self.hitstop, 0.032)
    self.flashA = max(self.flashA, 90)
    self.flashCol = C.magenta
end

function Fx:OnBlackholeBurst(x, y, rad)
    self:SpawnRing(x, y, rad, 12, C.purple, 0.38, 3.5)
    self:SpawnBurst(x, y, 22, C.purple, 190, 3.6)
    self.trauma = min(1, self.trauma + 0.35)
end

function Fx:OnJackpot777(x, y)
    self:ShowBanner("777 狂飙大奖!", C.gold, 1.5)
    self:SpawnBurst(x, y, 28, C.gold, 220, 4.2)
    self.flashA = 120
    self.flashCol = C.gold
end

function Fx:OnFeverStart(run)
    self.feverGlow = 1
    self:ShowBanner("狂欢时刻! FEVER ×2", C.magenta, 1.8)
    self.flashA = 135
    self.flashCol = C.magenta
    self.trauma = 0.55
end

function Fx:OnFeverEnd(run)
    self.feverGlow = 0
end

function Fx:OnGoalMet(run)
    self:ShowBanner("目标达成! 继续狂刷", C.green, 1.5)
    self.flashA = 85
    self.flashCol = C.green
end

function Fx:OnCombo(combo)
    self.comboPop = 1.0
end

function Fx:OnBossAction(msg)
    self:ShowBanner(msg or "Boss 行动!", C.red, 1.5)
    self.trauma = min(1, self.trauma + 0.3)
end

function Fx:TimeScale()
    if self.hitstop > 0 then return 0.15 end
    return 1.0
end

function Fx:Update(dt)
    self.time = self.time + dt
    if self.hitstop > 0 then self.hitstop = max(0, self.hitstop - dt) end
    if self.comboPop > 0 then self.comboPop = max(0, self.comboPop - dt * 5) end
    if self.flashA > 0 then self.flashA = max(0, self.flashA - dt * 280) end
    if self.banner.t > 0 then self.banner.t = max(0, self.banner.t - dt) end

    if self.trauma > 0 then
        self.trauma = max(0, self.trauma - dt * 2.2)
        local mag = self.trauma * self.trauma * 7.5
        self.shakeX = (random() * 2 - 1) * mag
        self.shakeY = (random() * 2 - 1) * mag
    else
        self.shakeX, self.shakeY = 0, 0
    end

    for i = 1, MAX_PARTICLES do
        local life = self.pLife[i]
        if life > 0 then
            self.pLife[i] = life - dt
            self.pVY[i] = self.pVY[i] + 240 * dt
            self.pX[i] = self.pX[i] + self.pVX[i] * dt
            self.pY[i] = self.pY[i] + self.pVY[i] * dt
        end
    end

    for i = 1, MAX_RINGS do
        local r = self.rings[i]
        if r.life > 0 then r.life = max(0, r.life - dt) end
    end

    for i = 1, MAX_BOLTS do
        local b = self.bolts[i]
        if b.life > 0 then b.life = max(0, b.life - dt) end
    end

    for i = 1, MAX_POPS do
        local p = self.pops[i]
        if p.life > 0 then
            p.life = max(0, p.life - dt)
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
            p.vy = p.vy * (1 - 1.8 * dt)
            if p.scale > 1.0 then p.scale = max(1.0, p.scale - dt * 2.2) end
        end
    end
end

function Fx:RenderWorld(nvg, font)
    -- 冲击环
    for i = 1, MAX_RINGS do
        local r = self.rings[i]
        if r.life > 0 then
            local t = 1 - r.life / r.max
            local rad = r.r0 + (r.r1 - r.r0) * t
            local a = floor(220 * (1 - t))
            nvgBeginPath(nvg)
            nvgCircle(nvg, r.x, r.y, rad)
            nvgStrokeColor(nvg, Col(r.col, a))
            nvgStrokeWidth(nvg, r.w * (1 - t * 0.5))
            nvgStroke(nvg)
        end
    end

    -- 闪电链
    for i = 1, MAX_BOLTS do
        local b = self.bolts[i]
        if b.life > 0 then
            local a = floor(255 * (b.life / b.max))
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, b.x1, b.y1)
            nvgLineTo(nvg, b.mx, b.my)
            nvgLineTo(nvg, b.x2, b.y2)
            nvgStrokeColor(nvg, Col(b.col, a))
            nvgStrokeWidth(nvg, 3.2)
            nvgStroke(nvg)
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, b.x1, b.y1)
            nvgLineTo(nvg, b.mx, b.my)
            nvgLineTo(nvg, b.x2, b.y2)
            nvgStrokeColor(nvg, Col(C.white, a))
            nvgStrokeWidth(nvg, 1.3)
            nvgStroke(nvg)
        end
    end

    -- 粒子
    for i = 1, MAX_PARTICLES do
        local life = self.pLife[i]
        if life > 0 then
            local f = life / self.pMax[i]
            local sz = self.pSize[i] * (0.4 + 0.6 * f)
            nvgBeginPath(nvg)
            nvgCircle(nvg, self.pX[i], self.pY[i], sz)
            nvgFillColor(nvg, Col(self.pCol[i], floor(240 * f)))
            nvgFill(nvg)
        end
    end

    -- 满屏描边飘字
    nvgFontFace(nvg, font or "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    for i = 1, MAX_POPS do
        local p = self.pops[i]
        if p.life > 0 then
            local f = min(1, (p.life / p.max) * 1.45)
            local a = floor(255 * f)
            nvgFontSize(nvg, floor(p.size * p.scale))
            -- 描边阴影层
            nvgFillColor(nvg, Col(OUTLINE_COL, a))
            nvgText(nvg, p.x - 1.5, p.y, p.text)
            nvgText(nvg, p.x + 1.5, p.y, p.text)
            nvgText(nvg, p.x, p.y - 1.5, p.text)
            nvgText(nvg, p.x, p.y + 1.5, p.text)
            -- 主字层
            nvgFillColor(nvg, Col(p.col, a))
            nvgText(nvg, p.x, p.y, p.text)
        end
    end
end

function Fx:RenderOverlay(nvg, w, h, font, run)
    -- 全屏闪烁
    if self.flashA > 1 then
        nvgBeginPath(nvg)
        nvgRect(nvg, 0, 0, w, h)
        nvgFillColor(nvg, Col(self.flashCol, floor(self.flashA)))
        nvgFill(nvg)
    end

    -- 狂欢彩虹霓虹边框
    if run and run.feverActive then
        local pulse = 0.55 + 0.45 * sin(self.time * 12)
        local edgeCol = (floor(self.time * 5) % 2 == 0) and C.magenta or C.gold
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, 3, 3, w - 6, h - 6, 12)
        nvgStrokeColor(nvg, Col(edgeCol, floor(220 * pulse)))
        nvgStrokeWidth(nvg, 5)
        nvgStroke(nvg)
    end

    -- 横幅提示
    if self.banner.t > 0 then
        local prog = self.banner.t / self.banner.dur
        local alpha = floor(255 * min(1, prog * 3))
        local bw, bh = min(w - 28, 280), 40
        local bx, by = (w - bw) * 0.5, h * 0.34
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, bx, by, bw, bh, 12)
        nvgFillColor(nvg, Col(C.bgInset, floor(alpha * 0.92)))
        nvgFill(nvg)
        nvgStrokeColor(nvg, Col(self.banner.col, alpha))
        nvgStrokeWidth(nvg, 2.2)
        nvgStroke(nvg)
        nvgFontFace(nvg, font or "sans")
        nvgFontSize(nvg, 18)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, Col(self.banner.col, alpha))
        nvgText(nvg, w * 0.5, by + bh * 0.5, self.banner.text)
    end
end

return Fx
