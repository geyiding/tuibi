-- ============================================================================
-- main.lua  《推币机的狂欢》成品主入口（全战役 / 双轨音频 / 双端存档 / 兑换码）
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("game/Config")
local Skin = require("game/Skin")
local Fx = require("game/Fx")
local Run = require("game/Run")
local Stage = require("game/Stage")
local Hud = require("game/Hud")
local CampaignHud = require("game/CampaignHud")
local CodexHud = require("game/CodexHud")
local SettingsHud = require("game/SettingsHud")
local SaveManager = require("game/SaveManager")
local RedeemCodes = require("game/RedeemCodes")
local Sfx = require("game/Sfx")
local Music = require("game/Music")

local game = {
    time = 0,
    font = "sans",
    paused = false,
    screen = "menu",     -- "menu" | "map" | "play" | "shop" | "rest" | "event" | "chest"
    modal = nil,
    run = nil,
    fx = nil,
    stage = nil,
    hudDirty = true,
    inActiveRun = false,
}

local function SyncDucking()
    Music.SetDucked(game.screen ~= "play" or game.modal ~= nil)
end

local function SyncDiscoveredFromRun()
    if not game.run then return end
    local d = SaveManager.GetData()
    for key in pairs(game.run.discoveredLog or {}) do
        local cat, id = key:match("^(%w+):(.+)$")
        if cat == "coin" then d.discovered.coins[id] = true
        elseif cat == "relic" then d.discovered.relics[id] = true
        elseif cat == "recipe" then d.discovered.recipes[id] = true
        elseif cat == "boss" then d.discovered.bosses[id] = true end
    end
end

local function PersistActiveRun()
    local d = SaveManager.GetData()
    if game.inActiveRun and game.run and game.run.hearts > 0 and game.screen ~= "menu" then
        d.activeRun = game.run:ExportSnapshot()
        SyncDiscoveredFromRun()
    else
        d.activeRun = nil
    end
    SaveManager.SaveLocal()
end

local function ShowScreen(name)
    game.screen = name
    Hud.ShowPage(name)
    if name == "map" then CampaignHud.RefreshMap(game.run)
    elseif name == "shop" then CampaignHud.RefreshShop(game.run)
    elseif name == "rest" then CampaignHud.RefreshRest(game.run)
    elseif name == "event" then CampaignHud.RefreshEvent(game.run)
    elseif name == "chest" then CampaignHud.RefreshChest(game.run)
    elseif name == "play" then Hud.RefreshPlay(game.run)
    elseif name == "menu" then
        local d = SaveManager.GetData()
        Hud.RefreshMenu(d, d.activeRun ~= nil)
    end
    SyncDucking()
end

local function OpenModal(name)
    Hud.CloseAllModals()
    game.modal = name
    Hud.SetModalVisible(name, true)
    SyncDucking()
end

local function CloseModal()
    Hud.CloseAllModals()
    game.modal = nil
    SyncDucking()
end

