require("main")
local orig = Start
function Start()
    orig()
    _G.__CALLBACKS.OnOpenSettings()
    _G.__CALLBACKS.OnRedeemCode("RICH2026")
end
