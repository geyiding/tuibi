-- ============================================================================
-- SaveManager.lua  双端存档 + 独立偏好 + 换设备防覆盖 + 10秒看门狗
--   · prefs.json       独立声音/振动/引导偏好，切开关即写
--   · carnival_save.json（+.bak 原子写）本地主档（30秒自动保存）
--   · clientCloud 三键 carnival_has_save / carnival_save_meta / carnival_save_data（120秒自动保存）
-- ============================================================================

local Config = require("game/Config")

local SaveManager = {}

local PREFS_FILE = "prefs.json"
local SAVE_FILE = "carnival_save.json"
local SAVE_TMP  = "carnival_save.json.tmp"
local SAVE_BAK  = "carnival_save.json.bak"
local KEY_HAS   = "carnival_has_save"
local KEY_META  = "carnival_save_meta"
local KEY_DATA  = "carnival_save_data"

local VERSION = 2
local LOCAL_INTERVAL = 30
local CLOUD_INTERVAL = 120
local CLOUD_WATCHDOG_SEC = 10

local cjsonLib = nil
local function Json()
    if cjsonLib then return cjsonLib end
    local ok, lib = pcall(require, "cjson")
    if ok and type(lib) == "table" then cjsonLib = lib else cjsonLib = rawget(_G, "cjson") end
    return cjsonLib
end

local prefs = { music = true, sfx = true, haptic = true, tips = {} }
local data = nil

local state = {
    cloudChecked = false,
    cloudBlocked = false,
    syncPending = false,
    syncSeq = 0,
    syncElapsed = 0,
    localTimer = 0,
    cloudTimer = 0,
    localSavedAt = 0,
    cloudSavedAt = 0,
    localFailed = false,
    cloudFailed = false,
    saving = false,
    onCloudFailCb = nil,
    onCloudReadyCb = nil,
    onStatusCb = nil,
}

local function ServerNow()
    local ok, t = pcall(function()
        return (common and common.get_server_time and common.get_server_time()) or 0
    end)
    if ok and type(t) == "number" and t > 0 then return math.floor(t) end
    return os.time()
end

function SaveManager.FormatTime(ts)
    if not ts or ts <= 0 then return "未保存" end
    return os.date("%m-%d %H:%M:%S", ts)
end

function SaveManager.DefaultData()
    return {
        version = VERSION,
        savedAt = 0,
        saveSeq = 0,
        difficulty = 1,
        unlockedDifficulty = 1,
        records = { runs = 0, wins = 0, bestScore = 0.0, bestHit = 0.0, maxCombo = 0 },
        discovered = { coins = { gold = true }, relics = {}, recipes = {}, bosses = {} },
        disabled = {},
        redeemedCodes = {},
        daily = {},
        activeRun = nil,
        tycoon = nil,
    }
end

local function SanitizeData(raw)
    local d = SaveManager.DefaultData()
    if type(raw) ~= "table" then return d end
    d.version = tonumber(raw.version) or VERSION
    d.savedAt = tonumber(raw.savedAt) or 0
    d.saveSeq = math.floor(tonumber(raw.saveSeq) or 0)
    d.unlockedDifficulty = math.max(1, math.min(20, math.floor(tonumber(raw.unlockedDifficulty) or 1)))
    d.difficulty = math.max(1, math.min(d.unlockedDifficulty, math.floor(tonumber(raw.difficulty) or 1)))
    if type(raw.records) == "table" then
        for k, v in pairs(d.records) do
            if k == "bestScore" or k == "bestHit" then
                d.records[k] = math.max(0.0, (tonumber(raw.records[k]) or v) + 0.0)
            else
                d.records[k] = math.max(0, math.floor(tonumber(raw.records[k]) or v))
            end
        end
    end
    if type(raw.discovered) == "table" then
        for cat in pairs(d.discovered) do
            if type(raw.discovered[cat]) == "table" then
                for k, v in pairs(raw.discovered[cat]) do
                    if type(k) == "string" and v then d.discovered[cat][k] = true end
                end
            end
        end
    end
    if type(raw.disabled) == "table" then
        local cnt = 0
        for k, v in pairs(raw.disabled) do
            if type(k) == "string" and v and cnt < 3 then
                d.disabled[k] = true
                cnt = cnt + 1
            end
        end
    end
    if type(raw.redeemedCodes) == "table" then
        for k, v in pairs(raw.redeemedCodes) do
            if type(k) == "string" and v then d.redeemedCodes[k] = true end
        end
    end
    if type(raw.daily) == "table" then d.daily = raw.daily end
    if type(raw.activeRun) == "table" then d.activeRun = raw.activeRun end
    if type(raw.tycoon) == "table" then d.tycoon = raw.tycoon end
    return d
