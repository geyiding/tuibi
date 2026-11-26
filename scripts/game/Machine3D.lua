-- ============================================================================
-- Machine3D.lua  《推币机的狂欢》真 3D PBR 街机推币机舞台（全兼容引擎内置几何体）
--   · 使用 Models/Box.mdl / Cylinder.mdl / Sphere.mdl / Plane.mdl / Torus.mdl 组装，
--     零第三方几何构建 API 依赖，兼容本地窗口与云端 Web 全版本 UrhoX 引擎
--   · 包含金属倒角机身、往复推板、摆动发射炮口、移动中奖门、发光钉阵、24 颗3D跑马灯球、
--     亚克力防护侧玻璃及 140 枚立体金属贴图硬币池
-- ============================================================================

local Config = require("game/Config")
local Physics = require("game/Physics")
local Skin = require("game/Skin")

local S = Config.STAGE
local floor, min, max = math.floor, math.min, math.max

local Machine3D = {}

-- 持有强引用防止 Scene / Camera / Viewport / Models 被 Lua GC 回收
local M = {
    active = false,
    scene = nil,
    viewport = nil,
    camNode = nil,
    cam = nil,
    zone = nil,
    dirLight = nil,
    ptLights = {},
    models = {},
    mats = {},
    coinMats = {},
    pegMats = {},
    cabinetNode = nil,
    backboardNode = nil,
    backboardMat = nil,
    pusherNode = nil,
    pusherNeonMat = nil,
    launcherNode = nil,
    gateNode = nil,
    gateLeftNode = nil,
    gateRightNode = nil,
    gateBeamNode = nil,
    leftGuardNode = nil,
    rightGuardNode = nil,
    guardMat = nil,
    bulbs = {},
    pegNodes = {},
    pegSig = "",
    lastPegVer = -1,
    lastThemeKey = "",
    lastBulbPhase = -1,
    lastGuarded = nil,
    lastCamKey = "",
    projSlot = nil,
    projDeck = nil,
    coinPool = {},
    lastTheme = -1,
    bulbLitMat = nil,
    bulbDimMat = nil,
}

-- 辅助：创建纯色 / 自发光 / 透明 PBR 材质（仅用合法内置 Technique）
local function MakePBR(diffCol, metallic, roughness, emissiveCol, alpha)
    local mat = Material:new()
    local isAlpha = (alpha ~= nil and alpha < 0.999)
    local techPath = isAlpha and "Techniques/PBR/PBRNoTextureAlpha.xml" or "Techniques/PBR/PBRNoTexture.xml"
    mat:SetTechnique(0, cache:GetResource("Technique", techPath))
    local col = Color(diffCol[1], diffCol[2], diffCol[3], alpha or 1.0)
    mat:SetShaderParameter("MatDiffColor", Variant(col))
    mat:SetShaderParameter("Metallic", Variant(metallic or 0.0))
    mat:SetShaderParameter("Roughness", Variant(roughness or 0.45))
    if emissiveCol then
        mat:SetShaderParameter("MatEmissiveColor", Variant(Color(emissiveCol[1], emissiveCol[2], emissiveCol[3])))
    end
    return mat
end

-- 辅助：创建贴图无光照材质（硬币表面图案 / 背板霓虹图案）
local function MakeTexturedUnlit(texPath, isAlpha, tintCol)
    if not cache or not texPath then return nil end
    if cache.Exists and not cache:Exists(texPath) then return nil end
    local tex = cache:GetResource("Texture2D", texPath)
    if not tex then return nil end
    local mat = Material:new()
    local tech = isAlpha and "Techniques/DiffUnlitAlpha.xml" or "Techniques/DiffUnlit.xml"
    mat:SetTechnique(0, cache:GetResource("Technique", tech))
    mat:SetTexture(TU_DIFFUSE, tex)
    local c = tintCol or { 1.0, 1.0, 1.0, 1.0 }
    mat:SetShaderParameter("MatDiffColor", Variant(Color(c[1], c[2], c[3], c[4] or 1.0)))
    mat.cullMode = CULL_NONE
    return mat
end

local function AddPart(parent, name, model, mat, pos, scale, rot)
    local n = parent:CreateChild(name)
    if pos then n.position = pos end
    if scale then n.scale = scale end
    if rot then n.rotation = rot end
    local sm = n:CreateComponent("StaticModel")
    sm:SetModel(model)
    if mat then sm:SetMaterial(mat) end
    sm.castShadows = false
    return n, sm
end

