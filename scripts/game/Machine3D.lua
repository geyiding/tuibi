-- ============================================================================
-- Machine3D.lua  《推币机的狂欢》真 3D PBR 街机推币机舞台（UrhoX + PropBuilder）
--   · 使用 PropBuilder / ProceduralGeometry 打造多材质金属倒角街机柜、往复推板、
--     摆动发射炮口、移动中奖门、发光钉阵、24 颗3D跑马灯球、亚克力护玻璃与 140 枚立体金属贴图币
--   · 纯无头单测环境下安全降级（Init 返回 false，不影响任何逻辑测试）
-- ============================================================================

local Config = require("game/Config")
local Physics = require("game/Physics")
local Skin = require("game/Skin")

local S = Config.STAGE
local floor, min, max, abs, sin, cos, sqrt = math.floor, math.min, math.max, math.abs, math.sin, math.cos, math.sqrt

local Machine3D = {}

-- 持有强引用防止 Scene / Camera / Models 被 Lua GC 回收
local M = {
    active = false,
    scene = nil,
    viewport = nil,
    camNode = nil,
    cam = nil,
    zone = nil,
    dirLight = nil,
    ptLights = {},
    mats = {},
    coinMats = {},
    pegMats = {},
    coinModel = nil,
    pegHeadModel = nil,
    pegStemModel = nil,
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
    coinPool = {},
    lastTheme = -1,
    bulbLitMat = nil,
    bulbDimMat = nil,
    lastShakeX = 0,
    lastShakeY = 0,
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
    return mat
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
    local c1, c2
    if themeIdx == 2 then
        c1 = { 1.0, 0.72, 0.16 } -- 黄金熔炉：暖金 + 烈焰橙
        c2 = { 1.0, 0.34, 0.12 }
    elseif themeIdx == 3 then
        c1 = { 0.72, 0.42, 1.0 } -- 赛博金库：魅紫 + 曜金
        c2 = { 1.0, 0.82, 0.22 }
    else
        c1 = { 0.18, 0.88, 1.0 } -- 霓虹游艺厅：电青 + 霓虹粉
        c2 = { 1.0, 0.25, 0.70 }
    end

    if feverOn then
        c1 = { 1.0, 0.25, 0.75 }
        c2 = { 1.0, 0.86, 0.22 }
    elseif boostOn then
        c2 = { 1.0, 0.86, 0.22 }
    end

    local pulse = (feverOn or boostOn) and 2.8 or 1.85
    SetMatEmissive(M.mats.neonPrimary, { c1[1] * pulse, c1[2] * pulse, c1[3] * pulse })
    SetMatColor(M.mats.neonPrimary, c1, 1.0)
    SetMatEmissive(M.mats.neonSecondary, { c2[1] * pulse, c2[2] * pulse, c2[3] * pulse })
    SetMatColor(M.mats.neonSecondary, c2, 1.0)
    SetMatEmissive(M.pusherNeonMat, { c2[1] * pulse, c2[2] * pulse, c2[3] * pulse })
    SetMatColor(M.pusherNeonMat, c2, 1.0)

    if M.ptLights[1] then M.ptLights[1].color = Color(c1[1], c1[2], c1[3]) end
    if M.ptLights[2] then M.ptLights[2].color = Color(c2[1], c2[2], c2[3]) end
    if M.ptLights[3] then M.ptLights[3].color = Color(1.0, 0.84, 0.35) end

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

-- 构建 3D 硬币共享模型（斜角厚金属边 + 顶部贴图盖 + 底部盖，两套子几何材质槽 0/1）
local function BuildSharedModels()
    local body = CylinderGeometry(0.50, 0.50, 0.22, 24)
    local topRim = TorusGeometry(0.47, 0.042, 8, 24):ApplyQuaternion(Quaternion(90, Vector3.RIGHT)):Translate(0, 0.10, 0)
    local botRim = TorusGeometry(0.47, 0.036, 8, 24):ApplyQuaternion(Quaternion(90, Vector3.RIGHT)):Translate(0, -0.10, 0)
    local rimMerged = MergeGeometries({ body, topRim, botRim }, false)

    -- CircleGeometry 默认竖直面朝 -Z，绕 X 旋 +90° 后法线朝 +Y（贴合桌面朝上币面）
    local capTop = CircleGeometry(0.45, 24):ApplyQuaternion(Quaternion(90, Vector3.RIGHT)):Translate(0, 0.114, 0)
    local capBot = CircleGeometry(0.45, 24):ApplyQuaternion(Quaternion(-90, Vector3.RIGHT)):Translate(0, -0.114, 0)
    local capMerged = MergeGeometries({ capTop, capBot }, false)

    local combined = MergeGeometries({ rimMerged, capMerged }, true)
    M.coinModel = combined:ToModel()

    M.pegStemModel = CylinderGeometry(0.028, 0.036, 0.18, 12):ApplyQuaternion(Quaternion(90, Vector3.RIGHT)):ToModel()
    M.pegHeadModel = SphereGeometry(0.056, 14, 10):Scale(1.0, 1.0, 0.68):ToModel()
end

local function GetCoinMaterials(kind)
    if M.coinMats[kind] then return M.coinMats[kind] end
    local def = Config.COINS[kind] or Config.COINS.gold
    local col = def.color or { 255, 210, 64 }
    local r, g, b = col[1] / 255, col[2] / 255, col[3] / 255
    local isEmissive = (def.rarity == "legendary" or def.rarity == "rare")
    local rimMat = MakePBR(
        { min(1, r * 0.95 + 0.1), min(1, g * 0.95 + 0.1), min(1, b * 0.95 + 0.1) },
        0.92,
        0.18,
        isEmissive and { r * 0.35, g * 0.35, b * 0.35 } or { r * 0.08, g * 0.08, b * 0.08 }
    )

    local spr = Skin.SPRITES["coin_" .. tostring(kind)]
    local faceMat = spr and MakeTexturedUnlit(spr, true, { 1.0, 1.0, 1.0, 1.0 }) or nil
    if not faceMat then
        faceMat = MakePBR({ r, g, b }, 0.85, 0.24, { r * 0.20, g * 0.20, b * 0.20 })
    end
    M.coinMats[kind] = { rim = rimMat, face = faceMat }
    return M.coinMats[kind]
end

local function GetPegMat(kind)
    if M.pegMats[kind] then return M.pegMats[kind] end
    local pDef = Config.PEG_TYPES[kind] or Config.PEG_TYPES.normal
    local c = pDef.col or { 100, 210, 255 }
    local r, g, b = c[1] / 255, c[2] / 255, c[3] / 255
    local mat = MakePBR({ r, g, b }, 0.35, 0.16, { r * 1.4, g * 1.4, b * 1.4 })
    M.pegMats[kind] = mat
    return mat
end

-- ----------------------------------------------------------------------------
-- 拼装 3D 街机推币机整柜（PropBuilder 按材质合批）
-- ----------------------------------------------------------------------------
local function BuildCabinet(PropBuilder)
    local b = PropBuilder.new()

    -- 1. 底部厚重深钛合金机身基座 (y in [-1.20, 0]) + 霓虹反光展厅底座地板
    b:Add("deck",    CylinderGeometry(4.4, 4.6, 0.08, 36):Translate(0, -1.23, 0.0))
    b:Add("chassis", ChamferBoxGeometry(3.26, 1.18, 3.24, 0.04):Translate(0, -0.60, 0.08))
    -- 两侧厚重立柱与护翼
    b:Add("chassis", ChamferBoxGeometry(0.24, 3.92, 0.56, 0.03):Translate(-1.60, 0.82, 1.38))
    b:Add("chassis", ChamferBoxGeometry(0.24, 3.92, 0.56, 0.03):Translate(1.60, 0.82, 1.38))
    -- 顶部街机霓虹皇冠灯箱顶篷
    b:Add("chassis", ChamferBoxGeometry(3.52, 0.34, 0.72, 0.04):Translate(0, 2.78, 1.32))
    b:Add("gold",    ChamferBoxGeometry(3.58, 0.08, 0.78, 0.02):Translate(0, 2.97, 1.32))
    b:Add("neonPrimary", ChamferBoxGeometry(2.96, 0.09, 0.08, 0.015):Translate(0, 2.76, 0.94), { castShadows = false })
    b:Add("gold",    ChamferBoxGeometry(0.16, 0.16, 0.16, 0.03):Translate(-1.60, 3.04, 1.32))
    b:Add("gold",    ChamferBoxGeometry(0.16, 0.16, 0.16, 0.03):Translate(1.60, 3.04, 1.32))

    -- 2. 主推台拉丝钛金台面（顶面对齐 y = 0）
    b:Add("deck", ChamferBoxGeometry(2.98, 0.10, 3.06, 0.02):Translate(0, -0.05, 0.0))
    -- 台面透视引导霓虹镶边
    b:Add("neonPrimary", BoxGeometry(0.03, 0.015, 2.96):Translate(-0.72, 0.004, 0.0), { castShadows = false })
    b:Add("neonPrimary", BoxGeometry(0.03, 0.015, 2.96):Translate(0.72, 0.004, 0.0), { castShadows = false })
    b:Add("neonPrimary", BoxGeometry(0.03, 0.015, 2.96):Translate(0.0, 0.004, 0.0), { castShadows = false })
    b:Add("neonPrimary", BoxGeometry(2.88, 0.015, 0.03):Translate(0.0, 0.004, -0.70), { castShadows = false })
    b:Add("neonPrimary", BoxGeometry(2.88, 0.015, 0.03):Translate(0.0, 0.004, 0.05), { castShadows = false })

    -- 3. 前沿黄金悬崖收币唇 + 下部发光出币奖槽
    b:Add("gold", ChamferBoxGeometry(3.16, 0.07, 0.08, 0.02):Translate(0, 0.012, -1.52))
    b:Add("chassis", ChamferBoxGeometry(3.26, 0.42, 0.62, 0.03):Translate(0, -0.96, -1.68))
    b:Add("gold", ChamferBoxGeometry(3.18, 0.06, 0.12, 0.015):Translate(0, -0.74, -1.96))
    b:Add("neonSecondary", BoxGeometry(2.74, 0.06, 0.44):Translate(0, -0.75, -1.70), { castShadows = false })

    -- 4. 推台上段左右金属挡墙（z in [+1.50, -0.74]，留出前方侧漏段）
    b:Add("chrome", ChamferBoxGeometry(0.11, 0.24, 2.24, 0.02):Translate(-1.49, 0.12, 0.38))
    b:Add("chrome", ChamferBoxGeometry(0.11, 0.24, 2.24, 0.02):Translate(1.49, 0.12, 0.38))
    b:Add("neonPrimary", BoxGeometry(0.04, 0.05, 2.20):Translate(-1.45, 0.24, 0.38), { castShadows = false })
    b:Add("neonPrimary", BoxGeometry(0.04, 0.05, 2.20):Translate(1.45, 0.24, 0.38), { castShadows = false })

    -- 5. 上部落币区垂直内框柱
    b:Add("chrome", ChamferBoxGeometry(0.09, 2.36, 0.24, 0.018):Translate(-1.44, 1.44, 1.38))
    b:Add("chrome", ChamferBoxGeometry(0.09, 2.36, 0.24, 0.018):Translate(1.44, 1.44, 1.38))
    b:Add("neonSecondary", BoxGeometry(0.045, 2.26, 0.05):Translate(-1.38, 1.44, 1.28), { castShadows = false })
    b:Add("neonSecondary", BoxGeometry(0.045, 2.26, 0.05):Translate(1.38, 1.44, 1.28), { castShadows = false })

    -- 6. 透明亚克力展示防护侧玻璃（超低 alpha 不遮挡币堆）
    b:Add("glass", BoxGeometry(0.025, 0.68, 3.06):Translate(-1.53, 0.35, 0.0), { castShadows = false })
    b:Add("glass", BoxGeometry(0.025, 0.68, 3.06):Translate(1.53, 0.35, 0.0), { castShadows = false })

    local prop = b:Build()
    M.cabinetNode = M.scene:CreateChild("Cabinet")
    PropBuilder.Attach(M.cabinetNode, prop, M.mats)

    -- 7. 3D 霓虹背板（随阶段换幕 1/2/3 自动换贴图）
    M.backboardNode = M.scene:CreateChild("Backboard")
    M.backboardNode.position = Vector3(0, 1.44, 1.49)
    local bbModel = M.backboardNode:CreateComponent("StaticModel")
    bbModel.model = PlaneGeometry(2.84, 2.36):ToModel()
    bbModel.castShadows = false
    M.backboardMat = MakeTexturedUnlit("image/machine/backdrop_act1.png", false, { 0.96, 0.96, 1.0, 1.0 })
        or MakePBR({ 0.08, 0.10, 0.22 }, 0.2, 0.7)
    bbModel.material = M.backboardMat

    -- 8. 两侧动态激光护栏（z in [-0.74, -1.52]）
    M.guardMat = MakePBR({ 0.15, 0.95, 0.55 }, 0.3, 0.2, { 0.25, 1.4, 0.75 })
    local guardGeo = ChamferBoxGeometry(0.07, 0.16, 0.78, 0.015):ToModel()
    M.leftGuardNode = M.scene:CreateChild("LeftGuard")
    M.leftGuardNode.position = Vector3(-1.46, 0.08, -1.13)
    local lgm = M.leftGuardNode:CreateComponent("StaticModel")
    lgm.model = guardGeo; lgm.material = M.guardMat; lgm.castShadows = false

    M.rightGuardNode = M.scene:CreateChild("RightGuard")
    M.rightGuardNode.position = Vector3(1.46, 0.08, -1.13)
    local rgm = M.rightGuardNode:CreateComponent("StaticModel")
    rgm.model = guardGeo; rgm.material = M.guardMat; rgm.castShadows = false

    -- 9. 24 颗 3D 跑马灯珠（左 12 + 右 12）
    local bulbModel = SphereGeometry(0.042, 10, 8):ToModel()
    M.bulbLitMat = MakePBR({ 1.0, 0.90, 0.30 }, 0.1, 0.1, { 2.6, 2.1, 0.55 })
    M.bulbDimMat = MakePBR({ 0.18, 0.20, 0.32 }, 0.2, 0.4, { 0.04, 0.06, 0.12 })
    M.bulbs = {}
    for side = -1, 1, 2 do
        local bx = side * 1.56
        for i = 0, 11 do
            local bn = M.scene:CreateChild("Bulb_" .. side .. "_" .. i)
            bn.position = Vector3(bx, 0.36 + i * 0.20, 1.12)
            local bm = bn:CreateComponent("StaticModel")
            bm.model = bulbModel
            bm.material = M.bulbDimMat
            bm.castShadows = false
            M.bulbs[#M.bulbs + 1] = { model = bm, idx = i, side = side }
        end
    end
end

-- 构建 3D 往复推板 + 顶部摆动发射器 + 中奖移动门
local function BuildAnimatedMechanisms(PropBuilder)
    -- 1. 推板：前缘紧贴局部 z = 0，板身向后延伸到 z = +1.40（从背板底滑出）
    M.pusherNeonMat = MakePBR({ 1.0, 0.28, 0.72 }, 0.3, 0.2, { 2.2, 0.45, 1.3 })
    local pb = PropBuilder.new()
    pb:Add("deck", ChamferBoxGeometry(2.74, 0.21, 1.40, 0.025):Translate(0, 0.115, 0.71))
    pb:Add("gold", ChamferBoxGeometry(2.76, 0.045, 0.08, 0.012):Translate(0, 0.225, 0.04))
    pb:Add("neon", BoxGeometry(2.72, 0.085, 0.04):Translate(0, 0.115, -0.005), { castShadows = false })
    -- 推板顶部装饰筋条
    for k = -2, 2 do
        pb:Add("chrome", BoxGeometry(0.05, 0.02, 1.24):Translate(k * 0.52, 0.225, 0.72))
    end
    local pProp = pb:Build()
    M.pusherNode = M.scene:CreateChild("Pusher")
    M.pusherNode.position = Vector3(0, 0.0, 0.90)
    PropBuilder.Attach(M.pusherNode, pProp, {
        deck = M.mats.pusherTop,
        gold = M.mats.gold,
        neon = M.pusherNeonMat,
        chrome = M.mats.chrome,
    })

    -- 2. 顶部摆动发射炮塔
    local lb = PropBuilder.new()
    lb:Add("gold",   CylinderGeometry(0.14, 0.16, 0.14, 18):ApplyQuaternion(Quaternion(90, Vector3.RIGHT)))
    lb:Add("chrome", ChamferBoxGeometry(0.18, 0.26, 0.18, 0.025):Translate(0, -0.14, 0))
    lb:Add("neon",   CylinderGeometry(0.075, 0.09, 0.08, 14):Translate(0, -0.28, 0), { castShadows = false })
    local lProp = lb:Build()
    M.launcherNode = M.scene:CreateChild("Launcher")
    M.launcherNode.position = Vector3(0, 2.48, 1.30)
    PropBuilder.Attach(M.launcherNode, lProp, {
        gold = M.mats.gold,
        chrome = M.mats.chrome,
        neon = M.mats.neonSecondary,
    })

    -- 3. 移动中奖门
    M.gateNode = M.scene:CreateChild("JackpotGate")
    M.gateNode.position = Vector3(0, 0.51, 1.31)
    local pillarModel = ChamferBoxGeometry(0.16, 0.22, 0.20, 0.02):ToModel()
    M.gateLeftNode = M.gateNode:CreateChild("GateLeft")
    M.gateLeftNode.position = Vector3(-0.32, 0, 0)
    local gl = M.gateLeftNode:CreateComponent("StaticModel")
    gl.model = pillarModel; gl.material = M.mats.neonSecondary

    M.gateRightNode = M.gateNode:CreateChild("GateRight")
    M.gateRightNode.position = Vector3(0.32, 0, 0)
    local gr = M.gateRightNode:CreateComponent("StaticModel")
    gr.model = pillarModel; gr.material = M.mats.neonSecondary

    M.gateBeamNode = M.gateNode:CreateChild("GateBeam")
    M.gateBeamNode.position = Vector3(0, -0.02, 0)
    local gb = M.gateBeamNode:CreateComponent("StaticModel")
    gb.model = BoxGeometry(1.0, 0.14, 0.06):ToModel()
    gb.material = MakePBR({ 1.0, 0.85, 0.25 }, 0.1, 0.1, { 2.4, 1.85, 0.35 }, 0.55)
    gb.castShadows = false
end

local function BuildCoinPool()
    M.coinPool = {}
    for i = 1, S.MAX_COINS do
        local n = M.scene:CreateChild("Coin3D_" .. i)
        n:SetEnabled(false)
        local sm = n:CreateComponent("StaticModel")
        sm.model = M.coinModel
        sm.castShadows = true
        local mats = GetCoinMaterials("gold")
        sm:SetMaterial(0, mats.rim)
        sm:SetMaterial(1, mats.face)
        M.coinPool[i] = { node = n, model = sm, lastKind = "gold" }
    end
end

local function SyncPegs3D(phys)
    local pegs = phys.pegs or {}
    local sigParts = { tostring(#pegs) }
    for i = 1, #pegs do sigParts[#sigParts + 1] = pegs[i].kind end
    local sig = table.concat(sigParts, ",")

    if sig ~= M.pegSig then
        M.pegSig = sig
        for _, pn in ipairs(M.pegNodes) do
            pn.node:Remove()
        end
        M.pegNodes = {}
        for i = 1, #pegs do
            local p = pegs[i]
            local pn = M.scene:CreateChild("Peg_" .. i)
            pn.position = LogicToWorld3D(p.x, p.y, "slot", 0, false)
            local stem = pn:CreateChild("Stem")
            stem.position = Vector3(0, 0, 0.06)
            local sm1 = stem:CreateComponent("StaticModel")
            sm1.model = M.pegStemModel; sm1.material = M.mats.chrome; sm1.castShadows = false

            local head = pn:CreateChild("Head")
            head.position = Vector3(0, 0, -0.04)
            local sm2 = head:CreateComponent("StaticModel")
            sm2.model = M.pegHeadModel; sm2.material = GetPegMat(p.kind); sm2.castShadows = true

            M.pegNodes[i] = { node = pn, head = head }
        end
    end

    for i = 1, #pegs do
        local p = pegs[i]
        local rec = M.pegNodes[i]
        if rec then
            local sc = 1.0 + (p.flash or 0) * 0.45
            rec.head.scale = Vector3(sc, sc, sc)
        end
    end
end

-- ----------------------------------------------------------------------------
-- 对外生命周期 API
-- ----------------------------------------------------------------------------
function Machine3D.Init(tycoon)
    M.active = false
    if not Scene or not renderer or not cache or not Viewport then
        return false
    end
    local ok, PropBuilder = pcall(require, "urhox-libs/Geometry/PropBuilder")
    if not ok or not PropBuilder then
        return false
    end

    local scene = Scene()
    scene:CreateComponent("Octree")
    M.scene = scene

    -- 使用 Midnight 预设氛围并关闭暗角/自动曝光确保透亮度与币面高光清晰
    local lgFile = cache:GetResource("XMLFile", "LightGroup/Midnight.xml")
    if lgFile then
        local lgNode = scene:CreateChild("LightGroup")
        lgNode:LoadXML(lgFile:GetRoot())
        local zone = lgNode:GetComponent("Zone", true)
        if zone then
            zone.fogColor = Color(0.03, 0.04, 0.09)
            zone.depthFogStart = 20.0
            zone.depthFogEnd = 70.0
            zone.vignetteEnabled = false
            zone.autoExposureEnabled = false
            M.zone = zone
        end
    end

    -- 主高光方向光 + 3 盏街机气氛点光
    local dlNode = scene:CreateChild("MainLight")
    dlNode.direction = Vector3(0.22, -0.84, 0.49):Normalized()
    local dl = dlNode:CreateComponent("Light")
    dl.lightType = LIGHT_DIRECTIONAL
    dl.color = Color(1.0, 0.96, 0.90)
    dl.brightness = 2.6
    dl.castShadows = true
    M.dirLight = dl

    M.ptLights = {}
    local ptPos = { Vector3(-1.85, 1.95, -0.15), Vector3(1.85, 1.95, -0.15), Vector3(0.0, 0.95, -2.15) }
    for idx, pos in ipairs(ptPos) do
        local plNode = scene:CreateChild("ArcadeLight_" .. idx)
        plNode.position = pos
        local pl = plNode:CreateComponent("Light")
        pl.lightType = LIGHT_POINT
        pl.brightness = (idx == 3) and 4.2 or 3.6
        pl.range = 12.0
        pl.castShadows = false
        M.ptLights[idx] = pl
    end

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
        deck          = MakePBR({ 0.12, 0.15, 0.28 }, 0.82, 0.24),
        pusherTop     = MakePBR({ 0.20, 0.26, 0.44 }, 0.88, 0.22),
        chrome        = MakePBR({ 0.78, 0.84, 0.94 }, 0.94, 0.16),
        gold          = MakePBR({ 1.0, 0.78, 0.22 }, 0.95, 0.16, { 0.18, 0.12, 0.02 }),
        neonPrimary   = MakePBR({ 0.18, 0.88, 1.0 }, 0.2, 0.2, { 0.35, 1.8, 2.2 }),
        neonSecondary = MakePBR({ 1.0, 0.25, 0.72 }, 0.2, 0.2, { 2.0, 0.45, 1.4 }),
        glass         = MakePBR({ 0.55, 0.86, 1.0 }, 0.1, 0.06, nil, 0.14),
    }

    BuildSharedModels()
    BuildCabinet(PropBuilder)
    BuildAnimatedMechanisms(PropBuilder)
    BuildCoinPool()

    M.lastTheme = -1
    M.active = true
    Machine3D.Update(0, tycoon, nil)
    print("[Machine3D] 3D PBR coin-pusher ready")
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

    -- 1. 屏幕宽高自适应相机距离，确保竖屏手机左右霓虹立柱与前沿完整入框不裁切
    local w = graphics and graphics:GetWidth() or 360
    local h = graphics and graphics:GetHeight() or 640
    local aspect = max(0.42, w / max(1, h))
    local target = Vector3(0, 0.74, 0.06)
    local dist = (aspect < 0.72) and min(10.2, 5.15 / aspect) or max(6.4, min(7.6, 5.5 / aspect))
    local sx = fx and (fx.shakeX or 0) * 0.008 or 0
    local sy = fx and (fx.shakeY or 0) * 0.008 or 0
    local dir = Vector3(0, -0.49, 0.87):Normalized()
    M.camNode.position = target - dir * dist + Vector3(sx, sy, 0)
    M.camNode:LookAt(target + Vector3(sx * 0.4, sy * 0.4, 0))

    -- 2. 主题配色 & 背板贴图同步
    ApplyThemeColors(themeIdx, boostOn, feverOn)

    -- 3. 跑马灯珠波浪闪烁
    local phase = floor((timeSec or tycoon.clock or 0) * (feverOn and 12 or 5))
    for _, b in ipairs(M.bulbs) do
        local lit = ((b.idx + phase) % 3 == 0)
        b.model.material = lit and M.bulbLitMat or M.bulbDimMat
    end

    -- 4. 动态护栏同步
    local guarded = (phys.railGuard or 0) > 0.2
    local gScaleY = guarded and 1.25 or 0.35
    M.leftGuardNode.scale = Vector3(1, gScaleY, 1)
    M.rightGuardNode.scale = Vector3(1, gScaleY, 1)
    if guarded then
        SetMatColor(M.guardMat, { 0.16, 0.96, 0.56 }, 1.0)
        SetMatEmissive(M.guardMat, { 0.28, 1.5, 0.85 })
    else
        SetMatColor(M.guardMat, { 0.95, 0.28, 0.32 }, 1.0)
        SetMatEmissive(M.guardMat, { 0.7, 0.12, 0.15 })
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
        M.gateBeamNode.scale = Vector3(max(0.15, gHalfWorld * 2.0), 1, 1)
    end

    -- 6. 钉阵位置 & 撞击脉冲缩放
    SyncPegs3D(phys)

    -- 7. 140 枚 3D 金属贴图硬币池更新（零分配）
    local activeIds = phys.activeIds or {}
    local coins = phys.coins or {}
    local cnt = min(#M.coinPool, phys.activeCount or #activeIds)
    for i = 1, cnt do
        local c = coins[activeIds[i]]
        local slot = M.coinPool[i]
        if c and c.active then
            slot.node:SetEnabled(true)
            local wp = LogicToWorld3D(c.x, c.y, c.zone, c.z, c.onPusher)
            slot.node.position = wp

            local dia = (c.r or S.COIN_RADIUS) * 2.0 * 0.0108
            local thickScale = dia * (c.isRain and 0.92 or 1.05)
            slot.node.scale = Vector3(dia, thickScale, dia)

            local rotDeg = math.deg(c.rot or 0)
            if c.zone == "slot" then
                slot.node.rotation = Quaternion(-90, Vector3.RIGHT) * Quaternion(rotDeg, Vector3.UP)
            elseif c.zone == "dropping" then
                local prog = max(0, min(1, (c.y - S.DECK_BOT_Y) / max(1, S.DROP_END_Y - S.DECK_BOT_Y)))
                slot.node.rotation = Quaternion(prog * 82, Vector3.RIGHT) * Quaternion(rotDeg, Vector3.UP)
            else
                slot.node.rotation = Quaternion(rotDeg, Vector3.UP)
            end

            local k = c.kind or "gold"
            if slot.lastKind ~= k then
                slot.lastKind = k
                local cm = GetCoinMaterials(k)
                slot.model:SetMaterial(0, cm.rim)
                slot.model:SetMaterial(1, cm.face)
            end
        else
            slot.node:SetEnabled(false)
        end
    end
    for i = cnt + 1, #M.coinPool do
        M.coinPool[i].node:SetEnabled(false)
    end
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
end

return Machine3D