end

local function ReadLocalFile(name)
    if not (File and fileSystem) then return nil end
    if not fileSystem:FileExists(name) then return nil end
    local f = File(name, FILE_READ)
    if not f or not f:IsOpen() then if f then f:Dispose() end; return nil end
    local s = f:ReadString()
    f:Dispose()
    local j = Json()
    if not j then return nil end
    local ok, tbl = pcall(j.decode, s)
    if not ok or type(tbl) ~= "table" then return nil end
    return tbl
end

local function WriteLocalAtomic(name, tmp, bak, tbl)
    if not (File and fileSystem) then return true end -- 离线单测兜底
    local j = Json()
    if not j then return false end
    local okEnc, raw = pcall(j.encode, tbl)
    if not okEnc or type(raw) ~= "string" then return false end
    -- 1. 写临时文件并回读校验
    local fTmp = File(tmp, FILE_WRITE)
    if not fTmp or not fTmp:IsOpen() then if fTmp then fTmp:Dispose() end; return false end
    local wOk = fTmp:WriteString(raw)
    fTmp:Dispose()
    if not wOk then return false end
    local check = ReadLocalFile(tmp)
    if not check then return false end
    -- 2. 备份旧档
    if fileSystem:FileExists(name) then
        pcall(function() fileSystem:Copy(name, bak) end)
    end
    -- 3. 写入正式档
    local fMain = File(name, FILE_WRITE)
    if not fMain or not fMain:IsOpen() then if fMain then fMain:Dispose() end; return false end
    local mOk = fMain:WriteString(raw)
    fMain:Dispose()
    return mOk == true
end

-- ----------------------------------------------------------------------------
-- 独立偏好（prefs.json）
-- ----------------------------------------------------------------------------
function SaveManager.LoadPrefs()
    local raw = ReadLocalFile(PREFS_FILE)
    if type(raw) == "table" then
        prefs.music = raw.music ~= false
        prefs.sfx = raw.sfx ~= false
        prefs.haptic = raw.haptic ~= false
        if type(raw.tips) == "table" then prefs.tips = raw.tips end
    end
    return prefs
end

function SaveManager.SavePrefs()
    if not (File and fileSystem) then return true end
    local j = Json()
    if not j then return false end
    local ok, raw = pcall(j.encode, prefs)
    if not ok then return false end
    local f = File(PREFS_FILE, FILE_WRITE)
    if not f or not f:IsOpen() then if f then f:Dispose() end; return false end
    local res = f:WriteString(raw)
    f:Dispose()
    return res == true
end

function SaveManager.GetPrefs() return prefs end

-- ----------------------------------------------------------------------------
-- 主存档读写与领先判断
-- ----------------------------------------------------------------------------
function SaveManager.GetData()
    if not data then data = SaveManager.DefaultData() end
    return data
end

function SaveManager.IsCloudAvailable()
    return clientCloud ~= nil and tonumber(clientCloud.userId or 0) ~= nil and tonumber(clientCloud.userId or 0) > 0
end

local function ComputeProgressScore(d)
    if type(d) ~= "table" then return 0 end
    if type(d.tycoon) == "table" then
        local t = d.tycoon
        local life = tonumber(t.lifetimeCash) or 0
        local logScore = (life > 1) and math.log(life + 1, 10) * 100 or 0
        return logScore + (tonumber(t.totalPrestiges) or 0) * 5000 + (tonumber(t.rankIdx) or 1) * 50
    end
    local rec = d.records or {}
    return (rec.wins or 0) * 1000 + (rec.runs or 0) * 10 + (d.unlockedDifficulty or 1) * 50
end

function SaveManager.IsLeading(a, b)
    if not b then return true end
    if not a then return false end
    local ta, tb = tonumber(a.savedAt) or 0, tonumber(b.savedAt) or 0
    if ta ~= tb then return ta > tb end
    local sa, sb = tonumber(a.saveSeq) or 0, tonumber(b.saveSeq) or 0
    if sa ~= sb then return sa > sb end
    return ComputeProgressScore(a) >= ComputeProgressScore(b)
end

function SaveManager.SaveLocal(opts)
    opts = opts or {}
    if not data then data = SaveManager.DefaultData() end
    if state.cloudBlocked and not opts.force then
        return false
    end
    if not opts.keepTimestamp then
        data.savedAt = ServerNow()
        data.saveSeq = (data.saveSeq or 0) + 1
    end
    local ok = WriteLocalAtomic(SAVE_FILE, SAVE_TMP, SAVE_BAK, data)
    if ok then
        state.localSavedAt = data.savedAt > 0 and data.savedAt or ServerNow()
        state.localFailed = false
        state.localTimer = 0
    else
        state.localFailed = true
    end
    if state.onStatusCb then state.onStatusCb(SaveManager.GetStatus()) end
    return ok
