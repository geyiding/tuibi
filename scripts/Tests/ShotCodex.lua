require("main")
local orig = Start
function Start()
    orig()
    _G.__GAME.tycoon.cash = 50000
    _G.__OPEN_MODAL("coins")
end
