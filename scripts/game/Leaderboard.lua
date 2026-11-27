-- ============================================================================
-- Leaderboard.lua  全服双排行榜客户端接入（最快登顶时间榜 + 总财富榜）
--   · 严格遵循 UrhoX clientCloud 约束：
--     1) iscores 客户端截断为 32 位有符号整数（±2,147,483,647）
--     2) 最快登顶用 (SPEED_SCORE_BASE - sec) 编码，与总财富均走降序，使 GetRankList 与 GetUserRank 排名完全一致
--     3) 总财富用 log10 单调映射到 32 位整数排序，同时以 values 附加字段回读双精度原值（支持万亿/兆/京/垓+）
--     4) GetRankList 不包含昵称，自动批量调 GetUserNickname 回填并缓存
-- ============================================================================

local Config = require("game/Config")

local floor, min, max = math.floor, math.min, math.max
local LOG10 = math.log(10)

local Leaderboard = {}

Leaderboard.KEY_SPEED        = "carnival_lb_speed_v1"
Leaderboard.KEY_SPEED_EXACT  = "carnival_lb_speed_sec_v1"
Leaderboard.KEY_WEALTH_RANK  = "carnival_lb_wealth_v1"
Leaderboard.KEY_WEALTH_EXACT = "carnival_lb_wealth_val_v1"

Leaderboard.SPEED_SCORE_BASE         = 2000000000 -- 20 亿秒，安全低于 32 位有符号上限 2,147,483,647
Leaderboard.MAX_ISCORE               = 2147483640
Leaderboard.TOP_COUNT                = 20
Leaderboard.FETCH_TTL                = 10
Leaderboard.SUBMIT_COOLDOWN          = 15
Leaderboard.PERIODIC_SUBMIT_INTERVAL = 60

local function NowSec()
    return (os and os.time) and os.time() or 0
end

local function MakeBoard(id, sortKey, exactKey)
    return {
        id = id,
        sortKey = sortKey,
        exactKey = exactKey,
        status = "idle",      -- idle | loading | ready | error | offline
        message = "",
        items = {},
        myRank = nil,
        myCloudValue = nil,
        total = 0,
        updatedAt = -1,
        reqSeq = 0,
    }
end

local st = {
    boards = {
        speed  = MakeBoard("speed",  Leaderboard.KEY_SPEED,       Leaderboard.KEY_SPEED_EXACT),
        wealth = MakeBoard("wealth", Leaderboard.KEY_WEALTH_RANK, Leaderboard.KEY_WEALTH_EXACT),
    },
    nickCache = {},
    lastSubmitAt = -999,
    lastSubmittedWealth = 0,
    lastSubmittedWealthScore = 0,
    lastSubmittedSpeedSec = nil,
    bestCloudSpeedSec = nil,
    submitInFlight = false,
    tickAccum = 0,
}

--- 将登顶耗时（秒）编码为 32 位整数排序分：耗时越短分越高（与 GetUserRank 默认降序对齐）
function Leaderboard.EncodeSpeedScore(sec)
    local s = tonumber(sec) or 0
    if s ~= s or s <= 0 then return 0 end
    if s == math.huge then s = Leaderboard.SPEED_SCORE_BASE - 1 end
    s = max(1, min(Leaderboard.SPEED_SCORE_BASE - 1, floor(s + 0.5)))
    return Leaderboard.SPEED_SCORE_BASE - s
end

function Leaderboard.DecodeSpeedScore(score)
    local v = tonumber(score) or 0
    if v ~= v or v <= 0 then return 0 end
    return max(1, Leaderboard.SPEED_SCORE_BASE - floor(v + 0.5))
end

--- 将双精度总财富严格单调编码到 32 位正整数区间（支持 1 ~ 1e214，保留约 7 位相对精度）
function Leaderboard.EncodeWealthScore(wealth)
    local w = tonumber(wealth) or 0
    if w ~= w or w <= 0 or w == math.huge then return 0 end
    local encoded = floor((math.log(w + 1) / LOG10) * 10000000)
    return min(Leaderboard.MAX_ISCORE, max(1, encoded))
end

