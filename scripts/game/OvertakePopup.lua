-- ============================================================================
-- OvertakePopup.lua  世界排名超越弹窗（整局最核心的爽点之一）
--   版式（参考宣传图）：徽记 → 3D 金色大标题 → 紫色绶带副标题 → 「你的财富 ≫ 被超越者」对比双卡
--                       → 对手吐槽 → 厚金按钮（带技能点赏金时：收下 / ×3 看广告）
--   六档层层递进（按被超越者的世界排名）：
--     T1 身边人（≥1亿名）       超越!      上箭头徽记，彩纸，2.4s 自动收起
--     T2 1亿~10万名             阶层跃迁!  银勋章 + 光芒，金币雨
--     T3 10万~1000名            身价暴涨!  金勋章 + 月桂 + 更强光芒
--     T4 真名富豪前1000          超越富豪!  皇冠 + 金光芒 + 烟花，需点按收下
--     T5 世界前10               超越传奇!  宝石皇冠 + 彩虹光芒 + 彩虹描边 + 连发烟花
--     T6 世界第1                超越巅峰!  巨型皇冠 + 地球光环 + 金雨 + 循环烟花
--   里程碑档位 +1 级；演出中再次超越 → 合并为“连超 N 人!”，内容切到最新对手并重新砸一次
-- ============================================================================

local UI = require("urhox-libs/UI")
local Skin = require("game/Skin")
local Fx = require("game/Fx")
local Number = require("game/Number")
local AvatarArt = require("game/AvatarArt")
local RankLadder = require("game/RankLadder")
local Billionaires = require("game/Billionaires")

local floor, min, max, sin, cos, pi, abs = math.floor, math.min, math.max, math.sin, math.cos, math.pi, math.abs
local random = math.random
local Col = Skin.Col
local C = Skin.C
local OutlinedText, SetAdditive, EstTextW, DrawRays, DrawStarPath, DrawMiniCoin, Rainbow =
    Fx.OutlinedText, Fx.SetAdditive, Fx.EstTextW, Fx.DrawRays, Fx.DrawStarPath, Fx.DrawMiniCoin, Fx.Rainbow

local OvertakePopup = UI.Widget:Extend("OvertakePopup")

-- 色板（常量表，Skin.Col 可缓存）
local OVERLAY = { 4, 4, 14 }
local INK = { 10, 8, 26 }
local GOLD_HI = { 255, 248, 196 }
local GOLD = { 255, 206, 64 }
local GOLD_LO = { 196, 118, 16 }
local GOLD_DEEP = { 96, 46, 4 }
local PANEL_TOP = { 30, 26, 72 }
local PANEL_BOT = { 12, 12, 34 }
local PURPLE = { 150, 90, 255 }
local PURPLE_DEEP = { 70, 30, 150 }
local RIBBON = { 110, 52, 210 }
local RIBBON_DARK = { 60, 22, 120 }
local CYAN = { 80, 220, 255 }
local CARD_ME_TOP = { 70, 48, 14 }
local CARD_ME_BOT = { 26, 18, 8 }
local CARD_RIVAL_TOP = { 34, 30, 80 }
local CARD_RIVAL_BOT = { 16, 14, 40 }
local GREY = { 140, 144, 160 }
local STAMP_RED = { 220, 40, 58 }
local BTN_HI = { 255, 236, 120 }
local BTN_LO = { 236, 150, 20 }
local BTN_EDGE = { 140, 70, 6 }
local BTN_AD_HI = { 255, 120, 200 }
local BTN_AD_LO = { 186, 40, 140 }
local BTN_AD_EDGE = { 100, 14, 70 }
local GEM_R = { 255, 70, 110 }
local GEM_B = { 80, 170, 255 }
local GEM_P = { 190, 110, 255 }
local LEAF = { 120, 220, 120 }

local TIER_DEF = {
    { title = "超越!",     auto = 2.4, rays = 0,  confetti = 18, coins = 0,  fireworks = 0 },
    { title = "阶层跃迁!", auto = 2.8, rays = 10, confetti = 26, coins = 6,  fireworks = 0 },
    { title = "身价暴涨!", auto = 3.4, rays = 14, confetti = 36, coins = 10, fireworks = 1 },
    { title = "超越富豪!", auto = 0,   rays = 16, confetti = 50, coins = 14, fireworks = 2 },
    { title = "超越传奇!", auto = 0,   rays = 20, confetti = 64, coins = 18, fireworks = 4 },
    { title = "超越巅峰!", auto = 0,   rays = 24, confetti = 90, coins = 24, fireworks = 8 },
}
OvertakePopup.TIER_DEF = TIER_DEF

local function EaseOutBack(t)
    local c1 = 1.70158
    local c3 = c1 + 1
    local u = t - 1
    return 1 + c3 * u * u * u + c1 * u * u
end

local function Clamp01(x) if x < 0 then return 0 elseif x > 1 then return 1 end return x end

--- 按被超越者分档（1..6）
function OvertakePopup.TierOf(item)
    if not item then return 1 end
    local e = item.entry or {}
    local r = item.rank or 1e9
    local tier
    if r <= 1 then return 6
    elseif e.isRealName and r <= 10 then tier = 5
    elseif e.isRealName then tier = 4
    elseif r < 1e5 then tier = 3
    elseif r < 1e8 then tier = 2
    else tier = 1 end
    if e.milestone and tier < 5 then tier = tier + 1 end
    return tier
end

