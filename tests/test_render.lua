-- ============================================================================
-- tests/test_render.lua  渲染层纯 Lua 回归测试（严格校验 Skin.Col / Stage / Fx / AvatarArt）
--   · 覆盖 Stage:Render（待机 / 老虎机旋转 / 100x狂潮 / Fever / 全部22+种硬币）
--   · 覆盖 Fx 全部回调 + RenderWorld/RenderOverlay、AvatarArt 85 档头像、Skin 全样式
--   · 任何 nil 颜色表、缺失 Skin.C 键或绘制层 nil 索引错误都将立即断言失败
-- ============================================================================

NVG_ALIGN_CENTER = 2
NVG_ALIGN_MIDDLE = 16
NVG_CW = 2
NVG_ROUND = 1

local function noop() end
for _, fnName in ipairs({
    "nvgSave", "nvgRestore", "nvgBeginPath", "nvgClosePath", "nvgFill", "nvgStroke",
    "nvgFillColor", "nvgStrokeColor", "nvgFillPaint", "nvgStrokeWidth",
    "nvgRect", "nvgRoundedRect", "nvgCircle", "nvgEllipse", "nvgArc",
    "nvgMoveTo", "nvgLineTo", "nvgBezierTo", "nvgQuadTo",
    "nvgTranslate", "nvgRotate", "nvgScale", "nvgIntersectScissor",
    "nvgFontFace", "nvgFontSize", "nvgTextAlign", "nvgText",
    "nvgLineCap", "nvgLineJoin",
}) do
    _G[fnName] = noop
end

function nvgRGBA(r, g, b, a)
    assert(type(r) == "number" and type(g) == "number" and type(b) == "number" and type(a) == "number",
        "nvgRGBA 参数必须是 4 个数字")
    return { r = r, g = g, b = b, a = a }
end
function nvgLinearGradient() return {} end
function nvgRadialGradient() return {} end
function nvgCreateImage() return 0 end
function nvgImagePattern() return {} end

-- 轻量 Stub urhox-libs/UI（供 Stage / Widgets 在无引擎环境下加载）
package.loaded["urhox-libs/UI"] = {
    Widget = {
        Extend = function(self)
            local cls = {}
            cls.__index = cls
            setmetatable(cls, { __index = self })
            return cls
        end,
        Init = function() end,
    },
    GetWidth = function() return 360 end,
    GetHeight = function() return 667 end,
    Input = { On = noop },
}

local Skin = require("game/Skin")
local origCol = Skin.Col
Skin.Col = function(t, a)
    assert(type(t) == "table" and type(t[1]) == "number" and type(t[2]) == "number" and type(t[3]) == "number",
        "Skin.Col 收到非法/nil 颜色表: " .. tostring(t))
    return origCol(t, a)
end

local Config = require("game/Config")
local Tycoon = require("game/Tycoon")
local Fx = require("game/Fx")
local Stage = require("game/Stage")
local AvatarArt = require("game/AvatarArt")
local Art = require("game/Art")

-- 1. Skin.Draw 全样式校验
for _, stName in ipairs({ "button", "panel", "card", "slot", "plate", "cloth", "banner" }) do
    Skin.Draw("nvg_stub", stName, 10, 10, 140, 44, { variant = "primary", rarity = "legendary", selected = true, color = "gold" })
    Skin.Draw("nvg_stub", stName, 10, 10, 140, 44, { variant = "dark", rarity = "common", pressed = true, disabled = true, color = "red" })
end

-- 2. AvatarArt 全体 85 个榜单元（匿名剪影 + 前1000强真名富豪）校验
for idx, rk in ipairs(Config.RANKS) do
    AvatarArt.Draw("nvg_stub", rk, 60, 60, 40, { shocked = false, surpassed = (idx % 2 == 0), time = 0.5 })
    AvatarArt.Draw("nvg_stub", rk, 60, 60, 40, { shocked = true, surpassed = true, time = 1.2 })
end
AvatarArt.Draw("nvg_stub", nil, 60, 60, 32, {})

