-- ============================================================================
-- Music.lua  双轨动态背景音乐（base + drums 无缝循环，连击/Fever 推鼓轨）
-- ============================================================================

local Music = {}

Music.MASTER = 0.58
Music.SFX_MASTER = 1.0
Music.DUCK = 0.4
Music.FADE = 0.5

local TRACKS = {
    bgm_act1 = { base = "audio/bgm/bgm_act1_base.wav", drums = "audio/bgm/bgm_act1_drums.wav" },
    bgm_act2 = { base = "audio/bgm/bgm_act2_base.wav", drums = "audio/bgm/bgm_act2_drums.wav" },
    bgm_act3 = { base = "audio/bgm/bgm_act3_base.wav", drums = "audio/bgm/bgm_act3_drums.wav" },
    bgm_boss = { base = "audio/bgm/bgm_boss_base.wav", drums = "audio/bgm/bgm_boss_drums.wav" },
}

local ROLES = { "base", "drums" }
local scene = nil
local chans = nil
local ready = false
local userEnabled = true
local paused = false
local ducked = false
local gate = 0
local duckGain = 1
local curName = nil
local pendingName = nil
local intensityTarget = 0
local drumsGain = 0

local function StartChan(c, name)
    c.name = nil
    c.src:Stop()
    local t = TRACKS[name]
    local s = t and cache:GetResource("Sound", t[c.role]) or nil
    if s then
        s.looped = true
        c.src:Play(s)
        c.name = name
    end
    c.phase = "in"
end

function Music.Init()
    if not (Scene and cache and audio) then return end
    if ready then return end
    audio:SetMasterGain(SOUND_MUSIC, Music.MASTER)
    audio:SetMasterGain(SOUND_EFFECT, Music.SFX_MASTER)
    scene = Scene()
    chans = {}
    for _, role in ipairs(ROLES) do
        local node = scene:CreateChild("Music_" .. role)
        local src = node:CreateComponent("SoundSource")
        src.soundType = SOUND_MUSIC
        src.gain = 0
        chans[role] = { node = node, src = src, role = role, phase = "idle", fade = 0, name = nil }
    end
    ready = true
end

function Music.Play(name)
    if not TRACKS[name] then return end
    if curName == name and pendingName == name then return end
    curName, pendingName = name, name
    if not ready then return end
    for _, role in ipairs(ROLES) do
        chans[role].phase = "out"
    end
end

function Music.SetIntensity(combo, feverActive)
    if feverActive then
        intensityTarget = 1.0
        return
    end
    local x = tonumber(combo) or 0
    if x <= 0 then intensityTarget = 0
    elseif x >= 24 then intensityTarget = 1
    elseif x <= 10 then intensityTarget = (x / 10) * 0.5
    else intensityTarget = 0.5 + ((x - 10) / 14) * 0.5 end
end

function Music.SetDucked(on)
    ducked = (on == true)
end

function Music.SetEnabled(on)
    userEnabled = (on ~= false)
end

function Music.SetPaused(on)
    paused = (on == true)
    if paused and chans then
        gate = 0
        for _, role in ipairs(ROLES) do
            if chans[role].src then chans[role].src.gain = 0 end
        end
    end
end

function Music.Update(dt)
    if not ready or not chans then return end
    local rate = (intensityTarget > drumsGain) and 1.8 or 0.8
    if drumsGain < intensityTarget then
        drumsGain = math.min(intensityTarget, drumsGain + rate * dt)
    else
        drumsGain = math.max(intensityTarget, drumsGain - rate * dt)
    end
    local gateTarget = (userEnabled and not paused) and 1 or 0
    if gate < gateTarget then gate = math.min(gateTarget, gate + 10 * dt)
    else gate = math.max(gateTarget, gate - 10 * dt) end

    local duckTarget = ducked and Music.DUCK or 1
    if duckGain < duckTarget then duckGain = math.min(duckTarget, duckGain + 3 * dt)
    else duckGain = math.max(duckTarget, duckGain - 3 * dt) end

    for _, role in ipairs(ROLES) do
        local c = chans[role]
        if c.phase == "out" then
            c.fade = c.fade - dt / Music.FADE
            if c.fade <= 0 then
                c.fade = 0
                StartChan(c, pendingName or curName)
            end
        elseif c.phase == "in" and c.fade < 1 then
            c.fade = math.min(1, c.fade + dt / Music.FADE)
        end
        local g = c.fade * duckGain * gate
        if role == "drums" then g = g * drumsGain end
        if g > 1 then g = 1 elseif g < 0 then g = 0 end
        c.src.gain = g
    end
end

function Music.Shutdown()
    if chans then
        for _, role in ipairs(ROLES) do
            if chans[role].src then pcall(function() chans[role].src:Stop() end) end
        end
    end
    chans, scene, ready = nil, nil, false
end

return Music
