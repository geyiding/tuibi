-- ============================================================================
-- tests/test_render.lua  渲染层纯 Lua 回归测试（严格校验 Skin.Col / Stage / Fx / AvatarArt）
--   · 覆盖 Stage:Render（待机 / 老虎机旋转 / 100x狂潮 / Fever / 全部22+种硬币）
--   · 覆盖 Fx 全部回调 + RenderWorld/RenderOverlay、AvatarArt 85 档头像、Skin 全样式
--   · 任何 nil 颜色表、缺失 Skin.C 键或绘制层 nil 索引错误都将立即断言失败
-- ============================================================================

NVG_ALIGN_CENTER = 2
NVG_ALIGN_MIDDLE = 16
NVG_ALIGN_LEFT = 1
NVG_ALIGN_RIGHT = 4
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
function nvgBoxGradient() return {} end
NVG_LIGHTER = 8
NVG_SOURCE_OVER = 0
local compositeCalls = 0
function nvgGlobalCompositeOperation(_, op)
    assert(op == NVG_LIGHTER or op == NVG_SOURCE_OVER, "非法混合模式")
    compositeCalls = compositeCalls + 1
end
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
    Label = function(p) return { props = p, SetText = function() end, SetStyle = function() end } end,
    GetWidth = function() return 360 end,
    GetHeight = function() return 667 end,
    Input = { On = noop },
}

package.loaded["urhox-libs/UI"].Panel = package.loaded["urhox-libs/UI"].Widget
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
local JuiceWidgets = require("game/JuiceWidgets")
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

-- 6. 新爽感链路：倍率追踪令牌 / 飞币入账 / 印章队列 / 购买爆点 / 全屏层（待机 / 激活 / 极值）
local fx2 = Fx.New()
local ty2 = Tycoon.New(fx2, { seed = 7 })
fx2.toScreen = function(x, y) return x, y + 100 end
fx2:TrackMult(ty2)                                 -- 初始化基线
ty2.combo = 60; ty2:TriggerFever(false); ty2.luckMult = 100; ty2.luckTimer = 15; ty2.luckDur = 15; ty2.adBoostLeft = 30
ty2.machineLv.global_mult = 3; ty2:InvalidateCaches()
fx2:TrackMult(ty2)                                 -- 狂欢 / 老虎机 / 印钞 / 连击 / 永久 五种令牌
local tokOn = 0
for i = 1, #fx2.tokens do if fx2.tokens[i].on then tokOn = tokOn + 1 end end
assert(tokOn >= 4, "倍率增益必须生成飞向招牌的令牌, got " .. tokOn)
assert(fx2.multTotal > 1000, "极值态总倍率应 > 1000")
assert(fx2.heat > 0.9, "极值态热度应接近 1")
-- 基准产值不含临时加成：×100 老虎机期间单次掉落应冲上高阶飘字
local base = ty2:GetBaselineCPS()
assert(base > 0 and base < ty2:GetEstimatedCPS(), "基准产值必须剔除临时加成")
assert(Fx.CalcTier(base * 0.5 * 100, base) == 5, "临时 ×100 时普通掉落应达到 T5")
for k = 1, 30 do
    fx2:OnScore(base * (k % 5 + 1) * 3, 120 + k * 4, 520, k % 3 == 0, 60, "gold", base, ty2:GetTotalMult())
    fx2:OnScore(base * 0.05, 180, 120, false, 60, "peg", base, 1)
