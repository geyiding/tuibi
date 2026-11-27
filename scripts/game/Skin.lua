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
Skin.USE_UI_TEXTURES = false
Skin.AUTO_SPRITES = {
    backdrop_act1   = IMG_PREFIX .. "machine/backdrop_act1.png",
    backdrop_act2   = IMG_PREFIX .. "machine/backdrop_act2.png",
    backdrop_act3   = IMG_PREFIX .. "machine/backdrop_act3.png",
    pusher_bar      = IMG_PREFIX .. "machine/pusher_bar.png",
    gate_badge      = IMG_PREFIX .. "machine/gate_badge.png",
    boss_gatekeeper = IMG_PREFIX .. "boss/boss_gatekeeper.png",
    boss_furnace    = IMG_PREFIX .. "boss/boss_furnace.png",
    boss_vaultbeast = IMG_PREFIX .. "boss/boss_vaultbeast.png",
    -- 九宫格幸运盘符号（1 金币 / 2 四叶草 / 3 闪电 / 4 红宝石 / 5 皇冠 / 6 星钻 / 7 JP 宝箱）+ 格子底板
    slot_sym_1      = IMG_PREFIX .. "slot/sym_1.png",
    slot_sym_2      = IMG_PREFIX .. "slot/sym_2.png",
    slot_sym_3      = IMG_PREFIX .. "slot/sym_3.png",
    slot_sym_4      = IMG_PREFIX .. "slot/sym_4.png",
    slot_sym_5      = IMG_PREFIX .. "slot/sym_5.png",
    slot_sym_6      = IMG_PREFIX .. "slot/sym_6.png",
    slot_sym_7      = IMG_PREFIX .. "slot/sym_7.png",
    slot_cell       = IMG_PREFIX .. "slot/cell.png",
    slot_center     = IMG_PREFIX .. "slot/cell_center.png",
    -- JP CHANCE 跑灯抽奖格
    jp_tile_mini    = IMG_PREFIX .. "jp/tile_mini.png",
    jp_tile_major   = IMG_PREFIX .. "jp/tile_major.png",
    jp_tile_grand   = IMG_PREFIX .. "jp/tile_grand.png",
    jp_tile_next    = IMG_PREFIX .. "jp/tile_next.png",
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
    -- UI 框体改为程序化“科技灯光线条”风格（Skin.Draw），不再挂载糖果色九宫格贴图；
    -- 如需恢复贴图框体，把 Skin.USE_UI_TEXTURES 设为 true
    if Skin.USE_UI_TEXTURES then
        for k, slice in pairs(UI_SLICES) do
            local p = IMG_PREFIX .. "ui/" .. k .. ".png"
            if not Skin.TEXTURES[k] and HasAsset(p) then
                Skin.TEXTURES[k] = { image = p, slice = slice }
            end
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
    if type(t) ~= "table" then t = C.white end
    a = a or 255
    if a < 0 then a = 0 elseif a > 255 then a = 255 end
    local q = floor(a / 17 + 0.5)
    local cacheTbl = t._nvg
    if not cacheTbl then cacheTbl = {}; t._nvg = cacheTbl end
    local c = cacheTbl[q]
    if not c then
        c = nvgRGBA(t[1] or 255, t[2] or 255, t[3] or 255, q * 17)
        cacheTbl[q] = c
    end
    return c
end

-- ----------------------------------------------------------------------------
-- 科技灯光线条风格（深色玻璃 + 切角 + 细光线描边 + 底部光条）
-- ----------------------------------------------------------------------------
-- 按钮主色：line = 光线色，tint = 玻璃底色染色，glow = 外发光
local VARIANTS = {
    primary = { line = { 255, 204, 72 },  tint = { 120, 84, 16 },  glow = { 255, 190, 60 } },
    cyan    = { line = { 80, 220, 255 },  tint = { 18, 86, 120 },  glow = { 60, 200, 255 } },
    magenta = { line = { 255, 96, 196 },  tint = { 110, 24, 84 },  glow = { 255, 80, 190 } },
    green   = { line = { 96, 240, 160 },  tint = { 20, 96, 60 },   glow = { 80, 230, 150 } },
    danger  = { line = { 255, 100, 110 }, tint = { 110, 24, 34 },  glow = { 255, 80, 90 } },
    dark    = { line = { 110, 150, 210 }, tint = { 26, 34, 56 },   glow = { 90, 140, 220 } },
}
Skin.VARIANTS = VARIANTS

local GLASS_TOP = { 22, 28, 46 }
local GLASS_BOT = { 10, 13, 24 }
local PANEL_TOP = { 17, 21, 36 }
local PANEL_BOT = { 8, 10, 19 }
local PANEL_LINE = { 70, 190, 255 }
local PANEL_TICK = { 150, 235, 255 }
local CARD_TOP = { 22, 27, 44 }
local CARD_BOT = { 13, 16, 28 }
local CARD_LINE = { 46, 58, 90 }
local SEL_GOLD = { 255, 206, 80 }
local WHITE = C.white

local function Additive(nvg, on)
    if type(nvgGlobalCompositeOperation) == "function" and NVG_LIGHTER ~= nil then
        nvgGlobalCompositeOperation(nvg, on and NVG_LIGHTER or (NVG_SOURCE_OVER or 0))
    end
end

--- 切角矩形路径（左上 / 右下切角，科技面板常用造型）
local function TechPath(nvg, x, y, w, h, c)
    c = math.min(c, w * 0.3, h * 0.45)
    nvgMoveTo(nvg, x + c, y)
    nvgLineTo(nvg, x + w, y)
    nvgLineTo(nvg, x + w, y + h - c)
    nvgLineTo(nvg, x + w - c, y + h)
    nvgLineTo(nvg, x, y + h)
    nvgLineTo(nvg, x, y + c)
    nvgClosePath(nvg)
end
Skin.TechPath = TechPath

--- 中间亮、两端渐隐的光线（水平）
local function LightLine(nvg, x, y, w, th, col, a)
    local half = w * 0.5
    nvgBeginPath(nvg)
    nvgRect(nvg, x, y, half, th)
    nvgFillPaint(nvg, nvgLinearGradient(nvg, x, y, x + half, y, Skin.Col(col, 0), Skin.Col(col, a)))
    nvgFill(nvg)
    nvgBeginPath(nvg)
    nvgRect(nvg, x + half, y, half, th)
    nvgFillPaint(nvg, nvgLinearGradient(nvg, x + half, y, x + w, y, Skin.Col(col, a), Skin.Col(col, 0)))
    nvgFill(nvg)
end
Skin.LightLine = LightLine

--- 绘制科技风面板 / 按钮 / 卡片
function Skin.Draw(nvg, styleName, x, y, w, h, opt)
    if w <= 0 or h <= 0 then return end
    opt = opt or {}

    if styleName == "button" then
        local v = VARIANTS[opt.variant or "primary"] or VARIANTS.primary
        local isDark = (opt.variant == "dark")
        local acc = (isDark and opt.accent and VARIANTS[opt.accent]) or v
        local c = math.min(9, h * 0.28)
        local yOff = opt.pressed and 1.5 or 0
        local by = y + yOff
        -- 外发光（非暗色按钮）
        if not isDark and not opt.disabled then
            Additive(nvg, true)
            nvgBeginPath(nvg)
            nvgRect(nvg, x - 10, by - 8, w + 20, h + 16)
            nvgFillPaint(nvg, nvgBoxGradient(nvg, x, by, w, h, c, 12, Skin.Col(v.glow, opt.pressed and 90 or 60), Skin.Col(v.glow, 0)))
            nvgFill(nvg)
            Additive(nvg, false)
        end
        -- 玻璃底（主色染色）
        nvgBeginPath(nvg)
        TechPath(nvg, x, by, w, h, c)
        nvgFillPaint(nvg, nvgLinearGradient(nvg, x, by, x, by + h,
            Skin.Col(isDark and GLASS_TOP or v.tint, 250), Skin.Col(GLASS_BOT, 250)))
        nvgFill(nvg)
        -- 主色由下往上的光晕（让按钮“亮着”）
        if not isDark then
            nvgBeginPath(nvg)
            TechPath(nvg, x, by, w, h, c)
            nvgFillPaint(nvg, nvgLinearGradient(nvg, x, by + h, x, by + h * 0.35, Skin.Col(v.line, opt.pressed and 110 or 80), Skin.Col(v.line, 0)))
            nvgFill(nvg)
        end
        -- 顶部玻璃高光线
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, x + c + 2, by + 1.5)
        nvgLineTo(nvg, x + w - 3, by + 1.5)
        nvgStrokeColor(nvg, Skin.Col(WHITE, opt.disabled and 20 or 55))
        nvgStrokeWidth(nvg, 1)
        nvgStroke(nvg)
        -- 细光线描边
        nvgBeginPath(nvg)
        TechPath(nvg, x + 0.5, by + 0.5, w - 1, h - 1, c)
        nvgStrokeColor(nvg, Skin.Col(isDark and acc.line or v.line, isDark and 120 or 235))
        nvgStrokeWidth(nvg, isDark and 1 or 1.4)
        nvgStroke(nvg)
        -- 底部光条
        LightLine(nvg, x + w * 0.12, by + h - 2.5, w * 0.76, 2, isDark and acc.line or v.line, isDark and 150 or 255)

    elseif styleName == "card" or styleName == "slot" then
        local rar = Skin.RARITY[opt.rarity or "common"] or Skin.RARITY.common
        local c = math.min(8, h * 0.18)
        nvgBeginPath(nvg)
        TechPath(nvg, x, y, w, h, c)
        nvgFillPaint(nvg, nvgLinearGradient(nvg, x, y, x, y + h, Skin.Col(CARD_TOP, 245), Skin.Col(CARD_BOT, 248)))
        nvgFill(nvg)
        -- 稀有度：顶部光条 + 极淡底色染色
        nvgBeginPath(nvg)
        TechPath(nvg, x, y, w, h, c)
        nvgFillPaint(nvg, nvgLinearGradient(nvg, x, y, x, y + h * 0.6, Skin.Col(rar.col, 26), Skin.Col(rar.col, 0)))
        nvgFill(nvg)
        LightLine(nvg, x + c, y + 0.5, w - c * 2, 2, rar.col, 220)
        nvgBeginPath(nvg)
        TechPath(nvg, x + 0.5, y + 0.5, w - 1, h - 1, c)
        nvgStrokeColor(nvg, Skin.Col(opt.selected and SEL_GOLD or CARD_LINE, opt.selected and 255 or 230))
        nvgStrokeWidth(nvg, opt.selected and 1.8 or 1)
        nvgStroke(nvg)
        if opt.selected then
            nvgBeginPath(nvg)
            TechPath(nvg, x + 1, y + 1, w - 2, h - 2, c)
            nvgFillPaint(nvg, nvgBoxGradient(nvg, x, y, w, h, c, math.min(w, h) * 0.3, Skin.Col(SEL_GOLD, 0), Skin.Col(SEL_GOLD, 60)))
            nvgFill(nvg)
        end

    elseif styleName == "plate" or styleName == "cloth" then
        -- 顶栏（plate，光线在底边）/ 底栏（cloth，光线在顶边）
        nvgBeginPath(nvg)
        nvgRect(nvg, x, y, w, h)
        nvgFillPaint(nvg, nvgLinearGradient(nvg, x, y, x, y + h, Skin.Col(PANEL_TOP, 248), Skin.Col(PANEL_BOT, 252)))
        nvgFill(nvg)
        local ly = (styleName == "plate") and (y + h - 1.5) or y
        LightLine(nvg, x, ly, w, 1.5, PANEL_LINE, 220)
        Additive(nvg, true)
        local gy = (styleName == "plate") and (y + h - 10) or y
        nvgBeginPath(nvg)
        nvgRect(nvg, x, gy, w, 10)
        nvgFillPaint(nvg, nvgLinearGradient(nvg, x, (styleName == "plate") and (y + h) or y,
            x, (styleName == "plate") and (y + h - 10) or (y + 10), Skin.Col(PANEL_LINE, 40), Skin.Col(PANEL_LINE, 0)))
        nvgFill(nvg)
        Additive(nvg, false)

    elseif styleName == "banner" then
        local col = (opt.color == "gold" and C.gold) or (opt.color == "red" and C.red)
            or (opt.color == "green" and C.green) or C.cyan
        local c = math.min(8, h * 0.3)
        nvgBeginPath(nvg)
        TechPath(nvg, x, y, w, h, c)
        nvgFillPaint(nvg, nvgLinearGradient(nvg, x, y, x, y + h, Skin.Col(GLASS_TOP, 245), Skin.Col(GLASS_BOT, 248)))
        nvgFill(nvg)
        nvgStrokeColor(nvg, Skin.Col(col, 230))
        nvgStrokeWidth(nvg, 1.2)
        nvgStroke(nvg)
        LightLine(nvg, x + w * 0.1, y + h - 2, w * 0.8, 2, col, 255)

    else
        -- 弹窗 / 容器面板 "panel"
        local c = math.min(16, w * 0.06)
        local line = opt.borderColor or PANEL_LINE
        nvgBeginPath(nvg)
        TechPath(nvg, x, y + 4, w, h, c)
        nvgFillColor(nvg, Skin.Col(C.shadow, 150))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        TechPath(nvg, x, y, w, h, c)
        nvgFillPaint(nvg, nvgLinearGradient(nvg, x, y, x, y + h, Skin.Col(PANEL_TOP, 250), Skin.Col(PANEL_BOT, 252)))
        nvgFill(nvg)
        -- 极淡横向扫描纹（科技屏幕质感）
        nvgBeginPath(nvg)
        for ly = y + 6, y + h - 4, 6 do
            nvgRect(nvg, x + 2, ly, w - 4, 1)
        end
        nvgFillColor(nvg, Skin.Col(WHITE, 6))
        nvgFill(nvg)
        -- 细描边 + 亮角标
        nvgBeginPath(nvg)
        TechPath(nvg, x + 0.5, y + 0.5, w - 1, h - 1, c)
        nvgStrokeColor(nvg, Skin.Col(line, 110))
        nvgStrokeWidth(nvg, 1)
        nvgStroke(nvg)
        local tk = math.min(22, w * 0.08)
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, x + c * 0.3, y + c + tk)
        nvgLineTo(nvg, x + 0.5, y + c)
        nvgLineTo(nvg, x + c, y + 0.5)
        nvgLineTo(nvg, x + c + tk, y + 0.5)
        nvgMoveTo(nvg, x + w - c - tk, y + h - 0.5)
        nvgLineTo(nvg, x + w - c, y + h - 0.5)
        nvgLineTo(nvg, x + w - 0.5, y + h - c)
        nvgLineTo(nvg, x + w - 0.5, y + h - c - tk)
        nvgStrokeColor(nvg, Skin.Col(PANEL_TICK, 240))
        nvgStrokeWidth(nvg, 2)
        nvgStroke(nvg)
        -- 顶边光线
        LightLine(nvg, x + w * 0.2, y + 0.5, w * 0.6, 1.5, PANEL_TICK, 200)
    end
end

return Skin
