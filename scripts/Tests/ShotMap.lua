require("main")
local orig = Start
function Start()
    orig()
    _G.__ENTER_PLAY(false)
    local run = _G.__GAME.run
    run.score = run.targetScore + 100
    run:FinishLevel()
    _G.__CALLBACKS.OnPickReward(1)
    _G.__SHOW_SCREEN("map")
end
