require("main")
local orig = Start
function Start()
    orig()
    _G.__OPEN_MODAL("ranks")
end
