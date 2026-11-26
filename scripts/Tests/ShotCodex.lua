require("main")
local orig = Start
function Start()
    orig()
    _G.__ENTER_PLAY(false)
    _G.__CALLBACKS.OnOpenCodex()
end
