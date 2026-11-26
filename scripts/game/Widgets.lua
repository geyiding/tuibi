-- ============================================================================
-- Widgets.lua  霓虹街机 UI 控件库（全一次建树 + 属性增量刷新）
-- ============================================================================

local UI = require("urhox-libs/UI")
local okIC, ImageCache = pcall(require, "urhox-libs/UI/Core/ImageCache")
local Config = require("game/Config")
local Skin = require("game/Skin")
local Art = require("game/Art")
local AvatarArt = require("game/AvatarArt")
local Number = require("game/Number")

local Widgets = {}
local C, U = Skin.C, Skin.UI

-- 全局动画时钟（main.lua 每帧 Widgets.Tick(dt) 推进；用于按钮流光等常驻动效）
Widgets.time = 0
function Widgets.Tick(dt)
    Widgets.time = Widgets.time + (dt or 0)
end

local BADGE_RED = { 255, 58, 82 }
local BADGE_EDGE = { 255, 236, 240 }
local SHINE = { 255, 255, 255 }
local floor, min, max = math.floor, math.min, math.max

local function PickWidget(a, b)
    if type(a) == "table" and a.GetAbsoluteLayout then return a end
    return b
end
Widgets.PickWidget = PickWidget

function Widgets.PressFx(props)
    props.transition = "scale 0.1s easeOut"
    props.onPointerDown = function(a, b)
        local w = PickWidget(a, b)
        if w and not (w.skin_ and w.skin_.disabled) then w:SetStyle({ scale = 0.94 }) end
    end
    props.onPointerUp = function(a, b)
        local w = PickWidget(a, b)
        if w then w:SetStyle({ scale = 1.0 }) end
    end
    props.onPointerLeave = function(a, b)
        local w = PickWidget(a, b)
        if w then w:SetStyle({ scale = 1.0 }) end
    end
    return props
end

-- ----------------------------------------------------------------------------
-- NeoFrame：支持 Skin.TEXTURES 九宫格切片替换的程序化容器
-- ----------------------------------------------------------------------------
local NeoFrame = UI.Panel:Extend("NeoFrame")
Widgets.NeoFrame = NeoFrame

function NeoFrame:Init(props)
    props = props or {}
    self.skinStyle_ = props.style or "panel"
    self.skin_ = props.skin or {}
    props.style, props.skin = nil, nil
    local tex = (self.skinStyle_ == "button")
        and (Skin.TEXTURES["button_" .. tostring(self.skin_.variant or "primary")] or Skin.TEXTURES.button)
        or Skin.TEXTURES[self.skinStyle_]
    if tex then
        props.backgroundImage = tex.image
        props.backgroundFit = "sliced"
        props.backgroundSlice = tex.slice
        self.useTexture_ = true
    end
    UI.Panel.Init(self, props)
end

