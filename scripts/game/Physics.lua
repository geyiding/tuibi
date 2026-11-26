-- ============================================================================
-- Physics.lua  纯 Lua 2D 推币机与钉阵物理引擎（零引擎依赖，lupa 可直接压测）
--   · 预分配 MAX_COINS = 110 扁平对象池 + 12×16 空间哈希网格（零每帧建表）
--   · 顶部摆动发射 → 钉阵碰撞 → 往复斜口幸运门 → 2.5D 梯形推台多米诺挤压
--   · 支持特殊功能钉、狂欢金币雨、侧漏保护、防卡死保险丝、满台溢出超频
-- ============================================================================

local Config = require("game/Config")

local S = Config.STAGE
local floor, min, max, abs, sqrt, sin, cos, pi =
    math.floor, math.min, math.max, math.abs, math.sqrt, math.sin, math.cos, math.pi

local Physics = {}
Physics.__index = Physics

local GRID_COLS = 10
local GRID_ROWS = 10
local GRID_CELLS = GRID_COLS * GRID_ROWS
local TWO_PI = pi * 2

function Physics.TrapezoidHalfW(y)
    local t = (y - S.DECK_TOP_Y) / (S.DECK_BOT_Y - S.DECK_TOP_Y)
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    return S.DECK_TOP_HALF + (S.DECK_BOT_HALF - S.DECK_TOP_HALF) * t
end

function Physics.New(callbacks)
    local self = setmetatable({}, Physics)
    self.cb = callbacks or {}
    self.time = 0
    self.gateCycleScale = 1.0
    self.pusherSpeedScale = 1.0
    self.pusherForceScale = 1.0
    self.gateWidthScale = 1.0
    self.railGuard = 0        -- 0..0.7 侧漏护栏保护
    self.frontLipResist = 0.08
    self.magLip = 0
    self._stepping = false
    self._needSync = false
    self._spawnArg = {}
    self.gateClosed = false
    self.launchPhase = 0
    self.gatePhase = 0.31
    self.slotCount = 0
    self.pusherPhase = 0.72   -- 起始靠近前推半程，首次投币很快响应
    self.pusherY = S.PUSHER_Y_MIN
    self.pusherPrevY = S.PUSHER_Y_MIN
    self.pusherVelY = 0
    self.gateX = S.LAUNCHER_X
    self.launchAngleDeg = 0

    -- 预分配硬币池（SoA/扁平槽，永不删除重建表）
    self.coins = {}
    self.activeIds = {}
    self.activeCount = 0
    for i = 1, S.MAX_COINS do
        self.coins[i] = {
            id = i,
            active = false,
            kind = "gold",
            level = 1,
            r = S.COIN_RADIUS,
            mass = 1.0,
            rest = 0.55,
            x = 0, y = 0, vx = 0, vy = 0,
            z = 0, vz = 0,        -- 2.5D 高度与竖直弹跳
            rot = 0, vrot = 0,
            zone = "slot",        -- "slot" | "deck" | "falling"
            onPusher = false,
            gateChecked = false,
            stuckT = 0,
            age = 0,
            fuseT = -1,
            frostT = 0,
            bhT = -1,
            bhCount = 0,
            bounceCount = 0,
            splitDone = false,
            ghostTimer = 0,
            isRain = false,
            isMini = false,
            isBonus = false,
            fromShot = false,
            fromManual = false,
            valueMul = 1.0,
            pegCashHits = 0,
            lastPegId = 0,
            spawnSeq = 0,
        }
    end
    self.nextSeq = 0

    -- 钉阵（可每关刷新特殊钉类型）
    self.pegs = {}
    self.pegVersion = 0
    self:BuildPegs(4)

    -- 预分配空间哈希网格（零每帧分配）
    self.gridHead = {}
    self.gridNext = {}
    for c = 1, GRID_CELLS do self.gridHead[c] = 0 end
    for i = 1, S.MAX_COINS do self.gridNext[i] = 0 end

    return self
end

