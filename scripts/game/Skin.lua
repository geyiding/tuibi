-- ============================================================================
-- Skin.lua  霓虹街机皮肤系统 + 贴图热替换映射表
--   · 现阶段全部程序化绘制，开箱即玩且高对比高饱和
--   · 后期更换成品贴图：将 PNG 放入 assets/image/... 对应路径（自动探测）
--     或在 Skin.TEXTURES / Skin.SPRITES 显式填入路径与九宫格切片即可零代码热替换
-- ============================================================================

local floor = math.floor

local Skin = {}

-- ----------------------------------------------------------------------------
-- 贴图热替换配置表（后期生成素材后可在此覆盖，或直接放进 AUTO_SPRITES 对应路径）
--   TEXTURES[style] = { image = "image/ui/panel.png", slice = { 12, 12, 12, 12 } }
--   SPRITES[key]    = "image/coins/coin_gold.png"
-- ----------------------------------------------------------------------------
Skin.TEXTURES = {}
Skin.SPRITES = {}

local IMG_PREFIX = "image/"
Skin.AUTO_SPRITES = {
    backdrop_act1   = IMG_PREFIX .. "machine/backdrop_act1.png",
    backdrop_act2   = IMG_PREFIX .. "machine/backdrop_act2.png",
    backdrop_act3   = IMG_PREFIX .. "machine/backdrop_act3.png",
    pusher_bar      = IMG_PREFIX .. "machine/pusher_bar.png",
    gate_badge      = IMG_PREFIX .. "machine/gate_badge.png",
    boss_gatekeeper = IMG_PREFIX .. "boss/boss_gatekeeper.png",
    boss_furnace    = IMG_PREFIX .. "boss/boss_furnace.png",
    boss_vaultbeast = IMG_PREFIX .. "boss/boss_vaultbeast.png",
}

local UI_SLICES = {
    panel          = { 24, 24, 24, 24 },
    card           = { 16, 16, 16, 16 },
    slot           = { 12, 12, 12, 12 },
    plate          = { 10, 16, 12, 16 },
    cloth          = { 12, 16, 10, 16 },
    banner         = { 14, 34, 16, 34 },
    button         = { 14, 18, 16, 18 },
    button_primary = { 14, 18, 16, 18 },
    button_cyan    = { 14, 18, 16, 18 },
    button_magenta = { 14, 18, 16, 18 },
    button_green   = { 14, 18, 16, 18 },
    button_danger  = { 14, 18, 16, 18 },
    button_dark    = { 14, 18, 16, 18 },
}

local function HasAsset(path)
    if not cache then return false end
    if cache.Exists and cache:Exists(path) then return true end
    if cache.GetResInfo and cache:GetResInfo(path) ~= nil then return true end
    return false
end

--- 自动检测可选贴图是否存在（存在才注册，零报错日志）
function Skin.ProbeAutoAssets()
    if not cache then return end
    local texCount, sprCount = 0, 0
    for k, path in pairs(Skin.AUTO_SPRITES) do
        if not Skin.SPRITES[k] and HasAsset(path) then
            Skin.SPRITES[k] = path
        end
    end
    for k, slice in pairs(UI_SLICES) do
        local p = IMG_PREFIX .. "ui/" .. k .. ".png"
        if not Skin.TEXTURES[k] and HasAsset(p) then
            Skin.TEXTURES[k] = { image = p, slice = slice }
        end
    end
    local Config = require("game/Config")
    for id in pairs(Config.COINS or {}) do
        local p = IMG_PREFIX .. "coins/coin_" .. id .. ".png"
        if not Skin.SPRITES["coin_" .. id] and HasAsset(p) then
            Skin.SPRITES["coin_" .. id] = p
        end
    end
    for id in pairs(Config.RELICS or {}) do
        local p = IMG_PREFIX .. "relics/relic_" .. id .. ".png"
        if not Skin.SPRITES["relic_" .. id] and HasAsset(p) then
            Skin.SPRITES["relic_" .. id] = p
        end
    end
    for id in pairs(Config.EVENTS or {}) do
        local p = IMG_PREFIX .. "events/event_" .. id .. ".png"
        if not Skin.SPRITES["event_" .. id] and HasAsset(p) then
            Skin.SPRITES["event_" .. id] = p
        end
    end
    for _ in pairs(Skin.TEXTURES) do texCount = texCount + 1 end
    for _ in pairs(Skin.SPRITES) do sprCount = sprCount + 1 end
    print(string.format("[Skin] loaded %d UI textures, %d sprites", texCount, sprCount))
