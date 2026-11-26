-- ============================================================================
-- main.lua  《推币机的狂欢》世界首富增量版主入口
--   · 开屏即永动推币 · 22币渐进解锁/进化 · 8大机台改造 · 12项黑科技
--   · IPO上市转生与传奇股天赋 · 离线收益 · 6组模拟激励广告点 · 双端存档
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("game/Config")
local Skin = require("game/Skin")
local Number = require("game/Number")
local Fx = require("game/Fx")
local Tycoon = require("game/Tycoon")
local Stage = require("game/Stage")
local Machine3D = require("game/Machine3D")
local TycoonHud = require("game/TycoonHud")
local MockAd = require("game/MockAd")
local SettingsHud = require("game/SettingsHud")
local SaveManager = require("game/SaveManager")
local Sfx = require("game/Sfx")
local Music = require("game/Music")

local game = {
    time = 0,
    font = "sans",
    paused = false,
    modal = nil,
    tycoon = nil,
    fx = nil,
    stage = nil,
    hudDirty = true,
    refreshAccum = 0,
    modalRefreshAccum = 0,
    snapshotAccum = 0,
    _lastShootSfx = -1,
    _lastPegSfx = -1,
    _lastCritSfx = -1,
    _lastDropSfx = -1,
}

local function SyncDataSnapshot()
    if not game.tycoon then return end
    local d = SaveManager.GetData()
    d.tycoon = game.tycoon:ExportState(os.time())
    d.records.bestScore = math.max(d.records.bestScore or 0, math.floor(game.tycoon.lifetimeCash))
    d.records.bestHit = math.max(d.records.bestHit or 0, math.floor(game.tycoon.bestHit))
    d.records.maxCombo = math.max(d.records.maxCombo or 0, math.floor(game.tycoon.maxCombo))
    for id, lv in pairs(game.tycoon.coinLv) do
        if lv > 0 then d.discovered.coins[id] = true end
    end
end

local function PersistTycoon(saveCloudNow)
    SyncDataSnapshot()
    SaveManager.SaveLocal()
    if saveCloudNow then
        SaveManager.SaveBoth(function()
            if TycoonHud.GetCurModal() == "settings" then
                SettingsHud.Refresh(SaveManager.GetPrefs(), SaveManager.GetStatus(), true)
            end
        end)
    end
end