end

function SaveManager.SaveCloud(onDone)
    if not data then data = SaveManager.DefaultData() end
    if not SaveManager.IsCloudAvailable() then
        state.cloudFailed = true
        if state.onStatusCb then state.onStatusCb(SaveManager.GetStatus()) end
        if onDone then onDone(false, "未登录或离线") end
        return
    end
    if state.cloudBlocked then
        state.cloudFailed = true
        if onDone then onDone(false, "云存档未确认") end
        return
    end
    state.saving = true
    if state.onStatusCb then state.onStatusCb(SaveManager.GetStatus()) end

    local meta = {
        savedAt = data.savedAt,
        saveSeq = data.saveSeq,
        progress = ComputeProgressScore(data),
        version = VERSION,
    }
    local payload = {
        savedAt = data.savedAt,
        saveSeq = data.saveSeq,
        payload = data,
    }

    local finished = false
    local function finish(ok, msg)
        if finished then return end
        finished = true
        state.saving = false
        if ok then
            state.cloudSavedAt = data.savedAt > 0 and data.savedAt or ServerNow()
            state.cloudFailed = false
            state.cloudTimer = 0
        else
            state.cloudFailed = true
        end
        if state.onStatusCb then state.onStatusCb(SaveManager.GetStatus()) end
        if onDone then onDone(ok, msg) end
    end

    local okCall, err = pcall(function()
        clientCloud:BatchSet()
            :SetInt(KEY_HAS, 1)
            :Set(KEY_META, meta)
            :Set(KEY_DATA, payload)
            :Save("保存推币机的狂欢进度", {
                ok = function() finish(true) end,
                error = function(_, reason) finish(false, tostring(reason)) end,
                timeout = function() finish(false, "云端保存超时") end,
            })
    end)
    if not okCall then finish(false, tostring(err)) end
end

function SaveManager.SaveBoth(onDone)
    local localOk = SaveManager.SaveLocal()
    if not SaveManager.IsCloudAvailable() then
        if onDone then onDone(localOk, false) end
        return
    end
    SaveManager.SaveCloud(function(cloudOk)
        if onDone then onDone(localOk, cloudOk) end
    end)
end

-- ----------------------------------------------------------------------------
-- 启动双端对比 & 换设备防覆盖弹窗
-- ----------------------------------------------------------------------------
function SaveManager.PeekLocal()
    local raw = ReadLocalFile(SAVE_FILE)
    if not raw then raw = ReadLocalFile(SAVE_BAK) end
    if raw then return SanitizeData(raw) end
    return nil
end