end

-- ----------------------------------------------------------------------------
-- 霓虹街机调色板
-- ----------------------------------------------------------------------------
local C = {
    bgDeep    = { 10, 12, 26 },
    bgPanel   = { 20, 24, 48 },
    bgCard    = { 28, 34, 66 },
    bgInset   = { 14, 16, 34 },
    border    = { 72, 92, 154 },
    cyan      = { 56, 224, 255 },
    cyanDark  = { 18, 92, 134 },
    magenta   = { 255, 72, 178 },
    magDark   = { 126, 22, 86 },
    gold      = { 255, 210, 64 },
    goldDark  = { 168, 102, 16 },
    purple    = { 166, 114, 255 },
    purpDark  = { 74, 42, 138 },
    green     = { 74, 232, 142 },
    greenDark = { 24, 114, 68 },
    red       = { 255, 82, 96 },
    redDark   = { 138, 28, 42 },
    white     = { 244, 248, 255 },
    muted     = { 146, 162, 198 },
    shadow    = { 4, 5, 14 },
}
Skin.C = C

local function A(t, a) return { t[1], t[2], t[3], a or 255 } end
Skin.RGBA = A

Skin.UI = {
    bgDeep      = A(C.bgDeep),
    bgPanel     = A(C.bgPanel, 242),
    bgCard      = A(C.bgCard, 245),
    bgInset     = A(C.bgInset, 235),
    border      = A(C.border, 220),
    cyan        = A(C.cyan),
    magenta     = A(C.magenta),
    gold        = A(C.gold),
    purple      = A(C.purple),
    green       = A(C.green),
    red         = A(C.red),
    text        = A(C.white),
    textDim     = A(C.muted),
    overlay     = A({ 6, 8, 18 }, 120),   -- 半透明微暗遮罩 (~47%)，保留下层机台清晰可见
    strokeDark  = "#090B16",
}

Skin.RARITY = {
    common    = { name = "普通", col = C.cyan,   dark = C.cyanDark,  bg = { 24, 34, 64 } },
    rare      = { name = "进阶", col = C.purple, dark = C.purpDark,  bg = { 42, 28, 76 } },
    epic      = { name = "史诗", col = C.magenta,dark = C.magDark,   bg = { 56, 22, 62 } },
    legendary = { name = "传说", col = C.gold,   dark = C.goldDark,  bg = { 62, 44, 18 } },
}

--- 量化 alpha 的 NanoVG 颜色缓存（避免每帧分配 NVGcolor）
function Skin.Col(t, a)
    a = a or 255
    if a < 0 then a = 0 elseif a > 255 then a = 255 end
    local q = floor(a / 17 + 0.5)
    local cacheTbl = t._nvg
    if not cacheTbl then cacheTbl = {}; t._nvg = cacheTbl end
    local c = cacheTbl[q]
    if not c then
        c = nvgRGBA(t[1], t[2], t[3], q * 17)
        cacheTbl[q] = c
    end
    return c
end

local VARIANTS = {
    primary = { top = { 255, 212, 66 }, bot = { 232, 142, 24 }, rim = { 255, 244, 178 }, edge = { 138, 74, 10 } },
    cyan    = { top = { 72, 232, 255 }, bot = { 24, 152, 220 }, rim = { 190, 248, 255 }, edge = { 14, 78, 128 } },
    magenta = { top = { 255, 92, 186 }, bot = { 196, 36, 128 }, rim = { 255, 194, 232 }, edge = { 104, 14, 68 } },
    green   = { top = { 92, 238, 150 }, bot = { 34, 168, 92 },  rim = { 196, 255, 220 }, edge = { 18, 92, 50 } },
    danger  = { top = { 255, 98, 108 }, bot = { 192, 42, 56 },  rim = { 255, 196, 202 }, edge = { 102, 16, 28 } },
    dark    = { top = { 44, 54, 98 },   bot = { 24, 30, 62 },   rim = { 104, 126, 196 }, edge = { 12, 16, 36 } },
}

