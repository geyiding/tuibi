-- ============================================================================
-- MockAd.lua  模拟激励视频广告控制器（先完整跑通 UI/冷却/发奖，不接真实广告 SDK）
--   · 后续接入真实 TapTap 激励广告时，只需替换 Show() 内分支调用 sdk:ShowRewardVideoAd
-- ============================================================================

local Config = require("game/Config")

local MockAd = {}

MockAd.MODE = "mock"

local openUiFn = nil
local pending = nil

--- 绑定模拟广告弹窗渲染器（由 TycoonHud.Init 挂载）
function MockAd.BindUI(fn)
    openUiFn = fn
end

--- 判断广告位当前是否冷却完毕
function MockAd.IsReady(tycoon, placementId)
    if not tycoon then return false end
    local cd = tycoon:GetAdCooldown(placementId)
    return cd <= 0
end

--- 触发一次激励广告观看：
--- @param placementId string Config.AD_PLACEMENTS key
--- @param extraDesc string|nil 动态奖励预览文案
--- @param onReward function 广告完成回调（发放奖励）
--- @param onCancel function|nil 放弃观看回调
function MockAd.Show(placementId, extraDesc, onReward, onCancel)
    local def = Config.AD_PLACEMENTS[placementId]
    if not def then
        if onCancel then onCancel("invalid_placement") end
        return false
    end

    if openUiFn then
        pending = {
            id = placementId,
            def = def,
            extraDesc = extraDesc or def.desc,
            onReward = onReward,
            onCancel = onCancel,
        }
        openUiFn(pending)
        return true
    end

    -- 无 UI（如离线单测/压测）下直接按模拟成功发放
    if onReward then onReward(placementId) end
    return true
end

function MockAd.CompletePending()
    local cur = pending
    pending = nil
    if cur and cur.onReward then
        cur.onReward(cur.id)
    end
end

function MockAd.CancelPending()
    local cur = pending
    pending = nil
    if cur and cur.onCancel then
        cur.onCancel("user_cancel")
    end
end

function MockAd.GetPending()
    return pending
end

return MockAd
