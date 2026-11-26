-- ============================================================================
-- Number.lua  共用大数字与现金格式化（单位表驱动、3位有效数字、不掩盖NaN/inf）
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

--- 格式化数值：先按候选单位舍入并检查进位（9999.5 -> "1.0万", 99999999 -> "1.00亿"）
function Number.FormatNum(n)
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
        if r >= 10000 then
            return neg .. "1.0万"
        end
        return neg .. tostring(r)
    end

    -- 挑选单位并统一检查四舍五入后是否触发向下一级进位
    local idx = #UNITS
    for i = 1, #UNITS do
        if i == #UNITS or n < UNITS[i + 1].val then
            idx = i
            break
        end
    end

    while idx <= #UNITS do
        local u = UNITS[idx]
        local scaled = n / u.val
        local txt, carry = FormatScaled3Sig(scaled)
        if not carry then
            -- 兼容传统 1.5万 / 3.50亿 展示（<100 若为1位小数则是 x.x，仅 <10 按万/亿区分）
            if u.sym == "万" and scaled < 10 then
                local r1 = floor(scaled * 10 + 0.5) / 10
                if r1 >= 10 then return neg .. string.format("%.1f", r1) .. u.sym end
                return neg .. string.format("%.1f", r1) .. u.sym
            end
            return neg .. txt .. u.sym
        end
        idx = idx + 1
    end
    return neg .. string.format("%.2e", n)
end

--- 世界排名数字格式化（60.00亿 / 5800.0万 / 1.50万 / 850）
function Number.FormatWorldRank(rank)
    local r = max(1, floor((tonumber(rank) or 6e9) + 0.5))
    if r >= 1e8 then
        return string.format("%.2f亿", r / 1e8)
    elseif r >= 1e6 then
        return string.format("%.1f万", r / 1e4)
    elseif r >= 1e4 then
        return string.format("%.2f万", r / 1e4)
    end
    return tostring(r)
end

--- 顶栏紧致排名胶囊文本（No.60.00亿 / No.5800万 / No.1.5万 / No.990）
function Number.FormatRankBadge(rank)
    local r = max(1, floor((tonumber(rank) or 6e9) + 0.5))
    if r >= 1e8 then
        return "No." .. string.format("%.2f亿", r / 1e8)
    elseif r >= 1e6 then
        return "No." .. string.format("%.0f万", r / 1e4)
    elseif r >= 1e4 then
        return "No." .. string.format("%.1f万", r / 1e4)
    end
    return "No." .. tostring(r)
end

--- 格式化现金："¥1.2万"
function Number.FormatCash(n)
    return "¥" .. Number.FormatNum(n)
end

--- 倍率格式化（<100 保留1位小数，100..999 取整，>=1000 走中文单位）
function Number.FormatMul(m)
    m = tonumber(m) or 1
    if m ~= m or m == math.huge then return "∞" end
    if m >= 1000 then return Number.FormatNum(m) end
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
