-- ============================================================================
-- Art.lua  2.5D 立体霓虹硬币 + 程序化 NanoVG 图标 + 可选贴图热替换缓存
--   · 当 Skin.SPRITES[key] 存在对应 PNG 时优先用 nvgImagePattern 绘制贴图
--   · 否则绘制高质感 2.5D 金属币 / 霓虹图标，零外部素材依赖
-- ============================================================================

local Config = require("game/Config")
local Skin = require("game/Skin")

local C = Skin.C
local Col = Skin.Col
local floor, min, max, sin, cos, pi = math.floor, math.min, math.max, math.sin, math.cos, math.pi

local Art = {}

-- NanoVG 图片句柄缓存（path -> handle 或 false）
local imgCache = {}

function Art.DrawSprite(nvg, key, x, y, w, h, alpha)
    local path = Skin.SPRITES[key]
    if not path then return false end
    local hnd = imgCache[path]
    if hnd == nil then
        hnd = nvgCreateImage(nvg, path, 0) or 0
        imgCache[path] = hnd
    end
    if not hnd or hnd <= 0 then return false end
    nvgBeginPath(nvg)
    nvgRect(nvg, x, y, w, h)
    nvgFillPaint(nvg, nvgImagePattern(nvg, x, y, w, h, 0, hnd, alpha or 1.0))
    nvgFill(nvg)
    return true
end

