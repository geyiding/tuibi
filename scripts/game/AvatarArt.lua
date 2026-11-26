-- ============================================================================
-- AvatarArt.lua  程序化世界富豪“擦边漫画风”头像生成器（纯 NanoVG，零贴图依赖）
--   · 支持 100 位富豪独特面相（肤色/脸型/发型/眼镜/胡须/服饰/随身梗道具）
--   · 支持 shocked（被反超吓呆表情+冷汗滴）与 surpassed（倾斜“已超越”印章）状态
-- ============================================================================

local Skin = require("game/Skin")
local C = Skin.C
local Col = Skin.Col
local min, max, sin, cos, pi = math.min, math.max, math.sin, math.cos, math.pi

local AvatarArt = {}

local SKINS = {
    { 255, 224, 198 }, -- 1 白皙
    { 246, 206, 174 }, -- 2 欧美暖调
    { 244, 208, 162 }, -- 3 东亚温润
    { 208, 152, 108 }, -- 4 古铜/南亚
    { 148, 96, 68 },   -- 5 深麦/非裔
    { 238, 192, 160 }, -- 6 红润
}

local BG_PAL = {
    [1] = { { 112, 68, 12 }, { 28, 16, 44 }, { 255, 214, 68 } },  -- Top10 皇室金芒
    [2] = { { 98, 32, 128 }, { 22, 16, 48 }, { 255, 86, 186 } },  -- 11~35 霓虹紫魅
    [3] = { { 18, 86, 134 }, { 14, 22, 48 }, { 64, 224, 255 } },  -- 36~70 赛博青蓝
    [4] = { { 36, 68, 92 },  { 16, 20, 38 }, { 126, 232, 156 } }, -- 71~100 新秀翡翠
}

local function Darker(rgb, f)
    return {
        max(0, math.floor(rgb[1] * f)),
        max(0, math.floor(rgb[2] * f)),
        max(0, math.floor(rgb[3] * f)),
    }
end