end
fx2:OnFrontDrop({ kind = "giant", x = 180, y = 540 }, base * 50, true)
fx2:OnSlotWin(Config.SLOT_PRIZES.jackpot_777)
fx2:OnSlotWin(Config.SLOT_PRIZES.triple_bolt)       -- 低优先级进入队列
fx2:OnSlotWin(Config.SLOT_PRIZES.pair)
fx2:OnSlotWin(Config.SLOT_PRIZES.miss)
fx2:OnRankUp(Config.RANKS[#Config.RANKS], true, {})
fx2:OnPrestige(10, 5, "港股敲钟上市")
fx2:OnSkillPointsGain(3); fx2:OnSkillPointsGain(4)
fx2:UiBurst(100, 600, 120, 46, "Lv.5!", Skin.C.gold)
fx2:OnTap(200, 400)
fx2:OnExplosion(180, 400, 90)
fx2:OnLightning(120, 150, 220, 340)
local merged = 0
for i = 1, #fx2.pops do if fx2.pops[i].life > 0 and fx2.pops[i].tier >= 4 then merged = merged + 1 end end
assert(merged <= 3, "高阶爆分必须合并为少量滚动大数字, got " .. merged)
local cc = setmetatable({}, JuiceWidgets.CashCounter)
cc:Init({ getTycoon = function() return ty2 end, getTime = function() return fx2.time end, fx = fx2 })
cc.GetAbsoluteLayout = function() return { x = 90, y = 10, w = 150, h = 54 } end
local layer = setmetatable({}, JuiceWidgets.FxLayer)
layer:Init({ fx = fx2, isModalOpen = function() return false end })
for f = 1, 90 do
    ty2:Update(1 / 60)
    fx2:TrackMult(ty2)
    fx2:Update(1 / 60)
    cc:Render("nvg_stub")
    layer:Render("nvg_stub")
end
fx2:Render("nvg_stub", 360, 667, "sans", true)     -- 弹窗打开态
assert(fx2.cashHits == 0, "飞币砸中计数必须被现金计数器消费")
assert(compositeCalls > 0, "发光特效应使用叠加混合")

-- 7. Stage 3D 锚点分支（模拟 Machine3D 激活）
local Machine3D = require("game/Machine3D")
local realActive, realAnchor, realProj = Machine3D.IsActive, Machine3D.GetAnchor, Machine3D.ProjectFast
Machine3D.IsActive = function() return true end
Machine3D.GetAnchor = function(name, w, h)
    local tbl = { marquee = { 0.5, 0.2 }, slotTL = { 0.16, 0.25 }, slotTR = { 0.84, 0.25 }, slotBot = { 0.5, 0.47 },
        deckTL = { 0.19, 0.49 }, deckTR = { 0.81, 0.49 }, deckBL = { 0.1, 0.68 }, deckBR = { 0.9, 0.68 } }
    local v = tbl[name]; return v[1] * w, v[2] * h
end
Machine3D.ProjectFast = function(lx, ly, w, h) return lx * w / 360, 160 + ly * 0.8 end
local game3 = { tycoon = ty2, fx = fx2, time = 2.0, font = "sans", showTapHint = function() return true end }
local stg3 = setmetatable({}, Stage)
stg3:Init({ game = game3 })
stg3.GetAbsoluteLayout = function() return { x = 0, y = 126, w = 360, h = 469 } end
for f = 1, 6 do game3.time = game3.time + 0.016; stg3:Render("nvg_stub") end
ty2.slotSpinning = true; ty2.slotSpinT = 0.5; stg3:Render("nvg_stub")
ty2.combo = 0; ty2.feverActive = false; ty2.luckMult = 1; ty2.adBoostLeft = 0; stg3:Render("nvg_stub")
assert(fx2.ancMultX > 0 and fx2.ancSlotY > fx2.ancMultY, "招牌在上、滚轮在下")
Machine3D.IsActive, Machine3D.GetAnchor, Machine3D.ProjectFast = realActive, realAnchor, realProj

-- 8. 程序化 UI：财富进度条（待机 / 接近完成 / 满）、买得起呼吸光、图标投影
local Widgets = require("game/Widgets")
for _, v in ipairs({ 0, 0.42, 0.95, 1 }) do
    local bar = setmetatable({}, Widgets.NeoBar)
    bar:Init({ value = v, text = "下位: No.1 马斯克", color = (v >= 1) and Skin.C.gold or Skin.C.cyan })
    bar.GetAbsoluteLayout = function() return { x = 10, y = 10, w = 260, h = 28 } end
    for f = 1, 3 do Widgets.Tick(0.4); bar:Render("nvg_stub") end
    bar:SetProgress(0.05, "重置", Skin.C.green); bar:Render("nvg_stub")
end
Widgets.DrawAffordGlow("nvg_stub", { x = 0, y = 0, w = 80, h = 100 }, 10)
for _, k in ipairs({ "gear", "shield", "heart", "bolt", "star", "crown", "flame", "lock", "magnet", "chest", "skull", "play", "coin" }) do
    Art.DrawIcon("nvg_stub", k, 0, 0, 24, nil)
    Art.DrawIcon("nvg_stub", k, 0, 0, 24, Skin.C.red)
end

print("[test_render] ALL PASS! ranks_drawn=" .. tostring(#Config.RANKS) .. " coins_drawn=" .. tostring(#Config.COIN_TIERS))
