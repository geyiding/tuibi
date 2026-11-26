-- ============================================================================
-- scripts/Tests/DemoSmokeValidation.lua  世界首富增量版冒烟验证脚本
-- ============================================================================

require("main")
local origStart = Start
local UI = require("urhox-libs/UI")

function Start()
    origStart()
    local game = _G.__GAME
    assert(game ~= nil, "全局 __GAME 必须存在")
    local ty = game.tycoon
    assert(ty ~= nil, "开屏即须就绪 tycoon 实例")

    -- 激活狂欢高潮并推进 180 帧自动推币与手动补充，验证爆分与掉落正常
    ty:TriggerFever(true)
    for i = 1, 180 do
        if i % 15 == 1 then ty:ManualShoot() end
        game.time = game.time + (1 / 60)
        game.fx:Update(1 / 60)
        ty:Update(1 / 60)
    end
    local TycoonHud = require("game/TycoonHud")
    TycoonHud.RefreshMain(ty)
    UI.Layout()

    local root = UI.GetRoot()
    assert(root ~= nil, "UI.GetRoot() 不可为空")
    assert(ty.cash > 0 and ty.lifetimeCash > 0, "180帧自动推币后现金必须大于 0")
    assert(ty.totalDrops > 0, "180帧后必有前沿掉落币, 实际=" .. tostring(ty.totalDrops))
    print(string.format("[DemoSmoke] OK: cash=%.0f drops=%d fever=%s combo=%d",
        ty.cash, ty.totalDrops, tostring(ty.feverActive), ty.combo))
end