--- 绘制 2.5D 立体金属硬币（cx, cy, r, kind, level, squashY, rot, frost, fuseT）
function Art.DrawCoin(nvg, kind, cx, cy, r, level, squashY, rot, frost, fuseT, isRain)
    local spriteKey = "coin_" .. tostring(kind)
    local sq = squashY or 0.86
    local ry = r * sq
    local thick = max(2.2, r * 0.24)

    -- 如果用户提供了硬币贴图，直接用贴图绘制（带投影、冰冻、引爆闪烁与升星角标）
    if Skin.SPRITES[spriteKey] then
        local dw = r * 2.20
        local dh = r * 2.20 * (0.94 + (sq - 0.86) * 0.35)
        nvgBeginPath(nvg)
        nvgEllipse(nvg, cx + 1.5, cy + thick + 2, r * 0.96, ry * 0.94)
        nvgFillColor(nvg, Col(C.shadow, 125))
        nvgFill(nvg)
        if Art.DrawSprite(nvg, spriteKey, cx - dw * 0.5, cy - dh * 0.5, dw, dh, 1.0) then
            if frost then
                nvgBeginPath(nvg)
                nvgEllipse(nvg, cx, cy, r * 1.04, ry * 1.04)
                nvgStrokeColor(nvg, Col(C.cyan, 235))
                nvgStrokeWidth(nvg, 2.0)
                nvgStroke(nvg)
            end
            if fuseT and fuseT > 0 and fuseT < 1.3 then
                nvgBeginPath(nvg)
                nvgCircle(nvg, cx, cy, r * 1.18)
                nvgStrokeColor(nvg, Col(C.gold, 210))
                nvgStrokeWidth(nvg, 2.0)
                nvgStroke(nvg)
            end
            if level and level > 1 then
                for s = 1, level do
                    local sx = cx + (s - (level + 1) * 0.5) * 5.2
                    local sy = cy - dh * 0.5 + 2
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, sx, sy, 2.4)
                    nvgFillColor(nvg, Col(C.gold, 255))
                    nvgFill(nvg)
                end
            end
            return
        end
    end

    local def = Config.COINS[kind] or Config.COINS.gold
    local pal = def.color

    -- 1. 投射阴影
    nvgBeginPath(nvg)
    nvgEllipse(nvg, cx + 1.5, cy + thick + 2.2, r * 0.98, ry * 0.92)
    nvgFillColor(nvg, Col(C.shadow, 120))
    nvgFill(nvg)

    -- 2. 金属厚度侧壁（假 3D 圆柱底缘）
    nvgBeginPath(nvg)
    nvgEllipse(nvg, cx, cy + thick, r, ry)
    nvgFillColor(nvg, Col(pal.dark, 255))
    nvgFill(nvg)

    -- 3. 硬币正面底盘
    nvgBeginPath(nvg)
    nvgEllipse(nvg, cx, cy, r, ry)
    nvgFillPaint(nvg, nvgLinearGradient(nvg, cx - r * 0.6, cy - ry, cx + r * 0.6, cy + ry,
        Col(pal.light, 255), Col(pal.base, 255)))
    nvgFill(nvg)

    -- 4. 压印内环
    nvgBeginPath(nvg)
    nvgEllipse(nvg, cx, cy, r * 0.76, ry * 0.76)
    nvgStrokeColor(nvg, Col(pal.dark, 180))
    nvgStrokeWidth(nvg, max(1.0, r * 0.08))
    nvgStroke(nvg)

    -- 5. 高光外圈
    nvgBeginPath(nvg)
    nvgEllipse(nvg, cx, cy, r * 0.95, ry * 0.95)
    nvgStrokeColor(nvg, Col(frost and C.cyan or pal.rim, 235))
    nvgStrokeWidth(nvg, frost and 2.2 or 1.3)
    nvgStroke(nvg)

    -- 6. 中心纹章符号
    local sym = def.symbol or "yen"
    local sr = r * 0.42
    nvgBeginPath(nvg)
    if sym == "bolt" then
        nvgMoveTo(nvg, cx + sr * 0.15, cy - sr)
        nvgLineTo(nvg, cx - sr * 0.45, cy + sr * 0.08)
        nvgLineTo(nvg, cx + sr * 0.05, cy + sr * 0.08)
        nvgLineTo(nvg, cx - sr * 0.15, cy + sr)
        nvgLineTo(nvg, cx + sr * 0.48, cy - sr * 0.08)
        nvgLineTo(nvg, cx - sr * 0.05, cy - sr * 0.08)
        nvgClosePath(nvg)
        nvgFillColor(nvg, Col(C.white, 240))
        nvgFill(nvg)
    elseif sym == "bomb" or sym == "flame" then
        nvgCircle(nvg, cx, cy + sr * 0.1, sr * 0.62)
        nvgFillColor(nvg, Col(pal.dark, 240))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgCircle(nvg, cx + sr * 0.35, cy - sr * 0.6, sr * 0.28)
        nvgFillColor(nvg, Col((fuseT and fuseT > 0 and fuseT < 1.3) and C.white or C.gold, 245))
        nvgFill(nvg)
    elseif sym == "split" then
        nvgCircle(nvg, cx - sr * 0.42, cy, sr * 0.34)
        nvgCircle(nvg, cx + sr * 0.42, cy, sr * 0.34)
        nvgFillColor(nvg, Col(pal.dark, 220))
        nvgFill(nvg)
    elseif sym == "star" or sym == "crown" then
        for i = 0, 9 do
            local a = -pi / 2 + i * pi / 5
            local rr = (i % 2 == 0) and sr * 0.95 or sr * 0.42
            local px, py = cx + cos(a) * rr, cy + sin(a) * rr * sq
            if i == 0 then nvgMoveTo(nvg, px, py) else nvgLineTo(nvg, px, py) end
        end
        nvgClosePath(nvg)
        nvgFillColor(nvg, Col(C.white, 235))
        nvgFill(nvg)
    elseif sym == "gem" then
        nvgMoveTo(nvg, cx, cy - sr * 0.85)
        nvgLineTo(nvg, cx + sr * 0.72, cy)
        nvgLineTo(nvg, cx, cy + sr * 0.85)
        nvgLineTo(nvg, cx - sr * 0.72, cy)
        nvgClosePath(nvg)
        nvgFillColor(nvg, Col(C.white, 220))
        nvgFill(nvg)
    elseif sym == "clover" then
        nvgCircle(nvg, cx, cy - sr * 0.32, sr * 0.34)
        nvgCircle(nvg, cx - sr * 0.32, cy + sr * 0.24, sr * 0.34)
        nvgCircle(nvg, cx + sr * 0.32, cy + sr * 0.24, sr * 0.34)
        nvgFillColor(nvg, Col(pal.dark, 210))
        nvgFill(nvg)
    elseif sym == "vortex" then
        nvgCircle(nvg, cx, cy, sr * 0.48)
        nvgFillColor(nvg, Col(C.shadow, 240))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgCircle(nvg, cx, cy, sr * 0.78)
        nvgStrokeColor(nvg, Col(C.cyan, 210))
        nvgStrokeWidth(nvg, 1.4)
        nvgStroke(nvg)
    else
        -- 经典竖条 / 方孔 / 777
        nvgRect(nvg, cx - sr * 0.16, cy - sr * 0.7, sr * 0.32, sr * 1.4)
        nvgFillColor(nvg, Col(pal.dark, 185))
        nvgFill(nvg)
    end

    -- 7. 左上角镜面反光点
    nvgBeginPath(nvg)
    nvgEllipse(nvg, cx - r * 0.36, cy - ry * 0.38, r * 0.22, ry * 0.14)
    nvgFillColor(nvg, Col(C.white, isRain and 245 or 190))
    nvgFill(nvg)

    -- 8. 升星角标点 (Lv2 / Lv3)
    if level and level > 1 then
        for s = 1, level do
            local sx = cx + (s - (level + 1) * 0.5) * 5.2
            local sy = cy - ry + 2
            nvgBeginPath(nvg)
            nvgCircle(nvg, sx, sy, 2.2)
            nvgFillColor(nvg, Col(C.white, 255))
            nvgFill(nvg)
        end
    end