local function MakeListener()
    local l = setmetatable({}, {
        __index = function(t, k)
            local f = Fx[k]
            if type(f) == "function" then
                local w = function(_, ...) return f(game.fx, ...) end
                rawset(t, k, w)
                return w
            end
        end,
    })
    function l:OnShoot(coin, ty)
        game.fx:OnShoot(coin, ty)
        if (game.time - game._lastShootSfx) >= 0.085 then
            game._lastShootSfx = game.time
            local cx = coin and coin.x or (Config.WORLD_W * 0.5)
            Sfx.Play("shoot", 0.55, 0.96 + math.random() * 0.1, Sfx.PanOf(cx, Config.WORLD_W))
        end
        game.hudDirty = true
    end
    function l:OnPegHit(coin, peg)
        game.fx:OnPegHit(coin, peg)
        if (game.time - game._lastPegSfx) >= 0.065 then
            game._lastPegSfx = game.time
            local combo = game.tycoon and game.tycoon.combo or 0
            local pitch = math.min(1.55, 1.0 + combo * 0.014)
            local px = peg and peg.x or (Config.WORLD_W * 0.5)
            if peg and (peg.kind == "mult" or peg.kind == "fever") then
                Sfx.Play("peg_mult", 0.65, pitch, Sfx.PanOf(px, Config.WORLD_W))
            else
                Sfx.PlayAny(Sfx.PEGS, 0.55, pitch, Sfx.PanOf(px, Config.WORLD_W))
            end
        end
    end
    function l:OnSplit(x, y, cnt)
        game.fx:OnSplit(x, y, cnt)
        Sfx.Play("split", 0.78, 1.0, Sfx.PanOf(x, Config.WORLD_W))
    end
    function l:OnGateWin(coin, rewardName)
        game.fx:OnGateWin(coin, rewardName)
        Sfx.Play("gate_win", 0.88, 1.0, Sfx.PanOf(coin.x, Config.WORLD_W))
        game.hudDirty = true
    end
    function l:OnGateBounce(coin)
        game.fx:OnGateBounce(coin)
        Sfx.Play("gate_bounce", 0.5, 1.0, Sfx.PanOf(coin.x, Config.WORLD_W))
    end
    function l:OnScore(dmg, x, y, crit, combo, tag, refCps)
        game.fx:OnScore(dmg, x, y, crit, combo, tag, refCps)
        Music.SetIntensity(combo, game.tycoon and game.tycoon.feverActive)
        if crit and (game.time - game._lastCritSfx) >= 0.12 then
            game._lastCritSfx = game.time
            Sfx.Play("crit", 0.85, 1.0, Sfx.PanOf(x, Config.WORLD_W))
        end
        game.hudDirty = true
    end
    function l:OnFrontDrop(coin, dmg, crit)
        game.fx:OnFrontDrop(coin, dmg, crit)
        if (game.time - game._lastDropSfx) >= 0.075 then
            game._lastDropSfx = game.time
            local combo = game.tycoon and game.tycoon.combo or 0
            local pitch = math.min(1.5, 0.95 + combo * 0.012)
            Sfx.PlayAny(Sfx.DROPS, 0.8, pitch, Sfx.PanOf(coin.x, Config.WORLD_W))
        end
    end
    function l:OnLightning(x1, y1, x2, y2)
        game.fx:OnLightning(x1, y1, x2, y2)
        Sfx.Play("zap", 0.75, 1.0, Sfx.PanOf(x2, Config.WORLD_W))
    end
    function l:OnExplosion(x, y, rad)
        game.fx:OnExplosion(x, y, rad)
        Sfx.Play("explode", 0.9, 0.95, Sfx.PanOf(x, Config.WORLD_W))
    end
    function l:OnFeverStart(ty)
        game.fx:OnFeverStart(ty)
        Sfx.Play("fever")
        Music.SetIntensity(ty.combo, true)
    end
    function l:OnJackpot777(x, y)
        game.fx:OnJackpot777(x, y)
        Sfx.Play("jackpot")
    end
    function l:OnRankUp(rankDef, themeChanged, info)
        game.fx:OnRankUp(rankDef, themeChanged, info)
        Sfx.Play("win", 0.95)
        if themeChanged and game.tycoon then
            Music.Play("bgm_act" .. math.min(3, game.tycoon.stageTheme))
        end
        TycoonHud.ShowOvertake(rankDef, info)
        game.hudDirty = true
    end
    function l:OnUnlockCoin(def)
        game.fx:OnUnlockCoin(def)
        Sfx.Play("pick", 0.9)
        game.hudDirty = true
    end
    function l:OnPrestige(shares)
        game.fx:OnPrestige(shares)
        Sfx.Play("jackpot", 1.0)
        if game.tycoon then
            Music.Play("bgm_act" .. math.min(3, game.tycoon.stageTheme))
        end
        game.hudDirty = true
    end
    function l:OnAdReward(label)
        game.fx:OnAdReward(label)
        Sfx.Play("jackpot", 0.9)
        game.hudDirty = true
    end
    return l
end

local listener = MakeListener()

