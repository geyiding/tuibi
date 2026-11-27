-- ============================================================================
-- Fx.lua  爽感特效总线（全屏幕空间渲染，3D / 2D 舞台共用一条路径）
--   · 分级爆分飘字：近邻合并滚数 + ×倍率戳 + 暴击角标 + T4/T5 光芒星爆
--   · 粒子：辉光点 / 火花拖尾 / 四芒星 / 翻转金币 / 彩纸（SoA 预分配，零每帧建表）
--   · 冲击环 / 闪光盘 / 锯齿闪电（三层辉光）
--   · 飞币入账：掉落处金币沿弧线飞进顶部现金计数器（计数器被“砸”一下）
--   · 倍率令牌：狂欢 / 三连 / 印钞 / 连击 / 永久 增益化作“×N”令牌飞入倍率招牌
--   · 中央重磅印章：FEVER / 大奖 / 超越 / 解锁 / 上市，带光芒、残影、冲击波
--   · 全屏闪光、狂欢霓虹暗角、热度边缘光、屏震、顿帧、镜头冲击（供 Machine3D 读取）
-- ============================================================================

local Config = require("game/Config")
local Skin = require("game/Skin")
local Number = require("game/Number")

local floor, min, max, sqrt, sin, cos, random, pi, abs =
    math.floor, math.min, math.max, math.sqrt, math.sin, math.cos, math.random, math.pi, math.abs
local Col = Skin.Col
local C = Skin.C

local Fx = {}
Fx.__index = Fx

local MAX_P = 200
local MAX_RINGS = 16
local MAX_BOLTS = 12
local BOLT_PTS = 8
local MAX_POPS = 26
local MAX_SPOPS = 8
local MAX_FLY = 40
local MAX_TOK = 6
local MAX_STAMP_Q = 3

-- 粒子种类
local K_DOT, K_SPARK, K_STAR, K_COIN, K_CONF = 1, 2, 3, 4, 5

-- 常量色（固定表，Skin.Col 可缓存 NVGcolor）
local WHITE = C.white
local GOLD = C.gold
local CYAN = C.cyan
local MAGENTA = C.magenta
local PURPLE = C.purple
local GREEN = C.green
local RED = C.red
local ORANGE = { 255, 132, 44 }
local HOT = { 255, 236, 150 }
local INK = { 10, 8, 26 }
local INK2 = { 30, 14, 52 }
local COIN_FACE = { 255, 214, 72 }
local COIN_RIM = { 196, 120, 18 }
local COIN_HI = { 255, 248, 200 }
local RAINBOW = {
    { 255, 72, 96 }, { 255, 140, 40 }, { 255, 214, 64 }, { 120, 240, 90 },
    { 56, 224, 255 }, { 110, 130, 255 }, { 196, 96, 255 }, { 255, 80, 196 },
}
local CONF_COLS = { GOLD, MAGENTA, CYAN, GREEN, ORANGE, PURPLE, WHITE }

-- 飘字分级（以“无临时加成”的基准产值为参照，倍率越高越容易冲上高阶）
local TIER_COL = { WHITE, CYAN, GOLD, ORANGE, MAGENTA }
local TIER_SIZE = { 14, 17, 21, 26, 32 }
local TIER_LIFE = { 0.62, 0.78, 1.0, 1.25, 1.55 }

local function EaseOutBack(t)
    local c1 = 1.70158
    local c3 = c1 + 1
    local u = t - 1
    return 1 + c3 * u * u * u + c1 * u * u
end

local function EaseOutCubic(t)
    local u = 1 - t
    return 1 - u * u * u
end

--- 估算单行文字宽度（中日韩全角≈字号，ASCII≈0.58 字号）
local function EstTextW(s, fs)
    local w = 0
    local i, n = 1, #s
    while i <= n do
        local b = s:byte(i)
        if b < 128 then
            w = w + fs * 0.58
            i = i + 1
        else
            w = w + fs
            if b >= 240 then i = i + 4 elseif b >= 224 then i = i + 3 else i = i + 2 end
        end
    end
    return w
end
Fx.EstTextW = EstTextW