function OvertakePopup:Init(props)
    props = props or {}
    self.fx_ = props.fx
    self.getTy_ = props.getTycoon
    self.getTime_ = props.getTime
    self.font_ = props.font or "sans"
    self.onCollect_ = props.onCollect
    self.onAd_ = props.onAd
    self.isBlocked_ = props.isBlocked
    props.fx, props.getTycoon, props.getTime, props.font, props.onCollect, props.onAd, props.isBlocked =
        nil, nil, nil, nil, nil, nil, nil
    props.position = "absolute"
    props.top = 0
    props.left = 0
    props.width = "100%"
    props.height = "100%"
    props.visible = false
    props.pointerEvents = "auto"
    self.on_ = false
    self.age_ = 0
    self.closing_ = -1
    self.item_ = nil
    self.tier_ = 1
    self.count_ = 1
    self.sp_ = 0
    self.punch_ = 0
    self.pending_ = nil
    self.pendingCount_ = 0
    self.pendingSp_ = 0
    self.btns_ = {}
    self.fwAcc_ = 0
    self.lastT_ = nil
    self.stamped_ = false
    self.txtName_ = ""
    self.txtRivalRank_ = ""
    self.txtRivalCash_ = ""
    self.txtQuote_ = ""
    self.txtSub_ = ""
    local selfRef = self
    props.onPointerDown = function(a, b)
        local e = (type(a) == "table" and a.GetAbsoluteLayout) and b or a
        selfRef:HandleTap(e and e.x, e and e.y)
    end
    UI.Widget.Init(self, props)
end

function OvertakePopup:SetFont(f) self.font_ = f end
function OvertakePopup:IsOpen() return self.on_ or self.pending_ ~= nil end

function OvertakePopup:Reset()
    self.on_ = false
    self.age_ = 0
    self.closing_ = -1
    self.item_ = nil
    self.tier_ = 1
    self.count_ = 1
    self.sp_ = 0
    self.punch_ = 0
    self.pending_ = nil
    self.pendingCount_ = 0
    self.pendingSp_ = 0
    self.stamped_ = false
    self.btnSp_ = nil
    self.lastT_ = nil
    for i = 1, #self.btns_ do self.btns_[i].w = 0 end
    self:SetVisible(false)
end

local function ApplyContent(self, item, count, sp)
    self.item_ = item
    self.count_ = count
    self.sp_ = sp or 0
    local e = item.entry or {}
    self.txtName_ = item.name or ""
    if e.isRealName then
        self.txtRivalRank_ = "世界第 " .. tostring(item.rank) .. " 名"
    else
        self.txtRivalRank_ = "世界第 " .. RankLadder.FormatRankShort(item.rank) .. " 名"
    end
    self.txtRivalCash_ = Number.FormatCash(item.target or 0)
    self.txtQuote_ = (item.quote and item.quote ~= "") and ("“" .. item.quote .. "”") or ""
end

--- 触发超越弹窗（item = RankLadder 条目；count = 一次越过人数；sp = 富豪榜技能点赏金）
function OvertakePopup:Trigger(item, count, sp)
    if not item then return end
    count = count or 1
    local tier = OvertakePopup.TierOf(item)
    if self.on_ and self.closing_ < 0 then
        -- 演出中再超越：合并为连超，切到最新对手，重新砸一次
        ApplyContent(self, item, self.count_ + count, self.sp_ + (sp or 0))
        self.tier_ = max(self.tier_, tier)
        self.punch_ = 1
        self.stamped_ = false
        self.age_ = min(self.age_, 0.35)
        return
    end
    if self.on_ or (self.isBlocked_ and self.isBlocked_()) then
        self.pending_ = item
        self.pendingCount_ = self.pendingCount_ + count
        self.pendingSp_ = self.pendingSp_ + (sp or 0)
        return
    end
    self:Open(item, count, sp, tier)
end

--- 技能点赏金到达（富豪榜条目由 Tycoon.OnRankUp 汇报，可能与阶梯追踪同帧）
function OvertakePopup:AddBounty(sp)
    if self.on_ and self.closing_ < 0 then
        self.sp_ = self.sp_ + (sp or 0)
    elseif self.pending_ then
        self.pendingSp_ = self.pendingSp_ + (sp or 0)
    end
end

function OvertakePopup:Open(item, count, sp, tier)
    ApplyContent(self, item, count, sp)
    self.tier_ = tier or OvertakePopup.TierOf(item)
    self.on_ = true
    self.age_ = 0
    self.closing_ = -1
    self.punch_ = 0
    self.stamped_ = false
    self.fwAcc_ = 0
    self:SetVisible(true)
    local fx = self.fx_
    if fx then
        local def = TIER_DEF[self.tier_]
        local w, h = fx.screenW, fx.screenH
        fx:Confetti(def.confetti, 0, w, -10)
        fx:AddFlash(60 + self.tier_ * 18, GOLD, self.tier_ >= 4)
        fx:AddTrauma(0.15 + self.tier_ * 0.06, self.tier_ >= 4)
        fx:AddKick(0.3 + self.tier_ * 0.1, self.tier_ >= 4)
    end
end

function OvertakePopup:Dismiss()
    if not self.on_ or self.closing_ >= 0 then return end
    self.closing_ = 0
end

function OvertakePopup:HandleTap(x, y)
    if not self.on_ or self.closing_ >= 0 then return end
    if self.age_ < 0.45 then return end -- 入场中防误触
    for _, b in ipairs(self.btns_) do
        if b.w > 0 and x and y and x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
            if b.id == "ad" then
                if self.onAd_ then self.onAd_(self.sp_) end
            else
                if self.onCollect_ then self.onCollect_(self.sp_) end
                self:Dismiss()
            end
            return
        end
    end
    -- 无赏金的低档弹窗：点哪儿都收起
    if self.sp_ <= 0 then
        if self.onCollect_ then self.onCollect_(0) end
        self:Dismiss()
    end
end

