-- ============================================================================
-- Number.lua  大数字与现金格式化（财富/排名默认精确到个位千分位，带非有限值兜底）
-- ============================================================================

local floor, max = math.floor, math.max

local Number = {}

local UNITS = {
    { sym = "万",   val = 1e4  },
    { sym = "亿",   val = 1e8  },
    { sym = "万亿", val = 1e12 },
    { sym = "京",   val = 1e16 },
    { sym = "垓",   val = 1e20 },
    { sym = "秭",   val = 1e24 },
    { sym = "穰",   val = 1e28 },
    { sym = "沟",   val = 1e32 },
    { sym = "涧",   val = 1e36 },
    { sym = "正",   val = 1e40 },
    { sym = "载",   val = 1e44 },
    { sym = "极",   val = 1e48 },
}

-- 全服总财富榜专用单位阶梯（万亿后依次为 兆 -> 京 -> 垓 ...）
local RANK_UNITS = {
    { sym = "万",   val = 1e4  },
    { sym = "亿",   val = 1e8  },
    { sym = "万亿", val = 1e12 },
    { sym = "兆",   val = 1e16 },
    { sym = "京",   val = 1e20 },
    { sym = "垓",   val = 1e24 },
    { sym = "秭",   val = 1e28 },
    { sym = "穰",   val = 1e32 },
    { sym = "沟",   val = 1e36 },
    { sym = "涧",   val = 1e40 },
    { sym = "正",   val = 1e44 },
    { sym = "载",   val = 1e48 },
    { sym = "极",   val = 1e52 },
}

local function AddCommas(digits)
    if #digits <= 3 then return digits end
    local res = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    if res:sub(1, 1) == "," then res = res:sub(2) end
    return res
end

local function FormatScaled3Sig(scaled)
    if scaled < 10 then
        local r = floor(scaled * 100 + 0.5) / 100
        if r >= 10 then
            return string.format("%.1f", r), false
        end
        return string.format("%.2f", r), false
    elseif scaled < 100 then
        local r = floor(scaled * 10 + 0.5) / 10
        return string.format("%.1f", r), false
    elseif scaled < 1000 then
        local r = floor(scaled * 10 + 0.5) / 10
        if r >= 1000 then return tostring(floor(r + 0.5)), false end
        return string.format("%.1f", r), false
    else
        local r = floor(scaled + 0.5)
        if r >= 10000 then return nil, true end
        return tostring(r), false
    end
end

--- 精确到个位的千分位整数串（1,130,000,000 / 8,000,000,000），超过 1e21 切换科学计数
function Number.FormatExactInt(n)
    if n == nil then return "0" end
    n = tonumber(n)
    if not n then return "0" end
    if n ~= n then
        print("[Number][WARN] non-finite value:", n)
        return "NaN"
    end
    if n == math.huge then
        print("[Number][WARN] non-finite value: inf")
        return "∞"
    elseif n == -math.huge then
        print("[Number][WARN] non-finite value: -inf")
        return "-∞"
    end

    local neg = ""
    if n < 0 then neg = "-"; n = -n end
    if n >= 1e21 then
        return neg .. string.format("%.2e", n)
    end
    local r = floor(n + 0.5)
    local raw = string.format("%.0f", r)
    if raw == "-0" then raw = "0" end
    if not raw:match("^%d+$") then
        return neg .. string.format("%.2e", n)
    end
    return neg .. AddCommas(raw)
end