local callbacks = {
    OnTapStage = function()
        if game.tycoon and not TycoonHud.GetCurModal() then
            game.tycoon:ManualShoot()
        end
    end,
    OnSetBuyMode = function(mode)
        if not game.tycoon then return end
        Sfx.Play("click")
        game.tycoon.buyMode = mode
        TycoonHud.RefreshCurrentModal()
    end,
    OnBuyMachine = function(id)
        if not game.tycoon then return end
        if game.tycoon:BuyMachineUpgrade(id) then
            Sfx.Play("pick")
            PersistTycoon(false)
            game.hudDirty = true
            TycoonHud.RefreshMain(game.tycoon)
            TycoonHud.RefreshCurrentModal()
        end
    end,
    OnBuyCoin = function(id)
        if not game.tycoon then return end
        local ok = game.tycoon:BuyCoin(id)
        if ok then
            Sfx.Play("coin")
            PersistTycoon(false)
            game.hudDirty = true
            TycoonHud.RefreshMain(game.tycoon)
            TycoonHud.RefreshCurrentModal()
        end
    end,
    OnBuyTech = function(id)
        if not game.tycoon then return end
        if game.tycoon:BuyTech(id) then
            Sfx.Play("win")
            PersistTycoon(false)
            game.hudDirty = true
            TycoonHud.RefreshMain(game.tycoon)
            TycoonHud.RefreshCurrentModal()
        end
    end,
    OnBuyTalent = function(id)
        if not game.tycoon then return end
        if game.tycoon:BuyPrestigeTalent(id) then
            Sfx.Play("pick")
            PersistTycoon(false)
            game.hudDirty = true
            TycoonHud.RefreshMain(game.tycoon)
            TycoonHud.RefreshCurrentModal()
        end
    end,
    OnConfirmPrestige = function(isDouble)
        if not game.tycoon then return end
        if not isDouble then
            game.tycoon:DoPrestige(false)
            TycoonHud.CloseModal()
            PersistTycoon(true)
            TycoonHud.RefreshMain(game.tycoon)
        else
            local pending = game.tycoon:CalcPendingShares()
            MockAd.Show("prestige_2x",
                string.format("上市传奇股 ×2: +%s 股 (模拟广告)", Number.FormatNum(pending * 2)),
                function()
                    if game.tycoon then
                        game.tycoon:DoPrestige(true)
                        PersistTycoon(true)
                        TycoonHud.RefreshMain(game.tycoon)
                    end
                end,
                function()
                    TycoonHud.OpenModal("prestige")
                end)
        end
    end,
    OnWatchAd = function(placementId)
        if not game.tycoon then return end
        if not MockAd.IsReady(game.tycoon, placementId) then
            Sfx.Play("click")
            return
        end
        Sfx.Play("click")
        MockAd.Show(placementId, nil, function()
            if game.tycoon then
                game.tycoon:ApplyAdReward(placementId)
                PersistTycoon(false)
                game.hudDirty = true
                TycoonHud.RefreshMain(game.tycoon)
            end
        end)
    end,
    OnClaimOffline = function(isDouble)
        local amt = TycoonHud.GetOfflineAmt()
        if not isDouble then
            Sfx.Play("coin")
            if game.tycoon then
                game.tycoon:ClaimOffline(amt, false)
                PersistTycoon(false)
            end
            TycoonHud.CloseModal()
            TycoonHud.RefreshMain(game.tycoon)
        else
            Sfx.Play("click")
            MockAd.Show("offline_2x",
                string.format("双倍领取离线收益: +%s (模拟广告)", Number.FormatCash(amt * 2)),
                function()
                    if game.tycoon then
                        game.tycoon:ClaimOffline(amt, true)
                        PersistTycoon(false)
                        TycoonHud.RefreshMain(game.tycoon)
                    end
                end)
        end
    end,
    OnClaimAirdrop = function(isAd)
        if not game.tycoon then return end
        if not isAd then
            Sfx.Play("coin")
            game.tycoon:ClaimAirdrop(false)
            PersistTycoon(false)
            TycoonHud.CloseModal()
            TycoonHud.RefreshMain(game.tycoon)
        else
            Sfx.Play("click")
            MockAd.Show("airdrop_5x", nil, function()
                if game.tycoon then
                    game.tycoon:ClaimAirdrop(true)
                    PersistTycoon(false)
                    TycoonHud.RefreshMain(game.tycoon)
                end
            end)
        end
    end,
    OnMockAdFinish = function()
        Sfx.Play("win")
        TycoonHud.CloseModal()
        MockAd.CompletePending()
        if game.tycoon then
            TycoonHud.RefreshMain(game.tycoon)
        end
    end,
    OnMockAdCancel = function()
        Sfx.Play("click")
        TycoonHud.CloseModal()
        MockAd.CancelPending()
        if game.tycoon then
            TycoonHud.RefreshMain(game.tycoon)
        end
    end,
    OnClaimOvertakeAd = function(bounty)
        if not game.tycoon then return end
        local bAmt = math.max(100, math.floor(bounty or 0))
        Sfx.Play("click")
        MockAd.Show("overtake_3x",
            string.format("超越赏金 ×3 加倍：额外再得 +%s（模拟广告）", Number.FormatCash(bAmt * 2)),
            function()
                if game.tycoon then
                    game.tycoon:ClaimOvertakeAdBonus(bAmt)
                    PersistTycoon(false)
                    TycoonHud.DismissOvertake()
                    TycoonHud.RefreshMain(game.tycoon)
                end
            end)
    end,
    -- 系统设置与双端存档
    OnOpenSettings = function()
        Sfx.Play("click")
        SettingsHud.Refresh(SaveManager.GetPrefs(), SaveManager.GetStatus(), true)
        TycoonHud.OpenModal("settings")
    end,
    OnCloseSettings = function()
        Sfx.Play("click")
        TycoonHud.CloseModal()
    end,
    OnToggleMusic = function(on)
        local prefs = SaveManager.GetPrefs()
        prefs.music = (on == true)
        SaveManager.SavePrefs()
        Music.SetEnabled(prefs.music)
    end,
    OnToggleSfx = function(on)
        local prefs = SaveManager.GetPrefs()
        prefs.sfx = (on == true)
        SaveManager.SavePrefs()
        Sfx.SetEnabled(prefs.sfx)
        Sfx.Play("click")
    end,
    OnToggleHaptic = function(on)
        local prefs = SaveManager.GetPrefs()
        prefs.haptic = (on == true)
        SaveManager.SavePrefs()
    end,
    OnManualSave = function()
        Sfx.Play("click")
        PersistTycoon(true)
        SettingsHud.Refresh(SaveManager.GetPrefs(), SaveManager.GetStatus(), true)
    end,
    OnManualLoadCloud = function()
        Sfx.Play("click")
        SaveManager.RetryCloudSync()
        SettingsHud.Refresh(SaveManager.GetPrefs(), SaveManager.GetStatus(), true)
    end,
    OnRedeemCode = function(codeStr)
        local d = SaveManager.GetData()
        if not game.tycoon then return end
        local ok, msg = game.tycoon:ClaimRedeemCode(codeStr, d.redeemedCodes)
        if ok then
            Sfx.Play("jackpot")
            PersistTycoon(false)
            game.hudDirty = true
            TycoonHud.RefreshMain(game.tycoon)
        else
            Sfx.Play("click")
        end
        SettingsHud.SetRedeemFeedback(ok, msg)
    end,
    OnSaveAndQuitRun = function()
        Sfx.Play("click")
        PersistTycoon(true)
        TycoonHud.CloseModal()
    end,
    OnCloudConfirmFresh = function()
        Sfx.Play("click")
        TycoonHud.CloseModal()
        SaveManager.ConfirmStartFresh()
        game.tycoon = Tycoon.New(listener, { seed = os.time() })
        _G.__TYCOON = game.tycoon
        Music.Play("bgm_act1")
        TycoonHud.RefreshMain(game.tycoon)
    end,
    OnCloudRetry = function()
        Sfx.Play("click")
        SaveManager.RetryCloudSync()
    end,
}