-- ----------------------------------------------------------------------------
-- 绘制部件
-- ----------------------------------------------------------------------------
--- 3D 金色立体字：深色厚度层 + 暗描边 + 金色主体 + 上半亮金（剪裁模拟渐变）+ 白高光
local function GoldTitle(nvg, cx, cy, text, fs, a, glowCol)
    nvgFontSize(nvg, fs)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local depth = max(3, floor(fs * 0.09))
    for d = depth, 1, -1 do
        nvgFillColor(nvg, Col(GOLD_DEEP, a))
        nvgText(nvg, cx, cy + d, text)
    end
    OutlinedText(nvg, cx, cy, text, GOLD, a, max(2, fs * 0.06), INK)
    local tw = EstTextW(text, fs)
    nvgSave(nvg)
    nvgIntersectScissor(nvg, cx - tw, cy - fs, tw * 2, fs * 0.92)
    nvgFillColor(nvg, Col(GOLD_HI, a))
    nvgText(nvg, cx, cy, text)
    nvgRestore(nvg)
    nvgSave(nvg)
    nvgIntersectScissor(nvg, cx - tw, cy + fs * 0.08, tw * 2, fs)
    nvgFillColor(nvg, Col(GOLD_LO, floor(a * 0.55)))
    nvgText(nvg, cx, cy, text)
    nvgRestore(nvg)
end

local function DrawCrown(nvg, cx, cy, s, a, gems, t)
    local w, h = s * 1.5, s
    local x0, y0 = cx - w * 0.5, cy - h * 0.5
    -- 冠体
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, x0, y0 + h * 0.78)
    nvgLineTo(nvg, x0 + w * 0.04, y0 + h * 0.18)
    nvgLineTo(nvg, x0 + w * 0.28, y0 + h * 0.48)
    nvgLineTo(nvg, x0 + w * 0.5, y0)
    nvgLineTo(nvg, x0 + w * 0.72, y0 + h * 0.48)
    nvgLineTo(nvg, x0 + w * 0.96, y0 + h * 0.18)
    nvgLineTo(nvg, x0 + w, y0 + h * 0.78)
    nvgClosePath(nvg)
    nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, y0, 0, y0 + h, Col(GOLD_HI, a), Col(GOLD_LO, a)))
    nvgFill(nvg)
    nvgStrokeColor(nvg, Col(GOLD_DEEP, a))
    nvgStrokeWidth(nvg, max(1.5, s * 0.05))
    nvgStroke(nvg)
    -- 冠带
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x0 - w * 0.02, y0 + h * 0.72, w * 1.04, h * 0.26, h * 0.08)
    nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, y0 + h * 0.72, 0, y0 + h, Col(GOLD, a), Col(GOLD_LO, a)))
    nvgFill(nvg)
    nvgStroke(nvg)
    -- 尖顶宝珠
    for _, px in ipairs({ 0.04, 0.5, 0.96 }) do
        nvgBeginPath(nvg)
        nvgCircle(nvg, x0 + w * px, y0 + (px == 0.5 and 0 or h * 0.18), s * 0.09)
        nvgFillColor(nvg, Col(GOLD_HI, a))
        nvgFill(nvg)
    end
    if gems then
        local gc = { GEM_R, GEM_B, GEM_P }
        for k = 1, 3 do
            local gx = x0 + w * (0.25 + (k - 1) * 0.25)
            local gy = y0 + h * 0.85
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, gx, gy - s * 0.09)
            nvgLineTo(nvg, gx + s * 0.08, gy)
            nvgLineTo(nvg, gx, gy + s * 0.09)
            nvgLineTo(nvg, gx - s * 0.08, gy)
            nvgClosePath(nvg)
            nvgFillColor(nvg, Col(gc[k], a))
            nvgFill(nvg)
        end
        -- 闪光
        local sp = (t * 0.8) % 1.6
        if sp < 1 then
            nvgBeginPath(nvg)
            DrawStarPath(nvg, x0 + w * sp, y0 + h * 0.4, s * 0.16, t, 0.2)
            nvgFillColor(nvg, Col(C.white, floor(a * (1 - abs(sp - 0.5) * 2))))
            nvgFill(nvg)
        end
    end
end

local function DrawMedal(nvg, cx, cy, s, a, gold)
    local hi, mid, lo = gold and GOLD_HI or { 250, 252, 255 }, gold and GOLD or { 190, 200, 216 }, gold and GOLD_LO or { 96, 106, 128 }
    -- 绶带
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, cx - s * 0.35, cy)
    nvgLineTo(nvg, cx - s * 0.55, cy + s * 0.95)
    nvgLineTo(nvg, cx - s * 0.3, cy + s * 0.8)
    nvgLineTo(nvg, cx - s * 0.12, cy + s * 0.98)
    nvgLineTo(nvg, cx, cy)
    nvgClosePath(nvg)
    nvgMoveTo(nvg, cx + s * 0.35, cy)
    nvgLineTo(nvg, cx + s * 0.55, cy + s * 0.95)
    nvgLineTo(nvg, cx + s * 0.3, cy + s * 0.8)
    nvgLineTo(nvg, cx + s * 0.12, cy + s * 0.98)
    nvgLineTo(nvg, cx, cy)
    nvgClosePath(nvg)
    nvgFillColor(nvg, Col(RIBBON, a))
    nvgFill(nvg)
    nvgBeginPath(nvg)
    nvgCircle(nvg, cx, cy, s * 0.5)
    nvgFillPaint(nvg, nvgLinearGradient(nvg, cx - s * 0.5, cy - s * 0.5, cx + s * 0.5, cy + s * 0.5, Col(hi, a), Col(lo, a)))
    nvgFill(nvg)
    nvgBeginPath(nvg)
    nvgCircle(nvg, cx, cy, s * 0.38)
    nvgFillColor(nvg, Col(mid, a))
    nvgFill(nvg)
    nvgBeginPath(nvg)
    DrawStarPath(nvg, cx, cy, s * 0.26, -pi * 0.5, 0.45)
    nvgFillColor(nvg, Col(hi, a))
    nvgFill(nvg)
