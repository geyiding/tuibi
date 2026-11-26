-- ============================================================================
-- RedeemCodes.lua  兑换码配置表与防重领校验（纯数据分离，测试与运营可直扩）
-- ============================================================================

local RedeemCodes = {}

-- 不区分大小写；rewards 支持 tickets / heal / coin / prechargeFever
RedeemCodes.CODES = {
    CARNIVAL2026 = {
        label = "狂欢见面礼",
        tickets = 50,
        coin = "jackpot7",
        desc = "50金券 + 777轮盘币",
    },
    COIN888 = {
        label = "金币狂潮礼",
        tickets = 88,
        coin = "gold",
        desc = "88金券 + 标准金币",
    },
    FEVER666 = {
        label = "超频狂欢礼",
        tickets = 40,
        prechargeFever = true,
        desc = "40金券 + 下局满狂欢开局",
    },
}

--- 校验并标记已领取；返回 ok, msg, reward
function RedeemCodes.Claim(rawCode, redeemedMap)
    if type(rawCode) ~= "string" then
        return false, "请输入兑换码"
    end
    local clean = rawCode:gsub("%s+", ""):upper()
    if clean == "" then
        return false, "请输入兑换码"
    end
    local def = RedeemCodes.CODES[clean]
    if not def then
        return false, "兑换码无效或已过期"
    end
    if redeemedMap and redeemedMap[clean] then
        return false, "该兑换码已领取过"
    end
    if redeemedMap then
        redeemedMap[clean] = true
    end
    return true, "兑换成功：" .. def.desc, def
end

return RedeemCodes
