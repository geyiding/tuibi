require("main")
local orig = Start
function Start()
    orig()
    _G.__ENTER_PLAY(false)
    _G.__CALLBACKS.OnOpenSettings()
    _G.__CALLBACKS.OnRedeemCode("CARNIVAL2026")
end
