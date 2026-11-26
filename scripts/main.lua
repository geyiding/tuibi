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
local Widgets = require("game/Widgets")
local RankLadder = require("game/RankLadder")

--- 竖屏适配缩放：按 390 设计宽度铺满手机（横屏/桌面窗口按 760 设计高度），
--- 取代 UI.Scale.DEFAULT 的“小屏密度自适应”（它会在手机上把整套 UI 再缩小约 26%，文字看不清）
local function PortraitFitScale()
    local w = (graphics and graphics.width) or 390
    local h = (graphics and graphics.height) or 844
    if w <= 0 or h <= 0 then return 1 end
    return math.max(0.5, math.min(w / 390, h / 760))
end

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
    saveDirty = false,
    saveDirtyAccum = 0,
    _lastShootSfx = -1,
    _lastPegSfx = -1,
    _lastCritSfx = -1,
    _lastDropSfx = -1,
}

local function SyncDataSnapshot()
    if not game.tycoon then return end
    local d = SaveManager.GetData()
    d.tycoon = game.tycoon:ExportState(os.time())
    d.records.bestScore = math.max((tonumber(d.records.bestScore) or 0) + 0.0, math.floor(game.tycoon.lifetimeCash) + 0.0)
    d.records.bestHit = math.max((tonumber(d.records.bestHit) or 0) + 0.0, math.floor(game.tycoon.bestHit) + 0.0)
    d.records.maxCombo = math.max(d.records.maxCombo or 0, math.floor(game.tycoon.maxCombo))
    for id, lv in pairs(game.tycoon.coinLv) do
        if lv > 0 then d.discovered.coins[id] = true end
    end
end

local function PersistTycoon(saveCloudNow)
    game.saveDirty = false
    game.saveDirtyAccum = 0
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

local function MarkSaveDirty()
    game.saveDirty = true
    game.saveDirtyAccum = 0
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
    function l:OnScore(dmg, x, y, crit, combo, tag, refCps, mult)
        game.fx:OnScore(dmg, x, y, crit, combo, tag, refCps, mult)
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
        -- 超越卡片（含技能点×3广告）等超越演出播完再弹，避免两套 UI 抢同一时刻
        game.pendingOvertake = rankDef
        game.pendingOvertakeInfo = info
        game.hudDirty = true
    end
    function l:OnUnlockCoin(def)
        game.fx:OnUnlockCoin(def)
        Sfx.Play("pick", 0.9)
        game.hudDirty = true
    end
    function l:OnComboWaveEnd(combo, waveMult, bonus)
        game.fx:OnComboWaveEnd(combo, waveMult, bonus)
        Sfx.Play("coin", 0.72)
        game.hudDirty = true
    end
    function l:OnSlotWin(prize)
        game.fx:OnSlotWin(prize)
        if prize and prize.mult and prize.mult >= 10 then
            Sfx.Play("jackpot", 0.95)
        elseif prize and prize.mult and prize.mult > 1 then
            Sfx.Play("win", 0.85)
        else
            Sfx.Play("click", 0.5)
        end
        game.hudDirty = true
    end
    function l:OnSkillPointsGain(gained, stepIdx)
        game.fx:OnSkillPointsGain(gained)
        Sfx.Play("pick", 0.72)
        game.hudDirty = true
    end
    function l:OnPrestige(shares, bonusSp, roundName)
        game.fx:OnPrestige(shares, bonusSp, roundName)
        Sfx.Play("jackpot", 1.0)
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

--- 购买成功爆点：在当前弹窗主按钮处炸开粒子 + 飘字（如 “Lv.5!”）
local function PurchaseFx(text, col)
    if not game.fx then return end
    local x, y, w, h = TycoonHud.GetActionRect()
    if x then game.fx:UiBurst(x, y, w, h, text, col) end
end

