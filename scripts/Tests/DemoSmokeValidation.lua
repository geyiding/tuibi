-- ============================================================================
-- scripts/Tests/DemoSmokeValidation.lua  Stage 3 真机引擎实测验收脚本
-- ============================================================================

require("main")
local origStart = Start
local UI = require("urhox-libs/UI")

function Start()
    origStart()
    local game = _G.__GAME
    assert(game ~= nil, "全局 __GAME 必须存在")
    _G.__ENTER_PLAY(false)
    local run = game.run
    assert(run ~= nil, "进入玩法后 run 必须就绪")
    run.autoDrop = true
    -- 注入足够狂欢能量让截图期展示高潮金币雨 + 满屏数字爆分效果
    run:AddFever(95)

    -- 推进 140 帧模拟真实物理和满屏飘字，确保画面丰富并检验零报错、安全区无溢出
    for _ = 1, 140 do
        game.time = game.time + (1 / 60)
        game.fx:Update(1 / 60)
        run:Update(1 / 60)
        if run.ammoLeft <= 2 then run.ammoLeft = 10 end
    end
    local Hud = require("game/Hud")
    Hud.RefreshPlay(run)
    UI.Layout()

    local root = UI.GetRoot()
    assert(root ~= nil, "UI.GetRoot() 不可为空")
    assert(run.score > 0, "140帧实战后得分必须大于 0, 实际=" .. tostring(run.score))
    assert(run.coinsDropped > 0, "140帧实战后必有前沿掉落币, 实际=" .. tostring(run.coinsDropped))
    print(string.format("[DemoSmoke] OK: score=%d dropped=%d fever=%s combo=%d",
        run.score, run.coinsDropped, tostring(run.feverActive), run.combo))
end