function Start()
    print("=== " .. Config.GAME_TITLE .. " Start() ===")
    if graphics then graphics.windowTitle = Config.GAME_TITLE end
    math.randomseed(os.time())
    Skin.ProbeAutoAssets()

    UI.Init({
        theme = "default-dark",
        scale = UI.Scale.DEFAULT,
    })
    if UI.Theme and UI.Theme.FontFace then
        game.font = UI.Theme.FontFace("sans", "bold") or "sans"
    end

    local prefs = SaveManager.LoadPrefs()
    Sfx.Init()
    Sfx.SetEnabled(prefs.sfx)
    Music.Init()
    Music.SetEnabled(prefs.music)
    Music.Play("bgm_act1")

    game.fx = Fx.New()
    game.tycoon = Tycoon.New(listener, { seed = os.time() })
    _G.__TYCOON = game.tycoon
    Machine3D.Init(game.tycoon)

    MockAd.BindUI(function(pendingInfo)
        TycoonHud.OpenMockAd(pendingInfo)
    end)

    game.stage = Stage {
        game = setmetatable({
            fx = game.fx,
            font = game.font,
            OnTapStage = callbacks.OnTapStage,
            showTapHint = function()
                return game.tycoon and game.tycoon.totalClicks < 3 and not TycoonHud.GetCurModal()
            end,
        }, {
            __index = function(_, k)
                if k == "tycoon" or k == "run" then return game.tycoon end
                if k == "time" then return game.time end
            end,
        }),
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
    }

    local extraModals = SettingsHud.BuildModals(callbacks)
    local root = TycoonHud.Build(game.stage, callbacks, extraModals.settings, extraModals.cloudFail)
    UI.SetRoot(root)
    TycoonHud.RefreshMain(game.tycoon)

    SaveManager.SetStatusListener(function(stInfo)
        if TycoonHud.GetCurModal() == "settings" then
            SettingsHud.Refresh(SaveManager.GetPrefs(), stInfo, true)
        end
    end)

    SaveManager.StartupSync(function(loadedData)
        if loadedData and loadedData.tycoon and game.tycoon then
            if game.tycoon:ImportState(loadedData.tycoon) then
                Music.Play("bgm_act" .. math.min(3, game.tycoon.stageTheme))
                local offAmt, offSec = game.tycoon:CalcOfflineEarnings(os.time())
                if offSec >= 30 and offAmt > 0 and not TycoonHud.GetCurModal() then
                    TycoonHud.OpenOfflineModal(offAmt, offSec)
                end
            end
        end
        if TycoonHud.GetCurModal() == "cloudFail" then
            TycoonHud.CloseModal()
        end
        TycoonHud.RefreshMain(game.tycoon)
    end, function(reason)
        SettingsHud.SetCloudFailReason(reason)
        TycoonHud.OpenModal("cloudFail")
    end)

    SubscribeToEvent("Update", "HandleUpdate")
    print("=== " .. Config.GAME_TITLE .. " Ready ===")