local function MaybeShowIntro(tipKey, iconKey, title, desc, iconKind)
    local prefs = SaveManager.GetPrefs()
    if prefs.tips[tipKey] then return end
    prefs.tips[tipKey] = true
    SaveManager.SavePrefs()
    CodexHud.OpenIntro(iconKey, title, desc, iconKind)
    OpenModal("intro")
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
    function l:OnLevelLoaded(run)
        game.fx:OnLevelLoaded(run)
        local track = run.bossId and "bgm_boss" or ("bgm_act" .. math.min(3, run.act))
        Music.Play(track)
        Music.SetIntensity(0, run.feverActive)
        if run.bossId then
            Sfx.Play("boss")
            local bDef = Config.BOSSES[run.bossId]
            if bDef then
                MaybeShowIntro("boss_" .. run.bossId, run.bossId, "Boss · " .. bDef.name, bDef.desc, "boss")
            end
        end
        game.hudDirty = true
    end
    function l:OnShoot(coin, run)
        game.fx:OnShoot(coin, run)
        Sfx.Play("shoot", 0.9, 0.96 + math.random() * 0.1, Sfx.PanOf(coin.x, Config.WORLD_W))
        game.hudDirty = true
    end
    function l:OnPegHit(coin, peg)
        game.fx:OnPegHit(coin, peg)
        local pitch = math.min(1.6, 1.0 + (game.run.combo or 0) * 0.015)
        if peg.kind == "mult" or peg.kind == "fever" then
            Sfx.Play("peg_mult", 0.85, pitch, Sfx.PanOf(peg.x, Config.WORLD_W))
        else
            Sfx.PlayAny(Sfx.PEGS, 0.75, pitch, Sfx.PanOf(peg.x, Config.WORLD_W))
        end
    end
    function l:OnSplit(x, y, cnt)
        game.fx:OnSplit(x, y, cnt)
        Sfx.Play("split", 0.85, 1.0, Sfx.PanOf(x, Config.WORLD_W))
    end
    function l:OnGateWin(coin, rewardName)
        game.fx:OnGateWin(coin, rewardName)
        Sfx.Play("gate_win", 1.0, 1.0, Sfx.PanOf(coin.x, Config.WORLD_W))
        game.hudDirty = true
    end
    function l:OnGateBounce(coin)
        game.fx:OnGateBounce(coin)
        Sfx.Play("gate_bounce", 0.75, 1.0, Sfx.PanOf(coin.x, Config.WORLD_W))
    end
    function l:OnScore(dmg, x, y, crit, combo, tag)
        game.fx:OnScore(dmg, x, y, crit, combo, tag)
        Music.SetIntensity(combo, game.run and game.run.feverActive)
        if crit then Sfx.Play("crit", 0.95, 1.0, Sfx.PanOf(x, Config.WORLD_W)) end
        game.hudDirty = true
    end
    function l:OnFrontDrop(coin, dmg, crit)
        game.fx:OnFrontDrop(coin, dmg, crit)
        local pitch = math.min(1.5, 0.95 + (game.run.combo or 0) * 0.012)
        Sfx.PlayAny(Sfx.DROPS, 0.9, pitch, Sfx.PanOf(coin.x, Config.WORLD_W))
    end
    function l:OnLightning(x1, y1, x2, y2)
        game.fx:OnLightning(x1, y1, x2, y2)
        Sfx.Play("zap", 0.85, 1.0, Sfx.PanOf(x2, Config.WORLD_W))
    end
    function l:OnExplosion(x, y, rad)
        game.fx:OnExplosion(x, y, rad)
        Sfx.Play("explode", 1.0, 0.95, Sfx.PanOf(x, Config.WORLD_W))
    end
    function l:OnFeverStart(run)
        game.fx:OnFeverStart(run)
        Sfx.Play("fever")
        Music.SetIntensity(run.combo, true)
    end
    function l:OnJackpot777(x, y)
        game.fx:OnJackpot777(x, y)
        Sfx.Play("jackpot")
    end
    function l:OnLevelEnd(won, summary)
        local d = SaveManager.GetData()
        SyncDiscoveredFromRun()
        if game.run.totalScore > (d.records.bestScore or 0) then d.records.bestScore = game.run.totalScore end
        if game.run.bestHit > (d.records.bestHit or 0) then d.records.bestHit = game.run.bestHit end
        if game.run.maxCombo > (d.records.maxCombo or 0) then d.records.maxCombo = game.run.maxCombo end

        if game.run.state == "reward" then
            Sfx.Play("win", 0.8)
            Hud.OpenReward(game.run)
            OpenModal("reward")
        elseif game.run.state == "result" then
            d.records.runs = (d.records.runs or 0) + 1
            if game.run.won then
                d.records.wins = (d.records.wins or 0) + 1
                if (d.unlockedDifficulty or 1) < 20 and game.run.difficulty == (d.unlockedDifficulty or 1) then
                    d.unlockedDifficulty = d.unlockedDifficulty + 1
                end
                Sfx.Play("win")
            else
                Sfx.Play("lose")
            end
            d.activeRun = nil
            game.inActiveRun = false
            SaveManager.SaveLocal()
            Hud.OpenResult(game.run, game.run.won)
            OpenModal("result")
        end
        game.hudDirty = true
    end
    return l
end

local listener = MakeListener()

local function StartNewRun(daily)
    CloseModal()
    local d = SaveManager.GetData()
    local seed = daily and select(1, Run.DailySeed()) or os.time()
    game.run = Run.New(listener, {
        seed = seed,
        daily = (daily == true),
        difficulty = d.difficulty or 1,
        disabled = d.disabled,
    })
    game.inActiveRun = true
    -- 从第1层直接进第1场实战，做到启动10秒内开玩！
    game.run:EnterNode("1_1")
    ShowScreen("play")
    PersistActiveRun()
end