-- ----------------------------------------------------------------------------
-- 逻辑坐标 (360×600) <-> 3D 世界坐标 (米, +X右 +Y上 +Z向机台内部, 相机在 -Z 看向 +Z)
-- ----------------------------------------------------------------------------
local function LogicToWorld3D(lx, ly, zone, lz, onPusher)
    lz = lz or 0
    if zone == "slot" then
        local wx = ((lx - 180) / 124.0) * 1.36
        local wy = 0.28 + (S.DECK_TOP_Y - ly) * 0.0101
        local wz = 1.37 + lz * 0.004
        return Vector3(wx, wy, wz)
    elseif zone == "dropping" then
        local progress = max(0, (ly - S.DECK_BOT_Y) / max(1, (S.DROP_END_Y - S.DECK_BOT_Y)))
        local nx = (lx - 180) / S.DECK_BOT_HALF
        local wx = nx * 1.40
        local wy = 0.045 - progress * 0.88 + lz * 0.008
        local wz = -1.52 - progress * 0.34
        return Vector3(wx, wy, wz)
    else
        local hw = Physics.TrapezoidHalfW(ly)
        local nx = (lx - 180) / max(1, hw)
        local wx = nx * 1.40
        local wz = 1.50 - (ly - S.DECK_TOP_Y) * 0.01
        local baseY = onPusher and 0.245 or 0.036
        local wy = baseY + lz * 0.009
        return Vector3(wx, wy, wz)
    end
end

local function SetMatColor(mat, rgb, a)
    if mat then
        mat:SetShaderParameter("MatDiffColor", Variant(Color(rgb[1], rgb[2], rgb[3], a or 1.0)))
    end
end

local function SetMatEmissive(mat, rgb)
    if mat then
        mat:SetShaderParameter("MatEmissiveColor", Variant(Color(rgb[1], rgb[2], rgb[3])))
    end
end

local function ApplyThemeColors(themeIdx, boostOn, feverOn)
    local themeKey = tostring(themeIdx) .. (boostOn and "B" or "") .. (feverOn and "F" or "")
    if themeKey == M.lastThemeKey then return end
    M.lastThemeKey = themeKey

    local c1, c2
    if themeIdx == 2 then
        c1 = { 1.0, 0.72, 0.16 }
        c2 = { 1.0, 0.34, 0.12 }
    elseif themeIdx == 3 then
        c1 = { 0.72, 0.42, 1.0 }
        c2 = { 1.0, 0.82, 0.22 }
    else
        c1 = { 0.18, 0.88, 1.0 }
        c2 = { 1.0, 0.25, 0.70 }
    end

    if feverOn then
        c1 = { 1.0, 0.25, 0.75 }
        c2 = { 1.0, 0.86, 0.22 }
    elseif boostOn then
        c2 = { 1.0, 0.86, 0.22 }
    end

    local pulse = (feverOn or boostOn) and 1.45 or 1.05
    SetMatEmissive(M.mats.neonPrimary, { c1[1] * pulse, c1[2] * pulse, c1[3] * pulse })
    SetMatColor(M.mats.neonPrimary, c1, 1.0)
    SetMatEmissive(M.mats.neonSecondary, { c2[1] * pulse, c2[2] * pulse, c2[3] * pulse })
    SetMatColor(M.mats.neonSecondary, c2, 1.0)
    SetMatEmissive(M.pusherNeonMat, { c2[1] * pulse, c2[2] * pulse, c2[3] * pulse })
    SetMatColor(M.pusherNeonMat, c2, 1.0)

    if M.ptLights[1] then M.ptLights[1].color = Color(c2[1] * 0.4 + 0.6, c2[2] * 0.4 + 0.5, c2[3] * 0.4 + 0.5) end

    if themeIdx ~= M.lastTheme then
        M.lastTheme = themeIdx
        local bgPath = "image/machine/backdrop_act" .. tostring(themeIdx) .. ".png"
        if M.backboardMat and cache and (not cache.Exists or cache:Exists(bgPath)) then
            local tex = cache:GetResource("Texture2D", bgPath)
            if tex then
                M.backboardMat:SetTexture(TU_DIFFUSE, tex)
            end
        end
    end
end

local function GetCoinMaterials(kind)
    if M.coinMats[kind] then return M.coinMats[kind] end
    local def = Config.COINS[kind] or Config.COINS.gold
    local rawCol = def and def.color
    local col = (type(rawCol) == "table" and (rawCol.rim or rawCol.base or (rawCol[1] and rawCol))) or { 255, 210, 64 }
    local r, g, b = (col[1] or 255) / 255, (col[2] or 210) / 255, (col[3] or 64) / 255
    local isEmissive = (def.rarity == "legendary" or def.rarity == "rare")
    local rimMat = MakePBR(
        { min(1, r * 0.85 + 0.04), min(1, g * 0.85 + 0.04), min(1, b * 0.85 + 0.04) },
        0.90,
        0.22,
        isEmissive and { r * 0.18, g * 0.18, b * 0.18 } or { r * 0.04, g * 0.04, b * 0.04 }
    )

    local spr = Skin.SPRITES["coin_" .. tostring(kind)]
    local faceMat = spr and MakeTexturedUnlit(spr, true, { 0.86, 0.86, 0.86, 1.0 }) or nil
    if not faceMat then
        faceMat = MakePBR({ r, g, b }, 0.85, 0.24, { r * 0.12, g * 0.12, b * 0.12 })
    end
    M.coinMats[kind] = { rim = rimMat, face = faceMat }
    return M.coinMats[kind]
end

