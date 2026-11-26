-- ============================================================================
-- Number.lua  共用大数字格式化（无引擎依赖，规则 / 表现 / UI 统一调用）
-- ============================================================================

local floor = math.floor

local Number = {}

--- 格式化分数/筹码：1234 -> "1234", 12345 -> "1.2万", 123456789 -> "1.23亿", 1e12+ -> "1.23兆"
function Number.FormatNum(n)
    n = tonumber(n) or 0
    if n ~= n or n == math.huge or n == -math.huge then return "0" end
    local neg = ""
    if n < 0 then neg = "-"; n = -n end
    if n >= 1e12 then
        return neg .. string.format("%.2f兆", n / 1e12)
    elseif n >= 1e8 then
        return neg .. string.format("%.2f亿", n / 1e8)
    elseif n >= 1e4 then
        return neg .. string.format("%.1f万", n / 1e4)
    end
    return neg .. tostring(floor(n + 0.5))
end

--- 倍率固定一位小数，如 "2.5"
function Number.FormatMul(m)
    m = tonumber(m) or 1
    if m >= 100 then return string.format("%.0f", m) end
    return string.format("%.1f", m)
end

--- 分级色彩键（供飘字按数量级变色缩放）
function Number.ScoreTier(v)
    v = v or 0
    if v >= 1e7 then return 5      -- 霓虹紫超爆
    elseif v >= 1e5 then return 4  -- 烈焰橙红
    elseif v >= 5000 then return 3 -- 黄金巨字
    elseif v >= 500 then return 2  -- 霓虹青亮
    end
    return 1                       -- 洁白基础
end

return Number