local function FormatWithUnits(n, units, oneDecSmallWan)
    if n == nil then return "0" end
    n = tonumber(n)
    if not n then return "0" end
    if n ~= n then
        print("[Number][WARN] non-finite value:", n)
        return "NaN"
    end
    if n == math.huge then
        print("[Number][WARN] non-finite value: inf")
        return "∞"
    elseif n == -math.huge then
        print("[Number][WARN] non-finite value: -inf")
        return "-∞"
    end

    local neg = ""
    if n < 0 then neg = "-"; n = -n end
    if n < 10000 then
        local r = floor(n + 0.5)
        if r == 0 then return "0" end
        if r >= 10000 then
            return neg .. (oneDecSmallWan and "1.0万" or "1.00万")
        end
        return neg .. (oneDecSmallWan and tostring(r) or AddCommas(tostring(r)))
    end

    local idx = #units
    for i = 1, #units do
        if i == #units or n < units[i + 1].val then
            idx = i
            break
        end
    end

    while idx <= #units do
        local u = units[idx]
        local scaled = n / u.val
        local txt, carry = FormatScaled3Sig(scaled)
        if not carry then
            if oneDecSmallWan and u.sym == "万" and scaled < 10 then
                local r1 = floor(scaled * 10 + 0.5) / 10
                return neg .. string.format("%.1f", r1) .. u.sym
            end
            return neg .. txt .. u.sym
        end
        idx = idx + 1
    end
    return neg .. string.format("%.2e", n)
end

--- 中文大数缩写（仅用于超大倍率等紧凑展示）
function Number.FormatCompact(n)
    return FormatWithUnits(n, UNITS, true)
end

--- 全服总财富榜大数单位（万 -> 亿 -> 万亿 -> 兆 -> 京 -> 垓...）
function Number.FormatRankWealth(n)
    return FormatWithUnits(n, RANK_UNITS, false)
end

--- 全服总财富榜带货币符号格式："¥1.25兆" / "¥8.90京"
function Number.FormatRankCash(n)
    return "¥" .. Number.FormatRankWealth(n)
end

--- 格式化数值：默认精确到个位（带千分位逗号，视觉冲击更震撼）
function Number.FormatNum(n)
    return Number.FormatExactInt(n)
end

--- 世界排名数字格式化（8,000,000,000 / 47,913 / 1）
function Number.FormatWorldRank(rank)
    local r = max(1, floor((tonumber(rank) or 8000000000) + 0.5))
    return Number.FormatExactInt(r)
end

--- 顶栏紧致排名胶囊文本（No.8,000,000,000 / No.47,913 / No.990）
function Number.FormatRankBadge(rank)
    return "No." .. Number.FormatWorldRank(rank)
end

--- 格式化现金："¥1,130,000,000"
function Number.FormatCash(n)
    return "¥" .. Number.FormatExactInt(n)
end

--- 倍率格式化（<100 保留1位小数，100..999 取整，1000..9,999,999 精确到个位，>=1e7 走中文单位）
function Number.FormatMul(m)
    m = tonumber(m) or 1
    if m ~= m or m == math.huge then return "∞" end
    if m >= 1e7 then return Number.FormatCompact(m) end
    if m >= 1000 then return Number.FormatExactInt(m) end
    if m >= 100 then return tostring(floor(m + 0.5)) end
    return string.format("%.1f", m)
end

--- 倒计时 MM:SS 或 H:MM:SS（>=3600s 自动转 H:MM:SS）
function Number.FormatClock(sec)
    local s = max(0, floor((tonumber(sec) or 0) + 0.5))
    if s >= 3600 then
        local h = floor(s / 3600)
        local m = floor((s % 3600) / 60)
        local r = s % 60
        return string.format("%d:%02d:%02d", h, m, r)
    end
    local m = floor(s / 60)
    local r = s % 60
    return string.format("%02d:%02d", m, r)
end

--- 飘字色彩分级（支持按参考每秒产值动态自适应分级，始终有暴击跃升爽感）
function Number.ScoreTier(v, refCps)
    v = v or 0
    local base = max(12, tonumber(refCps) or 12)
    local ratio = v / base
    if ratio >= 35 or v >= 1e7 then return 5
    elseif ratio >= 10 or v >= 1e5 then return 4
    elseif ratio >= 3 or v >= 5000 then return 3
    elseif ratio >= 1.1 or v >= 500 then return 2
    end
    return 1
end

return Number