end

local ICON_INK = { 6, 6, 18 }

--- 绘制程序化通用图标：贴纸式下投影 + 主体（投影用同形状暗色版，增强小尺寸可读性与立体感）
function Art.DrawIcon(nvg, key, x, y, size, tint)
    if key ~= "coin" and size >= 14 then
        local off = max(1, size * 0.06)
        Art.DrawIconFlat(nvg, key, x + off * 0.4, y + off, size, ICON_INK)
    end
    Art.DrawIconFlat(nvg, key, x, y, size, tint)
end

--- 单色扁平图标本体
function Art.DrawIconFlat(nvg, key, x, y, size, tint)
    local cx, cy = x + size * 0.5, y + size * 0.5
    local r = size * 0.42
    local col = tint

    if key == "coin" then
        Art.DrawCoin(nvg, "gold", cx, cy - 1, r * 0.92, 1, 0.9, 0, false, -1, false)
        return
    elseif key == "heart" then
        local c = col or C.red
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, cx, cy + r * 0.8)
        nvgQuadTo(nvg, cx - r * 1.15, cy + r * 0.1, cx - r * 0.92, cy - r * 0.38)
        nvgQuadTo(nvg, cx - r * 0.62, cy - r * 0.92, cx, cy - r * 0.32)
        nvgQuadTo(nvg, cx + r * 0.62, cy - r * 0.92, cx + r * 0.92, cy - r * 0.38)
        nvgQuadTo(nvg, cx + r * 1.15, cy + r * 0.1, cx, cy + r * 0.8)
        nvgClosePath(nvg)
        nvgFillColor(nvg, Col(c, 255))
        nvgFill(nvg)
        nvgStrokeColor(nvg, Col(C.white, 170))
        nvgStrokeWidth(nvg, 1.2)
        nvgStroke(nvg)
        return
    elseif key == "bolt" or key == "power" then
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, cx + r * 0.15, cy - r)
        nvgLineTo(nvg, cx - r * 0.55, cy + r * 0.1)
        nvgLineTo(nvg, cx + r * 0.05, cy + r * 0.1)
        nvgLineTo(nvg, cx - r * 0.15, cy + r)
        nvgLineTo(nvg, cx + r * 0.55, cy - r * 0.1)
        nvgLineTo(nvg, cx - r * 0.05, cy - r * 0.1)
        nvgClosePath(nvg)
        nvgFillColor(nvg, Col(col or C.cyan, 255))
        nvgFill(nvg)
        return
    elseif key == "star" or key == "crit" then
        nvgBeginPath(nvg)
        for i = 0, 9 do
            local a = -pi / 2 + i * pi / 5
            local rr = (i % 2 == 0) and r or r * 0.44
            local px, py = cx + cos(a) * rr, cy + sin(a) * rr
            if i == 0 then nvgMoveTo(nvg, px, py) else nvgLineTo(nvg, px, py) end
        end
        nvgClosePath(nvg)
        nvgFillColor(nvg, Col(col or C.gold, 255))
        nvgFill(nvg)
        return
    elseif key == "gear" then
        local c = col or C.muted
        for i = 0, 7 do
            local a = i * pi / 4
            nvgBeginPath(nvg)
            nvgCircle(nvg, cx + cos(a) * r * 0.72, cy + sin(a) * r * 0.72, r * 0.22)
            nvgFillColor(nvg, Col(c, 255))
            nvgFill(nvg)
        end
        nvgBeginPath(nvg)
        nvgCircle(nvg, cx, cy, r * 0.68)
        nvgFillColor(nvg, Col(c, 255))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgCircle(nvg, cx, cy, r * 0.28)
        nvgFillColor(nvg, Col(C.bgInset, 255))
        nvgFill(nvg)
        return
    elseif key == "shield" then
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, cx, cy - r * 0.92)
        nvgLineTo(nvg, cx + r * 0.85, cy - r * 0.55)
        nvgLineTo(nvg, cx + r * 0.65, cy + r * 0.35)
        nvgLineTo(nvg, cx, cy + r * 0.95)
        nvgLineTo(nvg, cx - r * 0.65, cy + r * 0.35)
        nvgLineTo(nvg, cx - r * 0.85, cy - r * 0.55)
        nvgClosePath(nvg)
        nvgFillColor(nvg, Col(col or C.cyan, 255))
        nvgFill(nvg)
        nvgStrokeColor(nvg, Col(C.white, 200))
        nvgStrokeWidth(nvg, 1.3)
        nvgStroke(nvg)
        return
    elseif key == "crown" then
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, cx - r * 0.85, cy + r * 0.55)
        nvgLineTo(nvg, cx - r * 0.85, cy - r * 0.35)
        nvgLineTo(nvg, cx - r * 0.35, cy + r * 0.05)
        nvgLineTo(nvg, cx, cy - r * 0.7)
        nvgLineTo(nvg, cx + r * 0.35, cy + r * 0.05)
        nvgLineTo(nvg, cx + r * 0.85, cy - r * 0.35)
        nvgLineTo(nvg, cx + r * 0.85, cy + r * 0.55)
        nvgClosePath(nvg)
        nvgFillColor(nvg, Col(col or C.gold, 255))
        nvgFill(nvg)
        return
    elseif key == "flame" or key == "bomb" then
        nvgBeginPath(nvg)
        nvgCircle(nvg, cx, cy + r * 0.18, r * 0.68)
        nvgFillColor(nvg, Col(col or C.magenta, 255))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, cx - r * 0.45, cy)
        nvgLineTo(nvg, cx, cy - r * 0.95)
        nvgLineTo(nvg, cx + r * 0.45, cy)
        nvgClosePath(nvg)
        nvgFillColor(nvg, Col(C.gold, 240))
        nvgFill(nvg)
        return
    elseif key == "lock" then
        local c = col or C.muted
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, cx - r * 0.65, cy - r * 0.1, r * 1.3, r * 0.95, 3)
        nvgFillColor(nvg, Col(c, 255))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgArc(nvg, cx, cy - r * 0.1, r * 0.42, pi, 0, NVG_CW)
        nvgStrokeColor(nvg, Col(c, 255))
        nvgStrokeWidth(nvg, 2.2)
        nvgStroke(nvg)
        return
    elseif key == "magnet" then
        local c = col or C.purple
        nvgBeginPath(nvg)
        nvgArc(nvg, cx, cy - r * 0.1, r * 0.62, 0, pi, NVG_CW)
        nvgStrokeColor(nvg, Col(c, 255))
        nvgStrokeWidth(nvg, r * 0.42)
        nvgStroke(nvg)
        nvgBeginPath(nvg)
        nvgRect(nvg, cx - r * 0.82, cy - r * 0.65, r * 0.42, r * 0.58)
        nvgRect(nvg, cx + r * 0.4, cy - r * 0.65, r * 0.42, r * 0.58)
        nvgFillColor(nvg, Col(C.white, 240))
        nvgFill(nvg)
        return
    elseif key == "book" or key == "bag" or key == "chest" then
        local c = col or C.gold
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, cx - r * 0.82, cy - r * 0.65, r * 1.64, r * 1.35, 3)
        nvgFillColor(nvg, Col(c, 255))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgRect(nvg, cx - r * 0.82, cy - r * 0.1, r * 1.64, r * 0.22)
        nvgFillColor(nvg, Col(C.bgInset, 220))
        nvgFill(nvg)
        return
    elseif key == "skull" then
        local c = col or C.red
        nvgBeginPath(nvg)
        nvgCircle(nvg, cx, cy - r * 0.1, r * 0.72)
        nvgRect(nvg, cx - r * 0.42, cy + r * 0.3, r * 0.84, r * 0.48)
        nvgFillColor(nvg, Col(c, 255))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgCircle(nvg, cx - r * 0.26, cy - r * 0.1, r * 0.18)
        nvgCircle(nvg, cx + r * 0.26, cy - r * 0.1, r * 0.18)
        nvgFillColor(nvg, Col(C.bgInset, 255))
        nvgFill(nvg)
        return
    elseif key == "play" then
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, cx - r * 0.55, cy - r * 0.75)
        nvgLineTo(nvg, cx + r * 0.85, cy)
        nvgLineTo(nvg, cx - r * 0.55, cy + r * 0.75)
        nvgClosePath(nvg)
        nvgFillColor(nvg, Col(col or C.white, 255))
        nvgFill(nvg)
        return
    else
        -- 默认菱形霓虹徽章（clover / split / spring / gate / quest）
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, cx, cy - r * 0.9)
        nvgLineTo(nvg, cx + r * 0.9, cy)
        nvgLineTo(nvg, cx, cy + r * 0.9)
        nvgLineTo(nvg, cx - r * 0.9, cy)
        nvgClosePath(nvg)
        nvgFillColor(nvg, Col(col or C.green, 255))
        nvgFill(nvg)
    end
end

return Art