-- 绘制无内部接缝的 9-slice（仅向内邻接边重叠 +0.85px，消除 NanoVG 相邻矩形 0.75 alpha 暗缝）
local function DrawSeamlessSliced(nvg, imagePath, l, slice, opacity)
    if not (okIC and ImageCache) or not imagePath or l.w <= 0 or l.h <= 0 then return false end
    local imgHandle = ImageCache.Get(imagePath)
    if not imgHandle or imgHandle <= 0 then return false end
    local imgW, imgH = ImageCache.GetSize(imagePath)
    if imgW <= 0 or imgH <= 0 then return false end

    local srcT, srcR, srcB, srcL = slice[1] or 0, slice[2] or 0, slice[3] or 0, slice[4] or 0
    local x, y, w, h = l.x, l.y, l.w, l.h
    local dstL, dstR, dstT, dstB = srcL, srcR, srcT, srcB
    if w < dstL + dstR and (dstL + dstR) > 0 then
        local kx = w / (dstL + dstR)
        dstL, dstR = dstL * kx, dstR * kx
    end
    if h < dstT + dstB and (dstT + dstB) > 0 then
        local ky = h / (dstT + dstB)
        dstT, dstB = dstT * ky, dstB * ky
    end
    local centerW = max(0, w - dstL - dstR)
    local centerH = max(0, h - dstT - dstB)
    local srcCW = max(1, imgW - srcL - srcR)
    local srcCH = max(1, imgH - srcT - srcB)
    local alpha = opacity or 1
    local ov = 0.85

    local function drawSlice(dx, dy, dw, dh, sx, sy, sw, sh, exL, exT, exR, exB)
        if dw <= 0.01 or dh <= 0.01 or sw <= 0 or sh <= 0 then return end
        local scaleX = dw / sw
        local scaleY = dh / sh
        local ox = dx - sx * scaleX
        local oy = dy - sy * scaleY
        nvgBeginPath(nvg)
        nvgRect(nvg, dx - exL, dy - exT, dw + exL + exR, dh + exT + exB)
        nvgFillPaint(nvg, nvgImagePattern(nvg, ox, oy, imgW * scaleX, imgH * scaleY, 0, imgHandle, alpha))
        nvgFill(nvg)
    end

    -- 1. 中心区（4 条内边均略微外延，先铺底）
    drawSlice(x + dstL, y + dstT, centerW, centerH, srcL, srcT, srcCW, srcCH, ov, ov, ov, ov)
    -- 2. 四边（仅沿贴片接触边向角/中心延伸）
    drawSlice(x + dstL, y, centerW, dstT, srcL, 0, srcCW, srcT, ov, 0, ov, ov)
    drawSlice(x + dstL, y + dstT + centerH, centerW, dstB, srcL, imgH - srcB, srcCW, srcB, ov, ov, ov, 0)
    drawSlice(x, y + dstT, dstL, centerH, 0, srcT, srcL, srcCH, 0, ov, ov, ov)
    drawSlice(x + dstL + centerW, y + dstT, dstR, centerH, imgW - srcR, srcT, srcR, srcCH, ov, ov, 0, ov)
    -- 3. 四角（严格贴合外框，0 外溢）
    drawSlice(x, y, dstL, dstT, 0, 0, srcL, srcT, 0, 0, 0, 0)
    drawSlice(x + dstL + centerW, y, dstR, dstT, imgW - srcR, 0, srcR, srcT, 0, 0, 0, 0)
    drawSlice(x, y + dstT + centerH, dstL, dstB, 0, imgH - srcB, srcL, srcB, 0, 0, 0, 0)
    drawSlice(x + dstL + centerW, y + dstT + centerH, dstR, dstB, imgW - srcR, imgH - srcB, srcR, srcB, 0, 0, 0, 0)
    return true
end

function NeoFrame:Render(nvg)
    if self.useTexture_ then
        local props = self.props
        if props.backgroundFit == "sliced" and props.backgroundSlice and props.backgroundImage then
            if not DrawSeamlessSliced(nvg, props.backgroundImage, self:GetAbsoluteLayout(), props.backgroundSlice, props.backgroundImageOpacity or 1) then
                UI.Panel.Render(self, nvg)
            end
        else
            UI.Panel.Render(self, nvg)
        end
        if self.skin_.selected then
            local l = self:GetAbsoluteLayout()
            local r = self.skin_.radius or 10
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, l.x + 1, l.y + 1, l.w - 2, l.h - 2, r)
            nvgStrokeColor(nvg, Skin.Col(C.gold, 255))
            nvgStrokeWidth(nvg, 2.5)
            nvgStroke(nvg)
        elseif self.skin_.afford then
            Widgets.DrawAffordGlow(nvg, self:GetAbsoluteLayout(), self.skin_.radius or 10)
        end
        return
    end
    local l = self:GetAbsoluteLayout()
    Skin.Draw(nvg, self.skinStyle_, l.x, l.y, l.w, l.h, self.skin_)
    if self.skin_.afford and not self.skin_.selected then
        Widgets.DrawAffordGlow(nvg, l, self.skin_.radius or 10)
    end
end

--- “买得起”呼吸光：内发光 + 脉动描边（哪里亮了点哪里）
function Widgets.DrawAffordGlow(nvg, l, r)
    if l.w <= 0 or l.h <= 0 then return end
    local p = 0.5 + 0.5 * math.sin(Widgets.time * 5)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, l.x + 1, l.y + 1, l.w - 2, l.h - 2, r)
    nvgFillPaint(nvg, nvgBoxGradient(nvg, l.x, l.y, l.w, l.h, r, min(l.w, l.h) * 0.35,
        Skin.Col(C.cyan, 0), Skin.Col(C.cyan, floor(40 + 50 * p))))
    nvgFill(nvg)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, l.x + 1.5, l.y + 1.5, l.w - 3, l.h - 3, r)
    nvgStrokeColor(nvg, Skin.Col(C.cyan, floor(170 + 85 * p)))
    nvgStrokeWidth(nvg, 1.8 + p * 0.8)
    nvgStroke(nvg)