--- 绘制霓虹街机样式面板/按钮/卡牌
function Skin.Draw(nvg, styleName, x, y, w, h, opt)
    if w <= 0 or h <= 0 then return end
    opt = opt or {}

    if styleName == "button" then
        local v = VARIANTS[opt.variant or "primary"] or VARIANTS.primary
        local r = opt.radius or 12
        local yOff = opt.pressed and 2 or 0
        -- 底部立体厚边
        if not opt.pressed then
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, x, y + 4, w, h, r)
            nvgFillColor(nvg, Skin.Col(v.edge, 255))
            nvgFill(nvg)
        end
        -- 主体渐变
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x, y + yOff, w, h, r)
        nvgFillPaint(nvg, nvgLinearGradient(nvg, x, y + yOff, x, y + yOff + h, Skin.Col(v.top), Skin.Col(v.bot)))
        nvgFill(nvg)
        -- 顶部高光条
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x + 3, y + yOff + 2, w - 6, h * 0.36, math.max(2, r - 3))
        nvgFillColor(nvg, Skin.Col(C.white, opt.disabled and 25 or 55))
        nvgFill(nvg)
        -- 霓虹边框
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x + 1, y + yOff + 1, w - 2, h - 2, r - 1)
        nvgStrokeColor(nvg, Skin.Col(v.rim, opt.disabled and 100 or 230))
        nvgStrokeWidth(nvg, 1.5)
        nvgStroke(nvg)

    elseif styleName == "card" or styleName == "slot" then
        local rar = Skin.RARITY[opt.rarity or "common"] or Skin.RARITY.common
        local r = opt.radius or 10
        local bgCol = opt.selected and { 54, 42, 92 } or rar.bg
        -- 投影
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x + 1, y + 3, w, h, r)
        nvgFillColor(nvg, Skin.Col(C.shadow, 130))
        nvgFill(nvg)
        -- 卡面
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x, y, w, h, r)
        nvgFillColor(nvg, Skin.Col(bgCol, 245))
        nvgFill(nvg)
        -- 边框（选中高亮金边）
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x + 1, y + 1, w - 2, h - 2, r - 1)
        nvgStrokeColor(nvg, Skin.Col(opt.selected and C.gold or rar.col, opt.selected and 255 or 190))
        nvgStrokeWidth(nvg, opt.selected and 2.5 or 1.6)
        nvgStroke(nvg)

    elseif styleName == "plate" then
        nvgBeginPath(nvg)
        nvgRect(nvg, x, y, w, h)
        nvgFillPaint(nvg, nvgLinearGradient(nvg, x, y, x, y + h, Skin.Col({ 24, 30, 60 }, 245), Skin.Col({ 12, 16, 36 }, 250)))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgRect(nvg, x, y + h - 2, w, 2)
        nvgFillColor(nvg, Skin.Col(C.cyan, 200))
        nvgFill(nvg)

    elseif styleName == "cloth" then
        nvgBeginPath(nvg)
        nvgRect(nvg, x, y, w, h)
        nvgFillPaint(nvg, nvgLinearGradient(nvg, x, y, x, y + h, Skin.Col({ 18, 24, 52 }, 248), Skin.Col({ 10, 12, 28 }, 252)))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgRect(nvg, x, y, w, 2)
        nvgFillColor(nvg, Skin.Col(C.magenta, 200))
        nvgFill(nvg)

    elseif styleName == "banner" then
        local r = 10
        local col = (opt.color == "gold" and C.gold) or (opt.color == "red" and C.red)
            or (opt.color == "green" and C.green) or C.cyan
        local dark = (opt.color == "gold" and C.goldDark) or (opt.color == "red" and C.redDark)
            or (opt.color == "green" and C.greenDark) or C.cyanDark
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x, y + 3, w, h, r)
        nvgFillColor(nvg, Skin.Col(dark, 255))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x, y, w, h, r)
        nvgFillColor(nvg, Skin.Col(col, 255))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x + 2, y + 2, w - 4, h - 4, r - 2)
        nvgStrokeColor(nvg, Skin.Col(C.white, 170))
        nvgStrokeWidth(nvg, 1.5)
        nvgStroke(nvg)

    else
        -- 默认弹窗/容器面板 "panel"
        local r = opt.radius or 14
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x, y + 4, w, h, r)
        nvgFillColor(nvg, Skin.Col(C.shadow, 160))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x, y, w, h, r)
        nvgFillPaint(nvg, nvgLinearGradient(nvg, x, y, x, y + h, Skin.Col(C.bgPanel, 250), Skin.Col(C.bgInset, 252)))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x + 1, y + 1, w - 2, h - 2, r - 1)
        nvgStrokeColor(nvg, Skin.Col(opt.borderColor or C.cyan, 210))
        nvgStrokeWidth(nvg, 2)
        nvgStroke(nvg)
    end
end

return Skin