local callbacks = {
    OnTapStage = function()
        if game.tycoon and not TycoonHud.GetCurModal() then
            if not game.tycoon:ManualShoot() then
                Sfx.Play("click", 0.35)
            end
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
            PurchaseFx("Lv." .. tostring(game.tycoon.machineLv[id] or 0) .. "!", Skin.C.gold)
            MarkSaveDirty()
            game.hudDirty = true
            TycoonHud.RefreshMain(game.tycoon)
            TycoonHud.RefreshCurrentModal()
        end
    end,
    OnBuyCoin = function(id)
        if not game.tycoon then return end
        local ok, isUnlock = game.tycoon:BuyCoin(id)
        if ok then
            Sfx.Play("coin")
            PurchaseFx(isUnlock and "解锁!" or ("Lv." .. tostring(game.tycoon.coinLv[id] or 0) .. "!"), Skin.C.cyan)
            MarkSaveDirty()
            game.hudDirty = true
            TycoonHud.RefreshMain(game.tycoon)
            TycoonHud.RefreshCurrentModal()
        end
    end,
    OnTogglePinCoin = function(id)
        if not game.tycoon then return end
        local ok, pinned = game.tycoon:TogglePinCoin(id)
        Sfx.Play(ok and "pick" or "click")
        if ok then
            PurchaseFx(pinned and "★常驻!" or "取消常驻", Skin.C.cyan)
            MarkSaveDirty()
            game.hudDirty = true
            TycoonHud.RefreshMain(game.tycoon)
            TycoonHud.RefreshCurrentModal()
        end
    end,
    OnBuyTech = function(id)
        if not game.tycoon then return end
        if game.tycoon:BuyTech(id) then
            Sfx.Play("win")
            PurchaseFx("研发成功!", Skin.C.green)
            MarkSaveDirty()
            game.hudDirty = true
            TycoonHud.RefreshMain(game.tycoon)
            TycoonHud.RefreshCurrentModal()
        end
    end,
    OnBuyTalent = function(id)
        if not game.tycoon then return end
        if game.tycoon:BuyPrestigeTalent(id) then
            Sfx.Play("pick")
            PurchaseFx("Lv." .. tostring(game.tycoon.prestigeLv[id] or 0) .. "!", Skin.C.magenta)
            MarkSaveDirty()
            game.hudDirty = true
            TycoonHud.RefreshMain(game.tycoon)
            TycoonHud.RefreshCurrentModal()
        end
    end,
    OnGalacticAscend = function()
        if not game.tycoon then return end
        if game.tycoon:CanAscendEra() then
            local shares, bonusSp = game.tycoon:DoGalacticAscend()
            Sfx.Play("jackpot", 1.0)
            PurchaseFx("星际飞升!", Skin.C.magenta)
            PersistTycoon(true)
            game.hudDirty = true
            TycoonHud.RefreshMain(game.tycoon)
            TycoonHud.RefreshCurrentModal()
        else
            Sfx.Play("click")
        end
    end,
    OnConfirmPrestige = function(isDouble)
        if not game.tycoon then return end
        if not isDouble then
            game.tycoon:DoCapitalIPO(false)
            PersistTycoon(true)
            TycoonHud.RefreshMain(game.tycoon)
            TycoonHud.RefreshCurrentModal()
        else
            local rInfo = game.tycoon:GetNextIpoInfo()
            MockAd.Show("prestige_2x",
                string.format("上市传奇股 ×2：获得 +%s 股 + %d 技能点（不清空财富）", Number.FormatNum((rInfo.shares or 0) * 2), rInfo.bonusSp or 0),
                function()
                    if game.tycoon then
                        game.tycoon:DoCapitalIPO(true)
                        PersistTycoon(true)
                        TycoonHud.OpenModal("prestige")
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
            if not MockAd.IsReady(game.tycoon, "airdrop_5x") then
                Sfx.Play("click")
                TycoonHud.RefreshAirdrop()
                return
            end
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
    OnClaimOvertakeAd = function(spBounty)
        if not game.tycoon then return end
        local bAmt = math.max(1, math.floor(spBounty or 2))
        Sfx.Play("click")
        MockAd.Show("overtake_3x",
            string.format("超越技能点 ×3：额外再得 +%d 技能点（模拟广告）", bAmt * 2),
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
        scale = PortraitFitScale,
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
            OnTapSign = function()
                if not TycoonHud.GetCurModal() then
                    Sfx.Play("click")
                    TycoonHud.OpenModal("formula")
                end
            end,
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
    local root = TycoonHud.Build(game.stage, callbacks, extraModals.settings, extraModals.cloudFail, {
        fx = game.fx,
        font = game.font,
        getTime = function() return game.time end,
    })
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
                game.ladderSilent = true -- 读档后已越过的阶梯不重播超越演出
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
    Widgets.Tick(dt)

    -- 定期同步数据快照以供 SaveManager 自动本地/云端保存；急购防抖 3 秒落盘避免连续点击写盘卡顿
    game.snapshotAccum = game.snapshotAccum + dt
    if game.snapshotAccum >= 5.0 then
        game.snapshotAccum = 0
        SyncDataSnapshot()
    end
    if game.saveDirty then
        game.saveDirtyAccum = game.saveDirtyAccum + dt
        if game.saveDirtyAccum >= 3.0 then
            PersistTycoon(false)
        end
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
    -- 倍率追踪：增益出现时生成“×N”令牌飞向机台倍率招牌
    if ty and fx then fx:TrackMult(ty) end

    -- 超越阶梯追踪：越过富豪榜条目 / 身边人角色时播放超越演出（同帧多跳合并为“连超 N 人”）
    if ty and fx then
        local passed = RankLadder.CountPassed(ty.lifetimeCash)
        if game.ladderIdx == nil or game.ladderSilent or passed < game.ladderIdx then
            game.ladderIdx = passed
            game.ladderSilent = false
        elseif passed > game.ladderIdx then
            local item = RankLadder.LIST[passed]
            fx:OnOvertake(item, passed - game.ladderIdx)
            if item and item.kind == "rival" then Sfx.Play("win", 0.8) end
            game.ladderIdx = passed
        end
        if game.pendingOvertake and not fx:IsOvertakeBusy() then
            TycoonHud.ShowOvertake(game.pendingOvertake, game.pendingOvertakeInfo)
            game.pendingOvertake, game.pendingOvertakeInfo = nil, nil
        end
    end

    -- 自适应画质：持续 3 秒平均低于 45 帧则特效降为低档（粒子减半、去辉光晕圈）
    if fx and fx.quality >= 1 then
        game.frameAvg = (game.frameAvg or (1 / 60)) * 0.95 + dt * 0.05
        if game.frameAvg > (1 / 45) then
            game.slowT = (game.slowT or 0) + dt
            if game.slowT > 3 then
                fx:SetQuality(0.5)
                print("[Fx] 平均帧时长 " .. string.format("%.1f", game.frameAvg * 1000) .. "ms，特效切换为低画质")
            end
        else
            game.slowT = 0
        end
    end

    if ty and Machine3D.IsActive() then
        Machine3D.Update(dt, ty, fx, game.time)
    end

    -- 严格限频增量 UI 刷新（约 6 次/秒，消除每帧 60Hz HUD 重绘卡顿）
    game.refreshAccum = game.refreshAccum + dt
    if ty and game.refreshAccum >= 0.16 then
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