end

-- ----------------------------------------------------------------------------
-- NeoButton：霓虹立体按钮（单行文字不裁剪，按压 0.94 缩放，支持禁用态）
-- ----------------------------------------------------------------------------
local NeoButton = NeoFrame:Extend("NeoButton")
Widgets.NeoButton = NeoButton

function NeoButton:Init(props)
    props = props or {}
    local frameStyle = props.style or "button"
    local variant = props.variant or "primary"
    local darkText = (frameStyle == "button") and (variant == "primary" or variant == "cyan" or variant == "green")
    self.onPress_ = props.onClick
    self.btnLabel_ = UI.Label {
        text = props.text or "",
        fontSize = props.fontSize or 16,
        fontWeight = "bold",
        fontColor = props.fontColor or (darkText and { 14, 16, 32, 255 } or U.text),
        textAlign = "center",
        maxLines = 1,
        flexShrink = 1,
    }
    local selfRef = self
    props.style = frameStyle
    props.skin = { variant = variant, pressed = false, disabled = false, radius = props.borderRadius or 12 }
    props.flexDirection = "row"
    props.justifyContent = "center"
    props.alignItems = "center"
    props.minHeight = props.minHeight or 44
    props.paddingHorizontal = props.paddingHorizontal or 12
    props.paddingBottom = 2
    props.children = { self.btnLabel_ }
    props.transition = props.transition or "scale 0.1s easeOut"
    props.onPointerDown = function()
        if selfRef.skin_.disabled then return end
        selfRef.skin_.pressed = true
        selfRef:SetStyle({ scale = 0.94 })
        selfRef.btnLabel_:SetStyle({ translateY = 1.5 })
    end
    props.onPointerUp = function() selfRef:Unpress() end
    props.onPointerLeave = function() selfRef:Unpress() end
    props.onClick = function()
        if selfRef.skin_.disabled then return end
        if selfRef.onPress_ then selfRef.onPress_(selfRef) end
    end
    props.variant, props.text, props.fontSize, props.fontColor = nil, nil, nil, nil
    NeoFrame.Init(self, props)
end

function NeoButton:Unpress()
    if not self.skin_.pressed then return end
    self.skin_.pressed = false
    self:SetStyle({ scale = 1.0 })
    self.btnLabel_:SetStyle({ translateY = 0 })
end

function NeoButton:SetText(t)
    if self.btnLabel_.props.text ~= t then
        self.btnLabel_:SetText(t)
    end
end

function NeoButton:SetVariant(v)
    if self.skin_.variant ~= v then
        self.skin_.variant = v
        local isBtn = (self.skinStyle_ == "button")
        local darkText = isBtn and (v == "primary" or v == "cyan" or v == "green")
        self.btnLabel_:SetStyle({ fontColor = darkText and { 14, 16, 32, 255 } or U.text })
        if self.useTexture_ and isBtn then
            local tex = Skin.TEXTURES["button_" .. tostring(v)] or Skin.TEXTURES.button
            if tex then
                self:SetStyle({ backgroundImage = tex.image, backgroundFit = "sliced", backgroundSlice = tex.slice })
            end
        end
    end
end

--- 右上角红点数字（0 隐藏）
function NeoButton:SetBadge(n)
    n = math.floor(tonumber(n) or 0)
    if n == self.badge_ then return end
    self.badge_ = n
    self.badgeTxt_ = (n > 99) and "99+" or tostring(n)
end

--- 常驻流光（可购买 / 可领取时提示“快点我”）
function NeoButton:SetShine(on)
    self.shine_ = (on == true)
    if self.shine_ and not self.shinePh_ then self.shinePh_ = math.random() * 1.6 end
end