end

local function DrawChevrons(nvg, cx, cy, s, a, t)
    for k = 0, 1 do
        local y = cy + k * s * 0.42 - (t * 30 % (s * 0.2))
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, cx - s * 0.5, y + s * 0.25)
        nvgLineTo(nvg, cx, y - s * 0.22)
        nvgLineTo(nvg, cx + s * 0.5, y + s * 0.25)
        nvgLineTo(nvg, cx + s * 0.5, y + s * 0.45)
        nvgLineTo(nvg, cx, y)
        nvgLineTo(nvg, cx - s * 0.5, y + s * 0.45)
        nvgClosePath(nvg)
        nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, y - s * 0.22, 0, y + s * 0.45, Col(GOLD_HI, a), Col(GOLD_LO, a)))
        nvgFill(nvg)
        nvgStrokeColor(nvg, Col(GOLD_DEEP, a))
        nvgStrokeWidth(nvg, 1.5)
        nvgStroke(nvg)
    end
end

-- 平放的一枚金币（侧边厚度 + 顶面 + 压印内圈 + 高光）
local COIN_SIDE = { 176, 104, 14 }
local function FlatCoin(nvg, x, y, r, a)
    local ry = r * 0.36
    nvgBeginPath(nvg)
    nvgRect(nvg, x - r, y, r * 2, r * 0.22)
    nvgEllipse(nvg, x, y + r * 0.22, r, ry)
    nvgFillColor(nvg, Col(COIN_SIDE, a))
    nvgFill(nvg)
    nvgBeginPath(nvg)
    nvgEllipse(nvg, x, y, r, ry)
    nvgFillPaint(nvg, nvgLinearGradient(nvg, x - r, y - ry, x + r, y + ry, Col(GOLD_HI, a), Col(GOLD, a)))
    nvgFill(nvg)
    nvgBeginPath(nvg)
    nvgEllipse(nvg, x, y, r * 0.68, ry * 0.68)
    nvgStrokeColor(nvg, Col(GOLD_LO, floor(a * 0.8)))
    nvgStrokeWidth(nvg, max(1, r * 0.08))
    nvgStroke(nvg)
end

local function DrawCoinStack(nvg, cx, cy, s, a, t)
    local r = s * 0.3
    -- 后排一摞（4 枚）+ 前排一摞（3 枚）+ 顶上一枚立着闪光的
    for k = 0, 3 do FlatCoin(nvg, cx - r * 0.7, cy + s * 0.32 - k * r * 0.34, r, a) end
    for k = 0, 2 do FlatCoin(nvg, cx + r * 0.75, cy + s * 0.42 - k * r * 0.34, r, a) end
    DrawMiniCoin(nvg, cx - r * 0.1, cy - s * 0.12, r * 0.95, t * 3, a)
    local sp = (t * 0.9) % 1.4
    if sp < 1 then
        nvgBeginPath(nvg)
        DrawStarPath(nvg, cx - r * 0.7 + sp * r * 1.6, cy - s * 0.2, r * 0.45, t, 0.18)
        nvgFillColor(nvg, Col(C.white, floor(a * (1 - abs(sp - 0.5) * 2))))
        nvgFill(nvg)
    end
end

local function Ribbon(nvg, cx, cy, w, h, a)
    local tail = h * 0.55
    -- 两端折尾
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, cx - w * 0.5 - tail, cy - h * 0.3)
    nvgLineTo(nvg, cx - w * 0.5 + 6, cy - h * 0.3)
    nvgLineTo(nvg, cx - w * 0.5 + 6, cy + h * 0.6)
    nvgLineTo(nvg, cx - w * 0.5 - tail, cy + h * 0.6)
    nvgLineTo(nvg, cx - w * 0.5 - tail * 0.55, cy + h * 0.15)
    nvgClosePath(nvg)
    nvgMoveTo(nvg, cx + w * 0.5 + tail, cy - h * 0.3)
    nvgLineTo(nvg, cx + w * 0.5 - 6, cy - h * 0.3)
    nvgLineTo(nvg, cx + w * 0.5 - 6, cy + h * 0.6)
    nvgLineTo(nvg, cx + w * 0.5 + tail, cy + h * 0.6)
    nvgLineTo(nvg, cx + w * 0.5 + tail * 0.55, cy + h * 0.15)
    nvgClosePath(nvg)
    nvgFillColor(nvg, Col(RIBBON_DARK, a))
    nvgFill(nvg)
    -- 主带
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, cx - w * 0.5, cy - h * 0.5, w, h, 4)
    nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, cy - h * 0.5, 0, cy + h * 0.5, Col(PURPLE, a), Col(RIBBON, a)))
    nvgFill(nvg)
    nvgStrokeColor(nvg, Col(GOLD, floor(a * 0.85)))
    nvgStrokeWidth(nvg, 1.5)
    nvgStroke(nvg)
end

