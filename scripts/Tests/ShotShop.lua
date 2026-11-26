require("main")
local orig = Start
function Start()
    orig()
    _G.__GAME.tycoon.cash = 100000
    _G.__OPEN_MODAL("machine")
end