function Physics:BuildPegs(extraMultCount)
    self.pegVersion = (self.pegVersion or 0) + 1
    local pegs = self.pegs
    for i = #pegs, 1, -1 do pegs[i] = nil end
    local rows = { 74, 112, 150, 188 }
    local cx = 180
    for rIdx = 1, #rows do
        local y = rows[rIdx]
        local even = (rIdx % 2 == 0)
        local cols = even and 4 or 5
        local step = 56
        local startX = cx - (cols - 1) * step * 0.5
        for c = 1, cols do
            local x = startX + (c - 1) * step
            local kind = "normal"
            if rIdx == 2 and (c == 2 or c == 3) then kind = "mult"
            elseif rIdx == 3 and c == 3 then kind = "fever"
            elseif rIdx == 1 and (c == 2 or c == 4) then kind = "bolt"
            elseif rIdx == 4 and (c == 2 or c == 3) then kind = "split"
            end
            pegs[#pegs + 1] = {
                x = x, y = y, r = S.PEG_RADIUS, kind = kind, flash = 0,
            }
        end
    end
    -- 额外转化金色倍增钉（顺序遍历全部 11 颗普通钉位，保证 Lv1~Lv11 每级生效）
    local n = extraMultCount or 0
    local idx = 1
    while n > 0 and idx <= #pegs do
        if pegs[idx].kind == "normal" then
            pegs[idx].kind = "mult"
            n = n - 1
        end
        idx = idx + 1
    end
end

function Physics:Reset(opts)
    opts = opts or {}
    self.time = 0
    self.gateCycleScale = opts.gateCycleScale or 1.0
    self.pusherSpeedScale = opts.pusherSpeedScale or 1.0
    self.pusherForceScale = opts.pusherForceScale or 1.0
    self.gateWidthScale = opts.gateWidthScale or 1.0
    self.railGuard = opts.railGuard or 0
    self.frontLipResist = opts.frontLipResist or 0.08
    self.magLip = opts.magLip or 0
    self._stepping = false
    self._needSync = false
    self.gateClosed = false
    self.launchPhase = 0
    self.gatePhase = 0.31
    self.slotCount = 0
    self.pusherPhase = 0.72
    self.pusherY = self:CalcPusherY(self.pusherPhase)
    self.pusherPrevY = self.pusherY
    self.pusherVelY = 0
    self.gateX = S.LAUNCHER_X
    self.launchAngleDeg = 0
    self.nextSeq = 0

    for i = 1, S.MAX_COINS do
        self.coins[i].active = false
    end
    self.activeCount = 0
    self:BuildPegs(opts.extraMultPegs or 0)
end

function Physics:CalcPusherY(phase)
    local mid = (S.PUSHER_Y_MIN + S.PUSHER_Y_MAX) * 0.5
    local amp = (S.PUSHER_Y_MAX - S.PUSHER_Y_MIN) * 0.5
    return mid - amp * cos(phase * TWO_PI)
end

function Physics:SyncActiveList()
    local cnt, sc = 0, 0
    local list = self.activeIds
    for i = 1, S.MAX_COINS do
        local c = self.coins[i]
        if c.active then
            cnt = cnt + 1
            list[cnt] = i
            if c.zone == "slot" then sc = sc + 1 end
        end
    end
    self.activeCount = cnt
    self.slotCount = sc
end

--- 推台群体前推脉冲：将前排/中排台面币向前沿加速挤压，防止后排新增直接淹没前排掉落
function Physics:PulseDeckForward(strength, countLimit)
    local touched = 0
    local limit = countLimit or S.MAX_COINS
    local coins = self.coins
    local ids = self.activeIds
    for idx = 1, self.activeCount do
        local c = coins[ids[idx]]
        if c and c.active and c.zone == "deck" and c.y >= 340 then
            local factor = (c.y >= 460) and 1.25 or 0.75
            c.vy = min(175, c.vy + strength * factor)
            touched = touched + 1
            if touched >= limit then break end
        end
    end
end

--- 释放槽位：优先复用已出界正在下落的币，其次清理中后排迷你子币，最后温和超频并向前推挤前排
function Physics:AllocCoinSlot()
    for i = 1, S.MAX_COINS do
        if not self.coins[i].active then return self.coins[i] end
    end
    -- 1. 优先复用已计分离开台面正在悬崖下方坠落的币（零损失）
    for i = 1, S.MAX_COINS do
        local c = self.coins[i]
        if c.active and c.zone == "falling" then
            c.active = false
            return c
        end
    end
    -- 2. 其次回收中后排分裂子币
    local pickMini, miniSeq = nil, math.huge
    for i = 1, S.MAX_COINS do
        local c = self.coins[i]
        if c.active and c.zone == "deck" and c.isMini and c.y < 480 and c.spawnSeq < miniSeq then
            miniSeq = c.spawnSeq
            pickMini = c
        end
    end
    if pickMini then
        if self.cb.OnOverclockCoin then self.cb.OnOverclockCoin(pickMini) end
        pickMini.active = false
        return pickMini
    end
    -- 3. 保护前沿悬崖带 (y > 460)，回收到极限前先推动前排跌落再回收最老普通币
    local pick, bestScore = nil, math.huge
    for i = 1, S.MAX_COINS do
        local c = self.coins[i]
        if c.active and c.zone == "deck" then
            local frontPen = (c.y > 460) and 200000 or 0
            local prio = c.spawnSeq + frontPen + ((c.kind == "gold" or c.kind == "mini") and 0 or 50000)
            if prio < bestScore then
                bestScore = prio
                pick = c
            end
        end
    end
    if not pick then pick = self.coins[1] end
    self:PulseDeckForward(36, 4)
    if self.cb.OnOverclockCoin then
        self.cb.OnOverclockCoin(pick)
    end
    pick.active = false
    return pick