-- 3. Stage:Render 在待机 / 老虎机旋转 / 100x 狂潮 / 狂欢 / 全硬币种类下的完整渲染校验
local ty = Tycoon.New(nil, { seed = 20261126 })
local fx = Fx.New()
local game = {
    tycoon = ty,
    fx = fx,
    time = 1.25,
    font = "sans",
    showTapHint = function() return true end,
}

local stg = setmetatable({}, Stage)
stg:Init({ game = game })
stg.GetAbsoluteLayout = function() return { x = 0, y = 102, w = 360, h = 493 } end

-- (a) 严格复现刚进游戏待机态：slotSpinning=false, luckMult=1, slotFlashT=0 (hot == false)
ty.slotSpinning = false
ty.luckMult = 1
ty.slotFlashT = 0
ty.slotQueue = 0
ty.adBoostLeft = 0
ty.feverActive = false
stg:Render("nvg_stub")

-- (b) 过门抽奖旋转中 + 待抽队列 + 第1~3符号
ty.slotSpinning = true
ty.slotSpinT = 0.25
ty.slotSpinDur = 0.85
ty.slotQueue = 3
ty.slotReels = { 1, 2, 3 }
stg:Render("nvg_stub")

-- (c) 锁定第4~6符号 + 100倍大满贯狂潮倒计时条 + 连击 + Fever + 广告×3
ty.slotSpinning = false
ty.slotReels = { 4, 5, 6 }
ty.luckMult = 100
ty.luckTimer = 14.2
ty.luckDur = 15
ty.luckName = "777大满贯 ×100!!"
ty.feverActive = true
ty.feverTimer = 5.0
ty.adBoostLeft = 90
ty.combo = 35
for i, tier in ipairs(Config.COIN_TIERS) do
    ty.physics:SpawnCoin({ kind = tier.id, level = (i % 15) + 1, x = 80 + (i % 7) * 32, y = 340 + math.floor(i / 7) * 32, zone = "deck" })
end
stg:Render("nvg_stub")

-- 4. Fx 全回调与 2D / 3D 投射渲染路径校验
fx:OnPegHit({ x = 180, y = 120 }, { x = 180, y = 120, kind = "mult" })
fx:OnScore(2500, 180, 120, true, 12, "drop", 500)
fx:OnGateWin({ x = 180, y = 216 }, "过门 ×2 + 老虎机!")
fx:OnUnlockCoin(Config.COINS.midas)
fx:OnPrestige(4, 6, "A 轮霓虹集团")
fx:OnRankUp(Config.RANKS[#Config.RANKS])
fx:OnSkillPointsGain(5, 10)
fx:OnAdReward("超级印钞 ×3 激活!")
fx:OnFrontDrop({ kind = "gold", x = 180, y = 540 }, 12000, true)
fx:OnSideDrain({ kind = "gold", x = 35, y = 490 })
fx:OnLightning(120, 150, 220, 340)
fx:OnExplosion(180, 400, 90)
fx:OnBlackholeBurst(180, 380, 90)
fx:OnJackpot777(180, 360)
fx:OnFeverStart(ty)
for _, prize in pairs(Config.SLOT_PRIZES) do
    fx:OnSlotWin(prize)
end
fx:Update(0.016)
fx:RenderWorld("nvg_stub", "sans")
fx:RenderWorld("nvg_stub", "sans", function(lx, ly) return lx, ly + 102 end)
fx:RenderOverlay("nvg_stub", 360, 493, "sans", ty)

-- 5. Art 全徽章绘制校验
for _, iconKey in ipairs({ "coin", "gear", "shield", "bolt", "flame", "crit", "lock", "magnet", "book", "skull", "play", "star" }) do
    Art.DrawIcon("nvg_stub", iconKey, 20, 20, 18, Skin.C.gold)
end

print("[test_render] ALL PASS! ranks_drawn=" .. tostring(#Config.RANKS) .. " coins_drawn=" .. tostring(#Config.COIN_TIERS))