local function ContinueSavedRun()
    local d = SaveManager.GetData()
    if not d.activeRun then StartNewRun(false); return end
    CloseModal()
    game.run = Run.New(listener, { seed = d.activeRun.seed or os.time(), difficulty = d.activeRun.difficulty or 1, disabled = d.disabled })
    if game.run:ImportSnapshot(d.activeRun) then
        game.inActiveRun = true
        ShowScreen("map")
    else
        StartNewRun(false)
    end
end

local callbacks = {
    OnStartGame = function(daily) Sfx.Play("click"); StartNewRun(daily) end,
    OnContinueRun = function() Sfx.Play("click"); ContinueSavedRun() end,
    OnDropCoin = function()
        if game.run and game.screen == "play" and not game.modal then
            game.run:ShootCoin()
        end
    end,
    OnTapStage = function()
        if game.run and game.screen == "play" and not game.modal then
            game.run:ShootCoin()
        end
    end,
    OnToggleAuto = function()
        if game.run then
            Sfx.Play("click")
            game.run.autoDrop = not game.run.autoDrop
            game.hudDirty = true
        end
    end,
    OnPickReward = function(idx)
        if not game.run then return end
        if game.run:PickReward(idx) then
            Sfx.Play("pick")
            CloseModal()
            local nextScreen = game.run:LeaveToMap()
            ShowScreen(nextScreen)
            PersistActiveRun()
        end
    end,
    OnSkipReward = function()
        if not game.run then return end
        if game.run:SkipReward() then
            Sfx.Play("coin")
            CloseModal()
            local nextScreen = game.run:LeaveToMap()
            ShowScreen(nextScreen)
            PersistActiveRun()
        end
    end,
    -- 路线图与各节点
    OnEnterMapNode = function(nid)
        if not game.run or game.screen ~= "map" or game.modal then return end
        local nextSc = game.run:EnterNode(nid)
        if nextSc then
            Sfx.Play("click")
            ShowScreen(nextSc)
            PersistActiveRun()
        end
    end,
    OnLeaveNode = function()
        if not game.run then return end
        Sfx.Play("click")
        local nextSc = game.run:LeaveToMap()
        ShowScreen(nextSc)
        PersistActiveRun()
    end,
    -- 商店
    OnBuyShop = function(idx)
        if not game.run or game.screen ~= "shop" then return end
        if game.run:BuyShopItem(idx) then
            Sfx.Play("coin")
            CampaignHud.RefreshShop(game.run)
            PersistActiveRun()
        end
    end,
    OnRefreshShop = function()
        if not game.run or game.screen ~= "shop" then return end
        if game.run:RefreshShop() then
            Sfx.Play("click")
            CampaignHud.RefreshShop(game.run)
        end
    end,
    OnShopOpenDelete = function()
        if not game.run then return end
        Sfx.Play("click")
        CodexHud.OpenDeck(game.run, true)
        OpenModal("deck")
    end,
    -- 工坊
    OnRestMerge = function()
        if not game.run then return end
        local groups = game.run.roster:FindMergeGroups()
        if #groups > 0 and game.run.roster:MergeThree(groups[1].kind, groups[1].level) then
            Sfx.Play("pick")
            CampaignHud.RefreshRest(game.run)
            PersistActiveRun()
        end
    end,
    OnRestEvolve = function()
        if not game.run then return end
        local evos = game.run.roster:FindAvailableEvolutions()
        if #evos > 0 and game.run.roster:Evolve(evos[1].id) then
            Sfx.Play("jackpot")
            local d = SaveManager.GetData()
            d.discovered.recipes[evos[1].id] = true
            d.discovered.coins[evos[1].result] = true
            CampaignHud.RefreshRest(game.run)
            PersistActiveRun()
        end
    end,
    OnRestHeal = function()
        if not game.run then return end
        if game.run:RestHealAndAmmo() then
            Sfx.Play("coin")
            CampaignHud.RefreshRest(game.run)
            PersistActiveRun()
        end
    end,
    -- 事件与宝箱
    OnEventChoice = function(ch)
        if not game.run or game.screen ~= "event" then return end
        if game.run:ChooseEvent(ch) then
            Sfx.Play("pick")
            CampaignHud.RefreshEvent(game.run)
            PersistActiveRun()
        end
    end,
    OnChestAction = function()
        if not game.run or game.screen ~= "chest" then return end
        if not game.run.chestClaimed then
            if game.run:ClaimChest() then
                Sfx.Play("jackpot")
                CampaignHud.RefreshChest(game.run)
                PersistActiveRun()
            end
        else
            Sfx.Play("click")
            ShowScreen(game.run:LeaveToMap())
            PersistActiveRun()
        end
    end,
    -- 投币仓 & 协同弹窗
    OnOpenDeck = function()
        if not game.run or game.modal then return end
        Sfx.Play("click")
        CodexHud.OpenDeck(game.run, false)
        OpenModal("deck")
    end,
    OnCloseDeck = function()
        Sfx.Play("click")
        CloseModal()
        if game.screen == "shop" then CampaignHud.RefreshShop(game.run) end
    end,
    OnDeckAction = function(coinEntry)
        if not game.run or not coinEntry then return end
        if game.screen == "shop" then
            if game.run:DeleteCoinFromShop(coinEntry.uid) then
                Sfx.Play("coin")
                CodexHud.OpenDeck(game.run, true)
                CampaignHud.RefreshShop(game.run)
                PersistActiveRun()
            end
        else
            if game.run.roster:MergeThree(coinEntry.kind, coinEntry.level) then
                Sfx.Play("pick")
                CodexHud.OpenDeck(game.run, false)
                PersistActiveRun()
            end
        end
    end,
    -- 图鉴 & 禁用池
    OnOpenCodex = function()
        if game.modal then return end
        Sfx.Play("click")
        SyncDiscoveredFromRun()
        CodexHud.OpenCodex(SaveManager.GetData())
        OpenModal("codex")
    end,
    OnCloseCodex = function() Sfx.Play("click"); CloseModal() end,
    OnToggleDisable = function(key)
        local d = SaveManager.GetData()
        if d.disabled[key] then
            d.disabled[key] = nil
        else
            local cnt = 0
            for _, v in pairs(d.disabled) do if v then cnt = cnt + 1 end end
            if cnt >= 3 then return end
            d.disabled[key] = true
        end
        Sfx.Play("click")
        SaveManager.SaveLocal()
        CodexHud.RefreshCodex()
    end,
    -- 难度
    OnOpenDifficulty = function()
        if game.modal then return end
        Sfx.Play("click")
        CodexHud.OpenDiff(SaveManager.GetData())
        OpenModal("difficulty")
    end,
    OnCloseDifficulty = function() Sfx.Play("click"); CloseModal() end,
    OnSelectDifficulty = function(n)
        local d = SaveManager.GetData()
        d.difficulty = math.max(1, math.min(d.unlockedDifficulty or 1, n))
        Sfx.Play("pick")
        SaveManager.SaveLocal()
        CloseModal()
        Hud.RefreshMenu(d, d.activeRun ~= nil)
    end,
    OnCloseIntro = function() Sfx.Play("click"); CloseModal() end,
    -- 总设置 & 存档 & 兑换码
    OnOpenSettings = function()
        if game.modal then return end
        Sfx.Play("click")
        SettingsHud.Refresh(SaveManager.GetPrefs(), SaveManager.GetStatus(), game.inActiveRun)
        OpenModal("settings")
    end,
    OnCloseSettings = function() Sfx.Play("click"); CloseModal() end,
    OnToggleMusic = function(on)
        local prefs = SaveManager.GetPrefs()
        prefs.music = on == true
        SaveManager.SavePrefs()
        Music.SetEnabled(prefs.music)
    end,
    OnToggleSfx = function(on)
        local prefs = SaveManager.GetPrefs()
        prefs.sfx = on == true
        SaveManager.SavePrefs()
        Sfx.SetEnabled(prefs.sfx)
        Sfx.Play("click")
    end,
    OnToggleHaptic = function(on)
        local prefs = SaveManager.GetPrefs()
        prefs.haptic = on == true
        SaveManager.SavePrefs()
    end,
    OnManualSave = function()
        Sfx.Play("click")
        PersistActiveRun()
        SaveManager.SaveBoth(function()
            SettingsHud.Refresh(SaveManager.GetPrefs(), SaveManager.GetStatus(), game.inActiveRun)
        end)
        SettingsHud.Refresh(SaveManager.GetPrefs(), SaveManager.GetStatus(), game.inActiveRun)
    end,
    OnManualLoadCloud = function()
        Sfx.Play("click")
        SaveManager.RetryCloudSync()
        SettingsHud.Refresh(SaveManager.GetPrefs(), SaveManager.GetStatus(), game.inActiveRun)
    end,
    OnRedeemCode = function(codeStr)
        local d = SaveManager.GetData()
        local ok, msg, reward = RedeemCodes.Claim(codeStr, d.redeemedCodes)
        if ok and reward then
            Sfx.Play("jackpot")
            if game.run then
                if reward.tickets then game.run.tickets = game.run.tickets + reward.tickets end
                if reward.coin then game.run.roster:AddCoin(reward.coin, 1) end
                if reward.prechargeFever then game.run.prechargedFever = true end
                game.hudDirty = true
            end
            SaveManager.SaveLocal()
        else
            Sfx.Play("click")
        end
        SettingsHud.SetRedeemFeedback(ok, msg)
    end,
    OnSaveAndQuitRun = function()
        Sfx.Play("click")
        PersistActiveRun()
        CloseModal()
        ShowScreen("menu")
    end,
    OnCloudConfirmFresh = function()
        Sfx.Play("click")
        CloseModal()
        SaveManager.ConfirmStartFresh()
    end,
    OnCloudRetry = function()
        Sfx.Play("click")
        SaveManager.RetryCloudSync()
    end,
    -- 结算
    OnRestart = function() Sfx.Play("click"); StartNewRun(game.run and game.run.daily) end,
    OnEndless = function()
        if not game.run then return end
        Sfx.Play("fever")
        CloseModal()
        game.run.endless = true
        game.run.endlessWave = 1
        game.run:StartLevel(3, 6, "boss")
        ShowScreen("play")
    end,
    OnBackMenu = function()
        Sfx.Play("click")
        CloseModal()
        game.inActiveRun = false
        ShowScreen("menu")
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
    game.run = Run.New(listener, { seed = os.time() })

    game.stage = Stage {
        game = setmetatable({
            fx = game.fx,
            font = game.font,
            OnTapStage = callbacks.OnTapStage,
            showTapHint = function()
                return game.run and game.run.shotsFired < 2 and game.screen == "play" and not game.modal
            end,
        }, {
            __index = function(_, k)
                if k == "run" then return game.run end
                if k == "time" then return game.time end
            end,
        }),
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
    }

    local extraPages = CampaignHud.BuildPages(callbacks)
    local extraModals = {}
    for k, m in pairs(CodexHud.BuildModals(callbacks)) do extraModals[k] = m end
    for k, m in pairs(SettingsHud.BuildModals(callbacks)) do extraModals[k] = m end

    local root = Hud.Build(game.stage, callbacks, extraPages, extraModals)
    UI.SetRoot(root)
    ShowScreen("menu")

    SaveManager.SetStatusListener(function(stInfo)
        if game.modal == "settings" then
            SettingsHud.Refresh(SaveManager.GetPrefs(), stInfo, game.inActiveRun)
        end
    end)
    SaveManager.StartupSync(function(loadedData)
        if game.screen == "menu" then
            Hud.RefreshMenu(loadedData, loadedData.activeRun ~= nil)
        end
        if game.modal == "cloudFail" then CloseModal() end
    end, function(reason)
        SettingsHud.SetCloudFailReason(reason)
        OpenModal("cloudFail")
    end)

    SubscribeToEvent("Update", "HandleUpdate")
    print("=== " .. Config.GAME_TITLE .. " Ready ===")
end

function SetGamePaused(p)
    game.paused = (p == true)
    Sfx.SetPaused(game.paused)
    Music.SetPaused(game.paused)
    if game.paused then
        PersistActiveRun()
    end
end

function Stop()
    PersistActiveRun()
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

    Sfx.Update(dt)
    Music.Update(dt)
    SaveManager.Tick(dt, game.inActiveRun and game.screen == "play" and not game.modal, game.paused)

    local run = game.run
    local fx = game.fx
    if fx then fx:Update(dt) end

    if run and game.screen == "play" and not game.modal then
        if game.stage and game.stage:IsHolding() then
            run:ShootCoin()
        end
        local gdt = dt * (fx and fx:TimeScale() or 1)
        run:Update(gdt)
        if run.ammoLeft <= 5 or run.feverActive then
            game.hudDirty = true
        end
    end

    if game.hudDirty and run and game.screen == "play" then
        game.hudDirty = false
        Hud.RefreshPlay(run)
    end
end

_G.__GAME = game
_G.__CALLBACKS = callbacks
_G.__SHOW_SCREEN = ShowScreen
_G.__OPEN_MODAL = OpenModal
_G.__CLOSE_MODAL = CloseModal
_G.__ENTER_PLAY = StartNewRun
