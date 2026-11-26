require("main")
local orig = Start
function Start()
    orig()
    _G.__GAME.tycoon.activeAirdrop = { eventId = "vault_crack", baseCash = 8888 }
    _G.__OPEN_MODAL("airdrop")
end
