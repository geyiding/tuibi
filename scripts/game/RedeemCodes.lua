-- ============================================================================
-- RedeemCodes.lua  兑换码配置表与防重领校验（适配增量首富模式）
-- ============================================================================

local RedeemCodes = {}

RedeemCodes.CODES = {
    CARNIVAL2026 = {
        label = "首富见面礼",
        cashSeconds = 180,
        minCash = 5000,
        triggerFever = true,
        desc = "180秒产值现金 + 满槽狂欢",
    },
    COIN888 = {
        label = "金币狂潮礼",
        cashSeconds = 300,
        minCash = 12000,
        dropBonusCoins = 10,
        desc = "300秒产值现金 + 10枚高阶金币雨",
    },
    RICH2026 = {
        label = "IPO传奇股礼",
        shares = 5,
        boostSec = 180,
        desc = "5股传奇声望股 + 3分钟×3印钞",
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