local function DrawPropBadge(nvg, prop, bx, by, br, tierCol)
    nvgSave(nvg)
    nvgTranslate(nvg, bx, by)

    -- 底座徽章圆圈
    nvgBeginPath(nvg)
    nvgCircle(nvg, 0, 0, br)
    nvgFillColor(nvg, Col(C.bgInset, 248))
    nvgFill(nvg)
    nvgStrokeColor(nvg, Col(tierCol, 240))
    nvgStrokeWidth(nvg, max(1.4, br * 0.14))
    nvgStroke(nvg)

    local s = br * 0.62
    if prop == "rocket" then
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, 0, -s * 1.1)
        nvgLineTo(nvg, s * 0.48, s * 0.25)
        nvgLineTo(nvg, -s * 0.48, s * 0.25)
        nvgClosePath(nvg)
        nvgFillColor(nvg, Col(C.white, 250))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, -s * 0.28, s * 0.35)
        nvgLineTo(nvg, 0, s * 1.05)
        nvgLineTo(nvg, s * 0.28, s * 0.35)
        nvgClosePath(nvg)
        nvgFillColor(nvg, Col(C.gold, 255))
        nvgFill(nvg)
    elseif prop == "gpu" then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, -s * 0.95, -s * 0.52, s * 1.9, s * 1.04, 2)
        nvgFillColor(nvg, Col({ 44, 186, 92 }, 255))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgCircle(nvg, -s * 0.38, 0, s * 0.32)
        nvgCircle(nvg, s * 0.38, 0, s * 0.32)
        nvgFillColor(nvg, Col(C.bgInset, 240))
        nvgFill(nvg)
    elseif prop == "vr" then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, -s * 0.9, -s * 0.42, s * 1.8, s * 0.84, s * 0.3)
        nvgFillColor(nvg, Col(C.cyan, 245))
        nvgFill(nvg)
    elseif prop == "cola" then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, -s * 0.42, -s * 0.78, s * 0.84, s * 1.56, s * 0.2)
        nvgFillColor(nvg, Col(C.red, 255))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgRect(nvg, -s * 0.42, -s * 0.15, s * 0.84, s * 0.3)
        nvgFillColor(nvg, Col(C.white, 240))
        nvgFill(nvg)
    elseif prop == "window" then
        local q = s * 0.42
        nvgBeginPath(nvg); nvgRect(nvg, -q * 1.85, -q * 1.85, q * 1.6, q * 1.6); nvgFillColor(nvg, Col(C.red, 250)); nvgFill(nvg)
        nvgBeginPath(nvg); nvgRect(nvg, q * 0.25, -q * 1.85, q * 1.6, q * 1.6); nvgFillColor(nvg, Col(C.green, 250)); nvgFill(nvg)
        nvgBeginPath(nvg); nvgRect(nvg, -q * 1.85, q * 0.25, q * 1.6, q * 1.6); nvgFillColor(nvg, Col(C.cyan, 250)); nvgFill(nvg)
        nvgBeginPath(nvg); nvgRect(nvg, q * 0.25, q * 0.25, q * 1.6, q * 1.6); nvgFillColor(nvg, Col(C.gold, 250)); nvgFill(nvg)
    elseif prop == "water" then
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, 0, -s * 0.95)
        nvgBezierTo(nvg, s * 0.8, -s * 0.1, s * 0.75, s * 0.9, 0, s * 0.92)
        nvgBezierTo(nvg, -s * 0.75, s * 0.9, -s * 0.8, -s * 0.1, 0, -s * 0.95)
        nvgFillColor(nvg, Col(C.cyan, 255))
        nvgFill(nvg)
    elseif prop == "penguin" then
        nvgBeginPath(nvg)
        nvgEllipse(nvg, 0, s * 0.08, s * 0.65, s * 0.82)
        nvgFillColor(nvg, Col({ 28, 34, 48 }, 255))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgEllipse(nvg, 0, s * 0.22, s * 0.42, s * 0.55)
        nvgFillColor(nvg, Col(C.white, 250))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgRect(nvg, -s * 0.55, -s * 0.12, s * 1.1, s * 0.22)
        nvgFillColor(nvg, Col(C.red, 255))
        nvgFill(nvg)
    elseif prop == "car" then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, -s * 0.92, -s * 0.18, s * 1.84, s * 0.66, s * 0.2)
        nvgFillColor(nvg, Col(C.cyan, 255))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgCircle(nvg, -s * 0.5, s * 0.52, s * 0.24)
        nvgCircle(nvg, s * 0.5, s * 0.52, s * 0.24)
        nvgFillColor(nvg, Col(C.gold, 255))
        nvgFill(nvg)
    elseif prop == "btc" then
        nvgBeginPath(nvg)
        nvgCircle(nvg, 0, 0, s * 0.84)
        nvgFillColor(nvg, Col(C.gold, 255))
        nvgFill(nvg)
        nvgFontFace(nvg, "sans")
        nvgFontSize(nvg, max(8, s * 1.25))
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, Col(C.bgInset, 255))
        nvgText(nvg, 0, 0.5, "₿")
    elseif prop == "ball" then
        nvgBeginPath(nvg)
        nvgCircle(nvg, 0, 0, s * 0.82)
        nvgFillColor(nvg, Col({ 242, 128, 36 }, 255))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, -s * 0.8, 0); nvgLineTo(nvg, s * 0.8, 0)
        nvgMoveTo(nvg, 0, -s * 0.8); nvgLineTo(nvg, 0, s * 0.8)
        nvgStrokeColor(nvg, Col(C.bgInset, 220))
        nvgStrokeWidth(nvg, 1.2)
        nvgStroke(nvg)
    elseif prop == "mic" then
        nvgBeginPath(nvg)
        nvgCircle(nvg, s * 0.16, -s * 0.34, s * 0.42)
        nvgFillColor(nvg, Col(C.magenta, 255))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, 0, 0); nvgLineTo(nvg, -s * 0.55, s * 0.72)
        nvgStrokeColor(nvg, Col(C.white, 240))
        nvgStrokeWidth(nvg, max(2, s * 0.26))
        nvgStroke(nvg)
    elseif prop == "steam" then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, -s * 0.86, -s * 0.48, s * 1.72, s * 0.96, s * 0.35)
        nvgFillColor(nvg, Col(C.purple, 250))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgCircle(nvg, -s * 0.38, 0, s * 0.18)
        nvgCircle(nvg, s * 0.38, 0, s * 0.18)
        nvgFillColor(nvg, Col(C.white, 255))
        nvgFill(nvg)
    elseif prop == "bag" then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, -s * 0.68, -s * 0.35, s * 1.36, s * 1.1, s * 0.22)
        nvgFillColor(nvg, Col(C.gold, 255))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgArc(nvg, 0, -s * 0.35, s * 0.38, pi, 0, NVG_CW)
        nvgStrokeColor(nvg, Col(C.white, 240))
        nvgStrokeWidth(nvg, max(1.5, s * 0.2))
        nvgStroke(nvg)
    elseif prop == "pig" then
        nvgBeginPath(nvg)
        nvgEllipse(nvg, 0, s * 0.05, s * 0.78, s * 0.62)
        nvgFillColor(nvg, Col({ 255, 146, 178 }, 255))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgCircle(nvg, 0, s * 0.14, s * 0.25)
        nvgFillColor(nvg, Col({ 226, 92, 136 }, 255))
        nvgFill(nvg)
    elseif prop == "phone" then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, -s * 0.48, -s * 0.82, s * 0.96, s * 1.64, s * 0.18)
        nvgFillColor(nvg, Col({ 34, 42, 62 }, 255))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, -s * 0.36, -s * 0.64, s * 0.72, s * 1.24, 1)
        nvgFillColor(nvg, Col(C.cyan, 235))
        nvgFill(nvg)
    else -- crown / fallback
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, -s * 0.75, s * 0.45)
        nvgLineTo(nvg, -s * 0.75, -s * 0.35)
        nvgLineTo(nvg, -s * 0.32, s * 0.05)
        nvgLineTo(nvg, 0, -s * 0.62)
        nvgLineTo(nvg, s * 0.32, s * 0.05)
        nvgLineTo(nvg, s * 0.75, -s * 0.35)
        nvgLineTo(nvg, s * 0.75, s * 0.45)
        nvgClosePath(nvg)
        nvgFillColor(nvg, Col(C.gold, 255))
        nvgFill(nvg)
    end

    nvgRestore(nvg)
