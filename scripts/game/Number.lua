-- ============================================================================
-- Number.lua  共用大数字与现金格式化（支持 万/亿/兆/京/垓/秭，无引擎依赖）
-- ============================================================================

local floor, max = math.floor, math.max

local Number = {}

--- 格式化数值：950 -> "950", 1.2万, 1.23亿, 2.50兆, 1.20京, 3.40垓, 5.60秭
function Number.FormatNum(n)
    n = tonumber(n) or 0
    if n ~= n or n == math.huge or n == -math.huge then return "0" end
    local neg = ""
    if n < 0 then neg = "-"; n = -n end
    if n >= 1e28 then
        return neg .. string.format("%.2e", n)
    elseif n >= 1e24 then
        return neg .. string.format("%.2f秭", n / 1e24)
    elseif n >= 1e20 then
        return neg .. string.format("%.2f垓", n / 1e20)
    elseif n >= 1e16 then
        return neg .. string.format("%.2f京", n / 1e16)
    elseif n >= 1e12 then
        return neg .. string.format("%.2f兆", n / 1e12)
    elseif n >= 1e8 then
        return neg .. string.format("%.2f亿", n / 1e8)
    elseif n >= 1e4 then
        return neg .. string.format("%.1f万", n / 1e4)
    end
    return neg .. tostring(floor(n + 0.5))
end

--- 格式化现金："¥1.2万"
function Number.FormatCash(n)
    return "¥" .. Number.FormatNum(n)
end

--- 倍率固定一位小数，如 "2.5"
function Number.FormatMul(m)
    m = tonumber(m) or 1
    if m >= 100 then return Number.FormatNum(m) end
    return string.format("%.1f", m)
end

--- 倒计时 MM:SS（Lua 5.4 %d 必须传整数）
function Number.FormatClock(sec)
    local s = max(0, floor((tonumber(sec) or 0) + 0.5))
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