end

function SetGamePaused(p)
    game.paused = (p == true)
    Sfx.SetPaused(game.paused)
    Music.SetPaused(game.paused)
    if game.paused then
        PersistTycoon(false)
    end
end

function Stop()
    PersistTycoon(false)
    Machine3D.Shutdown()
    Music.Shutdown()
    Sfx.Shutdown()
    UI.Shutdown()
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = math.min(0.05, math.max(0, eventData["TimeStep"]:GetFloat()))
    if game.paused then return end
    game.time = game.time + dt

    local curModal = TycoonHud.GetCurModal()
    if curModal ~= game.modal then
        game.modal = curModal
        Music.SetDucked(curModal ~= nil)
    end

    Sfx.Update(dt)
    Music.Update(dt)

    -- 定期同步数据快照以供 SaveManager 自动本地/云端保存
    game.snapshotAccum = game.snapshotAccum + dt
    if game.snapshotAccum >= 5.0 then
        game.snapshotAccum = 0
        SyncDataSnapshot()
    end
    SaveManager.Tick(dt, true, game.paused)

    local fx = game.fx
    if fx then fx:Update(dt) end

    TycoonHud.TickOvertake(dt)
    if curModal == "mockAd" then
        TycoonHud.TickMockAd(dt)
    end

    local ty = game.tycoon
    local simPaused = (curModal == "mockAd" or curModal == "cloudFail" or curModal == "offline")
    if ty and not simPaused then
        if not curModal and game.stage and game.stage:IsHolding() then
            ty:ManualShoot()
        end
        local gdt = dt * (fx and fx:TimeScale() or 1)
        ty:Update(gdt)
    end

    if ty and Machine3D.IsActive() then
        Machine3D.Update(dt, ty, fx, game.time)
    end

    -- 增量 UI 节流刷新：每秒最多 10 次主 HUD、4 次弹窗内容（零控件重建）
    game.refreshAccum = game.refreshAccum + dt
    if ty and (game.hudDirty or game.refreshAccum >= 0.12) then
        game.hudDirty = false
        game.refreshAccum = 0
        TycoonHud.RefreshMain(ty)
    end

    if curModal and curModal ~= "settings" and curModal ~= "cloudFail" and curModal ~= "mockAd" and curModal ~= "offline" then
        game.modalRefreshAccum = game.modalRefreshAccum + dt
        if game.modalRefreshAccum >= 0.25 then
            game.modalRefreshAccum = 0
            TycoonHud.RefreshCurrentModal()
        end
    end
end

_G.__GAME = game
_G.__TYCOON = game.tycoon
_G.__CALLBACKS = callbacks
_G.__MOCK_AD = MockAd
_G.__OPEN_MODAL = function(n) TycoonHud.OpenModal(n) end
_G.__CLOSE_MODAL = function() TycoonHud.CloseModal() end
