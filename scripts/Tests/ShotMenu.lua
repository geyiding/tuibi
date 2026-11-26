require("main")
local orig = Start
function Start()
    orig()
    _G.__SHOW_SCREEN("menu")
end
