require("main")
local orig = Start
function Start()
    orig()
    _G.__ENTER_PLAY(false)
    local run = _G.__GAME.run
    local Config = require("game/Config")
    run.currentEvent = Config.EVENTS.scrap_smith
    run.eventOutcome = nil
    run.state = "event"
    _G.__SHOW_SCREEN("event")
end