local function Rainbow(t)
    return RAINBOW[(floor(t) % #RAINBOW) + 1]
end
Fx.Rainbow = Rainbow

--- 描边文字：4 向暗色描边 + 下投影 + 主色（仅 3 级以上使用完整描边）
local function OutlinedText(nvg, x, y, text, col, a, ow, outlineCol)
    local oc = outlineCol or INK
    ow = ow or 2
    nvgFillColor(nvg, Col(oc, a))
    nvgText(nvg, x - ow, y, text)
    nvgText(nvg, x + ow, y, text)
    nvgText(nvg, x, y - ow, text)
    nvgText(nvg, x, y + ow + 1, text)
    nvgFillColor(nvg, Col(col, a))
    nvgText(nvg, x, y, text)
end
Fx.OutlinedText = OutlinedText

local function SetAdditive(nvg, on)
    if type(nvgGlobalCompositeOperation) == "function" and NVG_LIGHTER ~= nil then
        nvgGlobalCompositeOperation(nvg, on and NVG_LIGHTER or (NVG_SOURCE_OVER or 0))
    end
end
Fx.SetAdditive = SetAdditive

local function DrawStarPath(nvg, x, y, r, rot, sharp)
    local inner = r * (sharp or 0.28)
    for k = 0, 7 do
        local ang = rot + k * (pi * 0.25)
        local rr = (k % 2 == 0) and r or inner
        local px, py = x + cos(ang) * rr, y + sin(ang) * rr
        if k == 0 then nvgMoveTo(nvg, px, py) else nvgLineTo(nvg, px, py) end
    end
    nvgClosePath(nvg)
end
Fx.DrawStarPath = DrawStarPath

--- 光芒（星爆射线），n 条三角扇面
local function DrawRays(nvg, x, y, r0, r1, n, rot, col, a)
    nvgBeginPath(nvg)
    local half = pi / n * 0.45
    for k = 0, n - 1 do
        local ang = rot + k * (2 * pi / n)
        nvgMoveTo(nvg, x + cos(ang) * r0, y + sin(ang) * r0)
        nvgLineTo(nvg, x + cos(ang - half) * r1, y + sin(ang - half) * r1)
        nvgLineTo(nvg, x + cos(ang + half) * r1, y + sin(ang + half) * r1)
        nvgClosePath(nvg)
    end
    nvgFillPaint(nvg, nvgRadialGradient(nvg, x, y, r0, r1, Col(col, a), Col(col, 0)))
    nvgFill(nvg)
end
Fx.DrawRays = DrawRays

--- 小型金币（飞币 / 粒子币 / 图标共用）
local function DrawMiniCoin(nvg, x, y, r, spin, a)
    local sq = max(0.18, abs(cos(spin)))
    nvgBeginPath(nvg)
    nvgEllipse(nvg, x, y + r * 0.18, r * sq, r)
    nvgFillColor(nvg, Col(COIN_RIM, a))
    nvgFill(nvg)
    nvgBeginPath(nvg)
    nvgEllipse(nvg, x, y, r * sq, r)
    nvgFillColor(nvg, Col(COIN_FACE, a))
    nvgFill(nvg)
    if sq > 0.45 then
        nvgBeginPath(nvg)
        nvgEllipse(nvg, x - r * 0.22 * sq, y - r * 0.28, r * 0.32 * sq, r * 0.22)
        nvgFillColor(nvg, Col(COIN_HI, floor(a * 0.85)))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgEllipse(nvg, x, y, r * 0.64 * sq, r * 0.64)
        nvgStrokeColor(nvg, Col(COIN_RIM, floor(a * 0.7)))
        nvgStrokeWidth(nvg, max(0.8, r * 0.12))
        nvgStroke(nvg)
    end
end
Fx.DrawMiniCoin = DrawMiniCoin

-- ----------------------------------------------------------------------------
-- 构造
-- ----------------------------------------------------------------------------
function Fx.New()
    local self = setmetatable({}, Fx)
    self.time = 0
    self.trauma = 0
    self.shakeX, self.shakeY = 0, 0
    self.hitstop = 0
    self.flashA = 0
    self.flashCol = GOLD
    self.feverGlow = 0
    self.feverOn = false
    self.heat = 0            -- 0..1 临时倍率热度（连击 × 狂欢 × 三连 × 印钞）
    self.comboPop = 0
    self.kick = 0            -- 镜头冲击（Machine3D 读取做 FOV 收缩）
    self.lightFlash = 0      -- 机台点光闪烁强度
    self.lightCol = GOLD
    self.activePopCount = 0
    self.ws = 1.0            -- 世界->屏幕尺寸比例（Stage 每帧写入）
    self.screenW, self.screenH = 390, 844
    self.modalOpen = false
    self.quality = 1.0       -- 1 = 高画质；0.5 = 低端机（粒子减半、去辉光晕圈）
    -- 强反馈预算（每秒回充）：屏震 / 闪光 / 镜头冲击不论事件多密集都不会常驻
    self.shakeBudget = 0.8
    self.flashBudget = 160
    self.kickBudget = 1.0
    self.hitstopCd = 0
    self.lastSlotStampM = 1
    self.lastSlotStampT = -99

    -- 世界坐标 -> 屏幕坐标（Stage 绑定；无 Stage 时恒等映射）
    self.toScreen = nil

    -- 锚点（屏幕坐标，由 Stage / HUD 每帧刷新）
    self.ancCashX, self.ancCashY = 120, 40
    self.ancMultX, self.ancMultY = 195, 170
    self.ancSlotX, self.ancSlotY = 195, 225
    self.ancFeverX, self.ancFeverY = 40, 300
    self.ancComboX, self.ancComboY = 350, 300
    self.ancAdX, self.ancAdY = 340, 130
    self.ancDropY = 600

    -- HUD 消费的“被砸”计数
    self.cashHits = 0
    self.cashHitTier = 0
    self.multHits = 0
    self.multHitCol = GOLD

    -- 倍率追踪
    self.mtInit = false
    self.mtFever = false
    self.mtLuck = 1
    self.mtAd = false
    self.mtSurprise = 1
    self.mtComboStep = 0
    self.mtPerm = 1
    self.multTotal = 1
    self.multTemp = 1

    -- 粒子池 (SoA)
    self.pX, self.pY, self.pVX, self.pVY = {}, {}, {}, {}
    self.pLife, self.pMax, self.pSize, self.pCol = {}, {}, {}, {}
    self.pKind, self.pGrav, self.pDrag, self.pRot, self.pVR = {}, {}, {}, {}, {}
    for i = 1, MAX_P do
        self.pX[i], self.pY[i], self.pVX[i], self.pVY[i] = 0, 0, 0, 0
        self.pLife[i], self.pMax[i], self.pSize[i], self.pCol[i] = 0, 1, 2, GOLD
        self.pKind[i], self.pGrav[i], self.pDrag[i], self.pRot[i], self.pVR[i] = K_DOT, 0, 0, 0, 0
    end
    self.pCursor = 0

    self.rings = {}
    for i = 1, MAX_RINGS do
        self.rings[i] = { life = 0, max = 1, x = 0, y = 0, r0 = 4, r1 = 40, col = CYAN, w = 2.5, disc = false }
    end
    self.ringCursor = 0

    self.bolts = {}
    for i = 1, MAX_BOLTS do
        local b = { life = 0, max = 0.3, col = CYAN, px = {}, py = {} }
        for k = 1, BOLT_PTS do b.px[k], b.py[k] = 0, 0 end
        self.bolts[i] = b
    end
    self.boltCursor = 0

    self.pops = {}
    for i = 1, MAX_POPS do
        self.pops[i] = {
            life = 0, max = 1, age = 0, x = 0, y = 0, vx = 0, vy = 0,
            val = 0, text = "", tier = 1, crit = false, tag = "", size = 16, col = WHITE, tw = 0,
            multTxt = "", multW = 0, punch = 0,
        }
    end
    self.popCursor = 0

    self.spops = {}
    for i = 1, MAX_SPOPS do
        self.spops[i] = { life = 0, max = 1, x = 0, y = 0, text = "", col = GOLD, size = 18 }
    end
    self.spopCursor = 0

    self.fly = {}
    for i = 1, MAX_FLY do
        self.fly[i] = { on = false, age = 0, dur = 0.6, sx = 0, sy = 0, cx = 0, cy = 0, spin = 0, r = 7 }
    end
    self.flyCursor = 0

    self.tokens = {}
    for i = 1, MAX_TOK do
        self.tokens[i] = { on = false, age = 0, dur = 0.7, sx = 0, sy = 0, cx = 0, cy = 0, text = "", col = GOLD, w = 60 }
    end
    self.tokCursor = 0

    -- 中央印章（当前 + 等待队列）
    self.stamp = { on = false, age = 0, dur = 1.4, title = "", sub = "", col = GOLD, prio = 0, big = false, tw = 0, kind = "" }
    self.stampQ = {}
    for i = 1, MAX_STAMP_Q do
        self.stampQ[i] = { on = false, dur = 1.2, title = "", sub = "", col = GOLD, prio = 0, big = false, kind = "" }
    end

    -- 兼容旧横幅接口
    self.banner = { t = 0, dur = 0, text = "", col = GOLD }

    -- 世界排名超越演出（顶栏排名计数器锚点 / 被砸计数 / 实时排名文字）
    self.ancRankX, self.ancRankY = 100, 90
    self.rankHits = 0
    self.liveRankTxt = ""
    return self
end

--- 原地重置所有瞬态特效（保留 Stage / HUD / FxLayer 持有的同一 Fx 引用与锚点）
function Fx:Reset()
    self.time = 0
    self.trauma = 0
    self.shakeX, self.shakeY = 0, 0
    self.hitstop = 0
    self.flashA = 0
    self.flashCol = GOLD
    self.feverGlow = 0
    self.feverOn = false
    self.heat = 0
    self.comboPop = 0
    self.kick = 0
    self.lightFlash = 0
    self.lightCol = GOLD
    self.activePopCount = 0
    self.modalOpen = false
    self.shakeBudget = 0.8
    self.flashBudget = 160
    self.kickBudget = 1.0
    self.hitstopCd = 0
    self.lastSlotStampM = 1
    self.lastSlotStampT = -99

    self.cashHits = 0
    self.cashHitTier = 0
    self.multHits = 0
    self.multHitCol = GOLD
    self.rankHits = 0
    self.liveRankTxt = ""

    self.mtInit = false
    self.mtFever = false
    self.mtLuck = 1
    self.mtAd = false
    self.mtSurprise = 1
    self.mtComboStep = 0
    self.mtPerm = 1
    self.multTotal = 1
    self.multTemp = 1

    for i = 1, MAX_P do self.pLife[i] = 0 end
    self.pCursor = 0
    for i = 1, MAX_RINGS do self.rings[i].life = 0 end
    self.ringCursor = 0
    for i = 1, MAX_BOLTS do self.bolts[i].life = 0 end
    self.boltCursor = 0
    for i = 1, MAX_POPS do self.pops[i].life = 0 end
    self.popCursor = 0
    for i = 1, MAX_SPOPS do self.spops[i].life = 0 end
    self.spopCursor = 0
    for i = 1, MAX_FLY do self.fly[i].on = false end
    self.flyCursor = 0
    for i = 1, MAX_TOK do self.tokens[i].on = false end
    self.tokCursor = 0
    self.stamp.on = false
    for i = 1, MAX_STAMP_Q do self.stampQ[i].on = false end
    self.banner.t = 0
    self.banner.dur = 0
    self.banner.text = ""
end

--- 预算化强反馈：force=true 用于里程碑级事件（FEVER / 大奖 / 上市）
function Fx:AddTrauma(v, force)
    if not force then
        v = min(v, self.shakeBudget)
        self.shakeBudget = self.shakeBudget - v
    end
    if v > 0 then self.trauma = min(1, self.trauma + v) end
end

function Fx:AddFlash(a, col, force)
    if not force then
        a = min(a, self.flashBudget)
        self.flashBudget = self.flashBudget - a
    end
    if a > self.flashA then
        self.flashA = a
        self.flashCol = col or GOLD
    end
end

function Fx:AddKick(v, force)
    if not force then
        v = min(v, self.kickBudget)
        self.kickBudget = self.kickBudget - v
    end
    if v > 0 then self.kick = min(1, self.kick + v) end
end

function Fx:AddHitstop(sec)
    if self.hitstopCd > 0 then return end
    self.hitstop = max(self.hitstop, sec)
    self.hitstopCd = 2.0
end

--- 画质档位：1 高 / 0.5 低（低端机或连续掉帧时由外部调低）
function Fx:SetQuality(q)
    self.quality = (q and q < 0.75) and 0.5 or 1.0
end

function Fx:Clear()
    self.trauma = 0
    self.shakeX, self.shakeY = 0, 0
    self.hitstop = 0
    self.flashA = 0
    self.kick = 0
    self.lightFlash = 0
    for i = 1, MAX_P do self.pLife[i] = 0 end
    for i = 1, MAX_RINGS do self.rings[i].life = 0 end
    for i = 1, MAX_BOLTS do self.bolts[i].life = 0 end
    for i = 1, MAX_POPS do self.pops[i].life = 0 end
    for i = 1, MAX_SPOPS do self.spops[i].life = 0 end
    for i = 1, MAX_FLY do self.fly[i].on = false end
    for i = 1, MAX_TOK do self.tokens[i].on = false end
    self.stamp.on = false
    for i = 1, MAX_STAMP_Q do self.stampQ[i].on = false end
end

-- ----------------------------------------------------------------------------
-- 坐标
-- ----------------------------------------------------------------------------
function Fx:S(x, y)
    local f = self.toScreen
    if f then
        local sx, sy = f(x, y)
        if sx and sy then return sx, sy end
    end
    return x, y
end

-- ----------------------------------------------------------------------------
-- 生成器（全部屏幕坐标）
-- ----------------------------------------------------------------------------
function Fx:Emit(kind, x, y, vx, vy, life, size, col, grav, drag)
    self.pCursor = (self.pCursor % MAX_P) + 1
    local i = self.pCursor
    self.pKind[i] = kind
    self.pX[i], self.pY[i] = x, y
    self.pVX[i], self.pVY[i] = vx, vy
    self.pLife[i] = life
    self.pMax[i] = life
    self.pSize[i] = size
    self.pCol[i] = col
    self.pGrav[i] = grav or 0
    self.pDrag[i] = drag or 0
    self.pRot[i] = random() * pi * 2
    self.pVR[i] = (random() - 0.5) * 14
end

--- 爆发：火花 + 辉光点（+可选星光）
function Fx:Burst(x, y, count, col, speed, size, stars)
    local ws = self.ws
    speed = (speed or 140) * ws
    size = (size or 3) * ws
    col = col or GOLD
    count = math.ceil(count * self.quality)
    stars = floor((stars or 0) * self.quality)
    for k = 1, count do
        local ang = random() * pi * 2
        local spd = speed * (0.35 + random() * 0.9)
        local vx, vy = cos(ang) * spd, sin(ang) * spd - speed * 0.25
        if k % 3 == 0 then
            self:Emit(K_DOT, x, y, vx * 0.6, vy * 0.6, 0.35 + random() * 0.35, size * (0.8 + random() * 0.8), col, 260 * ws, 1.6)
        else
            self:Emit(K_SPARK, x, y, vx, vy, 0.3 + random() * 0.3, size * 0.7, (k % 4 == 0) and WHITE or col, 380 * ws, 2.2)
        end
    end
    for _ = 1, stars do
        local ang = random() * pi * 2
        local spd = speed * (0.2 + random() * 0.5)
        self:Emit(K_STAR, x, y, cos(ang) * spd, sin(ang) * spd - 30 * ws, 0.55 + random() * 0.4, size * (1.6 + random()), (random() < 0.5) and WHITE or col, 90 * ws, 1.2)
    end
end

--- 金币喷泉：真正“翻转的金币”向上喷射再落下
function Fx:CoinFountain(x, y, count, power)
    local ws = self.ws
    power = (power or 1) * ws
    for _ = 1, count do
        local vx = (random() - 0.5) * 220 * power
        local vy = -(220 + random() * 220) * power
        self:Emit(K_COIN, x, y, vx, vy, 0.8 + random() * 0.5, (5 + random() * 3) * ws, GOLD, 620 * ws, 0.6)
    end
end

--- 彩纸雨（屏幕上缘洒落）
function Fx:Confetti(count, x0, x1, y)
    local ws = self.ws
    for k = 1, count do
        local x = x0 + random() * (x1 - x0)
        self:Emit(K_CONF, x, y - random() * 40, (random() - 0.5) * 90, 60 + random() * 160, 1.4 + random() * 0.9,
            (3 + random() * 3) * ws, CONF_COLS[(k % #CONF_COLS) + 1], 140, 0.9)
    end
end

function Fx:Ring(x, y, r0, r1, col, dur, w, disc)
    self.ringCursor = (self.ringCursor % MAX_RINGS) + 1
    local r = self.rings[self.ringCursor]
    r.life = dur or 0.32
    r.max = r.life
    r.x, r.y = x, y
    r.r0, r.r1 = (r0 or 6) * self.ws, (r1 or 52) * self.ws
    r.col = col or CYAN
    r.w = (w or 2.5) * self.ws
    r.disc = disc == true
end

function Fx:Bolt(x1, y1, x2, y2, col)
    self.boltCursor = (self.boltCursor % MAX_BOLTS) + 1
    local b = self.bolts[self.boltCursor]
    b.life = 0.3
    b.max = 0.3
    b.col = col or CYAN
    local dx, dy = x2 - x1, y2 - y1
    local len = sqrt(dx * dx + dy * dy)
    local nx, ny = 0, 0
    if len > 0.01 then nx, ny = -dy / len, dx / len end
    local amp = min(22, len * 0.18)
    for k = 1, BOLT_PTS do
        local t = (k - 1) / (BOLT_PTS - 1)
        local off = (k == 1 or k == BOLT_PTS) and 0 or (random() - 0.5) * 2 * amp
        b.px[k] = x1 + dx * t + nx * off
        b.py[k] = y1 + dy * t + ny * off
    end
end

-- ----------------------------------------------------------------------------
-- 飘字（近邻合并 + ×倍率戳）
-- ----------------------------------------------------------------------------
local function CalcTier(dmg, refCps)
    local base = max(0.5, tonumber(refCps) or 1.0)
    local ratio = dmg / base
    if ratio >= 12 then return 5
    elseif ratio >= 4 then return 4
    elseif ratio >= 1.25 then return 3
    elseif ratio >= 0.35 then return 2
    end
    return 1
end
Fx.CalcTier = CalcTier

function Fx:SetPopText(p)
    p.text = "+" .. Number.FormatNum(p.val)
    p.size = TIER_SIZE[p.tier] + (p.crit and 4 or 0)
    p.col = TIER_COL[p.tier]
    p.tw = EstTextW(p.text, p.size)
end

function Fx:SpawnPop(sx, sy, val, tier, crit, tag, mult)
    -- 近邻合并：同来源短时间内、距离很近的飘字直接累加滚数；
    -- 高阶（T4+）爆分会被吸进同一个“大数字”持续滚动累加，避免满屏巨字互相遮挡
    for i = 1, MAX_POPS do
        local p = self.pops[i]
        local big = (tier >= 4 and p.tier >= 4)
        if p.life > 0 and p.tag == tag and p.age < (big and 0.6 or 0.3) then
            local dx, dy = p.x - sx, p.y - sy
            local rr = big and 170 or 46
            if dx * dx + dy * dy < rr * rr then
                p.val = p.val + val
                if tier > p.tier then p.tier = tier end
                p.crit = p.crit or crit
                self:SetPopText(p)
                p.punch = 1
                if big then p.age = min(p.age, 0.2) end
                p.life = max(p.life, TIER_LIFE[p.tier] * 0.85)
                p.max = max(p.max, p.life)
                return p
            end
        end
    end
    -- 拥挤时丢弃低阶字，保证高阶字清晰
    if tier <= 1 and self.activePopCount >= 12 then return nil end
    if tier <= 2 and self.activePopCount >= 20 then return nil end
    -- 优先复用已结束或最低阶的槽位
    local slot, worst = nil, 99
    for i = 1, MAX_POPS do
        local p = self.pops[i]
        if p.life <= 0 then slot = p; break end
        local score = p.tier + (1 - p.life / p.max)
        if score < worst then worst = score; slot = p end
    end
    local p = slot
    p.val = val
    p.tier = tier
    p.crit = crit
    p.tag = tag
    p.age = 0
    p.life = TIER_LIFE[tier] + (crit and 0.15 or 0)
    p.max = p.life
    p.x = max(44, min(self.screenW - 44, sx + (random() - 0.5) * 18))
    p.y = sy
    p.vx = (random() - 0.5) * 24
    p.vy = -(70 + tier * 16) * self.ws
    p.punch = 1
    if tier >= 3 and mult and mult >= 1.5 then
        p.multTxt = "×" .. Number.FormatMul(mult)
        p.multW = EstTextW(p.multTxt, 13 + tier) + 12
    else
        p.multTxt = ""
        p.multW = 0
    end
    self:SetPopText(p)
    return p
end

--- 屏幕 UI 飘字（购买 / 升级 / 技能点）
function Fx:UiPop(x, y, text, col, size)
    self.spopCursor = (self.spopCursor % MAX_SPOPS) + 1
    local p = self.spops[self.spopCursor]
    p.life = 1.1
    p.max = 1.1
    p.x, p.y = x, y
    p.text = text or ""
    p.col = col or GOLD
    p.size = size or 18
    p.isSp = false
end

--- 按钮 / 面板处的购买爆点
function Fx:UiBurst(x, y, w, h, text, col)
    local cx, cy = x + w * 0.5, y + h * 0.5
    col = col or GOLD
    local ws0 = self.ws
    self.ws = 1
    self:Burst(cx, cy, 16, col, 210, 3, 4)
    self:Ring(cx, cy, 6, max(w, h) * 0.75, col, 0.35, 3)
    self.ws = ws0
    if text then self:UiPop(cx, y - 4, text, col, 20) end
end

-- ----------------------------------------------------------------------------
-- 飞币 & 倍率令牌
-- ----------------------------------------------------------------------------
function Fx:FlyCoins(sx, sy, n)
    local tx, ty = self.ancCashX, self.ancCashY
    for k = 1, n do
        self.flyCursor = (self.flyCursor % MAX_FLY) + 1
        local f = self.fly[self.flyCursor]
        f.on = true
        f.age = -(k - 1) * 0.045
        f.dur = 0.55 + random() * 0.2
        f.sx = sx + (random() - 0.5) * 24
        f.sy = sy + (random() - 0.5) * 10
        -- 先向外侧上抛，再收束进计数器
        f.cx = (f.sx + tx) * 0.5 + (random() - 0.5) * 160
        f.cy = min(f.sy, ty) - 40 - random() * 90
        f.spin = random() * 6
        f.r = (6 + random() * 2.5) * self.ws
    end
end

function Fx:Token(sx, sy, text, col)
    self.tokCursor = (self.tokCursor % MAX_TOK) + 1
    local t = self.tokens[self.tokCursor]
    t.on = true
    t.age = 0
    t.dur = 0.75
    t.sx, t.sy = sx, sy
    local tx, ty = self.ancMultX, self.ancMultY
    t.cx = (sx + tx) * 0.5 + ((sx < tx) and -50 or 50)
    t.cy = min(sy, ty) - 70
    t.text = text
    t.col = col or GOLD
    t.w = EstTextW(text, 15) + 20
    self:Burst(sx, sy, 8, t.col, 120, 2.6, 2)
end

-- ----------------------------------------------------------------------------
-- 中央重磅印章
-- ----------------------------------------------------------------------------
function Fx:Stamp(title, sub, col, prio, dur, big, kind)
    prio = prio or 1
    kind = kind or title
    local st = self.stamp
    -- 同类印章刚结束 2.5s 内：降级为小飘字，避免高频事件（连续超越）让印章常驻
    if not st.on and st.kind == kind and (self.time - (self.stampEndT or -99)) < 2.5 then
        self:UiPop(self.screenW * 0.5, self.screenH * 0.3, title or "", col or GOLD, 18)
        return
    end
    if st.on then
        -- 同类印章（如连续超越）在显示中：直接刷新文字并续时，不再重复入场
        if st.kind == kind then
            st.title, st.sub, st.col = title or "", sub or "", col or GOLD
            st.dur = min(3.0, max(st.dur, st.age + (dur or 1.2) * 0.7))
            st.prio = max(st.prio, prio)
            return
        end
        -- 至少展示 0.8s 才允许被同级替换；更高优先级 0.35s 后可插队
        local canReplace = (prio > st.prio and st.age >= 0.35) or (prio >= st.prio and st.age >= 0.8)
        if not canReplace then
            local slot, low = nil, 99
            for i = 1, MAX_STAMP_Q do
                local q = self.stampQ[i]
                if q.on and q.kind == kind then slot = q; break end
                if not q.on then slot = q; low = -1; break end
                if q.prio < low then low = q.prio; slot = q end
            end
            if slot and (not slot.on or slot.kind == kind or slot.prio <= prio) then
                slot.on, slot.title, slot.sub, slot.col, slot.prio, slot.dur, slot.big, slot.kind =
                    true, title, sub or "", col or GOLD, prio, (dur or 1.2) * 0.8, big == true, kind
            end
            return
        end
    end
    st.on = true
    st.age = 0
    st.dur = dur or 1.3
    st.title = title or ""
    st.sub = sub or ""
    st.col = col or GOLD
    st.prio = prio
    st.big = big == true
    st.kind = kind
    local w, h = self.screenW, self.screenH
    self:Ring(w * 0.5, h * 0.36, 20, w * 0.62 / self.ws, st.col, 0.45, 5)
    self:AddTrauma(big and 0.55 or 0.25, big)
    self:AddKick(big and 0.9 or 0.45, big)
end

-- 兼容旧接口
function Fx:ShowBanner(text, col, dur)
    self:Stamp(text, "", col, 1, dur)
end

function Fx:SpawnBurst(x, y, count, col, speed, size)
    local sx, sy = self:S(x, y)
    self:Burst(sx, sy, count, col, speed, size, 0)
end

function Fx:SpawnRing(x, y, r0, r1, col, dur, w)
    local sx, sy = self:S(x, y)
    self:Ring(sx, sy, r0, r1, col, dur, w)
end

function Fx:SpawnBolt(x1, y1, x2, y2, col)
    local a, b = self:S(x1, y1)
    local c, d = self:S(x2, y2)
    self:Bolt(a, b, c, d, col)
end

function Fx:SpawnPopup(x, y, text, tier, isCrit)
    local sx, sy = self:S(x, y)
    self:UiPop(sx, sy, text, TIER_COL[max(1, min(5, tier or 1))], TIER_SIZE[max(1, min(5, tier or 1))])
end

-- ----------------------------------------------------------------------------
-- 倍率追踪：增益出现时化作令牌飞向倍率招牌
-- ----------------------------------------------------------------------------
function Fx:TrackMult(ty)
    if not ty or not ty.GetTotalMult then return end
    local total = ty:GetTotalMult()
    local perm = ty.GetPermMult and ty:GetPermMult() or 1
    local fever = ty.feverActive == true
    local luck = max(1, ty.luckMult or 1)
    local ad = (ty.adBoostLeft or 0) > 0
    local surp = max(1, ty.surpriseMult or 1)
    local comboFactor = (ty.HasTech and ty:HasTech("metronome")) and 0.012 or 0.008
    local comboM = 1 + min(100, ty.combo or 0) * comboFactor
    local comboStep = floor((comboM - 1) * 10 + 1e-6)
    self.multTotal = total
    local temp = total / max(1e-9, perm)
    self.multTemp = temp
    -- 热度：×1 -> 0，×10 -> 0.5，×100+ -> 1
    local h = min(1, max(0, math.log(max(1, temp), 10) * 0.5))
    self.heat = h

    if not self.mtInit then
        self.mtInit = true
        self.mtFever, self.mtLuck, self.mtAd, self.mtSurprise, self.mtComboStep, self.mtPerm =
            fever, luck, ad, surp, comboStep, perm
        return
    end
    if fever and not self.mtFever then
        self:Token(self.ancFeverX, self.ancFeverY, "狂欢 ×2.2", MAGENTA)
    end
    if luck > self.mtLuck + 0.01 then
        local luckTag = (luck < 1.99) and "对子 ×" or "三连 ×"
        self:Token(self.ancSlotX, self.ancSlotY, luckTag .. Number.FormatMul(luck), (luck >= 25) and GOLD or CYAN)
    end
    if ad and not self.mtAd then
        self:Token(self.ancAdX, self.ancAdY, "印钞 ×3", GREEN)
    end
    if surp > self.mtSurprise + 0.01 then
        self:Token(self.screenW * 0.5, self.screenH * 0.62, "奇遇 ×" .. Number.FormatMul(surp), ORANGE)
    end
    if comboStep > self.mtComboStep and comboStep > 0 then
        self:Token(self.ancComboX, self.ancComboY, "连击 ×" .. string.format("%.1f", comboM), CYAN)
        if comboStep % 3 == 0 then
            self:Stamp(tostring(ty.combo or 0) .. " 连击!", "连击倍率 ×" .. string.format("%.1f", comboM), CYAN, 1, 1.0, false, "combo")
        end
    end
    if perm > self.mtPerm * 1.0001 then
        local gain = perm / max(1e-9, self.mtPerm)
        self:Token(self.screenW * 0.5, self.screenH * 0.78, "永久 ×" .. Number.FormatMul(gain), GOLD)
    end
    self.mtFever, self.mtLuck, self.mtAd, self.mtSurprise, self.mtComboStep, self.mtPerm =
        fever, luck, ad, surp, comboStep, perm
end

-- ----------------------------------------------------------------------------
-- 游戏事件接收口
-- ----------------------------------------------------------------------------
function Fx:OnLevelLoaded(run)
    self:Clear()
end

function Fx:OnShoot(coin, run)
    if not coin then return end
    local sx, sy = self:S(coin.x, coin.y)
    self:Burst(sx, sy, 4, CYAN, 90, 2.2, 0)
    self:AddKick(0.04)
end

function Fx:OnTap(sx, sy)
    self:Ring(sx, sy, 4, 30, WHITE, 0.25, 2.2)
    self:Burst(sx, sy, 5, GOLD, 110, 2.2, 1)
end

function Fx:OnPegHit(coin, peg)
    local pDef = Config.PEG_TYPES[peg.kind] or Config.PEG_TYPES.normal
    local sx, sy = self:S(peg.x, peg.y)
    self:Burst(sx, sy, (peg.kind == "normal") and 3 or 6, pDef.col, 100, 2.2, (peg.kind == "normal") and 0 or 1)
    if peg.kind ~= "normal" then
        self:Ring(sx, sy, 3, 22, pDef.col, 0.24, 2)
    end
end

function Fx:OnSplit(x, y, cnt)
    local sx, sy = self:S(x, y)
    self:Ring(sx, sy, 6, 34, GREEN, 0.3, 2.5)
    self:Burst(sx, sy, 10, GREEN, 140, 2.6, 2)
end

function Fx:OnGateWin(coin, rewardName)
    local sx, sy = self:S(coin.x, coin.y)
    self:Ring(sx, sy, 8, 70, GOLD, 0.45, 4)
    self:Ring(sx, sy, 2, 40, HOT, 0.25, 0, true)
    self:Burst(sx, sy, 18, GOLD, 200, 3.2, 4)
    self:UiPop(sx, sy - 18, rewardName or "幸运门!", GOLD, 17)
    self:AddTrauma(0.2)
    self.lightFlash = max(self.lightFlash, 0.6)
    self.lightCol = GOLD
end

function Fx:OnGateBounce(coin)
    local sx, sy = self:S(coin.x, coin.y)
    self:Burst(sx, sy, 4, MAGENTA, 80, 2, 0)
end

function Fx:OnCoinLandDeck(coin)
    local sx, sy = self:S(coin.x, coin.y)
    self:Burst(sx, sy, 3, WHITE, 60, 1.8, 0)
end

function Fx:OnScore(dmg, x, y, crit, combo, tag, refCps, mult)
    local sx, sy = self:S(x, y)
    local tier = CalcTier(dmg, refCps)
    if tag == "peg" or tag == "thunder" or tag == "recycler" then
        -- 小额持续收入：只在不拥挤时显示，并且合并
        tier = min(tier, 2)
        if self.activePopCount >= 9 then return end
        self:SpawnPop(sx, sy, dmg, tier, crit, "s", nil)
        return
    end
    local p = self:SpawnPop(sx, sy - 10 * self.ws, dmg, tier, crit, "d", mult)
    if crit then
        self:AddTrauma(0.08 + tier * 0.03)
        self:Burst(sx, sy, 6 + tier * 2, GOLD, 150, 2.6, 1)
    end
    if tier >= 4 then
        self:Ring(sx, sy, 6, 46 + tier * 10, (tier >= 5) and MAGENTA or ORANGE, 0.38, 3.5)
        self:Burst(sx, sy, 10 + tier * 3, (tier >= 5) and MAGENTA or ORANGE, 220, 3.2, 3)
        self:AddTrauma(0.12 * (tier - 3))
        self:AddKick(0.18 * (tier - 3))
        self.lightFlash = max(self.lightFlash, 0.4 + 0.3 * (tier - 3))
        self.lightCol = (tier >= 5) and MAGENTA or ORANGE
    end
    if tier >= 5 then
        self:AddHitstop(0.05)
        self:AddFlash(70, MAGENTA)
    end
end

function Fx:OnFrontDrop(coin, dmg, crit)
    local def = Config.COINS[coin.kind] or Config.COINS.gold
    local sx, sy = self:S(coin.x, Config.STAGE.DECK_BOT_Y)
    local pop = nil
    for i = 1, MAX_POPS do
        local p = self.pops[i]
        if p.life > 0 and p.tag == "d" and p.age < 0.05 then pop = p end
    end
    local tier = pop and pop.tier or 2
    self:Burst(sx, sy, 5 + tier * 2, def.color.glow, 150, 2.8, (tier >= 3) and 2 or 0)
    if tier >= 3 then
        self:CoinFountain(sx, sy, tier - 1, 0.8 + tier * 0.1)
    end
    -- 飞币入账：每次掉落至少一枚，高阶多枚
    local n = (tier <= 1) and 1 or ((tier == 2) and 1 or ((tier == 3) and 2 or ((tier == 4) and 4 or 7)))
    self:FlyCoins(sx, sy, n)
end

function Fx:OnSideDrain(coin)
    local sx, sy = self:S(coin.x, coin.y)
    self:Burst(sx, sy, 5, RED, 80, 2, 0)
    -- 侧漏的币流进 JP 奖池：小金星飞向宝藏舱
    if self.ancJpX then
        self:Emit(K_STAR, sx, sy, (self.ancJpX - sx) * 1.6, (self.ancJpY - sy) * 1.6 - 60, 0.55, 3.2 * self.ws, GOLD, 120, 0.2)
    end
end

-- ----------------------------------------------------------------------------
-- JP 大奖池：点灯 / JP CHANCE / 跑灯定格 / 奖池倾泻
-- ----------------------------------------------------------------------------
function Fx:OnJpLamp(lamps, added)
    local x = self.ancJpX or self.screenW * 0.65
    local y = self.ancJpY or self.screenH * 0.85
    local near = (lamps or 0) >= (Config.JACKPOT.LAMPS - 1)
    self:Burst(x, y, 10 + (added or 1) * 6, GOLD, 190, 3.0, 4)
    self:Ring(x, y, 6, 60, GOLD, 0.4, 3)
    self:UiPop(x, y - 34, near and "JP 灯 差 1 盏!!" or ("JP 灯 +" .. tostring(added or 1) .. "!"), GOLD, near and 19 or 16)
    self.lightFlash = max(self.lightFlash, 0.6)
    self.lightCol = GOLD
end

function Fx:OnJpChance(pool, source)
    self:Confetti(36, 0, self.screenW, -10)
    self:AddFlash(170, GOLD, true)
    self:AddTrauma(0.45, true)
    self:AddKick(0.7, true)
    self:AddHitstop(0.1)
    self.lightFlash = 1.6
    self.lightCol = GOLD
    local x, y = self.ancSlotX or self.screenW * 0.25, self.ancSlotY or self.screenH * 0.85
    self:Ring(x, y, 10, 160, GOLD, 0.6, 5)
    self:Burst(x, y, 30, GOLD, 260, 3.6, 8)
end

function Fx:OnJpResult(tierId, round, bonus)
    local tier = Config.JACKPOT.TIERS[tierId] or Config.JACKPOT.TIERS.mini
    local col = tier.col or GOLD
    local x, y = self.ancSlotX or self.screenW * 0.25, self.ancSlotY or self.screenH * 0.85
    self:Ring(x, y, 8, 120, col, 0.5, 4)
    self:Burst(x, y, 24, col, 240, 3.4, 6)
    self:AddFlash((tierId == "grand") and 170 or 110, col, true)
    self.lightFlash = 1.3
    self.lightCol = col
    if tierId == "next" then
        self:UiPop(x, y - 60, "NEXT!! 倍数 ×" .. tostring((bonus or 1) + 1), GREEN, 22)
        self:AddKick(0.5, true)
    else
        self:AddHitstop(0.12)
    end
end

function Fx:OnJpRelease(payout)
    local tierId = payout and payout.tier or "mini"
    local col = (payout and payout.col) or GOLD
    local big = (tierId == "grand") or ((payout and payout.bonus or 1) >= 2)
    local w, h = self.screenW, self.screenH
    self:Confetti(big and 90 or 50, 0, w, -10)
    self:AddFlash(220, col, true)
    self:AddTrauma(big and 0.85 or 0.55, true)
    self:AddKick(1.0, true)
    self.lightFlash = 2.0
    self.lightCol = col
    local x, y = self.ancSlotX or w * 0.25, self.ancSlotY or h * 0.85
    self:CoinFountain(x, y, big and 26 or 16, 1.7)
    self:CoinFountain(w * 0.5, h * 0.42, big and 22 or 12, 1.5)
    self:Burst(w * 0.5, h * 0.42, 40, col, 340, 4.2, 10)
    self:Ring(w * 0.5, h * 0.42, 20, w * 0.7 / max(0.5, self.ws), col, 0.7, 6)
    self:FlyCoins(w * 0.5, h * 0.42, big and 30 or 18)
    self.heat = 1
end

function Fx:OnLightning(x1, y1, x2, y2)
    local a, b = self:S(x1, y1)
    local c, d = self:S(x2, y2)
    self:Bolt(a, b, c, d, CYAN)
    self:Burst(c, d, 6, CYAN, 120, 2.2, 1)
    self.lightFlash = max(self.lightFlash, 0.35)
    self.lightCol = CYAN
end

function Fx:OnExplosion(x, y, rad)
    local sx, sy = self:S(x, y)
    self:Ring(sx, sy, 4, rad * 0.9, HOT, 0.22, 0, true)
    self:Ring(sx, sy, 10, rad * 1.1, ORANGE, 0.4, 5)
    self:Ring(sx, sy, 6, rad * 0.7, MAGENTA, 0.3, 3)
    self:Burst(sx, sy, 26, ORANGE, 250, 3.6, 4)
    self:CoinFountain(sx, sy, 4, 1.0)
    self:AddTrauma(0.42)
    self:AddHitstop(0.035)
    self:AddFlash(60, ORANGE)
    self:AddKick(0.35)
    self.lightFlash = max(self.lightFlash, 0.9)
    self.lightCol = ORANGE
end

function Fx:OnBlackholeBurst(x, y, rad)
    local sx, sy = self:S(x, y)
    self:Ring(sx, sy, rad, 8, PURPLE, 0.4, 4)
    self:Ring(sx, sy, 6, rad * 1.2, MAGENTA, 0.45, 3)
    self:Burst(sx, sy, 22, PURPLE, 210, 3.2, 3)
    self:AddTrauma(0.32)
    self:AddKick(0.3)
end

function Fx:OnJackpot777(x, y)
    local sx, sy = self:S(x, y)
    self:CoinFountain(sx, sy, 10, 1.3)
    self:Burst(sx, sy, 20, GOLD, 240, 3.4, 5)
    self:Stamp("星耀爆发!", "星耀幸运 · 金币雨", GOLD, 3, 1.2)
    self:AddFlash(90, GOLD)
end

function Fx:OnRunnerHit(x, y, diceInfo)
    local sx, sy = self:S(x or 180, y or 540)
    self:Ring(sx, sy, 6, 75, GOLD, 0.42, 3.5)
    self:Ring(sx, sy, 10, 110, MAGENTA, 0.5, 2.5)
    self:Burst(sx, sy, 24, GOLD, 240, 3.4, 4)
    self:CoinFountain(sx, sy, 8, 1.2)
    self:AddFlash(110, GOLD, true)
    self:AddTrauma(0.28, true)
end

function Fx:OnBalloonPop(x, y, label, kind)
    local sx, sy = self:S(x or 180, y or 120)
    local col = (kind == "sp") and GREEN or GOLD
    self:Ring(sx, sy, 6, 85, col, 0.45, 3.0)
    self:Burst(sx, sy, 24, col, 240, 3.5, 4)
    self:Confetti(28, 0, self.screenW, -10)
    self:Stamp("黄金气球奇遇!", label or "超级惊喜!", col, 3, 1.5, true, "balloon")
    self:AddFlash(85, col, true)
end

function Fx:OnGoldRush(mult, dur)
    self:Confetti(42, 0, self.screenW, -10)
    self:AddFlash(150, GOLD, true)
    self:AddTrauma(0.45, true)
    self:AddKick(0.75, true)
    self:Stamp("黄金暴走突发!!",
        "奇遇 ×" .. tostring(mult or 10) .. " + 12枚高阶币雨 (" .. tostring(dur or 10) .. "秒)",
        ORANGE, 4, 1.8, true, "goldrush")
end

function Fx:OnSurpriseMult(mult, dur, name)
    if not mult or mult <= 1 then return end
    local cx, cy = self.screenW * 0.5, self.screenH * 0.58
    self:Burst(cx, cy, 18, ORANGE, 220, 3.2, 4)
    self:UiPop(cx, cy - 28, (name or "奇遇") .. " ×" .. Number.FormatMul(mult) .. " (" .. tostring(math.ceil(dur or 10)) .. "秒!)", ORANGE, 18)
end

function Fx:OnTowerLayer(x, y, layer, total, isCrown)
    local sx, sy = self:S(x or 180, y or 440)
    local hOff = (layer or 1) * 5
    local col = isCrown and MAGENTA or GOLD
    self:Burst(sx, sy - hOff, isCrown and 22 or 8, col, isCrown and 220 or 120, isCrown and 3.4 or 2.2, isCrown and 4 or 1)
    if isCrown then
        self:UiPop(sx, sy - hOff - 16, "45倍金库加冕!", GOLD, 18)
        self:AddKick(0.32, true)
    end
end

function Fx:OnTowerComplete(x, y, label)
    local sx, sy = self:S(x or 180, y or 440)
    self:Burst(sx, sy - 20, 18, GOLD, 190, 3.0, 3)
    self:Stamp(label or "金币塔落成！", "锁定稳固 · 即将推倒狂落!", GOLD, 3, 1.35, true, "tower_done")
end

function Fx:OnTowerTopple(x, y, label)
    local sx, sy = self:S(x or 180, y or 440)
    self:Burst(sx, sy, 28, ORANGE, 270, 3.8, 6)
    self:AddFlash(110, GOLD, true)
    self:AddTrauma(0.36, true)
    self:AddKick(0.55, true)
    self:UiPop(sx, sy - 26, "巨塔倾倒!! 全力推进!", ORANGE, 20)
end

function Fx:OnSlotWin(prize)
    if not prize then return end
    local m = prize.mult or 1
    local sx, sy = self.ancSlotX, self.ancSlotY
    if m <= 1 then
        self:UiPop(sx, sy + 22, "差一点!", WHITE, 15)
        return
    end
    local col = prize.col or GOLD
    -- 已处于同档或更高档幸运倍率时，重复大奖不再整屏印章（避免倍率常驻时刷屏），只给滚轮处爆点
    local fresh = (m > self.lastSlotStampM) or (self.time - self.lastSlotStampT > 10)
    if m >= 10 and not fresh then
        self:UiPop(sx, sy + 24, prize.label or ("×" .. tostring(m)), col, 18)
        self:Burst(sx, sy, 14, col, 200, 3, 3)
        self:CoinFountain(sx, sy, 4, 1.0)
        return
    end
    if m >= 10 then
        self.lastSlotStampM = m
        self.lastSlotStampT = self.time
    end
    if m >= 50 then
        self:Stamp(m >= 100 and "百倍狂潮!!" or "皇冠暴富!", "全场收益 ×" .. tostring(m), (m >= 100) and MAGENTA or GOLD, 5, 2.2, true, "slot")
        self:CoinFountain(sx, sy, 16, 1.5)
        self:Burst(sx, sy, 30, col, 300, 4, 8)
        self:Confetti(40, 0, self.screenW, -10)
        self:AddFlash(150, col)
        self:AddHitstop(0.08)
        self.lightFlash = 1.4
        self.lightCol = col
    elseif m >= 10 then
        self:Stamp("大奖 ×" .. tostring(m), prize.label or "", col, 4, 1.6, true, "slot")
        self:CoinFountain(sx, sy, 8, 1.2)
        self:Burst(sx, sy, 22, col, 240, 3.4, 5)
        self:AddFlash(95, col)
        self.lightFlash = 1.1
        self.lightCol = col
    elseif m >= 3 then
        self:UiPop(sx, sy + 24, prize.label or ("×" .. tostring(m)), col, 20)
        self:CoinFountain(sx, sy, 4, 0.8)
        self:Burst(sx, sy, 16, col, 200, 3.0, 3)
        self.lightFlash = max(self.lightFlash, 0.7)
        self.lightCol = col
    elseif m > 1 then
        self:UiPop(sx, sy + 24, prize.label or ("×" .. tostring(m)), col, 17)
        self:Burst(sx, sy, 10, col, 160, 2.6, 2)
        self.lightFlash = max(self.lightFlash, 0.4)
        self.lightCol = col
    else
        self:UiPop(sx, sy + 24, prize.label or "差一点点", col, 15)
    end
end

function Fx:OnSkillPointsGain(gained)
    if not gained or gained <= 0 then return end
    -- 技能点：在计数器下方飘出，0.5 秒内多次获得合并显示
    local p = self.spops[self.spopCursor]
    if p and p.life > p.max - 0.5 and p.isSp then
        p.spSum = p.spSum + gained
        p.text = "+" .. tostring(p.spSum) .. " 技能点"
        return
    end
    -- 落点：底部技能点栏与导航栏上方居中（不遮挡顶部资产与底部技能点条）
    self:UiPop(self.screenW * 0.5, self.screenH - 130, "+" .. tostring(gained) .. " 技能点", GREEN, 15)
    p = self.spops[self.spopCursor]
    p.isSp = true
    p.spSum = gained
end

function Fx:OnRankUp(rank, themeChanged, info)
    local head
    if rank.isRealName then
        head = "超越 No." .. tostring(rank.rank)
    else
        head = "冲入" .. (rank.name or ("全球前" .. Number.FormatWorldRank(rank.rank)))
    end
    -- 超越表现由 OvertakePopup 承担（RankLadder 追踪器触发）；这里只在换主题时补一枚印章
    if themeChanged then
        self:Stamp("新机台解锁!", head, GOLD, 3, 1.6, true, "theme")
    end
end

function Fx:OnUnlockCoin(def)
    local nm = (def and (def.name or def.short)) or "新内容"
    self:Stamp("解锁!", nm, CYAN, 3, 1.5)
    self:Burst(self.screenW * 0.5, self.screenH * 0.36, 24, CYAN, 230, 3.2, 6)
    self:AddFlash(70, CYAN)
end

function Fx:OnPrestige(shares, bonusSp, roundName)
    local spTxt = (bonusSp and bonusSp > 0) and (" · +" .. tostring(bonusSp) .. "技能点") or ""
    self:Stamp("敲钟上市!", (roundName or "") .. " +" .. Number.FormatNum(shares) .. "股" .. spTxt, MAGENTA, 5, 2.2, true)
    self:Confetti(60, 0, self.screenW, -10)
    self:AddFlash(150, GOLD, true)
end

function Fx:OnAdReward(msg)
    self:Stamp("福利到账!", msg or "", GREEN, 3, 1.5)
    self:CoinFountain(self.screenW * 0.5, self.screenH * 0.45, 10, 1.2)
    self:AddFlash(80, GOLD)
end

function Fx:OnFeverStart(run)
    self.feverGlow = 1
    self.feverOn = true
    self:Stamp("狂欢时刻!", "FEVER · 收益 ×2.2 · 射速 ×1.65", MAGENTA, 4, 1.8, true)
    self:Confetti(30, 0, self.screenW, -10)
    self:AddFlash(140, MAGENTA, true)
    self.lightFlash = 1.2
    self.lightCol = MAGENTA
end

function Fx:OnFeverEnd(run)
    self.feverOn = false
end

function Fx:OnGoalMet(run)
    self:Stamp("目标达成!", "", GREEN, 2, 1.3)
end

function Fx:OnCombo(combo)
    -- 只在前 10 连与每 10 连时弹一下，事件密集时不再常驻放大
    if (combo or 0) < 10 or combo % 10 == 0 then self.comboPop = 1.0 end
end

function Fx:OnComboWaveEnd(combo, waveMult, bonus)
    self.comboPop = 1.4
    local msg = string.format("波次 %d连 · +%s", combo or 0, Number.FormatCash(bonus or 0))
    self:UiPop(self.ancComboX - 42, self.ancComboY + 28, msg, GOLD, 16)
end

function Fx:OnComboBreak()
end

function Fx:OnBossAction(msg)
    self:Stamp(msg or "Boss 行动!", "", RED, 2, 1.3)
end

function Fx:TimeScale()
    if self.hitstop > 0 then return 0.15 end
    return 1.0
end

-- ----------------------------------------------------------------------------
-- 更新
-- ----------------------------------------------------------------------------
function Fx:Update(dt)
    self.time = self.time + dt
    if self.hitstop > 0 then self.hitstop = max(0, self.hitstop - dt) end
    if self.hitstopCd > 0 then self.hitstopCd = max(0, self.hitstopCd - dt) end
    self.shakeBudget = min(0.8, self.shakeBudget + dt * 0.45)
    self.flashBudget = min(160, self.flashBudget + dt * 70)
    self.kickBudget = min(1.0, self.kickBudget + dt * 0.5)
    if self.comboPop > 0 then self.comboPop = max(0, self.comboPop - dt * 5) end
    if self.flashA > 0 then self.flashA = max(0, self.flashA - dt * 320) end
    if self.kick > 0 then self.kick = max(0, self.kick - dt * 2.6) end
    if self.lightFlash > 0 then self.lightFlash = max(0, self.lightFlash - dt * 2.2) end
    if self.feverOn then
        self.feverGlow = min(1, self.feverGlow + dt * 3)
    elseif self.feverGlow > 0 then
        self.feverGlow = max(0, self.feverGlow - dt * 1.5)
    end

    if self.trauma > 0 then
        self.trauma = max(0, self.trauma - dt * 2.4)
        local mag = self.trauma * self.trauma * 9
        self.shakeX = (random() * 2 - 1) * mag
        self.shakeY = (random() * 2 - 1) * mag
    else
        self.shakeX, self.shakeY = 0, 0
    end

    local pX, pY, pVX, pVY, pLife = self.pX, self.pY, self.pVX, self.pVY, self.pLife
    for i = 1, MAX_P do
        local life = pLife[i]
        if life > 0 then
            pLife[i] = life - dt
            local drag = 1 - self.pDrag[i] * dt
            if drag < 0 then drag = 0 end
            pVX[i] = pVX[i] * drag
            pVY[i] = pVY[i] * drag + self.pGrav[i] * dt
            pX[i] = pX[i] + pVX[i] * dt
            pY[i] = pY[i] + pVY[i] * dt
            self.pRot[i] = self.pRot[i] + self.pVR[i] * dt
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

    local activePop = 0
    for i = 1, MAX_POPS do
        local p = self.pops[i]
        if p.life > 0 then
            p.life = max(0, p.life - dt)
            p.age = p.age + dt
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
            p.vy = p.vy * (1 - 3.2 * dt)
            if p.punch > 0 then p.punch = max(0, p.punch - dt * 4) end
            if p.life > 0 then activePop = activePop + 1 end
        end
    end
    self.activePopCount = activePop

    for i = 1, MAX_SPOPS do
        local p = self.spops[i]
        if p.life > 0 then
            p.life = max(0, p.life - dt)
            p.y = p.y - 46 * dt
        end
    end

    -- 飞币
    for i = 1, MAX_FLY do
        local f = self.fly[i]
        if f.on then
            f.age = f.age + dt
            f.spin = f.spin + dt * 16
            if f.age >= f.dur then
                f.on = false
                self.cashHits = self.cashHits + 1
                if random() < 0.5 then
                    self:Emit(K_STAR, self.ancCashX, self.ancCashY, (random() - 0.5) * 120, -random() * 90, 0.4, 5, WHITE, 60, 2)
                end
            end
        end
    end

    -- 倍率令牌
    for i = 1, MAX_TOK do
        local t = self.tokens[i]
        if t.on then
            t.age = t.age + dt
            if t.age >= t.dur then
                t.on = false
                self.multHits = self.multHits + 1
                self.multHitCol = t.col
                local ws0 = self.ws
                self.ws = 1
                self:Burst(self.ancMultX, self.ancMultY, 14, t.col, 200, 3, 4)
                self:Ring(self.ancMultX, self.ancMultY, 10, 90, t.col, 0.4, 4)
                self.ws = ws0
                self.lightFlash = max(self.lightFlash, 0.6)
                self.lightCol = t.col
            else
                -- 拖尾
                local u = t.age / t.dur
                local e = EaseOutCubic(u)
                local a = 1 - e
                local x = a * a * t.sx + 2 * a * e * t.cx + e * e * self.ancMultX
                local y = a * a * t.sy + 2 * a * e * t.cy + e * e * self.ancMultY
                if random() < 0.6 then
                    self:Emit(K_DOT, x, y, (random() - 0.5) * 30, (random() - 0.5) * 30, 0.3, 3, t.col, 0, 1)
                end
            end
        end
    end

    -- 印章
    local st = self.stamp
    if st.on then
        st.age = st.age + dt
        if st.age >= st.dur then
            st.on = false
            self.stampEndT = self.time
            for i = 1, MAX_STAMP_Q do
                local q = self.stampQ[i]
                if q.on then
                    q.on = false
                    self:Stamp(q.title, q.sub, q.col, q.prio, q.dur, q.big, q.kind)
                    break
                end
            end
        end
    end
end

-- ----------------------------------------------------------------------------
-- 渲染（屏幕空间，FxLayer 调用）
-- ----------------------------------------------------------------------------
function Fx:RenderParticles(nvg)
    local pX, pY, pLife, pMax, pSize, pCol, pKind = self.pX, self.pY, self.pLife, self.pMax, self.pSize, self.pCol, self.pKind
    -- 1) 实体：金币 & 彩纸（普通混合）
    for i = 1, MAX_P do
        local life = pLife[i]
        if life > 0 then
            local k = pKind[i]
            if k == K_COIN then
                local f = min(1, life / pMax[i] * 2.5)
                DrawMiniCoin(nvg, pX[i], pY[i], pSize[i], self.pRot[i], floor(255 * f))
            elseif k == K_CONF then
                local f = min(1, life / pMax[i] * 3)
                local s = pSize[i]
                local rot = self.pRot[i]
                local cw, sw = cos(rot) * s, abs(sin(rot * 1.7)) * s * 0.6 + 0.6
                nvgBeginPath(nvg)
                nvgRect(nvg, pX[i] - cw * 0.5, pY[i] - sw * 0.5, max(0.8, abs(cw)), sw)
                nvgFillColor(nvg, Col(pCol[i], floor(255 * f)))
                nvgFill(nvg)
            end
        end
    end
    -- 2) 发光：辉光点 / 火花 / 星（叠加混合）
    SetAdditive(nvg, true)
    for i = 1, MAX_P do
        local life = pLife[i]
        if life > 0 then
            local k = pKind[i]
            local f = life / pMax[i]
            if k == K_DOT then
                local sz = pSize[i] * (0.45 + 0.55 * f)
                local a = floor(235 * f)
                if sz >= 2.6 and self.quality >= 1 then
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, pX[i], pY[i], sz * 2.4)
                    nvgFillColor(nvg, Col(pCol[i], floor(a * 0.25)))
                    nvgFill(nvg)
                end
                nvgBeginPath(nvg)
                nvgCircle(nvg, pX[i], pY[i], sz)
                nvgFillColor(nvg, Col(pCol[i], a))
                nvgFill(nvg)
            elseif k == K_SPARK then
                local vx, vy = self.pVX[i], self.pVY[i]
                nvgBeginPath(nvg)
                nvgMoveTo(nvg, pX[i], pY[i])
                nvgLineTo(nvg, pX[i] - vx * 0.045, pY[i] - vy * 0.045)
                nvgStrokeColor(nvg, Col(pCol[i], floor(255 * f)))
                nvgStrokeWidth(nvg, max(0.8, pSize[i] * (0.5 + 0.5 * f)))
                nvgStroke(nvg)
            elseif k == K_STAR then
                local tw = 0.6 + 0.4 * sin(self.time * 22 + i)
                local r = pSize[i] * (0.4 + 0.6 * f) * tw
                nvgBeginPath(nvg)
                DrawStarPath(nvg, pX[i], pY[i], r, self.pRot[i] * 0.3, 0.22)
                nvgFillColor(nvg, Col(pCol[i], floor(255 * f)))
                nvgFill(nvg)
            end
        end
    end
    SetAdditive(nvg, false)
end

function Fx:RenderRingsBolts(nvg)
    SetAdditive(nvg, true)
    for i = 1, MAX_RINGS do
        local r = self.rings[i]
        if r.life > 0 then
            local t = 1 - r.life / r.max
            local e = EaseOutCubic(t)
            local rad = r.r0 + (r.r1 - r.r0) * e
            if r.disc then
                nvgBeginPath(nvg)
                nvgCircle(nvg, r.x, r.y, max(1, rad))
                nvgFillPaint(nvg, nvgRadialGradient(nvg, r.x, r.y, 0, max(1, rad), Col(r.col, floor(230 * (1 - t))), Col(r.col, 0)))
                nvgFill(nvg)
            else
                local a = floor(230 * (1 - t))
                nvgBeginPath(nvg)
                nvgCircle(nvg, r.x, r.y, max(1, rad))
                nvgStrokeColor(nvg, Col(r.col, a))
                nvgStrokeWidth(nvg, max(0.6, r.w * (1 - t * 0.7)))
                nvgStroke(nvg)
                nvgBeginPath(nvg)
                nvgCircle(nvg, r.x, r.y, max(1, rad * 0.94))
                nvgStrokeColor(nvg, Col(WHITE, floor(a * 0.45)))
                nvgStrokeWidth(nvg, max(0.5, r.w * 0.35 * (1 - t)))
                nvgStroke(nvg)
            end
        end
    end
    for i = 1, MAX_BOLTS do
        local b = self.bolts[i]
        if b.life > 0 then
            local f = b.life / b.max
            local flick = (floor(self.time * 40 + i) % 2 == 0) and 1 or 0.7
            local a = floor(255 * f * flick)
            for pass = 1, 3 do
                nvgBeginPath(nvg)
                nvgMoveTo(nvg, b.px[1], b.py[1])
                for k = 2, BOLT_PTS do nvgLineTo(nvg, b.px[k], b.py[k]) end
                if pass == 1 then
                    nvgStrokeColor(nvg, Col(b.col, floor(a * 0.3)))
                    nvgStrokeWidth(nvg, 8)
                elseif pass == 2 then
                    nvgStrokeColor(nvg, Col(b.col, a))
                    nvgStrokeWidth(nvg, 3)
                else
                    nvgStrokeColor(nvg, Col(WHITE, a))
                    nvgStrokeWidth(nvg, 1.2)
                end
                nvgStroke(nvg)
            end
        end
    end
    SetAdditive(nvg, false)
end

function Fx:RenderPops(nvg, font)
    nvgFontFace(nvg, font or "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local ws = self.ws
    -- 低阶先画，高阶压在上面
    for tierPass = 1, 5 do
        for i = 1, MAX_POPS do
            local p = self.pops[i]
            if p.life > 0 and p.tier == tierPass then
                local inT = min(1, p.age / 0.16)
                local sc = EaseOutBack(inT) * (1 + p.punch * 0.28)
                local f = min(1, (p.life / p.max) * 2.2)
                local a = floor(255 * f)
                local fs = p.size * ws * sc
                local maxPopW = self.screenW * 0.80
                local estW = p.tw * ws * sc
                if estW > maxPopW and estW > 0 then
                    fs = fs * (maxPopW / estW)
                end
                local dispScale = fs / max(1, p.size)
                local twDisp = p.tw * dispScale
                local pxDraw = max(twDisp * 0.5 + 8, min(self.screenW - twDisp * 0.5 - 8, p.x))
                local tCol = p.col
                if p.tier >= 5 then tCol = Rainbow(self.time * 10 + i) end
                -- T5 星爆光芒底（只给大数字，克制尺寸防止洗白画面）
                if p.tier >= 5 then
                    SetAdditive(nvg, true)
                    DrawRays(nvg, pxDraw, p.y, fs * 0.3, fs * 1.7, 10, self.time * 1.6 + i, tCol, floor(a * 0.32))
                    SetAdditive(nvg, false)
                end
                nvgFontSize(nvg, fs)
                if p.tier >= 3 then
                    OutlinedText(nvg, pxDraw, p.y, p.text, tCol, a, max(1.5, fs * 0.09))
                else
                    nvgFillColor(nvg, Col(INK, floor(a * 0.85)))
                    nvgText(nvg, pxDraw + 1.2, p.y + 1.6, p.text)
                    nvgFillColor(nvg, Col(tCol, a))
                    nvgText(nvg, pxDraw, p.y, p.text)
                end
                -- 暴击角标
                if p.crit and p.tier >= 3 then
                    local cfs = max(11, fs * 0.42)
                    nvgFontSize(nvg, cfs)
                    OutlinedText(nvg, pxDraw, p.y - fs * 0.78, "暴击!", ORANGE, a, 1.4)
                end
                -- ×倍率戳（延迟 0.1s 砸上）
                if p.multW > 0 and p.age > 0.08 then
                    local mt = min(1, (p.age - 0.08) / 0.14)
                    local msc = 1 + (1 - EaseOutBack(mt)) * 1.4
                    local cfs = (13 + p.tier) * ws * msc
                    local mw = p.multW * ws * msc
                    local mh = cfs * 1.35
                    local mx = pxDraw + twDisp * 0.5 + mw * 0.5 + 4
                    if mx + mw * 0.5 > self.screenW - 6 then mx = pxDraw - twDisp * 0.5 - mw * 0.5 - 4 end
                    local my = p.y + fs * 0.08
                    nvgSave(nvg)
                    nvgTranslate(nvg, mx, my)
                    nvgRotate(nvg, -0.12)
                    nvgBeginPath(nvg)
                    nvgRoundedRect(nvg, -mw * 0.5, -mh * 0.5, mw, mh, mh * 0.3)
                    nvgFillColor(nvg, Col(MAGENTA, a))
                    nvgFill(nvg)
                    nvgStrokeColor(nvg, Col(WHITE, a))
                    nvgStrokeWidth(nvg, 1.5)
                    nvgStroke(nvg)
                    nvgFontSize(nvg, cfs)
                    nvgFillColor(nvg, Col(WHITE, a))
                    nvgText(nvg, 0, 0.5, p.multTxt)
                    nvgRestore(nvg)
                end
            end
        end
    end
    for i = 1, MAX_SPOPS do
        local p = self.spops[i]
        if p.life > 0 then
            local age = p.max - p.life
            local sc = EaseOutBack(min(1, age / 0.18))
            local a = floor(255 * min(1, p.life / p.max * 2.5))
            nvgFontSize(nvg, p.size * sc)
            OutlinedText(nvg, p.x, p.y, p.text, p.col, a, 1.6)
        end
    end
end

function Fx:RenderFly(nvg)
    local tx, ty = self.ancCashX, self.ancCashY
    for i = 1, MAX_FLY do
        local f = self.fly[i]
        if f.on and f.age > 0 then
            local u = min(1, f.age / f.dur)
            local e = u * u * (3 - 2 * u)
            local a = 1 - e
            local x = a * a * f.sx + 2 * a * e * f.cx + e * e * tx
            local y = a * a * f.sy + 2 * a * e * f.cy + e * e * ty
            local r = f.r * (1 - 0.35 * e)
            DrawMiniCoin(nvg, x, y, r, f.spin, 255)
        end
    end
    -- 倍率令牌
    nvgFontFace(nvg, "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    for i = 1, MAX_TOK do
        local t = self.tokens[i]
        if t.on then
            local u = t.age / t.dur
            local e = EaseOutCubic(u)
            local a = 1 - e
            local x = a * a * t.sx + 2 * a * e * t.cx + e * e * self.ancMultX
            local y = a * a * t.sy + 2 * a * e * t.cy + e * e * self.ancMultY
            local sc = (u < 0.2) and EaseOutBack(u / 0.2) * 1.2 or (1.2 - 0.5 * (u - 0.2) / 0.8)
            local w, h = t.w * sc, 26 * sc
            SetAdditive(nvg, true)
            nvgBeginPath(nvg)
            nvgCircle(nvg, x, y, w * 0.7)
            nvgFillPaint(nvg, nvgRadialGradient(nvg, x, y, 2, w * 0.7, Col(t.col, 150), Col(t.col, 0)))
            nvgFill(nvg)
            SetAdditive(nvg, false)
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, x - w * 0.5, y - h * 0.5, w, h, h * 0.5)
            nvgFillColor(nvg, Col(INK, 235))
            nvgFill(nvg)
            nvgStrokeColor(nvg, Col(t.col, 255))
            nvgStrokeWidth(nvg, 2)
            nvgStroke(nvg)
            nvgFontSize(nvg, 15 * sc)
            nvgFillColor(nvg, Col(t.col, 255))
            nvgText(nvg, x, y + 0.5, t.text)
        end
    end
end

function Fx:RenderStamp(nvg, w, h, font)
    local st = self.stamp
    if not st.on then return end
    local t = st.age
    local inDur = 0.2
    local outStart = st.dur - 0.28
    local sc, a
    if t < inDur then
        local u = t / inDur
        sc = 2.6 - 1.6 * EaseOutBack(u)
        a = u
    elseif t > outStart then
        local u = min(1, (t - outStart) / 0.28)
        sc = 1 + 0.18 * u
        a = 1 - u
    else
        sc = 1 + 0.03 * sin((t - inDur) * 10) * (st.big and 1 or 0.4)
        a = 1
    end
    local A = floor(255 * a)
    local cx, cy = w * 0.5, h * 0.36
    local col = st.col
    if st.big and st.title:find("百倍") then col = Rainbow(self.time * 12) end
    local bandH = (st.big and 96 or 74)

    -- 光芒 + 暗带
    if st.big then
        SetAdditive(nvg, true)
        DrawRays(nvg, cx, cy, 20, w * 0.52, 14, self.time * 0.9, col, floor(A * 0.3))
        SetAdditive(nvg, false)
    end
    nvgBeginPath(nvg)
    nvgRect(nvg, 0, cy - bandH * 0.5, w, bandH)
    nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, cy - bandH * 0.5, 0, cy + bandH * 0.5, Col(INK2, floor(A * 0.82)), Col(INK, floor(A * 0.9))))
    nvgFill(nvg)
    nvgBeginPath(nvg)
    nvgRect(nvg, 0, cy - bandH * 0.5, w, 2)
    nvgRect(nvg, 0, cy + bandH * 0.5 - 2, w, 2)
    nvgFillColor(nvg, Col(col, A))
    nvgFill(nvg)

    nvgFontFace(nvg, font or "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local titleFs = (st.big and 44 or 34)
    -- 适配宽度（中文字宽≈字号）
    local estW = EstTextW(st.title, titleFs)
    if estW > w * 0.9 then titleFs = titleFs * (w * 0.9) / estW end
    local ty = cy - (st.sub ~= "" and 10 or 0)
    -- 入场残影
    if t < inDur then
        nvgFontSize(nvg, titleFs * sc * 1.35)
        nvgFillColor(nvg, Col(col, floor(A * 0.3)))
        nvgText(nvg, cx, ty, st.title)
    end
    nvgFontSize(nvg, titleFs * sc)
    OutlinedText(nvg, cx, ty + 3, st.title, INK, A, 3, INK)
    OutlinedText(nvg, cx, ty, st.title, col, A, 2.5, { 255, 255, 255 })
    nvgFillColor(nvg, Col(col, A))
    nvgText(nvg, cx, ty, st.title)
    if st.sub ~= "" then
        local subFs = 15
        local sw = EstTextW(st.sub, subFs)
        if sw > w * 0.9 then subFs = subFs * (w * 0.9) / sw end
        nvgFontSize(nvg, subFs * min(1.2, sc))
        OutlinedText(nvg, cx, cy + bandH * 0.5 - 14, st.sub, WHITE, A, 1.4)
    end
end

function Fx:RenderScreenFx(nvg, w, h)
    -- 狂欢霓虹暗角 + 流光边框
    local fg = self.feverGlow
    if fg > 0.01 then
        local pulse = 0.65 + 0.35 * sin(self.time * 9)
        local col = (floor(self.time * 4) % 2 == 0) and MAGENTA or GOLD
        nvgBeginPath(nvg)
        nvgRect(nvg, 0, 0, w, h)
        nvgFillPaint(nvg, nvgBoxGradient(nvg, 0, 0, w, h, 26, 70, Col(col, 0), Col(col, floor(90 * fg * pulse))))
        nvgFill(nvg)
        -- 跑马灯珠沿屏幕四边
        SetAdditive(nvg, true)
        local n = 18
        local ph = self.time * 8
        for k = 0, n - 1 do
            local lit = ((k + floor(ph)) % 3 == 0)
            if lit then
                local x = 6 + (w - 12) * k / (n - 1)
                nvgBeginPath(nvg)
                nvgCircle(nvg, x, 4, 3.5)
                nvgCircle(nvg, x, h - 4, 3.5)
                nvgFillColor(nvg, Col(Rainbow(k + ph), floor(230 * fg)))
                nvgFill(nvg)
            end
        end
        SetAdditive(nvg, false)
    elseif self.heat > 0.3 then
        -- 高热度（大倍率中）金色边缘光
        local hh = (self.heat - 0.3) / 0.7
        nvgBeginPath(nvg)
        nvgRect(nvg, 0, 0, w, h)
        nvgFillPaint(nvg, nvgBoxGradient(nvg, 0, 0, w, h, 24, 60, Col(GOLD, 0), Col(GOLD, floor(45 * hh * (0.7 + 0.3 * sin(self.time * 6))))))
        nvgFill(nvg)
    end
    -- 全屏闪光
    if self.flashA > 1 then
        SetAdditive(nvg, true)
        nvgBeginPath(nvg)
        nvgRect(nvg, 0, 0, w, h)
        nvgFillColor(nvg, Col(self.flashCol, floor(self.flashA * 0.45)))
        nvgFill(nvg)
        SetAdditive(nvg, false)
    end
end

--- 主渲染入口（FxLayer 每帧调用；任何弹窗打开时完全静默让位，绝不穿透弹窗跳特效）
function Fx:Render(nvg, w, h, font, modalOpen)
    self.screenW, self.screenH = w, h
    self.modalOpen = modalOpen == true
    if modalOpen then
        return
    end
    self:RenderScreenFx(nvg, w, h)
    self:RenderRingsBolts(nvg)
    self:RenderParticles(nvg)
    self:RenderPops(nvg, font)
    self:RenderFly(nvg)
    self:RenderStamp(nvg, w, h, font)
end

-- 兼容旧调用（Stage 不再直接绘制特效；保留给旧测试）
function Fx:RenderWorld(nvg, font, projectFn)
    self:RenderRingsBolts(nvg)
    self:RenderParticles(nvg)
    self:RenderPops(nvg, font)
end

function Fx:RenderOverlay(nvg, w, h, font, run)
    self:RenderScreenFx(nvg, w, h)
    self:RenderFly(nvg)
    self:RenderStamp(nvg, w, h, font)
end

return Fx