function Leaderboard.DecodeWealthScore(score)
    local s = tonumber(score) or 0
    if s ~= s or s <= 0 then return 0 end
    return max(0, (10 ^ (s / 10000000)) - 1)
end

function Leaderboard.IsAvailable()
    local cc = _G.clientCloud
    if type(cc) ~= "table" and type(cc) ~= "userdata" then return false end
    local uid = tonumber(cc.userId or 0)
    return uid ~= nil and uid > 0
end

local function FallbackName(uid, isMe)
    if isMe then return "我" end
    local n = tonumber(uid)
    if n then return "首富 #" .. tostring(floor(n) % 10000) end
    return "匿名首富"
end

function Leaderboard.GetMyNickname()
    local cc = _G.clientCloud
    local uid = cc and cc.userId
    if uid ~= nil then
        local cached = st.nickCache[tostring(uid)]
        if cached and cached ~= "" then return cached end
    end
    return "我"
end

function Leaderboard.GetState(boardId)
    return st.boards[boardId] or st.boards.speed
end

local function ResolveNicknames(board, seq, includeMyUid, onUpdate)
    local fn = _G.GetUserNickname
    if type(fn) ~= "function" then return end

    local seen = {}
    local reqIds = {}
    local function pushId(uid)
        if uid == nil then return end
        local key = tostring(uid)
        if seen[key] or st.nickCache[key] ~= nil then return end
        local numId = tonumber(uid)
        if numId and numId > 0 then
            seen[key] = true
            reqIds[#reqIds + 1] = numId
        end
    end

    for _, it in ipairs(board.items) do
        pushId(it.userId)
    end
    pushId(includeMyUid)
    if #reqIds == 0 then return end

    fn({
        userIds = reqIds,
        onSuccess = function(nicknames)
            if type(nicknames) == "table" then
                for _, info in ipairs(nicknames) do
                    local key = info and info.userId ~= nil and tostring(info.userId) or nil
                    local nick = info and info.nickname
                    if key and type(nick) == "string" and nick ~= "" then
                        st.nickCache[key] = nick
                    end
                end
            end
            if board.reqSeq == seq then
                for _, it in ipairs(board.items) do
                    local key = it.userId ~= nil and tostring(it.userId) or nil
                    local nick = key and st.nickCache[key]
                    if nick and nick ~= "" then
                        it.name = nick
                    end
                end
                if onUpdate then onUpdate(board) end
            end
        end,
        onError = function(_) end,
    })
end

--- 上报当前玩家的登顶速度与总财富（合并到单次 BatchSet；带节流与历史最快保护）
function Leaderboard.Submit(tycoon, force, onDone)
    local function finish(ok)
        if onDone then onDone(ok == true) end
    end
    if not Leaderboard.IsAvailable() or not tycoon then
        finish(false)
        return false
    end

    local now = NowSec()
    if not force then
        if st.submitInFlight then
            finish(false)
            return false
        end
        if (now - st.lastSubmitAt) < Leaderboard.SUBMIT_COOLDOWN then
            finish(false)
            return false
        end
    end

    local cc = _G.clientCloud
    local batch = cc:BatchSet()
    local dirty = false

    local cash = max(0.0, tonumber(tycoon.lifetimeCash) or 0.0)
    local wealthScore = Leaderboard.EncodeWealthScore(cash)
    local sentWealth = false
    if cash >= 1 and wealthScore > 0 then
        local grew = force
            or (wealthScore > (st.lastSubmittedWealthScore or 0))
            or (cash > (st.lastSubmittedWealth or 0) * 1.001)
        if grew then
            batch:SetInt(Leaderboard.KEY_WEALTH_RANK, wealthScore)
            batch:Set(Leaderboard.KEY_WEALTH_EXACT, cash + 0.0)
            dirty = true
            sentWealth = true
        end
    end

    local w1 = floor(tonumber(tycoon.world1TimeSec) or 0)
    local hasRank1 = (tonumber(tycoon.rankIdx) or 0) >= #Config.RANKS
    local sentSpeed = false
    if hasRank1 and w1 > 0 then
        local speedScore = Leaderboard.EncodeSpeedScore(w1)
        local cloudBest = st.bestCloudSpeedSec
        local betterThanCloud = (cloudBest == nil) or (w1 < cloudBest)
        local changedLocal = force or (st.lastSubmittedSpeedSec == nil) or (w1 < st.lastSubmittedSpeedSec)
        if speedScore > 0 and betterThanCloud and changedLocal then
            batch:SetInt(Leaderboard.KEY_SPEED, speedScore)
            batch:Set(Leaderboard.KEY_SPEED_EXACT, w1)
            dirty = true
            sentSpeed = true
        end
    end

    if not dirty then
        finish(true)
        return false
    end

    st.submitInFlight = true
    st.lastSubmitAt = now
    local okCall = pcall(function()
        batch:Save("leaderboard_sync", {
            ok = function()
                st.submitInFlight = false
                if sentWealth then
                    st.lastSubmittedWealth = cash
                    st.lastSubmittedWealthScore = wealthScore
                end
                if sentSpeed then
                    st.lastSubmittedSpeedSec = w1
                    st.bestCloudSpeedSec = st.bestCloudSpeedSec and min(st.bestCloudSpeedSec, w1) or w1
                end
                finish(true)
            end,
            error = function(code, reason)
                st.submitInFlight = false
                print("[Leaderboard][WARN] submit failed:", tostring(code), tostring(reason))
                finish(false)
            end,
            timeout = function()
                st.submitInFlight = false
                print("[Leaderboard][WARN] submit timeout")
                finish(false)
            end,
        })
    end)
    if not okCall then
        st.submitInFlight = false
        finish(false)
        return false
    end
    return true
end

local function QueryBoardFromCloud(board, seq, onUpdate)
    local cc = _G.clientCloud
    local myUid = cc.userId
    local myUidStr = myUid ~= nil and tostring(myUid) or nil
    local doneRankList, doneMyRank, doneTotal = false, false, false

    local function notifyIfCurrent()
        if board.reqSeq ~= seq then return end
        if doneRankList and board.status ~= "error" then
            board.status = "ready"
            board.message = ""
            board.updatedAt = NowSec()
        elseif doneRankList and doneMyRank and doneTotal and board.status == "loading" then
            board.status = "ready"
        end
        if onUpdate then onUpdate(board) end
    end

    cc:GetRankList(board.sortKey, 0, Leaderboard.TOP_COUNT, {
        ok = function(rankList)
            if board.reqSeq ~= seq then return end
            doneRankList = true
            local list = {}
            if type(rankList) == "table" then
                for i, item in ipairs(rankList) do
                    local uid = item.userId or item.player
                    local uidStr = uid ~= nil and tostring(uid) or ""
                    local isMe = (myUidStr ~= nil and uidStr == myUidStr)
                    local rawExact = item.score and tonumber(item.score[board.exactKey])
                    local rawInt = item.iscore and tonumber(item.iscore[board.sortKey])
                    local val = 0
                    if board.id == "speed" then
                        val = (rawExact and rawExact > 0) and floor(rawExact + 0.5)
                            or Leaderboard.DecodeSpeedScore(rawInt or 0)
                        if isMe and val > 0 then
                            st.bestCloudSpeedSec = st.bestCloudSpeedSec and min(st.bestCloudSpeedSec, val) or val
                            board.myCloudValue = val
                        end
                    else
                        val = (rawExact and rawExact > 0) and rawExact
                            or Leaderboard.DecodeWealthScore(rawInt or 0)
                        if isMe and val > 0 then
                            board.myCloudValue = val
                        end
                    end
                    local cachedNick = uidStr ~= "" and st.nickCache[uidStr] or nil
                    list[i] = {
                        rank = i,
                        userId = uid,
                        name = (cachedNick and cachedNick ~= "") and cachedNick or FallbackName(uid, isMe),
                        value = val,
                        isMe = isMe,
                    }
                end
            end
            board.items = list
            board.status = "ready"
            board.message = ""
            board.updatedAt = NowSec()
            notifyIfCurrent()
            ResolveNicknames(board, seq, myUid, onUpdate)
        end,
        error = function(code, reason)
            if board.reqSeq ~= seq then return end
            doneRankList = true
            board.status = "error"
            board.message = "拉取失败(" .. tostring(code or "ERR") .. ")，点击刷新重试"
            print("[Leaderboard][WARN] GetRankList error:", tostring(code), tostring(reason))
            if onUpdate then onUpdate(board) end
        end,
        timeout = function()
            if board.reqSeq ~= seq then return end
            doneRankList = true
            board.status = "error"
            board.message = "请求超时，点击刷新重试"
            print("[Leaderboard][WARN] GetRankList timeout")
            if onUpdate then onUpdate(board) end
        end,
    }, board.exactKey)

    cc:GetUserRank(myUid, board.sortKey, {
        ok = function(rank, scoreVal)
            if board.reqSeq ~= seq then return end
            doneMyRank = true
            if type(rank) == "number" and rank > 0 then
                board.myRank = floor(rank)
            else
                board.myRank = nil
            end
            if type(scoreVal) == "number" and scoreVal > 0 then
                if board.id == "speed" then
                    local sec = Leaderboard.DecodeSpeedScore(scoreVal)
                    board.myCloudValue = sec
                    st.bestCloudSpeedSec = st.bestCloudSpeedSec and min(st.bestCloudSpeedSec, sec) or sec
                else
                    board.myCloudValue = board.myCloudValue or Leaderboard.DecodeWealthScore(scoreVal)
                end
            end
            if onUpdate then onUpdate(board) end
        end,
        error = function() doneMyRank = true end,
        timeout = function() doneMyRank = true end,
    })

    cc:GetRankTotal(board.sortKey, {
        ok = function(total)
            if board.reqSeq ~= seq then return end
            doneTotal = true
            board.total = max(0, floor(tonumber(total) or 0))
            if onUpdate then onUpdate(board) end
        end,
        error = function() doneTotal = true end,
        timeout = function() doneTotal = true end,
    })
end

--- 拉取指定排行榜（"speed" | "wealth"），离线或未登录时优雅降级
function Leaderboard.Fetch(boardId, tycoon, forceRefresh, onUpdate)
    local board = Leaderboard.GetState(boardId)
    if not Leaderboard.IsAvailable() then
        board.status = "offline"
        board.message = "当前为离线环境，暂仅展示本地成绩"
        board.items = {}
        board.myRank = nil
        board.total = 0
        if onUpdate then onUpdate(board) end
        return board
    end

    local now = NowSec()
    if (not forceRefresh) and board.status == "ready" and board.updatedAt >= 0 and (now - board.updatedAt) < Leaderboard.FETCH_TTL then
        if onUpdate then onUpdate(board) end
        return board
    end

    board.reqSeq = board.reqSeq + 1
    local seq = board.reqSeq
    board.status = "loading"
    board.message = "正在同步全服排行..."
    if onUpdate then onUpdate(board) end

    local submitted = Leaderboard.Submit(tycoon, forceRefresh == true, function()
        if board.reqSeq ~= seq then return end
        QueryBoardFromCloud(board, seq, onUpdate)
    end)
    if not submitted then
        -- Submit 若因节流或无变化同步未发起网络请求，callback 已同步执行过一次？
        -- 注意：Submit 上方仅在返回 false 时也会调 onDone，若为真则异步回调；故这里不重复调用。
    end
    return board
end

function Leaderboard.Tick(dt, tycoon)
    if not tycoon then return end
    st.tickAccum = st.tickAccum + (dt or 0)
    if st.tickAccum >= Leaderboard.PERIODIC_SUBMIT_INTERVAL then
        st.tickAccum = 0
        Leaderboard.Submit(tycoon, false)
    end
end

function Leaderboard.ResetSession()
    st.lastSubmitAt = -999
    st.lastSubmittedWealth = 0
    st.lastSubmittedWealthScore = 0
    st.lastSubmittedSpeedSec = nil
    st.submitInFlight = false
    st.tickAccum = 0
    for _, b in pairs(st.boards) do
        b.status = "idle"
        b.message = ""
        b.items = {}
        b.myRank = nil
        b.myCloudValue = nil
        b.total = 0
        b.updatedAt = -1
        b.reqSeq = b.reqSeq + 1
    end
end

return Leaderboard