end

function Physics:SpawnCoin(params)
    if params.isMini and self.activeCount >= S.MAX_COINS - 14 then
        return nil
    end
    if params.isRain and self.activeCount >= S.MAX_COINS - 6 then
        self:PulseDeckForward(45, 6)
        return nil
    end
    local c = self:AllocCoinSlot()
    local kind = params.kind or "gold"
    local def = Config.COINS[kind] or Config.COINS.gold
    local lv = params.level or 1
    local scale = params.radiusMul or def.radiusMul or 1.0
    self.nextSeq = self.nextSeq + 1
    c.active = true
    c.kind = kind
    c.level = lv
    c.r = S.COIN_RADIUS * scale
    c.mass = (def.massMul or 1.0) * (1 + (lv - 1) * 0.12)
    c.rest = def.restitution or 0.55
    c.x = params.x or S.LAUNCHER_X
    c.y = params.y or S.LAUNCHER_Y
    c.vx = params.vx or 0
    c.vy = params.vy or 0
    c.z = params.z or 0
    c.vz = params.vz or 0
    c.rot = params.rot or (self.nextSeq * 0.7) % TWO_PI
    c.vrot = params.vrot or 0
    c.zone = params.zone or "slot"
    c.onPusher = params.onPusher == true
    c.gateChecked = params.gateChecked == true
    c.stuckT = 0
    c.age = 0
    c.fuseT = (def.fuseTime and c.zone == "deck") and def.fuseTime or -1
    c.frostT = 0
    c.bhT = (def.bhRadius and c.zone == "deck") and 2.2 or -1
    c.bhCount = 0
    c.bounceCount = 0
    c.splitDone = params.splitDone == true
    c.ghostTimer = def.phasePegs and 0.42 or 0
    c.isRain = params.isRain == true
    c.isMini = params.isMini == true
    c.isBonus = params.isBonus == true
    c.fromShot = params.fromShot == true
    c.fromManual = params.fromManual == true
    c.valueMul = params.valueMul or 1.0
    c.pegCashHits = 0
    c.lastPegId = 0
    c.spawnSeq = self.nextSeq
    if self._stepping then
        self._needSync = true
    else
        self:SyncActiveList()
    end
    return c
end

--- 顶部摆动炮发射硬币（上槽 >=22 时合并为高倍叠币并前推台面，防止挤占 deck 池位）
function Physics:LaunchFromTop(kind, level, offsetAngleDeg, fromManual)
    if (self.slotCount or 0) >= 22 then
        local newest, bestSeq = nil, -1
        for i = 1, self.activeCount do
            local c = self.coins[self.activeIds[i]]
            if c and c.active and c.zone == "slot" and c.spawnSeq > bestSeq then
                bestSeq = c.spawnSeq
                newest = c
            end
        end
        if newest then
            newest.valueMul = min(6.0, (newest.valueMul or 1.0) + 1.0)
            if fromManual then newest.fromManual = true end
            self:PulseDeckForward(fromManual and 26 or 14, 10)
            return newest
        end
    end
    local angDeg = self.launchAngleDeg + (offsetAngleDeg or 0)
    local rad = math.rad(angDeg)
    local spd = S.LAUNCH_SPEED
    local sx = S.LAUNCHER_X + sin(rad) * 14
    local sy = S.LAUNCHER_Y + cos(rad) * 14
    local a = self._spawnArg
    for k in pairs(a) do a[k] = nil end
    a.kind = kind
    a.level = level or 1
    a.x = sx
    a.y = sy
    a.vx = sin(rad) * spd
    a.vy = cos(rad) * spd
    a.zone = "slot"
    a.fromShot = true
    a.fromManual = fromManual == true
    a.vrot = (angDeg >= 0) and 3.5 or -3.5
    local spawned = self:SpawnCoin(a)
    if fromManual then
        self:PulseDeckForward(14, 8)
    end
    return spawned
