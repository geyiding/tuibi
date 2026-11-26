-- ============================================================================
-- Sfx.lua  音效系统（16路预建对象池 + 45ms高频节流 + 连击升调 + 声像）
-- ============================================================================

local Sfx = {}

local VOICES = 16
local SR = 44100

local DEFS = {
    shoot       = { "audio/shoot.wav",       0.65, 0.05 },
    peg1        = { "audio/peg1.wav",        0.48, 0.045 },
    peg2        = { "audio/peg2.wav",        0.48, 0.045 },
    peg_mult    = { "audio/peg_mult.wav",    0.65, 0.05 },
    gate_win    = { "audio/gate_win.wav",    0.85, 0.12 },
    gate_bounce = { "audio/gate_bounce.wav", 0.50, 0.05 },
    drop1       = { "audio/drop1.wav",       0.55, 0.045 },
    drop2       = { "audio/drop2.wav",       0.55, 0.045 },
    crit        = { "audio/crit.wav",        0.72, 0.06 },
    explode     = { "audio/explode.wav",     0.85, 0.08 },
    zap         = { "audio/zap.wav",         0.58, 0.05 },
    split       = { "audio/split.wav",       0.55, 0.05 },
    fever       = { "audio/fever.wav",       0.90, 0.40 },
    jackpot     = { "audio/jackpot.wav",     0.92, 0.40 },
    coin        = { "audio/coin.wav",        0.60, 0.05 },
    pick        = { "audio/pick.wav",        0.65, 0.06 },
    click       = { "audio/click.wav",       0.45, 0.04 },
    win         = { "audio/win.wav",         0.85, 0.40 },
    lose        = { "audio/lose.wav",        0.80, 0.40 },
    boss        = { "audio/boss.wav",        0.85, 0.30 },
}
Sfx.PEGS = { "peg1", "peg2" }
Sfx.DROPS = { "drop1", "drop2" }

local enabled = false
local userEnabled = true
local paused = false
local muted = false
local sounds = {}
local lastAt = {}
local voices = {}
local voiceStart = {}
local voiceGain = {}
local canQuery = false
local rr = 0
local now = 0

local function ApplyMute(m)
    if m == muted then return end
    muted = m
    for i = 1, VOICES do
        local v = voices[i]
        if v then
            if m then
                voiceGain[i] = v.gain
                v.gain = 0
            else
                v.gain = voiceGain[i] or 0
            end
        end
    end
end

function Sfx.Init()
    if not (Scene and cache and audio) then
        return
    end
    local scene = Scene()
    Sfx.scene = scene
    for i = 1, VOICES do
        local node = scene:CreateChild("Sfx_" .. i)
        local src = node:CreateComponent("SoundSource")
        src.soundType = SOUND_EFFECT
        voices[i] = src
        voiceStart[i] = -1
        voiceGain[i] = 1
    end
    local ok = 0
    for name, def in pairs(DEFS) do
        local s = cache:GetResource("Sound", def[1])
        if s then
            sounds[name] = s
            ok = ok + 1
        end
    end
    canQuery = voices[1] and (voices[1].IsPlaying ~= nil)
    enabled = ok > 0
    muted = false
    ApplyMute((not userEnabled) or paused)
end

local function PickVoice()
    if not canQuery then
        rr = (rr % VOICES) + 1
        return rr
    end
    local oldest, oldestT = 1, math.huge
    for i = 1, VOICES do
        local v = voices[i]
        if not v:IsPlaying() then return i end
        if voiceStart[i] < oldestT then oldest, oldestT = i, voiceStart[i] end
    end
    return oldest
end

function Sfx.PanOf(x, worldW)
    if not x or not worldW or worldW <= 0 then return 0 end
    local p = (x / worldW) * 2 - 1
    if p < -0.8 then p = -0.8 elseif p > 0.8 then p = 0.8 end
    return p
end

function Sfx.Play(name, gain, pitch, pan)
    if not enabled or muted then return end
    local s = sounds[name]
    if not s then return end
    local def = DEFS[name]
    local last = lastAt[name]
    if last and (now - last) < def[3] then return end
    lastAt[name] = now
    local i = PickVoice()
    local v = voices[i]
    if not v then return end
    voiceStart[i] = now
    v:Play(s)
    v.frequency = SR * (pitch or 1)
    local g = def[2] * (gain or 1)
    if g > 1 then g = 1 elseif g < 0 then g = 0 end
    v.gain = g
    voiceGain[i] = g
    v.panning = pan or 0
end

function Sfx.PlayAny(list, gain, pitch, pan)
    if not list or #list == 0 then return end
    Sfx.Play(list[math.random(#list)], gain, pitch, pan)
end

function Sfx.Update(dt)
    now = now + dt
end

function Sfx.SetEnabled(on)
    userEnabled = (on ~= false)
    if enabled then ApplyMute((not userEnabled) or paused) end
end

function Sfx.SetPaused(on)
    paused = (on == true)
    if enabled then ApplyMute((not userEnabled) or paused) end
end

function Sfx.Shutdown()
    for i = 1, VOICES do
        if voices[i] then pcall(function() voices[i]:Stop() end) end
    end
    voices = {}
    sounds = {}
    if Sfx.scene then
        pcall(function() Sfx.scene = nil end)
    end
    enabled = false
end

return Sfx