function NeoButton:Render(nvg)
    NeoFrame.Render(self, nvg)
    local hasBadge = (self.badge_ or 0) > 0
    if not self.shine_ and not hasBadge then return end
    local l = self:GetAbsoluteLayout()
    if l.w <= 0 or l.h <= 0 then return end
    if self.shine_ and not self.skin_.disabled then
        local ph = (Widgets.time * 0.7 + (self.shinePh_ or 0)) % 1.6
        if ph < 1 then
            local x = l.x - l.w * 0.3 + l.w * 1.6 * ph
            local bw = max(10, l.w * 0.16)
            nvgSave(nvg)
            nvgIntersectScissor(nvg, l.x + 2, l.y + 2, l.w - 4, l.h - 4)
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, x, l.y)
            nvgLineTo(nvg, x + bw, l.y)
            nvgLineTo(nvg, x + bw - l.h * 0.5, l.y + l.h)
            nvgLineTo(nvg, x - l.h * 0.5, l.y + l.h)
            nvgClosePath(nvg)
            nvgFillColor(nvg, Skin.Col(SHINE, 85))
            nvgFill(nvg)
            nvgRestore(nvg)
        end
    end
    if hasBadge then
        local r = 9
        local bx, by = l.x + l.w - r - 1, l.y + r + 1
        local pulse = 1 + 0.08 * math.sin(Widgets.time * 6)
        nvgBeginPath(nvg)
        nvgCircle(nvg, bx, by, r * pulse)
        nvgFillColor(nvg, Skin.Col(BADGE_RED, 255))
        nvgFill(nvg)
        nvgStrokeColor(nvg, Skin.Col(BADGE_EDGE, 255))
        nvgStrokeWidth(nvg, 1.5)
        nvgStroke(nvg)
        nvgFontFace(nvg, "sans")
        nvgFontSize(nvg, (#self.badgeTxt_ >= 3) and 9 or 11)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, Skin.Col(C.white, 255))
        nvgText(nvg, bx, by + 0.5, self.badgeTxt_)
    end
end

function NeoButton:SetDisabled(d)
    local b = d == true
    if self.skin_.disabled ~= b then
        self.skin_.disabled = b
        self:SetStyle({ opacity = b and 0.48 or 1.0 })
    end
end

-- ----------------------------------------------------------------------------
-- NeoIcon：绘制硬币 / 通用程序图标 / 遗物图标（支持 Skin.SPRITES 热替换）
-- ----------------------------------------------------------------------------
local NeoIcon = UI.Widget:Extend("NeoIcon")
Widgets.NeoIcon = NeoIcon

function NeoIcon:Init(props)
    props = props or {}
    local sz = props.size or 28
    props.width = props.width or sz
    props.height = props.height or sz
    props.pointerEvents = props.pointerEvents or "none"
    self.iconKind_ = props.kind or "icon"
    self.iconKey_ = props.key or "coin"
    self.iconLv_ = props.level or 1
    self.iconTint_ = props.tint
    props.kind, props.key, props.level, props.tint, props.size = nil, nil, nil, nil, nil
    UI.Widget.Init(self, props)
end

function NeoIcon:SetIcon(kind, key, level, tint)
    self.iconKind_ = kind or self.iconKind_
    self.iconKey_ = key or self.iconKey_
    self.iconLv_ = level or 1
    self.iconTint_ = tint
end

function NeoIcon:Render(nvg)
    local l = self:GetAbsoluteLayout()
    local s = min(l.w, l.h)
    if s <= 0 then return end
    local x = l.x + (l.w - s) * 0.5
    local y = l.y + (l.h - s) * 0.5
    if self.iconKind_ == "coin" then
        Art.DrawCoin(nvg, self.iconKey_, x + s * 0.5, y + s * 0.5, s * 0.44, self.iconLv_, 0.9, 0, false, -1, false)
    elseif self.iconKind_ == "relic" then
        local sp = "relic_" .. tostring(self.iconKey_)
        if not Art.DrawSprite(nvg, sp, x, y, s, s, 1) then
            local def = Config.RELICS[self.iconKey_]
            Art.DrawIcon(nvg, (def and def.icon) or "star", x, y, s, self.iconTint_)
        end
    elseif self.iconKind_ == "boss" then
        local sp = "boss_" .. tostring(self.iconKey_)
        if not Art.DrawSprite(nvg, sp, x, y, s, s, 1) then
            local bDef = Config.BOSSES[self.iconKey_]
            Art.DrawIcon(nvg, (bDef and bDef.icon) or "crown", x, y, s, self.iconTint_)
        end
    elseif self.iconKind_ == "event" then
        local sp = "event_" .. tostring(self.iconKey_)
        if not Art.DrawSprite(nvg, sp, l.x, l.y, l.w, l.h, 1) then
            Art.DrawIcon(nvg, "chest", x, y, s, self.iconTint_)
        end
    else
        Art.DrawIcon(nvg, self.iconKey_, x, y, s, self.iconTint_)
    end
end

-- ----------------------------------------------------------------------------
-- NeoBar：目标分进度条（内置文字居左，百分比居中）
-- ----------------------------------------------------------------------------
local NeoBar = UI.Widget:Extend("NeoBar")
Widgets.NeoBar = NeoBar

function NeoBar:Init(props)
    props = props or {}
    self.barVal_ = props.value or 0
    self.barText_ = props.text or ""
    self.barCol_ = props.color or C.cyan
    props.value, props.text, props.color = nil, nil, nil
    props.pointerEvents = "none"
    UI.Widget.Init(self, props)
end

function NeoBar:SetProgress(val, text, col)
    self.barVal_ = max(0, min(1, val or 0))
    if text ~= nil then self.barText_ = text end
    if col ~= nil then self.barCol_ = col end
end

-- 每种主色派生一次（亮/暗/高光），常量表供 Skin.Col 缓存
local barPalCache = {}
local function BarPalette(col)
    local p = barPalCache[col]
    if p then return p end
    p = {
        dark = { floor(col[1] * 0.35), floor(col[2] * 0.35), floor(col[3] * 0.45) },
        mid = { col[1], col[2], col[3] },
        light = { min(255, floor(col[1] * 0.5 + 128)), min(255, floor(col[2] * 0.5 + 128)), min(255, floor(col[3] * 0.5 + 128)) },
    }
    barPalCache[col] = p
    return p
end
local BAR_TRACK = { 8, 10, 24 }
local BAR_TRACK2 = { 22, 26, 52 }
local BAR_INK = { 6, 8, 20 }

function NeoBar:Render(nvg)
    local l = self:GetAbsoluteLayout()
    if l.w <= 0 or l.h <= 0 then return end
    local t = Widgets.time
    -- 显示值平滑追随（进度只涨时滑动，重置为低值时直接跳）
    local target = self.barVal_
    local shown = self.shownVal_ or target
    if target < shown - 0.02 then shown = target else shown = shown + (target - shown) * 0.18 end
    self.shownVal_ = shown

    local r = min(9, l.h * 0.5)
    local pal = BarPalette(self.barCol_ or C.cyan)
    -- 轨道（内凹）
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, l.x, l.y, l.w, l.h, r)
    nvgFillPaint(nvg, nvgLinearGradient(nvg, l.x, l.y, l.x, l.y + l.h, Skin.Col(BAR_TRACK, 245), Skin.Col(BAR_TRACK2, 245)))
    nvgFill(nvg)

    local inset = (l.h >= 16) and 2.5 or 1.5
    local fx0, fy0, fh = l.x + inset, l.y + inset, l.h - inset * 2
    local fw = (l.w - inset * 2) * shown
    local near = (shown >= 0.9 and shown < 1)
    if fw > 1 then
        local fr = max(1, r - inset)
        -- 填充：暗 -> 主色 -> 亮
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, fx0, fy0, fw, fh, min(fr, fw * 0.5))
        nvgFillPaint(nvg, nvgLinearGradient(nvg, fx0, 0, fx0 + max(fw, 8), 0, Skin.Col(pal.dark, 255), Skin.Col(pal.mid, 255)))
        nvgFill(nvg)
        -- 上半高光（玻璃感）
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, fx0 + 1, fy0 + 1, max(0, fw - 2), fh * 0.42, min(fr, fw * 0.5))
        nvgFillColor(nvg, Skin.Col(C.white, 70))
        nvgFill(nvg)
        -- 流光扫过
        if fw > 20 then
            local ph = (t * 0.6) % 1.4
            if ph < 1 then
                local sx = fx0 + fw * ph
                nvgSave(nvg)
                nvgIntersectScissor(nvg, fx0, fy0, fw, fh)
                nvgBeginPath(nvg)
                nvgRect(nvg, sx - 10, fy0, 20, fh)
                nvgFillPaint(nvg, nvgRadialGradient(nvg, sx, fy0 + fh * 0.5, 1, 12, Skin.Col(C.white, 110), Skin.Col(C.white, 0)))
                nvgFill(nvg)
                nvgRestore(nvg)
            end
        end
        -- 发光进度头
        if shown < 1 and l.h >= 8 then
            local hx = fx0 + fw
            local gr = fh * (near and (1.15 + 0.25 * math.sin(t * 10)) or 0.95)
            nvgBeginPath(nvg)
            nvgCircle(nvg, hx, fy0 + fh * 0.5, gr)
            nvgFillPaint(nvg, nvgRadialGradient(nvg, hx, fy0 + fh * 0.5, 0.5, gr, Skin.Col(pal.light, 230), Skin.Col(pal.light, 0)))
            nvgFill(nvg)
        end
    end
    -- 刻度（每 10%）
    if l.h >= 16 and l.w >= 120 then
        nvgBeginPath(nvg)
        for k = 1, 9 do
            local x = l.x + l.w * k / 10
            nvgMoveTo(nvg, x, l.y + l.h - 4)
            nvgLineTo(nvg, x, l.y + l.h - 1.5)
        end
        nvgStrokeColor(nvg, Skin.Col(C.white, 60))
        nvgStrokeWidth(nvg, 1)
        nvgStroke(nvg)
    end
    -- 外框（接近完成时呼吸发光）
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, l.x + 0.5, l.y + 0.5, l.w - 1, l.h - 1, r)
    nvgStrokeColor(nvg, Skin.Col(near and pal.light or C.border, near and floor(180 + 75 * math.sin(t * 8)) or 210))
    nvgStrokeWidth(nvg, near and 2 or 1.5)
    nvgStroke(nvg)

    if self.barText_ ~= "" then
        nvgFontFace(nvg, "sans")
        nvgFontSize(nvg, 13)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        local tx, ty = l.x + l.w * 0.5, l.y + l.h * 0.5
        nvgFillColor(nvg, Skin.Col(BAR_INK, 245))
        nvgText(nvg, tx - 1.2, ty, self.barText_)
        nvgText(nvg, tx + 1.2, ty, self.barText_)
        nvgText(nvg, tx, ty - 1.2, self.barText_)
        nvgText(nvg, tx, ty + 1.2, self.barText_)
        nvgFillColor(nvg, Skin.Col(C.white, 255))
        nvgText(nvg, tx, ty, self.barText_)
    end