local function GetPegMat(kind)
    if M.pegMats[kind] then return M.pegMats[kind] end
    local pDef = Config.PEG_TYPES[kind] or Config.PEG_TYPES.normal
    local c = pDef.col or { 100, 210, 255 }
    local r, g, b = (c[1] or 100) / 255, (c[2] or 210) / 255, (c[3] or 255) / 255
    local mat = MakePBR({ r, g, b }, 0.35, 0.16, { r * 1.4, g * 1.4, b * 1.4 })
    M.pegMats[kind] = mat
    return mat
end

-- ----------------------------------------------------------------------------
-- 拼装 3D 街机推币机整柜（全部基于内置 Box/Cylinder/Sphere/Plane/Torus.mdl）
-- ----------------------------------------------------------------------------
local function BuildCabinet()
    local box, cyl, sphere, plane = M.models.box, M.models.cyl, M.models.sphere, M.models.plane
    local root = M.scene:CreateChild("Cabinet")
    M.cabinetNode = root

    -- 1. 展厅暗色反光圆形地台 + 机身主底座
    AddPart(root, "Podium", cyl, M.mats.deck, Vector3(0, -1.23, 0.0), Vector3(8.8, 0.08, 9.2), nil, false)
    AddPart(root, "Chassis", box, M.mats.chassis, Vector3(0, -0.60, 0.08), Vector3(3.26, 1.18, 3.24))

    -- 两侧厚重立柱
    AddPart(root, "ColL", box, M.mats.chassis, Vector3(-1.60, 0.82, 1.38), Vector3(0.24, 3.92, 0.56))
    AddPart(root, "ColR", box, M.mats.chassis, Vector3(1.60, 0.82, 1.38), Vector3(0.24, 3.92, 0.56))

    -- 顶部街机霓虹皇冠灯箱顶篷
    AddPart(root, "MarqueeBox",  box, M.mats.chassis,     Vector3(0, 2.78, 1.32),     Vector3(3.52, 0.34, 0.72))
    AddPart(root, "MarqueeCap",  box, M.mats.gold,        Vector3(0, 2.97, 1.32),     Vector3(3.58, 0.08, 0.78))
    AddPart(root, "MarqueeGlow", box, M.mats.neonPrimary, Vector3(0, 2.76, 0.94),     Vector3(2.96, 0.09, 0.08), nil, false)
    AddPart(root, "FinialL",     box, M.mats.gold,        Vector3(-1.60, 3.04, 1.32), Vector3(0.16, 0.16, 0.16))
    AddPart(root, "FinialR",     box, M.mats.gold,        Vector3(1.60, 3.04, 1.32),  Vector3(0.16, 0.16, 0.16))

    -- 2. 主推台拉丝钛金台面（顶面对齐 y = 0） + 透视导光条
    AddPart(root, "Deck", box, M.mats.deck, Vector3(0, -0.05, 0.0), Vector3(2.98, 0.10, 3.06))
    AddPart(root, "GridL", box, M.mats.neonPrimary, Vector3(-0.72, 0.004, 0.0),  Vector3(0.03, 0.015, 2.96), nil, false)
    AddPart(root, "GridC", box, M.mats.neonPrimary, Vector3(0.0, 0.004, 0.0),    Vector3(0.03, 0.015, 2.96), nil, false)
    AddPart(root, "GridR", box, M.mats.neonPrimary, Vector3(0.72, 0.004, 0.0),   Vector3(0.03, 0.015, 2.96), nil, false)
    AddPart(root, "GridH1",box, M.mats.neonPrimary, Vector3(0.0, 0.004, -0.70),  Vector3(2.88, 0.015, 0.03), nil, false)
    AddPart(root, "GridH2",box, M.mats.neonPrimary, Vector3(0.0, 0.004, 0.05),   Vector3(2.88, 0.015, 0.03), nil, false)

    -- 3. 前沿黄金悬崖收币唇 + 下部发光出币奖槽
    AddPart(root, "FrontLip",   box, M.mats.gold,          Vector3(0, 0.012, -1.52), Vector3(3.16, 0.07, 0.08))
    AddPart(root, "ChuteBody",  box, M.mats.chassis,       Vector3(0, -0.96, -1.68), Vector3(3.26, 0.42, 0.62))
    AddPart(root, "ChuteLip",   box, M.mats.gold,          Vector3(0, -0.74, -1.96), Vector3(3.18, 0.06, 0.12))
    AddPart(root, "ChuteGlow",  box, M.mats.chuteGold, Vector3(0, -0.75, -1.70), Vector3(2.74, 0.06, 0.44), nil, false)

    -- 4. 推台上段左右金属挡墙（z in [+1.50, -0.74]）
    AddPart(root, "SideWallL", box, M.mats.chrome,      Vector3(-1.49, 0.12, 0.38), Vector3(0.11, 0.24, 2.24))
    AddPart(root, "SideWallR", box, M.mats.chrome,      Vector3(1.49, 0.12, 0.38),  Vector3(0.11, 0.24, 2.24))
    AddPart(root, "SideGlowL", box, M.mats.neonPrimary, Vector3(-1.45, 0.24, 0.38), Vector3(0.04, 0.05, 2.20), nil, false)
    AddPart(root, "SideGlowR", box, M.mats.neonPrimary, Vector3(1.45, 0.24, 0.38),  Vector3(0.04, 0.05, 2.20), nil, false)

    -- 5. 上部落币区垂直内框柱
    AddPart(root, "UpperFrameL", box, M.mats.chrome,        Vector3(-1.44, 1.44, 1.38), Vector3(0.09, 2.36, 0.24))
    AddPart(root, "UpperFrameR", box, M.mats.chrome,        Vector3(1.44, 1.44, 1.38),  Vector3(0.09, 2.36, 0.24))
    AddPart(root, "UpperNeonL",  box, M.mats.neonSecondary, Vector3(-1.38, 1.44, 1.28), Vector3(0.045, 2.26, 0.05), nil, false)
    AddPart(root, "UpperNeonR",  box, M.mats.neonSecondary, Vector3(1.38, 1.44, 1.28),  Vector3(0.045, 2.26, 0.05), nil, false)

    -- 6. 透明亚克力展示防护侧玻璃
    AddPart(root, "GlassL", box, M.mats.glass, Vector3(-1.53, 0.35, 0.0), Vector3(0.025, 0.68, 3.06), nil, false)
    AddPart(root, "GlassR", box, M.mats.glass, Vector3(1.53, 0.35, 0.0),  Vector3(0.025, 0.68, 3.06), nil, false)

    -- 7. 3D 霓虹背板（Plane.mdl 默认法线 +Y，绕 X 旋 -90 度后法线朝 -Z 面向相机）
    M.backboardMat = MakeTexturedUnlit("image/machine/backdrop_act1.png", false, { 0.96, 0.96, 1.0, 1.0 })
        or MakePBR({ 0.08, 0.10, 0.22 }, 0.2, 0.7)
    M.backboardNode = AddPart(
        M.scene, "Backboard", plane, M.backboardMat,
        Vector3(0, 1.44, 1.49), Vector3(2.84, 1.0, 2.36), Quaternion(-90, Vector3.RIGHT), false
    )

    -- 8. 两侧动态激光护栏（z in [-0.74, -1.52]）
    M.guardMat = MakePBR({ 0.15, 0.95, 0.55 }, 0.3, 0.2, { 0.25, 1.4, 0.75 })
    M.leftGuardNode  = AddPart(M.scene, "LeftGuard",  box, M.guardMat, Vector3(-1.46, 0.08, -1.13), Vector3(0.07, 0.16, 0.78), nil, false)
    M.rightGuardNode = AddPart(M.scene, "RightGuard", box, M.guardMat, Vector3(1.46, 0.08, -1.13),  Vector3(0.07, 0.16, 0.78), nil, false)

    -- 9. 24 颗 3D 跑马灯珠（左 12 + 右 12）
    M.bulbLitMat = MakePBR({ 1.0, 0.90, 0.30 }, 0.1, 0.1, { 2.6, 2.1, 0.55 })
    M.bulbDimMat = MakePBR({ 0.18, 0.20, 0.32 }, 0.2, 0.4, { 0.04, 0.06, 0.12 })
    M.bulbs = {}
    for side = -1, 1, 2 do
        local bx = side * 1.56
        for i = 0, 11 do
            local _, bm = AddPart(
                M.scene, "Bulb_" .. side .. "_" .. i, sphere, M.bulbDimMat,
                Vector3(bx, 0.36 + i * 0.20, 1.12), Vector3(0.084, 0.084, 0.084), nil, false
            )
            M.bulbs[#M.bulbs + 1] = { model = bm, idx = i, side = side }
        end
    end
end

-- 构建 3D 往复推板 + 顶部摆动发射器 + 中奖移动门
local function BuildAnimatedMechanisms()
    local box, cyl = M.models.box, M.models.cyl

    -- 1. 推板：前缘紧贴局部 z = 0，板身向后延伸到 z = +1.40
    M.pusherNeonMat = MakePBR({ 1.0, 0.28, 0.72 }, 0.3, 0.2, { 2.2, 0.45, 1.3 })
    M.pusherNode = M.scene:CreateChild("Pusher")
    M.pusherNode.position = Vector3(0, 0.0, 0.90)
    AddPart(M.pusherNode, "Body", box, M.mats.pusherTop, Vector3(0, 0.115, 0.71),   Vector3(2.74, 0.21, 1.40))
    AddPart(M.pusherNode, "Cap",  box, M.mats.gold,      Vector3(0, 0.225, 0.04),   Vector3(2.76, 0.045, 0.08))
    AddPart(M.pusherNode, "Neon", box, M.pusherNeonMat,  Vector3(0, 0.115, -0.005), Vector3(2.72, 0.085, 0.04), nil, false)
    for k = -2, 2 do
        AddPart(M.pusherNode, "Rib" .. k, box, M.mats.chrome, Vector3(k * 0.52, 0.225, 0.72), Vector3(0.05, 0.02, 1.24))
    end

    -- 2. 顶部摆动发射炮塔
    M.launcherNode = M.scene:CreateChild("Launcher")
    M.launcherNode.position = Vector3(0, 2.48, 1.30)
    AddPart(M.launcherNode, "Pivot",  cyl, M.mats.gold,          Vector3(0, 0, 0),     Vector3(0.30, 0.14, 0.30), Quaternion(90, Vector3.RIGHT))
    AddPart(M.launcherNode, "Barrel", box, M.mats.chrome,        Vector3(0, -0.14, 0), Vector3(0.18, 0.26, 0.18))
    AddPart(M.launcherNode, "Muzzle", cyl, M.mats.neonSecondary, Vector3(0, -0.28, 0), Vector3(0.16, 0.08, 0.16), nil, false)

    -- 3. 移动中奖门
    M.gateNode = M.scene:CreateChild("JackpotGate")
    M.gateNode.position = Vector3(0, 0.51, 1.31)
    M.gateLeftNode  = AddPart(M.gateNode, "GateLeft",  box, M.mats.neonSecondary, Vector3(-0.32, 0, 0), Vector3(0.16, 0.22, 0.20))
    M.gateRightNode = AddPart(M.gateNode, "GateRight", box, M.mats.neonSecondary, Vector3(0.32, 0, 0),  Vector3(0.16, 0.22, 0.20))
    local beamMat = MakePBR({ 1.0, 0.85, 0.25 }, 0.1, 0.1, { 2.4, 1.85, 0.35 }, 0.55)
    M.gateBeamNode = AddPart(M.gateNode, "GateBeam", box, beamMat, Vector3(0, -0.02, 0), Vector3(1.0, 0.14, 0.06), nil, false)
end

local function BuildCoinPool()
    local cyl, plane = M.models.cyl, M.models.plane
    local initMats = GetCoinMaterials("gold")
    M.coinPool = {}
    for i = 1, S.MAX_COINS do
        local n = M.scene:CreateChild("Coin3D_" .. i)
        local _, rimSm  = AddPart(n, "Rim",  cyl,   initMats.rim,  Vector3(0, 0, 0),     Vector3(1.0, 0.24, 1.0))
        local _, faceSm = AddPart(n, "Face", plane, initMats.face, Vector3(0, 0.125, 0), Vector3(0.90, 1.0, 0.90))
        n:SetDeepEnabled(false)
        M.coinPool[i] = {
            node = n, rim = rimSm, face = faceSm, lastKind = "gold", enabled = false,
            lastDia = -1, lastZone = "", lastOnPusher = nil, lastX = -9999, lastY = -9999, lastZ = -9999, lastRot = -999,
        }
    end
end

local function SyncPegs3D(phys)
    local pegs = phys.pegs or {}
    local pegVer = phys.pegVersion or 0
    if pegVer ~= M.lastPegVer then
        M.lastPegVer = pegVer
        for _, pn in ipairs(M.pegNodes) do
            pn.node:Remove()
        end
        M.pegNodes = {}
        local cyl, sphere = M.models.cyl, M.models.sphere
        for i = 1, #pegs do
            local p = pegs[i]
            local pn = M.scene:CreateChild("Peg_" .. i)
            pn.position = LogicToWorld3D(p.x, p.y, "slot", 0, false)
            AddPart(pn, "Stem", cyl, M.mats.chrome, Vector3(0, 0, 0.06), Vector3(0.06, 0.18, 0.06), Quaternion(90, Vector3.RIGHT))
            local head = AddPart(pn, "Head", sphere, GetPegMat(p.kind), Vector3(0, 0, -0.04), Vector3(0.112, 0.112, 0.076))
            M.pegNodes[i] = { node = pn, head = head, flashDirty = false }
        end
    end

    for i = 1, #pegs do
        local p = pegs[i]
        local rec = M.pegNodes[i]
        if rec then
            local fl = p.flash or 0
            if fl > 0.01 then
                local sc = 0.112 * (1.0 + fl * 0.45)
                rec.head.scale = Vector3(sc, sc, sc * 0.68)
                rec.flashDirty = true
            elseif rec.flashDirty then
                rec.head.scale = Vector3(0.112, 0.112, 0.076)
                rec.flashDirty = false
            end
        end
    end
end

local function UpdateFastProjPlanes()
    if not M.cam then return end
    local p = M.cam
    local s00 = p:WorldToScreenPoint(LogicToWorld3D(56,  S.DECK_TOP_Y, "slot", 0, false))
    local s10 = p:WorldToScreenPoint(LogicToWorld3D(304, S.DECK_TOP_Y, "slot", 0, false))
    local s01 = p:WorldToScreenPoint(LogicToWorld3D(56,  S.SLOT_TOP,   "slot", 0, false))
    local s11 = p:WorldToScreenPoint(LogicToWorld3D(304, S.SLOT_TOP,   "slot", 0, false))
    M.projSlot = { s00.x, s00.y, s10.x, s10.y, s01.x, s01.y, s11.x, s11.y }

    local d00 = p:WorldToScreenPoint(LogicToWorld3D(180 - S.DECK_TOP_HALF, S.DECK_TOP_Y, "deck", 0, false))
    local d10 = p:WorldToScreenPoint(LogicToWorld3D(180 + S.DECK_TOP_HALF, S.DECK_TOP_Y, "deck", 0, false))
    local d01 = p:WorldToScreenPoint(LogicToWorld3D(180 - S.DECK_BOT_HALF, S.DECK_BOT_Y, "deck", 0, false))
    local d11 = p:WorldToScreenPoint(LogicToWorld3D(180 + S.DECK_BOT_HALF, S.DECK_BOT_Y, "deck", 0, false))
    M.projDeck = { d00.x, d00.y, d10.x, d10.y, d01.x, d01.y, d11.x, d11.y }
end

-- ----------------------------------------------------------------------------
-- 对外生命周期 API
-- ----------------------------------------------------------------------------
function Machine3D.Init(tycoon)
    M.active = false
    if not Scene or not renderer or not cache or not Viewport then
        return false
    end

    local box    = cache:GetResource("Model", "Models/Box.mdl")
    local cyl    = cache:GetResource("Model", "Models/Cylinder.mdl")
    local sphere = cache:GetResource("Model", "Models/Sphere.mdl")
    local plane  = cache:GetResource("Model", "Models/Plane.mdl")
    if not (box and cyl and sphere and plane) then
        return false
    end
    M.models = { box = box, cyl = cyl, sphere = sphere, plane = plane }

    local scene = Scene()
    scene:CreateComponent("Octree")
    M.scene = scene

    -- 轻量暗色霓虹 Zone（关闭 SSAO / BloomUE / 雾效等高开销后处理，大幅提升电脑/手机帧率）
    local zoneNode = scene:CreateChild("ArcadeZone")
    local zone = zoneNode:CreateComponent("Zone")
    zone.boundingBox = BoundingBox(Vector3(-200, -200, -200), Vector3(200, 200, 200))
    zone.ambientSource = AMBIENT_COLOR
    zone.ambientColor = Color(0.32, 0.36, 0.50)
    zone.ambientIntensity = 1.0
    zone.vignetteEnabled = false
    zone.autoExposureEnabled = false
    zone.ssaoIntensity = 0
    zone.bloomMode = BLOOM_MODE_LEGACY
    zone.bloomWeight = 0
    zone.bloomPlusEnabled = false
    zone.bloomUEIntensity = 0
    zone.ssrEnabled = false
    zone.ssgiEnabled = false
    zone.motionBlurEnabled = false
    zone.volumetricFogEnabled = false
    zone.depthFogEnable = false
    M.zone = zone

    -- 主方向光 + 1 盏前置高光点光（无实时阴影，大幅减少 Pass 数）
    local dlNode = scene:CreateChild("MainLight")
    dlNode.direction = Vector3(0.22, -0.84, 0.49):Normalized()
    local dl = dlNode:CreateComponent("Light")
    dl.lightType = LIGHT_DIRECTIONAL
    dl.color = Color(1.0, 0.96, 0.90)
    dl.brightness = 1.85
    dl.castShadows = false
    M.dirLight = dl

    M.ptLights = {}
    local plNode = scene:CreateChild("ArcadeLight_1")
    plNode.position = Vector3(0.0, 1.35, -1.65)
    local pl = plNode:CreateComponent("Light")
    pl.lightType = LIGHT_POINT
    pl.brightness = 1.65
    pl.range = 10.0
    pl.castShadows = false
    M.ptLights[1] = pl

    -- 相机与 Viewport(0)
    local camNode = scene:CreateChild("Camera3D")
    camNode.position = Vector3(0, 4.9, -6.9)
    camNode:LookAt(Vector3(0, 0.72, 0.06))
    local cam = camNode:CreateComponent("Camera")
    cam.fov = 45.0
    cam.nearClip = 0.1
    cam.farClip = 100.0
    cam.autoAspectRatio = true
    M.camNode = camNode
    M.cam = cam

    M.viewport = Viewport:new(scene, cam)
    renderer:SetViewport(0, M.viewport)

    -- 共享 PBR 材质表
    M.mats = {
        chassis       = MakePBR({ 0.08, 0.10, 0.18 }, 0.72, 0.36),
        deck          = MakePBR({ 0.12, 0.15, 0.28 }, 0.82, 0.26),
        pusherTop     = MakePBR({ 0.20, 0.26, 0.44 }, 0.88, 0.22),
        chrome        = MakePBR({ 0.76, 0.82, 0.92 }, 0.92, 0.18),
        gold          = MakePBR({ 0.94, 0.70, 0.16 }, 0.92, 0.20, { 0.06, 0.04, 0.01 }),
        neonPrimary   = MakePBR({ 0.18, 0.88, 1.0 }, 0.2, 0.2, { 0.22, 1.05, 1.25 }),
        neonSecondary = MakePBR({ 1.0, 0.25, 0.72 }, 0.2, 0.2, { 1.15, 0.28, 0.85 }),
        chuteGold     = MakePBR({ 0.95, 0.72, 0.18 }, 0.4, 0.25, { 0.65, 0.42, 0.08 }),
        glass         = MakePBR({ 0.55, 0.86, 1.0 }, 0.1, 0.06, nil, 0.14),
    }

    BuildCabinet()
    BuildAnimatedMechanisms()
    BuildCoinPool()

    M.lastTheme = -1
    M.lastThemeKey = ""
    M.lastBulbPhase = -1
    M.lastGuarded = nil
    M.lastCamKey = ""
    M.lastPegVer = -1
    M.active = true
    Machine3D.Update(0, tycoon, nil)
    print("[Machine3D] 3D PBR coin-pusher ready (optimized)")
    return true
end

function Machine3D.IsActive()
    return M.active == true
end

function Machine3D.Update(dt, tycoon, fx, timeSec)
    if not M.active or not tycoon or not tycoon.physics then return end
    local phys = tycoon.physics
    local themeIdx = min(3, max(1, tycoon.stageTheme or 1))
    local boostOn = (tycoon.adBoostLeft or 0) > 0
    local feverOn = (tycoon.feverActive == true)

    -- 1. 屏幕宽高自适应相机距离（仅参数变化时更新节点矩阵并刷新平面快速投影表）
    local w = graphics and graphics:GetWidth() or 360
    local h = graphics and graphics:GetHeight() or 640
    local aspect = max(0.42, w / max(1, h))
    local sx = fx and (fx.shakeX or 0) * 0.008 or 0
    local sy = fx and (fx.shakeY or 0) * 0.008 or 0
    local camKey = string.format("%.3f:%.3f:%.3f", aspect, sx, sy)
    if camKey ~= M.lastCamKey then
        M.lastCamKey = camKey
        local target = Vector3(0, 0.74, 0.06)
        local dist = (aspect < 0.72) and min(10.2, 5.15 / aspect) or max(6.4, min(7.6, 5.5 / aspect))
        local dir = Vector3(0, -0.49, 0.87):Normalized()
        M.camNode.position = target - dir * dist + Vector3(sx, sy, 0)
        M.camNode:LookAt(target + Vector3(sx * 0.4, sy * 0.4, 0))
        UpdateFastProjPlanes()
    end

    -- 2. 主题配色 & 背板贴图同步（仅变化时提交着色器参数）
    ApplyThemeColors(themeIdx, boostOn, feverOn)

    -- 3. 跑马灯珠波浪闪烁（仅相位跳转时更新材质）
    local phase = floor((timeSec or tycoon.clock or 0) * (feverOn and 12 or 5))
    if phase ~= M.lastBulbPhase then
        M.lastBulbPhase = phase
        for _, b in ipairs(M.bulbs) do
            local lit = ((b.idx + phase) % 3 == 0)
            b.model.material = lit and M.bulbLitMat or M.bulbDimMat
        end
    end

    -- 4. 动态护栏同步（仅开关状态切换时更新）
    local guarded = (phys.railGuard or 0) > 0.2
    if guarded ~= M.lastGuarded then
        M.lastGuarded = guarded
        local gScaleY = guarded and 0.22 or 0.06
        M.leftGuardNode.scale = Vector3(0.07, gScaleY, 0.78)
        M.rightGuardNode.scale = Vector3(0.07, gScaleY, 0.78)
        if guarded then
            SetMatColor(M.guardMat, { 0.16, 0.96, 0.56 }, 1.0)
            SetMatEmissive(M.guardMat, { 0.28, 1.5, 0.85 })
        else
            SetMatColor(M.guardMat, { 0.95, 0.28, 0.32 }, 1.0)
            SetMatEmissive(M.guardMat, { 0.7, 0.12, 0.15 })
        end
    end

    -- 5. 往复推板、发射器角度、移动中奖门位置同步
    local pusherFrontZ = 1.50 - ((phys.pusherY or S.PUSHER_Y_MIN) - S.DECK_TOP_Y) * 0.01
    M.pusherNode.position = Vector3(0, 0.0, pusherFrontZ)

    M.launcherNode.rotation = Quaternion(phys.launchAngleDeg or 0, Vector3.FORWARD)

    local gx = (((phys.gateX or 180) - 180) / 124.0) * 1.36
    local gHalfWorld = ((phys.gateClosed and 4 or (S.GATE_BASE_HALF * (phys.gateWidthScale or 1))) / 124.0) * 1.36
    M.gateNode.position = Vector3(gx, 0.51, 1.31)
    M.gateLeftNode.position = Vector3(-gHalfWorld - 0.09, 0, 0)
    M.gateRightNode.position = Vector3(gHalfWorld + 0.09, 0, 0)
    M.gateBeamNode:SetEnabled(not phys.gateClosed)
    if not phys.gateClosed then
        M.gateBeamNode.scale = Vector3(max(0.15, gHalfWorld * 2.0), 0.14, 0.06)
    end

    -- 6. 钉阵位置 & 撞击脉冲缩放（仅版本变化或闪光期提交）
    SyncPegs3D(phys)

    -- 7. 90 枚 3D 金属贴图硬币池脏检查更新（静止硬币零矩阵写回）
    local activeIds = phys.activeIds or {}
    local coins = phys.coins or {}
    local cnt = min(#M.coinPool, phys.activeCount or #activeIds)
    for i = 1, cnt do
        local c = coins[activeIds[i]]
        local slot = M.coinPool[i]
        if c and c.active then
            if not slot.enabled then
                slot.enabled = true
                slot.node:SetDeepEnabled(true)
            end
            local cx, cy, cz, czZone, cOnPush = c.x, c.y, c.z or 0, c.zone or "deck", c.onPusher == true
            if czZone ~= slot.lastZone or cOnPush ~= slot.lastOnPusher
                or (cx - slot.lastX) * (cx - slot.lastX) + (cy - slot.lastY) * (cy - slot.lastY) + (cz - slot.lastZ) * (cz - slot.lastZ) > 0.01 then
                slot.lastX, slot.lastY, slot.lastZ = cx, cy, cz
                slot.node.position = LogicToWorld3D(cx, cy, czZone, cz, cOnPush)
            end

            local dia = (c.r or S.COIN_RADIUS) * 2.0 * 0.0096
            if dia ~= slot.lastDia or czZone ~= slot.lastZone or c.isRain ~= slot.lastIsRain then
                slot.lastDia = dia
                slot.lastIsRain = c.isRain
                local thickScale = dia * (c.isRain and 0.92 or 1.05)
                slot.node.scale = Vector3(dia, thickScale, dia)
            end

            local crot = c.rot or 0
            if czZone ~= slot.lastZone or (crot - slot.lastRot) * (crot - slot.lastRot) > 0.0004 then
                slot.lastRot = crot
                local rotDeg = math.deg(crot)
                if czZone == "slot" then
                    slot.node.rotation = Quaternion(-90, Vector3.RIGHT) * Quaternion(rotDeg, Vector3.UP)
                elseif czZone == "dropping" then
                    local prog = max(0, min(1, (cy - S.DECK_BOT_Y) / max(1, S.DROP_END_Y - S.DECK_BOT_Y)))
                    slot.node.rotation = Quaternion(prog * 82, Vector3.RIGHT) * Quaternion(rotDeg, Vector3.UP)
                else
                    slot.node.rotation = Quaternion(rotDeg, Vector3.UP)
                end
            end
            slot.lastZone = czZone
            slot.lastOnPusher = cOnPush

            local k = c.kind or "gold"
            if slot.lastKind ~= k then
                slot.lastKind = k
                local cm = GetCoinMaterials(k)
                slot.rim:SetMaterial(cm.rim)
                slot.face:SetMaterial(cm.face)
            end
        else
            if slot.enabled then
                slot.enabled = false
                slot.node:SetDeepEnabled(false)
            end
        end
    end
    for i = cnt + 1, #M.coinPool do
        local slot = M.coinPool[i]
        if slot.enabled then
            slot.enabled = false
            slot.node:SetDeepEnabled(false)
        end
    end
end

function Machine3D.ProjectFast(lx, ly, uiW, uiH)
    if not M.active then return nil end
    if ly <= S.DECK_TOP_Y and M.projSlot then
        local p = M.projSlot
        local tx = max(0, min(1, (lx - 56) / 248))
        local ty = max(0, min(1, (S.DECK_TOP_Y - ly) / max(1, S.DECK_TOP_Y - S.SLOT_TOP)))
        local bx = p[1] + tx * (p[3] - p[1])
        local by = p[2] + tx * (p[4] - p[2])
        local topX = p[5] + tx * (p[7] - p[5])
        local topY = p[6] + tx * (p[8] - p[6])
        return (bx + ty * (topX - bx)) * uiW, (by + ty * (topY - by)) * uiH
    elseif M.projDeck then
        local p = M.projDeck
        local ty = max(0, min(1.15, (ly - S.DECK_TOP_Y) / max(1, S.DECK_BOT_Y - S.DECK_TOP_Y)))
        local hw = Physics.TrapezoidHalfW(ly)
        local tx = max(0, min(1, (lx - (180 - hw)) / max(1, hw * 2)))
        local bx = p[1] + tx * (p[3] - p[1])
        local by = p[2] + tx * (p[4] - p[2])
        local topX = p[5] + tx * (p[7] - p[5])
        local topY = p[6] + tx * (p[8] - p[6])
        return (bx + ty * (topX - bx)) * uiW, (by + ty * (topY - by)) * uiH
    end
    return Machine3D.WorldToUi(lx, ly, (ly <= S.DECK_TOP_Y) and "slot" or "deck", 0, uiW, uiH)
end

function Machine3D.WorldToUi(lx, ly, zone, lz, uiW, uiH)
    if not M.active or not M.cam then return nil end
    local wp = LogicToWorld3D(lx, ly, zone or "deck", lz or 0, false)
    local pt = M.cam:WorldToScreenPoint(wp)
    return pt.x * uiW, pt.y * uiH
end

function Machine3D.Shutdown()
    M.active = false
    M.scene = nil
    M.viewport = nil
    M.camNode = nil
    M.cam = nil
    M.coinPool = {}
    M.pegNodes = {}
    M.bulbs = {}
    M.coinMats = {}
    M.pegMats = {}
    M.projSlot = nil
    M.projDeck = nil
end

return Machine3D