local function Button(nvg, x, y, w, h, text, a, ad, pulse, font)
    local hi, lo, edge = ad and BTN_AD_HI or BTN_HI, ad and BTN_AD_LO or BTN_LO, ad and BTN_AD_EDGE or BTN_EDGE
    local sc = 1 + pulse * 0.04
    local cx, cy = x + w * 0.5, y + h * 0.5
    nvgSave(nvg)
    nvgTranslate(nvg, cx, cy)
    nvgScale(nvg, sc, sc)
    local bx, by = -w * 0.5, -h * 0.5
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, bx, by + 5, w, h, 12)
    nvgFillColor(nvg, Col(edge, a))
    nvgFill(nvg)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, bx, by, w, h, 12)
    nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, by, 0, by + h, Col(hi, a), Col(lo, a)))
    nvgFill(nvg)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, bx + 4, by + 3, w - 8, h * 0.4, 9)
    nvgFillColor(nvg, Col(C.white, floor(a * 0.35)))
    nvgFill(nvg)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, bx + 1, by + 1, w - 2, h - 2, 11)
    nvgStrokeColor(nvg, Col(C.white, floor(a * 0.7)))
    nvgStrokeWidth(nvg, 1.5)
    nvgStroke(nvg)
    nvgFontFace(nvg, font)
    local fs = 19
    local tw = EstTextW(text, fs)
    if tw > w - 20 then fs = fs * (w - 20) / tw end
    nvgFontSize(nvg, fs)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, Col(ad and C.white or GOLD_DEEP, a))
    nvgText(nvg, 0, 1, text)
    nvgRestore(nvg)
end