end

-- ----------------------------------------------------------------------------
-- AvatarIcon：世界富豪程序化漫画圆章头像（支持增量刷新）
-- ----------------------------------------------------------------------------
local AvatarIcon = UI.Widget:Extend("AvatarIcon")
Widgets.AvatarIcon = AvatarIcon

function AvatarIcon:Init(props)
    props = props or {}
    local sz = props.size or 48
    props.width = props.width or sz
    props.height = props.height or sz
    props.pointerEvents = props.pointerEvents or "none"
    self.entry_ = props.entry
    self.shocked_ = (props.shocked == true)
    self.surpassed_ = (props.surpassed == true)
    self.t_ = 0
    props.entry, props.shocked, props.surpassed, props.size = nil, nil, nil, nil
    UI.Widget.Init(self, props)
end

function AvatarIcon:SetEntry(entry, shocked, surpassed)
    self.entry_ = entry
    self.shocked_ = (shocked == true)
    self.surpassed_ = (surpassed == true)
end

function AvatarIcon:Render(nvg)
    local l = self:GetAbsoluteLayout()
    local s = min(l.w, l.h)
    if s <= 0 then return end
    self.t_ = self.t_ + 0.016
    AvatarArt.Draw(nvg, self.entry_, l.x + l.w * 0.5, l.y + l.h * 0.5, s * 0.44, {
        shocked = self.shocked_,
        surpassed = self.surpassed_,
        time = self.t_,
    })
end

Widgets.FormatNum = Number.FormatNum
Widgets.FormatMul = Number.FormatMul

return Widgets