function SaveManager.StartupSync(onReady, onCloudFail)
    state.onCloudReadyCb = onReady
    state.onCloudFailCb = onCloudFail
    local localData = SaveManager.PeekLocal()
    if localData then
        data = localData
        state.localSavedAt = localData.savedAt or 0
    end

    if not SaveManager.IsCloudAvailable() then
        -- 离线/本地预览环境：优雅降级不阻断
        state.cloudChecked = true
        state.cloudBlocked = false
        if not data then data = SaveManager.DefaultData() end
        if onReady then onReady(data) end
        return
    end

    state.syncPending = true
    state.syncElapsed = 0
    state.syncSeq = state.syncSeq + 1
    local seq = state.syncSeq

    local function handleSyncError(reason)
        if not state.syncPending or state.syncSeq ~= seq then return end
        state.syncPending = false
        state.cloudFailed = true
        if localData then
            -- 有本地档：降级本地开玩，同时锁死自动覆写云端
            state.cloudChecked = false
            state.cloudBlocked = true
            data = localData
            if onReady then onReady(data) end
        else
            -- 换设备无本地档：绝不静默新建！必须弹窗由玩家确认
            state.cloudChecked = false
            state.cloudBlocked = true
            if onCloudFail then onCloudFail(reason or "云存档读取超时或失败") end
        end
    end

    local okCall, err = pcall(function()
        clientCloud:BatchGet():Key(KEY_HAS):Key(KEY_META):Fetch({
            ok = function(values, iscores)
                if not state.syncPending or state.syncSeq ~= seq then return end
                local hasFlag = (iscores and (iscores[KEY_HAS] or 0) > 0) or false
                local meta = values and values[KEY_META]
                if not hasFlag and not meta then
                    -- 明确无云档
                    state.syncPending = false
                    state.cloudChecked = true
                    state.cloudBlocked = false
                    if not data then data = SaveManager.DefaultData() end
                    if onReady then onReady(data) end
                    return
                end
                -- 有云档，若本地已领先或相等则直接用本地
                if localData and meta and SaveManager.IsLeading(localData, meta) then
                    state.syncPending = false
                    state.cloudChecked = true
                    state.cloudBlocked = false
                    state.cloudSavedAt = tonumber(meta.savedAt) or 0
                    data = localData
                    if onReady then onReady(data) end
                    return
                end
                -- 需要拉取完整云档体
                clientCloud:Get(KEY_DATA, {
                    ok = function(v2)
                        if not state.syncPending or state.syncSeq ~= seq then return end
                        state.syncPending = false
                        local pack = v2 and v2[KEY_DATA]
                        local cloudPayload = pack and pack.payload
                        if type(cloudPayload) == "table" then
                            local cloudData = SanitizeData(cloudPayload)
                            if (not localData) or SaveManager.IsLeading(cloudData, localData) then
                                data = cloudData
                                SaveManager.SaveLocal({ keepTimestamp = true, force = true })
                            else
                                data = localData
                            end
                            state.cloudSavedAt = cloudData.savedAt or 0
                            state.cloudChecked = true
                            state.cloudBlocked = false
                            state.cloudFailed = false
                            if onReady then onReady(data) end
                        else
                            handleSyncError("云端存档体为空或已损坏")
                        end
                    end,
                    error = function(_, r2) handleSyncError(tostring(r2)) end,
                    timeout = function() handleSyncError("读取云存档超时") end,
                })
            end,
            error = function(_, r) handleSyncError(tostring(r)) end,
            timeout = function() handleSyncError("检查云存档超时") end,
        })
    end)
    if not okCall then handleSyncError(tostring(err)) end
end

function SaveManager.ConfirmStartFresh()
    state.cloudBlocked = false
    state.cloudChecked = true
    data = SaveManager.DefaultData()
    SaveManager.SaveLocal({ force = true })
    if state.onCloudReadyCb then state.onCloudReadyCb(data) end
end

function SaveManager.RetryCloudSync()
    SaveManager.StartupSync(state.onCloudReadyCb, state.onCloudFailCb)
end

-- ----------------------------------------------------------------------------
-- 自动保存定时器与 10 秒客户端看门狗（dt 已钳制 <= 0.05）
-- ----------------------------------------------------------------------------
function SaveManager.Tick(dt, inActivePlay, paused)
    dt = math.min(0.05, math.max(0, dt or 0))
    if state.syncPending then
        state.syncElapsed = state.syncElapsed + dt
        if state.syncElapsed >= CLOUD_WATCHDOG_SEC then
            local cbFail = state.onCloudFailCb
            local seq = state.syncSeq
            state.syncPending = false
            state.cloudFailed = true
            state.cloudBlocked = true
            if data then
                if state.onCloudReadyCb then state.onCloudReadyCb(data) end
            elseif cbFail and seq == state.syncSeq then
                cbFail("云端响应超时（>10秒）")
            end
        end
    end

    if paused or not inActivePlay or state.cloudBlocked then return end

    state.localTimer = state.localTimer + dt
    if state.localTimer >= LOCAL_INTERVAL then
        state.localTimer = 0
        SaveManager.SaveLocal()
    end

    if state.cloudChecked and SaveManager.IsCloudAvailable() then
        state.cloudTimer = state.cloudTimer + dt
        if state.cloudTimer >= CLOUD_INTERVAL then
            state.cloudTimer = 0
            SaveManager.SaveCloud()
        end
    end
end

function SaveManager.GetStatus()
    return {
        localText = state.localFailed and "保存失败" or SaveManager.FormatTime(state.localSavedAt),
        localFailed = state.localFailed,
        cloudText = (not SaveManager.IsCloudAvailable()) and "离线模式"
            or (state.cloudFailed and "保存失败" or SaveManager.FormatTime(state.cloudSavedAt)),
        cloudFailed = state.cloudFailed,
        saving = state.saving,
    }
end

function SaveManager.SetStatusListener(cb)
    state.onStatusCb = cb
end

function SaveManager.SetMockTestHooks(mock)
    -- 仅供单元测试注入用
    if mock and mock.reset then
        data = nil
        state.cloudBlocked = false
        state.cloudChecked = false
        state.syncPending = false
        state.localFailed = false
        state.cloudFailed = false
        state.localTimer = 0
        state.cloudTimer = 0
    end
end

return SaveManager