end

--- 开局从推板前沿往悬崖铺满交错推台基础币（120 池中仅铺 70 枚，留 50 槽给高频率手点不爆池）
function Physics:SeedDeck(rng, poolKinds, extraSeed)
    local kinds = poolKinds or { "gold", "gold", "gold", "emerald", "split", "thunder" }
    local cap = min(S.MAX_COINS - 16, S.SEED_COUNT + (extraSeed or 0))
    local yStart, yEnd = 334, 536
    local rowStep = 26.8
    local rIdx = 0
    local ty = yStart
    local a = self._spawnArg
    while ty <= yEnd do
        rIdx = rIdx + 1
        local halfW = Physics.TrapezoidHalfW(ty) - 15
        local spacing = 30.0
        local count = max(5, floor((halfW * 2) / spacing) + 1)
        local stagger = (rIdx % 2 == 0) and 7 or 0
        for k = 1, count do
            local frac = (count == 1) and 0.5 or ((k - 1) / (count - 1))
            local jx = (rng and (rng() - 0.5) * 2.5) or 0
            local jy = (rng and (rng() - 0.5) * 1.8) or 0
            local x = (180 - halfW + stagger) + frac * (halfW * 2 - stagger * 2) + jx
            local y = min(S.FRONT_DROP_Y - 2.5, ty + jy)
            local pickKind = kinds[((rIdx * 7 + k) % #kinds) + 1]
            if ty >= 510 and (k % 2 == 0) then pickKind = "gold" end
            if self.activeCount < cap then
                for ak in pairs(a) do a[ak] = nil end
                a.kind = pickKind
                a.level = 1
                a.x = x
                a.y = y
                a.zone = "deck"
                a.gateChecked = true
                self:SpawnCoin(a)
            end
        end
        ty = ty + rowStep
    end
    if self._needSync then
        self._needSync = false
        self:SyncActiveList()
    end
end

--- 台面爆炸冲击波：向外推飞前方与周边币
function Physics:ApplyExplosion(ex, ey, radius, force)
    local r2 = radius * radius
    for idx = 1, self.activeCount do
        local c = self.coins[self.activeIds[idx]]
        if c.active and c.zone == "deck" then
            local dx = c.x - ex
            local dy = c.y - ey
            local d2 = dx * dx + dy * dy
            if d2 < r2 and d2 > 0.01 then
                local d = sqrt(d2)
                local falloff = 1 - d / radius
                -- 爆破优先向前方(+y)挤压推动，形成瀑布跌落感
                local nx = dx / d
                local ny = max(0.35, dy / d + 0.55)
                local nlen = sqrt(nx * nx + ny * ny)
                local imp = (force * falloff) / max(0.7, c.mass * 0.75)
                c.vx = c.vx + (nx / nlen) * imp
                c.vy = c.vy + (ny / nlen) * imp
                c.vz = max(c.vz, 75 * falloff)
            end
        end
    end
end

--- 磁力/黑洞吸聚周边硬币
function Physics:ApplyPull(ax, ay, radius, strength, dt)
    local r2 = radius * radius
    for idx = 1, self.activeCount do
        local c = self.coins[self.activeIds[idx]]
        if c.active and c.zone == "deck" then
            local dx = ax - c.x
            local dy = ay - c.y
            local d2 = dx * dx + dy * dy
            if d2 < r2 and d2 > 25 then
                local d = sqrt(d2)
                local pull = strength * (1 - d / radius * 0.5) * dt / max(0.8, c.mass)
                c.vx = c.vx + (dx / d) * pull
                c.vy = c.vy + (dy / d) * pull * 0.65
            end
        end
    end
end

function Physics:CountDeckCoins()
    local n = 0
    for idx = 1, self.activeCount do
        local c = self.coins[self.activeIds[idx]]
        if c.active and c.zone == "deck" then n = n + 1 end
    end
    return n
end

function Physics:HasActiveSlotCoins()
    for idx = 1, self.activeCount do
        local c = self.coins[self.activeIds[idx]]
        if c.active and (c.zone == "slot" or c.zone == "falling") then return true end
    end
    return false
end

function Physics:Step(dt)
    if dt <= 0 then return end
    if dt > 0.05 then dt = 0.05 end
    self.time = self.time + dt

    -- 1. 机械周期更新（摆动发射口 + 独立扫掠幸运门 + 机械推板）
    local gRate = (1 / S.GATE_CYCLE) * self.gateCycleScale
    self.launchPhase = (self.launchPhase + dt * gRate) % 1
    self.gatePhase = (self.gatePhase + dt * (1 / (S.GATE_CYCLE * 1.37)) * self.gateCycleScale) % 1
    self.launchAngleDeg = sin(self.launchPhase * TWO_PI) * S.LAUNCH_SWING_DEG
    self.gateX = S.LAUNCHER_X + sin(self.gatePhase * TWO_PI) * S.GATE_TRAVEL

    self.pusherPrevY = self.pusherY
    local pRate = (1 / S.PUSHER_CYCLE) * self.pusherSpeedScale
    self.pusherPhase = (self.pusherPhase + dt * pRate) % 1
    self.pusherY = self:CalcPusherY(self.pusherPhase)
    self.pusherVelY = (self.pusherY - self.pusherPrevY) / dt

    -- 钉子闪光衰减
    for p = 1, #self.pegs do
        local peg = self.pegs[p]
        if peg.flash > 0 then peg.flash = max(0, peg.flash - dt * 4) end
    end

    local gateHalf = self.gateClosed and 0 or (S.GATE_BASE_HALF * self.gateWidthScale)
    local gateLeftEdge = self.gateX - gateHalf
    local gateRightEdge = self.gateX + gateHalf
    local pusherFront = self.pusherY
    local pusherLeft = 180 - S.DECK_TOP_HALF + 4
    local pusherRight = 180 + S.DECK_TOP_HALF - 4

    -- 2. 单币积分、槽内碰撞与推台边界（遍历期间新增币延迟同步 activeIds）
    local cb = self.cb
    local needSync = false
    self._stepping = true
    self._needSync = false
    local stepCount = self.activeCount
    local crowdBoost = 1.0
    if stepCount > S.MAX_COINS * 0.78 then
        crowdBoost = 1.0 + 0.35 * ((stepCount / S.MAX_COINS - 0.78) / 0.22)
    end
    for i = 1, stepCount do
        local c = self.coins[self.activeIds[i]]
        if c and c.active then
            c.age = c.age + dt
            c.rot = c.rot + c.vrot * dt
            if c.frostT > 0 then c.frostT = max(0, c.frostT - dt) end

            if c.zone == "slot" then
                if c.ghostTimer > 0 then c.ghostTimer = max(0, c.ghostTimer - dt) end
                c.vy = c.vy + S.GRAVITY * dt
                -- 速度限幅防止单步穿钉
                local spd2 = c.vx * c.vx + c.vy * c.vy
                if spd2 > 340 * 340 then
                    local inv = 340 / sqrt(spd2)
                    c.vx, c.vy = c.vx * inv, c.vy * inv
                end
                local prevY = c.y
                c.x = c.x + c.vx * dt
                c.y = c.y + c.vy * dt

                -- 左右槽墙反弹
                if c.x - c.r < S.SLOT_LEFT then
                    c.x = S.SLOT_LEFT + c.r
                    c.vx = abs(c.vx) * 0.72
                elseif c.x + c.r > S.SLOT_RIGHT then
                    c.x = S.SLOT_RIGHT - c.r
                    c.vx = -abs(c.vx) * 0.72
                end

                -- 钉阵圆形碰撞（幽灵初期穿透，记录入钉前速度供真实撞钉限流）
                if c.ghostTimer <= 0 then
                    local pegs = self.pegs
                    for p = 1, #pegs do
                        local peg = pegs[p]
                        local dx = c.x - peg.x
                        local dy = c.y - peg.y
                        local minD = c.r + peg.r
                        local d2 = dx * dx + dy * dy
                        if d2 < minD * minD and d2 > 0.0001 then
                            local d = sqrt(d2)
                            local nx, ny = dx / d, dy / d
                            c.x = peg.x + nx * minD
                            c.y = peg.y + ny * minD
                            local vn = c.vx * nx + c.vy * ny
                            if vn < 0 then
                                local hitSpd = sqrt(c.vx * c.vx + c.vy * c.vy)
                                local imp = -(1 + c.rest) * vn
                                c.vx = c.vx + nx * imp
                                c.vy = c.vy + ny * imp
                                -- 极微随机扰动防正中心垂直死挂
                                if abs(nx) < 0.04 then
                                    c.vx = c.vx + ((c.id % 2 == 0) and 22 or -22)
                                end
                                c.vrot = (c.vx >= 0) and 4 or -4
                                c.bounceCount = c.bounceCount + 1
                                peg.flash = 1.0
                                if cb.OnPegHit and c.lastPegId ~= p then
                                    c.lastPegId = p
                                    cb.OnPegHit(c, peg, hitSpd)
                                elseif cb.OnPegHit and hitSpd >= 120 then
                                    cb.OnPegHit(c, peg, hitSpd)
                                end
                            end
                        end
                    end
                end

                -- 幸运门斜沿与穿越检测
                if not c.gateChecked and prevY < S.GATE_Y and c.y >= S.GATE_Y then
                    c.gateChecked = true
                    if not self.gateClosed and c.x >= gateLeftEdge and c.x <= gateRightEdge then
                        if cb.OnGateWin then cb.OnGateWin(c) end
                    else
                        -- 撞到左/右门板斜沿弹开
                        if c.x < gateLeftEdge and c.x >= gateLeftEdge - S.GATE_DOOR_W - c.r then
                            c.y = S.GATE_Y - c.r * 0.5
                            c.vx = -max(95, abs(c.vx) + 55)
                            c.vy = -85
                            if cb.OnGateBounce then cb.OnGateBounce(c) end
                        elseif c.x > gateRightEdge and c.x <= gateRightEdge + S.GATE_DOOR_W + c.r then
                            c.y = S.GATE_Y - c.r * 0.5
                            c.vx = max(95, abs(c.vx) + 55)
                            c.vy = -85
                            if cb.OnGateBounce then cb.OnGateBounce(c) end
                        end
                    end
                end

                -- 防卡死保险丝（低速滞留或槽内超5.5秒自动相位脱困落台）
                if spd2 < 60 * 60 then
                    c.stuckT = c.stuckT + dt
                else
                    c.stuckT = 0
                end
                if c.stuckT > S.STUCK_FUSE_SEC or c.age > 5.5 then
                    c.vx = (c.x < 180) and 65 or -65
                    c.vy = max(165, c.vy + 120)
                    c.ghostTimer = 0.45
                    c.stuckT = 0
                end

                -- 进入梯形推台
                if c.y >= S.DECK_TOP_Y + 6 then
                    c.zone = "deck"
                    c.y = max(S.DECK_TOP_Y + c.r + 2, c.y)
                    c.vx = c.vx * 0.35
                    c.vy = max(18, c.vy * 0.28)
                    c.z = 8
                    c.vz = 42
                    c.onPusher = (c.y < pusherFront - c.r * 0.25)
                    local def = Config.COINS[c.kind]
                    if def and def.fuseTime then c.fuseT = def.fuseTime end
                    if def and def.bhRadius then c.bhT = 2.1 end
                    if cb.OnEnterDeck then cb.OnEnterDeck(c) end
                end

            elseif c.zone == "deck" then
                -- 2.5D Z 轴弹跳回落
                if c.z > 0 or c.vz ~= 0 then
                    c.vz = c.vz - 360 * dt
                    c.z = c.z + c.vz * dt
                    if c.z <= 0 then
                        c.z = 0
                        if c.vz < -50 then
                            c.vz = -c.vz * 0.25
                        else
                            c.vz = 0
                        end
                    end
                end

                -- 特殊倒计时机制（炸弹 / 黑洞 / 磁石）
                local def = Config.COINS[c.kind]
                if def then
                    if c.fuseT > 0 then
                        c.fuseT = c.fuseT - dt
                        if c.fuseT <= 0 then
                            if cb.OnCoinFuseExplode then cb.OnCoinFuseExplode(c) end
                            c.active = false
                            needSync = true
                        end
                    end
                    if c.active and def.magnetR and def.magnetR > 0 then
                        self:ApplyPull(c.x, c.y, def.magnetR, 120, dt)
                    end
                    if c.active and c.bhT > 0 then
                        c.bhT = c.bhT - dt
                        self:ApplyPull(c.x, c.y, def.bhRadius or 90, 210, dt)
                        if c.bhT <= 0 then
                            if cb.OnBlackholeBurst then cb.OnBlackholeBurst(c) end
                            c.bhT = 3.2
                        end
                    end
                end

                if c.active then
                    -- 台面摩擦阻尼（静止靠推挤推动）
                    local damp = math.exp(-3.8 * dt)
                    c.vx = c.vx * damp
                    c.vy = c.vy * damp
                    c.vrot = c.vrot * damp

                    -- 推板互动：上层乘板或前缘推挤（拥挤满台时小幅增大前推速度，让狂点看得见掉币）
                    if c.onPusher then
                        if self.pusherVelY > 0 then
                            c.y = c.y + self.pusherVelY * 0.85 * crowdBoost * dt
                        end
                        if c.y >= pusherFront - c.r * 0.1 then
                            c.onPusher = false
                            c.z = 4
                        end
                    else
                        if c.x >= pusherLeft and c.x <= pusherRight and c.y - c.r < pusherFront then
                            c.y = pusherFront + c.r
                            if self.pusherVelY > 0 then
                                local pushV = max(40, self.pusherVelY * self.pusherForceScale * 1.2 * crowdBoost)
                                if c.vy < pushV then c.vy = pushV end
                            end
                        end
                    end

                    -- 磁力集束唇：前沿 36px 额外前拉跌落
                    if self.magLip > 0 and c.y >= S.DECK_BOT_Y - 36 and c.y < S.FRONT_DROP_Y then
                        c.vy = c.vy + 22 * self.magLip * dt
                    end

                    -- 推进积分
                    c.x = c.x + c.vx * dt
                    c.y = c.y + c.vy * dt

                    -- 后壁钳位
                    if c.y - c.r < S.DECK_TOP_Y + 2 then
                        c.y = S.DECK_TOP_Y + 2 + c.r
                        if c.vy < 0 then c.vy = 0 end
                    end

                    -- 前沿阻挡唇（制造悬崖堆币张力）
                    if c.y >= S.DECK_BOT_Y - 6 and c.y < S.FRONT_DROP_Y then
                        c.vy = c.vy * (1 - self.frontLipResist)
                    end

                    -- 梯形侧挡板与侧漏缝判定
                    local halfW = Physics.TrapezoidHalfW(c.y)
                    local inSideGap = (c.y >= S.SIDE_GAP_Y and c.y < S.FRONT_DROP_Y)
                    if inSideGap then
                        local safeGapHalf = halfW + c.r * (0.48 + self.railGuard)
                        if c.x < 180 - safeGapHalf or c.x > 180 + safeGapHalf then
                            if self.railGuard >= 0.45 and ((c.id + floor(self.time * 10)) % 3 ~= 0) then
                                -- 合金护栏弹回台内
                                if c.x < 180 then c.x = 180 - halfW + c.r else c.x = 180 + halfW - c.r end
                                c.vx = -c.vx * 0.5
                            else
                                c.zone = "falling"
                                c.vx = (c.x < 180) and -80 or 80
                                c.vy = 140
                                if cb.OnSideDrain then cb.OnSideDrain(c) end
                            end
                        end
                    else
                        if c.x - c.r < 180 - halfW then
                            c.x = 180 - halfW + c.r
                            if c.vx < 0 then c.vx = -c.vx * 0.35 end
                        elseif c.x + c.r > 180 + halfW then
                            c.x = 180 + halfW - c.r
                            if c.vx > 0 then c.vx = -c.vx * 0.35 end
                        end
                    end

                    -- 前沿悬崖跌落收集
                    if c.zone == "deck" and c.y >= S.FRONT_DROP_Y then
                        c.zone = "falling"
                        c.vy = max(145, c.vy + 110)
                        c.vz = 15
                        if cb.OnFrontDrop then cb.OnFrontDrop(c) end
                    end
                end

            elseif c.zone == "falling" then
                c.vy = c.vy + 460 * dt
                c.x = c.x + c.vx * dt
                c.y = c.y + c.vy * dt
                if c.y >= S.DROP_END_Y then
                    c.active = false
                    needSync = true
                end
            end
        end
    end

    self._stepping = false
    if needSync or self._needSync then
        self._needSync = false
        self:SyncActiveList()
    end

    -- 3. 推台币-币 3 迭代位置分离（带早停与静止Skip，空间网格零分配）
    self:ResolveDeckCollisions(crowdBoost)
end

function Physics:ResolveDeckCollisions(crowdBoost)
    local cnt = self.activeCount
    if cnt < 2 then return end
    local coins = self.coins
    local ids = self.activeIds
    local gridHead = self.gridHead
    local gridNext = self.gridNext

    local minX, maxX = 16, 344
    local minY, maxY = S.DECK_TOP_Y - 8, S.FRONT_DROP_Y + 16
    local cellW = (maxX - minX) / GRID_COLS
    local cellH = (maxY - minY) / GRID_ROWS
    local pusherFront = self.pusherY
    local pusherLeft = 180 - S.DECK_TOP_HALF + 4
    local pusherRight = 180 + S.DECK_TOP_HALF - 4
    local pushGain = crowdBoost or 1.0

    for iter = 1, 3 do
        local maxOv = 0
        for k = 1, GRID_CELLS do gridHead[k] = 0 end
        -- 入格
        for idx = 1, cnt do
            local id = ids[idx]
            local c = coins[id]
            if c.active and c.zone == "deck" then
                local gx = floor((c.x - minX) / cellW) + 1
                local gy = floor((c.y - minY) / cellH) + 1
                if gx < 1 then gx = 1 elseif gx > GRID_COLS then gx = GRID_COLS end
                if gy < 1 then gy = 1 elseif gy > GRID_ROWS then gy = GRID_ROWS end
                local cell = (gy - 1) * GRID_COLS + gx
                gridNext[id] = gridHead[cell]
                gridHead[cell] = id
            end
        end

        -- 邻格 3×3 检测
        for idx = 1, cnt do
            local idA = ids[idx]
            local a = coins[idA]
            if a.active and a.zone == "deck" then
                local gx = floor((a.x - minX) / cellW) + 1
                local gy = floor((a.y - minY) / cellH) + 1
                if gx < 1 then gx = 1 elseif gx > GRID_COLS then gx = GRID_COLS end
                if gy < 1 then gy = 1 elseif gy > GRID_ROWS then gy = GRID_ROWS end

                local x0, x1 = max(1, gx - 1), min(GRID_COLS, gx + 1)
                local y0, y1 = max(1, gy - 1), min(GRID_ROWS, gy + 1)

                for ny = y0, y1 do
                    local rowOff = (ny - 1) * GRID_COLS
                    for nx = x0, x1 do
                        local idB = gridHead[rowOff + nx]
                        while idB ~= 0 do
                            if idB > idA then
                                local b = coins[idB]
                                if a.onPusher == b.onPusher then
                                    local dx = b.x - a.x
                                    local dy = b.y - a.y
                                    local minD = a.r + b.r
                                    local d2 = dx * dx + dy * dy
                                    if d2 < minD * minD then
                                        local d = sqrt(d2)
                                        local ux, uy
                                        if d > 0.001 then
                                            ux, uy = dx / d, dy / d
                                        else
                                            ux, uy = 0.2, 0.98
                                            d = 0.001
                                        end
                                        local overlap = minD - d
                                        if overlap > maxOv then maxOv = overlap end
                                        local moving = (abs(a.vx) + abs(a.vy) + abs(b.vx) + abs(b.vy)) >= 1.5
                                        if moving or overlap > 0.2 then
                                            local wA = 1 / max(0.3, a.mass)
                                            local wB = 1 / max(0.3, b.mass)
                                            local wSum = wA + wB
                                            local rA = wA / wSum
                                            local rB = wB / wSum
                                            a.x = a.x - ux * overlap * rA
                                            a.y = a.y - uy * overlap * rA
                                            b.x = b.x + ux * overlap * rB
                                            b.y = b.y + uy * overlap * rB
                                            if moving then
                                                local rvx = b.vx - a.vx
                                                local rvy = b.vy - a.vy
                                                local vn = rvx * ux + rvy * uy
                                                if vn < 0 then
                                                    local j = -1.18 * vn * pushGain / wSum
                                                    a.vx = a.vx - ux * j * wA
                                                    a.vy = a.vy - uy * j * wA
                                                    b.vx = b.vx + ux * j * wB
                                                    b.vy = b.vy + uy * j * wB
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                            idB = gridNext[idB]
                        end
                    end
                end
                -- 钳位回推板前侧与后壁（每轮迭代强制推板刚体不退让，确保推力传递到前沿）
                if not a.onPusher and a.x >= pusherLeft and a.x <= pusherRight and a.y - a.r < pusherFront then
                    a.y = pusherFront + a.r
                end
                if a.y - a.r < S.DECK_TOP_Y + 2 then a.y = S.DECK_TOP_Y + 2 + a.r end
                local hw = Physics.TrapezoidHalfW(a.y)
                if a.y < S.SIDE_GAP_Y then
                    if a.x - a.r < 180 - hw then a.x = 180 - hw + a.r end
                    if a.x + a.r > 180 + hw then a.x = 180 + hw - a.r end
                end
            end
        end
        if iter >= 2 and maxOv < 0.15 then break end
    end
end

return Physics