-- ----------------------------------------------------------------------------
-- 主渲染（含时间推进：只在打开时工作）
-- ----------------------------------------------------------------------------
function OvertakePopup:Render(nvg)
    local t = (self.getTime_ and self.getTime_()) or 0
    local dt = self.lastT_ and max(0, min(0.1, t - self.lastT_)) or 0
    self.lastT_ = t
    if not self.on_ then
        if self.pending_ and not (self.isBlocked_ and self.isBlocked_()) then
            local p, c, s = self.pending_, self.pendingCount_, self.pendingSp_
            self.pending_, self.pendingCount_, self.pendingSp_ = nil, 0, 0
            self:Open(p, c, s)
        else
            return
        end
    end
    local l = self:GetAbsoluteLayout()
    local W = (UI.GetWidth and UI.GetWidth()) or l.w
    local H = (UI.GetHeight and UI.GetHeight()) or l.h
    local fx = self.fx_
    local ty = self.getTy_ and self.getTy_()
    local def = TIER_DEF[self.tier_]
    local tier = self.tier_

    self.age_ = self.age_ + dt
    if self.punch_ > 0 then self.punch_ = max(0, self.punch_ - dt * 3) end
    if self.closing_ >= 0 then
        self.closing_ = self.closing_ + dt
        if self.closing_ >= 0.22 then
            self.on_ = false
            self.closing_ = -1
            self:SetVisible(false)
            if self.pending_ then self:SetVisible(true) end
            return
        end
    elseif def.auto > 0 and self.sp_ <= 0 and self.age_ >= def.auto then
        self:Dismiss()
    end
    local age = self.age_
    local closeK = (self.closing_ >= 0) and (1 - self.closing_ / 0.22) or 1
    local A = floor(255 * Clamp01(age / 0.18) * closeK)

    -- 交错瞬间：已超越印章 + 爆点 + 顶栏排名被砸
    if not self.stamped_ and age >= 0.5 then
        self.stamped_ = true
        if fx then
            fx.rankHits = (fx.rankHits or 0) + 1
            fx:CoinFountain(W * 0.5, H * 0.5, def.coins, 1.2)
            fx:AddTrauma(0.2, tier >= 4)
        end
    end
    -- 烟花（T3+ 持续）
    if fx and def.fireworks > 0 and self.closing_ < 0 then
        self.fwAcc_ = self.fwAcc_ + dt * def.fireworks * 0.9
        while self.fwAcc_ >= 1 do
            self.fwAcc_ = self.fwAcc_ - 1
            local fxp, fyp = W * (0.12 + random() * 0.76), H * (0.08 + random() * 0.3)
            local col = Rainbow(random() * 8)
            local ws0 = fx.ws
            fx.ws = 1
            fx:Burst(fxp, fyp, 22, col, 230, 3, 4)
            fx:Ring(fxp, fyp, 4, 60, col, 0.45, 2.5)
            fx.ws = ws0
        end
    end

    -- 1. 遮罩
    nvgBeginPath(nvg)
    nvgRect(nvg, 0, 0, W, H)
    nvgFillColor(nvg, Col(OVERLAY, floor((95 + tier * 12) * Clamp01(age / 0.2) * closeK)))
    nvgFill(nvg)

    local pw = min(W - 24, 360)
    local u = pw / 360
    local inK = EaseOutBack(Clamp01(age / 0.3))
    local sc = (0.55 + 0.45 * inK) * (self.closing_ >= 0 and (0.9 + 0.1 * closeK) or 1)
    -- 版面高度：徽记 64 + 标题 64 + 绶带 52 + 卡片 196 + 吐槽 34 + 按钮 64
    local totalH = (64 + 64 + 52 + 196 + 34 + 64) * u
    local cx = W * 0.5
    local top = max(12, (H - totalH) * 0.45)

    nvgSave(nvg)
    nvgTranslate(nvg, cx, H * 0.5)
    nvgScale(nvg, sc, sc)
    nvgTranslate(nvg, -cx, -H * 0.5)

    local emblemY = top + 32 * u
    local titleY = top + 64 * u + 32 * u
    local ribbonY = top + 128 * u + 24 * u
    local panelY = top + 180 * u
    local panelH = 196 * u
    local quoteY = panelY + panelH + 18 * u
    local btnY = quoteY + 18 * u

    -- 2. 背景光芒 / 光环（档位越高越多越彩）
    if def.rays > 0 then
        SetAdditive(nvg, true)
        local rcol = (tier >= 5) and Rainbow(t * 3) or GOLD
        DrawRays(nvg, cx, titleY, 20 * u, pw * (0.62 + tier * 0.06), def.rays, t * 0.35, rcol, floor(A * (0.22 + tier * 0.04)))
        if tier >= 6 then
            -- 地球光环（经纬线）
            local gr = pw * 0.46
            nvgBeginPath(nvg)
            nvgCircle(nvg, cx, titleY + 10 * u, gr)
            nvgStrokeColor(nvg, Col(CYAN, floor(A * 0.35)))
            nvgStrokeWidth(nvg, 2)
            nvgStroke(nvg)
            for k = 1, 3 do
                nvgBeginPath(nvg)
                nvgEllipse(nvg, cx, titleY + 10 * u, gr * (0.3 + k * 0.22), gr)
                nvgEllipse(nvg, cx, titleY + 10 * u, gr, gr * (0.25 + k * 0.2))
                nvgStrokeColor(nvg, Col(CYAN, floor(A * 0.16)))
                nvgStrokeWidth(nvg, 1)
                nvgStroke(nvg)
            end
        end
        SetAdditive(nvg, false)
    end

    -- 3. 徽记
    local bob = sin(t * 3) * 3 * u
    if tier >= 6 then
        DrawCrown(nvg, cx, emblemY + bob, 64 * u, A, true, t)
    elseif tier == 5 then
        DrawCrown(nvg, cx, emblemY + bob, 54 * u, A, true, t)
    elseif tier == 4 then
        DrawCrown(nvg, cx, emblemY + bob, 46 * u, A, false, t)
    elseif tier == 3 then
        DrawMedal(nvg, cx, emblemY - 6 * u + bob, 52 * u, A, true)
    elseif tier == 2 then
        DrawMedal(nvg, cx, emblemY - 6 * u + bob, 46 * u, A, false)
    else
        DrawChevrons(nvg, cx, emblemY - 8 * u, 44 * u, A, t)
    end

    -- 4. 3D 金色大标题（入场砸下 + 连超时再砸一次）
    nvgFontFace(nvg, self.font_)
    local slam = 1 + (1 - EaseOutBack(Clamp01((age - 0.05) / 0.25))) * 1.4 + self.punch_ * 0.3
    local titleTxt = def.title
    local titleFs = (40 + tier * 3) * u
    local tw = EstTextW(titleTxt, titleFs)
    if tw > pw * 0.95 then titleFs = titleFs * pw * 0.95 / tw end
    if age < 0.3 then
        nvgFontSize(nvg, titleFs * slam * 1.25)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, Col(GOLD, floor(A * 0.25)))
        nvgText(nvg, cx, titleY, titleTxt)
    end
    GoldTitle(nvg, cx, titleY, titleTxt, titleFs * slam, A)
    -- 连超角标
    if self.count_ > 1 then
        local badge = "连超 " .. tostring(self.count_) .. " 人"
        local bfs = 14 * u
        local bw = EstTextW(badge, bfs) + 18 * u
        local bx, by = cx + min(pw * 0.5 - bw * 0.5, EstTextW(titleTxt, titleFs) * 0.5), titleY - titleFs * 0.75
        nvgSave(nvg)
        nvgTranslate(nvg, bx, by)
        nvgRotate(nvg, 0.18)
        nvgScale(nvg, 1 + self.punch_ * 0.4, 1 + self.punch_ * 0.4)
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, -bw * 0.5, -12 * u, bw, 24 * u, 12 * u)
        nvgFillColor(nvg, Col(STAMP_RED, A))
        nvgFill(nvg)
        nvgStrokeColor(nvg, Col(C.white, A))
        nvgStrokeWidth(nvg, 1.5)
        nvgStroke(nvg)
        nvgFontSize(nvg, bfs)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, Col(C.white, A))
        nvgText(nvg, 0, 1, badge)
        nvgRestore(nvg)
    end

    -- 5. 绶带副标题：你已超越【名字】!
    local subFs = 16 * u
    local pre, post = "你已超越 ", "!"
    local name = self.txtName_
    local wPre, wName, wPost = EstTextW(pre, subFs), EstTextW(name, subFs), EstTextW(post, subFs)
    local need = wPre + wName + wPost
    local rw = min(pw * 0.92, need + 36 * u)
    if need > rw - 24 * u then
        subFs = subFs * (rw - 24 * u) / need
        wPre, wName, wPost = EstTextW(pre, subFs), EstTextW(name, subFs), EstTextW(post, subFs)
        need = wPre + wName + wPost
    end
    Ribbon(nvg, cx, ribbonY, rw, 34 * u, A)
    nvgFontSize(nvg, subFs)
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local sx = cx - need * 0.5
    nvgFillColor(nvg, Col(C.white, A))
    nvgText(nvg, sx, ribbonY + 1, pre)
    nvgFillColor(nvg, Col(GOLD, A))
    nvgText(nvg, sx + wPre, ribbonY + 1, name)
    nvgFillColor(nvg, Col(C.white, A))
    nvgText(nvg, sx + wPre + wName, ribbonY + 1, post)

    -- 6. 主面板
    local px0 = cx - pw * 0.5
    SetAdditive(nvg, true)
    nvgBeginPath(nvg)
    nvgRect(nvg, px0 - 20, panelY - 20, pw + 40, panelH + 40)
    local edgeCol = (tier >= 5) and Rainbow(t * 4) or PURPLE
    nvgFillPaint(nvg, nvgBoxGradient(nvg, px0, panelY, pw, panelH, 16, 22, Col(edgeCol, floor(A * 0.5)), Col(edgeCol, 0)))
    nvgFill(nvg)
    SetAdditive(nvg, false)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, px0, panelY, pw, panelH, 16)
    nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, panelY, 0, panelY + panelH, Col(PANEL_TOP, floor(A * 0.97)), Col(PANEL_BOT, floor(A * 0.97))))
    nvgFill(nvg)
    nvgStrokePaint(nvg, nvgLinearGradient(nvg, px0, panelY, px0 + pw, panelY + panelH, Col(CYAN, A), Col(edgeCol, A)))
    nvgStrokeWidth(nvg, 2.5)
    nvgStroke(nvg)
    -- 四角装饰
    nvgBeginPath(nvg)
    local cl = 16 * u
    for _, c in ipairs({ { px0 + 6, panelY + 6, 1, 1 }, { px0 + pw - 6, panelY + 6, -1, 1 }, { px0 + 6, panelY + panelH - 6, 1, -1 }, { px0 + pw - 6, panelY + panelH - 6, -1, -1 } }) do
        nvgMoveTo(nvg, c[1], c[2] + c[4] * cl)
        nvgLineTo(nvg, c[1], c[2])
        nvgLineTo(nvg, c[1] + c[3] * cl, c[2])
    end
    nvgStrokeColor(nvg, Col(GOLD, A))
    nvgStrokeWidth(nvg, 2.5)
    nvgStroke(nvg)

    -- 7. 对比双卡（左右滑入）
    local cardW, cardH = pw * 0.4, panelH - 24 * u
    local slideL = (1 - EaseOutBack(Clamp01((age - 0.15) / 0.3))) * -pw * 0.6
    local slideR = (1 - EaseOutBack(Clamp01((age - 0.22) / 0.3))) * pw * 0.6
    local lx, rx = px0 + 12 * u + slideL, px0 + pw - 12 * u - cardW + slideR
    local cy0 = panelY + 12 * u
    -- 左：你的财富
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, lx, cy0, cardW, cardH, 12)
    nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, cy0, 0, cy0 + cardH, Col(CARD_ME_TOP, A), Col(CARD_ME_BOT, A)))
    nvgFill(nvg)
    nvgStrokeColor(nvg, Col(GOLD, A))
    nvgStrokeWidth(nvg, 2)
    nvgStroke(nvg)
    nvgFontFace(nvg, self.font_)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(nvg, 13 * u)
    nvgFillColor(nvg, Col(C.white, A))
    nvgText(nvg, lx + cardW * 0.5, cy0 + 16 * u, "你的财富")
    DrawCoinStack(nvg, lx + cardW * 0.5, cy0 + 58 * u, 54 * u, A, t)
    local myCash = Number.FormatCash(ty and ty.lifetimeCash or 0)
    local cfs = 19 * u
    local cw = EstTextW(myCash, cfs)
    if cw > cardW - 10 then cfs = cfs * (cardW - 10) / cw end
    nvgFontSize(nvg, cfs)
    OutlinedText(nvg, lx + cardW * 0.5, cy0 + 106 * u, myCash, GOLD, A, 1.6)
    -- 你的世界排名徽条
    local myRank = "世界第 " .. RankLadder.FormatRankShort(Billionaires.CalcWorldRank(ty and ty.lifetimeCash or 0)) .. " 名"
    local rfs = 12 * u
    local rwid = min(cardW - 8, EstTextW(myRank, rfs) + 22 * u)
    if EstTextW(myRank, rfs) + 22 * u > cardW - 8 then rfs = rfs * (cardW - 30 * u) / EstTextW(myRank, rfs) end
    local ry = cy0 + cardH - 26 * u
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, lx + cardW * 0.5 - rwid * 0.5, ry - 11 * u, rwid, 22 * u, 11 * u)
    nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, ry - 11 * u, 0, ry + 11 * u, Col(GOLD, A), Col(GOLD_LO, A)))
    nvgFill(nvg)
    nvgFontSize(nvg, rfs)
    nvgFillColor(nvg, Col(GOLD_DEEP, A))
    nvgText(nvg, lx + cardW * 0.5, ry + 1, myRank)
    -- 月桂（左右两枝）
    for side = -1, 1, 2 do
        for k = 0, 3 do
            local ang = pi * 0.5 + side * (1.25 + k * 0.28)
            local lxp = lx + cardW * 0.5 + cos(ang) * rwid * 0.55
            local lyp = ry - 4 * u + sin(ang) * 14 * u
            nvgBeginPath(nvg)
            nvgEllipse(nvg, lxp, lyp, 4.5 * u, 2.2 * u)
            nvgFillColor(nvg, Col(LEAF, floor(A * 0.9)))
            nvgFill(nvg)
        end
    end

    -- 中间箭头（脉动）
    local ax = cx + (slideL + slideR) * 0.1
    local ay = cy0 + cardH * 0.5
    local ap = 1 + 0.12 * sin(t * 8)
    SetAdditive(nvg, true)
    nvgBeginPath(nvg)
    nvgCircle(nvg, ax, ay, 22 * u * ap)
    nvgFillPaint(nvg, nvgRadialGradient(nvg, ax, ay, 2, 22 * u * ap, Col(GOLD, floor(A * 0.6)), Col(GOLD, 0)))
    nvgFill(nvg)
    SetAdditive(nvg, false)
    for k = 0, 1 do
        local ox = ax - 8 * u + k * 10 * u
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, ox - 5 * u * ap, ay - 12 * u * ap)
        nvgLineTo(nvg, ox + 7 * u * ap, ay)
        nvgLineTo(nvg, ox - 5 * u * ap, ay + 12 * u * ap)
        nvgLineTo(nvg, ox - 1 * u, ay)
        nvgClosePath(nvg)
        nvgFillColor(nvg, Col(GOLD_HI, A))
        nvgFill(nvg)
    end

    -- 右：被超越者
    local greyK = self.stamped_ and 1 or 0
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, rx, cy0, cardW, cardH, 12)
    nvgFillPaint(nvg, nvgLinearGradient(nvg, 0, cy0, 0, cy0 + cardH, Col(CARD_RIVAL_TOP, A), Col(CARD_RIVAL_BOT, A)))
    nvgFill(nvg)
    nvgStrokeColor(nvg, Col(PURPLE, A))
    nvgStrokeWidth(nvg, 2)
    nvgStroke(nvg)
    nvgFontSize(nvg, 13 * u)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, Col(C.white, A))
    nvgText(nvg, rx + cardW * 0.5, cy0 + 16 * u, "被你超越")
    if self.item_ and self.item_.entry then
        AvatarArt.Draw(nvg, self.item_.entry, rx + cardW * 0.5, cy0 + 62 * u, 32 * u, {
            shocked = self.stamped_, surpassed = false, time = t,
        })
    end
    local nfs = 15 * u
    local nw = EstTextW(self.txtName_, nfs)
    if nw > cardW - 10 then nfs = nfs * (cardW - 10) / nw end
    nvgFontSize(nvg, nfs)
    nvgFillColor(nvg, Col(greyK > 0 and GREY or C.white, A))
    nvgText(nvg, rx + cardW * 0.5, cy0 + 110 * u, self.txtName_)
    local rkFs = 12 * u
    local rkw = EstTextW(self.txtRivalRank_, rkFs)
    if rkw > cardW - 10 * u then rkFs = rkFs * (cardW - 10 * u) / rkw end
    nvgFontSize(nvg, rkFs)
    nvgFillColor(nvg, Col(C.muted, A))
    nvgText(nvg, rx + cardW * 0.5, cy0 + 130 * u, self.txtRivalRank_)
    local rcFs = 13 * u
    local rcw = EstTextW(self.txtRivalCash_, rcFs)
    if rcw > cardW - 10 * u then rcFs = rcFs * (cardW - 10 * u) / rcw end
    nvgFontSize(nvg, rcFs)
    nvgFillColor(nvg, Col(GOLD, floor(A * (greyK > 0 and 0.6 or 1))))
    nvgText(nvg, rx + cardW * 0.5, cy0 + cardH - 18 * u, self.txtRivalCash_)
    -- 已超越印章（0.5s 砸上）
    if self.stamped_ then
        local su = Clamp01((age - 0.5) / 0.16)
        local ssc = 1 + (1 - EaseOutBack(su)) * 1.8
        nvgSave(nvg)
        nvgTranslate(nvg, rx + cardW * 0.62, cy0 + 84 * u)
        nvgRotate(nvg, -0.24)
        nvgScale(nvg, ssc, ssc)
        local bw, bh = 76 * u, 26 * u
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, -bw * 0.5, -bh * 0.5, bw, bh, 6)
        nvgFillColor(nvg, Col(STAMP_RED, floor(A * 0.9)))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, -bw * 0.5 + 3, -bh * 0.5 + 3, bw - 6, bh - 6, 4)
        nvgStrokeColor(nvg, Col(C.white, A))
        nvgStrokeWidth(nvg, 1.6)
        nvgStroke(nvg)
        nvgFontSize(nvg, 15 * u)
        nvgFillColor(nvg, Col(C.white, A))
        nvgText(nvg, 0, 1, "已超越")
        nvgRestore(nvg)
    end

    -- 8. 吐槽
    if self.txtQuote_ ~= "" and age > 0.6 then
        local qa = floor(A * Clamp01((age - 0.6) / 0.25))
        local qfs = 13 * u
        local qw = EstTextW(self.txtQuote_, qfs)
        if qw > pw - 10 then qfs = qfs * (pw - 10) / qw end
        nvgFontSize(nvg, qfs)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, Col(C.white, qa))
        nvgText(nvg, cx, quoteY, self.txtQuote_)
    end

    -- 9. 按钮（0.6s 弹出，呼吸）
    for i = 1, #self.btns_ do self.btns_[i].w = 0 end
    if age > 0.55 then
        local bk = EaseOutBack(Clamp01((age - 0.55) / 0.25))
        local ba = floor(A * Clamp01((age - 0.55) / 0.15))
        local pulse = 0.5 + 0.5 * sin(t * 6)
        local bh = 50 * u
        local by = btnY + (1 - bk) * 30 * u
        if self.sp_ > 0 then
            local gap = 12 * u
            local bw = (pw - gap) * 0.5
            local b1 = self.btns_[1] or {}; self.btns_[1] = b1
            local b2 = self.btns_[2] or {}; self.btns_[2] = b2
            b1.id, b1.x, b1.y, b1.w, b1.h = "collect", px0, by, bw, bh
            b2.id, b2.x, b2.y, b2.w, b2.h = "ad", px0 + bw + gap, by, bw, bh
            if self.btnSp_ ~= self.sp_ then
                self.btnSp_ = self.sp_
                self.btnTxt1_ = "收下 +" .. tostring(self.sp_) .. "技能点"
                self.btnTxt2_ = "×3 看广告"
            end
            Button(nvg, b1.x, b1.y, b1.w, b1.h, self.btnTxt1_, ba, false, 0, self.font_)
            Button(nvg, b2.x, b2.y, b2.w, b2.h, self.btnTxt2_, ba, true, pulse, self.font_)
        else
            local bw = min(pw * 0.6, 220 * u)
            local b1 = self.btns_[1] or {}; self.btns_[1] = b1
            b1.id, b1.x, b1.y, b1.w, b1.h = "collect", cx - bw * 0.5, by, bw, bh
            Button(nvg, b1.x, b1.y, b1.w, b1.h, (tier >= 4) and "太棒了!" or "继续冲!", ba, false, pulse, self.font_)
            -- 自动收起倒计时细条
            if def.auto > 0 then
                local prog = 1 - Clamp01(age / def.auto)
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, b1.x + 10, by + bh + 8 * u, (b1.w - 20) * prog, 3, 1.5)
                nvgFillColor(nvg, Col(GOLD, floor(ba * 0.7)))
                nvgFill(nvg)
            end
        end
    end
    nvgRestore(nvg)
    -- 按钮命中框随整体缩放（sc 在入场后为 1，命中误差可忽略）
end

return OvertakePopup