end

--- 绘制富豪漫画头像圆章
---@param nvg any
---@param entry table|nil Billionaires.LIST 元素
---@param cx number
---@param cy number
---@param radius number
---@param opts table|nil { shocked = bool, surpassed = bool, time = number }
function AvatarArt.Draw(nvg, entry, cx, cy, radius, opts)
    if not nvg then return end
    opts = opts or {}
    local av = (entry and entry.avatar) or {
        skin = 2, head = "oval", hair = "part", hairCol = { 48, 38, 30 },
        glasses = "none", beard = "none", outfit = "suit", outfitCol = { 34, 44, 68 },
        prop = "crown", bgTier = 4,
    }
    local r = max(12, radius or 24)
    local shocked = (opts.shocked == true)
    local surpassed = (opts.surpassed == true)
    local bgP = BG_PAL[av.bgTier or 4] or BG_PAL[4]
    local tierCol = bgP[3]
    local skinCol = SKINS[av.skin or 2] or SKINS[2]
    local skinDark = Darker(skinCol, 0.80)
    local hairCol = av.hairCol or { 42, 34, 28 }
    local outCol = av.outfitCol or { 36, 44, 68 }
    local outDark = Darker(outCol, 0.66)

    nvgSave(nvg)
    nvgLineCap(nvg, NVG_ROUND)
    nvgLineJoin(nvg, NVG_ROUND)

    -- 1. 外圈光环 + 圆形底色渐变
    if av.bgTier == 1 or shocked then
        nvgBeginPath(nvg)
        nvgCircle(nvg, cx, cy, r * 1.12)
        nvgFillColor(nvg, Col(shocked and C.gold or tierCol, 65))
        nvgFill(nvg)
    end

    nvgBeginPath(nvg)
    nvgCircle(nvg, cx, cy, r)
    nvgFillPaint(nvg, nvgRadialGradient(nvg, cx, cy - r * 0.25, r * 0.1, r,
        Col(bgP[1], 255), Col(bgP[2], 255)))
    nvgFill(nvg)

    -- 2. 漫画放射光束（严格落在圆内 0.92r，绝不溢出边框）
    if r >= 22 then
        nvgBeginPath(nvg)
        local rays = (av.bgTier == 1) and 10 or 6
        local spin = (opts.time or 0) * (shocked and 1.1 or 0.18)
        for k = 0, rays - 1 do
            local a1 = spin + (k / rays) * pi * 2
            local a2 = a1 + (pi / rays) * 0.45
            nvgMoveTo(nvg, cx, cy)
            nvgLineTo(nvg, cx + cos(a1) * r * 0.92, cy + sin(a1) * r * 0.92)
            nvgLineTo(nvg, cx + cos(a2) * r * 0.92, cy + sin(a2) * r * 0.92)
            nvgClosePath(nvg)
        end
        nvgFillColor(nvg, Col(tierCol, shocked and 48 or 24))
        nvgFill(nvg)
    end

    -- 3. 肩部与个性服饰（严格贴合圆底弧面）
    local shY = cy + r * 0.46
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, cx - r * 0.72, cy + r * 0.58)
    nvgBezierTo(nvg, cx - r * 0.56, shY - r * 0.12, cx - r * 0.25, shY - r * 0.14, cx, shY - r * 0.12)
    nvgBezierTo(nvg, cx + r * 0.25, shY - r * 0.14, cx + r * 0.56, shY - r * 0.12, cx + r * 0.72, cy + r * 0.58)
    nvgBezierTo(nvg, cx + r * 0.45, cy + r * 0.94, cx - r * 0.45, cy + r * 0.94, cx - r * 0.72, cy + r * 0.58)
    nvgClosePath(nvg)
    nvgFillPaint(nvg, nvgLinearGradient(nvg, cx, shY - r * 0.1, cx, cy + r * 0.95,
        Col(outCol, 255), Col(outDark, 255)))
    nvgFill(nvg)

    -- 衣领细节：西装白衬衫+领带 / 皮衣拉链V领 / 运动大金链 / 礼服高光
    if av.outfit == "suit" then
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, cx - r * 0.16, shY - r * 0.10)
        nvgLineTo(nvg, cx, cy + r * 0.76)
        nvgLineTo(nvg, cx + r * 0.16, shY - r * 0.10)
        nvgClosePath(nvg)
        nvgFillColor(nvg, Col(C.white, 240))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, cx - r * 0.06, shY)
        nvgLineTo(nvg, cx + r * 0.06, shY)
        nvgLineTo(nvg, cx, cy + r * 0.72)
        nvgClosePath(nvg)
        nvgFillColor(nvg, Col(C.red, 240))
        nvgFill(nvg)
    elseif av.outfit == "leather" then
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, cx - r * 0.20, shY - r * 0.08)
        nvgLineTo(nvg, cx, cy + r * 0.72)
        nvgLineTo(nvg, cx + r * 0.20, shY - r * 0.08)
        nvgStrokeColor(nvg, Col({ 180, 194, 214 }, 230))
        nvgStrokeWidth(nvg, max(1.2, r * 0.05))
        nvgStroke(nvg)
    elseif av.outfit == "jersey" or av.outfit == "glam" then
        nvgBeginPath(nvg)
        nvgArc(nvg, cx, shY - r * 0.04, r * 0.22, 0.15, pi - 0.15, NVG_CW)
        nvgStrokeColor(nvg, Col(C.gold, 250))
        nvgStrokeWidth(nvg, max(1.6, r * 0.08))
        nvgStroke(nvg)
    elseif av.outfit == "royal" then
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, cx - r * 0.18, shY - r * 0.06)
        nvgLineTo(nvg, cx + r * 0.18, shY - r * 0.06)
        nvgStrokeColor(nvg, Col(C.gold, 255))
        nvgStrokeWidth(nvg, max(1.8, r * 0.09))
        nvgStroke(nvg)
    end

    -- 4. 颈部
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, cx - r * 0.13, cy + r * 0.16, r * 0.26, r * 0.30, r * 0.06)
    nvgFillColor(nvg, Col(skinDark, 255))
    nvgFill(nvg)

    -- 5. 长发后层
    local hCy = cy - r * 0.09
    local hRx = r * ((av.head == "round") and 0.42 or ((av.head == "square") and 0.40 or 0.37))
    local hRy = r * ((av.head == "round") and 0.40 or ((av.head == "angular") and 0.45 or 0.43))

    if av.hair == "long" or av.hair == "bob" or av.hair == "wild" then
        local extY = (av.hair == "long") and (r * 0.56) or (r * 0.34)
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, cx - hRx * 1.24, hCy - hRy * 0.72, hRx * 2.48, hRy + extY, hRx * 0.85)
        nvgFillColor(nvg, Col(Darker(hairCol, 0.82), 255))
        nvgFill(nvg)
    end

    -- 6. 耳朵
    nvgBeginPath(nvg)
    nvgCircle(nvg, cx - hRx * 0.98, hCy + r * 0.04, r * 0.10)
    nvgCircle(nvg, cx + hRx * 0.98, hCy + r * 0.04, r * 0.10)
    nvgFillColor(nvg, Col(skinDark, 255))
    nvgFill(nvg)

    -- 7. 卡通脸型主体 + 腮红与漫画高光
    nvgBeginPath(nvg)
    if av.head == "square" then
        nvgRoundedRect(nvg, cx - hRx, hCy - hRy, hRx * 2, hRy * 2, r * 0.22)
    elseif av.head == "angular" then
        nvgMoveTo(nvg, cx, hCy - hRy)
        nvgBezierTo(nvg, cx + hRx * 1.08, hCy - hRy, cx + hRx * 1.05, hCy + hRy * 0.32, cx + hRx * 0.55, hCy + hRy * 0.88)
        nvgLineTo(nvg, cx, hCy + hRy * 1.02)
        nvgLineTo(nvg, cx - hRx * 0.55, hCy + hRy * 0.88)
        nvgBezierTo(nvg, cx - hRx * 1.05, hCy + hRy * 0.32, cx - hRx * 1.08, hCy - hRy, cx, hCy - hRy)
    else
        nvgEllipse(nvg, cx, hCy, hRx, hRy)
    end
    nvgFillPaint(nvg, nvgRadialGradient(nvg, cx - r * 0.12, hCy - r * 0.14, r * 0.08, hRy * 1.3,
        Col(skinCol, 255), Col(skinDark, 255)))
    nvgFill(nvg)
    nvgStrokeColor(nvg, Col(Darker(skinCol, 0.52), 220))
    nvgStrokeWidth(nvg, max(1.0, r * 0.045))
    nvgStroke(nvg)

    -- 俏皮漫画腮红
    nvgBeginPath(nvg)
    nvgEllipse(nvg, cx - hRx * 0.56, hCy + r * 0.12, r * 0.11, r * 0.06)
    nvgEllipse(nvg, cx + hRx * 0.56, hCy + r * 0.12, r * 0.11, r * 0.06)
    nvgFillColor(nvg, Col({ 255, 118, 132 }, shocked and 130 or 85))
    nvgFill(nvg)

    -- 8. 胡须（腮/山羊胡/八字胡/满脸银须）
    if av.beard == "full" or av.beard == "silver" then
        local bc = (av.beard == "silver") and { 222, 226, 232 } or Darker(hairCol, 0.88)
        nvgBeginPath(nvg)
        nvgArc(nvg, cx, hCy + r * 0.12, hRx * 0.94, 0.15, pi - 0.15, NVG_CW)
        nvgClosePath(nvg)
        nvgFillColor(nvg, Col(bc, 240))
        nvgFill(nvg)
    elseif av.beard == "goatee" then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, cx - r * 0.12, hCy + hRy * 0.55, r * 0.24, r * 0.20, r * 0.06)
        nvgFillColor(nvg, Col(Darker(hairCol, 0.85), 235))
        nvgFill(nvg)
    elseif av.beard == "stubble" then
        nvgBeginPath(nvg)
        nvgArc(nvg, cx, hCy + r * 0.16, hRx * 0.86, 0.25, pi - 0.25, NVG_CW)
        nvgStrokeColor(nvg, Col(Darker(hairCol, 0.75), 110))
        nvgStrokeWidth(nvg, max(2.0, r * 0.11))
        nvgStroke(nvg)
    elseif av.beard == "mustache" then
        nvgBeginPath(nvg)
        nvgEllipse(nvg, cx - r * 0.09, hCy + r * 0.16, r * 0.11, r * 0.045)
        nvgEllipse(nvg, cx + r * 0.09, hCy + r * 0.16, r * 0.11, r * 0.045)
        nvgFillColor(nvg, Col(hairCol, 245))
        nvgFill(nvg)
    end

    -- 9. 五官（夸张漫画眉眼 + 嘴巴）
    local eyeY = hCy - r * 0.02
    local eyeX = hRx * 0.42
    local ew = max(1.2, r * 0.05)

    -- 眉毛
    nvgBeginPath(nvg)
    if shocked then
        nvgMoveTo(nvg, cx - eyeX - r * 0.11, eyeY - r * 0.16)
        nvgLineTo(nvg, cx - eyeX + r * 0.08, eyeY - r * 0.22)
        nvgMoveTo(nvg, cx + eyeX - r * 0.08, eyeY - r * 0.22)
        nvgLineTo(nvg, cx + eyeX + r * 0.11, eyeY - r * 0.16)
    else
        nvgMoveTo(nvg, cx - eyeX - r * 0.10, eyeY - r * 0.14)
        nvgLineTo(nvg, cx - eyeX + r * 0.10, eyeY - r * 0.12)
        nvgMoveTo(nvg, cx + eyeX - r * 0.10, eyeY - r * 0.12)
        nvgLineTo(nvg, cx + eyeX + r * 0.10, eyeY - r * 0.14)
    end
    nvgStrokeColor(nvg, Col(Darker(hairCol, 0.65), 245))
    nvgStrokeWidth(nvg, ew)
    nvgStroke(nvg)

    -- 眼睛
    if shocked then
        nvgBeginPath(nvg)
        nvgCircle(nvg, cx - eyeX, eyeY, r * 0.105)
        nvgCircle(nvg, cx + eyeX, eyeY, r * 0.105)
        nvgFillColor(nvg, Col(C.white, 255))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgCircle(nvg, cx - eyeX, eyeY, r * 0.042)
        nvgCircle(nvg, cx + eyeX, eyeY, r * 0.042)
        nvgFillColor(nvg, Col(C.bgInset, 255))
        nvgFill(nvg)
    else
        nvgBeginPath(nvg)
        nvgCircle(nvg, cx - eyeX, eyeY, r * 0.068)
        nvgCircle(nvg, cx + eyeX, eyeY, r * 0.068)
        nvgFillColor(nvg, Col({ 22, 24, 34 }, 255))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgCircle(nvg, cx - eyeX - r * 0.02, eyeY - r * 0.02, r * 0.022)
        nvgCircle(nvg, cx + eyeX - r * 0.02, eyeY - r * 0.02, r * 0.022)
        nvgFillColor(nvg, Col(C.white, 240))
        nvgFill(nvg)
    end

    -- 鼻尖漫画线条
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, cx, eyeY + r * 0.04)
    nvgLineTo(nvg, cx + r * 0.04, hCy + r * 0.12)
    nvgLineTo(nvg, cx - r * 0.02, hCy + r * 0.13)
    nvgStrokeColor(nvg, Col(Darker(skinCol, 0.62), 210))
    nvgStrokeWidth(nvg, max(1.0, r * 0.036))
    nvgStroke(nvg)

    -- 嘴巴（震撼 O 形张嘴 vs 自信坏笑）
    local mouthY = hCy + hRy * 0.56
    nvgBeginPath(nvg)
    if shocked then
        nvgEllipse(nvg, cx, mouthY, r * 0.11, r * 0.13)
        nvgFillColor(nvg, Col({ 128, 28, 42 }, 255))
        nvgFill(nvg)
        nvgStrokeColor(nvg, Col(Darker(skinCol, 0.55), 240))
        nvgStrokeWidth(nvg, max(1.0, r * 0.04))
        nvgStroke(nvg)
    else
        nvgMoveTo(nvg, cx - r * 0.14, mouthY - r * 0.01)
        nvgQuadTo(nvg, cx, mouthY + r * 0.10, cx + r * 0.16, mouthY - r * 0.04)
        nvgStrokeColor(nvg, Col({ 122, 46, 48 }, 245))
        nvgStrokeWidth(nvg, max(1.2, r * 0.05))
        nvgStroke(nvg)
    end

    -- 10. 眼镜 / 墨镜 / VR 护目镜 / 电竞耳机
    if av.glasses == "shades" then
        local glW, glH = r * 0.30, r * 0.18
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, cx - eyeX - glW * 0.5, eyeY - glH * 0.5, glW, glH, r * 0.04)
        nvgRoundedRect(nvg, cx + eyeX - glW * 0.5, eyeY - glH * 0.5, glW, glH, r * 0.04)
        nvgFillColor(nvg, Col({ 14, 18, 30 }, 248))
        nvgFill(nvg)
        nvgStrokeColor(nvg, Col(C.gold, 240))
        nvgStrokeWidth(nvg, max(1.0, r * 0.045))
        nvgStroke(nvg)
        -- 霓虹斜反光
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, cx - eyeX - glW * 0.25, eyeY + glH * 0.25)
        nvgLineTo(nvg, cx - eyeX + glW * 0.2, eyeY - glH * 0.25)
        nvgMoveTo(nvg, cx + eyeX - glW * 0.25, eyeY + glH * 0.25)
        nvgLineTo(nvg, cx + eyeX + glW * 0.2, eyeY - glH * 0.25)
        nvgStrokeColor(nvg, Col(C.cyan, 210))
        nvgStrokeWidth(nvg, max(1.0, r * 0.04))
        nvgStroke(nvg)
    elseif av.glasses == "round" or av.glasses == "rimless" then
        nvgBeginPath(nvg)
        nvgCircle(nvg, cx - eyeX, eyeY, r * 0.135)
        nvgCircle(nvg, cx + eyeX, eyeY, r * 0.135)
        nvgMoveTo(nvg, cx - eyeX + r * 0.135, eyeY)
        nvgLineTo(nvg, cx + eyeX - r * 0.135, eyeY)
        nvgStrokeColor(nvg, Col(av.glasses == "round" and C.gold or C.cyan, 235))
        nvgStrokeWidth(nvg, max(1.0, r * 0.04))
        nvgStroke(nvg)
    elseif av.glasses == "vr" then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, cx - hRx * 0.86, eyeY - r * 0.12, hRx * 1.72, r * 0.24, r * 0.08)
        nvgFillPaint(nvg, nvgLinearGradient(nvg, cx - hRx, eyeY, cx + hRx, eyeY,
            Col(C.cyan, 240), Col(C.magenta, 240)))
        nvgFill(nvg)
        nvgStrokeColor(nvg, Col(C.white, 235))
        nvgStrokeWidth(nvg, max(1.0, r * 0.04))
        nvgStroke(nvg)
    elseif av.glasses == "headset" then
        nvgBeginPath(nvg)
        nvgArc(nvg, cx, hCy - r * 0.05, hRx * 1.06, pi, 0, NVG_CW)
        nvgStrokeColor(nvg, Col(C.magenta, 240))
        nvgStrokeWidth(nvg, max(1.6, r * 0.08))
        nvgStroke(nvg)
    end

    -- 11. 发型顶层 / 光头反光星芒
    if av.hair == "bald" then
        -- 标志性“锃亮光头”漫画十字星高光
        local sx, sy = cx - hRx * 0.36, hCy - hRy * 0.56
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, sx, sy - r * 0.12); nvgLineTo(nvg, sx, sy + r * 0.12)
        nvgMoveTo(nvg, sx - r * 0.12, sy); nvgLineTo(nvg, sx + r * 0.12, sy)
        nvgStrokeColor(nvg, Col(C.white, 245))
        nvgStrokeWidth(nvg, max(1.2, r * 0.045))
        nvgStroke(nvg)
    elseif av.hair == "curly" or av.hair == "wild" then
        nvgBeginPath(nvg)
        for i = -3, 3 do
            local bx = cx + i * hRx * 0.28
            local by = hCy - hRy * (0.88 - math.abs(i) * 0.06)
            nvgCircle(nvg, bx, by, r * 0.18)
        end
        nvgFillColor(nvg, Col(hairCol, 255))
        nvgFill(nvg)
    elseif av.hair == "cap" then
        nvgBeginPath(nvg)
        nvgArc(nvg, cx, hCy - hRy * 0.30, hRx * 1.02, pi, 0, NVG_CW)
        nvgClosePath(nvg)
        nvgFillColor(nvg, Col(hairCol, 255))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, cx - hRx * 0.2, hCy - hRy * 0.44, hRx * 1.25, r * 0.12, r * 0.04)
        nvgFillColor(nvg, Col(Darker(hairCol, 0.72), 255))
        nvgFill(nvg)
    elseif av.hair == "buzz" then
        nvgBeginPath(nvg)
        nvgArc(nvg, cx, hCy - r * 0.08, hRx * 0.96, pi + 0.25, -0.25, NVG_CW)
        nvgClosePath(nvg)
        nvgFillColor(nvg, Col(hairCol, 255))
        nvgFill(nvg)
    else -- swept / part / silver / long / bob 顶部廓形
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, cx - hRx * 1.02, hCy - r * 0.06)
        nvgBezierTo(nvg, cx - hRx * 1.05, hCy - hRy * 1.25, cx + hRx * 0.25, hCy - hRy * 1.38, cx + hRx * 1.02, hCy - hRy * 0.25)
        nvgQuadTo(nvg, cx + hRx * 0.38, hCy - hRy * 0.76, cx - hRx * 0.12, hCy - hRy * 0.52)
        nvgQuadTo(nvg, cx - hRx * 0.66, hCy - hRy * 0.68, cx - hRx * 1.02, hCy - r * 0.06)
        nvgClosePath(nvg)
        nvgFillPaint(nvg, nvgLinearGradient(nvg, cx, hCy - hRy * 1.25, cx, hCy - r * 0.1,
            Col(hairCol, 255), Col(Darker(hairCol, 0.75), 255)))
        nvgFill(nvg)
    end

    -- 12. 漫画冷汗滴（被反超吓到时）
    if shocked and r >= 22 then
        local dx, dy = cx + hRx * 0.78, hCy - hRy * 0.28
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, dx, dy - r * 0.12)
        nvgBezierTo(nvg, dx + r * 0.09, dy + r * 0.02, dx + r * 0.08, dy + r * 0.14, dx, dy + r * 0.14)
        nvgBezierTo(nvg, dx - r * 0.08, dy + r * 0.14, dx - r * 0.09, dy + r * 0.02, dx, dy - r * 0.12)
        nvgFillColor(nvg, Col(C.cyan, 250))
        nvgFill(nvg)
    end

    -- 13. 金属斜角外圆框（遮盖肩底接缝，强化圆章质感）
    nvgBeginPath(nvg)
    nvgCircle(nvg, cx, cy, r)
    nvgStrokeColor(nvg, Col(shocked and C.gold or tierCol, 245))
    nvgStrokeWidth(nvg, max(2.0, r * 0.10))
    nvgStroke(nvg)
    nvgBeginPath(nvg)
    nvgCircle(nvg, cx, cy, r * 0.94)
    nvgStrokeColor(nvg, Col(C.white, 115))
    nvgStrokeWidth(nvg, max(0.8, r * 0.03))
    nvgStroke(nvg)

    -- 14. 右下角迷你代表道具徽章
    if r >= 20 and av.prop then
        DrawPropBadge(nvg, av.prop, cx + r * 0.68, cy + r * 0.68, r * 0.34, tierCol)
    end

    -- 15. “已超越”红金倾斜印章
    if surpassed and r >= 22 then
        nvgSave(nvg)
        nvgTranslate(nvg, cx + r * 0.42, cy - r * 0.56)
        nvgRotate(nvg, -0.26)
        local bw, bh = r * 0.92, max(12, r * 0.36)
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, -bw * 0.5, -bh * 0.5, bw, bh, 3)
        nvgFillColor(nvg, Col({ 168, 22, 36 }, 235))
        nvgFill(nvg)
        nvgStrokeColor(nvg, Col(C.gold, 245))
        nvgStrokeWidth(nvg, 1.3)
        nvgStroke(nvg)
        nvgFontFace(nvg, "sans")
        nvgFontSize(nvg, max(8, bh * 0.62))
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, Col(C.gold, 255))
        nvgText(nvg, 0, 0.5, "已超越")
        nvgRestore(nvg)
    end

    nvgRestore(nvg)
end

return AvatarArt
